import 'dart:async';

import 'package:flutter/foundation.dart';

/// Timer tidur & Lanjut Besok (F2 Batch 2, PRD 5.14 D).
/// - Mode menit: berbunyi setelah N menit.
/// - Mode akhir-lagu: berbunyi saat lagu berjalan berakhir alami
///   (dipegang handler.onNaturalTrackEnd — bukan saat skip manual).
/// F2.5: mode menit kini DIKHIRI peredupan di bentang akhirnya — rampa
/// volume turun selama [sleepFadeWindowFor] sebelum kedaluwarsa (kait
/// [onFadeStart] ke handler), sehingga saat timer berbunyi volume sudah
/// nol dan jeda tidak memotong kasar. Snapshot antrean PENUH tersimpan
/// ke pref 'sleep.last' untuk kartu "Lanjutkan dari semalam" di Beranda
/// (Sapuan D-15).
/// Interaksi putar manual membatalkan timer yang masih berjalan — KECUALI
/// aksi resume Lanjut Besok itu sendiri (flag satu-kali [resuming]).
/// Interaksi manual ≤10 menit SESUDAH timer berbunyi membatalkan simpanan
/// Lanjut Besok (pengguna sudah bangun & memilih sendiri — USER-FLOW F-10).
class SleepTimerState {
  final String mode; // 'minutes' | 'endOfSong'
  final DateTime? endsAt;
  final int? minutes;
  const SleepTimerState({required this.mode, this.endsAt, this.minutes});
}

/// Bentang peredupan tidur (F2.5): rampa volume menempati AKHIR masa
/// timer — 30 detik terakhir untuk timer panjang, proporsional (seperempat
/// masa) untuk timer pendek. Murni & diuji unit.
Duration sleepFadeWindowFor(Duration total) {
  if (total <= Duration.zero) return Duration.zero;
  final quarter = total ~/ 4;
  const cap = Duration(seconds: 30);
  return quarter > cap ? cap : quarter;
}

class SleepService extends ChangeNotifier {
  SleepTimerState? active;
  Timer? _timer;
  Duration _total = Duration.zero;
  bool _fadeBegun = false;

  /// Dipasang bootstrap: aksi saat timer berbunyi (fade + jeda + simpan posisi).
  Future<void> Function()? onFire;

  /// F2.5: dipanggil SEKALI saat peredupan akhir harus mulai; argumen =
  /// sisa waktu menuju kedaluwarsa (rampa diturunkan persis selama itu,
  /// sehingga volume mencapai nol tepat saat timer berbunyi).
  void Function(Duration remaining)? onFadeStart;

  /// F2.5: timer dibatalkan sesudah peredupan mulai — peredupan ikut batal
  /// dan volume dipulihkan.
  void Function()? onFadeCancel;

  /// Satu-kali: aksi putar berikutnya adalah resume Lanjut Besok.
  bool resuming = false;

  /// D-15: kapan timer terakhir berbunyi + kait pembatalan simpanan.
  DateTime? lastFiredAt;
  void Function()? onPostFireInteraction;
  static const postFireCancelWindow = Duration(minutes: 10);

  Duration? get remaining {
    final e = active?.endsAt;
    if (e == null) return null;
    final d = e.difference(DateTime.now());
    return d.isNegative ? Duration.zero : d;
  }

  void startMinutes(int minutes) {
    _timer?.cancel();
    onFadeCancel?.call(); // persenjataan baru: pulihkan peredupan basi
    _total = Duration(minutes: minutes);
    _fadeBegun = false;
    active = SleepTimerState(
      mode: 'minutes',
      minutes: minutes,
      endsAt: DateTime.now().add(_total),
    );
    // F2.5: penggerak jam-dinding per detik — satu mekanisme untuk ambang
    // peredupan DAN kedaluwarsa, konsisten dengan [remaining] yang memang
    // berbasis jam dinding. Granularitas 1 detik cukup untuk timer tidur.
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    notifyListeners();
  }

  void _tick() {
    final a = active;
    if (a == null || a.mode != 'minutes' || a.endsAt == null) return;
    final rem = a.endsAt!.difference(DateTime.now());
    if (rem <= Duration.zero) {
      fire();
      return;
    }
    if (!_fadeBegun && rem <= sleepFadeWindowFor(_total)) {
      _fadeBegun = true;
      onFadeStart?.call(rem);
    }
  }

  void startEndOfSong() {
    _timer?.cancel();
    _timer = null;
    onFadeCancel?.call(); // persenjataan baru: pulihkan peredupan basi
    _fadeBegun = false;
    active = const SleepTimerState(mode: 'endOfSong');
    notifyListeners();
  }

  /// Dipanggil handler saat lagu berakhir alami.
  void fireEndOfSong() {
    if (active?.mode == 'endOfSong') fire();
  }

  Future<void> fire() async {
    if (active == null) return;
    active = null;
    _timer?.cancel();
    _timer = null;
    _fadeBegun = false;
    lastFiredAt = DateTime.now();
    notifyListeners();
    final f = onFire;
    if (f != null) await f();
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
    active = null;
    _fadeBegun = false;
    // Selalu beri tahu handler: peredupan bisa sedang berjalan dari jalur
    // akhir-lagu (yang tidak melewati _fadeBegun layanan ini) — handler
    // yang menilai apakah ada yang perlu dipulihkan (no-op bila tidak).
    onFadeCancel?.call();
    notifyListeners();
  }

  /// Kait aksi putar manual dari handler.
  void cancelOnManualAction() {
    if (resuming) {
      resuming = false;
      return;
    }
    if (active != null) cancel();
    // D-15: interaksi ≤10 menit sesudah timer berbunyi membatalkan simpanan
    // Lanjut Besok — pengguna sudah bangun dan memilih putarannya sendiri.
    final fired = lastFiredAt;
    if (fired != null &&
        DateTime.now().difference(fired) <= postFireCancelWindow) {
      lastFiredAt = null;
      onPostFireInteraction?.call();
    }
  }
}
