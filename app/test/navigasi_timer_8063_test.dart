import 'dart:io';

import 'package:clai/services/sleep_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ronde 8063 — Sleep Timer hilang saat Next/Previous manual
/// (temuan perangkat pada staging 8062, 14 Nov 2026): pemilik
/// melaporkan timer mati/hilang bila ia menekan Berikutnya/
/// Sebelumnya sendiri, sementara pergantian alami karena lagu
/// habis membiarkan timer normal.
///
/// Akar terbukti dari kode: skipToNext/skipToPrevious memanggil
/// kait onManualPlayAction TANPA syarat di awal fungsi, dan kait
/// itu tersambung ke SleepService.cancelOnManualAction yang
/// membatalkan timer aktif apa pun — aturan F2 lama "semua
/// interaksi manual membatalkan timer". Jalur selesai alami tidak
/// memanggil kait itu, persis cocok dengan laporan.
///
/// Perilaku baru yang dikunci di sini:
/// (1) Next/Previous manual memakai kait navigasi tersendiri
///     (handler.onManualTrackSkip → SleepService
///     .handleManualTrackSkip) dan TIDAK membatalkan timer aktif:
///     mode menit berjalan apa adanya di atas jam dinding; mode
///     akhir-lagu tetap terpasang, peredupan per-lagu lama
///     dipulihkan lewat onFadeCancel;
/// (2) timer yang SUDAH berbunyi: navigasi tetap membatalkan
///     simpanan Lanjut Besok ≤10 menit (onPostFireInteraction);
/// (3) memilih putaran/trek baru (playTracks, jumpTo langsung)
///     tetap memakai kait lama dan tetap membatalkan timer;
/// (4) eskalasi internal _verifyAdvance (yang memperbaiki Next
///     manual maupun lanjut otomatis lewat jumpTo ke target yang
///     sama) menandai preserveSleepTimer agar timer tidak batal
///     secara tidak langsung;
/// (5) lapisan kedua yang terbukti dari bukti emulator ronde ini:
///     _onIndexChanged menutup trek lama completed:true untuk SEMUA
///     perpindahan indeks maju (seekToNext perintah terlihat sama
///     dengan selesai alami baginya), sehingga onNaturalTrackEnd
///     ikut menembak pada skip manual dan timer akhir-lagu TERBAKAR
///     (fire) — sebelum ronde ini tertutup karena hook lama memang
///     sudah membatalkan timer lebih dulu. Kini skipToNext menandai
///     target lompatan perintahnya (_skipTargetKey) dan
///     _onIndexChanged menutup buku seperti biasa tetapi menekan
///     kait akhir alami (fireNaturalEnd: false) untuk lompatan
///     bertanda itu. Jalur crossfade terbukti sudah menutup skip
///     dengan completed:false secara eksplisit.
///
/// Handler konkret tidak bisa dibangun di unit test (konstruktornya
/// menyentuh kanal platform — kendala yang sama dicatat suite
/// 8054/8055/8057/8059), jadi paruh perilaku diuji pada layanan,
/// dan paruh kabel diverifikasi pada sumber dengan pola sapuan
/// yang sama seperti suite ronde sebelumnya.
void main() {
  group('SleepService.handleManualTrackSkip — perilaku', () {
    test('(1) mode menit: tetap aktif, endsAt & minutes sama persis, '
        'onFadeCancel TIDAK dipanggil', () {
      final s = SleepService();
      var fadeCancels = 0;
      s.onFadeCancel = () => fadeCancels++;
      s.startMinutes(30);
      final endsAt = s.active!.endsAt;
      // Persenjataan sendiri memanggil onFadeCancel sekali (memulihkan
      // peredupan basi) — hitung hanya yang berasal dari navigasi.
      fadeCancels = 0;
      s.handleManualTrackSkip();
      expect(s.active, isNotNull);
      expect(s.active!.mode, 'minutes');
      expect(s.active!.minutes, 30);
      expect(s.active!.endsAt, endsAt);
      expect(fadeCancels, 0,
          reason: 'rampa berbasis waktu mode menit berjalan apa adanya');
      s.cancel();
    });

    test('(2) mode akhir-lagu: tetap aktif, onFadeCancel dipanggil '
        'tepat sekali (peredupan trek lama dipulihkan)', () {
      final s = SleepService();
      var fadeCancels = 0;
      s.onFadeCancel = () => fadeCancels++;
      s.startEndOfSong();
      fadeCancels = 0; // abaikan panggilan persenjataan
      s.handleManualTrackSkip();
      expect(s.active, isNotNull);
      expect(s.active!.mode, 'endOfSong');
      expect(fadeCancels, 1);
      s.cancel();
    });

    test('(3) sudah berbunyi + lastFiredAt BARU (≤10 menit): '
        'onPostFireInteraction dipanggil, simpanan dibatalkan', () {
      final s = SleepService();
      var postFire = 0;
      s.onPostFireInteraction = () => postFire++;
      s.lastFiredAt = DateTime.now();
      s.handleManualTrackSkip();
      expect(postFire, 1);
      expect(s.lastFiredAt, isNull);
    });

    test('(4) sudah berbunyi + lastFiredAt LAMA (>10 menit): '
        'onPostFireInteraction TIDAK dipanggil', () {
      final s = SleepService();
      var postFire = 0;
      s.onPostFireInteraction = () => postFire++;
      final old = DateTime.now().subtract(const Duration(minutes: 11));
      s.lastFiredAt = old;
      s.handleManualTrackSkip();
      expect(postFire, 0);
      expect(s.lastFiredAt, old);
    });

    test('(5) kait lama tidak berubah: cancelOnManualAction tetap '
        'membatalkan timer aktif (memilih putaran/trek baru)', () {
      final s = SleepService();
      s.startMinutes(15);
      expect(s.active, isNotNull);
      s.cancelOnManualAction();
      expect(s.active, isNull);
    });
  });

  group('kabel navigasi pada sumber (struktur)', () {
    final handler = File('lib/player/audio_handler.dart').readAsStringSync();
    final app = File('lib/app.dart').readAsStringSync();

    String body(String src, String startMarker, String endMarker) {
      final start = src.indexOf(startMarker);
      expect(start, greaterThanOrEqualTo(0),
          reason: 'penanda awal tidak ditemukan: $startMarker');
      final end = src.indexOf(endMarker, start);
      expect(end, greaterThan(start),
          reason: 'penanda akhir tidak ditemukan: $endMarker');
      return src.substring(start, end);
    }

    test('(6) skipToNext memakai kait skip baru, BUKAN kait lama', () {
      final b = body(handler, 'Future<void> skipToNext() async {',
          'Future<void> skipToPrevious() async {');
      expect(b.contains('onManualTrackSkip?.call()'), isTrue);
      expect(b.contains('onManualPlayAction'), isFalse);
    });

    test('(7) skipToPrevious memakai kait skip baru, BUKAN kait lama',
        () {
      final b = body(handler, 'Future<void> skipToPrevious() async {',
          'Future<void> _previousViaHistory() async {');
      expect(b.contains('onManualTrackSkip?.call()'), isTrue);
      expect(b.contains('onManualPlayAction'), isFalse);
    });

    test('(8) app.dart menyambungkan kait baru ke layanan, kait lama '
        'tetap tersambung', () {
      expect(
          app.contains(
              'handler.onManualTrackSkip = () => sleep.handleManualTrackSkip();'),
          isTrue);
      expect(
          app.contains(
              'handler.onManualPlayAction = () => sleep.cancelOnManualAction();'),
          isTrue);
    });

    test('(9) jumpTo langsung tetap memakai kait lama di balik penjaga '
        'preserveSleepTimer', () {
      final start = handler.indexOf('Future<void> jumpTo(TrackKey k');
      expect(start, greaterThanOrEqualTo(0));
      final head = handler.substring(start, start + 1200);
      expect(head.contains('bool preserveSleepTimer = false'), isTrue);
      expect(
          head.contains(
              'if (!preserveSleepTimer && !_advancingFromCompleted)'),
          isTrue);
      expect(head.contains('onManualPlayAction?.call()'), isTrue);
    });

    test('(10) playTracks tetap memakai kait lama (memilih putaran '
        'baru membatalkan timer)', () {
      final start = handler.indexOf('Future<void> playTracks(');
      expect(start, greaterThanOrEqualTo(0));
      final head = handler.substring(start, start + 1400);
      expect(head.contains('onManualPlayAction?.call()'), isTrue);
      expect(head.contains('onManualTrackSkip'), isFalse);
    });

    test('(11) _verifyAdvance memakai penjaga preserveSleepTimer '
        'pada eskalasi jumpTo-nya', () {
      final b = body(handler, 'void _verifyAdvance(',
          'Future<void> retryAutoplayRefill()');
      expect(b.contains('jumpTo(toKey, preserveSleepTimer: true)'),
          isTrue);
    });

    test('(12) _advanceIntoContinuation tetap memanggil jumpTo biasa '
        '(terlindung flag _advancingFromCompleted)', () {
      final b = body(handler, 'Future<void> _advanceIntoContinuation()',
          'void _verifyAdvance(');
      expect(
          b.contains('await jumpTo(engine.effectiveQueue.first.key);'),
          isTrue);
      expect(b.contains('preserveSleepTimer'), isFalse);
    });

    test('(13) skipToNext menandai target lompatan perintah '
        '(_skipTargetKey) untuk listener indeks', () {
      final b = body(handler, 'Future<void> skipToNext() async {',
          'Future<void> skipToPrevious() async {');
      expect(b.contains('_skipTargetKey = nextKey;'), isTrue);
      expect(b.contains('_skipTargetAt = DateTime.now();'), isTrue);
    });

    test('(14) _onIndexChanged menekan kait akhir alami HANYA untuk '
        'lompatan bertanda perintah (fireNaturalEnd)', () {
      final b = body(handler, 'void _onIndexChanged(int sourceIndex) {',
          'void _syncEngineTo(int fullIndex) {');
      expect(b.contains('_skipTargetKey'), isTrue);
      expect(
          b.contains(
              '_closeTrackEvent(prev,\n            completed: true, fireNaturalEnd: fireNaturalEnd);'),
          isTrue);
    });

    test('(15) _closeTrackEvent hanya menembak onNaturalTrackEnd '
        'bila completed DAN fireNaturalEnd', () {
      final b = body(handler, 'void _closeTrackEvent(Track t,',
          '// ---------------- isi ulang Putar Otomatis ----------------');
      expect(b.contains('bool fireNaturalEnd = true'), isTrue);
      expect(b.contains('if (completed && fireNaturalEnd)'), isTrue);
    });

    test('(16) jalur crossfade menutup skip dengan completed: false '
        'secara eksplisit (tidak ada tembakan akhir alami palsu)', () {
      final xfNext = body(handler, 'Future<void> _xfSkipNext() async {',
          'Future<void> _xfSkipPrevious() async {');
      expect(
          xfNext.contains('_closeTrackEvent(cur, completed: false);'),
          isTrue);
      final xfPrev = body(handler,
          'Future<void> _xfSkipPrevious() async {',
          '// ---------------- perintah publik');
      expect(
          xfPrev.contains('_closeTrackEvent(prev, completed: false);'),
          isTrue);
    });
  });
}
