import 'dart:io';

import 'package:clai/app.dart';
import 'package:clai/data/app_db.dart';
import 'package:clai/domain/models.dart';
import 'package:clai/l10n/l10n.dart';
import 'package:clai/services/library_controller.dart';
import 'package:clai/ui/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/src/google_fonts_base.dart' as gfb;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Tes regresi Ronde Perbaikan Audit 8047 — satu grup per temuan yang
/// bisa dikunci mesin: byline Mood anti-merek, alur buat-playlist dari
/// lembar Tambah ke Playlist (trek wajib ikut masuk), dan ketiadaan
/// pola yang dilarang audit di seluruh lib/ (penimpaan ibu jari
/// sakelar, fontSize pecahan, radius 10).

Track _t(String id) => Track(
      key: TrackKey('ytmusic', id),
      title: 'Lagu $id',
      artistNames: 'Artis',
      duration: const Duration(minutes: 3),
      playableRef: id,
    );

void main() {
  group('moodRowSubtitle (audit #5: Mood anti-merek)', () {
    test('segmen merek dibuang, segmen jujur dipertahankan', () {
      expect(moodRowSubtitle('Playlist • YouTube Music', 'Playlist'),
          'Playlist');
      expect(moodRowSubtitle('Artist • YouTube Music', 'Album'), 'Artist');
    });

    test('byline merek murni jatuh ke label jenis', () {
      expect(moodRowSubtitle('YouTube Music', 'Albums'), 'Albums');
      expect(moodRowSubtitle('', 'Playlists'), 'Playlists');
    });

    test('nama artis nyata tidak disentuh', () {
      expect(moodRowSubtitle('Iwan Fals', 'Albums'), 'Iwan Fals');
    });
  });

  group('buat playlist dari lembar Tambah ke Playlist (temuan fungsi)',
      () {
    late AppDb db;
    late LibraryController lib;

    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      // Teks isi memakai GoogleFonts (Inter): di lingkungan tes, layani
      // berkas font ASLI dari fixture lewat klien HTTP tiruan
      // (hash+ukuran diverifikasi google_fonts sendiri) dan arahkan
      // path_provider ke direktori sementara agar simpan font di latar
      // tidak melempar MissingPluginException. (Font tampilan Clash
      // Display terbundel sejak 8049 — tidak lagi lewat jalur ini.)
      TestWidgetsFlutterBinding.ensureInitialized();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async => Directory.systemTemp.path,
      );
      gfb.httpClient = MockClient((request) async {
        final f = File('test/fixtures/fonts/${request.url.pathSegments.last}');
        if (request.url.host == 'fonts.gstatic.com' && f.existsSync()) {
          return http.Response.bytes(await f.readAsBytes(), 200);
        }
        return http.Response('', 404);
      });
    });

    setUp(() async {
      db = AppDb();
      await db.openAt(':memory:');
      lib = LibraryController(db);
      await lib.load();
    });

    testWidgets('trek yang ditambahkan ikut masuk ke playlist barunya',
        (tester) async {
      final track = _t('f1');
      await tester.pumpWidget(
        ProviderScope(
          overrides: [libraryProvider.overrideWith((_) => lib)],
          child: MaterialApp(
            locale: const Locale('id'),
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            home: Consumer(
              builder: (context, ref, _) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () =>
                        showAddToPlaylistSheet(context, ref, track),
                    child: const Text('buka'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('buka'));
      await tester.pumpAndSettle();
      // Baris "Playlist baru" di lembar pemilih.
      await tester.tap(find.text('Playlist baru'));
      await tester.pumpAndSettle();
      // Dialog nama: isi lalu Simpan.
      await tester.enterText(find.byType(TextField), 'Campuran Uji');
      await tester.tap(find.text('Simpan'));
      await tester.pumpAndSettle();
      // Rantai buat+masuk BERGANTIAN antara mikrotugas zona-palsu dan
      // future IO basis data NYATA (ffi): pumpAndSettle saja membuat
      // future nyata menggantung, runAsync saja membuat kelanjutan
      // zona-palsu macet — keduanya harus diselang-seling sampai
      // KEADAAN AKHIR (playlist lahir DAN hitungannya sudah 1)
      // mendarat.
      for (var i = 0; i < 40; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pumpAndSettle();
        if (lib.playlists.isNotEmpty && lib.playlists.single.count == 1) {
          break;
        }
      }

      expect(lib.playlists, hasLength(1),
          reason: 'playlist baru harus lahir dari alur lembar');
      expect(lib.playlists.single.name, 'Campuran Uji');
      expect(lib.playlists.single.count, 1,
          reason:
              'BUG audit 8047: playlist lahir 0 lagu — trek yang sedang ditambahkan tidak ikut masuk');
      final tracks = await tester
          .runAsync(() => db.playlistTracks(lib.playlists.single.id));
      expect(tracks!.map((e) => e.id), ['f1']);
      // Lembar dibuka lagi oleh alur setelah trek masuk — beri
      // beberapa putaran siram yang sama agar rute lembarnya sempat
      // terbangun, lalu periksa hitungan yang tampil di barisnya.
      for (var i = 0; i < 10 && find.text('1 lagu').evaluate().isEmpty; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pumpAndSettle();
      }
      expect(find.text('1 lagu'), findsOneWidget);
    });
  });

  group('sapuan sumber (audit #1/#7/#8)', () {
    String allSources() => Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .map((f) => f.readAsStringSync())
        .join('\n');

    test('tidak ada penimpaan activeThumbColor tersisa di lib/', () {
      expect(allSources().contains('activeThumbColor'), isFalse,
          reason: 'tema §6.14 yang memerintah ibu jari sakelar');
    });

    test('tidak ada fontSize pecahan di lib/', () {
      expect(
          RegExp(r'fontSize: \d+\.\d').hasMatch(allSources()), isFalse,
          reason: 'semua ukuran teks pada tangga type Bab 3');
    });

    test('tidak ada BorderRadius.circular(10) di lib/', () {
      expect(allSources().contains('BorderRadius.circular(10)'), isFalse,
          reason: 'radius pada tangga §4 (8/12–16/20/999)');
    });

    test('Mode Mobil: penekanan chrome aman-struktur, bukan rute akar',
        () {
      // Regresi bisek 8047 (#16) — DUA jalan buntu yang terbukti di
      // bangku, keduanya dilarang kembali:
      // (a) Mendorong DrivingScreen pada navigator akar melempar
      //     "No ProviderScope found" (log insiden perangkat
      //     2026-11-10 16:31) — scope hidup di dalam cangkang.
      // (b) Menukar anak Stack chrome menjadi SizedBox.shrink() saat
      //     bendera naik membuat rute HITAM TOTAL tanpa error terlog
      //     (pertukaran struktur di Stack yang berbagi tempat dengan
      //     platform view DirectEngineHost).
      // Pola yang diizinkan: bendera claiChromeSuppressed + chrome
      // selalu terpasang, disembunyikan lewat Opacity/IgnorePointer
      // dengan sub-pohon diteruskan sebagai child yang identik.
      final app = File('lib/app.dart').readAsStringSync();
      expect(app.contains('claiChromeSuppressed'), isTrue);
      expect(app.contains('IgnorePointer'), isTrue,
          reason: 'penekanan chrome wajib tanpa pertukaran struktur');
      expect(app.contains('Opacity'), isTrue);
      final section =
          File('lib/ui/driving_section.dart').readAsStringSync();
      expect(section.contains('rootNavigator: true'), isFalse,
          reason: 'navigator akar di luar ProviderScope aplikasi');
      final screen =
          File('lib/ui/driving_screen.dart').readAsStringSync();
      expect(screen.contains('addPostFrameCallback'), isTrue,
          reason: 'bendera hanya dipasang/lepas pasca-bingkai');
    });
  });
}
