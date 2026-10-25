import 'package:clai/bootstrap.dart';
import 'package:clai/ui/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Uji widget sapuan: D-26 kerangka memuat berdenyut, D-05 gerak-reduksi,
/// D-35 placeholder sampul tanpa glif teks.
void main() {
  Widget wrap(Widget child, {bool reduced = false}) => MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reduced),
          child: Scaffold(body: Center(child: child)),
        ),
      );

  Color? blockColor(WidgetTester tester) {
    for (final c in tester.widgetList<Container>(find.byType(Container))) {
      if (c.color != null) return c.color;
      final d = c.decoration;
      if (d is BoxDecoration && d.color != null) return d.color;
    }
    return null;
  }

  testWidgets('D-26: LoadingSkeleton berdenyut (animasi aktif tanpa gerak-reduksi)',
      (tester) async {
    await tester.pumpWidget(wrap(const LoadingSkeleton()));
    final first = blockColor(tester);
    await tester.pump(const Duration(milliseconds: 600));
    final later = blockColor(tester);
    expect(first, isNotNull);
    expect(later, isNot(first),
        reason: 'kerangka harus berdenyut 0.6↔1.0 per DS 6.12, bukan blok statis');
  });

  testWidgets('D-05: gerak-reduksi → kerangka statis, marquee jadi elipsis',
      (tester) async {
    await tester.pumpWidget(wrap(const LoadingSkeleton(), reduced: true));
    final first = blockColor(tester);
    await tester.pump(const Duration(milliseconds: 600));
    expect(blockColor(tester), first,
        reason: 'warna kerangka TIDAK berubah saat disableAnimations sistem aktif');
    await tester.pumpWidget(wrap(
        const SizedBox(
            width: 120,
            child: MarqueeText('Judul Lagu Yang Sangat Panjang Sekali',
                style: TextStyle(fontSize: 16))),
        reduced: true));
    expect(find.byType(SingleChildScrollView), findsNothing);
    expect(find.byType(Text), findsOneWidget);
  });

  testWidgets('marquee aktif (tanpa gerak-reduksi) memakai gulir', (tester) async {
    await tester.pumpWidget(wrap(const SizedBox(
        width: 120,
        child: MarqueeText('Judul Lagu Yang Sangat Panjang Sekali',
            style: TextStyle(fontSize: 16)))));
    expect(find.byType(SingleChildScrollView), findsOneWidget);
    // Lepas widget agar putaran marquee (timer berkala) berhenti bersih.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('D-35: placeholder sampul kosong memakai ikon vektor, bukan glif ♪',
      (tester) async {
    await tester.pumpWidget(wrap(const CoverArt(size: 64, label: '')));
    expect(find.text('♪'), findsNothing);
    expect(find.byType(CustomPaint), findsWidgets,
        reason: 'glif not musik digambar ClaiIcon (DS 6.13)');
  });

  testWidgets('D-27: cache gambar dibatasi 150 MB (Blueprint 8.1)', (tester) async {
    configureImageCache();
    expect(PaintingBinding.instance.imageCache.maximumSizeBytes,
        150 * 1024 * 1024);
    expect(kImageCacheMaxBytes, 150 * 1024 * 1024);
  });

  testWidgets('D-02 golden: kerangka memuat & placeholder sampul', (tester) async {
    await tester.pumpWidget(wrap(const SizedBox(
      width: 360,
      height: 320,
      child: Column(children: [
        Expanded(child: LoadingSkeleton()),
        SizedBox(height: 8),
        CoverArt(size: 64, label: ''),
      ]),
    )));
    await expectLater(find.byType(SizedBox).first,
        matchesGoldenFile('goldens/sapuan_skeleton_cover.png'));
  });
}
