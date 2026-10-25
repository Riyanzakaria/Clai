import 'dart:async';
import 'package:clai/domain/models.dart';
import 'package:clai/player/similarity.dart';
import 'package:flutter_test/flutter_test.dart';

Track t(String id, String artist) => Track(
      key: TrackKey('ytmusic', id), title: 'Lagu $id', artistNames: artist,
      artistIds: ['UC_$artist'], duration: const Duration(minutes: 3), playableRef: id);

class FakeSource implements SimilaritySource {
  @override
  Future<List<Track>> sameArtist(Track seed) async => [t('sa1', 'A'), t('sa2', 'A'), t('sa3', 'A'), t('sa4', 'A')];
  @override
  Future<List<Track>> related(Track seed) async => [t('r1', 'B'), t('r2', 'C')];
  @override
  Future<List<Artist>> similarArtists(Track seed) async =>
      [const Artist(providerId: 'ytmusic', id: 'UC_D', name: 'D')];
  @override
  Future<List<Track>> artistTopTracks(String artistId) async => [t('d1', 'D')];
  @override
  Future<List<Track>> sameGenre(Track seed) async => [t('g1', 'E')];
}

void main() {
  test('Tangga: urutan 1→2→3, pagar maks 2 artis sama berurutan, eksklusi bekerja', () async {
    final ladder = SimilarityLadder(FakeSource());
    final batch = await ladder.buildBatch(
      seeds: [t('seed', 'A')],
      alreadyQueued: {const TrackKey('ytmusic', 'seed')},
      sessionNegative: {const TrackKey('ytmusic', 'r2')},
      lastArtistNames: null,
    );
    final ids = batch.map((x) => x.id).toList();
    expect(ids.contains('r2'), isFalse, reason: 'sinyal negatif sesi harus tersaring (L-06)');
    expect(ids.indexOf('sa1'), lessThan(ids.indexOf('r1')), reason: 'tangga 1 sebelum tangga 2');
    expect(ids.indexOf('r1'), lessThan(ids.indexOf('d1')), reason: 'tangga 2 sebelum tangga 3');
    // Pagar artis: tidak boleh 3 lagu artis A berurutan.
    var run = 0;
    for (final x in batch) {
      run = x.artistNames == 'A' ? run + 1 : 0;
      expect(run, lessThanOrEqualTo(2));
    }
  });

  test('Tangga 5 penguat: lagu liked dari tangga yang sama naik lebih dulu', () async {
    final ladder = SimilarityLadder(FakeSource(), likedKeys: {const TrackKey('ytmusic', 'sa3')});
    final batch = await ladder.buildBatch(
      seeds: [t('seed', 'A')], alreadyQueued: const {}, sessionNegative: const {}, lastArtistNames: null);
    expect(batch.first.id, 'sa3');
  });

  test('Benih kosong menghasilkan batch kosong (tidak menebak)', () async {
    final ladder = SimilarityLadder(FakeSource());
    final batch = await ladder.buildBatch(seeds: const [], alreadyQueued: const {}, sessionNegative: const {}, lastArtistNames: null);
    expect(batch, isEmpty);
  });

  gateTests();
}

Track gt(String id, String title, String artist,
        {Duration? duration = const Duration(minutes: 3, seconds: 30), bool structured = true}) =>
    Track(
      key: TrackKey('ytmusic', id), title: title, artistNames: artist,
      albumId: structured ? 'AL_$id' : null,
      artistIds: structured ? ['UC_$id'] : const [],
      duration: duration, playableRef: id);

class GateSource implements SimilaritySource {
  List<Track> sa = const [], rel = const [], genre = const [];
  List<Artist> similar = const [];
  Map<String, List<Track>> tops = const {};
  bool hangRelated = false;
  @override
  Future<List<Track>> sameArtist(Track seed) async => sa;
  @override
  Future<List<Track>> related(Track seed) =>
      hangRelated ? Completer<List<Track>>().future : Future.value(rel);
  @override
  Future<List<Artist>> similarArtists(Track seed) async => similar;
  @override
  Future<List<Track>> artistTopTracks(String artistId) async => tops[artistId] ?? const [];
  @override
  Future<List<Track>> sameGenre(Track seed) async => genre;
}

