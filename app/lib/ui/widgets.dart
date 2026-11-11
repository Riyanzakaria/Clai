import 'dart:async';
import 'dart:math' as math;

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import '../app.dart';
import '../core/artwork.dart';
import '../core/clai_icons.dart';
import '../core/display_text.dart';
import '../core/spring.dart';
import '../core/tokens.dart';
import 'glass.dart';
import 'haptics.dart';
import '../domain/models.dart';
import '../services/waveform.dart';
import '../l10n/l10n.dart';
import 'content_screen.dart';
import 'radio_screen.dart';

/// Dekorasi kartu baku DS: permukaan + garis tepi 1px samar + radius seragam.
BoxDecoration claiCardDecoration({
  Color color = ClaiColors.surface2,
  double radius = ClaiRadius.card,
}) => BoxDecoration(
  color: color,
  borderRadius: BorderRadius.circular(radius),
  border: Border.all(color: ClaiColors.divider, width: 1),
);

/// Pegangan (handle) sheet baku — SATU bentuk untuk semua lembar bawah (v4.4).
/// Halaman gulir FINITE — pola baku untuk halaman yang anak-anaknya
/// berhingga dan tingginya sangat bervariasi (kartu grup Pengaturan,
/// rak Beranda, panel EQ, kepala halaman konten, dst.).
///
/// Ronde 8052 (glitch gulir halus): `ListView(children:)` membangun
/// anak secara malas dan MEMBUANG anak di luar jendela cache; luas
/// gulir maksimumnya lalu hanya PERKIRAAN dari rata-rata anak yang
/// sedang terbangun (terukur di hub Pengaturan: perkiraan awal 6311 dp
/// runtuh ke 1807–2021 dp dan BERKEDIP di antara dua nilai saat
/// menyeret). Setiap perkiraan ulang menyuntikkan koreksi offset yang
/// MELAWAN seretan pengguna — isi maju lalu terpental kembali
/// berulang-ulang, paling parah pada seretan lambat di zona dalam.
/// Dengan seluruh anak dibangun eager di dalam Column, luas gulir
/// dihitung dari geometri nyata dan KONSTAN sejak bingkai pertama:
/// tidak ada perkiraan, tidak ada pembuangan, tidak ada koreksi.
///
/// Pakai HANYA untuk halaman finite (anak belasan, bukan daftar baris
/// tak berhingga). Daftar baris panjang yang seragam tetap memakai
/// builder/separated seperti biasa — rata-rata tingginya eksak.
class FiniteScrollPage extends StatelessWidget {
  final List<Widget> children;
  final EdgeInsetsGeometry? padding;
  final ScrollController? controller;
  final ScrollPhysics? physics;

  const FiniteScrollPage({
    super.key,
    required this.children,
    this.padding,
    this.controller,
    this.physics,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      controller: controller,
      padding: padding,
      physics: physics,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}

class SheetHandle extends StatelessWidget {
  const SheetHandle({super.key});
  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      width: 36,
      height: 4,
      decoration: BoxDecoration(
        color: ClaiColors.surface3,
        borderRadius: BorderRadius.circular(2),
      ),
    ),
  );
}

/// Tekan ber-spring (DS Bab 5): skala menyusut saat disentuh lalu kembali dengan
/// overshoot halus memakai ClaiSprings.press. Hanya transform — tanpa mengubah
/// perilaku ketuk anak di dalamnya (mendengar pointer, bukan merebut gesture).
class PressableScale extends StatefulWidget {
  final Widget child;
  final double pressedScale;
  const PressableScale({
    super.key,
    required this.child,
    // v4.0 (DS §6.2): skala tekan berevolusi 0,96 → 0,95.
    this.pressedScale = 0.95,
  });
  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController.unbounded(
    vsync: this,
    value: 1,
  );
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _to(double target) {
    // D-05: gerak-reduksi sistem — tanpa spring; nilai ditetapkan langsung.
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _c.value = target;
      return;
    }
    _c.animateWith(
      SpringSimulation(ClaiSprings.press, _c.value, target, _c.velocity),
    );
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: (_) => _to(widget.pressedScale),
    onPointerUp: (_) => _to(1),
    onPointerCancel: (_) => _to(1),
    child: AnimatedBuilder(
      animation: _c,
      builder: (_, child) => Transform.scale(scale: _c.value, child: child),
      child: widget.child,
    ),
  );
}

/// Sampul: gambar jaringan bila ada; placeholder berpola (inisial di atas surface-2) bila tidak (DS Bab 4).
/// v4.4: URL ditulis ulang sadar ukuran tampil (core/artwork.dart) — permukaan
/// besar meminta varian besar, baris daftar tetap varian kecil.
class CoverArt extends StatelessWidget {
  final String? url;
  final double size;
  final String label;
  final double radius;
  const CoverArt({
    super.key,
    this.url,
    required this.size,
    required this.label,
    this.radius = ClaiRadius.cover,
  });
  @override
  Widget build(BuildContext context) {
    // D-35 (DS 6.13): placeholder tanpa label memakai glif nada GAMBAR SENDIRI
    // (ClaiIcons.musicNote), bukan karakter teks '♪' — set ikon aplikasi
    // tidak boleh bocor glyph Unicode.
    final placeholder = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: ClaiColors.surface2,
        borderRadius: BorderRadius.circular(radius),
      ),
      alignment: Alignment.center,
      child: label.isEmpty
          ? ClaiIcon(
              ClaiIcons.musicNote,
              size: math.min(size * 0.44, 72),
              color: ClaiColors.inkFaint,
            )
          : Text(
              label.characters.first.toUpperCase(),
              style: TextStyle(
                fontSize: math.min(size * 0.36, 72),
                fontWeight: FontWeight.w700,
                color: ClaiColors.inkFaint,
              ),
            ),
    );
    if (url == null || url!.isEmpty) return placeholder;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final bucket = artworkBucketFor(size, dpr);
    final sizedUrl = artworkUrlForSize(url, bucket) ?? url!;
    // v4.4.1 (performa): decode DIBATASI seukuran tampil. Sumber persegi
    // (sampul album googleusercontent) di-decode tepat sebesar piksel tampil
    // (ceil(size × dpr), tidak melebihi ember URL) — daftar panjang tidak lagi
    // membayar decode 200px untuk baris 48dp. Sumber lebar (thumbnail video
    // ytimg) tetap memakai ember penuh: krop perseginya butuh lebar ekstra
    // sumber agar ketajaman tidak turun dari v4.4.
    final decodeWidth = sizedUrl.contains('ytimg.com')
        ? bucket
        : math.min(bucket, math.max((size * dpr).ceil(), 1));
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      // Kunci per-URL final (v4.3): ganti lagu = ganti elemen gambar secara tegas,
      // tidak ada peluang elemen lama tertahan menampilkan sampul trek sebelumnya.
      child: Image.network(
        sizedUrl,
        key: ValueKey(sizedUrl),
        width: size,
        height: size,
        fit: BoxFit.cover,
        cacheWidth: decodeWidth,
        errorBuilder: (_, __, ___) => placeholder,
        loadingBuilder: (c, child, prog) => prog == null ? child : placeholder,
      ),
    );
  }
}

