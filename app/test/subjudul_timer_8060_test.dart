import 'package:clai/app.dart';
import 'package:clai/l10n/app_localizations.dart';
import 'package:clai/l10n/app_localizations_en.dart';
import 'package:clai/l10n/app_localizations_id.dart';
import 'package:clai/services/sleep_service.dart';
import 'package:clai/ui/sleep_timer_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ronde 8060 — koreksi temuan bukti emulator 8059: subjudul keadaan
/// aktif Sleep Timer menduplikasi kata sisa ("Timer active — 13:51
/// left left. ..."). Akar: nilai placeholder {remaining} SUDAH frasa
/// lengkap dari sleepRemaining ("13:51 left" / "Sisa 13:51"), tetapi
/// templat sleepSubMinutes menambahkan kata yang sama sekali lagi
/// ("left" di EN, "lagi" sesudah "Sisa" di ID). Perbaikan di sisi
/// templat ARB kedua bahasa: templat kini netral ("{remaining}."),
/// frasa sisa tetap milik sleepRemaining; komposisi di kode
/// (_remainingLabel → sleepSubMinutes) tidak berubah, dan permukaan
/// lain (chip mini player, angka pahlawan, kartu Lanjut Besok) tidak
/// memakai kedua string ini sama sekali.
///
/// Tes ini mengunci redaksi akhir EN + ID, murni (komposisi persis
/// seperti di kode) dan lewat widget (yang benar-benar tampil).
void main() {
  group('komposisi subjudul aktif (murni, persis jalur kode)', () {
    test('EN: satu "left", kalimat persis', () {
      final en = AppLocalizationsEn();
      // Jalur kode: sleepSubMinutes(_remainingLabel(d)) dengan
      // _remainingLabel(d) = sleepRemaining(formatSleepCountdown(d)).
      final subtitle = en.sleepSubMinutes(
          en.sleepRemaining(formatSleepCountdown(
              const Duration(minutes: 13, seconds: 51))));
      expect(
          subtitle,
          'Timer active — 13:51 left. The volume fades out smoothly '
          'over the final stretch, then the music pauses.');
      expect(subtitle, isNot(contains('left left')));
    });

    test('ID: tanpa "Sisa ... lagi", kalimat persis', () {
      final id = AppLocalizationsId();
      final subtitle = id.sleepSubMinutes(
          id.sleepRemaining(formatSleepCountdown(
              const Duration(minutes: 13, seconds: 51))));
      expect(subtitle,
          'Timer aktif — Sisa 13:51. Volume memudar halus di bentang akhir, lalu musik jeda.');
      expect(subtitle, isNot(contains('lagi')));
    });
  });

  group('Lembar Timer Tidur (widget) — subjudul aktif tampil benar', () {
    late SleepService service;

    Future<void> pumpHost(WidgetTester tester, Locale locale) async {
      service = SleepService();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [sleepServiceProvider.overrideWith((ref) => service)],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: locale,
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
      // JANGAN pumpAndSettle — ticker 1 detik lembar selalu terjadwal.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    Future<void> teardown(WidgetTester tester) async {
      service.cancel();
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    }

    String subtitleStartingWith(WidgetTester tester, String prefix) {
      for (final w in tester.widgetList<Text>(find.byType(Text))) {
        final data = w.data;
        if (data != null && data.startsWith(prefix)) return data;
      }
      fail('subjudul berawalan "$prefix" tidak ditemukan');
    }

    testWidgets('EN: "Timer active — MM:SS left." satu left', (tester) async {
      await pumpHost(tester, const Locale('en'));
      service.startMinutes(30);
      await openSheet(tester);
      final subtitle = subtitleStartingWith(tester, 'Timer active — ');
      // Sisa nyata sesaat sesudah dipasang: 30:00 atau 29:5x.
      expect(subtitle,
          matches(RegExp(r'^Timer active — (30:00|29:5\d) left\. The volume fades')));
      expect(subtitle, isNot(contains('left left')));
      expect(tester.takeException(), isNull);
      await teardown(tester);
    });

    testWidgets('ID: "Timer aktif — Sisa MM:SS." tanpa lagi', (tester) async {
      await pumpHost(tester, const Locale('id'));
      service.startMinutes(30);
      await openSheet(tester);
      final subtitle = subtitleStartingWith(tester, 'Timer aktif — ');
      expect(subtitle,
          matches(RegExp(r'^Timer aktif — Sisa (30:00|29:5\d)\. Volume memudar')));
      expect(subtitle, isNot(contains('lagi')));
      expect(tester.takeException(), isNull);
      await teardown(tester);
    });
  });
}
