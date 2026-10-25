import 'package:clai/data/app_db.dart';
import 'package:clai/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Track t(String id) => Track(key: TrackKey('ytmusic', id), title: 'Lagu $id',
    artistNames: 'Artis', duration: const Duration(minutes: 2), playableRef: id);

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('skema v1 terbuka; suka & playlist bertahan dalam satu siklus', () async {
    final db = AppDb();
    final d = await db.openAt(':memory:');
    expect(await d.getVersion(), AppDb.schemaVersion);
    await db.setLiked(t('1'), true);
    expect(await db.isLiked(const TrackKey('ytmusic', '1')), isTrue);
    expect((await db.likedTracks()).single.id, '1');
    await db.createPlaylist('pl1', 'Uji');
    expect(await db.addToPlaylist('pl1', t('1')), isTrue);
    expect(await db.addToPlaylist('pl1', t('1')), isFalse, reason: 'duplikat ditolak tanpa izin (PRD 5.7)');
    expect(await db.addToPlaylist('pl1', t('1'), allowDuplicate: true), isTrue);
    expect(await db.playlistCount('pl1'), 2);
    await db.saveQueueSnapshot({'seeds': [], 'manual': [], 'continuation': [], 'autoplay': [], 'positionMs': 0});
    expect(await db.loadQueueSnapshot(), isNotNull);
  });
}