/// Sampul LEBAR PENUH persegi (PRD 5.5 "sampul besar", koreksi pemilik v4.3):
/// memenuhi lebar konten (tepi sejajar margin layar), aspek 1:1, sudut membulat.
/// Dipakai Player — sebelumnya sampul hanya kotak 176dp mepet kiri.
class CoverArtWide extends StatelessWidget {
  final String? url;
  final String label;
  final double radius;
  const CoverArtWide({
    super.key,
    this.url,
    required this.label,
    this.radius = 16,
  });
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) =>
        CoverArt(url: url, size: c.maxWidth, label: label, radius: radius),
  );
}

/// Rangka lembar bawah anti-luap (v4.3): tinggi dibatasi 85% layar dan isi bisa
/// digulir. Bukti perangkat v4.2: menu konteks trek menampilkan pita debug
/// "BOTTOM OVERFLOWED BY 3.6 PIXELS" — kolom tetap (pegangan + kepala + sederet
/// aksi) melebihi layar pendek/skala font besar. Semua sheet memakai rangka ini.
class ClaiSheetScaffold extends StatelessWidget {
  final List<Widget> children;
  const ClaiSheetScaffold({super.key, required this.children});
  @override
  Widget build(BuildContext context) {
    final maxH = MediaQuery.sizeOf(context).height * 0.85;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxH),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: children),
        ),
      ),
    );
  }
}

/// Ekualiser 3 batang (DS 6.1) — animasi sederhana, berhenti saat tidak diputar.
class EqualizerBars extends StatefulWidget {
  final bool animating;
  const EqualizerBars({super.key, required this.animating});
  @override
  State<EqualizerBars> createState() => _EqualizerBarsState();
}

class _EqualizerBarsState extends State<EqualizerBars>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void initState() {
    super.initState();
    // 8053 B(ii): controller hanya berlari saat batang sungguh
    // beranimasi. Cabang statis (animating=false) menggambar baris diam
    // yang tidak membaca _c sama sekali, jadi menghentikan controller
    // tidak mengubah satu piksel pun — sebelumnya ticker berputar
    // selamanya di balik baris diam itu.
    if (widget.animating) _c.repeat();
  }

  @override
  void didUpdateWidget(EqualizerBars oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animating != oldWidget.animating) {
      if (widget.animating) {
        _c.repeat();
      } else {
        _c.stop();
      }
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.animating) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final h in [6.0, 10.0, 4.0])
            Container(
              width: 3,
              height: h,
              margin: const EdgeInsets.only(right: 2),
              color: ClaiColors.accent,
            ),
        ],
      );
    }
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        final v = _c.value;
        final hs = [
          6 + 6 * (v < .5 ? v * 2 : (1 - v) * 2),
          12 - 6 * v,
          4 + 8 * ((v + .33) % 1),
        ];
        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (final h in hs)
              Container(
                width: 3,
                height: h,
                margin: const EdgeInsets.only(right: 2),
                color: ClaiColors.accent,
              ),
          ],
        );
      },
    );
  }
}

/// Baris Lagu baku (DS 6.1) — dipakai semua daftar di semua layar.
class SongRow extends ConsumerWidget {
  final Track track;
  final VoidCallback? onTap;
  final bool showMenu;
  final Widget? trailing;
  final int? number;

  /// Tekan-lama pada baris (Ronde Tambahan 2015: masuk mode pilih-banyak
  /// antrean). Null = perilaku lama (tanpa tekan-lama).
  final VoidCallback? onLongPress;

  /// Aksi tombol ⋮ khusus pemanggil (Ronde Tambahan 2015: item antrean
  /// membuka lembar konteks dengan konteks seksinya). Null = lembar
  /// konteks baku atas trek ini.
  final VoidCallback? onMenuPressed;

  /// Keadaan seleksi mode pilih-banyak: null = bukan mode seleksi;
  /// true/false = terpilih/tidak (lingkaran penanda digambar di kiri
  /// sampul, baris terpilih disorot).
  final bool? selected;

  /// v4.0: baris "sedang diputar" di dalam kartu kaca (Antrean) — latar
  /// surface-2 padat diganti transparan agar kaca pembungkusnya tampil.
  final bool glassCurrent;

  /// Nomor tampil DUA DIGIT ("01", "02", …) — bahasa Antrian Redesign
  /// 8051 (DS 6.10 amendemen 4.10). Pemanggil lain (Album, rak Beranda)
  /// membiarkan false: nomor polos seperti sebelumnya.
  final bool twoDigitNumber;

  /// Baris diredupkan (judul ink-secondary, artis ink-faint) — bahasa
  /// baris saran mesin Putar Otomatis di Antrian: saran tidak boleh
  /// tampil sekuat antrean yang disusun pemakai sendiri.
  final bool dimmed;

