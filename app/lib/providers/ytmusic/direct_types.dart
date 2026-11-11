/// Tipe data + helper MURNI jalur DIRECT-1 (Tahap 3, Mesin Penyeberangan
/// 2.0). Berkas ini sengaja bebas dari impor aplikasi lain (hanya model
/// domain) agar:
///  - `ytmusic_provider.dart` bisa me-re-export-nya tanpa siklus impor, dan
///  - `services/direct_stream_service.dart` bisa memakainya tanpa mengimpor
///    provider,
///  - semua logika di sini teruji unit tanpa jaringan/WebView.
///
/// Nilai URL, token, dan visitorData yang mengalir lewat tipe-tipe ini
/// adalah bahan sesi: hanya hidup di memori, tidak pernah ditulis ke
/// log/bukti (yang dicatat: nama parameter, panjang, itag, bitrate).
library;

import 'dart:math';

import '../../domain/models.dart';

/// Parse bilangan longgar: JSON InnerTube mencampur num dan String
/// untuk kolom yang sama antar klien (expiresInSeconds, contentLength,
/// bitrate kadang String). Cast `as num?` pada nilai String MELEMPAR —
/// pelajaran emulator Tahap 3: resolusi produksi gugur di sini.
int? looseInt(Object? v) {
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v);
  return null;
}

/// User-Agent konteks resolusi DIRECT-1 — identitas klien WEB_REMIX
/// katalog innertubex v0.11.2 (Firefox/140). Info aliran jalur ini membawa
/// UA ini sebagai pasangan UA–URL-nya: pengambilan byte (tangga muat,
/// proxy, unduhan) memakainya persis, sama seperti drain pembuktian E3
/// Tahap 2 memakai UA ini.
const kDirectPathUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:140.0) Gecko/20100101 Firefox/140.0';

/// Bahan konteks dari SATU halaman watch: visitorData tamu,
/// signatureTimestamp, dan alamat JS player. `html` hanya hidup selama
/// sesi minter dibangun darinya.
class WatchPageData {
  final String? html; // memori saja — tidak pernah dicatat
  final String? visitorData; // memori saja
  final int? signatureTimestamp;
  final String? jsUrl; // path JS player resmi (bukan rahasia sesi)
  final bool hasEventId;
  final bool hasYtAtN;
  final String source;
  final String? error;
  const WatchPageData({
    this.html,
    this.visitorData,
    this.signatureTimestamp,
    this.jsUrl,
    this.hasEventId = false,
    this.hasYtAtN = false,
    this.source = '-',
    this.error,
  });
  int get htmlLen => html?.length ?? 0;
  int get visitorDataLen => visitorData?.length ?? 0;
}

/// Hasil urai MURNI halaman watch (lihat [parseWatchContextHtml]).
class WatchContextFields {
  final String? visitorData;
  final int? signatureTimestamp;
  final String? jsUrl;
  final bool hasEventId;
  final bool hasYtAtN;
  const WatchContextFields({
    this.visitorData,
    this.signatureTimestamp,
    this.jsUrl,
    this.hasEventId = false,
    this.hasYtAtN = false,
  });
}

/// Urai halaman watch menjadi bahan konteks — pola ekstraksi PERSIS yang
/// terbukti di Tahap 2 (Matriks U lari 2+). Jebakan yang sudah terbayar:
/// regex signatureTimestamp lama mensyaratkan `'":<digit>'` menempel,
/// padahal halaman nyata menulis `"STS": <5 digit>` atau
/// `signatureTimestamp: 20761` dengan spasi — Batch 0 sempat memvonis
/// keluarga WEB "menolak resolusi" hanya karena sts hilang. Pola di sini
/// mengikuti YtConfigParserImpl sumber: `(signatureTimestamp|sts)` dengan
/// spasi opsional sesudah titik-dua, ATAU kunci ytcfg `"STS"`; nilai 5
/// digit persis.
WatchContextFields parseWatchContextHtml(String html) {
  final vdM = RegExp(r'"VISITOR_DATA":"([^"]+)"').firstMatch(html) ??
      RegExp(r'"visitorData":"([^"]+)"').firstMatch(html);
  final stsM = RegExp(r'(?:signatureTimestamp|sts)"?\s*:\s*(\d{5})').firstMatch(html) ??
      RegExp(r'"STS":\s*(\d{5})').firstMatch(html);
  final jsM = RegExp(r'"jsUrl":"([^"]+)"').firstMatch(html);
  final jsUrl = jsM?.group(1)?.replaceAll(r'\/', '/').replaceAll(r'\u002f', '/');
  return WatchContextFields(
    visitorData: vdM?.group(1),
    signatureTimestamp: stsM == null ? null : int.tryParse(stsM.group(1)!),
    jsUrl: jsUrl,
    hasEventId: html.contains('"EVENT_ID"'),
    hasYtAtN: html.contains('ytAtN'),
  );
}

