import 'package:clai/player/audio_handler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';

/// Ronde 8057 — regresi cacat tombol Putar mati sesudah trek terakhir
/// antrean selesai ALAMI.
///
/// Akar terbukti (audit kode): play() di audio_handler jatuh ke
/// `await _player.play()` penutup TANPA pemeriksaan completed dan tanpa
/// seek. just_audio/ExoPlayer mengabaikan play() pada keadaan completed;
/// _onPlaybackCompleted tidak pernah memutar-balik, dan trek terakhir
/// tidak mendapat peristiwa indeks-berikutnya — pemain parkir permanen
/// di posisi == durasi, processingState == completed, dan setiap tekanan
/// Putar (semua tombol UI bermuara playNow() → play()) adalah no-op.
///
/// Perbaikan: keputusan murni [shouldRewindBeforePlay] — completed wajib
/// seek ke Duration.zero SEBELUM play(), pada jalur jatuh gapless dan
/// pada cabang putar-di-tempat crossfade. Jalur ini sebelumnya NOL tes.
///
/// Yang diuji di sini: tabel kebenaran keputusan itu. Handler konkret
/// menyentuh kanal platform (kendala yang sama dicatat
/// antrean_kembali_8055_test & radio_header_a5_test), jadi koreografi
/// seek→play pada pemain nyata dibuktikan di bench emulator; permukaan
/// yang bisa diuji unit memang keputusan murninya — itulah alasan
/// keputusan ini diekstrak sebagai fungsi top-level.
void main() {
  group('shouldRewindBeforePlay — tabel kebenaran (Ronde 8057)', () {
    test('completed → true (satu-satunya keadaan yang wajib putar-balik)',
        () {
      expect(shouldRewindBeforePlay(ProcessingState.completed), isTrue);
    });

    test('ready → false (jeda biasa: play() melanjutkan dari posisi)', () {
      expect(shouldRewindBeforePlay(ProcessingState.ready), isFalse);
    });

    test('loading → false', () {
      expect(shouldRewindBeforePlay(ProcessingState.loading), isFalse);
    });

    test('buffering → false', () {
      expect(shouldRewindBeforePlay(ProcessingState.buffering), isFalse);
    });

    test('idle → false', () {
      expect(shouldRewindBeforePlay(ProcessingState.idle), isFalse);
    });

    test('tuntas: SETIAP nilai ProcessingState terpetakan persis', () {
      // Penjaga tuntas: nilai enum baru dari just_audio di masa depan
      // WAJIB gagal di sini sampai keputusannya disadari eksplisit —
      // putar-balik yang menyala di keadaan selain completed akan
      // menolkan posisi pada jeda biasa (regresi arah sebaliknya).
      expect(ProcessingState.values, hasLength(5));
      for (final state in ProcessingState.values) {
        expect(
          shouldRewindBeforePlay(state),
          state == ProcessingState.completed,
          reason: 'keputusan untuk $state menyimpang dari tabel 8057',
        );
      }
    });

    test('completed adalah SATU-SATUNYA true di seluruh enum', () {
      final trues =
          ProcessingState.values.where(shouldRewindBeforePlay).toList();
      expect(trues, [ProcessingState.completed]);
    });
  });

  group('koreografi keputusan — tekanan Putar berurutan (Ronde 8057)', () {
    // Tiru urutan keputusan handler pada pemain yang parkir completed:
    // tekanan pertama memutar-balik lalu play() menghidupkan pemain
    // (keadaan keluar dari completed); tekanan berikutnya pada pemain
    // yang sudah hidup TIDAK boleh memutar-balik lagi — posisi yang
    // sedang berjalan tidak ditolkan oleh Putar redundan.
    test('parkir completed → putar-balik sekali; hidup → tidak lagi', () {
      var state = ProcessingState.completed;
      final rewinds = <bool>[];
      for (var press = 0; press < 3; press++) {
        final rewind = shouldRewindBeforePlay(state);
        rewinds.add(rewind);
        if (rewind) {
          // Efek seek(Duration.zero) + play() yang berhasil: pemain
          // meninggalkan keadaan completed menuju ready/berbunyi.
          state = ProcessingState.ready;
        }
      }
      expect(rewinds, [true, false, false]);
    });

    test('jeda di tengah trek (ready) tidak pernah diputar-balik', () {
      // Skenario pembeda cacat: pengguna menjeda di 1:23 lalu menekan
      // Putar — keputusan harus false agar putaran lanjut dari 1:23,
      // bukan dari 0:00.
      expect(shouldRewindBeforePlay(ProcessingState.ready), isFalse);
    });
  });
}
