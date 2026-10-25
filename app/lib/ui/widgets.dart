import 'dart:math' as math;

import 'package:audio_service/audio_service.dart';
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
import '../domain/models.dart';
import '../l10n/l10n.dart';
import 'content_screen.dart';

/// Dekorasi kartu baku DS: permukaan + garis tepi 1px samar + radius seragam.
BoxDecoration claiCardDecoration({Color color = ClaiColors.surface2, double radius = ClaiRadius.card}) =>
    BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: ClaiColors.divider, width: 1),
    );

/// Pegangan (handle) sheet baku — SATU bentuk untuk semua lembar bawah (v4.4).
class SheetHandle extends StatelessWidget {
  const SheetHandle({super.key});
  @override
  Widget build(BuildContext context) => Center(
        child: Container(
          width: 36, height: 4,
          decoration: BoxDecoration(color: ClaiColors.surface3, borderRadius: BorderRadius.circular(2)),
        ),
      );
}

/// Tekan ber-spring (DS Bab 5): skala menyusut saat disentuh lalu kembali dengan
/// overshoot halus memakai ClaiSprings.press. Hanya transform — tanpa mengubah
/// perilaku ketuk anak di dalamnya (mendengar pointer, bukan merebut gesture).
class PressableScale extends StatefulWidget {
  final Widget child;
  final double pressedScale;
  const PressableScale({super.key, required this.child, this.pressedScale = 0.92});
  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController.unbounded(vsync: this, value: 1);
  @override
  void dispose() { _c.dispose(); super.dispose(); }
  void _to(double target) {
    // D-05: gerak-reduksi sistem — tanpa spring; nilai ditetapkan langsung.
    if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) {
      _c.value = target;
      return;
    }
    _c.animateWith(SpringSimulation(ClaiSprings.press, _c.value, target, _c.velocity));
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
  const CoverArt({super.key, this.url, required this.size, required this.label, this.radius = ClaiRadius.cover});
  @override
  Widget build(BuildContext context) {
    // D-35 (DS 6.13): placeholder tanpa label memakai glif nada GAMBAR SENDIRI
    // (ClaiIcons.musicNote), bukan karakter teks '♪' — set ikon aplikasi
    // tidak boleh bocor glyph Unicode.
    final placeholder = Container(
      width: size, height: size,
      decoration: BoxDecoration(color: ClaiColors.surface2, borderRadius: BorderRadius.circular(radius)),
      alignment: Alignment.center,
      child: label.isEmpty
          ? ClaiIcon(ClaiIcons.musicNote, size: math.min(size * 0.44, 72), color: ClaiColors.inkFaint)
          : Text(label.characters.first.toUpperCase(),
              style: TextStyle(fontSize: math.min(size * 0.36, 72), fontWeight: FontWeight.w700, color: ClaiColors.inkFaint)),
    );
    if (url == null || url!.isEmpty) return placeholder;
    final dpr = MediaQuery.of(context).devicePixelRatio;
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
      child: Image.network(sizedUrl, key: ValueKey(sizedUrl), width: size, height: size, fit: BoxFit.cover,
          cacheWidth: decodeWidth,
          errorBuilder: (_, __, ___) => placeholder,
          loadingBuilder: (c, child, prog) => prog == null ? child : placeholder),
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
  const CoverArtWide({super.key, this.url, required this.label, this.radius = 16});
  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, c) => CoverArt(url: url, size: c.maxWidth, label: label, radius: radius),
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
    final maxH = MediaQuery.of(context).size.height * 0.85;
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

class _EqualizerBarsState extends State<EqualizerBars> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat();
  @override
  void dispose() { _c.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    if (!widget.animating) {
      return Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
        for (final h in [6.0, 10.0, 4.0])
          Container(width: 3, height: h, margin: const EdgeInsets.only(right: 2), color: ClaiColors.accent),
      ]);
    }
    return AnimatedBuilder(animation: _c, builder: (_, __) {
      final v = _c.value;
      final hs = [6 + 6 * (v < .5 ? v * 2 : (1 - v) * 2), 12 - 6 * v, 4 + 8 * ((v + .33) % 1)];
      return Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
        for (final h in hs)
          Container(width: 3, height: h, margin: const EdgeInsets.only(right: 2), color: ClaiColors.accent),
      ]);
    });
  }
}

