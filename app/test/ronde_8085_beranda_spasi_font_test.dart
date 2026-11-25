// Ronde 8085 — Keseragaman Beranda (butir SPASI + FONT).
//
// Kontrak yang diuji:
// (a) Padding bawaan SectionHeader == fromLTRB(16, 24, 16, 12) — standar
//     keseragaman judul seksi ronde ini (atas 24 / bawah 12, kisi 4dp,
//     rasio 2:1 mengikuti DS §4), hidup di SATU tempat (nilai bawaan
//     komponen). Menggantikan bawaan lama (16, 18, 16, 6) dan seluruh
//     padding eksplisit Beranda (16, 26, 16, 10) / (16, 26, 16, 6) /
//     (16, 18, 16, 10) yang kini dilepas pemanggilnya.
// (b) Judul rak Jelajah ter-render lewat SectionHeader dengan
//     fontFamily Clash Display (displayStyle) — bukan lagi Text
//     bertulis tangan Inter 17/600.
// (c) Source-lock: tidak ada lagi padding eksplisit lama di situs-situs
//     Beranda yang dinormalkan ronde ini, dan konversi SectionHeader
//     untuk Brankas Sesi + dua judul tangan warisan tetap terpasang.
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
import 'package:clai/providers/ytmusic/ytmusic_provider.dart';
import 'package:clai/ui/glass.dart';
import 'package:clai/ui/jelajah_section.dart';

String _src(String path) => File(path).readAsStringSync();

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
    kind: 'playlist',
    id: playlistId,
    title: 'x',
    tracks: const [],
  );
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
  Future<StreamInfo> resolveStream(
    Track track,
    StreamQuality quality, {
    bool Function()? stillWanted,
  }) async => StreamInfo(
    url: 'https://example.invalid/x',
    mimeType: 'audio/mp4',
    expiresAt: DateTime.now().add(const Duration(hours: 1)),
  );
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

/// Umpan Jelajah palsu: satu rak "Trending" berisi satu trek; umpan
/// Tangga Lagu kosong. Tanpa jaringan sama sekali.
class _FakeYtMusic extends YtMusicProvider {
  _FakeYtMusic(super.db);

  @override
  Future<List<ExploreShelf>> getHomeFeed() async => [
    ExploreShelf(
      title: 'Trending',
      tracks: [
        Track(
          key: TrackKey('ytmusic', 't1'),
          title: 'Lagu Tren',
          artistNames: 'Artis Tren',
          duration: const Duration(minutes: 3),
          playableRef: 't1',
        ),
      ],
    ),
  ];

  @override
  Future<List<ExploreShelf>> getChartsFeed() async => const [];
}

