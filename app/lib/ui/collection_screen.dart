import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../app.dart';
import '../core/artwork.dart';
import '../core/clai_icons.dart';
import '../core/tokens.dart';
import '../data/app_db.dart';
import '../domain/models.dart';
import '../l10n/l10n.dart';
import '../services/ambient_theme.dart';
import '../services/download_service.dart';
import '../services/library_controller.dart';
import 'cover_accent_glow.dart';
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

/// Label "terakhir diputar" relatif untuk meta baris playlist (papan 05)
/// dari cap waktu epoch milidetik peristiwa putar terakhir playlist itu.
/// Murni & diuji — memakai hari kalender, bukan jendela 24 jam bergulir.
String lastPlayedLabel(AppLocalizations l, int msEpoch, DateTime now) {
  final then = DateTime.fromMillisecondsSinceEpoch(msEpoch);
  final a = DateTime(now.year, now.month, now.day);
  final b = DateTime(then.year, then.month, then.day);
  final days = a.difference(b).inDays;
  if (days <= 0) return l.collectionLastPlayedToday;
  if (days == 1) return l.collectionLastPlayedYesterday;
  if (days < 7) return l.collectionLastPlayedDays(days);
  if (days < 30) return l.collectionLastPlayedWeeks(days ~/ 7);
  if (days < 365) return l.collectionLastPlayedMonths(days ~/ 30);
  return l.collectionLastPlayedYears(days ~/ 365);
}

/// Ukuran penyimpanan terbaca untuk meta Unduhan ("512 MB di perangkat"):
/// MB bulat; GB dengan satu desimal (koma untuk id, titik untuk en).
/// Murni & diuji.
String formatStorageSize(int bytes, {required bool commaDecimal}) {
  if (bytes <= 0) return '0 MB';
  final mb = bytes / (1024 * 1024);
  if (mb < 1024) return '${mb.round()} MB';
  final gb = (mb / 1024).toStringAsFixed(1);
  return '${commaDecimal ? gb.replaceAll('.', ',') : gb} GB';
}

/// Agregat nyata Koleksi dari basis data lokal (papan 05): gabungan trek
/// berbeda (suka ∪ semua playlist pengguna), putar terakhir per playlist,
/// dan hitungan lagu tersimpan per artis tersimpan. Semua angka dari DB —
/// tidak ada yang dikarang untuk mengisi meta.
typedef CollectionMeta = ({
  int songs,
  Map<String, int> lastPlayed,
  Map<String, int> artistCounts,
});

Future<CollectionMeta> loadCollectionMeta(
    AppDb db, List<PlaylistInfo> playlists, List<SavedItemInfo> artists) async {
  final union = <TrackKey, Track>{};
  for (final t in await db.likedTracks()) {
    union[t.key] = t;
  }
  for (final pl in playlists) {
    for (final t in await db.playlistTracks(pl.id)) {
      union[t.key] = t;
    }
  }
  final tracks = union.values.toList();
  final artistCounts = <String, int>{};
  for (final a in artists) {
    final want = a.title.trim().toLowerCase();
    var n = 0;
    for (final t in tracks) {
      if (t.artistIds.contains(a.id) ||
          primaryArtistName(t.artistNames).trim().toLowerCase() == want) {
        n++;
      }
    }
    artistCounts[a.id] = n;
  }
  return (
    songs: tracks.length,
    lastPlayed: await db.playlistLastPlayed(),
    artistCounts: artistCounts,
  );
}

/// Koleksi (PRD 5.6) — Gelombang 2 (8048), komposisi papan Stitch:
/// kepala (gir + judul display 34 + garis statistik tiga angka), bidang
/// saring, lalu SATU halaman gulir berjangkar chip (Semua / Playlist /
/// Album / Artis / Tersukai): panggung terakhir-diputar berwarna sampul
/// playlist itu, blok MILIKMU (Disukai lebar penuh + Unduhan & Berkas
/// Lokal setengah lebar sebagai pintu ke badannya masing-masing), kisi
/// mosaik playlist, rel album, rel avatar Artis Kamu. Semua angka dari
/// agregat DB yang sama seperti sebelumnya; FAB hanya di konteks
/// playlist. Unduhan/Lokal tampil sebagai badan penuh menggantikan
/// guliran (pintu blok), kembali lewat chip.
class CollectionScreen extends ConsumerStatefulWidget {
  /// Audit UX 2017: jalan keluar dari keadaan kosong tab Koleksi menuju
  /// tab Cari (disambungkan pemilik cangkang di app.dart; null = tanpa aksi).
  final VoidCallback? onGoSearch;
  const CollectionScreen({super.key, this.onGoSearch});
  @override
  ConsumerState<CollectionScreen> createState() => _CollectionScreenState();
}