  const SongRow({
    super.key,
    required this.track,
    this.onTap,
    this.showMenu = true,
    this.trailing,
    this.number,
    this.onLongPress,
    this.onMenuPressed,
    this.selected,
    this.glassCurrent = false,
    this.twoDigitNumber = false,
    this.dimmed = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final handler = ref.watch(audioHandlerProvider);
    return StreamBuilder<MediaItem?>(
      stream: handler.mediaItem.stream,
      initialData: handler.mediaItem.valueOrNull,
      builder: (context, snap) {
        final currentId = snap.data?.id;
        final isCurrent = currentId == '${track.providerId}|${track.id}';
        return StreamBuilder<dynamic>(
          stream: handler.playbackState.stream,
          initialData: handler.playbackState.valueOrNull,
          builder: (context, ps) {
            final playing = (ps.data?.playing ?? false) && isCurrent;
            // v4.4.1: RepaintBoundary per baris — animasi inset keyboard &
            // guliran tidak menggambar ulang isi baris yang tidak berubah.
            return RepaintBoundary(
              child: InkWell(
                onTap: onTap,
                onLongPress: onLongPress,
                splashColor: ClaiColors.accent.withValues(alpha: 0.07),
                highlightColor: ClaiColors.surface2.withValues(alpha: 0.55),
                child: Container(
                  color: selected == true
                      ? ClaiColors.accent.withValues(alpha: 0.10)
                      : isCurrent
                          ? (glassCurrent
                              ? Colors.transparent
                              : ClaiColors.surface2)
                          : null,
                  padding: const EdgeInsets.symmetric(
                    horizontal: ClaiSpace.screenMargin,
                    vertical: 6,
                  ),
                  child: Row(
                    children: [
                      if (selected != null) ...[
                        Container(
                          width: 24,
                          height: 24,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: selected!
                                ? ClaiColors.accent
                                : Colors.transparent,
                            border: Border.all(
                              color: selected!
                                  ? ClaiColors.accent
                                  : ClaiColors.inkFaint,
                              width: 1.6,
                            ),
                          ),
                          child: selected!
                              ? ClaiIcon(
                                  ClaiIcons.check,
                                  size: 15,
                                  color: ClaiColors.onAccent,
                                )
                              : null,
                        ),
                        const SizedBox(width: 10),
                      ],
                      if (number != null)
                        SizedBox(
                          width: 26,
                          child: Text(
                            rowNumberLabel(number!,
                                twoDigit: twoDigitNumber),
                            style: const TextStyle(
                              color: ClaiColors.inkFaint,
                              fontSize: 13,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                        ),
                      Stack(
                        children: [
                          CoverArt(
                            url: track.artworkUrl,
                            size: 48,
                            label: track.title,
                          ),
                          if (isCurrent)
                            Positioned(
                              right: 3,
                              bottom: 3,
                              child: EqualizerBars(animating: playing),
                            ),
                        ],
                      ),
                      const SizedBox(width: ClaiSpace.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Ronde Poles Beranda butir 3: judul–artis TAMPIL dibersihkan
                            // (awalan kurung unggahan & metadata "views/ago" dibuang dari
                            // lapisan tampil saja — data asli tak diubah).
                            Text(
                              cleanDisplayTitle(track.title),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                                color: isCurrent
                                    ? ClaiColors.accent
                                    : dimmed
                                        ? ClaiColors.inkSecondary
                                        : ClaiColors.ink,
                              ),
                            ),
                            Text(
                              cleanDisplayArtist(track.artistNames),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                color: dimmed && !isCurrent
                                    ? ClaiColors.inkFaint
                                    : ClaiColors.inkSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Durasi belum termuat: kolom disembunyikan — tanda "–" lama
                      // terbaca sebagai kerusakan (Poles Beranda butir 3).
                      if (track.duration != null)
                        Text(
                          formatDuration(track.duration!),
                          style: const TextStyle(
                            fontSize: 12,
                            color: ClaiColors.inkSecondary,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      if (trailing != null) trailing!,
                      if (showMenu)
                        // D-01: tombol berikon wajib bernama untuk TalkBack.
                        IconButton(
                          icon: ClaiIcon(
                            ClaiIcons.moreVert,
                            color: ClaiColors.inkSecondary,
                          ),
                          tooltip: context.l10n.a11yTrackOptions,
                          onPressed: onMenuPressed ??
                              () => showTrackContextSheet(context, ref, track),
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

/// Label nomor baris daftar: polos ("7"), atau DUA DIGIT ("07") bila
/// [twoDigit] — bahasa penomoran Antrian Redesign 8051. Angka ≥ 100
/// tampil apa adanya (antrean pemilik bisa ratusan trek).
String rowNumberLabel(int number, {bool twoDigit = false}) =>
    twoDigit ? '$number'.padLeft(2, '0') : '$number';

String formatDuration(Duration d) {
  final m = d.inMinutes;
  final s = d.inSeconds % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}

/// Dropdown penutup baris yang lebarnya TERBATAS (Ronde Poles Beranda,
/// cacat C): DropdownButton polos pada `trailing` ListTile mengukur
/// dirinya dari item TERPANJANGNYA (label kualitas berangka kbps dsb.) —
/// pada layar sempit judul baris teremas sampai ±1 huruf per baris dan
/// nilainya melayang bertumpuk (bukti perangkat pemilik, Pengaturan →
/// Pemutaran). Di sini lebar tombol dibatasi dan tombol diperluas ke
/// batas itu, sehingga judul selalu menyisakan ruang wajar. Semua baris
/// pengaturan berpola nilai-pilihan WAJIB memakai ini.
class BoundedDropdown<T> extends StatelessWidget {
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;
  final double maxWidth;
  const BoundedDropdown({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.maxWidth = 176,
  });
  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: BoxConstraints(maxWidth: maxWidth),
    child: DropdownButton<T>(
      value: value,
      isExpanded: true,
      dropdownColor: ClaiColors.surface2,
      underline: const SizedBox.shrink(),
      items: items,
      onChanged: onChanged,
    ),
  );
}

/// Ubin dropdown BERTUMPUK — pola baku DS §6.14 (Ronde Perbaikan Audit
/// 8047). Pola lama (dropdown sebagai `trailing` ListTile) terbukti
/// meremas kolom judul/subjudul pada lebar 360 dp: judul patah di
/// tengah kata ("Langu/age"), subjudul 5–16 baris dalam kolom ±110 dp
/// (bukti audit: hub Bahasa, skema Menyetir, kualitas Putar). Di pola
/// ini judul + subjudul selebar ubin penuh, dan dropdown
/// [BoundedDropdown] tak terbatas menempati barisnya sendiri di
/// bawahnya. Semua baris pengaturan berpola nilai-pilihan memakai ini;
/// dropdown `trailing` hanya sah untuk nilai pendek pada baris tanpa
/// subjudul panjang — dan pola bertumpuk tetap pilihan baku.
class DropdownTile<T> extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? leading;
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;
  const DropdownTile({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    required this.value,
    required this.items,
    required this.onChanged,
  });
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      ListTile(
        leading: leading,
        title: Text(title, style: const TextStyle(color: ClaiColors.ink)),
        subtitle: subtitle == null
            ? null
            : Text(
                subtitle!,
                style: const TextStyle(color: ClaiColors.inkSecondary),
              ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: BoundedDropdown<T>(
          value: value,
          items: items,
          onChanged: onChanged,
          maxWidth: double.infinity,
        ),
      ),
    ],
  );
}

/// Rak sampul horizontal (Ronde Poles Beranda butir 4): kartu sampul 112
/// dengan judul–artis bersih di bawahnya; ketuk kartu memutar daftar rak
/// dari trek itu. Beranda lama menampilkan semua rak sebagai baris daftar
/// vertikal — layar pertama tidak memuat satu sampul pun selain kartu
/// Sedang Diputar.
class CoverRail extends StatelessWidget {
  final String title;
  final List<Track> tracks;
  final void Function(List<Track> tracks, int index) onPlay;
  const CoverRail({
    super.key,
    required this.title,
    required this.tracks,
    required this.onPlay,
  });

  @override
  Widget build(BuildContext context) {
    if (tracks.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title,
          padding: const EdgeInsets.fromLTRB(16, 26, 16, 10),
        ),
        SizedBox(
          height: 152,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(
              horizontal: ClaiSpace.screenMargin,
            ),
            itemCount: tracks.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, i) {
              final t = tracks[i];
              final titleClean = cleanDisplayTitle(t.title);
              final artistClean = cleanDisplayArtist(t.artistNames);
              return SizedBox(
                width: 112,
                child: Semantics(
                  button: true,
                  label: artistClean.isEmpty
                      ? titleClean
                      : '$titleClean — $artistClean',
                  child: PressableScale(
                    child: GestureDetector(
                      onTap: () => onPlay(tracks, i),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CoverArt(
                            url: t.artworkUrl,
                            size: 112,
                            label: t.title,
                            radius: 12,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            titleClean,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: ClaiColors.ink,
                            ),
                          ),
                          Text(
                            artistClean,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              color: ClaiColors.inkSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Penyaring merek untuk byline (aturan pemilik 2026-10-25: sumber
/// katalog tidak pernah dinamai di teks aplikasi). Nama kanal milik
/// platform itu sendiri ("YouTube Charts" dsb.) menjadi string kosong;
/// nama artis/pengguna nyata tidak disentuh. Ditemukan ronde Koreksi
/// Komposisi: byline kartu Charts menampilkan nama kanal platform.
String brandSafeByline(String raw) =>
    raw.toLowerCase().contains('youtube') ? '' : raw;

/// Varian strapline halaman konten ("A • B • C"): segmen yang menamai
/// platform dibuang, segmen jujur lain dipertahankan; kosong total →
/// null (pemanggil menyembunyikan barisnya / menyimpan tanpa subjudul).
String? brandSafeSubtitle(String? raw) {
  if (raw == null) return null;
  final kept = raw
      .split('•')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty && !s.toLowerCase().contains('youtube'))
      .toList();
  return kept.isEmpty ? null : kept.join(' • ');
}

/// Subjudul baris halaman Mood (audit 8047): byline mentah umpan Mood
/// ("Playlist • YouTube Music") dulu tampil apa adanya — menamai merek
/// sumber di UI, melanggar aturan merek. Kini melewati saringan yang
/// sama seperti permukaan lain; tak bersisa → label jenis barisnya.
String moodRowSubtitle(String rawByline, String kindLabel) =>
    brandSafeSubtitle(rawByline) ?? kindLabel;

/// Lembar Menu Konteks (DS 6.8) — urutan baku, sama di semua layar; varian antrean menambah aksi destruktif terakhir.
Future<void> showTrackContextSheet(
  BuildContext context,
  WidgetRef ref,
  Track track, {
  bool fromQueue = false,
  VoidCallback? onRemoveFromQueue,
  // Ronde Tambahan 2015 (Butir 3): untuk item yang SUDAH di antrean,
  // "Putar Berikutnya"/"Tambah ke Antrian" ditimpa pemanggil menjadi
  // semantik PINDAH (tanpa duplikat); null = semantik salin baku.
  VoidCallback? onPlayNextOverride,
  VoidCallback? onAddToQueueOverride,
}) async {
  final handler = ref.read(audioHandlerProvider);
  final lib = ref.read(libraryProvider);
  final liked = lib.isLiked(track.key);
  await showModalBottomSheet<void>(
    context: claiRootContext(context),
    // v4.0: lembar konteks = KACA bertinta lagu berjalan (U3) — latar
    // digambar GlassSurface di dalam; tema mati → fallback tonal
    // surface-2 persis seperti sebelumnya.
    backgroundColor: Colors.transparent,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(ClaiRadius.sheet),
      ),
    ),
    builder: (sheetCtx) {
      Widget act(
        ClaiIconData icon,
        String label,
        VoidCallback fn, {
        Color? color,
      }) => ListTile(
        leading: ClaiIcon(icon, color: color ?? ClaiColors.ink, size: 24),
        title: Text(
          label,
          style: TextStyle(color: color ?? ClaiColors.ink, fontSize: 17),
        ),
        minTileHeight: 52,
        onTap: () {
          Navigator.of(sheetCtx).pop();
          fn();
        },
      );
      // Kepala papan 07: sampul 56 radius 12 + judul display + sub
      // "artis · durasi" + HATI interaktif di kepala. Keadaan suka =
      // state lokal lembar (likedNow, disemai dari perpustakaan saat
      // lembar dibuka); hati kepala dan baris Simpan ke Koleksi
      // mengubahnya tanpa menutup lembar. Tanpa garis pemisah di bawah
      // kepala (papan 07).
      var likedNow = liked;
      return StatefulBuilder(
        builder: (innerCtx, setSheetState) {
          void toggleLikeNow() {
            ClaiHaptics.like();
            lib.toggleLike(track);
            setSheetState(() => likedNow = !likedNow);
          }

          return GlassSurface(
            radius: ClaiRadius.sheet,
            topOnly: true,
            darken: 0.55,
            child: ClaiSheetScaffold(
              children: [
                const SizedBox(height: 8),
                const SheetHandle(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 12, 12),
                  child: Row(children: [
                    CoverArt(
                      url: track.artworkUrl,
                      size: 56,
                      label: track.title,
                      radius: 12,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            track.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: displayStyle(20)
                                .copyWith(color: ClaiColors.ink),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            // Gabung hanya bagian yang ada: artis kosong
                            // di data sumber tidak boleh menyisakan
                            // "· durasi" menggantung (temuan bukti k4).
                            [
                              if (track.artistNames.trim().isNotEmpty)
                                track.artistNames,
                              if (track.duration != null)
                                formatDuration(track.duration!),
                            ].join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: ClaiColors.inkSecondary,
                                fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: likedNow
                          ? context.l10n.ctxRemoveFromCollection
                          : context.l10n.ctxSaveToCollection,
                      onPressed: toggleLikeNow,
                      icon: ClaiIcon(
                        likedNow ? ClaiIcons.heartFill : ClaiIcons.heart,
                        color: likedNow
                            ? ClaiColors.liked
                            : ClaiColors.inkSecondary,
                        size: 26,
                      ),
                    ),
                  ]),
                ),
          act(
            ClaiIcons.next,
            context.l10n.ctxPlayNext,
            onPlayNextOverride ?? () => handler.enqueue(track, next: true),
          ),
          act(
            ClaiIcons.queue,
            context.l10n.ctxAddToQueue,
            onAddToQueueOverride ?? () => handler.enqueue(track, next: false),
          ),
          act(
            ClaiIcons.radio,
            context.l10n.ctxStartRadio,
            () => openRadioPage(context, track),
          ),
          act(
            likedNow ? ClaiIcons.heartFill : ClaiIcons.heart,
            likedNow
                ? context.l10n.ctxRemoveFromCollection
                : context.l10n.ctxSaveToCollection,
            toggleLikeNow,
            // Audit 8047 (§6.8/Bab 2): warna liked HANYA saat keadaan
            // tersukai aktif; baris netral (tinta baku) selain itu —
            // dulu baris ini selalu merah muda meski belum disukai.
            color: likedNow ? ClaiColors.liked : null,
          ),
          act(
            ClaiIcons.playlistAdd,
            context.l10n.ctxAddToPlaylist,
            () => showAddToPlaylistSheet(context, ref, track),
          ),
          // Unduh (F2, DS 6.8): berkas lokal perangkat tidak perlu diunduh.
          if (track.providerId != 'local')
            Builder(
              builder: (_) {
                final svc = ref.read(downloadServiceProvider);
                final downloaded = svc.isDownloaded(track.key);
                return act(
                  downloaded ? ClaiIcons.trash : ClaiIcons.download,
                  downloaded
                      ? context.l10n.ctxDeleteDownload
                      : context.l10n.commonDownload,
                  () {
                    if (downloaded) {
                      svc.deleteDownload(track.key);
                    } else {
                      // D-03: unduhan memakai kualitas EFEKTIF (hemat data
                      // memaksa Rendah juga untuk berkas offline).
                      svc.download(track, handler.effectiveQuality);
                    }
                  },
                );
              },
            ),
          if (track.albumId != null)
            act(
              ClaiIcons.album,
              context.l10n.ctxOpenAlbum,
              () => openContent(
                context,
                ref,
                'album',
                track.albumId!,
                track.albumTitle ?? 'Album',
              ),
            ),
          // Butir E (Poles Beranda): "Buka Artis" tampil kapan pun trek punya
          // NAMA artis — bukan hanya bila ID artis terbawa. Trek playlist
          // sering hanya membawa nama; ID diselesaikan lewat pencarian.
          if (canOpenArtist(track))
            act(
              ClaiIcons.person,
              context.l10n.ctxOpenArtist,
              () => openArtistFromTrack(context, ref, track),
            ),
          act(
            ClaiIcons.share,
            context.l10n.ctxShare,
            () => Share.share(claiTrackShareText(track, context.l10n)),
          ),
          if (fromQueue)
            act(
              ClaiIcons.close,
              context.l10n.ctxRemoveFromQueue,
              () => onRemoveFromQueue?.call(),
              color: ClaiColors.error,
            ),
          const SizedBox(height: 8),
              ],
            ),
          );
        },
      );
    },
  );
}

/// Kepala judul lembar pemilih playlist (papan 07: judul display di
/// atas daftar — bukan daftar telanjang tanpa kepala).
Widget _playlistSheetTitle(BuildContext context) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 6),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          context.l10n.ctxAddToPlaylist,
          style: displayStyle(20).copyWith(color: ClaiColors.ink),
        ),
      ),
    );

/// Ubin seni baris playlist di lembar pemilih: mosaik mini dari sampul
/// trek playlist itu sendiri (data nyata PlaylistInfo.artworkUrls);
/// playlist kosong → ubin ikon antrean tonal.
Widget playlistArtTile(List<String?> urls, double size) {
  final arts =
      urls.whereType<String>().where((u) => u.isNotEmpty).take(4).toList();
  if (arts.isEmpty) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: ClaiColors.surface3,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(
          child: ClaiIcon(ClaiIcons.queue,
              color: ClaiColors.inkSecondary, size: size * 0.45)),
    );
  }
  if (arts.length == 1) {
    return CoverArt(url: arts.first, size: size, label: '', radius: 12);
  }
  return ClipRRect(
    borderRadius: BorderRadius.circular(12),
    child: SizedBox(
      width: size,
      height: size,
      child: GridView.count(
        crossAxisCount: 2,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          for (final u in arts)
            CoverArt(url: u, size: size / 2, label: '', radius: 0)
        ],
      ),
    ),
  );
}

Future<void> showAddToPlaylistSheet(
  BuildContext context,
  WidgetRef ref,
  Track track,
) async {
  final lib = ref.read(libraryProvider);
  await showModalBottomSheet<void>(
    context: claiRootContext(context),
    backgroundColor: ClaiColors.surface2,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(ClaiRadius.sheet),
      ),
    ),
    builder: (ctx) => ClaiSheetScaffold(
      children: [
        const SizedBox(height: 8),
        const SheetHandle(),
        _playlistSheetTitle(context),
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
          leading: tonalIconBox(ClaiIcons.add, size: 48, iconSize: 22),
          title: Text(
            context.l10n.ctxNewPlaylist,
            style: const TextStyle(color: ClaiColors.ink, fontSize: 16),
          ),
          onTap: () async {
            Navigator.of(ctx).pop();
            final name = await promptText(
              context,
              context.l10n.ctxPlaylistName,
            );
            if (name != null && name.trim().isNotEmpty) {
              // Temuan fungsi audit 8047: dulu playlist baru dibuat
              // lalu lembar dibuka lagi TANPA memasukkan trek yang
              // sedang ditambahkan — playlist lahir 0 lagu. Kini trek
              // ikut masuk ke playlist barunya lebih dulu.
              final id = await lib.createPlaylist(name.trim());
              await lib.addToPlaylist(id, track);
              if (context.mounted) showAddToPlaylistSheet(context, ref, track);
            }
          },
        ),
        for (final pl in lib.playlists)
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
            leading: playlistArtTile(pl.artworkUrls, 48),
            title: Text(pl.name, style: const TextStyle(color: ClaiColors.ink)),
            subtitle: Text(
              context.l10n.songCount(pl.count),
              style: const TextStyle(color: ClaiColors.inkSecondary),
            ),
            onTap: () async {
              Navigator.of(ctx).pop();
              final added = await lib.addToPlaylist(pl.id, track);
              if (!added && context.mounted) {
                final keep = await showDialog<bool>(
                  context: context,
                  builder: (d) => AlertDialog(
                    backgroundColor: ClaiColors.surface2,
                    title: Text(
                      context.l10n.ctxAlreadyInPlaylist,
                      style: const TextStyle(color: ClaiColors.ink),
                    ),
                    content: Text(
                      context.l10n.ctxAlreadyInPlaylistBody,
                      style: const TextStyle(color: ClaiColors.inkSecondary),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(d, false),
                        child: Text(context.l10n.ctxSkip),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(d, true),
                        child: Text(context.l10n.ctxAddAnyway),
                      ),
                    ],
                  ),
                );
                if (keep == true) {
                  await lib.addToPlaylist(pl.id, track, allowDuplicate: true);
                }
              }
            },
          ),
        const SizedBox(height: 8),
      ],
    ),
  );
}

/// Pemilih playlist MASSAL (Ronde Tambahan 2015): pola visual yang sama
/// dengan [showAddToPlaylistSheet] per-lagu, tetapi menambahkan SELURUH
/// [tracks] sekaligus. Duplikat dilewati tanpa dialog per-lagu; umpan
/// balik berupa satu pemberitahuan hitungan di akhir. "Playlist Baru"
/// membuat playlist lalu mengisinya dengan seluruh daftar. Mengembalikan
/// true bila ada trek yang masuk ke suatu playlist (pemanggil memakai
/// ini untuk keluar dari mode pilih-banyak); [onFeedback] menimpa kanal
/// SnackBar baku (layar Antrian memakai messenger lokalnya sendiri).
Future<bool> showAddTracksToPlaylistSheet(
  BuildContext context,
  WidgetRef ref,
  List<Track> tracks, {
  void Function(String message)? onFeedback,
}) async {
  final lib = ref.read(libraryProvider);
  final l = context.l10n;
  void feedback(String message) {
    if (onFeedback != null) {
      onFeedback(message);
    } else if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<bool> addAllTo(String playlistId) async {
    final added = await lib.addAllToPlaylist(playlistId, tracks);
    feedback(added > 0
        ? l.bulkPlaylistAdded(added)
        : l.bulkPlaylistNone);
    return added > 0;
  }

  // Hasil akhir ditentukan lewat Completer: baris lembar menutup lembar
  // DULU baru menjalankan aksinya (pola pemilih per-lagu), sehingga masa
  // depan lembar selesai sebelum `acted` diketahui — menunggu lembar
  // saja akan membaca nilai basi (mode pilih tak keluar; terbukti di
  // emulator Ronde Tambahan 2015).
  final done = Completer<bool>();
  var flowStarted = false;
  void finish(bool ok) {
    if (!done.isCompleted) done.complete(ok);
  }

  await showModalBottomSheet<void>(
    context: claiRootContext(context),
    backgroundColor: ClaiColors.surface2,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(ClaiRadius.sheet),
      ),
    ),
    builder: (ctx) => ClaiSheetScaffold(
      children: [
        const SizedBox(height: 8),
        const SheetHandle(),
        _playlistSheetTitle(context),
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
          leading: tonalIconBox(ClaiIcons.add, size: 48, iconSize: 22),
          title: Text(
            context.l10n.ctxNewPlaylist,
            style: const TextStyle(color: ClaiColors.ink, fontSize: 16),
          ),
          onTap: () async {
            flowStarted = true;
            Navigator.of(ctx).pop();
            final name = await promptText(
              context,
              context.l10n.ctxPlaylistName,
            );
            if (name != null && name.trim().isNotEmpty) {
              final id = await lib.createPlaylist(name.trim());
              finish(await addAllTo(id));
            } else {
              finish(false);
            }
          },
        ),
        for (final pl in lib.playlists)
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
            leading: playlistArtTile(pl.artworkUrls, 48),
            title: Text(pl.name, style: const TextStyle(color: ClaiColors.ink)),
            subtitle: Text(
              context.l10n.songCount(pl.count),
              style: const TextStyle(color: ClaiColors.inkSecondary),
            ),
            onTap: () async {
              flowStarted = true;
              Navigator.of(ctx).pop();
              finish(await addAllTo(pl.id));
            },
          ),
        const SizedBox(height: 8),
      ],
    ),
  );
  if (done.isCompleted) return done.future;
  if (flowStarted) return done.future;
  return false;
}

/// SnackBar untuk halaman yang didorong DI DALAM cangkang (Ronde
/// Tambahan 2015, Butir 4): halaman-halaman itu kini hidup di navigator
/// dalam, sehingga SnackBar biasa mendarat di dasar area dalam — tertutup
/// gugus chrome melayang. Varian melayang ini terangkat tepat di atas
/// gugus (margin bawah = ruang bebas chrome + napas).
SnackBar claiSnackAboveChrome(BuildContext context, String message,
    {SnackBarAction? action}) {
  return SnackBar(
    content: Text(message),
    action: action,
    behavior: SnackBarBehavior.floating,
    margin: EdgeInsets.fromLTRB(
        16, 0, 16, bottomChromeClearance(context) + 6),
  );
}

/// Dekorasi bidang teks baku DS (Ronde Sapuan 8045): isian tonal
/// surface-3, radius 12, TANPA garis bawah Material — satu resep untuk
/// semua bidang ketik di dialog & lembar (nama playlist, nama sapaan,
/// tempel tautan Tangkap, token ListenBrainz, ketik suara). Bidang
/// cari utama memakai varian pilnya sendiri (papan 04).
InputDecoration claiFieldDecoration({String? hintText, String? labelText}) {
  const border = OutlineInputBorder(
    borderSide: BorderSide.none,
    borderRadius: BorderRadius.all(Radius.circular(12)),
  );
  return InputDecoration(
    hintText: hintText,
    labelText: labelText,
    hintStyle: const TextStyle(color: ClaiColors.inkFaint),
    labelStyle: const TextStyle(color: ClaiColors.inkSecondary),
    filled: true,
    fillColor: ClaiColors.surface3,
    border: border,
    enabledBorder: border,
    focusedBorder: const OutlineInputBorder(
      borderSide: BorderSide(color: ClaiColors.accent, width: 1),
      borderRadius: BorderRadius.all(Radius.circular(12)),
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
  );
}

/// Kotak ikon tonal baku (DS: ikon berkotak tonal): wadah surface-2
/// radius 12 berisi satu ikon — dipakai baris pintu, strip, dan kartu
/// di seluruh aplikasi agar bahasanya satu.
Widget tonalIconBox(ClaiIconData icon,
    {double size = 40, double iconSize = 20, Color? color}) {
  return Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: ClaiColors.surface2,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Center(
      child: ClaiIcon(icon, size: iconSize, color: color ?? ClaiColors.accent),
    ),
  );
}

/// Baris entitas baku DS (Ronde Sapuan 8045): sampul 48 radius 8
/// (artis: bulat), judul 15 w500, subjudul 13 — keluarga baris yang
/// sama dengan [SongRow] untuk entitas non-trek (album, playlist,
/// artis). Menggantikan ListTile mentah yang tersisa di hasil Cari,
/// halaman Mood, diskografi & artis terkait halaman konten, dan
/// baris unduhan/Spotify. [trailing] bebas (status, chevron, aksi).
class EntityRow extends StatelessWidget {
  final String? artworkUrl;
  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool round;
  const EntityRow({
    super.key,
    this.artworkUrl,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    this.round = false,
  });
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(children: [
          leading ??
              CoverArt(
                url: artworkUrl,
                size: 48,
                label: title,
                radius: round ? 24 : 8,
              ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: ClaiColors.ink,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      color: ClaiColors.inkSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 8),
            trailing!,
          ],
        ]),
      ),
    );
  }
}

