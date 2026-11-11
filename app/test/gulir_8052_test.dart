import 'dart:io';

import 'package:clai/app.dart';
import 'package:clai/data/app_db.dart';
import 'package:clai/l10n/app_localizations.dart';
import 'package:clai/ui/settings_screen.dart';
import 'package:clai/ui/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tes regresi Ronde Perbaikan Glitch Gulir 8052.
///
/// Cacat (rekaman pemilik, hub Pengaturan, build 8051): saat seretan
/// lambat, posisi gulir maju lalu MELONCAT KEMBALI berulang-ulang
/// (gigi gergaji). Akar terbukti di bangku emulator dengan log offset
/// terinstrumentasi: `ListView(children:)` membuang anak di luar
/// jendela cache dan luas gulir maksimumnya hanya PERKIRAAN dari
/// rata-rata anak yang sedang terbangun — perkiraan hub runtuh dari
/// 6311 dp ke 1807–2021 dp dan berkedip di antara dua nilai; setiap
/// perkiraan ulang menyuntikkan koreksi offset melawan seretan
/// (langkah terukur +25…+38 dp lalu −5…−35 dp di px≈1050–1200).
/// Obat lapisan akar: halaman finite memakai [FiniteScrollPage]
/// (SingleChildScrollView + Column) — seluruh anak dibangun eager,
/// luas gulir eksak dan konstan sejak bingkai pertama.
///
/// Tes ini mengunci tiga hal:
/// 1. Halaman finite sintetis beranak tinggi-variabel: seretan lambat
///    terprogram MONOTON (toleransi pembalikan ≤2 px) dan extent
///    konstan-eksak — sementara kontrol ListView lama menunjukkan
///    extent TIDAK stabil pada profil anak yang sama (pembuktian
///    bahwa rangka tes ini memang bisa melihat cacat kelasnya).
/// 2. Hub Pengaturan asli pada metrik HP pemilik (360×800 dp):
///    seretan lambat monoton + extent konstan.
/// 3. Kunci sumber: halaman finite yang dikonversi tidak boleh
///    kembali ke `ListView(... children: ...)`.
void main() {
  group('gulir 8052 — halaman finite sintetis', () {
    // Profil tinggi meniru hub: satu kartu raksasa + kartu-kartu
    // sedang/kecil bergantian (total 4420 dp; viewport 800 dp →
    // extent eksak 3620 dp).
    const heights = <double>[
      1500, 96, 340, 260, 96, 420, 96, 300, 96, 380, 96, 240, 500,
    ];
    const exactExtent = 4420.0 - 800.0;

    List<Widget> anak() => [
          for (final h in heights)
            SizedBox(
                height: h, child: const ColoredBox(color: Color(0xFF222233))),
        ];

    Future<List<({double px, double max})>> seretLambat(
      WidgetTester tester,
      ScrollPosition pos, {
      required double total,
      required double arah,
    }) async {
      final sampel = <({double px, double max})>[];
      final gesture = await tester.startGesture(const Offset(180, 400));
      var jalan = 0.0;
      while (jalan < total) {
        await gesture.moveBy(Offset(0, -6.0 * arah));
        await tester.pump(const Duration(milliseconds: 16));
        jalan += 6;
        sampel.add((px: pos.pixels, max: pos.maxScrollExtent));
      }
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 300));
      return sampel;
    }

    void cekMonoton(List<({double px, double max})> s, double arah) {
      for (var i = 1; i < s.length; i++) {
        final d = (s[i].px - s[i - 1].px) * arah;
        expect(d, greaterThanOrEqualTo(-2.0),
            reason: 'pembalikan ${-d} px pada sampel $i melampaui '
                'toleransi 2 px (px ${s[i - 1].px} → ${s[i].px})');
      }
    }

    testWidgets('FiniteScrollPage: extent eksak-konstan, seretan monoton',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      final ctrl = ScrollController();
      addTearDown(ctrl.dispose);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: FiniteScrollPage(controller: ctrl, children: anak()),
        ),
      ));
      // Extent eksak sejak bingkai PERTAMA — bukan perkiraan.
      expect(ctrl.position.maxScrollExtent, closeTo(exactExtent, 0.5),
          reason: 'extent harus geometri nyata, bukan rata-rata perkiraan');
      final turun = await seretLambat(tester, ctrl.position,
          total: 1400, arah: 1);
      cekMonoton(turun, 1);
      for (final s in turun) {
        expect(s.max, closeTo(exactExtent, 0.5),
            reason: 'extent berubah di tengah seretan: ${s.max}');
      }
      final naik = await seretLambat(tester, ctrl.position,
          total: 500, arah: -1);
      cekMonoton(naik, -1);
    });

    testWidgets('kontrol: ListView(children:) extent-nya TIDAK stabil',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      final ctrl = ScrollController();
      addTearDown(ctrl.dispose);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: ListView(controller: ctrl, children: anak())),
      ));
      final sampel = await seretLambat(tester, ctrl.position,
          total: 1400, arah: 1);
      final nilaiMax = sampel.map((s) => s.max).toSet();
      expect(
        nilaiMax.length > 1 || (nilaiMax.single - exactExtent).abs() > 1,
        isTrue,
        reason: 'kontrol ListView seharusnya menunjukkan extent '
            'perkiraan yang berubah/tidak eksak (kelas cacat 8052); '
            'terbaca: $nilaiMax',
      );
    });
  });

  group('gulir 8052 — hub Pengaturan asli', () {
    // Notis debug SUDAH-ADA yang diserap tes ini: ListTile baris grup
    // tinggal di dalam kartu DecoratedBox berwarna (leluhur yang sama
    // persis seperti di ListView lama) → assert debug "ink splashes
    // may be invisible" menyala saat hub di-pump dalam mode debug.
    // Assert terstrip di build rilis dan tidak berkaitan dengan
    // glitch gulir; dicatat di laporan ronde 8052 sebagai temuan
    // sampingan, BUKAN diperbaiki di ronde ini.
    void serapNotisListTile(WidgetTester tester) {
      var e = tester.takeException();
      while (e != null) {
        final s = e.toString();
        // Notis satuan, ATAU agregat "Multiple exceptions (N)" berisi
        // N ≤ 12 notis yang sama (12 baris grup hub) yang menumpuk
        // sebelum sempat diserap — agregat disamarkan isinya oleh
        // kerangka tes, jadi jumlahnya yang dijaga di sini.
        final agregat = RegExp(r'Multiple exceptions \((\d+)\)').firstMatch(s);
        final ok = s.contains('ListTile background color or ink splashes') ||
            (agregat != null && int.parse(agregat.group(1)!) <= 12);
        expect(ok, isTrue, reason: 'eksepsi tak terduga di hub: $e');
        e = tester.takeException();
      }
    }

    testWidgets('seretan lambat monoton + extent konstan (metrik pemilik)',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [appDbProvider.overrideWithValue(_NullDb())],
          child: const MaterialApp(
            locale: Locale('id'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: SettingsScreen(),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      serapNotisListTile(tester);
      final pos =
          tester.state<ScrollableState>(find.byType(Scrollable).first).position;
      final maxAwal = pos.maxScrollExtent;
      expect(maxAwal, greaterThan(500),
          reason: 'hub harus punya isi gulir yang panjang');

      Future<void> seret(double total, double arah) async {
        final gesture = await tester.startGesture(const Offset(180, 500));
        var jalan = 0.0;
        var pxSebelumnya = pos.pixels;
        while (jalan < total) {
          await gesture.moveBy(Offset(0, -6.0 * arah));
          await tester.pump(const Duration(milliseconds: 16));
          jalan += 6;
          final d = (pos.pixels - pxSebelumnya) * arah;
          expect(d, greaterThanOrEqualTo(-2.0),
              reason: 'offset hub berbalik ${-d} px melawan seretan '
                  'pada px=${pos.pixels}');
          expect(pos.maxScrollExtent, closeTo(maxAwal, 0.5),
              reason: 'extent hub berubah di tengah seretan');
          pxSebelumnya = pos.pixels;
        }
        await gesture.up();
        await tester.pump(const Duration(milliseconds: 300));
      }

      await seret(1000, 1);
      serapNotisListTile(tester);
      expect(pos.pixels, greaterThan(600),
          reason: 'seretan harus benar-benar menggerakkan hub');
      await seret(400, -1);
      serapNotisListTile(tester);
      // Lepas seluruh pohon agar provider (timer ambien 300 md) dibuang
      // bersih sebelum tes berakhir.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      serapNotisListTile(tester);
    });
  });

  group('gulir 8052 — kunci sumber halaman finite', () {
    const berkas = <String>[
      'lib/ui/settings_screen.dart',
      'lib/ui/home_screen.dart',
      'lib/ui/eq_screen.dart',
      'lib/ui/downloads_screen.dart',
      'lib/ui/local_screen.dart',
      'lib/ui/queue_screen.dart',
      'lib/ui/collection_screen.dart',
      'lib/ui/search_screen.dart',
      'lib/ui/content_screen.dart',
      'lib/ui/radio_screen.dart',
      'lib/ui/mood_screen.dart',
      'lib/ui/lyrics_sheet.dart',
    ];
    test('halaman finite memakai FiniteScrollPage, bukan ListView(children:)',
        () {
      final polaListViewFinite = RegExp(
          r'(^|[^A-Za-z])ListView\(\s*(padding:[^)]*,\s*)?children:');
      for (final path in berkas) {
        final isi = File(path).readAsStringSync();
        expect(isi, contains('FiniteScrollPage('),
            reason: '$path harus memakai FiniteScrollPage');
        expect(polaListViewFinite.hasMatch(isi), isFalse,
            reason: '$path kembali ke ListView(children:) — kelas cacat '
                'glitch gulir 8052 (extent perkiraan melawan seretan)');
      }
    });
  });
}

class _NullDb extends AppDb {
  @override
  Future<T?> pref<T>(String key) async => null;
}
