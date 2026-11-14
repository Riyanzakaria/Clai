import 'package:clai/app.dart';
import 'package:clai/l10n/app_localizations.dart';
import 'package:clai/services/sleep_service.dart';
import 'package:clai/ui/sleep_timer_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ronde 8059 — penerapan frame Stitch "Sleep Timer — Setting State" +
/// "Sleep Timer — Active Countdown State" (perintah pemilik 2026-11-12,
/// ditegaskan 2026-11-13 11:24):
/// (1) format hitung mundur murni "MM:SS";
/// (2) keadaan aktif mode menit menampilkan sisa waktu BESAR (angka
///     pahlawan, key sleepCountdownHero) — bukan nilai contoh frame
///     (24:36) melainkan sisa nyata layanan;
/// (3) keadaan setel tidak berubah: 4 preset + akhir lagu, tanpa baris
///     batal, tanpa blok hitung mundur;
/// (4) batal dari lembar mengembalikan layanan ke tidak-aktif;
/// (5) sheet 55% nyata TIDAK meluap pada layar pendek + font besar
///     (isi kini bisa digulir; baris batal tercapai lewat gulir).
void main() {
  group('formatSleepCountdown (murni)', () {
    test('nol & negatif dijepit ke 00:00', () {
      expect(formatSleepCountdown(Duration.zero), '00:00');
      expect(formatSleepCountdown(const Duration(seconds: -5)), '00:00');
    });

    test('detik pecahan dibuang, dua digit selalu', () {
      expect(formatSleepCountdown(const Duration(milliseconds: 59999)), '00:59');
      expect(formatSleepCountdown(const Duration(seconds: 9)), '00:09');
      expect(formatSleepCountdown(const Duration(seconds: 65)), '01:05');
    });

    test('nilai frame 24:36 & preset maksimum 60:00', () {
      expect(
          formatSleepCountdown(const Duration(minutes: 24, seconds: 36)),
          '24:36');
      expect(formatSleepCountdown(const Duration(minutes: 60)), '60:00');
    });
  });

  group('Lembar Timer Tidur (widget)', () {
    late SleepService service;

    Future<void> pumpHost(WidgetTester tester) async {
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
    }

    Future<void> openSheet(WidgetTester tester) async {
      await tester.tap(find.text('buka'));
      // Animasi naik lembar ±250 mdtk; JANGAN pumpAndSettle — ticker
      // 1 detik lembar membuat bingkai selalu terjadwal.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    Future<void> teardown(WidgetTester tester) async {
      service.cancel();
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    }

    testWidgets('keadaan setel: preset lengkap, tanpa batal, tanpa hero',
        (tester) async {
      await pumpHost(tester);
      await openSheet(tester);
      expect(find.byType(SleepTimerSheet), findsOneWidget);
      for (final m in [15, 30, 45, 60]) {
        expect(find.text('$m minutes'), findsOneWidget);
      }
      expect(find.text('End of this song'), findsOneWidget);
      expect(find.text('Cancel timer'), findsNothing);
      expect(find.byKey(const Key('sleepCountdownHero')), findsNothing);
      expect(tester.takeException(), isNull);
      await teardown(tester);
    });

    testWidgets('ketuk preset memasang timer menit & menutup lembar',
        (tester) async {
      await pumpHost(tester);
      await openSheet(tester);
      await tester.tap(find.text('30 minutes'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(service.active?.mode, 'minutes');
      expect(service.active?.minutes, 30);
      expect(find.byType(SleepTimerSheet), findsNothing);
      await teardown(tester);
    });

    testWidgets('keadaan aktif menit: sisa BESAR tampil nyata + baris batal',
        (tester) async {
      await pumpHost(tester);
      service.startMinutes(30);
      await openSheet(tester);
      final hero = find.byKey(const Key('sleepCountdownHero'));
      expect(hero, findsOneWidget);
      final label = tester.widget<Text>(hero).data!;
      // Sisa nyata sesaat sesudah dipasang: 30:00 atau 29:5x.
      expect(label, matches(RegExp(r'^(30:00|29:5\d)$')),
          reason: 'sisa nyata layanan, bukan nilai contoh frame');
      expect(find.text('Cancel timer'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await teardown(tester);
    });

    testWidgets('batal dari lembar mengembalikan keadaan tidak-aktif',
        (tester) async {
      await pumpHost(tester);
      service.startMinutes(15);
      await openSheet(tester);
      expect(service.active, isNotNull);
      // Baris batal di bawah lipatan sheet 55% — gulir dulu (isi lembar
      // kini bisa digulir, Ronde 8059).
      await tester.drag(
          find.byType(SingleChildScrollView), const Offset(0, -400));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Cancel timer'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(service.active, isNull);
      expect(find.byType(SleepTimerSheet), findsNothing);
      await teardown(tester);
    });

    testWidgets('keadaan aktif akhir-lagu: tanpa hero hitung mundur',
        (tester) async {
      await pumpHost(tester);
      service.startEndOfSong();
      await openSheet(tester);
      expect(find.byKey(const Key('sleepCountdownHero')), findsNothing);
      expect(find.text('Cancel timer'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await teardown(tester);
    });

    testWidgets('layar pendek + font besar: tidak meluap, batal tergulir',
        (tester) async {
      tester.view.physicalSize = const Size(720, 1280); // 360x640 @2x
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);
      await pumpHost(tester);
      service.startMinutes(45);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [sleepServiceProvider.overrideWith((ref) => service)],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('en'),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(1.3)),
              child: child!,
            ),
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
      await openSheet(tester);
      expect(find.byType(SleepTimerSheet), findsOneWidget);
      expect(tester.takeException(), isNull,
          reason: 'sheet 55% pada layar pendek tidak boleh RenderFlex overflow');
      // Baris batal ada di dokumen; gulir isi sampai terlihat & ketuk.
      await tester.drag(
          find.byType(SingleChildScrollView), const Offset(0, -400));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Cancel timer'));
      await tester.pump();
      expect(service.active, isNull);
      await teardown(tester);
    });
  });
}
