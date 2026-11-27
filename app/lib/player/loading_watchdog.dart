/// Pengawas loading-abadi (Ronde 8092, F4) — logika murni.
///
/// Celah yang dijaga (terbukti dari kode, builds/bukti-lompat-cepat):
/// keadaan `playing == true` + `processingState` di loading/buffering
/// yang menetap tanpa kemajuan tidak dijaga watchdog mana pun —
/// StallWatchdog mensyaratkan `ready`, SessionCoherenceWatchdog hanya
/// mengenal `idle`, dan eskalasi-lompat hanya memeriksa kunci trek
/// sekali pada 1,5 dtk. Trek tujuan yang alirannya tidak pernah
/// mencapai `ready` dapat menggantung selamanya tanpa pemulihan.
///
/// Aturan: tembak TEPAT SEKALI per episode bila playing menyala,
/// keadaan proses loading/buffering, DAN tidak ada kemajuan — posisi
/// DAN posisi buffer sama-sama tidak berubah — selama
/// [loadingThreshold]. Kemajuan apa pun (posisi ATAU buffer bergerak)
/// mereset episode; keluar dari keadaan (tidak playing, atau proses
/// bukan loading/buffering) juga mereset. Loading yang lambat tetapi
/// buffer/posisinya masih maju TIDAK pernah menembak.
///
/// Ronde 8092 D1 (R5): tahapan diperluas — sesudah [LoadingStage.fire]
/// pertama, episode yang SAMA yang berlanjut TANPA kemajuan selama
/// [loadingThreshold] lagi menghasilkan [LoadingStage.escalated]
/// tepat sekali. Kemajuan di antara kedua tahap membatalkan eskalasi
/// (episode reset; macet berikutnya mulai dari tahap fire lagi).
enum LoadingStage { none, fire, escalated }

class LoadingWatchdog {
  static const loadingThreshold = Duration(seconds: 25);

  int? _lastPositionMs;
  int? _lastBufferedMs;
  DateTime? _lastAdvanceAt;
  DateTime? _firedAt;
  bool _firedForEpisode = false;
  bool _escalatedForEpisode = false;

  /// Lama keadaan macet saat ini diukur dari [now]; null bila belum
  /// ada sampel episode yang berjalan.
  Duration? stuckDuration(DateTime now) {
    final since = _lastAdvanceAt;
    if (since == null || _lastPositionMs == null) return null;
    return now.difference(since);
  }

  /// Beri makan satu sampel. Kembalikan tahap episode macet ini:
  /// [LoadingStage.fire] tepat sekali pada ambang pertama,
  /// [LoadingStage.escalated] tepat sekali pada ambang kedua (episode
  /// berakhir saat ada kemajuan atau keadaan berubah).
  LoadingStage feed({
    required bool playing,
    required bool loadingOrBuffering,
    required int positionMs,
    required int bufferedPositionMs,
    required DateTime now,
  }) {
    if (!playing || !loadingOrBuffering) {
      _lastPositionMs = positionMs;
      _lastBufferedMs = bufferedPositionMs;
      _lastAdvanceAt = now;
      _firedForEpisode = false;
      _escalatedForEpisode = false;
      _firedAt = null;
      return LoadingStage.none;
    }
    if (_lastPositionMs == null ||
        positionMs != _lastPositionMs ||
        bufferedPositionMs != _lastBufferedMs) {
      _lastPositionMs = positionMs;
      _lastBufferedMs = bufferedPositionMs;
      _lastAdvanceAt = now;
      _firedForEpisode = false;
      _escalatedForEpisode = false;
      _firedAt = null;
      return LoadingStage.none;
    }
    if (!_firedForEpisode) {
      final since = _lastAdvanceAt;
      if (since != null && now.difference(since) > loadingThreshold) {
        _firedForEpisode = true;
        _firedAt = now;
        return LoadingStage.fire;
      }
      return LoadingStage.none;
    }
    // Ronde 8092 D1 (R5): tahap kedua — episode yang sama berlanjut
    // tanpa kemajuan selama satu ambang lagi sesudah fire pertama.
    if (!_escalatedForEpisode) {
      final firedAt = _firedAt;
      if (firedAt != null && now.difference(firedAt) > loadingThreshold) {
        _escalatedForEpisode = true;
        return LoadingStage.escalated;
      }
    }
    return LoadingStage.none;
  }

  void reset() {
    _lastPositionMs = null;
    _lastBufferedMs = null;
    _lastAdvanceAt = null;
    _firedAt = null;
    _firedForEpisode = false;
    _escalatedForEpisode = false;
  }
}

/// Ronde 8092 D1 (R6): kemajuan muat trek tujuan lompatan — murni.
/// True bila kunci sudah di target, pemain masih loading/buffering,
/// dan posisi belum melebihi posisi yang tercatat saat lompatan
/// dilakukan: perpindahan kunci saja belum berarti trek termuat.
bool loadProgressStalled({
  required bool keyAtTarget,
  required bool loadingOrBuffering,
  required int positionMs,
  required int positionAtJumpMs,
}) =>
    keyAtTarget && loadingOrBuffering && positionMs <= positionAtJumpMs;

/// Target verifikasi lompatan yang DAPAT DIGANTI (Ronde 8092, F3) —
/// logika murni penjadwalan `_verifyAdvance`.
///
/// Dulu penjaga tunggal membuang panggilan berikutnya selama satu
/// verifikasi tertunda, sehingga dalam rentetan lompat cepat hanya
/// lompatan PERTAMA yang terverifikasi. Kini setiap panggilan
/// memperbarui target (from/to/what) dan cap waktu upaya terakhir;
/// verifikasi jatuh [delay] sesudah upaya TERAKHIR, bukan pertama.
class AdvanceVerifyTarget {
  static const delay = Duration(milliseconds: 1500);

  /// Ronde 8092 D1 (R6): tunda pemeriksaan kemajuan muat susulan.
  static const loadRecheckDelay = Duration(seconds: 5);

  String? fromKey;
  String? toKey;
  String? what;
  DateTime? lastAttemptAt;

  /// Ronde 8092 D1 (R6): posisi pemain saat lompatan dilakukan, dan
  /// penanda persenjataan ulang pemeriksaan muat (maks SATU per
  /// target — diatur ulang oleh setiap [update]).
  int? positionAtJumpMs;
  bool loadRearmed = false;

  bool get hasTarget => fromKey != null && toKey != null && what != null;

  /// Catat upaya maju terbaru: target lama diganti seluruhnya.
  void update({
    required String from,
    required String to,
    required String whatLabel,
    required DateTime now,
    int? positionMs,
  }) {
    fromKey = from;
    toKey = to;
    what = whatLabel;
    lastAttemptAt = now;
    positionAtJumpMs = positionMs;
    loadRearmed = false;
  }

  /// Ronde 8092 D1 (R6): persenjatai ulang pemeriksaan muat SATU kali
  /// per target. True bila persenjataan ini yang pertama; false bila
  /// target ini sudah pernah dipersenjatai ulang.
  bool tryArmLoadRecheck() {
    if (loadRearmed) return false;
    loadRearmed = true;
    return true;
  }

  /// True bila target ada dan tenggatnya (1,5 dtk sesudah upaya
  /// terakhir) sudah tiba pada [now].
  bool due(DateTime now) {
    final at = lastAttemptAt;
    if (!hasTarget || at == null) return false;
    return !now.isBefore(at.add(delay));
  }

  void clear() {
    fromKey = null;
    toKey = null;
    what = null;
    lastAttemptAt = null;
    positionAtJumpMs = null;
    loadRearmed = false;
  }
}
