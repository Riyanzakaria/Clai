import 'dart:math' as math;

/// Matematika transisi audio (F2, ADR-002) — murni & teruji.
///
/// Crossfade memakai kurva equal-power (cosinus/sinus): pada tengah transisi
/// kedua lagu masing-masing berbunyi pada 0,707 (≈ −3 dB), sehingga kenyaringan
/// gabungan tetap rata — crossfade linear (0,5 + 0,5) justru terdengar menciut
/// di tengah karena daya gabungan turun.
({double outgoing, double incoming}) crossfadeVolumes(double t) {
  final c = t.clamp(0.0, 1.0);
  return (
    outgoing: math.cos(c * math.pi / 2),
    incoming: math.sin(c * math.pi / 2),
  );
}

/// Perataan gain normalisasi: interpolasi linear dari [from] ke [to] selama
/// [duration]; di luar rentang dijepit ke ujung (tanpa klik volume).
double smoothGain(double from, double to, Duration elapsed, Duration duration) {
  if (duration <= Duration.zero) return to;
  final t = (elapsed.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);
  return from + (to - from) * t;
}

/// Jeda transisi gapless (ms): dari peristiwa completed trek lama sampai
/// indeks pemutar berpindah ke trek baru. Diukur di handler & dicatat ke log
/// insiden — gerbang PRD ≤ 50 ms dibuktikan angka, bukan perasaan.
int? transitionGapMs(DateTime? completedAt, DateTime nextStartedAt) {
  if (completedAt == null) return null;
  return nextStartedAt.difference(completedAt).inMilliseconds;
}
