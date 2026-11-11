import 'package:clai/services/ambient_theme.dart';
import 'package:clai/services/local_files.dart';
import 'package:clai/services/lyrics_service.dart';
import 'package:clai/ui/lyrics_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tes Ronde Bangun Gelombang 2 (staging 8048): nada pekat §11.9 untuk
/// sampul arbitrer + gerbang keadaan lembar lirik (regresi noTrack).
void main() {
  group('deepToneFromColor (§11.9 untuk sampul arbitrer)', () {
    test('rona netral jatuh ke Volt — abu tidak dikarang jadi warna', () {
      expect(deepToneFromColor(const Color(0xFF8A8A8A)), ClaiColorsVolt);
      expect(deepToneFromColor(const Color(0xFF3C3C40)), ClaiColorsVolt);
    });

    test('rona jenuh masuk pita lightness tegas 0,45–0,68', () {
      for (final c in [
        const Color(0xFFB3541E), // amber sampul contoh
        const Color(0xFF1E5FB3),
        const Color(0xFF7A1FA2),
        const Color(0xFF0E7A3D),
      ]) {
        final tone = deepToneFromColor(c);
        final hsl = HSLColor.fromColor(tone);
        // Pita diatur 0,45–0,58 (+ undakan kontras s.d. 0,68); bacaan
        // balik boleh bergeser ±0,01 oleh kuantisasi 8-bit warna.
        expect(hsl.lightness, inInclusiveRange(0.44, 0.68),
            reason: 'tone $tone dari $c');
        expect(hsl.saturation, greaterThanOrEqualTo(0.55),
            reason: 'tone $tone dari $c');
        expect(contrastOf(tone, const Color(0xFF070406)),
            greaterThanOrEqualTo(3.0));
      }
    });

    test('deterministik: warna sama → nada sama', () {
      const c = Color(0xFFB3541E);
      expect(deepToneFromColor(c), deepToneFromColor(c));
    });

    test('progressToneFor palet nonaktif tetap Volt', () {
      expect(progressToneFor(AmbientPalette.inactive), ClaiColorsVolt);
    });
  });

  group('gerbang lirik (regresi noTrack 8048)', () {
    test('tanpa trek → noTrack, BUKAN loading abadi', () {
      expect(lyricsGateState(hasTrack: false), LyricsViewState.noTrack);
    });

    test('ada trek → loading sambil memuat', () {
      expect(lyricsGateState(hasTrack: true), LyricsViewState.loading);
    });

    test('pemetaan data → keadaan jujur', () {
      expect(lyricsStateFor(null), LyricsViewState.notFound);
      expect(lyricsStateFor(const LyricsData(source: 'error')),
          LyricsViewState.netError);
      expect(
          lyricsStateFor(
              const LyricsData(source: 'LRCLIB', instrumental: true)),
          LyricsViewState.instrumental);
      expect(
          lyricsStateFor(const LyricsData(
              source: 'LRCLIB',
              lines: [LyricsLine(Duration.zero, 'satu')])),
          LyricsViewState.synced);
      expect(
          lyricsStateFor(
              const LyricsData(source: 'LRCLIB', plain: 'teks polos')),
          LyricsViewState.plain);
    });
  });

  group('localFormatLabel (chip format Berkas Lokal dari MIME nyata)', () {
    test('keluarga MIME yang dikenali terpetakan', () {
      expect(localFormatLabel('audio/mpeg'), 'MP3');
      expect(localFormatLabel('audio/flac'), 'FLAC');
      expect(localFormatLabel('audio/x-flac'), 'FLAC');
      expect(localFormatLabel('audio/mp4'), 'M4A');
      expect(localFormatLabel('audio/aac'), 'AAC');
      expect(localFormatLabel('audio/ogg'), 'OGG');
      expect(localFormatLabel('audio/opus'), 'OPUS');
      expect(localFormatLabel('audio/x-wav'), 'WAV');
    });

    test('tak dikenal / kosong → null (UI tidak menebak format)', () {
      expect(localFormatLabel(null), isNull);
      expect(localFormatLabel(''), isNull);
      expect(localFormatLabel('audio/x-aneh'), isNull);
      expect(localFormatLabel(' AUDIO/MPEG '), 'MP3');
    });
  });
}

/// Volt baku DS (#B8F135) — dirujuk lewat token agar tes ikut berubah
/// bila token resmi berubah.
const ClaiColorsVolt = Color(0xFFB8F135);
