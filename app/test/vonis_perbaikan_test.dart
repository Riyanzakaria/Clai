import 'package:clai/domain/models.dart';
import 'package:clai/player/similarity.dart';
import 'package:clai/player/source_sync.dart';
import 'package:flutter_test/flutter_test.dart';

Track _t(String id, [String artist = 'X']) => Track(
      key: TrackKey('ytm', id),
      title: 'Lagu $id',
      artistNames: artist,
      artistIds: ['UC_$artist'],
      duration: const Duration(minutes: 3),
      playableRef: id,
    );

List<Track> _tracks(List<String> ids) => [for (final id in ids) _t(id)];

/// Terapkan rencana sesuai kontrak eksekusi handler: cabut menurun,
/// sisip menaik. Hasilnya harus persis daftar tujuan.
List<String> _apply(List<Track> loaded, List<TailEdit> edits) {
  final list = List<Track>.of(loaded);
  final removes = edits.whereType<TailRemove>().toList()
    ..sort((a, b) => b.tailIndex.compareTo(a.tailIndex));
  for (final e in removes) {
    list.removeAt(e.tailIndex);
  }
  final inserts = edits.whereType<TailInsert>().toList()
    ..sort((a, b) => a.tailIndex.compareTo(b.tailIndex));
  for (final e in inserts) {
    list.insert(e.tailIndex, e.track);
  }
  return list.map((t) => t.id).toList();
}

void _expectPlan(List<String> loadedIds, List<String> desiredIds,
    {int? removes, int? inserts}) {
  final loaded = _tracks(loadedIds);
  final desired = _tracks(desiredIds);
  final plan = planTailEdits(loaded, desired);
  expect(_apply(loaded, plan), desiredIds,
      reason: 'rencana $loadedIds → $desiredIds harus menghasilkan tujuan');
  if (removes != null) {
    expect(plan.whereType<TailRemove>().length, removes,
        reason: 'jumlah cabut $loadedIds → $desiredIds');
  }
  if (inserts != null) {
    expect(plan.whereType<TailInsert>().length, inserts,
        reason: 'jumlah sisip $loadedIds → $desiredIds');
  }
}

