import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import '../app.dart';
import '../core/clai_icons.dart';
import '../core/tokens.dart';
import '../domain/models.dart';
import '../l10n/l10n.dart';
import '../services/download_service.dart';
import 'widgets.dart';

/// Halaman Konten (PRD 5.3): Album / Playlist sumber / Artis.
class ContentScreen extends ConsumerStatefulWidget {
  final String kind; // album | playlist | artist
  final String id;
  final String titleHint;
  const ContentScreen({super.key, required this.kind, required this.id, required this.titleHint});
  @override
  ConsumerState<ContentScreen> createState() => _ContentScreenState();
}

class _ContentScreenState extends ConsumerState<ContentScreen> {
  ContentPage? _page;
  String? _error;
  bool _loading = true;
  bool _fromCache = false;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; _fromCache = false; });
    try {
      final p = ref.read(ytMusicProvider);
      final page = switch (widget.kind) {
        'album' => await p.getAlbum(widget.id),
        'playlist' => await p.getPlaylist(widget.id),
        _ => await p.getArtist(widget.id),
      };
      if (mounted) setState(() { _page = page; _loading = false; });
    } catch (e) {
      // D-10: sumber tak terjangkau → tawarkan salinan cache lokal halaman
      // ini (album_tracks/remote_playlists) dengan label jujur, bukan
      // layar gagal polos, bila halaman pernah dibuka sebelumnya.
      final cached = await ref.read(appDbProvider).browseCachePage(widget.kind, widget.id);
      if (cached != null && cached.tracks.isNotEmpty) {
        if (mounted) setState(() { _page = cached; _fromCache = true; _loading = false; });
        return;
      }
      if (mounted) setState(() { _error = 'Tidak dapat memuat halaman ini dari sumber.'; _loading = false; });
    }
  }

  /// D-13: simpan halaman ke Koleksi. Album/artis → item tersimpan (tab
  /// Koleksi); playlist sumber → disalin menjadi playlist pengguna.
  Future<void> _saveToCollection(ContentPage page) async {
    final lib = ref.read(libraryProvider);
    if (widget.kind == 'playlist') {
      final id = await lib.createPlaylist(page.title.isEmpty ? widget.titleHint : page.title);
      for (final t in page.tracks) {
        await lib.addToPlaylist(id, t, allowDuplicate: true);
      }
      await lib.load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.l10n.contentPlaylistCopied)));
      }
      return;
    }
    await lib.toggleSavedItem(widget.kind, 'ytmusic', widget.id,
        title: page.title.isEmpty ? widget.titleHint : page.title,
        subtitle: page.subtitle, artworkUrl: page.artworkUrl);
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
        SnackBar(content: Text(context.l10n.contentDownloadQueued(n))));
  }

  @override
  Widget build(BuildContext context) {
    final handler = ref.watch(audioHandlerProvider);
    final page = _page;
    return Scaffold(
      appBar: AppBar(title: Text(widget.titleHint, maxLines: 1, overflow: TextOverflow.ellipsis)),
      body: _loading
          ? const LoadingSkeleton()
          : _error != null
              ? ErrorState(message: _error!, onRetry: _load)
              : page == null
                  ? EmptyState(icon: ClaiIcons.album, message: context.l10n.contentUnavailable)
                  : ListView(children: [
                      if (_fromCache)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(color: ClaiColors.surface2, borderRadius: BorderRadius.circular(10)),
                            child: Row(children: [
                              ClaiIcon(ClaiIcons.cloudOff, size: 18, color: ClaiColors.warning),
                              const SizedBox(width: 8),
                              Expanded(child: Text(context.l10n.contentFromCache,
                                  style: const TextStyle(fontSize: 12, color: ClaiColors.inkSecondary))),
                            ]),
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          CoverArt(url: page.artworkUrl, size: 120, label: page.title, radius: 12),
                          const SizedBox(width: 14),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(page.title.isEmpty ? widget.titleHint : page.title, style: displayStyle(19)),
                            if (page.subtitle != null)
                              Padding(padding: const EdgeInsets.only(top: 4),
                                  child: Text(page.subtitle!, style: const TextStyle(color: ClaiColors.inkSecondary, fontSize: 13))),
                            if (page.tracks.isNotEmpty)
                              Padding(padding: const EdgeInsets.only(top: 4), child: Text(
                                  context.l10n.contentCountLine(page.tracks.length, formatDuration(page.tracks.fold<Duration>(Duration.zero, (a, t) => a + (t.duration ?? Duration.zero)))),
                                  style: const TextStyle(color: ClaiColors.inkFaint, fontSize: 12.5))),
                            const SizedBox(height: 12),
                            Row(children: [
                              PressableScale(
                                child: GestureDetector(
                                  onTap: () { if (page.tracks.isNotEmpty) handler.playTracks(page.tracks, 0, kind: widget.kind, id: widget.id, label: page.title); },
                                  child: Container(width: 48, height: 48, decoration: const BoxDecoration(color: ClaiColors.accent, shape: BoxShape.circle),
                                      child: ClaiIcon(ClaiIcons.play, color: ClaiColors.onAccent, size: 26)),
                                ),
                              ),
                              const SizedBox(width: 10),
                              OutlinedButton.icon(
                                onPressed: () {
                                  if (page.tracks.isEmpty) return;
                                  handler.setShuffleMode(AudioServiceShuffleMode.all);
                                  handler.playTracks(page.tracks, 0, kind: widget.kind, id: widget.id, label: context.l10n.contentShuffleContext(page.title));
                                },
                                icon: ClaiIcon(ClaiIcons.shuffle, size: 18, color: ClaiColors.ink),
                                label: Text(context.l10n.contentShuffle, style: const TextStyle(color: ClaiColors.ink)),
                              ),
                            ]),
                          ])),
                        ]),
                      ),
                      // Butir F (Poles Beranda): baris aksi SERAGAM lebar
                      // penuh di bawah kepala — Simpan / Unduh / Bagikan
                      // sebagai tiga segmen ikon+label selebar sama, bukan
                      // pil bertumpuk mengikuti panjang teks di kolom
                      // kepala yang sempit. Play + Shuffle tetap dominan
                      // di kepala. Semua keadaan D-13 utuh: tersimpan,
                      // progres unduhan (x/y), dan "semua terunduh".
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                        child: Row(children: [
                          Expanded(child: Builder(builder: (context) {
                            final lib = ref.watch(libraryProvider);
                            final saved = widget.kind != 'playlist' &&
                                lib.isSavedItem(widget.kind, 'ytmusic', widget.id);
                            return _ActionSegment(
                              leading: ClaiIcon(saved ? ClaiIcons.heartFill : ClaiIcons.playlistAdd,
                                  size: 18, color: saved ? ClaiColors.liked : ClaiColors.ink),
                              label: saved ? context.l10n.contentSaved : context.l10n.contentSave,
                              onTap: () => _saveToCollection(page),
                            );
                          })),
                          const SizedBox(width: 8),
                          Expanded(child: Builder(builder: (context) {
                            final svc = ref.watch(downloadServiceProvider);
                            final downloadable =
                                page.tracks.where((t) => t.providerId != 'local').toList();
                            final doneCount =
                                downloadable.where((t) => svc.isDownloaded(t.key)).length;
                            final activeCount = downloadable.where((t) {
                              final s = svc.itemFor(t.key)?.status;
                              return s == DownloadStatus.queued ||
                                  s == DownloadStatus.downloading ||
                                  s == DownloadStatus.paused;
                            }).length;
                            if (downloadable.isNotEmpty &&
                                doneCount == downloadable.length) {
                              return _ActionSegment(
                                leading: ClaiIcon(ClaiIcons.check, size: 18, color: ClaiColors.accent),
                                label: context.l10n.contentDownloaded,
                                onTap: null,
                              );
                            }
                            if (activeCount > 0) {
                              return _ActionSegment(
                                leading: SizedBox(
                                  width: 18, height: 18,
                                  child: CircularProgressIndicator(
                                    value: downloadable.isEmpty
                                        ? null
                                        : doneCount / downloadable.length,
                                    strokeWidth: 2, color: ClaiColors.accent),
                                ),
                                label: context.l10n
                                    .contentDownloadingCount(doneCount, downloadable.length),
                                onTap: () => _downloadAll(page),
                              );
                            }
                            return _ActionSegment(
                              leading: ClaiIcon(ClaiIcons.download, size: 18, color: ClaiColors.ink),
                              label: context.l10n.contentDownloadAll,
                              onTap: page.tracks.isEmpty ? null : () => _downloadAll(page),
                            );
                          })),
                          const SizedBox(width: 8),
                          Expanded(child: _ActionSegment(
                            leading: ClaiIcon(ClaiIcons.share, size: 18, color: ClaiColors.ink),
                            label: context.l10n.contentShare,
                            onTap: () => Share.share(context.l10n.ctxShareText(
                                page.title.isEmpty ? widget.titleHint : page.title,
                                page.subtitle ?? '')),
                          )),
                        ]),
                      ),
                      if (widget.kind == 'artist' && page.tracks.isNotEmpty)
                        Padding(padding: const EdgeInsets.fromLTRB(16, 14, 16, 2),
                            child: Text(context.l10n.contentPopular, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: ClaiColors.ink))),
                      for (var i = 0; i < page.tracks.length; i++)
                        SongRow(track: page.tracks[i], number: widget.kind == 'album' ? i + 1 : null,
                            onTap: () => handler.playTracks(page.tracks, i, kind: widget.kind, id: widget.id, label: page.title)),
                      if (page.albums.isNotEmpty) ...[
                        Padding(padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
                            child: Text(context.l10n.contentDiscography, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: ClaiColors.ink))),
                        for (final a in page.albums)
                          ListTile(
                            leading: CoverArt(url: a.artworkUrl, size: 56, label: a.title),
                            title: Text(a.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: ClaiColors.ink, fontWeight: FontWeight.w500)),
                            subtitle: Text(a.artistNames, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: ClaiColors.inkSecondary)),
                            onTap: () => openContent(context, ref, 'album', a.id, a.title),
                          ),
                      ],
                      if (page.relatedArtists.isNotEmpty) ...[
                        Padding(padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
                            child: Text(context.l10n.contentSimilar, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: ClaiColors.ink))),
                        for (final a in page.relatedArtists)
                          ListTile(
                            leading: CoverArt(url: a.artworkUrl, size: 48, label: a.name),
                            title: Text(a.name, style: const TextStyle(color: ClaiColors.ink, fontWeight: FontWeight.w500)),
                            onTap: () => openContent(context, ref, 'artist', a.id, a.name),
                          ),
                      ],
                      const SizedBox(height: 28),
                    ]),
    );
  }
}

/// Satu segmen baris aksi halaman konten (Butir F): ikon + label di
/// permukaan surface-2 radius 10, tinggi tetap 46 — tiga segmen berbagi
/// lebar sama rata lewat Expanded di pemanggil, jadi lebar TIDAK pernah
/// mengikuti panjang teks (label Inggris yang panjang memotong elipsis,
/// bukan mendorong segmen lain). Keadaan nonaktif (onTap null) tampil
/// dengan label samar, tanpa respons sentuh.
class _ActionSegment extends StatelessWidget {
  final Widget leading;
  final String label;
  final VoidCallback? onTap;
  const _ActionSegment({required this.leading, required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: Material(
        color: ClaiColors.surface2,
        borderRadius: BorderRadius.circular(10),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: 46,
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              leading,
              const SizedBox(width: 6),
              Flexible(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: enabled ? ClaiColors.ink : ClaiColors.inkFaint)),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
