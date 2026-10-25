import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:just_audio/just_audio.dart';

import '../domain/models.dart';

/// Sumber audio MALAS (v4: resolusi per-trek; v4.1: kontrak proxy & penolakan googlevideo).
///
/// AUDIT v4.1 terhadap kontrak StreamAudioSource just_audio 0.10.6 (dibaca dari sumbernya,
/// _proxyHandlerForSource) — cacat yang ditemukan & diperbaiki di berkas ini:
///
/// 1. PERMINTAAN PERTAMA PASTI DITOLAK. ExoPlayer selalu meminta dengan Range TERBUKA
///    (`bytes=0-`); versi lama meneruskannya apa adanya ke googlevideo. Probe PC 2026-10-23
///    (python + dart:io, tumpukan HTTP yang sama dengan aplikasi): range terbuka & GET
///    tanpa Range pada URL audio adaptif → **HTTP 403**; yang lolos hanya range TERBATAS.
///    Karena itu request() kini SELALU membatasi jendela ambil (maks [maxChunkBytes]).
/// 2. LEDAKAN NULL DI PROXY. Bila ExoPlayer mengirim Range dan respons sumber ber-offset
///    != null, proxy menghitung `offset + contentLength! - 1` — contentLength null membuat
///    handler proxy runtuh DI LUAR try/catch-nya → soket mati → ExoPlayer "(0) Source
///    error" (persis insiden perangkat v4). [planResponse] menjamin: contentLength null
///    ⇒ offset null (proxy mengambil cabang 200 yang aman).
/// 3. MATEMATIKA RANGE DARI HEADER, BUKAN HARAPAN. Panjang kini diturunkan dari
///    Content-Range upstream yang sebenarnya (start/end/total terurai), bukan dari
///    Content-Length saja — termasuk kasus server memotong jendela & kasus 200
///    (Range diabaikan: byte dilewati agar posisi cocok, bila panjangnya diketahui).
/// 4. CADANGAN MUXED SEKALI PER SUMBER. Bila URL adaptif tetap ditolak (403/416/5xx)
///    pada permintaan PERTAMA sumber ini, sumber beralih permanen ke URL progresif
///    (itag 18 — terbukti melayani semua pola range) sebelum satu byte pun disajikan,
///    agar byte satu trek tidak pernah tercampur dari dua berkas berbeda.

// StreamAudioSource ditandai @experimental oleh just_audio, tetapi inilah API resmi
// sumber malasnya — dipakai sadar penuh (satu-satunya jalan resolusi per-trek).
// ignore: experimental_member_use
class ResolvingAudioSource extends StreamAudioSource {
  final Track track;
  final Future<StreamInfo> Function() resolve;

  /// Resolusi URL cadangan (muxed) — null bila provider tak punya.
  final Future<StreamInfo?> Function()? resolveFallback;

  /// Pengambil byte (dapat disuntik untuk uji).
  final RangeFetcher fetcher;

  /// Batas satu jendela ambil upstream (byte) — lihat cacat 1.
  static const int maxChunkBytes = 1048576;

  /// UA keluarga klien ANDROID — pasangan URL yang diterbitkan klien itu.
  static const String playerUserAgent =
      'com.google.android.youtube/20.10.38 (Linux; U; Android 14; in_ID; Pixel 8) gzip';

  StreamInfo? _primary;
  StreamInfo? _fallback;
  bool _onFallback = false;
  int? _knownTotal;

  /// Apakah sumber ini sudah beralih ke cadangan muxed (untuk laporan diagnostik).
  bool get fallbackActive => _onFallback;

  ResolvingAudioSource(this.track, this.resolve,
      {super.tag, this.resolveFallback, RangeFetcher? fetcher})
      : fetcher = fetcher ?? fetchHttpRange;

  /// Satu HttpClient bersama: pooling koneksi ke googlevideo antar permintaan range.
  static final HttpClient _client = HttpClient()..connectionTimeout = const Duration(seconds: 10);

