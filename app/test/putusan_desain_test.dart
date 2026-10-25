import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:clai/app.dart';
import 'package:clai/core/tokens.dart';
import 'package:clai/l10n/l10n.dart';
import 'package:clai/player/audio_handler.dart';
import 'package:clai/player/queue_engine.dart';
import 'package:clai/services/cover_accent.dart';
import 'package:clai/ui/cover_accent_glow.dart';
import 'package:clai/ui/home_screen.dart';
import 'package:clai/ui/mini_player.dart';

/// Ronde Putusan Desain (perintah/temuan pemilik atas build 2009,
/// 25 Okt 2026) — uji per butir A (kartu sesi), B (gradasi chrome),
/// C (mini player bertinta penuh), D (sinkronisasi indikator acak).
void main() {
  group('butir A — SessionCardInfo muat di lebar 360–430, ID & EN', () {
    Future<void> pumpCard(
      WidgetTester tester,
      double width,
      Locale locale,
    ) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          locale: locale,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            backgroundColor: ClaiColors.base,
            body: Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Container(
                  key: const ValueKey('card-under-test'),
                  padding: const EdgeInsets.all(14),
                  decoration: const BoxDecoration(color: ClaiColors.surface2),
                  child: Row(
                    children: [
                      // Blok sampul persis geometri kartu asli: glow pad 8 +
                      // sampul 96 + jarak 14.
                      const SizedBox(width: 112, height: 112),
                      const SizedBox(width: 14),
                      Expanded(
                        child: SessionCardInfo(
                          title:
                              'Judul Lagu yang Sangat Panjang Sekali Sampai Harus Terpotong',
                          artist:
                              'Artis Dengan Nama Panjang • Album Panjang • 2024',
                          position: const Duration(minutes: 3, seconds: 24),
                          duration: const Duration(minutes: 3, seconds: 47),
                          playing: false,
                          liked: true,
                          onPrevious: () {},
                          onNext: () {},
                          onPlayPause: () {},
                          onToggleLike: () {},
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    for (final width in [360.0, 411.0, 430.0]) {
      for (final locale in [const Locale('id'), const Locale('en')]) {
        testWidgets(
          'lebar ${width.toInt()}dp locale ${locale.languageCode}: tanpa luapan, waktu utuh di dalam kartu',
          (tester) async {
            await pumpCard(tester, width, locale);
            expect(
              tester.takeException(),
              isNull,
              reason: 'tidak boleh ada RenderFlex overflow',
            );
            final time = find.byKey(const ValueKey('session-card-time'));
            expect(time, findsOneWidget);
            expect(find.text('3:24 / 3:47'), findsOneWidget);
            final cardRect = tester.getRect(
              find.byKey(const ValueKey('card-under-test')),
            );
            final timeRect = tester.getRect(time);
            expect(
              timeRect.right,
              lessThanOrEqualTo(cardRect.right),
              reason: 'tepi kanan teks waktu harus di dalam kartu',
            );
            expect(timeRect.left, greaterThanOrEqualTo(cardRect.left));
            // Semua kontrol hadir: sebelumnya, putar, berikutnya, suka.
            expect(
              find.byTooltip(
                locale.languageCode == 'id' ? 'Lagu sebelumnya' : 'Previous track',
              ),
              findsOneWidget,
            );
            expect(find.byType(IconButton), findsNWidgets(3));
          },
        );
      }
    }
  });

  group('butir C — permukaan mini player bertinta sampul', () {
    ({int r, int g, int b}) rgbOf(Color c) => (
      r: (c.r * 255).round(),
      g: (c.g * 255).round(),
      b: (c.b * 255).round(),
    );
    const inkSecondary = (r: 0xA8, g: 0xAE, b: 0xA4);

    test('tanpa aksen → permukaan netral DS', () {
      expect(miniPlayerSurfaceColor(null), ClaiColors.surface2);
    });

    test('tonal gelap khas (sampul merah) lolos tanpa diubah', () {
      const tonal = Color(0xFF5D191F); // tonal rumus t=0,50 dari merah jenuh
      expect(
        contrastRatioRgb(inkSecondary, rgbOf(tonal)),
        greaterThanOrEqualTo(4.5),
      );
      expect(miniPlayerSurfaceColor(tonal), tonal);
    });

    test(
      'tonal terang luar biasa (kuning) digelapkan sampai teks kontras, rona dipertahankan',
      () {
        const tonal = Color(0xFF7A7332);
        final surface = miniPlayerSurfaceColor(tonal);
        expect(surface, isNot(tonal));
        expect(
          contrastRatioRgb(inkSecondary, rgbOf(surface)),
          greaterThanOrEqualTo(4.5),
        );
        final s = rgbOf(surface);
        // Rona kuning zaitun dipertahankan: kanal merah & hijau di atas biru.
        expect(s.r, greaterThan(s.b));
        expect(s.g, greaterThan(s.b));
      },
    );

    test(
      'readableSurfaceRgb: permukaan putih ekstrem berakhir kontras juga',
      () {
        final out = readableSurfaceRgb(
          (r: 255, g: 255, b: 255),
          inkSecondary,
          (r: 0x0A, g: 0x0A, b: 0x0E),
        );
        expect(contrastRatioRgb(inkSecondary, out), greaterThanOrEqualTo(4.5));
      },
    );
  });

  group('butir B — gradasi chrome bawah', () {
    test(
      'tanpa aksen: gradasi netral 3 hentian, zona nav semi-transparan '
      '(Koreksi Gradasi)',
      () {
        final colors = chromeScrimColors(null);
        expect(colors.length, 3);
        expect(colors[0], ClaiColors.base.withValues(alpha: kScrimNavTopAlpha));
        expect(colors[1], ClaiColors.base.withValues(alpha: kScrimNavMidAlpha));
        expect(colors[2], ClaiColors.base.withValues(alpha: kScrimBottomAlpha));
        expect(kChromeScrimStops, [0, 0.5, 1.0]);
      },
    );

    test(
      'dengan aksen: tinta aman semi-transparan, memudar ke base di tepi bawah',
      () {
        const tonal = Color(0xFF5D191F);
        final colors = chromeScrimColors(tonal);
        final surface = readableAccentSurface(tonal);
        expect(colors[0], surface.withValues(alpha: kScrimNavTopAlpha));
        expect(colors[1], surface.withValues(alpha: kScrimNavMidAlpha));
        expect(
          colors[2],
          Color.lerp(surface, ClaiColors.base, 0.5)!
              .withValues(alpha: kScrimBottomAlpha),
        );
        // Zona nav (hentian bawah) tetap kontras untuk label redup —
        // dinilai pada piksel EFEKTIF: tinta beralfa di atas latar dasar
        // (keadaan konten tergelap di balik chrome).
        ({int r, int g, int b}) rgbOf(Color c) => (
          r: (c.r * 255).round(),
          g: (c.g * 255).round(),
          b: (c.b * 255).round(),
        );
        final bottomRgb = rgbOf(colors[2]);
        final baseRgb = rgbOf(ClaiColors.base);
        final a = colors[2].a;
        final effective = (
          r: (a * bottomRgb.r + (1 - a) * baseRgb.r).round(),
          g: (a * bottomRgb.g + (1 - a) * baseRgb.g).round(),
          b: (a * bottomRgb.b + (1 - a) * baseRgb.b).round(),
        );
        expect(
          contrastRatioRgb((r: 0x8A, g: 0x8F, b: 0x87), effective),
          greaterThanOrEqualTo(4.5),
        );
      },
    );
  });

  group('butir D — sinkronisasi mode acak ke playbackState', () {
    test('pemetaan tunggal: off→none, pure→all, smart→all', () {
      expect(
        audioServiceShuffleMode(ShuffleMode.off),
        AudioServiceShuffleMode.none,
      );
      expect(
        audioServiceShuffleMode(ShuffleMode.pure),
        AudioServiceShuffleMode.all,
      );
      expect(
        audioServiceShuffleMode(ShuffleMode.smart),
        AudioServiceShuffleMode.all,
      );
    });

    // Handler tidak bisa dibangun di unit test (konstruktornya menyentuh
    // kanal platform AudioSession/just_audio — itulah sebabnya seluruh
    // suite tidak punya uji konstruksi handler), jadi kontrak penerbitan
    // diverifikasi pada kabelnya: setiap jalur yang menetapkan
    // engine.shuffle WAJIB memanggil syncShuffleState, dan transformasi
    // peristiwa pemain memakai pemetaan yang sama. Perilaku hidupnya
    // dibuktikan di emulator (lihat RINGKASAN ronde).
    test('semua jalur penetap shuffle menerbitkan status (kabel sumber)', () {
      final handler = File('lib/player/audio_handler.dart').readAsStringSync();
      final bootstrap = File('lib/bootstrap.dart').readAsStringSync();

      final def = handler.indexOf('void syncShuffleState()');
      expect(
        def,
        greaterThanOrEqualTo(0),
        reason: 'syncShuffleState harus ada',
      );
      final defBody = handler.substring(def, def + 400);
      expect(defBody, contains('audioServiceShuffleMode(engine.shuffle)'));
      expect(defBody, contains('playbackState.add'));

      String bodyOf(String startMarker, [int window = 1600]) {
        final start = handler.indexOf(startMarker);
        expect(
          start,
          greaterThanOrEqualTo(0),
          reason: '$startMarker tidak ditemukan',
        );
        return handler.substring(start, start + window);
      }

      expect(
        bodyOf('Future<void> setSmartShuffle', 1200),
        contains('syncShuffleState();'),
        reason: 'setSmartShuffle wajib menerbitkan status',
      );
      expect(
        bodyOf('Future<void> _restoreSession', 4200),
        contains('syncShuffleState();'),
        reason: 'pemulihan sesi wajib menerbitkan status',
      );
      expect(
        bodyOf('Future<void> restoreSleepSession', 2400),
        contains('syncShuffleState();'),
        reason: 'Lanjut Besok wajib menerbitkan status',
      );
      expect(
        bootstrap,
        contains('handler!.syncShuffleState();'),
        reason: 'pref boot Acak Cerdas wajib menerbitkan status',
      );
      // _transformState memakai pemetaan yang sama (satu sumber kebenaran).
      expect(
        bodyOf('PlaybackState _transformState', 2600),
        contains('shuffleMode: audioServiceShuffleMode(engine.shuffle)'),
      );
    });
  });
}
