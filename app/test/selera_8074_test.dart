import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:clai/app.dart';
import 'package:clai/data/app_db.dart';
import 'package:clai/domain/models.dart';
import 'package:clai/domain/personal_rank.dart';
import 'package:clai/domain/taste_mirror.dart';
import 'package:clai/l10n/app_localizations.dart';
import 'package:clai/player/similarity.dart';
import 'package:clai/services/taste_service.dart';
import 'package:clai/ui/samaran_pill.dart';
import 'package:clai/ui/taste_control_screen.dart';

/// Ronde 8074 — Ruang Kendali Selera. Kontrak yang dijaga:
/// (1) bobot selera: e=1 PERSIS peringkat campuran F2.5 (bawaan tak
///     mengubah perilaku lama), e=0 hitungan seumur murni;
/// (2) cermin murni dari cap waktu: pola jam/hari + keseimbangan;
/// (3) pengecualian RETROAKTIF sebagai saringan baca — riwayat tidak
///     pernah diubah, urungkan mengembalikan keadaan persis;
/// (4) tangga Putar Otomatis menghormati pengecualian;
/// (5) Reset Selera menghapus data turunan selera SAJA (perpustakaan,
///     playlist, suka utuh) dalam keadaan atomik terbaca;
/// (6) Samaran: keadaan persisten + gerbang handler membaca pemeriksa.
Track mk(String id, String title, String artist) => Track(
    key: TrackKey('ytmusic', id),
    title: title,
    artistNames: artist,
    playableRef: id,
    duration: const Duration(minutes: 3));

