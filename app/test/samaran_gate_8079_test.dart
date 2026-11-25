// Ronde 8079 — Gerbang penjelas Mode Samaran (S1; spec
// desain-f3/pisah-pengaturan/DIALOG-SAMARAN.md).
//
// Kontrak yang diuji:
// (1) Menyalakan dari pil Player ATAU saklar Selera kamu menampilkan
//     lembar penjelas yang SAMA dulu (4 baris jujur + centang).
// (2) "Batal" menutup dan Samaran tetap MATI.
// (3) "Aktifkan Samaran" menyalakan keadaan TUNGGAL TasteService
//     (pref persisten ikut tertulis).
// (4) Mematikan tidak pernah menampilkan lembar.
// (5) Centang "Jangan tampilkan lagi" menulis pref; pengaktifan
//     berikutnya langsung tanpa lembar di pintu yang sama.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:clai/app.dart';
import 'package:clai/data/app_db.dart';
import 'package:clai/l10n/app_localizations.dart';
import 'package:clai/ui/samaran_pill.dart';
import 'package:clai/ui/taste_control_screen.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('gerbang Samaran S1', () {
    late Directory dir;
    late AppDb db;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('samaran_gate');
      db = AppDb();
      await db.openAt('${dir.path}/t.db');
    });

    tearDown(() async {
      await db.close();
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    Widget tree(Widget home) => ProviderScope(
          overrides: [appDbProvider.overrideWithValue(db)],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('id'),
            home: home,
          ),
        );

    Future<void> untilFound(WidgetTester tester, Finder finder) async {
      for (var i = 0; i < 100; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        if (finder.evaluate().isNotEmpty) return;
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      await tester.pump();
    }

    Future<void> untilGone(WidgetTester tester, Finder finder) async {
      for (var i = 0; i < 100; i++) {
        if (finder.evaluate().isEmpty) return;
        await tester.pump(const Duration(milliseconds: 100));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      await tester.pump();
    }

    /// Pompa berbingkai kecil: satu pump panjang hanya merender satu
    /// bingkai — animasi lembar tidak ikut melompat (jebakan ronde
    /// 8079 yang terbukti di suite laci).
    Future<void> settleSteps(WidgetTester tester, [int steps = 5]) async {
      for (var i = 0; i < steps; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        await Future<void>.delayed(const Duration(milliseconds: 30));
      }
    }

    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    }

    testWidgets('pil: lembar tampil dulu; Batal → tetap mati', (tester) async {
      await tester.runAsync(() async {
        await tester.pumpWidget(tree(const Scaffold(body: SamaranPill())));
        await untilFound(tester, find.text('Samaran'));
        final svc = ProviderScope.containerOf(
                tester.element(find.byType(SamaranPill)))
            .read(tasteServiceProvider);
        await tester.tap(find.text('Samaran'));
        await untilFound(tester, find.text('Cara kerja Mode Samaran'));
        // Empat baris jujur S1.
        expect(
            find.text('Yang kamu dengarkan tidak masuk Riwayat putar.'),
            findsOneWidget);
        expect(find.text('Tidak memengaruhi Cermin Selera & rekomendasi.'),
            findsOneWidget);
        expect(find.text('Tidak dikirim ke ListenBrainz.'), findsOneWidget);
        expect(
            find.text(
                'Tetap aktif sampai kamu mematikannya sendiri — tidak ada batas waktu.'),
            findsOneWidget);
        expect(find.text('Jangan tampilkan lagi'), findsOneWidget);
        expect(svc.samaranOn, isFalse,
            reason: 'lembar belum dijawab: Samaran tidak boleh menyala');
        await settleSteps(tester);
        await tester.tap(find.text('Batal'));
        await untilGone(tester, find.text('Cara kerja Mode Samaran'));
        expect(find.text('Cara kerja Mode Samaran'), findsNothing);
        expect(svc.samaranOn, isFalse);
        expect(await db.pref<bool>(AppDb.prefTasteSamaran), isNot(true));
        await settle(tester);
      });
    });

    testWidgets('pil: Aktifkan → menyala; mematikan tanpa lembar',
        (tester) async {
      await tester.runAsync(() async {
        await tester.pumpWidget(tree(const Scaffold(body: SamaranPill())));
        await untilFound(tester, find.text('Samaran'));
        final svc = ProviderScope.containerOf(
                tester.element(find.byType(SamaranPill)))
            .read(tasteServiceProvider);
        await tester.tap(find.text('Samaran'));
        await untilFound(tester, find.text('Aktifkan Samaran'));
        await settleSteps(tester);
        await tester.tap(find.text('Aktifkan Samaran'));
        await untilGone(tester, find.text('Cara kerja Mode Samaran'));
        expect(find.text('Cara kerja Mode Samaran'), findsNothing);
        expect(svc.samaranOn, isTrue);
        expect(await db.pref<bool>(AppDb.prefTasteSamaran), isTrue);
        // Mematikan: langsung, tanpa lembar.
        await tester.tap(find.text('Samaran'));
        await settleSteps(tester, 4);
        expect(find.text('Cara kerja Mode Samaran'), findsNothing);
        expect(svc.samaranOn, isFalse);
        await settle(tester);
      });
    });

    testWidgets('centang "Jangan tampilkan lagi": berikutnya langsung',
        (tester) async {
      await tester.runAsync(() async {
        await tester.pumpWidget(tree(const Scaffold(body: SamaranPill())));
        await untilFound(tester, find.text('Samaran'));
        final svc = ProviderScope.containerOf(
                tester.element(find.byType(SamaranPill)))
            .read(tasteServiceProvider);
        await tester.tap(find.text('Samaran'));
        await untilFound(tester, find.text('Jangan tampilkan lagi'));
        await settleSteps(tester);
        await tester.tap(find.byType(Checkbox));
        await settleSteps(tester, 3);
        await tester.tap(find.text('Aktifkan Samaran'));
        await untilGone(tester, find.text('Cara kerja Mode Samaran'));
        expect(svc.samaranOn, isTrue);
        expect(await db.pref<bool>(AppDb.prefTasteSamaranHowSeen), isTrue);
        // Matikan, nyalakan lagi: TANPA lembar.
        await tester.tap(find.text('Samaran'));
        await settleSteps(tester, 4);
        expect(svc.samaranOn, isFalse);
        await tester.tap(find.text('Samaran'));
        await settleSteps(tester, 6);
        expect(find.text('Cara kerja Mode Samaran'), findsNothing);
        expect(svc.samaranOn, isTrue);
        await settle(tester);
      });
    });

    testWidgets('saklar Selera kamu memakai gerbang yang sama',
        (tester) async {
      await tester.runAsync(() async {
        await tester.pumpWidget(tree(const TasteControlScreen()));
        await untilFound(tester, find.text('Mode Samaran'));
        final svc = ProviderScope.containerOf(
                tester.element(find.byType(TasteControlScreen)))
            .read(tasteServiceProvider);
        // Ronde 8083: judul seksi datar kini sentence-case persis
        // "Mode Samaran" (dulu header ter-uppercase sehingga tak ikut
        // tertangkap finder ini) — teks yang dicari adalah JUDUL
        // SwitchListTile-nya, yakni kemunculan TERAKHIR di pohon.
        final tile = find.ancestor(
            of: find.text('Mode Samaran').last,
            matching: find.byType(SwitchListTile));
        final sw = find.descendant(
            of: tile, matching: find.byType(Switch));
        await tester.tap(sw);
        await untilFound(tester, find.text('Cara kerja Mode Samaran'));
        expect(svc.samaranOn, isFalse);
        await settleSteps(tester);
        await tester.tap(find.text('Aktifkan Samaran'));
        await untilGone(tester, find.text('Cara kerja Mode Samaran'));
        expect(svc.samaranOn, isTrue);
        // Mematikan lewat saklar: tanpa lembar.
        await tester.tap(sw);
        await settleSteps(tester, 4);
        expect(find.text('Cara kerja Mode Samaran'), findsNothing);
        expect(svc.samaranOn, isFalse);
        await settle(tester);
      });
    });
  });
}
