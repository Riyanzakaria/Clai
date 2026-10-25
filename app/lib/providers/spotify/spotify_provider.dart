import 'package:dio/dio.dart';
import '../../l10n/l10n.dart';

import '../../domain/models.dart';
import '../../services/observability.dart';
import 'spotify_web.dart';

/// Klien metadata Spotify publik (F2 Batch 1) — token web anonim + GraphQL
/// persisted `fetchPlaylist`. TANPA akun, TANPA kunci pengguna.
///
/// Ketahanan (mandat butir 4): token ter-cache sampai kedaluwarsa absolutnya;
/// 401 → token baru SATU kali lalu ulang; hash ditolak (412) / operasi tak
/// dikenal → SpotifyProviderException berpesan jelas agar UI menawarkan
/// degradasi anggun. Semua kegagalan provider tercatat di Log insiden.
class SpotifyMetadataProvider {
  final Dio _dio;
  SpotifyMetadataProvider({Dio? dio}) : _dio = dio ?? Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 8), receiveTimeout: const Duration(seconds: 20),
      headers: {'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36'}));

  String? _token;
  int _tokenExpiryMs = 0;

  Future<String> _accessToken({bool force = false}) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (!force && _token != null && now < _tokenExpiryMs - 30000) return _token!;
    try {
      final st = await _dio.get<Map<String, dynamic>>('https://open.spotify.com/api/server-time');
      final serverTime = (st.data?['serverTime'] as num?)?.toInt();
      if (serverTime == null) throw SpotifyProviderException(l10n.spErrServerTime);
      final totp = spotifyTotp(serverTime);
      final res = await _dio.get<Map<String, dynamic>>(
          'https://open.spotify.com/api/token?reason=transport&productType=web_player&totp=$totp&totpVer=$kSpotifyTotpVersion',
          options: Options(validateStatus: (s) => s != null && s < 500));
      final token = res.data?['accessToken'] as String?;
      if (res.statusCode != 200 || token == null || token.isEmpty) {
        // Sebab paling mungkin: rahasia/ver TOTP dirotasi Spotify.
        throw SpotifyProviderException(l10n.spErrTokenRejected);
      }
      _token = token;
      _tokenExpiryMs = (res.data?['accessTokenExpirationTimestampMs'] as num?)?.toInt() ?? (now + 20 * 60 * 1000);
      return token;
    } on SpotifyProviderException {
      rethrow;
    } catch (e) {
      throw SpotifyProviderException(l10n.spErrUnreachable('${e.runtimeType}'));
    }
  }

  Future<Map<String, dynamic>> _fetchPlaylistPage(String playlistId, int offset, int limit, {bool retried = false}) async {
    final token = await _accessToken(force: retried);
    final res = await _dio.post<dynamic>('https://api-partner.spotify.com/pathfinder/v2/query',
        data: {
          'operationName': 'fetchPlaylist',
          'variables': {'uri': 'spotify:playlist:$playlistId', 'offset': offset, 'limit': limit},
          'extensions': {'persistedQuery': {'version': 1, 'sha256Hash': kSpotifyFetchPlaylistHash}},
        },
        options: Options(headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
          'app-platform': 'WebPlayer',
        }, validateStatus: (s) => s != null && s < 600));
    if (res.statusCode == 401 && !retried) {
      _token = null;
      return _fetchPlaylistPage(playlistId, offset, limit, retried: true);
    }
    if (res.statusCode == 412) {
      throw SpotifyProviderException(l10n.spErrHashRotated);
    }
    if (res.statusCode != 200) {
      throw SpotifyProviderException(l10n.spErrHttp(res.statusCode ?? 0));
    }
    final data = res.data;
    if (data is! Map) throw SpotifyProviderException(l10n.spErrShape);
    final map = data.cast<String, dynamic>();
    final errors = map['errors'];
    if (errors is List && errors.isNotEmpty) {
      final msg = (errors.first as Map?)?['message'] as String? ?? 'operasi ditolak';
      throw SpotifyProviderException(l10n.spErrQueryRejected(msg));
    }
    return map;
  }

  /// Ambil playlist publik LENGKAP (paginasi defensif 100/halaman; berhenti di
  /// totalCount / halaman kosong; pagar 1000 trek dengan penanda truncated).
  Future<SpotifyPlaylistData> getPlaylist(String playlistId) async {
    try {
      const pageSize = 100;
      const cap = 1000;
      final h = parseFetchPlaylistPage(await _fetchPlaylistPage(playlistId, 0, pageSize));
      final all = <Track>[...h.tracks];
      var nonTrack = h.nonTrackItems;
      var offset = pageSize;
      var truncated = false;
      while (offset < h.totalCount && all.length < cap) {
        final page = parseFetchPlaylistPage(await _fetchPlaylistPage(playlistId, offset, pageSize));
        if (page.tracks.isEmpty && page.nonTrackItems == 0) break;
        all.addAll(page.tracks);
        nonTrack += page.nonTrackItems;
        offset += pageSize;
      }
      truncated = offset < h.totalCount && all.length >= cap;
      return SpotifyPlaylistData(
        id: h.id.isEmpty ? playlistId : h.id,
        name: h.name, description: h.description, ownerName: h.ownerName,
        imageUrl: h.imageUrl, totalCount: h.totalCount,
        tracks: all, nonTrackItems: nonTrack, truncated: truncated,
      );
    } on SpotifyProviderException catch (e) {
      Observability.instance.log('spotify-playlist-gagal', e.message);
      rethrow;
    } catch (e) {
      Observability.instance.log('spotify-playlist-gagal', e.toString());
      throw SpotifyProviderException(l10n.spLoadFail);
    }
  }
}
