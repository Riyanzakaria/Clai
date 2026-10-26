import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:clai/data/app_db.dart';
import 'package:clai/domain/models.dart';

/// F2.5 butir 1 di tingkat DB + regresi cacat laten rak artis:
/// (a) peringkat rak mengikuti skor campuran (baru-panas menyalip
///     lama-kuat; lama-kuat tidak tenggelam);
/// (b) tracksByArtists WAJIB menemukan trek artis walau pustaka cache
///     melewati 500 baris (dulu pemindaian limit-500 membuatnya kosong).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  Track mk(String id, String title, String artist) => Track(
      key: TrackKey('ytmusic', id),
      title: title,
      artistNames: artist,
      playableRef: id,
      duration: const Duration(minutes: 3));

  test('rak campuran di tingkat DB + trek artis di luar 500 baris pertama',
      () async {
    final dir = await Directory.systemTemp.createTemp('shelves');
    final appDb = AppDb();
    final d = await appDb.openAt('${dir.path}/t.db');
    final now = DateTime.now().millisecondsSinceEpoch;
    const day = 86400000;

    // 600 trek pengisi agar trek sasaran berada DI LUAR 500 baris pertama.
    await appDb.cacheTracks([
      for (var i = 0; i < 600; i++)
        mk('filler$i', 'Filler $i', 'Pengisi $i'),
    ]);
    final lama = mk('VredAgNScOw', 'Teddy Picker', 'Arctic Monkeys');
    final panas = mk('BN4oEK07-dA', "i don't know you anymore", 'sombr');
    await appDb.cacheTracks([lama, panas]);

    Future<void> seed(Track t, int n, int base) async {
      for (var i = 0; i < n; i++) {
        await appDb.logPlayback(t,
            listenedMs: 90000, completed: true, contextKind: 'search');
        await d.execute(
            'update playback_events set started_at = ? where provider_track_id = ? and started_at > ?',
            [base + i * 3600000, t.id, base + i * 3600000 - 3600000]);
      }
    }

    await seed(lama, 40, now - 100 * day); // lama-kuat: hybrid 10.0
    await seed(panas, 15, now - 2 * day); // baru-panas: hybrid ±14.3

    final freq = await appDb.frequentTracks(limit: 10);
    expect(freq.map((t) => t.title).toList(),
        ["i don't know you anymore", 'Teddy Picker']);

    final artists = await appDb.artistPlayCounts(limit: 5);
    expect(artists.first.artistNames, 'sombr');
    expect(artists.first.count, 15);
    expect(artists[1].artistNames, 'Arctic Monkeys');
    expect(artists[1].count, 40);

    // Inti regresi: trek artis teratas ditemukan walau barisnya > 500.
    final topTracks = await appDb.tracksByArtists(['sombr'], limit: 10);
    expect(topTracks.map((t) => t.title), contains("i don't know you anymore"));
    final lamaTracks =
        await appDb.tracksByArtists(['Arctic Monkeys'], limit: 10);
    expect(lamaTracks.map((t) => t.title), contains('Teddy Picker'));

    await appDb.close();
  });
}
