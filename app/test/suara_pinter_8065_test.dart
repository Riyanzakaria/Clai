import 'dart:io';

import 'package:clai/domain/models.dart';
import 'package:clai/services/track_matcher.dart';
import 'package:clai/services/voice_commands.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ronde 8065 — korpus gerbang "pinter" Antrean Suara, dari kegagalan
/// nyata di HP riyan 14 Nov 2026 (18:39–18:40): transkrip "putar lagu
/// sway" dan "putar sway color code" terbaca BENAR oleh pengenal, tetapi
/// (1) dibuang veto keyakinan < 0.5 sebelum diurai, lalu (2) sesi dibuang
/// error pengenal kode 11. Korpus ini mengunci: urai + pembersih kueri,
/// bentuk perintah baru, pencocokan kabur/fonetik, konteks berbobot, dan
/// fungsi kebijakan (tanpa veto; bunyi kegagalan; keputusan resolusi).
Track _t(String id, String title, String artist) => Track(
      key: TrackKey('ytm', id),
      title: title,
      artistNames: artist,
      playableRef: id,
    );

void main() {
  final swayColorcode = _t('sway-cc', 'Sway', 'COLORCODE');
  final swayAsing = _t('sway-x', 'Sway', 'Artis Lain');
  final colorCodeJudul = _t('cc-j', 'Color Code', 'Penyanyi Lain');
  final umpan = _t('umpan', 'Bergoyang', 'Biduan Z');

  group('cleanVoiceQuery — kata pengisi ujung dibuang', () {
    test('awalan lagu/berjudul, akhiran dong/aja/saja/nya/yang', () {
      expect(cleanVoiceQuery('lagu sway'), 'sway');
      expect(cleanVoiceQuery('berjudul sway'), 'sway');
      expect(cleanVoiceQuery('sway dong'), 'sway');
      expect(cleanVoiceQuery('sway aja'), 'sway');
      expect(cleanVoiceQuery('sway nya dong'), 'sway');
      expect(cleanVoiceQuery('lagu sway dong'), 'sway');
    });
    test('bukan pengisi tidak disentuh; pengisi tunggal → kosong', () {
      expect(cleanVoiceQuery('sway'), 'sway');
      // "yang" di DEPAN adalah bagian judul ("Yang Terdalam") — hanya
      // posisi akhiran yang dibuang.
      expect(cleanVoiceQuery('yang terdalam'), 'yang terdalam');
      expect(cleanVoiceQuery('lagu'), '');
      expect(cleanVoiceQuery(''), '');
    });
  });

  group('korpus urai — perintah realistis riyan', () {
    test('"putar lagu sway" → play, kueri "sway"', () {
      final p = parseVoiceCommand('putar lagu sway');
      expect(p.action, VoiceAction.play);
      expect(p.query, 'sway');
    });
    test('"putarin sway dong" → play "sway"; "putarkan" juga play', () {
      final p = parseVoiceCommand('putarin sway dong');
      expect(p.action, VoiceAction.play);
      expect(p.query, 'sway');
      expect(parseVoiceCommand('putarkan sway').action, VoiceAction.play);
      expect(parseVoiceCommand('putarkan sway').query, 'sway');
    });
    test('"ganti ke sway" & "pindah ke sway" → play', () {
      expect(parseVoiceCommand('ganti ke sway').action, VoiceAction.play);
      expect(parseVoiceCommand('ganti ke sway').query, 'sway');
      expect(parseVoiceCommand('pindah ke sway').action, VoiceAction.play);
    });
    test('"tambah sway setelah ini" → addNext; antrean tetap addQueue', () {
      final p = parseVoiceCommand('tambah sway setelah ini');
      expect(p.action, VoiceAction.addNext);
      expect(p.query, 'sway');
      final q = parseVoiceCommand('tambah lagu sway ke antrean');
      expect(q.action, VoiceAction.addQueue);
      expect(q.query, 'sway');
    });
    test('judul polos tanpa kata kerja TETAP unknown (anti salah picu)',
        () {
      expect(parseVoiceCommand('sway').action, VoiceAction.unknown);
      expect(parseVoiceCommand('ganti sway').action, VoiceAction.unknown);
    });
  });

  group('kemiripan diperkuat — fonetik rapat & toleransi edit', () {
    test('"color code" ≡ "COLORCODE" (bentuk rapat)', () {
      expect(fuzzyTitleSimilarity('color code', 'COLORCODE'), 1);
      expect(fuzzyArtistSimilarity('color code', 'COLORCODE'), 1);
      expect(fuzzyArtistSimilarity('sway color code', 'COLORCODE'), 1);
    });
    test('salah-dengar satu huruf tetap bertemu ("suay" → "Sway")', () {
      expect(levenshteinDistance('suay', 'sway'), 1);
      expect(levenshteinDistance('abc', 'abc'), 0);
      expect(fuzzyTitleSimilarity('suay', 'Sway'), 1);
      // Fungsi lama TIDAK berubah perilakunya (pencocokan Spotify aman).
      expect(titleSimilarity('suay', 'Sway'), lessThan(1));
    });
  });

  group('korpus skor — kandidat sintetis', () {
    test('"putar sway color code": COLORCODE—Sway teratas & diterima', () {
      final q = parseVoiceCommand('putar sway color code').query;
      final skorCc = voiceScore(q, swayColorcode);
      final skorAsing = voiceScore(q, swayAsing);
      final skorJudul = voiceScore(q, colorCodeJudul);
      expect(skorCc, greaterThan(skorAsing));
      expect(skorCc, greaterThan(skorJudul));
      expect(skorCc, greaterThanOrEqualTo(kVoiceAcceptThreshold));
      // Melawan sesama "Sway" tanpa petunjuk artis, keputusannya apply.
      expect(decideVoiceResolution([skorCc, skorAsing]),
          VoiceResolveDecision.apply);
    });
    test('"putar suay": Sway diterima lewat toleransi edit', () {
      final q = parseVoiceCommand('putar suay').query;
      final skor = voiceScore(q, swayColorcode);
      expect(skor, greaterThanOrEqualTo(kVoiceAcceptThreshold));
      expect(decideVoiceResolution([skor, voiceScore(q, umpan)]),
          VoiceResolveDecision.apply);
    });
    test('konteks berbobot: disukai & riwayat memecah seri judul kembar',
        () {
      final polos = voiceScore('sway', swayAsing);
      final konteks =
          voiceScore('sway', swayColorcode, liked: true, plays: 4);
      expect(konteks - polos, closeTo(0.20, 1e-9)); // +0.10 suka +0.10 riwayat
      expect(decideVoiceResolution([konteks, polos]),
          VoiceResolveDecision.apply);
      // Tanpa konteks, dua "Sway" asing memang harus DITANYAKAN.
      expect(
          decideVoiceResolution(
              [voiceScore('sway', swayColorcode), voiceScore('sway', swayAsing)]),
          VoiceResolveDecision.askChoice);
    });
  });

  group('kebijakan keyakinan — veto dicabut (fungsi murni)', () {
    test('aksi tanpa argumen tidak berkuesi: "lewati" jalan pada '
        'keyakinan 0.2 sekalipun', () {
      final p = parseVoiceCommand('lewati');
      expect(p.action, VoiceAction.skip);
      // Inilah komposisi gerbang di handleText: aksi tanpa kueri tidak
      // pernah ditanya keyakinannya; yang berkuesi diputuskan skor.
      expect(voiceActionNeedsQuery(p.action), isFalse);
      expect(voiceActionNeedsQuery(VoiceAction.play), isTrue);
    });
    test('keyakinan 0.2 + "putar lagu sway" cocok kuat → tetap diputar '
        '(keputusan dari skor, bukan angka keyakinan)', () {
      final p = parseVoiceCommand('putar lagu sway');
      final skor = [
        voiceScore(p.query, swayColorcode),
        voiceScore(p.query, umpan),
      ]..sort((a, b) => b.compareTo(a));
      expect(decideVoiceResolution(skor), VoiceResolveDecision.apply);
    });
    test('bunyi kegagalan: rendah → ajakan (maks 2) lalu menyerah; '
        'normal → spesifik', () {
      expect(
          voiceFailureWording(lowConfidence: true, failedAttempts: 0),
          VoiceFailureWording.askRepeat);
      expect(
          voiceFailureWording(lowConfidence: true, failedAttempts: 1),
          VoiceFailureWording.askRepeat);
      expect(
          voiceFailureWording(lowConfidence: true, failedAttempts: 2),
          VoiceFailureWording.giveUp);
      expect(
          voiceFailureWording(lowConfidence: false, failedAttempts: 0),
          VoiceFailureWording.specific);
      expect(
          voiceFailureWording(lowConfidence: false, failedAttempts: 9),
          VoiceFailureWording.specific);
    });
    test('keputusan resolusi: ambang & celah ambiguitas', () {
      expect(decideVoiceResolution(const []), VoiceResolveDecision.fail);
      expect(decideVoiceResolution(const [0.30]), VoiceResolveDecision.fail);
      expect(decideVoiceResolution(const [0.35]), VoiceResolveDecision.apply);
      expect(decideVoiceResolution(const [0.90, 0.85]),
          VoiceResolveDecision.askChoice);
      expect(decideVoiceResolution(const [0.90, 0.50]),
          VoiceResolveDecision.apply);
    });
    test('kode error pengenal terbaca dari string bawaan', () {
      expect(voiceErrorCode('kode 11'), 11);
      expect(voiceErrorCode('kode 7'), 7);
      expect(voiceErrorCode('jaringan putus'), isNull);
    });
  });

  group('struktur sumber layanan suara (Ronde 8065)', () {
    final src = File('lib/services/voice_service.dart').readAsStringSync();
    test('veto lama hilang; kebijakan & penanda sesi terpasang', () {
      expect(src.contains('decideVoiceResolution'), isTrue);
      expect(src.contains('voiceFailureWording'), isTrue);
      expect(src.contains('_finalHandled'), isTrue);
      expect(src.contains('_disconnectRetried'), isTrue);
      // Blok veto lama ("Keyakinan rendah: minta ulangi" SEBELUM urai)
      // tidak boleh hidup lagi.
      expect(src.contains('if (confidence != null && confidence < 0.5) {'),
          isFalse);
    });
  });
}
