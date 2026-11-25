/// Detektor ulang-trek-sama + parkir di ujung (Ronde 8087) — logika murni.
///
/// Pola yang sama dengan [StallWatchdog]: kelas ini hanya menerima sampel
/// keadaan pemain lewat [feed] dan mengembalikan keputusan TEPAT SEKALI
/// per episode; handler yang bertindak (log + pemulihan).
///
/// Cacat yang dideteksi (terbukti bangku, builds/bukti-ulang-3x/LAPORAN-2.md):
/// transisi periode tengah-jendela HILANG di akhir alami — pemain menyiapkan
/// ulang trek yang sama dari ±0 (keputusan [RepeatDecision.repeat]) atau
/// parkir di posisi == durasi dalam keadaan "berbunyi"
/// (keputusan [RepeatDecision.park]), tanpa galat/log apa pun.
///
/// Ambang terkunci (PROGRES Ronde 8087, keputusan 2):
/// - persenjatai tanda ulang pada posisi ≥ durasi − 1.500 md, hanya untuk
///   durasi ≥ 6.000 md (kedua zona tak boleh tumpang tindih);
/// - tanda ulang menembak saat sampel berikutnya kunci sama, posisi
///   ≤ 2.000 md, dan playing;
/// - tanda parkir: posisi ≥ durasi − 250 md (posisi bisa MELEWATI durasi)
///   dengan playing/completed bertahan kontinu ≥ 2.000 md;
/// - sesudah menembak: jeda dingin 5.000 md + wajib persenjataan segar.
library;

enum RepeatDecision { none, repeat, park }

class RepeatDetector {
  static const armWindowMs = 1500;
  static const resetBoundMs = 2000;
  static const minArmDurationMs = 6000;
  static const parkToleranceMs = 250;
  static const parkGraceMs = 2000;
  static const cooldownMs = 5000;

  String? _key;
  bool _armed = false;
  int? _armedPeriodIndex;

  /// Penanda mulai-ulang-sah yang belum terkonsumsi (lihat
  /// [noteLegitRestart]).
  bool _legitPending = false;

  /// Sesudah penanda sah membatalkan episode yang dipersenjatai,
  /// persenjataan ulang DIBLOKIR selama posisi masih di zona akhir —
  /// tik detektor bisa tiba di antara penanda dan seek-nya benar-benar
  /// berlaku; tanpa blokir ini sampel yang sama mempersenjatai ulang
  /// episode yang baru saja dibatalkan secara sah.
  bool _legitBlocksArm = false;

  DateTime? _parkSince;
  int? _parkPeriodIndex;
  DateTime? _cooldownUntil;

  /// Tandai mulai-ulang yang SAH dari handler: seek pengguna ke trek yang
  /// sama, restart Sebelumnya, atau putar-balik `shouldRewindBeforePlay`.
  /// Berlaku hanya untuk episode yang SEDANG dipersenjatai — penanda yang
  /// tiba saat tidak ada episode bersenjata gugur pada sampel berikutnya
  /// dan tidak membatalkan episode masa depan.
  void noteLegitRestart() {
    _legitPending = true;
  }

  void reset() {
    _key = null;
    _armed = false;
    _armedPeriodIndex = null;
    _legitPending = false;
    _legitBlocksArm = false;
    _parkSince = null;
    _parkPeriodIndex = null;
    _cooldownUntil = null;
  }

  void _fire(DateTime now) {
    _armed = false;
    _armedPeriodIndex = null;
    _parkSince = null;
    _parkPeriodIndex = null;
    _legitPending = false;
    _cooldownUntil = now.add(const Duration(milliseconds: cooldownMs));
  }

