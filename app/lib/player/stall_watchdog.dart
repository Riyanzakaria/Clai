/// Pengawas posisi macet (Blueprint 4.3, Sapuan D-09) — logika murni.
///
/// Aturan: pemutar mengaku SEDANG MEMUTAR, keadaan proses `ready` (di luar
/// buffering/loading), tetapi posisi tidak maju selama lebih dari
/// [stallThreshold] → aliran macet dan jalur pemulihan L-10 harus berjalan.
/// Sebelum sapuan, satu-satunya pemicu pemulihan adalah galat pemutar —
/// aliran yang menggantung senyap (koneksi mati di tengah tanpa galat)
/// membuat lagu "berputar" selamanya tanpa suara dan tanpa pemulihan.
class StallWatchdog {
  static const stallThreshold = Duration(seconds: 4);

  int? _lastPositionMs;
  DateTime? _lastAdvanceAt;
  bool _firedForStall = false;

  /// Beri makan satu sampel. Kembalikan true TEPAT SEKALI per episode macet
  /// (episode berakhir saat posisi maju lagi atau keadaan berubah).
  bool feed({
    required bool playing,
    required bool ready,
    required int positionMs,
    required DateTime now,
  }) {
    if (!playing || !ready) {
      _lastPositionMs = positionMs;
      _lastAdvanceAt = now;
      _firedForStall = false;
      return false;
    }
    if (_lastPositionMs == null || positionMs != _lastPositionMs) {
      _lastPositionMs = positionMs;
      _lastAdvanceAt = now;
      _firedForStall = false;
      return false;
    }
    if (_firedForStall) return false;
    final since = _lastAdvanceAt;
    if (since != null && now.difference(since) > stallThreshold) {
      _firedForStall = true;
      return true;
    }
    return false;
  }

  void reset() {
    _lastPositionMs = null;
    _lastAdvanceAt = null;
    _firedForStall = false;
  }
}

/// Keputusan refresh URL proaktif (PRD 5.4, Sapuan D-08) — murni.
///
/// Untuk trek hingga [maxAhead] posisi di depan trek berjalan: bila URL
/// tercache-nya tersisa valid kurang dari [threshold], segarkan SEKARANG
/// (buang cache + resolusi ulang) agar perpindahan lagu tidak membayar
/// resolusi di titik putar — sebelumnya penyegaran hanya reaktif sesudah
/// galat, persis di momen pengguna mendengar jeda.
bool shouldProactivelyRefresh(Duration? remaining, {int thresholdMinutes = 30}) {
  if (remaining == null) return false; // belum tercache: jalur normal yang mengurus
  if (remaining.isNegative) return false; // sudah kedaluwarsa: cachedStream menolaknya sendiri
  return remaining < Duration(minutes: thresholdMinutes);
}
