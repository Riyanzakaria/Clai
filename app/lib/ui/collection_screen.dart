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
import 'menu_drawer.dart';
import 'playlist_screen.dart';
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

/// Total durasi playlist dari durasi trek NYATA: hanya terdefinisi bila
/// playlist tidak kosong DAN semua treknya punya durasi diketahui —
/// satu trek tanpa durasi membuat totalnya TIDAK tampil (aturan
/// kejujuran Ronde 8083; total tidak ditebak dari sebagian trek).
/// Murni & diuji.
Duration? playlistTotalDuration(List<Track> tracks) {
  if (tracks.isEmpty) return null;
  var total = Duration.zero;
  for (final t in tracks) {
    final d = t.duration;
    if (d == null) return null;
    total += d;
  }
  return total;
}

/// Bentuk panjang total durasi untuk meta playlist Koleksi: "3 jam
/// 12 mnt" untuk ≥ 1 jam, "45 mnt" di bawahnya (en: "3 hr 12 min" /
/// "45 min"). Pembentuk total yang sudah ada di aplikasi (ringkasan
/// Antrean di queue_screen.dart) memakai formatDuration m:ss untuk
/// durasi per trek — tidak ada bentuk panjang total di aplikasi, jadi
/// bentuk ini mengikuti gaya spesimen "Koleksi — Perbaikan" (8083).
/// Murni & diuji.
String formatTotalDuration(Duration d, {required bool indonesian}) {
  final h = d.inHours;
  final m = d.inMinutes - h * 60;
  final hourWord = indonesian ? 'jam' : 'hr';
  final minWord = indonesian ? 'mnt' : 'min';
  if (h > 0 && m > 0) return '$h $hourWord $m $minWord';
  if (h > 0) return '$h $hourWord';
  return '$m $minWord';
}

/// Baris ringkasan header Koleksi: "`<N>` lagu • `<N>` playlist • `<N>` album",
/// dirakit dari kunci yang sudah ada — songCount untuk lagu, label
/// collectionPlaylists/collectionAlbums diturunkan ke sentence-case.
/// Tidak ada kunci kalimat persis untuk kombinasi ini di arb.
/// Murni & diuji.
String collectionSummaryLine(
  AppLocalizations l, {
  required int songs,
  required int playlists,
  required int albums,
}) {
  String label(String s) => s.isEmpty ? s : s[0].toLowerCase() + s.substring(1);
  return '${l.songCount(songs)} • $playlists ${label(l.collectionPlaylists)}'
      ' • $albums ${label(l.collectionAlbums)}';
}

/// Motif batang gelombang redup DETERMINISTIK untuk keadaan kosong
/// Koleksi (pola A7, Ronde 8083): tinggi batang dari pola tetap —
/// bukan data, bukan acak; digambar sekali sebagai dekorasi redup
/// di atas teks keadaan kosong lokal berkas ini.
const List<double> kEmptyWaveHeights = [
  6,
  12,
  20,
  10,
  26,
  16,
  32,
  14,
  22,
  8,
  18,
  28,
  12,
  24,
  10,
  30,
  16,
  20,
  8,
  14,
];

/// Agregat nyata Koleksi dari basis data lokal (papan 05): gabungan trek
/// berbeda (suka ∪ semua playlist pengguna), putar terakhir per playlist,
/// dan hitungan lagu tersimpan per artis tersimpan. Semua angka dari DB —
/// tidak ada yang dikarang untuk mengisi meta.
typedef CollectionMeta = ({
  int songs,
  Map<String, int> lastPlayed,
  Map<String, int> artistCounts,
  Map<String, Duration?> playlistDurations,
});

