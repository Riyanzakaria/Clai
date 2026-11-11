import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:clai/player/queue_engine.dart' as qe;
import 'package:clai/ui/queue_screen.dart';
import 'package:clai/ui/shuffle_button_state.dart';
import 'package:clai/ui/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ronde 8051 — Antrian Redesign (keputusan pemilik 2026-11-10 20:42)
/// + tombol acak Player tiga keadaan jujur (cacat pemilik 20:40).
/// Mengunci: penomoran dua digit yang MENERUS antar seksi, posisi panel
/// Acak Cerdas di bawah panggung hero, kapsul ringkasan, dan pemetaan
/// mode acak → wujud + sasaran ketuk tombol Player.
void main() {
  group('penomoran antrean dua digit & menerus (Redesign 8051)', () {
    test('label dua digit: 1→01, 9→09, 10→10, 100→100 apa adanya', () {
      expect(rowNumberLabel(1, twoDigit: true), '01');
      expect(rowNumberLabel(9, twoDigit: true), '09');
      expect(rowNumberLabel(10, twoDigit: true), '10');
      expect(rowNumberLabel(100, twoDigit: true), '100');
    });

    test('label polos tidak berubah untuk pemanggil lain', () {
      expect(rowNumberLabel(1), '1');
      expect(rowNumberLabel(12), '12');
    });

    test('manual bernomor dari 1 mengikuti urutan terlihat', () {
      expect(
          queueVisibleNumber(
              section: 'manual',
              visibleManualCount: 3,
              positionInSection: 0),
          1);
      expect(
          queueVisibleNumber(
              section: 'manual',
              visibleManualCount: 3,
              positionInSection: 2),
          3);
    });

    test('lanjutan MENERUSKAN hitungan manual yang terlihat', () {
      // 3 baris manual terlihat → lanjutan mulai 04, bukan mengulang 01.
      expect(
          queueVisibleNumber(
              section: 'continuation',
              visibleManualCount: 3,
              positionInSection: 0),
          4);
      expect(
          queueVisibleNumber(
              section: 'continuation',
              visibleManualCount: 3,
              positionInSection: 1),
          5);
      // Tanpa manual terlihat, lanjutan mulai dari 1.
      expect(
          queueVisibleNumber(
              section: 'continuation',
              visibleManualCount: 0,
              positionInSection: 0),
          1);
    });

    test('putar otomatis tanpa nomor (saran mesin)', () {
      expect(
          queueVisibleNumber(
              section: 'autoplay',
              visibleManualCount: 3,
              positionInSection: 0),
          isNull);
    });
  });

  group('komposisi Antrian Redesign (sapuan sumber queue_screen)', () {
    final src = File('lib/ui/queue_screen.dart').readAsStringSync();

    test('panggung hero: wash pahlawan palet + judul display di atas kapsul & panel', () {
      expect(src, contains('AmbientSurfaceKind.hero'));
      expect(src, contains('displayStyle(22)'));
      final stageAt = src.indexOf('nowStage()');
      final capsuleAt = src.indexOf('KAPSUL ringkasan skala');
      final smartAt = src.indexOf('Panel ACAK CERDAS');
      expect(stageAt, greaterThan(-1));
      expect(capsuleAt, greaterThan(stageAt),
          reason: 'kapsul ringkasan di bawah panggung');
      expect(smartAt, greaterThan(capsuleAt),
          reason: 'panel Acak Cerdas di BAWAH panggung & kapsul');
    });

    test('kartu kaca SongRow lama untuk trek berjalan sudah pensiun', () {
      expect(src, isNot(contains('glassCurrent: true')));
    });

    test('baris antrean memakai nomor dua digit & baris AUTO redup', () {
      expect(src, contains('twoDigitNumber: number != null'));
      expect(src, contains('dimmed: auto'));
    });

    test('panel Acak Cerdas berikon kotak tonal, sakelar & perilaku sama', () {
      expect(src, contains('tonalIconBox(ClaiIcons.shuffle)'));
      expect(src, contains('handler.setSmartShuffle(v)'));
      expect(src, contains('engine.shuffle == qe.ShuffleMode.smart'));
    });
  });

  group('tombol acak Player tiga keadaan jujur (8051)', () {
    test('pemetaan mode → wujud: mati/murni/cerdas terbedakan', () {
      expect(shuffleButtonLook(qe.ShuffleMode.off), ShuffleButtonLook.off);
      expect(shuffleButtonLook(qe.ShuffleMode.pure), ShuffleButtonLook.pure);
      expect(
          shuffleButtonLook(qe.ShuffleMode.smart), ShuffleButtonLook.smart);
    });

    test('ketuk: dari mati menyalakan murni; mode aktif apa pun → mati', () {
      expect(shuffleTapTarget(qe.ShuffleMode.off),
          AudioServiceShuffleMode.all);
      expect(shuffleTapTarget(qe.ShuffleMode.pure),
          AudioServiceShuffleMode.none);
      // Inti cacat 20:40: ketuk saat CERDAS tidak boleh menukarnya
      // diam-diam menjadi murni — sasaran satu-satunya adalah mati.
      expect(shuffleTapTarget(qe.ShuffleMode.smart),
          AudioServiceShuffleMode.none);
    });

    test('kabel sumber: kedua transportasi Player memakai pemetaan bersama', () {
      final src = File('lib/ui/player_sheet.dart').readAsStringSync();
      expect(src, contains('shuffle_button_state.dart'));
      expect(src, contains('shuffleButtonLook'));
      expect(src, contains('shuffleTapTarget'));
      expect(src, contains('smartBadge'));
      // Lencana berlian pembeda cerdas benar-benar digambar _CtrlButton.
      expect(src, contains('math.pi / 4'));
    });

    test('handler: jalur sistem tidak menukar cerdas→murni (penjaga lama utuh)', () {
      final src = File('lib/player/audio_handler.dart').readAsStringSync();
      final body = src.substring(src.indexOf('Future<void> setShuffleMode'));
      expect(body.substring(0, 900),
          contains('engine.shuffle != ShuffleMode.smart'));
    });
  });
}
