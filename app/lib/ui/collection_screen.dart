import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../app.dart';
import '../core/artwork.dart';
import '../core/clai_icons.dart';
import '../core/tokens.dart';
import '../domain/models.dart';
import '../services/library_controller.dart';
import '../l10n/l10n.dart';
import 'downloads_screen.dart';
import 'local_screen.dart';
import 'playlist_screen.dart';
import 'settings_screen.dart';
import 'widgets.dart';

/// U-2 (Audit UX, diterapkan build 2018): urutan untuk tab Album & Artis
/// Koleksi — menghormati pilihan urut global yang sama seperti Playlist &
/// Tersimpan: 'az' → judul A–Z; selain itu urutan simpan bawaan dipertahankan.
/// Murni & diuji.
List<SavedItemInfo> sortSavedItems(List<SavedItemInfo> items, String sort) {
  final out = List<SavedItemInfo>.of(items);
  if (sort == 'az') out.sort((a, b) => a.title.compareTo(b.title));
  return out;
}

/// Koleksi (PRD 5.6): Playlist pengguna · Lagu Tersimpan · File Lokal — dengan saring lokal & urut.
class CollectionScreen extends ConsumerStatefulWidget {
  /// Audit UX 2017: jalan keluar dari keadaan kosong tab Koleksi menuju
  /// tab Cari (disambungkan pemilik cangkang di app.dart; null = tanpa aksi).
  final VoidCallback? onGoSearch;
  const CollectionScreen({super.key, this.onGoSearch});
  @override
  ConsumerState<CollectionScreen> createState() => _CollectionScreenState();
}

class _CollectionScreenState extends ConsumerState<CollectionScreen> {
  String _tab = 'playlists';
  String _filter = '';
  String _sort = 'terbaru';

