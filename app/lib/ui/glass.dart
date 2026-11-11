import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app.dart';
import '../core/spring.dart';
import '../core/tokens.dart';
import '../services/ambient_theme.dart';

/// Animasi silang warna tinta (U2): warna TIDAK memotong — ia mengalir
/// dari warna lama ke warna baru digerakkan simulasi spring
/// (ClaiSprings.trackChange, ±600 md), bukan easing. Gerak-reduksi
/// (sistem atau sakelar Kurangi Efek) → warna menetap seketika.
class TintCrossfade extends StatefulWidget {
  final Color target;
  final bool reduceMotion;
  final Widget Function(BuildContext context, Color color) builder;
  const TintCrossfade({
    super.key,
    required this.target,
    required this.builder,
    this.reduceMotion = false,
  });
  @override
  State<TintCrossfade> createState() => _TintCrossfadeState();
}

class _TintCrossfadeState extends State<TintCrossfade>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController.unbounded(vsync: this, value: 1);
  late Color _from = widget.target;
  late Color _to = widget.target;

  @override
  void didUpdateWidget(TintCrossfade old) {
    super.didUpdateWidget(old);
    if (old.target == widget.target) return;
    _from = Color.lerp(_from, _to, _c.value.clamp(0, 1)) ?? _to;
    _to = widget.target;
    if (widget.reduceMotion) {
      _c.value = 1;
      _from = _to;
      return;
    }
    _c
      ..stop()
      ..value = 0
      ..animateWith(
        SpringSimulation(ClaiSprings.trackChange, 0, 1, 0),
      );
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (context, _) => widget.builder(
          context,
          Color.lerp(_from, _to, _c.value.clamp(0, 1)) ?? _to,
        ),
      );
}

/// Permukaan KACA (DS v4.0 §3-P2): hanya untuk elemen yang MELAYANG di
/// atas konten bergerak — mini player, bilah nav, lembar konteks, kartu
/// lagu berjalan, kepala lengket. Resep: blur latar 24 + tint tinta
/// sampul + tepi cahaya 1 dp sebagai SATU mekanisme kedalaman (tanpa
/// bayangan tebal — hukum ghost-card dirumuskan ulang, bukan dicabut).
///
/// Tema mati atau Kurangi Efek aktif → jatuh ke permukaan tonal
/// [fallback] (perilaku v3.1), tanpa blur.
class GlassSurface extends ConsumerWidget {
  final double radius;
  final Widget child;

  /// Warna tonal saat kaca tidak berlaku (bawaan surface-2 DS).
  final Color fallback;

  /// Tint eksplisit; null = ambil dari palet ambien berjalan.
  final Color? tint;

  /// True = hanya sudut atas yang membulat (lembar bawah).
  final bool topOnly;

  /// Penggelapan dasar di bawah tint (0..1): lembar di atas konten
  /// ramai butuh dasar lebih pekat agar teks tetap raja; permukaan di
  /// atas penopang pekat (nav) memakai 0.
  final double darken;

  const GlassSurface({
    super.key,
    required this.radius,
    required this.child,
    this.fallback = ClaiColors.surface2,
    this.tint,
    this.topOnly = false,
    this.darken = 0,
  });

