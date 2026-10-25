import 'dart:async';

import 'package:dio/dio.dart';

import '../data/app_db.dart';
import '../domain/models.dart';
import 'lyrics_service.dart' show primaryArtistName;
import 'observability.dart';

/// Pengayaan metadata MusicBrainz + Cover Art Archive (F2, PETA-JALAN butir 2):
/// HANYA sampul cadangan, dan HANYA bila sumber utama trek tidak memberi
/// sampul sama sekali. MusicBrainz membatasi 1 permintaan/detik — antrean
/// serial di sini menegakkannya. Hasil positif & negatif tercache lokal.
class EnrichmentService {
  final AppDb db;
  final Dio _dio;
  EnrichmentService(this.db, {Dio? dio}) : _dio = dio ?? Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 6), receiveTimeout: const Duration(seconds: 12),
      headers: {'User-Agent': 'Clai/1.0.0 ( https://github.com/Riyanzakaria/clai )', 'Accept': 'application/json'}));

  Future<void> _tail = Future<void>.value();
  DateTime _lastCall = DateTime.fromMillisecondsSinceEpoch(0);

  /// URL sampul album (front-250 CAA) atau null bila tidak ditemukan/gagal.
  Future<String?> coverFor(Track t) {
    final run = _tail.then((_) => _coverForInner(t));
    _tail = run.then((_) {}, onError: (_) {});
    return run;
  }

  Future<String?> _coverForInner(Track t) async {
    final album = t.albumTitle?.trim();
    if (album == null || album.isEmpty) return null; // tanpa nama album, pencarian rilis tak bertanggung jawab
    final key = '${primaryArtistName(t.artistNames).toLowerCase()}|$album'.toLowerCase();
    final cached = await db.enrichment('caa-cover', key);
    if (cached.exists) return cached.value;
    try {
      await _respectRateLimit();
      final artist = primaryArtistName(t.artistNames);
      final query = 'release:"${album.replaceAll('"', '')}" AND artist:"${artist.replaceAll('"', '')}"';
      final res = await _dio.get<Map<String, dynamic>>('https://musicbrainz.org/ws/2/release/',
          queryParameters: {'query': query, 'fmt': 'json', 'limit': 3},
          options: Options(validateStatus: (s) => s != null && s < 500));
      String? coverUrl;
      final releases = res.data?['releases'];
      if (res.statusCode == 200 && releases is List) {
        for (final r in releases) {
          if (r is! Map) continue;
          final id = r['id'] as String?;
          if (id == null) continue;
          final candidate = 'https://coverartarchive.org/release/$id/front-250';
          await _respectRateLimit();
          // Validasi keberadaan sampul lewat unduhan kecil; URL yang disimpan
          // adalah URL CAA-nya sendiri (stabil untuk ditampilkan CoverArt).
          final head = await _dio.get<List<int>>(candidate,
              options: Options(responseType: ResponseType.bytes,
                  validateStatus: (s) => s != null && s < 500,
                  receiveTimeout: const Duration(seconds: 8)));
          if (head.statusCode == 200 && (head.data?.isNotEmpty ?? false)) { coverUrl = candidate; break; }
        }
      }
      await db.saveEnrichment('caa-cover', key, coverUrl);
      return coverUrl;
    } catch (e) {
      // Kegagalan jaringan TIDAK dicache — kesempatan berikutnya tetap terbuka.
      Observability.instance.log('pengayaan-sampul-gagal', e.toString());
      return null;
    }
  }

  Future<void> _respectRateLimit() async {
    final wait = const Duration(milliseconds: 1100) - DateTime.now().difference(_lastCall);
    if (wait > Duration.zero) await Future<void>.delayed(wait);
    _lastCall = DateTime.now();
  }
}
