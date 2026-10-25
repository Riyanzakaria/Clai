import 'package:flutter/widgets.dart';

/// Parameter spring fisik DS Bab 5 — massa 1, overshoot tipis adalah nyawa.
class ClaiSprings {
  static const listIn = SpringDescription(mass: 1, stiffness: 260, damping: 26);
  static const hero = SpringDescription(mass: 1, stiffness: 180, damping: 24);
  static const sheet = SpringDescription(mass: 1, stiffness: 300, damping: 28);
  static const press = SpringDescription(mass: 1, stiffness: 400, damping: 22);
  static const trackChange = SpringDescription(mass: 1, stiffness: 200, damping: 26);
}

/// Gerak-reduksi sistem (DS Bab 5, Sapuan D-05): true bila pengguna mematikan
/// animasi di tingkat sistem (MediaQuery.disableAnimations). Dalam mode ini
/// spring diganti crossfade 80 ms, marquee mati, dan denyut skeleton diam —
/// sebelumnya pengaturan aksesibilitas ini diabaikan total oleh aplikasi.
bool reducedMotionOf(BuildContext context) =>
    MediaQuery.maybeOf(context)?.disableAnimations ?? false;

/// Durasi efektif sebuah animasi: [normal] utuh, atau 80 ms saat gerak-reduksi.
Duration motionDuration(BuildContext context, Duration normal) =>
    reducedMotionOf(context) ? const Duration(milliseconds: 80) : normal;
