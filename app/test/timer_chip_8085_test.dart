import 'package:clai/services/sleep_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ronde 8085 — chip hitung mundur timer tidur di mini player membeku.
///
/// Mekanisme TERBUKTI dari kode: SleepService._tick() dipanggil
/// Timer.periodic 1 detik dan menggerakkan fade/fire dengan benar,
/// tetapi (sebelum ronde ini) tidak pernah memanggil
/// notifyListeners(). Mini player membaca
/// ref.watch(sleepServiceProvider).remaining — getter jam-dinding —
/// sehingga tampilan hanya terbaca ulang saat widget terbangun oleh
/// sebab lain.
///
/// Perbaikan yang dikunci di sini: _tick memberi tahu pendengar HANYA
/// saat detik tampil (remaining.inSeconds) berubah dari yang terakhir
/// diberitahukan.
///
/// Catatan pendekatan: fake_async TIDAK dipakai — ia bukan
/// dev_dependency langsung repo ini (hanya transitif via flutter_test,
/// impornya menambah isu depend_on_referenced_packages) dan versi
/// 1.3.3 yang terkunci tidak memalsukan DateTime.now (terverifikasi:
/// elapse 1 dtk palsu menggerakkan jam nyata hanya ±23 mdtk),
/// sementara SleepService berbasis jam-dinding. Maka tes memakai
/// timer nyata seperti suite 8063, dengan endsAt digeser untuk
/// menciptakan tick yang detik tampilnya SENGAJA tidak berubah.
void main() {
  group('SleepService — notify per detik tampil (Ronde 8085)', () {
    test('(a) sesudah startMinutes, pendengar menerima notify ketika '
        'detik tampil berubah antar tick', () async {
      final s = SleepService();
      var notifies = 0;
      s.addListener(() => notifies++);
      s.startMinutes(1);
      expect(notifies, 1, reason: 'notify persenjataan dari start');
      expect(s.remaining!.inSeconds, 59,
          reason: 'getter jam-dinding: sisa < 60 dtk sesaat sesudah start');
      // Tick pertama jatuh ±1 detik sesudah start; sisa tampil turun
      // ke 58–59 detik (≠ 60 yang diberitahukan saat start) → notify.
      await Future<void>.delayed(const Duration(milliseconds: 1600));
      expect(notifies, greaterThanOrEqualTo(2),
          reason: 'tick dengan detik tampil berubah wajib notify');
      expect(s.remaining!.inSeconds, lessThan(59));
      s.cancel();
    });

    test('(b) tick yang detik tampilnya BELUM berubah tidak memicu '
        'notify berlebih; tick berikutnya yang berubah tetap notify',
        () async {
      final s = SleepService();
      var notifies = 0;
      s.addListener(() => notifies++);
      s.startMinutes(1);
      expect(notifies, 1);
      // Geser tenggat +1,5 detik: tick pertama (±1 dtk) mendarat pada
      // sisa ±60,5 dtk → inSeconds 60, SAMA dengan penanda saat start
      // → penjaga di _tick harus menahan notify. Tick kedua (±2 dtk)
      // mendarat pada ±59,5 dtk → inSeconds 59 → harus notify.
      s.active = SleepTimerState(
        mode: 'minutes',
        minutes: 1,
        endsAt: s.active!.endsAt!.add(const Duration(milliseconds: 1500)),
      );
      await Future<void>.delayed(const Duration(milliseconds: 1300));
      expect(notifies, 1,
          reason: 'tick dengan detik tampil sama tidak boleh notify');
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      expect(notifies, 2,
          reason: 'tick saat detik tampil berubah harus notify');
      s.cancel();
    });
  });
}
