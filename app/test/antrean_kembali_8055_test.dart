import 'package:clai/domain/models.dart';
import 'package:clai/player/audio_handler.dart';
import 'package:clai/player/queue_engine.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ronde 8055 — regresi cacat navigasi antrean yang dilaporkan dari
/// perangkat: sesudah ketuk-lompat pada baris antrean (termasuk baris Putar
/// Otomatis), tombol Sebelumnya TIDAK kembali ke lagu yang berbunyi tepat
/// sebelum lompatan.
///
/// Akar terbukti (audit kode + bench emulator, builds/bukti-antrean-8055):
/// Mundur gapless dulu murni posisional di jendela sumber just_audio;
/// ketuk-lompat membangun ulang sumber berjangkar di trek tujuan sehingga
/// trek sebelumnya terdampar di luar jendela, walau engine.played mencatatnya.
/// Perbaikan: keputusan Mundur ≤ 3 dtk kini jatuh ke riwayat sesi bila
/// jendela tak memuat pendahulu (fungsi murni [gaplessPreviousStep]), dan
/// handler memulihkan trek itu lewat restorePlayed + bangun ulang.
///
/// Yang diuji di sini: fungsi keputusan + koreografi engine persis seperti
/// yang dijalankan handler (handler konkret menyentuh kanal platform —
/// kendala yang sama dicatat radio_header_a5_test). Sisi pemutar (bangun
/// ulang sumber) dibuktikan di bench emulator dengan koreografi yang sama.
void main() {
  Track t(String id) => Track(
      key: TrackKey('ytmusic', id),
      title: 'Lagu $id',
      artistNames: 'Artis A',
      duration: const Duration(minutes: 3),
      playableRef: id);

  /// Tiru _syncEngineTo handler untuk maju alami gapless satu langkah:
  /// current lama masuk riwayat sesi, kepala antrean efektif menjadi current.
  void majuAlami(QueueEngine e) {
    final old = e.current!;
    final next = e.effectiveQueue.first;
    if (e.manual.isNotEmpty && e.manual.first.key == next.key) {
      e.manual.removeAt(0);
    } else if (e.continuation.isNotEmpty &&
        e.continuation.first.key == next.key) {
      e.continuation.removeAt(0);
    } else if (e.autoplay.isNotEmpty && e.autoplay.first.key == next.key) {
      e.autoplay.removeAt(0);
    }
    e.played.add(old);
    e.current = next;
  }

  /// Efek engine dari Mundur ≤ 3 dtk pasca-8055 (kedua cabang — jendela dan
  /// riwayat — bermuara ke pemulihan yang sama di engine; bedanya hanya di
  /// pemutar: seek di dalam sumber vs bangun ulang).
  void mundur(QueueEngine e) {
    e.restorePlayed(e.played.length - 1);
  }

  group('gaplessPreviousStep — urutan keputusan Mundur (Ronde 8055)', () {
    test('pendahulu di jendela → langkah jendela (rantai murni tak berubah)',
        () {
      expect(
          gaplessPreviousStep(
              hasPreviousInWindow: true, hasSessionHistory: true),
          GaplessPreviousStep.windowPrevious);
      expect(
          gaplessPreviousStep(
              hasPreviousInWindow: true, hasSessionHistory: false),
          GaplessPreviousStep.windowPrevious);
    });

    test('jendela kosong + riwayat ada → langkah riwayat (perbaikan 8055)',
        () {
      expect(
          gaplessPreviousStep(
              hasPreviousInWindow: false, hasSessionHistory: true),
          GaplessPreviousStep.historyPrevious);
    });

    test('keduanya kosong → ulang trek berjalan (perilaku lama sesi baru)',
        () {
      expect(
          gaplessPreviousStep(
              hasPreviousInWindow: false, hasSessionHistory: false),
          GaplessPreviousStep.restartCurrent);
    });
  });

  group('koreografi engine — Mundur sesudah lompatan (Ronde 8055)', () {
    test('ketuk-lompat lalu Mundur kembali ke trek sebelum lompatan', () {
      final e = QueueEngine();
      final tracks = [t('1'), t('2'), t('3'), t('4'), t('5')];
      e.playContext(
          PlayContext(kind: 'album', label: 'A', tracks: tracks), 0);
      majuAlami(e); // current 2, riwayat [1]
      majuAlami(e); // current 3, riwayat [1, 2]
      expect(e.current!.id, '3');
      // Ketuk baris '5' di antrean: jumpTo mencatat trek keluar (3).
      e.jumpTo(t('5').key);
      expect(e.current!.id, '5');
      expect(e.played.map((x) => x.id), ['1', '2', '3']);
      // Sumber dibangun ulang berjangkar di 5 → jendela tanpa pendahulu;
      // Mundur jatuh ke riwayat dan WAJIB mendarat di 3.
      expect(
          gaplessPreviousStep(
              hasPreviousInWindow: false,
              hasSessionHistory: e.played.isNotEmpty),
          GaplessPreviousStep.historyPrevious);
      mundur(e);
      expect(e.current!.id, '3');
      expect(e.played.map((x) => x.id), ['1', '2']);
      // Maju lagi mengulang langkah yang sama: kepala lanjutan = 5.
      expect(e.continuation.first.id, '5');
    });

    test('ketuk baris Putar Otomatis lalu Mundur kembali ke trek sebelumnya',
        () {
      final e = QueueEngine();
      final tracks = [t('1'), t('2'), t('3')];
      e.playContext(
          PlayContext(kind: 'album', label: 'A', tracks: tracks), 0);
      e.appendAutoplay([t('a1'), t('a2')]);
      majuAlami(e); // current 2, riwayat [1]
      // Ketuk baris AUTO 'a1'.
      e.jumpTo(t('a1').key);
      expect(e.current!.id, 'a1');
      expect(e.played.map((x) => x.id), ['1', '2']);
      // Mundur lewat riwayat → trek sebelum lompatan (2), bukan mengulang a1.
      mundur(e);
      expect(e.current!.id, '2');
      expect(e.played.map((x) => x.id), ['1']);
      expect(e.continuation.first.id, 'a1');
    });

    test('lompat → Maju → Mundur → Mundur menembus titik lompatan', () {
      final e = QueueEngine();
      final tracks = [t('1'), t('2'), t('3'), t('4'), t('5'), t('6')];
      e.playContext(
          PlayContext(kind: 'album', label: 'A', tracks: tracks), 0);
      majuAlami(e); // X = 2, riwayat [1]
      final x = e.current!;
      expect(x.id, '2');
      e.jumpTo(t('4').key); // lompat ke Y = 4; riwayat [1, 2]
      expect(e.current!.id, '4');
      majuAlami(e); // Maju ke Z = 5; riwayat [1, 2, 4]
      expect(e.current!.id, '5');
      // Mundur #1 (pendahulu masih di jendela yang sama) → Y.
      mundur(e);
      expect(e.current!.id, '4');
      // Mundur #2: jendela hasil bangun ulang di Y tak memuat pendahulu —
      // riwayat menembus titik lompatan kembali ke X.
      expect(
          gaplessPreviousStep(
              hasPreviousInWindow: false,
              hasSessionHistory: e.played.isNotEmpty),
          GaplessPreviousStep.historyPrevious);
      mundur(e);
      expect(e.current!.id, x.id);
      expect(e.played.map((p) => p.id), ['1']);
      // Urutan maju pulih utuh dari X: 4, 5, 6.
      expect(e.continuation.map((p) => p.id), ['4', '5', '6']);
    });

    test('rantai Maju/Mundur murni tidak berubah; riwayat habis di awal sesi',
        () {
      final e = QueueEngine();
      final tracks = [t('1'), t('2'), t('3')];
      e.playContext(
          PlayContext(kind: 'album', label: 'A', tracks: tracks), 0);
      majuAlami(e);
      majuAlami(e); // current 3, riwayat [1, 2]
      mundur(e);
      expect(e.current!.id, '2');
      mundur(e);
      expect(e.current!.id, '1');
      expect(e.played, isEmpty);
      // Di awal sesi tak ada lagi yang bisa dipulihkan: keputusan handler
      // jatuh ke ulang-dari-awal, persis perilaku sebelum 8055.
      expect(
          gaplessPreviousStep(
              hasPreviousInWindow: false,
              hasSessionHistory: e.played.isNotEmpty),
          GaplessPreviousStep.restartCurrent);
      expect(e.continuation.map((x) => x.id), ['2', '3']);
    });
  });
}
