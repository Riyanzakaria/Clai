/// Pemilih sampul sadar ukuran tampil (v4.4, keluhan pemilik: "cover blur semua").
///
/// Akar: pengurai menyimpan SATU varian thumbnail dari sumber — yang kecil,
/// cukup untuk baris daftar 48dp — lalu Player merentangkannya selebar layar.
/// Sumber (YouTube Music) sebenarnya melayani banyak ukuran; URL-nya sendiri
/// membawa parameter ukuran yang bisa ditulis ulang:
/// - googleusercontent: `...=w60-h60-l90-rj` → ganti pasangan w/h, flag lain utuh.
/// - i.ytimg.com: segmen kualitas (`default|mqdefault|hqdefault|sddefault|maxresdefault`).
/// URL lokal (content://, file://, jalur MediaStore) dan host lain tidak disentuh.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// Tangga ukuran unduh (px) — permukaan tampil dibulatkan NAIK ke anak tangga
/// terdekat supaya dua permukaan berukuran mirip berbagi satu unduhan/cache.
const artworkBuckets = [200, 544, 1080];

/// Anak tangga unduh untuk sampul selebar [displaySizeDp] pada kerapatan [dpr].
int artworkBucketFor(double displaySizeDp, double dpr) {
  final need = (displaySizeDp * dpr).ceil();
  for (final b in artworkBuckets) {
    if (need <= b) return b;
  }
  return artworkBuckets.last;
}

final _gucSizeRe = RegExp(r'=w(\d+)(?:-h(\d+))?((?:-[a-zA-Z0-9]+)*)$');
final _ytimgRe = RegExp(r'((?:i\.ytimg\.com|img\.youtube\.com)/vi/[^/]+/)([a-z]+)(\.jpg)');

const _ytimgRank = {'default': 0, 'mqdefault': 1, 'hqdefault': 2, 'sddefault': 3, 'maxresdefault': 4};

int _ytimgRankForTarget(int targetPx) {
  if (targetPx >= 1000) return 4; // maxresdefault 1280
  if (targetPx >= 600) return 3; // sddefault 640
  if (targetPx >= 320) return 2; // hqdefault 480
  if (targetPx >= 160) return 1; // mqdefault 320
  return 0;
}

/// URL sampul untuk permukaan yang butuh gambar ±[targetPx] piksel.
/// Mengembalikan URL asal bila tidak ada skema ukuran yang dikenal.
String? artworkUrlForSize(String? url, int targetPx) {
  if (url == null || url.isEmpty) return url;
  if (!url.startsWith('http')) return url; // lokal/MediaStore: jangan diubah

  // Pisahkan query agar regex ukuran berlabuh di akhir jalur.
  final q = url.indexOf('?');
  final head = q == -1 ? url : url.substring(0, q);
  final tail = q == -1 ? '' : url.substring(q);

  if (head.contains('googleusercontent.com')) {
    final sized = head.replaceFirstMapped(
      _gucSizeRe,
      (m) => '=w$targetPx-h$targetPx${m.group(3) ?? ''}',
    );
    return '$sized$tail';
  }

  final yt = _ytimgRe.firstMatch(head);
  if (yt != null) {
    final current = _ytimgRank[yt.group(2)] ?? 0;
    final want = _ytimgRankForTarget(targetPx);
    if (want <= current) return url; // jangan turunkan varian yang sudah lebih besar
    final name = _ytimgRank.entries.firstWhere((e) => e.value == want).key;
    return '${head.replaceRange(yt.start, yt.end, '${yt.group(1)}$name${yt.group(3)}')}$tail';
  }

  return url;
}

/// URL cadangan (Ronde 8057, FIX B): varian 544 dari sampul yang sama,
/// dipakai HANYA bila varian besar ([sizedUrl], ember > 544) gagal muat.
///
/// Latar: MediaItem.artUri terkurung di 544 dan varian itu terbukti
/// andal; varian 1080 yang hanya diminta Player justru rapuh —
/// googleusercontent =w1080 kadang gagal ambil dingin, dan i.ytimg.com
/// yang ditulis ulang ke maxresdefault.jpg deterministik 404 untuk
/// banyak video (varian itu memang tidak selalu ada di sumber).
///
/// - googleusercontent dengan lebar > 544: ditulis ulang ke w544-h544
///   (lewat [artworkUrlForSize], flag lain utuh).
/// - i.ytimg.com/img.youtube.com dengan kualitas di atas hqdefault
///   (sddefault/maxresdefault): diturunkan EKSPLISIT ke hqdefault —
///   [artworkUrlForSize] sendiri menolak menurunkan, jadi penurunan
///   ini memang hanya milik jalur cadangan di sini.
///
/// Null bila tidak ada cadangan yang bermakna: input null/kosong,
/// URL lokal/non-http, host tak dikenal / tanpa skema ukuran,
/// varian yang sudah ≤ 544, atau ytimg yang sudah ≤ hqdefault.
String? artworkFallbackUrl(String? sizedUrl) {
  if (sizedUrl == null || sizedUrl.isEmpty) return null;
  if (!sizedUrl.startsWith('http')) return null; // lokal/MediaStore

  final q = sizedUrl.indexOf('?');
  final head = q == -1 ? sizedUrl : sizedUrl.substring(0, q);
  final tail = q == -1 ? '' : sizedUrl.substring(q);

  if (head.contains('googleusercontent.com')) {
    final m = _gucSizeRe.firstMatch(head);
    if (m == null) return null; // tanpa suffix ukuran: tak ada varian lain
    final w = int.tryParse(m.group(1) ?? '');
    if (w == null || w <= 544) return null; // sudah varian 544 / lebih kecil
    final fallback = artworkUrlForSize(sizedUrl, 544);
    return (fallback == null || fallback == sizedUrl) ? null : fallback;
  }

  final yt = _ytimgRe.firstMatch(head);
  if (yt != null) {
    final current = _ytimgRank[yt.group(2)];
    if (current == null) return null;
    if (current <= _ytimgRank['hqdefault']!) return null; // sudah ≤ hqdefault
    return '${head.replaceRange(yt.start, yt.end, '${yt.group(1)}hqdefault${yt.group(3)}')}$tail';
  }

  return null;
}

