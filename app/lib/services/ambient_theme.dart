import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/tokens.dart';
import 'cover_accent.dart';

/// Mesin tema "Sampul Hidup" (DS v4.0 §5, Workstream E F3) — MURNI &
/// teruji unit. Doktrin dua lapis: Volt = sinyal (tidak disentuh di
/// sini); tinta sampul = suasana. Semua fungsi deterministik: warna
/// sumber yang sama selalu menghasilkan palet yang sama.
///
/// Alur: warna tanda tangan sampul → normalisasi (saturasi −25%,
/// lightness dijepit 18–38%) → penjaga keterbacaan (kekuatan wash
/// menurun berundak 28→18→10→diam sampai teks lulus WCAG) → palet
/// (wash / kaca / glow / ink-soft). Sampul monokrom atau absen jatuh ke
/// tinta cadangan [ambientDiamColor] — Volt dilemahkan.

/// Kekuatan ambien terpilih pengguna (KD-3; bawaan terpilih: hidup).
enum AmbientStrength { tenang, hidup }

/// Jenis permukaan untuk dosis tinta (DS v4.0 §3-P6): layar pahlawan
/// dosis penuh, Player plafon khusus, layar tugas 40%.
enum AmbientSurfaceKind { hero, player, task }

({int r, int g, int b}) _rgbOf(Color c) => (
      r: (c.r * 255).round(),
      g: (c.g * 255).round(),
      b: (c.b * 255).round(),
    );

/// Komposit source-over [fg] beralfa di atas [bg] opak (matematika yang
/// sama dengan render Flutter) — dasar semua hitungan penjaga.
Color compositeOver(Color fg, Color bg) {
  final a = fg.a;
  final f = _rgbOf(fg);
  final b = _rgbOf(bg);
  int mix(int x, int y) => (a * x + (1 - a) * y).round().clamp(0, 255);
  return Color.fromARGB(255, mix(f.r, b.r), mix(f.g, b.g), mix(f.b, b.b));
}

double contrastOf(Color a, Color b) => contrastRatioRgb(_rgbOf(a), _rgbOf(b));

/// Apakah sampul praktis tak berwarna? Saturasi HSL di bawah ambang ini
/// berarti rona tidak membawa suasana — tinta cadangan yang dipakai.
bool isAmbientMonochrome(Color source) =>
    HSLColor.fromColor(source).saturation < 0.08;

/// Normalisasi tinta (DS v4.0 §5.1): saturasi diturunkan,
/// lightness dijepit ke pita 18–38% agar wash tidak pernah menyilaukan
/// (terang) atau menghilang (gelap). [saturationScale] = pecahan
/// saturasi sumber yang dipertahankan: baku 0,75 (Tenang); mode Hidup
/// memakai 0,90 (Ronde Sapuan 8045 — vonis pemilik: warna ruangan
/// kurang pekat; kejenuhan ikut naik bersama plafon wash-nya).
Color normalizeAmbientSource(Color source, {double saturationScale = 0.75}) {
  final hsl = HSLColor.fromColor(source);
  return hsl
      .withSaturation((hsl.saturation * saturationScale).clamp(0.0, 1.0))
      .withLightness(hsl.lightness.clamp(0.18, 0.38))
      .toColor();
}

/// Tinta cadangan `amb/diam`: Volt dengan saturasi ±18% dan lightness
/// 26% — ruangan tetap punya suhu Volt yang sangat lemah saat sampul
/// absen/monokrom, tanpa memalsukan warna lagu.
Color ambientDiamColor() => HSLColor.fromColor(ClaiColors.accent)
    .withSaturation(0.18)
    .withLightness(0.26)
    .toColor();

/// Undakan kekuatan wash yang dicoba penjaga, dari [requested] menurun:
/// nilai-nilai perantara baku DS (0,28 · 0,18 · 0,10) yang tidak melebihi
/// permintaan, lalu 0 (diam).
List<double> guardLadder(double requested) {
  final steps = <double>{requested, 0.28, 0.18, 0.10, 0.0}
      .where((s) => s <= requested + 1e-9)
      .toList()
    ..sort((a, b) => b.compareTo(a));
  return steps;
}

