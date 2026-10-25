import 'package:dio/dio.dart';

import '../data/app_db.dart';
import '../domain/models.dart';
import 'observability.dart';

/// Satu baris lirik tersinkron.
class LyricsLine {
  final Duration at;
  final String text;
  const LyricsLine(this.at, this.text);
}

/// Hasil lirik untuk satu trek: [lines] tersinkron bila ada; [plain] bila
/// hanya versi polos; [instrumental] = trek dinyatakan instrumental sumber.
class LyricsData {
  final List<LyricsLine>? lines;
  final String? plain;
  final bool instrumental;
  final String source; // 'LRCLIB' | 'cache'
  const LyricsData({this.lines, this.plain, this.instrumental = false, required this.source});
  bool get found => lines != null || plain != null || instrumental;
  bool get synced => lines != null;
}

final _tsRe = RegExp(r'\[(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?\]');
final _offsetRe = RegExp(r'\[offset:\s*([+-]?\d+)\]', caseSensitive: false);

/// Urai lirik format LRC menjadi baris-baris bertanda waktu (murni, diuji unit).
/// Mengembalikan null bila kurang dari dua baris bertanda waktu — teks seperti
/// itu bukan lirik tersinkron dan pemanggil memakai jalur polos.
/// Tag [offset:±ms]: nilai positif menggeser lirik tampil LEBIH AWAL.
List<LyricsLine>? parseLrc(String text) {
  var offsetMs = 0;
  final om = _offsetRe.firstMatch(text);
  if (om != null) offsetMs = int.tryParse(om.group(1)!) ?? 0;
  final out = <LyricsLine>[];
  for (final raw in text.split('\n')) {
    final stamps = _tsRe.allMatches(raw).toList();
    if (stamps.isEmpty) continue;
    final lineText = raw.replaceAll(_tsRe, '').trim();
    for (final m in stamps) {
      final min = int.parse(m.group(1)!);
      final sec = int.parse(m.group(2)!);
      var ms = 0;
      final frac = m.group(3);
      if (frac != null) ms = int.parse(frac.padRight(3, '0'));
      final at = Duration(minutes: min, seconds: sec, milliseconds: ms) - Duration(milliseconds: offsetMs);
      out.add(LyricsLine(at.isNegative ? Duration.zero : at, lineText));
    }
  }
  out.sort((a, b) => a.at.compareTo(b.at));
  // Runtuhkan baris kosong berurutan (jeda instrumental cukup satu penanda).
  final collapsed = <LyricsLine>[];
  for (final l in out) {
    if (l.text.isEmpty && collapsed.isNotEmpty && collapsed.last.text.isEmpty) continue;
    collapsed.add(l);
  }
  return collapsed.length >= 2 ? collapsed : null;
}

/// Nama artis utama dari byline: "Arctic Monkeys • 16M views" → "Arctic Monkeys";
/// "A, B" → "A". LRCLIB mencocokkan per nama artis utama.
String primaryArtistName(String artistNames) {
  var s = artistNames.split('•').first.trim();
  s = s.split(',').first.trim();
  return s;
}

/// Judul dibersihkan untuk percobaan kedua: buang kurung/bracket & embel-embel video.
String cleanedSongTitle(String title) {
  var s = title.replaceAll(RegExp(r'\([^)]*\)'), ' ').replaceAll(RegExp(r'\[[^\]]*\]'), ' ');
  s = s.replaceAll(RegExp(r'\s+-\s+(official|music|lyric|audio|video).*$', caseSensitive: false), ' ');
  return s.replaceAll(RegExp(r'\s+'), ' ').trim();
}

String _normMatch(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9 ]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

