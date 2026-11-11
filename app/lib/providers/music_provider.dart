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

/// Hasil probe resolusi SATU klien bernama (Diagnostik Putar — Ronde Klien
/// InnerTube, Fase A). [info] memegang URL mentah pilihan tingkat Normal
/// HANYA di memori sesi (bahan probe rentang/putar harness); yang boleh
/// masuk laporan adalah [urlHost] + [urlParams] (nama parameter saja).
class ClientStreamProbe {
  final String client;
  final String version;
  final String userAgent;
  final String playability;
  final String reason;
  final String? error;
  final List<({int itag, String mime, int? bitrate, int? contentLength})> audioFormats;
  final int totalFormats;

  /// Hitungan format adaptif mentah (Ronde Probe Penutup Peta): total
  /// adaptiveFormats dan yang bermime audio/* TANPA syarat URL langsung —
  /// membedakan "audio adaptif tidak ada sama sekali" dari "ada tetapi
  /// tercipher", yang keduanya membuat [audioFormats] kosong.
  final int adaptiveTotal;
  final int adaptiveAudioAny;
  final Map<String, int?> tierItags;
  final StreamInfo? info;
  final String? urlHost;
  final List<String> urlParams;
  const ClientStreamProbe({
    required this.client,
    required this.version,
    required this.userAgent,
    required this.playability,
    required this.reason,
    this.error,
    this.audioFormats = const [],
    this.totalFormats = 0,
    this.adaptiveTotal = 0,
    this.adaptiveAudioAny = 0,
    this.tierItags = const {},
    this.info,
    this.urlHost,
    this.urlParams = const [],
  });

  /// Klien ini menghasilkan URL audio adaptif langsung.
  bool get resolved => info != null;
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