/// Penjaga keterbacaan (DS v4.0 §5.2 — hukum, bukan opsi): kekuatan wash
/// terbesar dari undakan [guardLadder] yang membuat teks utama [ink] di
/// atas komposit wash-di-atas-[base] tetap lulus WCAG ≥ 4,5:1. Teks
/// tidak pernah dikorbankan demi suasana; yang turun adalah tintanya.
double guardAmbientStrength(
  Color norm,
  double requested, {
  Color base = ClaiColors.base,
  Color ink = ClaiColors.ink,
  double minRatio = 4.5,
}) {
  for (final s in guardLadder(requested)) {
    if (s <= 0) return 0.0;
    final comp = compositeOver(norm.withValues(alpha: s), base);
    if (contrastOf(ink, comp) >= minRatio) return s;
  }
  return 0.0;
}

/// Teks sekunder di zona ambien (`amb/ink-soft`, konflik C8): turunan
/// rona tinta yang lightness-nya dinaikkan berundak sampai lulus ≥4,5:1
/// di atas permukaan setempat [over] — tidak pernah abu netral di atas
/// warna. Jatuh terakhir: ink primer DS (selalu aman di permukaan DS).
Color ambientInkSoft(Color norm, Color over, {double minRatio = 4.5}) {
  final hsl = HSLColor.fromColor(norm);
  for (var i = 0; i <= 40; i++) {
    final l = (hsl.lightness + i * 0.02).clamp(0.0, 0.92);
    final c = hsl.withLightness(l).toColor();
    if (contrastOf(c, over) >= minRatio) return c;
  }
  return ClaiColors.ink;
}

/// Dosis alfa wash untuk satu jenis permukaan: kekuatan efektif palet
/// diskalakan per jenis (Player memakai plafonnya sendiri, tugas 40%).
double ambientDoseFor(
  AmbientSurfaceKind kind,
  double effectiveStrength,
  AmbientStrength strength,
) {
  switch (kind) {
    case AmbientSurfaceKind.hero:
      return effectiveStrength;
    case AmbientSurfaceKind.player:
      final scale = strength == AmbientStrength.hidup
          ? 1.0
          : ClaiAmbient.washCapCalm / ClaiAmbient.washCapLively;
      final scaled = effectiveStrength *
          (ClaiAmbient.washCapPlayer / ClaiAmbient.washCapLively) *
          scale;
      return math.min(scaled, ClaiAmbient.washCapPlayer * scale);
    case AmbientSurfaceKind.task:
      return effectiveStrength * ClaiAmbient.taskDose;
  }
}

/// Palet suasana yang sudah jadi (immutable). [active] false berarti
/// netral: tidak ada wash, tidak ada tint — perilaku v3.1 persis.
class AmbientPalette {
  final bool active;

  /// True bila tinta berasal dari cadangan `amb/diam` (sampul monokrom).
  final bool fallbackDiam;

  /// `amb/norm` — basis semua derivasi.
  final Color norm;

  /// Kekuatan wash hero EFEKTIF sesudah penjaga (0..plafon terpilih).
  final double washStrength;

  const AmbientPalette._({
    required this.active,
    required this.fallbackDiam,
    required this.norm,
    required this.washStrength,
  });

  static const inactive = AmbientPalette._(
    active: false,
    fallbackDiam: false,
    norm: ClaiColors.base,
    washStrength: 0,
  );

  /// Warna wash (dengan alfa dosis) untuk permukaan [kind].
  Color washColor(AmbientSurfaceKind kind, AmbientStrength strength) {
    if (!active) return Colors.transparent;
    return norm.withValues(alpha: ambientDoseFor(kind, washStrength, strength));
  }

  /// Tint permukaan kaca (di atas blur): alfa resep 0,15.
  Color get glassTint => active
      ? norm.withValues(alpha: ClaiAmbient.glassTintAlpha)
      : Colors.transparent;

  /// Warna tepi cahaya kaca.
  Color get glassEdge =>
      active ? norm.withValues(alpha: ClaiAmbient.glassEdgeAlpha) : ClaiColors.divider;

  /// Glow di balik sampul Player sebelum diskala napas (U1).
  Color get glowColor =>
      active ? norm.withValues(alpha: ClaiAmbient.glowAlpha) : Colors.transparent;

  /// Teks sekunder aman di atas permukaan ambien setempat [over].
  Color inkSoftOver(Color over) =>
      active ? ambientInkSoft(norm, over) : ClaiColors.inkSecondary;

  @override
  bool operator ==(Object other) =>
      other is AmbientPalette &&
      other.active == active &&
      other.fallbackDiam == fallbackDiam &&
      other.norm == norm &&
      other.washStrength == washStrength;

