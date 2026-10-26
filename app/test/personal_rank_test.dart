import 'package:clai/domain/personal_rank.dart';
import 'package:flutter_test/flutter_test.dart';

/// Uji fungsi peringkat campuran F2.5 (kasus wajib dari komposisi terkunci):
/// lama-kuat vs baru-panas vs baru-sekali.
void main() {
  const dayMs = Duration.millisecondsPerDay;
  final now = DateTime(2026, 10, 26, 12).millisecondsSinceEpoch;

  List<int> plays(int count, int ageDays) =>
      List.generate(count, (i) => now - ageDays * dayMs - i * 1000);

  group('bobot peluruhan + lantai', () {
    test('putar hari ini bernilai 1', () {
      expect(hybridPlayWeight(0), 1.0);
      expect(hybridPlayWeight(3600 * 1000), closeTo(0.997, 0.01));
    });
    test('30 hari = 0.5, 60 hari = 0.25', () {
      expect(hybridPlayWeight(30 * dayMs), closeTo(0.5, 0.001));
      expect(hybridPlayWeight(60 * dayMs), closeTo(0.25, 0.001));
    });
    test('sesudah 60 hari lantai 0.25 berlaku permanen', () {
      expect(hybridPlayWeight(90 * dayMs), 0.25);
      expect(hybridPlayWeight(365 * dayMs), 0.25);
      expect(hybridPlayWeight(3650 * dayMs), 0.25);
    });
  });

  group('kasus peringkat wajib', () {
    test('lama-kuat (40 putar, 100 hari lalu) mengalahkan baru-sekali', () {
      final lamaKuat = hybridPlayScore(plays(40, 100), now); // 40 × 0.25 = 10
      final baruSekali = hybridPlayScore(plays(1, 0), now); // ~1
      expect(lamaKuat, closeTo(10.0, 0.01));
      expect(lamaKuat, greaterThan(baruSekali));
    });

    test('baru-panas (15 putar minggu ini) menyalip lama-kuat', () {
      final lamaKuat = hybridPlayScore(plays(40, 100), now); // 10
      final baruPanas = hybridPlayScore(plays(15, 2), now); // ~14.3
      expect(baruPanas, greaterThan(lamaKuat));
    });

    test('baru-hangat saja (6 putar hari ini) BELUM menyalip lama-kuat', () {
      final lamaKuat = hybridPlayScore(plays(40, 100), now); // 10
      final baruHangat = hybridPlayScore(plays(6, 0), now); // ~6
      expect(baruHangat, lessThan(lamaKuat));
    });

    test('baru-sekali tidak pernah mengalahkan trek mapan mana pun', () {
      final sekali = hybridPlayScore(plays(1, 0), now);
      final mapanSedang = hybridPlayScore(plays(8, 45), now); // 8 × ~0.35
      expect(sekali, lessThan(mapanSedang));
      expect(sekali, lessThan(hybridPlayScore(plays(40, 100), now)));
    });

    test('monoton: menambah putar tidak pernah menurunkan skor', () {
      final dasar = plays(5, 10);
      final lebih = [...dasar, now - 3 * dayMs];
      expect(hybridPlayScore(lebih, now),
          greaterThan(hybridPlayScore(dasar, now)));
    });

    test('skor campuran nol untuk trek tanpa riwayat', () {
      expect(hybridPlayScore(const [], now), 0.0);
    });
  });

  group('pemutus seri', () {
    test('skor sama → hitungan sepanjang masa lebih besar menang', () {
      final c = compareHybridRank(
          scoreA: 5, countA: 20, lastPlayedA: 100,
          scoreB: 5, countB: 9, lastPlayedB: 999);
      expect(c, lessThan(0)); // A di atas B
    });
    test('skor & hitungan sama → putar terakhir lebih baru menang', () {
      final c = compareHybridRank(
          scoreA: 5, countA: 9, lastPlayedA: 100,
          scoreB: 5, countB: 9, lastPlayedB: 999);
      expect(c, greaterThan(0)); // B di atas A
    });
  });
}
