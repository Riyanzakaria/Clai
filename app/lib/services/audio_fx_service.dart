import 'dart:async';

import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

/// Info Equalizer perangkat (dari kanal 'clai/audiofx', sesi pemain Clai).
class EqInfo {
  final int bandCount;
  final List<int> centerFreqHz;
  final int minLevel; // millibel
  final int maxLevel; // millibel
  final List<String> presets;
  final int currentPreset;
  final List<int> bandLevels;
  final bool enabled;
  const EqInfo({
    required this.bandCount,
    required this.centerFreqHz,
    required this.minLevel,
    required this.maxLevel,
    required this.presets,
    required this.currentPreset,
    required this.bandLevels,
    required this.enabled,
  });

  static EqInfo? fromMap(Map? m) {
    if (m == null) return null;
    return EqInfo(
      bandCount: (m['bandCount'] as num?)?.toInt() ?? 0,
      centerFreqHz: ((m['centerFreqHz'] as List?) ?? const [])
          .map((e) => (e as num).toInt())
          .toList(),
      minLevel: (m['minLevel'] as num?)?.toInt() ?? 0,
      maxLevel: (m['maxLevel'] as num?)?.toInt() ?? 0,
      presets: ((m['presets'] as List?) ?? const []).map((e) => '$e').toList(),
      currentPreset: (m['currentPreset'] as num?)?.toInt() ?? -1,
      bandLevels: ((m['bandLevels'] as List?) ?? const [])
          .map((e) => (e as num).toInt())
          .toList(),
      enabled: m['enabled'] as bool? ?? false,
    );
  }
}

/// Jembatan Equalizer + Visualizer (F2 Batch 2, kanal 'clai/audiofx').
/// Semua metode GAGAL-AMAN: kegagalan mengembalikan null/false —
/// UI menyatakan keadaan sebenarnya, bukan crash.
///
/// F2 Batch 2.1: dukungan EQ DIPUTUSKAN dari percobaan pembuatan pada
/// sesi pemain yang hidup. Probe lama memakai sesi 0 (mix global) yang
/// ditolak Android modern/OEM walau EQ sesi nyata bisa dibuat — itulah
/// akar pesan "tidak tersedia" yang keliru di HP riyan (build 2005).
class AudioFxService {
  static const _ch = MethodChannel('clai/audiofx');
  static const _events = EventChannel('clai/audiofx_events');

  /// Alasan gagal terakhir memulai Visualizer (dari sisi Kotlin, untuk
  /// dicatat ke Log insiden — bukan ditelan).
  String? lastVisError;

  Future<bool> eqSupported(int sessionId) async {
    try {
      return await _ch.invokeMethod<bool>(
              'eqSupported', {'sessionId': sessionId}) ??
          false;
    } catch (_) {
      return false;
    }
  }

  /// Diagnosis terstruktur ketersediaan EQ pada [sessionId] (deskriptor
  /// efek perangkat + hasil percobaan sesi 0 vs sesi nyata) — untuk Log
  /// insiden saat EQ dinilai tidak tersedia.
  Future<Map<String, Object?>?> eqDiagnose(int sessionId) async {
    try {
      return await _ch.invokeMapMethod<String, Object>(
          'eqDiagnose', {'sessionId': sessionId});
    } catch (_) {
      return null;
    }
  }

  Future<EqInfo?> eqInfo(int sessionId) async {
    try {
      final r = await _ch.invokeMapMethod<String, Object>(
          'eqInfo', {'sessionId': sessionId});
      return EqInfo.fromMap(r);
    } catch (_) {
      return null;
    }
  }

