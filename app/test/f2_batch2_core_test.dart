import 'package:clai/data/app_db.dart';
import 'package:clai/domain/models.dart';
import 'package:clai/player/queue_engine.dart';
import 'package:clai/player/smart_shuffle.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Track t(String id, String artist, {String title = ''}) => Track(
      key: TrackKey('ytmusic', id),
      title: title.isEmpty ? 'Lagu $id' : title,
      artistNames: artist,
      duration: const Duration(minutes: 3),
      playableRef: id,
    );

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Smart Shuffle', () {
    test('keluaran adalah permutasi persis — tidak ada lagu baru, tidak ada yang hilang', () {
      final input = [t('1', 'A'), t('2', 'B'), t('3', 'A'), t('4', 'C'), t('5', 'B'), t('6', 'A')];
      final out = smartShuffleOrder(input, seed: 7);
      expect(out.length, input.length);
      expect(out.map((x) => x.key).toSet(), input.map((x) => x.key).toSet());
    });

    test('artis sama disebar bila kolam memungkinkan', () {
      final input = [t('1', 'A'), t('2', 'B'), t('3', 'A'), t('4', 'C'), t('5', 'A'), t('6', 'D')];
      final out = smartShuffleOrder(input, seed: 11);
      expect(hasAdjacentSameArtist(out), isFalse);
    });

    test('deterministik untuk seed yang sama; lagu disukai terdorong ke depan', () {
      final input = [t('1', 'A'), t('2', 'B'), t('3', 'C')];
      final a = smartShuffleOrder(input, seed: 3);
      final b = smartShuffleOrder(input, seed: 3);
      expect(a.map((x) => x.id).toList(), b.map((x) => x.id).toList());
      final boosted = smartShuffleOrder(input, seed: 3, likedKeys: {const TrackKey('ytmusic', '3')});
      expect(boosted.first.id, '3');
    });

    test('kolam satu artis tetap utuh (fallback jujur, bukan dibuang)', () {
      final input = [t('1', 'A'), t('2', 'A'), t('3', 'A')];
      final out = smartShuffleOrder(input, seed: 1);
      expect(out.length, 3);
    });
  });

  group('QueueEngine mode smart', () {
    test('playContext smart: berjalan tetap yang diketuk, lanjutan teracak cerdas, manual utuh', () {
      final e = QueueEngine();
      e.shuffle = ShuffleMode.smart;
      e.manual = [t('m', 'Manual')];
      final ctx = [t('1', 'A'), t('2', 'B'), t('3', 'A'), t('4', 'C')];
      e.playContext(PlayContext(kind: 'search', label: 'Cari', tracks: ctx), 1);
      expect(e.current!.id, '2');
      expect(e.continuation.map((x) => x.id).toSet(), {'1', '3', '4'});
      expect(e.manual.single.id, 'm', reason: 'L-03: manual milik pengguna, tak ikut diacak');
    });

    test('applySmartShuffle hanya mengurut ulang lanjutan; snapshot smart pulih', () {
      final e = QueueEngine();
      e.current = t('0', 'X');
      e.continuation = [t('1', 'A'), t('2', 'B'), t('3', 'A')];
      e.applySmartShuffle();
      expect(e.continuation.map((x) => x.id).toSet(), {'1', '2', '3'});
      e.shuffle = ShuffleMode.smart;
      final snap = e.snapshot(positionMs: 0);
      final e2 = QueueEngine();
      e2.restore(snap, {for (final x in [t('0', 'X'), t('1', 'A'), t('2', 'B'), t('3', 'A')]) x.key: x});
      expect(e2.shuffle, ShuffleMode.smart);
    });
  });

  group('AppDb v3', () {
    test('skema segar v3 memuat track_gains + CRUD unduhan & gain', () async {
      final db = AppDb();
      await db.openAt(':memory:');
      expect(await db.trackGain(const TrackKey('ytmusic', 'x')), isNull);
      await db.setTrackGain(const TrackKey('ytmusic', 'x'), 0.5);
      expect(await db.trackGain(const TrackKey('ytmusic', 'x')), 0.5);
      await db.saveDownloadItem(const TrackKey('ytmusic', 'x'),
          status: 'done', bytesDone: 1234, localPath: '/tmp/x.m4a', quality: 'normal');
      final item = await db.downloadItem(const TrackKey('ytmusic', 'x'));
      expect(item?['status'], 'done');
      await db.deleteDownloadItem(const TrackKey('ytmusic', 'x'));
      expect(await db.downloadItem(const TrackKey('ytmusic', 'x')), isNull);
      await db.close();
    });

    test('migrasi v2→v3: tabel lama utuh, track_gains muncul', () async {
      // Bangun berkas v2 mentah (salinan pernyataan v2 yang relevan), lalu buka lewat AppDb.
      final path = 'test-v2-to-v3.db';
      final raw = await databaseFactoryFfi.openDatabase(path, options: OpenDatabaseOptions(
        version: 2,
        onCreate: (d, _) async {
          await d.execute('''CREATE TABLE tracks (
            provider_id TEXT NOT NULL, provider_track_id TEXT NOT NULL, title TEXT NOT NULL,
            artist_names TEXT NOT NULL, album_id TEXT, duration_ms INTEGER, artwork_url TEXT,
            is_explicit INTEGER NOT NULL DEFAULT 0, playable_ref TEXT NOT NULL, cached_at INTEGER NOT NULL,
            PRIMARY KEY (provider_id, provider_track_id))''');
          await d.execute('CREATE TABLE user_prefs (key TEXT PRIMARY KEY, value_json TEXT NOT NULL, schema_v INTEGER NOT NULL)');
          // Sapuan D-12: fixture kini skema v2 LENGKAP (basis + F2) — fixture
          // dua tabel lama membuat migrasi v4 gagal di ALTER queue_snapshots
          // dan menutupi jalur migrasi asli di balik jalur pemulihan.
          for (final ddl in [
            '''CREATE TABLE albums (provider_id TEXT NOT NULL, provider_album_id TEXT NOT NULL, title TEXT NOT NULL, artist_names TEXT NOT NULL, year INTEGER, artwork_url TEXT, cached_at INTEGER NOT NULL, PRIMARY KEY (provider_id, provider_album_id))''',
            '''CREATE TABLE artists (provider_id TEXT NOT NULL, provider_artist_id TEXT NOT NULL, name TEXT NOT NULL, artwork_url TEXT, cached_at INTEGER NOT NULL, PRIMARY KEY (provider_id, provider_artist_id))''',
            '''CREATE TABLE liked_tracks (provider_id TEXT NOT NULL, provider_track_id TEXT NOT NULL, liked_at INTEGER NOT NULL, PRIMARY KEY (provider_id, provider_track_id))''',
            '''CREATE TABLE playlists (id TEXT PRIMARY KEY, name TEXT NOT NULL, description TEXT, is_system INTEGER NOT NULL DEFAULT 0, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL)''',
            '''CREATE TABLE playlist_entries (playlist_id TEXT NOT NULL, position INTEGER NOT NULL, provider_id TEXT NOT NULL, provider_track_id TEXT NOT NULL, added_at INTEGER NOT NULL, PRIMARY KEY (playlist_id, position))''',
            '''CREATE TABLE playback_events (id INTEGER PRIMARY KEY AUTOINCREMENT, provider_id TEXT NOT NULL, provider_track_id TEXT NOT NULL, started_at INTEGER NOT NULL, listened_ms INTEGER NOT NULL, completed INTEGER NOT NULL DEFAULT 0, context_kind TEXT, context_id TEXT)''',
            '''CREATE TABLE queue_snapshots (id INTEGER PRIMARY KEY CHECK (id = 1), context_kind TEXT, context_id TEXT, context_label TEXT, seed_json TEXT NOT NULL, manual_json TEXT NOT NULL, continuation_json TEXT NOT NULL, autoplay_json TEXT NOT NULL, current_ref TEXT, position_ms INTEGER NOT NULL DEFAULT 0, shuffle_mode TEXT NOT NULL DEFAULT 'off', repeat_mode TEXT NOT NULL DEFAULT 'off', autoplay_enabled INTEGER NOT NULL DEFAULT 1, session_signals_json TEXT NOT NULL DEFAULT '{}', saved_at INTEGER NOT NULL)''',
            '''CREATE TABLE stream_cache (provider_id TEXT NOT NULL, provider_track_id TEXT NOT NULL, resolved_url TEXT NOT NULL, mime TEXT, bitrate INTEGER, expires_at INTEGER NOT NULL, PRIMARY KEY (provider_id, provider_track_id))''',
            '''CREATE TABLE search_history (query TEXT PRIMARY KEY, searched_at INTEGER NOT NULL)''',
            '''CREATE TABLE download_items (provider_id TEXT NOT NULL, provider_track_id TEXT NOT NULL, status TEXT NOT NULL, bytes_total INTEGER, bytes_done INTEGER NOT NULL DEFAULT 0, local_path TEXT, checksum TEXT, quality TEXT NOT NULL, PRIMARY KEY (provider_id, provider_track_id))''',
            '''CREATE TABLE lyrics_cache (provider_id TEXT NOT NULL, provider_track_id TEXT NOT NULL, synced TEXT, plain TEXT, source TEXT NOT NULL, found INTEGER NOT NULL DEFAULT 0, fetched_at INTEGER NOT NULL, PRIMARY KEY (provider_id, provider_track_id))''',
            '''CREATE TABLE provider_matches (source_provider TEXT NOT NULL, source_id TEXT NOT NULL, target_provider TEXT NOT NULL, target_track_id TEXT, status TEXT NOT NULL, checked_at INTEGER NOT NULL, PRIMARY KEY (source_provider, source_id))''',
            '''CREATE TABLE enrichment_cache (kind TEXT NOT NULL, cache_key TEXT NOT NULL, value TEXT, fetched_at INTEGER NOT NULL, PRIMARY KEY (kind, cache_key))''',
          ]) {
            await d.execute(ddl);
          }
        },
      ));
      await raw.close();
      final db = AppDb();
      await db.openAt(path);
      final d = await db.db;
      final tables = await d.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='track_gains'");
      expect(tables.length, 1);
      await db.close();
      await databaseFactoryFfi.deleteDatabase(path);
    });

    test('playCounts & artistPlayCounts dari playback_events', () async {
      final db = AppDb();
      await db.openAt(':memory:');
      await db.logPlayback(t('1', 'Artis A'), listenedMs: 1000, completed: true);
      await db.logPlayback(t('1', 'Artis A'), listenedMs: 1000, completed: true);
      await db.logPlayback(t('2', 'Artis B'), listenedMs: 1000, completed: false);
      final counts = await db.playCounts();
      expect(counts[const TrackKey('ytmusic', '1')], 2);
      final artists = await db.artistPlayCounts();
      expect(artists.first.artistNames, 'Artis A');
      expect(artists.first.count, 2);
      await db.close();
    });
  });
}
