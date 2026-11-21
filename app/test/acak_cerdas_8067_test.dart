import 'dart:io';

import 'package:clai/domain/models.dart';
import 'package:clai/player/queue_engine.dart';
import 'package:clai/player/smart_shuffle.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ronde 8067 — vonis HP 20 Nov 2026 atas staging 8066: "Smart Shuffle
/// MASIH belum berfungsi, dan respons saklar on/off-nya LAMBAT."
/// Bukti emulator 8066 lulus dengan SESI BERSIH (saklar OFF dulu,
/// playContext segar menanam potret alami). Vonis perangkat mengalahkan
/// bangku: yang tidak dicakup bukti bersih adalah KEADAAN TERBAWA —
/// sesi yang dipulihkan (restore) dan snapshot warisan pasang-timpa.
///
/// Akar terbukti dari pembacaan kode:
/// 1. `QueueEngine.restore` mengosongkan potret urutan alami
///    (_naturalContinuation/_naturalAutoplay = null) dan `snapshot()`
///    tidak pernah menyerialkannya. Sesudah SETIAP start dingin dengan
///    sesi tersimpan: (a) mode cerdas pulih dari snapshot tetapi urutan
///    cerdas TIDAK PERNAH diterapkan ke antrean pulih (tak ada
///    applySmartShuffle di jalur restore/bootstrap) — saklar terbaca
///    ON, urutan tetap alami; (b) ketukan OFF memanggil
///    restoreSmartShuffleOrder yang no-op senyap karena potret null —
///    antrean yang tersimpan dalam urutan cerdas tidak bisa kembali.
/// 2. `setShuffleMode(none)` (tombol acak Player / sistem, termasuk
///    ketukan "matikan mode aktif" pada mode cerdas) hanya membalik
///    flag engine: urutan cerdas tertinggal, potret tertinggal, pref
///    `playback.smartShuffle` tetap menyala — kedua saklar berselisih
///    dan OFF berikutnya di setSmartShuffle terhalang pagar
///    `engine.shuffle == ShuffleMode.smart`.
/// 3. Latensi saklar: setSmartShuffle menunggu likedKeys + playCounts
///    (GROUP BY atas seluruh playback_events) di KEDUA arah, lalu
///    bedah ekor sumber (hingga ±60 trek, per-anak await), dan
///    _emitQueue — satu-satunya pemicu gambar ulang saklar lembar
///    Antrean — baru berjalan di AKHIR. Saklar menunggu seluruh rantai.
Track t(String id, String artist) => Track(
      key: TrackKey('ytmusic', id),
      title: 'Lagu $id',
      artistNames: artist,
      duration: const Duration(minutes: 3),
      playableRef: id,
    );

List<String> ids(List<Track> l) => l.map((x) => x.id).toList();

Map<TrackKey, Track> byKeyOf(List<Track> tracks) =>
    {for (final x in tracks) x.key: x};

/// Snapshot persis bentuk keluaran 8066 (TANPA kolom potret alami —
/// kolom itu belum ada): kunci direferensikan {'p','i'} seperti
/// serialisasi L-16.
Map<String, Object?> legacySnap({
  required List<Track> seeds,
  required List<Track> continuation,
  required List<Track> autoplay,
  required Track current,
  required String shuffle,
}) =>
    {
      'contextKind': 'album',
      'contextId': 'x',
      'contextLabel': 'Warisan',
      'seeds': [
        for (final x in seeds) {'p': 'ytmusic', 'i': x.id},
      ],
      'manual': <Object?>[],
      'continuation': [
        for (final x in continuation) {'p': 'ytmusic', 'i': x.id},
      ],
      'autoplay': [
        for (final x in autoplay) {'p': 'ytmusic', 'i': x.id},
      ],
      'played': <Object?>[],
      'currentRef': 'ytmusic|${current.id}',
      'positionMs': 0,
      'shuffle': shuffle,
      'repeat': 'off',
      'autoplayEnabled': true,
    };