  BorderRadius get _borderRadius => topOnly
      ? BorderRadius.vertical(top: Radius.circular(radius))
      : BorderRadius.circular(radius);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 8053 B(i): irisan UI (tanpa breathFactor) — permukaan kaca tidak
    // dibangun ulang oleh terbitan napas; disableAnimations beraspek
    // agar animasi inset keyboard tidak membangun ulang kaca per bingkai.
    final amb = ref.watch(ambientControllerProvider.select(ambientUiSlice));
    final systemReduced =
        MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final glassOn = amb.enabled && !amb.reduceEffects && !systemReduced;
    if (!glassOn) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: fallback,
          borderRadius: _borderRadius,
          // Fallback transparan (mis. bilah nav mode v3.1) = tanpa kotak
          // sama sekali: tak ada tepi yang digambar.
          border: fallback == Colors.transparent
              ? null
              : Border.all(color: ClaiColors.divider, width: 1),
        ),
        child: child,
      );
    }
    final palette = amb.palette;
    return TintCrossfade(
      target: tint ?? palette.glassTint,
      reduceMotion: amb.reduceEffects || systemReduced,
      builder: (context, tintColor) => ClipRRect(
        borderRadius: _borderRadius,
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(
            sigmaX: ClaiAmbient.glassBlur,
            sigmaY: ClaiAmbient.glassBlur,
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: darken > 0
                  ? Color.alphaBlend(
                      tintColor,
                      ClaiColors.base.withValues(alpha: darken),
                    )
                  : tintColor,
              borderRadius: _borderRadius,
              border: Border.all(color: palette.glassEdge, width: 1),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Lapisan wash ambien di kepala layar (DS v4.0 §5): gradasi radial
/// tinta dari tepi atas, memudar penuh sebelum ±45% tinggi layar.
/// [kind] menentukan dosis (pahlawan penuh / tugas 40%). Digambar di
/// BELAKANG konten (IgnorePointer) dan ber-crossfade spring antar lagu.
/// Tema mati → tidak menggambar apa pun (latar v3.1 persis).
class AmbientWashLayer extends ConsumerWidget {
  final AmbientSurfaceKind kind;

  /// Pecahan tinggi layar yang dicakup wash (bawaan 0,45 per DS).
  final double heightFraction;

  /// Pengali alfa wash (napas U1 di Player: faktor amplop 0,7–1,3 yang
  /// sudah diinterpolasi pemanggil). 1,0 = tanpa modulasi (bawaan,
  /// semua permukaan selain Player).
  final double alphaFactor;
  const AmbientWashLayer({
    super.key,
    required this.kind,
    this.heightFraction = 0.45,
    this.alphaFactor = 1.0,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 8053 B(i): irisan UI (tanpa breathFactor) — wash Beranda/Koleksi
    // tidak dibangun ulang oleh napas (modulasi napas hanya di Player,
    // yang faktornya tiba lewat alphaFactor dari papan Player sendiri).
    final amb = ref.watch(ambientControllerProvider.select(ambientUiSlice));
    if (!amb.enabled || !amb.palette.active) {
      return const SizedBox.shrink();
    }
    final systemReduced =
        MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final h = MediaQuery.sizeOf(context).height * heightFraction;
    return IgnorePointer(
      child: SizedBox(
        height: h,
        width: double.infinity,
        child: TintCrossfade(
          target: amb.palette.washColor(kind, amb.strength),
          reduceMotion: amb.reduceEffects || systemReduced,
          builder: (context, wash) => DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  wash.withValues(
                      alpha: breathModulatedAlpha(wash.a, alphaFactor)),
                  wash.withValues(alpha: 0),
                ],
                stops: const [0, 1],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Kicker mikro (KD-6, DS v4.0 §3-P4): label seksi fungsional —
/// huruf-besar berjarak, berwarna Volt, hanya di permukaan aplikasi.
class KickerLabel extends StatelessWidget {
  final String text;
  const KickerLabel(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.6,
          color: ClaiColors.accent,
        ),
      );
}

/// Kepala seksi bersama (DS v4.0 §3-P4/P6): saat Tema Dinamis menyala,
/// judul seksi menjadi kicker mikro Volt (KD-6); saat mati, judul klasik
/// DS (17 w600) persis seperti v3.1. [padding] mengikuti pemanggil.
class SectionHeader extends ConsumerWidget {
  final String title;
  final EdgeInsets padding;
  final Widget? trailing;
  const SectionHeader(
    this.title, {
    super.key,
    this.padding = const EdgeInsets.fromLTRB(16, 26, 16, 6),
    this.trailing,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ambOn = ref.watch(
      ambientControllerProvider.select((s) => s.enabled),
    );
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Expanded(
            child: ambOn
                ? KickerLabel(title)
                : Text(
                    title,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: ClaiColors.ink,
                    ),
                  ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}