const dayMs = 86400000;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('bobot selera (murni)', () {
    test('e=1 identik hybrid di semua umur; e=0 selalu 1', () {
      for (final age in [0, dayMs, 30 * dayMs, 90 * dayMs, 400 * dayMs]) {
        expect(tastePlayWeight(age, 1.0), hybridPlayWeight(age),
            reason: 'umur $age: bawaan harus persis F2.5');
        expect(tastePlayWeight(age, 0.0), 1.0);
      }
    });

    test('e=0,5 titik tengah linear; skor peta sama bentuknya', () {
      final age = 30 * dayMs; // hybrid = 0.5
      expect(tastePlayWeight(age, 0.5), closeTo(0.75, 1e-9));
      final plays = {
        const TrackKey('ytmusic', 'a'): [1000, 2000],
      };
      expect(tasteTrackScores(plays, 2000, 1.0),
          hybridTrackScores(plays, 2000));
      // Penekanan di luar 0..1 dijepit.
      expect(tastePlayWeight(age, 7), hybridPlayWeight(age));
      expect(tastePlayWeight(age, -2), 1.0);
    });
  });

  group('cermin selera (murni)', () {
    test('pola jam/hari + keseimbangan terkini dihitung dari cap waktu',
        () {
      // Jumat 20 Nov 2026 21:30 lokal; Senin 16 Nov 10:00; 40 hari lalu 09:00.
      final fri = DateTime(2026, 11, 20, 21, 30);
      final mon = DateTime(2026, 11, 16, 10, 0);
      final old = DateTime(2026, 10, 11, 9, 0);
      final now = DateTime(2026, 11, 21, 12, 0).millisecondsSinceEpoch;
      final events = <({int startedAt, int listenedMs})>[
        for (var i = 0; i < 6; i++)
          (
            startedAt:
                fri.millisecondsSinceEpoch + i * 60000,
            listenedMs: 60000,
          ),
        (
          startedAt: mon.millisecondsSinceEpoch,
          listenedMs: 30000,
        ),
        (
          startedAt: old.millisecondsSinceEpoch,
          listenedMs: 45000,
        ),
      ];
      final m = computeTasteMirror(events: events, nowMs: now);
      expect(m.totalPlays, 8);
      expect(m.totalListenedMs, 6 * 60000 + 30000 + 45000);
      expect(m.recentPlays, 7); // yang 40 hari lalu di luar jendela 30 hari
      expect(m.hourCounts[21], 6);
      expect(m.hourCounts[10], 1);
      expect(m.dayCounts[4], 6); // Jumat = indeks 4 (Senin 0)
      expect(m.dayCounts[0], 1); // Senin
      expect(m.peakDaypart, Daypart.malam);
      expect(m.peakDayIndex, 4);
      expect(m.recentShare, closeTo(7 / 8, 1e-9));
      expect(m.isThin, isTrue); // 8 < 10
    });

    test('kosong: nol jujur, tanpa puncak karangan', () {
      final m = computeTasteMirror(events: const [], nowMs: 1000);
      expect(m.isEmpty, isTrue);
      expect(m.peakDaypart, isNull);
      expect(m.peakDayIndex, isNull);
      expect(m.recentShare, 0);
    });
  });

  group('pencocokan pengecualian (murni)', () {
    test('byline penuh, artis primer kolaborasi, huruf/spasi', () {
      expect(artistExclusionMatches('Pamungkas', 'Pamungkas'), isTrue);
      expect(artistExclusionMatches(' pamungkas ', 'PAMUNGKAS'), isTrue);
      expect(artistExclusionMatches('Pamungkas, Hindia', 'Pamungkas'),
          isTrue);
      expect(artistExclusionMatches('Hindia, Pamungkas', 'Pamungkas'),
          isFalse,
          reason: 'hanya artis PRIMER yang menyeret kolaborasi');
      expect(artistExclusionMatches('Hindia', 'Pamungkas'), isFalse);
      expect(artistExclusionMatches('Hindia', ''), isFalse);
    });
  });

  group('basis data — pengecualian, bobot, reset', () {
    late Directory dir;
    late AppDb db;
    late Database raw;

    final a1 = mk('a1', 'Lagu A1', 'Artis X');
    final a2 = mk('a2', 'Lagu A2', 'Artis X, Tamu Z');
    final b1 = mk('b1', 'Lagu B1', 'Artis Y');

    Future<void> seedPlays(Track t, int n, int baseMs) async {
      for (var i = 0; i < n; i++) {
        await raw.insert('playback_events', {
          'provider_id': t.providerId,
          'provider_track_id': t.id,
          'started_at': baseMs + i * 3600000,
          'listened_ms': 90000,
          'completed': 1,
        });
      }
    }

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('selera8074');
      db = AppDb();
      raw = await db.openAt('${dir.path}/t.db');
      await db.cacheTracks([a1, a2, b1]);
      final now = DateTime.now().millisecondsSinceEpoch;
      await seedPlays(a1, 5, now - 2 * dayMs);
      await seedPlays(a2, 3, now - 2 * dayMs);
      await seedPlays(b1, 4, now - 2 * dayMs);
    });

    tearDown(() async {
      await db.close();
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    test('skema v7: tabel pengecualian lahir di basis data baru', () async {
      final rows = await raw.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='taste_exclusions'");
      expect(rows, hasLength(1));
      expect(await raw.getVersion(), AppDb.schemaVersion);
    });

    test('kecualikan artis: rak menyaring retroaktif; urungkan memulihkan',
        () async {
      var freq = await db.frequentTracks(limit: 10);
      expect(freq.map((t) => t.id).toSet(), {'a1', 'a2', 'b1'});
      var artists = await db.artistPlayCounts(limit: 5);
      expect(artists.map((a) => a.artistNames).toSet(),
          {'Artis X', 'Artis X, Tamu Z', 'Artis Y'});

      await db.addTasteExclusion(const TasteExclusion(
          kind: 'artist', key: 'Artis X', label: 'Artis X', createdAt: 1));

      freq = await db.frequentTracks(limit: 10);
      expect(freq.map((t) => t.id).toSet(), {'b1'},
          reason: 'a1 (artis X) dan a2 (primer X) gugur; b1 bertahan');
      artists = await db.artistPlayCounts(limit: 5);
      expect(artists.map((a) => a.artistNames).toSet(), {'Artis Y'});
      final top = await db.topPlayedSince(0, limit: 10);
      expect(top.map((e) => e.track.id).toSet(), {'b1'});
      final byArtist = await db.tracksByArtists(['Artis X'], limit: 10);
      expect(byArtist, isEmpty,
          reason: 'rak artis untuk artis yang dikeluarkan kosong');
      // Riwayat mentah TIDAK berubah — inilah arti retroaktif yang bisa
      // diurungkan.
      final countRows =
          await raw.rawQuery('SELECT COUNT(*) AS c FROM playback_events');
      expect(countRows.single['c'], 12);

      await db.removeTasteExclusion('artist', 'Artis X');
      freq = await db.frequentTracks(limit: 10);
      expect(freq.map((t) => t.id).toSet(), {'a1', 'a2', 'b1'},
          reason: 'urungkan = keadaan semula persis');
    });

    test('kecualikan per trek: hanya trek itu yang gugur', () async {
      await db.addTasteExclusion(TasteExclusion(
          kind: 'track',
          key: trackExclusionKey(b1.providerId, b1.id),
          label: b1.title,
          createdAt: 1));
      final freq = await db.frequentTracks(limit: 10);
      expect(freq.map((t) => t.id).toSet(), {'a1', 'a2'});
      final keys = await db.tasteExcludedTrackKeys();
      expect(keys, {b1.key});
    });

    test('slider bobot membalik peringkat lama-kuat vs baru-panas',
        () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      final lama = mk('lama', 'Lagu Lama', 'Artis Lama');
      final panas = mk('panas', 'Lagu Panas', 'Artis Panas');
      await db.cacheTracks([lama, panas]);
      await seedPlays(lama, 40, now - 100 * dayMs);
      await seedPlays(panas, 15, now - 2 * dayMs);
      // Bawaan (e=1): campuran F2.5 — baru-panas di atas.
      var freq = await db.frequentTracks(limit: 2);
      expect(freq.first.id, 'panas');
      // e=0: hitungan seumur murni — lama-kuat (40) di atas (15).
      await db.setPref(AppDb.prefTasteRecentEmphasis, 0.0);
      freq = await db.frequentTracks(limit: 2);
      expect(freq.first.id, 'lama');
    });

    test('reset: data selera hilang; suka/playlist/pref lain utuh',
        () async {
      await db.setLiked(a1, true);
      await db.createPlaylist('pid-uji', 'Playlist Uji');
      await db.addToPlaylist('pid-uji', a1);
      await db.addTasteExclusion(const TasteExclusion(
          kind: 'artist', key: 'Artis X', label: 'Artis X', createdAt: 1));
      await db.setPref(AppDb.prefTasteRecentEmphasis, 0.3);
      await db.setPref('ui.language', 'id');

      await db.resetTaste();

      expect(await db.allPlayEvents(), isEmpty);
      expect(await db.tasteExclusions(), isEmpty);
      expect(await db.tasteRecentEmphasis(), 1.0,
          reason: 'bobot kembali ke bawaan');
      expect(await db.isLiked(a1.key), isTrue,
          reason: 'lagu suka TIDAK ikut terhapus');
      final pls = await db.playlists();
      expect(pls.map((r) => r['name']), contains('Playlist Uji'));
      expect(await db.pref<String>('ui.language'), 'id',
          reason: 'pref di luar selera tidak disentuh');
    });
  });

  test('migrasi v6 → v7: tabel lahir, data lama utuh', () async {
    final dir = await Directory.systemTemp.createTemp('selera_mig');
    final path = '${dir.path}/v6.db';
    final v6 = await databaseFactoryFfi.openDatabase(path,
        options: OpenDatabaseOptions(
          version: 6,
          onCreate: (d, v) async {
            await d.execute(
                'CREATE TABLE user_prefs (key TEXT PRIMARY KEY, value_json TEXT NOT NULL, schema_v INTEGER NOT NULL)');
          },
        ));
    await v6.insert('user_prefs',
        {'key': 'ui.themeDynamic', 'value_json': 'false', 'schema_v': 1});
    await v6.close();
    final db = AppDb();
    final d = await db.openAt(path);
    // Skema berjalan kini 8 (Ronde 8075); migrasi v6 tetap harus
    // menembus sampai skema kini dengan data lama utuh.
    expect(await d.getVersion(), AppDb.schemaVersion);
    expect(await db.pref<bool>('ui.themeDynamic'), isFalse);
    await db.addTasteExclusion(const TasteExclusion(
        kind: 'artist', key: 'X', label: 'X', createdAt: 1));
    expect(await db.tasteExclusions(), hasLength(1));
    await db.close();
    await dir.delete(recursive: true);
  });

  group('tangga Putar Otomatis menghormati pengecualian', () {
    test('kunci trek + kunci artis yang dikeluarkan tidak jadi kandidat',
        () async {
      final ladder = SimilarityLadder(
        _FakeSource(),
        excludedKeys: {const TrackKey('ytmusic', 'sa2')},
        excludedArtistKeys: {AutoplayGate.primaryArtistKey('B')},
      );
      final batch = await ladder.buildBatch(
        seeds: [mk('seed', 'Benih', 'A')],
        alreadyQueued: const {},
        sessionNegative: const {},
        lastArtistNames: null,
      );
      final ids = batch.map((t) => t.id).toSet();
      expect(ids.contains('sa2'), isFalse, reason: 'trek dikeluarkan');
      expect(ids.contains('r1'), isFalse,
          reason: 'artis B dikeluarkan (r1 = artis B)');
      expect(ids.contains('sa1'), isTrue);
      expect(ids.contains('r2'), isTrue, reason: 'artis C tidak kena');
    });
  });

  group('layanan selera + gerbang samaran', () {
    late Directory dir;
    late AppDb db;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('selera_svc');
      db = AppDb();
      await db.openAt('${dir.path}/t.db');
    });

    tearDown(() async {
      await db.close();
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    test('samaran persisten lintas muat ulang; bawaan mati', () async {
      final svc = TasteService(db);
      await svc.load();
      expect(svc.samaranOn, isFalse);
      await svc.setSamaran(true);
      final svc2 = TasteService(db);
      await svc2.load();
      expect(svc2.samaranOn, isTrue,
          reason: 'keadaan samaran dibaca dari pref, bukan ingatan sesi');
    });

    test('layanan: kecualikan → urungkan → reset', () async {
      final svc = TasteService(db);
      await svc.load();
      await svc.excludeArtist('Artis X');
      expect(svc.exclusions, hasLength(1));
      expect(svc.artistExcluded('Artis X'), isTrue);
      await svc.setRecentEmphasis(0.25);
      expect(await db.tasteRecentEmphasis(), 0.25);
      await svc.resetTaste();
      expect(svc.exclusions, isEmpty);
      expect(svc.recentEmphasis, 1.0);
    });
  });

  group('widget — Kendali Selera & pil Samaran', () {
    late Directory dir;
    late AppDb db;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('selera_widget');
      db = AppDb();
      await db.openAt('${dir.path}/t.db');
    });

    tearDown(() async {
      await db.close();
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    Widget tree(Widget home) => ProviderScope(
          overrides: [appDbProvider.overrideWithValue(db)],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('id'),
            home: home,
          ),
        );

    // Pola untilFound 8072: pompa dengan jeda NYATA agar rantai ffi
    // basis data sempat selesai (pump(Duration) saja tidak cukup).
    Future<void> untilFound(WidgetTester tester, Finder finder) async {
      for (var i = 0; i < 150; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        if (finder.evaluate().isNotEmpty) return;
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      await tester.pump();
    }

    testWidgets('riwayat kosong: keadaan belum-terbentuk yang jujur',
        (tester) async {
      await tester.runAsync(() async {
        await tester.pumpWidget(tree(const TasteControlScreen()));
        await untilFound(
            tester, find.textContaining('belum terbentuk'));
        expect(find.textContaining('belum terbentuk'), findsOneWidget);
        expect(find.text('Mode Samaran'), findsWidgets);
        expect(find.text('Reset Selera'), findsWidgets);
      });
    });

    testWidgets(
        'regresi audit 8074: kecualikan dari layar lain menyegarkan cermin',
        (tester) async {
      // Cacat yang ditemukan audit emulator ronde ini: cermin TIDAK
      // menyaring artis yang baru dikeluarkan karena ref.listen
      // membandingkan prev/next ChangeNotifierProvider (objek yang sama).
      final x = mk('x1', 'Lagu X', 'Artis X');
      final y = mk('y1', 'Lagu Y', 'Artis Y');
      // Semua kerja basis data di dalam runAsync: future ffi nyata
      // tidak pernah selesai di zona async-palsu badan testWidgets.
      await tester.runAsync(() async {
        await db.cacheTracks([x, y]);
        for (var i = 0; i < 6; i++) {
          await db.logPlayback(x,
              listenedMs: 90000, completed: true, contextKind: 'search');
        }
        for (var i = 0; i < 5; i++) {
          await db.logPlayback(y,
              listenedMs: 90000, completed: true, contextKind: 'search');
        }
        await tester.pumpWidget(tree(const TasteControlScreen()));
        await untilFound(tester, find.text('Artis X'));
        expect(find.text('Artis X'), findsWidgets);
        expect(find.text('Artis Y'), findsWidgets);
        final container = ProviderScope.containerOf(
            tester.element(find.byType(TasteControlScreen)));
        await container.read(tasteServiceProvider).excludeArtist('Artis X');
        for (var i = 0; i < 100; i++) {
          await tester.pump(const Duration(milliseconds: 100));
          if (find.text('Artis X').evaluate().isEmpty) break;
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
        expect(find.text('Artis X'), findsNothing,
            reason:
                'artis yang dikeluarkan harus hilang dari cermin tanpa membuka ulang layar');
        expect(find.text('Artis Y'), findsWidgets);
        // Rantai tag genre berjalan malas dengan jeda serial 1 dtk antar
        // panggilan — beri waktu menetap sebelum tearDown menutup basis
        // data, kalau tidak panggilan berikutnya membuka jalur bawaan
        // dan melempar MissingPluginException sesudah uji selesai
        // (keluarga jebakan yang sama dengan AmbientController di uji pil).
        for (var i = 0; i < 20; i++) {
          await tester.pump(const Duration(milliseconds: 100));
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
      });
    });

    testWidgets('pil Samaran di Player: ketuk → gerbang S1 → menyalakan '
        'keadaan layanan', (tester) async {
      // Ronde 8079: pil kini melewati gerbang penjelas S1 (dulu ketuk
      // langsung menyala). Kontrak layanan di bawahnya tidak berubah:
      // sesudah "Aktifkan Samaran", keadaan + pref menyala.
      await tester.runAsync(() async {
        await tester.pumpWidget(tree(const Scaffold(body: SamaranPill())));
        await untilFound(tester, find.text('Samaran'));
        final svc = ProviderScope.containerOf(
                tester.element(find.byType(SamaranPill)))
            .read(tasteServiceProvider);
        expect(svc.samaranOn, isFalse);
        await tester.tap(find.text('Samaran'));
        await untilFound(tester, find.text('Cara kerja Mode Samaran'));
        expect(svc.samaranOn, isFalse,
            reason: 'gerbang S1: belum dijawab, belum boleh menyala');
        // Lembar menenangkan dulu (pompa berbingkai kecil — satu pump
        // panjang hanya merender satu bingkai; tombol masih meluncur
        // di luar layar pada bingkai pertama).
        for (var i = 0; i < 5; i++) {
          await tester.pump(const Duration(milliseconds: 100));
          await Future<void>.delayed(const Duration(milliseconds: 30));
        }
        await tester.tap(find.text('Aktifkan Samaran'));
        for (var i = 0; i < 50 && !svc.samaranOn; i++) {
          await tester.pump(const Duration(milliseconds: 100));
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
        expect(svc.samaranOn, isTrue);
        expect(await db.pref<bool>(AppDb.prefTasteSamaran), isTrue);
        // GlassSurface membangun AmbientController yang memuat 4 pref
        // berurutan secara async — beri rantai itu waktu menetap SEBELUM
        // tearDown menutup basis data (pola menetap 8072), kalau tidak
        // pref berikutnya membuka jalur bawaan dan melempar
        // MissingPluginException sesudah uji selesai.
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 100));
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
      });
    });
  });
}

class _FakeSource implements SimilaritySource {
  @override
  Future<List<Track>> sameArtist(Track seed) async =>
      [mk('sa1', 'SA1', 'A'), mk('sa2', 'SA2', 'A')];
  @override
  Future<List<Track>> related(Track seed) async =>
      [mk('r1', 'R1', 'B'), mk('r2', 'R2', 'C')];
  @override
  Future<List<Artist>> similarArtists(Track seed) async => const [];
  @override
  Future<List<Track>> artistTopTracks(String artistId) async => const [];
  @override
  Future<List<Track>> sameGenre(Track seed) async => const [];
}