void gateTests() {
  test('Gerbang: video numerologi dari related ditolak (kasus perangkat pemilik)', () async {
    final src = GateSource()
      ..rel = [
        gt('num', '✨ Name Number 59 in Numerology', 'Numerology, Name Meanings', structured: false, duration: null),
        gt('ok', 'Lagu Tetangga Sah', 'Artis Tetangga'),
      ];
    final batch = await SimilarityLadder(src).buildBatch(
      seeds: [gt('seed', 'Menungso Oratoto', 'Nabih Fvnky')],
      alreadyQueued: const {}, sessionNegative: const {}, lastArtistNames: null);
    expect(batch.map((x) => x.id), ['ok'], reason: 'non-musik jelas tidak boleh lolos; lagu sah tetap lolos');
  });

  test('Gerbang: mixtape 1 jam artis lain ditolak; rekaman panjang artis benih lolos', () async {
    final src = GateSource()
      ..rel = [gt('mix', 'PRIVATE MIXTAPE FULL SET', 'DJ Leo', duration: const Duration(minutes: 62))]
      ..sa = [gt('live', 'Konser Live 40 Menit', 'Artis Benih', duration: const Duration(minutes: 40))];
    final batch = await SimilarityLadder(src).buildBatch(
      seeds: [gt('seed', 'Lagu Benih', 'Artis Benih')],
      alreadyQueued: const {}, sessionNegative: const {}, lastArtistNames: null);
    expect(batch.map((x) => x.id), ['live'],
        reason: 'durasi ekstrem hanya sah dari artis utama yang sama dengan benih');
  });

  test('Gerbang: lagu sah genre tetangga (panel, tanpa struktur) tetap lolos', () async {
    final src = GateSource()
      ..rel = [gt('panel', 'Do I Wanna Know?', 'Arctic Monkeys • 1.9B views', structured: false, duration: null)];
    final batch = await SimilarityLadder(src).buildBatch(
      seeds: [gt('seed', '505', 'Arctic Monkeys')],
      alreadyQueued: const {}, sessionNegative: const {}, lastArtistNames: null);
    expect(batch.map((x) => x.id), ['panel'],
        reason: 'item panel bukan sampah per se — yang disaring penanda non-musik & durasi ekstrem');
  });

  test('Pagar: varian huruf nama artis tidak bisa mengelabui maks-2-berurutan', () async {
    final src = GateSource()
      ..sa = [
        gt('h1', 'Satu', 'Hendraa RMX V2'),
        gt('h2', 'Dua', 'HENDRAA RMX V2'),
        gt('h3', 'Tiga', 'Hendraa Rmx V2'),
        gt('h4', 'Empat', 'hendraa rmx v2'),
        gt('h5', 'Lima', 'Hendraa RMX V2'),
      ];
    final batch = await SimilarityLadder(src).buildBatch(
      seeds: [gt('seed', 'Benih', 'Penyanyi Lain')],
      alreadyQueued: const {}, sessionNegative: const {}, lastArtistNames: null);
    expect(batch.length, 2,
        reason: 'kolam hanya berisi satu artis: sesudah 2 berurutan sisanya gugur — batch pendek & jujur');
  });

  test('Dedup versi: versi lain lagu benih & versi ganda di batch dibuang', () async {
    final src = GateSource()
      ..rel = [
        gt('alt', 'For All The Dreams That Wings Could Fly', 'Themilo & Weeds'),
        gt('a1', 'Kalam', 'Swellow'),
        gt('a2', 'Kalam (Remastered)', 'Swellow'),
      ];
    final batch = await SimilarityLadder(src).buildBatch(
      seeds: [gt('seed', 'For All The Dreams That Wings Could Fly', 'Themilo & Maradilla Syahridar')],
      alreadyQueued: const {}, sessionNegative: const {}, lastArtistNames: null);
    expect(batch.map((x) => x.id), ['a1'],
        reason: 'alt = lagu benih itu sendiri versi lain; a2 = duplikat versi a1');
  });

  test('Sumber menggantung tidak menyandera batch (batas waktu per panggilan)', () async {
    final src = GateSource()
      ..hangRelated = true
      ..sa = [gt('sa1', 'Masih Jalan', 'Artis Benih')];
    final ladder = SimilarityLadder(src, sourceTimeout: const Duration(milliseconds: 60));
    final batch = await ladder.buildBatch(
      seeds: [gt('seed', 'Lagu Benih', 'Artis Benih')],
      alreadyQueued: const {}, sessionNegative: const {}, lastArtistNames: null);
    expect(batch.map((x) => x.id), ['sa1'], reason: 'tangga 2 gugur oleh batas waktu; tangga 1 tetap mengisi');
  });
}