Future<String?> promptText(
  BuildContext context,
  String label, {
  String? initialValue,
}) async {
  // Audit 8047: nilai awal opsional (mis. dialog ganti nama mengisi
  // nama saat ini, terpilih semua agar mudah diganti total).
  final c = TextEditingController(text: initialValue);
  if (initialValue != null && initialValue.isNotEmpty) {
    c.selection = TextSelection(
      baseOffset: 0,
      extentOffset: initialValue.length,
    );
  }
  return showDialog<String>(
    context: context,
    builder: (d) => AlertDialog(
      backgroundColor: ClaiColors.surface2,
      title: Text(label, style: const TextStyle(color: ClaiColors.ink)),
      content: TextField(
        controller: c,
        autofocus: true,
        style: const TextStyle(color: ClaiColors.ink),
        decoration: claiFieldDecoration(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(d),
          child: Text(context.l10n.commonCancel),
        ),
        TextButton(
          onPressed: () => Navigator.pop(d, c.text),
          child: Text(context.l10n.commonSave),
        ),
      ],
    ),
  );
}

void openContent(
  BuildContext context,
  WidgetRef ref,
  String kind,
  String id,
  String title,
) {
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => ContentScreen(kind: kind, id: id, titleHint: title),
    ),
  );
}

/// Buka halaman Radio lagu (F2.5): halaman ini HANYA menampilkan bangkitan
/// radio — membukanya tidak menyentuh pemutaran yang sedang berjalan.
void openRadioPage(BuildContext context, Track seed) {
  Navigator.of(
    context,
  ).push(MaterialPageRoute(builder: (_) => RadioScreen(seed: seed)));
}

