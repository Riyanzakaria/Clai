import 'dart:async';

import 'package:clai/domain/models.dart';
import 'package:clai/player/load_ladder.dart';
import 'package:clai/providers/ytmusic/direct_types.dart';
import 'package:clai/services/direct_stream_service.dart';
import 'package:clai/services/direct_web_engine.dart';
import 'package:clai/services/update_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ronde 8054 — regresi dua cacat yang terbukti:
/// (1) Putar: kelas BATAL pada tangga muat (pembangunan yang dikalahkan
///     tidak lagi membakar anak tangga berikutnya) + pembuangan pekerjaan
///     resolusi DIRECT yang sudah dikalahkan dari antrean berseri
///     (mekanisme di balik "ketukan menumpuk, lalu berbunyi berurutan").
/// (2) Pembaruan dalam aplikasi: perbandingan rilis yang dulu menelan
///     semua rilis terbit — nama versi kini kunci utama, nomor bangun
///     hanya pemecah seri pada nama yang sama.
void main() {
  Track track(String id) => Track(
      key: TrackKey('ytmusic', id),
      title: 'Lagu $id',
      artistNames: 'A',
      playableRef: id);

  StreamInfo info(String url) => StreamInfo(
      url: url,
      mimeType: 'audio/webm',
      expiresAt: DateTime.now().add(const Duration(hours: 1)));

  group('isNewerRelease — nama versi kunci utama (Ronde 8054)', () {
    ReleaseInfo rel(String tag) => parseGithubReleaseJson(
        <String, dynamic>{'tag_name': tag, 'assets': const []})!;

    test('(a) tag v2.0.0 tanpa bangun vs terpasang 1.1.0/bangun 18 → BARU',
        () {
      final r = rel('v2.0.0');
      expect(r.build, 0); // semua tag terbit memang tanpa sufiks bangun
      expect(
          isNewerRelease(r, currentName: '1.1.0', currentBuild: 18), isTrue);
    });

    test('(b) tag v1.1.0 vs terpasang 1.0.0/bangun 13 → BARU', () {
      expect(isNewerRelease(rel('v1.1.0'), currentName: '1.0.0', currentBuild: 13),
          isTrue);
    });

    test('(c) nama sama: bangun tag lebih tinggi → BARU; lebih rendah → bukan',
        () {
      expect(
          isNewerRelease(rel('v2.0.0+60'),
              currentName: '2.0.0', currentBuild: 53),
          isTrue);
      expect(
          isNewerRelease(rel('v2.0.0+40'),
              currentName: '2.0.0', currentBuild: 53),
          isFalse);
      // Tag tanpa bangun pada nama yang sama tidak bisa memecah seri.
      expect(
          isNewerRelease(rel('v2.0.0'), currentName: '2.0.0', currentBuild: 53),
          isFalse);
    });

    test('(d) nama lebih tua walau bangun raksasa → BUKAN baru', () {
      expect(
          isNewerRelease(rel('v1.9.9+9999'),
              currentName: '2.0.0', currentBuild: 53),
          isFalse);
    });
  });

  group('LoadLadder.run — kelas batal tidak menaiki tangga', () {
    LoadLadder ladder() => LoadLadder(
          resolveAdaptive: (t, {stillWanted}) async =>
              info('https://contoh/adaptif'),
          resolveMuxed: (t) async => null,
          tagFor: (t) => 'tag-${t.id}',
          isLocal: (t) => false,
        );

    test('galat batal di anak 0: dilempar ulang seketika, anak lain tak dicoba',
        () async {
      final l = ladder();
      final tried = <int>[];
      var rungFailedCalls = 0;
      await expectLater(
        l.run(
          attempt: (rung) async {
            tried.add(rung);
            throw const DirectSuperseded();
          },
          onRungFailed: (rung, e, st) => rungFailedCalls++,
          isAbortError: (e) => e is DirectSuperseded,
        ),
        throwsA(isA<DirectSuperseded>()),
      );
      expect(tried, [LoadLadder.rungAdaptiveUri]);
      expect(rungFailedCalls, 0);
      expect(l.stickyRung, LoadLadder.rungAdaptiveUri);
    });

    test('galat biasa tetap menaiki tangga walau predikat batal terpasang',
        () async {
      final l = ladder();
      final tried = <int>[];
      final winner = await l.run(
        attempt: (rung) async {
          tried.add(rung);
          if (rung == LoadLadder.rungAdaptiveUri) {
            throw StateError('source error');
          }
        },
        isAbortError: (e) => e is DirectSuperseded,
      );
      expect(winner, LoadLadder.rungMuxedUri);
      expect(tried, [LoadLadder.rungAdaptiveUri, LoadLadder.rungMuxedUri]);
    });

    test('childFor meneruskan stillWanted ke resolusi adaptif', () async {
      bool? seenWanted;
      final l = LoadLadder(
        resolveAdaptive: (t, {stillWanted}) async {
          seenWanted = stillWanted?.call();
          if (seenWanted == false) throw const DirectSuperseded();
          return info('https://contoh/adaptif');
        },
        resolveMuxed: (t) async => null,
        tagFor: (t) => 'tag-${t.id}',
        isLocal: (t) => false,
      );
      await expectLater(
        l.childFor(track('v1'), LoadLadder.rungAdaptiveUri,
            strict: true, stillWanted: () => false),
        throwsA(isA<DirectSuperseded>()),
      );
      expect(seenWanted, isFalse);
      final ok = await l.childFor(track('v1'), LoadLadder.rungAdaptiveUri,
          strict: true, stillWanted: () => true);
      expect(ok, isNotNull);
      expect(seenWanted, isTrue);
    });
  });

  group('DirectStreamService — pekerjaan usang dibuang dari antrean', () {
    const goodPage = WatchPageData(
      html: '<html>watch</html>',
      visitorData: 'VD',
      signatureTimestamp: 20761,
      jsUrl: '/s/player/x/base.js',
      source: 'uji',
    );

    test(
        'percobaan kedua yang dikalahkan saat mengantre tidak menyentuh jahitan',
        () async {
      final gate = Completer<void>();
      final calls = <String, int>{};
      void bump(String k) => calls[k] = (calls[k] ?? 0) + 1;
      final svc = DirectStreamService(
        fetchWatchContext: (videoId) async {
          bump('watch');
          if (videoId == 'vA') await gate.future; // percobaan A menggantung
          return goodPage;
        },
        buildSession: (html) async {
          bump('session');
          return const DirectSessionResult(
              ok: true, ttlSecs: 43200, visitorToken: 'VT');
        },
        resolveDirectFormats: (t,
            {visitorData, signatureTimestamp, playerPoToken}) async {
          bump('resolve');
          return DirectResolveData(
            playability: 'OK',
            expiresInSeconds: 21600,
            formats: const [
              DirectFormat(
                itag: 251,
                mime: 'audio/webm; codecs="opus"',
                bitrate: 140000,
                contentLength: 4300517,
                directUrl: 'https://gv/videoplayback?expire=9&n=RAWN&sig=ABC',
              ),
            ],
          );
        },
        fetchText: (url) async {
          bump('text');
          return 'PLAYERJS';
        },
        readEnabled: () async => true,
        mintToken: (videoId) async {
          bump('mint');
          return const DirectMintResult(ok: true, token: 'TOK');
        },
        solve: (
            {required playerJs,
            nChallenges = const [],
            sigChallenges = const [],
            playerKey}) async {
          bump('solve');
          return EjsSolveOutcome(
            ok: true,
            n: {for (final c in nChallenges) c: 'SOLVED-$c'},
            sig: {for (final c in sigChallenges) c: 'SIG-$c'},
          );
        },
        now: () => DateTime.now(),
      );

      var wanted = true;
      final futA = svc.tryResolve(track('vA'), StreamQuality.normal);
      final futB = svc.tryResolve(track('vB'), StreamQuality.normal,
          stillWanted: () => wanted);
      // B mengantre di belakang A pada rantai berseri; A masih menggantung
      // di jahitan konteks → kalahkan B sebelum gilirannya tiba.
      wanted = false;
      gate.complete();

      final a = await futA;
      expect(a, isNotNull); // yang sedang berjalan tetap tuntas
      await expectLater(futB, throwsA(isA<DirectSuperseded>()));
      // B dibuang SEBELUM jahitan apa pun: hanya A yang menyentuh rantai.
      expect(calls['watch'], 1);
      expect(calls['resolve'], 1);
      // Pembuangan bukan kegagalan: tak masuk hitungan jatuh/demosi.
      expect(svc.stats.okCount, 1);
      expect(svc.stats.fallbackCount, 0);
      expect(svc.stats.supersededCount, 1);
    });
  });
}
