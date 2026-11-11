import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:clai/data/app_db.dart';
import 'package:clai/domain/models.dart';
import 'package:clai/player/audio_handler.dart';
import 'package:clai/player/queue_engine.dart';
import 'package:clai/player/session_coherence.dart';

/// Ronde Bug Notifikasi (2026-11-04): pengerasan di balik notifikasi polos
/// "Clai sedang berjalan" — pengawas koherensi sesi, pengumpulan kunci
/// snapshot yang defensif, dan snapshot DB yang toleran korup + bisa dibuang.
void main() {
  group('SessionCoherenceWatchdog — niat tanpa sumber', () {
    final t0 = DateTime(2026, 11, 4, 11, 0, 0);
    SessionCoherenceWatchdog w = SessionCoherenceWatchdog();
    setUp(() => w = SessionCoherenceWatchdog());

    CoherenceFault feedAt(int secs,
            {bool intent = true,
            bool source = false,
            bool idle = true,
            int pos = 0}) =>
        w.feed(
          intentPlaying: intent,
          hasSource: source,
          processingIdle: idle,
          positionMs: pos,
          now: t0.add(Duration(seconds: secs)),
        );

    test('meledak sekali setelah >4 dtk, lalu diam sampai episode berakhir',
        () {
      expect(feedAt(0), CoherenceFault.none);
      expect(feedAt(2), CoherenceFault.none);
      expect(feedAt(4), CoherenceFault.none);
      expect(feedAt(5), CoherenceFault.sourcelessIntent);
      expect(feedAt(6), CoherenceFault.none);
      expect(feedAt(30), CoherenceFault.none);
      // Episode baru setelah niat mati: boleh meledak lagi.
      expect(feedAt(31, intent: false), CoherenceFault.none);
      expect(feedAt(32), CoherenceFault.none);
      expect(feedAt(37), CoherenceFault.sourcelessIntent);
    });

    test('tidak meledak saat buffering/loading (proses bukan idle)', () {
      expect(feedAt(0, idle: false), CoherenceFault.none);
      expect(feedAt(60, idle: false), CoherenceFault.none);
    });

    test('tidak meledak saat niat mati', () {
      expect(feedAt(0, intent: false), CoherenceFault.none);
      expect(feedAt(60, intent: false), CoherenceFault.none);
    });
  });

  group('SessionCoherenceWatchdog — idle macet dengan sumber', () {
    final t0 = DateTime(2026, 11, 4, 11, 0, 0);
    SessionCoherenceWatchdog w = SessionCoherenceWatchdog();
    setUp(() => w = SessionCoherenceWatchdog());

    CoherenceFault feedAt(int secs, {int pos = 5000, bool idle = true}) =>
        w.feed(
          intentPlaying: true,
          hasSource: true,
          processingIdle: idle,
          positionMs: pos,
          now: t0.add(Duration(seconds: secs)),
        );

    test('meledak sekali setelah >10 dtk posisi membeku; posisi maju mereset',
        () {
      expect(feedAt(0), CoherenceFault.none);
      expect(feedAt(9), CoherenceFault.none);
      expect(feedAt(11), CoherenceFault.stuckIdle);
      expect(feedAt(12), CoherenceFault.none);
      expect(feedAt(13, pos: 6000), CoherenceFault.none);
      expect(feedAt(24, pos: 6000), CoherenceFault.stuckIdle);
    });

    test('keadaan selain idle tidak pernah dianggap macet', () {
      expect(feedAt(0, idle: false), CoherenceFault.none);
      expect(feedAt(99, idle: false), CoherenceFault.none);
    });
  });

  group('collectSnapshotKeys — defensif terhadap entri cacat', () {
    test('kunci valid terkumpul dari semua seksi + currentRef', () {
      final keys = collectSnapshotKeys({
        'seeds': [
          {'p': 'ytmusic', 'i': 'A'},
        ],
        'manual': [
          {'p': 'ytmusic', 'i': 'B'},
        ],
        'continuation': const [],
        'autoplay': const [],
        'played': [
          {'p': 'ytmusic', 'i': 'C'},
        ],
        'currentRef': 'ytmusic|A',
      });
      expect(
        keys,
        {
          TrackKey('ytmusic', 'A'),
          TrackKey('ytmusic', 'B'),
          TrackKey('ytmusic', 'C'),
        },
      );
    });

    test('entri tanpa i/p, entri bukan Map, seksi bukan List: dilewati',
        () {
      final keys = collectSnapshotKeys({
        'seeds': [
          {'p': 'ytmusic'}, // tanpa 'i' — dulu melempar TypeError
          {'i': 'X'}, // tanpa 'p'
          'bukan-map',
          {'p': 'ytmusic', 'i': 'SELAMAT'},
        ],
        'manual': 'bukan-list',
        'continuation': null,
        'autoplay': const [],
        'currentRef': 'tanpa-pemisah',
      });
      expect(keys, {TrackKey('ytmusic', 'SELAMAT')});
    });

    test('currentRef dengan | di dalam id terbaca utuh', () {
      final keys = collectSnapshotKeys({
        'seeds': const [],
        'manual': const [],
        'continuation': const [],
        'autoplay': const [],
        'currentRef': 'ytmusic|id|dengan|pemisah',
      });
      expect(keys, {TrackKey('ytmusic', 'id|dengan|pemisah')});
    });
  });

  group('QueueEngine.restore — entri cacat dilewati, bukan melempar', () {
    test('snapshot manual tanpa i: restore selamat, seksi sehat utuh', () {
      Track mk(String id) => Track(
            key: TrackKey('ytmusic', id),
            title: 'T$id',
            artistNames: 'A',
            playableRef: id,
            duration: const Duration(minutes: 3),
          );
      final a = mk('A');
      final e = QueueEngine();
      // Map persis seperti hasil loadQueueSnapshot atas baris beracun P3.
      e.restore(
        {
          'seeds': [
            {'p': 'ytmusic', 'i': 'A'},
          ],
          'manual': [
            {'p': 'ytmusic'}, // tanpa 'i' — dulu TypeError di _keysOf
            {'p': 'ytmusic', 'i': 'A'},
          ],
          'continuation': const [],
          'autoplay': const [],
          'played': const [],
          'currentRef': 'ytmusic|A',
          'contextKind': 'playlist',
          'contextId': null,
          'contextLabel': 'Uji',
          'signals': const {},
        },
        {a.key: a},
      );
      expect(e.current?.key, a.key);
      expect(e.manual.map((t) => t.key), [a.key]);
    });
  });

  group('snapshot DB — toleran korup + deleteQueueSnapshot', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    test('kolom JSON korup jatuh ke kosong; snapshot bisa dibuang', () async {
      final dir = await Directory.systemTemp.createTemp('snap');
      final appDb = AppDb();
      final d = await appDb.openAt('${dir.path}/t.db');
      await appDb.saveQueueSnapshot({
        'contextKind': 'playlist',
        'contextId': 'PLx',
        'contextLabel': 'Uji',
        'seeds': [
          {'p': 'ytmusic', 'i': 'A'},
        ],
        'manual': [
          {'p': 'ytmusic', 'i': 'B'},
        ],
        'continuation': const [],
        'autoplay': const [],
        'currentRef': 'ytmusic|A',
        'positionMs': 1200,
        'shuffle': 'off',
        'repeat': 'off',
        'autoplayEnabled': true,
        'signals': const {},
        'played': const [],
        'volume': 0.8,
      });
      final ok = await appDb.loadQueueSnapshot();
      expect(ok, isNotNull);
      expect((ok!['seeds'] as List).length, 1);
      expect((ok['manual'] as List).length, 1);

      // Rusak SATU kolom: kolom lain harus tetap terbaca, tanpa lempar.
      await d.execute(
          "update queue_snapshots set manual_json='{korup' where id=1");
      final rusak = await appDb.loadQueueSnapshot();
      expect(rusak, isNotNull);
      expect(rusak!['manual'], isEmpty);
      expect((rusak['seeds'] as List).length, 1);
      expect(rusak['currentRef'], 'ytmusic|A');

      // Buang snapshot: muat berikutnya null (mulai bersih).
      await appDb.deleteQueueSnapshot();
      expect(await appDb.loadQueueSnapshot(), isNull);
      await d.close();
    });
  });
}
