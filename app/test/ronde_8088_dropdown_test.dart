// Ronde 8088 — Cacat dropdown tertutup mini player.
//
// Kontrak yang diuji:
// (a) GEOMETRI/LAPISAN (inti cacat): di dalam kerangka yang meniru
//     cangkang aplikasi — Navigator tab di dalam Stack, chrome bawah
//     (blok setinggi mini player + navigasi) sebagai anak Stack yang
//     LEBIH AKHIR — menu BoundedDropdown yang menjulur ke zona chrome
//     tetap menerima ketuk di TENGAH itemnya: onChanged terpicu dengan
//     nilai item itu dan chrome tidak menerima satu ketuk pun.
//     Pada implementasi lama (DropdownButton) tes ini GAGAL: menunya
//     hidup di navigator tab, di bawah chrome, sehingga ketuk tengah
//     item dicuri chrome persis seperti di perangkat/bangku.
// (b) WAJAH: tinggi tombol 48 (paritas DropdownButton), teks item
//     terpilih + ikon panah tampil, lebar terikat maxWidth, dan
//     keadaan nonaktif (onChanged null) tidak membuka menu.
// (c) PILIHAN TERAPLIKASI: mengetuk item memanggil onChanged dengan
//     nilai item itu — termasuk mengetuk item yang sedang terpilih
//     (semantik DropdownButton lama).
import 'package:clai/ui/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

BoundedDropdown<String> _dropdown({
  required String value,
  required ValueChanged<String?>? onChanged,
  double maxWidth = 176,
}) {
  return BoundedDropdown<String>(
    value: value,
    maxWidth: maxWidth,
    onChanged: onChanged,
    items: const [
      DropdownMenuItem<String>(value: 'gapless', child: Text('Gapless')),
      DropdownMenuItem<String>(value: 'crossfade', child: Text('Crossfade')),
    ],
  );
}

void main() {
  testWidgets('(a) menu di atas chrome cangkang: ketuk tengah item memilih, '
      'chrome tidak menerima ketuk', (tester) async {
    String? chosen;
    var chromeTaps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Stack(
          children: [
            Positioned.fill(
              child: Navigator(
                onGenerateRoute: (_) => MaterialPageRoute<void>(
                  builder: (_) => Scaffold(
                    body: Align(
                      alignment: Alignment.bottomCenter,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 100),
                        child: _dropdown(
                          value: 'gapless',
                          onChanged: (v) => chosen = v,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // Chrome melayang: anak Stack sesudah navigator — persis
            // susunan cangkang (mini player + navigasi bawah).
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 100,
              child: GestureDetector(
                key: const ValueKey('chrome'),
                onTap: () => chromeTaps++,
                child: Container(color: const Color(0xFF26262F)),
              ),
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Gapless').first);
    await tester.pumpAndSettle();

    // Item kedua harus ADA di pohon (menu terbuka) dan TENGAHNYA harus
    // jatuh di dalam zona chrome — kalau tidak, tes ini tidak menguji
    // cacatnya sama sekali.
    final itemFinder = find.text('Crossfade');
    expect(itemFinder, findsOneWidget);
    final itemCenter = tester.getCenter(itemFinder);
    final chromeRect = tester.getRect(find.byKey(const ValueKey('chrome')));
    expect(
      chromeRect.contains(itemCenter),
      isTrue,
      reason: 'tengah item Crossfade harus berada di zona chrome '
          '(itemCenter=$itemCenter, chrome=$chromeRect)',
    );

    await tester.tap(itemFinder);
    await tester.pumpAndSettle();

    expect(chosen, 'crossfade');
    expect(chromeTaps, 0);
  });

  testWidgets('(b) wajah: tinggi 48, lebar terikat, nonaktif tidak membuka',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: _dropdown(
              value: 'crossfade',
              onChanged: null,
              maxWidth: 176,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final size = tester.getSize(find.byType(BoundedDropdown<String>));
    expect(size.height, 48);
    expect(size.width, 176);
    expect(find.text('Crossfade'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_drop_down), findsOneWidget);

    // Nonaktif: ketuk tidak membuka menu apa pun.
    await tester.tap(find.byType(BoundedDropdown<String>));
    await tester.pumpAndSettle();
    expect(find.text('Gapless'), findsNothing);
  });

  testWidgets('(c) pilihan teraplikasi, termasuk item yang sedang terpilih',
      (tester) async {
    final calls = <String?>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: _dropdown(value: 'gapless', onChanged: calls.add),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Gapless').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Crossfade'));
    await tester.pumpAndSettle();
    expect(calls, ['crossfade']);

    // Buka lagi dan ketuk item yang sedang terpilih di wajah — menu
    // menampilkan kedua item; ketuk 'Gapless' di menu tetap memicu
    // onChanged (semantik DropdownButton).
    await tester.tap(find.text('Gapless').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gapless').last);
    await tester.pumpAndSettle();
    expect(calls, ['crossfade', 'gapless']);
  });
}
