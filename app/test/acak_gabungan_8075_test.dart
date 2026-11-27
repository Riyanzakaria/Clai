import 'dart:io';

import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:clai/app.dart';
import 'package:clai/data/app_db.dart';
import 'package:clai/domain/models.dart';
import 'package:clai/l10n/app_localizations.dart';
import 'package:clai/player/audio_handler.dart';
import 'package:clai/player/queue_engine.dart';
import 'package:clai/providers/music_provider.dart';
import 'package:clai/player/similarity.dart';
import 'package:clai/ui/queue_screen.dart';

/// Ronde 8075 — Panel Acak Gabungan. Kontrak yang dijaga:
/// (1) fondasi Jujur = siklus tanpa-ulang: dalam satu siklus penuh
///     tidak ada kunci yang berulang; bungkus Repeat-Semua menanam
///     siklus baru yang teracak (bukan urutan alami) dan kepala siklus
///     baru bukan lagu yang baru selesai;
/// (2) progres siklus (dimainkan/total) akurat dan selamat dari
///     start dingin (snapshot → restore);
/// (3) Acak Cerdas terukur: sebaran artis menaikkan jarak minimum
///     artis-sama dibanding acak Jujur polos, dan yang jarang diputar
///     terukur muncul lebih dulu (suka tetap di atas jarang);
/// (4) OFF memulihkan urutan byte-exact sesudah kombinasi sakelar,
///     lompatan, acak-ulang, dan start dingin;
/// (5) panel: urutan yang TERLIHAT di lembar panel == urutan efektif
///     mesin (urutan putar sebenarnya).
Track t(String id, {String artist = 'Artis A'}) => Track(
      key: TrackKey('ytmusic', id),
      title: 'Lagu $id',
      artistNames: artist,
      duration: const Duration(minutes: 3),
      playableRef: id,
    );

List<String> ids(List<Track> l) => l.map((x) => x.id).toList();

/// Jarak minimum antara dua kemunculan artis yang sama dalam [order]
/// (jarak indeks); tak hingga bila tak ada artis yang berulang.
int minSameArtistDistance(List<Track> order) {
  final last = <String, int>{};
  var best = 1 << 30;
  for (var i = 0; i < order.length; i++) {
    final a = order[i].artistNames;
    final prev = last[a];
    if (prev != null && i - prev < best) best = i - prev;
    last[a] = i;
  }
  return best;
}

int adjacentSameArtistPairs(List<Track> order) {
  var n = 0;
  for (var i = 1; i < order.length; i++) {
    if (order[i].artistNames == order[i - 1].artistNames) n++;
  }
  return n;
}

