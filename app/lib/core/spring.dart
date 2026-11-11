import 'package:flutter/widgets.dart';

/// Parameter spring fisik DS Bab 5 — massa 1, overshoot tipis adalah nyawa.
/// Evolusi v4.0 (DS v4.0 §6.2): hero 180/24 → 165/22 (sedikit lebih berani
/// di momen pahlawan), skala tekan menuju 0,95 (lihat PressableScale),
/// stagger masuk daftar 30 → 26 md. Fisika TIDAK diganti easing.
class ClaiSprings {
  static const listIn = SpringDescription(mass: 1, stiffness: 260, damping: 26);
  static const hero = SpringDescription(mass: 1, stiffness: 165, damping: 22);
  static const sheet = SpringDescription(mass: 1, stiffness: 300, damping: 28);
  static const press = SpringDescription(mass: 1, stiffness: 400, damping: 22);
  static const trackChange = SpringDescription(mass: 1, stiffness: 200, damping: 26);

  /// Jeda antar item saat daftar masuk berurutan (v4.0: 26 md).
  static const stagger = Duration(milliseconds: 26);
}

/// Gerak-reduksi sistem (DS Bab 5, Sapuan D-05): true bila pengguna mematikan
/// animasi di tingkat sistem (MediaQuery.disableAnimations). Dalam mode ini
/// spring diganti crossfade 80 ms, marquee mati, dan denyut skeleton diam —
/// sebelumnya pengaturan aksesibilitas ini diabaikan total oleh aplikasi.
bool reducedMotionOf(BuildContext context) =>
    MediaQuery.maybeDisableAnimationsOf(context) ?? false;

/// Durasi efektif sebuah animasi: [normal] utuh, atau 80 ms saat gerak-reduksi.
Duration motionDuration(BuildContext context, Duration normal) =>
    reducedMotionOf(context) ? const Duration(milliseconds: 80) : normal;
