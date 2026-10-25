import 'package:clai/domain/models.dart';
import 'package:clai/player/crossfade.dart';
import 'package:clai/player/queue_engine.dart';
import 'package:clai/services/loudness_estimator.dart';
import 'package:flutter_test/flutter_test.dart';

Track _t(String id, String artist) => Track(
      key: TrackKey('ytm', id),
      title: 'Lagu $id',
      artistNames: artist,
      duration: const Duration(minutes: 3),
      playableRef: id,
    );

void main() {
  group('crossfade equal-power', () {
    test('titik tengah flat (0.707/0.707), ujung 1/0 dan 0/1, daya konstan', () {
      final mid = crossfadeVolumes(0.5);
      expect(mid.outgoing, closeTo(0.7071, 0.001));
      expect(mid.incoming, closeTo(0.7071, 0.001));
      expect(crossfadeVolumes(0).outgoing, closeTo(1.0, 1e-9));
      expect(crossfadeVolumes(0).incoming, closeTo(0.0, 1e-9));
      expect(crossfadeVolumes(1).outgoing, closeTo(0.0, 1e-9));
      expect(crossfadeVolumes(1).incoming, closeTo(1.0, 1e-9));
      // Daya total konstan (bukan linear yang turun di tengah).
      for (final p in [0.0, 0.25, 0.5, 0.75, 1.0]) {
        final g = crossfadeVolumes(p);
        expect(g.outgoing * g.outgoing + g.incoming * g.incoming,
            closeTo(1.0, 0.001));
      }
    });
    test('smoothGain linier dari lama ke baru selama durasi', () {
      expect(smoothGain(0.8, 1.0, Duration.zero, const Duration(seconds: 5)), 0.8);
      expect(
          smoothGain(0.8, 1.0, const Duration(seconds: 5), const Duration(seconds: 5)),
          1.0);
      expect(
          smoothGain(0.8, 1.0, const Duration(milliseconds: 2500),
              const Duration(seconds: 5)),
          closeTo(0.9, 1e-9));
    });
    test('transitionGapMs: null bila tak ada completed, selisih bila ada', () {
      expect(transitionGapMs(null, DateTime(2026, 1, 1)), null);
      expect(
          transitionGapMs(
              DateTime(2026, 1, 1, 0, 0, 0), DateTime(2026, 1, 1, 0, 0, 0, 40)),
          40);
    });
  });

  group('takeNextForCrossfade', () {
    test('manual dulu, lalu lanjutan; repeat-one tanpa skip manual', () {
      final e = QueueEngine();
      final a = _t('a', 'Artis A');
      final b = _t('b', 'Artis B');
      final c = _t('c', 'Artis C');
      e.playContext(
          PlayContext(kind: 'album', label: 'Album', tracks: [a, b]), 0);
      e.enqueueNext(c);
      expect(e.takeNextForCrossfade(), c);
      expect(e.current, c);
      expect(e.takeNextForCrossfade(), b);
      expect(e.current, b);
      // Habis: repeat-one mengembalikan current (bukan maju).
      e.repeat = RepeatMode.one;
      expect(e.takeNextForCrossfade(), b);
      expect(e.takeNextForCrossfade(manualSkip: true), null);
    });
    test('repeat-all melingkar dari awal konteks setelah habis', () {
      final e = QueueEngine();
      final a = _t('a', 'Artis A');
      final b = _t('b', 'Artis B');
      e.playContext(
          PlayContext(kind: 'album', label: 'Album', tracks: [a, b]), 0);
      e.repeat = RepeatMode.all;
      expect(e.takeNextForCrossfade(), b);
      expect(e.takeNextForCrossfade(), a);
      expect(e.current, a);
    });
  });

  group('gainFromLoudness', () {
    test('target −16 dB: terukur −16 → 1.0; −22 → naik; −10 → turun; dijepit', () {
      expect(gainFromLoudness(-16.0), closeTo(1.0, 1e-9));
      expect(gainFromLoudness(-22.0), closeTo(1.995, 0.01));
      expect(gainFromLoudness(-10.0), closeTo(0.501, 0.01));
      expect(gainFromLoudness(-40.0), 4.0); // jepit atas
      expect(gainFromLoudness(0.0), 0.25); // jepit bawah
    });
  });
}
