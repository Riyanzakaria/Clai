import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:clai/app.dart';
import 'package:clai/core/tokens.dart';
import 'package:clai/services/cover_accent.dart';
import 'package:clai/ui/cover_accent_glow.dart';

/// Ronde Perbaikan Scrim (vonis pemilik 2026-11-09 10:06 atas tangkapan
/// HP-nya sendiri, build 6035). Cacat yang ditunjuknya pada gradasi
/// chrome — "yang aku maksud gradasi itu yang ini, bukan miniplayer;
/// batas gradasi dengan miniplayer nya kan masih keliatan, harus
/// dibikin lebih mulus":
/// 1. Judul rak terang ("Koleksi Kamu") TERBACA menghantui di belakang
///    ikon/label nav — profil warisan 0,32/0,55/0,85 (kalibrasi "tipis
///    seperti Spotify", 25 Okt 2026) memang dirancang tembus cahaya.
/// 2. Garis perbatasan yang bisa ditunjuk di tepi mini player: alfa
///    awal 0,32 tepat di bawah kartu (warisan) dan, pada mode tema,
///    sambungan falloff 0,85 ↔ penopang pekat tepat di tepi atas kartu.
///
/// Standar baru yang dinyatakan & diuji di sini (kedua mode):
/// - Gradasi mencapai alfa ≥0,97 pada titik yang masih TERTUTUP di
///   balik kartu mini, dan ≥0,99 tepat di tepi bawah kartu — profil
///   latar melintasi tepi kartu tanpa anak tangga yang bisa ditunjuk.
/// - Di zona nav alfa mencapai 1,00: teks terang yang terparkir di
///   belakang nav tersisa ≤1% cahayanya — tak terbaca.
/// - Fade yang TERLIHAT (falloff tema di atas kartu) tetap panjang
///   250 dp dan mulus seperti resep papan yang disetujui.
/// Bukti piksel kasus-ujinya (judul terang diparkir di belakang nav,
/// sebelum vs sesudah) disimpan di builds/bukti-scrim-f3.

/// CATATAN 8046 (putusan final pemilik 2026-11-10 11:43): bagian
/// tema-hidup dari standar di atas (falloff + lapisan penutup +
/// fade zona nav mode tema) TERGANTIKAN — mekanismenya dihapus
/// total dari kode dan grup tesnya diganti grup 'chrome bersih
/// (8046)' di berkas ini. Yang tetap berlaku dari berkas ini:
/// seluruh standar mode warisan (tema mati).

({int r, int g, int b}) _rgbOf(Color c) =>
    (r: (c.r * 255).round(), g: (c.g * 255).round(), b: (c.b * 255).round());

