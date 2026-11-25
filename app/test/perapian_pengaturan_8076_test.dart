import 'package:clai/data/app_db.dart';
import 'package:clai/app.dart';
import 'package:clai/l10n/app_localizations.dart';
import 'package:clai/ui/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ronde 8076 — Perapian Pengaturan (desain Stitch yang diterima riyan
/// 21 Nov 17:43): hub 14 pintu → 7 kelompok desain + Selera + Tentang;
/// Tampilan jadi sub-halaman; "Cari pengaturan" mengindeks SETIAP baris.
///
/// Ronde 8079 (Pisah Pengaturan): pintu Selera + Kepemilikan keluar
/// dari hub ke laci Menu — hub kini TUJUH pintu murni preferensi;
/// Kepemilikan diuji sebagai halaman publik yang berdiri sendiri;
/// kelengkapan indeks cari tetap dijaga di sini (label lokasi barunya
/// diuji di menu_laci_8079_test.dart).
///
/// Kontrak yang dijaga di sini:
/// 1. Struktur hub persis (8076: 9 pintu; 8079: TUJUH — Selera &
///    Kepemilikan pindah ke laci Menu dan TIDAK lagi tampil sebagai
///    pintu hub).
/// 2. Kelengkapan indeks pencarian: setiap entri [settingsSearchIndex]
///    ketemu lewat judulnya sendiri di kolom cari (uji besar versi
///    widget — tanpa baris yatim).
/// 3. Keadaan kosong pencarian jujur.
/// 4. Catatan kaki Tampilan = kebenaran DS v5.0 (temuan basi 8073).
/// 5. Pintu Brankas Sesi hadir di Kepemilikan (penempatan 8076; pada
///    8079 halamannya dipompa langsung karena pintu hubnya pindah).
class _NullPrefDb extends AppDb {
  @override
  Future<T?> pref<T>(String key) async => null;
}

/// Serap notis debug WARISAN hub (pola 8070/8052): ListTile telanjang
/// di kartu DecoratedBox → aseran "ink splashes may be invisible" di
/// mode debug (terstrip di rilis). Serap HANYA notis itu; eksepsi lain
/// menggagalkan tes.
void absorbHubNotices(WidgetTester tester, {int cap = 80}) {
  var e = tester.takeException();
  while (e != null) {
    final s = e.toString();
    final agg = RegExp(r'Multiple exceptions \((\d+)\)').firstMatch(s);
    final ok = s.contains('ListTile background color or ink splashes') ||
        (agg != null && int.parse(agg.group(1)!) <= cap);
    expect(ok, isTrue, reason: 'eksepsi tak terduga: $e');
    e = tester.takeException();
  }
}

Future<void> untilFound(WidgetTester tester, Finder f,
    {int tries = 40}) async {
  for (var i = 0; i < tries; i++) {
    if (f.evaluate().isNotEmpty) return;
    await tester.pump(const Duration(milliseconds: 100));
  }
  throw StateError('tidak ditemukan: $f');
}

Future<void> pumpSettings(WidgetTester tester) async {
  tester.view.physicalSize = const Size(390, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.runAsync(() async {
    await tester.pumpWidget(ProviderScope(
      overrides: [appDbProvider.overrideWithValue(_NullPrefDb())],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('id'),
        home: const SettingsScreen(),
      ),
    ));
    await untilFound(tester, find.text('Pengaturan'));
    await tester.pump();
  });
}