  /// Terapkan setelan ke satu sesi. [preset] >= 0 memakai preset perangkat;
  /// -1 memakai [bandLevels] kustom (millibel per band).
  Future<bool> eqApply({
    required int sessionId,
    required bool enabled,
    required int preset,
    required List<int> bandLevels,
  }) async {
    try {
      await _ch.invokeMethod<void>('eqApply', {
        'sessionId': sessionId,
        'enabled': enabled,
        'preset': preset,
        'bandLevels': bandLevels,
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> visSupported(int sessionId) async {
    try {
      return await _ch.invokeMethod<bool>('visSupported', {'sessionId': sessionId}) ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> visStart(int sessionId) async {
    try {
      lastVisError = null;
      return await _ch.invokeMethod<bool>('visStart', {'sessionId': sessionId}) ?? false;
    } on PlatformException catch (e) {
      lastVisError = e.message ?? e.code;
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<void> visStop(int sessionId) async {
    try {
      await _ch.invokeMethod<void>('visStop', {'sessionId': sessionId});
    } catch (_) {/* berhenti diam-diam */}
  }

  /// Lepas instance Equalizer satu sesi (Ronde Kresek): dipanggil saat sesi
  /// berganti, EQ dimatikan, atau handler berhenti. Sebelumnya instance
  /// dibuat per sesi dan tidak pernah dilepas — yatim di sesi mati.
  Future<void> eqRelease(int sessionId) async {
    try {
      await _ch.invokeMethod<void>('eqRelease', {'sessionId': sessionId});
    } catch (_) {/* lepas diam-diam */}
  }

  /// Lepas SEMUA instance efek (EQ + Visualizer) di sisi native.
  Future<void> fxReleaseAll() async {
    try {
      await _ch.invokeMethod<void>('fxReleaseAll');
    } catch (_) {/* lepas diam-diam */}
  }

  /// Jumlah instance efek yang hidup di sisi native + sesi pemiliknya —
  /// bukti pembeda kebocoran untuk Log insiden (null bila kanal gagal).
  Future<Map<String, Object?>?> fxCounts() async {
    try {
      return await _ch.invokeMapMethod<String, Object>('fxCounts');
    } catch (_) {
      return null;
    }
  }

  /// Izin mikrofon terpasang? Visualizer Android MEWAJIBKAN izin ini
  /// walau tidak merekam apa pun (ia mengukur sesi audio) — tanpa izin,
  /// pembuatan Visualizer gagal "error: -3" dan seluruh rantai ukur
  /// (waveform, napas, gain normalisasi) mati senyap (Ronde 8064).
  Future<bool> micGranted() async {
    try {
      return await Permission.microphone.isGranted;
    } catch (_) {
      return false;
    }
  }

  /// Minta izin mikrofon lewat dialog sistem; true bila diberikan.
  Future<bool> micRequest() async {
    try {
      return (await Permission.microphone.request()).isGranted;
    } catch (_) {
      return false;
    }
  }

  /// Aliran peristiwa RMS Visualizer: {sessionId, rmsDb} ±1×/detik per sesi.
  ///
  /// **SATU instans bersama untuk SEMUA konsumen (Ronde 8064).**
  /// `EventChannel.receiveBroadcastStream()` memasang handler kanal
  /// BARU pada setiap panggilan: handler instans yang terakhir
  /// berlangganan MENANG dan handler instans sebelumnya terganti
  /// diam-diam; pembatalan langganan instans mana pun pula mengirim
  /// 'cancel' ke sisi natif yang menonaktifkan sink untuk semua.
  /// Konsumen aliran ini ada dua instans stream terpisah (cangkang
  /// aplikasi untuk napas + waveform; estimator kenyaringan untuk
  /// normalisasi) — akibatnya estimator tidak pernah menerima satu
  /// pun sampel sejak cangkang mulai mendengarkan (ia berlangganan
  /// lebih dulu, handlernya terganti), dan gain normalisasi tidak
  /// pernah terukur tanpa satu pun galat. Kini alirannya dibuat
  /// SEKALI dan dibagikan: satu 'listen' ke natif, dan setiap
  /// pendengar Dart menerima setiap peristiwa.
  static Stream<Map<String, Object?>>? _rmsShared;
  Stream<Map<String, Object?>> get rmsEvents => _rmsShared ??= _events
      .receiveBroadcastStream()
      .map((e) => (e as Map).cast<String, Object?>())
      .asBroadcastStream();
}
