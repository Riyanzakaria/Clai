import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/l10n.dart';
import '../app.dart';
import '../core/clai_icons.dart';
import '../core/tokens.dart';
import '../domain/models.dart';
import '../providers/ytmusic/innertube.dart' show exploreTitleId;
import 'glass.dart';
import 'widgets.dart';

/// Beranda Jelajah (F2, PRD 5.1): rak penemuan dari umpan YouTube Music —
/// rilis baru, playlist publik, radio/populer — di BAWAH rak dasar F1.
///
/// Muat malas (saat Beranda pertama dibangun), dan kegagalan dinyatakan PER
/// SUMBER: umpan Beranda dan umpan Tangga Lagu dimuat independen; yang gagal
/// menampilkan baris gagalnya sendiri + tombol coba lagi, dan tidak pernah
/// meruntuhkan Beranda. Ketuk kartu membuka halaman konten; ketuk trek
/// memutar dengan semantik konteks & jangkar v4.4.3 (playTracks biasa).
class JelajahSection extends ConsumerStatefulWidget {
  const JelajahSection({super.key});
  @override
  ConsumerState<JelajahSection> createState() => _JelajahSectionState();
}

class _FeedState {
  List<ExploreShelf>? shelves;
  bool loading = true;
  bool failed = false;
}

class _JelajahSectionState extends ConsumerState<JelajahSection> {
  final _home = _FeedState();
  final _charts = _FeedState();

  @override
  void initState() {
    super.initState();
    _load(_home, () => ref.read(ytMusicProvider).getHomeFeed());
    _load(_charts, () => ref.read(ytMusicProvider).getChartsFeed());
  }

