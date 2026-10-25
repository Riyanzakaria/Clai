import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:clai/app.dart';
import 'package:clai/core/tokens.dart';
import 'package:clai/services/cover_accent.dart';
import 'package:clai/ui/cover_accent_glow.dart';

/// Ronde Koreksi Gradasi (klarifikasi + perintah pemilik atas build 2010,
/// 25 Okt 2026). DUA koreksi atas Butir B build 2010:
/// 1. SEMI-TRANSPARAN: 2010 memakai warna permukaan opak penuh (alfa 1.0)
///    persis di zona ketinggian ikon navigasi, sehingga gradasi terbaca
///    blok warna dan konten yang digulir tidak menembus sama sekali.
///    Kini seluruh ruas yang dilukis beralfa parsial.
/// 2. TINGGI LUKISAN DIPANGKAS: gradasi hanya boleh hidup DI BAWAH mini
///    player ("dibawah miniplayer, ga sampe miniplayer") — pita pudar
///    +56 dp di atas gugus dihapus; tepi atas scrim duduk di tepi BAWAH
///    kartu mini, menaungi margin bawah kartu + bilah nav + inset saja.
///
/// Pilihan yang dinyatakan & diuji di sini:
/// - Profil alfa mengikuti referensi Spotify kiriman pemilik: berjangkar
///   di BAWAH — 0.32 di tepi atas ruas (di bawah kartu) → 0.55 di tengah
///   (zona ikon) → 0.85 di tepi paling bawah. TIPIS adalah kata kunci:
///   konten di balik nav terbaca jelas menembus; jangkar keterbacaan
///   seminimal yang masih membuat ikon/label terbaca.
/// - Tinggi lukisan = [chromeScrimHeight] = margin 1 + nav 54 + inset;
///   TIDAK memuat tinggi kartu, celah atas, atau pita pudar apa pun.
/// - Matematika tembus cahaya dibuktikan dengan komposit alfa: piksel
///   zona nav di atas konten terang berbeda nyata dari warna scrim
///   murni (yang akan terlihat bila scrim opak).

({int r, int g, int b}) _rgbOf(Color c) => (
      r: (c.r * 255).round(),
      g: (c.g * 255).round(),
      b: (c.b * 255).round(),
    );

/// Komposit "source-over" warna [fg] beralfa di atas latar [bgRgb].
({int r, int g, int b}) _compositeOver(Color fg, ({int r, int g, int b}) bgRgb) {
  final f = _rgbOf(fg);
  final a = fg.a;
  return (
    r: (a * f.r + (1 - a) * bgRgb.r).round(),
    g: (a * f.g + (1 - a) * bgRgb.g).round(),
    b: (a * f.b + (1 - a) * bgRgb.b).round(),
  );
}

/// Alfa efektif gradasi pada posisi [t] (interpolasi linear antar
/// hentian, sama seperti render LinearGradient).
double _alphaAt(List<Color> colors, double t) {
  final stops = kChromeScrimStops;
  for (var i = 0; i < stops.length - 1; i++) {
    if (t <= stops[i + 1]) {
      final f = (t - stops[i]) / (stops[i + 1] - stops[i]);
      return colors[i].a + (colors[i + 1].a - colors[i].a) * f;
    }
  }
  return colors.last.a;
}

