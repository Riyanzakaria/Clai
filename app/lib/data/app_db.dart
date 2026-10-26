import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import '../domain/models.dart';
import '../domain/personal_rank.dart';

/// Basis data lokal Clai — skema fisik TECHNICAL-BLUEPRINT Bab 2 (SQLite).
/// ADR-003: sqflite menggantikan drift; aturan migrasi Bab 2.5 tetap berlaku penuh:
/// cadangan pra-migrasi wajib, kegagalan migrasi membuka cadangan, data pengguna tidak boleh hilang.
class AppDb {
  static const dbName = 'clai.db';
  static const schemaVersion = 4;
  Database? _db;
  Future<Database>? _opening;

  /// Sapuan D-12: true bila pembukaan terakhir pulih dari cadangan karena
  /// migrasi gagal — aplikasi tetap mulai (Blueprint 2.5) dan kegagalannya
  /// tercatat, bukan layar gagal senyap.
  bool migrationRecovered = false;
  String? lastMigrationError;

  /// Getter single-flight: SEMUA pemanggil bersamaan berbagi satu proses buka
  /// yang sama. (Sebelumnya assignment `_db` terjadi sesudah `await openDatabase`,
  /// sehingga pemanggil bersamaan sama-sama lolos cek null dan sama-sama membuka —
  /// sqflite bisa terkunci/macet, terutama di frame pertama saat Beranda, Cari,
  /// Koleksi, dan LibraryController meminta DB bersamaan.)
  /// Kegagalan buka membersihkan [_opening] agar percobaan ulang mungkin.
  Future<Database> get db {
    final ready = _db;
    if (ready != null) return Future.value(ready);
    return _opening ??= _openTracked(_openDefault);
  }

  Future<Database> _openTracked(Future<Database> Function() opener) async {
    try {
      final d = await opener();
      _db = d;
      return d;
    } finally {
      _opening = null;
    }
  }