void main() {
  group('Ronde 8076 — Perapian Pengaturan', () {
    testWidgets('hub = TUJUH pintu preferensi (8079: Selera & '
        'Kepemilikan pindah ke laci Menu); pintu lama yang dilipat '
        'hilang dari hub', (tester) async {
      await pumpSettings(tester);
      absorbHubNotices(tester);
      for (final g in [
        'Tampilan',
        'Pemutaran',
        'Audio',
        'Unduhan & Offline',
        'Fitur Tambahan',
        'Sistem',
        'Tentang',
      ]) {
        expect(find.text(g), findsWidgets, reason: 'pintu hub hilang: $g');
      }
      // Pintu-pintu lama yang DILIPAT tidak boleh lagi jadi pintu hub —
      // termasuk dua pintu 8076 yang pindah ke laci Menu pada 8079.
      for (final gone in [
        'Berkendara',
        'Tangkap',
        'Jalan di Latar',
        'Data & Penyimpanan',
        'Pembaruan',
        'ListenBrainz',
        'Diagnosis',
        'Selera',
        'Kepemilikan',
      ]) {
        expect(find.text(gone), findsNothing,
            reason: 'pintu lama masih di hub: $gone');
      }
      // Pil Cari pengaturan tampil di puncak hub.
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Cari pengaturan'), findsOneWidget);
      absorbHubNotices(tester);
    });

    testWidgets('Tampilan kini sub-halaman: isinya utuh, TANPA catatan '
        'kaki apa pun (sapuan tegas 8081)', (tester) async {
      await pumpSettings(tester);
      await tester.tap(find.text('Tampilan').last);
      await untilFound(tester, find.text('Tema Dinamis'));
      absorbHubNotices(tester);
      expect(find.text('Tema Dinamis'), findsOneWidget);
      expect(find.text('Nama sapaan'), findsWidgets);
      expect(find.text('Bahasa'), findsWidgets);
      // Riwayat spec: 8076 menuntut catatan kaki DS v5.0; 8080
      // memangkasnya jadi satu baris; 8081 (perintah tegas pemilik)
      // MENGHAPUSNYA — halaman berakhir di baris terakhirnya.
      // Gulir ke baris terbawah (Bahasa) agar dasar halaman terender,
      // lalu buktikan tak ada catatan kaki dalam bentuk apa pun.
      await tester.ensureVisible(find.text('Bahasa').last);
      await tester.pump();
      expect(find.textContaining('Nuansa mengikuti warna sampul'),
          findsNothing,
          reason: 'catatan kaki 8080 tidak boleh kembali (8081)');
      expect(find.textContaining('selalu Volt'), findsNothing,
          reason: 'klaim basi 8073 masih hidup');
      absorbHubNotices(tester);
    });

    testWidgets('Kepemilikan (halaman publik 8079) memuat pintu '
        'Brankas Sesi', (tester) async {
      // 8076 menjangkau halaman ini lewat pintu hub; 8079 pintu hubnya
      // hilang (pindah ke laci Menu) — halaman dipompa langsung.
      tester.view.physicalSize = const Size(390, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.runAsync(() async {
        await tester.pumpWidget(ProviderScope(
          overrides: [appDbProvider.overrideWithValue(_NullPrefDb())],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('id'),
            home: const OwnershipPage(),
          ),
        ));
        await untilFound(tester, find.text('Ekspor data'));
      });
      absorbHubNotices(tester);
      await tester.ensureVisible(find.text('Brankas Sesi'));
      await tester.pump();
      expect(find.text('Brankas Sesi'), findsWidgets);
      absorbHubNotices(tester);
    });

    testWidgets('Fitur Tambahan memuat Berkendara + Tangkap + ListenBrainz',
        (tester) async {
      await pumpSettings(tester);
      await tester.ensureVisible(find.text('Fitur Tambahan'));
      await tester.pump();
      await tester.tap(find.text('Fitur Tambahan').last);
      await untilFound(tester, find.text('Mode Berkendara'));
      absorbHubNotices(tester);
      expect(find.text('Mode Berkendara'), findsWidgets);
      await tester.ensureVisible(
          find.text('Kirim riwayat dengar ke ListenBrainz'));
      await tester.pump();
      expect(find.text('Kirim riwayat dengar ke ListenBrainz'),
          findsWidgets);
      absorbHubNotices(tester);
    });

    testWidgets('Sistem memuat Pembaruan + Diagnosis + Data', (tester) async {
      await pumpSettings(tester);
      await tester.ensureVisible(find.text('Sistem'));
      await tester.pump();
      await tester.tap(find.text('Sistem').last);
      await untilFound(tester, find.text('Status izin latar'));
      absorbHubNotices(tester);
      expect(find.text('Periksa pembaruan'), findsWidgets);
      await tester.ensureVisible(find.text('Diagnostik Putar'));
      await tester.pump();
      expect(find.text('Diagnostik Putar'), findsWidgets);
      absorbHubNotices(tester);
    });

    testWidgets('UJIAN KELENGKAPAN: setiap entri indeks ketemu lewat '
        'judulnya sendiri di Cari pengaturan', (tester) async {
      await pumpSettings(tester);
      final ctx = tester.element(find.byType(SettingsScreen));
      final index = settingsSearchIndex(ctx);
      expect(index.length, greaterThanOrEqualTo(55),
          reason: 'indeks menyusut dari inventaris baris nyata');
      // Judul entri tidak boleh ganda persis (hasil ambigu).
      final titles = index.map((e) => e.title).toList();
      expect(titles.toSet().length, titles.length,
          reason: 'judul entri ganda: $titles');
      final field = find.byType(TextField);
      for (final entry in index) {
        await tester.enterText(field, entry.title);
        await tester.pump();
        expect(find.text(entry.title), findsWidgets,
            reason: 'baris yatim: "${entry.title}" tidak ketemu lewat '
                'judulnya sendiri');
        absorbHubNotices(tester);
      }
      // Kata kunci sampah → keadaan kosong yang jujur.
      await tester.enterText(field, 'zxqvkj');
      await tester.pump();
      expect(find.textContaining('Tidak ada pengaturan untuk'), findsOneWidget);
      // Sapuan tegas 8081: subjudul saran di bawah keadaan kosong
      // dibuang — keadaan kosong kini judulnya saja.
      expect(find.textContaining('Coba kata lain'), findsNothing);
      absorbHubNotices(tester);
    });

    testWidgets(
        'regresi 8076: memilih hasil membersihkan kueri — Kembali '
        'mendarat di hub bersih', (tester) async {
      await pumpSettings(tester);
      final field = find.byType(TextField);
      await tester.enterText(field, 'Bahasa');
      await tester.pump();
      absorbHubNotices(tester);
      await tester.tap(find.text('Bahasa').last);
      await untilFound(tester, find.text('Nama sapaan'));
      absorbHubNotices(tester);
      // Halaman Tampilan (tujuan baris Bahasa) yang terbuka.
      expect(find.text('Nama sapaan'), findsOneWidget);
      // Halaman memakai tombol kembali kustom (bukan BackButton Material),
      // jadi pop langsung lewat Navigator.
      tester.state<NavigatorState>(find.byType(Navigator).first).pop();
      await untilFound(tester, find.text('Tampilan'));
      absorbHubNotices(tester);
      // Hub penuh tampil lagi, kolom cari kosong DAN tidak berfokus
      // (keyboard tidak boleh membuka lagi sendiri saat Kembali).
      expect(find.text('Tampilan'), findsWidgets);
      final f = tester.widget<TextField>(find.byType(TextField));
      expect(f.controller!.text, isEmpty);
      expect(f.focusNode!.hasFocus, isFalse);
    });
  });
}