Future<CollectionMeta> loadCollectionMeta(
  AppDb db,
  List<PlaylistInfo> playlists,
  List<SavedItemInfo> artists,
) async {
  final union = <TrackKey, Track>{};
  for (final t in await db.likedTracks()) {
    union[t.key] = t;
  }
  final playlistDurations = <String, Duration?>{};
  for (final pl in playlists) {
    final tracks = await db.playlistTracks(pl.id);
    playlistDurations[pl.id] = playlistTotalDuration(tracks);
    for (final t in tracks) {
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
    playlistDurations: playlistDurations,
  );
}

/// Koleksi (PRD 5.6) — Gelombang 2 (8048), komposisi papan Stitch;
/// Ronde 8083 ("Koleksi — Perbaikan"): kepala (judul display 34 +
/// tombol markah laci + numeral editorial lagu nyata + baris ringkasan
/// lagu/playlist/album), bidang saring, lalu SATU halaman gulir
/// berjangkar chip (Semua / Playlist / Album / Artis / Tersukai):
/// panggung terakhir-diputar berwarna sampul playlist itu, baris pintu
/// MILIKMU (ikon telanjang + label + angka besar), baris playlist
/// [CollectionRow], rel album, rel avatar Artis Kamu. Semua angka dari
/// agregat DB yang sama seperti sebelumnya; FAB hanya di konteks
/// playlist. Unduhan/Lokal tampil sebagai badan penuh menggantikan
/// guliran (pintu baris), kembali lewat chip.
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
        ref.read(appDbProvider),
        lib.playlists,
        lib.savedArtists,
      );
    }
    final showFab = _tab == 'semua' || _tab == 'playlists';
    return Stack(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 8, 0),
              child: Row(
                children: [
                  Text(l.collectionTitle, style: displayStyle(34)),
                  const Spacer(),
                  PopupMenuButton<String>(
                    icon: ClaiIcon(
                      ClaiIcons.sort,
                      color: ClaiColors.inkSecondary,
                    ),
                    tooltip: l.a11ySort,
                    color: ClaiColors.surface2,
                    onSelected: (v) => setState(() => _sort = v),
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: 'terbaru',
                        child: Text(l.collectionSortRecent),
                      ),
                      const PopupMenuItem(value: 'az', child: Text('A–Z')),
                    ],
                  ),
                  // Ronde 8079: gir Pengaturan → tombol markah laci Menu.
                  Padding(
                    padding: const EdgeInsets.all(4),
                    child: ClaiMarkButton(
                      onPressed: () => showClaiMenuDrawer(context),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 2, 20, 6),
              child: FutureBuilder<CollectionMeta>(
                future: _metaFuture,
                builder: (context, snap) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Numeral editorial (Ronde 8083, "Koleksi — Perbaikan"):
                    // angka BESAR font tampilan = jumlah lagu NYATA koleksi (gabungan
                    // suka ∪ playlist dari agregat DB yang sama). Selagi
                    // agregat dimuat tampil kosong — perilaku garis statistik
                    // sebelumnya; angka 0 hanya tampil bila koleksi memang
                    // kosong, bukan sebagai penampung muat.
                    Text(
                      snap.hasData ? '${snap.data!.songs}' : '',
                      style: heroStyle(40),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      snap.hasData
                          ? collectionSummaryLine(
                              l,
                              songs: snap.data!.songs,
                              playlists: lib.playlists.length,
                              albums: lib.savedAlbums.length,
                            )
                          : '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: ClaiColors.inkSecondary,
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(
                onChanged: (v) =>
                    setState(() => _filter = v.trim().toLowerCase()),
                style: const TextStyle(color: ClaiColors.ink),
                decoration: InputDecoration(
                  hintText: l.collectionFilterHint,
                  prefixIcon: ClaiIcon(ClaiIcons.search),
                  filled: true,
                  fillColor: ClaiColors.surface1,
                  border: const OutlineInputBorder(
                    borderSide: BorderSide.none,
                    borderRadius: BorderRadius.all(Radius.circular(12)),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  for (final t in [
                    'semua',
                    'playlists',
                    'albums',
                    'artists',
                    'liked',
                  ])
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
                ],
              ),
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
          ],
        ),
        if (showFab)
          // FAB matte gelap (papan Stitch) MELAYANG di atas daftar
          // (Ronde 8084): bukan lagi anak aliran Column — dulu Padding
          // selebar layar sesudah Expanded menyisakan pita hitam tetap
          // ±200dp di bawah daftar. Jarak bawah dinamis dipertahankan:
          // mengikuti ada/tidaknya mini player (rumus yang sama seperti
          // padding lama, kini sebagai posisi dari dasar Stack).
          StreamBuilder<MediaItem?>(
            stream: handler.mediaItem.stream,
            initialData: handler.mediaItem.valueOrNull,
            builder: (context, snap) => Positioned(
              right: 20,
              bottom: snap.data != null
                  ? bottomChromeClearance(context) + 16
                  : kNavBarHeight + MediaQuery.paddingOf(context).bottom + 16,
              child: FloatingActionButton(
                backgroundColor: ClaiColors.surface3,
                foregroundColor: ClaiColors.signal,
                onPressed: () async {
                  final name = await promptText(
                    context,
                    l.collectionNewPlaylistName,
                  );
                  if (name != null && name.trim().isNotEmpty) {
                    await lib.createPlaylist(name.trim());
                  }
                },
                child: ClaiIcon(ClaiIcons.add, color: ClaiColors.signal),
              ),
            ),
          ),
      ],
    );
  }

  /// Bantalan bawah DI DALAM konten gulir tiap tampilan tab (Ronde
  /// 8084): chrome melayang + napas 16 + tinggi FAB 56 + napas 16,
  /// supaya baris terakhir bisa digulir UTUH ke atas FAB melayang
  /// (pola SizedBox clearance di akhir daftar halaman lain).
  double _scrollEndClearance(BuildContext context) =>
      bottomChromeClearance(context) + 16 + 56 + 16;

  /// Chip jangkar papan Stitch: pil gelap; aktif = permukaan lebih
  /// terang + titik putih tinta 6 dp (penanda terpilih, bukan isian;
  /// DS v5.0).
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
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selected) ...[
                Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: ClaiColors.signal,
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
            ],
          ),
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
          .where(
            (e) =>
                e.title.toLowerCase().contains(_filter) ||
                (e.subtitle ?? '').toLowerCase().contains(_filter),
          )
          .toList(),
      _sort,
    );
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
    // Ronde 8066 (minor 8064-b): ringkasan memisahkan selesai vs sedang
    // berjalan — dulu hanya yang selesai dihitung, jadi selama unduhan
    // pertama berjalan pintu ini terbaca "0 lagu".
    final dlSummary = downloadsSummaryOf(dl.items);
    final dlSize = formatStorageSize(
      dlSummary.doneBytes,
      commaDecimal: Localizations.localeOf(context).languageCode == 'id',
    );
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
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 4),
            child: DimKicker(l.collectionYours),
          ),
          // Pintu Milikmu (Ronde 8083, densitas R2): TANPA kotak ikon
          // dan tanpa wadah kartu — ikon telanjang 24 + label 15/600 +
          // angka hitungan BESAR font tampilan 20 + meta keadaan nyata.
          // Substansi baris datang dari tipografi, bukan ubin.
          _doorRow(
            icon: ClaiIcons.heartFill,
            iconColor: ClaiColors.liked,
            label: l.collectionLikedSongs,
            count: lib.likedKeys.length,
            onTap: () => setState(() => _tab = 'liked'),
          ),
          _doorRow(
            icon: ClaiIcons.queue,
            label: l.collectionPlaylists,
            count: lib.playlists.length,
            onTap: () => setState(() => _tab = 'playlists'),
          ),
          _doorRow(
            icon: ClaiIcons.album,
            label: l.collectionAlbums,
            count: lib.savedAlbums.length,
            onTap: () => setState(() => _tab = 'albums'),
          ),
          _doorRow(
            icon: ClaiIcons.person,
            label: l.collectionArtists,
            count: lib.savedArtists.length,
            onTap: () => setState(() => _tab = 'artists'),
          ),
          _doorRow(
            icon: ClaiIcons.download,
            label: l.collectionDownloads,
            count: dlSummary.done,
            meta: dlSummary.active > 0
                ? l.collectionDownloadsMetaActive(
                    dlSummary.done,
                    dlSize,
                    dlSummary.active,
                  )
                : l.collectionDownloadsMeta(dlSummary.done, dlSize),
            onTap: () => setState(() => _tab = 'downloads'),
          ),
          _doorRow(
            icon: ClaiIcons.folder,
            label: l.collectionLocalFiles,
            count: scan?.length,
            // Sapuan tegas 8081: meta hanya keadaan nyata
            // (jumlah hasil pindai); belum dipindai = tanpa meta.
            meta: scan != null ? l.collectionLocalMeta(scan.length) : null,
            onTap: () => setState(() => _tab = 'local'),
          ),
        ],
        if (playlists.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 4),
            child: DimKicker(l.collectionPlaylists),
          ),
          _playlistRows(playlists, meta),
        ] else if (!_filtering)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: _emptyPlaylistsState(),
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
                          radius: 16,
                          label: a.title,
                        ),
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
                          radius: 32,
                        ),
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
                          l.collectionSavedCount(meta?.artistCounts[a.id] ?? 0),
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
        SizedBox(height: _scrollEndClearance(context)),
      ],
    );
  }

  /// Baris pintu Milikmu (Ronde 8083, densitas R2): ikon TELANJANG 24
  /// (tanpa wadah tonal/kartu, tanpa border), label 15/600, angka
  /// hitungan BESAR font tampilan 20 di kanan, dan meta keadaan nyata opsional
  /// di bawah label (mis. Unduhan "41 lagu (512 MB)" dari data unduhan
  /// asli). [count] null = hitungan belum diketahui (Berkas Lokal
  /// sebelum pindai pertama) — angka tidak dikarang.
  Widget _doorRow({
    required ClaiIconData icon,
    Color? iconColor,
    required String label,
    required int? count,
    String? meta,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Row(
          children: [
            rowLeadIcon(icon, size: 24, iconSize: 24, color: iconColor),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: ClaiColors.ink,
                    ),
                  ),
                  if (meta != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: ClaiColors.inkSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (count != null) ...[
              const SizedBox(width: 12),
              Text('$count', style: displayStyle(20)),
            ],
          ],
        ),
      ),
    );
  }

  /// Keadaan kosong playlist lokal berkas ini (pola A7, Ronde 8083):
  /// motif batang gelombang redup deterministik di atas teks kosong —
  /// dekorasi tetap, bukan data.
  Widget _emptyPlaylistsState() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (final h in kEmptyWaveHeights)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Container(
                  width: 3,
                  height: h,
                  decoration: BoxDecoration(
                    color: ClaiColors.inkFaint.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
          ],
        ),
        EmptyState(
          icon: ClaiIcons.queue,
          message: context.l10n.collectionEmptyPlaylists,
        ),
      ],
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
        final tone = tonal == null
            ? ClaiColors.signal
            : deepToneFromColor(tonal);
        return Material(
          borderRadius: BorderRadius.circular(20),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) =>
                    PlaylistScreen(playlistId: pl.id, name: pl.name),
              ),
            ),
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
                                lastPlayedLabel(
                                  l,
                                  meta!.lastPlayed[pl.id]!,
                                  DateTime.now(),
                                ),
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
                          handler.playTracks(
                            tracks,
                            0,
                            kind: 'userPlaylist',
                            id: pl.id,
                            label: pl.name,
                          );
                        },
                        child: Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            color: tone,
                            shape: BoxShape.circle,
                          ),
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

  /// Daftar playlist milik sendiri sebagai baris [CollectionRow]
  /// (Ronde 8083): data teks di bawah nama = "`<N>` lagu • `<total durasi>`"
  /// — total durasi hanya tampil bila SEMUA trek playlist punya durasi
  /// diketahui (lihat [playlistTotalDuration]); selain itu jumlah lagu
  /// saja. Tanpa mini waveform, tanpa border.
  Widget _playlistRows(List<PlaylistInfo> items, CollectionMeta? meta) {
    final l = context.l10n;
    final indonesian = Localizations.localeOf(context).languageCode == 'id';
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final pl in items)
          CollectionRow(
            mosaic: _mosaic(pl.artworkUrls, pl.name, size: 56, radius: 12),
            name: pl.name,
            meta: [
              l.songCount(pl.count),
              if (meta?.playlistDurations[pl.id] != null)
                formatTotalDuration(
                  meta!.playlistDurations[pl.id]!,
                  indonesian: indonesian,
                ),
            ].join(' • '),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) =>
                    PlaylistScreen(playlistId: pl.id, name: pl.name),
              ),
            ),
          ),
      ],
    );
  }

  // ------------------------------------------------------------------
  // Pandangan per jenis.
  // ------------------------------------------------------------------
  Widget _playlistsView(LibraryController lib, CollectionMeta? meta) {
    if (!lib.loaded) return const LoadingSkeleton();
    final items = _playlistsFiltered(lib);
    if (items.isEmpty) {
      return _emptyPlaylistsState();
    }
    return FiniteScrollPage(
      padding: const EdgeInsets.only(top: 12),
      children: [
        _playlistRows(items, meta),
        SizedBox(height: _scrollEndClearance(context)),
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
                      label: a.title,
                    ),
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
                  CoverArt(
                    url: a.artworkUrl,
                    size: 96,
                    label: a.title,
                    radius: 48,
                  ),
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
        return FiniteScrollPage(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      l.collectionSavedCount(tracks.length),
                      style: const TextStyle(
                        color: ClaiColors.inkSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  Semantics(
                    button: true,
                    label: l.a11yPlay,
                    child: PressableScale(
                      child: GestureDetector(
                        onTap: () => handler.playTracks(
                          tracks,
                          0,
                          kind: 'liked',
                          label: l.homeSavedSongs,
                        ),
                        child: Container(
                          width: 48,
                          height: 48,
                          decoration: const BoxDecoration(
                            color: ClaiColors.signal,
                            shape: BoxShape.circle,
                          ),
                          child: ClaiIcon(
                            ClaiIcons.play,
                            color: ClaiColors.onSignal,
                            size: 26,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            for (final t in tracks)
              SongRow(
                track: t,
                onTap: () => handler.playTracks(
                  tracks,
                  tracks.indexOf(t),
                  kind: 'liked',
                  label: l.homeSavedSongs,
                ),
              ),
            SizedBox(height: bottomChromeClearance(context)),
          ],
        );
      },
    );
  }

  Widget _mosaic(
    List<String> urls,
    String name, {
    double size = 72,
    double radius = 14,
  }) {
    final filled = urls.where((u) => u.isNotEmpty).toList();
    if (filled.isEmpty) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: ClaiColors.surface2,
          borderRadius: BorderRadius.circular(radius),
        ),
        child: ClaiIcon(ClaiIcons.queue, color: ClaiColors.inkFaint),
      );
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
              Image.network(
                artworkUrlForSize(filled[i % filled.length], 200)!,
                fit: BoxFit.cover,
                cacheWidth: 128,
                errorBuilder: (_, _, _) =>
                    Container(color: ClaiColors.surface3),
              ),
          ],
        ),
      ),
    );
  }
}

