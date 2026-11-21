import 'dart:io';

import 'package:clai/domain/models.dart';
import 'package:clai/player/queue_engine.dart';
import 'package:clai/player/smart_shuffle.dart';
import 'package:clai/services/download_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ronde 8066 — regresi Smart Shuffle no-op (temuan terverifikasi
/// 15 Nov 2026: saklar ON tidak mengubah Up Next maupun urutan putar,
/// di Antrean maupun Putar Otomatis) + minor 8064-b (ringkasan Unduhan
/// terbaca "0 lagu" selama unduhan berjalan).
///
/// Akar terbukti dari pembacaan kode:
/// 1. Cakupan mesin: applySmartShuffle hanya mengurut ulang Lanjutan.
///    Pada antrean berbentuk Putar Otomatis (konteks satu trek + isi
///    ulang) Lanjutan kosong → sakelar no-op total, tampilan & putaran.
/// 2. Handler: setSmartShuffle adalah satu-satunya mutasi antrean yang
///    tidak memanggil _syncTailAfterMutation — sumber gabungan tidak
///    pernah menerima urutan cerdas, jadi urutan putar sebenarnya tetap
///    urutan lama (dibuktikan struktural di sini; sisi pemutarnya
///    dibuktikan di bench emulator).
///
/// Kontrak yang dijaga: himpunan tiap seksi tidak berubah, tidak ada
/// lagu baru, manual (L-03) tidak disentuh, mematikan mode
/// mengembalikan urutan alami pra-cerdas.
Track t(String id, String artist) => Track(
      key: TrackKey('ytmusic', id),
      title: 'Lagu $id',
      artistNames: artist,
      duration: const Duration(minutes: 3),
      playableRef: id,
    );

List<String> ids(List<Track> l) => l.map((x) => x.id).toList();