  @override
  Widget build(BuildContext context) {
    final lib = ref.watch(libraryProvider);
    final handler = ref.watch(audioHandlerProvider);
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 4),
        child: Row(children: [
          Expanded(child: Text(context.l10n.collectionTitle, style: displayStyle(21))),
          PopupMenuButton<String>(
            icon: ClaiIcon(ClaiIcons.sort, color: ClaiColors.inkSecondary),
            tooltip: context.l10n.a11ySort,
            color: ClaiColors.surface2,
            onSelected: (v) => setState(() => _sort = v),
            itemBuilder: (_) => [
              PopupMenuItem(value: 'terbaru', child: Text(context.l10n.collectionSortRecent)),
              const PopupMenuItem(value: 'az', child: Text('A–Z')),
            ],
          ),
          IconButton(icon: ClaiIcon(ClaiIcons.settings, color: ClaiColors.inkSecondary),
              tooltip: context.l10n.a11ySettings,
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen()))),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: TextField(
          onChanged: (v) => setState(() => _filter = v.trim().toLowerCase()),
          style: const TextStyle(color: ClaiColors.ink),
          decoration: InputDecoration(hintText: context.l10n.collectionFilterHint, prefixIcon: ClaiIcon(ClaiIcons.search),
              filled: true, fillColor: ClaiColors.surface1,
              border: const OutlineInputBorder(borderSide: BorderSide.none, borderRadius: BorderRadius.all(Radius.circular(10)))),
        ),
      ),
      const SizedBox(height: 10),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(children: [
          for (final t in ['playlists', 'liked', 'albums', 'artists', 'local', 'downloads'])
            Padding(padding: const EdgeInsets.only(right: 8), child: ChoiceChip(
              label: Text(switch (t) {
                'liked' => context.l10n.homeSavedSongs,
                'albums' => context.l10n.collectionAlbums,
                'artists' => context.l10n.collectionArtists,
                'local' => context.l10n.collectionLocalFiles,
                'downloads' => context.l10n.collectionDownloads,
                _ => context.l10n.collectionPlaylists,
              }), selected: _tab == t,
              onSelected: (_) => setState(() => _tab = t),
              selectedColor: ClaiColors.accent,
              labelStyle: TextStyle(color: _tab == t ? ClaiColors.onAccent : ClaiColors.ink, fontSize: 13, fontWeight: FontWeight.w500),
              backgroundColor: ClaiColors.surface2, side: BorderSide.none,
            )),
        ]),
      ),
      const SizedBox(height: 6),
      Expanded(child: switch (_tab) {
        'liked' => _likedList(handler),
        'albums' => _savedItemsList(lib, 'album'),
        'artists' => _savedItemsList(lib, 'artist'),
        'local' => const LocalFilesBody(),
        'downloads' => DownloadsBody(onGoSearch: widget.onGoSearch),
        _ => _playlistList(lib),
      }),
      if (_tab == 'playlists')
        // FAB harus bebas dari chrome melayang: jarak bawah mengikuti ada/tidaknya
        // mini player (chrome lebih tinggi saat ada lagu aktif).
        StreamBuilder<MediaItem?>(
          stream: handler.mediaItem.stream,
          initialData: handler.mediaItem.valueOrNull,
          builder: (context, snap) => Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, snap.data != null ? bottomChromeClearance(context) + 16 : kNavBarHeight + MediaQuery.paddingOf(context).bottom + 16),
            child: Align(alignment: Alignment.bottomRight, child: FloatingActionButton(
              backgroundColor: ClaiColors.accent, foregroundColor: ClaiColors.onAccent,
              onPressed: () async {
                final name = await promptText(context, context.l10n.collectionNewPlaylistName);
                if (name != null && name.trim().isNotEmpty) await lib.createPlaylist(name.trim());
              },
              child: ClaiIcon(ClaiIcons.add, color: ClaiColors.onAccent),
            )),
          ),
        ),
    ]);
  }

  Widget _playlistList(LibraryController lib) {
    var items = lib.playlists.where((p) => p.name.toLowerCase().contains(_filter)).toList();
    if (_sort == 'az') items.sort((a, b) => a.name.compareTo(b.name));
    if (!lib.loaded) return const LoadingSkeleton();
    if (items.isEmpty) {
      return EmptyState(icon: ClaiIcons.queue, message: context.l10n.collectionEmptyPlaylists);
    }
    return ListView(children: [
      for (final pl in items)
        ListTile(
          leading: _mosaic(pl.artworkUrls, pl.name),
          title: Text(pl.name, style: const TextStyle(fontWeight: FontWeight.w600, color: ClaiColors.ink)),
          subtitle: Text(context.l10n.songCount(pl.count), style: const TextStyle(color: ClaiColors.inkSecondary)),
          trailing: ClaiIcon(ClaiIcons.chevronRight, color: ClaiColors.inkFaint),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => PlaylistScreen(playlistId: pl.id, name: pl.name))),
        ),
      const SizedBox(height: 24),
    ]);
  }

  Widget _mosaic(List<String> urls, String name) {
    final filled = urls.where((u) => u.isNotEmpty).toList();
    if (filled.isEmpty) {
      return Container(width: 56, height: 56, decoration: BoxDecoration(color: ClaiColors.surface2, borderRadius: BorderRadius.circular(8)),
          child: ClaiIcon(ClaiIcons.queue, color: ClaiColors.inkFaint));
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(width: 56, height: 56, child: GridView.count(crossAxisCount: 2, physics: const NeverScrollableScrollPhysics(), children: [
        for (var i = 0; i < 4; i++)
          Image.network(artworkUrlForSize(filled[i % filled.length], 200)!, fit: BoxFit.cover, cacheWidth: 128, errorBuilder: (_, __, ___) => Container(color: ClaiColors.surface3)),
      ])),
    );
  }

  /// Tab Album & Artis tersimpan (PRD 5.6, Sapuan D-13) — item disimpan
  /// dari halaman konten; ketuk membuka halaman kontennya lagi.
  Widget _savedItemsList(LibraryController lib, String kind) {
    // U-2 (build 2018): urut global kini berlaku di tab ini juga.
    final items = sortSavedItems(
        (kind == 'album' ? lib.savedAlbums : lib.savedArtists)
            .where((e) =>
                e.title.toLowerCase().contains(_filter) ||
                (e.subtitle ?? '').toLowerCase().contains(_filter))
            .toList(),
        _sort);
    if (!lib.loaded) return const LoadingSkeleton();
    if (items.isEmpty) {
      return EmptyState(
        icon: kind == 'album' ? ClaiIcons.album : ClaiIcons.person,
        message: kind == 'album'
            ? context.l10n.collectionEmptyAlbums
            : context.l10n.collectionEmptyArtists,
        actionLabel:
            widget.onGoSearch == null ? null : context.l10n.collectionGoSearch,
        onAction: widget.onGoSearch,
      );
    }
    return ListView(children: [
      for (final e in items)
        ListTile(
          leading: CoverArt(url: e.artworkUrl, size: 56, label: e.title),
          title: Text(e.title, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600, color: ClaiColors.ink)),
          subtitle: e.subtitle == null
              ? null
              : Text(e.subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: ClaiColors.inkSecondary)),
          trailing: ClaiIcon(ClaiIcons.chevronRight, color: ClaiColors.inkFaint),
          onTap: () => openContent(context, ref, kind, e.id, e.title),
        ),
      SizedBox(height: bottomChromeClearance(context)),
    ]);
  }

  Widget _likedList(dynamic handler) {
    return FutureBuilder<List<Track>>(
      future: ref.read(appDbProvider).likedTracks(),
      builder: (context, snap) {
        if (!snap.hasData) return const LoadingSkeleton();
        var tracks = snap.data!.where((t) =>
            t.title.toLowerCase().contains(_filter) || t.artistNames.toLowerCase().contains(_filter)).toList();
        if (_sort == 'az') tracks.sort((a, b) => a.title.compareTo(b.title));
        if (tracks.isEmpty) {
          return EmptyState(
            icon: ClaiIcons.heart,
            message: context.l10n.collectionEmptySaved,
            actionLabel: widget.onGoSearch == null
                ? null
                : context.l10n.collectionGoSearch,
            onAction: widget.onGoSearch,
          );
        }
        return ListView(children: [
          // Audit UX 2017: kepala daftar kini punya tombol Putar bulat
          // (pola sama seperti kepala halaman Radio/konten) — memutar
          // seluruh daftar dari awal tanpa harus mengetuk baris tertentu.
          Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Row(children: [
                Expanded(child: Text(context.l10n.collectionSavedCount(tracks.length), style: const TextStyle(color: ClaiColors.inkSecondary, fontSize: 13))),
                Semantics(
                  button: true,
                  label: context.l10n.a11yPlay,
                  child: PressableScale(
                    child: GestureDetector(
                      onTap: () => handler.playTracks(tracks, 0, kind: 'liked', label: context.l10n.homeSavedSongs),
                      child: Container(width: 48, height: 48,
                          decoration: const BoxDecoration(color: ClaiColors.accent, shape: BoxShape.circle),
                          child: ClaiIcon(ClaiIcons.play, color: ClaiColors.onAccent, size: 26)),
                    ),
                  ),
                ),
              ])),
          for (final t in tracks)
            SongRow(track: t, onTap: () => handler.playTracks(tracks, tracks.indexOf(t), kind: 'liked', label: context.l10n.homeSavedSongs)),
          SizedBox(height: bottomChromeClearance(context)),
        ]);
      },
    );
  }
}
