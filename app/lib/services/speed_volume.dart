import 'dart:math' as math;

/// Median dari daftar (murni, diuji unit).
double median(List<double> values) {
  if (values.isEmpty) return 0;
  final s = List<double>.from(values)..sort();
  final m = s.length ~/ 2;
  return s.length.isOdd ? s[m] : (s[m - 1] + s[m]) / 2;
}

/// Target Volume Ikut Kecepatan (PRD 5.14 A) — murni, diuji unit.
/// Mengembalikan null = BEKU (volume tetap, gagal-aman): akurasi buruk,
/// interupsi (panggilan/notifikasi), atau belum ada sampel.
/// - [medianKmh]: median kecepatan 10 detik terakhir.
/// - [stoppedLong]: median ≈ berhenti selama > 15 detik → kembali ke titik berhenti.
/// - Selain itu: interpolasi linear titik berhenti → titik tercepat,
///   dijepit ke rentang itu — plafon pengguna tidak pernah dilampaui.
double? speedVolumeTarget({
  required double medianKmh,
  required double stopVolume,
  required double fastVolume,
  required double anchorKmh,
  required bool poorAccuracy,
  required bool interrupted,
  required bool stoppedLong,
}) {
  if (poorAccuracy || interrupted) return null;
  if (stoppedLong) return stopVolume;
  final f = (medianKmh / anchorKmh).clamp(0.0, 1.0);
  final lo = math.min(stopVolume, fastVolume);
  final hi = math.max(stopVolume, fastVolume);
  return (stopVolume + (fastVolume - stopVolume) * f).clamp(lo, hi);
}

/// Langkah ramp maksimal per 2 detik: 5% dari rentang (keputusan RENCANA).
double speedVolumeStep(double stopVolume, double fastVolume) =>
    (fastVolume - stopVolume).abs() * 0.05;