void main() {
  group('Smart Shuffle 8066 — cakupan antrean efektif', () {
    test('antrean bentuk Putar Otomatis: sakelar bukan no-op lagi', () {
      final e = QueueEngine();
      e.current = t('0', 'X');
      e.autoplay = [t('1', 'D'), t('2', 'D'), t('3', 'E'), t('4', 'F')];
      final before = ids(e.autoplay);
      e.applySmartShuffle();
      expect(e.autoplay.map((x) => x.id).toSet(), before.toSet(),
          reason: 'himpunan tidak berubah');
      expect(hasAdjacentSameArtist(e.autoplay), isFalse,
          reason: 'gugus artis yang sama tersebar');
      expect(ids(e.autoplay), isNot(before),
          reason: 'urutan sungguh berubah (dulu: identik)');
    });

    test('lanjutan + autoplay terurut cerdas; manual utuh & tak bergeser',
        () {
      final e = QueueEngine();
      e.current = t('0', 'X');
      e.manual = [t('m1', 'M'), t('m2', 'M')];
      e.continuation = [t('1', 'A'), t('2', 'A'), t('3', 'B'), t('4', 'C')];
      e.autoplay = [t('5', 'D'), t('6', 'D'), t('7', 'E'), t('8', 'F')];
      final effBefore = e.effectiveQueue.map((x) => x.key).toSet();
      e.applySmartShuffle();
      expect(ids(e.manual), ['m1', 'm2'],
          reason: 'L-03: manual milik pengguna, tidak disentuh');
      expect(e.continuation.map((x) => x.id).toSet(), {'1', '2', '3', '4'});
      expect(e.autoplay.map((x) => x.id).toSet(), {'5', '6', '7', '8'});
      expect(e.effectiveQueue.map((x) => x.key).toSet(), effBefore,
          reason: 'urutan putar efektif: himpunan sama, tanpa lagu baru');
      expect(hasAdjacentSameArtist(e.continuation), isFalse);
      expect(hasAdjacentSameArtist(e.autoplay), isFalse);
    });

    test('mode mati sejak awal: playContext tetap berurutan (penjaga)', () {
      final e = QueueEngine();
      final ctx = [t('1', 'A'), t('2', 'B'), t('3', 'A'), t('4', 'C')];
      e.playContext(
          PlayContext(kind: 'album', label: 'Al', tracks: ctx), 0);
      expect(ids(e.continuation), ['2', '3', '4']);
    });

    test('playContext mode smart dari awal: lanjutan cerdas, '
        'mematikan mode mengembalikan urutan konteks', () {
      final e = QueueEngine();
      e.shuffle = ShuffleMode.smart;
      final ctx = [
        t('1', 'A'),
        t('2', 'A'),
        t('3', 'A'),
        t('4', 'B'),
        t('5', 'C'),
        t('6', 'D'),
      ];
      e.playContext(
          PlayContext(kind: 'album', label: 'Al', tracks: ctx), 0);
      expect(e.current!.id, '1');
      expect(hasAdjacentSameArtist(e.continuation), isFalse,
          reason: 'lanjutan terurut cerdas sejak konteks mulai');
      e.restoreSmartShuffleOrder();
      expect(ids(e.continuation), ['2', '3', '4', '5', '6'],
          reason: 'OFF mengembalikan urutan alami konteks');
    });
  });

  group('Smart Shuffle 8066 — pulih urutan alami saat OFF', () {
    test('urutan persis kembali di kedua seksi; trek terkonsumsi hilang '
        'dari potret dengan wajar', () {
      final e = QueueEngine();
      e.current = t('0', 'X');
      e.continuation = [
        t('1', 'A'),
        t('2', 'A'),
        t('3', 'B'),
        t('4', 'C'),
        t('5', 'B'),
      ];
      e.autoplay = [t('6', 'D'), t('7', 'D'), t('8', 'E')];
      e.applySmartShuffle();
      // Konsumsi trek pertama lanjutan (putar alami) sebelum OFF:
      final consumed = e.continuation.first;
      e.continuation.removeAt(0);
      e.restoreSmartShuffleOrder();
      final expected = ['1', '2', '3', '4', '5']..remove(consumed.id);
      expect(ids(e.continuation), expected,
          reason: 'penyintas kembali persis ke urutan alami relatifnya');
      expect(ids(e.autoplay), ['6', '7', '8']);
    });

    test('konteks baru menggugurkan potret: OFF tidak membangkitkan '
        'urutan sesi lama', () {
      final e = QueueEngine();
      e.current = t('0', 'X');
      e.continuation = [t('1', 'A'), t('2', 'A'), t('3', 'B')];
      e.applySmartShuffle();
      e.playContext(
          PlayContext(
              kind: 'album',
              label: 'Baru',
              tracks: [t('7', 'P'), t('8', 'Q'), t('9', 'R')]),
          0);
      e.restoreSmartShuffleOrder();
      expect(ids(e.continuation), ['8', '9'],
          reason: 'potret sesi lama tidak boleh membangkitkan urutan lama');
    });

    test('restore tanpa potret adalah no-op yang aman', () {
      final e = QueueEngine();
      e.current = t('0', 'X');
      e.continuation = [t('2', 'B'), t('1', 'A')];
      e.restoreSmartShuffleOrder();
      expect(ids(e.continuation), ['2', '1']);
    });
  });

  group('Smart Shuffle 8066 — isi ulang saat mode menyala', () {
    test('batch baru diurut cerdas di ekornya; antrean lama tak bergeser',
        () {
      final e = QueueEngine();
      e.current = t('0', 'X');
      e.autoplay = [t('1', 'P'), t('2', 'Q')];
      final headBefore = ids(e.autoplay);
      final tailFrom = e.autoplay.length;
      e.appendAutoplay([t('3', 'D'), t('4', 'D'), t('5', 'E'), t('6', 'F')]);
      e.smartOrderAutoplayTail(tailFrom);
      expect(ids(e.autoplay).sublist(0, tailFrom), headBefore,
          reason: 'trek yang sudah antre tidak digeser isi ulang');
      final tail = e.autoplay.sublist(tailFrom);
      expect(tail.map((x) => x.id).toSet(), {'3', '4', '5', '6'});
      expect(hasAdjacentSameArtist(tail), isFalse,
          reason: 'batch baru tiba sudah tersebar');
    });
  });

  group('Smart Shuffle 8066 — struktur handler (rantai ke sumber)', () {
    final handler = File('lib/player/audio_handler.dart').readAsStringSync();

    String bodyOf(String startMarker, [int window = 3200]) {
      final start = handler.indexOf(startMarker);
      expect(start, greaterThanOrEqualTo(0),
          reason: '$startMarker tidak ditemukan');
      return handler.substring(start, start + window);
    }

    test('setSmartShuffle menyinkronkan ekor sumber di KEDUA arah', () {
      final body = bodyOf('Future<void> setSmartShuffle');
      expect(body, contains('engine.applySmartShuffle();'));
      expect(body, contains('engine.restoreSmartShuffleOrder();'),
          reason: 'OFF wajib memulihkan urutan alami');
      // 8067: struktur berubah — satu panggilan sinkronisasi TANPA
      // SYARAT sesudah cabang if/else (bukan satu per cabang), dan
      // penerbitan UI kini mendahuluinya. Kontraknya tetap: bedah
      // ekor berjalan untuk ON dan OFF.
      final syncAt = body.indexOf('await _syncTailAfterMutation(');
      expect(syncAt, greaterThanOrEqualTo(0),
          reason: 'sinkronisasi sumber wajib ada — inilah rantai '
              'yang putus sebelum 8066');
      expect(syncAt,
          greaterThan(body.indexOf('engine.applySmartShuffle();')));
      expect(syncAt,
          greaterThan(body.indexOf('engine.restoreSmartShuffleOrder();')),
          reason: 'sinkronisasi berada sesudah kedua cabang → '
              'berjalan untuk ON dan OFF');
    });

    test('kedua jalur isi ulang mengurut cerdas ekor batch saat smart',
        () {
      expect('smartOrderAutoplayTail(tailFrom)'.allMatches(handler).length,
          2,
          reason: 'isi ulang daring + luring sama-sama menerapkan');
    });
  });

  group('Ringkasan unduhan 8066 (minor 8064-b)', () {
    DownloadItemState item(String id, DownloadStatus s,
            {int? total, int done = 0}) =>
        DownloadItemState(
          track: t(id, 'A'),
          status: s,
          bytesTotal: total,
          bytesDone: done,
          quality: 'normal',
        );

    test('kosong → semua nol', () {
      final s = downloadsSummaryOf(const []);
      expect(s.done, 0);
      expect(s.active, 0);
      expect(s.doneBytes, 0);
    });

    test('unduhan pertama sedang berjalan: bukan "0 lagu" yang bisu', () {
      final s = downloadsSummaryOf([
        item('1', DownloadStatus.downloading, total: 1000, done: 400),
      ]);
      expect(s.done, 0);
      expect(s.active, 1,
          reason: 'unduhan berjalan dilaporkan terpisah, tidak disembunyikan');
      expect(s.doneBytes, 0,
          reason: 'byte di perangkat hanya dari yang selesai');
    });

    test('selesai dihitung + byte-nya; antre/terjeda aktif; '
        'gagal & rusak tidak dihitung', () {
      final s = downloadsSummaryOf([
        item('1', DownloadStatus.done, total: 5000, done: 5000),
        item('2', DownloadStatus.done, done: 700), // total tak diketahui
        item('3', DownloadStatus.queued),
        item('4', DownloadStatus.paused, total: 900, done: 100),
        item('5', DownloadStatus.failed),
        item('6', DownloadStatus.corrupt),
      ]);
      expect(s.done, 2);
      expect(s.active, 2);
      expect(s.doneBytes, 5700);
    });
  });
}
