/// Pengawas koherensi sesi (Ronde Bug Notifikasi, 2026-11-04) — logika murni.
///
/// Cacat yang dijaga: perintah putar menyalakan NIAT putar pada pemain yang
/// tidak punya sumber (atau sumbernya tak pernah meninggalkan keadaan idle),
/// sehingga niat itu menetap `playing=true / proses=idle` tanpa batas —
/// sesi media menerbitkan keadaan tak-koheren dan permukaan sistem (panel
/// notifikasi / dynamic island) hanya menampilkan notifikasi polos
/// "Clai sedang berjalan" tanpa metadata dan tanpa kontrol yang bekerja.
/// Terbukti di emulator dari dua pintu: (a) klik sesi media pada sesi
/// kosong, (b) pembangunan sumber sesi pulih yang gagal di semua anak
/// tangga lalu play() tetap memanggil play() pemain.
///
/// Dua bentuk ketidakkoherenan, masing-masing MELEDAK SEKALI per episode:
/// - [CoherenceFault.sourcelessIntent]: niat menyala, TIDAK ada sumber,
///   proses idle > [sourcelessThreshold]. Tidak ada jalan sah keadaan ini
///   sembuh sendiri — satu-satunya transisi sah dari "niat tanpa sumber"
///   adalah pembangunan sumber, dan pembangunan selalu mendahului niat.
/// - [CoherenceFault.stuckIdle]: niat menyala, sumber terpasang, tetapi
///   proses idle dan posisi membeku > [stuckIdleThreshold] — sumber mati
///   yang tidak pernah melempar galat (pengawas posisi macet D-09 hanya
///   menjaga keadaan `ready`, jadi bentuk ini lolos darinya).
enum CoherenceFault { none, sourcelessIntent, stuckIdle }

class SessionCoherenceWatchdog {
  static const sourcelessThreshold = Duration(seconds: 4);
  static const stuckIdleThreshold = Duration(seconds: 10);

  DateTime? _sourcelessSince;
  bool _sourcelessFired = false;
  DateTime? _idleSince;
  int? _idlePositionMs;
  bool _idleFired = false;

  /// Beri makan satu sampel (detak 1 detik dari handler). Kembalikan fault
  /// TEPAT SEKALI per episode; episode berakhir saat syaratnya berhenti
  /// terpenuhi (niat mati / sumber terpasang / proses bergerak / posisi maju).
  CoherenceFault feed({
    required bool intentPlaying,
    required bool hasSource,
    required bool processingIdle,
    required int positionMs,
    required DateTime now,
  }) {
    // Cabang niat-tanpa-sumber.
    if (intentPlaying && !hasSource && processingIdle) {
      _sourcelessSince ??= now;
      if (!_sourcelessFired &&
          now.difference(_sourcelessSince!) > sourcelessThreshold) {
        _sourcelessFired = true;
        return CoherenceFault.sourcelessIntent;
      }
    } else {
      _sourcelessSince = null;
      _sourcelessFired = false;
    }
    // Cabang idle-macet-dengan-sumber.
    if (intentPlaying && hasSource && processingIdle) {
      if (_idlePositionMs != positionMs) {
        _idlePositionMs = positionMs;
        _idleSince = now;
        _idleFired = false;
      } else if (!_idleFired &&
          _idleSince != null &&
          now.difference(_idleSince!) > stuckIdleThreshold) {
        _idleFired = true;
        return CoherenceFault.stuckIdle;
      }
    } else {
      _idleSince = null;
      _idlePositionMs = null;
      _idleFired = false;
    }
    return CoherenceFault.none;
  }

  void reset() {
    _sourcelessSince = null;
    _sourcelessFired = false;
    _idleSince = null;
    _idlePositionMs = null;
    _idleFired = false;
  }
}