  /// Pengambil byte bawaan (dart:io — tumpukan yang sama di perangkat & uji desktop).
  static Future<FetchedBytes> fetchHttpRange(Uri uri,
      {required int start, required int endInclusive}) async {
    final req = await _client.getUrl(uri);
    req.headers.set(HttpHeaders.userAgentHeader, playerUserAgent);
    // Range SELALU terbatas (inklusif di kedua ujung, per semantik header HTTP).
    req.headers.set(HttpHeaders.rangeHeader, 'bytes=$start-$endInclusive');
    final res = await req.close().timeout(const Duration(seconds: 20));
    return FetchedBytes(
      statusCode: res.statusCode,
      contentLength: res.contentLength,
      contentRange: res.headers.value(HttpHeaders.contentRangeHeader),
      contentType: res.headers.contentType?.mimeType,
      body: res,
    );
  }

  @override
  // ignore: experimental_member_use
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    final rangeRequested = start != null || end != null;
    final reqStart = start ?? 0;
    var info = _onFallback
        ? (_fallback ??= await resolveFallback?.call() ?? await _primaryInfo())
        : await _primaryInfo();

    var attempt = await _fetchBounded(info, reqStart, end);
    if (!_onFallback && _fallback == null && attempt.statusCode != HttpStatus.ok &&
        attempt.statusCode != HttpStatus.partialContent) {
      // Permintaan gagal sebelum byte disajikan: coba cadangan muxed SEKALI untuk
      // seluruh umur sumber ini (keputusan lengket — lihat cacat 4 di kepala berkas).
      final fb = await resolveFallback?.call();
      if (fb != null) {
        unawaited(attempt.body.drain<void>().catchError((_) {})); // bebaskan koneksi gagal
        _fallback = fb;
        _onFallback = true;
        info = fb;
        _knownTotal = null;
        attempt = await _fetchBounded(info, reqStart, end);
      }
    }
    if (attempt.statusCode != HttpStatus.ok && attempt.statusCode != HttpStatus.partialContent) {
      unawaited(attempt.body.drain<void>().catchError((_) {}));
      throw Exception('aliran "${track.title}" ditolak sumber (HTTP ${attempt.statusCode})');
    }
    final plan = planResponse(
      rangeRequested: rangeRequested,
      reqStart: reqStart,
      statusCode: attempt.statusCode,
      fetchedContentLength: attempt.contentLength,
      contentRange: attempt.contentRange,
      knownSourceLength: _knownTotal,
    );
    if (plan.sourceLength != null) _knownTotal = plan.sourceLength;
    var stream = attempt.body;
    if (plan.skipBytes > 0) stream = skipBytes(stream, plan.skipBytes);
    // ignore: experimental_member_use
    return StreamAudioResponse(
      rangeRequestsSupported: plan.rangeRequestsSupported,
      sourceLength: plan.sourceLength,
      contentLength: plan.contentLength,
      offset: plan.offset,
      contentType: attempt.contentType ?? info.mimeType,
      stream: stream,
    );
  }

  Future<StreamInfo> _primaryInfo() async => _primary ??= await resolve();

  Future<FetchedBytes> _fetchBounded(StreamInfo info, int reqStart, int? end) {
    final w = fetchWindow(reqStart, end, knownTotal: _knownTotal);
    return fetcher(Uri.parse(info.url), start: w.start, endInclusive: w.endInclusive);
  }
}

/// Hasil satu ambilan HTTP mentah (dapat dipalsukan di uji).
class FetchedBytes {
  final int statusCode;
  final int contentLength; // -1 = tak dinyatakan (chunked), semantik dart:io
  final String? contentRange;
  final String? contentType;
  final Stream<List<int>> body;
  const FetchedBytes({
    required this.statusCode,
    required this.contentLength,
    required this.body,
    this.contentRange,
    this.contentType,
  });
}

typedef RangeFetcher = Future<FetchedBytes> Function(Uri uri,
    {required int start, required int endInclusive});

/// Jendela ambil upstream untuk satu request(): selalu terbatas, ditambatkan ke
/// total yang sudah diketahui bila ada. [end] mengikuti kontrak just_audio (eksklusif).
({int start, int endInclusive}) fetchWindow(int start, int? end, {int? knownTotal}) {
  var endEx = end ?? (start + ResolvingAudioSource.maxChunkBytes);
  endEx = math.min(endEx, start + ResolvingAudioSource.maxChunkBytes);
  if (endEx <= start) endEx = start + 1; // jendela minimal 1 byte
  if (knownTotal != null) endEx = math.min(endEx, knownTotal);
  return (start: start, endInclusive: endEx - 1);
}

