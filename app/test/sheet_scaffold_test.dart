import 'package:clai/ui/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// ClaiSheetScaffold (v4.3) — regresi cacat perangkat v4.2: menu konteks trek
/// menampilkan "BOTTOM OVERFLOWED BY 3.6 PIXELS" karena kolom sheet tetap.
/// Rangka baru membatasi tinggi (85% layar) dan membuat isi bisa digulir:
/// pada layar pendek + font besar pun tidak boleh ada luapan, dan item terakhir
/// harus tercapai lewat gulir.
void main() {
  testWidgets('sheet tinggi penuh tidak meluap pada layar pendek & font besar', (tester) async {
    tester.view.physicalSize = const Size(720, 960); // 360x480 dp @2x — layar pendek
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.3)),
        child: child!,
      ),
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: Material(
            child: ClaiSheetScaffold(children: [
              for (var i = 0; i < 10; i++)
                ListTile(title: Text('Aksi $i'), minTileHeight: 52),
            ]),
          ),
        ),
      ),
    ));
    expect(tester.takeException(), isNull, reason: 'tidak boleh ada RenderFlex overflow');
    // Item terakhir terlipat di bawah tepi sheet sebelum digulir (posisi
    // geometrisnya melewati tinggi layar uji 480dp), masuk sesudah digulir.
    expect(tester.getTopLeft(find.text('Aksi 9')).dy, greaterThan(480));
    await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('Aksi 9')).dy, lessThan(480));
    expect(tester.takeException(), isNull);
  });

  testWidgets('sheet pendek tampil utuh tanpa gulir paksa', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: Material(
            child: ClaiSheetScaffold(children: [
              ListTile(title: Text('Satu-satunya aksi')),
            ]),
          ),
        ),
      ),
    ));
    expect(find.text('Satu-satunya aksi'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