  @override
  int get hashCode => Object.hash(active, fallbackDiam, norm, washStrength);
}

/// Bangun palet dari warna tanda tangan sampul. [source] null (tanpa
/// sampul / muat gagal) atau tema mati → palet tidak aktif (netral).
AmbientPalette buildAmbientPalette({
  required Color? source,
  required bool enabled,
  required AmbientStrength strength,
}) {
  if (!enabled || source == null) return AmbientPalette.inactive;
  final mono = isAmbientMonochrome(source);
  final norm = mono
      ? ambientDiamColor()
      : normalizeAmbientSource(source,
          saturationScale:
              strength == AmbientStrength.hidup ? 0.90 : 0.75);
  final cap = strength == AmbientStrength.hidup
      ? ClaiAmbient.washCapLively
      : ClaiAmbient.washCapCalm;
  final eff = guardAmbientStrength(norm, cap);
  return AmbientPalette._(
    active: true,
    fallbackDiam: mono,
    norm: norm,
    washStrength: eff,
  );
}

/// "Tinta menetap" (DS v4.0 §5, keadaan ganti-cepat): tinta TIDAK
/// mengikuti setiap ganti trek. Trek baru menjadi *tertunda*; ia baru
/// terpasang bila bertahan selama [settleWindow] tanpa digantikan.
/// Trek pertama sesi terpasang seketika (belum ada tinta yang
/// dipertahankan). Kembali ke trek yang sedang terpasang membatalkan
/// yang tertunda. Murni & deterministik — waktu disuntikkan pemanggil.
class TintSettler {
  final Duration settleWindow;
  String? _committedKey;
  String? _pendingKey;
  DateTime? _pendingSince;

  TintSettler({this.settleWindow = ClaiAmbient.settleWindow});

  String? get committedKey => _committedKey;
  String? get pendingKey => _pendingKey;

  /// Daftarkan sumber baru pada waktu [now]. Mengembalikan kunci yang
  /// harus terpasang SEKARANG (hanya trek pertama), atau null.
  String? onSource(String key, DateTime now) {
    if (key == _committedKey) {
      _pendingKey = null;
      _pendingSince = null;
      return null;
    }
    if (_committedKey == null) {
      _committedKey = key;
      return key;
    }
    _pendingKey = key;
    _pendingSince = now;
    return null;
  }

  /// Detak berkala pemanggil: pasang yang tertunda bila jendelanya
  /// sudah lewat. Mengembalikan kunci yang baru terpasang, atau null.
  String? tick(DateTime now) {
    final p = _pendingKey;
    final since = _pendingSince;
    if (p == null || since == null) return null;
    if (now.difference(since) >= settleWindow) {
      _committedKey = p;
      _pendingKey = null;
      _pendingSince = null;
      return p;
    }
    return null;
  }

  /// Lupakan semua (tema dimatikan): pemasangan berikutnya seketika.
  void reset() {
    _committedKey = null;
    _pendingKey = null;
    _pendingSince = null;
  }
}

/// Nada progres (ATURAN WARNA PROGRES — keputusan pemilik 2026-11-09
/// 11:24): indikator putar/progres BUKAN Volt lagi, melainkan nada
/// tanda tangan sampul yang DIPEKATKAN ("lebih pekat atau tegas"):
/// rona dari `amb/norm`, saturasi didorong ×1,3 (lantai 0,55), dan
/// lightness diangkat dari pita ambien gelap (0,18–0,38) ke pita
/// tegas 0,45–0,58 supaya tetap garang di atas lelehan & kaca gelap.
/// Disiplin penjaga yang sama seperti wash: kontras terhadap latar
/// lelehan terbawah (hampir-hitam) harus ≥ 3:1 — bila kurang,
/// lightness naik berundak +0,06 sampai maks 0,68.
/// Cadangan penjaga: palet tak aktif, sampul monokrom/`amb/diam`,
/// atau rona hampir-netral (saturasi norm < 0,12 — memekatkan abu
/// hanya akan mengarang warna dan tenggelam di kaca) → Volt, yang
/// selalu terbaca. Volt sesudah aturan ini berdomain: keadaan aktif
/// + aksen merek saja.
Color progressToneFor(AmbientPalette palette) {
  if (!palette.active || palette.fallbackDiam) return ClaiColors.accent;
  return deepToneFromColor(palette.norm);
}