/// Satu format audio untuk jalur DIRECT (E3): URL langsung bila terbit,
/// atau potongan signatureCipher (s/sp/url dasar) untuk di-decipher.
class DirectFormat {
  final int itag;
  final String mime;
  final int? bitrate;
  final int? contentLength;
  final String? directUrl; // memori saja
  final String? cipherS; // memori saja
  final String cipherSp;
  final String? cipherBaseUrl; // memori saja
  const DirectFormat({
    required this.itag,
    required this.mime,
    this.bitrate,
    this.contentLength,
    this.directUrl,
    this.cipherS,
    this.cipherSp = 'signature',
    this.cipherBaseUrl,
  });
  bool get ciphered => directUrl == null && cipherS != null && cipherBaseUrl != null;
}

/// Hasil resolusi player WEB_REMIX untuk jalur DIRECT: playability +
/// daftar format audio mentah (URL langsung / tercipher).
class DirectResolveData {
  final String playability;
  final String reason;
  final String? error;
  final List<DirectFormat> formats;

  /// Masa berlaku streamingData (detik) — dasar kedaluwarsa StreamInfo.
  final int expiresInSeconds;
  const DirectResolveData({
    this.playability = '-',
    this.reason = '',
    this.error,
    this.formats = const [],
    this.expiresInSeconds = 21600,
  });
}

/// Pilih format DIRECT untuk [quality] — konvensi harness E3 (`_e3Pick`)
/// diperumum ke tingkat kualitas yang diminta: format terpakai (URL
/// langsung atau tercipher) dengan bitrate tertinggi ≤ plafon tingkat;
/// bila tak ada yang di bawah plafon, yang terendah di atasnya.
DirectFormat? pickDirectFormat(List<DirectFormat> formats, StreamQuality quality) {
  final usable = formats.where((f) => f.directUrl != null || f.ciphered).toList()
    ..sort((a, b) => (a.bitrate ?? 0).compareTo(b.bitrate ?? 0));
  if (usable.isEmpty) return null;
  DirectFormat? best;
  for (final f in usable) {
    if ((f.bitrate ?? 0) <= quality.maxBitrate) best = f;
  }
  return best ?? usable.first;
}

/// Tempel token konten terikat VIDEO_ID sebagai `&pot=` (persis E3:
/// encodeComponent, lewati bila sudah ada).
String appendPotToken(String url, String token) {
  if (url.contains('&pot=') || url.contains('?pot=')) return url;
  return '$url&pot=${Uri.encodeComponent(token)}';
}

/// Nonce cpn 16 char [a-zA-Z0-9_-] (pola PlaybackNonce harness).
String generateCpnNonce([Random? random]) {
  const alpha = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_';
  final rnd = random ?? Random();
  return String.fromCharCodes(
      [for (var i = 0; i < 16; i++) alpha.codeUnitAt(rnd.nextInt(alpha.length))]);
}

/// Tempel cpn (persis harness: putar-balik Uri, lewati bila sudah ada).
String appendCpn(String url, {String? nonce}) {
  final u = Uri.parse(url);
  if (u.queryParameters.containsKey('cpn')) return url;
  return u.replace(queryParameters: {...u.queryParameters, 'cpn': nonce ?? generateCpnNonce()}).toString();
}

/// Ganti/tambah satu parameter query lewat putar-balik Uri (pola harness
/// untuk mengganti parameter `n` hasil solver).
String replaceQueryParam(String url, String key, String value) {
  final u = Uri.parse(url);
  return u.replace(queryParameters: {...u.queryParameters, key: value}).toString();
}

/// Tempel hasil decipher: `&<sp>=<sig>` dengan sig ter-encodeComponent
/// (persis rakitan E3).
String appendSignatureParam(String url, String sp, String sig) =>
    '$url&$sp=${Uri.encodeComponent(sig)}';

/// Sinyal batal (Ronde 8054): percobaan resolusi DIRECT dibuang dari antrean
/// rantai berseri karena pemanggilnya menyatakan pekerjaannya tidak lagi
/// dikehendaki (perintah putar yang memintanya sudah dikalahkan ketukan yang
/// lebih baru). BUKAN kegagalan: tidak dicatat sebagai jatuh, tidak menyentuh
/// bucket kesehatan. Ditempatkan di berkas tipe bersama agar layanan DIRECT,
/// provider, tangga muat, dan handler bisa mengenal kelas batal yang sama
/// tanpa impor melingkar.
class DirectSuperseded implements Exception {
  const DirectSuperseded();
}

/// Rusak tanda tangan URL secara deterministik (balik char pertama nilai
/// `sig`/`signature`; bila tak ada, rusak `pot`). HANYA untuk pementasan
/// bukti penolakan edge (403) dari layar Diagnostik — kelas galat yang
/// sama dengan token/sig ditolak server. Tidak pernah dipanggil jalur
/// produksi normal.
String sabotageStreamUrl(String url) {
  for (final key in ['sig', 'signature', 'pot']) {
    final m = RegExp('([?&]$key=)([^&])').firstMatch(url);
    if (m != null) {
      final flipped = m.group(2) == 'A' ? 'B' : 'A';
      return url.replaceRange(m.start, m.end, '${m.group(1)}$flipped');
    }
  }
  return url;
}
