import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../data/app_db.dart';
import '../domain/models.dart';

class PlaylistInfo {
  final String id, name;
  final int count;
  final List<String> artworkUrls;
  const PlaylistInfo(this.id, this.name, this.count, this.artworkUrls);
}

/// Wajah UI untuk data milik pengguna (suka, playlist) — selalu dari basis data lokal (PRD Bab 6).
/// Item koleksi tersimpan non-lagu (D-13): album & artis.
class SavedItemInfo {
  final String kind; // album | artist
  final String providerId;
  final String id;
  final String title;
  final String? subtitle;
  final String? artworkUrl;
  const SavedItemInfo(this.kind, this.providerId, this.id, this.title, this.subtitle, this.artworkUrl);
}

class LibraryController extends ChangeNotifier {
  final AppDb db;
  LibraryController(this.db);
  Set<TrackKey> _liked = {};
  List<PlaylistInfo> _playlists = [];
  List<SavedItemInfo> _savedAlbums = [];
  List<SavedItemInfo> _savedArtists = [];
  bool loaded = false;

  Set<TrackKey> get likedKeys => _liked;
  List<PlaylistInfo> get playlists => _playlists;
  List<SavedItemInfo> get savedAlbums => _savedAlbums;
  List<SavedItemInfo> get savedArtists => _savedArtists;
  bool isLiked(TrackKey k) => _liked.contains(k);

  bool isSavedItem(String kind, String providerId, String id) =>
      (kind == 'album' ? _savedAlbums : _savedArtists)
          .any((e) => e.providerId == providerId && e.id == id);

  Future<void> toggleSavedItem(String kind, String providerId, String id,
      {String title = '', String? subtitle, String? artworkUrl}) async {
    final nowSaved = !isSavedItem(kind, providerId, id);
    await db.setSavedItem(kind, providerId, id, nowSaved,
        title: title, subtitle: subtitle, artworkUrl: artworkUrl);
    await _loadSavedItems();
    notifyListeners();
  }

  Future<void> _loadSavedItems() async {
    SavedItemInfo mapRow(Map<String, Object?> r) => SavedItemInfo(
        r['kind'] as String, r['provider_id'] as String, r['item_id'] as String,
        r['title'] as String, r['subtitle'] as String?, r['artwork_url'] as String?);
    _savedAlbums = (await db.savedItems('album')).map(mapRow).toList();
    _savedArtists = (await db.savedItems('artist')).map(mapRow).toList();
  }

  Future<void> load() async {
    _liked = await db.likedKeys();
    final rows = await db.playlists();
    final infos = <PlaylistInfo>[];
    for (final r in rows) {
      final id = r['id'] as String;
      final tracks = await db.playlistTracks(id);
      infos.add(PlaylistInfo(id, r['name'] as String, tracks.length,
          tracks.take(4).map((t) => t.artworkUrl ?? '').toList()));
    }
    _playlists = infos;
    await _loadSavedItems();
    loaded = true;
    notifyListeners();
  }

  Future<void> toggleLike(Track t) async {
    final nowLiked = !_liked.contains(t.key);
    await db.setLiked(t, nowLiked);
    if (nowLiked) { _liked.add(t.key); } else { _liked.remove(t.key); }
    notifyListeners();
  }

  /// Simpan banyak trek ke Koleksi sekaligus (Ronde Tambahan 2015:
  /// halaman Radio & mode pilih-banyak antrean). Yang sudah tersimpan
  /// dilewati tanpa mengubah apa pun. Mengembalikan jumlah yang BARU
  /// tersimpan, untuk umpan balik jujur.
  Future<int> saveAllToCollection(List<Track> tracks) async {
    var saved = 0;
    for (final t in tracks) {
      if (_liked.contains(t.key)) continue;
      await db.setLiked(t, true);
      _liked.add(t.key);
      saved++;
    }
    if (saved > 0) notifyListeners();
    return saved;
  }

  /// Tambah banyak trek ke satu playlist sekaligus (Ronde Tambahan
  /// 2015). Duplikat dilewati (semantik [addToPlaylist] bawaan tanpa
  /// allowDuplicate). Mengembalikan jumlah yang benar-benar masuk.
  Future<int> addAllToPlaylist(String playlistId, List<Track> tracks) async {
    var added = 0;
    for (final t in tracks) {
      if (await db.addToPlaylist(playlistId, t)) added++;
    }
    if (added > 0) await load();
    return added;
  }

  Future<String> createPlaylist(String name) async {
    final id = const Uuid().v4();
    await db.createPlaylist(id, name);
    await load();
    return id;
  }

  Future<bool> addToPlaylist(String playlistId, Track t, {bool allowDuplicate = false}) async {
    final ok = await db.addToPlaylist(playlistId, t, allowDuplicate: allowDuplicate);
    await load();
    return ok;
  }

  Future<void> renamePlaylist(String id, String name) async { await db.renamePlaylist(id, name); await load(); }
  Future<void> deletePlaylist(String id) async { await db.deletePlaylist(id); await load(); }
  Future<void> removeFromPlaylistAt(String id, int pos) async { await db.removeFromPlaylistAt(id, pos); await load(); }
  Future<void> moveInPlaylist(String id, int from, int to) async { await db.moveInPlaylist(id, from, to); await load(); }
}
