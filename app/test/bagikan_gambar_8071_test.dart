// Ronde 8071 — penyelesaian kecil D2 (perintah riyan 2026-11-21 22:16):
// (1) Bagikan membagikan GAMBAR kartu QR (PNG) — render + tombol lembar;
// (2) Pindai menerima GAMBAR QR ("Pilih gambar QR") — kehadiran pintu
//     di keadaan kamera-tak-tersedia (dekode gambar-diam dibuktikan
//     hidup di audit emulator; di sini yang dijaga kontrak UI-nya);
// (3) Perbaikan cacat warisan: luapan RenderFlex 6,8px kartu Tampilan
//     hub Pengaturan pada 360dp TIDAK boleh ada lagi — tes ini
//     mengumpulkan eksepsi satu per satu dan menolak luapan apa pun
//     (hanya notis tinta ListTile warisan yang diserap).
import 'dart:ui' as ui;

import 'package:clai/app.dart';
import 'package:clai/data/app_db.dart';
import 'package:clai/domain/transfer_data.dart';
import 'package:clai/l10n/app_localizations.dart';
import 'package:clai/services/library_transfer.dart';
import 'package:clai/ui/qr_scan_screen.dart';
import 'package:clai/ui/settings_screen.dart';
import 'package:clai/ui/share_playlist_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';

TransferTrack _trk(String id) => TransferTrack(
      providerId: 'ytmusic',
      trackId: id,
      title: 'Lagu $id',
      artistNames: 'Artis $id',
      durationMs: 200000,
      playableRef: id,
    );

class _NullPrefDb extends AppDb {
  @override
  Future<T?> pref<T>(String key) async => null;
}