/// Baris Lagu baku (DS 6.1) — dipakai semua daftar di semua layar.
class SongRow extends ConsumerWidget {
  final Track track;
  final VoidCallback? onTap;
  final bool showMenu;
  final Widget? trailing;
  final int? number;
  const SongRow({super.key, required this.track, this.onTap, this.showMenu = true, this.trailing, this.number});

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
            return RepaintBoundary(child: InkWell(
              onTap: onTap,
              splashColor: ClaiColors.accent.withValues(alpha: 0.07),
              highlightColor: ClaiColors.surface2.withValues(alpha: 0.55),
              child: Container(
                color: isCurrent ? ClaiColors.surface2 : null,
                padding: const EdgeInsets.symmetric(horizontal: ClaiSpace.screenMargin, vertical: 6),
                child: Row(children: [
                  if (number != null)
                    SizedBox(width: 26, child: Text('$number', style: const TextStyle(color: ClaiColors.inkFaint, fontSize: 13, fontFeatures: [FontFeature.tabularFigures()]))),
                  Stack(children: [
                    CoverArt(url: track.artworkUrl, size: 48, label: track.title),
                    if (isCurrent)
                      Positioned(right: 3, bottom: 3, child: EqualizerBars(animating: playing)),
                  ]),
                  const SizedBox(width: ClaiSpace.md),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    // Ronde Poles Beranda butir 3: judul–artis TAMPIL dibersihkan
                    // (awalan kurung unggahan & metadata "views/ago" dibuang dari
                    // lapisan tampil saja — data asli tak diubah).
                    Text(cleanDisplayTitle(track.title), maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: isCurrent ? ClaiColors.accent : ClaiColors.ink)),
                    Text(cleanDisplayArtist(track.artistNames), maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13, color: ClaiColors.inkSecondary)),
                  ])),
                  // Durasi belum termuat: kolom disembunyikan — tanda "–" lama
                  // terbaca sebagai kerusakan (Poles Beranda butir 3).
                  if (track.duration != null)
                    Text(formatDuration(track.duration!),
                        style: const TextStyle(fontSize: 12, color: ClaiColors.inkSecondary, fontFeatures: [FontFeature.tabularFigures()])),
                  if (trailing != null) trailing!,
                  if (showMenu)
                    // D-01: tombol berikon wajib bernama untuk TalkBack.
                    IconButton(icon: ClaiIcon(ClaiIcons.moreVert, color: ClaiColors.inkSecondary),
                        tooltip: context.l10n.a11yTrackOptions,
                        onPressed: () => showTrackContextSheet(context, ref, track)),
                ]),
              ),
            ));
          },
        );
      },
    );
  }
}

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

/// Rak sampul horizontal (Ronde Poles Beranda butir 4): kartu sampul 112
/// dengan judul–artis bersih di bawahnya; ketuk kartu memutar daftar rak
/// dari trek itu. Beranda lama menampilkan semua rak sebagai baris daftar
/// vertikal — layar pertama tidak memuat satu sampul pun selain kartu
/// Sedang Diputar.
class CoverRail extends StatelessWidget {
  final String title;
  final List<Track> tracks;
  final void Function(List<Track> tracks, int index) onPlay;
  const CoverRail({super.key, required this.title, required this.tracks, required this.onPlay});

  @override
  Widget build(BuildContext context) {
    if (tracks.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 26, 16, 10),
        child: Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: ClaiColors.ink)),
      ),
      SizedBox(
        height: 152,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: ClaiSpace.screenMargin),
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
                label: artistClean.isEmpty ? titleClean : '$titleClean — $artistClean',
                child: PressableScale(
                  child: GestureDetector(
                    onTap: () => onPlay(tracks, i),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      CoverArt(url: t.artworkUrl, size: 112, label: t.title, radius: 12),
                      const SizedBox(height: 6),
                      Text(titleClean, maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: ClaiColors.ink)),
                      Text(artistClean, maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11.5, color: ClaiColors.inkSecondary)),
                    ]),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    ]);
  }
}

