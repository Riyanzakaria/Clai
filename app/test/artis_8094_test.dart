import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:clai/core/clai_icons.dart';
import 'package:clai/data/app_db.dart';
import 'package:clai/domain/models.dart';
import 'package:clai/l10n/app_localizations.dart';
import 'package:clai/services/track_metadata_healer.dart';
import 'package:clai/ui/menu_drawer.dart';
import 'package:clai/ui/widgets.dart' show resolveArtistForIdlessTrack;

/// Ronde 8094 — Paket A (resolusi artis by-id untuk trek tanpa pengenal;
/// sumber kebenaran: builds/bukti-artis-tidak-ditemukan/BEDAH.md) +
/// Paket B/C (tombol markah logo netral; wordmark "Clai.").
///
/// Lubang pengujian 8092 yang TIDAK diulang di sini: cabang tanpa
/// pengenal dilatih lewat RESOLUSI BY-ID dengan trek hasil resolusi —
/// bukan daftar nama sintetis yang memuat padanan persis.

Track mk(String id,
        {String provider = 'ytmusic',
        String names = 'magnolia celebration',
        List<String> ids = const [],
        String? artwork = 'https://img/x'}) =>
    Track(
      key: TrackKey(provider, id),
      title: 'Lagu $id',
      artistNames: names,
      artistIds: ids,
      artworkUrl: artwork,
      duration: const Duration(minutes: 3),
      playableRef: id,
    );

const asing = Artist(
    providerId: 'ytmusic', id: 'UCSeP4LSDvpnRarE15oriMoQ', name: 'Alvin Lizada');
