import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:clai/data/app_db.dart';
import 'package:clai/services/ocr_model_service.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:clai/domain/models.dart';
import 'package:clai/player/queue_engine.dart';
import 'package:clai/player/stall_watchdog.dart';
import 'package:clai/providers/ytmusic/innertube.dart';
import 'package:clai/services/download_service.dart';
import 'package:clai/services/gate_metrics.dart';
import 'package:clai/services/observability.dart';
import 'package:clai/ui/sleep_resume_card.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Adapter Dio palsu untuk uji layanan umpan tanpa jaringan.
class _FakeAdapter implements HttpClientAdapter {
  final Future<ResponseBody> Function(RequestOptions) _handler;
  _FakeAdapter(this._handler);
  @override
  Future<ResponseBody> fetch(RequestOptions options,
          Stream<Uint8List>? requestStream, Future<void>? cancelFuture) =>
      _handler(options);
  @override
  void close({bool force = false}) {}
}

Track t(String id) => Track(
    key: TrackKey('ytmusic', id),
    title: 'Lagu $id',
    artistNames: 'Artis',
    duration: const Duration(minutes: 3),
    playableRef: id);

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('D-16/D-17 QueueEngine — sinyal sesi & antrean manual', () {
    test('playContext membersihkan sinyal sesi lama (L-06/L-07 "sesi ini")', () {
      final e = QueueEngine();
      final a = t('a');
      e.playContext(PlayContext(kind: 'album', label: 'A', tracks: [a, t('b')]), 0);
      e.noteSkipped(t('b'));
      e.noteCompleted(a);
      expect(e.skippedKeys, isNotEmpty);
      e.playContext(PlayContext(kind: 'album', label: 'B', tracks: [t('c'), t('d')]), 0);
      expect(e.skippedKeys, isEmpty, reason: 'sinyal sesi lama tidak boleh bocor ke sesi baru');
      expect(e.completedKeys, isEmpty);
    });

    test('playRadio MENJAGA antrean manual (L-03) dan membersihkan sinyal', () {
      final e = QueueEngine();
      e.playContext(PlayContext(kind: 'album', label: 'A', tracks: [t('a'), t('b')]), 0);
      e.enqueueNext(t('m1'));
      e.enqueueLater(t('m2'));
      e.noteSkipped(t('b'));
      e.playRadio(t('r'));
      expect(e.manual.map((x) => x.id), ['m1', 'm2'],
          reason: 'radio tidak boleh membuang antrean manual (pelanggaran L-03 lama)');
      expect(e.skippedKeys, isEmpty);
      expect(e.seeds.single.id, 'r');
    });
  });

  group('D-09/D-08 watchdog & refresh proaktif (murni)', () {
    DateTime at(int ms) => DateTime.fromMillisecondsSinceEpoch(ms);
    test('watchdog: posisi macet >4 dtk saat memutar → tembak SEKALI per episode', () {
      final w = StallWatchdog();
      expect(w.feed(playing: true, ready: true, positionMs: 1000, now: at(0)), isFalse);
      expect(w.feed(playing: true, ready: true, positionMs: 1000, now: at(3000)), isFalse);
      expect(w.feed(playing: true, ready: true, positionMs: 1000, now: at(4500)), isTrue);
      expect(w.feed(playing: true, ready: true, positionMs: 1000, now: at(9000)), isFalse,
          reason: 'satu episode satu tembakan');
      expect(w.feed(playing: true, ready: true, positionMs: 2000, now: at(9500)), isFalse,
          reason: 'posisi maju = episode selesai');
      expect(w.feed(playing: true, ready: true, positionMs: 2000, now: at(14000)), isTrue);
    });

    test('watchdog: jeda/buffering bukan stall', () {
      final w = StallWatchdog();
      w.feed(playing: true, ready: true, positionMs: 500, now: at(0));
      expect(w.feed(playing: false, ready: true, positionMs: 500, now: at(9000)), isFalse);
      expect(w.feed(playing: true, ready: false, positionMs: 500, now: at(20000)), isFalse);
    });

    test('refresh proaktif: sisa validitas <30 menit saja', () {
      expect(shouldProactivelyRefresh(const Duration(minutes: 29)), isTrue);
      expect(shouldProactivelyRefresh(const Duration(minutes: 31)), isFalse);
      expect(shouldProactivelyRefresh(null), isFalse);
      expect(shouldProactivelyRefresh(const Duration(minutes: -1)), isFalse);
    });
  });

  group('B-01 GateMetrics persentil', () {
    test('median & p95 nearest-rank', () {
      expect(GateMetrics.percentile([100, 200, 300, 400], 50), 200);
      expect(GateMetrics.percentile([100, 200, 300, 400], 95), 400);
      expect(GateMetrics.percentile([], 50), isNull);
      expect(GateMetrics.percentile([42], 95), 42);
    });
  });

  group('D-19/D-22 innertube', () {
    Map<String, dynamic> resWith(List<int> bitrates) => {
          'playabilityStatus': {'status': 'OK'},
          'streamingData': {
            'expiresInSeconds': '20000',
            'adaptiveFormats': [
              for (final b in bitrates)
                {
                  'itag': 140,
                  'mimeType': 'audio/mp4; codecs="mp4a.40.2"',
                  'bitrate': b,
                  'url': 'https://example.invalid/$b',
                },
            ],
          },
        };

    test('D-19: semua format di atas plafon → pilih TERENDAH, bukan tertinggi', () {
      final info = pickStreamFormat(resWith([250000, 130000]), StreamQuality.low);
      expect(info, isNotNull);
      expect(info!.bitrate, 130000,
          reason: 'fallback lama memilih audio.last = bitrate TERTINGGI');
    });

    test('D-22: isRegionUnavailable mengenali penolakan wilayah', () {
      expect(isRegionUnavailable('UNPLAYABLE', 'This video is not available in your country'), isTrue);
      expect(isRegionUnavailable('UNPLAYABLE', 'The uploader has not made this video available'), isTrue);
      expect(isRegionUnavailable('LOGIN_REQUIRED', 'Sign in to confirm your age'), isFalse);
      expect(isRegionUnavailable(null, null), isFalse);
    });
  });

  group('D-14 status unduhan — pemetaan persistensi', () {
    test('vocabulary Blueprint: running/error; warisan dipetakan', () {
      expect(downloadStatusToDb(DownloadStatus.downloading), 'running');
      expect(downloadStatusToDb(DownloadStatus.failed), 'error');
      expect(downloadStatusToDb(DownloadStatus.paused), 'paused');
      expect(downloadStatusToDb(DownloadStatus.corrupt), 'corrupt');
      expect(downloadStatusFromDb('downloading', fileExists: true), DownloadStatus.paused,
          reason: 'proses lama mati di tengah jalan → JEDA, bukan gagal');
      expect(downloadStatusFromDb('failed', fileExists: true), DownloadStatus.failed);
      expect(downloadStatusFromDb('running', fileExists: true), DownloadStatus.paused);
      expect(downloadStatusFromDb('error', fileExists: true), DownloadStatus.failed);
      expect(downloadStatusFromDb('done', fileExists: true), DownloadStatus.done);
      expect(downloadStatusFromDb('done', fileExists: false), DownloadStatus.failed,
          reason: 'status done tanpa berkas = jujur gagal, bukan selesai semu');
    });
  });

  group('D-15 jendela Lanjut Besok 48 jam', () {
    const now = 100 * 3600 * 1000;
    test('di dalam 48 jam sah; lewat kedaluwarsa; masa depan ditolak', () {
      expect(sleepSaveValid(now - 47 * 3600 * 1000, now), isTrue);
      expect(sleepSaveValid(now - 49 * 3600 * 1000, now), isFalse);
      expect(sleepSaveValid(now + 1000, now), isFalse);
    });
  });

  group('D-04 Observability — persistensi', () {
    test('entri sebelum sink terpasang ikut tersimpan; muat-balik bergabung', () async {
      final o = Observability.instance;
      o.log('awal', 'sebelum DB siap');
      final saved = <String>[];
      await o.attachPersistence(
        sink: (kind, detail, atMs) async => saved.add(kind),
        load: () async => [(at: 1, kind: 'lama', detail: 'dari DB')],
      );
      expect(saved, contains('awal'));
      o.log('baru', 'setelah pasang');
      expect(saved, contains('baru'));
      expect(o.entries.map((e) => e.kind), containsAll(['awal', 'baru', 'lama']));
    });
  });

  group('Pra-rilis umpan (laporan perangkat 2006) — klasifikasi keadaan', () {
    test('pemetaan status HTTP → jenis keadaan', () {
      expect(classifyFeedStatus(200), FeedAvailability.available);
      expect(classifyFeedStatus(404), FeedAvailability.notPublished,
          reason: '404 = repo belum punya rilis: NETRAL, bukan galat');
      expect(classifyFeedStatus(500), FeedAvailability.failed);
      expect(classifyFeedStatus(403), FeedAvailability.failed);
      expect(classifyFeedStatus(null), FeedAvailability.failed);
    });

    Future<OcrModelController> controllerWith(
        Future<ResponseBody> Function(RequestOptions) handler) async {
      final db = AppDb();
      await db.openAt(':memory:');
      final dio = Dio();
      dio.httpClientAdapter = _FakeAdapter(handler);
      final tmp = await Directory.systemTemp.createTemp('clai-ocr-');
      return OcrModelController(db,
          dio: dio,
          supportDir: () async => tmp,
          feedUrlOverride: 'http://mock.test/feed');
    }

    ResponseBody jsonBody(Object body, int status) => ResponseBody.fromString(
        jsonEncode(body), status,
        headers: {
          Headers.contentTypeHeader: ['application/json']
        });

    test('umpan 404 → unavailable (netral), BUKAN error', () async {
      final c = await controllerWith((o) async => jsonBody(
          {'message': 'Not Found'}, 404));
      await c.download();
      expect(c.status, OcrModelStatus.unavailable);
      expect(c.message, isNot(contains('404')));
    });

    test('rilis sehat tanpa aset model → unavailable (netral)', () async {
      final c = await controllerWith((o) async => jsonBody({
            'tag_name': 'v1.0.0+7',
            'assets': [
              {
                'name': 'app-arm64-v8a-release.apk',
                'browser_download_url': 'http://mock.test/app.apk',
                'size': 10
              }
            ]
          }, 200));
      await c.download();
      expect(c.status, OcrModelStatus.unavailable);
    });

    test('jaringan mati → error jujur (tetap galat, bukan netral)', () async {
      final c = await controllerWith((o) async =>
          throw DioException(
              requestOptions: o, type: DioExceptionType.connectionError));
      await c.download();
      expect(c.status, OcrModelStatus.error);
    });

    test('umpan sehat lengkap → model terpasang (mekanisme 2006 utuh)',
        () async {
      final modelBytes = Uint8List.fromList(List.filled(4096, 7));
      final manifest = {
        'lang': 'eng',
        'file': 'eng.traineddata',
        'size': modelBytes.length,
        'sha256': sha256.convert(modelBytes).toString(),
        'version': 'uji',
      };
      final c = await controllerWith((o) async {
        final u = o.uri.toString();
        if (u.endsWith('/feed')) {
          return jsonBody({
            'tag_name': 'v1.0.0+7',
            'assets': [
              {
                'name': 'clai-ocr-model.json',
                'browser_download_url': 'http://mock.test/manifest',
                'size': 10
              },
              {
                'name': 'eng.traineddata',
                'browser_download_url': 'http://mock.test/model',
                'size': modelBytes.length
              }
            ]
          }, 200);
        }
        if (u.endsWith('/manifest')) return jsonBody(manifest, 200);
        if (u.endsWith('/model')) {
          return ResponseBody.fromBytes(modelBytes, 200, headers: {
            Headers.contentLengthHeader: ['${modelBytes.length}']
          });
        }
        return jsonBody({}, 404);
      });
      await c.download();
      expect(c.status, OcrModelStatus.ready);
      expect(c.installedSize, modelBytes.length);
    });
  });

  group('D-10/D-11/D-12/D-34 Basis data', () {
    late Directory tmp;
    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('clai-sapuan-');
    });
    tearDown(() async {
      await tmp.delete(recursive: true);
    });

    // DDL v3 persis seperti kode pra-sapuan (dasar + F2 + track_gains).
    const v3Ddl = [
      '''CREATE TABLE tracks (
        provider_id TEXT NOT NULL, provider_track_id TEXT NOT NULL, title TEXT NOT NULL,
        artist_names TEXT NOT NULL, album_id TEXT, duration_ms INTEGER, artwork_url TEXT,
        is_explicit INTEGER NOT NULL DEFAULT 0, playable_ref TEXT NOT NULL, cached_at INTEGER NOT NULL,
        PRIMARY KEY (provider_id, provider_track_id))''',
      '''CREATE TABLE albums (
        provider_id TEXT NOT NULL, provider_album_id TEXT NOT NULL, title TEXT NOT NULL,
        artist_names TEXT NOT NULL, year INTEGER, artwork_url TEXT, cached_at INTEGER NOT NULL,
        PRIMARY KEY (provider_id, provider_album_id))''',
      '''CREATE TABLE artists (
        provider_id TEXT NOT NULL, provider_artist_id TEXT NOT NULL, name TEXT NOT NULL,
        artwork_url TEXT, cached_at INTEGER NOT NULL,
        PRIMARY KEY (provider_id, provider_artist_id))''',
      '''CREATE TABLE liked_tracks (
        provider_id TEXT NOT NULL, provider_track_id TEXT NOT NULL, liked_at INTEGER NOT NULL,
        PRIMARY KEY (provider_id, provider_track_id))''',
      '''CREATE TABLE playlists (
        id TEXT PRIMARY KEY, name TEXT NOT NULL, description TEXT,
        is_system INTEGER NOT NULL DEFAULT 0, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL)''',
      '''CREATE TABLE playlist_entries (
        playlist_id TEXT NOT NULL REFERENCES playlists(id) ON DELETE CASCADE,
        position INTEGER NOT NULL, provider_id TEXT NOT NULL, provider_track_id TEXT NOT NULL,
        added_at INTEGER NOT NULL, PRIMARY KEY (playlist_id, position))''',
      '''CREATE TABLE playback_events (
        id INTEGER PRIMARY KEY AUTOINCREMENT, provider_id TEXT NOT NULL, provider_track_id TEXT NOT NULL,
        started_at INTEGER NOT NULL, listened_ms INTEGER NOT NULL, completed INTEGER NOT NULL DEFAULT 0,
        context_kind TEXT, context_id TEXT)''',
      '''CREATE TABLE queue_snapshots (
        id INTEGER PRIMARY KEY CHECK (id = 1), context_kind TEXT, context_id TEXT, context_label TEXT,
        seed_json TEXT NOT NULL, manual_json TEXT NOT NULL, continuation_json TEXT NOT NULL,
        autoplay_json TEXT NOT NULL, current_ref TEXT, position_ms INTEGER NOT NULL DEFAULT 0,
        shuffle_mode TEXT NOT NULL DEFAULT 'off', repeat_mode TEXT NOT NULL DEFAULT 'off',
        autoplay_enabled INTEGER NOT NULL DEFAULT 1, session_signals_json TEXT NOT NULL DEFAULT '{}',
        saved_at INTEGER NOT NULL)''',
      '''CREATE TABLE stream_cache (
        provider_id TEXT NOT NULL, provider_track_id TEXT NOT NULL, resolved_url TEXT NOT NULL,
        mime TEXT, bitrate INTEGER, expires_at INTEGER NOT NULL,
        PRIMARY KEY (provider_id, provider_track_id))''',
      'CREATE TABLE user_prefs (key TEXT PRIMARY KEY, value_json TEXT NOT NULL, schema_v INTEGER NOT NULL)',
      '''CREATE TABLE search_history (query TEXT PRIMARY KEY, searched_at INTEGER NOT NULL)''',
      '''CREATE TABLE download_items (
        provider_id TEXT NOT NULL, provider_track_id TEXT NOT NULL, status TEXT NOT NULL,
        bytes_total INTEGER, bytes_done INTEGER NOT NULL DEFAULT 0, local_path TEXT, checksum TEXT,
        quality TEXT NOT NULL, PRIMARY KEY (provider_id, provider_track_id))''',
      '''CREATE TABLE lyrics_cache (
        provider_id TEXT NOT NULL, provider_track_id TEXT NOT NULL,
        synced TEXT, plain TEXT, source TEXT NOT NULL, found INTEGER NOT NULL DEFAULT 0,
        fetched_at INTEGER NOT NULL,
        PRIMARY KEY (provider_id, provider_track_id))''',
      '''CREATE TABLE provider_matches (
        source_provider TEXT NOT NULL, source_id TEXT NOT NULL,
        target_provider TEXT NOT NULL, target_track_id TEXT,
        status TEXT NOT NULL, checked_at INTEGER NOT NULL,
        PRIMARY KEY (source_provider, source_id))''',
      '''CREATE TABLE enrichment_cache (
        kind TEXT NOT NULL, cache_key TEXT NOT NULL, value TEXT,
        fetched_at INTEGER NOT NULL, PRIMARY KEY (kind, cache_key))''',
      '''CREATE TABLE track_gains (
        provider_id TEXT NOT NULL, provider_track_id TEXT NOT NULL,
        gain REAL NOT NULL, updated_at INTEGER NOT NULL,
        PRIMARY KEY (provider_id, provider_track_id))''',
    ];

    Future<void> seedV3(String path, {bool withPlayedColumn = false}) async {
      final raw = await openDatabase(path, version: 3, onCreate: (db, v) async {
        for (final ddl in v3Ddl) {
          await db.execute(ddl);
        }
        if (withPlayedColumn) {
          // Simulasi migrasi TERPUTUS: kolom sudah ditambah, versi belum naik —
          // ALTER sapuan akan gagal (kolom duplikat) → jalur pemulihan D-12.
          await db.execute(
              "ALTER TABLE queue_snapshots ADD COLUMN played_json TEXT NOT NULL DEFAULT '[]'");
        }
      });
      final batch = raw.batch();
      for (final id in ['a', 'b']) {
        batch.insert('tracks', {
          'provider_id': 'ytmusic', 'provider_track_id': id, 'title': 'Lagu $id',
          'artist_names': 'Artis', 'duration_ms': 180000,
          'playable_ref': id, 'cached_at': 1000,
        });
      }
      batch.insert('liked_tracks',
          {'provider_id': 'ytmusic', 'provider_track_id': 'a', 'liked_at': 5});
      batch.insert('playlists',
          {'id': 'pl1', 'name': 'Uji', 'is_system': 0, 'created_at': 1, 'updated_at': 1});
      batch.insert('playlist_entries', {
        'playlist_id': 'pl1', 'position': 0, 'provider_id': 'ytmusic',
        'provider_track_id': 'a', 'added_at': 1,
      });
      batch.insert('playback_events', {
        'provider_id': 'ytmusic', 'provider_track_id': 'a', 'started_at': 1,
        'listened_ms': 1000, 'completed': 1,
      });
      await batch.commit(noResult: true);
      await raw.close();
    }

    test('migrasi v3→v4: jumlah baris identik + tabel F4 ada (PRD Bab 8)', () async {
      final path = '${tmp.path}/v3.db';
      await seedV3(path);
      final db = AppDb();
      final d = await db.openAt(path);
      expect(await d.getVersion(), AppDb.schemaVersion);
      expect((await db.likedTracks()).map((x) => x.id), ['a']);
      expect(await db.playlistCount('pl1'), 1);
      final events = await d.rawQuery('SELECT COUNT(*) c FROM playback_events');
      expect(events.single['c'], 1);
      for (final tbl in ['album_tracks', 'remote_playlists', 'remote_playlist_tracks', 'incident_log', 'saved_items']) {
        final r = await d.rawQuery(
            "SELECT name FROM sqlite_master WHERE type='table' AND name=?", [tbl]);
        expect(r, isNotEmpty, reason: 'tabel $tbl (Blueprint 2.1/2.2) harus ada di v4');
      }
      await db.close();
    });

    test('D-12: migrasi gagal → cadangan pra-naik dibuka, data selamat, tercatat', () async {
      final path = '${tmp.path}/gagal.db';
      await seedV3(path, withPlayedColumn: true);
      final db = AppDb();
      await db.openAt(path);
      expect(db.migrationRecovered, isTrue,
          reason: 'kegagalan migrasi TIDAK boleh membunuh aplikasi (Blueprint 2.5)');
      expect((await db.likedTracks()).map((x) => x.id), ['a'],
          reason: 'data dari cadangan pra-migrasi utuh');
      await db.close();
    });

    test('D-34/D-04: potret played+volume & log insiden membulat via DB', () async {
      final db = AppDb();
      await db.openAt(':memory:');
      await db.saveQueueSnapshot({
        'seeds': ['ytmusica'],
        'manual': <String>[],
        'continuation': <String>[],
        'autoplay': <String>[],
        'currentRef': 'ytmusica',
        'played': ['ytmusicz'],
        'positionMs': 42000,
        'repeat': 'off',
        'shuffle': 'off',
        'autoplayEnabled': true,
        'volume': 0.6,
      });
      final snap = await db.loadQueueSnapshot();
      expect(snap!['played'], ['ytmusicz']);
      expect(snap['volume'], 0.6);
      await db.insertIncident('uji', 'rinci', at: 123);
      final inc = await db.incidents();
      expect(inc.single.kind, 'uji');
      await db.close();
    });

    test('D-11 retensi: stream_cache kedaluwarsa+kepenuhan, events tua, katalog LRU', () async {
      final db = AppDb();
      final d = await db.openAt(':memory:');
      const now = 100000000000;
      // 250 entri stream_cache: 240 segar (kadaluwarsa masa depan), 10 lampau.
      final batch = d.batch();
      for (var i = 0; i < 240; i++) {
        batch.insert('stream_cache', {
          'provider_id': 'ytmusic', 'provider_track_id': 'k$i',
          'resolved_url': 'https://example.invalid/$i',
          'expires_at': now + 3600000 + i,
        });
      }
      for (var i = 0; i < 10; i++) {
        batch.insert('stream_cache', {
          'provider_id': 'ytmusic', 'provider_track_id': 'old$i',
          'resolved_url': 'https://example.invalid/old$i',
          'expires_at': now - 1000,
        });
      }
      batch.insert('playback_events', {
        'provider_id': 'ytmusic', 'provider_track_id': 'a',
        'started_at': now - 400 * 86400000, 'listened_ms': 10,
      });
      batch.insert('playback_events', {
        'provider_id': 'ytmusic', 'provider_track_id': 'a',
        'started_at': now, 'listened_ms': 10,
      });
      // Trek tua tak-terujuk vs trek tua yang disukai.
      batch.insert('tracks', {
        'provider_id': 'ytmusic', 'provider_track_id': 'orphan', 'title': 'Yatim',
        'artist_names': 'A', 'playable_ref': 'orphan',
        'cached_at': now - 200 * 86400000,
      });
      batch.insert('tracks', {
        'provider_id': 'ytmusic', 'provider_track_id': 'liked', 'title': 'Suka',
        'artist_names': 'A', 'playable_ref': 'liked',
        'cached_at': now - 200 * 86400000,
      });
      batch.insert('liked_tracks', {
        'provider_id': 'ytmusic', 'provider_track_id': 'liked', 'liked_at': 1,
      });
      await batch.commit(noResult: true);
      await db.pruneRetention(
          historyDays: 365, now: DateTime.fromMillisecondsSinceEpoch(now));
      final sc = await d.rawQuery('SELECT COUNT(*) c FROM stream_cache');
      expect(sc.single['c'], 200, reason: 'batas 200 baris Blueprint 2.4');
      final ev = await d.rawQuery('SELECT COUNT(*) c FROM playback_events');
      expect(ev.single['c'], 1, reason: 'event >365 hari dibuang, yang baru tinggal');
      final tr = await d.rawQuery('SELECT provider_track_id FROM tracks');
      expect(tr.map((r) => r['provider_track_id']), ['liked'],
          reason: 'LRU 90 hari membuang yatim, menjaga yang disukai');
      await db.close();
    });

    test('D-10/D-13: cache jelajah + item tersimpan membulat', () async {
      final db = AppDb();
      await db.openAt(':memory:');
      await db.cacheTracks([t('x')]);
      final page = ContentPage(
        kind: 'album', id: 'ALB1', title: 'Album Uji', subtitle: 'Artis',
        tracks: [t('x')], albums: const [], relatedArtists: const [],
      );
      await db.cacheBrowsePage('album', page);
      final back = await db.browseCachePage('album', 'ALB1');
      expect(back, isNotNull);
      expect(back!.title, 'Album Uji');
      expect(back.tracks.single.id, 'x');
      await db.setSavedItem('album', 'ytmusic', 'ALB1', true,
          title: 'Album Uji', subtitle: 'Artis');
      expect(await db.isSavedItem('album', 'ytmusic', 'ALB1'), isTrue);
      expect((await db.savedItems('album')).single['item_id'], 'ALB1');
      await db.close();
    });
  });
}
