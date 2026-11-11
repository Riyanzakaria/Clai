import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/app_db.dart';
import '../domain/models.dart';
import 'waveform.dart';

/// Perekam waveform ukur (Ronde Player B): diberi makan aliran RMS
/// Visualizer yang sama dengan estimator kenyaringan & napas oleh
/// cangkang aplikasi (app.dart) — tidak ada Visualizer kedua. Setiap
/// sampel dipetakan ke ember posisi trek aktif dan digabung sebagai
/// RATA-RATA berjalan **di domain dB mentah** ke data trek itu
/// (Ronde 8050 — nilai tersimpan tidak lagi dipetakan lebih dulu;
/// pemetaan jendela tetap era v2 terbukti menjenuhkan pita sempit
/// perangkat secara permanen di basis data); data tersimpan
/// persisten di DB (tabel track_waveforms, skema v5; muatan format
/// v3) dan dibaca kembali pada putaran ulang.
///
/// Perekam adalah KONSUMEN KETIGA aliran RMS dan sejak Sisipan G-1
/// punya suara di gerbang Visualizer: cangkang menyalakan Visualizer
/// selama data trek berjalan belum lengkap terukur (predikat
/// waveformWantsVisualizer) — tanpa itu, pada keadaan bawaan
/// (normalisasi mati + napas mati) perekam kelaparan permanen.
///
/// Kejujuran data: perekam hanya menulis ember yang benar-benar
/// terlewati pemutaran dengan energi terukur. Berkas lokal & unduhan
/// terisi lewat jalur yang sama saat diputar (tidak ada lewatan
/// dekode terpisah di ronde ini) — embernya tetap energi nyata lagu,
/// hanya sumber sampelnya pemutaran, bukan berkas.
class WaveformRecorder extends ChangeNotifier {
  final AppDb db;
  final Map<TrackKey, WaveformData> _cache = {};
  final Set<TrackKey> _loading = {};

  WaveformRecorder(this.db);

  // ---- Instrumentasi rantai umpan (Ronde Perbaikan Waveform Perangkat,
  // 2026-11-10). Bukti perangkat build 8042: RMS hidup (napas seen 37 ·
  // fed 9) tetapi waveform "Timur" NOL ember pada 1:32 — kelaparan
  // perekam hidup di pola putar nyata (antrean + autoplay + transisi),
  // bukan di bangku sekuensial sederhana. Penghitung ini membuktikan
  // titik buang dari angka di Diagnostik, bukan dari tebakan: setiap
  // peristiwa RMS yang tiba di cangkang dicatat asalnya (sesi pemain
  // aktif vs sesi lain), dan setiap panggilan feed dicatat nasibnya
  // per sebab. Baris ringkasnya tampil permanen di Diagnostik Putar.
  /// Peristiwa RMS yang tiba di pendengar cangkang.
  int rmsEvents = 0;

  /// …di antaranya yang berasal dari sesi pemain yang sedang berbunyi.
  int rmsFromActiveSession = 0;

  /// …di antaranya yang berasal dari sesi pemain LAIN (diam/preload).
  int rmsFromOtherSession = 0;

  /// …di antaranya yang tiba saat engine tak punya trek berjalan.
  int rmsNoCurrent = 0;

  /// Peristiwa yang kunci umpannya (engine.current) TIDAK sama dengan
  /// kunci yang benar-benar dimuat pemain berbunyi (handler.soundingKey).
  int rmsKeyMismatch = 0;

  /// Panggilan feed() yang masuk ke perekam.
  int feedCalls = 0;

  /// Sampel yang benar-benar menulis ember.
  int acceptedWrites = 0;

  /// Buang: bendera playing terbaca false saat sampel tiba.
  int dropNotPlaying = 0;

  /// Buang: durasi trek berjalan nol/belum diketahui (indeks tak sah).
  int dropNoDuration = 0;

  /// Buang: indeks ember di luar rentang sebab lain.
  int dropBadIndex = 0;

  /// Sampel tiba & sah tetapi rata-rata ember tak bergerak (konvergen).
  int dropNoChange = 0;

  /// Snapshot umpan terakhir untuk dibaca Diagnostik.
  TrackKey? lastFeedKey;
  TrackKey? lastSoundingKey;
  int lastFeedIdx = -1;
  int lastPosMs = -1;
  int lastDurMs = -1;

  /// Catat asal satu peristiwa RMS dari cangkang (dipanggil tepat
  /// sebelum feed agar angka Diagnostik sebanding dengan napas).
  void noteRmsEvent({
    required bool fromActiveSession,
    required bool hasCurrent,
    required TrackKey? feedKey,
    required TrackKey? soundingKey,
  }) {
    rmsEvents++;
    if (fromActiveSession) {
      rmsFromActiveSession++;
    } else {
      rmsFromOtherSession++;
    }
    if (!hasCurrent) rmsNoCurrent++;
    lastSoundingKey = soundingKey;
    if (feedKey != null && soundingKey != null && feedKey != soundingKey) {
      rmsKeyMismatch++;
    }
  }

  /// Data waveform untuk [key] (memicu muat malas dari DB bila belum
  /// ter-cache). Mengembalikan data kosong saat belum ada apa pun —
  /// UI menggambar keadaan "belum terukur" darinya.
  WaveformData dataFor(TrackKey key) {
    final cached = _cache[key];
    if (cached != null) return cached;
    if (!_loading.contains(key)) {
      _loading.add(key);
      unawaited(_load(key));
    }
    return WaveformData.empty;
  }

  Future<void> _load(TrackKey key) async {
    try {
      final stored = await db.waveformFor(key);
      if (stored != null) {
        // Gabung dengan umpan langsung yang mungkin lebih dulu tiba.
        final cur = _cache[key];
        _cache[key] = cur == null ? stored : cur.mergedWith(stored);
        notifyListeners();
      }
    } catch (_) {
      /* DB gagal: waveform tetap kosong sesi ini, bukan crash */
    } finally {
      _loading.remove(key);
    }
  }

  /// Umpan satu sampel RMS untuk trek yang sedang diputar.
  void feed({
    required TrackKey key,
    required Duration position,
    required Duration duration,
    required double rmsDb,
    required bool playing,
  }) {
    feedCalls++;
    lastFeedKey = key;
    lastPosMs = position.inMilliseconds;
    lastDurMs = duration.inMilliseconds;
    if (!playing) {
      dropNotPlaying++;
      return;
    }
    if (duration <= Duration.zero) {
      dropNoDuration++;
      return;
    }
    final idx = waveformBucketIndex(position, duration);
    if (idx < 0) {
      dropBadIndex++;
      return;
    }
    lastFeedIdx = idx;
    final cur = _cache[key] ?? WaveformData.empty;
    final next = cur.withSample(idx, rmsDb);
    if (identical(next, cur)) {
      dropNoChange++;
      return;
    }
    acceptedWrites++;
    _cache[key] = next;
    notifyListeners();
    unawaited(_persist(key, next));
  }

  Future<void> _persist(TrackKey key, WaveformData data) async {
    try {
      await db.saveWaveform(key, data);
    } catch (_) {
      /* tulis gagal: data tetap hidup di cache sesi ini */
    }
  }
}
