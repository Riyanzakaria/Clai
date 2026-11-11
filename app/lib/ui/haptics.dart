import 'package:flutter/services.dart';

/// Bahasa haptik Clai (U6, DS v4.0 §3-P7): getar mikro HANYA di momen
/// bermakna — suka, skip mendarat, unduhan selesai, timer terpasang.
/// Tidak pernah pada gulir, ketuk navigasi, buka lembar, atau ketik.
/// Selalu mati bersama Kurangi Efek ([reduceEffects] disetel cangkang
/// dari keadaan tema + pengaturan sistem).
class ClaiHaptics {
  static bool reduceEffects = false;

  static bool _skipArmed = false;
  static String? _lastTrackId;

  /// Tandai bahwa pengguna baru saja memerintah skip: denyut mendarat
  /// ditembakkan saat trek baru benar-benar mulai (lihat [trackLanded]).
  static void armSkipLanding() {
    _skipArmed = true;
  }

  /// Dipanggil cangkang tiap media item berganti. Menembak denyut
  /// sangat ringan hanya bila pergantian ini adalah pendaratan skip
  /// yang ditandai [armSkipLanding] dan trek baru sedang diputar.
  static void trackLanded(String? trackId, {required bool playing}) {
    final changed = trackId != null && trackId != _lastTrackId;
    _lastTrackId = trackId;
    if (!changed || !_skipArmed) return;
    _skipArmed = false;
    if (playing) fire(HapticFeedback.selectionClick);
  }

  /// Suka / batal suka: satu denyut pendek.
  static void like() => fire(HapticFeedback.lightImpact);

  /// Unduhan selesai: satu denyut jelas.
  static void downloadDone() => fire(HapticFeedback.mediumImpact);

  /// Timer tidur terpasang: denyut sangat ringan.
  static void timerSet() => fire(HapticFeedback.selectionClick);

  static void fire(void Function() fn) {
    if (reduceEffects) return;
    fn();
  }
}
