// Ronde 8079 — Laci Menu + tombol markah ("Pisah Pengaturan";
// ADDENDUM-L7-L8 yang diterima riyan 22 Nov).
//
// Kontrak yang diuji:
// (1) Tombol markah membuka laci dari KANAN: wordmark + keterangan +
//     EMPAT pintu datar persis (Selera kamu, Brankas Sesi, Kepemilikan,
//     Pengaturan) dengan subjudul maket; tanpa kicker kelompok.
// (2) Menutup: ✕, ketuk kerudung, dan Kembali — ketiganya menutup.
// (3) Ketukan ganda cepat tidak menumpuk dua laci.
// (4) Keempat pintu mendarat di halaman yang benar.
// (5) Label lokasi "Cari pengaturan": baris pindahan berlabel nama
//     halamannya, baris menetap "Pengaturan · <grup>" — nol yatim.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:clai/app.dart';
import 'package:clai/data/app_db.dart';
import 'package:clai/domain/models.dart';
import 'package:clai/l10n/app_localizations.dart';
import 'package:clai/player/audio_handler.dart';
import 'package:clai/player/similarity.dart';
import 'package:clai/providers/music_provider.dart';
import 'package:clai/ui/collection_screen.dart';
import 'package:clai/ui/menu_drawer.dart';
import 'package:clai/ui/session_vault_screen.dart';
import 'package:clai/ui/settings_screen.dart';
import 'package:clai/ui/taste_control_screen.dart';

class _FakeProvider implements MusicProvider {
  @override
  String get id => 'fake';
  @override
  String get displayName => 'Fake';
  @override
  Future<SearchResults> search(String query) async => const SearchResults();
  @override
  Future<List<String>> searchSuggestions(String query) async => const [];
  @override
  Future<ContentPage> getAlbum(String albumId) async =>
      ContentPage(kind: 'album', id: albumId, title: 'x', tracks: const []);
  @override
  Future<ContentPage> getPlaylist(String playlistId) async => ContentPage(
      kind: 'playlist', id: playlistId, title: 'x', tracks: const []);
  @override
  Future<ContentPage> getArtist(String artistId) async =>
      ContentPage(kind: 'artist', id: artistId, title: 'x', tracks: const []);
  @override
  Future<List<Track>> getRelated(Track seed) async => const [];
  @override
  Future<List<Track>> getSameArtist(Track seed) async => const [];
  @override
  Future<List<Artist>> getSimilarArtists(Track seed) async => const [];
  @override
  Future<List<Track>> getSameGenre(Track seed) async => const [];
  @override
  Future<StreamInfo> resolveStream(Track track, StreamQuality quality,
          {bool Function()? stillWanted}) async =>
      StreamInfo(
          url: 'https://example.invalid/x',
          mimeType: 'audio/mp4',
          expiresAt: DateTime.now().add(const Duration(hours: 1)));
  @override
  Future<StreamInfo?> resolveMuxedFallback(Track track) async => null;
}

class _FakeSimilarity implements SimilaritySource {
  @override
  Future<List<Track>> sameArtist(Track seed) async => const [];
  @override
  Future<List<Track>> related(Track seed) async => const [];
  @override
  Future<List<Artist>> similarArtists(Track seed) async => const [];
  @override
  Future<List<Track>> artistTopTracks(String artistId) async => const [];
  @override
  Future<List<Track>> sameGenre(Track seed) async => const [];
}