/// Lembar Menu Konteks (DS 6.8) — urutan baku, sama di semua layar; varian antrean menambah aksi destruktif terakhir.
Future<void> showTrackContextSheet(BuildContext context, WidgetRef ref, Track track, {bool fromQueue = false, VoidCallback? onRemoveFromQueue}) async {
  final handler = ref.read(audioHandlerProvider);
  final lib = ref.read(libraryProvider);
  final liked = lib.isLiked(track.key);
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: ClaiColors.surface2,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(ClaiRadius.sheet))),
    builder: (sheetCtx) {
      Widget act(ClaiIconData icon, String label, VoidCallback fn, {Color? color}) => ListTile(
            leading: ClaiIcon(icon, color: color ?? ClaiColors.ink, size: 24),
            title: Text(label, style: TextStyle(color: color ?? ClaiColors.ink, fontSize: 15)),
            minTileHeight: 52,
            onTap: () { Navigator.of(sheetCtx).pop(); fn(); },
          );
      return ClaiSheetScaffold(children: [
        const SizedBox(height: 8),
        const SheetHandle(),
        ListTile(
          leading: CoverArt(url: track.artworkUrl, size: 48, label: track.title),
          title: Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, color: ClaiColors.ink)),
          subtitle: Text(track.artistNames, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: ClaiColors.inkSecondary)),
        ),
        const Divider(color: ClaiColors.divider, height: 1),
        act(ClaiIcons.next, context.l10n.ctxPlayNext, () => handler.enqueue(track, next: true)),
        act(ClaiIcons.queue, context.l10n.ctxAddToQueue, () => handler.enqueue(track, next: false)),
        act(ClaiIcons.radio, context.l10n.ctxStartRadio, () => handler.startRadio(track)),
        act(liked ? ClaiIcons.heartFill : ClaiIcons.heart, liked ? context.l10n.ctxRemoveFromCollection : context.l10n.ctxSaveToCollection,
            () => lib.toggleLike(track), color: ClaiColors.liked),
        act(ClaiIcons.playlistAdd, context.l10n.ctxAddToPlaylist, () => showAddToPlaylistSheet(context, ref, track)),
        // Unduh (F2, DS 6.8): berkas lokal perangkat tidak perlu diunduh.
        if (track.providerId != 'local')
          Builder(builder: (_) {
            final svc = ref.read(downloadServiceProvider);
            final downloaded = svc.isDownloaded(track.key);
            return act(downloaded ? ClaiIcons.trash : ClaiIcons.download,
                downloaded ? context.l10n.ctxDeleteDownload : context.l10n.commonDownload,
                () {
                  if (downloaded) {
                    svc.deleteDownload(track.key);
                  } else {
                    // D-03: unduhan memakai kualitas EFEKTIF (hemat data
                    // memaksa Rendah juga untuk berkas offline).
                    svc.download(track, handler.effectiveQuality);
                  }
                });
          }),
        if (track.albumId != null)
          act(ClaiIcons.album, context.l10n.ctxOpenAlbum, () => openContent(context, ref, 'album', track.albumId!, track.albumTitle ?? 'Album')),
        // Butir E (Poles Beranda): "Buka Artis" tampil kapan pun trek punya
        // NAMA artis — bukan hanya bila ID artis terbawa. Trek playlist
        // sering hanya membawa nama; ID diselesaikan lewat pencarian.
        if (canOpenArtist(track))
          act(ClaiIcons.person, context.l10n.ctxOpenArtist, () => openArtistFromTrack(context, ref, track)),
        act(ClaiIcons.share, context.l10n.ctxShare, () => Share.share(context.l10n.ctxShareText(track.title, track.artistNames))),
        if (fromQueue)
          act(ClaiIcons.close, context.l10n.ctxRemoveFromQueue, () => onRemoveFromQueue?.call(), color: ClaiColors.error),
        const SizedBox(height: 8),
      ]);
    },
  );
}

Future<void> showAddToPlaylistSheet(BuildContext context, WidgetRef ref, Track track) async {
  final lib = ref.read(libraryProvider);
  await showModalBottomSheet<void>(
    context: context, backgroundColor: ClaiColors.surface2,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(ClaiRadius.sheet))),
    builder: (ctx) => ClaiSheetScaffold(children: [
      const SizedBox(height: 8),
      const SheetHandle(),
      ListTile(leading: ClaiIcon(ClaiIcons.add, color: ClaiColors.accent), title: Text(context.l10n.ctxNewPlaylist, style: const TextStyle(color: ClaiColors.ink)),
          onTap: () async {
            Navigator.of(ctx).pop();
            final name = await promptText(context, context.l10n.ctxPlaylistName);
            if (name != null && name.trim().isNotEmpty) {
              await lib.createPlaylist(name.trim());
              if (context.mounted) showAddToPlaylistSheet(context, ref, track);
            }
          }),
      for (final pl in lib.playlists)
        ListTile(
          leading: ClaiIcon(ClaiIcons.queue, color: ClaiColors.inkSecondary),
          title: Text(pl.name, style: const TextStyle(color: ClaiColors.ink)),
          subtitle: Text(context.l10n.songCount(pl.count), style: const TextStyle(color: ClaiColors.inkSecondary)),
          onTap: () async {
            Navigator.of(ctx).pop();
            final added = await lib.addToPlaylist(pl.id, track);
            if (!added && context.mounted) {
              final keep = await showDialog<bool>(context: context, builder: (d) => AlertDialog(
                backgroundColor: ClaiColors.surface2,
                title: Text(context.l10n.ctxAlreadyInPlaylist, style: const TextStyle(color: ClaiColors.ink)),
                content: Text(context.l10n.ctxAlreadyInPlaylistBody, style: const TextStyle(color: ClaiColors.inkSecondary)),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(d, false), child: Text(context.l10n.ctxSkip)),
                  TextButton(onPressed: () => Navigator.pop(d, true), child: Text(context.l10n.ctxAddAnyway)),
                ]));
              if (keep == true) await lib.addToPlaylist(pl.id, track, allowDuplicate: true);
            }
          },
        ),
      const SizedBox(height: 8),
    ]),
  );
}

