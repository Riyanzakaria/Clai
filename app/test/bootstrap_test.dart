import 'dart:async';

import 'package:clai/bootstrap.dart';
import 'package:clai/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BootstrapRunner', () {
    test('menjalankan langkah berurutan & melaporkan kemajuan', () async {
      final order = <String>[];
      final progress = <String>[];
      const runner = BootstrapRunner();
      await runner.run([
        BootstrapStep('satu', () async => order.add('satu')),
        BootstrapStep('dua', () async => order.add('dua')),
      ], onStep: progress.add);
      expect(order, ['satu', 'dua']);
      expect(progress, ['satu', 'dua']);
    });

    test('kegagalan langkah dibungkus dengan nama langkahnya', () async {
      const runner = BootstrapRunner();
      await expectLater(
        runner.run([BootstrapStep('meledak', () async => throw StateError('boom'))]),
        throwsA(isA<BootstrapFailure>()
            .having((f) => f.stepLabel, 'stepLabel', 'meledak')
            .having((f) => f.error, 'error', isA<StateError>())),
      );
    });

    test('langkah yang melewati batas waktu gagal sebagai timeout', () async {
      const runner = BootstrapRunner(stepTimeout: Duration(milliseconds: 50));
      await expectLater(
        runner.run([
          BootstrapStep('lambat', () => Future<void>.delayed(const Duration(milliseconds: 300)))
        ]),
        throwsA(isA<BootstrapFailure>().having((f) => f.error, 'error', isA<TimeoutException>())),
      );
    });

    test('jalan ulang sesudah gagal bisa berhasil (dasar tombol Coba Lagi)', () async {
      var attempts = 0;
      const runner = BootstrapRunner();
      final steps = [
        BootstrapStep('rapuh', () async {
          attempts++;
          if (attempts == 1) throw StateError('gagal pertama');
        })
      ];
      await expectLater(runner.run(steps), throwsA(isA<BootstrapFailure>()));
      await runner.run(steps); // tidak melempar
      expect(attempts, 2);
    });
  });

  test('laporan mulai memuat langkah, error, dan versi', () {
    final report = buildStartupReport(
        BootstrapFailure('Menyiapkan pemutar…', StateError('layanan macet'), StackTrace.fromString('a\nb')));
    expect(report, contains('Menyiapkan pemutar'));
    expect(report, contains('layanan macet'));
    expect(report, contains(kAppVersion));
  });

  group('layar mulai', () {
    testWidgets('splash menampilkan merek & langkah berjalan', (tester) async {
      await tester.pumpWidget(
          const MaterialApp(home: SplashScreen(stepLabel: 'Menyiapkan pemutar…')));
      expect(find.text('Clai'), findsOneWidget);
      expect(find.text('Menyiapkan pemutar…'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('layar kesalahan menyebut langkah & tombol-tombolnya bekerja', (tester) async {
      String? clipboardText;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboardText = (call.arguments as Map)['text'] as String?;
        }
        return null;
      });
      var retries = 0;
      final failure = BootstrapFailure(
          'Menyiapkan pemutar…', StateError('layanan macet'), StackTrace.fromString('x'));
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('id'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: StartupErrorScreen(
          failure: failure,
          report: 'LAPORAN-UJI',
          onRetry: () => retries++,
        ),
      ));
      expect(find.text('Clai gagal mulai'), findsOneWidget);
      expect(find.textContaining('Menyiapkan pemutar'), findsWidgets);
      expect(find.textContaining('layanan macet'), findsOneWidget);

      await tester.tap(find.text('Coba Lagi'));
      expect(retries, 1);

      await tester.tap(find.text('Salin Laporan'));
      await tester.pump();
      expect(clipboardText, 'LAPORAN-UJI');
    });
  });
}