void main() {
  group('Smart Shuffle 8067 — restore sesi (keadaan terbawa)', () {
    test('pulih dari snapshot sendiri: OFF tetap bekerja sesudah '
        'start dingin (potret alami ikut terserialkan)', () {
      final natural = [
        t('1', 'A'),
        t('2', 'A'),
        t('3', 'B'),
        t('4', 'C'),
        t('5', 'B'),
      ];
      final auto = [t('6', 'D'), t('7', 'D'), t('8', 'E')];
      final cur = t('0', 'X');
      final e = QueueEngine();
      e.current = cur;
      e.shuffle = ShuffleMode.smart;
      e.continuation = List.of(natural);
      e.autoplay = List.of(auto);
      e.applySmartShuffle();
      expect(hasAdjacentSameArtist(e.continuation), isFalse,
          reason: 'prasyarat: sesi hidup memang terurut cerdas');

      final snap = e.snapshot(positionMs: 0);
      final e2 = QueueEngine();
      e2.restore(snap, byKeyOf([cur, ...natural, ...auto]));
      expect(e2.shuffle, ShuffleMode.smart,
          reason: 'mode cerdas pulih dari snapshot');
      e2.restoreSmartShuffleOrder();
      expect(ids(e2.continuation), ['1', '2', '3', '4', '5'],
          reason: 'OFF sesudah pulih mengembalikan urutan alami '
              'pra-cerdas (8066: potret null → no-op, urutan cerdas '
              'tertinggal permanen)');
      expect(ids(e2.autoplay), ['6', '7', '8']);
    });

    test('snapshot yang dipulihkan TIDAK diacak ulang: urutan cerdas '
        'tersimpan dipertahankan persis (penjaga cabang persisten)',
        () {
      final natural = [
        t('1', 'A'),
        t('2', 'A'),
        t('3', 'B'),
        t('4', 'C'),
        t('5', 'B'),
      ];
      final cur = t('0', 'X');
      final e = QueueEngine();
      e.current = cur;
      e.shuffle = ShuffleMode.smart;
      e.continuation = List.of(natural);
      e.applySmartShuffle();
      final appliedOrder = ids(e.continuation);
      final snap = e.snapshot(positionMs: 0);
      final e2 = QueueEngine();
      e2.restore(snap, byKeyOf([cur, ...natural]));
      expect(ids(e2.continuation), appliedOrder,
          reason: 'restore mempertahankan urutan yang ditinggalkan '
              'sesi asal, bukan mengacaknya lagi');
    });

    test('snapshot warisan 8064/8066 (mode cerdas, urutan ALAMI, '
        'tanpa kolom potret): pulih langsung menerapkan urutan '
        'cerdas, OFF mengembalikan urutan warisan persis', () {
      final cur = t('0', 'X');
      final auto = [t('1', 'D'), t('2', 'D'), t('3', 'E'), t('4', 'F')];
      final snap = legacySnap(
        seeds: [cur],
        continuation: const [],
        autoplay: auto,
        current: cur,
        shuffle: 'smart',
      );
      final e = QueueEngine();
      e.restore(snap, byKeyOf([cur, ...auto]));
      expect(e.shuffle, ShuffleMode.smart);
      expect(e.autoplay.map((x) => x.id).toSet(), {'1', '2', '3', '4'},
          reason: 'himpunan tidak berubah oleh pemulihan');
      expect(hasAdjacentSameArtist(e.autoplay), isFalse,
          reason: 'mode cerdas yang pulih harus BERLAKU pada antrean '
              'pulih (8066: tak ada penerapan di jalur restore — '
              'saklar terbaca ON, urutan tetap alami)');
      e.restoreSmartShuffleOrder();
      expect(ids(e.autoplay), ['1', '2', '3', '4'],
          reason: 'OFF mengembalikan urutan warisan pra-cerdas');
    });

    test('snapshot warisan (mode cerdas, urutan CERDAS terbawa): '
        'potret tertanam saat pulih — snapshot berikutnya MEMUAT '
        'kolom potret, siklus ON→OFF konsisten', () {
      final cur = t('0', 'X');
      // Urutan yang ditinggalkan sesi 8066 (sudah terurut cerdas):
      final carried = [t('3', 'E'), t('1', 'D'), t('4', 'F'), t('2', 'D')];
      final snap = legacySnap(
        seeds: [cur],
        continuation: const [],
        autoplay: carried,
        current: cur,
        shuffle: 'smart',
      );
      final e = QueueEngine();
      e.restore(snap, byKeyOf([cur, ...carried]));
      final snap2 = e.snapshot(positionMs: 0);
      expect(snap2.containsKey('naturalAutoplay'), isTrue,
          reason: 'sesudah pulih, potret alami harus ADA dan ikut '
              'terserialkan — kalau tidak, start dingin berikutnya '
              'mengulang lubang yang sama (8066: kolom tak pernah '
              'ditulis)');
      expect(snap2.containsKey('naturalContinuation'), isTrue);
      // Siklus saklar dari keadaan terbawa ini harus konsisten:
      // ON (terapkan dari alas terbawa) lalu OFF kembali ke alas itu.
      e.applySmartShuffle();
      e.restoreSmartShuffleOrder();
      expect(ids(e.autoplay), ['3', '1', '4', '2'],
          reason: 'OFF kembali ke urutan terbawa yang ditanam '
              'sebagai alas alami sesi pulih');
    });

    test('snapshot warisan mode mati: restore tidak mengacak apa '
        'pun dan potret tetap kosong (penjaga)', () {
      final cur = t('0', 'X');
      final cont = [t('1', 'A'), t('2', 'A'), t('3', 'B')];
      final snap = legacySnap(
        seeds: [cur, ...cont],
        continuation: cont,
        autoplay: const [],
        current: cur,
        shuffle: 'off',
      );
      final e = QueueEngine();
      e.restore(snap, byKeyOf([cur, ...cont]));
      expect(e.shuffle, ShuffleMode.off);
      expect(ids(e.continuation), ['1', '2', '3'],
          reason: 'mode mati: urutan pulih apa adanya');
      e.restoreSmartShuffleOrder();
      expect(ids(e.continuation), ['1', '2', '3']);
    });
  });

  group('Smart Shuffle 8067 — struktur handler', () {
    final handler = File('lib/player/audio_handler.dart').readAsStringSync();

    String bodyOf(String startMarker, [int window = 2600]) {
      final start = handler.indexOf(startMarker);
      expect(start, greaterThanOrEqualTo(0),
          reason: '$startMarker tidak ditemukan');
      return handler.substring(start, start + window);
    }

    test('setShuffleMode(none) dari mode cerdas memulihkan urutan '
        'dan menulis pref — bukan membalik flag saja', () {
      final body = bodyOf('Future<void> setShuffleMode', 1800);
      expect(body, contains('restoreSmartShuffleOrder'),
          reason: 'mematikan acak dari tombol Player saat mode '
              'cerdas aktif wajib mengembalikan urutan alami '
              '(8066: tertinggal urutan cerdas)');
      expect(body, contains("setPref('playback.smartShuffle', false"),
          reason: 'pref wajib ikut mati — kalau tidak, saklar '
              'Pengaturan (berbasis pref) tetap menyala dan '
              'berselisih dengan lembar Antrean (berbasis engine)');
    });

    test('setSmartShuffle: UI memancarkan keadaan SEBELUM bedah '
        'ekor, dan sinyal selera hanya diambil saat menyalakan', () {
      final body = bodyOf('Future<void> setSmartShuffle');
      final emitAt = body.indexOf('_emitQueue()');
      final syncAt = body.indexOf('_syncTailAfterMutation');
      expect(emitAt, greaterThanOrEqualTo(0));
      expect(syncAt, greaterThanOrEqualTo(0));
      expect(emitAt, lessThan(syncAt),
          reason: 'saklar lembar Antrean menggambar ulang dari '
              'queueStream — emisi harus mendahului sinkronisasi '
              'sumber yang lambat, bukan menunggunya (8066: '
              '_emitQueue di akhir, saklar terasa lambat)');
      final onAt = body.indexOf('if (on)');
      final signalsAt = body.indexOf('playCounts');
      expect(onAt, greaterThanOrEqualTo(0));
      expect(signalsAt, greaterThan(onAt),
          reason: 'likedKeys/playCounts (GROUP BY playback_events) '
              'hanya perlu saat MENYALAKAN — arah OFF tidak boleh '
              'membayarnya (8066: diambil di kedua arah, sebelum '
              'kerja apa pun)');
    });

    test('_restoreSession memuat sinyal selera sebelum restore '
        'mesin (penerapan cerdas di jalur pulih butuh sinyal)', () {
      final body = bodyOf('Future<void> _restoreSession()', 4600);
      final signalsAt = body.indexOf('setSmartSignals');
      final restoreAt = body.indexOf('engine.restore(');
      expect(signalsAt, greaterThanOrEqualTo(0),
          reason: 'restore warisan mode cerdas menerapkan urutan '
              'di dalam engine.restore — sinyal harus sudah '
              'dimuat handler sebelum itu');
      expect(restoreAt, greaterThanOrEqualTo(0));
      expect(signalsAt, lessThan(restoreAt));
    });
  });

  group('Smart Shuffle 8067 — skenario vonis: antrean koleksi statistik',
      () {
    // Bentuk persis jalur "Paling Sering Minggu Ini" di Beranda:
    // home_screen memanggil playTracks(kind: 'search') → playContext
    // dengan seluruh daftar rak. Ketukan saklar dari lembar Antrean
    // harus mengubah urutan continuation TANPA navigasi apa pun —
    // di tingkat mesin itu berarti applySmartShuffle bekerja atas
    // konteks ini, dan OFF memulihkannya persis.
    test('putar dari koleksi statistik → ON mengubah urutan, '
        'OFF memulihkan', () {
      final tracks = <Track>[
        t('b1', 'Michael Bublé'),
        t('s1', 'Sheila On 7'),
        t('b2', 'Michael Bublé'),
        t('b3', 'Michael Bublé'),
        t('s2', 'Sheila On 7'),
        t('b4', 'Michael Bublé'),
        t('j1', 'Jason Mraz'),
        t('b5', 'Michael Bublé'),
        t('s3', 'Sheila On 7'),
        t('j2', 'Jason Mraz'),
        t('b6', 'Michael Bublé'),
        t('s4', 'Sheila On 7'),
      ];
      final e = QueueEngine();
      e.playContext(
        PlayContext(
            kind: 'search',
            label: 'Paling Sering Minggu Ini',
            tracks: tracks),
        0,
      );
      final natural = ids(e.continuation);
      expect(natural.length, 11);
      e.shuffle = ShuffleMode.smart;
      e.applySmartShuffle();
      final smart = ids(e.continuation);
      expect(smart.toSet(), natural.toSet(),
          reason: 'himpunan continuation tidak berubah');
      expect(smart, isNot(natural),
          reason: 'urutan continuation WAJIB berubah saat saklar ON '
              '(vonis HP: diam total)');
      for (var i = 1; i < e.continuation.length; i++) {
        expect(e.continuation[i].artistNames,
            isNot(e.continuation[i - 1].artistNames),
            reason: 'artis sama tidak boleh bersebelahan sesudah '
                'pengurutan cerdas konteks statistik');
      }
      e.shuffle = ShuffleMode.off;
      e.restoreSmartShuffleOrder();
      expect(ids(e.continuation), natural,
          reason: 'OFF memulihkan urutan alami konteks persis');
    });

    test('struktur handler: kegagalan bedah ekor sesudah toggle '
        'dicatat, tidak menelan penerbitan', () {
      final src = File('lib/player/audio_handler.dart').readAsStringSync();
      final start = src.indexOf('Future<void> setSmartShuffle');
      expect(start, greaterThanOrEqualTo(0));
      final body = src.substring(start, start + 2600);
      expect(body,
          contains("Observability.instance.log('acak-sinkron-gagal'"),
          reason: 'bedah ekor yang gagal sesudah toggle wajib masuk '
              'log insiden (Diagnostik) — bukan membekukan UI dalam '
              'diam');
      final emitAt = body.indexOf('_emitQueue();');
      final catchAt = body.indexOf('acak-sinkron-gagal');
      expect(emitAt, greaterThanOrEqualTo(0));
      expect(catchAt, greaterThan(emitAt),
          reason: 'penjaga kegagalan membungkus langkah SESUDAH '
              'penerbitan, bukan sebelumnya');
    });
  });
}
