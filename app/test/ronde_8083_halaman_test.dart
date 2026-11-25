// Ronde 8083 PK4 — halaman sejenis Pengaturan + lembar Timer.
//
// Kontrak yang diuji:
// (a) Cacat B: openSleepTimerSheet TIDAK lagi memaksa lembar 55%
//     layar — tidak ada FractionallySizedBox di pohon, tinggi lembar
//     terukur < 55% tinggi layar uji, dan sumber tidak mengandung
//     "heightFactor".
// (b) Laci Menu (R3): tepat 4 pintu, masing-masing baris datar
//     setinggi 68±2 (pitch disiplin ronde 8089, DS §14.6), subjudul
//     satu baris ringkas DI DALAM baris itu
//     (spesifikasi R3 + maket L7; keberadaan teks subjudulnya sendiri
//     terkunci di menu_laci_8079_test.dart).
// (c) Uji sumber terarah: sleep_timer_sheet.dart tidak mengandung
//     "0.55".
import 'dart:io';

import 'package:clai/app.dart';
import 'package:clai/l10n/app_localizations.dart';
import 'package:clai/services/sleep_service.dart';
import 'package:clai/ui/menu_drawer.dart';
import 'package:clai/ui/sleep_timer_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('sumber — Cacat B', () {
    final src = File('lib/ui/sleep_timer_sheet.dart').readAsStringSync();

    test('openSleepTimerSheet tidak mengandung heightFactor', () {
      expect(src.contains('heightFactor'), isFalse);
    });

    test('sleep_timer_sheet.dart tidak mengandung 0.55', () {
      expect(src.contains('0.55'), isFalse);
    });

    test('sleep_timer_sheet.dart tidak memakai FractionallySizedBox', () {
      expect(src.contains('FractionallySizedBox'), isFalse);
    });
  });

  group('widget — lembar Timer memeluk isi', () {
    late SleepService service;

    testWidgets('tinggi lembar < 55% layar; tak ada FractionallySizedBox', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      service = SleepService();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [sleepServiceProvider.overrideWith((ref) => service)],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('en'),
            home: Scaffold(
              body: Builder(
                builder: (ctx) => Center(
                  child: ElevatedButton(
                    onPressed: () => openSleepTimerSheet(ctx),
                    child: const Text('buka'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('buka'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(SleepTimerSheet), findsOneWidget);
      expect(find.byType(FractionallySizedBox), findsNothing);
      final sheetSize = tester.getSize(find.byType(SleepTimerSheet));
      expect(sheetSize.height, greaterThan(0));
      expect(
        sheetSize.height,
        lessThan(0.55 * 800),
        reason: 'lembar memeluk isi 5 opsi, bukan dipaksa 55% layar (440)',
      );
      expect(tester.takeException(), isNull);

      service.cancel();
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });
  });

  group('widget — Laci Menu R3', () {
    testWidgets('tepat 4 pintu, tiap baris 68±2 (subjudul di dalam baris)', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Scaffold(
            body: Builder(
              builder: (ctx) => Center(
                child: ElevatedButton(
                  onPressed: () => showClaiMenuDrawer(ctx),
                  child: const Text('menu'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('menu'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      const doors = ['Your Taste', 'Session Vault', 'Ownership', 'Settings'];
      for (final title in doors) {
        expect(find.text(title), findsOneWidget, reason: 'pintu $title');
        final row = find.ancestor(
          of: find.text(title),
          matching: find.byType(InkWell),
        );
        expect(row, findsOneWidget, reason: 'baris pintu $title');
        final h = tester.getSize(row).height;
        expect(
          h,
          inInclusiveRange(66, 70),
          reason: 'baris pintu $title harus datar 68±2, terukur $h',
        );
      }
      // Tepat 4 pintu: di seluruh pohon, InkWell setinggi baris
      // pintu (68±2) hanya milik keempat pintu laci (tombol tutup =
      // IconButton, tombol pemanggil jauh lebih pendek).
      final doorSized = tester.widgetList<InkWell>(find.byType(InkWell)).where((
        w,
      ) {
        final s = tester.getSize(find.byWidget(w));
        return s.height >= 66 && s.height <= 70;
      }).length;
      expect(doorSized, 4, reason: 'tepat 4 baris pintu setinggi 68');
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });
  });
}
