// Ronde 8079 — Pengumuman sesudah update (B1/B2; spec
// desain-f3/pisah-pengaturan/BANNER-UPDATE.md).
//
// Kontrak yang diuji:
// (1) Klasifikasi tingkat murni: minor/major → fitur; patch/bangun →
//     tambalan; sama/turun → tidak ada.
// (2) Pemetaan kata kunci permukaan + pemecahan item sorotan (murni).
// (3) Mesin tampil-sekali di UpdateController: instalasi segar diam;
//     debut pada basis lama bersumber umpan; perubahan versi memakai
//     simpanan unduhan; belum terjawab → tampil lagi (basis tidak
//     maju); sesudah ditutup → tidak pernah lagi untuk versi itu.
// (4) Widget: spanduk B2 tampil/menutup; overlay B1 tampil sekali
//     lewat pemicu, ≤4 baris sorotan + hitungan sisa, "Nanti saja"
//     menutup & memajukan basis.
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:clai/app.dart';
import 'package:clai/data/app_db.dart';
import 'package:clai/l10n/app_localizations.dart';
import 'package:clai/services/update_service.dart';
import 'package:clai/ui/announcement.dart';

const _sysChannel = MethodChannel('clai/sys');
({String name, int code}) _installed = (name: '2.1.0', code: 10079);

void _mockSys() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_sysChannel, (call) async {
    if (call.method == 'appVersion') {
      return <String, Object>{
        'versionName': _installed.name,
        'versionCode': _installed.code,
      };
    }
    return null;
  });
}

class _FeedAdapter implements HttpClientAdapter {
  final Map<String, dynamic> payload;
  _FeedAdapter(this.payload);
  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    return ResponseBody.fromString(jsonEncode(payload), 200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType]
        });
  }

  @override
  void close({bool force = false}) {}
}

