import 'dart:async';
import 'dart:math' as math;

import '../data/app_db.dart';
import '../domain/models.dart';
import '../player/audio_handler.dart';
import 'audio_fx_service.dart';

/// Target kenyaringan normalisasi (RMS, dBFS): lagu yang diukur lebih pelan
/// dari ini dinaikkan gain-nya, yang lebih keras diturunkan — dijepit ±12 dB.
const kLoudnessTargetDb = -16.0;

/// Gain linear dari selisih dB terukur vs target (murni — diuji unit).
double gainFromLoudness(double measuredDb, {double targetDb = kLoudnessTargetDb}) {
  final gain = math.pow(10, (targetDb - measuredDb) / 20).toDouble();
  return gain.clamp(0.25, 4.0);
}

/// Estimator kenyaringan (F2 Batch 2): mengakumulasi sampel RMS Visualizer
/// per lagu yang sedang berjalan (diatribusikan lewat engine.current saat
/// sampel tiba), lalu saat lagu berganti menyimpan gain hasil ukur ke
/// track_gains — gain itu dipakai MULAI putaran berikutnya atas lagu yang
/// sama (bukan di tengah lagu; perubahan volume tengah lagu terasa glitch).
/// Sampel di bawah −60 dB diabaikan (hening/jeda bukan data kenyaringan).
class LoudnessEstimator {
  final AppDb db;
  final ClaiAudioHandler handler;
  final AudioFxService fx;

  final Map<TrackKey, ({double sumPower, int count})> _acc = {};
  TrackKey? _currentKey;
  StreamSubscription<Map<String, Object?>>? _sub;
  bool running = false;

  LoudnessEstimator(this.db, this.handler, this.fx);

  void start() {
    if (running) return;
    running = true;
    _sub = fx.rmsEvents.listen(_onRms, onError: (_) {/* kanal putus: diam */});
  }

  Future<void> stop() async {
    running = false;
    await _sub?.cancel();
    _sub = null;
    if (_currentKey != null) {
      final k = _currentKey!;
      _currentKey = null;
      await _finalize(k);
    }
  }

  void _onRms(Map<String, Object?> e) {
    if (!handler.normalizationOn) return;
    final rmsDb = (e['rmsDb'] as num?)?.toDouble();
    if (rmsDb == null || rmsDb < -60) return;
    final key = handler.engine.current?.key;
    if (key == null) return;
    if (_currentKey != null && _currentKey != key) {
      _finalize(_currentKey!).then((_) {}, onError: (_) {});
    }
    _currentKey = key;
    // Daya ∝ kuadrat RMS: dari dB amplitudo (20·log10) ke daya (10·log10).
    final power = math.pow(10, rmsDb / 10).toDouble();
    final a = _acc[key] ?? (sumPower: 0.0, count: 0);
    _acc[key] = (sumPower: a.sumPower + power, count: a.count + 1);
  }

  Future<void> _finalize(TrackKey key) async {
    final a = _acc.remove(key);
    if (a == null || a.count < 5) return; // terlalu sedikit sampel: bukan data
    final avgDb = 10 * (math.log(a.sumPower / a.count) / math.ln10);
    final gain = gainFromLoudness(avgDb);
    await db.setTrackGain(key, gain);
    handler.noteGainMeasured(key, gain);
  }
}