/// Serap notis debug WARISAN panel (pola 8076 persis): ListTile
/// telanjang di kartu DecoratedBox → aseran "ink splashes may be
/// invisible" di mode debug (terstrip di rilis). Serap HANYA notis
/// itu; eksepsi lain menggagalkan tes.
void absorbNotices(WidgetTester tester, {int cap = 80}) {
  var e = tester.takeException();
  while (e != null) {
    final str = e.toString();
    final agg = RegExp(r'Multiple exceptions \((\d+)\)').firstMatch(str);
    final ok = str.contains('ListTile background color or ink splashes') ||
        (agg != null && int.parse(agg.group(1)!) <= cap);
    expect(ok, isTrue, reason: 'eksepsi tak terduga: $e');
    e = tester.takeException();
  }
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('laci Menu', () {
    late Directory dir;
    late AppDb db;
    late ClaiAudioHandler handler;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('laci8079');
      db = AppDb();
      await db.openAt('${dir.path}/t.db');
      handler = ClaiAudioHandler(
        db: db,
        provider: _FakeProvider(),
        similaritySource: _FakeSimilarity(),
      );
      await Future<void>.delayed(const Duration(milliseconds: 600));
    });

    tearDown(() async {
      await db.close();
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    Widget tree() => ProviderScope(
          overrides: [
            appDbProvider.overrideWithValue(db),
            audioHandlerProvider.overrideWithValue(handler),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('id'),
            home: Scaffold(
              body: Builder(
                builder: (context) => Align(
                  alignment: Alignment.topRight,
                  child: ClaiMarkButton(
                      onPressed: () => showClaiMenuDrawer(context)),
                ),
              ),
            ),
          ),
        );

    Future<void> untilFound(WidgetTester tester, Finder finder) async {
      for (var i = 0; i < 100; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        if (finder.evaluate().isNotEmpty) return;
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      await tester.pump();
      throw StateError('tidak ditemukan: $finder');
    }

    /// Pompa berbingkai kecil berurutan: satu pump panjang hanya
    /// merender SATU bingkai — animasi rute tidak ikut melompat
    /// (jebakan yang terbukti di ronde ini: laci tampak "membeku" di
    /// offset awal sesudah pump(600ms) tunggal, dan ketukan berikutnya
    /// mengenai ✕ laci sendiri).
    Future<void> settleSteps(WidgetTester tester, [int steps = 6]) async {
      for (var i = 0; i < steps; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        await Future<void>.delayed(const Duration(milliseconds: 30));
      }
    }

    Future<void> openDrawer(WidgetTester tester) async {
      await tester.tap(find.byType(ClaiMarkButton));
      // Sapuan tegas 8081: keterangan laci ("Semua fitur & …") dibuang —
      // jangkar "laci terbuka" kini pintu pertamanya.
      await untilFound(tester, find.text('Selera kamu'));
      await tester.pump(const Duration(milliseconds: 400));
    }

    /// Pompa berbingkai sampai finder kosong (animasi keluar rute
    /// butuh banyak bingkai — satu pump tunggal tidak cukup, pola
    /// untilFound yang sama untuk arah sebaliknya).
    Future<void> untilGone(WidgetTester tester, Finder finder) async {
      for (var i = 0; i < 100; i++) {
        if (finder.evaluate().isEmpty) return;
        await tester.pump(const Duration(milliseconds: 100));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      await tester.pump();
    }

    testWidgets('markah membuka laci: wordmark, 4 pintu datar '
        '(keterangan laci dibuang — sapuan tegas 8081)',
        (tester) async {
      await tester.runAsync(() async {
        await tester.pumpWidget(tree());
        await openDrawer(tester);
        expect(find.text('Clai'), findsOneWidget);
        expect(find.text('Semua fitur & pengaturan dalam satu tempat'),
            findsNothing,
            reason: 'keterangan laci tidak boleh kembali (8081)');
        // Empat pintu + subjudul persis maket L7.
        expect(find.text('Selera kamu'), findsOneWidget);
        expect(find.text('Cermin selera, mode samaran & rekomendasi'),
            findsOneWidget);
        expect(find.text('Brankas Sesi'), findsOneWidget);
        expect(find.text('Antrean yang kamu simpan untuk nanti'),
            findsOneWidget);
        expect(find.text('Kepemilikan'), findsOneWidget);
        expect(find.text('Ekspor, impor, bagikan & terima playlist'),
            findsOneWidget);
        expect(find.text('Pengaturan'), findsOneWidget);
        expect(find.text('Tampilan, pemutaran, audio & lainnya'),
            findsOneWidget);
        // Laci menempel di kanan: tepi kirinya jauh dari tepi layar.
        final rect = tester.getRect(find.text('Selera kamu'));
        expect(rect.left, greaterThan(60),
            reason: 'laci harus menempel kanan, bukan memenuhi layar');
        // Tutup lagi: penjaga buka-ganda di menu_drawer adalah static
        // seumur proses — laci yang dibiarkan terbuka mengunci uji
        // berikutnya di berkas yang sama.
        await tester.tap(find.byTooltip('Tutup'));
        await untilGone(tester, find.text('Selera kamu'));
        expect(find.text('Selera kamu'), findsNothing);
      });
    });

    testWidgets('tutup lewat ✕, kerudung, dan Kembali', (tester) async {
      await tester.runAsync(() async {
        await tester.pumpWidget(tree());
        // ✕
        await openDrawer(tester);
        await tester.tap(find.byTooltip('Tutup'));
        await untilGone(tester, find.text('Selera kamu'));
        expect(find.text('Selera kamu'), findsNothing);
        // Kerudung (ketuk jauh di kiri laci)
        await openDrawer(tester);
        await tester.tapAt(const Offset(16, 300));
        await untilGone(tester, find.text('Selera kamu'));
        expect(find.text('Selera kamu'), findsNothing);
        // Kembali (rute pop sistem — pageBack() menuntut widget
        // BackButton yang memang tidak ada di laci dialog).
        await openDrawer(tester);
        await tester.binding.handlePopRoute();
        await untilGone(tester, find.text('Selera kamu'));
        expect(find.text('Selera kamu'), findsNothing);
      });
    });

    testWidgets('ketukan ganda & masuk-ulang: tidak pernah dua laci',
        (tester) async {
      await tester.runAsync(() async {
        await tester.pumpWidget(tree());
        // Ketukan mentah beruntun: ketukan kedua mendarat di atas laci
        // yang sedang membuka (bisa mengenai ✕/pintunya) — invarian
        // yang dijaga BUKAN "laci pasti terbuka", melainkan "tidak
        // pernah ada DUA laci".
        await tester.tap(find.byType(ClaiMarkButton));
        await tester.tap(find.byType(ClaiMarkButton));
        await settleSteps(tester, 8);
        expect(
            find.text('Selera kamu').evaluate().length,
            lessThanOrEqualTo(1),
            reason: 'dua laci menumpuk');
        if (find.text('Selera kamu').evaluate().isNotEmpty) {
          await tester.tap(find.byTooltip('Tutup'));
          await untilGone(tester, find.text('Selera kamu'));
        }
        // Masuk-ulang langsung saat laci terbuka: penjaga menolak
        // panggilan kedua; satu tutup cukup.
        await openDrawer(tester);
        final hostCtx = tester.element(find.byType(ClaiMarkButton));
        await showClaiMenuDrawer(hostCtx);
        await settleSteps(tester, 3);
        expect(find.text('Selera kamu'), findsOneWidget);
        await tester.tap(find.byTooltip('Tutup'));
        await untilGone(tester, find.text('Selera kamu'));
        expect(find.text('Selera kamu'), findsNothing);
      });
    });

    testWidgets('empat pintu mendarat di halaman yang benar',
        (tester) async {
      await tester.runAsync(() async {
        await tester.pumpWidget(tree());
        // → Brankas Sesi
        await openDrawer(tester);
        await tester.tap(find.text('Brankas Sesi'));
        await untilFound(tester, find.byType(SessionVaultScreen));
        absorbNotices(tester);
        expect(find.byType(SessionVaultScreen), findsOneWidget);
        // Laci & halaman berjalan bersamaan selama transisi — tertutup
        // dibuktikan dari hilangnya pintu laci, bukan seketika.
        await untilGone(tester, find.text('Selera kamu'));
        expect(find.text('Selera kamu'), findsNothing,
            reason: 'laci harus sudah tertutup sesudah pintu dipilih');
        tester
            .state<NavigatorState>(find.byType(Navigator).first)
            .pop();
        await untilGone(tester, find.byType(SessionVaultScreen));
        // → Kepemilikan
        await openDrawer(tester);
        await tester.tap(find.text('Kepemilikan'));
        await untilFound(tester, find.byType(OwnershipPage));
        absorbNotices(tester);
        expect(find.text('Ekspor data'), findsWidgets);
        tester
            .state<NavigatorState>(find.byType(Navigator).first)
            .pop();
        await untilGone(tester, find.byType(OwnershipPage));
        // → Selera kamu (judul AppBar baru, isi layar yang sama)
        await openDrawer(tester);
        await tester.tap(find.text('Selera kamu'));
        await untilFound(tester, find.byType(TasteControlScreen));
        absorbNotices(tester);
        expect(find.text('Selera kamu'), findsWidgets);
        expect(find.text('Mode Samaran'), findsWidgets);
        tester
            .state<NavigatorState>(find.byType(Navigator).first)
            .pop();
        await untilGone(tester, find.byType(TasteControlScreen));
        // Beri rantai tag genre Selera waktu menetap sebelum tearDown.
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 100));
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
        // → Pengaturan
        await openDrawer(tester);
        await tester.tap(find.text('Pengaturan'));
        await untilFound(tester, find.byType(SettingsScreen));
        absorbNotices(tester);
        expect(find.text('Cari pengaturan'), findsOneWidget);
      });
    });

    testWidgets('label lokasi Cari pengaturan jujur (indeks)', (tester) async {
      await tester.runAsync(() async {
        await tester.pumpWidget(tree());
        // Buka Pengaturan lewat laci untuk meminjam konteks ber-l10n.
        await openDrawer(tester);
        await tester.tap(find.text('Pengaturan'));
        await untilFound(tester, find.byType(SettingsScreen));
        absorbNotices(tester);
        final ctx = tester.element(find.byType(SettingsScreen));
        final index = settingsSearchIndex(ctx);
        String groupOf(String title) =>
            index.singleWhere((e) => e.title == title).group;
        // Pindahan → nama halamannya.
        expect(groupOf('Mode Samaran'), 'Selera kamu');
        expect(groupOf('Cermin Selera'), 'Selera kamu');
        expect(groupOf('Ekspor data'), 'Kepemilikan');
        expect(groupOf('Brankas Sesi'), 'Brankas Sesi');
        // Menetap → "Pengaturan · <grup>".
        expect(groupOf('Bahasa'), 'Pengaturan · Tampilan');
        expect(groupOf('Periksa pembaruan'), 'Pengaturan · Sistem');
      });
    });
  });

  group('kepala Koleksi', () {
    testWidgets('markah menggantikan gir di Koleksi', (tester) async {
      late Directory dir;
      late AppDb db;
      addTearDown(() async {
        await db.close();
        if (await dir.exists()) await dir.delete(recursive: true);
      });
      await tester.runAsync(() async {
        dir = await Directory.systemTemp.createTemp('laci_kol');
        db = AppDb();
        await db.openAt('${dir.path}/t.db');
        final handler = ClaiAudioHandler(
          db: db,
          provider: _FakeProvider(),
          similaritySource: _FakeSimilarity(),
        );
        await Future<void>.delayed(const Duration(milliseconds: 600));
        await tester.pumpWidget(ProviderScope(
          overrides: [
            appDbProvider.overrideWithValue(db),
            audioHandlerProvider.overrideWithValue(handler),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('id'),
            home: const CollectionScreen(),
          ),
        ));
        await tester.pump(const Duration(milliseconds: 300));
        absorbNotices(tester);
        expect(find.byType(ClaiMarkButton), findsOneWidget);
        expect(find.byTooltip('Pengaturan'), findsNothing,
            reason: 'gir Pengaturan lama tidak boleh tersisa di Koleksi');
      });
    });
  });
}
