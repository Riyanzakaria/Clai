import 'dart:math' as math;

/// Matematika aksen cover dinamis (F2 Batch 2, DS Bab 2) — murni & teruji.
/// Aturan DS: aksen dinamis HANYA mewarnai latar tonal di belakang sampul
/// (Player & NowCard), dijenuhkan 20% (desaturasi), dan TIDAK PERNAH
/// menggantikan Volt pada tombol putar / indikator status.
({int r, int g, int b}) averageRgb(List<int> rgba, {int maxSamples = 2048}) {
  var sr = 0, sg = 0, sb = 0, n = 0;
  final totalPixels = rgba.length ~/ 4;
  if (totalPixels == 0) return (r: 0, g: 0, b: 0);
  final stride = (totalPixels / maxSamples).ceil();
  for (var i = 0; i < totalPixels; i += stride) {
    final a = rgba[i * 4 + 3];
    if (a < 128) continue; // piksel transparan bukan warna sampul
    sr += rgba[i * 4];
    sg += rgba[i * 4 + 1];
    sb += rgba[i * 4 + 2];
    n++;
  }
  if (n == 0) return (r: 0, g: 0, b: 0);
  return (r: sr ~/ n, g: sg ~/ n, b: sb ~/ n);
}

/// Warna TANDA TANGAN sampul (F2 Batch 2.1 — akar perbaikan aksen tak
/// terlihat di HP riyan): piksel dikelompokkan ke 12 ember rona, tiap piksel
/// ditimbang SATURASINYA (piksel putih/pucat nyaris tak berbobot), ember
/// terberat (beserta dua tetangganya, agar rona yang terbelah di tepi ember
/// tetap utuh) dirata-rata tertimbang. Rata-rata global lama menenggelamkan
/// warna khas sampul dominan-putih (mis. hijau lime di atas putih → abu
/// kehijauan kusam). Mengembalikan null bila sampul praktis tak berwarna —
/// pemanggil jatuh ke [averageRgb].
({int r, int g, int b})? dominantSaturatedRgb(
  List<int> rgba, {
  int maxSamples = 4096,
}) {
  final totalPixels = rgba.length ~/ 4;
  if (totalPixels == 0) return null;
  final stride = (totalPixels / maxSamples).ceil();
  const bins = 12;
  final sumR = List<double>.filled(bins, 0);
  final sumG = List<double>.filled(bins, 0);
  final sumB = List<double>.filled(bins, 0);
  final sumW = List<double>.filled(bins, 0);
  for (var i = 0; i < totalPixels; i += stride) {
    if (rgba[i * 4 + 3] < 128) continue;
    final r = rgba[i * 4], g = rgba[i * 4 + 1], b = rgba[i * 4 + 2];
    final mx = r > g ? (r > b ? r : b) : (g > b ? g : b);
    final mn = r < g ? (r < b ? r : b) : (g < b ? g : b);
    if (mx == 0) continue;
    final sat = (mx - mn) / mx; // saturasi HSV 0..1
    if (sat < 0.15) continue; // putih/abu: bukan warna tanda tangan
    // Rona 0..1 (rumus HSV standar).
    final d = (mx - mn).toDouble();
    double hue;
    if (mx == r) {
      hue = ((g - b) / d) % 6;
    } else if (mx == g) {
      hue = (b - r) / d + 2;
    } else {
      hue = (r - g) / d + 4;
    }
    hue /= 6;
    if (hue < 0) hue += 1;
    final bin = (hue * bins).floor() % bins;
    // Bobot: saturasi × kecerahan relatif — warna khas yang terang menang
    // atas bayangan gelap yang jenuh semu.
    final w = sat * (0.35 + 0.65 * (mx / 255));
    sumR[bin] += r * w;
    sumG[bin] += g * w;
    sumB[bin] += b * w;
    sumW[bin] += w;
  }
  var best = -1;
  var bestW = 0.0;
  for (var i = 0; i < bins; i++) {
    if (sumW[i] > bestW) {
      bestW = sumW[i];
      best = i;
    }
  }
  if (best < 0 || bestW <= 0) return null;
  var r = 0.0, g = 0.0, b = 0.0, w = 0.0;
  for (final j in [(best + bins - 1) % bins, best, (best + 1) % bins]) {
    r += sumR[j];
    g += sumG[j];
    b += sumB[j];
    w += sumW[j];
  }
  if (w <= 0) return null;
  return (r: (r / w).round(), g: (g / w).round(), b: (b / w).round());
}