void main() {
  group('planTailEdits (temuan vonis #3: edit bedah ekor sumber)', () {
    test('identik → rencana kosong', () {
      _expectPlan(['a', 'b', 'c'], ['a', 'b', 'c'], removes: 0, inserts: 0);
      _expectPlan([], [], removes: 0, inserts: 0);
    });

    test('hapus satu di tengah → satu cabut tepat di indeksnya', () {
      final plan = planTailEdits(_tracks(['a', 'b', 'c', 'd']), _tracks(['a', 'c', 'd']));
      expect(plan, [const TailRemove(1)]);
    });

    test('hapus di ujung ekor → satu cabut', () {
      _expectPlan(['a', 'b', 'c'], ['a', 'b'], removes: 1, inserts: 0);
    });

    test('hapus tersebar (pola saring offline) → hanya yang hilang dicabut', () {
      _expectPlan(['a', 'b', 'c', 'd', 'e'], ['a', 'd'], removes: 3, inserts: 0);
    });

    test('blok autoplay di suffix hilang (saklar mati) → cabut suffix saja', () {
      _expectPlan(['m', 'c', 'p1', 'p2'], ['m', 'c'], removes: 2, inserts: 0);
    });

    test('sisip satu di tengah (urungkan) → satu sisip, ekor lama utuh', () {
      final plan = planTailEdits(_tracks(['a', 'c']), _tracks(['a', 'b', 'c']));
      expect(plan.length, 1);
      final ins = plan.single as TailInsert;
      expect(ins.tailIndex, 1);
      expect(ins.track.id, 'b');
    });

    test('sisip di kepala ekor (Putar Berikutnya) → sisip indeks 0', () {
      _expectPlan(['a', 'b'], ['x', 'a', 'b'], removes: 0, inserts: 1);
    });

    test('sisip di dalam jendela tidak membuang penghuni terakhir jendela', () {
      _expectPlan(['a', 'b', 'c'], ['a', 'x', 'b', 'c'], removes: 0, inserts: 1);
    });

    test('geser urutan → satu cabut + satu sisip untuk trek yang pindah', () {
      _expectPlan(['a', 'b', 'c', 'd'], ['a', 'c', 'b', 'd'], removes: 1, inserts: 1);
    });

    test('bersihkan antrean → seluruh ekor dicabut', () {
      _expectPlan(['a', 'b', 'c'], [], removes: 3, inserts: 0);
    });

    test('ekor kosong → semua disisipkan', () {
      _expectPlan([], ['a', 'b'], removes: 0, inserts: 2);
    });

    test('kunci duplikat ditangani posisional, bukan asal cocok', () {
      // Trek 'a' muncul dua kali; yang harus hilang hanya 'b' di tengah.
      _expectPlan(['a', 'b', 'a'], ['a', 'a'], removes: 1, inserts: 0);
    });
  });

  group('buildRefillBatch (temuan vonis #4: eksklusi riwayat bertingkat)', () {
    test('kolam cukup: yang sudah diputar tidak ditawarkan lagi, tanpa pelonggaran', () async {
      final ladder = SimilarityLadder(_RefillSource());
      final result = await buildRefillBatch(
        ladder,
        seeds: [_t('seed', 'A')],
        queuedKeys: {_t('seed', 'A').key},
        playedKeys: {_t('p1', 'A').key, _t('p2', 'B').key},
        sessionNegative: const {},
      );
      final ids = result.batch.map((t) => t.id).toList();
      expect(ids, isNot(contains('p1')));
      expect(ids, isNot(contains('p2')));
      expect(ids, containsAll(['f1', 'f2', 'f3']));
      expect(result.relaxed, isFalse);
    });

    test('kolam hanya berisi riwayat: pelonggaran menyala dan pengulangan diizinkan', () async {
      final ladder = SimilarityLadder(_PlayedOnlySource());
      final result = await buildRefillBatch(
        ladder,
        seeds: [_t('seed', 'A')],
        queuedKeys: {_t('seed', 'A').key},
        playedKeys: {_t('p1', 'A').key, _t('p2', 'A').key, _t('p3', 'B').key, _t('p4', 'E').key},
        sessionNegative: const {},
      );
      expect(result.relaxed, isTrue);
      expect(result.batch, isNotEmpty);
      expect(result.batch.map((t) => t.id), contains('p1'));
    });

    test('sinyal skip TIDAK pernah dilonggarkan walau kolam habis', () async {
      final ladder = SimilarityLadder(_PlayedOnlySource());
      final result = await buildRefillBatch(
        ladder,
        seeds: [_t('seed', 'A')],
        queuedKeys: {_t('seed', 'A').key},
        playedKeys: {_t('p1', 'A').key, _t('p2', 'A').key, _t('p4', 'E').key},
        sessionNegative: {_t('p3', 'B').key},
      );
      expect(result.relaxed, isTrue);
      expect(result.batch.map((t) => t.id), isNot(contains('p3')));
      expect(result.batch.map((t) => t.id), contains('p1'));
    });

    test('riwayat kosong: satu percobaan saja, hasil normal', () async {
      final ladder = SimilarityLadder(_RefillSource());
      final result = await buildRefillBatch(
        ladder,
        seeds: [_t('seed', 'A')],
        queuedKeys: {_t('seed', 'A').key},
        playedKeys: const {},
        sessionNegative: const {},
      );
      expect(result.relaxed, isFalse);
      expect(result.batch.map((t) => t.id), contains('p1'));
    });
  });
}

/// Kolam campuran: sebagian sudah diputar sesi ini (p*), sebagian segar (f*).
class _RefillSource implements SimilaritySource {
  @override
  Future<List<Track>> sameArtist(Track seed) async => [_t('p1', 'A'), _t('f1', 'A')];
  @override
  Future<List<Track>> related(Track seed) async => [_t('p2', 'B'), _t('f2', 'C')];
  @override
  Future<List<Artist>> similarArtists(Track seed) async =>
      [const Artist(providerId: 'ytm', id: 'UC_D', name: 'D')];
  @override
  Future<List<Track>> artistTopTracks(String artistId) async => [_t('f3', 'D')];
  @override
  Future<List<Track>> sameGenre(Track seed) async => [_t('f4', 'E')];
}

/// Kolam yang seluruhnya sudah diputar sesi ini.
class _PlayedOnlySource implements SimilaritySource {
  @override
  Future<List<Track>> sameArtist(Track seed) async => [_t('p1', 'A'), _t('p2', 'A')];
  @override
  Future<List<Track>> related(Track seed) async => [_t('p3', 'B')];
  @override
  Future<List<Artist>> similarArtists(Track seed) async => const [];
  @override
  Future<List<Track>> artistTopTracks(String artistId) async => const [];
  @override
  Future<List<Track>> sameGenre(Track seed) async => [_t('p4', 'E')];
}
