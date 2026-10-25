import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app.dart';
import '../core/tokens.dart';
import '../services/cover_accent.dart';
import '../services/cover_accent_service.dart';

/// Apakah warna tonal praktis tak berona (sampel monokrom/hampir monokrom)?
/// Ronde Poles Beranda butir 5: permukaan kartu dengan aksen seperti ini
/// tidak boleh tampil flat — pemanggil memberi gradasi netral halus.
/// Ambang: rentang kanal < 10 dari 255 (≈4%) — di bawah itu mata membaca
/// permukaan sebagai abu polos.
bool tonalIsNeutral(Color c) {
  final mx = [c.r, c.g, c.b].reduce((a, b) => a > b ? a : b);
  final mn = [c.r, c.g, c.b].reduce((a, b) => a < b ? a : b);
  return (mx - mn) < 0.04;
}

/// Varian [tonal] yang aman menjadi PERMUKAAN PENUH bertuliskan teks DS
/// (Ronde Putusan Desain butir B & C): digelapkan seperlunya saja menuju
/// [ClaiColors.base] sampai teks sekunder lulus kontras WCAG 4,5:1 —
/// lihat [readableSurfaceRgb]. Tonal kebanyakan sampul lolos tanpa diubah.
Color readableAccentSurface(Color tonal) {
  ({int r, int g, int b}) rgbOf(Color c) =>
      (r: (c.r * 255).round(), g: (c.g * 255).round(), b: (c.b * 255).round());
  final out = readableSurfaceRgb(
    rgbOf(tonal),
    rgbOf(ClaiColors.inkSecondary),
    rgbOf(ClaiColors.base),
  );
  return Color.fromARGB(255, out.r, out.g, out.b);
}

/// Memuat warna tonal sampul (aturan yang sama dengan [CoverAccentGlow]:
/// sakelar `ui.dynamicAccent`, cache layanan aksen) lalu menyerahkannya ke
/// [builder] — untuk permukaan yang perlu MEWARNAI DIRINYA (kartu Beranda),
/// bukan sekadar memberi latar di belakang sampul.
class CoverAccentBuilder extends ConsumerStatefulWidget {
  final String? artworkUrl;
  final Widget Function(BuildContext context, Color? tonal) builder;
  const CoverAccentBuilder({
    super.key,
    required this.artworkUrl,
    required this.builder,
  });
  @override
  ConsumerState<CoverAccentBuilder> createState() => _CoverAccentBuilderState();
}

class _CoverAccentBuilderState extends ConsumerState<CoverAccentBuilder> {
  Color? _tonal;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(CoverAccentBuilder old) {
    super.didUpdateWidget(old);
    if (old.artworkUrl != widget.artworkUrl) _load();
  }

  Future<void> _load() async {
    final db = ref.read(appDbProvider);
    final on = await db.pref<bool>('ui.dynamicAccent') ?? true;
    if (!on || widget.artworkUrl == null) {
      if (mounted) setState(() => _tonal = null);
      return;
    }
    final tonal = await CoverAccentService(db).tonalForUrl(widget.artworkUrl);
    if (mounted) setState(() => _tonal = tonal);
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _tonal);
}

/// Latar tonal di belakang sampul (F2 Batch 2, DS Bab 2): warna diturunkan
/// dari sampul yang sedang tampil, dijenuhkan 20%, hanya sebagai latar —
/// tombol putar & indikator status tetap Volt. Bila sakelar mati atau aksen
/// tak tersedia, anak tampil apa adanya (tanpa latar).
class CoverAccentGlow extends ConsumerStatefulWidget {
  final String? artworkUrl;
  final double pad;
  final double radius;
  final Widget child;
  const CoverAccentGlow({
    super.key,
    required this.artworkUrl,
    required this.child,
    this.pad = 10,
    this.radius = 20,
  });
  @override
  ConsumerState<CoverAccentGlow> createState() => _CoverAccentGlowState();
}

class _CoverAccentGlowState extends ConsumerState<CoverAccentGlow> {
  Color? _tonal;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(CoverAccentGlow old) {
    super.didUpdateWidget(old);
    if (old.artworkUrl != widget.artworkUrl) _load();
  }

  Future<void> _load() async {
    final db = ref.read(appDbProvider);
    final on = await db.pref<bool>('ui.dynamicAccent') ?? true;
    if (!on || widget.artworkUrl == null) {
      if (mounted) setState(() => _tonal = null);
      return;
    }
    final tonal = await CoverAccentService(db).tonalForUrl(widget.artworkUrl);
    if (mounted) setState(() => _tonal = tonal);
  }

  @override
  Widget build(BuildContext context) {
    final tonal = _tonal;
    if (tonal == null) return widget.child;
    return Container(
      padding: EdgeInsets.all(widget.pad),
      decoration: BoxDecoration(
        color: tonal,
        borderRadius: BorderRadius.circular(widget.radius),
        // F2 Batch 2.1: halo berwarna yang memancar ke permukaan di
        // sekelilingnya — bingkai padat saja (5–10 dp, 72% hitam pada
        // rumus lama) berada di bawah ambang persepsi layar HP. Bayangan
        // berwarna membuat nuansa sampul terbaca nyata, sementara isi
        // kotak tetap gelap dan tombol/indikator tetap Volt.
        boxShadow: [
          BoxShadow(
            color: tonal.withValues(alpha: 0.55),
            blurRadius: 26,
            spreadRadius: 2,
          ),
        ],
      ),
      child: widget.child,
    );
  }
}