/// Urai Content-Range: `bytes <start>-<end>/<total|*>`. Null bila tak terbaca.
({int start, int end, int? total})? parseContentRange(String? header) {
  if (header == null) return null;
  final m = RegExp(r'bytes\s+(\d+)-(\d+)/(\d+|\*)').firstMatch(header);
  if (m == null) return null;
  return (
    start: int.parse(m.group(1)!),
    end: int.parse(m.group(2)!),
    total: m.group(3) == '*' ? null : int.parse(m.group(3)!),
  );
}

/// Rencana respons yang AMAN terhadap kontrak proxy just_audio (murni — diuji).
class PlannedResponse {
  final int? offset;
  final int? sourceLength;
  final int? contentLength;

  /// Byte awal yang harus dilewati pemanggil dari aliran (kasus 200 + start>0).
  final int skipBytes;
  final bool rangeRequestsSupported;
  const PlannedResponse({
    required this.offset,
    required this.sourceLength,
    required this.contentLength,
    required this.skipBytes,
    required this.rangeRequestsSupported,
  });
}

PlannedResponse planResponse({
  required bool rangeRequested,
  required int reqStart,
  required int statusCode,
  required int fetchedContentLength,
  required String? contentRange,
  required int? knownSourceLength,
}) {
  final cr = statusCode == HttpStatus.partialContent ? parseContentRange(contentRange) : null;
  if (statusCode == HttpStatus.partialContent) {
    final offset = cr?.start ?? reqStart;
    final sourceLength = cr?.total ?? knownSourceLength ??
        (fetchedContentLength >= 0 ? offset + fetchedContentLength : null);
    int? contentLength = fetchedContentLength >= 0
        ? fetchedContentLength
        : (cr != null ? cr.end - cr.start + 1 : (sourceLength != null ? sourceLength - offset : null));
    if (contentLength != null && contentLength < 0) contentLength = null;
    if (rangeRequested && contentLength == null) {
      // Jaminan anti-ledakan proxy: tanpa panjang pasti, offset WAJIB null.
      return PlannedResponse(
          offset: null, sourceLength: null, contentLength: null,
          skipBytes: 0, rangeRequestsSupported: false);
    }
    return PlannedResponse(
        offset: offset, sourceLength: sourceLength, contentLength: contentLength,
        skipBytes: 0, rangeRequestsSupported: true);
  }
  // 200: server mengabaikan Range & mengirim seluruh berkas dari byte 0.
  if (rangeRequested && reqStart > 0) {
    if (fetchedContentLength > reqStart) {
      // Lewati byte agar aliran mulai tepat di posisi yang diminta.
      return PlannedResponse(
          offset: reqStart, sourceLength: fetchedContentLength,
          contentLength: fetchedContentLength - reqStart,
          skipBytes: reqStart, rangeRequestsSupported: true);
    }
    if (fetchedContentLength >= 0) {
      // Posisi diminta di luar berkas: aliran kosong yang jujur.
      return PlannedResponse(
          offset: reqStart, sourceLength: fetchedContentLength, contentLength: 0,
          skipBytes: fetchedContentLength, rangeRequestsSupported: true);
    }
    // Panjang tak diketahui: jangan lewati apa pun, offset null (cabang 200 aman);
    // ExoPlayer memperlakukan 200 sebagai berkas penuh dari 0.
    return PlannedResponse(
        offset: null, sourceLength: null, contentLength: null,
        skipBytes: 0, rangeRequestsSupported: false);
  }
  return PlannedResponse(
      offset: 0,
      sourceLength: fetchedContentLength >= 0 ? fetchedContentLength : knownSourceLength,
      contentLength: fetchedContentLength >= 0 ? fetchedContentLength : null,
      skipBytes: 0, rangeRequestsSupported: true);
}

/// Lewati [count] byte pertama dari aliran (perpotongan chunk aman).
Stream<List<int>> skipBytes(Stream<List<int>> source, int count) async* {
  var remaining = count;
  await for (final chunk in source) {
    if (remaining <= 0) {
      yield chunk;
    } else if (chunk.length <= remaining) {
      remaining -= chunk.length;
    } else {
      yield chunk.sublist(remaining);
      remaining = 0;
    }
  }
}

void unawaited(Future<void> f) {
  f.catchError((_) => null);
}
