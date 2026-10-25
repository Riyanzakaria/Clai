import 'dart:async';
import '../l10n/l10n.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../data/app_db.dart';
import '../domain/models.dart';
import 'speed_volume.dart';

/// Mode Berkendara (F2 Batch 2, PRD 5.14 A) + Volume Ikut Kecepatan.
/// Pemicu TIDAK ditebak: sakelar manual, atau perangkat Bluetooth yang
/// ditandai pengguna sebagai kendaraan (daftar tersimpan di pref).
/// Skema kendali: 'buttons' (tombol media standar — bawaan), 'patterns'
/// (pola tekan satu tombol, dipegang handler), 'voice' (perintah suara).
/// Volume Ikut Kecepatan gagal-aman: keraguan apa pun = volume tetap.
class DrivingService extends ChangeNotifier {
  final AppDb db;
  static const _ch = MethodChannel('clai/driving');
  static const _events = EventChannel('clai/driving_events');
  static const _tts = MethodChannel('clai/tts');

  bool on = false;
  bool announceOn = false;
  bool speedVolumeOn = false;
  double stopVolume = 0.7;
  double fastVolume = 1.0;
  double anchorKmh = 80;
  String scheme = 'buttons';
  List<String> vehicles = [];

  /// Dipasang app.dart: terapkan faktor volume ke handler.
  Future<void> Function(double v)? onVolumeTarget;

  StreamSubscription? _eventSub;
  final List<({DateTime at, double kmh, double accuracyM})> _window = [];
  double _currentVolume = 1.0;
  DateTime? _lastStepAt;
  DateTime? _stoppedSince;
  bool _interrupted = false;
  bool _locRunning = false;

  DrivingService(this.db);

  Future<void> load() async {
    on = await db.pref<bool>('driving.on') ?? false;
    announceOn = await db.pref<bool>('driving.announce') ?? false;
    speedVolumeOn = await db.pref<bool>('driving.speedVolume') ?? false;
    stopVolume = await db.pref<double>('driving.stopVolume') ?? 0.7;
    fastVolume = await db.pref<double>('driving.fastVolume') ?? 1.0;
    anchorKmh = await db.pref<double>('driving.anchorKmh') ?? 80;
    scheme = await db.pref<String>('driving.scheme') ?? 'buttons';
    final v = await db.pref<List>('driving.vehicles');
    vehicles = v == null ? [] : v.map((e) => '$e').toList();
    notifyListeners();
  }

  Future<void> setOn(bool v) async {
    on = v;
    await db.setPref('driving.on', v);
    if (!v) await _applyVolume(1.0);
    notifyListeners();
  }

  Future<void> setAnnounce(bool v) async {
    announceOn = v;
    await db.setPref('driving.announce', v);
    notifyListeners();
  }

  Future<void> setScheme(String s) async {
    scheme = s;
    await db.setPref('driving.scheme', s);
    notifyListeners();
  }

  Future<void> setCalibration(
      {required double stop, required double fast, required double anchor}) async {
    stopVolume = stop.clamp(0.0, 1.0);
    fastVolume = fast.clamp(0.0, 1.0);
    anchorKmh = anchor.clamp(20, 160);
    await db.setPref('driving.stopVolume', stopVolume);
    await db.setPref('driving.fastVolume', fastVolume);
    await db.setPref('driving.anchorKmh', anchorKmh);
    notifyListeners();
  }

  Future<void> setSpeedVolume(bool v) async {
    speedVolumeOn = v;
    await db.setPref('driving.speedVolume', v);
    if (v) {
      await _startLocation();
    } else {
      await _stopLocation();
      await _applyVolume(1.0);
    }
    notifyListeners();
  }

  Future<void> markVehicle(String name) async {
    if (!vehicles.contains(name)) {
      vehicles = [...vehicles, name];
      await db.setPref('driving.vehicles', vehicles);
      notifyListeners();
    }
  }

