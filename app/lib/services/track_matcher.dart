import '../data/app_db.dart';
import '../domain/models.dart';
import '../providers/music_provider.dart';
import 'lyrics_service.dart' show primaryArtistName;

/// Normalisasi teks untuk pencocokan antar-sumber: huruf kecil, buang isi
/// kurung/bracket, potong "feat./ft.", sisakan huruf-angka.
String normalizeMatchText(String s) {
  var t = s.toLowerCase();
  t = t.replaceAll(RegExp(r'\([^)]*\)'), ' ');
  t = t.replaceAll(RegExp(r'\[[^\]]*\]'), ' ');
  t = t.replaceAll(RegExp(r'\s+(feat\.?|ft\.?)\s+.*$'), ' ');
  t = t.replaceAll(RegExp(r'[^a-z0-9 ]'), ' ');
  return t.replaceAll(RegExp(r'\s+'), ' ').trim();
}

Set<String> _tokens(String s) => normalizeMatchText(s).split(' ').where((w) => w.isNotEmpty).toSet();

/// Kemiripan judul (Jaccard token + bonus kandung penuh): 0..1.
double titleSimilarity(String a, String b) {
  final na = normalizeMatchText(a), nb = normalizeMatchText(b);
  if (na.isEmpty || nb.isEmpty) return 0;
  if (na == nb) return 1;
  final ta = _tokens(a), tb = _tokens(b);
  final inter = ta.intersection(tb).length;
  final union = ta.union(tb).length;
  var score = union == 0 ? 0.0 : inter / union;
  if (na.contains(nb) || nb.contains(na)) score = (score + 0.25).clamp(0, 1);
  return score;
}

/// Kemiripan artis: 1 bila nama utama salah satu terkandung di byline lain.
double artistSimilarity(String a, String b) {
  final na = normalizeMatchText(primaryArtistName(a));
  final nb = normalizeMatchText(b);
  if (na.isEmpty || nb.isEmpty) return 0;
  if (nb.contains(na) || na == nb) return 1;
  final ta = _tokens(a), tb = _tokens(b);
  final union = ta.union(tb).length;
  return union == 0 ? 0 : ta.intersection(tb).length / union;
}

/// Skor total kandidat (0..1): judul dominan, artis kuat, durasi penopang.
double matchScore({required String srcTitle, required String srcArtist, required Duration? srcDuration,
    required Track candidate}) {
  final title = titleSimilarity(srcTitle, candidate.title);
  final artist = artistSimilarity(srcArtist, candidate.artistNames);
  var durScore = 0.5; // netral bila salah satu durasi tak diketahui
  if (srcDuration != null && candidate.duration != null) {
    final delta = (srcDuration.inMilliseconds - candidate.duration!.inMilliseconds).abs();
    durScore = (1 - (delta / 10000)).clamp(0, 1).toDouble();
  }
  return 0.55 * title + 0.30 * artist + 0.15 * durScore;
}

/// Ambang terima cocok: di bawah ini trek dinyatakan TIDAK tercocokkan secara
/// jujur — lebih baik kosong daripada memutar lagu yang salah.
const kMatchThreshold = 0.62;

/// Pencocok trek Spotify → audio YouTube Music (F2 butir 4): pencarian yang
/// ada + penilaian kemiripan. Hasil positif & negatif tercache di
/// provider_matches (negatif 30 hari — katalog YTM bisa berubah).
class TrackMatcher {
  final MusicProvider ytm;
  final AppDb db;
  TrackMatcher(this.ytm, this.db);

  static const _negativeTtl = Duration(days: 30);

  Future<Track?> match(Track src, {bool forceRetry = false}) async {
    if (!forceRetry) {
      final cached = await db.providerMatch('spotify', src.id);
      if (cached != null) {
        if (cached.status == 'matched' && cached.targetTrackId != null) {
          final t = await db.trackByKey(TrackKey('ytmusic', cached.targetTrackId!));
          if (t != null) return t;
        }
        if (cached.status == 'unmatched' &&
            DateTime.now().millisecondsSinceEpoch - cached.checkedAt < _negativeTtl.inMilliseconds) {
          return null;
        }
      }
    }
    final artist = primaryArtistName(src.artistNames);
    final queries = <String>['${src.title} $artist', src.title];
    Track? best;
    var bestScore = 0.0;
    final seenQuery = <String>{};
    for (final q in queries) {
      if (!seenQuery.add(q)) continue;
      final SearchResults res;
      try {
        res = await ytm.search(q);
      } catch (_) {
        continue; // satu kueri gagal tidak menggagalkan kueri lain
      }
      for (final cand in res.songs) {
        final s = matchScore(srcTitle: src.title, srcArtist: src.artistNames,
            srcDuration: src.duration, candidate: cand);
        if (s > bestScore) { bestScore = s; best = cand; }
      }
      if (bestScore >= 0.9) break; // sudah sangat yakin — hemat panggilan
    }
    if (best != null && bestScore >= kMatchThreshold) {
      await db.saveProviderMatch('spotify', src.id, 'ytmusic', targetTrackId: best.id, status: 'matched');
      return best;
    }
    await db.saveProviderMatch('spotify', src.id, 'ytmusic', status: 'unmatched');
    return null;
  }
}
