import 'package:clai/data/app_db.dart';
import 'package:clai/domain/models.dart';
import 'package:clai/player/queue_engine.dart';
import 'package:clai/player/source_sync.dart';
import 'package:clai/services/library_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Track t(String id, {String artist = 'Artis'}) => Track(
      key: TrackKey('ytmusic', id),
      title: 'Lagu $id',
      artistNames: artist,
      duration: const Duration(minutes: 3),
      playableRef: id,
    );

List<String> ids(List<Track> l) => l.map((e) => e.id).toList();

void main() {
  group('enqueueAllLater (Butir 1: antrekan semua dari Radio)', () {
    test('seluruh daftar masuk ekor Berikutnya berurutan', () {
      final e = QueueEngine();
      e.manual = [t('m0')];
      e.enqueueAllLater([t('r1'), t('r2'), t('r3')]);
      expect(ids(e.manual), ['m0', 'r1', 'r2', 'r3']);
    });

    test('daftar kosong = no-op', () {
      final e = QueueEngine();
      final v = e.version;
      e.enqueueAllLater(const []);
      expect(e.manual, isEmpty);
      expect(e.version, v);
    });
  });

  group('removeAllKeys (Butir 2: hapus massal pilih-banyak)', () {
    test('cabut lintas kunci; urutan penyintas & hasil cabutan terjaga', () {
      final e = QueueEngine();
      e.manual = [t('a'), t('b'), t('c'), t('d')];
      final removed = e.removeAllKeys(
          e.manual, {t('b').key, t('d').key, t('zz').key});
      expect(ids(removed), ['b', 'd'], reason: 'urutan asal dipertahankan');
      expect(ids(e.manual), ['a', 'c']);
    });

    test('duplikat kunci dalam satu seksi: kedua salinan tercabut', () {
      final e = QueueEngine();
      e.autoplay = [t('x'), t('y'), t('x')];
      final removed = e.removeAllKeys(e.autoplay, {t('x').key});
      expect(removed.length, 2);
      expect(ids(e.autoplay), ['y']);
    });

    test('himpunan kosong = no-op tanpa menaikkan versi', () {
      final e = QueueEngine();
      e.continuation = [t('a')];
      final v = e.version;
      expect(e.removeAllKeys(e.continuation, const {}), isEmpty);
      expect(e.version, v);
    });

    test('rencana edit ekor untuk hapus massal TIDAK menyentuh trek berjalan',
        () {
      // Simulasi komposisi handler: loadedTail = antrean efektif sebelum,
      // desired = sesudah removeAllKeys di ketiga seksi. Trek berjalan
      // tidak pernah menjadi bagian ekor → tidak ada edit yang
      // mengindeksnya (semua TailRemove/TailInsert berkoordinat ekor ≥ 0).
      final e = QueueEngine();
      e.current = t('now');
      e.manual = [t('m1'), t('m2')];
      e.continuation = [t('c1'), t('c2')];
      e.autoplay = [t('a1'), t('a2')];
      final loadedTail = e.effectiveQueue;
      e.removeAllKeys(e.manual, {t('m2').key});
      e.removeAllKeys(e.continuation, {t('c1').key});
      e.removeAllKeys(e.autoplay, {t('a1').key, t('a2').key});
      final edits = planTailEdits(loadedTail, e.effectiveQueue);
      expect(ids(e.effectiveQueue), ['m1', 'c2']);
      expect(edits.whereType<TailInsert>(), isEmpty);
      expect(
        edits.whereType<TailRemove>().map((r) => r.tailIndex).toSet(),
        {1, 2, 4, 5},
        reason: 'hanya indeks ekor milik item terpilih yang dicabut',
      );
      expect(e.current!.id, 'now', reason: 'trek berjalan utuh');
    });
  });

  group('extractQueued (Butir 3: pindah dari menu konteks antrean)', () {
    test('petunjuk indeks tepat → item itu yang tercabut', () {
      final e = QueueEngine();
      e.continuation = [t('c1'), t('c2'), t('c3')];
      final got = e.extractQueued('continuation', 1, t('c2').key);
      expect(got!.id, 'c2');
      expect(ids(e.continuation), ['c1', 'c3']);
    });

    test('indeks basi → jatuh ke pencarian kunci di seksi yang sama', () {
      final e = QueueEngine();
      e.manual = [t('m1'), t('m2'), t('m3')];
      final got = e.extractQueued('manual', 0, t('m3').key);
      expect(got!.id, 'm3');
      expect(ids(e.manual), ['m1', 'm2']);
    });

    test('kunci tak ada / seksi tak dikenal → null, daftar utuh', () {
      final e = QueueEngine();
      e.autoplay = [t('a1')];
      expect(e.extractQueued('autoplay', 0, t('nope').key), isNull);
      expect(e.extractQueued('aneh', 0, t('a1').key), isNull);
      expect(ids(e.autoplay), ['a1']);
    });

    test('komposisi Putar Berikutnya: AUTO → kepala Berikutnya, tanpa duplikat',
        () {
      final e = QueueEngine();
      e.manual = [t('m1')];
      e.autoplay = [t('a1'), t('a2')];
      final moved = e.extractQueued('autoplay', 1, t('a2').key)!;
      e.enqueueNext(moved);
      expect(ids(e.manual), ['a2', 'm1']);
      expect(ids(e.autoplay), ['a1']);
      expect(e.effectiveQueue.length, 3, reason: 'pindah, bukan menyalin');
    });

    test('komposisi Tambah ke Antrian: Lanjutan → ekor Berikutnya', () {
      final e = QueueEngine();
      e.manual = [t('m1')];
      e.continuation = [t('c1'), t('c2')];
      final moved = e.extractQueued('continuation', 0, t('c1').key)!;
      e.enqueueLater(moved);
      expect(ids(e.manual), ['m1', 'c1']);
      expect(ids(e.continuation), ['c2']);
    });
  });

  group('LibraryController massal (Butir 1 & 2)', () {
    late AppDb db;
    late LibraryController lib;

    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });

    setUp(() async {
      db = AppDb();
      await db.openAt(':memory:');
      lib = LibraryController(db);
      await lib.load();
    });

    test('saveAllToCollection: yang sudah tersimpan dilewati, hitungan jujur',
        () async {
      expect(await lib.saveAllToCollection([t('s1'), t('s2')]), 2);
      expect(lib.isLiked(t('s1').key), isTrue);
      expect(await lib.saveAllToCollection([t('s1'), t('s3')]), 1,
          reason: 'hanya s3 yang baru');
      expect(await lib.saveAllToCollection([t('s1'), t('s2'), t('s3')]), 0);
    });

    test('addAllToPlaylist: duplikat dilewati, hitungan = yang benar masuk',
        () async {
      final id = await lib.createPlaylist('Campuran');
      expect(await lib.addAllToPlaylist(id, [t('p1'), t('p2')]), 2);
      expect(await lib.addAllToPlaylist(id, [t('p1'), t('p3')]), 1);
      final tracks = await db.playlistTracks(id);
      expect(ids(tracks), ['p1', 'p2', 'p3']);
    });
  });
}