/// Registri URL sampul yang SEDANG gagal muat (Ronde 8092, paket S1–S4).
///
/// Latar (ANALISIS-SAMPUL K1+K2): widget sampul yang sudah masuk keadaan
/// error hidup seumur proses di dalam `IndexedStack`, refresh Beranda
/// hanya memuat ulang data dengan URL+kunci yang identik, dan tidak ada
/// satu pun `imageCache.evict` di aplikasi — sekali gagal, tidak ada
/// aksi pengguna yang meminta gambar itu lagi. Registri ini adalah
/// simpul pemulihannya:
///
/// - [markFailed] mencatat URL final (sizedUrl) yang gagal. Nilai
///   kembaliannya adalah GERBANG LOG S3: `true` hanya pada kegagalan
///   pertama URL itu dalam satu sesi, sehingga Log insiden menerima
///   tepat satu entri `sampul-gagal` per URL per sesi.
/// - [evictOne]/[evictAllFailed] mengusir entri gambar dari
///   `imageCache` (provider `NetworkImage(url)` — persis provider yang
///   dibuat `Image.network` di CoverArt; `cacheWidth` bukan bagian
///   kunci provider), menghapus URL dari daftar gagal, lalu
///   `notifyListeners()` supaya widget yang HIDUP dan berlangganan
///   (CoverArt / FallbackArtworkImage) mereset keadaan error-nya dan
///   membangun Image generasi baru — permintaan benar-benar terbit
///   lagi tanpa mulai-ulang proses.
/// - Pengusiran TIDAK menghapus catatan log: URL yang gagal lagi
///   sesudah di-evict tidak dicatat dua kali dalam sesi yang sama.
class FailedArtworkRegistry extends ChangeNotifier {
  FailedArtworkRegistry._();
  static final FailedArtworkRegistry instance = FailedArtworkRegistry._();

  final Set<String> _failed = <String>{};
  final Set<String> _logged = <String>{};

  /// Apakah [url] saat ini tercatat gagal (belum di-evict).
  bool isFailed(String url) => _failed.contains(url);

  /// Salinan daftar URL yang saat ini gagal (untuk uji/diagnosis).
  Set<String> get failedUrls => Set<String>.unmodifiable(_failed);

  /// Catat [url] sebagai gagal. Mengembalikan `true` HANYA bila URL ini
  /// belum pernah dicatat ke log sesi ini — pemanggil memakai nilai ini
  /// sebagai gerbang satu-satunya untuk menulis Log insiden.
  bool markFailed(String url) {
    _failed.add(url);
    if (_logged.contains(url)) return false;
    _logged.add(url);
    return true;
  }

  /// Usir SATU [url] yang gagal dari cache gambar dan beri tahu para
  /// pelanggan agar mencoba lagi. Bukan URL yang tercatat gagal →
  /// tidak melakukan apa-apa (tidak ada notifikasi kosong).
  void evictOne(String url) {
    if (!_failed.contains(url)) return;
    PaintingBinding.instance.imageCache.evict(NetworkImage(url));
    _failed.remove(url);
    notifyListeners();
  }

  /// Usir SEMUA URL yang tercatat gagal (jalur refresh Beranda, S1).
  void evictAllFailed() {
    if (_failed.isEmpty) return;
    for (final url in _failed) {
      PaintingBinding.instance.imageCache.evict(NetworkImage(url));
    }
    _failed.clear();
    notifyListeners();
  }

  /// Kosongkan kedua daftar (hanya untuk uji; sesi produksi tidak
  /// pernah mereset gerbang log di tengah jalan).
  @visibleForTesting
  void resetForTesting() {
    _failed.clear();
    _logged.clear();
  }
}