  Future<void> _load(
    _FeedState st,
    Future<List<ExploreShelf>> Function() fetch,
  ) async {
    setState(() {
      st.loading = true;
      st.failed = false;
    });
    try {
      final shelves = await fetch();
      if (mounted) {
        setState(() {
          st.shelves = shelves;
          st.loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          st.failed = true;
          st.loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final anyContent =
        (_home.shelves?.isNotEmpty ?? false) ||
        (_charts.shelves?.isNotEmpty ?? false);
    final anyLoading = _home.loading || _charts.loading;
    if (!anyContent && !anyLoading && _home.failed && _charts.failed) {
      // Kedua sumber gagal: satu baris jujur yang ringkas, bukan bagian kosong besar.
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 26, 16, 6),
        child: Row(
          children: [
            ClaiIcon(ClaiIcons.warning, size: 18, color: ClaiColors.warning),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                context.l10n.jelajahLoadFail,
                style: TextStyle(color: ClaiColors.inkSecondary, fontSize: 13),
              ),
            ),
            TextButton(
              onPressed: () {
                _load(_home, () => ref.read(ytMusicProvider).getHomeFeed());
                _load(_charts, () => ref.read(ytMusicProvider).getChartsFeed());
              },
              child: Text(
                context.l10n.commonRetry,
                style: const TextStyle(color: ClaiColors.signal),
              ),
            ),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Ronde 8083 butir 8: kepala editorial — judul "Jelajah" font tampilan
        // besar langsung (bukan kicker SectionHeader). Subjudul kurasi
        // TIDAK ditambahkan: tidak ada kunci l10n Jelajah yang memuat
        // subjudul kurasi (yang ada hanya jelajahTitle & nama sumber),
        // dan kunci baru dilarang di ronde ini — dicatat di laporan.
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
          child: Text(context.l10n.jelajahTitle, style: displayStyle(24)),
        ),
        if (anyLoading && !anyContent)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Row(
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: ClaiColors.signal,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  context.l10n.jelajahLoading,
                  style: const TextStyle(
                    color: ClaiColors.inkSecondary,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ..._sourceShelves(
          _home,
          context.l10n.jelajahYtmHome,
          () => ref.read(ytMusicProvider).getHomeFeed(),
        ),
        ..._sourceShelves(
          _charts,
          context.l10n.jelajahCharts,
          () => ref.read(ytMusicProvider).getChartsFeed(),
        ),
      ],
    );
  }

  List<Widget> _sourceShelves(
    _FeedState st,
    String sourceName,
    Future<List<ExploreShelf>> Function() fetch,
  ) {
    if (st.failed) {
      return [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
          child: Row(
            children: [
              ClaiIcon(ClaiIcons.warning, size: 16, color: ClaiColors.warning),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  context.l10n.jelajahShelfFail(sourceName),
                  style: const TextStyle(
                    color: ClaiColors.inkSecondary,
                    fontSize: 13,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => _load(st, fetch),
                child: Text(
                  context.l10n.commonRetry,
                  style: const TextStyle(color: ClaiColors.signal),
                ),
              ),
            ],
          ),
        ),
      ];
    }
    final shelves = st.shelves;
    if (shelves == null) return const [];
    return [for (final s in shelves) _ExploreShelfView(shelf: s)];
  }
}

class _ExploreShelfView extends ConsumerWidget {
  final ExploreShelf shelf;
  const _ExploreShelfView({required this.shelf});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final handler = ref.watch(audioHandlerProvider);
    final cards =
        <({String kind, String id, String title, String sub, String? art})>[
          for (final a in shelf.albums)
            (
              kind: 'album',
              id: a.id,
              title: a.title,
              sub: a.artistNames,
              art: a.artworkUrl,
            ),
          for (final p in shelf.playlists)
            (
              kind: 'playlist',
              id: p.id,
              title: p.title,
              sub: p.artistNames,
              art: p.artworkUrl,
            ),
          for (final a in shelf.artists)
            (
              kind: 'artist',
              id: a.id,
              title: a.name,
              sub: context.l10n.jelajahArtists,
              art: a.artworkUrl,
            ),
        ];
    // Ronde 8083 butir 8: rak video/tangga lagu ("Video charts")
    // duduk di atas permukaan gelap surface-1 sebagai latar kartu;
    // sampul/artwork chart tetap berwarna apa adanya.
    final shelfKey = shelf.title.toLowerCase();
    final darkCard = shelfKey.contains('video') || shelfKey.contains('chart');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Ronde 8085: judul rak lewat SectionHeader (Inter Tight 17,
        // padding bawaan standar) — bukan lagi Text bertulis tangan Inter.
        SectionHeader(exploreTitleId(shelf.title)),
        if (cards.isNotEmpty)
          SizedBox(
            height: darkCard ? 204 : 188,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: cards.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, i) {
                final c = cards[i];
                final cardBody = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CoverArt(url: c.art, size: 132, label: c.title, radius: 10),
                    const SizedBox(height: 8),
                    Text(
                      c.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: ClaiColors.ink,
                        height: 1.25,
                      ),
                    ),
                    Text(
                      c.sub,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: ClaiColors.inkSecondary,
                      ),
                    ),
                  ],
                );
                return InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => openContent(context, ref, c.kind, c.id, c.title),
                  child: darkCard
                      ? Container(
                          width: 148,
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: ClaiColors.surface1,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: cardBody,
                        )
                      : SizedBox(width: 132, child: cardBody),
                );
              },
            ),
          ),
        if (cards.isEmpty)
          for (var i = 0; i < shelf.tracks.length && i < 5; i++)
            SongRow(
              track: shelf.tracks[i],
              onTap: () => handler.playTracks(
                shelf.tracks,
                i,
                kind: 'search',
                label: context.l10n.jelajahShelfTitle(
                  exploreTitleId(shelf.title),
                ),
              ),
            ),
        if (cards.isNotEmpty && shelf.tracks.isNotEmpty)
          for (var i = 0; i < shelf.tracks.length && i < 3; i++)
            SongRow(
              track: shelf.tracks[i],
              onTap: () => handler.playTracks(
                shelf.tracks,
                i,
                kind: 'search',
                label: context.l10n.jelajahShelfTitle(
                  exploreTitleId(shelf.title),
                ),
              ),
            ),
      ],
    );
  }
}
