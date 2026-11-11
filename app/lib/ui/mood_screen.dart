import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../app.dart';
import '../core/clai_icons.dart';
import '../core/tokens.dart';

import '../domain/models.dart';
import '../l10n/l10n.dart';
import 'widgets.dart';

/// Halaman kategori Mood & Genre: tujuan NYATA satu ubin kategori
/// sumber — daftar playlist/album (dan trek bila sumber memberikannya)
/// dari telusur titik akhir ubin itu. Judul halaman = judul ubin dari
/// sumber, apa adanya.
///
/// Gelombang 2 (8048): kepala = PITA warna garis khas mood itu sendiri
/// (150 dp, gradasi diagonal dari fungsi yang sama dengan ubin
/// Jelajah), chip kaca kembali, kicker + nama kategori DI pita; badan
/// memakai bahasa Jelajah — kisi 2 kolom untuk playlist, rel untuk
/// album, baris lagu untuk trek. Subjudul kartu tetap lewat saringan
/// merek audit 8047 (moodRowSubtitle / komposisi "Jenis · Katalog").
class MoodScreen extends ConsumerStatefulWidget {
  final MoodGenreItem item;
  const MoodScreen({super.key, required this.item});
  @override
  ConsumerState<MoodScreen> createState() => _MoodScreenState();
}

class _MoodScreenState extends ConsumerState<MoodScreen> {
  ContentPage? _page;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await ref
          .read(ytMusicProvider)
          .getMoodPage(widget.item.browseId, widget.item.params, widget.item.title);
      if (mounted) {
        setState(() {
          _page = page;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = context.l10n.contentUnavailable;
          _loading = false;
        });
      }
    }
  }

  /// Jenis konten dari awalan id sumber (aturan yang sama seperti
  /// pengumpul dua-baris provider): VL/PL/RD = playlist, selainnya album.
  String _kindOf(String id) =>
      (id.startsWith('VL') || id.startsWith('PL') || id.startsWith('RD'))
          ? 'playlist'
          : 'album';

  @override
  Widget build(BuildContext context) {
    final handler = ref.watch(audioHandlerProvider);
    final l = context.l10n;
    final page = _page;
    final (bandTop, bandBottom) = moodTileGradient(widget.item.stripeColor);
    final playlists = page == null
        ? const <Album>[]
        : page.albums.where((a) => _kindOf(a.id) == 'playlist').toList();
    final albums = page == null
        ? const <Album>[]
        : page.albums.where((a) => _kindOf(a.id) == 'album').toList();
    return Scaffold(
      body: FiniteScrollPage(
        padding: EdgeInsets.zero,
        children: [
          // PITA MOOD: warna dari garis khas kategori itu sendiri
          // (warna konten, hanya di pita ini).
          Container(
            height: 150,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [bandTop, bandBottom],
              ),
            ),
            child: Stack(
              children: [
                Positioned(
                  top: MediaQuery.paddingOf(context).top + 12,
                  left: 16,
                  child: const GlassBackChip(),
                ),
                Positioned(
                  left: 20,
                  right: 20,
                  bottom: 16,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        l.searchMoodGenreKicker.toUpperCase(),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.6,
                          color: Colors.white.withValues(alpha: 0.9),
                        ),
                      ),
                      const SizedBox(height: 5),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          widget.item.title,
                          maxLines: 1,
                          style: displayStyle(32)
                              .copyWith(color: ClaiColors.ink),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (_loading)
            const SizedBox(height: 340, child: LoadingSkeleton())
          else if (_error != null)
            SizedBox(
              height: 340,
              child: ErrorState(message: _error!, onRetry: _load),
            )
          else if (page == null)
            SizedBox(
              height: 340,
              child: EmptyState(
                icon: ClaiIcons.album,
                message: l.contentUnavailable,
              ),
            )
          else ...[
            if (playlists.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
                child: DimKicker(l.searchPlaylists),
              ),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 20),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 16,
                  mainAxisExtent: 224,
                ),
                itemCount: playlists.length,
                itemBuilder: (context, i) {
                  final a = playlists[i];
                  return InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () =>
                        openContent(context, ref, 'playlist', a.id, a.title),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        LayoutBuilder(
                          builder: (context, box) => CoverArt(
                              url: a.artworkUrl,
                              size: box.maxWidth,
                              radius: 14,
                              label: a.title),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          a.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: ClaiColors.ink,
                            height: 1.25,
                          ),
                        ),
                        const SizedBox(height: 2),
                        // Keterangan kartu Mood (papan): "Playlist ·
                        // Katalog" — jenis dari awalan id, kata katalog
                        // netral; TIDAK pernah byline sumber mentah.
                        Text(
                          '${l.searchPlaylists} · ${l.catalogWord}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: ClaiColors.inkSecondary,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
            if (albums.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 22, 20, 10),
                child: DimKicker(l.searchAlbums),
              ),
              SizedBox(
                height: 178,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: albums.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 12),
                  itemBuilder: (context, i) {
                    final a = albums[i];
                    return InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () =>
                          openContent(context, ref, 'album', a.id, a.title),
                      child: SizedBox(
                        width: 128,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            CoverArt(
                                url: a.artworkUrl,
                                size: 128,
                                radius: 14,
                                label: a.title),
                            const SizedBox(height: 8),
                            Text(
                              a.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                                color: ClaiColors.ink,
                              ),
                            ),
                            Text(
                              '${l.searchAlbums} · ${l.catalogWord}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                color: ClaiColors.inkSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
            if (page.tracks.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 22, 20, 6),
                child: DimKicker(l.searchSongs),
              ),
              for (var i = 0; i < page.tracks.length; i++)
                SongRow(
                  track: page.tracks[i],
                  onTap: () => handler.playTracks(page.tracks, i,
                      kind: 'search', label: page.title),
                ),
            ],
          ],
          SizedBox(height: bottomChromeClearance(context)),
        ],
      ),
    );
  }
}
