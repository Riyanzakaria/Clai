// Ronde 8086 — Lembar Antrean Suara gaya sekarang.
//
// Kontrak yang diuji:
// (a) Keadaan idle: judul tampil, teks contoh PERSIS string padat baru,
//     cakram mikrofon = Container lingkaran warna signal 88×88, dan
//     teks petunjuk idle tampil.
// (b) Transkrip tampil italic fontSize 15.
// (c) Keadaan awaitingChoice: dua baris kandidat datar dengan nomor
//     '1'/'2' bergaya font display (Clash), TANPA kotak nomor tonal
//     48×48 surface2 radius 12 warisan. Kandidat TIDAK diketuk di tes
//     widget (handler `late` — jalur ketuk dibuktikan di emulator).
// (d) Sumber: voice_sheet.dart tidak mengandung 'EntityRow' dan tidak
//     mengandung 'width: 96' (lingkaran 96 lama pensiun).
import 'dart:io';

import 'package:clai/app.dart';
import 'package:clai/core/tokens.dart';
import 'package:clai/data/app_db.dart';
import 'package:clai/domain/models.dart';
import 'package:clai/l10n/app_localizations.dart';
import 'package:clai/providers/music_provider.dart';
import 'package:clai/services/voice_service.dart';
import 'package:clai/ui/voice_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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

/// notifyListeners bersifat @protected di ChangeNotifier — subclass uji
/// ini mengeksposnya secara sah agar tes bisa memicu rebuild lembar
/// sesudah memutasi field layanan secara langsung.
class _TestVoiceService extends VoiceService {
  _TestVoiceService(super.db, super.provider);
  void poke() => notifyListeners();
}

Track _t(String id, String title, String artist) => Track(
      key: TrackKey('ytm', id),
      title: title,
      artistNames: artist,
      playableRef: id,
    );

void main() {
  late _TestVoiceService svc;

  Widget tree() => ProviderScope(
        overrides: [voiceServiceProvider.overrideWith((ref) => svc)],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('id'),
          home: const Scaffold(body: VoiceSheet()),
        ),
      );

  setUp(() {
    svc = _TestVoiceService(AppDb(), _FakeProvider());
  });

  group('widget — lembar suara 8086', () {
    testWidgets('(a) idle: judul, contoh persis, cakram signal 88, petunjuk',
        (tester) async {
      await tester.pumpWidget(tree());
      await tester.pumpAndSettle();

      expect(find.text('Antrean Suara'), findsOneWidget);

      const contoh = 'Coba: "putar [judul]", "lewati", "jeda", "lanjut".';
      expect(find.text(contoh), findsOneWidget);
      final contohStyle = tester.widget<Text>(find.text(contoh)).style;
      expect(contohStyle?.fontSize, 13);
      expect(contohStyle?.color, ClaiColors.inkSecondary);

      final cakram = find.byWidgetPredicate((w) {
        if (w is! Container) return false;
        final d = w.decoration;
        return d is BoxDecoration &&
            d.shape == BoxShape.circle &&
            d.color == ClaiColors.signal;
      });
      expect(cakram, findsOneWidget);
      expect(tester.getSize(cakram), const Size(88, 88));

      expect(find.text('Ketuk mikrofon, atau ketik perintah di bawah.'),
          findsOneWidget);
    });

    testWidgets('(b) transkrip tampil italic 15', (tester) async {
      await tester.pumpWidget(tree());
      await tester.pumpAndSettle();

      svc.lastTranscript = 'putar sway';
      svc.poke();
      await tester.pumpAndSettle();

      final transkrip = find.text('“putar sway”');
      expect(transkrip, findsOneWidget);
      final style = tester.widget<Text>(transkrip).style;
      expect(style?.fontSize, 15);
      expect(style?.fontStyle, FontStyle.italic);
    });

    testWidgets('(c) kandidat: nomor Clash datar, tanpa kotak tonal 48',
        (tester) async {
      await tester.pumpWidget(tree());
      await tester.pumpAndSettle();

      svc.state = VoiceState.awaitingChoice;
      svc.candidates = [
        _t('1', 'Sway', 'COLORCODE'),
        _t('2', 'Sway', 'Artis Lain'),
      ];
      svc.poke();
      await tester.pumpAndSettle();

      expect(find.text('Sway'), findsNWidgets(2));
      for (final nomor in ['1', '2']) {
        final f = find.text(nomor);
        expect(f, findsOneWidget);
        final style = tester.widget<Text>(f).style;
        expect(style?.fontFamily, kDisplayFontFamily);
        expect(style?.color, ClaiColors.signal);
      }

      // Kotak nomor tonal warisan (Container surface2 radius 12) pensiun.
      final kotak = find.byWidgetPredicate((w) {
        if (w is! Container) return false;
        final d = w.decoration;
        return d is BoxDecoration &&
            d.color == ClaiColors.surface2 &&
            d.borderRadius == BorderRadius.circular(12);
      });
      expect(kotak, findsNothing);
    });
  });

  group('sumber — voice_sheet.dart', () {
    final src = File('lib/ui/voice_sheet.dart').readAsStringSync();

    test('(d) tidak memakai EntityRow; lingkaran 96 lama hilang', () {
      expect(src.contains('EntityRow'), isFalse);
      expect(src.contains('width: 96'), isFalse);
    });
  });
}
