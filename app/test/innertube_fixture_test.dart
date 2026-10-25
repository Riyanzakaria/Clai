import 'dart:convert';
import 'dart:io';

import 'package:clai/providers/ytmusic/innertube.dart';
import 'package:flutter_test/flutter_test.dart';

/// Uji parser terhadap fixture HIDUP: subpohon renderer verbatim dari respons
/// WEB_REMIX asli (diambil dari PC, 2026-10-23, putaran v4 — hanya `menu` yang
/// dibuang karena parser tidak memakainya). Bukan fixture karangan.
Map<String, dynamic> fixture(String name) =>
    jsonDecode(File('test/fixtures/$name').readAsStringSync()) as Map<String, dynamic>;

void main() {
  group('cacat v4-2: playlist publik dari pencarian "Semua"', () {
    test('lofi: album, artis, dan playlist muncul dari daftar campuran', () {
      final r = parseSearchResponse(fixture('search_lofi.json'));
      expect(r.songs, isNotEmpty, reason: 'lagu tetap terurai seperti sebelumnya');
      expect(r.albums.length, greaterThanOrEqualTo(3));
      expect(r.artists, isNotEmpty);
      expect(r.playlists.length, greaterThanOrEqualTo(5),
          reason: 'fixture hidup memuat 6 playlist publik');
      final jazz = r.playlists.firstWhere((p) => p.id == 'VLRDCLAK5uy_m6aBO70zO2mNRnBrz9vLCLyjMf8hsZKeE');
      expect(jazz.title, 'Jazz Coffee Shop');
      // Prefiks kategori dibuang dari subjudul: "YouTube Music • 68 songs".
      expect(jazz.artistNames, isNot(startsWith('Playlist')));
      expect(jazz.artistNames, contains('68 songs'));
      expect(jazz.artworkUrl, isNotNull);
    });

    test('top hits 2024: playlist komunitas (VLPL…) ikut muncul', () {
      final r = parseSearchResponse(fixture('search_tophits.json'));
      expect(r.playlists.length, greaterThanOrEqualTo(4));
      expect(r.playlists.any((p) => p.id.startsWith('VLPL')), isTrue,
          reason: 'playlist buatan pengguna berawalan VLPL harus terklasifikasi playlist');
    });

    test('membuka playlist: browse mengurai 68 trek dan SEMUA berdurasi', () {
      final tracks = collectTracks(fixture('browse_playlist.json'));
      expect(tracks.length, greaterThanOrEqualTo(60));
      expect(tracks.first.title, 'Autumn In New York');
      expect(tracks.first.duration, const Duration(minutes: 3, seconds: 53));
      expect(tracks.every((t) => t.duration != null), isTrue,
          reason: 'item browse playlist membawa durasi di fixedColumns');
    });
  });

  group('tambahan v4: durasi & byline dari item pencarian', () {
    test('505: durasi pulih dari segmen ekor byline item Video', () {
      final r = parseSearchResponse(fixture('search_505.json'));
      final top = r.songs.firstWhere((t) => t.title == '505');
      expect(top.duration, const Duration(minutes: 4, seconds: 31),
          reason: 'byline hidup: "Arctic Monkeys • 16M views • 4:31"');
      expect(top.artistNames, isNot(contains('4:31')),
          reason: 'segmen durasi tidak lagi menempel di nama artis');
      expect(top.artistNames, contains('Arctic Monkeys'));
      expect(top.artworkUrl, isNotNull,
          reason: 'thumbUrl harus menembus musicThumbnailRenderer (regresi v4: 0/14 ber-artwork)');
    });

    test('item Song: prefiks kategori dibuang dari nama artis', () {
      final r = parseSearchResponse(fixture('search_505.json'));
      final notion = r.songs.firstWhere((t) => t.title == 'Notion');
      expect(notion.artistNames, 'The Rare Occasions',
          reason: 'byline hidup: "Song • The Rare Occasions"');
      // Jujur: item Song pada pencarian "Semua" memang TIDAK membawa durasi dari sumber
      // (kolom ketiganya jumlah putar) — parser tidak mengarang durasi.
      expect(notion.duration, isNull);
    });
  });
}