/// Tautan unduh APK yang selalu menunjuk rilis terbaru (dipakai baris
/// kredit teks berbagi F2.5 dan permukaan lain yang butuh URL abadi).
const String kClaiEvergreenApkUrl =
    'https://github.com/Riyanzakaria/Clai/releases/latest/download/clai.apk';

/// URL katalog publik satu trek (untuk teks yang DIBAGIKAN, bukan teks
/// tampilan aplikasi). Null untuk trek non-katalog (berkas lokal dsb.) —
/// tidak ada tautan jujur yang bisa dibuat untuk mereka.
String? catalogWatchUrl(Track t) => t.providerId == 'ytmusic'
    ? 'https://music.youtube.com/watch?v=${t.id}'
    : null;

/// Teks berbagi lagu (F2.5, Pamer tingkat 1 — murni & diuji): baris pertama
/// "Judul — Artis", baris kedua tautan katalog (hanya trek katalog), baris
/// terakhir kredit Clai + tautan unduh abadi.
String claiTrackShareText(Track t, AppLocalizations l10n) {
  final buf = StringBuffer('${t.title} — ${t.artistNames}');
  final url = catalogWatchUrl(t);
  if (url != null) buf.write('\n$url');
  buf.write('\n${l10n.ctxShareCredit(kClaiEvergreenApkUrl)}');
  return buf.toString();
}

