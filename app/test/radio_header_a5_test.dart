// Regresi A-5 (Ronde Audit UX 2017): tombol Putar header halaman Radio
// sadar-keadaan — Jeda saat sesi radio halaman ini berbunyi, lanjutkan
// saat sesi halaman ini terjeda, mulai baru bila bukan sesi halaman ini.
//
// Catatan cakupan: RadioScreen utuh tidak dipompa di sini karena handler-nya
// konkret (ClaiAudioHandler) dan konstruktornya menyentuh kanal platform
// AudioSession/just_audio — kendala yang sama dicatat putusan_desain_test.
// Yang diuji: fungsi keputusan murni + predikat sesi pada mesin antrean
// sungguhan + widget tombol presentasi sungguhan.
import 'package:clai/core/clai_icons.dart';
import 'package:clai/domain/models.dart';
import 'package:clai/player/queue_engine.dart';
import 'package:clai/ui/radio_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Track t(String id) => Track(
      key: TrackKey('ytmusic', id),
      title: 'Lagu $id',
      artistNames: 'Artis A',
      duration: const Duration(minutes: 3),
      playableRef: id,
    );

void main() {
  group('A-5: keputusan aksi tombol header', () {
    test('berbunyi -> jeda (apa pun sesinya)', () {
      expect(
        resolveRadioHeaderAction(thisSession: true, playing: true),
        RadioHeaderAction.pause,
      );
      expect(
        resolveRadioHeaderAction(thisSession: false, playing: true),
        RadioHeaderAction.pause,
      );
    });
    test('terjeda pada sesi halaman ini -> lanjutkan', () {
      expect(
        resolveRadioHeaderAction(thisSession: true, playing: false),
        RadioHeaderAction.resume,
      );
    });
    test('bukan sesi halaman ini dan tidak berbunyi -> mulai baru', () {
      expect(
        resolveRadioHeaderAction(thisSession: false, playing: false),
        RadioHeaderAction.start,
      );
    });
  });

  group('A-5: predikat sesi radio halaman ini', () {
    test('radio + id benih sama -> sesi halaman ini', () {
      expect(isRadioSessionOfPage('radio', 's1', 's1'), isTrue);
    });
    test('radio + id benih beda -> bukan sesi halaman ini', () {
      expect(isRadioSessionOfPage('radio', 's2', 's1'), isFalse);
    });
    test('bukan radio + id sama -> bukan sesi halaman ini', () {
      expect(isRadioSessionOfPage('search', 's1', 's1'), isFalse);
    });
    test('tanpa konteks -> bukan sesi halaman ini', () {
      expect(isRadioSessionOfPage(null, null, 's1'), isFalse);
    });
  });

  group('A-5: predikat pada mesin antrean sungguhan', () {
    test('playRadio menanam konteks radio id benih', () {
      final e = QueueEngine();
      e.playRadio(t('s1'));
      expect(
        isRadioSessionOfPage(e.context?.kind, e.context?.id, 's1'),
        isTrue,
      );
      e.playRadio(t('s2'));
      expect(
        isRadioSessionOfPage(e.context?.kind, e.context?.id, 's1'),
        isFalse,
      );
    });
    test('playRadioFromPage menjaga jangkar benih halaman', () {
      final e = QueueEngine();
      e.playRadioFromPage(seed: t('s1'), page: [t('p1'), t('p2')], startIndex: 1);
      expect(e.current!.id, 'p2');
      expect(
        isRadioSessionOfPage(e.context?.kind, e.context?.id, 's1'),
        isTrue,
      );
    });
    test('konteks non-radio bukan sesi halaman radio', () {
      final e = QueueEngine();
      e.playContext(
        PlayContext(kind: 'album', label: 'A', tracks: [t('s1')]),
        0,
      );
      expect(
        isRadioSessionOfPage(e.context?.kind, e.context?.id, 's1'),
        isFalse,
      );
    });
  });

  group('A-5: widget tombol header', () {
    testWidgets('berbunyi -> ikon jeda; tidak berbunyi -> ikon putar',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RadioHeaderPlayButton(playing: true, onTap: () {}),
          ),
        ),
      );
      expect(
        tester.widget<ClaiIcon>(find.byType(ClaiIcon)).data,
        same(ClaiIcons.pause),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RadioHeaderPlayButton(playing: false, onTap: () {}),
          ),
        ),
      );
      expect(
        tester.widget<ClaiIcon>(find.byType(ClaiIcon)).data,
        same(ClaiIcons.play),
      );
    });

    testWidgets('ketukan memicu onTap tepat sekali', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RadioHeaderPlayButton(
              playing: false,
              onTap: () => taps++,
            ),
          ),
        ),
      );
      await tester.tap(find.byType(GestureDetector));
      expect(taps, 1);
    });
  });
}
