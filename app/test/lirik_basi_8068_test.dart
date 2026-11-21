// Ronde 8068 — BUG LIRIK BASI + BARIS PANJANG KEPOTONG (vonis perangkat
// pemilik 2026-11-20 12:06–12:09 atas staging 8067):
//
// (1) BASI TOTAL: lembar Lirik dibuka pada trek A dan dibiarkan terbuka;
//     trek berganti (selesai alami MAUPUN lompat manual Next) — lirik
//     yang tampil TETAP milik A. Tutup-buka lembar baru benar. Kontrak:
//     lembar yang terbuka WAJIB mengikuti trek berjalan lewat jahitan
//     yang sama persis dengan yang dipakai semua jalur pergantian di
//     handler (engine.current berpindah lalu mediaItem diterbitkan —
//     lihat _onIndexChanged, _xfAdvanceAfterEnd, _xfSkipNext).
//
// (2) BARIS PANJANG KEPOTONG (per BARIS, klarifikasi pemilik 12:09):
//     satu baris lirik yang panjang terpotong ekornya. Tersangka
//     tampilan: baris tak-aktif di _syncedView dibatasi maxLines 2 +
//     elipsis. Kontrak: teks baris tampil UTUH (membungkus), berapa pun
//     panjangnya.
//
// (3) KONTROL SUMBER: parseLrc atas LRC panjang (120 baris) utuh sampai
//     baris terakhir — pemotongan BUKAN di sumber/urai.
import 'dart:io';

import 'package:audio_service/audio_service.dart';
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
import 'package:clai/services/ambient_theme.dart';
import 'package:clai/services/lyrics_service.dart';
import 'package:clai/ui/lyrics_sheet.dart';

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
  Future<ContentPage> getPlaylist(String playlistId) async =>
      ContentPage(kind: 'playlist', id: playlistId, title: 'x', tracks: const []);
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

class _FakeLyrics extends LyricsService {
  _FakeLyrics(super.db, this.byId);
  final Map<String, LyricsData> byId;
  @override
  Future<LyricsData?> getLyrics(Track t, {bool forceRefresh = false}) async =>
      byId[t.key.id];
}

Track _mk(String id, String title) => Track(
      key: TrackKey('ytmusic', id),
      title: title,
      artistNames: 'Artis $id',
      playableRef: id,
      duration: const Duration(minutes: 3),
    );