  Future<Database> _openDefault() async {
    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, dbName);
    final d = await _openWithRecovery(path);
    await d.execute('PRAGMA journal_mode=WAL');
    await d.execute('PRAGMA foreign_keys=ON');
    return d;
  }

  /// Dipakai uji (databaseFactory ffi + path memori). Ikut single-flight yang sama.
  Future<Database> openAt(String path) {
    final ready = _db;
    if (ready != null) return Future.value(ready);
    return _opening ??= _openTracked(() => _openWithRecovery(path));
  }

  /// Buka basis data; bila migrasi GAGAL, pulihkan cadangan pra-migrasi
  /// terbaru dan buka pada versi lamanya (Blueprint 2.5, Sapuan D-12) —
  /// sebelumnya kegagalan di onUpgrade tertelan dan aplikasi gagal mulai.
  Future<Database> _openWithRecovery(String path) async {
    try {
      return await openDatabase(
        path,
        version: schemaVersion,
        onCreate: (d, v) async => _createAll(d),
        onUpgrade: _upgrade,
      );
    } catch (e) {
      final restored = await _restoreLatestBackup(path);
      if (restored == null) rethrow;
      migrationRecovered = true;
      lastMigrationError = '$e';
      final d = await openDatabase(path, version: restored);
      try {
        await d.insert('incident_log', {
          'at': DateTime.now().millisecondsSinceEpoch,
          'kind': 'migrasi-gagal-dipulihkan',
          'detail':
              'migrasi ke v$schemaVersion gagal; dibuka dari cadangan v$restored',
        });
      } catch (_) {
        /* basis data versi lama mungkin belum punya tabel insiden */
      }
      return d;
    }
  }

  /// Pulihkan salinan `<path>.bak-v{n}` dengan n terbesar; kembalikan n,
  /// atau null bila tidak ada cadangan yang bisa dipakai.
  Future<int?> _restoreLatestBackup(String path) async {
    try {
      var best = -1;
      for (var v = schemaVersion - 1; v >= 1; v--) {
        if (await File('$path.bak-v$v').exists()) {
          best = v;
          break;
        }
      }
      if (best < 0) return null;
      // Berkas samping sisa dari basis data yang gagal dibuka bisa
      // mengotori cadangan yang baru dipulihkan — buang dulu.
      for (final suffix in ['-wal', '-shm', '-journal']) {
        final side = File('$path$suffix');
        if (await side.exists()) await side.delete();
      }
      await File('$path.bak-v$best').copy(path);
      return best;
    } catch (_) {
      return null;
    }
  }

  /// Menutup basis data dan membersihkan state single-flight.
  /// Aman dipanggil walau belum pernah terbuka atau sudah tertutup;
  /// sesudah ditutup, [db]/[openAt] membuka ulang dari awal.
  /// (Penting di Windows: berkas SQLite yang masih terbuka tidak bisa dihapus.)
  Future<void> close() async {
    final opening = _opening;
    if (opening != null) {
      // Pembukaan sedang berjalan: tunggu selesai agar koneksinya ikut tertutup,
      // tapi kegagalan membuka bukanlah kegagalan menutup.
      try {
        await opening;
      } catch (_) {
        /* kegagalan sudah dicatat pemanggil pembuka */
      }
    }
    final open = _db;
    _db = null;
    if (open != null && open.isOpen) await open.close();
  }

  Future<void> _upgrade(Database d, int oldV, int newV) async {
    // Cadangan pra-migrasi (Bab 2.5): salin berkas DB sebelum skema disentuh.
    try {
      final path = d.path;
      if (path != ':memory:' && await File(path).exists()) {
        await File(path).copy('$path.bak-v$oldV');
      }
    } catch (_) {
      /* cadangan gagal tidak boleh menggagalkan migrasi; insiden dicatat pemanggil */
    }
    if (oldV < 2) {
      // v2 (F2 Batch 1): cache lirik, peta pencocokan antar-provider, cache pengayaan.
      final b = d.batch();
      _createF2Tables(b);
      await b.commit(noResult: true);
    }
    if (oldV < 3) {
      // v3 (F2 Batch 2): gain normalisasi per-lagu (netral 1.0 sampai data terukur).
      final b = d.batch();
      _createF3Tables(b);
      await b.commit(noResult: true);
    }
    if (oldV < 4) {
      // v4 (Sapuan Kepatuhan pra-1.0.0):
      // - D-04: tabel log insiden persisten.
      // - D-10: album_tracks + remote_playlists(+tracks) Blueprint 2.1/2.2.
      // - D-13: saved_items (album/artis tersimpan untuk tab Koleksi).
      // - D-34: queue_snapshots.played_json + volume (riwayat sesi & volume L-16).
      // - D-14: kosakata status unduhan diselaraskan ke Blueprint
      //   (downloading→running, failed→error).
      final b = d.batch();
      _createF4Tables(b);
      b.execute(
        "ALTER TABLE queue_snapshots ADD COLUMN played_json TEXT NOT NULL DEFAULT '[]'",
      );
      b.execute('ALTER TABLE queue_snapshots ADD COLUMN volume REAL');
      b.execute(
        "UPDATE download_items SET status='running' WHERE status='downloading'",
      );
      b.execute(
        "UPDATE download_items SET status='error' WHERE status='failed'",
      );
      await b.commit(noResult: true);
    }
  }

  /// Tabel Sapuan Kepatuhan (v4) — dipakai jalur buat-baru & migrasi v3→v4.
  static void _createF4Tables(Batch b) {
    b.execute('''CREATE TABLE IF NOT EXISTS incident_log (
      id INTEGER PRIMARY KEY AUTOINCREMENT, at INTEGER NOT NULL,
      kind TEXT NOT NULL, detail TEXT NOT NULL)''');
    b.execute(
      'CREATE INDEX IF NOT EXISTS idx_incident_at ON incident_log (at)',
    );
    b.execute('''CREATE TABLE IF NOT EXISTS album_tracks (
      provider_id TEXT NOT NULL, provider_album_id TEXT NOT NULL,
      provider_track_id TEXT NOT NULL, position INTEGER NOT NULL,
      PRIMARY KEY (provider_id, provider_album_id, position))''');
    b.execute('''CREATE TABLE IF NOT EXISTS remote_playlists (
      provider_id TEXT NOT NULL, provider_playlist_id TEXT NOT NULL,
      title TEXT NOT NULL, owner TEXT, artwork_url TEXT, cached_at INTEGER NOT NULL,
      PRIMARY KEY (provider_id, provider_playlist_id))''');
    b.execute('''CREATE TABLE IF NOT EXISTS remote_playlist_tracks (
      provider_id TEXT NOT NULL, provider_playlist_id TEXT NOT NULL,
      provider_track_id TEXT NOT NULL, position INTEGER NOT NULL,
      PRIMARY KEY (provider_id, provider_playlist_id, position))''');
    b.execute('''CREATE TABLE IF NOT EXISTS saved_items (
      kind TEXT NOT NULL, provider_id TEXT NOT NULL, item_id TEXT NOT NULL,
      title TEXT NOT NULL, subtitle TEXT, artwork_url TEXT, saved_at INTEGER NOT NULL,
      PRIMARY KEY (kind, provider_id, item_id))''');
  }

  /// Tabel F2 Batch 2 — dipakai bersama oleh jalur buat-baru (onCreate) dan migrasi v2→v3.
  static void _createF3Tables(Batch b) {
    b.execute('''CREATE TABLE IF NOT EXISTS track_gains (
      provider_id TEXT NOT NULL, provider_track_id TEXT NOT NULL,
      gain REAL NOT NULL, updated_at INTEGER NOT NULL,
      PRIMARY KEY (provider_id, provider_track_id))''');
  }

  /// Tabel F2 Batch 1 — dipakai bersama oleh jalur buat-baru (onCreate) dan migrasi v1→v2.
  static void _createF2Tables(Batch b) {
    b.execute('''CREATE TABLE IF NOT EXISTS lyrics_cache (
      provider_id TEXT NOT NULL, provider_track_id TEXT NOT NULL,
      synced TEXT, plain TEXT, source TEXT NOT NULL, found INTEGER NOT NULL DEFAULT 0,
      fetched_at INTEGER NOT NULL,
      PRIMARY KEY (provider_id, provider_track_id))''');
    b.execute('''CREATE TABLE IF NOT EXISTS provider_matches (
      source_provider TEXT NOT NULL, source_id TEXT NOT NULL,
      target_provider TEXT NOT NULL, target_track_id TEXT,
      status TEXT NOT NULL, checked_at INTEGER NOT NULL,
      PRIMARY KEY (source_provider, source_id))''');
    b.execute('''CREATE TABLE IF NOT EXISTS enrichment_cache (
      kind TEXT NOT NULL, cache_key TEXT NOT NULL, value TEXT,
      fetched_at INTEGER NOT NULL, PRIMARY KEY (kind, cache_key))''');
  }

  Future<void> _createAll(Database d) async {
    final b = d.batch();
    b.execute('''CREATE TABLE tracks (
      provider_id TEXT NOT NULL, provider_track_id TEXT NOT NULL, title TEXT NOT NULL,
      artist_names TEXT NOT NULL, album_id TEXT, duration_ms INTEGER, artwork_url TEXT,
      is_explicit INTEGER NOT NULL DEFAULT 0, playable_ref TEXT NOT NULL, cached_at INTEGER NOT NULL,
      PRIMARY KEY (provider_id, provider_track_id))''');
    b.execute('CREATE INDEX idx_tracks_title ON tracks (title)');
    b.execute(
      'CREATE INDEX idx_tracks_album ON tracks (provider_id, album_id)',
    );
    b.execute('''CREATE TABLE albums (
      provider_id TEXT NOT NULL, provider_album_id TEXT NOT NULL, title TEXT NOT NULL,
      artist_names TEXT NOT NULL, year INTEGER, artwork_url TEXT, cached_at INTEGER NOT NULL,
      PRIMARY KEY (provider_id, provider_album_id))''');
    b.execute('''CREATE TABLE artists (
      provider_id TEXT NOT NULL, provider_artist_id TEXT NOT NULL, name TEXT NOT NULL,
      artwork_url TEXT, cached_at INTEGER NOT NULL,
      PRIMARY KEY (provider_id, provider_artist_id))''');
    b.execute('CREATE INDEX idx_artists_name ON artists (name)');
    b.execute('''CREATE TABLE liked_tracks (
      provider_id TEXT NOT NULL, provider_track_id TEXT NOT NULL, liked_at INTEGER NOT NULL,
      PRIMARY KEY (provider_id, provider_track_id))''');
    b.execute(
      '''CREATE TABLE playlists (
      id TEXT PRIMARY KEY, name TEXT NOT NULL, description TEXT,
      is_system INTEGER NOT NULL DEFAULT 0, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL)''',
    );
    b.execute('''CREATE TABLE playlist_entries (
      playlist_id TEXT NOT NULL REFERENCES playlists(id) ON DELETE CASCADE,
      position INTEGER NOT NULL, provider_id TEXT NOT NULL, provider_track_id TEXT NOT NULL,
      added_at INTEGER NOT NULL, PRIMARY KEY (playlist_id, position))''');
    b.execute(
      'CREATE INDEX idx_entries_track ON playlist_entries (provider_id, provider_track_id)',
    );
    b.execute('''CREATE TABLE playback_events (
      id INTEGER PRIMARY KEY AUTOINCREMENT, provider_id TEXT NOT NULL, provider_track_id TEXT NOT NULL,
      started_at INTEGER NOT NULL, listened_ms INTEGER NOT NULL, completed INTEGER NOT NULL DEFAULT 0,
      context_kind TEXT, context_id TEXT)''');
    b.execute('CREATE INDEX idx_events_time ON playback_events (started_at)');
    b.execute(
      'CREATE INDEX idx_events_track ON playback_events (provider_id, provider_track_id)',
    );
    b.execute('''CREATE TABLE queue_snapshots (
      id INTEGER PRIMARY KEY CHECK (id = 1), context_kind TEXT, context_id TEXT, context_label TEXT,
      seed_json TEXT NOT NULL, manual_json TEXT NOT NULL, continuation_json TEXT NOT NULL,
      autoplay_json TEXT NOT NULL, current_ref TEXT, position_ms INTEGER NOT NULL DEFAULT 0,
      shuffle_mode TEXT NOT NULL DEFAULT 'off', repeat_mode TEXT NOT NULL DEFAULT 'off',
      autoplay_enabled INTEGER NOT NULL DEFAULT 1, session_signals_json TEXT NOT NULL DEFAULT '{}',
      saved_at INTEGER NOT NULL)''');
    b.execute('''CREATE TABLE stream_cache (
      provider_id TEXT NOT NULL, provider_track_id TEXT NOT NULL, resolved_url TEXT NOT NULL,
      mime TEXT, bitrate INTEGER, expires_at INTEGER NOT NULL,
      PRIMARY KEY (provider_id, provider_track_id))''');
    b.execute(
      '''CREATE TABLE user_prefs (key TEXT PRIMARY KEY, value_json TEXT NOT NULL, schema_v INTEGER NOT NULL)''',
    );
    b.execute('''CREATE TABLE search_history (
      query TEXT PRIMARY KEY, searched_at INTEGER NOT NULL)''');
    b.execute('''CREATE TABLE download_items (
      provider_id TEXT NOT NULL, provider_track_id TEXT NOT NULL, status TEXT NOT NULL,
      bytes_total INTEGER, bytes_done INTEGER NOT NULL DEFAULT 0, local_path TEXT, checksum TEXT,
      quality TEXT NOT NULL, PRIMARY KEY (provider_id, provider_track_id))''');
    _createF2Tables(b);
    _createF3Tables(b);
    _createF4Tables(b);
    b.execute(
      "ALTER TABLE queue_snapshots ADD COLUMN played_json TEXT NOT NULL DEFAULT '[]'",
    );
    b.execute('ALTER TABLE queue_snapshots ADD COLUMN volume REAL');
    await b.commit(noResult: true);
  }

  // ---------- katalog cache ----------
  Future<void> cacheTracks(List<Track> tracks) async {
    if (tracks.isEmpty) return;
    final d = await db;
    // Penjaga metadata (Ronde Cacat Metadata): satu trek yang sama tiba dari
    // banyak bentuk sumber — sebagian tidak membawa artis/sampul/durasi.
    // Tulis-ulang TIDAK boleh menghapus nilai yang sudah dikenal dengan
    // nilai kosong dari bentuk lain (dulu: replace polos, sehingga satu
    // stub dari jalur mana pun menimpa rekam yang baik secara permanen).
    // Nilai tak-kosong yang masuk selalu menang; yang kosong mewarisi lama.
    final merged = <Track>[];
    for (final t in tracks) {
      var m = t;
      final old = await trackByKey(t.key);
      if (old != null) {
        if (m.artistNames.trim().isEmpty && old.artistNames.trim().isNotEmpty) {
          m = m.copyWith(
            artistNames: old.artistNames,
            artistIds: m.artistIds.isEmpty ? old.artistIds : m.artistIds,
          );
        }
        if (m.artworkUrl == null && old.artworkUrl != null) {
          m = m.copyWith(artworkUrl: old.artworkUrl);
        }
        if (m.duration == null && old.duration != null) {
          m = m.copyWith(duration: old.duration);
        }
      }
      merged.add(m);
    }
    final b = d.batch();
    for (final t in merged) {
      b.insert(
        'tracks',
        t.toDbRow(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await b.commit(noResult: true);
  }

  Future<Track?> trackByKey(TrackKey k) async {
    final d = await db;
    final rows = await d.query(
      'tracks',
      where: 'provider_id=? AND provider_track_id=?',
      whereArgs: [k.providerId, k.id],
      limit: 1,
    );
    return rows.isEmpty ? null : Track.fromDbRow(rows.first);
  }

  Future<List<Track>> tracksByKeys(List<TrackKey> keys) async {
    final out = <Track>[];
    for (final k in keys) {
      final t = await trackByKey(k);
      if (t != null) out.add(t);
    }
    return out;
  }

  // ---------- suka ----------
  Future<bool> isLiked(TrackKey k) async {
    final d = await db;
    final r = await d.query(
      'liked_tracks',
      where: 'provider_id=? AND provider_track_id=?',
      whereArgs: [k.providerId, k.id],
      limit: 1,
    );
    return r.isNotEmpty;
  }

  Future<void> setLiked(Track t, bool liked) async {
    final d = await db;
    if (liked) {
      await cacheTracks([t]);
      await d.insert('liked_tracks', {
        'provider_id': t.providerId,
        'provider_track_id': t.id,
        'liked_at': DateTime.now().millisecondsSinceEpoch,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    } else {
      await d.delete(
        'liked_tracks',
        where: 'provider_id=? AND provider_track_id=?',
        whereArgs: [t.providerId, t.id],
      );
    }
  }

  Future<List<Track>> likedTracks() async {
    final d = await db;
    final rows = await d.rawQuery('''SELECT t.* FROM liked_tracks l
      JOIN tracks t ON t.provider_id=l.provider_id AND t.provider_track_id=l.provider_track_id
      ORDER BY l.liked_at DESC''');
    return rows.map(Track.fromDbRow).toList();
  }

  Future<Set<TrackKey>> likedKeys() async {
    final d = await db;
    final rows = await d.query('liked_tracks');
    return rows
        .map(
          (r) => TrackKey(
            r['provider_id'] as String,
            r['provider_track_id'] as String,
          ),
        )
        .toSet();
  }

  // ---------- playlist pengguna ----------
  Future<List<Map<String, Object?>>> playlists() async {
    final d = await db;
    return d.query('playlists', orderBy: 'updated_at DESC');
  }

  Future<void> createPlaylist(String id, String name) async {
    final d = await db;
    final now = DateTime.now().millisecondsSinceEpoch;
    await d.insert('playlists', {
      'id': id,
      'name': name,
      'created_at': now,
      'updated_at': now,
    });
  }

  Future<void> renamePlaylist(String id, String name) async {
    final d = await db;
    await d.update(
      'playlists',
      {'name': name, 'updated_at': DateTime.now().millisecondsSinceEpoch},
      where: 'id=?',
      whereArgs: [id],
    );
  }

  Future<void> deletePlaylist(String id) async {
    final d = await db;
    await d.delete('playlist_entries', where: 'playlist_id=?', whereArgs: [id]);
    await d.delete('playlists', where: 'id=?', whereArgs: [id]);
  }

  Future<List<Track>> playlistTracks(String playlistId) async {
    final d = await db;
    final rows = await d.rawQuery(
      '''SELECT t.* FROM playlist_entries e
      JOIN tracks t ON t.provider_id=e.provider_id AND t.provider_track_id=e.provider_track_id
      WHERE e.playlist_id=? ORDER BY e.position ASC''',
      [playlistId],
    );
    return rows.map(Track.fromDbRow).toList();
  }

  Future<int> playlistCount(String playlistId) async {
    final d = await db;
    final r = await d.rawQuery(
      'SELECT COUNT(*) c FROM playlist_entries WHERE playlist_id=?',
      [playlistId],
    );
    return (r.first['c'] as int?) ?? 0;
  }

  Future<bool> playlistContains(String playlistId, TrackKey k) async {
    final d = await db;
    final r = await d.query(
      'playlist_entries',
      where: 'playlist_id=? AND provider_id=? AND provider_track_id=?',
      whereArgs: [playlistId, k.providerId, k.id],
      limit: 1,
    );
    return r.isNotEmpty;
  }

  /// Mengembalikan false bila duplikat dan [allowDuplicate] false (PRD 5.7: diberi pilihan, bukan diam-diam).
  Future<bool> addToPlaylist(
    String playlistId,
    Track t, {
    bool allowDuplicate = false,
  }) async {
    final d = await db;
    if (!allowDuplicate && await playlistContains(playlistId, t.key)) {
      return false;
    }
    await cacheTracks([t]);
    final c = await playlistCount(playlistId);
    await d.insert('playlist_entries', {
      'playlist_id': playlistId,
      'position': c,
      'provider_id': t.providerId,
      'provider_track_id': t.id,
      'added_at': DateTime.now().millisecondsSinceEpoch,
    });
    await d.update(
      'playlists',
      {'updated_at': DateTime.now().millisecondsSinceEpoch},
      where: 'id=?',
      whereArgs: [playlistId],
    );
    return true;
  }

  Future<void> removeFromPlaylistAt(String playlistId, int position) async {
    final d = await db;
    await d.transaction((tx) async {
      await tx.delete(
        'playlist_entries',
        where: 'playlist_id=? AND position=?',
        whereArgs: [playlistId, position],
      );
      final rows = await tx.query(
        'playlist_entries',
        where: 'playlist_id=?',
        whereArgs: [playlistId],
        orderBy: 'position ASC',
      );
      for (var i = 0; i < rows.length; i++) {
        await tx.update(
          'playlist_entries',
          {'position': i},
          where: 'playlist_id=? AND position=?',
          whereArgs: [playlistId, rows[i]['position']],
        );
      }
    });
  }

  Future<void> moveInPlaylist(String playlistId, int from, int to) async {
    final tracks = await playlistTracks(playlistId);
    if (from < 0 || from >= tracks.length || to < 0 || to >= tracks.length) {
      return;
    }
    final item = tracks.removeAt(from);
    tracks.insert(to, item);
    final d = await db;
    await d.transaction((tx) async {
      await tx.delete(
        'playlist_entries',
        where: 'playlist_id=?',
        whereArgs: [playlistId],
      );
      for (var i = 0; i < tracks.length; i++) {
        await tx.insert('playlist_entries', {
          'playlist_id': playlistId,
          'position': i,
          'provider_id': tracks[i].providerId,
          'provider_track_id': tracks[i].id,
          'added_at': DateTime.now().millisecondsSinceEpoch,
        });
      }
    });
  }

  // ---------- riwayat ----------
  Future<void> logPlayback(
    Track t, {
    required int listenedMs,
    required bool completed,
    String? contextKind,
    String? contextId,
  }) async {
    final d = await db;
    await cacheTracks([t]);
    await d.insert('playback_events', {
      'provider_id': t.providerId,
      'provider_track_id': t.id,
      'started_at': DateTime.now().millisecondsSinceEpoch,
      'listened_ms': listenedMs,
      'completed': completed ? 1 : 0,
      'context_kind': contextKind,
      'context_id': contextId,
    });
  }

  Future<List<Track>> recentTracks({int limit = 20}) async {
    final d = await db;
    final rows = await d.rawQuery(
      '''SELECT t.*, MAX(e.started_at) last FROM playback_events e
      JOIN tracks t ON t.provider_id=e.provider_id AND t.provider_track_id=e.provider_track_id
      GROUP BY e.provider_id, e.provider_track_id ORDER BY last DESC LIMIT ?''',
      [limit],
    );
    return rows.map(Track.fromDbRow).toList();
  }

  /// Cap waktu putar per trek dari playback_events (bahan peringkat
  /// campuran F2.5 — lihat domain/personal_rank.dart).
  Future<Map<TrackKey, List<int>>> trackPlayTimestamps() async {
    final d = await db;
    final rows = await d.rawQuery(
      'SELECT provider_id, provider_track_id, started_at FROM playback_events ORDER BY started_at',
    );
    final out = <TrackKey, List<int>>{};
    for (final r in rows) {
      final k = TrackKey(
        r['provider_id'] as String,
        r['provider_track_id'] as String,
      );
      (out[k] ??= []).add((r['started_at'] as int?) ?? 0);
    }
    return out;
  }

  /// Cap waktu putar per NAMA artis (byline trek saat ini) — bahan
  /// peringkat campuran untuk rak artis personal.
  Future<Map<String, List<int>>> artistPlayTimestamps() async {
    final d = await db;
    final rows = await d.rawQuery(
      '''SELECT t.artist_names a, e.started_at s FROM playback_events e
      JOIN tracks t ON t.provider_id=e.provider_id AND t.provider_track_id=e.provider_track_id''',
    );
    final out = <String, List<int>>{};
    for (final r in rows) {
      final a = (r['a'] as String?) ?? '';
      (out[a] ??= []).add((r['s'] as int?) ?? 0);
    }
    return out;
  }

  /// "Putar Lagi": peringkat CAMPURAN (F2.5) — kemutakhiran berpeluruhan
  /// ±30 hari ditopang lantai sepanjang masa; bukan lagi hitungan mentah
  /// sepanjang masa (temuan vonis 2008 #1: rak terasa tidak berubah).
  Future<List<Track>> frequentTracks({int limit = 20}) async {
    final d = await db;
    final rows = await d.rawQuery('''SELECT t.* FROM playback_events e
      JOIN tracks t ON t.provider_id=e.provider_id AND t.provider_track_id=e.provider_track_id
      GROUP BY e.provider_id, e.provider_track_id''');
    final tracks = rows.map(Track.fromDbRow).toList();
    final plays = await trackPlayTimestamps();
    final now = DateTime.now().millisecondsSinceEpoch;
    final scores = hybridTrackScores(plays, now);
    tracks.sort((a, b) {
      final pa = plays[a.key] ?? const <int>[];
      final pb = plays[b.key] ?? const <int>[];
      return compareHybridRank(
        scoreA: scores[a.key] ?? 0,
        countA: pa.length,
        lastPlayedA: pa.isEmpty ? 0 : pa.last,
        scoreB: scores[b.key] ?? 0,
        countB: pb.length,
        lastPlayedB: pb.isEmpty ? 0 : pb.last,
      );
    });
    return tracks.take(limit).toList();
  }

  Future<void> clearHistory() async {
    final d = await db;
    await d.delete('playback_events');
  }

  // ---------- statistik personal (F2 Batch 2: rak Beranda) ----------
  /// Hitungan putar per trek (bahan dorongan Smart Shuffle & rak personal).
  Future<Map<TrackKey, int>> playCounts() async {
    final d = await db;
    final rows = await d.rawQuery(
      'SELECT provider_id, provider_track_id, COUNT(*) c FROM playback_events GROUP BY provider_id, provider_track_id',
    );
    return {
      for (final r in rows)
        TrackKey(r['provider_id'] as String, r['provider_track_id'] as String):
            (r['c'] as int?) ?? 0,
    };
  }

  /// Artis teratas menurut peringkat CAMPURAN (F2.5): urutan kini mengikuti
  /// skor kemutakhiran berlantai sepanjang masa; [count] yang dikembalikan
  /// tetap hitungan putar sepanjang masa (ambang tampil rak ≥3 memakai itu).
  Future<List<({String artistNames, int count})>> artistPlayCounts({
    int limit = 5,
  }) async {
    final byArtist = await artistPlayTimestamps();
    final now = DateTime.now().millisecondsSinceEpoch;
    final out = <({String artistNames, int count, double score, int last})>[
      for (final e in byArtist.entries)
        (
          artistNames: e.key,
          count: e.value.length,
          score: hybridPlayScore(e.value, now),
          last: e.value.isEmpty ? 0 : e.value.reduce((a, b) => a > b ? a : b),
        ),
    ];
    out.sort(
      (a, b) => compareHybridRank(
        scoreA: a.score,
        countA: a.count,
        lastPlayedA: a.last,
        scoreB: b.score,
        countB: b.count,
        lastPlayedB: b.last,
      ),
    );
    return out
        .take(limit)
        .map((e) => (artistNames: e.artistNames, count: e.count))
        .toList();
  }

  /// Trek dari katalog cache yang byline-nya cocok salah satu artis (pencocokan
  /// substring dua arah pada nama utama — katalog cache hanya berisi trek yang
  /// pernah dilihat/diputar, jadi ini rak "dari yang sudah dikenal", bukan rekomendasi luar).
  Future<List<Track>> tracksByArtists(
    List<String> artists, {
    int limit = 30,
  }) async {
    if (artists.isEmpty) return const [];
    final d = await db;
    // Perbaikan F2.5 (cacat laten): dulu fungsi ini memindai 500 baris
    // trek pertama TANPA urutan lalu menyaring di Dart — begitu pustaka
    // cache melewati 500 trek, trek artis yang dicari bisa berada di
    // luar jendela itu dan rak artis Beranda kosong diam-diam (terbukti
    // di emulator: 1.437 trek, rak tak pernah tampil di 2014 maupun
    // 2015). Kini kandidat dipersempit dulu per artis lewat LIKE
    // (superhimpunan saringan primer di bawah untuk nama ASCII), lalu
    // saringan primer yang sama persis diterapkan pada kandidat itu.
    final candidates = <Track>[];
    final seenRows = <TrackKey>{};
    for (final a in artists) {
      final needle = a.trim();
      if (needle.isEmpty) continue;
      final found = await d.query(
        'tracks',
        where: 'artist_names like ?',
        whereArgs: ['%$needle%'],
      );
      for (final r in found) {
        final t = Track.fromDbRow(r);
        if (seenRows.add(t.key)) candidates.add(t);
      }
    }
    final out = <Track>[];
    for (final t in candidates) {
      final primary = t.artistNames
          .split(RegExp(r'[,&]'))
          .first
          .trim()
          .toLowerCase();
      if (artists.any(
        (a) =>
            primary.contains(a.toLowerCase()) ||
            a.toLowerCase().contains(primary),
      )) {
        out.add(t);
      }
    }
    // F2.5: urutan di dalam rak mengikuti peringkat campuran (yang sedang
    // hidup & mapan di atas; trek artis yang belum pernah diputar menyusul
    // di ekor dengan urutan temuan semula). Batas [limit] diterapkan
    // SESUDAH pengurutan agar yang tampil benar-benar peringkat teratas.
    final plays = await trackPlayTimestamps();
    final now = DateTime.now().millisecondsSinceEpoch;
    final scores = hybridTrackScores(plays, now);
    final indexed = <(int, Track)>[
      for (var i = 0; i < out.length; i++) (i, out[i]),
    ];
    indexed.sort((x, y) {
      final a = x.$2, b = y.$2;
      final pa = plays[a.key] ?? const <int>[];
      final pb = plays[b.key] ?? const <int>[];
      final c = compareHybridRank(
        scoreA: scores[a.key] ?? 0,
        countA: pa.length,
        lastPlayedA: pa.isEmpty ? 0 : pa.last,
        scoreB: scores[b.key] ?? 0,
        countB: pb.length,
        lastPlayedB: pb.isEmpty ? 0 : pb.last,
      );
      return c != 0 ? c : x.$1.compareTo(y.$1);
    });
    return [for (final e in indexed.take(limit)) e.$2];
  }

  /// Lagu tersimpan beserta hitungan putarnya (rak "tersimpan tapi jarang diputar").
  Future<List<({Track track, int plays})>> likedWithPlayCounts() async {
    final d = await db;
    final rows = await d.rawQuery(
      '''SELECT t.*, COUNT(e.id) c FROM liked_tracks l
      JOIN tracks t ON t.provider_id=l.provider_id AND t.provider_track_id=l.provider_track_id
      LEFT JOIN playback_events e ON e.provider_id=t.provider_id AND e.provider_track_id=t.provider_track_id
      GROUP BY t.provider_id, t.provider_track_id ORDER BY l.liked_at DESC''',
    );
    return rows
        .map((r) => (track: Track.fromDbRow(r), plays: (r['c'] as int?) ?? 0))
        .toList();
  }

  // ---------- unduhan (F2 Batch 2) ----------
  Future<List<Map<String, Object?>>> downloadItems() async {
    final d = await db;
    return d.query('download_items', orderBy: 'rowid DESC');
  }

  Future<Map<String, Object?>?> downloadItem(TrackKey k) async {
    final d = await db;
    final rows = await d.query(
      'download_items',
      where: 'provider_id=? AND provider_track_id=?',
      whereArgs: [k.providerId, k.id],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<void> saveDownloadItem(
    TrackKey k, {
    required String status,
    int? bytesTotal,
    required int bytesDone,
    String? localPath,
    String? checksum,
    required String quality,
  }) async {
    final d = await db;
    await d.insert('download_items', {
      'provider_id': k.providerId,
      'provider_track_id': k.id,
      'status': status,
      'bytes_total': bytesTotal,
      'bytes_done': bytesDone,
      'local_path': localPath,
      'checksum': checksum,
      'quality': quality,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteDownloadItem(TrackKey k) async {
    final d = await db;
    await d.delete(
      'download_items',
      where: 'provider_id=? AND provider_track_id=?',
      whereArgs: [k.providerId, k.id],
    );
  }

  // ---------- gain normalisasi (F2 Batch 2) ----------
  /// Gain linear per trek (1.0 = netral). Null bila belum pernah dicatat.
  Future<double?> trackGain(TrackKey k) async {
    final d = await db;
    final rows = await d.query(
      'track_gains',
      where: 'provider_id=? AND provider_track_id=?',
      whereArgs: [k.providerId, k.id],
      limit: 1,
    );
    return rows.isEmpty ? null : (rows.first['gain'] as num?)?.toDouble();
  }

  Future<void> setTrackGain(TrackKey k, double gain) async {
    final d = await db;
    await d.insert('track_gains', {
      'provider_id': k.providerId,
      'provider_track_id': k.id,
      'gain': gain.clamp(0.25, 4.0),
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // ---------- riwayat pencarian ----------
  Future<void> addSearchHistory(String q) async {
    final d = await db;
    await d.insert('search_history', {
      'query': q,
      'searched_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<String>> searchHistory() async {
    final d = await db;
    final rows = await d.query(
      'search_history',
      orderBy: 'searched_at DESC',
      limit: 15,
    );
    return rows.map((r) => r['query'] as String).toList();
  }

  Future<void> removeSearchHistory(String q) async {
    final d = await db;
    await d.delete('search_history', where: 'query=?', whereArgs: [q]);
  }

  Future<void> clearSearchHistory() async {
    final d = await db;
    await d.delete('search_history');
  }

  // ---------- snapshot antrean (L-16) ----------
  Future<void> saveQueueSnapshot(Map<String, Object?> snapshot) async {
    final d = await db;
    await d.insert('queue_snapshots', {
      'id': 1,
      'context_kind': snapshot['contextKind'],
      'context_id': snapshot['contextId'],
      'context_label': snapshot['contextLabel'],
      'seed_json': jsonEncode(snapshot['seeds']),
      'manual_json': jsonEncode(snapshot['manual']),
      'continuation_json': jsonEncode(snapshot['continuation']),
      'autoplay_json': jsonEncode(snapshot['autoplay']),
      'current_ref': snapshot['currentRef'],
      'position_ms': snapshot['positionMs'] ?? 0,
      'shuffle_mode': snapshot['shuffle'] ?? 'off',
      'repeat_mode': snapshot['repeat'] ?? 'off',
      'autoplay_enabled': ((snapshot['autoplayEnabled'] as bool?) ?? true)
          ? 1
          : 0,
      'session_signals_json': jsonEncode(snapshot['signals'] ?? {}),
      // D-34: riwayat sesi (played) & volume kini benar-benar disimpan —
      // sebelumnya saveQueueSnapshot membuang 'played' senyap karena kolomnya
      // tidak ada (Blueprint kini diamendemen terbuka mencatat kolom ini).
      'played_json': jsonEncode(snapshot['played'] ?? []),
      'volume': snapshot['volume'],
      'saved_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Map<String, Object?>?> loadQueueSnapshot() async {
    final d = await db;
    final rows = await d.query('queue_snapshots', where: 'id=1', limit: 1);
    if (rows.isEmpty) return null;
    final r = rows.first;
    return {
      'contextKind': r['context_kind'],
      'contextId': r['context_id'],
      'contextLabel': r['context_label'],
      'seeds': jsonDecode(r['seed_json'] as String),
      'manual': jsonDecode(r['manual_json'] as String),
      'continuation': jsonDecode(r['continuation_json'] as String),
      'autoplay': jsonDecode(r['autoplay_json'] as String),
      'currentRef': r['current_ref'],
      'positionMs': r['position_ms'],
      'shuffle': r['shuffle_mode'],
      'repeat': r['repeat_mode'],
      'autoplayEnabled': (r['autoplay_enabled'] as int) == 1,
      'signals': jsonDecode(r['session_signals_json'] as String),
      'played': (r['played_json'] is String)
          ? jsonDecode(r['played_json'] as String)
          : const [],
      'volume': (r['volume'] as num?)?.toDouble(),
    };
  }

  // ---------- cache aliran ----------
  Future<StreamInfo?> cachedStream(TrackKey k) async {
    final d = await db;
    final rows = await d.query(
      'stream_cache',
      where: 'provider_id=? AND provider_track_id=?',
      whereArgs: [k.providerId, k.id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final r = rows.first;
    final exp = DateTime.fromMillisecondsSinceEpoch(r['expires_at'] as int);
    if (exp.isBefore(DateTime.now())) return null;
    return StreamInfo(
      url: r['resolved_url'] as String,
      mimeType: (r['mime'] as String?) ?? 'audio/mp4',
      bitrate: r['bitrate'] as int?,
      expiresAt: exp,
    );
  }

  Future<void> cacheStream(TrackKey k, StreamInfo s) async {
    final d = await db;
    await d.insert('stream_cache', {
      'provider_id': k.providerId,
      'provider_track_id': k.id,
      'resolved_url': s.url,
      'mime': s.mimeType,
      'bitrate': s.bitrate,
      'expires_at': s.expiresAt.millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> clearStreamCache() async {
    final d = await db;
    await d.delete('stream_cache');
  }

  /// Buang entri cache SATU trek (refresh proaktif D-08 & pemulihan L-10
  /// per-trek tidak perlu mengorbankan cache trek lain).
  Future<void> clearStreamCacheFor(TrackKey k) async {
    final d = await db;
    await d.delete(
      'stream_cache',
      where: 'provider_id=? AND provider_track_id=?',
      whereArgs: [k.providerId, k.id],
    );
  }

  // ---------- preferensi ----------
  Future<T?> pref<T>(String key) async {
    final d = await db;
    final rows = await d.query(
      'user_prefs',
      where: 'key=?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return jsonDecode(rows.first['value_json'] as String) as T;
  }

  Future<void> setPref(String key, Object? value) async {
    final d = await db;
    await d.insert('user_prefs', {
      'key': key,
      'value_json': jsonEncode(value),
      'schema_v': 1,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // ---------- cache lirik (F2) ----------
  Future<Map<String, Object?>?> lyricsCache(TrackKey k) async {
    final d = await db;
    final rows = await d.query(
      'lyrics_cache',
      where: 'provider_id=? AND provider_track_id=?',
      whereArgs: [k.providerId, k.id],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<void> saveLyricsCache(
    TrackKey k, {
    String? synced,
    String? plain,
    required String source,
    required bool found,
  }) async {
    final d = await db;
    await d.insert('lyrics_cache', {
      'provider_id': k.providerId,
      'provider_track_id': k.id,
      'synced': synced,
      'plain': plain,
      'source': source,
      'found': found ? 1 : 0,
      'fetched_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // ---------- peta pencocokan antar-provider (F2: Spotify → YouTube Music) ----------
  /// status: 'matched' (targetTrackId terisi) | 'unmatched'.
  Future<({String status, String? targetTrackId, int checkedAt})?>
  providerMatch(String sourceProvider, String sourceId) async {
    final d = await db;
    final rows = await d.query(
      'provider_matches',
      where: 'source_provider=? AND source_id=?',
      whereArgs: [sourceProvider, sourceId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final r = rows.first;
    return (
      status: r['status'] as String,
      targetTrackId: r['target_track_id'] as String?,
      checkedAt: r['checked_at'] as int,
    );
  }

  Future<void> saveProviderMatch(
    String sourceProvider,
    String sourceId,
    String targetProvider, {
    String? targetTrackId,
    required String status,
  }) async {
    final d = await db;
    await d.insert('provider_matches', {
      'source_provider': sourceProvider,
      'source_id': sourceId,
      'target_provider': targetProvider,
      'target_track_id': targetTrackId,
      'status': status,
      'checked_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // ---------- cache pengayaan (F2: mis. sampul MusicBrainz/CAA) ----------
  /// value null pada baris yang ada = hasil negatif tercache (sudah dicari, tidak ada).
  Future<({bool exists, String? value, int fetchedAt})> enrichment(
    String kind,
    String key,
  ) async {
    final d = await db;
    final rows = await d.query(
      'enrichment_cache',
      where: 'kind=? AND cache_key=?',
      whereArgs: [kind, key],
      limit: 1,
    );
    if (rows.isEmpty) return (exists: false, value: null, fetchedAt: 0);
    return (
      exists: true,
      value: rows.first['value'] as String?,
      fetchedAt: rows.first['fetched_at'] as int,
    );
  }

  Future<void> saveEnrichment(String kind, String key, String? value) async {
    final d = await db;
    await d.insert('enrichment_cache', {
      'kind': kind,
      'cache_key': key,
      'value': value,
      'fetched_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // ---------- log insiden persisten (Sapuan D-04) ----------
  Future<void> insertIncident(String kind, String detail, {int? at}) async {
    final d = await db;
    await d.insert('incident_log', {
      'at': at ?? DateTime.now().millisecondsSinceEpoch,
      'kind': kind,
      'detail': detail,
    });
  }

  Future<List<({int at, String kind, String detail})>> incidents({
    int limit = 200,
  }) async {
    final d = await db;
    final rows = await d.query(
      'incident_log',
      orderBy: 'at DESC, id DESC',
      limit: limit,
    );
    return rows
        .map(
          (r) => (
            at: r['at'] as int,
            kind: r['kind'] as String,
            detail: r['detail'] as String,
          ),
        )
        .toList();
  }

  /// Retensi log insiden: simpan [keep] entri terbaru saja.
  Future<void> pruneIncidents({int keep = 500}) async {
    final d = await db;
    await d.rawDelete(
      'DELETE FROM incident_log WHERE id NOT IN (SELECT id FROM incident_log ORDER BY at DESC, id DESC LIMIT ?)',
      [keep],
    );
  }

  // ---------- retensi (Blueprint 2.4, Sapuan D-11) ----------
  /// Satu lintasan retensi:
  /// - stream_cache: buang yang kedaluwarsa; batasi 200 baris (yang paling
  ///   cepat kedaluwarsa dibuang lebih dulu).
  /// - playback_events: buang yang lebih tua dari [historyDays]
  ///   (historyDays < 0 = simpan selamanya, pilihan pengguna).
  /// - katalog tracks: LRU 90 hari — trek yang tidak disukai, tidak ada di
  ///   playlist mana pun, tidak diunduh, dan tidak diputar/di-cache dalam
  ///   90 hari dibuang (beserta baris album_tracks/remote_playlist_tracks).
  Future<void> pruneRetention({required int historyDays, DateTime? now}) async {
    final d = await db;
    final t = now ?? DateTime.now();
    final nowMs = t.millisecondsSinceEpoch;
    await d.delete('stream_cache', where: 'expires_at < ?', whereArgs: [nowMs]);
    await d.rawDelete('''DELETE FROM stream_cache WHERE rowid NOT IN
      (SELECT rowid FROM stream_cache ORDER BY expires_at DESC LIMIT 200)''');
    if (historyDays >= 0) {
      final cutoff = nowMs - historyDays * 86400000;
      await d.delete(
        'playback_events',
        where: 'started_at < ?',
        whereArgs: [cutoff],
      );
    }
    final lruCutoff = nowMs - 90 * 86400000;
    final orphan = '''provider_id IN (SELECT provider_id FROM tracks) AND
      NOT EXISTS (SELECT 1 FROM liked_tracks l WHERE l.provider_id=tracks.provider_id AND l.provider_track_id=tracks.provider_track_id) AND
      NOT EXISTS (SELECT 1 FROM playlist_entries e WHERE e.provider_id=tracks.provider_id AND e.provider_track_id=tracks.provider_track_id) AND
      NOT EXISTS (SELECT 1 FROM download_items di WHERE di.provider_id=tracks.provider_id AND di.provider_track_id=tracks.provider_track_id AND di.status='done') AND
      NOT EXISTS (SELECT 1 FROM playback_events pe WHERE pe.provider_id=tracks.provider_id AND pe.provider_track_id=tracks.provider_track_id AND pe.started_at >= $lruCutoff)''';
    await d.rawDelete(
      '''DELETE FROM album_tracks WHERE EXISTS
      (SELECT 1 FROM tracks WHERE tracks.provider_id=album_tracks.provider_id AND tracks.provider_track_id=album_tracks.provider_track_id AND tracks.cached_at < $lruCutoff AND $orphan)''',
    );
    await d.rawDelete(
      '''DELETE FROM remote_playlist_tracks WHERE EXISTS
      (SELECT 1 FROM tracks WHERE tracks.provider_id=remote_playlist_tracks.provider_id AND tracks.provider_track_id=remote_playlist_tracks.provider_track_id AND tracks.cached_at < $lruCutoff AND $orphan)''',
    );
    await d.rawDelete(
      'DELETE FROM tracks WHERE cached_at < $lruCutoff AND $orphan',
    );
  }

  // ---------- item tersimpan: album & artis (Sapuan D-13) ----------
  Future<bool> isSavedItem(
    String kind,
    String providerId,
    String itemId,
  ) async {
    final d = await db;
    final rows = await d.query(
      'saved_items',
      where: 'kind=? AND provider_id=? AND item_id=?',
      whereArgs: [kind, providerId, itemId],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<void> setSavedItem(
    String kind,
    String providerId,
    String itemId,
    bool saved, {
    String title = '',
    String? subtitle,
    String? artworkUrl,
  }) async {
    final d = await db;
    if (saved) {
      await d.insert('saved_items', {
        'kind': kind,
        'provider_id': providerId,
        'item_id': itemId,
        'title': title,
        'subtitle': subtitle,
        'artwork_url': artworkUrl,
        'saved_at': DateTime.now().millisecondsSinceEpoch,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    } else {
      await d.delete(
        'saved_items',
        where: 'kind=? AND provider_id=? AND item_id=?',
        whereArgs: [kind, providerId, itemId],
      );
    }
  }

  Future<List<Map<String, Object?>>> savedItems(String kind) async {
    final d = await db;
    return d.query(
      'saved_items',
      where: 'kind=?',
      whereArgs: [kind],
      orderBy: 'saved_at DESC',
    );
  }

  // ---------- cache halaman browse (Blueprint 2.1/2.2, Sapuan D-10) ----------
  /// Tulis relasi halaman → trek setiap kali halaman album/playlist berhasil
  /// diambil dari sumber; dipakai sebagai cadangan offline halaman konten.
  Future<void> cacheBrowsePage(String kind, ContentPage page) async {
    final d = await db;
    final now = DateTime.now().millisecondsSinceEpoch;
    await cacheTracks(page.tracks);
    if (kind == 'album') {
      await d.transaction((tx) async {
        // Metadata album ikut disimpan: browseCachePage membaca judul dari
        // tabel albums — tanpa baris ini halaman offline berjudul kosong.
        await tx.insert('albums', {
          'provider_id': page.tracks.isEmpty
              ? 'ytmusic'
              : page.tracks.first.providerId,
          'provider_album_id': page.id,
          'title': page.title,
          'artist_names': page.subtitle ?? '',
          'artwork_url': page.artworkUrl,
          'cached_at': now,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
        await tx.delete(
          'album_tracks',
          where: 'provider_album_id=?',
          whereArgs: [page.id],
        );
        for (var i = 0; i < page.tracks.length; i++) {
          await tx.insert('album_tracks', {
            'provider_id': page.tracks[i].providerId,
            'provider_album_id': page.id,
            'provider_track_id': page.tracks[i].id,
            'position': i,
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      });
    } else if (kind == 'playlist') {
      await d.transaction((tx) async {
        await tx.insert('remote_playlists', {
          'provider_id': 'ytmusic',
          'provider_playlist_id': page.id,
          'title': page.title,
          'owner': page.subtitle,
          'artwork_url': page.artworkUrl,
          'cached_at': now,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
        await tx.delete(
          'remote_playlist_tracks',
          where: 'provider_id=? AND provider_playlist_id=?',
          whereArgs: ['ytmusic', page.id],
        );
        for (var i = 0; i < page.tracks.length; i++) {
          await tx.insert('remote_playlist_tracks', {
            'provider_id': page.tracks[i].providerId,
            'provider_playlist_id': page.id,
            'provider_track_id': page.tracks[i].id,
            'position': i,
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      });
    }
  }

  /// Halaman konten dari cache lokal (cadangan saat sumber tak terjangkau).
  /// Null bila halaman ini belum pernah tercache.
  Future<ContentPage?> browseCachePage(String kind, String id) async {
    final d = await db;
    if (kind == 'album') {
      final rows = await d.rawQuery(
        '''SELECT t.* FROM album_tracks a
        JOIN tracks t ON t.provider_id=a.provider_id AND t.provider_track_id=a.provider_track_id
        WHERE a.provider_album_id=? ORDER BY a.position ASC''',
        [id],
      );
      if (rows.isEmpty) return null;
      final tracks = rows.map(Track.fromDbRow).toList();
      final albums = await d.query(
        'albums',
        where: 'provider_album_id=?',
        whereArgs: [id],
        limit: 1,
      );
      return ContentPage(
        kind: 'album',
        id: id,
        title: albums.isEmpty
            ? (tracks.first.albumTitle ?? '')
            : albums.first['title'] as String,
        subtitle: albums.isEmpty
            ? tracks.first.artistNames
            : albums.first['artist_names'] as String,
        artworkUrl: albums.isEmpty
            ? tracks.first.artworkUrl
            : albums.first['artwork_url'] as String?,
        tracks: tracks,
      );
    }
    if (kind == 'playlist') {
      final meta = await d.query(
        'remote_playlists',
        where: 'provider_playlist_id=?',
        whereArgs: [id],
        limit: 1,
      );
      if (meta.isEmpty) return null;
      final rows = await d.rawQuery(
        '''SELECT t.* FROM remote_playlist_tracks r
        JOIN tracks t ON t.provider_id=r.provider_id AND t.provider_track_id=r.provider_track_id
        WHERE r.provider_playlist_id=? ORDER BY r.position ASC''',
        [id],
      );
      return ContentPage(
        kind: 'playlist',
        id: id,
        title: meta.first['title'] as String,
        subtitle: meta.first['owner'] as String?,
        artworkUrl: meta.first['artwork_url'] as String?,
        tracks: rows.map(Track.fromDbRow).toList(),
      );
    }
    return null;
  }

  /// Sisa masa berlaku entri stream_cache (untuk refresh proaktif D-08):
  /// null bila tidak ada entri; nilai negatif berarti sudah kedaluwarsa.
  Future<Duration?> streamCacheRemaining(TrackKey k) async {
    final d = await db;
    final rows = await d.query(
      'stream_cache',
      where: 'provider_id=? AND provider_track_id=?',
      whereArgs: [k.providerId, k.id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final exp = rows.first['expires_at'] as int;
    return Duration(milliseconds: exp - DateTime.now().millisecondsSinceEpoch);
  }
}