void main() {
  group('Ronde 8085 — standar padding SectionHeader', () {
    test('nilai bawaan == fromLTRB(16, 24, 16, 12)', () {
      const header = SectionHeader('Judul');
      expect(
        header.padding,
        const EdgeInsets.fromLTRB(16, 24, 16, 12),
        reason:
            'standar keseragaman Ronde 8085: atas 24 / bawah 12 '
            '(kisi 4dp, rasio 2:1 DS §4) sebagai nilai bawaan tunggal',
      );
    });

    testWidgets('SectionHeader ter-render memakai padding bawaan itu', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: SectionHeader('Judul Seksi'))),
      );
      await tester.pump();
      final padding = tester.widget<Padding>(
        find.descendant(
          of: find.byType(SectionHeader),
          matching: find.byType(Padding),
        ),
      );
      expect(padding.padding, const EdgeInsets.fromLTRB(16, 24, 16, 12));
      final text = tester.widget<Text>(find.text('Judul Seksi'));
      expect(text.style?.fontFamily, kDisplayFontFamily);
      expect(text.style?.fontSize, 17);
    });
  });

  group('Ronde 8085 — judul rak Jelajah Clash (widget, provider palsu)', () {
    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });

    late Directory dir;
    late AppDb db;
    late ClaiAudioHandler handler;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('jelajah8085');
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

    testWidgets('judul rak ter-render sebagai SectionHeader Clash Display', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDbProvider.overrideWithValue(db),
            audioHandlerProvider.overrideWithValue(handler),
            ytMusicProvider.overrideWithValue(_FakeYtMusic(db)),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('id'),
            home: const Scaffold(
              body: SingleChildScrollView(child: JelajahSection()),
            ),
          ),
        ),
      );
      // Umpan palsu selesai async — pompa (jam palsu testWidgets) sampai
      // judul rak muncul. TANPA Future.delayed: menunggu timer asli di
      // zona fake-async = deadlock.
      Finder shelfTitle = find.text('Sedang Tren');
      for (var i = 0; i < 100 && shelfTitle.evaluate().isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(shelfTitle, findsOneWidget, reason: 'judul rak Jelajah tampil');
      // Judul rak kini anak SectionHeader (bukan Text bertulis tangan).
      expect(
        find.ancestor(of: shelfTitle, matching: find.byType(SectionHeader)),
        findsOneWidget,
      );
      final text = tester.widget<Text>(shelfTitle);
      expect(
        text.style?.fontFamily,
        kDisplayFontFamily,
        reason: 'judul rak Jelajah harus Clash Display (displayStyle)',
      );
      expect(text.style?.fontSize, 17);
      // Isi rak tidak berubah: trek rak tetap ter-render.
      expect(find.text('Lagu Tren'), findsOneWidget);
    });
  });

  group('Ronde 8085 — source-lock situs Beranda yang dinormalkan', () {
    test('padding eksplisit lama hilang dari situs Beranda', () {
      for (final path in [
        'lib/ui/home_screen.dart',
        'lib/ui/personal_shelves_section.dart',
      ]) {
        final src = _src(path);
        expect(src.contains('fromLTRB(16, 26, 16, 10)'), isFalse, reason: path);
        expect(src.contains('fromLTRB(16, 26, 16, 6)'), isFalse, reason: path);
      }
      expect(
        _src('lib/ui/widgets.dart').contains('fromLTRB(16, 18, 16, 10)'),
        isFalse,
        reason: 'CoverRail melepas padding eksplisit → bawaan SectionHeader',
      );
      expect(
        _src('lib/ui/glass.dart').contains('fromLTRB(16, 18, 16, 6)'),
        isFalse,
        reason: 'bawaan lama SectionHeader pensiun di Ronde 8085',
      );
    });

    test('konversi SectionHeader terpasang di rak Jelajah, Brankas Sesi, '
        'dan judul tangan warisan', () {
      expect(
        _src(
          'lib/ui/jelajah_section.dart',
        ).contains('SectionHeader(exploreTitleId(shelf.title))'),
        isTrue,
      );
      final vault = _src('lib/ui/session_vault_screen.dart');
      expect(vault.contains('SectionHeader('), isTrue);
      expect(vault.contains('s.vaultTitle'), isTrue);
      // Dua judul modern yang sudah bawaan tetap tanpa padding eksplisit,
      // dan dua judul warisan kini SectionHeader juga (home_screen total
      // memuat homeYourCollection/homeUpNext sebagai SectionHeader).
      final home = _src('lib/ui/home_screen.dart');
      expect(
        'SectionHeader(context.l10n.homeYourCollection)'
            .allMatches(home)
            .length,
        2,
        reason: 'modern (738) + warisan hasil konversi 8085',
      );
      expect(
        RegExp(
          r'SectionHeader\(\s*context\.l10n\.homeUpNext,\s*trailing:',
        ).hasMatch(home),
        isTrue,
        reason: 'warisan Antrian Berikutnya = SectionHeader + trailing',
      );
    });

    test('judul besar Jelajah dinormalkan, font displayStyle(24) utuh', () {
      final src = _src('lib/ui/jelajah_section.dart');
      expect(src.contains('fromLTRB(16, 24, 16, 12)'), isTrue);
      expect(src.contains('displayStyle(24)'), isTrue);
    });
  });
}