LyricsData _synced(String tag) => LyricsData(
      source: 'test',
      lines: [
        // Stempel pertama 0 dtk = bentuk nyata: pada posisi 0 indeks
        // aktif menjadi 0 di bingkai render pertama — persis bingkai
        // yang dulu gugur oleh setState-saat-bangun di _onPosition.
        LyricsLine(Duration.zero, '$tag-LINE-ONE'),
        const LyricsLine(Duration(seconds: 5), 'pengisi tengah'),
        const LyricsLine(Duration(seconds: 10), 'pengisi akhir'),
      ],
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('kontrol sumber — parseLrc lirik panjang', () {
    test('120 baris utuh sampai baris terakhir', () {
      final buf = StringBuffer();
      for (var i = 0; i < 120; i++) {
        final mm = (i * 2) ~/ 60;
        final ss = (i * 2) % 60;
        buf.writeln(
            '[${mm.toString().padLeft(2, '0')}:${ss.toString().padLeft(2, '0')}.00]baris ke-$i');
      }
      final lines = parseLrc(buf.toString());
      expect(lines, isNotNull);
      expect(lines!.length, 120);
      expect(lines.last.text, 'baris ke-119');
    });
  });

  group('lembar lirik — mengikuti pergantian trek + baris utuh', () {
    late AppDb db;
    late ClaiAudioHandler handler;
    late Directory dir;

    final trackA = _mk('A', 'Lagu A');
    final trackB = _mk('B', 'Lagu B');
    final trackC = _mk('C', 'Lagu C');

    // Baris sangat panjang (±170 karakter): pada lebar HP pemilik
    // (360 dp, teks 304 dp, huruf 20) ia membungkus ≥4 baris visual.
    const longLine =
        'malam ini aku berjalan sendiri menyusuri jalan yang panjang '
        'dan berliku tanpa tahu kapan langkahku akan berhenti sejenak '
        'untuk sekadar menatap langit yang gelap';

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('lirik8068');
      db = AppDb();
      await db.openAt('${dir.path}/t.db');
      handler = ClaiAudioHandler(
        db: db,
        provider: _FakeProvider(),
        similaritySource: _FakeSimilarity(),
      );
      handler.engine.current = trackA;
      // Jahitan start trek asli: SEMUA jalur putar handler menerbitkan
      // mediaItem trek yang mulai (tanpa ini, subjek mediaItem yang
      // berbenih null memutar-ulang null ke lembar — keadaan "belum
      // pernah ada putaran" yang bukan skenario vonis).
      handler.mediaItem.add(MediaItem(
        id: '${trackA.key.providerId}|${trackA.key.id}',
        title: trackA.title,
        artist: trackA.artistNames,
      ));
      // Biarkan rantai _init handler (async, membaca pref/DB lewat
      // kanal platform) menetap SEBELUM badan tes — bila tidak, bacaan
      // DB-nya berlomba dengan tearDown yang menutup DB dan eksepsinya
      // mencemari tes berikutnya (derau harness, bukan cacat aplikasi).
      await Future<void>.delayed(const Duration(milliseconds: 600));
    });

    tearDown(() async {
      await db.close();
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    Widget tree(Map<String, LyricsData> lyrics) => ProviderScope(
          overrides: [
            appDbProvider.overrideWithValue(db),
            audioHandlerProvider.overrideWithValue(handler),
            lyricsServiceProvider
                .overrideWithValue(_FakeLyrics(db, lyrics)),
          ],
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: Locale('en'),
            home: LyricsScreen(),
          ),
        );

    Future<void> pumpSheet(WidgetTester tester,
        Map<String, LyricsData> lyrics) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(tree(lyrics));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }

    // Jahitan pergantian trek persis seperti handler: engine berpindah
    // DULU, lalu mediaItem diterbitkan (semua jalur: _onIndexChanged
    // untuk maju alami & Next manual gapless; takeNextForCrossfade +
    // mediaItem.add untuk crossfade).
    void gantiTrek(Track t) {
      handler.engine.current = t;
      handler.mediaItem.add(MediaItem(
        id: '${t.key.providerId}|${t.key.id}',
        title: t.title,
        artist: t.artistNames,
      ));
    }

    testWidgets('lembar terbuka mengikuti maju alami lalu Next manual',
        (tester) async {
      await pumpSheet(tester, {
        'A': _synced('AAA'),
        'B': _synced('BBB'),
        'C': _synced('CCC'),
      });
      expect(find.text('AAA-LINE-ONE'), findsOneWidget,
          reason: 'lirik awal milik trek A');

      // Selesai alami: A → B.
      gantiTrek(trackB);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('BBB-LINE-ONE'), findsOneWidget,
          reason: 'sesudah trek berganti alami, lirik WAJIB milik B');
      expect(find.text('AAA-LINE-ONE'), findsNothing,
          reason: 'lirik A tidak boleh tertinggal');

      // Lompat manual Next: B → C.
      gantiTrek(trackC);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('CCC-LINE-ONE'), findsOneWidget,
          reason: 'sesudah Next manual, lirik WAJIB milik C');
      expect(find.text('BBB-LINE-ONE'), findsNothing);
    });

    testWidgets('emisi terlewat: rekonsiliasi bangun menyembuhkan lembar',
        (tester) async {
      final lyrics = {
        'A': _synced('AAA'),
        'B': _synced('BBB'),
      };
      await pumpSheet(tester, lyrics);
      expect(find.text('AAA-LINE-ONE'), findsOneWidget);

      // Trek berpindah TANPA emisi mediaItem (jahitan utama terlewat):
      // lembar tidak boleh basi permanen — bangun berikutnya (di sini
      // dipicu perubahan irisan ambien, persis pemicu bangun lembar di
      // perangkat saat trek berganti dan palet sampul menyusul)
      // menjadwalkan penyelarasan pasca-bingkai.
      handler.engine.current = trackB;
      final container = ProviderScope.containerOf(
          tester.element(find.byType(LyricsScreen)));
      final amb = container.read(ambientControllerProvider.notifier);
      // ignore: invalid_use_of_protected_member
      amb.state = amb.state.copyWith(strength: AmbientStrength.tenang);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      expect(find.text('BBB-LINE-ONE'), findsOneWidget,
          reason: 'rekonsiliasi bangun WAJIB memuat lirik trek berjalan');
      expect(find.text('AAA-LINE-ONE'), findsNothing);
    });

    testWidgets('satu baris sangat panjang tampil UTUH (membungkus)',
        (tester) async {
      await pumpSheet(tester, {
        'A': const LyricsData(
          source: 'test',
          lines: [
            LyricsLine(Duration(seconds: 5), 'pembuka pendek'),
            LyricsLine(Duration(seconds: 10), longLine),
            LyricsLine(Duration(seconds: 15), 'penutup pendek'),
          ],
        ),
      });
      final finder = find.text(longLine);
      expect(finder, findsOneWidget);
      final tw = tester.widget<Text>(finder);
      expect(tw.maxLines, isNull,
          reason: 'baris lirik tidak boleh dibatasi maxLines — '
              'teks panjang wajib membungkus sampai utuh');
      expect(tw.overflow, isNot(TextOverflow.ellipsis),
          reason: 'baris lirik tidak boleh dipotong elipsis');
      // Bukti terlukis: tinggi baris > 2 baris visual pada hurufnya.
      final size = tester.getSize(finder);
      final lineHeight = (tw.style?.fontSize ?? 20) * (tw.style?.height ?? 1.3);
      expect(size.height, greaterThan(lineHeight * 2 + 1),
          reason: 'baris panjang harus benar-benar terlukis >2 baris');
    });
  });
}
