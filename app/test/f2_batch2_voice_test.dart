import 'package:clai/domain/models.dart';
import 'package:clai/services/voice_commands.dart';
import 'package:flutter_test/flutter_test.dart';

Track _t(String id, String title, String artist) => Track(
      key: TrackKey('ytm', id),
      title: title,
      artistNames: artist,
      playableRef: id,
    );

void main() {
  group('parseVoiceCommand', () {
    test('Indonesia: putar / tambah setelah ini / tambah antrean / aksi', () {
      expect(parseVoiceCommand('putar Menungso Oratoto').action, VoiceAction.play);
      expect(parseVoiceCommand('putar Menungso Oratoto').query, 'menungso oratoto');
      expect(parseVoiceCommand('mainkan Fade').action, VoiceAction.play);
      final a = parseVoiceCommand('tambah Themilo setelah ini');
      expect(a.action, VoiceAction.addNext);
      expect(a.query, 'themilo');
      final b = parseVoiceCommand('tambah Fade ke antrean');
      expect(b.action, VoiceAction.addQueue);
      expect(b.query, 'fade');
      expect(parseVoiceCommand('lewati').action, VoiceAction.skip);
      expect(parseVoiceCommand('jeda').action, VoiceAction.pause);
      expect(parseVoiceCommand('putar lagi').action, VoiceAction.resume);
      expect(parseVoiceCommand('lanjutkan').action, VoiceAction.resume);
    });
    test('Inggris: play / add after this / queue / skip / pause / resume', () {
      expect(parseVoiceCommand('play Fade').action, VoiceAction.play);
      final a = parseVoiceCommand('add Themilo after this');
      expect(a.action, VoiceAction.addNext);
      expect(a.query, 'themilo');
      expect(parseVoiceCommand('queue Fade').action, VoiceAction.addQueue);
      expect(parseVoiceCommand('skip').action, VoiceAction.skip);
      expect(parseVoiceCommand('pause').action, VoiceAction.pause);
      expect(parseVoiceCommand('resume').action, VoiceAction.resume);
    });
    test('tak dikenal & kosong → unknown', () {
      expect(parseVoiceCommand('kamu cantik').action, VoiceAction.unknown);
      expect(parseVoiceCommand('').action, VoiceAction.unknown);
      expect(parseVoiceCommand('putar').action, VoiceAction.unknown);
    });
  });

  group('parseChoiceAnswer', () {
    test('pertama/kedua/batal/dll', () {
      expect(parseChoiceAnswer('yang pertama'), 0);
      expect(parseChoiceAnswer('second'), 1);
      expect(parseChoiceAnswer('batal'), -1);
      expect(parseChoiceAnswer('yang ketiga'), null);
    });
  });

  group('voiceScore', () {
    test('judul persis menang; penguat riwayat menaikkan', () {
      final t = _t('1', 'Menungso Oratoto', 'Denny Caknan');
      // Judul cocok penuh (0.7) + artis tak cocok (0.0) = 0.7.
      final s1 = voiceScore('menungso oratoto', t);
      expect(s1, closeTo(0.7, 1e-9));
      final s2 = voiceScore('menungso oratoto', t, liked: true, plays: 3);
      expect(s2, closeTo(0.8, 1e-9));
      final other = _t('2', 'Lagu Lain', 'Artis Lain');
      expect(voiceScore('menungso oratoto', other),
          lessThan(kVoiceAcceptThreshold));
    });
  });
}