Map<String, dynamic> _feed210() => {
      'tag_name': 'v2.1.0+8079',
      'body': '## Yang baru\n'
          '- Brankas Sesi: simpan antrean yang sedang berjalan untuk nanti.\n'
          '- Panel Acak gabungan: acak jujur dan acak cerdas dalam satu panel.\n'
          '\n---\n<details><summary>Teknis</summary>isi teknis</details>',
      'assets': <Object>[],
    };

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    _mockSys();
  });

  group('klasifikasi tingkat (murni)', () {
    AnnouncementTier c(String a, int ab, String b, int bb) =>
        classifyVersionChange(
            fromName: a, fromBuild: ab, toName: b, toBuild: bb);
    test('minor berubah → fitur', () {
      expect(c('2.0.3', 68, '2.1.0', 79), AnnouncementTier.feature);
      expect(c('2.1.0', 79, '3.0.0', 90), AnnouncementTier.feature);
    });
    test('patch / bangun saja → tambalan', () {
      expect(c('2.1.0', 79, '2.1.1', 80), AnnouncementTier.patch);
      expect(c('2.1.0', 79, '2.1.0', 80), AnnouncementTier.patch);
    });
    test('sama / turun → tidak ada', () {
      expect(c('2.1.0', 79, '2.1.0', 79), AnnouncementTier.none);
      expect(c('2.1.0', 79, '2.1.0', 78), AnnouncementTier.none);
      expect(c('2.1.0', 79, '2.0.3', 68), AnnouncementTier.none);
    });
  });

  group('pemetaan permukaan & pecah item (murni)', () {
    test('kata kunci → permukaan unggulan', () {
      expect(announceSurfaceFor('Brankas Sesi untuk antreanmu'),
          AnnounceSurface.vault);
      expect(announceSurfaceFor('Bagikan playlist lewat kode QR'),
          AnnounceSurface.share);
      expect(announceSurfaceFor('Mode Samaran kini punya penjelas'),
          AnnounceSurface.taste);
      expect(announceSurfaceFor('Panel Acak gabungan yang jujur'),
          AnnounceSurface.shuffle);
      expect(announceSurfaceFor('Perbaikan kecil di balik layar'), isNull);
    });
    test('pecah "Kepala: isi" hanya untuk kepala pendek', () {
      final a = splitAnnounceItem('Brankas Sesi: simpan antreanmu.');
      expect(a.title, 'Brankas Sesi');
      expect(a.subtitle, 'simpan antreanmu.');
      final b = splitAnnounceItem(
          'Panel acak kini menampilkan urutan lagu berikutnya secara terbuka dan jujur');
      expect(b.subtitle, isNull);
      expect(b.title, startsWith('Panel acak'));
      final long = splitAnnounceItem(
          'Judul yang sangat panjang sekali melebihi batas: isinya di sini');
      expect(long.subtitle, isNull);
    });
  });

  group('mesin tampil-sekali (UpdateController)', () {
    late Directory dir;
    late AppDb db;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('announce8079');
      db = AppDb();
      await db.openAt('${dir.path}/t.db');
      _installed = (name: '2.1.0', code: 10079);
    });

    tearDown(() async {
      await db.close();
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    test('instalasi segar: basis diam-diam, tanpa pengumuman', () async {
      final c = UpdateController(db);
      await c.evaluateAnnouncement();
      expect(c.hasAnnouncement, isFalse);
      expect(await db.pref<String>('announce.seenVersionName'), '2.1.0');
      expect(await db.pref<int>('announce.seenBuild'), 79);
    });

    test('debut pada basis lama: bersumber umpan → fitur bersenjata',
        () async {
      await db.setPref(
          'update.lastCheckMs', DateTime.now().millisecondsSinceEpoch);
      final dio = Dio()..httpClientAdapter = _FeedAdapter(_feed210());
      final c = UpdateController(db, dio: dio);
      await c.evaluateAnnouncement();
      expect(c.announceTier, AnnouncementTier.feature);
      expect(c.announceVersionName, '2.1.0');
      expect(c.announceNotes.length, 2);
      expect(c.announceNotes.first, contains('Brankas Sesi'));
      // Cache catatan terpasang terisi oleh check() di dalamnya.
      expect(await db.pref<String>('announce.currentNotesVersion'),
          '2.1.0');
    });

    test('perubahan versi memakai simpanan unduhan; belum terjawab '
        '→ tampil lagi; sesudah ditutup → tidak lagi', () async {
      await db.setPref('announce.seenVersionName', '2.0.3');
      await db.setPref('announce.seenBuild', 68);
      await db.setPref('announce.pendingVersionName', '2.1.0');
      await db.setPref('announce.pendingBuild', 8079);
      await db.setPref('announce.pendingNotes',
          '## Yang baru\n- Brankas Sesi: simpan antreanmu.\n');
      final c1 = UpdateController(db)..autoCheck = false;
      await c1.evaluateAnnouncement();
      expect(c1.announceTier, AnnouncementTier.feature);
      expect(c1.announceNotes, hasLength(1));
      // Basis TIDAK maju sebelum dijawab:
      expect(await db.pref<String>('announce.seenVersionName'), '2.0.3');
      // Pengendali baru (buka dingin berikutnya) → bersenjata lagi.
      final c2 = UpdateController(db)..autoCheck = false;
      await c2.evaluateAnnouncement();
      expect(c2.announceTier, AnnouncementTier.feature);
      // Ditutup → basis maju; pengendali berikutnya diam.
      await c2.dismissAnnouncement();
      expect(await db.pref<String>('announce.seenVersionName'), '2.1.0');
      final c3 = UpdateController(db)..autoCheck = false;
      await c3.evaluateAnnouncement();
      expect(c3.hasAnnouncement, isFalse);
    });

    test('tambalan tanpa catatan: B2 bersenjata dengan catatan kosong',
        () async {
      await db.setPref('announce.seenVersionName', '2.1.0');
      await db.setPref('announce.seenBuild', 79);
      _installed = (name: '2.1.1', code: 10080);
      final c = UpdateController(db)..autoCheck = false;
      await c.evaluateAnnouncement();
      expect(c.announceTier, AnnouncementTier.patch);
      expect(c.announceNotes, isEmpty);
    });

    test('turun versi: basis digeser diam-diam', () async {
      await db.setPref('announce.seenVersionName', '2.1.0');
      await db.setPref('announce.seenBuild', 79);
      _installed = (name: '2.0.3', code: 10068);
      final c = UpdateController(db)..autoCheck = false;
      await c.evaluateAnnouncement();
      expect(c.hasAnnouncement, isFalse);
      expect(await db.pref<String>('announce.seenVersionName'), '2.0.3');
    });
  });

  group('widget — B2 & B1', () {
    late Directory dir;
    late AppDb db;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('announce_w');
      db = AppDb();
      await db.openAt('${dir.path}/t.db');
      _installed = (name: '2.1.0', code: 10079);
    });

    tearDown(() async {
      await db.close();
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    UpdateController armed(AnnouncementTier tier, List<String> notes,
        {String version = '2.1.1'}) {
      final c = UpdateController(db)..autoCheck = false;
      c.announceTier = tier;
      c.announceVersionName = version;
      c.announceNotes = notes;
      return c;
    }

    Widget tree(UpdateController c, Widget home) => ProviderScope(
          overrides: [
            appDbProvider.overrideWithValue(db),
            updateControllerProvider.overrideWith((ref) => c),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('id'),
            home: home,
          ),
        );

    testWidgets('B2: tampil untuk tambalan, ✕ menutup & memajukan basis',
        (tester) async {
      // Semua sentuhan ffi WAJIB di dalam runAsync (jebakan zona
      // async-palsu badan testWidgets — pola suite 8072/8074).
      await tester.runAsync(() async {
        await db.setPref('announce.seenVersionName', '2.1.0');
        await db.setPref('announce.seenBuild', 79);
      });
      _installed = (name: '2.1.1', code: 10080);
      final c = armed(AnnouncementTier.patch, const [], version: '2.1.1');
      await tester.pumpWidget(
          tree(c, const Scaffold(body: PatchInstalledBanner())));
      await tester.pump();
      expect(find.text('Clai 2.1.1 sudah terpasang'), findsOneWidget);
      expect(find.text('Perbaikan kecil di balik layar'), findsOneWidget);
      // Tanpa catatan: "Lihat" disembunyikan.
      expect(find.text('Lihat'), findsNothing);
      await tester.runAsync(() async {
        await tester.tap(find.byTooltip('Tutup'));
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();
      expect(c.hasAnnouncement, isFalse);
      expect(find.text('Clai 2.1.1 sudah terpasang'), findsNothing);
      await tester.runAsync(() async {
        expect(await db.pref<String>('announce.seenVersionName'), '2.1.1');
      });
    });

    testWidgets('B2 dengan catatan: "Lihat" membuka lembar catatan',
        (tester) async {
      final c = armed(AnnouncementTier.patch,
          const ['Perbaikan putar di latar.'], version: '2.1.1');
      await tester.pumpWidget(
          tree(c, const Scaffold(body: PatchInstalledBanner())));
      await tester.pump();
      expect(find.text('Lihat'), findsOneWidget);
      await tester.runAsync(() async {
        await tester.tap(find.text('Lihat'));
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pumpAndSettle();
      expect(find.text('Perbaikan putar di latar.'), findsOneWidget);
      expect(find.text('Yang baru di Clai'), findsOneWidget);
    });

    testWidgets(
        'B1: pemicu menampilkan overlay sekali — kicker, ≤4 sorotan, '
        'hitungan sisa, CTA dari item teratas; "Nanti saja" menutup',
        (tester) async {
      await tester.runAsync(() async {
        await db.setPref('announce.seenVersionName', '2.0.3');
        await db.setPref('announce.seenBuild', 68);
      });
      final c = armed(AnnouncementTier.feature, const [
        'Brankas Sesi: simpan antrean yang sedang berjalan untuk nanti.',
        'Panel Acak gabungan dalam satu panel.',
        'Mode Samaran kini punya dialog penjelas.',
        'Cari pengaturan menemukan semua baris.',
        'Perbaikan kecil di balik layar.',
      ], version: '2.1.0');
      await tester.pumpWidget(tree(
          c,
          const Scaffold(
              body: Stack(children: [FeatureAnnouncementTrigger()]))));
      // Pemicu menjadwalkan sesudah bingkai; dialog beranimasi masuk.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('BARU DI CLAI 2.1.0'), findsOneWidget);
      expect(find.text('Yang baru di Clai'), findsOneWidget);
      expect(find.text('Brankas Sesi'), findsOneWidget);
      expect(find.text('simpan antrean yang sedang berjalan untuk nanti.'),
          findsOneWidget);
      // Item kelima BUKAN baris sorotan — hanya hitungan sisa.
      expect(find.text('Perbaikan kecil di balik layar.'), findsNothing);
      expect(find.text('dan 1 hal baru lainnya'), findsOneWidget);
      // CTA mengikuti item teratas (Brankas).
      expect(find.text('Buka Brankas Sesi'), findsOneWidget);
      expect(find.text('Nanti saja'), findsOneWidget);
      await tester.runAsync(() async {
        await tester.tap(find.text('Nanti saja'));
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pumpAndSettle();
      expect(find.text('BARU DI CLAI 2.1.0'), findsNothing);
      expect(c.hasAnnouncement, isFalse);
      await tester.runAsync(() async {
        expect(await db.pref<String>('announce.seenVersionName'), '2.1.0');
      });
    });
  });
}