/// Campur warna menuju abu-abu luminansinya sebesar [amount] (0–1).
({int r, int g, int b}) desaturateRgb(
  ({int r, int g, int b}) c,
  double amount,
) {
  final gray = (0.299 * c.r + 0.587 * c.g + 0.114 * c.b).round();
  int mix(int v) => (v + (gray - v) * amount).round().clamp(0, 255);
  return (r: mix(c.r), g: mix(c.g), b: mix(c.b));
}

/// Latar tonal: campur [accent] ke [bg] sebesar [t] — tetap gelap, hanya bernuansa.
({int r, int g, int b}) tonalRgb(
  ({int r, int g, int b}) accent,
  ({int r, int g, int b}) bg,
  double t,
) {
  int mix(int a, int b) => (b + (a - b) * t).round().clamp(0, 255);
  return (
    r: mix(accent.r, bg.r),
    g: mix(accent.g, bg.g),
    b: mix(accent.b, bg.b),
  );
}

String rgbToHex(({int r, int g, int b}) c) =>
    '#${c.r.toRadixString(16).padLeft(2, '0')}${c.g.toRadixString(16).padLeft(2, '0')}${c.b.toRadixString(16).padLeft(2, '0')}';

/// Luminans relatif WCAG 2.x (0 = hitam, 1 = putih).
double relativeLuminanceRgb(({int r, int g, int b}) c) {
  double lin(int v) {
    final s = v / 255;
    return s <= 0.03928
        ? s / 12.92
        : math.pow((s + 0.055) / 1.055, 2.4).toDouble();
  }

  return 0.2126 * lin(c.r) + 0.7152 * lin(c.g) + 0.0722 * lin(c.b);
}

/// Rasio kontras WCAG antara dua warna (1 = sama, 21 = hitam-putih).
double contrastRatioRgb(({int r, int g, int b}) a, ({int r, int g, int b}) b) {
  final la = relativeLuminanceRgb(a);
  final lb = relativeLuminanceRgb(b);
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

/// Permukaan aksen yang AMAN DITULISI (Ronde Putusan Desain, 25 Okt 2026):
/// permukaan yang MEWARISI warna sampul secara penuh (kartu mini player,
/// gradasi chrome bawah) harus tetap lulus kontras untuk teks di atasnya.
/// Bila [surface] terlalu terang untuk [text], ia digelapkan bertahap
/// menuju [darkenToward] (rona dipertahankan — yang turun hanya terang)
/// sampai rasio ≥ [minRatio] tercapai. Sampul kebanyakan sudah gelap
/// sesudah rumus tonal sehingga fungsi ini tidak mengubah apa pun;
/// hanya sampul luar biasa terang (kuning/hijau muda jenuh) yang digelapkan.
({int r, int g, int b}) readableSurfaceRgb(
  ({int r, int g, int b}) surface,
  ({int r, int g, int b}) text,
  ({int r, int g, int b}) darkenToward, {
  double minRatio = 4.5,
}) {
  var c = surface;
  for (var i = 0; i < 24; i++) {
    if (contrastRatioRgb(text, c) >= minRatio) return c;
    c = tonalRgb(darkenToward, c, 0.18);
  }
  return darkenToward;
}

({int r, int g, int b})? rgbFromHex(String hex) {
  final h = hex.replaceFirst('#', '');
  if (h.length != 6) return null;
  final v = int.tryParse(h, radix: 16);
  if (v == null) return null;
  return (r: (v >> 16) & 0xFF, g: (v >> 8) & 0xFF, b: v & 0xFF);
}