/// Nada pekat §11.9 dari warna tanda tangan sampul ARBITRER (bukan
/// palet ambien trek berjalan) — dipakai permukaan yang mewarnai
/// dirinya dari sampulnya sendiri (dok putar Kepala Hidup Gelombang 2,
/// kartu panggung Koleksi, tombol panel Spotify). Matematika yang sama
/// persis seperti [progressToneFor]: saturasi ×1,3 (lantai 0,55),
/// lightness di pita tegas 0,45–0,58, penjaga kontras ≥ 3:1 terhadap
/// hampir-hitam; rona hampir-netral (saturasi < 0,12) jatuh ke Volt —
/// memekatkan abu hanya akan mengarang warna. Murni & diuji.
Color deepToneFromColor(Color base) {
  final hsl = HSLColor.fromColor(base);
  if (hsl.saturation < 0.12) return ClaiColors.accent;
  final sat = (hsl.saturation * 1.3).clamp(0.55, 1.0);
  var light = hsl.lightness.clamp(0.45, 0.58);
  var tone = hsl.withSaturation(sat).withLightness(light).toColor();
  const backdrop = Color(0xFF070406); // lelehan terbawah panggung P1
  while (contrastOf(tone, backdrop) < 3.0 && light < 0.68) {
    light = math.min(0.68, light + 0.06);
    tone = hsl.withSaturation(sat).withLightness(light).toColor();
  }
  return tone;
}

/// Warna ikon di atas [progressToneFor] (tombol putar dok P1, KD-2
/// longgar 2026-11-09 11:19): pilih tinta-hampir-hitam merek atau
/// putih, mana yang kontrasnya lebih besar terhadap nadanya.
Color onProgressTone(Color tone) =>
    contrastOf(Colors.white, tone) >= contrastOf(ClaiColors.onAccent, tone)
        ? Colors.white
        : ClaiColors.onAccent;

/// Gerbang konsumen Visualizer (murni): SATU Visualizer melayani TIGA
/// konsumen aliran RMS yang sama — normalisasi kenyaringan, napas
/// ambien (U1), dan **perekam waveform ukur** (DS §11.10). Ia harus
/// menyala bila SALAH SATU konsumen membutuhkannya (hitung referensi
/// boolean di handler).
///
/// Riwayat gerbang ini adalah riwayat konsumen yang tertinggal:
/// awalnya Visualizer hanya mengikuti normalisasi (napas mati biner
/// di keadaan bawaan — diperbaiki ronde Player F3); lalu **Sisipan
/// G-1 (2026-11-10, bukti perangkat pemilik atas 8039)** menemukan
/// perekam waveform adalah konsumen ketiga yang tidak punya suara:
/// dengan normalisasi mati (bawaan) dan napas mati, Visualizer tidak
/// pernah menyala dan waveform kelaparan permanen — ember hanya
/// terisi pada putaran yang gerbangnya kebetulan terbuka. Kini
/// perekam bersuara lewat [waveformWanted]: ada trek berjalan yang
/// datanya belum lengkap terukur (predikat murninya
/// `waveformWantsVisualizer` di waveform.dart; trek penuh = diam).
bool visualizerNeeded({
  required bool normalizationOn,
  required bool breathWanted,
  bool waveformWanted = false,
}) =>
    normalizationOn || breathWanted || waveformWanted;

/// Penjaga kesehatan Visualizer (Ronde 8050) — predikat murni untuk
/// keputusan "tegaskan ulang Visualizer sekarang": gerbang konsumen
/// menyatakan Visualizer DIBUTUHKAN dan pemain sedang BERBUNYI,
/// tetapi aliran RMS sudah diam lebih lama dari [silenceMs] (atau
/// belum pernah tiba sama sekali sesi ini) → rantai ukur di
/// perangkat dianggap mati di tengah jalan (penempelan sesi
/// Visualizer di beberapa ROM terbukti bisa lepas tanpa galat yang
/// sampai ke Dart) dan handler menegaskan ulang mulai-dari-awal.
/// [cooldownMs] menjaga penegasan tidak beruntun. Tanpa penjaga ini,
/// satu-satunya obat rantai yang mati diam-diam adalah memasang
/// build baru — persis gejala yang dilaporkan pemilik 2026-11-10.
bool visWatchdogDue({
  required bool needed,
  required bool playing,
  required int? msSinceLastRms,
  required int? msSinceLastReassert,
  int silenceMs = 15000,
  int cooldownMs = 20000,
}) {
  if (!needed || !playing) return false;
  if (msSinceLastRms != null && msSinceLastRms < silenceMs) return false;
  if (msSinceLastReassert != null && msSinceLastReassert < cooldownMs) {
    return false;
  }
  return true;
}