void main() {
  group('fondasi Jujur — siklus tanpa-ulang (uji besar)', () {
    test('120 trek, 12 artis: tiga siklus penuh tanpa pengulangan '
        'di dalam siklus; bungkus menanam urutan teracak baru', () {
      final tracks = [
        for (var i = 0; i < 120; i++)
          t('s$i', artist: 'Artis ${i % 12}'),
      ];
      final e = QueueEngine()..shuffle = ShuffleMode.pure;
      e.repeat = RepeatMode.all;
      e.playContext(
          PlayContext(kind: 'playlist', label: 'Besar', tracks: tracks), 0);
      expect(e.cycleTotalCount, 120);
      expect(e.cyclePlayedCount, 1);

      List<String> runCycle() {
        final seq = <String>[e.current!.id];
        while (seq.length < 120) {
          final n = e.advance(byCompletion: true);
          expect(n, isNotNull);
          seq.add(n!.id);
        }
        return seq;
      }

      final c1 = runCycle();
      expect(c1.toSet(), hasLength(120),
          reason: 'siklus 1: 120 kunci berbeda — tanpa pengulangan');
      expect(e.cyclePlayedCount, 120,
          reason: 'progres siklus tuntas di akhir siklus');

      final c2first = e.advance(byCompletion: true);
      expect(c2first, isNotNull);
      expect(c2first!.id, isNot(c1.last),
          reason: 'kepala siklus baru bukan lagu yang baru selesai');
      final c2 = <String>[c2first.id];
      while (c2.length < 120) {
        c2.add(e.advance(byCompletion: true)!.id);
      }
      expect(c2.toSet(), hasLength(120),
          reason: 'siklus 2: tanpa pengulangan juga');
      expect(c2, isNot(ids(tracks)),
          reason: 'siklus 2 BUKAN urutan alami (cacat bocor lama)');
      expect(c2, isNot(c1), reason: 'siklus 2 permutasi baru');

      final c3first = e.advance(byCompletion: true)!;
      final c3 = <String>[c3first.id];
      while (c3.length < 120) {
        c3.add(e.advance(byCompletion: true)!.id);
      }
      expect(c3.toSet(), hasLength(120),
          reason: 'siklus 3: tanpa pengulangan juga');
    });

    test('progres siklus maju per lagu dan selamat dari start dingin',
        () {
      final tracks = [for (var i = 0; i < 30; i++) t('c$i')];
      final e = QueueEngine()..shuffle = ShuffleMode.pure;
      e.playContext(
          PlayContext(kind: 'album', label: 'A', tracks: tracks), 0);
      for (var i = 0; i < 7; i++) {
        e.advance(byCompletion: true);
      }
      expect(e.cyclePlayedCount, 8);
      expect(e.cycleTotalCount, 30);

      final snap = e.snapshot(positionMs: 0);
      expect(snap['cyclePlayed'], isNotNull,
          reason: 'snapshot membawa himpunan terputar siklus');
      final byKey = {for (final x in tracks) x.key: x};
      final e2 = QueueEngine();
      e2.restore(snap, byKey);
      expect(e2.cyclePlayedCount, 8,
          reason: 'start dingin tidak menghitung ulang siklus dari nol');
      expect(e2.cycleTotalCount, 30);
      expect(e2.shuffle, ShuffleMode.pure);
      // Siklus berlanjut tanpa pengulangan sesudah restore: putar sisa
      // antrean efektif; tidak ada kunci yang sudah terputar muncul.
      final already = (snap['cyclePlayed'] as List)
          .map((m) => (m as Map)['i'] as String)
          .toSet();
      final rest = <String>[];
      Track? n;
      while ((n = e2.advance(byCompletion: true)) != null) {
        rest.add(n!.id);
      }
      expect(rest.toSet().intersection(already), isEmpty,
          reason: 'sesudah restore, yang sudah terputar tidak dijadwalkan ulang');
    });

    test('acak-ulang: himpunan & lagu berjalan utuh, potret tidak dibuang',
        () {
      final tracks = [for (var i = 0; i < 40; i++) t('r$i')];
      final e = QueueEngine()..shuffle = ShuffleMode.pure;
      e.playContext(
          PlayContext(kind: 'album', label: 'A', tracks: tracks), 0);
      final before = e.effectiveQueue.map((x) => x.key).toSet();
      e.reshuffleUpcoming(seed: 7);
      expect(e.current!.id, 'r0');
      expect(e.effectiveQueue.map((x) => x.key).toSet(), before);
      e.restoreSmartShuffleOrder();
      expect(ids(e.continuation), [for (var i = 1; i < 40; i++) 'r$i'],
          reason: 'OFF sesudah acak-ulang tetap memulihkan urutan asli');
    });
  });

  group('Acak Cerdas — terukur (uji besar)', () {
    test('sebaran artis: jarak minimum artis-sama naik vs Jujur polos',
        () {
      // 100 trek, 10 artis × 10 — gugus padat yang membuat acak polos
      // nyaris pasti menempelkan artis yang sama.
      final tracks = [
        for (var i = 0; i < 100; i++)
          t('a$i', artist: 'Artis ${i % 10}'),
      ];
      var honestAdjacencyRuns = 0;
      var honestMinTotal = 0;
      for (var run = 0; run < 20; run++) {
        final e = QueueEngine()..shuffle = ShuffleMode.pure;
        e.playContext(
            PlayContext(kind: 'playlist', label: 'P', tracks: tracks), 0);
        final order = [e.current!, ...e.effectiveQueue];
        if (adjacentSameArtistPairs(order) > 0) honestAdjacencyRuns++;
        honestMinTotal += minSameArtistDistance(order);
      }
      expect(honestAdjacencyRuns, greaterThanOrEqualTo(15),
          reason: 'acak Jujur polos menempelkan artis sama di ≥15/20 jalan');

      final e = QueueEngine()..shuffle = ShuffleMode.smart;
      e.playContext(
          PlayContext(kind: 'playlist', label: 'P', tracks: tracks), 0);
      final smartOrder = [e.current!, ...e.effectiveQueue];
      expect(adjacentSameArtistPairs(smartOrder), 0,
          reason: 'cerdas: nol pasangan artis-sama bersebelahan');
      expect(minSameArtistDistance(smartOrder),
          greaterThan(honestMinTotal / 20),
          reason: 'jarak minimum cerdas di atas rata-rata Jujur');
    });

    test('jarang-diputar terukur lebih dulu; suka di atas jarang', () {
      // 40 artis berbeda (satu trek per artis — sebaran tidak ikut
      // bermain, yang diukur murni prioritas putar): 20 trek diputar
      // 50×, 19 trek 0×, 1 trek disukai tetapi diputar 50×.
      final frequent = [for (var i = 0; i < 20; i++) t('f$i', artist: 'F$i')];
      final rare = [for (var i = 0; i < 19; i++) t('j$i', artist: 'J$i')];
      final liked = t('suka', artist: 'Suka');
      final all = [...frequent, liked, ...rare];
      final counts = <TrackKey, int>{
        for (final x in frequent) x.key: 50,
        liked.key: 50,
      };
      final e = QueueEngine()..shuffle = ShuffleMode.smart;
      e.setSmartSignals(likedKeys: {liked.key}, playCounts: counts);
      e.playContext(
          PlayContext(kind: 'playlist', label: 'P', tracks: all), 0);
      // current = f0 (trek yang diketuk). Sisa: 39 trek terurut cerdas.
      final order = ids(e.continuation);
      final rareIdx = [for (final x in rare) order.indexOf(x.id)];
      final freqIdx = [
        for (final x in frequent.skip(1)) order.indexOf(x.id)
      ];
      expect(order.indexOf('suka'), 0,
          reason: 'yang disukai tetap paling depan (dorongan suka utuh)');
      expect(rareIdx.reduce((a, b) => a > b ? a : b),
          lessThan(freqIdx.reduce((a, b) => a < b ? a : b)),
          reason: 'SELURUH yang jarang diputar mendahului yang sering');
    });
  });

  group('OFF byte-exact — kombinasi sakelar, lompatan, start dingin', () {
    test('pure → lompat jauh → naik cerdas → acak-ulang → dingin → OFF',
        () {
      final tracks = [
        for (var i = 0; i < 50; i++)
          t('k$i', artist: 'Artis ${i % 7}'),
      ];
      final natural = ids(tracks);
      final e = QueueEngine()..shuffle = ShuffleMode.pure;
      e.playContext(
          PlayContext(kind: 'playlist', label: 'P', tracks: tracks), 0);
      // Lompat jauh ke depan (ketuk di Antrean): trek sebelum target
      // di seksi yang sama gugur dari antrean (aturan lompatan).
      final target = e.effectiveQueue[20];
      e.jumpTo(target.key);
      // Naik ke Cerdas di tengah sesi.
      e.shuffle = ShuffleMode.smart;
      e.setSmartSignals(likedKeys: {}, playCounts: {});
      e.applySmartShuffle();
      // Putar beberapa, lalu acak-ulang.
      e.advance(byCompletion: true);
      e.advance(byCompletion: true);
      e.reshuffleUpcoming(seed: 3);
      // Start dingin: snapshot → mesin baru.
      final snap = e.snapshot(positionMs: 1200);
      final byKey = {for (final x in tracks) x.key: x};
      final e2 = QueueEngine();
      e2.restore(snap, byKey);
      expect(e2.shuffle, ShuffleMode.smart);
      // OFF di mesin hasil restore: sisa antrean kembali ke urutan
      // alami — persis trek yang masih ada, dalam urutan aslinya.
      e2.restoreSmartShuffleOrder();
      final remaining = e2.effectiveQueue.map((x) => x.id).toList();
      final expected = natural.where(remaining.contains).toList();
      expect(remaining, expected,
          reason: 'urutan sisa == urutan alami disaring ke yang ada');
      expect(e2.current!.id, e.current!.id,
          reason: 'lagu berjalan tidak berganti oleh OFF');
    });

    test('turun cerdas → jujur menjaga potret: OFF tetap byte-exact', () {
      final tracks = [for (var i = 0; i < 30; i++) t('d$i')];
      final e = QueueEngine()..shuffle = ShuffleMode.smart;
      e.setSmartSignals(likedKeys: {}, playCounts: {});
      e.playContext(
          PlayContext(kind: 'album', label: 'A', tracks: tracks), 0);
      // Turun ke fondasi (semantik handler.setSmartShuffle(false)).
      e.restoreSmartShuffleOrder();
      e.shuffle = ShuffleMode.pure;
      e.applyHonestShuffle(seed: 11);
      // OFF penuh dari fondasi.
      e.restoreSmartShuffleOrder();
      expect(ids(e.continuation), [for (var i = 1; i < 30; i++) 'd$i']);
    });

    test('manual tidak pernah disentuh panel di semua kombinasi', () {
      final tracks = [for (var i = 0; i < 20; i++) t('m$i')];
      final e = QueueEngine()..shuffle = ShuffleMode.pure;
      e.playContext(
          PlayContext(kind: 'album', label: 'A', tracks: tracks), 0);
      e.enqueueNext(t('pin1'));
      e.enqueueLater(t('pin2'));
      e.shuffle = ShuffleMode.smart;
      e.applySmartShuffle();
      e.reshuffleUpcoming(seed: 5);
      e.restoreSmartShuffleOrder();
      expect(ids(e.manual), ['pin1', 'pin2'],
          reason: 'L-03: urutan manual persis seperti yang pengguna buat');
    });
  });

  group('DB v8 — snapshot antrean membawa potret & siklus', () {
    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });

    test('simpan → muat → restore: OFF byte-exact & progres utuh '
        'sesudah start dingin jalur L-16', () async {
      final db = AppDb();
      final d = await db.openAt(':memory:');
      expect(await d.getVersion(), AppDb.schemaVersion);
      expect(AppDb.schemaVersion, 9);
      final tracks = [for (var i = 0; i < 20; i++) t('v$i')];
      final e = QueueEngine()..shuffle = ShuffleMode.pure;
      e.playContext(
          PlayContext(kind: 'album', label: 'A', tracks: tracks), 0);
      e.advance(byCompletion: true);
      e.advance(byCompletion: true);
      e.advance(byCompletion: true);
      expect(e.cyclePlayedCount, 4);
      await db.saveQueueSnapshot(e.snapshot(positionMs: 500));
      final loaded = await db.loadQueueSnapshot();
      expect(loaded, isNotNull);
      expect(loaded!['naturalContinuation'], isNotNull,
          reason: 'potret alami TIDAK terbuang jalur kolom-tetap (v8)');
      expect(loaded['cyclePlayed'], isNotNull,
          reason: 'himpunan terputar siklus ikut tersimpan (v8)');
      final byKey = {for (final x in tracks) x.key: x};
      final e2 = QueueEngine();
      e2.restore(loaded, byKey);
      expect(e2.shuffle, ShuffleMode.pure);
      expect(e2.cyclePlayedCount, 4,
          reason: 'progres siklus selamat dari start dingin L-16');
      e2.restoreSmartShuffleOrder();
      // Trek yang sudah terkonsumsi tidak kembali; sisanya urutan
      // alami persis.
      final remaining = ids(e2.continuation);
      final naturalFiltered =
          ids(tracks).where(remaining.contains).toList();
      expect(remaining, naturalFiltered,
          reason: 'OFF sesudah start dingin memulihkan urutan alami');
      await db.close();
    });
  });

  group('rekonsiliasi D-07 — pref acak menimpa snapshot restore', () {
    String bodyOf(String src, String anchor, int len) {
      final at = src.indexOf(anchor);
      expect(at, greaterThanOrEqualTo(0), reason: 'jangkar: $anchor');
      final end = at + len > src.length ? src.length : at + len;
      return src.substring(at, end);
    }

    test('kedua jalur restore memanggil penengah pref; penengah '
        'membaca kedua pref dan memakai tiga operasi mesin', () {
      final src = File('lib/player/audio_handler.dart').readAsStringSync();
      final sleep = bodyOf(src, 'Future<void> restoreSleepSession', 3400);
      final cold = bodyOf(src, 'Future<void> _restoreSession()', 4600);
      expect(sleep, contains('_reconcileShufflePrefsAfterRestore();'),
          reason: 'Brankas/Lanjut Besok wajib direkonsiliasi');
      expect(cold, contains('_reconcileShufflePrefsAfterRestore();'),
          reason: 'start dingin wajib direkonsiliasi');
      final helper = bodyOf(
          src, 'Future<void> _reconcileShufflePrefsAfterRestore()', 2100);
      expect(helper, contains("'playback.smartShuffle'"));
      expect(helper, contains("'playback.shuffle'"));
      expect(helper, contains('engine.applySmartShuffle();'));
      expect(helper, contains('engine.applyHonestShuffle();'));
      expect(helper, contains('engine.restoreSmartShuffleOrder();'));
    });

    test('sesi tersimpan mati + pref menyala: lapisan diterapkan di '
        'atas urutan sesi; OFF mengembalikan urutan sesi byte-exact',
        () {
      final tracks = [
        for (var i = 0; i < 16; i++) t('b$i', artist: 'Artis ${i % 5}'),
      ];
      List<String> orderOf(QueueEngine e) => [
            if (e.current != null) e.current!.id,
            ...ids(e.continuation),
            ...ids(e.autoplay),
          ];
      final vault = QueueEngine();
      vault.playContext(
          PlayContext(kind: 'playlist', label: 'Sesi', tracks: tracks), 3);
      final snap = vault.snapshot(positionMs: 0);
      expect(snap['shuffle'], 'off');
      final sessionOrder = orderOf(vault);

      final byKey = {for (final x in tracks) x.key: x};
      final e = QueueEngine();
      e.restore(snap, byKey);
      expect(e.shuffle, ShuffleMode.off);
      expect(orderOf(e), sessionOrder,
          reason: 'restore sendiri tetap setia pada sesi');

      // Tiru rekonsiliasi pref-menyala (lapisan fondasi Jujur).
      e.shuffle = ShuffleMode.pure;
      e.applyHonestShuffle(seed: 5);
      expect([...orderOf(e)]..sort(), [...sessionOrder]..sort(),
          reason: 'lapisan hanya menyusun ulang urutan sesi');
      expect(orderOf(e), isNot(sessionOrder),
          reason: 'lapisan benar-benar menyusun ulang');

      // OFF sesudah rekonsiliasi → urutan sesi byte-exact.
      e.shuffle = ShuffleMode.off;
      e.restoreSmartShuffleOrder();
      expect(orderOf(e), sessionOrder);
    });
  });

  group('widget — panel Acak gabungan', () {
    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });

    late AppDb db;
    late ClaiAudioHandler handler;
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('acak8075');
      // Kanal platform yang disentuh rantai handler (penjadwalan
      // simpan sesi + dispose pemutar di akhir uji) dimock agar
      // MissingPluginException tidak mencemari hasil uji widget.
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async => dir.path,
      );
      messenger.setMockMethodCallHandler(
        const MethodChannel('com.ryanheise.just_audio.methods'),
        // disposeAllPlayers membaca respons sebagai Map — null melempar
        // di lapisan platform-interface, jadi balas peta kosong.
        (call) async => <dynamic, dynamic>{},
      );
      db = AppDb();
      await db.openAt('${dir.path}/t.db');
      handler = ClaiAudioHandler(
        db: db,
        provider: _FakeProvider(),
        similaritySource: _FakeSimilarity(),
      );
      await Future<void>.delayed(const Duration(milliseconds: 600));
    });

    tearDown(() async {
      await db.close();
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    Widget tree() => ProviderScope(
          overrides: [
            appDbProvider.overrideWithValue(db),
            audioHandlerProvider.overrideWithValue(handler),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('id'),
            home: Consumer(
              builder: (context, ref, _) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () => openShufflePanel(context, ref),
                    child: const Text('buka panel'),
                  ),
                ),
              ),
            ),
          ),
        );

    testWidgets('urutan terlihat di panel == urutan efektif mesin; '
        'saklar cerdas menaikkan mode', (tester) async {
      // Layar tinggi agar daftar urutan panel membangun semua barisnya
      // (ListView malas: hanya baris terlihat yang dibangun).
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.runAsync(() async {
        final tracks = [
          for (var i = 0; i < 12; i++)
            t('w$i', artist: 'Artis ${i % 4}'),
        ];
        handler.engine.shuffle = ShuffleMode.pure;
        handler.engine.playContext(
            PlayContext(kind: 'playlist', label: 'P', tracks: tracks), 0);
        await tester.pumpWidget(tree());
        await tester.tap(find.text('buka panel'));
        for (var i = 0; i < 60; i++) {
          await tester.pump(const Duration(milliseconds: 100));
          if (find.text('Urutan putar berikutnya').evaluate().isNotEmpty) {
            break;
          }
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
        expect(find.text('Urutan putar berikutnya'), findsOneWidget);
        expect(find.textContaining('sudah diputar dalam siklus ini'),
            findsOneWidget);
        // Setiap judul pada daftar terlihat, dalam urutan mesin.
        final expected = handler.engine.effectiveQueue
            .take(10)
            .map((x) => x.title)
            .toList();
        final found = <String>[];
        for (final w in find.byType(Text).evaluate()) {
          final d = (w.widget as Text).data;
          if (d != null && expected.contains(d)) found.add(d);
        }
        expect(found.length, greaterThanOrEqualTo(8),
            reason: 'daftar panel membangun hampir semua barisnya');
        expect(found, expected.sublist(0, found.length),
            reason: 'urutan TERLIHAT == urutan putar sebenarnya');
        // Saklar Cerdas di dalam panel menaikkan mode mesin. Biarkan
        // animasi buka lembar menetap dulu — ketuk di tengah geser
        // meleset dari saklar (peringatan hit-test pada jalan pertama).
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        final switches = find.byType(Switch);
        expect(switches, findsNWidgets(2));
        await tester.tap(switches.at(1));
        for (var i = 0; i < 60; i++) {
          await tester.pump(const Duration(milliseconds: 100));
          if (handler.engine.shuffle == ShuffleMode.smart) break;
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
        expect(handler.engine.shuffle, ShuffleMode.smart);
        expect(await db.pref<bool>('playback.smartShuffle'), isTrue);
        expect(await db.pref<bool>('playback.shuffle'), isTrue);
      });
    });
  });
}

