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

/// Bobot selera (Ruang Kendali Selera, Ronde 8074): campuran antara
/// hitungan seumur (setiap putar bernilai 1) dan peringkat campuran F2.5,
/// diatur [recentEmphasis] dalam 0..1 — ujung "Terkini" pada slider.
/// e = 1 → [hybridPlayWeight] PERSIS (bawaan; perilaku F2.5 tidak berubah
/// sampai pengguna sendiri menggeser slider). e = 0 → peringkat hitungan
/// seumur murni. Di antara keduanya: interpolasi linear per peristiwa.
double tastePlayWeight(int ageMs, double recentEmphasis) {
  final e = recentEmphasis.clamp(0.0, 1.0).toDouble();
  if (e == 1.0) return hybridPlayWeight(ageMs);
  if (e == 0.0) return 1.0;
  return (1 - e) + e * hybridPlayWeight(ageMs);
}

/// Skor selera satu trek dari daftar cap waktu putarnya (ms epoch).
double tastePlayScore(Iterable<int> startedAtsMs, int nowMs, double e) {
  var s = 0.0;
  for (final t in startedAtsMs) {
    s += tastePlayWeight(nowMs - t, e);
  }
  return s;
}

/// Skor selera per trek dari peta cap waktu putar.
Map<TrackKey, double> tasteTrackScores(
  Map<TrackKey, List<int>> playsByTrack,
  int nowMs,
  double recentEmphasis,
) {
  return {
    for (final e in playsByTrack.entries)
      e.key: tastePlayScore(e.value, nowMs, recentEmphasis),
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
