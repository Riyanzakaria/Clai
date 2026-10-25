import 'package:clai/domain/models.dart';
import 'package:clai/player/load_ladder.dart';
import 'package:clai/player/queue_engine.dart';
import 'package:clai/player/resolving_audio_source.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';

/// Penutup cakupan mesin pemutar (Sapuan D-02, gerbang Bab 8: cakupan baris
/// mesin pemutar ≥90%). Menyasar cabang-cabang QueueEngine & LoadLadder yang
/// belum tersentuh suite lain: penghapusan/penggeseran seksi, sinyal cerdas,
/// filter offline, penempelan durasi/sampul, lompat-ke-trek, label anak tangga,
/// dan jalur gugur tangga muat.
Track t(String id) => Track(
    key: TrackKey('ytmusic', id),
    title: 'Lagu $id',
    artistNames: 'Artis',
    duration: const Duration(minutes: 3),
    playableRef: id);

void main() {
  group('QueueEngine — cabang pelengkap cakupan', () {
    test('removeAt/moveIn batas & sah', () {
      final e = QueueEngine();
      e.playContext(
          PlayContext(kind: 'album', label: 'A', tracks: [t('a'), t('b')]), 0);
      e.enqueueLater(t('m1'));
      e.enqueueLater(t('m2'));
      e.enqueueLater(t('m3'));
      expect(e.removeAt(e.manual, 5), isNull);
      expect(e.removeAt(e.manual, -1), isNull);
      expect(e.removeAt(e.manual, 0)!.id, 'm1');
      e.moveIn(e.manual, 0, 0); // no-op
      e.moveIn(e.manual, 9, 0); // di luar batas: no-op
      e.moveIn(e.manual, 0, 1);
      expect(e.manual.map((x) => x.id), ['m3', 'm2']);
      expect(e.fullIndexOf(const TrackKey('ytmusic', 'm3')), 1);
      expect(e.fullIndexOf(const TrackKey('ytmusic', 'tidak-ada')), -1);
      expect(e.hasCurrent, isTrue);
      expect(e.effectiveQueue, isNotEmpty);
      expect(e.fullQueue.first.id, 'a');
    });

    test('playContext kosong & shuffle murni dari indeks tengah', () {
      final e = QueueEngine();
      e.playContext(PlayContext(kind: 'album', label: 'K', tracks: const []), 0);
      expect(e.seeds, isEmpty);
      expect(e.current, isNull);
      final e2 = QueueEngine();
      e2.shuffle = ShuffleMode.pure;
      e2.playContext(
          PlayContext(kind: 'album', label: 'A', tracks: [t('a'), t('b'), t('c')]), 1);
      expect(e2.current!.id, 'b', reason: 'trek yang diketuk tetap pertama');
      expect(e2.seeds.length, 3);
    });

    test('clearManual/clearAutoplay/clearAllUpcoming + setAutoplayBatch', () {
      final e = QueueEngine();
      e.playContext(PlayContext(kind: 'album', label: 'A', tracks: [t('a'), t('b')]), 0);
      e.enqueueLater(t('m'));
      e.setAutoplayBatch([t('x'), t('y')]);
      expect(e.autoplay.length, 2);
      e.clearAutoplay();
      expect(e.autoplay, isEmpty);
      e.setAutoplayBatch([t('x')]);
      e.clearAllUpcoming();
      expect(e.manual, isEmpty);
      expect(e.autoplay, isEmpty);
      e.enqueueLater(t('m'));
      e.clearManual();
      expect(e.manual, isEmpty);
    });

    test('applySmartShuffle memakai sinyal; seksi pendek no-op', () {
      final e = QueueEngine();
      e.playContext(
          PlayContext(kind: 'album', label: 'A', tracks: [t('a'), t('b'), t('c'), t('d')]), 0);
      e.applySmartShuffle(); // lanjutan 3 trek tanpa sinyal: tetap permutasi
      expect(e.continuation.length, 3);
      e.setSmartSignals(
          likedKeys: {const TrackKey('ytmusic', 'd')},
          playCounts: {const TrackKey('ytmusic', 'c'): 9});
      e.applySmartShuffle();
      expect(e.continuation.map((x) => x.id).toSet(), {'b', 'c', 'd'});
      final e2 = QueueEngine();
      e2.playContext(PlayContext(kind: 'album', label: 'A', tracks: [t('a')]), 0);
      e2.applySmartShuffle(); // lanjutan kosong: tidak melempar
      expect(e2.continuation, isEmpty);
    });

    test('retainOffline menyaring seksi & menghitung yang dibuang', () {
      final e = QueueEngine();
      e.playContext(PlayContext(kind: 'album', label: 'A', tracks: [t('a'), t('b')]), 0);
      e.enqueueLater(t('m1'));
      e.setAutoplayBatch([t('x')]);
      final removed = e.retainOffline({const TrackKey('ytmusic', 'b')});
      expect(removed, 2, reason: 'm1 & x tersaring; b tinggal di lanjutan');
      expect(e.continuation.single.id, 'b');
      expect(e.current!.id, 'a', reason: 'trek berjalan tidak disentuh');
      expect(e.retainOffline({const TrackKey('ytmusic', 'b')}), 0);
    });

    test('noteDuration & noteArtwork menempel ke semua kemunculan', () {
      final e = QueueEngine();
      final a = t('a');
      e.playContext(PlayContext(kind: 'album', label: 'A', tracks: [a, t('b')]), 0);
      expect(e.noteDuration(a.key, const Duration(minutes: 4)), isTrue);
      expect(e.current!.duration, const Duration(minutes: 4));
      expect(e.noteDuration(const TrackKey('ytmusic', 'zz'), const Duration(minutes: 1)), isFalse);
      expect(e.noteArtwork(a.key, 'http://img'), isTrue);
      expect(e.current!.artworkUrl, 'http://img');
      expect(e.noteArtwork(a.key, 'http://lain'), isFalse,
          reason: 'sampul yang sudah ada tidak ditimpa');
    });

    test('jumpTo melompat lintas seksi & memotong yang terlewat', () {
      final e = QueueEngine();
      e.playContext(
          PlayContext(kind: 'album', label: 'A', tracks: [t('a'), t('b'), t('c')]), 0);
      e.enqueueNext(t('m1'));
      final landed = e.jumpTo(const TrackKey('ytmusic', 'c'));
      expect(landed!.id, 'c');
      expect(e.continuation, isEmpty);
      expect(e.jumpTo(const TrackKey('ytmusic', 'tidak-ada')), isNull);
      final e2 = QueueEngine();
      e2.playContext(PlayContext(kind: 'album', label: 'A', tracks: [t('a'), t('b')]), 0);
      e2.enqueueLater(t('m1'));
      e2.setAutoplayBatch([t('x'), t('y')]);
      expect(e2.jumpTo(const TrackKey('ytmusic', 'y'))!.id, 'y');
      expect(e2.autoplay, isEmpty);
    });
  });

  group('LoadLadder — cabang pelengkap cakupan', () {
    StreamInfo info(String url) => StreamInfo(
        url: url,
        mimeType: 'audio/mp4',
        expiresAt: DateTime.now().add(const Duration(hours: 1)));
    LoadLadder ladder({
      Future<StreamInfo> Function(Track)? adaptive,
      Future<StreamInfo?> Function(Track)? muxed,
      String? Function(Track)? localFileFor,
      bool Function(Track)? isLocal,
    }) =>
        LoadLadder(
          resolveAdaptive: adaptive ?? (t) async => info('https://cdn/${t.id}'),
          resolveMuxed: muxed ?? (t) async => info('https://mux/${t.id}'),
          tagFor: (t) => null,
          isLocal: isLocal ?? (t) => t.playableRef.startsWith('file'),
          localFileFor: localFileFor,
        );

    test('label anak tangga lengkap', () {
      expect(LoadLadder.rungLabel(LoadLadder.rungAdaptiveUri), contains('adaptif'));
      expect(LoadLadder.rungLabel(LoadLadder.rungMuxedUri), contains('muxed'));
      expect(LoadLadder.rungLabel(LoadLadder.rungProxy), contains('proxy'));
      expect(LoadLadder.rungLabel(99), contains('99'));
    });

    test('run: semua anak gugur → galat anak terakhir dilempar', () async {
      final l = ladder();
      final failed = <int>[];
      await expectLater(
        l.run(
          attempt: (rung) async => throw StateError('gugur $rung'),
          onRungFailed: (rung, e, st) => failed.add(rung),
        ),
        throwsStateError,
      );
      expect(failed.length, LoadLadder.rungCount);
    });

    test('run: anak kedua menang → lengket di sana; advance memutar', () async {
      final l = ladder();
      final won = await l.run(attempt: (rung) async {
        if (rung == LoadLadder.rungAdaptiveUri) throw StateError('x');
      });
      expect(won, LoadLadder.rungMuxedUri);
      expect(l.stickyRung, LoadLadder.rungMuxedUri);
      expect(l.orderForAttempt().first, LoadLadder.rungMuxedUri);
      expect(l.advance(), LoadLadder.rungProxy);
    });

    test('childFor: berkas unduhan & trek lokal melewati tangga', () async {
      final l = ladder(localFileFor: (t) => '/data/${t.id}.m4a');
      final src = await l.childFor(t('a'), LoadLadder.rungAdaptiveUri);
      expect(src, isA<UriAudioSource>());
      expect((src as UriAudioSource).uri.scheme, 'file');
      final l2 = ladder();
      final local = Track(
          key: const TrackKey('local', 'f1'),
          title: 'Lokal',
          artistNames: 'A',
          playableRef: 'file:///storage/f1.mp3');
      final src2 = await l2.childFor(local, LoadLadder.rungAdaptiveUri);
      expect((src2 as UriAudioSource).uri.scheme, 'file');
    });

    test('childFor: adaptif gugur non-ketat → proxy; ketat → lempar', () async {
      final l = ladder(adaptive: (t) async => throw StateError('mati'));
      final soft = await l.childFor(t('a'), LoadLadder.rungAdaptiveUri);
      expect(soft, isA<ResolvingAudioSource>());
      await expectLater(
          l.childFor(t('a'), LoadLadder.rungAdaptiveUri, strict: true),
          throwsStateError);
    });

    test('childFor: muxed kosong ketat → lempar; non-ketat → proxy; proxy langsung', () async {
      final l = ladder(muxed: (t) async => null);
      await expectLater(l.childFor(t('a'), LoadLadder.rungMuxedUri, strict: true),
          throwsStateError);
      expect(await l.childFor(t('a'), LoadLadder.rungMuxedUri),
          isA<ResolvingAudioSource>());
      expect(await l.childFor(t('a'), LoadLadder.rungProxy),
          isA<ResolvingAudioSource>());
      final l2 = ladder();
      final mux = await l2.childFor(t('a'), LoadLadder.rungMuxedUri);
      expect((mux as UriAudioSource).uri.toString(), contains('mux'));
    });
  });
}