class _FakeProvider implements MusicProvider {
  @override
  String get id => 'fake';
  @override
  String get displayName => 'Fake';
  @override
  Future<SearchResults> search(String query) async => const SearchResults();
  @override
  Future<List<String>> searchSuggestions(String query) async => const [];
  @override
  Future<ContentPage> getAlbum(String albumId) async =>
      ContentPage(kind: 'album', id: albumId, title: 'x', tracks: const []);
  @override
  Future<ContentPage> getPlaylist(String playlistId) async => ContentPage(
      kind: 'playlist', id: playlistId, title: 'x', tracks: const []);
  @override
  Future<ContentPage> getArtist(String artistId) async =>
      ContentPage(kind: 'artist', id: artistId, title: 'x', tracks: const []);
  @override
  Future<List<Track>> getRelated(Track seed) async => const [];
  @override
  Future<List<Track>> getSameArtist(Track seed) async => const [];
  @override
  Future<List<Artist>> getSimilarArtists(Track seed) async => const [];
  @override
  Future<List<Track>> getSameGenre(Track seed) async => const [];
  @override
  Future<StreamInfo> resolveStream(Track track, StreamQuality quality,
          {bool Function()? stillWanted}) async =>
      StreamInfo(
          url: 'https://example.invalid/x',
          mimeType: 'audio/mp4',
          expiresAt: DateTime.now().add(const Duration(hours: 1)));
  @override
  Future<StreamInfo?> resolveMuxedFallback(Track track) async => null;
}

class _FakeSimilarity implements SimilaritySource {
  @override
  Future<List<Track>> sameArtist(Track seed) async => const [];
  @override
  Future<List<Track>> related(Track seed) async => const [];
  @override
  Future<List<Artist>> similarArtists(Track seed) async => const [];
  @override
  Future<List<Track>> artistTopTracks(String artistId) async => const [];
  @override
  Future<List<Track>> sameGenre(Track seed) async => const [];
}
