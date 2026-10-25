import 'package:dio/dio.dart';

import '../data/app_db.dart';
import '../domain/models.dart';
import 'observability.dart';

/// ListenBrainz (F2, PETA-JALAN butir 2): scrobble & "sedang diputar" memakai
/// token MILIK PENGGUNA yang diisi sendiri di Pengaturan. MATI secara default.
/// Semua pengiriman best-effort: kegagalan hanya masuk Log insiden, TIDAK
/// PERNAH mengganggu pemutaran (pemanggil pun membungkusnya try/catch).
class ListenBrainzService {
  final AppDb db;
  final Dio _dio;
  ListenBrainzService(this.db, {Dio? dio}) : _dio = dio ?? Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 6), receiveTimeout: const Duration(seconds: 10),
      headers: {'User-Agent': 'Clai/1.0.0 ( https://github.com/Riyanzakaria/clai )', 'Content-Type': 'application/json'}));

  static const _base = 'https://api.listenbrainz.org/1';

  Future<bool> get enabled async => await db.pref<bool>('lb.enabled') ?? false;
  Future<String?> get token async {
    final t = (await db.pref<String>('lb.token'))?.trim();
    return (t == null || t.isEmpty) ? null : t;
  }

  Future<void> setEnabled(bool v) => db.setPref('lb.enabled', v);
  Future<void> setToken(String t) => db.setPref('lb.token', t.trim());

  Future<bool> validateToken(String token) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>('$_base/validate-token',
          options: Options(headers: {'Authorization': 'Token $token'},
              validateStatus: (s) => s != null && s < 500));
      return res.statusCode == 200 && res.data?['valid'] == true;
    } catch (_) {
      return false;
    }
  }

  Map<String, dynamic> _metadata(Track t) => {
        'track_name': t.title,
        'artist_name': t.artistNames,
        if (t.albumTitle != null && t.albumTitle!.isNotEmpty) 'release_name': t.albumTitle,
        'additional_info': {'media_player': 'Clai', 'submission_client': 'Clai', 'submission_client_version': '1.0.0'},
      };

  /// playing_now TIDAK boleh membawa listened_at (aturan API ListenBrainz).
  Future<void> playingNow(Track t) async {
    if (!await enabled) return;
    final tok = await token;
    if (tok == null) return;
    try {
      await _dio.post<dynamic>('$_base/submit-listens',
          data: {'listen_type': 'playing_now', 'payload': [{'track_metadata': _metadata(t)}]},
          options: Options(headers: {'Authorization': 'Token $tok'},
              validateStatus: (s) => s != null && s < 500));
    } catch (e) {
      Observability.instance.log('listenbrainz-playingnow-gagal', e.toString());
    }
  }

  /// Scrobble 'single' — dipanggil saat trek selesai didengar (ambang di pemanggil).
  Future<void> scrobble(Track t, {required DateTime startedAt}) async {
    if (!await enabled) return;
    final tok = await token;
    if (tok == null) return;
    try {
      final res = await _dio.post<dynamic>('$_base/submit-listens',
          data: {'listen_type': 'single', 'payload': [
            {'listened_at': startedAt.millisecondsSinceEpoch ~/ 1000, 'track_metadata': _metadata(t)}
          ]},
          options: Options(headers: {'Authorization': 'Token $tok'},
              validateStatus: (s) => s != null && s < 500));
      if (res.statusCode != 200) {
        Observability.instance.log('listenbrainz-scrobble-ditolak', 'HTTP ${res.statusCode}');
      }
    } catch (e) {
      Observability.instance.log('listenbrainz-scrobble-gagal', e.toString());
    }
  }
}