  /// Beri makan satu sampel keadaan pemain. [key] = kunci trek berjalan
  /// versi string (unik per trek); [periodIndex] = indeks periode pemain
  /// (gapless) atau null (crossfade — tak ada periode yang bisa dibaca).
  RepeatDecision feed({
    required String key,
    required int? periodIndex,
    required int positionMs,
    required int? durationMs,
    required bool playing,
    required bool completed,
    required bool loopOne,
    required DateTime now,
  }) {
    // Repeat-Satu: lumpuh total + keadaan bersih (keputusan 4). Loop
    // pemain menangani pengulangannya sendiri; tanda apa pun di sini
    // adalah positif palsu menurut definisi.
    if (loopOne) {
      reset();
      _key = key;
      return RepeatDecision.none;
    }

    // Kunci berubah = episode bersih (keputusan 3c).
    if (_key != key) {
      _key = key;
      _armed = false;
      _armedPeriodIndex = null;
      _legitPending = false;
      _legitBlocksArm = false;
      _parkSince = null;
      _parkPeriodIndex = null;
    }

    // Jeda dingin sesudah tembakan: jangan mempersenjatai dan jangan
    // mengakumulasi tenggang parkir — persenjataan sesudahnya selalu
    // segar menurut konstruksi.
    if (_cooldownUntil != null) {
      if (now.isBefore(_cooldownUntil!)) {
        _armed = false;
        _armedPeriodIndex = null;
        _parkSince = null;
        _parkPeriodIndex = null;
        return RepeatDecision.none;
      }
      _cooldownUntil = null;
    }

    final inArmZone =
        durationMs != null &&
        durationMs >= minArmDurationMs &&
        positionMs >= durationMs - armWindowMs;

    // Penanda mulai-ulang-sah (keputusan 3b): membatalkan episode yang
    // sedang dipersenjatai, tepat sekali, tanpa tembakan.
    if (_legitPending) {
      _legitPending = false;
      if (_armed) {
        _armed = false;
        _armedPeriodIndex = null;
        _parkSince = null;
        _parkPeriodIndex = null;
        _legitBlocksArm = true;
      }
    }
    if (_legitBlocksArm && !inArmZone) _legitBlocksArm = false;

    // Indeks periode berubah sejak persenjataan = transisi native yang
    // sah (keputusan 3a), termasuk trek-sama-berturut-turut yang sah.
    if (_armed && periodIndex != _armedPeriodIndex) {
      _armed = false;
      _armedPeriodIndex = null;
    }

    // Tanda ulang: dulu di zona akhir, kini kembali ke awal, kunci sama,
    // masih playing, tanpa satu pun pembeda sah di atas.
    if (_armed && playing && positionMs <= resetBoundMs) {
      _fire(now);
      return RepeatDecision.repeat;
    }

    // Tanda parkir: diam di pita toleransi ujung dengan keadaan
    // playing/completed bertahan kontinu. Keadaan TIDAK playing dan
    // TIDAK completed (jeda disengaja di dekat akhir) MEMBATALKAN
    // akumulasi — posisi diam di sana bukan parkir cacat.
    final inParkBand =
        durationMs != null &&
        durationMs > 0 &&
        positionMs >= durationMs - parkToleranceMs &&
        (playing || completed);
    if (inParkBand) {
      if (_parkSince == null || _parkPeriodIndex != periodIndex) {
        _parkSince = now;
        _parkPeriodIndex = periodIndex;
      } else if (now.difference(_parkSince!).inMilliseconds >= parkGraceMs) {
        _fire(now);
        return RepeatDecision.park;
      }
    } else {
      _parkSince = null;
      _parkPeriodIndex = null;
    }

    // Persenjataan tanda ulang (hanya zona akhir, durasi cukup panjang,
    // dan tidak diblokir penanda sah yang baru membatalkan episode ini).
    if (inArmZone && !_legitBlocksArm) {
      _armed = true;
      _armedPeriodIndex = periodIndex;
    }
    return RepeatDecision.none;
  }
}

/// Verifikasi perpindahan untuk penjaga `_verifyAdvance` (Ronde 8087,
/// keputusan 7) — murni, tabel kebenarannya diuji unit.
///
/// "Sudah berpindah" ⇔ kunci periode PEMAIN ≠ [fromKey] (gapless, dibaca
/// handler lewat `_sourceTracks[currentIndex]`). Bila kunci pemain tak
/// bisa dibaca ([playerKey] null — crossfade), ⇔ kunci MESIN ≠ [fromKey]
/// DAN pemain tidak parkir di ujung trek asal. Parkir di ujung
/// ([playerParkedAtEnd]) selalu dibaca BELUM berpindah: posisi pemain
/// yang masih ≥ ujung trek asal menutup celah parkir walau kunci mesin
/// sudah bergerak lebih dulu.
bool advanceVerified({
  required String? playerKey,
  required String? engineKey,
  required String fromKey,
  required bool playerParkedAtEnd,
}) {
  if (playerParkedAtEnd) return false;
  if (playerKey != null) return playerKey != fromKey;
  if (engineKey == null) return false;
  return engineKey != fromKey;
}
