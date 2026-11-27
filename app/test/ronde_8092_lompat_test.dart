import 'package:clai/player/loading_watchdog.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ronde 8092 — Paket Lompat F1–F6: uji logika murni LoadingWatchdog
/// (F4) dan target verifikasi yang dapat diganti (F3). Sampel disuapkan
/// dengan jam dinding palsu, gaya uji StallWatchdog/RepeatDetector.
void main() {
  DateTime at(int s) => DateTime.fromMillisecondsSinceEpoch(s * 1000);

  group('LoadingWatchdog (F4)', () {
    LoadingWatchdog w = LoadingWatchdog();
    setUp(() => w = LoadingWatchdog());

    // Ronde 8092 D1 (R5): feed kini mengembalikan LoadingStage
    // (none/fire/escalated), bukan bool — tanda tangan berubah.
    LoadingStage feedAt(
      int s, {
      bool playing = true,
      bool loading = true,
      int pos = 1000,
      int buf = 5000,
    }) => w.feed(
      playing: playing,
      loadingOrBuffering: loading,
      positionMs: pos,
      bufferedPositionMs: buf,
      now: at(s),
    );

    test('(a) loading tanpa kemajuan 25 dtk → tembak sekali per episode',
        () {
      expect(feedAt(0), LoadingStage.none);
      expect(feedAt(10), LoadingStage.none);
      expect(feedAt(25), LoadingStage.none, reason: 'ambang >25 dtk, bukan ≥');
      expect(feedAt(26), LoadingStage.fire);
      expect(feedAt(27), LoadingStage.none, reason: 'tidak berulang dalam episode');
      // Ronde 8092 D1 (R5): asersi lama "tetap none sampai 120" diubah
      // — episode yang sama kini bereskalasi 25 dtk sesudah fire.
      expect(feedAt(51), LoadingStage.none,
          reason: 'eskalasi >25 dtk sesudah fire, bukan ≥');
      expect(feedAt(52), LoadingStage.escalated);
      expect(feedAt(120), LoadingStage.none,
          reason: 'eskalasi tepat sekali per episode');
      // Kemajuan mengakhiri episode; macet baru boleh menembak lagi.
      expect(feedAt(121, pos: 2000), LoadingStage.none);
      expect(feedAt(147, pos: 2000), LoadingStage.fire);
    });

    test('(b) NEGATIF: buffering dengan buffer maju perlahan 60 dtk '
        '→ TIDAK tembak', () {
      expect(feedAt(0, buf: 0), LoadingStage.none);
      for (var s = 5; s <= 60; s += 5) {
        expect(
          feedAt(s, buf: s * 200),
          LoadingStage.none,
          reason: 'buffer maju pada t=$s — loading lambat bukan macet',
        );
      }
    });

    test('(c) posisi maju → episode reset', () {
      expect(feedAt(0), LoadingStage.none);
      expect(feedAt(20), LoadingStage.none);
      expect(feedAt(24, pos: 3000), LoadingStage.none, reason: 'kemajuan di t=24');
      expect(feedAt(49, pos: 3000), LoadingStage.none, reason: 'baru 25 dtk macet');
      expect(feedAt(50, pos: 3000), LoadingStage.fire);
    });

    test('(d) jeda (playing=false) → tidak tembak & mereset', () {
      expect(feedAt(0), LoadingStage.none);
      expect(feedAt(30, playing: false), LoadingStage.none);
      expect(feedAt(60, playing: false), LoadingStage.none);
      // Bermain lagi: ambang diukur dari sampel jeda terakhir (t=60,
      // dalam praktik handler memberi makan tiap 1 dtk saat jeda).
      expect(feedAt(61), LoadingStage.none);
      expect(feedAt(85), LoadingStage.none, reason: 'baru 25 dtk sejak t=60');
      expect(feedAt(86), LoadingStage.fire);
    });

    test('(e) ready (bukan loading/buffering) → reset episode', () {
      expect(feedAt(0), LoadingStage.none);
      expect(feedAt(20), LoadingStage.none);
      expect(feedAt(21, loading: false), LoadingStage.none, reason: 'ready: reset');
      expect(feedAt(22), LoadingStage.none, reason: 'episode baru mulai t=21/22');
      expect(feedAt(46), LoadingStage.none, reason: '25 dtk sejak reset t=21');
      expect(feedAt(47), LoadingStage.fire);
    });

    test('reset() membersihkan episode', () {
      feedAt(0);
      w.reset();
      expect(feedAt(100), LoadingStage.none);
      expect(feedAt(126), LoadingStage.fire);
    });
  });

  group('LoadingWatchdog eskalasi (Ronde 8092 D1, R5)', () {
    LoadingWatchdog w = LoadingWatchdog();
    setUp(() => w = LoadingWatchdog());

    LoadingStage feedAt(
      int s, {
      bool playing = true,
      bool loading = true,
      int pos = 1000,
      int buf = 5000,
    }) => w.feed(
      playing: playing,
      loadingOrBuffering: loading,
      positionMs: pos,
      bufferedPositionMs: buf,
      now: at(s),
    );

    test('fire → escalated sesudah +25 dtk lagi tanpa kemajuan', () {
      expect(feedAt(0), LoadingStage.none);
      expect(feedAt(26), LoadingStage.fire);
      expect(feedAt(40), LoadingStage.none);
      expect(feedAt(51), LoadingStage.none, reason: 'baru 25 dtk sesudah fire');
      expect(feedAt(52), LoadingStage.escalated);
      expect(feedAt(90), LoadingStage.none, reason: 'eskalasi sekali saja');
    });

    test('kemajuan di antara fire dan eskalasi MEMBATALKAN eskalasi',
        () {
      expect(feedAt(0), LoadingStage.none);
      expect(feedAt(26), LoadingStage.fire);
      expect(feedAt(40, pos: 2000), LoadingStage.none,
          reason: 'kemajuan = episode baru');
      expect(feedAt(52, pos: 2000), LoadingStage.none,
          reason: 'bukan escalated — episode baru belum mencapai fire');
      expect(feedAt(66, pos: 2000), LoadingStage.fire,
          reason: 'episode baru menembak fire lagi, bukan escalated');
      expect(feedAt(92, pos: 2000), LoadingStage.escalated);
    });

    test('kemajuan buffer saja juga membatalkan eskalasi', () {
      expect(feedAt(0), LoadingStage.none);
      expect(feedAt(26), LoadingStage.fire);
      expect(feedAt(50, buf: 9000), LoadingStage.none);
      expect(feedAt(76, buf: 9000), LoadingStage.fire);
    });

    test('NEGATIF lama tetap berlaku: buffer maju perlahan 120 dtk '
        '→ tidak fire, tidak escalated', () {
      expect(feedAt(0, buf: 0), LoadingStage.none);
      for (var s = 5; s <= 120; s += 5) {
        expect(feedAt(s, buf: s * 200), LoadingStage.none,
            reason: 'buffer maju pada t=$s');
      }
    });
  });

  group('R6 — loadProgressStalled + persenjataan ulang (D1)', () {
    test('kunci di target + loading + posisi tak melebihi saat lompat '
        '→ macet muat', () {
      expect(
        loadProgressStalled(
          keyAtTarget: true,
          loadingOrBuffering: true,
          positionMs: 69348,
          positionAtJumpMs: 69348,
        ),
        isTrue,
      );
    });

    test('posisi sudah maju dari saat lompat → ada kemajuan muat', () {
      expect(
        loadProgressStalled(
          keyAtTarget: true,
          loadingOrBuffering: true,
          positionMs: 70000,
          positionAtJumpMs: 69348,
        ),
        isFalse,
      );
    });

    test('bukan loading / kunci belum di target → bukan macet muat', () {
      expect(
        loadProgressStalled(
          keyAtTarget: true,
          loadingOrBuffering: false,
          positionMs: 0,
          positionAtJumpMs: 0,
        ),
        isFalse,
      );
      expect(
        loadProgressStalled(
          keyAtTarget: false,
          loadingOrBuffering: true,
          positionMs: 0,
          positionAtJumpMs: 0,
        ),
        isFalse,
      );
    });

    test('tryArmLoadRecheck: maks SATU persenjataan ulang per target; '
        'update target baru mengaturnya ulang', () {
      final t = AdvanceVerifyTarget();
      t.update(from: 'yt:a', to: 'yt:b', whatLabel: 'skip-manual',
          now: at(0), positionMs: 69348);
      expect(t.positionAtJumpMs, 69348);
      expect(t.tryArmLoadRecheck(), isTrue);
      expect(t.tryArmLoadRecheck(), isFalse, reason: 'maks satu kali');
      t.update(from: 'yt:b', to: 'yt:c', whatLabel: 'skip-manual',
          now: at(10), positionMs: 0);
      expect(t.loadRearmed, isFalse);
      expect(t.tryArmLoadRecheck(), isTrue);
      t.clear();
      expect(t.positionAtJumpMs, isNull);
      expect(t.loadRearmed, isFalse);
    });
  });

  group('AdvanceVerifyTarget (F3)', () {
    AdvanceVerifyTarget t = AdvanceVerifyTarget();
    setUp(() => t = AdvanceVerifyTarget());

    test('panggilan kedua MENGGANTI target pertama', () {
      t.update(from: 'yt:a', to: 'yt:b', whatLabel: 'skip-manual', now: at(0));
      t.update(from: 'yt:b', to: 'yt:c', whatLabel: 'skip-manual', now: at(1));
      expect(t.fromKey, 'yt:b');
      expect(t.toKey, 'yt:c', reason: 'target terakhir yang diverifikasi');
      expect(t.what, 'skip-manual');
    });

    test('jatuh tempo 1,5 dtk sesudah upaya TERAKHIR, bukan pertama',
        () {
      t.update(from: 'yt:a', to: 'yt:b', whatLabel: 'skip-manual', now: at(0));
      t.update(from: 'yt:b', to: 'yt:c', whatLabel: 'skip-manual', now: at(1));
      expect(t.due(at(1).add(const Duration(milliseconds: 1499))), isFalse);
      expect(
        t.due(at(1).add(const Duration(milliseconds: 1500))),
        isTrue,
        reason: '1,5 dtk sesudah upaya terakhir (t=1), bukan t=0',
      );
    });

    test('tanpa target / sesudah clear → tidak jatuh tempo', () {
      expect(t.hasTarget, isFalse);
      expect(t.due(at(99)), isFalse);
      t.update(from: 'yt:a', to: 'yt:b', whatLabel: 'x', now: at(0));
      t.clear();
      expect(t.hasTarget, isFalse);
      expect(t.due(at(99)), isFalse);
    });
  });
}
