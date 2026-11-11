import 'dart:io';

import 'package:clai/data/app_db.dart';
import 'package:clai/domain/models.dart';
import 'package:clai/services/waveform.dart';
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

  test('pref null-safe & type-safe (perbaikan crash Sleep Resume)', () async {
    final db = AppDb();
    await db.openAt(':memory:');
    // Nilai yang disimpan SAH berupa null (setPref('sleep.last', null)
    // saat simpanan dibuang): cast lama `as T` melempar
    // "type 'Null' is not a subtype of type 'String'" — crash berulang
    // kartu Sleep Resume di logcat ronde 8038.
    await db.setPref('sleep.last', null);
    expect(await db.pref<String>('sleep.last'), isNull);
    // Tipe tak cocok dibaca sebagai "tidak ada", bukan lemparan.
    await db.setPref('campuran', 'teks');
    expect(await db.pref<String>('campuran'), 'teks');
    expect(await db.pref<int>('campuran'), isNull);
    await db.setPref('angka', 42);
    expect(await db.pref<int>('angka'), 42);
    expect(await db.pref<bool>('angka'), isNull);
    await db.close();
  });

  test('migrasi v4 → v5: tabel track_waveforms lahir, data lama utuh',
      () async {
    final dir = await Directory.systemTemp.createTemp('clai_mig');
    final path = '${dir.path}/v4.db';
    // Bangun berkas skema v4 minimal (cukup user_prefs + satu isinya).
    final v4 = await databaseFactoryFfi.openDatabase(path,
        options: OpenDatabaseOptions(
          version: 4,
          onCreate: (d, v) async {
            await d.execute(
                'CREATE TABLE user_prefs (key TEXT PRIMARY KEY, value_json TEXT NOT NULL, schema_v INTEGER NOT NULL)');
          },
        ));
    await v4.insert('user_prefs',
        {'key': 'ui.themeDynamic', 'value_json': 'false', 'schema_v': 1});
    await v4.close();
    // Buka lewat AppDb (skema v5): migrasi berjalan, pref lama terbaca,
    // tabel baru bisa dipakai.
    final db = AppDb();
    final d = await db.openAt(path);
    expect(await d.getVersion(), 5);
    expect(await db.pref<bool>('ui.themeDynamic'), isFalse);
    expect(await db.waveformFor(const TrackKey('ytmusic', 'x')), isNull);
    await db.saveWaveform(const TrackKey('ytmusic', 'x'),
        WaveformData.empty.withSample(0, -20));
    expect(
        (await db.waveformFor(const TrackKey('ytmusic', 'x')))
            ?.buckets[0],
        closeTo(-20, 0.001));
    await db.close();
    await dir.delete(recursive: true);
  });
}
