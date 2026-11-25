import 'package:clai/player/repeat_detector.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ronde 8087 — detektor ulang-trek-sama + tabel kebenaran penjaga.
/// Logika murni: sampel disuapkan dengan jam dinding palsu, persis gaya
/// uji StallWatchdog di sapuan_kepatuhan_test.dart.
void main() {
  DateTime at(int ms) => DateTime.fromMillisecondsSinceEpoch(ms);

  RepeatDecision feed(
    RepeatDetector d, {
    String key = 'ytmusic:a',
    int? periodIndex = 0,
    required int positionMs,
    int? durationMs = 200000,
    bool playing = true,
    bool completed = false,
    bool loopOne = false,
    required int t,
  }) => d.feed(
    key: key,
    periodIndex: periodIndex,
    positionMs: positionMs,
    durationMs: durationMs,
    playing: playing,
    completed: completed,
    loopOne: loopOne,
    now: at(t),
  );

  group('Ronde 8087 — tanda ulang', () {
    test('menembak SEKALI sesudah persenjataan di zona akhir', () {
      final d = RepeatDetector();
      expect(
        feed(d, positionMs: 199000, t: 0),
        RepeatDecision.none,
        reason: 'sampel zona akhir hanya mempersenjatai',
      );
      expect(feed(d, positionMs: 500, t: 500), RepeatDecision.repeat);
      expect(
        feed(d, positionMs: 500, t: 1000),
        RepeatDecision.none,
        reason: 'satu episode satu tembakan',
      );
    });

    test('batal oleh perubahan indeks periode', () {
      final d = RepeatDetector();
      feed(d, positionMs: 199000, periodIndex: 0, t: 0);
      expect(
        feed(d, positionMs: 500, periodIndex: 1, t: 500),
        RepeatDecision.none,
        reason:
            'indeks berubah = transisi native yang sah, termasuk '
            'trek-sama-berturut-turut',
      );
    });

    test('batal oleh penanda mulai-ulang-sah', () {
      final d = RepeatDetector();
      feed(d, positionMs: 199000, t: 0);
      d.noteLegitRestart();
      expect(feed(d, positionMs: 500, t: 500), RepeatDecision.none);
    });

    test('penanda sah yang tiba sebelum persenjataan tidak membatalkan '
        'episode masa depan', () {
      final d = RepeatDetector();
      d.noteLegitRestart();
      feed(d, positionMs: 100000, t: 0); // penanda gugur di sini
      feed(d, positionMs: 199000, t: 500); // persenjataan segar
      expect(feed(d, positionMs: 500, t: 1000), RepeatDecision.repeat);
    });

    test('lumpuh total oleh loopOne + keadaan bersih', () {
      final d = RepeatDetector();
      feed(d, positionMs: 199000, t: 0); // persenjatai
      expect(
        feed(d, positionMs: 199500, loopOne: true, t: 500),
        RepeatDecision.none,
      );
      expect(
        feed(d, positionMs: 500, t: 1000),
        RepeatDecision.none,
        reason: 'loopOne membersihkan persenjataan yang sudah ada',
      );
      // Dan loop yang sah memang mengulang tanpa pernah menembak:
      final d2 = RepeatDetector();
      feed(d2, positionMs: 199000, loopOne: true, t: 0);
      expect(
        feed(d2, positionMs: 500, loopOne: true, t: 500),
        RepeatDecision.none,
      );
    });

    test('tanpa persenjataan (reset dari tengah trek) tidak menembak', () {
      final d = RepeatDetector();
      feed(d, positionMs: 100000, t: 0);
      expect(feed(d, positionMs: 500, t: 500), RepeatDecision.none);
    });

    test('trek pendek <6000 md tidak dipersenjatai', () {
      final d = RepeatDetector();
      feed(d, positionMs: 4900, durationMs: 5000, t: 0);
      expect(
        feed(d, positionMs: 100, durationMs: 5000, t: 500),
        RepeatDecision.none,
        reason: 'zona akhir & zona reset akan tumpang tindih',
      );
    });

    test('reset() membersihkan episode', () {
      final d = RepeatDetector();
      feed(d, positionMs: 199000, t: 0);
      d.reset();
      expect(feed(d, positionMs: 500, t: 500), RepeatDecision.none);
    });
  });

  group('Ronde 8087 — tanda parkir', () {
    test('menembak sesudah tenggang 2000 md, tidak sebelum', () {
      final d = RepeatDetector();
      expect(feed(d, positionMs: 199900, t: 0), RepeatDecision.none);
      expect(feed(d, positionMs: 199900, t: 1000), RepeatDecision.none);
      expect(feed(d, positionMs: 199900, t: 1999), RepeatDecision.none);
      expect(feed(d, positionMs: 199900, t: 2000), RepeatDecision.park);
      expect(
        feed(d, positionMs: 199900, t: 4000),
        RepeatDecision.none,
        reason: 'satu episode satu tembakan',
      );
    });

    test('keadaan completed juga parkir (parkir varian Sway)', () {
      final d = RepeatDetector();
      feed(d, positionMs: 200000, playing: false, completed: true, t: 0);
      expect(
        feed(d, positionMs: 200000, playing: false, completed: true, t: 2000),
        RepeatDecision.park,
      );
    });

    test('posisi MELEWATI durasi tetap dihitung parkir', () {
      final d = RepeatDetector();
      feed(d, positionMs: 200005, t: 0); // durasi 200000 + 5 (bukti bangku)
      expect(feed(d, positionMs: 200005, t: 2000), RepeatDecision.park);
    });

    test('batal oleh jeda disengaja (tidak playing, tidak completed)', () {
      final d = RepeatDetector();
      feed(d, positionMs: 199900, t: 0);
      feed(d, positionMs: 199900, playing: false, t: 1000);
      // Tenggang mulai dari nol lagi saat playing kembali:
      feed(d, positionMs: 199900, t: 3000);
      expect(
        feed(d, positionMs: 199900, t: 4000),
        RepeatDecision.none,
        reason: 'baru 1000 md kontinu sejak jeda batal',
      );
      expect(feed(d, positionMs: 199900, t: 5000), RepeatDecision.park);
    });

    test('batal oleh perpindahan kunci sebelum tenggang', () {
      final d = RepeatDetector();
      feed(d, key: 'ytmusic:a', positionMs: 199900, t: 0);
      feed(d, key: 'ytmusic:b', positionMs: 199900, t: 1000);
      expect(
        feed(d, key: 'ytmusic:b', positionMs: 199900, t: 2500),
        RepeatDecision.none,
        reason: 'kunci baru baru parkir 1500 md',
      );
      expect(
        feed(d, key: 'ytmusic:b', positionMs: 199900, t: 3000),
        RepeatDecision.park,
      );
    });

    test('keluar dari pita toleransi membatalkan akumulasi', () {
      final d = RepeatDetector();
      feed(d, positionMs: 199900, t: 0);
      feed(d, positionMs: 150000, t: 1000); // posisi maju/berpindah
      feed(d, positionMs: 199900, t: 1500); // masuk pita lagi: dari nol
      expect(feed(d, positionMs: 199900, t: 3000), RepeatDecision.none);
      expect(feed(d, positionMs: 199900, t: 3500), RepeatDecision.park);
    });
  });

  group('Ronde 8087 — jeda dingin', () {
    test('menahan tembakan kedua; persenjataan segar mengizinkan lagi', () {
      final d = RepeatDetector();
      feed(d, positionMs: 199000, t: 0);
      expect(feed(d, positionMs: 500, t: 500), RepeatDecision.repeat);
      // Putaran berikutnya mencoba mempersenjatai di dalam jeda dingin
      // (tembakan 500 + 5000 = 5500): ditahan seluruhnya.
      feed(d, positionMs: 199000, t: 1000);
      expect(
        feed(d, positionMs: 500, t: 1500),
        RepeatDecision.none,
        reason: 'masih jeda dingin — persenjataan di dalamnya tak sah',
      );
      // Sesudah jeda dingin: persenjataan segar menembak lagi.
      feed(d, positionMs: 199000, t: 6000);
      expect(feed(d, positionMs: 500, t: 6500), RepeatDecision.repeat);
    });
  });

  group('Ronde 8087 — advanceVerified (keputusan 7)', () {
    test('kunci pemain berpindah → terverifikasi', () {
      expect(
        advanceVerified(
          playerKey: 'ytmusic:b',
          engineKey: 'ytmusic:a',
          fromKey: 'ytmusic:a',
          playerParkedAtEnd: false,
        ),
        isTrue,
      );
    });

    test('kunci pemain masih trek asal → belum berpindah', () {
      expect(
        advanceVerified(
          playerKey: 'ytmusic:a',
          engineKey: 'ytmusic:b',
          fromKey: 'ytmusic:a',
          playerParkedAtEnd: false,
        ),
        isFalse,
        reason: 'mesin boleh sudah bergerak — pemain yang menentukan',
      );
    });

    test('crossfade: kunci mesin berpindah & tidak parkir → terverifikasi', () {
      expect(
        advanceVerified(
          playerKey: null,
          engineKey: 'ytmusic:b',
          fromKey: 'ytmusic:a',
          playerParkedAtEnd: false,
        ),
        isTrue,
      );
    });

    test('crossfade: kunci mesin berpindah TETAPI pemain parkir di ujung '
        'trek asal → belum berpindah (celah parkir 12:24)', () {
      expect(
        advanceVerified(
          playerKey: null,
          engineKey: 'ytmusic:b',
          fromKey: 'ytmusic:a',
          playerParkedAtEnd: true,
        ),
        isFalse,
      );
    });

    test('crossfade: kunci mesin belum berpindah → belum berpindah', () {
      expect(
        advanceVerified(
          playerKey: null,
          engineKey: 'ytmusic:a',
          fromKey: 'ytmusic:a',
          playerParkedAtEnd: false,
        ),
        isFalse,
      );
    });

    test('tak ada kunci yang bisa dibaca → belum terverifikasi', () {
      expect(
        advanceVerified(
          playerKey: null,
          engineKey: null,
          fromKey: 'ytmusic:a',
          playerParkedAtEnd: false,
        ),
        isFalse,
      );
    });

    test('parkir di ujung meniadakan kunci pemain yang tampak berpindah', () {
      expect(
        advanceVerified(
          playerKey: 'ytmusic:b',
          engineKey: 'ytmusic:b',
          fromKey: 'ytmusic:a',
          playerParkedAtEnd: true,
        ),
        isFalse,
      );
    });
  });
}
