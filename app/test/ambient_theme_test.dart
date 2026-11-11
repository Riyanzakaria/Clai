import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:clai/core/tokens.dart';
import 'package:clai/services/ambient_theme.dart';

/// Mesin tema "Sampul Hidup" (DS v4.0 §5, Workstream E F3): derivasi
/// tinta deterministik, undakan penjaga keterbacaan, dosis per jenis
/// layar, tinta menetap anti-kedip, amplop napas U1, dan saklar mati =
/// perilaku v3.1 persis (palet tidak aktif, nol wash, nol tint).
void main() {
  group('derivasi tinta — deterministik & terjepit', () {
    test('normalisasi: hasil sama untuk masukan sama (deterministik)', () {
      const src = Color(0xFF2E7D6B);
      expect(normalizeAmbientSource(src), normalizeAmbientSource(src));
    });

    test('normalisasi: saturasi ×0,75 dan lightness dijepit 0,18–0,38', () {
      // Merah jenuh terang: saturasi 1 → 0,75; lightness 0,5 → 0,38.
      final n = normalizeAmbientSource(const Color(0xFFFF0000));
      final hsl = HSLColor.fromColor(n);
      expect(hsl.saturation, closeTo(0.75, 0.01));
      expect(hsl.lightness, closeTo(0.38, 0.01));
      // Warna gelap redup: lightness naik ke lantai 0,18.
      final dark = normalizeAmbientSource(const Color(0xFF101418));
      expect(HSLColor.fromColor(dark).lightness, closeTo(0.18, 0.01));
    });

    test('monokrom terdeteksi; warna jenuh bukan monokrom', () {
      expect(isAmbientMonochrome(const Color(0xFF808080)), isTrue);
      expect(isAmbientMonochrome(const Color(0xFF2E7D6B)), isFalse);
    });

    test('palet: sampul monokrom → cadangan amb/diam', () {
      final p = buildAmbientPalette(
        source: const Color(0xFF8A8A8A),
        enabled: true,
        strength: AmbientStrength.hidup,
      );
      expect(p.active, isTrue);
      expect(p.fallbackDiam, isTrue);
      expect(p.norm, ambientDiamColor());
    });

    test('palet: sampul berwarna → norm adalah normalisasinya', () {
      const src = Color(0xFFB3541E);
      final p = buildAmbientPalette(
        source: src,
        enabled: true,
        strength: AmbientStrength.hidup,
      );
      expect(p.fallbackDiam, isFalse);
      // 8045: mode Hidup menahan saturasi lebih banyak (0,90).
      expect(p.norm, normalizeAmbientSource(src, saturationScale: 0.90));
    });
  });

  group('penjaga keterbacaan — teks tidak pernah dikorbankan', () {
    test('undakan guard: bentuk baku menurun dari permintaan', () {
      expect(guardLadder(0.28), [0.28, 0.18, 0.10, 0.0]);
      expect(guardLadder(0.16), [0.16, 0.10, 0.0]);
      expect(guardLadder(0.40).first, 0.40);
      expect(guardLadder(0.40).last, 0.0);
    });

    test('norm dalam pita: kekuatan penuh lulus (ink ≥ 4,5 di atasnya)', () {
      final norm = normalizeAmbientSource(const Color(0xFF2E7D6B));
      final s = guardAmbientStrength(norm, ClaiAmbient.washCapLively);
      expect(s, ClaiAmbient.washCapLively);
      final comp = compositeOver(norm.withValues(alpha: s), ClaiColors.base);
      expect(contrastOf(ClaiColors.ink, comp), greaterThanOrEqualTo(4.5));
    });

    test('norm TERANG di atas alas TERANG: penjaga menurunkan undakan '
        'sampai ink lulus — tidak pernah mengembalikan kekuatan yang '
        'melanggar', () {
      // Di atas alas gelap aplikasi wash terang 28% tetap aman (komposit
      // tetap gelap); penjaga menggigit bila alasnya terang — diuji
      // lewat parameter alas yang memang disediakan fungsi penjaga.
      const bright = Color(0xFFD8E4F0);
      const lightBase = Color(0xFFB9C2CC);
      final s = guardAmbientStrength(
        bright,
        ClaiAmbient.washCapLively,
        base: lightBase,
      );
      expect(s, lessThan(ClaiAmbient.washCapLively));
      if (s > 0) {
        final comp =
            compositeOver(bright.withValues(alpha: s), lightBase);
        expect(contrastOf(ClaiColors.ink, comp), greaterThanOrEqualTo(4.5));
      }
      // Dan di atas alas gelap aplikasi, wash yang sama memang lulus
      // penuh — penjaga tidak menurunkan yang tidak perlu diturunkan.
      expect(
        guardAmbientStrength(bright, ClaiAmbient.washCapLively),
        ClaiAmbient.washCapLively,
      );
    });

    test('ink-soft: selalu lulus ≥4,5 di atas permukaan setempat', () {
      final norm = normalizeAmbientSource(const Color(0xFFB3541E));
      final over = compositeOver(
        norm.withValues(alpha: 0.28),
        ClaiColors.base,
      );
      final soft = ambientInkSoft(norm, over);
      expect(contrastOf(soft, over), greaterThanOrEqualTo(4.5));
    });

    test('kekuatan tenang memakai plafon tenang', () {
      final p = buildAmbientPalette(
        source: const Color(0xFF2E7D6B),
        enabled: true,
        strength: AmbientStrength.tenang,
      );
      expect(p.washStrength, lessThanOrEqualTo(ClaiAmbient.washCapCalm));
    });
  });

  group('dosis per jenis layar', () {
    test('hero = kekuatan efektif penuh', () {
      expect(
        ambientDoseFor(AmbientSurfaceKind.hero, 0.28, AmbientStrength.hidup),
        0.28,
      );
    });

    test('player = skala plafon Player, dijepit plafonnya', () {
      final d = ambientDoseFor(
        AmbientSurfaceKind.player,
        0.28,
        AmbientStrength.hidup,
      );
      // 8045: pada kekuatan efektif 0,28 dosis Player belum jenuh —
      // 0,28 × (plafonPlayer/plafonHidup); jenuh tepat di plafon
      // Player bila kekuatan efektif = plafon Hidup.
      expect(
          d,
          closeTo(0.28 * (ClaiAmbient.washCapPlayer / ClaiAmbient.washCapLively),
              1e-9));
      expect(
          ambientDoseFor(AmbientSurfaceKind.player, ClaiAmbient.washCapLively,
              AmbientStrength.hidup),
          closeTo(ClaiAmbient.washCapPlayer, 1e-9));
      // Tenang: terskala 0,16/0,28 dari hidup.
      final calm = ambientDoseFor(
        AmbientSurfaceKind.player,
        0.16,
        AmbientStrength.tenang,
      );
      expect(calm, lessThan(d));
      // 8045: plafon naik (Player 0,50 / Hidup 0,44) — rumus diturunkan
      // dari konstanta agar tidak basi lagi.
      final want = 0.16 *
          (ClaiAmbient.washCapPlayer / ClaiAmbient.washCapLively) *
          (0.16 / ClaiAmbient.washCapLively);
      expect(calm, closeTo(want, 1e-9));
    });

    test('tugas = 40% dari kekuatan efektif', () {
      expect(
        ambientDoseFor(AmbientSurfaceKind.task, 0.28, AmbientStrength.hidup),
        closeTo(0.28 * 0.40, 1e-9),
      );
    });
  });

  group('saklar tema mati / tanpa sampul = v3.1 persis', () {
    test('palet tidak aktif: nol wash, nol tint, ink-soft klasik', () {
      for (final p in [
        buildAmbientPalette(
          source: const Color(0xFFFF5722),
          enabled: false,
          strength: AmbientStrength.hidup,
        ),
        buildAmbientPalette(
          source: null,
          enabled: true,
          strength: AmbientStrength.hidup,
        ),
      ]) {
        expect(p, AmbientPalette.inactive);
        expect(p.active, isFalse);
        expect(
          p.washColor(AmbientSurfaceKind.hero, AmbientStrength.hidup),
          Colors.transparent,
        );
        expect(
          p.washColor(AmbientSurfaceKind.player, AmbientStrength.hidup),
          Colors.transparent,
        );
        expect(p.glassTint, Colors.transparent);
        expect(p.glowColor, Colors.transparent);
        expect(p.glassEdge, ClaiColors.divider);
        expect(p.inkSoftOver(ClaiColors.base), ClaiColors.inkSecondary);
      }
    });
  });

  group('tinta menetap (anti-kedip ganti trek cepat)', () {
    final t0 = DateTime(2026, 11, 9, 7, 0);

    test('trek pertama terpasang seketika', () {
      final s = TintSettler();
      expect(s.onSource('a', t0), 'a');
      expect(s.committedKey, 'a');
    });

    test('ganti cepat A→B→C: tetap A sampai 1,5 dtk sesudah C, lalu C', () {
      final s = TintSettler();
      s.onSource('a', t0);
      expect(s.onSource('b', t0.add(const Duration(milliseconds: 400))), isNull);
      expect(s.onSource('c', t0.add(const Duration(milliseconds: 800))), isNull);
      expect(
        s.tick(t0.add(const Duration(milliseconds: 2000))),
        isNull,
        reason: 'baru 1,2 dtk sejak C — belum menetap',
      );
      expect(s.committedKey, 'a');
      expect(
        s.tick(t0.add(const Duration(milliseconds: 2300))),
        'c',
        reason: '1,5 dtk sejak C — terpasang',
      );
      expect(s.committedKey, 'c');
    });

    test('kembali ke trek terpasang membatalkan yang tertunda', () {
      final s = TintSettler();
      s.onSource('a', t0);
      s.onSource('b', t0.add(const Duration(milliseconds: 300)));
      expect(s.onSource('a', t0.add(const Duration(milliseconds: 600))), isNull);
      expect(s.pendingKey, isNull);
      expect(
        s.tick(t0.add(const Duration(seconds: 5))),
        isNull,
      );
      expect(s.committedKey, 'a');
    });

    test('reset: pemasangan berikutnya seketika lagi', () {
      final s = TintSettler();
      s.onSource('a', t0);
      s.reset();
      expect(s.onSource('b', t0), 'b');
    });
  });

  group('amplop napas U1 — lambat & terbatas', () {
    test('pemetaan RMS: −55 dB → 0, −15 dB → 1, tengah linear', () {
      expect(BreathEnvelope.targetForRmsDb(-55), 0);
      expect(BreathEnvelope.targetForRmsDb(-15), 1);
      expect(BreathEnvelope.targetForRmsDb(-35), closeTo(0.5, 1e-9));
      expect(BreathEnvelope.targetForRmsDb(-80), 0);
      expect(BreathEnvelope.targetForRmsDb(0), 1);
    });

    test('level mulai di NETRAL 0,5 dan faktor mulai TEPAT 1,0', () {
      // Koherensi inisialisasi (perbaikan U1): pemasangan segar tidak
      // boleh membuka Player dalam keadaan redup 0,7 atau terang 1,3.
      final e = BreathEnvelope();
      expect(e.level, BreathEnvelope.neutralLevel);
      expect(e.factor, 1.0);
    });

    test('laju perubahan ≤ 0,30/dtk (ayunan penuh ≥ 3,33 dtk < 0,15 Hz)',
        () {
      final e = BreathEnvelope();
      e.feed(-15, const Duration(milliseconds: 100));
      expect(e.level, lessThanOrEqualTo(0.5 + 0.30 * 0.1 + 1e-9));
      // Dari netral, mencapai keras penuh butuh ≥ separuh ayunan.
      var elapsed = 0.1;
      while (e.level < 1 && elapsed < 10) {
        e.feed(-15, const Duration(milliseconds: 100));
        elapsed += 0.1;
      }
      expect(elapsed, greaterThanOrEqualTo(1.6));
    });

    test('faktor modulasi = pita 0,7–1,3, linear pada level', () {
      final e = BreathEnvelope();
      e.level = 1;
      expect(e.factor, closeTo(1.3, 1e-9));
      e.level = 0;
      expect(e.factor, closeTo(0.7, 1e-9));
      e.level = 0.5;
      expect(e.factor, closeTo(1.0, 1e-9));
      e.level = 0.75;
      expect(e.factor, closeTo(1.15, 1e-9));
    });

    test('decay menuju NETRAL (bukan nol) dari dua arah', () {
      final atas = BreathEnvelope()..level = 0.9;
      atas.decay(const Duration(seconds: 1));
      expect(atas.level, closeTo(0.6, 1e-9));
      atas.decay(const Duration(seconds: 10));
      expect(atas.level, BreathEnvelope.neutralLevel);
      expect(atas.factor, 1.0);
      final bawah = BreathEnvelope()..level = 0.1;
      bawah.decay(const Duration(seconds: 1));
      expect(bawah.level, closeTo(0.4, 1e-9));
    });

    test('breathFeedDt: dt dijepit [0, 2 dtk], sampel tak pernah dibuang',
        () {
      // Akar rekaman datar ronde 8038: penerbitan RMS Kotlin berjeda
      // ±2 dtk; penjaga lama membuang sampel berjeda > 2 dtk sehingga
      // amplop kelaparan total. Kini jeda panjang hanya DIJEPIT.
      expect(breathFeedDt(const Duration(milliseconds: 300)),
          const Duration(milliseconds: 300));
      expect(breathFeedDt(const Duration(seconds: 2)),
          const Duration(seconds: 2));
      expect(breathFeedDt(const Duration(milliseconds: 2100)),
          const Duration(seconds: 2));
      expect(breathFeedDt(const Duration(minutes: 3)),
          const Duration(seconds: 2));
      expect(breathFeedDt(const Duration(milliseconds: -50)), Duration.zero);
      // Konsekuensi: urutan sampel berjeda 2,1 dtk tetap menggerakkan
      // amplop (dulu: nol sampel yang lolos penjaga).
      final e = BreathEnvelope();
      for (var i = 0; i < 5; i++) {
        e.feed(-15, breathFeedDt(const Duration(milliseconds: 2100)));
      }
      expect(e.level, 1.0);
      expect(e.factor, closeTo(1.3, 1e-9));
    });
  });

  group('nada progres (aturan 2026-11-09 11:24: sampul dipekatkan)', () {
    test('sampul jenuh: rona dipertahankan, dipekatkan ke pita tegas', () {
      final palette = buildAmbientPalette(
        source: const Color(0xFFB43A2A),
        enabled: true,
        strength: AmbientStrength.hidup,
      );
      final tone = progressToneFor(palette);
      expect(tone, isNot(ClaiColors.accent));
      final hsl = HSLColor.fromColor(tone);
      final normHsl = HSLColor.fromColor(palette.norm);
      expect(hsl.hue, closeTo(normHsl.hue, 2));
      expect(hsl.saturation, greaterThanOrEqualTo(0.55));
      expect(hsl.lightness, inInclusiveRange(0.45, 0.68));
      // Penjaga: tetap terbaca di atas lelehan hampir-hitam.
      expect(contrastOf(tone, const Color(0xFF070406)),
          greaterThanOrEqualTo(3.0));
    });

    test('monokrom & hampir-netral & tak aktif → cadangan Volt penjaga', () {
      final mono = buildAmbientPalette(
        source: const Color(0xFF808080),
        enabled: true,
        strength: AmbientStrength.hidup,
      );
      expect(mono.fallbackDiam, isTrue);
      expect(progressToneFor(mono), ClaiColors.accent);
      final netral = buildAmbientPalette(
        source: const Color(0xFF8A8F87),
        enabled: true,
        strength: AmbientStrength.hidup,
      );
      expect(progressToneFor(netral), ClaiColors.accent);
      expect(progressToneFor(AmbientPalette.inactive), ClaiColors.accent);
    });

    test('onProgressTone memilih sisi kontras yang lebih besar', () {
      // Volt terang → tinta hampir-hitam merek.
      expect(onProgressTone(ClaiColors.accent), ClaiColors.onAccent);
      // Merah pekat → putih.
      expect(onProgressTone(const Color(0xFF8E2323)), Colors.white);
    });
  });

  group('gerbang konsumen Visualizer (perbaikan U1)', () {
    test('tabel kebenaran: nyala bila normalisasi ATAU napas butuh', () {
      expect(
          visualizerNeeded(normalizationOn: false, breathWanted: false),
          isFalse);
      expect(
          visualizerNeeded(normalizationOn: true, breathWanted: false),
          isTrue);
      // Baris inilah perbaikan vonis 10:44: normalisasi MATI (bawaan)
      // + napas diminta → Visualizer tetap menyala.
      expect(
          visualizerNeeded(normalizationOn: false, breathWanted: true),
          isTrue);
      expect(
          visualizerNeeded(normalizationOn: true, breathWanted: true),
          isTrue);
    });

    test('Sisipan G-1: suara ketiga waveform menyalakan gerbang sendiri',
        () {
      // Keadaan persis bukti perangkat pemilik atas 8039: normalisasi
      // MATI (bawaan) + napas MATI + perekam butuh → Visualizer WAJIB
      // menyala; tanpanya waveform berhenti di ±23% ember.
      expect(
          visualizerNeeded(
              normalizationOn: false,
              breathWanted: false,
              waveformWanted: true),
          isTrue);
      // Ketiganya mati → gerbang mati (tidak ada pembakaran diam-diam).
      expect(
          visualizerNeeded(
              normalizationOn: false,
              breathWanted: false,
              waveformWanted: false),
          isFalse);
      expect(
          visualizerNeeded(
              normalizationOn: true,
              breathWanted: true,
              waveformWanted: true),
          isTrue);
    });

    test('breathModulatedAlpha: kali lalu jepit 0..1', () {
      expect(breathModulatedAlpha(0.4, 1.0), closeTo(0.4, 1e-9));
      expect(breathModulatedAlpha(0.4, 1.3), closeTo(0.52, 1e-9));
      expect(breathModulatedAlpha(0.4, 0.7), closeTo(0.28, 1e-9));
      expect(breathModulatedAlpha(0.9, 1.3), 1.0); // terjepit
      expect(breathModulatedAlpha(0.0, 1.3), 0.0);
    });

    test('amplitudo konstruksi: ayunan luminansi ≥ 8/255 (tinta cerah)',
        () {
      // Tinta representatif cerah (sampul kuning-ambar): wash Player
      // dan glow panggung di atas dasar aplikasi, faktor 0,7 vs 1,3.
      final palette = buildAmbientPalette(
        source: const Color(0xFFE8B33C),
        enabled: true,
        strength: AmbientStrength.hidup,
      );
      expect(palette.active, isTrue);
      double lum(Color c) => c.computeLuminance() * 255;
      final wash = palette.washColor(
          AmbientSurfaceKind.player, AmbientStrength.hidup);
      final washSwing = (lum(compositeOver(
                  wash.withValues(
                      alpha: breathModulatedAlpha(wash.a, 1.3)),
                  ClaiColors.base)) -
              lum(compositeOver(
                  wash.withValues(
                      alpha: breathModulatedAlpha(wash.a, 0.7)),
                  ClaiColors.base)))
          .abs();
      expect(washSwing, greaterThanOrEqualTo(8));
      final glow = palette.glowColor;
      final glowSwing = (lum(compositeOver(
                  glow.withValues(
                      alpha: breathModulatedAlpha(glow.a, 1.3)),
                  ClaiColors.base)) -
              lum(compositeOver(
                  glow.withValues(
                      alpha: breathModulatedAlpha(glow.a, 0.7)),
                  ClaiColors.base)))
          .abs();
      expect(glowSwing, greaterThanOrEqualTo(8));
    });
  });

  group('penjaga kesehatan Visualizer (Ronde 8050)', () {
    // Akar perangkat "waveform hanya nyala ketika build baru": rantai
    // RMS bisa mati diam-diam di tengah sesi (penempelan sesi
    // Visualizer lepas tanpa galat). Predikat ini memutuskan kapan
    // handler menegaskan ulang (berhenti → mulai).
    test('RMS belum pernah tiba sesi ini + butuh + berbunyi → tegaskan',
        () {
      expect(
          visWatchdogDue(
              needed: true, playing: true, msSinceLastRms: null,
              msSinceLastReassert: null),
          isTrue);
    });

    test('RMS diam melewati ambang hening (15 dtk) → tegaskan', () {
      expect(
          visWatchdogDue(
              needed: true, playing: true, msSinceLastRms: 20000,
              msSinceLastReassert: null),
          isTrue);
    });

    test('RMS masih segar → jangan ganggu', () {
      expect(
          visWatchdogDue(
              needed: true, playing: true, msSinceLastRms: 5000,
              msSinceLastReassert: null),
          isFalse);
    });

    test('tidak berbunyi atau gerbang tidak butuh → tidak ada penegasan',
        () {
      expect(
          visWatchdogDue(
              needed: true, playing: false, msSinceLastRms: null,
              msSinceLastReassert: null),
          isFalse);
      expect(
          visWatchdogDue(
              needed: false, playing: true, msSinceLastRms: null,
              msSinceLastReassert: null),
          isFalse);
    });

    test('jeda pendinginan 20 dtk mencegah penegasan beruntun; lewat '
        'itu boleh lagi', () {
      expect(
          visWatchdogDue(
              needed: true, playing: true, msSinceLastRms: 40000,
              msSinceLastReassert: 5000),
          isFalse);
      expect(
          visWatchdogDue(
              needed: true, playing: true, msSinceLastRms: 60000,
              msSinceLastReassert: 30000),
          isTrue);
    });
  });
}