Future<String?> promptText(BuildContext context, String label) async {
  final c = TextEditingController();
  return showDialog<String>(context: context, builder: (d) => AlertDialog(
        backgroundColor: ClaiColors.surface2,
        title: Text(label, style: const TextStyle(color: ClaiColors.ink)),
        content: TextField(controller: c, autofocus: true, style: const TextStyle(color: ClaiColors.ink),
            decoration: const InputDecoration(enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: ClaiColors.surface3)))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: Text(context.l10n.commonCancel)),
          TextButton(onPressed: () => Navigator.pop(d, c.text), child: Text(context.l10n.commonSave)),
        ]));
}

void openContent(BuildContext context, WidgetRef ref, String kind, String id, String title) {
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => ContentScreen(kind: kind, id: id, titleHint: title)));
}

/// Aturan tampil "Buka Artis" (Butir E, murni & diuji): trek cukup punya
/// ID artis ATAU nama artis — tombol tidak lagi hilang diam-diam untuk
/// trek playlist yang hanya membawa nama.
bool canOpenArtist(Track track) =>
    track.artistIds.isNotEmpty || primaryArtistName(track.artistNames).isNotEmpty;

/// Nama artis utama untuk kueri resolusi: segmen byline pertama, dipotong
/// pada penanda kolaborasi ("&", ",", "feat.").
String primaryArtistName(String artistNames) {
  var s = artistNames.split('•').first.trim();
  s = s.split(RegExp(r'\s*(?:&|,)\s*')).first.trim();
  s = s.split(RegExp(r'\s+(?:feat\.?|ft\.?)\s+', caseSensitive: false)).first.trim();
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
Future<void> openArtistFromTrack(BuildContext context, WidgetRef ref, Track track) async {
  if (track.artistIds.isNotEmpty) {
    openContent(context, ref, 'artist', track.artistIds.first, track.artistNames);
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
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.artistNotFound)));
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
      vsync: this, duration: const Duration(milliseconds: 1200))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduced && _pulse.isAnimating) _pulse.stop();
    if (!reduced && !_pulse.isAnimating) _pulse.repeat(reverse: true);
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) {
        final opacity = reduced ? 1.0 : 0.6 + 0.4 * _pulse.value;
        final block = ClaiColors.surface2.withValues(alpha: opacity);
        return ListView.builder(
          itemCount: 6, physics: const NeverScrollableScrollPhysics(),
          itemBuilder: (_, __) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: ClaiSpace.screenMargin, vertical: 6),
            child: Row(children: [
              Container(width: 48, height: 48, decoration: BoxDecoration(color: block, borderRadius: BorderRadius.circular(8))),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(height: 14, color: block),
                const SizedBox(height: 6),
                Container(height: 12, width: 140, color: block),
              ])),
            ]),
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
      await _scroll.animateTo(max,
          duration: Duration(milliseconds: (max * 28).round()),
          curve: Curves.linear);
      if (!mounted) return;
      await Future<void>.delayed(const Duration(seconds: 2));
      if (!mounted || !_scroll.hasClients) return;
      _scroll.jumpTo(0);
      await Future<void>.delayed(const Duration(seconds: 3));
    }
  }

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduced) {
      return Text(widget.text, style: widget.style, maxLines: 2, overflow: TextOverflow.ellipsis);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
    return SingleChildScrollView(
      controller: _scroll,
      scrollDirection: Axis.horizontal,
      physics: const NeverScrollableScrollPhysics(),
      child: Text(widget.text, style: widget.style, maxLines: 1, softWrap: false),
    );
  }
}

class EmptyState extends StatelessWidget {
  final ClaiIconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  const EmptyState({super.key, required this.icon, required this.message, this.actionLabel, this.onAction});
  @override
  Widget build(BuildContext context) => Center(child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ClaiIcon(icon, size: 56, color: ClaiColors.inkFaint),
          const SizedBox(height: 16),
          Text(message, textAlign: TextAlign.center, style: const TextStyle(color: ClaiColors.inkSecondary, fontSize: 15)),
          if (actionLabel != null) ...[
            const SizedBox(height: 16),
            FilledButton(style: FilledButton.styleFrom(backgroundColor: ClaiColors.accent, foregroundColor: ClaiColors.onAccent),
                onPressed: onAction, child: Text(actionLabel!)),
          ],
        ]),
      ));
}

class ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const ErrorState({super.key, required this.message, required this.onRetry});
  @override
  Widget build(BuildContext context) => Center(child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ClaiIcon(ClaiIcons.cloudOff, size: 48, color: ClaiColors.error),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center, style: const TextStyle(color: ClaiColors.inkSecondary)),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onRetry, child: Text(context.l10n.commonRetry)),
        ]),
      ));
}
