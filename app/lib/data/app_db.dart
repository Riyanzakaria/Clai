import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../domain/models.dart';
import '../domain/personal_rank.dart';
import '../domain/taste_mirror.dart';
import '../domain/transfer_data.dart';
import '../services/waveform.dart';

/// Basis data lokal Clai — skema fisik TECHNICAL-BLUEPRINT Bab 2 (SQLite).
/// ADR-003: sqflite menggantikan drift; aturan migrasi Bab 2.5 tetap berlaku penuh:
/// cadangan pra-migrasi wajib, kegagalan migrasi membuka cadangan, data pengguna tidak boleh hilang.
class AppDb {
  static const dbName = 'clai.db';
  static const schemaVersion = 9;
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
    if (oldV < 5) {
      // v5 (Ronde Player B): waveform ukur per trek — ember energi hasil
      // pengukuran RMS nyata saat pemutaran (bukan data karangan).
      final b = d.batch();
      _createF5Tables(b);
      await b.commit(noResult: true);
    }
    if (oldV < 6) {
      // v6 (Ronde 8072, Brankas Sesi): arsip sesi putar permanen —
      // snapshot antrean penuh per sesi bernama (Workstream D, 2.1.0).
      final b = d.batch();
      _createF6Tables(b);
      await b.commit(noResult: true);
    }
    if (oldV < 7) {
      // v7 (Ronde 8074, Ruang Kendali Selera): pengecualian rekomendasi
      // per artis/lagu — diterapkan sebagai saringan baca di atas
      // playback_events (retroaktif, dapat diurungkan).
      final b = d.batch();
      _createF7Tables(b);
      await b.commit(noResult: true);
    }
    if (oldV < 8) {
      // v8 (Ronde 8075, Panel Acak Gabungan): potret urutan alami +
      // himpunan terputar siklus Jujur ikut disimpan di snapshot
      // antrean L-16. Tanpa kolom ini saveQueueSnapshot MEMBUANG
      // keduanya: sesudah start dingin, mematikan Acak mode Jujur
      // menjadi no-op senyap (potret hilang) dan progres siklus
      // dihitung ulang dari nol — penyakit 8066 yang kambuh lewat
      // jalur kolom-tetap. (Jalur Brankas menyimpan JSON penuh,
      // tidak terkena.) Penjaga keberadaan tabel: basis data nyata
      // selalu punya queue_snapshots (lahir di onCreate v1), tetapi
      // migrasi tidak boleh meledak pada basis data parsial.
      final tables = await d.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='queue_snapshots'",
      );
      if (tables.isNotEmpty) {
        final b = d.batch();
        b.execute(
          'ALTER TABLE queue_snapshots ADD COLUMN natural_continuation_json TEXT',
        );
        b.execute(
          'ALTER TABLE queue_snapshots ADD COLUMN natural_autoplay_json TEXT',
        );
        b.execute(
          'ALTER TABLE queue_snapshots ADD COLUMN cycle_played_json TEXT',
        );
        await b.commit(noResult: true);
      }
    }
    if (oldV < 9) {
      // v9 (Ronde 8092, Paket Artis): kolom artist_ids di tracks (TEXT,
      // JSON array string) — pengenal artis trek kini persisten. Sebelumnya
      // Track.toDbRow membuangnya, sehingga semua trek bersumber DB
      // (riwayat, rak personal, koleksi) selalu lahir dengan artistIds=[]
      // dan buka-artis dari Player jatuh ke resolusi nama yang rapuh.
      // Migrasi murni aditif: baris lama utuh, artist_ids-nya NULL dan
      // dibaca fromDbRow sebagai daftar kosong. Penjaga keberadaan tabel
      // sama seperti v8: migrasi tidak boleh meledak pada basis data parsial.
      final tables = await d.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='tracks'",
      );
      if (tables.isNotEmpty) {
        await d.execute('ALTER TABLE tracks ADD COLUMN artist_ids TEXT');
      }
    }
  }

  /// Tabel Ruang Kendali Selera (v7) — dipakai jalur buat-baru & migrasi v6→v7.
  static void _createF7Tables(Batch b) {
    b.execute('''CREATE TABLE IF NOT EXISTS taste_exclusions (
      kind TEXT NOT NULL, key TEXT NOT NULL, label TEXT NOT NULL,
      created_at INTEGER NOT NULL, PRIMARY KEY (kind, key))''');
  }

  /// Tabel Brankas Sesi (v6) — dipakai jalur buat-baru & migrasi v5→v6.
  /// snapshot_json = peta snapshot QueueEngine persis seperti yang
  /// disimpan jalur Lanjut Besok (D-15); kolom lain adalah denormalisasi
  /// tampilan (daftar & rak Beranda membaca tanpa mendekode snapshot).
  static void _createF6Tables(Batch b) {
    b.execute('''CREATE TABLE IF NOT EXISTS saved_sessions (
      id TEXT PRIMARY KEY, name TEXT NOT NULL, saved_at INTEGER NOT NULL,
      snapshot_json TEXT NOT NULL, track_count INTEGER NOT NULL DEFAULT 0,
      current_title TEXT, current_artist TEXT, current_artwork TEXT,
      context_label TEXT, position_ms INTEGER NOT NULL DEFAULT 0)''');
    b.execute(
      'CREATE INDEX IF NOT EXISTS idx_saved_sessions_at ON saved_sessions (saved_at DESC)',
    );
  }

  /// Tabel Ronde Player B (v5) — dipakai jalur buat-baru & migrasi v4→v5.
  static void _createF5Tables(Batch b) {
    b.execute('''CREATE TABLE IF NOT EXISTS track_waveforms (
      provider_id TEXT NOT NULL, provider_track_id TEXT NOT NULL,
      buckets TEXT NOT NULL, updated_at INTEGER NOT NULL,
      PRIMARY KEY (provider_id, provider_track_id))''');
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
      artist_names TEXT NOT NULL, album_id TEXT, artist_ids TEXT, duration_ms INTEGER, artwork_url TEXT,
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
      natural_continuation_json TEXT, natural_autoplay_json TEXT, cycle_played_json TEXT,
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
    _createF5Tables(b);
    _createF6Tables(b);
    _createF7Tables(b);
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
          m = m.copyWith(artistNames: old.artistNames);
        }
        // Ronde 8092: pewarisan artistIds berdiri sendiri (dulu menumpang
        // cabang nama kosong di atas, sehingga trek masuk bernama lengkap
        // tetapi tanpa id tetap menghapus id tersimpan). Kini: id masuk
        // kosong mewarisi id lama yang terisi; id masuk terisi memperbarui.
        if (m.artistIds.isEmpty && old.artistIds.isNotEmpty) {
          m = m.copyWith(artistIds: old.artistIds);
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

  /// Putar terakhir per playlist pengguna (Ronde Koreksi Komposisi F3,
  /// meta baris Koleksi papan 05): MAX(started_at) peristiwa putar atas
  /// trek-trek playlist itu, epoch milidetik. Playlist yang belum pernah
  /// diputar tidak muncul di peta — meta-nya tanpa klaim waktu.
  Future<Map<String, int>> playlistLastPlayed() async {
    final d = await db;
    final rows = await d.rawQuery(
      '''SELECT e.playlist_id AS pid, MAX(ev.started_at) AS last_ms
      FROM playlist_entries e
      JOIN playback_events ev
        ON ev.provider_id = e.provider_id
        AND ev.provider_track_id = e.provider_track_id
      GROUP BY e.playlist_id''',
    );
    return {
      for (final r in rows)
        if (r['pid'] != null && r['last_ms'] != null)
          r['pid'] as String: (r['last_ms'] as num).toInt(),
    };
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

  /// Sampul per artis untuk Selera Cermin Panggung (Ronde 8089):
  /// artwork trek PALING SERING DIPUTAR milik tiap artis (seri diputus
  /// putar terakhir terbaru). Baris dikembalikan urut peringkat trek
  /// global; pemenang per artis dipilih di sini: artwork NON-NULL
  /// pertama dalam urutan itu — trek pemenang tanpa artwork memberi
  /// jalan ke trek berikutnya milik artis yang sama. Artis tanpa
  /// artwork apa pun → null (UI menggambar ubin motif).
  Future<Map<String, String?>> topTrackArtworkByArtist() async {
    final d = await db;
    final rows = await d.rawQuery(
      '''SELECT t.artist_names a, t.artwork_url art, COUNT(*) c, MAX(e.started_at) last FROM playback_events e JOIN tracks t ON t.provider_id=e.provider_id AND t.provider_track_id=e.provider_track_id GROUP BY e.provider_id, e.provider_track_id ORDER BY c DESC, last DESC''',
    );
    final out = <String, String?>{};
    for (final r in rows) {
      final a = (r['a'] as String?) ?? '';
      final art = r['art'] as String?;
      if (!out.containsKey(a)) {
        out[a] = art;
      } else if (out[a] == null && art != null) {
        out[a] = art;
      }
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
    // Ronde 8074: pengecualian selera menyaring rak rekomendasi ini
    // (retroaktif — peristiwa lama ikut tersaring karena saringan baca),
    // dan peringkat memakai bobot selera pengguna (bawaan = campuran
    // F2.5 persis).
    final excl = await tasteExclusions();
    final tracks = rows
        .map(Track.fromDbRow)
        .where((t) => !isTrackExcluded(t, excl))
        .toList();
    final plays = await trackPlayTimestamps();
    final now = DateTime.now().millisecondsSinceEpoch;
    final scores = tasteTrackScores(plays, now, await tasteRecentEmphasis());
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

  /// Teratas menurut hitungan putar MENTAH dalam jendela waktu
  /// (Kampanye Rombak UI — rak Beranda "Paling sering minggu ini"):
  /// hanya event dengan started_at >= [fromMs] yang dihitung; urutan
  /// hitungan menurun, seri diputus oleh putar terakhir terbaru.
  /// Berbeda dari [frequentTracks] (peringkat campuran sepanjang
  /// masa): rak mingguan harus jujur pada jendelanya — minggu yang
  /// kosong mengembalikan daftar kosong, bukan juara lama.
  Future<List<({Track track, int count})>> topPlayedSince(
    int fromMs, {
    int limit = 3,
  }) async {
    final d = await db;
    // Ronde 8074: ambil lebih banyak dari batas, saring pengecualian
    // selera di Dart (pencocokan artis butuh normalisasi), baru potong —
    // rak mingguan tidak boleh memajang trek/artis yang dikeluarkan.
    final rows = await d.rawQuery(
      '''SELECT t.*, COUNT(*) c, MAX(e.started_at) last FROM playback_events e
      JOIN tracks t ON t.provider_id=e.provider_id AND t.provider_track_id=e.provider_track_id
      WHERE e.started_at >= ? GROUP BY e.provider_id, e.provider_track_id
      ORDER BY c DESC, last DESC LIMIT ?''',
      [fromMs, limit * 4],
    );
    final excl = await tasteExclusions();
    return [
      for (final r in rows)
        if (!isTrackExcluded(Track.fromDbRow(r), excl))
          (track: Track.fromDbRow(r), count: (r['c'] as int?) ?? 0),
    ].take(limit).toList();
  }

  Future<void> clearHistory() async {
    final d = await db;
    await d.delete('playback_events');
  }

  // ---------- Ruang Kendali Selera (Ronde 8074, skema v7) ----------

  /// Kunci pref bobot selera (penekanan terkini 0..1; bawaan 1,0 =
  /// peringkat campuran F2.5 persis) dan Mode Samaran.
  static const prefTasteRecentEmphasis = 'taste.recentEmphasis';
  static const prefTasteSamaran = 'taste.samaran';

  /// Ronde 8079: "Jangan tampilkan lagi" pada lembar penjelas Mode
  /// Samaran (S1) — sekali terisi true, pengaktifan Samaran langsung
  /// tanpa lembar di kedua pintu masuk (pill Player & saklar Selera).
  static const prefTasteSamaranHowSeen = 'taste.samaranHowSeen';

  /// Kunci pref cap waktu ekspor D2 terakhir yang berhasil (ditulis
  /// LibraryTransferService; dibaca lembar Reset Selera sebagai
  /// "Cadangan terakhir").
  static const prefLastExportAt = 'transfer.lastExportAt';

  /// Semua pengecualian rekomendasi, terbaru dulu.
  Future<List<TasteExclusion>> tasteExclusions() async {
    final d = await db;
    final rows = await d.query('taste_exclusions',
        orderBy: 'created_at DESC, label ASC');
    return rows.map(TasteExclusion.fromRow).toList();
  }

  Future<void> addTasteExclusion(TasteExclusion e) async {
    final d = await db;
    await d.insert('taste_exclusions', e.toRow(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> removeTasteExclusion(String kind, String key) async {
    final d = await db;
    await d.delete('taste_exclusions',
        where: 'kind=? AND key=?', whereArgs: [kind, key]);
  }

  /// Kunci trek yang dikeluarkan langsung (untuk tangga Putar Otomatis).
  Future<Set<TrackKey>> tasteExcludedTrackKeys() async {
    final excl = await tasteExclusions();
    final out = <TrackKey>{};
    for (final e in excl) {
      if (e.isArtist) continue;
      final parts = e.key.split('\u001f');
      if (parts.length == 2) out.add(TrackKey(parts[0], parts[1]));
    }
    return out;
  }

  /// Byline artis yang dikeluarkan (untuk tangga Putar Otomatis —
  /// pemanggil menormalkannya dengan kunci artis primer miliknya).
  Future<List<String>> tasteExcludedArtistBylines() async {
    final excl = await tasteExclusions();
    return [for (final e in excl) if (e.isArtist) e.key];
  }

  /// Penekanan terkini pengguna (0..1). Bawaan 1,0: peringkat campuran
  /// F2.5 yang sudah berjalan — slider Selera mengubahnya dari sana.
  Future<double> tasteRecentEmphasis() async {
    final v = await pref<num>(prefTasteRecentEmphasis);
    if (v == null) return 1.0;
    return v.toDouble().clamp(0.0, 1.0).toDouble();
  }

  /// Peristiwa putar mentah untuk Cermin Selera (cap waktu + durasi
  /// dengar), urut waktu naik.
  Future<List<({int startedAt, int listenedMs})>> allPlayEvents() async {
    final d = await db;
    final rows = await d.rawQuery(
      'SELECT started_at, listened_ms FROM playback_events ORDER BY started_at',
    );
    return [
      for (final r in rows)
        (
          startedAt: (r['started_at'] as int?) ?? 0,
          listenedMs: (r['listened_ms'] as int?) ?? 0,
        ),
    ];
  }

  /// Reset Selera: hapus SEMUA data turunan selera dalam satu transaksi —
  /// riwayat putar (bahan baku selera), pengecualian, dan bobot.
  /// Perpustakaan, playlist, lagu suka, unduhan, dan Brankas Sesi TIDAK
  /// disentuh. Mode Samaran adalah keadaan sesi, bukan data selera —
  /// tidak ikut direset.
  Future<void> resetTaste() async {
    final d = await db;
    await d.transaction((txn) async {
      await txn.delete('playback_events');
      await txn.delete('taste_exclusions');
      await txn.delete('user_prefs',
          where: 'key=?', whereArgs: [prefTasteRecentEmphasis]);
    });
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
    // Ronde 8074: artis yang dikeluarkan tidak lagi memimpin peringkat
    // (rak "karena artis" Beranda membaca dari sini), dan skor memakai
    // bobot selera pengguna (bawaan = campuran F2.5 persis).
    final excl = await tasteExclusions();
    final emphasis = await tasteRecentEmphasis();
    final out = <({String artistNames, int count, double score, int last})>[
      for (final e in byArtist.entries)
        if (!isArtistExcluded(e.key, excl))
          (
            artistNames: e.key,
            count: e.value.length,
            score: tastePlayScore(e.value, now, emphasis),
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
    // Ronde 8074: trek yang dikeluarkan (langsung atau lewat artisnya)
    // gugur dari rak; skor memakai bobot selera pengguna.
    final excl = await tasteExclusions();
    out.removeWhere((t) => isTrackExcluded(t, excl));
    final plays = await trackPlayTimestamps();
    final now = DateTime.now().millisecondsSinceEpoch;
    final scores = tasteTrackScores(plays, now, await tasteRecentEmphasis());
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
      // v8 (Ronde 8075): potret urutan alami & himpunan terputar
      // siklus ikut disimpan — tanpa ini keduanya terbuang senyap di
      // jalur kolom-tetap ini (lihat catatan migrasi v8).
      'natural_continuation_json': snapshot['naturalContinuation'] == null
          ? null
          : jsonEncode(snapshot['naturalContinuation']),
      'natural_autoplay_json': snapshot['naturalAutoplay'] == null
          ? null
          : jsonEncode(snapshot['naturalAutoplay']),
      'cycle_played_json': snapshot['cyclePlayed'] == null
          ? null
          : jsonEncode(snapshot['cyclePlayed']),
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
    // Dekode TOLERAN per kolom (Ronde Bug Notifikasi): JSON satu kolom yang
    // korup tidak boleh membunuh seluruh snapshot — kolom itu jatuh ke nilai
    // kosongnya dan kolom sehat tetap terbaca. (Versi lama melempar keluar
    // dari jsonDecode pertama yang rusak, dan karena barisnya menetap,
    // restorasi gagal IDENTIK di setiap start dingin sampai data dihapus.)
    Object? decodeTolerant(Object? raw, Object? fallback) {
      if (raw is! String) return fallback;
      try {
        return jsonDecode(raw);
      } catch (_) {
        return fallback;
      }
    }

    return {
      'contextKind': r['context_kind'],
      'contextId': r['context_id'],
      'contextLabel': r['context_label'],
      'seeds': decodeTolerant(r['seed_json'], const []),
      'manual': decodeTolerant(r['manual_json'], const []),
      'continuation': decodeTolerant(r['continuation_json'], const []),
      'autoplay': decodeTolerant(r['autoplay_json'], const []),
      'currentRef': r['current_ref'],
      'positionMs': r['position_ms'],
      'shuffle': r['shuffle_mode'],
      'repeat': r['repeat_mode'],
      'autoplayEnabled': (r['autoplay_enabled'] as int) == 1,
      'signals': decodeTolerant(r['session_signals_json'], const {}),
      'played': decodeTolerant(r['played_json'], const []),
      // v8 (Ronde 8075): kunci hanya disertakan bila kolomnya terisi,
      // agar restore() membedakan "potret memang tidak ada" dari
      // "potret kosong" persis seperti snapshot di ingatan.
      if (r['natural_continuation_json'] != null)
        'naturalContinuation':
            decodeTolerant(r['natural_continuation_json'], const []),
      if (r['natural_autoplay_json'] != null)
        'naturalAutoplay':
            decodeTolerant(r['natural_autoplay_json'], const []),
      if (r['cycle_played_json'] != null)
        'cyclePlayed': decodeTolerant(r['cycle_played_json'], const []),
      'volume': (r['volume'] as num?)?.toDouble(),
    };
  }

  /// Buang snapshot antrean (Ronde Bug Notifikasi): snapshot yang terbukti
  /// beracun — gagal dibaca karena bentuk datanya, atau menyatakan sesi
  /// tetapi tak satu pun treknya ada di katalog — dibuang oleh jalur
  /// restorasi agar start berikutnya mulai dari sesi bersih, bukan gagal
  /// yang sama selamanya.
  Future<void> deleteQueueSnapshot() async {
    final d = await db;
    await d.delete('queue_snapshots', where: 'id=1');
  }

  // ---------- Brankas Sesi (Ronde 8072, v6) ----------
  /// Simpan satu sesi bernama dari snapshot antrean PENUH (bentuk yang
  /// sama dengan snapshot L-16 / simpanan Lanjut Besok D-15). Mengembalikan
  /// id sesi. Satu INSERT tunggal — simpan bersifat atomik: sesi tercatat
  /// utuh atau tidak sama sekali (titik bunuh di tengah simpan tidak
  /// meninggalkan baris setengah jadi).
  Future<String> saveVaultSession({
    required String name,
    required Map<String, Object?> snapshot,
    Track? currentTrack,
  }) async {
    final d = await db;
    final id = const Uuid().v4();
    int countOf(String key) {
      final v = snapshot[key];
      return v is List ? v.length : 0;
    }

    final trackCount = countOf('played') +
        (snapshot['currentRef'] != null ? 1 : 0) +
        countOf('manual') +
        countOf('continuation') +
        countOf('autoplay');
    await d.insert('saved_sessions', {
      'id': id,
      'name': name,
      'saved_at': DateTime.now().millisecondsSinceEpoch,
      'snapshot_json': jsonEncode(snapshot),
      'track_count': trackCount,
      'current_title': currentTrack?.title,
      'current_artist': currentTrack?.artistNames,
      'current_artwork': currentTrack?.artworkUrl,
      'context_label': snapshot['contextLabel'],
      'position_ms': (snapshot['positionMs'] as num?)?.toInt() ?? 0,
    });
    return id;
  }

  /// Metadata semua sesi tersimpan, terbaru dulu (daftar Brankas & rak
  /// Beranda). Snapshot TIDAK ikut — muat terpisah lewat [vaultSnapshot].
  Future<List<Map<String, Object?>>> vaultSessions() async {
    final d = await db;
    final rows = await d.query(
      'saved_sessions',
      columns: [
        'id',
        'name',
        'saved_at',
        'track_count',
        'current_title',
        'current_artist',
        'current_artwork',
        'context_label',
        'position_ms',
      ],
      orderBy: 'saved_at DESC, rowid DESC',
    );
    return rows;
  }

  /// Snapshot antrean penuh milik sesi [id]; null bila sesi tak ada atau
  /// JSON-nya rusak (dekode toleran: sesi rusak tidak boleh menjatuhkan
  /// layar — pemanggil menawarkannya sebagai tak-bisa-dipulihkan).
  Future<Map<String, Object?>?> vaultSnapshot(String id) async {
    final d = await db;
    final rows = await d.query(
      'saved_sessions',
      columns: ['snapshot_json'],
      where: 'id=?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    try {
      final decoded = jsonDecode(rows.first['snapshot_json'] as String);
      return decoded is Map ? decoded.cast<String, Object?>() : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> deleteVaultSession(String id) async {
    final d = await db;
    await d.delete('saved_sessions', where: 'id=?', whereArgs: [id]);
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
    // Null-safe & type-safe (perbaikan Ronde Player B): nilai yang
    // disimpan bisa SAH berupa null JSON (mis. setPref('sleep.last',
    // null) saat simpanan dibuang) atau tipenya berbeda dari yang
    // diminta pemanggil. Cast lama `as T` melempar
    // "type 'Null' is not a subtype of type 'String'" di jalur itu —
    // crash berulang kartu Sleep Resume di logcat ronde 8038. Nilai
    // yang tak cocok tipe kini dibaca sebagai "tidak ada".
    final decoded = jsonDecode(rows.first['value_json'] as String);
    return decoded is T ? decoded : null;
  }

  Future<void> setPref(String key, Object? value) async {
    final d = await db;
    await d.insert('user_prefs', {
      'key': key,
      'value_json': jsonEncode(value),
      'schema_v': 1,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // ---------- waveform ukur (Ronde Player B, skema v5) ----------
  Future<WaveformData?> waveformFor(TrackKey k) async {
    final d = await db;
    final rows = await d.query(
      'track_waveforms',
      where: 'provider_id=? AND provider_track_id=?',
      whereArgs: [k.providerId, k.id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return WaveformData.decode(rows.first['buckets'] as String?);
  }

  Future<void> saveWaveform(TrackKey k, WaveformData data) async {
    final d = await db;
    await d.insert('track_waveforms', {
      'provider_id': k.providerId,
      'provider_track_id': k.id,
      'buckets': data.encode(),
      'updated_at': DateTime.now().millisecondsSinceEpoch,
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

  // ---------- ekspor/impor kepemilikan (Ronde 8070, D2 / F-12) ----------
  // Seksi ADITIF penuh: tidak satu pun metode lama diubah. Penerapan
  // impor berjalan dalam SATU transaksi (F-12: gagal di tengah = tidak
  // ada perubahan sebagian); penguraian & validasi berkas selesai di
  // services/library_transfer.dart SEBELUM metode terapkan dipanggil.

  /// Semua playlist pengguna (bukan sistem) beserta treknya, urutan
  /// pembuatan & posisi entri dipertahankan. Entri yang baris katalognya
  /// sudah terhapus retensi dilewati — metadata-nya tidak ada lagi di
  /// mana pun di aplikasi, jadi tidak bisa direkonstruksi dengan jujur.
  Future<List<TransferPlaylist>> exportPlaylistsData() async {
    final d = await db;
    final pls = await d.query(
      'playlists',
      where: 'is_system=0',
      orderBy: 'created_at ASC',
    );
    final out = <TransferPlaylist>[];
    for (final p in pls) {
      final rows = await d.rawQuery(
        '''SELECT t.* FROM playlist_entries e
        JOIN tracks t ON t.provider_id=e.provider_id AND t.provider_track_id=e.provider_track_id
        WHERE e.playlist_id=? ORDER BY e.position ASC''',
        [p['id']],
      );
      out.add(TransferPlaylist(
        name: p['name'] as String,
        description: p['description'] as String?,
        createdAt: p['created_at'] as int?,
        tracks: [
          for (final r in rows)
            TransferTrack.fromTrack(Track.fromDbRow(r)),
        ],
      ));
    }
    return out;
  }

  /// Lagu disukai beserta waktu sukanya, urutan suka menaik.
  Future<List<TransferLike>> exportLikedData() async {
    final d = await db;
    final rows = await d.rawQuery('''SELECT t.*, l.liked_at FROM liked_tracks l
      JOIN tracks t ON t.provider_id=l.provider_id AND t.provider_track_id=l.provider_track_id
      ORDER BY l.liked_at ASC''');
    return [
      for (final r in rows)
        TransferLike(
          track: TransferTrack.fromTrack(Track.fromDbRow(r)),
          likedAt: (r['liked_at'] as int?) ?? 0,
        ),
    ];
  }

  /// Peristiwa putar mentah beserta metadata treknya, urutan waktu
  /// menaik. Peristiwa yang baris katalognya sudah terhapus retensi
  /// dilewati (alasan sama seperti ekspor playlist).
  Future<List<TransferEvent>> exportHistoryData() async {
    final d = await db;
    final rows = await d.rawQuery('''SELECT t.*, e.started_at, e.listened_ms,
        e.completed, e.context_kind, e.context_id FROM playback_events e
      JOIN tracks t ON t.provider_id=e.provider_id AND t.provider_track_id=e.provider_track_id
      ORDER BY e.started_at ASC''');
    return [
      for (final r in rows)
        TransferEvent(
          track: TransferTrack.fromTrack(Track.fromDbRow(r)),
          startedAt: (r['started_at'] as int?) ?? 0,
          listenedMs: (r['listened_ms'] as int?) ?? 0,
          completed: (r['completed'] as int? ?? 0) == 1,
          contextKind: r['context_kind'] as String?,
          contextId: r['context_id'] as String?,
        ),
    ];
  }

  /// Item tersimpan (album/artis) untuk berkas ekspor.
  Future<List<TransferSavedItem>> exportSavedItemsData() async {
    final d = await db;
    final rows = await d.query('saved_items', orderBy: 'saved_at ASC');
    return [
      for (final r in rows)
        TransferSavedItem(
          kind: r['kind'] as String,
          providerId: r['provider_id'] as String,
          itemId: r['item_id'] as String,
          title: r['title'] as String,
          subtitle: r['subtitle'] as String?,
          artworkUrl: r['artwork_url'] as String?,
          savedAt: (r['saved_at'] as int?) ?? 0,
        ),
    ];
  }

  /// Hitungan pustaka saat ini (bahan lembar Ekspor & dialog konfirmasi).
  Future<({int playlists, int liked, int history})> libraryCounts() async {
    final d = await db;
    Future<int> count(String sql) async {
      final r = await d.rawQuery(sql);
      return (r.first.values.first as int?) ?? 0;
    }

    return (
      playlists: await count(
          'SELECT COUNT(*) FROM playlists WHERE is_system=0'),
      liked: await count('SELECT COUNT(*) FROM liked_tracks'),
      history: await count('SELECT COUNT(*) FROM playback_events'),
    );
  }

  /// Proyeksi mode Gabungkan atas [data] terhadap keadaan basis data
  /// sekarang — murni baca, tidak menulis apa pun.
  Future<ImportProjection> projectLibraryImport(
      LibraryTransferData data) async {
    final d = await db;
    final existingPl = await d.query(
      'playlists',
      columns: ['id', 'name'],
      where: 'is_system=0',
      orderBy: 'updated_at DESC',
    );
    final idByName = <String, String>{};
    for (final r in existingPl) {
      idByName.putIfAbsent(r['name'] as String, () => r['id'] as String);
    }
    var newPl = 0, mergedPl = 0, tracksAdded = 0;
    for (final p in data.playlists) {
      final distinct = <TrackKey>{for (final t in p.tracks) t.key};
      final targetId = idByName[p.name];
      if (targetId == null) {
        newPl++;
        tracksAdded += distinct.length;
      } else {
        mergedPl++;
        final rows = await d.query(
          'playlist_entries',
          columns: ['provider_id', 'provider_track_id'],
          where: 'playlist_id=?',
          whereArgs: [targetId],
        );
        final have = <TrackKey>{
          for (final r in rows)
            TrackKey(
                r['provider_id'] as String, r['provider_track_id'] as String),
        };
        tracksAdded += distinct.difference(have).length;
      }
    }
    final likedNow = await likedKeys();
    final likedAdded =
        data.liked.where((l) => !likedNow.contains(l.track.key)).length;
    var historyAdded = 0;
    final history = data.history;
    if (history != null) {
      final rows = await d.rawQuery(
          'SELECT provider_id, provider_track_id, started_at, listened_ms FROM playback_events');
      final seen = <String>{
        for (final r in rows)
          '${r['provider_id']}|${r['provider_track_id']}|${r['started_at']}|${r['listened_ms']}',
      };
      for (final e in history) {
        final k =
            '${e.track.providerId}|${e.track.trackId}|${e.startedAt}|${e.listenedMs}';
        if (seen.add(k)) historyAdded++;
      }
    }
    return ImportProjection(
      newPlaylists: newPl,
      mergedPlaylists: mergedPl,
      playlistTracksAdded: tracksAdded,
      likedAdded: likedAdded,
      historyAdded: historyAdded,
    );
  }

  /// Terapkan berkas ekspor yang SUDAH tervalidasi penuh, dalam satu
  /// transaksi. [replace] = mode Ganti semua: playlist pengguna, suka,
  /// dan riwayat saat ini dihapus di dalam transaksi yang sama sebelum
  /// isi berkas ditulis (riwayat hanya dihapus bila berkas memuat
  /// riwayat — berkas tanpa riwayat tidak menyentuhnya, F-12).
  Future<void> applyLibraryImport(
    LibraryTransferData data, {
    required bool replace,
  }) async {
    final d = await db;
    final now = DateTime.now().millisecondsSinceEpoch;
    await d.transaction((tx) async {
      // 1) Semua trek dirujuk berkas → katalog (penjaga metadata sama
      //    seperti cacheTracks: nilai kosong mewarisi nilai lama).
      final byKey = <TrackKey, TransferTrack>{};
      for (final p in data.playlists) {
        for (final t in p.tracks) {
          byKey[t.key] = t;
        }
      }
      for (final l in data.liked) {
        byKey[l.track.key] = l.track;
      }
      final history = data.history;
      if (history != null) {
        for (final e in history) {
          byKey[e.track.key] = e.track;
        }
      }
      await _upsertTransferTracks(tx, byKey.values);

      // 2) Mode ganti: kosongkan milik pengguna di transaksi yang sama.
      if (replace) {
        await tx.rawDelete(
            'DELETE FROM playlist_entries WHERE playlist_id IN (SELECT id FROM playlists WHERE is_system=0)');
        await tx.delete('playlists', where: 'is_system=0');
        await tx.delete('liked_tracks');
        if (history != null) await tx.delete('playback_events');
      }

      // 3) Playlist: gabung per nama (mode gabung) atau buat baru.
      for (final p in data.playlists) {
        String? targetId;
        if (!replace) {
          final rows = await tx.query(
            'playlists',
            columns: ['id'],
            where: 'name=? AND is_system=0',
            whereArgs: [p.name],
            orderBy: 'updated_at DESC',
            limit: 1,
          );
          if (rows.isNotEmpty) targetId = rows.first['id'] as String;
        }
        if (targetId == null) {
          targetId = const Uuid().v4();
          await tx.insert('playlists', {
            'id': targetId,
            'name': p.name,
            'description': p.description,
            'is_system': 0,
            'created_at': p.createdAt ?? now,
            'updated_at': now,
          });
        }
        final existing = await tx.query(
          'playlist_entries',
          columns: ['provider_id', 'provider_track_id', 'position'],
          where: 'playlist_id=?',
          whereArgs: [targetId],
        );
        final have = <TrackKey>{};
        var pos = 0;
        for (final r in existing) {
          have.add(TrackKey(
              r['provider_id'] as String, r['provider_track_id'] as String));
          final rp = (r['position'] as int?) ?? 0;
          if (rp >= pos) pos = rp + 1;
        }
        final batch = tx.batch();
        var inserted = 0;
        for (final t in p.tracks) {
          if (!have.add(t.key)) continue; // dedupe per kunci trek
          batch.insert('playlist_entries', {
            'playlist_id': targetId,
            'position': pos++,
            'provider_id': t.providerId,
            'provider_track_id': t.trackId,
            'added_at': now,
          });
          inserted++;
        }
        if (inserted > 0) await batch.commit(noResult: true);
        await tx.update(
          'playlists',
          {'updated_at': now},
          where: 'id=?',
          whereArgs: [targetId],
        );
      }

      // 4) Suka: gabungan — baris yang sudah ada mempertahankan waktu
      //    sukanya (insert ignore).
      final likeBatch = tx.batch();
      for (final l in data.liked) {
        likeBatch.insert(
          'liked_tracks',
          {
            'provider_id': l.track.providerId,
            'provider_track_id': l.track.trackId,
            'liked_at': l.likedAt,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
      if (data.liked.isNotEmpty) await likeBatch.commit(noResult: true);

      // 5) Riwayat: tambahkan peristiwa yang belum tercatat (dedupe
      //    tupel persis terhadap isi tabel + isi berkas itu sendiri).
      if (history != null) {
        final rows = await tx.rawQuery(
            'SELECT provider_id, provider_track_id, started_at, listened_ms FROM playback_events');
        final seen = <String>{
          for (final r in rows)
            '${r['provider_id']}|${r['provider_track_id']}|${r['started_at']}|${r['listened_ms']}',
        };
        final evBatch = tx.batch();
        var evInserted = 0;
        for (final e in history) {
          final k =
              '${e.track.providerId}|${e.track.trackId}|${e.startedAt}|${e.listenedMs}';
          if (!seen.add(k)) continue;
          evBatch.insert('playback_events', {
            'provider_id': e.track.providerId,
            'provider_track_id': e.track.trackId,
            'started_at': e.startedAt,
            'listened_ms': e.listenedMs,
            'completed': e.completed ? 1 : 0,
            'context_kind': e.contextKind,
            'context_id': e.contextId,
          });
          evInserted++;
        }
        if (evInserted > 0) await evBatch.commit(noResult: true);
      }

      // 6) Item tersimpan: tulis per kunci utama (idempoten).
      final savedBatch = tx.batch();
      for (final s in data.savedItems) {
        savedBatch.insert(
          'saved_items',
          {
            'kind': s.kind,
            'provider_id': s.providerId,
            'item_id': s.itemId,
            'title': s.title,
            'subtitle': s.subtitle,
            'artwork_url': s.artworkUrl,
            'saved_at': s.savedAt,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      if (data.savedItems.isNotEmpty) {
        await savedBatch.commit(noResult: true);
      }
    });
  }

  /// Impor satu playlist bagikan (QR/berkas) sebagai playlist BARU —
  /// penerima selalu mendapat salinannya sendiri; tabrakan nama diberi
  /// akhiran " (2)", " (3)", … Mengembalikan nama final yang dipakai.
  Future<String> importSharedPlaylist(SharedPlaylistData data) async {
    final d = await db;
    final now = DateTime.now().millisecondsSinceEpoch;
    return d.transaction((tx) async {
      await _upsertTransferTracks(tx, data.tracks);
      var name = data.name;
      var suffix = 2;
      while (true) {
        final rows = await tx.query(
          'playlists',
          columns: ['id'],
          where: 'name=? AND is_system=0',
          whereArgs: [name],
          limit: 1,
        );
        if (rows.isEmpty) break;
        name = '${data.name} (${suffix++})';
      }
      final id = const Uuid().v4();
      await tx.insert('playlists', {
        'id': id,
        'name': name,
        'is_system': 0,
        'created_at': now,
        'updated_at': now,
      });
      final have = <TrackKey>{};
      final batch = tx.batch();
      var pos = 0;
      for (final t in data.tracks) {
        if (!have.add(t.key)) continue;
        batch.insert('playlist_entries', {
          'playlist_id': id,
          'position': pos++,
          'provider_id': t.providerId,
          'provider_track_id': t.trackId,
          'added_at': now,
        });
      }
      if (pos > 0) await batch.commit(noResult: true);
      return name;
    });
  }

  /// Tulis trek transfer ke katalog di dalam transaksi, dengan penjaga
  /// metadata yang sama seperti [cacheTracks]: nilai tak-kosong yang
  /// masuk menang; yang kosong mewarisi baris lama.
  Future<void> _upsertTransferTracks(
    Transaction tx,
    Iterable<TransferTrack> tracks,
  ) async {
    for (final tt in tracks) {
      final t = tt.toTrack();
      final row = t.toDbRow();
      final old = await tx.query(
        'tracks',
        where: 'provider_id=? AND provider_track_id=?',
        whereArgs: [t.providerId, t.id],
        limit: 1,
      );
      if (old.isNotEmpty) {
        final o = old.first;
        if ((row['artist_names'] as String).trim().isEmpty &&
            (o['artist_names'] as String).trim().isNotEmpty) {
          row['artist_names'] = o['artist_names'];
        }
        if (row['artwork_url'] == null && o['artwork_url'] != null) {
          row['artwork_url'] = o['artwork_url'];
        }
        if (row['duration_ms'] == null && o['duration_ms'] != null) {
          row['duration_ms'] = o['duration_ms'];
        }
      }
      await tx.insert(
        'tracks',
        row,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }
}
