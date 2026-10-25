/// Metrik gerbang kualitas PRD Bab 3 (Sapuan B-01/D-02).
///
/// Sebelum sapuan, angka gerbang Bab 3 (ketuk→bunyi ≤2 dtk median / ≤4 dtk
/// p95, kegagalan putar <1% tanpa satu pun senyap, mulai dingin ≤1,5 dtk)
/// tidak diinstrumentasi sama sekali — Layar Diagnostik hanya menjalankan
/// uji rantai manual. Kelas ini mengumpulkan sampel NYATA dari pemakaian:
/// sampel ketuk→bunyi per perintah putar, penghitung percobaan/gagal putar,
/// dan durasi mulai dingin terakhir. Statistiknya fungsi murni agar teruji.
class GateMetrics {
  GateMetrics._();
  static final GateMetrics instance = GateMetrics._();

  final List<int> _tapToSoundMs = [];
  int playbackAttempts = 0;
  int playbackFailures = 0;
  int? coldStartMs;

  static const maxSamples = 200;

  void recordTapToSound(Duration d) {
    _tapToSoundMs.add(d.inMilliseconds);
    if (_tapToSoundMs.length > maxSamples) {
      _tapToSoundMs.removeRange(0, _tapToSoundMs.length - maxSamples);
    }
  }

  void recordAttempt() => playbackAttempts++;
  void recordFailure() => playbackFailures++;

  List<int> get tapToSoundSamples => List.unmodifiable(_tapToSoundMs);

  double get failureRatio =>
      playbackAttempts == 0 ? 0 : playbackFailures / playbackAttempts;

  /// Median sampel (ms); null bila kosong.
  int? get tapToSoundMedian => percentile(_tapToSoundMs, 50);

  /// Persentil-95 sampel (ms); null bila kosong.
  int? get tapToSoundP95 => percentile(_tapToSoundMs, 95);

  /// Persentil terdekat-peringkat atas daftar ms (murni, diuji unit).
  static int? percentile(List<int> values, int p) {
    if (values.isEmpty) return null;
    final sorted = List.of(values)..sort();
    final rank = ((p / 100) * sorted.length).ceil();
    final idx = (rank - 1).clamp(0, sorted.length - 1);
    return sorted[idx];
  }
}
