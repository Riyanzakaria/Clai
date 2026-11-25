// Ronde 8083 (PK1) — kit Pola Pengaturan baru + Cacat C.
//
// Kontrak yang diuji:
// (a) AppBarTheme tema aplikasi: surfaceTintColor transparan +
//     scrolledUnderElevation 0 (Cacat C — bilah judul halaman turunan
//     tidak lagi "menyala" oleh surface tint Material 3 saat scroll).
// (b) settingsSection: label tampil sentence-case apa adanya (TIDAK
//     di-uppercase) dan pohonnya tidak lagi memuat Container kartu
//     tonal surface-1 radius 20.
// (c) rowLeadIcon (pengganti tonalIconBox): pohonnya SizedBox tanpa
//     Container ber-BoxDecoration sama sekali (ikon telanjang).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:clai/app.dart';
import 'package:clai/core/clai_icons.dart';
import 'package:clai/core/tokens.dart';
import 'package:clai/ui/settings_screen.dart';
import 'package:clai/ui/widgets.dart';

void main() {
  group('Cacat C — AppBarTheme', () {
    // testWidgets (bukan test polos): buildClaiTheme memakai
    // GoogleFonts.interTextTheme yang memicu pemuatan font async —
    // di zona test() polos error muat font lingkungan tes itu
    // menempel sebagai kegagalan; di zona testWidgets ia hanya
    // notis tercetak seperti di seluruh suite lain (artefak bangku
    // tes, bukan cacat produk).
    testWidgets('surfaceTintColor transparan + scrolledUnderElevation 0', (
      tester,
    ) async {
      final theme = buildClaiTheme();
      expect(theme.appBarTheme.surfaceTintColor, Colors.transparent);
      expect(theme.appBarTheme.scrolledUnderElevation, 0);
    });
  });

  group('Pola Pengaturan baru — settingsSection', () {
    testWidgets('label sentence-case apa adanya; tanpa kartu tonal', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: settingsSection('Pemutaran', const [
                ListTile(title: Text('Baris uji')),
              ]),
            ),
          ),
        ),
      );
      await tester.pump();

      // Label tampil persis seperti diserahkan — bukan "PEMUTARAN".
      expect(find.text('Pemutaran'), findsOneWidget);
      expect(find.text('PEMUTARAN'), findsNothing);

      // Tidak ada Container berdekorasi kartu surface-1 radius 20
      // di pohon seksi (wadah kartu era lama pensiun total).
      final cardContainers = tester
          .widgetList<Container>(find.byType(Container))
          .where((c) {
            final d = c.decoration;
            return d is BoxDecoration &&
                d.color == ClaiColors.surface1 &&
                d.borderRadius == BorderRadius.circular(20);
          });
      expect(
        cardContainers,
        isEmpty,
        reason: 'settingsSection masih membangun kartu tonal lama',
      );
    });
  });

  group('rowLeadIcon — ikon telanjang', () {
    testWidgets('SizedBox tanpa Container ber-BoxDecoration', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: Center(child: rowLeadIcon(ClaiIcons.add))),
        ),
      );
      await tester.pump();

      // Akar widget yang dibangun rowLeadIcon adalah SizedBox polos.
      final lead = find.byWidgetPredicate(
        (w) => w is SizedBox && w.width == 40 && w.height == 40,
      );
      expect(lead, findsWidgets);

      // Tidak ada Container dengan BoxDecoration di subtree ikon.
      final decorated = tester
          .widgetList<Container>(find.byType(Container))
          .where((c) => c.decoration is BoxDecoration);
      expect(
        decorated,
        isEmpty,
        reason: 'rowLeadIcon masih membungkus ikon dalam kotak dekorasi',
      );
    });
  });
}
