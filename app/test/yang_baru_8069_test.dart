// Ronde 8069 — "Yang Baru": lembar catatan rilis di dalam aplikasi.
//
// Kontrak yang dikunci pemilik (2026-11-21):
// (1) Aplikasi menampilkan HANYA blok pengguna badan rilis — poin-poin
//     di bawah judul `## Yang baru`. Lapis teknis (di bawah pemisah
//     `---` / di dalam `<details>`) TIDAK PERNAH tampil.
// (2) Rilis tanpa blok pengguna (warisan) → tidak ada pintu masuk:
//     tombol banner tidak muncul, baris Pengaturan tidak muncul.
// (3) Lembar mengikuti rujukan desain Stitch yang divonis pemilik:
//     judul Clash Display "Yang baru di {versi}", "Bangun {build}",
//     poin bertitik Volt, tombol utama pill Volt terisi (Unduh/Pasang
//     mengikuti status), "Nanti saja" menutup lembar saja.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:clai/app.dart';
import 'package:clai/data/app_db.dart';
import 'package:clai/l10n/app_localizations.dart';
import 'package:clai/services/update_service.dart';
import 'package:clai/ui/update_section.dart';
import 'package:clai/ui/whats_new_sheet.dart';

/// Badan rilis 2.0.3 ASLI (terbit 21 Nov 2026, tag v2.0.3+8068) —
/// bentuk dua-lapis persis seperti yang dilayani GitHub.
const body203 = '''
## Yang baru

- Pembaruan di dalam aplikasi tidak lagi salah memasang berkas lama: Clai kini selalu mengambil versi yang benar, dan berkas pembaruan lama yang tersimpan dibersihkan.
- Perintah suara makin paham cara kamu bicara: lebih banyak variasi kalimat dikenali, dan judul lagu atau nama penyanyi yang terdengar mirip tetap ketemu.
- Acak Cerdas sekarang benar-benar mengacak — termasuk antrean putar otomatis dan sesi yang dipulihkan dari sebelumnya — dan saklarnya langsung merespons saat diketuk, tanpa harus keluar-masuk layar.
- Lirik mengikuti lagu: biarkan layar lirik tetap terbuka, liriknya ikut berganti saat lagu berpindah. Baris lirik yang panjang juga tidak terpotong lagi.
- Saat lagu sedang diunduh, jumlah yang masih berjalan kini terlihat — tidak lagi terbaca nol.

---

<details>
<summary>Technical details</summary>

**Updater (8065)** — The in-app updater could reinstall a stale download from a previous release.

**Gates** — 834/834 tests passing on both machines.

</details>
''';

