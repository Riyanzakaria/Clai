import 'dart:math' as math;

import 'models.dart';

/// Peringkat personal CAMPURAN (F2.5, keputusan pemilik 25–26 Okt 2026):
/// skor kemutakhiran dengan peluruhan ±30 hari, DITOPANG lantai peringkat
/// sepanjang masa.
///
/// Setiap peristiwa putar menyumbang bobot menurut umurnya:
///   bobot = max(2^(−umurHari/30), 0.25)
/// Artinya: putar hari ini bernilai ~1; putar 30 hari lalu 0.5; 60 hari lalu
/// 0.25; dan sesudah itu TIDAK pernah turun lagi di bawah 0.25 — seperempat
/// bobot adalah lantai permanen dari setiap putar sepanjang masa. Akibatnya:
/// - Trek lama yang sangat sering diputar (banyak putar × lantai 0.25)
///   tidak tenggelam oleh trek baru yang hanya diputar sekali-dua kali.
/// - Trek baru yang SEDANG PANAS (banyak putar segar bernilai ~1) bisa
///   menyalip trek lama begitu volume segarnya melewati lantai akumulatif
///   trek lama.
/// - Menambah putar tidak pernah menurunkan skor (monoton).
///
/// Murni & teruji unit (personal_rank_test).
const double kHybridHalfLifeDays = 30.0;
const double kHybridFloorPerPlay = 0.25;

/// Bobot satu peristiwa putar berumur [ageMs] milidetik.
double hybridPlayWeight(int ageMs) {
  if (ageMs <= 0) return 1.0;
  final ageDays = ageMs / Duration.millisecondsPerDay;
  final decayed = math.pow(0.5, ageDays / kHybridHalfLifeDays).toDouble();
  return decayed < kHybridFloorPerPlay ? kHybridFloorPerPlay : decayed;
}

/// Skor campuran satu trek dari daftar cap waktu putarnya (ms epoch).
double hybridPlayScore(Iterable<int> startedAtsMs, int nowMs) {
  var s = 0.0;
  for (final t in startedAtsMs) {
    s += hybridPlayWeight(nowMs - t);
  }
  return s;
}

/// Skor campuran per trek dari peta cap waktu putar.
Map<TrackKey, double> hybridTrackScores(
  Map<TrackKey, List<int>> playsByTrack,
  int nowMs,
) {
  return {
    for (final e in playsByTrack.entries)
      e.key: hybridPlayScore(e.value, nowMs),
  };
}

/// Perbandingan peringkat campuran: skor lebih tinggi dulu; seri diputus
/// hitungan sepanjang masa (lebih banyak dulu), lalu putar terakhir
/// (lebih baru dulu). Mengembalikan <0 bila A di atas B.
int compareHybridRank({
  required double scoreA,
  required int countA,
  required int lastPlayedA,
  required double scoreB,
  required int countB,
  required int lastPlayedB,
}) {
  final byScore = scoreB.compareTo(scoreA);
  if (byScore != 0) return byScore;
  final byCount = countB.compareTo(countA);
  if (byCount != 0) return byCount;
  return lastPlayedB.compareTo(lastPlayedA);
}
