// Ronde 8084 — Koleksi: numeral rata kiri + FAB melayang.
//
// Kontrak yang diuji:
// (a) Numeral editorial rata kiri: dx teks numeral == dx judul
//     "Koleksi" (20) — Column akar kini CrossAxisAlignment.start,
//     bukan bawaan tengah yang menggeser blok numeral ke tengah.
// (b) FAB MELAYANG: FloatingActionButton berada di dalam Stack
//     (dibungkus Positioned) dan wilayahnya TUMPANG TINDIH wilayah
//     daftar gulir — ia melayang DI ATAS daftar, bukan anak aliran
//     Column yang mendorong daftar dan menyisakan pita di bawahnya.
// (c) Daftar bisa digulir sampai baris playlist TERAKHIR terlihat
//     UTUH di atas FAB: sesudah gulir maksimal, batas bawah baris
//     terakhir (CollectionRow 72, termasuk meta "N lagu • durasi")
//     ≤ batas atas FAB. Clearance kini di DALAM konten gulir:
//     bottomChromeClearance + 16 + 56 (FAB) + 16.
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
import 'package:clai/services/library_controller.dart';
import 'package:clai/ui/collection_screen.dart';

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

Track _track(String id) => Track(
      key: TrackKey('ytmusic', id),
      title: 'Lagu $id',
      artistNames: 'Artis $id',
      duration: const Duration(minutes: 3),
      playableRef: id,
    );

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Koleksi 8084 — numeral kiri & FAB melayang', () {
    late Directory dir;
    late AppDb db;
    late ClaiAudioHandler handler;
    late LibraryController lib;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('kol8084');
      db = AppDb();
      await db.openAt('${dir.path}/t.db');
      handler = ClaiAudioHandler(
        db: db,
        provider: _FakeProvider(),
        similaritySource: _FakeSimilarity(),
      );
      await Future<void>.delayed(const Duration(milliseconds: 600));
      // 12 playlist × 1 trek berdurasi → numeral lagu = 12; baris
      // playlist terakhir dalam daftar (urutan simpan terbaru dulu)
      // adalah "Daftar 01" (dibuat pertama).
      for (var i = 1; i <= 12; i++) {
        final n = i.toString().padLeft(2, '0');
        await db.createPlaylist('pl$n', 'Daftar $n');
        await db.addToPlaylist('pl$n', _track('t$n'));
      }
      // Di aplikasi asli load() dipanggil cangkang (app.dart); di sini
      // controller dimuat lebih dulu lalu disuntikkan lewat override.
      lib = LibraryController(db);
      await lib.load();
    });

    tearDown(() async {
      await db.close();
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    Widget tree() => ProviderScope(
          overrides: [
            appDbProvider.overrideWithValue(db),
            audioHandlerProvider.overrideWithValue(handler),
            libraryProvider.overrideWith((_) => lib),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('id'),
            home: const Scaffold(body: CollectionScreen()),
          ),
        );

    Future<void> pumpUntil(WidgetTester tester, Finder finder) async {
      for (var i = 0; i < 100; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        if (finder.evaluate().isNotEmpty) return;
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      await tester.pump();
      throw StateError('tidak ditemukan: $finder');
    }

    /// Numeral editorial header: teks angka lagu dengan gaya hero 40.
    /// (find.text('12') polos SALAH di sini: angka hitungan pintu
    /// Playlist di kanan juga berbunyi '12' dan muncul lebih dulu.)
    Finder numeralFinder() => find.byWidgetPredicate(
          (w) => w is Text && w.data == '12' && w.style?.fontSize == 40,
        );

    /// Beri pekerjaan async layar (aksen sampul panggung dkk) waktu
    /// selesai SEBELUM tearDown menutup DB — pola harness 8079.
    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        await Future<void>.delayed(const Duration(milliseconds: 30));
      }
    }

    testWidgets('(a) numeral rata kiri sejajar judul "Koleksi"',
        (tester) async {
      await tester.runAsync(() async {
        await tester.pumpWidget(tree());
        // Numeral muncul sesudah agregat meta selesai (angka lagu = 12).
        await pumpUntil(tester, numeralFinder());
        final titleRect = tester.getRect(find.text('Koleksi'));
        final numeralRect = tester.getRect(numeralFinder());
        expect(numeralRect.left, titleRect.left,
            reason: 'numeral harus sejajar margin kiri judul (20), '
                'bukan ke tengah halaman');
        expect(numeralRect.left, 20);
        await settle(tester);
      });
    });

    testWidgets('(b) FAB melayang di dalam Stack, tumpang tindih daftar',
        (tester) async {
      await tester.runAsync(() async {
        await tester.pumpWidget(tree());
        await pumpUntil(tester, find.byType(FloatingActionButton));
        // FAB punya leluhur Stack dan Positioned (melayang), dan
        // sumber berkas menegaskan bukan anak Padding aliran Column.
        expect(
          find.ancestor(
              of: find.byType(FloatingActionButton),
              matching: find.byType(Stack)),
          findsWidgets,
        );
        expect(
          find.ancestor(
              of: find.byType(FloatingActionButton),
              matching: find.byType(Positioned)),
          findsOneWidget,
        );
        final src = File('lib/ui/collection_screen.dart').readAsStringSync();
        expect(src.contains('crossAxisAlignment: CrossAxisAlignment.start'),
            isTrue);
        // Wilayah FAB tumpang tindih wilayah daftar gulir: batas atas
        // FAB di atas batas bawah daftar, batas bawah FAB juga di atas
        // batas bawah daftar (FAB tidak mendorong daftar dari bawah).
        await pumpUntil(tester, find.byType(CollectionRow));
        final listRect = tester.getRect(
          find
              .ancestor(
                  of: find.byType(CollectionRow).first,
                  matching: find.byType(Scrollable))
              .first,
        );
        final fabRect = tester.getRect(find.byType(FloatingActionButton));
        expect(fabRect.top, lessThan(listRect.bottom),
            reason: 'FAB harus melayang DI ATAS wilayah daftar');
        expect(fabRect.bottom, lessThan(listRect.bottom),
            reason: 'FAB tidak boleh berada di bawah daftar (pita FAB)');
        expect(fabRect.right, lessThanOrEqualTo(listRect.right));
        await settle(tester);
      });
    });

    testWidgets('(c) gulir maksimal: baris terakhir utuh di atas FAB',
        (tester) async {
      await tester.runAsync(() async {
        await tester.pumpWidget(tree());
        await pumpUntil(tester, numeralFinder());
        final scrollable = find
            .ancestor(
                of: find.byType(CollectionRow).first,
                matching: find.byType(Scrollable))
            .first;
        final position =
            tester.state<ScrollableState>(scrollable).position;
        position.jumpTo(position.maxScrollExtent);
        await tester.pump(const Duration(milliseconds: 300));
        // Baris terakhir daftar (urutan simpan DB tidak ditebak: ambil
        // CollectionRow terakhir yang terpasang) — meta-nya harus
        // "1 lagu • 3 mnt" dari agregat durasi nyata.
        final lastRow = find.byType(CollectionRow).last;
        expect(lastRow, findsOneWidget);
        final rowWidget = tester.widget<CollectionRow>(lastRow);
        expect(rowWidget.meta, '1 lagu • 3 mnt');
        final rowRect = tester.getRect(lastRow);
        final fabRect = tester.getRect(find.byType(FloatingActionButton));
        expect(rowRect.height, 72,
            reason: 'baris CollectionRow utuh 72 termasuk meta');
        expect(rowRect.bottom, lessThanOrEqualTo(fabRect.top),
            reason: 'batas bawah baris terakhir harus ≤ batas atas FAB '
                'sesudah gulir maksimal (clearance di dalam guliran)');
        await settle(tester);
      });
    });
  });
}
