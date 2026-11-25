import 'models.dart';

// Cermin Selera (Ruang Kendali Selera, Ronde 8074) — matematika MURNI
// di atas cap waktu `playback_events`. Keputusan terkunci BEDAH-F3 #3:
// tulang punggung cermin = artis teratas + pola jam/hari + keseimbangan
// terkini-vs-seumur, MURNI dari cap waktu peristiwa putar lokal. Genre
// katalog DITOLAK; genre hanya tag artis MusicBrainz (lapis layanan),
// tidak pernah masuk hitungan di sini.

/// Satu baris pengecualian rekomendasi (tabel `taste_exclusions`).
/// [kind] = 'artist' | 'track'. Untuk artis, [key] adalah byline artis
/// persis seperti tampil; untuk trek, [key] adalah kunci trek
/// 'providerId␟providerTrackId' (lihat [trackExclusionKey]).
class TasteExclusion {
  final String kind;
  final String key;
  final String label;
  final int createdAt;
  const TasteExclusion({
    required this.kind,
    required this.key,
    required this.label,
    required this.createdAt,
  });

  bool get isArtist => kind == 'artist';

  Map<String, Object?> toRow() => {
        'kind': kind,
        'key': key,
        'label': label,
        'created_at': createdAt,
      };

  factory TasteExclusion.fromRow(Map<String, Object?> r) => TasteExclusion(
        kind: (r['kind'] as String?) ?? '',
        key: (r['key'] as String?) ?? '',
        label: (r['label'] as String?) ?? '',
        createdAt: (r['created_at'] as int?) ?? 0,
      );
}

/// Kunci pengecualian untuk satu trek.
String trackExclusionKey(String providerId, String providerTrackId) =>
    '$providerId\u001f$providerTrackId';

/// Normalisasi nama artis untuk pencocokan pengecualian.
String normalizeArtistName(String s) => s.trim().toLowerCase();

/// Nama artis PRIMER dari byline (bagian pertama sebelum , atau &).
String primaryArtistNameOf(String artistNames) =>
    artistNames.split(RegExp(r'[,&]')).first.trim();

/// Apakah byline [artistNames] terkena pengecualian artis [excludedKey]
/// (byline yang disimpan saat pengecualian dibuat)? Cocok bila byline
/// penuh sama, ATAU artis primernya sama — trek kolaborasi yang artis
/// pertamanya yang dikeluarkan ikut tersaring.
bool artistExclusionMatches(String artistNames, String excludedKey) {
  final full = normalizeArtistName(artistNames);
  final key = normalizeArtistName(excludedKey);
  if (key.isEmpty) return false;
  if (full == key) return true;
  return normalizeArtistName(primaryArtistNameOf(artistNames)) == key;
}

/// Apakah byline ini cocok dengan SALAH SATU kunci artis yang dikeluarkan.
bool anyArtistExclusionMatches(
    String artistNames, Set<String> excludedArtistKeys) {
  for (final k in excludedArtistKeys) {
    if (artistExclusionMatches(artistNames, k)) return true;
  }
  return false;
}

/// Apakah byline ini dikeluarkan (ada pengecualian artis yang cocok)?
bool isArtistExcluded(String artistNames, List<TasteExclusion> exclusions) =>
    exclusions.any(
        (e) => e.isArtist && artistExclusionMatches(artistNames, e.key));

/// Apakah trek ini dikeluarkan — langsung per trek, atau lewat artisnya?
bool isTrackExcluded(Track t, List<TasteExclusion> exclusions) {
  final tk = trackExclusionKey(t.providerId, t.id);
  for (final e in exclusions) {
    if (e.isArtist) {
      if (artistExclusionMatches(t.artistNames, e.key)) return true;
    } else if (e.key == tk) {
      return true;
    }
  }
  return false;
}

/// Lima bagian hari (jam lokal) untuk pola mendengar.
enum Daypart { diniHari, pagi, siang, sore, malam }