/// Baris koleksi baku (Ronde 8083, densitas R2): mosaik 56 radius 12,
/// nama Inter Tight 17, meta hitungan nyata 12 di bawah nama, tinggi
/// baris total ±72 (padding vertikal 8 + mosaik 56). Tanpa border,
/// tanpa mini waveform — playlist tidak punya waveform tunggal.
class CollectionRow extends StatelessWidget {
  final Widget mosaic;
  final String name;
  final String meta;
  final VoidCallback? onTap;
  const CollectionRow({
    super.key,
    required this.mosaic,
    required this.name,
    required this.meta,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Row(
          children: [
            mosaic,
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: displayStyle(17),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    meta,
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
          ],
        ),
      ),
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
      appBar: claiPushedAppBar(context, context.l10n.homeSavedSongs),
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
          return FiniteScrollPage(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        context.l10n.collectionSavedCount(tracks.length),
                        style: const TextStyle(
                          color: ClaiColors.inkSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    Semantics(
                      button: true,
                      label: context.l10n.a11yPlay,
                      child: PressableScale(
                        child: GestureDetector(
                          onTap: () => handler.playTracks(
                            tracks,
                            0,
                            kind: 'liked',
                            label: context.l10n.homeSavedSongs,
                          ),
                          child: Container(
                            width: 48,
                            height: 48,
                            decoration: const BoxDecoration(
                              color: ClaiColors.signal,
                              shape: BoxShape.circle,
                            ),
                            child: ClaiIcon(
                              ClaiIcons.play,
                              color: ClaiColors.onSignal,
                              size: 26,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              for (final t in tracks)
                SongRow(
                  track: t,
                  onTap: () => handler.playTracks(
                    tracks,
                    tracks.indexOf(t),
                    kind: 'liked',
                    label: context.l10n.homeSavedSongs,
                  ),
                ),
              SizedBox(height: bottomChromeClearance(context)),
            ],
          );
        },
      ),
    );
  }
}
