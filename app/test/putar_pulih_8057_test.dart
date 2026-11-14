import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Ronde 8057 FIX C — regresi cacat Putar pada sesi yang dipulihkan:
/// tekanan Putar tampak mati, lalu putaran menyentak balik ke trek
/// pulih menimpa apa pun yang sudah dimulai pengguna.
///
/// Akar terbukti (audit kode): cabang pulih play() memanggil
/// _buildOrNotify TANPA gen dan TANPA firstOnly — satu-satunya situs
/// pembangunan perintah putar yang seperti itu (jumpTo/playTracks/
/// restoreSleepSession/_previousViaHistory semuanya meneruskan
/// `gen: gen, firstOnly: true`). Akibatnya _buildSource meresolusi
/// jendela penuh (≤60 trek) secara serial sebelum bunyi pertama
/// (Putar tampak mati), dan karena gen == null ketiga penjaga
/// kalah-ganti di _buildSource mati (stillWanted, titik komit,
/// pasca-pasang): bangun yang selesai belakangan memasang jendelanya
/// berjangkar di trek pulih TANPA syarat, menimpa sumber perintah
/// yang lebih baru; playWhenReady selamat dari setAudioSource
/// sehingga trek pulih berbunyi, bahkan di _lastPosition trek lain.
/// _rebuildTail menderita penyakit yang sama (bangun jendela penuh
/// tanpa generasi di semua situsnya) — itulah sebabnya Berikutnya
/// pada pemain tanpa sumber hanya merespons secara kumulatif.
///
/// Perbaikan yang dikunci di sini:
/// (1) cabang pulih play() mengklaim generasi TEPAT sebelum bangun
///     (meniru restoreSleepSession — BUKAN di kepala play(), agar
///     lanjut-di-tempat/interupsi/pola-tekan yang tidak membangun
///     sumber tidak membatalkan pembangunan sah yang sedang terbang),
///     meneruskan gen + firstOnly, berhenti total bila dikalahkan
///     (tanpa pembersihan stop()/buang-cache yang bisa membunuh
///     sumber pemenang), diperiksa ulang sesudah seek, dan mengisi
///     sisa jendela di latar lewat _extendSourceToQueue;
/// (2) _rebuildTail menerima gen/firstOnly dan melaporkan terkomit
///     (TRUE) vs dikalahkan/tidak membangun (FALSE) — situs perintah
///     (skipToNext) mengklaim generasi baru, situs otomatis/mutasi/
///     pemulihan meneruskan generasi berjalan tanpa klaim, dan
///     firstOnly tidak dipakai di situs _rebuildTail mana pun karena
///     maksud bangunnya adalah mematerialkan/memulihkan EKOR jendela.
///
/// Handler konkret tidak bisa dibangun di unit test (konstruktornya
/// menyentuh kanal platform AudioSession/just_audio — kendala yang
/// sama dicatat putusan_desain_test & antrean_kembali_8055_test),
/// jadi kontraknya diverifikasi pada KABEL SUMBER dengan pola sapuan
/// yang sama seperti antrean_redesign_8051_test/putusan_desain_test:
/// bila ada yang mengembalikan situs mana pun ke keadaan tanpa
/// generasi, suite ini yang berteriak. Perilaku hidupnya (ketuk →
/// bunyi pada sesi pulih, tanpa sentak-balik) dibuktikan di bench
/// emulator dengan koreografi yang sama.
void main() {
  final src = File('lib/player/audio_handler.dart').readAsStringSync();

  /// Badan fungsi: dari awal [startMarker] sampai awal [endMarker].
  /// Dipanggil juga pada taraf deklarasi grup (di luar badan test),
  /// jadi penanda hilang dilempar sebagai StateError, bukan expect.
  String bodyBetween(String startMarker, String endMarker) {
    final start = src.indexOf(startMarker);
    if (start < 0) throw StateError('$startMarker tidak ditemukan');
    final end = src.indexOf(endMarker, start);
    if (end <= start) {
      throw StateError('$endMarker tidak ditemukan sesudah $startMarker');
    }
    return src.substring(start, end);
  }

  int count(String haystack, String needle) =>
      haystack.split(needle).length - 1;

  group('prasyarat: penjaga kalah-ganti _buildSource utuh (Ronde 8057)',
      () {
    final build = bodyBetween(
        'Future<void> _buildSource({', 'Future<void> _maybeExtendWindow');

    test('stillWanted diteruskan ke resolusi hanya bila bergenerasi', () {
      expect(build,
          contains('stillWanted: gen == null ? null : () => gen == _playGen'));
    });

    test('titik komit: generasi usang gugur SEBELUM menyentuh pemutar', () {
      expect(build,
          contains('if (gen != null && gen != _playGen) throw const _Superseded();'));
    });

    test('penjaga pasca-pasang: generasi usang tidak menyalakan putar', () {
      expect(build, contains('if (gen != null && gen != _playGen)'));
      // Tepat dua penjaga != : titik komit (lempar _Superseded) +
      // pasca-pasang (kembali tanpa play). stillWanted membaca arah
      // sebaliknya (gen == _playGen) di dalam closure resolusi.
      expect(count(build, 'gen != _playGen'), 2,
          reason: 'titik komit + pasca-pasang, tidak lebih tidak kurang');
      expect(count(build, 'gen == _playGen'), greaterThanOrEqualTo(1),
          reason: 'closure stillWanted membaca generasi berjalan');
    });

    test('_buildOrNotify meneruskan gen & firstOnly apa adanya', () {
      final notify =
          bodyBetween('Future<bool> _buildOrNotify({', 'Future<void> _buildSource({');
      expect(notify, contains('gen: gen'));
      expect(notify, contains('firstOnly: firstOnly'));
      // Kelas batal tetap dilaporkan FALSE secara senyap, bukan insiden.
      expect(notify, contains('if (e is _Superseded) return false;'));
    });
  });

  group('pola saudara yang dicerminkan tetap utuh (Ronde 8057)', () {
    test('jumpTo: klaim + gen + firstOnly', () {
      // Penanda tanda tangan diperbarui Ronde 8063 (parameter
      // preserveSleepTimer ditambahkan); maksud tes tidak berubah.
      final body = bodyBetween(
          'Future<void> jumpTo(TrackKey k, {bool preserveSleepTimer = false}) {',
          'Future<void> setAutoplaySession');
      expect(body, contains('final gen = ++_playGen;'));
      expect(body, contains('gen: gen'));
      expect(body, contains('firstOnly: true'));
    });

    test('playTracks: klaim + gen + firstOnly', () {
      final body =
          bodyBetween('Future<void> playTracks(', 'Future<void> startRadio(');
      expect(body, contains('final gen = ++_playGen;'));
      expect(body, contains('gen: gen'));
      expect(body, contains('firstOnly: true'));
    });

    test('restoreSleepSession: klaim tepat sebelum bangun + gen + firstOnly',
        () {
      final body = bodyBetween('Future<void> restoreSleepSession',
          'void syncShuffleState()');
      expect(body, contains('final gen = ++_playGen;'));
      expect(body, contains('gen: gen'));
      expect(body, contains('firstOnly: true'));
    });
  });

  group('cabang pulih play() — FIX C inti (Ronde 8057)', () {
    final play =
        bodyBetween('Future<void> play() async {', 'Future<void> _pauseFromSystem');
    final callAt = play.indexOf("what: 'sesi yang dipulihkan'");

    test('situs pembangunan pulih ditemukan di dalam play()', () {
      expect(callAt, greaterThan(-1),
          reason: "panggilan 'sesi yang dipulihkan' harus ada di play()");
    });

    test('pembangunan pulih meneruskan gen + firstOnly', () {
      final callWindow = play.substring(callAt, callAt + 220);
      expect(callWindow, contains('gen: gen'),
          reason: 'tanpa gen, ketiga penjaga kalah-ganti _buildSource mati');
      expect(callWindow, contains('firstOnly: true'),
          reason:
              'tanpa firstOnly, bunyi pertama menunggu resolusi serial ≤60 trek');
    });

    test('generasi diklaim TEPAT sebelum bangun, BUKAN di kepala play()', () {
      final claimAt = play.indexOf('final gen = ++_playGen;');
      expect(claimAt, greaterThan(-1));
      expect(claimAt, lessThan(callAt),
          reason: 'klaim harus mendahului panggilan bangun pulih');
      // Tepat satu klaim di seluruh play(): klaim kedua / klaim di
      // kepala akan membatalkan pembangunan sah yang sedang terbang
      // lewat jalur lanjut-di-tempat, lanjut pasca-interupsi, dan
      // hitungan pola tekan yang tidak membangun sumber sama sekali.
      expect(count(play, '++_playGen'), 1,
          reason: 'play() hanya boleh mengklaim generasi di cabang pulih');
      final emptyGuardAt = play.indexOf('main-putar-tanpa-sesi');
      final resumeGuardAt = play.indexOf('shouldRewindBeforePlay');
      expect(claimAt, greaterThan(emptyGuardAt),
          reason: 'penjaga sesi kosong berjalan sebelum klaim apa pun');
      expect(resumeGuardAt, greaterThan(-1),
          reason: 'penjaga putar-balik Fix A harus tetap ada di play()');
    });

    test('dikalahkan → berhenti SEBELUM pembersihan gagal-total', () {
      final guardAt = play.indexOf('if (gen != _playGen) return;', callAt);
      final cleanupAt =
          play.indexOf('pembangunan sumber sesi pulih gagal total', callAt);
      expect(guardAt, greaterThan(callAt),
          reason: 'penjaga kalah-ganti harus mengikuti panggilan bangun');
      expect(cleanupAt, greaterThan(guardAt),
          reason:
              'stop()/buang-cache pembersihan gagal-total tidak boleh menyentuh '
              'sumber perintah pemenang — penjaga generasi mendahuluinya');
    });

    test('diperiksa ulang sesudah seek & sisa jendela diisi di latar', () {
      expect(count(play, 'if (gen != _playGen) return;'), 2,
          reason: 'satu penjaga sesudah bangun, satu lagi sesudah seek');
      final extendAt = play.indexOf('unawaited(_extendSourceToQueue())', callAt);
      expect(extendAt, greaterThan(callAt),
          reason:
              'firstOnly memasang satu trek; tanpa pengisian latar sesi pulih '
              'berhenti sesudah trek pertama');
    });
  });

  group('_rebuildTail — disiplin generasi (Ronde 8057)', () {
    final def = bodyBetween(
        'Future<bool> _rebuildTail({', 'Future<void> _syncTailAfterMutation');

    test('tanda tangan: menerima gen & firstOnly, melaporkan bool', () {
      expect(def, contains('int? gen'));
      expect(def, contains('bool firstOnly = false'));
      expect(def, contains('gen: gen'));
      expect(def, contains('firstOnly: firstOnly'));
    });

    test('kelas batal ditelan menjadi FALSE; bukan dianggap terkomit', () {
      expect(def, contains('on _Superseded'));
      expect(def, contains('on DirectSuperseded'));
      expect(def, contains('return false'));
      expect(def, contains('return true'));
      // Penjaga pasca-pasang versi _rebuildTail: generasi yang berubah
      // SELAMA setAudioSource juga dilaporkan belum terkomit.
      expect(def, contains('if (gen != null && gen != _playGen) return false;'));
    });

    test('tidak ada lagi situs panggil _rebuildTail tanpa generasi', () {
      expect(count(src, '_rebuildTail()'), 0,
          reason:
              'setiap situs panggil wajib meneruskan generasi (klaim baru '
              'atau generasi berjalan) — panggilan polos menghidupkan lagi '
              'penyakit sentak-balik 8057');
      expect(count(src, '_rebuildTail(gen:'), 6,
          reason: 'enam situs panggil: lanjut otomatis, sinkron '
              'mutasi, Berikutnya ×2, pemulihan galat ×2');
    });
  });

  group('situs _rebuildTail per peran (Ronde 8057)', () {
    test('skipToNext: klaim generasi baru, tanpa firstOnly, seek berpenjaga',
        () {
      final body = bodyBetween('Future<void> skipToNext() async',
          'Future<void> skipToPrevious() async');
      expect(count(body, '++_playGen'), 1,
          reason: 'Berikutnya = perintah manual: tepat satu klaim');
      expect(body.indexOf('final gen = ++_playGen;'),
          lessThan(body.indexOf('_rebuildTail(gen: gen)')),
          reason: 'klaim mendahului kedua bangun ekor');
      expect(count(body, '_rebuildTail(gen: gen)'), 2,
          reason: 'kedua cabang bangun (antrean ada + sesudah isi ulang)');
      expect(body, isNot(contains('firstOnly: true')),
          reason:
              'firstOnly akan membuat seekToNext tanpa tujuan — bangun di '
              'sini justru mematerialkan trek berikutnya ke jendela');
      expect(count(body, 'if (await _rebuildTail(gen: gen))'), 2,
          reason:
              'seekToNext hanya bila bangun terkomit; yang dikalahkan tidak '
              'boleh seek di atas sumber milik perintah lain');
    });

    test('_advanceIntoContinuation: generasi berjalan, tanpa klaim/firstOnly',
        () {
      final body = bodyBetween('Future<void> _advanceIntoContinuation() async',
          'void _verifyAdvance');
      expect(body, contains('if (!await _rebuildTail(gen: _playGen)) return;'));
      expect(body, isNot(contains('++_playGen')),
          reason:
              'lanjut otomatis adalah jalur mesin — mengklaim akan '
              'mengalahkan ketukan pengguna yang sedang terbang');
      expect(body, isNot(contains('firstOnly: true')),
          reason: 'kepala sambungan harus ikut masuk jendela untuk seekToNext');
    });

    test('_syncTailAfterMutation: generasi berjalan, tanpa klaim/firstOnly',
        () {
      final body = bodyBetween('Future<void> _syncTailAfterMutation',
          'Future<bool> _trySyncTailSurgical');
      expect(body, contains('await _rebuildTail(gen: _playGen);'));
      expect(body, isNot(contains('++_playGen')),
          reason: 'mutasi antrean bukan perintah putar — tidak boleh '
              'membatalkan pembangunan ketukan');
      expect(body, isNot(contains('firstOnly: true')),
          reason: 'sinkron ekor memulihkan seluruh ekor hasil mutasi');
    });

    test('_onPlayerError: kedua coba-ulang memakai generasi berjalan', () {
      final body = bodyBetween(
          'Future<void> _onPlayerError(Object e) async',
          'Future<void> onTaskRemoved');
      expect(count(body, '_rebuildTail(gen: _playGen)'), 2,
          reason: 'coba-ulang URL segar + coba-ulang anak tangga berikutnya');
      expect(count(body, 'if (!await _rebuildTail(gen: _playGen)) return;'), 2,
          reason:
              'pemulihan yang dikalahkan berhenti — pemain milik perintah '
              'yang lebih baru, bukan untuk diputar dari sini');
      expect(body, isNot(contains('++_playGen')),
          reason: 'pemulihan galat tidak boleh mengalahkan ketukan pengguna');
      expect(body, isNot(contains('firstOnly: true')),
          reason: 'coba-ulang memulihkan ekor utuh seperti perilaku lama');
    });
  });
}
