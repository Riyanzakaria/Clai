import '../domain/models.dart';

/// Kontrak provider — Blueprint Bab 5.1: bentuk InnerTube tidak pernah bocor melewati batas ini.
abstract class MusicProvider {
  String get id;
  String get displayName;
  Future<SearchResults> search(String query);
  Future<List<String>> searchSuggestions(String query);
  Future<ContentPage> getAlbum(String albumId);
  Future<ContentPage> getPlaylist(String playlistId);
  Future<ContentPage> getArtist(String artistId);

  /// Tangga 2: lagu terkait/radio dari satu lagu benih.
  Future<List<Track>> getRelated(Track seed);

  /// Tangga 1: lagu lain dari artis yang sama (lagu populer artis benih).
  Future<List<Track>> getSameArtist(Track seed);

  /// Tangga 3: artis serupa → lagu-lagu mereka.
  Future<List<Artist>> getSimilarArtists(Track seed);

  /// Tangga 4: pencarian berbasis genre/niche dari metadata benih.
  Future<List<Track>> getSameGenre(Track seed);

  Future<StreamInfo> resolveStream(Track track, StreamQuality quality);

  /// Aliran cadangan (muxed/progresif) bila URL utama ditolak sumber saat diambil
  /// pemutar — v4.1. Default: provider tidak punya cadangan (null).
  Future<StreamInfo?> resolveMuxedFallback(Track track) async => null;
}

/// Satu percobaan klien pada rantai resolusi — bahan laporan Diagnostik Putar (v4.1).
class ClientAttempt {
  final String client;
  final bool ok;
  final String detail;
  final StreamInfo? info;
  const ClientAttempt({required this.client, required this.ok, required this.detail, this.info});
}

/// Sumber dinyatakan terdegradasi (Blueprint 5.5): bentuk berubah / ditolak sumber —
/// dibedakan dari gagal jaringan agar UI jujur.
class ProviderDegradedException implements Exception {
  final String message;
  ProviderDegradedException(this.message);
  @override
  String toString() => 'ProviderDegraded: $message';
}

class StreamResolutionException implements Exception {
  final String message;
  StreamResolutionException(this.message);
  @override
  String toString() => 'StreamResolution: $message';
}

/// Konten tidak tersedia di wilayah pengguna (Blueprint 5.5, Sapuan D-22):
/// dibedakan dari kegagalan jaringan/degradasi agar UI menyatakan sebab
/// sebenarnya per konten.
class RegionUnavailableException implements Exception {
  final String message;
  RegionUnavailableException(this.message);
  @override
  String toString() => 'RegionUnavailable: $message';
}
