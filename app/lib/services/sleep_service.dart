import 'dart:async';

import 'package:flutter/foundation.dart';

/// Timer tidur & Lanjut Besok (F2 Batch 2, PRD 5.14 D).
/// - Mode menit: berbunyi setelah N menit.
/// - Mode akhir-lagu: berbunyi saat lagu berjalan berakhir alami
///   (dipegang handler.onNaturalTrackEnd — bukan saat skip manual).
/// Saat berbunyi: pemutar memudar 30 detik (USER-FLOW F-10) lalu jeda, dan
/// snapshot antrean PENUH tersimpan ke pref 'sleep.last' untuk kartu
/// "Lanjutkan dari semalam" di Beranda (Sapuan D-15).
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

class SleepService extends ChangeNotifier {
  SleepTimerState? active;
  Timer? _timer;

  /// Dipasang bootstrap: aksi saat timer berbunyi (fade + jeda + simpan posisi).
  Future<void> Function()? onFire;

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
    active = SleepTimerState(
        mode: 'minutes',
        minutes: minutes,
        endsAt: DateTime.now().add(Duration(minutes: minutes)));
    _timer = Timer(Duration(minutes: minutes), fire);
    notifyListeners();
  }

  void startEndOfSong() {
    _timer?.cancel();
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
    lastFiredAt = DateTime.now();
    notifyListeners();
    final f = onFire;
    if (f != null) await f();
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
    active = null;
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
