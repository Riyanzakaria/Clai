// Ronde 8085 — Kedip Hitam Beranda, Opsi 1 (laporan bedah
// builds/bukti-kedip-beranda/LAPORAN.md).
//
// Kontrak yang diuji:
// (a) Konfigurasi tema: builder Android di buildClaiTheme() adalah
//     PredictiveBackPageTransitionsBuilder dengan fallbackColor
//     TRANSPARAN (properti publik SDK 3.47.7 — fallbackColor diteruskan
//     SDK ke FadeForwardsPageTransitionsBuilder.backgroundColor, dan
//     _delegatedTransition melukis ColoredBox dengan warna itu selama
//     secondaryAnimation berjalan). Platform lain tetap pembangun
//     bawaan kerangka.
// (b) Perilaku: selama pop dua rute berjalan, TIDAK ada ColoredBox
//     berwarna ColorScheme.surface (#121218 = ClaiColors.surface1)
//     di pohon — kotak delegasi yang ada berwarna transparan, jadi
//     wash ambient cangkang menembus.
import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:clai/app.dart';
import 'package:clai/core/tokens.dart';

void main() {
  group('Kedip Beranda 8085 — konfigurasi tema transisi', () {
    // testWidgets: buildClaiTheme memakai GoogleFonts (lihat preseden
    // ronde_8083_kit_test.dart).
    testWidgets('builder Android PredictiveBack fallbackColor transparan', (
      tester,
    ) async {
      final theme = buildClaiTheme();
      final builders = theme.pageTransitionsTheme.builders;

      final android = builders[TargetPlatform.android];
      expect(android, isA<PredictiveBackPageTransitionsBuilder>());
      expect(
        (android! as PredictiveBackPageTransitionsBuilder).fallbackColor,
        Colors.transparent,
      );

      // Platform lain tidak diubah: pembangun bawaan kerangka persis.
      expect(
        builders[TargetPlatform.iOS],
        isA<CupertinoPageTransitionsBuilder>(),
      );
      expect(
        builders[TargetPlatform.macOS],
        isA<CupertinoPageTransitionsBuilder>(),
      );
      expect(builders[TargetPlatform.windows], isA<ZoomPageTransitionsBuilder>());
      expect(builders[TargetPlatform.linux], isA<ZoomPageTransitionsBuilder>());
    });

    testWidgets('selama pop: nol ColoredBox #121218, delegasi transparan', (
      tester,
    ) async {
      final theme = buildClaiTheme();
      expect(theme.colorScheme.surface, ClaiColors.surface1);

      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          const Scaffold(body: Center(child: Text('Turunan'))),
                    ),
                  ),
                  child: const Text('Buka turunan'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Buka turunan'));
      await tester.pumpAndSettle();
      expect(find.text('Turunan'), findsOneWidget);

      // Pop non-gestur, lalu bekukan di tengah transisi 450 mdtk:
      // secondaryAnimation rute bawah sedang berjalan, jadi inilah
      // jendela tempat ColoredBox delegasi dulu melukis #121218.
      final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
      nav.pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final boxes = tester
          .widgetList<ColoredBox>(find.byType(ColoredBox))
          .toList();
      expect(
        boxes.where((b) => b.color == ClaiColors.surface1),
        isEmpty,
        reason: 'ColoredBox delegasi tidak boleh lagi berwarna surface',
      );
      expect(
        boxes.where((b) => b.color == Colors.transparent),
        isNotEmpty,
        reason: 'ColoredBox delegasi transparan harus hadir selama transisi',
      );

      await tester.pumpAndSettle();
      expect(find.text('Buka turunan'), findsOneWidget);
    });
  });
}