/// Teks berbagi halaman koleksi (album/playlist/artis): entitasnya bukan
/// satu trek, jadi tanpa tautan tonton — judul — subjudul + baris kredit.
String claiPageShareText(String title, String subtitle, AppLocalizations l10n) {
  final head = subtitle.trim().isEmpty ? title : '$title — $subtitle';
  return '$head\n${l10n.ctxShareCredit(kClaiEvergreenApkUrl)}';
}

/// Aturan tampil "Buka Artis" (Butir E, murni & diuji): trek cukup punya
/// ID artis ATAU nama artis — tombol tidak lagi hilang diam-diam untuk
/// trek playlist yang hanya membawa nama.
bool canOpenArtist(Track track) =>
    track.artistIds.isNotEmpty ||
    primaryArtistName(track.artistNames).isNotEmpty;

/// Nama artis utama untuk kueri resolusi: segmen byline pertama, dipotong
/// pada penanda kolaborasi ("&", ",", "feat.").
String primaryArtistName(String artistNames) {
  var s = artistNames.split('•').first.trim();
  s = s.split(RegExp(r'\s*(?:&|,)\s*')).first.trim();
  s = s
      .split(RegExp(r'\s+(?:feat\.?|ft\.?)\s+', caseSensitive: false))
      .first
      .trim();
  // Label kategori sumber ("Song"/"Video" dari kolom byline YTM)
  // BUKAN nama artis — diperlakukan sebagai tanpa nama.
  if (s.toLowerCase() == 'song' || s.toLowerCase() == 'video') return '';
  return s;
}