void main() {
  group('userFacingNotes — ekstrak blok pengguna saja', () {
    test('badan dua-lapis nyata 2.0.3: 5 poin, nol isi teknis', () {
      final notes = userFacingNotes(body203);
      expect(notes.length, 5);
      expect(notes.first, startsWith('Pembaruan di dalam aplikasi'));
      expect(notes.last, startsWith('Saat lagu sedang diunduh'));
      for (final n in notes) {
        expect(n, isNot(contains('Updater (8065)')));
        expect(n, isNot(contains('834/834')));
        expect(n, isNot(contains('Technical details')));
      }
    });

    test('badan warisan tanpa blok → kosong', () {
      const legacy = '''
**Perbaikan**

- Poin lama satu.
- Poin lama dua.
''';
      expect(userFacingNotes(legacy), isEmpty);
      expect(userFacingNotes(''), isEmpty);
      expect(userFacingNotes('hanya teks biasa'), isEmpty);
    });

    test('CRLF: akhir baris Windows tidak mengubah hasil', () {
      final crlf = body203.replaceAll('\n', '\r\n');
      expect(userFacingNotes(crlf), userFacingNotes(body203));
      expect(userFacingNotes(crlf).length, 5);
    });

    test('<details> tanpa pemisah --- tetap menghentikan pengumpulan', () {
      const body = '''
## Yang baru

- Satu-satunya poin pengguna.
<details>
<summary>Technical details</summary>

- Poin teknis yang tidak boleh bocor.

</details>
''';
      expect(userFacingNotes(body), ['Satu-satunya poin pengguna.']);
    });

    test('judul ## berikutnya menghentikan pengumpulan', () {
      const body = '''
## Yang baru

- Poin pengguna.

## Bagian lain

- Bukan poin pengguna.
''';
      expect(userFacingNotes(body), ['Poin pengguna.']);
    });

    test('blok ada tapi nol poin → kosong', () {
      const body = '''
## Yang baru

Belum ada catatan untuk rilis ini.

---

<details>
<summary>Technical details</summary>

- Teknis.
</details>
''';
      expect(userFacingNotes(body), isEmpty);
    });

    test('konten sebelum blok tidak ikut terbawa', () {
      const body = '''
Pembuka rilis.

- Poin liar sebelum blok.

## Yang baru

- Poin resmi.
''';
      expect(userFacingNotes(body), ['Poin resmi.']);
    });
  });

  group('UI Yang Baru — lembar, banner, Pengaturan', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    late AppDb db;
    late Directory dir;

    setUp(() async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      dir = await Directory.systemTemp.createTemp('yangbaru8069');
      db = AppDb();
      await db.openAt('${dir.path}/t.db');
    });

    tearDown(() async {
      await db.close();
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    UpdateController controller(UpdateStatus status, String notes) {
      final upd = UpdateController(db);
      upd.release = ReleaseInfo(
        tag: 'v2.0.3+8068',
        versionName: '2.0.3',
        build: 8068,
        notes: notes,
        assets: const [
          (name: 'clai.apk', url: 'https://example.invalid/clai.apk', size: 1)
        ],
      );
      upd.status = status;
      return upd;
    }

    Widget tree(UpdateController upd, Widget home) => ProviderScope(
          overrides: [
            appDbProvider.overrideWithValue(db),
            updateControllerProvider.overrideWith((_) => upd),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('id'),
            home: home,
          ),
        );

    testWidgets('lembar: judul, bangun, 5 poin nyata, aksi Unduh',
        (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final upd = controller(UpdateStatus.available, body203);
      await tester.pumpWidget(tree(
        upd,
        Scaffold(
          body: Builder(
            builder: (ctx) => Center(
              child: TextButton(
                onPressed: () => openWhatsNewSheet(ctx),
                child: const Text('buka lembar'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('buka lembar'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Yang baru di 2.0.3'), findsOneWidget);
      expect(find.text('Bangun 8068'), findsOneWidget);
      for (final n in userFacingNotes(body203)) {
        expect(find.text(n), findsOneWidget, reason: 'poin tampil: $n');
      }
      // Lapis teknis tidak boleh muncul di lembar.
      expect(find.textContaining('Technical details'), findsNothing);
      expect(find.textContaining('Updater (8065)'), findsNothing);
      // Aksi utama keadaan "tersedia" = Unduh; hantu menutup lembar saja.
      expect(find.text('Unduh'), findsOneWidget);
      await tester.tap(find.text('Nanti saja'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Yang baru di 2.0.3'), findsNothing,
          reason: 'Nanti saja menutup lembar');
      expect(upd.status, UpdateStatus.available,
          reason: 'menutup lembar tidak mengubah status pembaruan');
    });

    testWidgets('lembar: keadaan siap pasang → aksi utama Pasang',
        (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final upd = controller(UpdateStatus.readyToInstall, body203);
      await tester.pumpWidget(tree(upd, const Scaffold(body: WhatsNewSheet())));
      await tester.pump();
      expect(find.text('Pasang'), findsOneWidget);
      expect(find.text('Unduh'), findsNothing);
    });

    // Banner membaca pref dari DB (I/O nyata) sebelum tampil — beri
    // waktu nyata lewat runAsync, bukan hanya pompa jam palsu.
    Future<void> pumpBanner(WidgetTester tester, String notes) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(tree(
        controller(UpdateStatus.available, notes),
        const Scaffold(body: UpdateHomeBanner()),
      ));
      await tester
          .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 250)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }

    testWidgets('banner: poin ada → tombol Yang baru tampil', (tester) async {
      await pumpBanner(tester, body203);
      expect(find.text('Clai 2.0.3 tersedia'), findsOneWidget);
      expect(find.text('Yang baru'), findsOneWidget);
    });

    testWidgets('banner: rilis warisan tanpa blok → tombol absen',
        (tester) async {
      await pumpBanner(tester, 'catatan lama tanpa blok');
      expect(find.text('Clai 2.0.3 tersedia'), findsOneWidget,
          reason: 'banner tetap tampil untuk rilis warisan');
      expect(find.text('Yang baru'), findsNothing,
          reason: 'tanpa blok pengguna, tombol Yang baru WAJIB absen');
    });

    Future<void> pumpSettings(WidgetTester tester, String notes) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(tree(
        controller(UpdateStatus.available, notes),
        const Scaffold(
            body: SingleChildScrollView(child: UpdateSettingsSection())),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }

    testWidgets('Pengaturan: poin ada → baris Yang baru tampil',
        (tester) async {
      await pumpSettings(tester, body203);
      expect(find.text('Yang baru di 2.0.3'), findsOneWidget);
      // Ronde 8084 (§13.2): subjudul penjelas baris ini DIBUANG —
      // baris tampil lewat judulnya saja.
      expect(find.text('Lihat catatan rilis pembaruan'), findsNothing,
          reason: 'subjudul penjelas dibuang ronde 8084');
    });

    testWidgets('Pengaturan: catatan kosong → baris Yang baru absen',
        (tester) async {
      await pumpSettings(tester, '');
      expect(find.text('Yang baru di 2.0.3'), findsNothing,
          reason: 'catatan kosong → baris Yang baru WAJIB absen');
    });
  });
}
