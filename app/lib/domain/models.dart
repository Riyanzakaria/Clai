import 'package:flutter/foundation.dart';

/// Kunci identitas trek: selalu gabungan (providerId, id) — PRD Bab 6 / Blueprint Bab 2.
@immutable
class TrackKey {
  final String providerId;
  final String id;
  const TrackKey(this.providerId, this.id);
  @override
  bool operator ==(Object other) => other is TrackKey && other.providerId == providerId && other.id == id;
  @override
  int get hashCode => Object.hash(providerId, id);
  @override
  String toString() => '$providerId:$id';
}

@immutable
class Track {
  final TrackKey key;
  final String title;
  final String artistNames;
  final String? albumId;
  final String? albumTitle;
  final List<String> artistIds;
  final Duration? duration;
  final String? artworkUrl;
  final bool isExplicit;

  /// Referensi resolusi aliran per provider (untuk ytmusic = videoId; untuk lokal = path/uri).
  final String playableRef;

  const Track({
    required this.key,
    required this.title,
    required this.artistNames,
    this.albumId,
    this.albumTitle,
    this.artistIds = const [],
    this.duration,
    this.artworkUrl,
    this.isExplicit = false,
    required this.playableRef,
  });

  String get id => key.id;
  String get providerId => key.providerId;

  Track copyWith({String? artworkUrl, Duration? duration}) => Track(
        key: key, title: title, artistNames: artistNames, albumId: albumId,
        albumTitle: albumTitle, artistIds: artistIds,
        duration: duration ?? this.duration, artworkUrl: artworkUrl ?? this.artworkUrl,
        isExplicit: isExplicit, playableRef: playableRef,
      );

  Map<String, Object?> toDbRow() => {
        'provider_id': providerId, 'provider_track_id': id, 'title': title,
        'artist_names': artistNames, 'album_id': albumId,
        'duration_ms': duration?.inMilliseconds, 'artwork_url': artworkUrl,
        'is_explicit': isExplicit ? 1 : 0, 'playable_ref': playableRef,
        'cached_at': DateTime.now().millisecondsSinceEpoch,
      };

  factory Track.fromDbRow(Map<String, Object?> r) => Track(
        key: TrackKey(r['provider_id'] as String, r['provider_track_id'] as String),
        title: r['title'] as String, artistNames: r['artist_names'] as String,
        albumId: r['album_id'] as String?,
        duration: r['duration_ms'] == null ? null : Duration(milliseconds: r['duration_ms'] as int),
        artworkUrl: r['artwork_url'] as String?,
        isExplicit: (r['is_explicit'] as int? ?? 0) == 1,
        playableRef: r['playable_ref'] as String,
      );
}

@immutable
class Album {
  final String providerId, id, title, artistNames;
  final int? year;
  final String? artworkUrl;
  const Album({required this.providerId, required this.id, required this.title, required this.artistNames, this.year, this.artworkUrl});
}

@immutable
class Artist {
  final String providerId, id, name;
  final String? artworkUrl;
  const Artist({required this.providerId, required this.id, required this.name, this.artworkUrl});
}

/// Halaman konten (album / playlist sumber / artis) hasil browse provider.
@immutable
class ContentPage {
  final String kind; // album | playlist | artist
  final String id;
  final String title;
  final String? subtitle;
  final String? description;
  final String? artworkUrl;
  final List<Track> tracks;
  final List<Album> albums;      // diskografi (artis)
  final List<Artist> relatedArtists; // tangga 3
  const ContentPage({required this.kind, required this.id, required this.title, this.subtitle,
      this.description, this.artworkUrl, this.tracks = const [], this.albums = const [], this.relatedArtists = const []});
}

/// Satu rak Beranda Jelajah (F2, PRD 5.1): campuran trek & kartu konten dari
/// umpan penemuan sumber. Rak yang gagal dimuat TIDAK direpresentasikan di
/// sini — kegagalan per sumber dinyatakan UI secara terpisah dan jujur.
@immutable
class ExploreShelf {
  final String title;
  final List<Track> tracks;
  final List<Album> albums;
  final List<Artist> artists;
  final List<Album> playlists; // playlist sumber sebagai Album-berdaftar (spt. SearchResults)
  const ExploreShelf({required this.title, this.tracks = const [], this.albums = const [],
      this.artists = const [], this.playlists = const []});
  bool get isEmpty => tracks.isEmpty && albums.isEmpty && artists.isEmpty && playlists.isEmpty;
  bool get hasCards => albums.isNotEmpty || artists.isNotEmpty || playlists.isNotEmpty;
}

@immutable
class SearchResults {
  final List<Track> songs;
  final List<Album> albums;
  final List<Artist> artists;
  final List<Album> playlists; // playlist sumber diperlakukan sebagai Album-berdaftar
  const SearchResults({this.songs = const [], this.albums = const [], this.artists = const [], this.playlists = const []});
  bool get isEmpty => songs.isEmpty && albums.isEmpty && artists.isEmpty && playlists.isEmpty;
}

@immutable
class StreamInfo {
  final String url;
  final String mimeType;
  final int? bitrate;
  final DateTime expiresAt;
  const StreamInfo({required this.url, required this.mimeType, this.bitrate, required this.expiresAt});
}

enum StreamQuality { low, normal, high }

extension StreamQualityLabel on StreamQuality {
  int get maxBitrate => switch (this) { StreamQuality.low => 70000, StreamQuality.normal => 160000, StreamQuality.high => 1 << 30 };
}

/// Apakah entri cache aliran cocok untuk tingkat kualitas yang diminta?
/// Cache aliran tidak menyimpan tingkat resolusinya; bitrate entri
/// adalah satu-satunya bukti. Entri hanya dipakai ulang bila
/// bitrate-nya jatuh DI DALAM pita tingkat yang diminta — temuan
/// emulator ronde poles: tanpa pemeriksaan ini, mode hemat data
/// (D-03) tidak berpengaruh sama sekali pada trek yang URL-nya sudah
/// tercache di tingkat Normal/Tinggi, karena resolveStream selalu
/// mengembalikan cache apa pun tingkatnya.
bool streamCacheFitsQuality(StreamInfo info, StreamQuality quality) {
  final b = info.bitrate;
  if (b == null) return false;
  return switch (quality) {
    StreamQuality.low => b <= 70000,
    StreamQuality.normal => b > 70000 && b <= 160000,
    StreamQuality.high => b > 160000,
  };
}