Daypart daypartOfHour(int hour) {
  if (hour < 5) return Daypart.diniHari;
  if (hour < 11) return Daypart.pagi;
  if (hour < 15) return Daypart.siang;
  if (hour < 19) return Daypart.sore;
  return Daypart.malam;
}

/// Hasil hitung cermin dari daftar peristiwa putar.
class TasteMirrorData {
  final int totalPlays;
  final int totalListenedMs;

  /// Putar dalam 30 hari terakhir (jendela "terkini").
  final int recentPlays;
  final int recentListenedMs;

  /// Histogram jam lokal 0..23.
  final List<int> hourCounts;

  /// Histogram hari, Senin = 0 … Minggu = 6.
  final List<int> dayCounts;

  const TasteMirrorData({
    required this.totalPlays,
    required this.totalListenedMs,
    required this.recentPlays,
    required this.recentListenedMs,
    required this.hourCounts,
    required this.dayCounts,
  });

  static const empty = TasteMirrorData(
    totalPlays: 0,
    totalListenedMs: 0,
    recentPlays: 0,
    recentListenedMs: 0,
    hourCounts: <int>[],
    dayCounts: <int>[],
  );

  /// Bagian riwayat yang "cukup" untuk cermin jujur — di bawah ini layar
  /// menampilkan keadaan belum-terbentuk, bukan angka karangan.
  static const int minPlaysForMirror = 10;

  bool get isEmpty => totalPlays == 0;
  bool get isThin => totalPlays < minPlaysForMirror;

  /// Porsi putar terkini (0..1) dari seluruh riwayat.
  double get recentShare => totalPlays == 0 ? 0 : recentPlays / totalPlays;

  /// Bagian hari terpadat; null bila belum ada putar.
  Daypart? get peakDaypart {
    if (totalPlays == 0) return null;
    final buckets = <Daypart, int>{for (final d in Daypart.values) d: 0};
    for (var h = 0; h < hourCounts.length; h++) {
      buckets[daypartOfHour(h)] = buckets[daypartOfHour(h)]! + hourCounts[h];
    }
    Daypart? best;
    var bestCount = -1;
    for (final d in Daypart.values) {
      if (buckets[d]! > bestCount) {
        bestCount = buckets[d]!;
        best = d;
      }
    }
    return best;
  }

  /// Indeks hari terpadat (Senin = 0); null bila belum ada putar.
  int? get peakDayIndex {
    if (totalPlays == 0) return null;
    var best = 0;
    for (var i = 1; i < dayCounts.length; i++) {
      if (dayCounts[i] > dayCounts[best]) best = i;
    }
    return best;
  }
}

/// Hitung cermin dari peristiwa putar mentah. [events] = daftar
/// (startedAt ms epoch, listenedMs). Waktu lokal perangkat yang berlaku
/// (pola mendengar adalah pola jam dinding pengguna).
TasteMirrorData computeTasteMirror({
  required Iterable<({int startedAt, int listenedMs})> events,
  required int nowMs,
}) {
  final hours = List<int>.filled(24, 0);
  final days = List<int>.filled(7, 0);
  var total = 0;
  var listened = 0;
  var recent = 0;
  var recentListened = 0;
  final recentCutoff = nowMs - const Duration(days: 30).inMilliseconds;
  for (final e in events) {
    total++;
    listened += e.listenedMs;
    final dt = DateTime.fromMillisecondsSinceEpoch(e.startedAt);
    hours[dt.hour]++;
    days[dt.weekday - 1]++; // DateTime.weekday: Senin = 1 … Minggu = 7
    if (e.startedAt >= recentCutoff) {
      recent++;
      recentListened += e.listenedMs;
    }
  }
  return TasteMirrorData(
    totalPlays: total,
    totalListenedMs: listened,
    recentPlays: recent,
    recentListenedMs: recentListened,
    hourCounts: hours,
    dayCounts: days,
  );
}
