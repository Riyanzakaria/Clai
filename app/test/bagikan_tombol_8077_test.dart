// Ronde 8077 — regresi cacat NYATA dari HP riyan (vonis kumulatif
// staging 8076): pada lembar Bagikan playlist, kedua tombol di bawah
// kode QR ("Bagikan gambar QR" + "Bagikan berkas") mati total — dipencet
// tidak ada respons sama sekali. Keadaan kedua lembar yang sama
// (playlist terlalu besar untuk QR → satu tombol "Bagikan berkas")
// juga dikunci di sini.
//
// Akar terbukti (logcat emulator build 8076): _ShareSheet memegang
// WidgetRef MILIK LEMBAR PEMILIH; pemilih menutup dirinya lalu membuka
// lembar Bagikan dengan ref elemen yang sudah dibuang →
// "Bad state: Cannot use \"ref\" after the widget was disposed" pada
// langkah pertama kedua handler. Tes lama lolos karena host-nya
// Consumer yang TETAP TERPASANG (ref tidak pernah mati) — tes ini
// memakai jalur pengguna yang sesungguhnya: hub → openSharePlaylistPicker
// → pemilih pop → lembar Bagikan, lalu MENGETUK kedua tombol dan
// memeriksa efeknya (berkas bagikan sungguh ditulis oleh layanan).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:clai/app.dart';
import 'package:clai/data/app_db.dart';
import 'package:clai/domain/transfer_data.dart';
import 'package:clai/l10n/app_localizations.dart';
import 'package:clai/services/library_transfer.dart';
import 'package:clai/ui/share_playlist_sheet.dart';

TransferTrack _tt(String id, {String title = 'Lagu', String artist = 'Artis'}) =>
    TransferTrack(
      providerId: 'ytmusic',
      trackId: id,
      title: '$title $id',
      artistNames: artist,
      durationMs: 200000,
      playableRef: id,
    );

/// DB pura-pura: tiga playlist pengguna tanpa menyentuh disk.
class _FakeDb extends AppDb {
  @override
  Future<List<Map<String, Object?>>> playlists() async => [
        {'id': 'p1', 'name': 'Senja', 'is_system': 0},
        {'id': 'p2', 'name': 'Raksasa', 'is_system': 0},
        {'id': 'p3', 'name': 'Menengah', 'is_system': 0},
      ];

  @override
  Future<int> playlistCount(String playlistId) async =>
      playlistId == 'p1' ? 2 : (playlistId == 'p3' ? 49 : 200);
}

/// Layanan transfer perekam: menulis sungguh ke berkas temporer dan
/// mencatat nama berkasnya — inilah batas yang diblokir cacat 8077
/// (handler mati SEBELUM mencapai layanan).
class _RecordingTransfer extends LibraryTransferService {
  _RecordingTransfer(super.db);
  final List<String> filesWritten = [];
  final List<String> bytesWritten = [];

  @override
  Future<TransferPlaylist?> playlistData(String playlistId) async {
    if (playlistId == 'p1') {
      return TransferPlaylist(name: 'Senja', tracks: [_tt('a'), _tt('b')]);
    }
    var seedN = 987654;
    String word(int len) {
      const chars = 'abcdefghijklmnopqrstuvwxyz';
      var s = '';
      for (var i = 0; i < len; i++) {
        seedN = (seedN * 1103515245 + 12345) & 0x7fffffff;
        s += chars[seedN % 26];
      }
      return s;
    }

    List<TransferTrack> bigTracks(int n) => [
          for (var i = 0; i < n; i++)
            TransferTrack(
              providerId: 'ytmusic',
              trackId: word(11),
              title: '${word(9)} ${word(7)} ${word(12)}',
              artistNames: '${word(8)} ${word(6)}',
              durationMs: 200000,
              playableRef: word(11),
            ),
        ];

    // Sejak ronde 8078: 200 trek = bahkan mode ringkas melewati ambang
    // (keadaan terlalu-besar yang sesungguhnya); 49 trek = mode penuh
    // tidak muat tetapi mode ringkas muat (kasus "play" riyan).
    if (playlistId == 'p3') {
      return TransferPlaylist(name: 'Menengah', tracks: bigTracks(49));
    }
    return TransferPlaylist(name: 'Raksasa', tracks: bigTracks(200));
  }

