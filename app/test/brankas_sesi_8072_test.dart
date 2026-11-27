// Ronde 8072 — Brankas Sesi (KOMPOSISI-F3 Paket Pertama butir 6;
// USER-FLOW F-17).
//
// Kontrak yang diuji:
// (1) DB v6: tabel saved_sessions lahir di buat-baru DAN migrasi v5→v6
//     (data lama utuh); simpan→meta→snapshot→hapus putar-balik persis;
//     hitungan trek dihitung dari snapshot; JSON rusak terbaca null,
//     tidak melempar.
// (2) Nama bawaan berpola waktu per locale ("Sabtu malam, 21 Nov").
// (3) Jahitan pulih: snapshot antrean penuh yang tersimpan di brankas —
//     termasuk potret urutan alami Smart Shuffle (jahitan 8067) —
//     memulihkan mesin ke urutan & lagu berjalan yang PERSIS, dan OFF
//     mengembalikan urutan alami persis.
// (4) Widget: keadaan kosong jujur, daftar berisi, detail terlarut
//     (urutan putar + penanda titik berhenti), lembar konfirmasi pulih.
import 'dart:io';

import 'package:flutter/material.dart';
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
import 'package:clai/services/session_vault.dart';
import 'package:clai/ui/session_vault_screen.dart';

Track _t(String id) => Track(
      key: TrackKey('ytmusic', id),
      title: 'Lagu $id',
      artistNames: 'Artis $id',
      duration: const Duration(minutes: 3),
      playableRef: id,
    );