void main() {
  group('koreksi gradasi — tinggi lukisan hanya di bawah mini player', () {
    test('chromeScrimHeight = margin bawah kartu + nav + inset, itu saja', () {
      expect(chromeScrimHeight(0), kMiniPlayerBottomMargin + kNavBarHeight);
      expect(chromeScrimHeight(0), 55);
      expect(
        chromeScrimHeight(24),
        kMiniPlayerBottomMargin + kNavBarHeight + 24,
      );
      // Tidak memuat kartu mini, celah atas, atau pita pudar:
      // tinggi lukisan jauh di bawah tinggi gugus penuh.
      final clusterTanpaInset =
          kChromeTopGap + kMiniPlayerHeight + kMiniPlayerBottomMargin + kNavBarHeight;
      expect(chromeScrimHeight(0), lessThan(clusterTanpaInset));
    });

    test('kabel sumber: pelukis memakai chromeScrimHeight & pita pudar '
        'sudah tidak ada di app.dart', () {
      final src = File('lib/app.dart').readAsStringSync();
      expect(src, contains('height: chromeScrimHeight(bottomInset)'));
      expect(src, isNot(contains('kScrimFadeHeight')));
    });
  });

  group('koreksi gradasi — alfa zona nav', () {
    test('netral: seluruh hentian beralfa parsial (tak ada yang opak)', () {
      final colors = chromeScrimColors(null);
      expect(colors.length, 3);
      for (final c in colors) {
        expect(c.a, lessThan(1.0));
      }
      expect(colors[0].a, kScrimNavTopAlpha);
      expect(colors[1].a, kScrimNavMidAlpha);
      expect(colors[2].a, kScrimBottomAlpha);
    });

    test('aksen: seluruh hentian beralfa parsial (tak ada yang opak)', () {
      final colors = chromeScrimColors(const Color(0xFF5D191F));
      expect(colors.length, 3);
      for (final c in colors) {
        expect(c.a, lessThan(1.0));
      }
      expect(colors[0].a, kScrimNavTopAlpha);
      expect(colors[1].a, kScrimNavMidAlpha);
      expect(colors[2].a, kScrimBottomAlpha);
    });

    test('profil alfa seperti referensi: tipis di atas, menggelap ke '
        'bawah (0.32 → 0.55 → 0.85)', () {
      for (final tonal in <Color?>[null, const Color(0xFF5D191F)]) {
        final colors = chromeScrimColors(tonal);
        expect(_alphaAt(colors, 0), 0.32);
        expect(_alphaAt(colors, 0.5), 0.55);
        expect(_alphaAt(colors, 1.0), 0.85);
        // Berjangkar di bawah: alfa monoton naik ke arah tepi bawah.
        expect(_alphaAt(colors, 0), lessThan(_alphaAt(colors, 0.5)));
        expect(_alphaAt(colors, 0.5), lessThan(_alphaAt(colors, 1.0)));
        // Zona ikon (±tengah ruas): tipis — konten dominan menembus.
        final mid = _alphaAt(colors, 0.5);
        expect(mid, greaterThan(0.40));
        expect(mid, lessThan(0.70));
      }
    });

    test('konstanta profil yang dinyatakan', () {
      expect(kScrimNavTopAlpha, 0.32);
      expect(kScrimNavMidAlpha, 0.55);
      expect(kScrimBottomAlpha, 0.85);
    });
  });

  group('koreksi gradasi — matematika tembus cahaya', () {
    const bright = (r: 200, g: 200, b: 200);

    test('netral: piksel zona nav di atas konten terang ≠ scrim murni', () {
      final colors = chromeScrimColors(null);
      // Tengah ruas (zona ikon, alfa 0.55): konten menyumbang 45% piksel
      // — sampul di baliknya terbaca, bukan sekadar menyirip.
      final mid = _compositeOver(colors[1], bright);
      final midPure = _rgbOf(colors[1]);
      expect((mid.r - midPure.r).abs(), greaterThanOrEqualTo(25));
      expect((mid.g - midPure.g).abs(), greaterThanOrEqualTo(25));
      expect((mid.b - midPure.b).abs(), greaterThanOrEqualTo(25));
      // Tepi bawah (alfa 0.85) pun masih tembus, bukan opak:
      final bottom = _compositeOver(colors.last, bright);
      final bottomPure = _rgbOf(colors.last);
      expect((bottom.r - bottomPure.r).abs(), greaterThanOrEqualTo(12));
      expect((bottom.g - bottomPure.g).abs(), greaterThanOrEqualTo(12));
      expect((bottom.b - bottomPure.b).abs(), greaterThanOrEqualTo(12));
    });

    test('aksen: piksel zona nav di atas konten terang ≠ scrim murni', () {
      final colors = chromeScrimColors(const Color(0xFF5D191F));
      final mid = _compositeOver(colors[1], bright);
      final midPure = _rgbOf(colors[1]);
      expect((mid.r - midPure.r).abs(), greaterThanOrEqualTo(25));
      expect((mid.g - midPure.g).abs(), greaterThanOrEqualTo(25));
      expect((mid.b - midPure.b).abs(), greaterThanOrEqualTo(25));
      final bottom = _compositeOver(colors.last, bright);
      final bottomPure = _rgbOf(colors.last);
      expect((bottom.r - bottomPure.r).abs(), greaterThanOrEqualTo(12));
      expect((bottom.g - bottomPure.g).abs(), greaterThanOrEqualTo(12));
      expect((bottom.b - bottomPure.b).abs(), greaterThanOrEqualTo(12));
    });

    test('lantai keterbacaan: label redup tetap ≥4.5:1 di atas konten '
        'terang realistis (abu 144) pada tepi bawah netral', () {
      final bottom = chromeScrimColors(null).last;
      final eff = _compositeOver(bottom, (r: 144, g: 144, b: 144));
      expect(
        contrastRatioRgb((r: 0x8A, g: 0x8F, b: 0x87), eff),
        greaterThanOrEqualTo(4.5),
      );
    });

    test('baris label (alfa ±0.70) di atas ubin terang nyata (merah muda '
        '194,77,121): label terpilih jauh di atas ambang, label redup '
        'tetap terbaca — kompromi "tipis" yang dinyatakan pemilik', () {
      final atLabelRow =
          ClaiColors.base.withValues(alpha: 0.70);
      final eff = _compositeOver(atLabelRow, (r: 194, g: 77, b: 121));
      expect(
        contrastRatioRgb((r: 0xF4, g: 0xF6, b: 0xF1), eff),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        contrastRatioRgb((r: 0x8A, g: 0x8F, b: 0x87), eff),
        greaterThanOrEqualTo(4.0),
      );
    });

    test('rona sampul tetap terasa: zona nav beraksen berbeda dari netral', () {
      const tonal = Color(0xFF5D191F);
      final surface = readableAccentSurface(tonal);
      final accent = chromeScrimColors(tonal);
      expect(_rgbOf(accent[0]), _rgbOf(surface));
      expect(_rgbOf(accent[1]), _rgbOf(surface));
      expect(accent.last, isNot(chromeScrimColors(null).last));
      expect(ClaiColors.base, isNot(surface));
    });
  });
}