class _CollectionScreenState extends ConsumerState<CollectionScreen> {
  String _tab = 'semua';
  String _filter = '';
  String _sort = 'terbaru';
  Future<CollectionMeta>? _metaFuture;
  String _metaSig = '';

  bool get _filtering => _filter.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final lib = ref.watch(libraryProvider);
    final handler = ref.watch(audioHandlerProvider);
    // Agregat dihitung ulang hanya bila bentuk koleksi berubah
    // (tanda tangan: jumlah suka + (id:hitungan) tiap playlist + artis).
    final sig =
        '${lib.likedKeys.length}|${lib.playlists.map((p) => '${p.id}:${p.count}').join(',')}|${lib.savedArtists.length}';
    if (sig != _metaSig) {
      _metaSig = sig;
      _metaFuture = loadCollectionMeta(
          ref.read(appDbProvider), lib.playlists, lib.savedArtists);
    }
    final showFab = _tab == 'semua' || _tab == 'playlists';
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 8, 0),
        child: Row(children: [
          Text(l.collectionTitle, style: displayStyle(34)),
          const Spacer(),
          PopupMenuButton<String>(
            icon: ClaiIcon(ClaiIcons.sort, color: ClaiColors.inkSecondary),
            tooltip: l.a11ySort,
            color: ClaiColors.surface2,
            onSelected: (v) => setState(() => _sort = v),
            itemBuilder: (_) => [
              PopupMenuItem(
                  value: 'terbaru', child: Text(l.collectionSortRecent)),
              const PopupMenuItem(value: 'az', child: Text('A–Z')),
            ],
          ),
          IconButton(
              icon: ClaiIcon(ClaiIcons.settings, color: ClaiColors.inkSecondary),
              tooltip: l.a11ySettings,
              onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SettingsScreen()))),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 2, 20, 6),
        child: FutureBuilder<CollectionMeta>(
          future: _metaFuture,
          builder: (context, snap) => Text(
            snap.hasData
                ? l.collectionStatsFull(snap.data!.songs, lib.playlists.length,
                    lib.savedArtists.length)
                : '',
            maxLines: 2,
            style: const TextStyle(
                color: ClaiColors.inkSecondary, fontSize: 13, height: 1.4),
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: TextField(
          onChanged: (v) => setState(() => _filter = v.trim().toLowerCase()),
          style: const TextStyle(color: ClaiColors.ink),
          decoration: InputDecoration(
              hintText: l.collectionFilterHint,
              prefixIcon: ClaiIcon(ClaiIcons.search),
              filled: true,
              fillColor: ClaiColors.surface1,
              border: const OutlineInputBorder(
                  borderSide: BorderSide.none,
                  borderRadius: BorderRadius.all(Radius.circular(12)))),
        ),
      ),
      const SizedBox(height: 10),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(children: [
          for (final t in ['semua', 'playlists', 'albums', 'artists', 'liked'])
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _anchorChip(
                label: switch (t) {
                  'semua' => l.collectionAll,
                  'albums' => l.collectionAlbums,
                  'artists' => l.collectionArtists,
                  'liked' => l.collectionLikedSongs,
                  _ => l.collectionPlaylists,
                },
                selected: _tab == t,
                onTap: () => setState(() => _tab = t),
              ),
            ),
        ]),
      ),
      const SizedBox(height: 6),
      Expanded(
        child: FutureBuilder<CollectionMeta>(
          future: _metaFuture,
          builder: (context, snap) => switch (_tab) {
            'albums' => _albumsView(lib),
            'artists' => _artistsView(lib, snap.data),
            'liked' => _likedBody(),
            'local' => const LocalFilesBody(),
            'downloads' => DownloadsBody(onGoSearch: widget.onGoSearch),
            'playlists' => _playlistsView(lib, snap.data),
            _ => _semuaView(lib, snap.data),
          },
        ),
      ),
      if (showFab)
        // FAB matte gelap (papan Stitch): bebas dari chrome melayang —
        // jarak bawah mengikuti ada/tidaknya mini player.
        StreamBuilder<MediaItem?>(
          stream: handler.mediaItem.stream,
          initialData: handler.mediaItem.valueOrNull,
          builder: (context, snap) => Padding(
            padding: EdgeInsets.fromLTRB(20, 8, 20,
                snap.data != null
                    ? bottomChromeClearance(context) + 16
                    : kNavBarHeight +
                        MediaQuery.paddingOf(context).bottom +
                        16),
            child: Align(
              alignment: Alignment.bottomRight,
              child: FloatingActionButton(
                backgroundColor: ClaiColors.surface3,
                foregroundColor: ClaiColors.accent,
                onPressed: () async {
                  final name =
                      await promptText(context, l.collectionNewPlaylistName);
                  if (name != null && name.trim().isNotEmpty) {
                    await lib.createPlaylist(name.trim());
                  }
                },
                child: ClaiIcon(ClaiIcons.add, color: ClaiColors.accent),
              ),
            ),
          ),
        ),
    ]);
  }

  /// Chip jangkar papan Stitch: pil gelap; aktif = permukaan lebih
  /// terang + titik Volt 6 dp (sinyal mikro, bukan isian).
  Widget _anchorChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: selected ? ClaiColors.surface3 : ClaiColors.surface2,
      borderRadius: BorderRadius.circular(999),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (selected) ...[
              Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: ClaiColors.accent,
                ),
              ),
              const SizedBox(width: 7),
            ],
            Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: ClaiColors.ink,
              ),
            ),
          ]),
        ),
      ),
    );
  }

  List<PlaylistInfo> _playlistsFiltered(LibraryController lib) {
    var items = lib.playlists
        .where((p) => p.name.toLowerCase().contains(_filter))
        .toList();
    if (_sort == 'az') items.sort((a, b) => a.name.compareTo(b.name));
    return items;
  }

  List<SavedItemInfo> _savedFiltered(LibraryController lib, String kind) {
    return sortSavedItems(
        (kind == 'album' ? lib.savedAlbums : lib.savedArtists)
            .where((e) =>
                e.title.toLowerCase().contains(_filter) ||
                (e.subtitle ?? '').toLowerCase().contains(_filter))
            .toList(),
        _sort);
  }

  // ------------------------------------------------------------------
  // Pandangan SEMUA: panggung + MILIKMU + kisi + rel-rel.
  // ------------------------------------------------------------------
  Widget _semuaView(LibraryController lib, CollectionMeta? meta) {
    if (!lib.loaded) return const LoadingSkeleton();
    final l = context.l10n;
    final playlists = _playlistsFiltered(lib);
    final albums = _savedFiltered(lib, 'album');
    final artists = _savedFiltered(lib, 'artist');
    final dl = ref.watch(downloadServiceProvider);
    final doneDownloads =
        dl.items.where((i) => i.status == DownloadStatus.done).toList();
    final dlBytes = doneDownloads.fold<int>(
        0, (a, i) => a + (i.bytesTotal ?? i.bytesDone));
    final scan = ref.watch(localScanCacheProvider);
    // Playlist panggung: yang terakhir diputar menurut agregat; tanpa
    // riwayat putar, playlist pertama dalam urutan simpan.
    PlaylistInfo? featured;
    if (playlists.isNotEmpty && !_filtering) {
      featured = playlists.first;
      var best = -1;
      for (final pl in playlists) {
        final lp = meta?.lastPlayed[pl.id] ?? -1;
        if (lp > best) {
          best = lp;
          featured = pl;
        }
      }
    }
    return FiniteScrollPage(
      padding: const EdgeInsets.only(top: 6),
      children: [
        if (featured != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
            child: _heroCard(featured, meta),
          ),
        if (!_filtering) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 10),
            child: DimKicker(l.collectionYours),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Material(
              color: ClaiColors.surface1,
              borderRadius: BorderRadius.circular(16),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => setState(() => _tab = 'liked'),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(children: [
                    tonalIconBox(ClaiIcons.heartFill, size: 44, iconSize: 22, color: ClaiColors.liked),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        l.collectionLikedSongs,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: ClaiColors.ink,
                        ),
                      ),
                    ),
                    Text(
                      '${lib.likedKeys.length}',
                      style: displayStyle(24),
                    ),
                  ]),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(children: [
              Expanded(
                child: _doorBlock(
                  icon: ClaiIcons.download,
                  title: l.collectionDownloads,
                  meta: l.collectionDownloadsMeta(
                    doneDownloads.length,
                    formatStorageSize(dlBytes,
                        commaDecimal: Localizations.localeOf(context)
                                .languageCode ==
                            'id'),
                  ),
                  onTap: () => setState(() => _tab = 'downloads'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _doorBlock(
                  icon: ClaiIcons.folder,
                  title: l.collectionLocalFiles,
                  meta: scan != null
                      ? l.collectionLocalMeta(scan.length)
                      : l.localSub,
                  onTap: () => setState(() => _tab = 'local'),
                ),
              ),
            ]),
          ),
        ],
        if (playlists.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 10),
            child: DimKicker(l.collectionPlaylists),
          ),
          _playlistGrid(playlists, meta),
        ] else if (!_filtering)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: EmptyState(
                icon: ClaiIcons.queue, message: l.collectionEmptyPlaylists),
          ),
        if (albums.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 10),
            child: DimKicker(l.collectionAlbums),
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
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => openContent(context, ref, 'album', a.id, a.title),
                  child: SizedBox(
                    width: 128,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CoverArt(
                            url: a.artworkUrl,
                            size: 128,
                            radius: 16,
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
                        if (a.subtitle != null)
                          Text(
                            a.subtitle!,
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
        if (artists.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 10),
            child: DimKicker(l.collectionYourArtists),
          ),
          SizedBox(
            height: 106,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: artists.length,
              separatorBuilder: (_, _) => const SizedBox(width: 14),
              itemBuilder: (context, i) {
                final a = artists[i];
                return InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () =>
                      openContent(context, ref, 'artist', a.id, a.title),
                  child: SizedBox(
                    width: 76,
                    child: Column(
                      children: [
                        CoverArt(
                            url: a.artworkUrl,
                            size: 64,
                            label: a.title,
                            radius: 32),
                        const SizedBox(height: 7),
                        Text(
                          a.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 13,
                            color: ClaiColors.ink,
                          ),
                        ),
                        Text(
                          l.collectionSavedCount(
                              meta?.artistCounts[a.id] ?? 0),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 11,
                            color: ClaiColors.inkFaint,
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

  /// Blok pintu setengah lebar (Unduhan / Berkas Lokal): ubin ikon
  /// tonal + judul 15 + meta nyata — matte, tanpa lime.
  Widget _doorBlock({
    required ClaiIconData icon,
    required String title,
    required String meta,
    required VoidCallback onTap,
  }) {
    return Material(
      color: ClaiColors.surface1,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              tonalIconBox(icon, size: 40, iconSize: 20),
              const SizedBox(height: 10),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: ClaiColors.ink,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                meta,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  color: ClaiColors.inkSecondary,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Kartu panggung terakhir-diputar: kartu berwarna tinta sampul
  /// playlist unggulan (gradasi tonal → surface-2), mosaik 84, tombol
  /// Putar 52 bernada sampul diperdalam (§11.9).
  Widget _heroCard(PlaylistInfo pl, CollectionMeta? meta) {
    final l = context.l10n;
    final handler = ref.read(audioHandlerProvider);
    final filledCovers = pl.artworkUrls.where((u) => u.isNotEmpty).toList();
    final cover = filledCovers.isEmpty ? null : filledCovers.first;
    return CoverAccentBuilder(
      artworkUrl: cover,
      builder: (context, tonal) {
        final tone =
            tonal == null ? ClaiColors.accent : deepToneFromColor(tonal);
        return Material(
          borderRadius: BorderRadius.circular(20),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) =>
                    PlaylistScreen(playlistId: pl.id, name: pl.name))),
            child: Ink(
              decoration: BoxDecoration(
                gradient: tonal == null
                    ? null
                    : LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          tonal.withValues(alpha: 0.55),
                          tonal.withValues(alpha: 0.22),
                          ClaiColors.surface2,
                        ],
                      ),
                color: tonal == null ? ClaiColors.surface2 : null,
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _mosaic(pl.artworkUrls, pl.name, size: 84, radius: 12),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            l.collectionLastPlayedKicker.toUpperCase(),
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1.6,
                              color: ClaiColors.inkSecondary,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            pl.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: displayStyle(22),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            [
                              l.collectionPlaylists,
                              l.songCount(pl.count),
                              if (meta?.lastPlayed[pl.id] != null)
                                lastPlayedLabel(l, meta!.lastPlayed[pl.id]!,
                                    DateTime.now()),
                            ].join(' · '),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              color: ClaiColors.inkSecondary,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    PressableScale(
                      child: GestureDetector(
                        onTap: () async {
                          final tracks = await ref
                              .read(appDbProvider)
                              .playlistTracks(pl.id);
                          if (tracks.isEmpty || !context.mounted) return;
                          handler.playTracks(tracks, 0,
                              kind: 'userPlaylist', id: pl.id, label: pl.name);
                        },
                        child: Container(
                          width: 52,
                          height: 52,
                          decoration:
                              BoxDecoration(color: tone, shape: BoxShape.circle),
                          child: ClaiIcon(
                            ClaiIcons.play,
                            color: onProgressTone(tone),
                            size: 25,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _playlistGrid(List<PlaylistInfo> items, CollectionMeta? meta) {
    final l = context.l10n;
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 16,
        mainAxisExtent: 238,
      ),
      itemCount: items.length,
      itemBuilder: (context, i) {
        final pl = items[i];
        return InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) =>
                  PlaylistScreen(playlistId: pl.id, name: pl.name))),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LayoutBuilder(
                builder: (context, box) =>
                    _mosaic(pl.artworkUrls, pl.name, size: box.maxWidth, radius: 16),
              ),
              const SizedBox(height: 8),
              Text(
                pl.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: ClaiColors.ink,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                [
                  l.collectionPlaylists,
                  l.songCount(pl.count),
                  if (meta?.lastPlayed[pl.id] != null)
                    lastPlayedLabel(
                        l, meta!.lastPlayed[pl.id]!, DateTime.now()),
                ].join(' · '),
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
    );
  }

  // ------------------------------------------------------------------
  // Pandangan per jenis.
  // ------------------------------------------------------------------
  Widget _playlistsView(LibraryController lib, CollectionMeta? meta) {
    if (!lib.loaded) return const LoadingSkeleton();
    final items = _playlistsFiltered(lib);
    if (items.isEmpty) {
      return EmptyState(
        icon: ClaiIcons.queue,
        message: context.l10n.collectionEmptyPlaylists,
      );
    }
    return FiniteScrollPage(
      padding: const EdgeInsets.only(top: 12),
      children: [
        _playlistGrid(items, meta),
        SizedBox(height: bottomChromeClearance(context)),
      ],
    );
  }

  Widget _albumsView(LibraryController lib) {
    if (!lib.loaded) return const LoadingSkeleton();
    final l = context.l10n;
    final items = _savedFiltered(lib, 'album');
    if (items.isEmpty) {
      return EmptyState(
        icon: ClaiIcons.album,
        message: l.collectionEmptyAlbums,
        actionLabel: widget.onGoSearch == null ? null : l.collectionGoSearch,
        onAction: widget.onGoSearch,
      );
    }
    return FiniteScrollPage(
      padding: const EdgeInsets.only(top: 12),
      children: [
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
          itemCount: items.length,
          itemBuilder: (context, i) {
            final a = items[i];
            return InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => openContent(context, ref, 'album', a.id, a.title),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LayoutBuilder(
                    builder: (context, box) => CoverArt(
                        url: a.artworkUrl,
                        size: box.maxWidth,
                        radius: 16,
                        label: a.title),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    a.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: ClaiColors.ink,
                      height: 1.25,
                    ),
                  ),
                  if (a.subtitle != null)
                    Text(
                      a.subtitle!,
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
        SizedBox(height: bottomChromeClearance(context)),
      ],
    );
  }

  Widget _artistsView(LibraryController lib, CollectionMeta? meta) {
    if (!lib.loaded) return const LoadingSkeleton();
    final l = context.l10n;
    final items = _savedFiltered(lib, 'artist');
    if (items.isEmpty) {
      return EmptyState(
        icon: ClaiIcons.person,
        message: l.collectionEmptyArtists,
        actionLabel: widget.onGoSearch == null ? null : l.collectionGoSearch,
        onAction: widget.onGoSearch,
      );
    }
    return FiniteScrollPage(
      padding: const EdgeInsets.only(top: 12),
      children: [
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 16,
            mainAxisExtent: 172,
          ),
          itemCount: items.length,
          itemBuilder: (context, i) {
            final a = items[i];
            return InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => openContent(context, ref, 'artist', a.id, a.title),
              child: Column(
                children: [
                  CoverArt(url: a.artworkUrl, size: 96, label: a.title, radius: 48),
                  const SizedBox(height: 8),
                  Text(
                    a.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: ClaiColors.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    l.collectionSavedCount(meta?.artistCounts[a.id] ?? 0),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
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
        SizedBox(height: bottomChromeClearance(context)),
      ],
    );
  }

  /// Badan Tersukai sebaris (chip Tersukai): isi yang sama dengan
  /// [LikedSongsScreen] — hitungan + Putar semua + baris lagu.
  Widget _likedBody() {
    final l = context.l10n;
    final handler = ref.watch(audioHandlerProvider);
    return FutureBuilder<List<Track>>(
      future: ref.read(appDbProvider).likedTracks(),
      builder: (context, snap) {
        if (!snap.hasData) return const LoadingSkeleton();
        final tracks = snap.data!;
        if (tracks.isEmpty) {
          return EmptyState(
            icon: ClaiIcons.heart,
            message: l.collectionEmptySaved,
          );
        }
        return FiniteScrollPage(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
            child: Row(children: [
              Expanded(
                child: Text(
                  l.collectionSavedCount(tracks.length),
                  style: const TextStyle(
                      color: ClaiColors.inkSecondary, fontSize: 13),
                ),
              ),
              Semantics(
                button: true,
                label: l.a11yPlay,
                child: PressableScale(
                  child: GestureDetector(
                    onTap: () => handler.playTracks(tracks, 0,
                        kind: 'liked', label: l.homeSavedSongs),
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: const BoxDecoration(
                          color: ClaiColors.accent, shape: BoxShape.circle),
                      child: ClaiIcon(ClaiIcons.play,
                          color: ClaiColors.onAccent, size: 26),
                    ),
                  ),
                ),
              ),
            ]),
          ),
          for (final t in tracks)
            SongRow(
              track: t,
              onTap: () => handler.playTracks(tracks, tracks.indexOf(t),
                  kind: 'liked', label: l.homeSavedSongs),
            ),
          SizedBox(height: bottomChromeClearance(context)),
        ]);
      },
    );
  }

  Widget _mosaic(List<String> urls, String name,
      {double size = 72, double radius = 14}) {
    final filled = urls.where((u) => u.isNotEmpty).toList();
    if (filled.isEmpty) {
      return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
              color: ClaiColors.surface2,
              borderRadius: BorderRadius.circular(radius)),
          child: ClaiIcon(ClaiIcons.queue, color: ClaiColors.inkFaint));
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
          width: size,
          height: size,
          child: GridView.count(
              crossAxisCount: 2,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                for (var i = 0; i < 4; i++)
                  Image.network(artworkUrlForSize(filled[i % filled.length], 200)!,
                      fit: BoxFit.cover,
                      cacheWidth: 128,
                      errorBuilder: (_, _, _) =>
                          Container(color: ClaiColors.surface3)),
              ])),
    );
  }
}

/// Halaman Lagu yang Disukai (tujuan baris khusus papan 05): daftar lagu
/// tersimpan yang sama seperti tab lama — kepala hitungan + tombol Putar
/// semua (Audit UX 2017) — kini sebagai halamannya sendiri.
class LikedSongsScreen extends ConsumerWidget {
  const LikedSongsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final handler = ref.watch(audioHandlerProvider);
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.homeSavedSongs)),
      body: FutureBuilder<List<Track>>(
        future: ref.read(appDbProvider).likedTracks(),
        builder: (context, snap) {
          if (!snap.hasData) return const LoadingSkeleton();
          final tracks = snap.data!;
          if (tracks.isEmpty) {
            return EmptyState(
              icon: ClaiIcons.heart,
              message: context.l10n.collectionEmptySaved,
            );
          }
          return FiniteScrollPage(children: [
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
      ),
    );
  }
}