/// Komposit "source-over" warna [fg] beralfa di atas latar [bgRgb].
({int r, int g, int b}) _compositeOver(
  Color fg,
  ({int r, int g, int b}) bgRgb,
) {
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
double _alphaAt(List<Color> colors, List<double> stops, double t) {
  for (var i = 0; i < stops.length - 1; i++) {
    if (t <= stops[i + 1]) {
      final f = (t - stops[i]) / (stops[i + 1] - stops[i]);
      return colors[i].a + (colors[i + 1].a - colors[i].a) * f;
    }
  }
  return colors.last.a;
}

/// Alfa efektif pada jarak [dp] dari tepi atas lukisan setinggi
/// [height].
double _alphaAtDp(
  ({List<Color> colors, List<double> stops}) g,
  double dp,
  double height,
) => _alphaAt(g.colors, g.stops, dp / height);

void main() {
  group('perbaikan scrim — tinggi lukisan warisan', () {
    test('chromeScrimHeight = margin bawah kartu + nav + inset, itu saja', () {
      expect(chromeScrimHeight(0), kMiniPlayerBottomMargin + kNavBarHeight);
      expect(chromeScrimHeight(0), 55);
      expect(
        chromeScrimHeight(24),
        kMiniPlayerBottomMargin + kNavBarHeight + 24,
      );
    });

    test('tinggi lukisan = pita sudut tertutup kartu + ruas bawah kartu; '
        'tetap jauh di bawah tinggi gugus penuh', () {
      expect(chromeScrimPaintHeight(0), kChromeScrimTuck + 55);
      expect(chromeScrimPaintHeight(24), kChromeScrimTuck + 55 + 24);
      final clusterTanpaInset =
          kChromeTopGap +
          kMiniPlayerHeight +
          kMiniPlayerBottomMargin +
          kNavBarHeight;
      expect(chromeScrimPaintHeight(0), lessThan(clusterTanpaInset));
    });

    test('kabel sumber: pelukis memakai chromeScrimPaintHeight & '
        'chromeScrimGradient; pita pudar lama tetap tidak ada', () {
      final src = File('lib/app.dart').readAsStringSync();
      expect(src, contains('height: chromeScrimPaintHeight(bottomInset)'));
      expect(src, contains('chromeScrimGradient('));
      expect(src, isNot(contains('kScrimFadeHeight')));
    });
  });

  group('perbaikan scrim — profil alfa warisan baru', () {
    const h0 = 71.0; // tinggi lukisan pada inset 0: tuck 16 + 55

    test('netral: 5 hentian, alfa pita [0.88, 0.97, 0.99, 1.0] + terminal', () {
      final g = chromeScrimGradient(null, h0);
      expect(g.colors.length, 5);
      expect(g.stops.length, 5);
      expect(g.colors.map((c) => c.a).toList(), [0.88, 0.97, 0.99, 1.0, 1.0]);
      for (final c in g.colors) {
        expect(_rgbOf(c), _rgbOf(ClaiColors.base));
      }
      expect(g.stops, [0, 6 / h0, 16 / h0, 40 / h0, 1.0]);
    });

    test('aksen: alfa sama, rona permukaan dipertahankan lalu menggeser '
        'ke base', () {
      const tonal = Color(0xFF5D191F);
      final surface = readableAccentSurface(tonal);
      final g = chromeScrimGradient(tonal, h0);
      expect(g.colors.map((c) => c.a).toList(), [0.88, 0.97, 0.99, 1.0, 1.0]);
      expect(_rgbOf(g.colors[0]), _rgbOf(surface));
      expect(_rgbOf(g.colors[1]), _rgbOf(surface));
      expect(_rgbOf(g.colors[2]), _rgbOf(surface));
      expect(
        g.colors[3],
        Color.lerp(surface, ClaiColors.base, 0.35)!.withValues(alpha: 1.0),
      );
      expect(
        g.colors[4],
        Color.lerp(surface, ClaiColors.base, 0.5)!.withValues(alpha: 1.0),
      );
      expect(g.colors[4], isNot(chromeScrimGradient(null, h0).colors[4]));
    });

    test('jangkar profil: 0,97 tertutup kartu, 0,99 di tepi bawah kartu, '
        '1,00 di zona nav; monoton tanpa anak tangga', () {
      for (final tonal in <Color?>[null, const Color(0xFF5D191F)]) {
        final g = chromeScrimGradient(tonal, h0);
        expect(_alphaAtDp(g, 0, h0), 0.88);
        expect(_alphaAtDp(g, 6, h0), closeTo(0.97, 1e-9));
        // Tepi bawah kartu duduk pada dp = tuck:
        expect(_alphaAtDp(g, kChromeScrimTuck, h0), closeTo(0.99, 1e-9));
        expect(_alphaAtDp(g, 40, h0), 1.0);
        expect(_alphaAtDp(g, h0, h0), 1.0);
        var prev = _alphaAtDp(g, 0, h0);
        for (var dp = 1; dp <= h0; dp++) {
          final a = _alphaAtDp(g, dp.toDouble(), h0);
          expect(
            a,
            greaterThanOrEqualTo(prev - 1e-9),
            reason: 'alfa turun pada dp=$dp',
          );
          expect(
            a - prev,
            lessThanOrEqualTo(0.02),
            reason: 'anak tangga pada dp=$dp: $prev → $a',
          );
          prev = a;
        }
      }
    });

    test('konstanta profil yang dinyatakan', () {
      expect(kChromeScrimTuck, 16);
      expect(kChromeScrimBandDp, [0, 6, 16, 40]);
      expect(kChromeScrimBandAlphas, [0.88, 0.97, 0.99, 1.0]);
      // Titik nyaris-pekat (0,97 pada +6 dp) masih di dalam pita yang
      // tertutup kartu (tuck 16 dp) — bukan di zona terlihat.
      expect(kChromeScrimBandDp[1], lessThan(kChromeScrimTuck));
      // Pita tuck sejajar radius sudut bawah kartu: busur sudut kartu
      // seluruhnya tertopang gradasi.
      expect(kChromeScrimTuck, ClaiRadius.card);
    });
  });

  group('perbaikan scrim — matematika penekanan hantu', () {
    const bright = (r: 200, g: 200, b: 200);
    const dark = (r: 10, g: 10, b: 14);

    int maxChannelDiff(({int r, int g, int b}) a, ({int r, int g, int b}) b) =>
        [
          (a.r - b.r).abs(),
          (a.g - b.g).abs(),
          (a.b - b.b).abs(),
        ].reduce((x, y) => x > y ? x : y);

    test('netral: di tepi bawah kartu (alfa 0,99) konten terang vs gelap '
        'nyaris tak bisa dibedakan (≤3/255 per kanal)', () {
      final g = chromeScrimGradient(null, 71);
      final overBright = _compositeOver(g.colors[2], bright);
      final overDark = _compositeOver(g.colors[2], dark);
      expect(maxChannelDiff(overBright, overDark), lessThanOrEqualTo(3));
    });

    test('aksen: penekanan sama kuatnya pada tinta sampul', () {
      final g = chromeScrimGradient(const Color(0xFF5D191F), 71);
      final overBright = _compositeOver(g.colors[2], bright);
      final overDark = _compositeOver(g.colors[2], dark);
      expect(maxChannelDiff(overBright, overDark), lessThanOrEqualTo(3));
    });

    test('zona nav (alfa 1,00): hantu hilang penuh — konten di baliknya '
        'tidak menyumbang apa pun', () {
      for (final tonal in <Color?>[null, const Color(0xFF5D191F)]) {
        final g = chromeScrimGradient(tonal, 71);
        for (final stop in [g.colors[3], g.colors[4]]) {
          final overBright = _compositeOver(stop, bright);
          final overDark = _compositeOver(stop, dark);
          expect(maxChannelDiff(overBright, overDark), 0);
        }
      }
    });

    test('lantai keterbacaan: label redup ≥4.5:1 di atas warna terminal '
        'netral maupun aksen (label digambar DI ATAS scrim pekat)', () {
      for (final tonal in <Color?>[null, const Color(0xFF5D191F)]) {
        final terminal = chromeScrimGradient(tonal, 71).colors[4];
        expect(
          contrastRatioRgb((r: 0x8A, g: 0x8F, b: 0x87), _rgbOf(terminal)),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          contrastRatioRgb((r: 0xF4, g: 0xF6, b: 0xF1), _rgbOf(terminal)),
          greaterThanOrEqualTo(4.5),
        );
      }
    });

    test('rona sampul tetap terasa: zona nav beraksen berbeda dari netral', () {
      const tonal = Color(0xFF5D191F);
      final surface = readableAccentSurface(tonal);
      final accent = chromeScrimGradient(tonal, 71);
      expect(_rgbOf(accent.colors[0]), _rgbOf(surface));
      expect(accent.colors[4], isNot(chromeScrimGradient(null, 71).colors[4]));
      expect(ClaiColors.base, isNot(surface));
    });
  });

  // ------------------------------------------------------------ 8046
  // Chrome bersih (putusan final pemilik 2026-11-10 11:43): tema
  // hidup tidak melukis latar apa pun di sekitar chrome. Falloff,
  // lapisan penutup, dan fade zona nav mode tema DIHAPUS dari
  // kode; yang tersisa hanya scrim warisan (tema mati) + geometri
  // daerah lukis bersama yang kini melayani warisan saja.
  group('chrome bersih (8046) — tema hidup tanpa lukisan latar', () {
    test('kabel sumber: mekanisme gradasi tema hidup sudah tidak '
        'ada di app.dart; warisan tetap terpasang', () {
      final src = File('lib/app.dart').readAsStringSync();
      // Mekanisme yang dihapus total (nama persisnya):
      expect(src, isNot(contains('chromeFalloff')));
      expect(src, isNot(contains('kChromeFalloff')));
      expect(src, isNot(contains('chromeCompletion')));
      expect(src, isNot(contains('chromeNavFadeColors')));
      expect(src, isNot(contains('chromeMiniTopOffset')));
      // Cabang lukisan hanya hidup saat tema mati:
      expect(src, contains('if (!ambOn)'));
      // Warisan tidak disentuh — scrim + fade warisan terpasang:
      expect(src, contains('chromeScrimGradient('));
      expect(src, contains('chromeNavFadeLegacyGradient('));
      expect(src, contains('ChromeBackingPainter('));
    });
  });
}