/// Alfa permukaan termodulasi napas: [base] diskalakan [factor]
/// (0,7–1,3), dijepit ke rentang alfa sah. Murni.
double breathModulatedAlpha(double base, double factor) =>
    (base * factor).clamp(0.0, 1.0);

/// Selang umpan napas yang dipakai amplop (murni, diuji): JEPIT ke
/// [0, 2 dtk] — JANGAN PERNAH membuang sampel. Akar kelaparan ronde
/// 8038: sisi Kotlin menerbitkan RMS tiap ±2 dtk (20 tangkapan pada
/// laju tangkap maks/2), penjaga lama membuang setiap sampel yang
/// jedanya > 2 dtk — di peranti yang lajunya sedikit lebih lambat,
/// SETIAP sampel terbuang, amplop tak pernah makan, faktor terkunci
/// tepat 1,0 dan rekaman ROI datar sempurna. Amplop sudah membatasi
/// lajunya sendiri (0,30/dtk), jadi dt yang dijepit tetap tak bisa
/// membuat permukaan melompat; membuangnya hanya mematikan napas.
Duration breathFeedDt(Duration raw) {
  if (raw.isNegative) return Duration.zero;
  const maxDt = Duration(seconds: 2);
  return raw > maxDt ? maxDt : raw;
}

/// Amplop napas ambien (U1): energi audio (RMS dBFS dari Visualizer)
/// dihaluskan menjadi level 0..1 dengan laju perubahan dibatasi —
/// ayunan penuh butuh ≥ 1/(2·0,15 Hz), jadi denyut yang terlihat
/// selalu di bawah 0,15 Hz. Level 0,5 adalah NETRAL dan level awal:
/// [factor] mulai tepat di 1,0 (koheren sejak sampel pertama — cacat
/// lama memulai di 0,85 walau belum ada energi apa pun).
///
/// Perbaikan ronde Player F3 (vonis perangkat 2026-11-09 10:44,
/// "gaada bernapas-bernapasnya"): yang dimodulasi bukan lagi skala
/// kotak bayangan tersembunyi (ayunan terlihat hanya ±1–3/255,
/// berundak 1 Hz) melainkan ALFA permukaan terlihat — glow panggung
/// Player dan wash Player — lewat [factor] 0,7–1,3, diinterpolasi
/// kontinu di sisi UI. Murni & teruji.
class BreathEnvelope {
  /// Laju maksimum level per detik: ayunan 0→1 ≥ 3,33 dtk.
  static const double maxRatePerSecond = 0.30;

  /// Level netral: faktor tepat 1,0; decay selalu pulang ke sini.
  static const double neutralLevel = 0.5;

  /// Plafon penyimpangan faktor alfa (±30% — terlihat di bidang luas).
  static const double maxDeviation = 0.30;

  double level = neutralLevel;

  /// Petakan RMS dBFS ke target level: −55 dB → 0, −15 dB → 1.
  static double targetForRmsDb(double rmsDb) =>
      ((rmsDb + 55) / 40).clamp(0.0, 1.0);

  /// Umpan satu sampel dengan selang [dt] sejak sampel sebelumnya.
  void feed(double rmsDb, Duration dt) {
    final target = targetForRmsDb(rmsDb);
    final maxDelta = maxRatePerSecond * dt.inMilliseconds / 1000.0;
    final delta = (target - level).clamp(-maxDelta, maxDelta);
    level = (level + delta).clamp(0.0, 1.0);
  }

  /// Menuju NETRAL (jeda / napas mati): level meluruh ke 0,5 dengan
  /// laju yang sama — tidak pernah memotong, tidak pernah mengunci
  /// permukaan di keadaan redup atau menyala.
  void decay(Duration dt) {
    final maxDelta = maxRatePerSecond * dt.inMilliseconds / 1000.0;
    final delta = (neutralLevel - level).clamp(-maxDelta, maxDelta);
    level = (level + delta).clamp(0.0, 1.0);
  }

  /// Faktor modulasi alfa saat ini: 0,7 (paling hening) – 1,3
  /// (paling keras); tepat 1,0 saat netral.
  double get factor => 1 + (level - neutralLevel) * 2 * maxDeviation;
}
