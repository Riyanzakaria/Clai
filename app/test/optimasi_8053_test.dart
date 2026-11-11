import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:clai/app.dart';
import 'package:clai/data/app_db.dart';
import 'package:clai/services/ambient_controller.dart';
import 'package:clai/services/ambient_theme.dart';
import 'package:clai/ui/widgets.dart';

/// Tes pengunci Ronde Optimasi 8053.
///
/// B(i) — irisan UI ambien: terbitan napas (yang HANYA mengubah
/// breathFactor) tidak boleh membangun ulang konsumen UI mana pun;
/// perubahan visual sungguhan (strength/palet/sakelar) tetap wajib
/// menyebar. Sekaligus membuktikan jalur napasnya sendiri TIDAK
/// kelaparan oleh irisan (pelajaran gerbang G-1: gerbang yang
/// membungkam konsumen yang salah = fitur mati diam-diam).
///
/// B(ii) — gerbang ticker EqualizerBars: controller diam total saat
/// baris statis / tab tersembunyi (TickerMode), dan BANGUN LAGI saat
/// kembali beranimasi / tampil. Bungkam permanen = gagal.
/// DB pura-pura: pref selalu kosong → pengontrol ambien memakai
/// bawaan (tema menyala, napas menyala, strength hidup) tanpa
/// menyentuh plugin berkas sama sekali.
class _PrefDb extends AppDb {
  @override
  Future<T?> pref<T>(String key) async => null;

  @override
  Future<void> setPref(String key, Object? value) async {}
}

void main() {
  group('8053 B(i) — irisan UI kebal napas, peka perubahan nyata', () {
    test('napas bergerak: irisan diam, breathProvider bergerak; '
        'strength berubah: irisan ikut berubah', () async {
      final controller = AmbientController(_PrefDb());
      final container = ProviderContainer(
        overrides: [
          ambientControllerProvider.overrideWith((ref) => controller),
        ],
      );
      // Kepemilikan pengontrol diserahkan ke kontainer (dispose-nya
      // ikut kontainer) — jangan dispose dua kali.
      addTearDown(container.dispose);

      // Tunggu muat prefs awal pengontrol sampai keadaan menetap
      // (dua baca berurutan yang identik) sebelum mulai mendengar —
      // emisi muat-prefs bukan bagian dari yang diuji.
      AmbientUiState? prev;
      for (var i = 0; i < 40; i++) {
        final cur =
            container.read(ambientControllerProvider.select(ambientUiSlice));
        if (prev != null && cur == prev) break;
        prev = cur;
        await Future<void>.delayed(const Duration(milliseconds: 60));
      }
      final slice0 =
          container.read(ambientControllerProvider.select(ambientUiSlice));
      final breath0 = container.read(
          ambientControllerProvider.select((s) => s.breathFactor));
      expect(breath0, 1.0, reason: 'amplop mulai netral');

      var sliceChanges = 0;
      var stateChanges = 0;
      final subSlice = container.listen(
        ambientControllerProvider.select(ambientUiSlice),
        (_, _) => sliceChanges++,
      );
      final subState = container.listen(
        ambientControllerProvider,
        (_, _) => stateChanges++,
      );
      addTearDown(() {
        subSlice.close();
        subState.close();
      });

      // Umpan RMS kencang berulang dengan jeda nyata (laju amplop
      // 0,30 level/dtk — 4 umpan ±320 md menggerakkan faktor jauh
      // melewati deadband terbit 0,004).
      for (var i = 0; i < 4; i++) {
        controller.feedRms(-6, playing: true);
        await Future<void>.delayed(const Duration(milliseconds: 320));
      }

      final breath1 = container.read(
          ambientControllerProvider.select((s) => s.breathFactor));
      expect(
        (breath1 - breath0).abs(),
        greaterThan(0.02),
        reason: 'jalur napas sendiri harus tetap hidup (faktor bergerak)',
      );
      expect(
        stateChanges,
        greaterThan(0),
        reason: 'pengontrol memang menerbitkan keadaan selama umpan',
      );
      expect(
        sliceChanges,
        0,
        reason: 'irisan UI TIDAK boleh berubah oleh napas semata',
      );
      expect(container.read(ambientControllerProvider.select(ambientUiSlice)),
          slice0);

      // Perubahan visual sungguhan wajib tetap menyebar ke irisan.
      await controller.setStrength(AmbientStrength.tenang);
      expect(
        sliceChanges,
        greaterThan(0),
        reason: 'ganti strength harus membangunkan konsumen irisan',
      );
      expect(
          container.read(ambientControllerProvider.select(ambientUiSlice)).strength,
          AmbientStrength.tenang);
    });
  });

  group('8053 B(ii) — gerbang ticker EqualizerBars', () {
    Widget wrap({required bool animating, required bool tickerOn}) {
      return MaterialApp(
        home: TickerMode(
          enabled: tickerOn,
          child: Center(child: EqualizerBars(animating: animating)),
        ),
      );
    }

    testWidgets('statis = ticker diam; beranimasi = hidup; TickerMode '
        'membungkam lalu MEMBANGUNKAN lagi', (tester) async {
      // Baris statis (trek tidak diputar): controller tidak berlari.
      await tester.pumpWidget(wrap(animating: false, tickerOn: true));
      await tester.pump(const Duration(milliseconds: 120));
      expect(
        tester.binding.hasScheduledFrame,
        isFalse,
        reason: 'baris statis tidak boleh menjadwalkan bingkai apa pun',
      );

      // Diputar: ticker hidup (transisi didUpdateWidget yang sama
      // seperti pergantian trek di aplikasi).
      await tester.pumpWidget(wrap(animating: true, tickerOn: true));
      await tester.pump(const Duration(milliseconds: 120));
      expect(
        tester.binding.hasScheduledFrame,
        isTrue,
        reason: 'baris beranimasi harus menjadwalkan bingkai',
      );

      // Tab disembunyikan (TickerMode mati, pola IndexedStack cangkang):
      // ticker membisu walau animating tetap true.
      await tester.pumpWidget(wrap(animating: true, tickerOn: false));
      await tester.pump(const Duration(milliseconds: 120));
      expect(
        tester.binding.hasScheduledFrame,
        isFalse,
        reason: 'tab tersembunyi tidak boleh menjadwalkan bingkai',
      );

      // Tab tampil lagi: ticker WAJIB bangun — gerbang yang membunuh
      // permanen adalah kelas bug G-1.
      await tester.pumpWidget(wrap(animating: true, tickerOn: true));
      await tester.pump(const Duration(milliseconds: 120));
      expect(
        tester.binding.hasScheduledFrame,
        isTrue,
        reason: 'ticker harus bangun lagi saat tab kembali tampil',
      );

      // Jeda lagi: diam lagi.
      await tester.pumpWidget(wrap(animating: false, tickerOn: true));
      await tester.pump(const Duration(milliseconds: 120));
      expect(tester.binding.hasScheduledFrame, isFalse);
    });
  });
}