  Future<void> unmarkVehicle(String name) async {
    vehicles = vehicles.where((e) => e != name).toList();
    await db.setPref('driving.vehicles', vehicles);
    notifyListeners();
  }

  /// Pemicu otomatis: nama perangkat yang tersambung ada di daftar kendaraan.
  bool shouldAutoEnter(String connectedName) => vehicles.contains(connectedName);

  /// Perangkat Bluetooth terpasang (Kotlin). Kosong di emulator (tanpa radio BT).
  Future<List<String>> bondedDevices() async {
    try {
      final r = await _ch.invokeMethod<List<Object?>>('bondedDevices');
      return (r ?? []).map((e) => '$e').toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> announce(Track t) async {
    if (!on || !announceOn) return;
    try {
      await _tts.invokeMethod<void>(
          'speak', {'text': l10n.drvAnnounceNext(t.title, t.artistNames)});
    } catch (_) {/* TTS gagal: musik jalan terus tanpa pengumuman */}
  }

  Future<void> _startLocation() async {
    if (_locRunning) return;
    try {
      final ok = await _ch.invokeMethod<bool>('startLocation') ?? false;
      if (!ok) return;
      _locRunning = true;
      _eventSub = _events.receiveBroadcastStream().listen(_onEvent,
          onError: (_) {/* kanal putus: volume membeku di nilai terakhir */});
    } catch (_) {/* lokasi gagal: volume tetap */}
  }

  Future<void> _stopLocation() async {
    _locRunning = false;
    await _eventSub?.cancel();
    _eventSub = null;
    try {
      await _ch.invokeMethod<void>('stopLocation');
    } catch (_) {}
  }

  void _onEvent(Object? event) {
    if (event is! Map) return;
    final kmh = (event['speedKmh'] as num?)?.toDouble();
    final acc = (event['accuracyM'] as num?)?.toDouble();
    final call = event['callActive'] as bool?;
    if (call != null) _interrupted = call;
    if (kmh == null || acc == null) return;
    if (!on || !speedVolumeOn) return;
    final now = DateTime.now();
    _window.add((at: now, kmh: kmh, accuracyM: acc));
    _window.removeWhere((e) => now.difference(e.at).inSeconds > 10);
    final poor = _window.any((e) => e.accuracyM > 50);
    final med = median(_window.map((e) => e.kmh).toList());
    if (med < 1) {
      _stoppedSince ??= now;
    } else {
      _stoppedSince = null;
    }
    final stoppedLong = _stoppedSince != null &&
        now.difference(_stoppedSince!).inSeconds > 15;
    final target = speedVolumeTarget(
      medianKmh: med,
      stopVolume: stopVolume,
      fastVolume: fastVolume,
      anchorKmh: anchorKmh,
      poorAccuracy: poor,
      interrupted: _interrupted,
      stoppedLong: stoppedLong,
    );
    if (target == null) return; // beku — gagal-aman
    // Ramp: maksimal 1 langkah per 2 detik.
    final step = speedVolumeStep(stopVolume, fastVolume);
    if (_lastStepAt != null &&
        now.difference(_lastStepAt!).inMilliseconds < 2000 &&
        (target - _currentVolume).abs() > step) {
      return; // tunggu jendela ramp berikutnya
    }
    final next = (_currentVolume + (target - _currentVolume).clamp(-step, step));
    _lastStepAt = now;
    _currentVolume = next;
    _applyVolume(next).then((_) {}, onError: (_) {});
  }

  Future<void> _applyVolume(double v) async {
    _currentVolume = v;
    final f = onVolumeTarget;
    if (f != null) await f(v);
  }

  /// Jalur uji: suntikkan sampel kecepatan tanpa GPS (dipakai unit test).
  void injectSpeedSample(double kmh, double accuracyM) {
    _onEvent({'speedKmh': kmh, 'accuracyM': accuracyM});
  }

  /// Jalur uji: suntikkan status panggilan tanpa telefoni.
  void injectCallState(bool active) {
    _onEvent({'callActive': active});
  }
}
