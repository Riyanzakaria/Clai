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