void main() {
  group('kartu QR gambar (butir 1)', () {
    testWidgets('render PNG: tanda tangan PNG, lebar 1080, isi nyata',
        (tester) async {
      await tester.runAsync(() async {
        final shared = SharedPlaylistData(
          formatVersion: kTransferFormatVersion,
          name: 'Senja di Kota',
          tracks: [_trk('a'), _trk('b')],
        );
        final payload = encodeQrPayload(shared);
        final png = await renderQrShareCardPng(
          payload: payload,
          playlistName: shared.name,
          countText: '2 lagu',
          footerText: 'Pindai kode ini dari Clai',
        );
        // Tanda tangan PNG.
        expect(png.length, greaterThan(10000));
        expect(png.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
        // Bisa didekode sebagai gambar selebar kartu.
        final codec = await ui.instantiateImageCodec(png);
        final frame = await codec.getNextFrame();
        expect(frame.image.width, 1080);
        expect(frame.image.height, greaterThan(1200));
        // Payload berbeda → gambar berbeda (QR-nya sungguhan berubah).
        final lain = await renderQrShareCardPng(
          payload: encodeQrPayload(SharedPlaylistData(
            formatVersion: kTransferFormatVersion,
            name: 'Senja di Kota',
            tracks: [_trk('zz')],
          )),
          playlistName: shared.name,
          countText: '2 lagu',
          footerText: 'Pindai kode ini dari Clai',
        );
        expect(lain, isNot(equals(png)));
      });
    });

    Widget tree(Widget home) => ProviderScope(
          overrides: [appDbProvider.overrideWithValue(_NullPrefDb())],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('id'),
            home: home,
          ),
        );

    Future<void> untilFound(WidgetTester tester, Finder finder) async {
      for (var i = 0; i < 150; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        if (finder.evaluate().isNotEmpty) return;
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      await tester.pump();
    }

    testWidgets('lembar Bagikan: playlist kecil → tombol gambar QR ada',
        (tester) async {
      await tester.runAsync(() async {
        await tester.pumpWidget(tree(Scaffold(
          body: Consumer(
            builder: (ctx, ref, _) => TextButton(
              onPressed: () => openSharePlaylistSheet(
                  ctx,
                  TransferPlaylist(
                      name: 'Senja', tracks: [_trk('a'), _trk('b')])),
              child: const Text('buka'),
            ),
          ),
        )));
        await tester.pump();
        await tester.tap(find.text('buka'));
        await untilFound(tester, find.byType(QrImageView));
        expect(find.byType(QrImageView), findsOneWidget);
        expect(find.text('Bagikan gambar QR'), findsOneWidget);
        expect(find.text('Bagikan berkas'), findsOneWidget);
      });
    });

    testWidgets('lembar Bagikan: playlist besar → tombol gambar QR '
        'TIDAK ada (QR-nya sendiri tidak ditawarkan)', (tester) async {
      var seedN = 424242;
      String word(int len) {
        const chars = 'abcdefghijklmnopqrstuvwxyz';
        var s = '';
        for (var i = 0; i < len; i++) {
          seedN = (seedN * 1103515245 + 12345) & 0x7fffffff;
          s += chars[seedN % 26];
        }
        return s;
      }

      // Sejak ronde 8078 "terlalu besar" berarti mode ringkas pun
      // melewati ambang: 200 trek (40 trek kini masuk mode ringkas).
      final big = TransferPlaylist(name: 'Raksasa', tracks: [
        for (var i = 0; i < 200; i++)
          TransferTrack(
            providerId: 'ytmusic',
            trackId: word(11),
            title: '${word(9)} ${word(7)} ${word(12)}',
            artistNames: '${word(8)} ${word(6)}',
            durationMs: 200000,
            playableRef: word(11),
          ),
      ]);
      await tester.runAsync(() async {
        await tester.pumpWidget(tree(Scaffold(
          body: Consumer(
            builder: (ctx, ref, _) => TextButton(
              onPressed: () => openSharePlaylistSheet(ctx, big),
              child: const Text('buka'),
            ),
          ),
        )));
        await tester.pump();
        await tester.tap(find.text('buka'));
        await untilFound(
            tester, find.textContaining('terlalu besar untuk kode QR'));
        expect(find.byType(QrImageView), findsNothing);
        expect(find.text('Bagikan gambar QR'), findsNothing);
        expect(find.text('Bagikan berkas'), findsOneWidget);
      });
    });
  });

  group('pindai gambar (butir 2)', () {
    testWidgets('izin kamera ditolak → pintu "Pilih gambar QR" tampil '
        'di panel pengganti dan di pill melayang', (tester) async {
      const channel =
          MethodChannel('flutter.baseflow.com/permissions/methods');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        switch (call.method) {
          case 'requestPermissions':
            return {1: 0}; // kamera (1) → ditolak (0)
          case 'checkPermissionStatus':
            return 0;
          case 'openAppSettings':
            return true;
          case 'shouldShowRequestPermissionRationale':
            return false;
        }
        return null;
      });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });

      await tester.pumpWidget(ProviderScope(
        overrides: [appDbProvider.overrideWithValue(_NullPrefDb())],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: Locale('id'),
          home: QrScanScreen(),
        ),
      ));
      // Tunggu status izin (saluran mock menjawab di mikro-task).
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        if (find.text('Pilih gambar QR').evaluate().isNotEmpty) break;
      }
      expect(find.text('Izin kamera diperlukan untuk memindai'),
          findsOneWidget);
      // Dua pintu: pill melayang di dasar + tombol teks panel pengganti.
      expect(find.text('Pilih gambar QR'), findsNWidgets(2));
      expect(find.text('Impor dari berkas'), findsNWidgets(2));
    });
  });

  group('luapan kartu Tampilan (butir 3)', () {
    testWidgets('hub Pengaturan 360dp: NOL eksepsi RenderFlex/luapan',
        (tester) async {
      final errors = <FlutterErrorDetails>[];
      final oldOnError = FlutterError.onError;
      FlutterError.onError = (d) => errors.add(d);
      try {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 3.0;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [appDbProvider.overrideWithValue(_NullPrefDb())],
            child: const MaterialApp(
              locale: Locale('id'),
              localizationsDelegates:
                  AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: SettingsScreen(),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      } finally {
        FlutterError.onError = oldOnError;
      }
      // Buang sisa yang ditangkap kerangka (agregat notis tinta).
      var e = tester.takeException();
      while (e != null) {
        e = tester.takeException();
      }
      final luapan = errors
          .where((d) =>
              d.exception.toString().contains('RenderFlex') ||
              d.exception.toString().contains('overflowed'))
          .toList();
      expect(luapan, isEmpty,
          reason: 'luapan tidak boleh ada lagi: $luapan');
      // Yang tersisa hanya notis tinta ListTile warisan (12 baris grup).
      for (final d in errors) {
        expect(d.exception.toString(),
            contains('ListTile background color or ink splashes'),
            reason: 'eksepsi tak terduga selain notis tinta: $d');
      }
    });
  });
}
