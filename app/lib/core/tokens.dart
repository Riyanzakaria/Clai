import 'package:flutter/material.dart';

/// Token Clai DS v3.1 "Volt" — satu sumber kebenaran visual (DESIGN-SYSTEM.md Bab 2–4).
class ClaiColors {
  static const base = Color(0xFF0A0A0E);
  static const surface1 = Color(0xFF121218);
  static const surface2 = Color(0xFF1B1B23);
  static const surface3 = Color(0xFF26262F);
  static const ink = Color(0xFFF4F6F1);
  static const inkSecondary = Color(0xFFA8AEA4);
  // B-04 (Sapuan): dinaikkan dari #62665F (3,37:1 di atas base — di bawah
  // lantai WCAG 4,5:1 untuk teks caption 13dp yang memakainya di mana-mana)
  // ke nilai yang lulus ≥4,5:1 di SEMUA permukaan DS: base 5,98:1 ·
  // surface-1 5,65:1 · surface-2 5,18:1 · surface-3 4,54:1 (tabel hitung
  // ulang di bukti sapuan; amendemen tercatat di DESIGN-SYSTEM.md).
  static const inkFaint = Color(0xFF8A8F87);
  static const accent = Color(0xFFB8F135);
  static const onAccent = Color(0xFF10130A);
  static const accentPressed = Color(0xFF9BD62A);
  static const liked = Color(0xFFFF5C7A);
  static const error = Color(0xFFFF6B5E);
  static const warning = Color(0xFFFFB224);
  static const divider = Color(0x14FFFFFF);
  static const scrim = Color(0x8F000000);
}

/// Spasi grid 4dp (DS Bab 4).
class ClaiSpace {
  static const xs = 4.0, sm = 8.0, md = 12.0, lg = 16.0, xl = 20.0, xxl = 24.0, huge = 32.0;
  static const screenMargin = 16.0;
}

class ClaiRadius {
  static const cover = 8.0, card = 16.0, sheet = 20.0, pill = 999.0;
}

/// Token v4.0 (DS v4.0 — "Volt Dimodernkan", Workstream E F3): lapis
/// SUASANA di samping lapis sinyal Volt. Volt tetap satu-satunya aksen
/// fungsional; nilai-nilai di sini hanya mengatur tinta sampul
/// ("Sampul Hidup") dan bahan kaca. Matematika derivasinya hidup di
/// `services/ambient_theme.dart` (murni & teruji).
class ClaiAmbient {
  /// Latar pekat di balik gugus chrome (resep papan varian Beranda A):
  /// di bawah tepi atas kartu mini, konten TIDAK lagi menembus — gradasi
  /// panjang di atas kartulah yang meleburkan konten ke pekat ini.
  static const chromeBacking = Color(0xFF060609);

  /// Resep kaca (DS v4.0 §3-P2): blur latar + tint tinta + tepi cahaya.
  static const glassBlur = 24.0;
  static const glassTintAlpha = 0.15; // pita resep 0,12–0,18
  static const glassEdgeAlpha = 0.20;

  /// Plafon kekuatan wash per kekuatan ambien terpilih (KD-3).
  /// Ronde Sapuan 8045 (vonis perangkat pemilik 2026-11-10): plafon
  /// Hidup NAIK 0,28 → 0,44 — pada 0,28 ruangan Beranda tidak terbaca
  /// mengambil warna sampul ("kurang pekat dalam mode Hidup").
  /// Penjaga keterbacaan tetap berhak menurunkan dari plafon ini
  /// (undakan penjaga di ambient_theme.dart); Tenang TIDAK berubah.
  static const washCapLively = 0.44; // "Hidup" (bawaan terpilih)
  static const washCapCalm = 0.16; // "Tenang"

  /// Plafon wash di Player: ruang lagu itu sendiri boleh lebih pekat.
  /// 8045: 0,40 → 0,50 (kepala ruang untuk ayunan napas yang terlihat).
  static const washCapPlayer = 0.50;

  /// Dosis tinta layar tugas/baca relatif terhadap dosis layar pahlawan.
  static const taskDose = 0.40;

  /// Alfa glow di balik sampul Player (amb/glow).
  /// 8045 (vonis "ambien bernapas belum berfungsi"): sinyal napas di
  /// HP pemilik TERBUKTI berayun penuh (level 1,00 · faktor 1,30) —
  /// kegagalannya VISIBILITAS: pada alfa dasar 0,45 ayunan ±30%
  /// hanya menggerakkan ±0,135 alfa di rim glow yang sempit. Dasar
  /// naik ke 0,65 → ayunan ±0,195 alfa pada bidang glow yang sama,
  /// frekuensi amplop tetap < 0,15 Hz (Anggaran Gerak utuh).
  static const glowAlpha = 0.65;

  /// Jendela "tinta menetap": ganti trek lebih cepat dari ini tidak
  /// mengganti tinta sampai trek bertahan selama jendela ini (anti-kedip).
  static const settleWindow = Duration(milliseconds: 1500);
}
