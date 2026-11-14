import 'dart:io';

import 'package:clai/services/ambient_theme.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ronde 8064 — waveform mati diam-diam & sapuan konsumen Visualizer
/// (temuan perangkat pada staging 8063, 14 Nov 2026): pemilik
/// melaporkan waveform mati; kemudian terkoreksi — waveform pulih
/// sesudah "di-refresh". Penyelidikan membuktikan kelas
/// kegagalannya dari angka di emulator (bukan tebakan):
///
/// (1) IZIN: dengan izin mikrofon tertolak, Diagnostik membaca
///     "Waveform: RMS 0 · umpan 0 · tulis 0 · ember 0/56" dan
///     "Breath: RMS seen 0" sementara trek berbunyi — Log insiden
///     penuh 'vis-gagal-mulai … Cannot initialize Visualizer
///     engine, error: -3' dan penjaga sudah menegaskan ulang
///     17–20 kali tanpa hasil. Visualizer Android MEWAJIBKAN izin
///     mikrofon walau tidak merekam apa pun; tanpa izin ia tidak
///     bisa dibuat sama sekali. Sesudah izin diberikan dari luar
///     (pm grant), rantai pulih SENDIRI dalam ±25 detik lewat
///     penegasan penjaga — tanpa ganti trek, tanpa mulai ulang:
///     ember 0 → 10/56, RMS 17. Jadi titik butanya BUKAN penjaga,
///     melainkan TIDAK ADANYA jalan minta izin di permukaan
///     waveform/napas: izin hanya diminta sakelar normalisasi dan
///     lembar suara, sehingga pulihnya rantai bergantung pada
///     pemberian izin di tempat lain ("harus di-refresh").
/// (2) KANAL BERBAGI: AudioFxService.rmsEvents dulu memanggil
///     EventChannel.receiveBroadcastStream() pada SETIAP akses
///     getter — setiap instans stream memasang handler kanal baru,
///     handler terakhir MENANG, dan cancel instans mana pun
///     mematikan sink natif untuk semua. Estimator kenyaringan
///     (berlangganan lebih dulu, dari bootstrap) kehilangan
///     handlernya sejak cangkang mulai mendengarkan, sehingga
///     gain normalisasi TIDAK PERNAH terukur tanpa galat apa pun.
///     Kini alirannya satu instans bersama.
///
/// Perilaku baru yang dikunci di sini:
/// (a) predikat murni shouldRequestMicForVisualizer: minta hanya
///     bila ada konsumen yang membutuhkan, belum pernah diminta
///     proses ini, izin belum terpasang, dan aplikasi di depan;
/// (b) cangkang (app.dart) menjalankan ensureMicForVisualizer dari
///     KEDUA penilai gerbang (napas & waveform) dan menegaskan
///     ulang Visualizer seketika sesudah izin diberikan
///     (handler.reassertVisualizer);
/// (c) rmsEvents adalah instans bersama: receiveBroadcastStream
///     muncul tepat SATU kali di audio_fx_service.dart;
/// (d) log 'vis-gagal-mulai' didedupe per (sesi, alasan) agar
///     keadaan tertolak permanen tidak membanjiri Log insiden.
///
/// Handler & layanan kanal tidak bisa dibangun di unit test
/// (konstruktor menyentuh kanal platform — kendala yang sama
/// dicatat suite ronde sebelumnya), jadi paruh kabel diverifikasi
/// pada sumber, paruh keputusan diuji sebagai fungsi murni.
void main() {
  group('shouldRequestMicForVisualizer — tabel kebenaran', () {
    test('semua syarat terpenuhi → minta', () {
      expect(
        shouldRequestMicForVisualizer(
          consumerWants: true,
          alreadyAsked: false,
          granted: false,
          appResumed: true,
        ),
        isTrue,
      );
    });

    test('tak ada konsumen → tidak minta', () {
      expect(
        shouldRequestMicForVisualizer(
          consumerWants: false,
          alreadyAsked: false,
          granted: false,
          appResumed: true,
        ),
        isFalse,
      );
    });

    test('sudah pernah diminta proses ini → tidak minta lagi', () {
      expect(
        shouldRequestMicForVisualizer(
          consumerWants: true,
          alreadyAsked: true,
          granted: false,
          appResumed: true,
        ),
        isFalse,
      );
    });

    test('izin sudah terpasang → tidak minta', () {
      expect(
        shouldRequestMicForVisualizer(
          consumerWants: true,
          alreadyAsked: false,
          granted: true,
          appResumed: true,
        ),
        isFalse,
      );
    });

    test('aplikasi di latar → tidak minta (dialog tak bisa tampil)', () {
      expect(
        shouldRequestMicForVisualizer(
          consumerWants: true,
          alreadyAsked: false,
          granted: false,
          appResumed: false,
        ),
        isFalse,
      );
    });
  });

  group('kabel izin & kanal bersama — struktur sumber', () {
    final fx = File('lib/services/audio_fx_service.dart').readAsStringSync();
    final app = File('lib/app.dart').readAsStringSync();
    final handler = File('lib/player/audio_handler.dart').readAsStringSync();

    String bodyBetween(String src, String startMarker, String endMarker) {
      final start = src.indexOf(startMarker);
      if (start < 0) throw StateError('$startMarker tidak ditemukan');
      final end = src.indexOf(endMarker, start);
      if (end <= start) {
        throw StateError('$endMarker tidak ditemukan sesudah $startMarker');
      }
      return src.substring(start, end);
    }

    test('rmsEvents: receiveBroadcastStream tepat satu & dibagikan', () {
      // Hitung SITUS PANGGIL nyata (bentuk `_events .receive…`),
      // bukan penyebutan nama metode di komentar penjelasan.
      final callSites =
          RegExp(r'_events\s*\n\s*\.receiveBroadcastStream\(\)')
              .allMatches(fx)
              .length;
      expect(callSites, 1,
          reason: 'satu instans EventChannel untuk semua konsumen');
      expect(fx.contains('_rmsShared'), isTrue);
      expect(fx.contains('asBroadcastStream()'), isTrue);
    });

    test('AudioFxService punya helper izin mikrofon', () {
      expect(fx.contains('Future<bool> micGranted()'), isTrue);
      expect(fx.contains('Future<bool> micRequest()'), isTrue);
      expect(fx.contains('Permission.microphone'), isTrue);
    });

    test('cangkang: ensureMicForVisualizer dipanggil kedua penilai gerbang',
        () {
      expect(app.contains('ensureMicForVisualizer'), isTrue);
      final breath = bodyBetween(
          app, 'void syncBreathVis()', 'ref.listenManual');
      expect(breath.contains('ensureMicForVisualizer(want)'), isTrue);
      final wave = bodyBetween(
          app, 'void syncWaveformVis()', 'handler.mediaItem.listen');
      expect(wave.contains('ensureMicForVisualizer(wants)'), isTrue);
    });

    test('cangkang: pemberian izin menegaskan ulang Visualizer', () {
      final ensure = bodyBetween(
          app, 'Future<void> ensureMicForVisualizer', 'void syncBreathVis()');
      expect(ensure.contains('handler.reassertVisualizer()'), isTrue);
      expect(ensure.contains('shouldRequestMicForVisualizer'), isTrue);
    });

    test('handler: reassertVisualizer publik lewat jalur terserialisasi',
        () {
      expect(
          handler.contains(
              'Future<void> reassertVisualizer() => _syncVisualizer(forceRestart: true);'),
          isTrue);
    });

    test('handler: log vis-gagal-mulai didedupe per sesi+alasan', () {
      expect(handler.contains('_lastVisFailKey'), isTrue);
      final now = bodyBetween(handler, 'Future<void> _syncVisualizerNow',
          'Future<void> reassertVisualizer()');
      expect(now.contains('failKey != _lastVisFailKey'), isTrue);
    });
  });
}
