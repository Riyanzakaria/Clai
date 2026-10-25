import 'package:clai/player/interruption_policy.dart';
import 'package:flutter_test/flutter_test.dart';

/// Matriks interupsi (USER-FLOW 2.2; laporan riyan 2026-10-24):
/// lanjut-otomatis hanya sah bila jeda terakhir disebabkan interupsi
/// sistem; jeda manual bersifat lengket (handler menghapus hak di pause()).
void main() {
  final t0 = DateTime(2026, 10, 24, 16, 0);

  group('mayAutoResume', () {
    test('hak ada + pengaturan aktif + jeda singkat → lanjut', () {
      expect(
        mayAutoResume(
            granted: true,
            settingEnabled: true,
            pausedAt: t0,
            now: t0.add(const Duration(minutes: 2))),
        isTrue,
      );
    });

    test('tanpa hak (jeda bukan dari interupsi) → tidak lanjut', () {
      expect(
        mayAutoResume(
            granted: false,
            settingEnabled: true,
            pausedAt: t0,
            now: t0.add(const Duration(minutes: 2))),
        isFalse,
      );
    });

    test('pengaturan lanjut-otomatis mati → tidak lanjut walau ada hak', () {
      expect(
        mayAutoResume(
            granted: true,
            settingEnabled: false,
            pausedAt: t0,
            now: t0.add(const Duration(minutes: 2))),
        isFalse,
      );
    });

    test('jeda interupsi ≥ 30 menit → hak kedaluwarsa', () {
      expect(
        mayAutoResume(
            granted: true,
            settingEnabled: true,
            pausedAt: t0,
            now: t0.add(const Duration(minutes: 30))),
        isFalse,
      );
      expect(
        mayAutoResume(
            granted: true,
            settingEnabled: true,
            pausedAt: t0,
            now: t0.add(const Duration(minutes: 29))),
        isTrue,
      );
    });

    test('waktu jeda tidak tercatat → tidak lanjut', () {
      expect(
        mayAutoResume(
            granted: true, settingEnabled: true, pausedAt: null, now: t0),
        isFalse,
      );
    });
  });

  // Regresi interupsi build 2012: tanpa bendera pause-when-ducked pada
  // permintaan fokus, framework tidak mengirim peristiwa CAN_DUCK sama
  // sekali (notified: false di MediaFocusControl) — setelan 'Jeda' tidak
  // mungkin menjeda untuk perebut kelas duck. Bukti pentasan:
  // builds/bukti-regresi-interupsi/pentasan/RINGKASAN-PENTASAN.md.
  group('willPauseWhenDuckedForFocusBehavior', () {
    test("setelan 'pause' (Jeda) → true: peristiwa CAN_DUCK wajib terkirim",
        () {
      expect(willPauseWhenDuckedForFocusBehavior('pause'), isTrue);
    });

    test("setelan 'duck' (Redam) → false: framework yang men-duck", () {
      expect(willPauseWhenDuckedForFocusBehavior('duck'), isFalse);
    });

    test('pref belum terpasang (bawaan Redam) → false', () {
      expect(willPauseWhenDuckedForFocusBehavior(null), isFalse);
    });

    test('nilai tak dikenal → false (aman ke perilaku bawaan)', () {
      expect(willPauseWhenDuckedForFocusBehavior('lainnya'), isFalse);
    });
  });
}
