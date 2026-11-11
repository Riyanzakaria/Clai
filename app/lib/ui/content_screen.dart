import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import '../app.dart';
import '../core/clai_icons.dart';
import '../core/tokens.dart';
import '../domain/models.dart';
import '../l10n/l10n.dart';
import '../player/queue_engine.dart' as qe;
import '../services/ambient_theme.dart';
import '../services/download_service.dart';
import 'cover_accent_glow.dart';
import 'widgets.dart';

/// Halaman Konten (PRD 5.3): Album / Playlist sumber / Artis.
///
/// Gelombang 2 (8048): komposisi "Kepala Hidup" — panggung sampul
/// lebar-penuh 300 dp dengan teks di atas gradasi kaki panggung saja,
/// chip kaca kembali, lalu dok aksi berlabel 16 dp di bawah panggung
/// (Putar 56 dp bernada sampul diperdalam §11.9; Acak/Simpan/Unduh/
/// Bagikan sebagai aksi berlabel). Perilaku D-10 (cache) & D-13
/// (simpan/unduh) tidak berubah — yang berubah hanya komposisinya.
class ContentScreen extends ConsumerStatefulWidget {
  final String kind; // album | playlist | artist
  final String id;
  final String titleHint;
  const ContentScreen({
    super.key,
    required this.kind,
    required this.id,
    required this.titleHint,
  });
  @override
  ConsumerState<ContentScreen> createState() => _ContentScreenState();
}