Map<String, Object?> _snap({
  List<String> played = const [],
  String? current = 'c1',
  List<String> manual = const [],
  List<String> continuation = const [],
  List<String> autoplay = const [],
  int positionMs = 42000,
}) =>
    <String, Object?>{
      'contextKind': 'search',
      'contextId': null,
      'contextLabel': 'Konteks Uji',
      'seeds': [
        {'p': 'ytmusic', 'i': 'c1'}
      ],
      'manual': [
        for (final i in manual) {'p': 'ytmusic', 'i': i}
      ],
      'continuation': [
        for (final i in continuation) {'p': 'ytmusic', 'i': i}
      ],
      'autoplay': [
        for (final i in autoplay) {'p': 'ytmusic', 'i': i}
      ],
      'played': [
        for (final i in played) {'p': 'ytmusic', 'i': i}
      ],
      'currentRef': current == null ? null : 'ytmusic|$current',
      'positionMs': positionMs,
      'shuffle': 'off',
      'repeat': 'off',
      'autoplayEnabled': true,
      'signals': {'skipped': [], 'completed': []},
    };

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

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('DB v6 — Brankas Sesi', () {
    test('simpan → meta terhitung → snapshot utuh → hapus', () async {
      final db = AppDb();
      final d = await db.openAt(':memory:');
      // Versi skema kini 9 sejak Ronde 8092 (kolom artist_ids di
      // tracks); asersi versi mengikuti skema berjalan, bukan angka
      // ronde ini.
      expect(await d.getVersion(), AppDb.schemaVersion);
      expect(AppDb.schemaVersion, 9);
      final snap = _snap(
        played: ['p1'],
        manual: ['m1'],
        continuation: ['k1', 'k2'],
        autoplay: ['a1'],
      );
      final id = await db.saveVaultSession(
          name: 'Sesi Uji', snapshot: snap, currentTrack: _t('c1'));
      final rows = await db.vaultSessions();
      expect(rows, hasLength(1));
      final row = rows.single;
      expect(row['id'], id);
      expect(row['name'], 'Sesi Uji');
      // 1 riwayat + 1 berjalan + 1 manual + 2 lanjutan + 1 autoplay.
      expect(row['track_count'], 6);
      expect(row['current_title'], 'Lagu c1');
      expect(row['context_label'], 'Konteks Uji');
      expect(row['position_ms'], 42000);
      final back = await db.vaultSnapshot(id);
      expect(back, isNotNull);
      expect(back!['currentRef'], 'ytmusic|c1');
      expect((back['continuation'] as List).length, 2);
      await db.deleteVaultSession(id);
      expect(await db.vaultSessions(), isEmpty);
      expect(await db.vaultSnapshot(id), isNull);
      await db.close();
    });

    test('urutan terbaru dulu walau milidetik sama', () async {
      final db = AppDb();
      await db.openAt(':memory:');
      await db.saveVaultSession(
          name: 'Pertama', snapshot: _snap(), currentTrack: _t('c1'));
      await db.saveVaultSession(
          name: 'Kedua', snapshot: _snap(), currentTrack: _t('c1'));
      final rows = await db.vaultSessions();
      expect(rows.map((r) => r['name']).toList(), ['Kedua', 'Pertama']);
      await db.close();
    });

    test('snapshot_json rusak terbaca null, tidak melempar', () async {
      final db = AppDb();
      final d = await db.openAt(':memory:');
      await d.insert('saved_sessions', {
        'id': 'rusak',
        'name': 'Rusak',
        'saved_at': 1,
        'snapshot_json': 'bukan json {',
        'track_count': 0,
      });
      expect(await db.vaultSnapshot('rusak'), isNull);
      expect(await db.vaultSnapshot('tidak-ada'), isNull);
      await db.close();
    });

    test('migrasi v5 → skema kini: tabel lahir, data lama utuh', () async {
      final dir = await Directory.systemTemp.createTemp('clai_mig6');
      final path = '${dir.path}/v5.db';
      final v5 = await databaseFactoryFfi.openDatabase(path,
          options: OpenDatabaseOptions(
            version: 5,
            onCreate: (d, v) async {
              await d.execute(
                  'CREATE TABLE user_prefs (key TEXT PRIMARY KEY, value_json TEXT NOT NULL, schema_v INTEGER NOT NULL)');
              await d.insert('user_prefs', {
                'key': 'uji.lama',
                'value_json': '"tetap"',
                'schema_v': 1,
              });
            },
          ));
      await v5.close();
      final db = AppDb();
      final d = await db.openAt(path);
      expect(await d.getVersion(), AppDb.schemaVersion);
      expect(await db.pref<String>('uji.lama'), 'tetap');
      final id = await db.saveVaultSession(
          name: 'Sesudah Migrasi', snapshot: _snap(), currentTrack: _t('c1'));
      expect(await db.vaultSnapshot(id), isNotNull);
      await db.close();
      await dir.delete(recursive: true);
    });
  });

  group('nama bawaan & label (murni)', () {
    test('pola desain "Jumat malam, 21 Nov" per locale & bagian hari', () {
      // 21 Nov 2026 = Sabtu.
      expect(defaultSessionName(DateTime(2026, 11, 21, 20, 30), 'id'),
          'Sabtu malam, 21 Nov');
      expect(defaultSessionName(DateTime(2026, 11, 21, 8, 0), 'id'),
          'Sabtu pagi, 21 Nov');
      expect(defaultSessionName(DateTime(2026, 11, 21, 13, 0), 'id'),
          'Sabtu siang, 21 Nov');
      expect(defaultSessionName(DateTime(2026, 11, 21, 16, 0), 'id'),
          'Sabtu sore, 21 Nov');
      expect(defaultSessionName(DateTime(2026, 11, 21, 20, 30), 'en'),
          'Saturday night, Nov 21');
      expect(defaultSessionName(DateTime(2026, 11, 21, 9, 0), 'en'),
          'Saturday morning, Nov 21');
    });

    test('label tanggal & jam', () {
      expect(vaultDateLabel(DateTime(2026, 11, 21), 'id'), '21 Nov 2026');
      expect(vaultDateLabel(DateTime(2026, 11, 21), 'en'), 'Nov 21, 2026');
      expect(vaultTimeLabel(DateTime(2026, 11, 21, 9, 5)), '09:05');
      expect(vaultTimeLabel(DateTime(2026, 11, 21, 19, 42)), '19:42');
    });
  });

  group('jahitan pulih — putar-balik snapshot brankas di mesin', () {
    test('urutan, riwayat, mode cerdas & potret alami bertahan persis',
        () async {
      final db = AppDb();
      await db.openAt(':memory:');
      final tracks = [for (var i = 1; i <= 8; i++) _t('$i')];
      final extra = _t('9');
      final all = [...tracks, extra];
      final byKey = {for (final t in all) t.key: t};

      final a = QueueEngine();
      a.setSmartSignals(
        likedKeys: {_t('5').key},
        playCounts: {_t('6').key: 9},
      );
      a.playContext(
        PlayContext(kind: 'search', label: 'Uji', tracks: tracks),
        0,
      );
      // Maju dua trek lewat jalur yang mencatat riwayat sesi (gerak
      // manual silang-memudar mesin — jalur advance() polos memang
      // tidak mencatat played; pencatatnya handler/jalur ini).
      a.takeNextForCrossfade(manualSkip: true);
      a.takeNextForCrossfade(manualSkip: true);
      a.enqueueNext(extra);
      a.shuffle = ShuffleMode.smart;
      a.applySmartShuffle();
      expect(a.current!.id, '3');
      expect(a.played.map((t) => t.id).toList(), ['1', '2']);

      final vault = SessionVaultService(db);
      final id = await vault.saveCurrent(
        engine: a,
        position: const Duration(milliseconds: 12345),
        name: 'Sesi Mesin',
      );
      expect(id, isNotNull);
      final back = await vault.snapshotOf(id!);
      expect(back, isNotNull);

      final b = QueueEngine();
      b.restore(back!, byKey);
      expect(b.current!.id, '3');
      expect(b.played.map((t) => t.id).toList(), ['1', '2']);
      expect(
        b.fullQueue.map((t) => t.id).toList(),
        a.fullQueue.map((t) => t.id).toList(),
      );
      expect(b.shuffle, ShuffleMode.smart);
      // OFF sesudah pulih dari brankas: urutan alami konteks persis
      // (jahitan 8067 tidak rusak oleh serialisasi brankas).
      b.restoreSmartShuffleOrder();
      expect(b.continuation.map((t) => t.id).toList(),
          ['4', '5', '6', '7', '8']);
      expect(b.manual.map((t) => t.id).toList(), ['9']);
      await db.close();
    });

    test('saveCurrent tanpa lagu berjalan → null, tanpa baris', () async {
      final db = AppDb();
      await db.openAt(':memory:');
      final vault = SessionVaultService(db);
      final id = await vault.saveCurrent(
        engine: QueueEngine(),
        position: Duration.zero,
        name: 'Kosong',
      );
      expect(id, isNull);
      expect(await db.vaultSessions(), isEmpty);
      await db.close();
    });

    test(
        'Uji Besar — 10x siklus simpan-pulih: nol drift, nol duplikasi, mode utuh',
        () async {
      final db = AppDb();
      await db.openAt(':memory:');
      final vault = SessionVaultService(db);
      final tracks = [for (var i = 1; i <= 8; i++) _t('$i')];
      final extra = _t('9');
      final byKey = {for (final t in [...tracks, extra]) t.key: t};

      var engine = QueueEngine();
      engine.setSmartSignals(
        likedKeys: {_t('5').key},
        playCounts: {_t('6').key: 9},
      );
      engine.playContext(
        PlayContext(kind: 'search', label: 'Siklus', tracks: tracks),
        0,
      );
      engine.takeNextForCrossfade(manualSkip: true);
      engine.takeNextForCrossfade(manualSkip: true);
      engine.enqueueNext(extra);
      engine.shuffle = ShuffleMode.smart;
      engine.applySmartShuffle();

      // fullQueue sudah memuat trek berjalan sebagai elemen pertama.
      List<String> seqOf(QueueEngine e) => [
            for (final t in e.played) t.id,
            for (final t in e.fullQueue) t.id,
          ];
      final before = seqOf(engine);
      expect(before.length, 9);

      for (var cycle = 1; cycle <= 10; cycle++) {
        final id = await vault.saveCurrent(
          engine: engine,
          position: const Duration(milliseconds: 5000),
          name: 'Siklus $cycle',
        );
        expect(id, isNotNull, reason: 'siklus $cycle: simpan gagal');
        final back = await vault.snapshotOf(id!);
        expect(back, isNotNull, reason: 'siklus $cycle: snapshot hilang');
        final fresh = QueueEngine();
        fresh.restore(back!, byKey);
        expect(seqOf(fresh), before,
            reason: 'siklus $cycle: urutan bergeser');
        expect(fresh.shuffle, ShuffleMode.smart,
            reason: 'siklus $cycle: mode cerdas hilang');
        expect(fresh.manual.map((t) => t.id).toList(), ['9'],
            reason: 'siklus $cycle: manual berubah');
        engine = fresh;
      }
      expect((await db.vaultSessions()).length, 10,
          reason: 'satu sesi per siklus — tak ada duplikasi');
      await db.close();
    });
  });

  group('widget — Brankas Sesi', () {
    late AppDb db;
    late ClaiAudioHandler handler;
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('brankas8072');
      db = AppDb();
      await db.openAt('${dir.path}/t.db');
      handler = ClaiAudioHandler(
        db: db,
        provider: _FakeProvider(),
        similaritySource: _FakeSimilarity(),
      );
      // Rantai _init handler menetap dulu (pola lirik_basi_8068).
      await Future<void>.delayed(const Duration(milliseconds: 600));
    });

    tearDown(() async {
      await db.close();
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    Widget tree(Widget home) => ProviderScope(
          overrides: [
            appDbProvider.overrideWithValue(db),
            audioHandlerProvider.overrideWithValue(handler),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('id'),
            home: home,
          ),
        );

    Future<void> untilFound(WidgetTester tester, Finder finder) async {
      for (var i = 0; i < 150; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        if (finder.evaluate().isNotEmpty) return;
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      await tester.pump();
    }

    testWidgets('keadaan kosong jujur; kartu simpan sembunyi tanpa lagu',
        (tester) async {
      await tester.runAsync(() async {
        await tester.pumpWidget(tree(const SessionVaultScreen()));
        await untilFound(
            tester, find.textContaining('Belum ada sesi tersimpan'));
        expect(find.textContaining('Belum ada sesi tersimpan'),
            findsOneWidget);
        expect(find.text('Simpan antrean saat ini'), findsNothing);
      });
    });

    testWidgets('daftar berisi + kartu simpan saat ada lagu berjalan',
        (tester) async {
      await tester.runAsync(() async {
        await db.cacheTracks([_t('c1'), _t('k1')]);
        await db.saveVaultSession(
          name: 'Sesi Widget',
          snapshot: _snap(continuation: ['k1']),
          currentTrack: _t('c1'),
        );
        handler.engine.current = _t('c1');
        await tester.pumpWidget(tree(const SessionVaultScreen()));
        await untilFound(tester, find.text('Sesi Widget'));
        expect(find.text('Sesi Widget'), findsOneWidget);
        expect(find.text('Simpan antrean saat ini'), findsOneWidget);
      });
    });

    testWidgets('detail terlarut: urutan putar + penanda berhenti + lembar pulih',
        (tester) async {
      late VaultSessionInfo info;
      await tester.runAsync(() async {
        await db.cacheTracks([_t('p1'), _t('c1'), _t('k1')]);
        final id = await db.saveVaultSession(
          name: 'Sesi Detail',
          snapshot: _snap(played: ['p1'], continuation: ['k1']),
          currentTrack: _t('c1'),
        );
        info = VaultSessionInfo.fromRow((await db.vaultSessions()).single);
        expect(info.id, id);
        await tester.pumpWidget(tree(SessionDetailScreen(info: info)));
        await untilFound(tester, find.text('Lagu k1'));
        // Urutan putar: riwayat → berhenti → lanjutan.
        expect(find.text('Lagu p1'), findsOneWidget);
        expect(find.text('Lagu c1'), findsOneWidget);
        expect(find.text('Lagu k1'), findsOneWidget);
        expect(find.text('Berhenti di sini'), findsOneWidget);
        // Konfirmasi pulih = lembar, bukan aksi langsung.
        await tester.tap(find.text('Pulihkan sesi'));
        await untilFound(
            tester, find.textContaining('akan digantikan oleh sesi ini'));
        expect(find.text('Sesi Detail'), findsWidgets);
      });
    });

    testWidgets(
        'snapshot bengkok bentuk: Detail gagal jujur, Pulihkan nonaktif',
        (tester) async {
      // Snapshot JSON sah tetapi currentRef berbentuk PETA, bukan string
      // "provider|id" — bentuk rusak yang tertangkap Uji Besar emulator
      // 8072 (cast `as String?` melempar → Detail berputar selamanya,
      // tombol Pulihkan mati dalam keadaan sibuk). Kini keduanya jatuh
      // ke jalur gagal jujur.
      await tester.runAsync(() async {
        await db.cacheTracks([_t('c1'), _t('k1')]);
        final bent = Map<String, Object?>.of(_snap(continuation: ['k1']));
        bent['currentRef'] = {'p': 'ytmusic', 'i': 'c1'};
        await db.saveVaultSession(
          name: 'Sesi Bengkok',
          snapshot: bent,
          currentTrack: _t('c1'),
        );
        final info =
            VaultSessionInfo.fromRow((await db.vaultSessions()).single);
        await tester.pumpWidget(tree(SessionDetailScreen(info: info)));
        await untilFound(
            tester, find.textContaining('tidak bisa dipulihkan'));
        expect(find.textContaining('tidak bisa dipulihkan'), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsNothing);
        final btn = tester.widget<FilledButton>(find.byType(FilledButton));
        expect(btn.onPressed, isNull);
      });
    });

    testWidgets('rak Beranda menampilkan sesi tersimpan', (tester) async {
      await tester.runAsync(() async {
        await db.saveVaultSession(
          name: 'Sesi Rak',
          snapshot: _snap(),
          currentTrack: _t('c1'),
        );
        await tester.pumpWidget(
            tree(const Scaffold(body: SessionShelf())));
        await untilFound(tester, find.text('Sesi Rak'));
        expect(find.text('Sesi Rak'), findsOneWidget);
        expect(find.text('Brankas Sesi'), findsOneWidget);
      });
    });
  });
}
