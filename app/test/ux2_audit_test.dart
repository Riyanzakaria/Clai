// Regresi perluasan Audit UX (build 2018): lima butir yang diputuskan
// pemilik masuk ronde ini — celah A-3 (seksi filter pencarian kosong),
// U-2 (urut Koleksi rata), U-1 (chevron geser mini player permanen),
// artis bisa diketuk di Player, indikator timer tidur di mini player.
//
// Pola cakupan sama seperti radio_header_a5_test: fungsi keputusan murni +
// widget presentasi sungguhan; layar utuh yang bergantung handler konkret
// tidak dipompa.
import 'package:clai/app.dart';
import 'package:clai/core/clai_icons.dart';
import 'package:clai/l10n/app_localizations.dart';
import 'package:clai/domain/models.dart';
import 'package:clai/services/library_controller.dart';
import 'package:clai/ui/collection_screen.dart';
import 'package:clai/ui/mini_player.dart';
import 'package:clai/ui/search_screen.dart';
import 'package:clai/ui/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Track t(String id, {String artist = 'Artis A', String provider = 'ytmusic'}) =>
    Track(
      key: TrackKey(provider, id),
      title: 'Lagu $id',
      artistNames: artist,
      duration: const Duration(minutes: 3),
      playableRef: id,
    );

Album alb(String id) => Album(
      providerId: 'ytmusic',
      id: id,
      title: 'Album $id',
      artistNames: 'Artis A',
    );

SavedItemInfo saved(String title) =>
    SavedItemInfo('album', 'ytmusic', 'id-$title', title, null, null);

void main() {
  group('A-3 lanjutan: seksi filter pencarian kosong', () {
    test('filter Album kosong padahal lagu ada -> seksi kosong', () {
      final res = SearchResults(songs: [t('s1')], albums: const []);
      expect(selectedSearchSectionEmpty('albums', res), isTrue);
    });
    test('filter Album terisi -> bukan kosong', () {
      final res = SearchResults(albums: [alb('a1')]);
      expect(selectedSearchSectionEmpty('albums', res), isFalse);
    });
    test('filter Lagu kosong padahal album ada -> seksi kosong', () {
      final res = SearchResults(albums: [alb('a1')], songs: const []);
      expect(selectedSearchSectionEmpty('songs', res), isTrue);
    });
    test('kategori all mengikuti kekosongan total', () {
      expect(selectedSearchSectionEmpty('all', SearchResults(songs: [t('s1')])),
          isFalse);
      expect(selectedSearchSectionEmpty('all', const SearchResults()),
          isTrue);
    });
  });

  group('U-2: urut Koleksi berlaku di Album & Artis', () {
    test('az mengurutkan judul A-Z', () {
      final out = sortSavedItems(
          [saved('Zeta'), saved('Alpha'), saved('Midnight')], 'az');
      expect(out.map((e) => e.title), ['Alpha', 'Midnight', 'Zeta']);
    });
    test('terbaru mempertahankan urutan simpan', () {
      final input = [saved('Zeta'), saved('Alpha')];
      final out = sortSavedItems(input, 'terbaru');
      expect(out.map((e) => e.title), ['Zeta', 'Alpha']);
    });
    test('daftar asal tidak diubah', () {
      final input = [saved('Zeta'), saved('Alpha')];
      sortSavedItems(input, 'az');
      expect(input.map((e) => e.title), ['Zeta', 'Alpha']);
    });
  });

  group('U-1: chevron geser permanen di mini player', () {
    testWidgets('dua chevron tepi: data benar, alfa samar terkunci',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: Row(children: [
            MiniSwipeEdgeHint(left: true),
            MiniSwipeEdgeHint(left: false),
          ]),
        ),
      ));
      final icons = tester.widgetList<ClaiIcon>(find.byType(ClaiIcon)).toList();
      expect(icons.length, 2);
      for (final i in icons) {
        expect(i.data, ClaiIcons.chevronRight);
        expect(i.color?.a, closeTo(kMiniSwipeHintAlpha, 0.001));
      }
      // Yang kiri dicerminkan (satu Transform skala-X negatif).
      final transforms =
          tester.widgetList<Transform>(find.byType(Transform)).toList();
      expect(
        transforms.any((tr) => tr.transform.getMaxScaleOnAxis().isFinite &&
            tr.transform.storage[0] < 0),
        isTrue,
      );
    });
    test('geometri chrome terkunci tidak berubah', () {
      expect(kMiniPlayerHeight, 64);
      expect(kNavBarHeight, 54);
    });
  });

  group('Player: gerbang artis bisa diketuk (canOpenArtist)', () {
    test('trek katalog dengan ID artis -> bisa', () {
      final track = Track(
        key: const TrackKey('ytmusic', 'x1'),
        title: 'X',
        artistNames: 'Artis A',
        artistIds: const ['ida'],
        playableRef: 'x1',
      );
      expect(canOpenArtist(track), isTrue);
    });
    test('trek katalog nama saja -> bisa (resolusi lewat nama)', () {
      expect(canOpenArtist(t('x2', artist: 'Nama Saja')), isTrue);
    });
    test('file lokal tanpa artis -> tidak bisa (tetap teks biasa)', () {
      final local = Track(
        key: const TrackKey('local', '/musik/x.mp3'),
        title: 'Rekaman',
        artistNames: '',
        playableRef: '/musik/x.mp3',
      );
      expect(canOpenArtist(local), isFalse);
    });
    test('byline kata kategori (Song) bukan nama artis -> tidak bisa', () {
      expect(canOpenArtist(t('x3', artist: 'Song')), isFalse);
    });
  });

  group('Indikator timer tidur di mini player', () {
    test('format sisa ringkas m:ss', () {
      expect(formatSleepRemaining(const Duration(minutes: 30)), '30:00');
      expect(formatSleepRemaining(const Duration(minutes: 29, seconds: 41)),
          '29:41');
      expect(formatSleepRemaining(const Duration(seconds: 65)), '1:05');
      expect(formatSleepRemaining(Duration.zero), '0:00');
      expect(formatSleepRemaining(const Duration(seconds: -5)), '0:00');
    });
    testWidgets('chip menampilkan bulan + sisa dan meneruskan ketukan',
        (tester) async {
      var tapped = false;
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SleepTimerChip(
            remaining: const Duration(minutes: 29, seconds: 41),
            onTap: () => tapped = true,
          ),
        ),
      ));
      expect(find.text('29:41'), findsOneWidget);
      final icons = tester.widgetList<ClaiIcon>(find.byType(ClaiIcon)).toList();
      expect(icons.single.data, ClaiIcons.moon);
      await tester.tap(find.byType(SleepTimerChip));
      expect(tapped, isTrue);
    });
  });
}