/// Pilih artis hasil pencarian untuk [name]: kecocokan nama persis
/// (abaikan huruf besar/kecil) didahulukan; bila tak ada, hasil artis
/// pertama; daftar kosong → null (resolusi gagal).
Artist? pickArtistForName(List<Artist> results, String name) {
  final want = name.trim().toLowerCase();
  for (final a in results) {
    if (a.name.trim().toLowerCase() == want) return a;
  }
  return results.isEmpty ? null : results.first;
}

/// Buka halaman artis untuk [track] dari lembar konteks (Butir E):
/// ID langsung bila ada; bila hanya nama, selesaikan lewat pencarian
/// artis provider. Gagal total → keadaan jujur (snackbar), bukan diam.
Future<void> openArtistFromTrack(
  BuildContext context,
  WidgetRef ref,
  Track track,
) async {
  if (track.artistIds.isNotEmpty) {
    openContent(
      context,
      ref,
      'artist',
      track.artistIds.first,
      track.artistNames,
    );
    return;
  }
  final name = primaryArtistName(track.artistNames);
  Artist? artist;
  try {
    final res = await ref.read(ytMusicProvider).search(name);
    artist = pickArtistForName(res.artists, name);
  } catch (_) {
    artist = null;
  }
  if (!context.mounted) return;
  if (artist != null) {
    openContent(context, ref, 'artist', artist.id, artist.name);
  } else {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(context.l10n.artistNotFound)));
  }
}

// ---------- keadaan layar (DS 6.12) ----------
/// Rangka muat DS 6.12 (Sapuan D-26): blok surface-2 BERDENYUT opasitas
/// 0,6↔1 dalam siklus 1200 ms — sebelumnya balok statis. Saat gerak-reduksi
/// sistem aktif (D-05), denyut mati dan rangka tampil statis.
class LoadingSkeleton extends StatefulWidget {
  const LoadingSkeleton({super.key});
  @override
  State<LoadingSkeleton> createState() => _LoadingSkeletonState();
}

class _LoadingSkeletonState extends State<LoadingSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduced && _pulse.isAnimating) _pulse.stop();
    if (!reduced && !_pulse.isAnimating) _pulse.repeat(reverse: true);
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) {
        final opacity = reduced ? 1.0 : 0.6 + 0.4 * _pulse.value;
        final block = ClaiColors.surface2.withValues(alpha: opacity);
        return ListView.builder(
          itemCount: 6,
          physics: const NeverScrollableScrollPhysics(),
          itemBuilder: (_, __) => Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: ClaiSpace.screenMargin,
              vertical: 6,
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: block,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(height: 14, color: block),
                      const SizedBox(height: 6),
                      Container(height: 12, width: 140, color: block),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Teks berjalan (marquee) DS 6.9 (Sapuan D-25): teks yang muat tampil
/// statis; teks panjang mulai bergeser sesudah 3 detik diam, berputar
/// halus. Mati total saat gerak-reduksi sistem aktif (D-05).
class MarqueeText extends StatefulWidget {
  final String text;
  final TextStyle? style;
  const MarqueeText(this.text, {super.key, this.style});
  @override
  State<MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<MarqueeText> {
  final _scroll = ScrollController();
  bool _started = false;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    if (_started || !mounted) return;
    _started = true;
    // Diam 3 detik dulu (DS 6.9), baru bergeser bila memang meluap.
    await Future<void>.delayed(const Duration(seconds: 3));
    while (mounted && _scroll.hasClients) {
      final max = _scroll.position.maxScrollExtent;
      if (max <= 0) return;
      await _scroll.animateTo(
        max,
        duration: Duration(milliseconds: (max * 28).round()),
        curve: Curves.linear,
      );
      if (!mounted) return;
      await Future<void>.delayed(const Duration(seconds: 2));
      if (!mounted || !_scroll.hasClients) return;
      _scroll.jumpTo(0);
      await Future<void>.delayed(const Duration(seconds: 3));
    }
  }

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduced) {
      return Text(
        widget.text,
        style: widget.style,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      );
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
    return SingleChildScrollView(
      controller: _scroll,
      scrollDirection: Axis.horizontal,
      physics: const NeverScrollableScrollPhysics(),
      child: Text(
        widget.text,
        style: widget.style,
        maxLines: 1,
        softWrap: false,
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  final ClaiIconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  const EmptyState({
    super.key,
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
  });
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClaiIcon(icon, size: 56, color: ClaiColors.inkFaint),
          const SizedBox(height: 16),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: ClaiColors.inkSecondary,
              fontSize: 15,
            ),
          ),
          if (actionLabel != null) ...[
            const SizedBox(height: 16),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: ClaiColors.accent,
                foregroundColor: ClaiColors.onAccent,
              ),
              onPressed: onAction,
              child: Text(actionLabel!),
            ),
          ],
        ],
      ),
    ),
  );
}

class ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const ErrorState({super.key, required this.message, required this.onRetry});
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClaiIcon(ClaiIcons.cloudOff, size: 48, color: ClaiColors.error),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: ClaiColors.inkSecondary),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: onRetry,
            child: Text(context.l10n.commonRetry),
          ),
        ],
      ),
    ),
  );
}

/// Pita waveform ukur untuk permukaan ringkas (Kampanye Rombak UI —
/// kartu Lanjutkan Beranda): gambar diam dari [WaveformData] NYATA
/// trek (DS §11.10). Ember terukur = batang (terputar [playedColor],
/// belum [unplayedColor]); ember belum terukur = garis datar 3 dp
/// [flatColor] — keadaan jujur, bukan batang karangan. Bukan kontrol:
/// seek tetap urusan Player; di kartu, ketukan membuka Player.
class WaveformStrip extends StatelessWidget {
  final WaveformData data;
  final double fraction;
  final Color playedColor;
  final Color unplayedColor;
  final Color flatColor;
  final double height;

