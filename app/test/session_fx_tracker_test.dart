import 'package:flutter_test/flutter_test.dart';
import 'package:clai/player/session_fx_tracker.dart';

/// Ronde Kresek (2026-11-04): higiene efek per sesi — Equalizer Android
/// dibuat per audio-session-id dan sebelumnya tidak pernah dilepas.
/// Tracker memutuskan sesi mana yang diterapkan / dilepas pada setiap
/// peristiwa sesi-muncul, per pemain.
void main() {
  group('SessionFxTracker', () {
    late SessionFxTracker t;
    setUp(() => t = SessionFxTracker());

    test('kemunculan pertama: terapkan, tak ada yang dilepas, isFirst', () {
      final d = t.onAppear(0, 281);
      expect(d.applyTo, 281);
      expect(d.releasePrevious, isNull);
      expect(d.isFirst, isTrue);
      expect(d.isChange, isFalse);
    });

    test('id sama berulang: bukan pergantian, tidak melepas apa pun', () {
      t.onAppear(0, 281);
      final d = t.onAppear(0, 281);
      expect(d.applyTo, 281);
      expect(d.releasePrevious, isNull);
      expect(d.isFirst, isFalse);
      expect(d.isChange, isFalse);
    });

    test('id berganti: sesi lama wajib dilepas', () {
      t.onAppear(0, 281);
      final d = t.onAppear(0, 297);
      expect(d.applyTo, 297);
      expect(d.releasePrevious, 281);
      expect(d.isChange, isTrue);
      expect(d.isFirst, isFalse);
    });

    test('rantai pergantian A->B->C melepas tepat pendahulu masing-masing',
        () {
      t.onAppear(0, 10);
      expect(t.onAppear(0, 11).releasePrevious, 10);
      expect(t.onAppear(0, 12).releasePrevious, 11);
      expect(t.knownSessionIds, [12]);
    });

    test('dua pemain independen: pergantian satu tak menyentuh yang lain',
        () {
      t.onAppear(0, 100);
      final dB = t.onAppear(1, 200);
      expect(dB.isFirst, isTrue);
      expect(dB.releasePrevious, isNull);
      final dA = t.onAppear(0, 101);
      expect(dA.releasePrevious, 100);
      expect(t.knownSessionIds, containsAll(<int>[101, 200]));
      // Pemain B mengulang id-nya: tetap bukan pergantian.
      expect(t.onAppear(1, 200).releasePrevious, isNull);
    });

    test('forget: kemunculan berikutnya dihitung pertama lagi', () {
      t.onAppear(0, 55);
      t.forget(0);
      final d = t.onAppear(0, 55);
      expect(d.isFirst, isTrue);
      expect(d.releasePrevious, isNull);
    });

    test('clear mengosongkan semua pemain', () {
      t.onAppear(0, 1);
      t.onAppear(1, 2);
      t.clear();
      expect(t.knownSessionIds, isEmpty);
      expect(t.onAppear(1, 2).isFirst, isTrue);
    });
  });
}