/// Lirik tersinkron dari LRCLIB (F2, PETA-JALAN butir 2) — API publik tanpa
/// kunci. Hasil (positif maupun negatif) tercache lokal; negatif kedaluwarsa
/// 7 hari agar katalog yang bertumbuh tetap bisa ditemukan lagi.
class LyricsService {
  final AppDb db;
  final Dio _dio;
  LyricsService(this.db, {Dio? dio}) : _dio = dio ?? Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 6), receiveTimeout: const Duration(seconds: 10),
      headers: {'User-Agent': 'Clai/1.0.0 ( https://github.com/Riyanzakaria/clai )', 'Accept': 'application/json'}));

  static const _negativeTtl = Duration(days: 7);

  Future<LyricsData?> getLyrics(Track t, {bool forceRefresh = false}) async {
    if (!forceRefresh) {
      final c = await db.lyricsCache(t.key);
      if (c != null) {
        final found = (c['found'] as int) == 1;
        final age = DateTime.now().millisecondsSinceEpoch - (c['fetched_at'] as int);
        if (found || age < _negativeTtl.inMilliseconds) {
          if (!found) return null; // negatif tercache yang masih segar
          final syncedText = c['synced'] as String?;
          final plainText = c['plain'] as String?;
          return LyricsData(
            lines: syncedText == null ? null : parseLrc(syncedText),
            plain: plainText,
            // Baris "ditemukan" tanpa teks apa pun hanya mungkin dari trek instrumental.
            instrumental: syncedText == null && plainText == null,
            source: 'cache',
          );
        }
      }
    }
    try {
      final data = await _fetchLrclib(t);
      if (data == null) {
        await db.saveLyricsCache(t.key, source: 'lrclib', found: false);
        return null;
      }
      await db.saveLyricsCache(t.key,
          synced: data.$2, plain: data.$3, source: 'lrclib', found: true);
      return LyricsData(lines: data.$1, plain: data.$3, instrumental: data.$4, source: 'LRCLIB');
    } catch (e) {
      // Jaringan gagal ≠ tidak ditemukan: JANGAN cache negatif; UI membedakan
      // "tidak ditemukan" dari "tidak dapat memeriksa" lewat nilai khusus ini.
      Observability.instance.log('lirik-gagal', e.toString());
      return const LyricsData(source: 'error');
    }
  }

  /// (baris tersinkron, teks LRC mentah, teks polos, instrumental)
  Future<(List<LyricsLine>?, String?, String?, bool)?> _fetchLrclib(Track t) async {
    final artist = primaryArtistName(t.artistNames);
    final attempts = <String>[t.title, cleanedSongTitle(t.title)];
    for (final title in attempts) {
      if (title.isEmpty) continue;
      final got = await _getExact(title, artist, t);
      if (got != null) return got;
    }
    // Cadangan: pencarian — pilih kandidat berdurasi terdekat yang judulnya cocok.
    final firstTitle = attempts.firstWhere((s) => s.isNotEmpty, orElse: () => t.title);
    final candidates = await _search(firstTitle, artist);
    (List<LyricsLine>?, String?, String?, bool)? best;
    var bestScore = double.infinity;
    for (final c in candidates) {
      final syncedText = c['syncedLyrics'] as String?;
      final plain = c['plainLyrics'] as String?;
      if (syncedText == null && plain == null) continue;
      if (_normMatch(c['trackName'] as String? ?? '') != _normMatch(firstTitle)) continue;
      final durSec = (c['duration'] as num?)?.toDouble();
      var score = 100000.0;
      if (durSec != null && t.duration != null) score = (durSec * 1000 - t.duration!.inMilliseconds).abs().toDouble();
      if (syncedText != null) score -= 500; // utamakan yang tersinkron pada skor setara
      if (score < bestScore) {
        bestScore = score;
        best = (syncedText == null ? null : parseLrc(syncedText), syncedText, plain, c['instrumental'] == true);
      }
    }
    return best;
  }

  Future<(List<LyricsLine>?, String?, String?, bool)?> _getExact(String title, String artist, Track t) async {
    final res = await _dio.get<Map<String, dynamic>>('https://lrclib.net/api/get',
        queryParameters: {
          'track_name': title, 'artist_name': artist,
          if (t.albumTitle != null && t.albumTitle!.isNotEmpty) 'album_name': t.albumTitle,
          if (t.duration != null) 'duration': t.duration!.inSeconds,
        },
        options: Options(validateStatus: (s) => s != null && s < 500));
    if (res.statusCode != 200 || res.data == null) return null;
    final syncedText = res.data!['syncedLyrics'] as String?;
    final plain = res.data!['plainLyrics'] as String?;
    final instrumental = res.data!['instrumental'] == true;
    if (syncedText == null && plain == null && !instrumental) return null;
    return (syncedText == null ? null : parseLrc(syncedText), syncedText, plain, instrumental);
  }

  Future<List<Map<String, dynamic>>> _search(String title, String artist) async {
    final res = await _dio.get<List<dynamic>>('https://lrclib.net/api/search',
        queryParameters: {'track_name': title, 'artist_name': artist},
        options: Options(validateStatus: (s) => s != null && s < 500));
    if (res.statusCode != 200 || res.data == null) return const [];
    return [for (final e in res.data!) if (e is Map) e.cast<String, dynamic>()];
  }
}