  const WaveformStrip({
    super.key,
    required this.data,
    required this.fraction,
    required this.playedColor,
    required this.unplayedColor,
    required this.flatColor,
    this.height = 30,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
        height: height,
        width: double.infinity,
        child: CustomPaint(
          painter: _WaveformStripPainter(
            heights: data.displayHeights(),
            fraction: fraction.clamp(0.0, 1.0),
            playedColor: playedColor,
            unplayedColor: unplayedColor,
            flatColor: flatColor,
          ),
        ),
      );
}

class _WaveformStripPainter extends CustomPainter {
  final List<double?> heights;
  final double fraction;
  final Color playedColor;
  final Color unplayedColor;
  final Color flatColor;

  const _WaveformStripPainter({
    required this.heights,
    required this.fraction,
    required this.playedColor,
    required this.unplayedColor,
    required this.flatColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final n = heights.length;
    if (n == 0 || size.width <= 0) return;
    final slot = size.width / n;
    final barW = math.min(4.0, slot * 0.52);
    final midY = size.height / 2;
    final paint = Paint()..strokeCap = StrokeCap.round;
    for (var i = 0; i < n; i++) {
      final cx = slot * (i + 0.5);
      final h = heights[i];
      final played = (i + 0.5) / n <= fraction;
      if (h == null) {
        paint
          ..color = flatColor
          ..strokeWidth = barW;
        canvas.drawLine(
          Offset(cx, midY - 1.5),
          Offset(cx, midY + 1.5),
          paint,
        );
      } else {
        final bh = math.max(4.0, h * size.height);
        paint
          ..color = played ? playedColor : unplayedColor
          ..strokeWidth = barW;
        canvas.drawLine(
          Offset(cx, midY - bh / 2),
          Offset(cx, midY + bh / 2),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_WaveformStripPainter old) =>
      old.fraction != fraction ||
      !listEquals(old.heights, heights) ||
      old.playedColor != playedColor ||
      old.unplayedColor != unplayedColor ||
      old.flatColor != flatColor;
}

/// Chip kembali kaca 40 dp (Gelombang 2, pola "Kepala Hidup"): satu
/// affordance kembali untuk layar tanpa AppBar — kaca di atas panggung
/// sampul, tonal saat tema kaca/ambien mati (lewat [GlassSurface]).
class GlassBackChip extends StatelessWidget {
  final VoidCallback? onTap;
  const GlassBackChip({super.key, this.onTap});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 40,
        height: 40,
        child: GlassSurface(
          radius: 20,
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: onTap ?? () => Navigator.of(context).maybePop(),
            child: Center(
              child: ClaiIcon(ClaiIcons.arrowBack, size: 20, color: ClaiColors.ink),
            ),
          ),
        ),
      );
}

/// Kicker seksi REDUP (Gelombang 2): saudara tenang [KickerLabel] —
/// huruf-besar berjarak warna tinta redup, untuk kepala seksi di dalam
/// halaman konten/koleksi (papan Stitch: kicker pudar, bukan Volt;
/// Volt tetap milik sinyal, bukan label struktural).
class DimKicker extends StatelessWidget {
  final String text;
  const DimKicker(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.6,
          color: ClaiColors.inkFaint,
        ),
      );
}

/// Aksi berlabel pada dok "Kepala Hidup" (Gelombang 2): ikon 24 di
/// target sentuh 44, label mikro huruf-besar di bawahnya; keadaan aktif
/// = ikon+label Volt + titik 4 dp (satu-satunya Volt di dok selain
/// aksen sampul tombol putar).
class DockAction extends StatelessWidget {
  final ClaiIconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool active;
  final Color? color;

  /// Pengganti ikon bila keadaan membawa widget sendiri (mis. cincin
  /// progres unduhan) — slot ikon tetap 24–28 dp di atas label.
  final Widget? iconWidget;

  const DockAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
    this.color,
    this.iconWidget,
  });

  @override
  Widget build(BuildContext context) {
    final ink = active ? ClaiColors.accent : (color ?? ClaiColors.inkSecondary);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 28,
              child: Center(
                child: iconWidget ?? ClaiIcon(icon, size: 24, color: ink),
              ),
            ),
            const SizedBox(height: 3),
            Text(
              label.toUpperCase(),
              maxLines: 2,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.1,
                height: 1.15,
                color: ink,
              ),
            ),
            const SizedBox(height: 3),
            Container(
              width: 4,
              height: 4,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: active ? ClaiColors.accent : Colors.transparent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Seni panggung lebar-penuh (Gelombang 2): sampul memenuhi lebar layar
/// setinggi [height], dipotong cover; tanpa URL / gagal muat → penahan
/// tonal berikon (tidak pernah kotak abu kosong).
class StageArtwork extends StatelessWidget {
  final String? url;
  final double height;
  const StageArtwork({super.key, required this.url, required this.height});

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      color: ClaiColors.surface2,
      child: Center(
        child: ClaiIcon(ClaiIcons.musicNote, size: 64, color: ClaiColors.surface3),
      ),
    );
    return SizedBox(
      height: height,
      width: double.infinity,
      child: url == null
          ? placeholder
          : Image.network(
              artworkUrlForSize(url, 720) ?? url!,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => placeholder,
              loadingBuilder: (context, child, progress) =>
                  progress == null ? child : placeholder,
            ),
    );
  }
}

/// Warna ubin/pita Mood & Genre dari warna garis khas SUMBER: gradasi
/// dari varian terangnya ke varian pekatnya. Warna 0/hilang → tonal
/// netral. Murni & diuji. (Dipindah dari search_screen di Gelombang 2
/// agar halaman Mood memakai sumber kebenaran yang sama dengan ubin
/// Jelajah yang membukanya.)
(Color, Color) moodTileGradient(int stripeColor) {
  if (stripeColor == 0) {
    return (ClaiColors.surface3, ClaiColors.surface1);
  }
  final hsl = HSLColor.fromColor(Color(stripeColor | 0xFF000000));
  final light = hsl
      .withSaturation((hsl.saturation * 0.9).clamp(0.25, 0.85))
      .withLightness((hsl.lightness + 0.10).clamp(0.32, 0.55))
      .toColor();
  final dark = hsl
      .withSaturation((hsl.saturation * 0.9).clamp(0.25, 0.85))
      .withLightness((hsl.lightness - 0.16).clamp(0.14, 0.40))
      .toColor();
  return (light, dark);
}

/// Blok slider lebar-penuh untuk panel Pengaturan (pola pengaturan.md
/// Gelombang 2): baris judul+subjudul di atas, slider memenuhi lebar
/// panel di bawahnya — menggantikan slider 160 dp yang terjepit di
/// trailing ListTile.
class SettingsSliderBlock extends StatelessWidget {
  final ClaiIconData? icon;
  final String title;
  final String? subtitle;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeEnd;

  const SettingsSliderBlock({
    super.key,
    this.icon,
    required this.title,
    this.subtitle,
    required this.value,
    required this.min,
    required this.max,
    this.divisions,
    required this.onChanged,
    this.onChangeEnd,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            if (icon != null) ...[
              tonalIconBox(icon!, size: 40, iconSize: 20),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          color: ClaiColors.ink, fontSize: 15)),
                  if (subtitle != null)
                    Text(subtitle!,
                        style: const TextStyle(
                            color: ClaiColors.inkSecondary, fontSize: 13)),
                ],
              ),
            ),
          ]),
          Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            activeColor: ClaiColors.accent,
            onChanged: onChanged,
            onChangeEnd: onChangeEnd,
          ),
        ],
      ),
    );
  }
}
