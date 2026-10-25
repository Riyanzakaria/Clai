import 'dart:convert';
import 'dart:io';

import 'package:clai/domain/models.dart';
import 'package:clai/player/resolving_audio_source.dart';
import 'package:clai/providers/ytmusic/innertube.dart';
import 'package:flutter_test/flutter_test.dart';

/// Uji matematika rentang ResolvingAudioSource (v4.1) terhadap kontrak proxy
/// just_audio 0.10.6 (_proxyHandlerForSource): bila ExoPlayer mengirim Range dan
/// offset != null, proxy menghitung offset + contentLength! - 1 — contentLength
/// null = handler runtuh = "(0) Source error". Rencana di sini harus selalu aman.
void main() {
  group('parseContentRange', () {
    test('bentuk standar terurai penuh', () {
      final cr = parseContentRange('bytes 0-1023/4300517');
      expect(cr, isNotNull);
      expect(cr!.start, 0);
      expect(cr.end, 1023);
      expect(cr.total, 4300517);
    });
    test('total bintang = null, sampah = null', () {
      expect(parseContentRange('bytes 10-19/*')!.total, isNull);
      expect(parseContentRange('ngawur'), isNull);
      expect(parseContentRange(null), isNull);
    });
  });

  group('fetchWindow — selalu terbatas (penolakan 403 googlevideo)', () {
    test('permintaan terbuka (end null) dibatasi satu chunk', () {
      final w = fetchWindow(0, null);
      expect(w.start, 0);
      expect(w.endInclusive, ResolvingAudioSource.maxChunkBytes - 1);
    });
    test('end jauh dipotong ke satu chunk dari start', () {
      final w = fetchWindow(5000, 5000 + 10 * ResolvingAudioSource.maxChunkBytes);
      expect(w.endInclusive - w.start + 1, ResolvingAudioSource.maxChunkBytes);
    });
    test('end di dalam chunk dipertahankan (eksklusif → inklusif)', () {
      final w = fetchWindow(100, 350);
      expect(w.endInclusive, 349);
    });
    test('total diketahui menambatkan end', () {
      final w = fetchWindow(4000, null, knownTotal: 4300);
      expect(w.endInclusive, 4299);
    });
  });

  group('planResponse 206', () {
    test('Content-Range lengkap: offset/panjang persis dari header', () {
      final p = planResponse(rangeRequested: true, reqStart: 0, statusCode: 206,
          fetchedContentLength: 1024, contentRange: 'bytes 0-1023/4300517', knownSourceLength: null);
      expect(p.offset, 0);
      expect(p.contentLength, 1024);
      expect(p.sourceLength, 4300517);
      expect(p.skipBytes, 0);
    });
    test('tanpa Content-Range: sourceLength = offset + panjang terambil', () {
      final p = planResponse(rangeRequested: true, reqStart: 2000, statusCode: 206,
          fetchedContentLength: 500, contentRange: null, knownSourceLength: null);
      expect(p.offset, 2000);
      expect(p.contentLength, 500);
      expect(p.sourceLength, 2500);
    });
    test('chunked (cl -1) dengan Content-Range: panjang dari selisih header', () {
      final p = planResponse(rangeRequested: true, reqStart: 100, statusCode: 206,
          fetchedContentLength: -1, contentRange: 'bytes 100-1123/9000', knownSourceLength: null);
      expect(p.offset, 100);
      expect(p.contentLength, 1024);
      expect(p.sourceLength, 9000);
    });
    test('chunked tanpa header & range diminta: offset WAJIB null (anti ledakan proxy)', () {
      final p = planResponse(rangeRequested: true, reqStart: 0, statusCode: 206,
          fetchedContentLength: -1, contentRange: null, knownSourceLength: null);
      expect(p.contentLength, isNull);
      expect(p.offset, isNull);
      expect(p.rangeRequestsSupported, isFalse);
    });
    test('konsisten antar panggilan berturutan (total diingat)', () {
      final p1 = planResponse(rangeRequested: true, reqStart: 0, statusCode: 206,
          fetchedContentLength: 1048576, contentRange: 'bytes 0-1048575/4300517', knownSourceLength: null);
      final p2 = planResponse(rangeRequested: true, reqStart: 1048576, statusCode: 206,
          fetchedContentLength: -1, contentRange: null, knownSourceLength: p1.sourceLength);
      expect(p2.sourceLength, 4300517);
      expect(p2.contentLength, 4300517 - 1048576);
    });
  });

  group('planResponse 200 (Range diabaikan server)', () {
    test('dari awal: offset 0, panjang penuh', () {
      final p = planResponse(rangeRequested: true, reqStart: 0, statusCode: 200,
          fetchedContentLength: 4000, contentRange: null, knownSourceLength: null);
      expect(p.offset, 0);
      expect(p.contentLength, 4000);
      expect(p.sourceLength, 4000);
      expect(p.skipBytes, 0);
    });
    test('start>0 & panjang diketahui: byte dilewati, offset = posisi diminta', () {
      final p = planResponse(rangeRequested: true, reqStart: 1500, statusCode: 200,
          fetchedContentLength: 4000, contentRange: null, knownSourceLength: null);
      expect(p.skipBytes, 1500);
      expect(p.offset, 1500);
      expect(p.contentLength, 2500);
      expect(p.sourceLength, 4000);
    });
    test('start>0 & panjang tak diketahui: offset null, tanpa lewati (cabang 200 aman)', () {
      final p = planResponse(rangeRequested: true, reqStart: 1500, statusCode: 200,
          fetchedContentLength: -1, contentRange: null, knownSourceLength: null);
      expect(p.offset, isNull);
      expect(p.skipBytes, 0);
      expect(p.rangeRequestsSupported, isFalse);
    });
    test('start di luar berkas: aliran kosong yang jujur', () {
      final p = planResponse(rangeRequested: true, reqStart: 9999, statusCode: 200,
          fetchedContentLength: 4000, contentRange: null, knownSourceLength: null);
      expect(p.contentLength, 0);
    });
  });

  group('skipBytes', () {
    test('melewati lintas potongan', () async {
      final out = await skipBytes(Stream.fromIterable([[1, 2, 3], [4, 5, 6], [7]]), 4).toList();
      expect(out.expand((e) => e).toList(), [5, 6, 7]);
    });
    test('melewati lebih dari isi = kosong', () async {
      final out = await skipBytes(Stream.fromIterable([[1, 2]]), 99).toList();
      expect(out.expand((e) => e).toList(), isEmpty);
    });
    test('nol = apa adanya', () async {
      final out = await skipBytes(Stream.fromIterable([[9, 9]]), 0).toList();
      expect(out.expand((e) => e).toList(), [9, 9]);
    });
  });

  group('ResolvingAudioSource dengan fetcher palsu', () {
    const track = Track(key: TrackKey('ytmusic', 'x'), title: 'Uji', artistNames: 'A', playableRef: 'x');
    StreamInfo info(String url) => StreamInfo(url: url, mimeType: 'audio/webm', expiresAt: DateTime.now().add(const Duration(hours: 1)));

    test('permintaan pertama selalu TERBATAS (tidak pernah open-ended)', () async {
      int? seenEnd;
      final src = ResolvingAudioSource(track, () async => info('https://contoh/a'),
          fetcher: (uri, {required start, required endInclusive}) async {
        seenEnd = endInclusive;
        return FetchedBytes(statusCode: 206, contentLength: endInclusive - start + 1,
            contentRange: 'bytes $start-$endInclusive/5000000',
            body: Stream.value(List.filled(endInclusive - start + 1, 7)));
      });
      final r = await src.request(0, null); // pola ExoPlayer: terbuka
      expect(seenEnd, ResolvingAudioSource.maxChunkBytes - 1);
      expect(r.contentLength, ResolvingAudioSource.maxChunkBytes);
      expect(r.sourceLength, 5000000);
      expect(r.offset, 0);
    });

    test('403 pada URL utama → beralih ke cadangan muxed & lengket', () async {
      final hits = <String>[];
      final src = ResolvingAudioSource(track, () async => info('https://contoh/adaptif'),
          resolveFallback: () async => info('https://contoh/muxed'),
          fetcher: (uri, {required start, required endInclusive}) async {
            hits.add(uri.host + uri.path);
            if (uri.path.contains('adaptif')) {
              return FetchedBytes(statusCode: 403, contentLength: 0, body: const Stream.empty());
            }
            return FetchedBytes(statusCode: 206, contentLength: 10,
                contentRange: 'bytes $start-${start + 9}/100', body: Stream.value(List.filled(10, 3)));
          });
      final r1 = await src.request(0, null);
      expect(r1.contentLength, 10);
      expect(src.fallbackActive, isTrue);
      final r2 = await src.request(10, 20);
      expect(r2.contentLength, 10);
      // adaptif hanya dicoba sekali; sesudahnya semua ke muxed
      expect(hits.where((h) => h.contains('adaptif')).length, 1);
      expect(hits.where((h) => h.contains('muxed')).length, 2);
    });

    test('403 tanpa cadangan → galat jujur berisi status', () async {
      final src = ResolvingAudioSource(track, () async => info('https://contoh/adaptif'),
          fetcher: (uri, {required start, required endInclusive}) async =>
              FetchedBytes(statusCode: 403, contentLength: 0, body: const Stream.empty()));
      expect(() => src.request(0, null), throwsA(predicate((e) => e.toString().contains('403'))));
    });
  });

  test('pickMuxedFallbackFormat: itag 18 dari fixture player ANDROID', () {
    final res = jsonDecode(File('test/fixtures/player_android.json').readAsStringSync()) as Map<String, dynamic>;
    final fb = pickMuxedFallbackFormat(res);
    expect(fb, isNotNull);
    expect(fb!.mimeType, 'video/mp4');
    expect(fb.url, startsWith('https://'));
  });
}