const benarArtis = Artist(
    providerId: 'ytmusic',
    id: 'UCufMCbapcb69A44RTZ8RY-w',
    name: 'Magnolia Celebration');

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('A — resolusi by-id didahulukan dari pencarian nama', () {
    test(
        'resolusi by-id membawa pengenal → id itu dipakai, tulis-balik '
        'dipanggil dengan salinan sembuh, pencarian TIDAK dipanggil',
        () async {
      var searchCalls = 0;
      Track? writtenBack;
      final res = await resolveArtistForIdlessTrack(
        mk('z8J8fOHdpPw'),
        resolveById: (id) async => mk(id,
            names: 'magnolia celebration',
            ids: const ['UCufMCbapcb69A44RTZ8RY-w']),
        searchArtists: (q) async {
          searchCalls++;
          return const [asing];
        },
        onResolved: (healed) async => writtenBack = healed,
      );
      expect(res, isNotNull);
      expect(res!.id, 'UCufMCbapcb69A44RTZ8RY-w');
      expect(searchCalls, 0,
          reason: 'by-id berhasil → pencarian nama tidak boleh berjalan');
      expect(writtenBack, isNotNull,
          reason: 'baris lokal wajib ditulis balik agar sembuh permanen');
      expect(writtenBack!.key, const TrackKey('ytmusic', 'z8J8fOHdpPw'));
      expect(writtenBack!.artistIds, ['UCufMCbapcb69A44RTZ8RY-w']);
      expect(writtenBack!.title, 'Lagu z8J8fOHdpPw',
          reason: 'tulis-balik = salinan trek ASAL yang disembuhkan '
              '(pola penyembuh), bukan trek hasil parse mentah');
    });

    test('resolusi by-id null → jatuh ke pencarian nama padanan persis',
        () async {
      final res = await resolveArtistForIdlessTrack(
        mk('z8J8fOHdpPw'),
        resolveById: (id) async => null,
        searchArtists: (q) async => const [asing, benarArtis],
      );
      expect(res?.id, 'UCufMCbapcb69A44RTZ8RY-w');
      expect(res?.name, 'Magnolia Celebration');
    });

    test(
        'resolusi by-id mengembalikan trek TANPA pengenal → jatuh ke '
        'pencarian nama', () async {
      final res = await resolveArtistForIdlessTrack(
        mk('z8J8fOHdpPw'),
        resolveById: (id) async => mk(id), // tetap tanpa pengenal
        searchArtists: (q) async => const [benarArtis],
      );
      expect(res?.id, 'UCufMCbapcb69A44RTZ8RY-w');
    });

    test('resolusi by-id melempar → jatuh ke pencarian nama', () async {
      final res = await resolveArtistForIdlessTrack(
        mk('z8J8fOHdpPw'),
        resolveById: (id) async => throw StateError('jaringan mati'),
        searchArtists: (q) async => const [benarArtis],
      );
      expect(res?.id, 'UCufMCbapcb69A44RTZ8RY-w');
    });

    test(
        'komposisi probe hidup BEDAH (rak artis TIDAK memuat artisnya) → '
        'by-id menyelamatkan; tanpa by-id hasilnya null jujur', () async {
      // Rak persis probe "magnolia celebration": Alvin Lizada dkk.
      Future<List<Artist>> rakAsing(String q) async => const [asing];
      final tanpaById = await resolveArtistForIdlessTrack(
        mk('z8J8fOHdpPw'),
        resolveById: (id) async => null,
        searchArtists: rakAsing,
      );
      expect(tanpaById, isNull,
          reason: 'inilah kegagalan 8093 di HP pemilik — jujur null');
      final denganById = await resolveArtistForIdlessTrack(
        mk('z8J8fOHdpPw'),
        resolveById: (id) async =>
            mk(id, ids: const ['UCufMCbapcb69A44RTZ8RY-w']),
        searchArtists: rakAsing,
      );
      expect(denganById?.id, 'UCufMCbapcb69A44RTZ8RY-w');
    });

    test('provider bukan katalog → by-id TIDAK dipanggil, nama saja',
        () async {
      var byIdCalls = 0;
      final res = await resolveArtistForIdlessTrack(
        mk('lagu-lokal', provider: 'spotify', names: 'Artis Impor'),
        resolveById: (id) async {
          byIdCalls++;
          return null;
        },
        searchArtists: (q) async => const [
          Artist(providerId: 'ytmusic', id: 'UCimpor', name: 'Artis Impor'),
        ],
      );
      expect(byIdCalls, 0);
      expect(res?.id, 'UCimpor');
    });

    test('semua jalur gagal → null (snackbar jujur di pemanggil)', () async {
      final res = await resolveArtistForIdlessTrack(
        mk('z8J8fOHdpPw'),
        resolveById: (id) async => null,
        searchArtists: (q) async => const [asing],
      );
      expect(res, isNull);
    });

    test('nama utama kosong (label kategori) + by-id gagal → null tanpa '
        'pencarian', () async {
      var searchCalls = 0;
      final res = await resolveArtistForIdlessTrack(
        mk('x1', names: 'Song'),
        resolveById: (id) async => null,
        searchArtists: (q) async {
          searchCalls++;
          return const [benarArtis];
        },
      );
      expect(res, isNull);
      expect(searchCalls, 0);
    });
  });

  group('A — penyembuh: pengenal kosong pada trek katalog sehat', () {
    test('needsHeal kini benar untuk bernama sehat + bersampul + ids kosong',
        () {
      final t = mk('h1', names: 'rumahsakit');
      expect(TrackMetadataHealer.needsHeal(t), isTrue,
          reason: 'kelas baris pra-v9: nama sehat, sampul ada, pengenal '
              'kosong — dulu tidak pernah disembuhkan');
    });

    test('needsHeal tetap salah bila pengenal sudah terisi', () {
      final t = mk('h2', names: 'rumahsakit', ids: const ['UCrDchPabbq4ATorprRY0-KA']);
      expect(TrackMetadataHealer.needsHeal(t), isFalse);
    });

    test('healIfNeeded menyalin pengenal dari resolusi dan menulis ke DB',
        () async {
      final db = AppDb();
      await db.openAt(':memory:');
      final lama = mk('WxkJVvSgCGk', names: 'rumahsakit');
      await db.cacheTracks([lama]);
      final healer = TrackMetadataHealer(db, resolveById: (id) async => mk(id,
          names: 'rumahsakit', ids: const ['UCrDchPabbq4ATorprRY0-KA']));
      final healed = await healer.healIfNeeded(lama);
      expect(healed, isNotNull);
      expect(healed!.artistIds, ['UCrDchPabbq4ATorprRY0-KA']);
      final row = await db.trackByKey(const TrackKey('ytmusic', 'WxkJVvSgCGk'));
      expect(row!.artistIds, ['UCrDchPabbq4ATorprRY0-KA'],
          reason: 'baris basis data sembuh permanen');
      await db.close();
    });

    test('healIfNeeded: resolusi tanpa pengenal → null, baris tetap kosong',
        () async {
      final db = AppDb();
      await db.openAt(':memory:');
      final lama = mk('WxkJVvSgCGk', names: 'rumahsakit');
      await db.cacheTracks([lama]);
      final healer =
          TrackMetadataHealer(db, resolveById: (id) async => mk(id, names: 'rumahsakit'));
      expect(await healer.healIfNeeded(lama), isNull);
      final row = await db.trackByKey(const TrackKey('ytmusic', 'WxkJVvSgCGk'));
      expect(row!.artistIds, isEmpty);
      await db.close();
    });
  });

  group('B/C — markah logo netral + wordmark "Clai."', () {
    Widget host(Widget child) => MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('id'),
          home: Scaffold(body: Center(child: child)),
        );

    testWidgets('wordmark merender "Clai." (titik di akhir)', (tester) async {
      await tester.pumpWidget(host(const ClaiWordmark()));
      expect(find.text('Clai.'), findsOneWidget);
      expect(find.text('Clai'), findsNothing);
    });

    testWidgets('tombol markah berisi markah logo, bukan atom "C" + titik',
        (tester) async {
      var taps = 0;
      await tester.pumpWidget(host(ClaiMarkButton(onPressed: () => taps++)));
      expect(find.byType(ClaiMark), findsOneWidget);
      expect(find.text('C'), findsNothing);
      await tester.tap(find.byType(ClaiMarkButton));
      expect(taps, 1, reason: 'semantik ketuk tombol tidak berubah');
    });
  });
}
