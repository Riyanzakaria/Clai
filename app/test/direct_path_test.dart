import 'dart:async';

import 'package:clai/domain/models.dart';
import 'package:clai/player/load_ladder.dart';
import 'package:clai/player/resolving_audio_source.dart';
import 'package:clai/providers/ytmusic/direct_types.dart';
import 'package:clai/services/direct_stream_service.dart';
import 'package:clai/services/direct_web_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';

/// Tahap 3 — jalur DIRECT-1: ekstraksi konteks watch (pola sts yang
/// benar), pemilihan format per tingkat, rakitan URL, matriks kegagalan
/// layanan (solver mati, minter gagal/kedaluwarsa, demosi kesehatan,
/// pengecualian per-trek, kill-switch), serta coba-ulang 403 proxy dan
/// pasangan UA–URL tangga. Semua tanpa jaringan/WebView (jahitan palsu).
void main() {
  group('looseInt — JSON campuran num/String', () {
    test('num, string angka, dan nilai lain', () {
      expect(looseInt(21600), 21600);
      expect(looseInt(21600.0), 21600);
      expect(looseInt('21600'), 21600);
      expect(looseInt('abc'), isNull);
      expect(looseInt(null), isNull);
      expect(looseInt(true), isNull);
    });
  });

  group('parseWatchContextHtml — pola ekstraksi Tahap 2', () {
    test('signatureTimestamp dengan spasi + visitorData + jsUrl ter-unescape', () {
      final f = parseWatchContextHtml(
          r'{"visitorData":"VD-abc","signatureTimestamp": 20761,"jsUrl":"\/s\/player\/x\/base.js","EVENT_ID":1} var ytAtN=1;');
      expect(f.visitorData, 'VD-abc');
      expect(f.signatureTimestamp, 20761);
      expect(f.jsUrl, '/s/player/x/base.js');
      expect(f.hasEventId, isTrue);
      expect(f.hasYtAtN, isTrue);
    });

    test('kunci ytcfg "STS" dengan spasi (bentuk halaman nyata)', () {
      final f = parseWatchContextHtml(r'"STS": 20760, "VISITOR_DATA":"VD2"');
      expect(f.signatureTimestamp, 20760);
      expect(f.visitorData, 'VD2');
    });

    test('bentuk menempel "sts":20755 juga terbaca', () {
      final f = parseWatchContextHtml(r'"sts":20755');
      expect(f.signatureTimestamp, 20755);
    });

    test('halaman tanpa bahan → semua null, bendera mati', () {
      final f = parseWatchContextHtml('<html>kosong</html>');
      expect(f.visitorData, isNull);
      expect(f.signatureTimestamp, isNull);
      expect(f.jsUrl, isNull);
      expect(f.hasEventId, isFalse);
      expect(f.hasYtAtN, isFalse);
    });
  });

  group('pickDirectFormat — tingkat kualitas menjadi nyata', () {
    DirectFormat fmt(int itag, int kbps, {bool ciphered = false}) => DirectFormat(
          itag: itag,
          mime: 'audio/webm',
          bitrate: kbps * 1000,
          directUrl: ciphered ? null : 'https://gv/$itag',
          cipherS: ciphered ? 'S$itag' : null,
          cipherBaseUrl: ciphered ? 'https://gv/$itag' : null,
        );
    final formats = [fmt(251, 140), fmt(140, 128), fmt(250, 64), fmt(249, 48)];

    test('Rendah: tertinggi ≤70k', () {
      expect(pickDirectFormat(formats, StreamQuality.low)?.itag, 250);
    });
    test('Normal: tertinggi ≤160k', () {
      expect(pickDirectFormat(formats, StreamQuality.normal)?.itag, 251);
    });
    test('Tinggi: tertinggi keseluruhan', () {
      expect(pickDirectFormat(formats, StreamQuality.high)?.itag, 251);
    });
    test('semua di atas plafon → terendah di atasnya', () {
      expect(pickDirectFormat([fmt(251, 140)], StreamQuality.low)?.itag, 251);
    });
    test('format tercipher terpilih; tak terpakai → null', () {
      expect(pickDirectFormat([fmt(251, 140, ciphered: true)], StreamQuality.normal)?.itag, 251);
      expect(
          pickDirectFormat(
              const [DirectFormat(itag: 1, mime: 'audio/webm')], StreamQuality.normal),
          isNull);
      expect(pickDirectFormat(const [], StreamQuality.normal), isNull);
    });
  });

  group('rakitan URL — pot/cpn/sig/sabotase', () {
    test('pot ditempel ter-encode, tidak ganda', () {
      const u = 'https://gv/v?a=1';
      expect(appendPotToken(u, 'T O K'), 'https://gv/v?a=1&pot=T%20O%20K');
      expect(appendPotToken('https://gv/v?a=1&pot=x', 'y'), 'https://gv/v?a=1&pot=x');
    });
    test('cpn ditempel sekali dengan nonce yang diberikan', () {
      final u = appendCpn('https://gv/v?a=1', nonce: 'ABCDEFGHIJKLMNOP');
      expect(u, contains('cpn=ABCDEFGHIJKLMNOP'));
      expect(appendCpn(u, nonce: 'ZZZZZZZZZZZZZZZZ'), u);
    });
    test('sig ditempel dengan nama sp; n diganti', () {
      expect(appendSignatureParam('https://gv/v?n=1', 'signature', 'S G'),
          'https://gv/v?n=1&signature=S%20G');
      expect(replaceQueryParam('https://gv/v?n=LAMA&x=1', 'n', 'BARU'),
          contains('n=BARU'));
    });
    test('sabotase membalik char pertama sig (atau pot)', () {
      expect(sabotageStreamUrl('https://gv/v?sig=ABC&x=1'), 'https://gv/v?sig=BBC&x=1');
      expect(sabotageStreamUrl('https://gv/v?pot=ABC'), 'https://gv/v?pot=BBC');
      expect(sabotageStreamUrl('https://gv/v?x=1'), 'https://gv/v?x=1');
    });
  });

  // ---------- Layanan DIRECT dengan jahitan palsu ----------
  Track track(String id) => Track(
      key: TrackKey('ytmusic', id), title: 'Lagu $id', artistNames: 'A', playableRef: id);

  const goodPage = WatchPageData(
    html: '<html>watch</html>',
    visitorData: 'VD',
    signatureTimestamp: 20761,
    jsUrl: '/s/player/x/base.js',
    source: 'uji',
  );

  DirectFormat directFmt() => const DirectFormat(
        itag: 251,
        mime: 'audio/webm; codecs="opus"',
        bitrate: 140000,
        contentLength: 4300517,
        directUrl: 'https://gv/videoplayback?expire=9&n=RAWN&sig=ABC',
      );

  DirectFormat cipherFmt() => const DirectFormat(
        itag: 251,
        mime: 'audio/webm; codecs="opus"',
        bitrate: 140000,
        contentLength: 4300517,
        cipherS: 'SCH',
        cipherSp: 'signature',
        cipherBaseUrl: 'https://gv/videoplayback?expire=9&n=RAWN',
      );

  ({
    DirectStreamService svc,
    Map<String, int> calls,
    List<String?> playerTokens,
    void Function(Duration) advance,
  }) makeService({
    bool enabled = true,
    List<DirectFormat> formats = const [],
    bool mintOk = true,
    bool solveOk = true,
    bool watchOk = true,
    bool sessionOk = true,
    int mintFailuresBeforeOk = 0,
  }) {
    final calls = <String, int>{};
    final playerTokens = <String?>[];
    var now = DateTime.now();
    var mintAttempts = 0;
    void bump(String k) => calls[k] = (calls[k] ?? 0) + 1;
    final svc = DirectStreamService(
      fetchWatchContext: (videoId) async {
        bump('watch');
        return watchOk ? goodPage : const WatchPageData(source: 'x', error: 'gagal ambil');
      },
      resolveDirectFormats: (t, {visitorData, signatureTimestamp, playerPoToken}) async {
        bump('resolve');
        playerTokens.add(playerPoToken);
        return DirectResolveData(
          playability: 'OK',
          formats: formats,
          expiresInSeconds: 21600,
        );
      },
      fetchText: (url) async {
        bump('text');
        return 'PLAYERJS';
      },
      readEnabled: () async => enabled,
      buildSession: (html) async {
        bump('session');
        return sessionOk
            ? const DirectSessionResult(ok: true, ttlSecs: 43200, visitorToken: 'VT')
            : const DirectSessionResult(ok: false, errors: ['tantangan gagal']);
      },
      mintToken: (videoId) async {
        bump('mint');
        mintAttempts++;
        final ok = mintOk && mintAttempts > mintFailuresBeforeOk;
        return ok
            ? const DirectMintResult(ok: true, token: 'TOK')
            : const DirectMintResult(ok: false, errorClass: 'cetak gagal');
      },
      solve: ({required playerJs, nChallenges = const [], sigChallenges = const [], playerKey}) async {
        bump('solve');
        if (!solveOk) return const EjsSolveOutcome(ok: false, error: 'solver mati');
        return EjsSolveOutcome(
          ok: true,
          n: {for (final c in nChallenges) c: 'SOLVED-$c'},
          sig: {for (final c in sigChallenges) c: 'SIG-$c'},
        );
      },
      now: () => now,
    );
    return (
      svc: svc,
      calls: calls,
      playerTokens: playerTokens,
      advance: (d) => now = now.add(d),
    );
  }

  group('DirectStreamService — jalur senang', () {
    test('URL langsung: n tertransformasi, pot+cpn tertempel, UA pasangan', () async {
      final h = makeService(formats: [directFmt()]);
      final info = await h.svc.tryResolve(track('V1'), StreamQuality.normal);
      expect(info, isNotNull);
      expect(info!.url, contains('n=SOLVED-RAWN'));
      expect(info.url, contains('&pot=TOK'));
      expect(info.url, contains('cpn='));
      expect(info.userAgent, kDirectPathUserAgent);
      expect(info.viaDirectPath, isTrue);
      expect(info.bitrate, 140000);
      expect(h.svc.stats.okCount, 1);
      // Cache memori: resolusi kedua tanpa jahitan lagi.
      final again = await h.svc.tryResolve(track('V1'), StreamQuality.normal);
      expect(again?.url, info.url);
      expect(h.calls['resolve'], 1);
    });

    test('tercipher: sig+n hasil solver terakit', () async {
      final h = makeService(formats: [cipherFmt()]);
      final info = await h.svc.tryResolve(track('V2'), StreamQuality.normal);
      expect(info, isNotNull);
      expect(info!.url, contains('n=SOLVED-RAWN'));
      expect(info.url, contains('&signature=SIG-SCH'));
      expect(info.url, contains('&pot=TOK'));
    });

    test('direktur-2: tanpa format → ulang dengan token player visitor', () async {
      var resolveCount = 0;
      final calls = <String, int>{};
      final svc = DirectStreamService(
        fetchWatchContext: (v) async => goodPage,
        resolveDirectFormats: (t, {visitorData, signatureTimestamp, playerPoToken}) async {
          resolveCount++;
          expect(visitorData, 'VD');
          expect(signatureTimestamp, 20761);
          return DirectResolveData(
            playability: 'OK',
            formats: playerPoToken == null ? const [] : [directFmt()],
          );
        },
        fetchText: (u) async => 'JS',
        readEnabled: () async => true,
        buildSession: (html) async =>
            const DirectSessionResult(ok: true, ttlSecs: 43200, visitorToken: 'VT'),
        mintToken: (v) async => const DirectMintResult(ok: true, token: 'TOK'),
        solve: ({required playerJs, nChallenges = const [], sigChallenges = const [], playerKey}) async =>
            EjsSolveOutcome(ok: true, n: {for (final c in nChallenges) c: c}),
      );
      final info = await svc.tryResolve(track('V3'), StreamQuality.normal);
      expect(info, isNotNull);
      expect(resolveCount, 2);
      expect(calls, isEmpty); // sanity: peta lokal tak dipakai
    });
  });

  group('DirectStreamService — matriks gagal (instruksi 23:00)', () {
    test('kill-switch mati → null tanpa menyentuh jahitan', () async {
      final h = makeService(enabled: false, formats: [directFmt()]);
      expect(await h.svc.tryResolve(track('V1'), StreamQuality.normal), isNull);
      expect(h.calls, isEmpty);
      expect(h.svc.stats.lastCause, DirectFailCause.disabled.label);
    });

    test('solver mati → gugur bersih, sebab solver, trek dikecualikan', () async {
      final h = makeService(formats: [cipherFmt()], solveOk: false);
      expect(await h.svc.tryResolve(track('V1'), StreamQuality.normal), isNull);
      expect(h.svc.stats.lastCause, DirectFailCause.solver.label);
      // Percobaan kedua untuk trek yang sama: dikecualikan, tanpa resolusi.
      expect(await h.svc.tryResolve(track('V1'), StreamQuality.normal), isNull);
      expect(h.calls['resolve'], 1);
      expect(h.svc.stats.lastCause, DirectFailCause.excluded.label);
      // Sesudah ±5 menit pengecualian lewat: dicoba lagi.
      h.advance(const Duration(minutes: 6));
      await h.svc.tryResolve(track('V1'), StreamQuality.normal);
      expect(h.calls['resolve'], 2);
    });

    test('minter gagal sekali → sesi disegarkan satu kali lalu berhasil', () async {
      final h = makeService(formats: [directFmt()], mintFailuresBeforeOk: 1);
      final info = await h.svc.tryResolve(track('V1'), StreamQuality.normal);
      expect(info, isNotNull);
      expect(h.calls['session'], 2); // lahir + segar
      expect(h.calls['mint'], 2);
    });

    test('minter gagal terus → gugur sebab minter (fallback pemanggil)', () async {
      final h = makeService(formats: [directFmt()], mintOk: false);
      expect(await h.svc.tryResolve(track('V1'), StreamQuality.normal), isNull);
      expect(h.svc.stats.lastCause, DirectFailCause.minter.label);
      expect(h.calls['mint'], 2); // satu cetak + satu sesudah segarkan
    });

    test('sesi tak bisa lahir → sebab sesi', () async {
      final h = makeService(formats: [directFmt()], sessionOk: false);
      expect(await h.svc.tryResolve(track('V1'), StreamQuality.normal), isNull);
      expect(h.svc.stats.lastCause, DirectFailCause.session.label);
      expect(h.svc.stats.lastError, 'tantangan gagal');
    });

    test('jahitan melempar → sebab lainnya + jejak langkah & teks galat', () async {
      final events = <String>[];
      final svc = DirectStreamService(
        fetchWatchContext: (v) async => goodPage,
        resolveDirectFormats: (t, {visitorData, signatureTimestamp, playerPoToken}) async =>
            DirectResolveData(playability: 'OK', formats: [directFmt()]),
        fetchText: (u) async => 'JS',
        readEnabled: () async => true,
        buildSession: (html) async => throw StateError('webview belum siap'),
        mintToken: (v) async => const DirectMintResult(ok: true, token: 'TOK'),
        solve: ({required playerJs, nChallenges = const [], sigChallenges = const [], playerKey}) async =>
            const EjsSolveOutcome(ok: true),
        onEvent: (kind, detail) => events.add('$kind|$detail'),
      );
      expect(await svc.tryResolve(track('V1'), StreamQuality.normal), isNull);
      expect(svc.stats.lastCause, DirectFailCause.unknown.label);
      expect(svc.stats.lastError, contains('langkah=sesi-minter'));
      expect(svc.stats.lastError, contains('webview belum siap'));
      expect(events.any((e) => e.startsWith('direct-jatuh') && e.contains('webview belum siap')),
          isTrue);
    });

    test('gerbang eksekusi: saklar dibalik saat antre → percobaan menunggu dilewati', () async {
      var enabled = true;
      var resolveCalls = 0;
      final gateA = Completer<void>();
      final svc = DirectStreamService(
        fetchWatchContext: (v) async => goodPage,
        resolveDirectFormats: (t, {visitorData, signatureTimestamp, playerPoToken}) async {
          resolveCalls++;
          if (t.playableRef == 'A') await gateA.future;
          return DirectResolveData(playability: 'OK', formats: [directFmt()]);
        },
        fetchText: (u) async => 'JS',
        readEnabled: () async => enabled,
        buildSession: (html) async =>
            const DirectSessionResult(ok: true, ttlSecs: 43200, visitorToken: 'VT'),
        mintToken: (v) async => const DirectMintResult(ok: true, token: 'TOK'),
        solve: ({required playerJs, nChallenges = const [], sigChallenges = const [], playerKey}) async =>
            EjsSolveOutcome(ok: true, n: {for (final c in nChallenges) c: c}),
      );
      final fA = svc.tryResolve(track('A'), StreamQuality.normal);
      final fB = svc.tryResolve(track('B'), StreamQuality.normal);
      // Biarkan B lolos gerbang masuk dan mengantre di belakang A.
      await Future<void>.delayed(const Duration(milliseconds: 20));
      enabled = false; // kill-switch dibalik SELAGI B menunggu
      gateA.complete();
      expect(await fA, isNotNull); // yang sudah berjalan: selesai wajar
      expect(await fB, isNull); // yang menunggu: dilewati gerbang eksekusi
      expect(resolveCalls, 1); // B tidak pernah menyentuh resolusi
      expect(svc.stats.lastCause, DirectFailCause.disabled.label);
    });

    test('dedupe in-flight: pemanggil serentak berbagi satu percobaan', () async {
      var resolveCalls = 0;
      final svc = DirectStreamService(
        fetchWatchContext: (v) async => goodPage,
        resolveDirectFormats: (t, {visitorData, signatureTimestamp, playerPoToken}) async {
          resolveCalls++;
          await Future<void>.delayed(const Duration(milliseconds: 30));
          return DirectResolveData(playability: 'OK', formats: [directFmt()]);
        },
        fetchText: (u) async => 'JS',
        readEnabled: () async => true,
        buildSession: (html) async =>
            const DirectSessionResult(ok: true, ttlSecs: 43200, visitorToken: 'VT'),
        mintToken: (v) async => const DirectMintResult(ok: true, token: 'TOK'),
        solve: ({required playerJs, nChallenges = const [], sigChallenges = const [], playerKey}) async =>
            EjsSolveOutcome(ok: true, n: {for (final c in nChallenges) c: c}),
      );
      final t = track('V7');
      final results = await Future.wait([
        svc.tryResolve(t, StreamQuality.normal),
        svc.tryResolve(t, StreamQuality.normal),
        svc.tryResolve(t, StreamQuality.normal),
      ]);
      expect(results.every((r) => r != null), isTrue);
      expect(resolveCalls, 1);
    });

    test('onRecovered: sukses sesudah penolakan menyala tepat satu kali', () async {
      final h = makeService(formats: [directFmt()]);
      var recovered = 0;
      h.svc.onRecovered = () => recovered++;
      final t = track('V5');
      expect(await h.svc.tryResolve(t, StreamQuality.normal), isNotNull);
      expect(recovered, 0); // belum ada penolakan: tidak menyala
      h.svc.markFetchRejected(t.key); // penolakan ke-1: cache dibuang
      expect(await h.svc.tryResolve(t, StreamQuality.normal), isNotNull);
      expect(recovered, 1); // resolusi bersih sesudah penolakan = pulih
      // Penolakan ke-2 (masih tersangka): trek DIKECUALIKAN ±5 menit —
      // resolusi dilewati, dan pulih dihitung saat ia berhasil lagi
      // sesudah pengecualian lewat.
      h.svc.markFetchRejected(t.key);
      expect(await h.svc.tryResolve(t, StreamQuality.normal), isNull);
      expect(h.svc.stats.lastCause, DirectFailCause.excluded.label);
      h.advance(const Duration(minutes: 6));
      expect(await h.svc.tryResolve(t, StreamQuality.normal), isNotNull);
      expect(recovered, 2);
    });

    test('konteks gagal 3× beruntun → demosi bucket kesehatan', () async {
      final h = makeService(watchOk: false);
      for (final id in ['A', 'B', 'C']) {
        expect(await h.svc.tryResolve(track(id), StreamQuality.normal), isNull);
        expect(h.svc.stats.lastCause, DirectFailCause.context.label);
      }
      expect(h.calls['watch'], 3);
      // Trek keempat: didemosi — tanpa menyentuh jaringan sama sekali.
      expect(await h.svc.tryResolve(track('D'), StreamQuality.normal), isNull);
      expect(h.svc.stats.lastCause, DirectFailCause.demoted.label);
      expect(h.calls['watch'], 3);
    });

    test('penolakan 403: ke-1 segarkan sesi, ke-2 kecualikan trek', () async {
      final h = makeService(formats: [directFmt()]);
      final t = track('V9');
      expect(await h.svc.tryResolve(t, StreamQuality.normal), isNotNull);
      expect(h.calls['session'], 1);
      h.svc.markFetchRejected(t.key);
      // Resolusi berikut: sesi dibangun ulang (segar satu kali), berhasil.
      expect(await h.svc.tryResolve(t, StreamQuality.normal), isNotNull);
      expect(h.calls['session'], 2);
      h.svc.markFetchRejected(t.key);
      // Kini trek dikecualikan: resolusi jatuh tanpa jahitan resolusi.
      final resolvesBefore = h.calls['resolve'];
      expect(await h.svc.tryResolve(t, StreamQuality.normal), isNull);
      expect(h.calls['resolve'], resolvesBefore);
      expect(h.svc.stats.lastCause, DirectFailCause.excluded.label);
    });
  });

  group('ResolvingAudioSource — coba-ulang 403 sebelum vonis', () {
    FetchedBytes resp(int status, {String body = 'abc'}) => FetchedBytes(
          statusCode: status,
          contentLength: body.length,
          contentRange: status == 206 ? 'bytes 0-2/3' : null,
          body: Stream<List<int>>.fromIterable([body.codeUnits]),
        );
    StreamInfo infoFor(String url) => StreamInfo(
        url: url,
        mimeType: 'audio/webm',
        expiresAt: DateTime.now().add(const Duration(hours: 1)));

    test('403, 403, lalu 206 → byte tersaji, tanpa fallback, tanpa laporan', () async {
      var fetches = 0;
      var rejected = 0;
      final src = ResolvingAudioSource(
        track('P1'),
        () async => infoFor('https://gv/adaptive'),
        resolveFallback: () async => infoFor('https://gv/muxed'),
        onPrimaryRejected: () => rejected++,
        fetcher: (uri, {required start, required endInclusive}) async {
          fetches++;
          return resp(fetches < 3 ? 403 : 206);
        },
      )..retryDelays = [Duration.zero, Duration.zero];
      final r = await src.request(0, 3);
      expect(await r.stream.expand((c) => c).toList(), 'abc'.codeUnits);
      expect(fetches, 3);
      expect(src.fallbackActive, isFalse);
      expect(rejected, 0);
    });

    test('403 badai tak pulih → fallback muxed + laporan penolakan satu kali', () async {
      var rejected = 0;
      final src = ResolvingAudioSource(
        track('P2'),
        () async => infoFor('https://gv/adaptive'),
        resolveFallback: () async => infoFor('https://gv/muxed'),
        onPrimaryRejected: () => rejected++,
        fetcher: (uri, {required start, required endInclusive}) async =>
            resp(uri.toString().contains('muxed') ? 206 : 403),
      )..retryDelays = [Duration.zero, Duration.zero];
      final r = await src.request(0, 3);
      expect(await r.stream.expand((c) => c).toList(), 'abc'.codeUnits);
      expect(src.fallbackActive, isTrue);
      expect(rejected, 1);
    });

    test('status 500 → tanpa coba-ulang, langsung fallback', () async {
      var adaptiveFetches = 0;
      final src = ResolvingAudioSource(
        track('P3'),
        () async => infoFor('https://gv/adaptive'),
        resolveFallback: () async => infoFor('https://gv/muxed'),
        fetcher: (uri, {required start, required endInclusive}) async {
          if (uri.toString().contains('adaptive')) {
            adaptiveFetches++;
            return resp(500);
          }
          return resp(206);
        },
      )..retryDelays = [Duration.zero, Duration.zero];
      await src.request(0, 3);
      expect(adaptiveFetches, 1);
      expect(src.fallbackActive, isTrue);
    });
  });

  group('LoadLadder — pasangan UA–URL', () {
    test('anak URI memakai UA info DIRECT; info biasa UA bawaan', () async {
      Track t = track('L1');
      final directInfo = StreamInfo(
        url: 'https://gv/direct',
        mimeType: 'audio/webm',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
        userAgent: kDirectPathUserAgent,
        viaDirectPath: true,
      );
      final legacyInfo = StreamInfo(
        url: 'https://gv/legacy',
        mimeType: 'audio/mp4',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      );
      LoadLadder mk(StreamInfo info) => LoadLadder(
            resolveAdaptive: (x, {stillWanted}) async => info,
            resolveMuxed: (x) async => null,
            tagFor: (x) => 'tag',
            isLocal: (x) => false,
          );
      final a = await mk(directInfo).childFor(t, LoadLadder.rungAdaptiveUri) as UriAudioSource;
      expect(a.headers?['User-Agent'], kDirectPathUserAgent);
      final b = await mk(legacyInfo).childFor(t, LoadLadder.rungAdaptiveUri) as UriAudioSource;
      expect(b.headers?['User-Agent'], ResolvingAudioSource.playerUserAgent);
    });
  });
}