class _ContentScreenState extends ConsumerState<ContentScreen> {
  ContentPage? _page;
  String? _error;
  bool _loading = true;
  bool _fromCache = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _fromCache = false;
    });
    try {
      final p = ref.read(ytMusicProvider);
      final page = switch (widget.kind) {
        'album' => await p.getAlbum(widget.id),
        'playlist' => await p.getPlaylist(widget.id),
        _ => await p.getArtist(widget.id),
      };
      if (mounted) {
        setState(() {
          _page = page;
          _loading = false;
        });
      }
    } catch (e) {
      // D-10: sumber tak terjangkau → tawarkan salinan cache lokal halaman
      // ini (album_tracks/remote_playlists) dengan label jujur, bukan
      // layar gagal polos, bila halaman pernah dibuka sebelumnya.
      final cached = await ref
          .read(appDbProvider)
          .browseCachePage(widget.kind, widget.id);
      if (cached != null && cached.tracks.isNotEmpty) {
        if (mounted) {
          setState(() {
            _page = cached;
            _fromCache = true;
            _loading = false;
          });
        }
        return;
      }
      if (mounted) {
        setState(() {
          _error = 'Tidak dapat memuat halaman ini dari sumber.';
          _loading = false;
        });
      }
    }
  }

  /// D-13: simpan halaman ke Koleksi. Album/artis → item tersimpan (tab
  /// Koleksi); playlist sumber → disalin menjadi playlist pengguna.
  Future<void> _saveToCollection(ContentPage page) async {
    final lib = ref.read(libraryProvider);
    if (widget.kind == 'playlist') {
      final id = await lib.createPlaylist(
        page.title.isEmpty ? widget.titleHint : page.title,
      );
      for (final t in page.tracks) {
        await lib.addToPlaylist(id, t, allowDuplicate: true);
      }
      await lib.load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          claiSnackAboveChrome(context, context.l10n.contentPlaylistCopied),
        );
      }
      return;
    }
    await lib.toggleSavedItem(
      widget.kind,
      'ytmusic',
      widget.id,
      title: page.title.isEmpty ? widget.titleHint : page.title,
      subtitle: brandSafeSubtitle(page.subtitle),
      artworkUrl: page.artworkUrl,
    );
  }

  /// D-13: antrekan SEMUA trek halaman untuk diunduh (FIFO maks 2 paralel
  /// di layanan unduhan yang mengurus sisanya).
  void _downloadAll(ContentPage page) {
    final svc = ref.read(downloadServiceProvider);
    final handler = ref.read(audioHandlerProvider);
    var n = 0;
    for (final t in page.tracks) {
      if (t.providerId == 'local' || svc.isDownloaded(t.key)) continue;
      svc.download(t, handler.effectiveQuality);
      n++;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      claiSnackAboveChrome(context, context.l10n.contentDownloadQueued(n)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final page = _page;
    return Scaffold(
      body: _loading
          ? _withBackChip(context, const LoadingSkeleton())
          : _error != null
              ? _withBackChip(
                  context, ErrorState(message: _error!, onRetry: _load))
              : page == null
                  ? _withBackChip(
                      context,
                      EmptyState(
                        icon: ClaiIcons.album,
                        message: context.l10n.contentUnavailable,
                      ),
                    )
                  : _loaded(context, page),
    );
  }

  /// Keadaan non-isi tetap punya affordance kembali (dulu AppBar).
  Widget _withBackChip(BuildContext context, Widget child) => Stack(
        children: [
          Positioned.fill(child: child),
          Positioned(
            top: MediaQuery.paddingOf(context).top + 12,
            left: 16,
            child: const GlassBackChip(),
          ),
        ],
      );

  Widget _loaded(BuildContext context, ContentPage page) {
    final l = context.l10n;
    final handler = ref.watch(audioHandlerProvider);
    final title = page.title.isEmpty ? widget.titleHint : page.title;
    final kindLabel = switch (widget.kind) {
      'album' => l.searchAlbums,
      'playlist' => l.searchPlaylists,
      _ => l.searchArtists,
    };
    final metaParts = <String>[
      if (brandSafeSubtitle(page.subtitle) != null)
        brandSafeSubtitle(page.subtitle)!,
      if (page.tracks.isNotEmpty)
        l.contentCountLine(
          page.tracks.length,
          formatDuration(page.tracks.fold<Duration>(
            Duration.zero,
            (a, t) => a + (t.duration ?? Duration.zero),
          )),
        ),
    ];
    return FiniteScrollPage(
      padding: EdgeInsets.zero,
      children: [
        // PANGGUNG (Kepala Hidup): sampul lebar-penuh 300 dp; teks hidup
        // di atas gradasi kaki panggung SAJA (hitam 0 → 55% di 150 dp
        // terbawah) — tidak ada lelehan ke badan halaman.
        SizedBox(
          height: 300,
          child: Stack(
            fit: StackFit.expand,
            children: [
              StageArtwork(url: page.artworkUrl, height: 300),
              const Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: 150,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0x00000000), Color(0x8C000000)],
                    ),
                  ),
                ),
              ),
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
                      kindLabel.toUpperCase(),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.6,
                        color: Colors.white.withValues(alpha: 0.85),
                      ),
                    ),
                    const SizedBox(height: 6),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        title,
                        maxLines: 1,
                        style: displayStyle(30)
                            .copyWith(color: ClaiColors.ink),
                      ),
                    ),
                    if (metaParts.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        metaParts.join(' · '),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.white.withValues(alpha: 0.75),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        // DOK AKSI: Putar 56 bernada sampul + empat aksi berlabel.
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _stagePlayButton(context, page),
              const SizedBox(width: 6),
              Expanded(
                child: StreamBuilder<dynamic>(
                  stream: handler.queueStream,
                  builder: (context, _) {
                    final shuffleOn =
                        handler.engine.shuffle != qe.ShuffleMode.off;
                    return DockAction(
                      icon: ClaiIcons.shuffle,
                      label: l.contentShuffle,
                      active: shuffleOn,
                      onTap: page.tracks.isEmpty
                          ? null
                          : () {
                              handler.setShuffleMode(
                                AudioServiceShuffleMode.all,
                              );
                              handler.playTracks(
                                page.tracks,
                                0,
                                kind: widget.kind,
                                id: widget.id,
                                label: l.contentShuffleContext(page.title),
                              );
                            },
                    );
                  },
                ),
              ),
              Expanded(
                child: Builder(
                  builder: (context) {
                    final lib = ref.watch(libraryProvider);
                    final saved = widget.kind != 'playlist' &&
                        lib.isSavedItem(widget.kind, 'ytmusic', widget.id);
                    return DockAction(
                      icon: widget.kind == 'playlist'
                          ? ClaiIcons.playlistAdd
                          : (saved ? ClaiIcons.heartFill : ClaiIcons.heart),
                      label: saved ? l.contentSaved : l.contentSave,
                      color: saved ? ClaiColors.liked : null,
                      onTap: () => _saveToCollection(page),
                    );
                  },
                ),
              ),
              Expanded(
                child: Builder(
                  builder: (context) {
                    final svc = ref.watch(downloadServiceProvider);
                    final downloadable = page.tracks
                        .where((t) => t.providerId != 'local')
                        .toList();
                    final doneCount = downloadable
                        .where((t) => svc.isDownloaded(t.key))
                        .length;
                    final activeCount = downloadable.where((t) {
                      final s = svc.itemFor(t.key)?.status;
                      return s == DownloadStatus.queued ||
                          s == DownloadStatus.downloading ||
                          s == DownloadStatus.paused;
                    }).length;
                    if (downloadable.isNotEmpty &&
                        doneCount == downloadable.length) {
                      return DockAction(
                        icon: ClaiIcons.check,
                        label: l.contentDownloaded,
                        color: ClaiColors.accent,
                        onTap: null,
                      );
                    }
                    if (activeCount > 0) {
                      return DockAction(
                        icon: ClaiIcons.download,
                        label: l.contentDownloadingCount(
                            doneCount, downloadable.length),
                        iconWidget: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            value: downloadable.isEmpty
                                ? null
                                : doneCount / downloadable.length,
                            strokeWidth: 2,
                            color: ClaiColors.accent,
                          ),
                        ),
                        onTap: () => _downloadAll(page),
                      );
                    }
                    return DockAction(
                      icon: ClaiIcons.download,
                      label: l.contentDownloadAll,
                      onTap: page.tracks.isEmpty
                          ? null
                          : () => _downloadAll(page),
                    );
                  },
                ),
              ),
              Expanded(
                child: DockAction(
                  icon: ClaiIcons.share,
                  label: l.contentShare,
                  onTap: () => Share.share(
                    claiPageShareText(
                      title,
                      brandSafeSubtitle(page.subtitle) ?? '',
                      l,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (_fromCache)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: ClaiColors.surface2,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  ClaiIcon(ClaiIcons.cloudOff,
                      size: 18, color: ClaiColors.warning),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l.contentFromCache,
                      style: const TextStyle(
                        fontSize: 12,
                        color: ClaiColors.inkSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (widget.kind == 'artist' && page.tracks.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 6),
            child: DimKicker(l.contentPopular),
          ),
        for (var i = 0; i < page.tracks.length; i++)
          SongRow(
            track: page.tracks[i],
            number: widget.kind == 'album' ? i + 1 : null,
            onTap: () => handler.playTracks(
              page.tracks,
              i,
              kind: widget.kind,
              id: widget.id,
              label: page.title,
            ),
          ),
        if (page.albums.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 10),
            child: DimKicker(l.contentDiscography),
          ),
          SizedBox(
            height: 178,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: page.albums.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, i) {
                final a = page.albums[i];
                return InkWell(
                  borderRadius: BorderRadius.circular(12),
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
                            radius: 12,
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
                        if (brandSafeSubtitle(a.artistNames) != null)
                          Text(
                            brandSafeSubtitle(a.artistNames)!,
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
        if (page.relatedArtists.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 10),
            child: DimKicker(l.contentSimilar),
          ),
          SizedBox(
            height: 128,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: page.relatedArtists.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, i) {
                final a = page.relatedArtists[i];
                return InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () =>
                      openContent(context, ref, 'artist', a.id, a.name),
                  child: SizedBox(
                    width: 96,
                    child: Column(
                      children: [
                        CoverArt(
                            url: a.artworkUrl,
                            size: 96,
                            radius: 48,
                            label: a.name),
                        const SizedBox(height: 8),
                        Text(
                          a.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 13,
                            color: ClaiColors.ink,
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
        SizedBox(height: bottomChromeClearance(context)),
      ],
    );
  }

  /// Tombol Putar panggung: lingkaran 56 diisi nada sampul diperdalam
  /// (§11.9 lewat [CoverAccentBuilder] + [deepToneFromColor]); sampul
  /// tanpa tinta / ambien mati → Volt, konsisten dengan kartu Lanjut
  /// Beranda. Ikon putih di atas nada (penjaga kontras di fungsi nada).
  Widget _stagePlayButton(BuildContext context, ContentPage page) {
    final handler = ref.read(audioHandlerProvider);
    return CoverAccentBuilder(
      artworkUrl: page.artworkUrl,
      builder: (context, tonal) {
        final tone =
            tonal == null ? ClaiColors.accent : deepToneFromColor(tonal);
        return PressableScale(
          child: GestureDetector(
            onTap: page.tracks.isEmpty
                ? null
                : () => handler.playTracks(
                      page.tracks,
                      0,
                      kind: widget.kind,
                      id: widget.id,
                      label: page.title,
                    ),
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(color: tone, shape: BoxShape.circle),
              child: ClaiIcon(
                ClaiIcons.play,
                color: onProgressTone(tone),
                size: 26,
              ),
            ),
          ),
        );
      },
    );
  }
}