  @override
  Future<File> writeShareFile(String fileName, String content) async {
    filesWritten.add(fileName);
    final f = File('${Directory.systemTemp.path}/$fileName');
    await f.writeAsString(content);
    return f;
  }

  @override
  Future<File> writeShareBytes(String fileName, List<int> bytes) async {
    bytesWritten.add(fileName);
    final f = File('${Directory.systemTemp.path}/$fileName');
    await f.writeAsBytes(bytes, flush: true);
    return f;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const shareChannel = MethodChannel('dev.fluttercommunity.plus/share_plus');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late _FakeDb db;
  late _RecordingTransfer svc;

  setUp(() {
    db = _FakeDb();
    svc = _RecordingTransfer(db);
    // Share sheet sistem diwakili kanal tiruan: yang dikunci tes ini
    // adalah handler SAMPAI ke layanan + panggilan bagikan terbit.
    messenger.setMockMethodCallHandler(shareChannel, (call) async {
      if (call.method == 'share') return 'success';
      return null;
    });
  });

  tearDown(() => messenger.setMockMethodCallHandler(shareChannel, null));

  Widget tree(Widget home) => ProviderScope(
        overrides: [
          appDbProvider.overrideWithValue(db),
          libraryTransferProvider.overrideWithValue(svc),
        ],
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

  /// Tuntaskan animasi masuk lembar: di zona runAsync jam animasi hanya
  /// maju lewat pump berdurasI — untilFound berhenti begitu widget ADA,
  /// yang bisa masih di tengah animasi geser lembar (tombol masih di
  /// bawah tepi layar). 20 x 100ms terbukti membuat geometri menetap.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> untilTrue(WidgetTester tester, bool Function() cond) async {
    for (var i = 0; i < 150; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (cond()) return;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    await tester.pump();
  }

  /// Permukaan uji seukuran HP sungguhan (1080x2400 @ 2.625): pada
  /// permukaan bawaan 800x600 kedua tombol jatuh di bawah lipatan gulir
  /// lembar dan ketukan tester meleset — bukan itu yang diuji di sini.
  void sizeLikePhone(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
  }

  /// Buka pemilih dari host yang tetap terpasang (pola hub Kepemilikan),
  /// lalu pilih playlist [name] — pemilih menutup dirinya dan lembar
  /// Bagikan terbuka: persis rantai pop-lalu-buka yang membunuh ref.
  Future<void> openViaPicker(WidgetTester tester, String name) async {
    await tester.pumpWidget(tree(Scaffold(
      body: Consumer(
        builder: (ctx, ref, _) => TextButton(
          onPressed: () => openSharePlaylistPicker(ctx, ref),
          child: const Text('bagikan'),
        ),
      ),
    )));
    await tester.pump();
    await tester.tap(find.text('bagikan'));
    await untilFound(tester, find.text('Pilih playlist'));
    await untilFound(tester, find.text(name));
    // Tuntaskan animasi geser lembar pemilih sebelum mengetuk baris:
    // untilFound berhenti begitu widget ADA — baris terbawah (ketiga)
    // bisa masih bergerak, dan ketukan meleset dari hit-test
    // (kegagalan semu yang terlihat pada tes mode ringkas 8078).
    await settle(tester);
    await tester.tap(find.text(name));
  }

  testWidgets(
      'jalur pemilih → lembar Bagikan (QR tampil): KEDUA tombol di bawah '
      'QR berfungsi', (tester) async {
    sizeLikePhone(tester);
    await tester.runAsync(() async {
      await openViaPicker(tester, 'Senja');
      await untilFound(tester, find.byType(QrImageView));
      await settle(tester);
      expect(find.byType(QrImageView), findsOneWidget);
      expect(find.text('Bagikan gambar QR'), findsOneWidget);
      expect(find.text('Bagikan berkas'), findsOneWidget);

      // Tombol 1: Bagikan gambar QR → kartu PNG ditulis layanan.
      await tester.ensureVisible(find.text('Bagikan gambar QR'));
      await tester.pump();
      await tester.tap(find.text('Bagikan gambar QR'));
      await untilTrue(tester, () => svc.bytesWritten.isNotEmpty);
      expect(svc.bytesWritten.single, startsWith('clai-qr-'));
      expect(svc.bytesWritten.single, endsWith('.png'));

      // Tombol 2: Bagikan berkas → berkas JSON playlist ditulis layanan.
      await tester.ensureVisible(find.text('Bagikan berkas'));
      await tester.pump();
      await tester.tap(find.text('Bagikan berkas'));
      await untilTrue(tester, () => svc.filesWritten.isNotEmpty);
      expect(svc.filesWritten.single, startsWith('clai-playlist-'));
      expect(svc.filesWritten.single, endsWith('.json'));

      expect(tester.takeException(), isNull,
          reason: 'tidak boleh ada eksepsi lolos dari kedua tombol');
    });
  });

  testWidgets(
      'jalur pemilih → lembar Bagikan (terlalu besar untuk QR): tombol '
      '"Bagikan berkas" satu-satunya berfungsi', (tester) async {
    sizeLikePhone(tester);
    await tester.runAsync(() async {
      await openViaPicker(tester, 'Raksasa');
      await untilFound(
          tester, find.textContaining('terlalu besar untuk kode QR'));
      await settle(tester);
      expect(find.byType(QrImageView), findsNothing);
      expect(find.text('Bagikan gambar QR'), findsNothing);
      expect(find.text('Bagikan berkas'), findsOneWidget);

      await tester.ensureVisible(find.text('Bagikan berkas'));
      await tester.pump();
      await tester.tap(find.text('Bagikan berkas'));
      await untilTrue(tester, () => svc.filesWritten.isNotEmpty);
      expect(svc.filesWritten.single, startsWith('clai-playlist-'));
      expect(svc.filesWritten.single, endsWith('.json'));

      expect(tester.takeException(), isNull,
          reason: 'tidak boleh ada eksepsi lolos dari tombol berkas');
    });
  });

  // Ronde 8078: keadaan ketiga lembar yang sama — playlist 49 trek
  // masuk mode RINGKAS (QR tampil). Kedua tombol wajib berfungsi juga
  // di keadaan ini, lewat jalur pemilih yang sama.
  // Ronde 8084 (§13.2): catatan referensi di bawah QR DIBUANG —
  // uji kini mengunci ketidakhadirannya.
  testWidgets(
      'jalur pemilih → lembar Bagikan (mode ringkas 8078): QR tampil, '
      'catatan referensi absen (8084), KEDUA tombol berfungsi',
      (tester) async {
    sizeLikePhone(tester);
    await tester.runAsync(() async {
      await openViaPicker(tester, 'Menengah');
      await untilFound(tester, find.byType(QrImageView));
      await settle(tester);
      expect(find.byType(QrImageView), findsOneWidget);
      expect(find.textContaining('referensi lagu'), findsNothing,
          reason: 'catatan penjelasan di bawah QR dibuang ronde 8084');
      expect(find.text('Bagikan gambar QR'), findsOneWidget);
      expect(find.text('Bagikan berkas'), findsOneWidget);

      await tester.ensureVisible(find.text('Bagikan gambar QR'));
      await tester.pump();
      await tester.tap(find.text('Bagikan gambar QR'));
      await untilTrue(tester, () => svc.bytesWritten.isNotEmpty);
      expect(svc.bytesWritten.single, startsWith('clai-qr-'));
      expect(svc.bytesWritten.single, endsWith('.png'));

      await tester.ensureVisible(find.text('Bagikan berkas'));
      await tester.pump();
      await tester.tap(find.text('Bagikan berkas'));
      await untilTrue(tester, () => svc.filesWritten.isNotEmpty);
      expect(svc.filesWritten.single, startsWith('clai-playlist-'));
      expect(svc.filesWritten.single, endsWith('.json'));

      expect(tester.takeException(), isNull,
          reason: 'tidak boleh ada eksepsi lolos dari kedua tombol');
    });
  });
}
