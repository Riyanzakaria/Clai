import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../app.dart';
import '../core/clai_icons.dart';
import '../core/tokens.dart';
import '../domain/models.dart';
import '../providers/music_provider.dart';
import '../providers/spotify/spotify_web.dart';
import '../providers/ytmusic/innertube.dart' show exploreTitleId;
import 'mood_screen.dart';
import 'spotify_playlist_screen.dart';
import '../l10n/l10n.dart';
import '../services/capture_service.dart';
import 'capture_sheet.dart';
import 'glass.dart';
import 'widgets.dart';

/// Daftar konteks untuk ketukan lagu di hasil pencarian.
///
/// Keputusan pemilik 2026-10-26 (mutlak): mengetuk lagu di HASIL PENCARIAN
/// menjadikan HANYA lagu itu konteks putar — bukan seluruh daftar hasil.
/// Daftar hasil cari adalah daftar temu (lagu mirip nama, cover, versi lain),
/// bukan urutan kurasi seperti playlist/album; menjadikannya antrean berarti
/// antrean terisi lagu di luar selera pengguna. Kelanjutan sesudah lagu itu
/// adalah pekerjaan Putar Otomatis (benih sesi = lagu yang diketuk), sama
/// seperti konteks satu-lagu lain (suara, Lanjut Besok). Titik ketuk lain
/// (playlist, album, artis, Koleksi, rak) TIDAK memakai fungsi ini — mereka
/// tetap konteks daftar penuh.
List<Track> searchTapTracks(Track tapped) => [tapped];

/// A-3 lanjutan (build 2018): apakah seksi filter yang sedang terpilih
/// kosong? Kasus celahnya: total hasil TIDAK kosong tetapi seksi terpilih
/// kosong (mis. filter Album atas kata kunci acak) — dulu layar merender
/// nol baris (hitam kosong tanpa pesan). Keadaan itu kini mendapat
/// EmptyState baku yang sama dengan hasil total kosong.
bool selectedSearchSectionEmpty(String category, SearchResults res) =>
    switch (category) {
      'songs' => res.songs.isEmpty,
      'albums' => res.albums.isEmpty,
      'artists' => res.artists.isEmpty,
      'playlists' => res.playlists.isEmpty,
      _ => res.isEmpty,
    };

/// Satu kartu tangga lagu untuk rel Charts papan 04: item NYATA dari umpan
/// Charts sumber (playlist/album), plus judul rak asalnya untuk subjudul
/// cadangan. Murni & diuji.
typedef ChartCard = ({Album item, String kind, String shelfTitle});

/// Ratakan rak-rak umpan Charts menjadi kartu rel papan 04: playlist dulu
/// (tangga lagu sumber berbentuk playlist), lalu album; dedupe per id;
/// rak tanpa kartu tidak menyumbang apa pun.
List<ChartCard> chartCardsOf(List<ExploreShelf> shelves) {
  final out = <ChartCard>[];
  final seen = <String>{};
  for (final s in shelves) {
    for (final p in s.playlists) {
      if (seen.add(p.id)) {
        out.add((item: p, kind: 'playlist', shelfTitle: s.title));
      }
    }
  }
  for (final s in shelves) {
    for (final a in s.albums) {
      if (seen.add(a.id)) {
        out.add((item: a, kind: 'album', shelfTitle: s.title));
      }
    }
  }
  return out;
}

/// Ukuran huruf judul CADANGAN kartu Charts (butir (c), 8045):
/// kartu tanpa sampul menampilkan judulnya besar — teks Flutter
/// mematahkan kata yang lebih lebar dari barisnya DI TENGAH KATA
/// ("INDONESI A" pada bukti 8043). Ukuran diturunkan sampai kata
/// terpanjang judul muat selebar wajah kartu. Faktor lebar glyph
/// dikalibrasi ulang pada Ronde Ganti Font (8049): Clash Display 600
/// terukur 0,61–0,65 × ukuran untuk kata kapital khas judul Charts
/// (INDONESIA 0,613 · TRENDING 0,651 · INTERNASIONAL 0,636) — faktor
/// aman 0,68. (Space Grotesk lama memakai 0,62.) Lantai 17, plafon 27.
double chartFallbackTitleSize(String title) {
  var longest = 0;
  for (final w in title.split(RegExp(r'\s+'))) {
    if (w.length > longest) longest = w.length;
  }
  if (longest == 0) return 27;
  final fit = 136 / (longest * 0.68);
  return fit.clamp(17, 27).toDouble();
}

/// Gradasi kaya kartu Charts (papan 04) — gaun visual saja; label dan
/// tujuan kartu tetap judul & konten NYATA sumber. Berputar per indeks.
const chartCardGradients = <(Color, Color)>[
  (Color(0xFF9BC53D), Color(0xFF5B8C2A)),
  (Color(0xFFC94F5E), Color(0xFF7E2A35)),
  (Color(0xFF4E8FB8), Color(0xFF2C5A7C)),
  (Color(0xFF7E6BB8), Color(0xFF4A3A75)),
  (Color(0xFFC46A4A), Color(0xFF7E3E28)),
  (Color(0xFF3FA08C), Color(0xFF256354)),
];

/// Pencarian (PRD 5.2 + Phase 2 F-02): debounce 300 ms, token L-13, kategori, riwayat lokal,
/// status gagal ≠ status tidak ditemukan.
///
/// Komposisi papan 04 (Ronde Koreksi Komposisi F3): judul display "Cari"
/// + ikon Tangkap kanan atas; bidang cari PIL stadium; keadaan telusur
/// (belum mengetik) adalah JELAJAH — rel kartu tangga lagu besar dari
/// umpan Charts sumber + kisi ubin Mood & Genre dari halaman kategori
/// sumber. Chip sumber (Katalog Utama/Indie) TIDAK dibuat: sumber indie
/// belum ada (Workstream B), chip mati dilarang — chip tipe hasil tetap
/// tampil pada keadaan hasil/saran.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});
  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  Timer? _debounce;
  int _token = 0;
  String _category = 'all';
  SearchResults? _results;
  bool _loading = false;
  String? _error;
  bool _degraded = false;
  List<String> _history = [];
  // D-23: saran pencarian dari provider (searchSuggestions sudah ada di
  // lapisan provider sejak F1 tetapi tidak pernah dipanggil UI).
  List<String> _suggestions = [];
  int _suggestToken = 0;
  // Keadaan telusur Jelajah (papan 04): dua umpan INDEPENDEN — tangga
  // lagu & mood/genre — kegagalan satu tidak menyeret yang lain (pola
  // JelajahSection Beranda).
  List<ExploreShelf>? _chartShelves;
  bool _chartsLoading = true;
  bool _chartsFailed = false;
  List<MoodGenreSection>? _moodSections;
  bool _moodsLoading = true;
  bool _moodsFailed = false;

  @override
  void initState() {
    super.initState();
    _loadHistory();
    _loadCharts();
    _loadMoods();
  }

  Future<void> _loadHistory() async {
    final h = await ref.read(appDbProvider).searchHistory();
    if (mounted) setState(() => _history = h);
  }

  Future<void> _loadCharts() async {
    setState(() {
      _chartsLoading = true;
      _chartsFailed = false;
    });
    try {
      final shelves = await ref.read(ytMusicProvider).getChartsFeed();
      if (mounted) {
        setState(() {
          _chartShelves = shelves;
          _chartsLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _chartsFailed = true;
          _chartsLoading = false;
        });
      }
    }
  }

  Future<void> _loadMoods() async {
    setState(() {
      _moodsLoading = true;
      _moodsFailed = false;
    });
    try {
      final sections = await ref.read(ytMusicProvider).getMoodGenres();
      if (mounted) {
        setState(() {
          _moodSections = sections;
          _moodsLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _moodsFailed = true;
          _moodsLoading = false;
        });
      }
    }
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    final q = v.trim();
    if (q.isEmpty) {
      setState(() { _results = null; _error = null; _loading = false; _suggestions = []; });
      return;
    }
    setState(() => _loading = true);
    _debounce = Timer(const Duration(milliseconds: 300), () => _run(q));
    // D-23: saran menyusul lebih cepat dari pencarian penuh (150 ms) dan
    // hanya tampil selama hasil belum ada; token membuang saran basi.
    final mySuggest = ++_suggestToken;
    Timer(const Duration(milliseconds: 150), () async {
      if (!mounted || mySuggest != _suggestToken) return;
      final s = await ref.read(ytMusicProvider).searchSuggestions(q);
      if (!mounted || mySuggest != _suggestToken) return;
      setState(() => _suggestions = s.take(8).toList());
    });
  }

  Future<void> _run(String q) async {
    // F2 butir 4: tautan Spotify yang ditempel di bidang Cari membuka halaman
    // playlist Spotify (metadata anonim + pencocokan), BUKAN pencarian teks.
    final link = spotifyLinkOf(q);
    if (link != null) {
      if (link.playlistId != null) {
        _controller.clear();
        setState(() { _results = null; _loading = false; _error = null; _degraded = false; });
        await Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => SpotifyPlaylistScreen(playlistId: link.playlistId!)));
      } else {
        setState(() { _loading = false; });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(context.l10n.searchSpotifyOnlySnack)));
      }
      return;
    }
    final myToken = ++_token;
    try {
      final res = await ref.read(ytMusicProvider).search(q);
      if (!mounted || myToken != _token) return; // L-13: hasil basi dibuang
      await ref.read(appDbProvider).addSearchHistory(q);
      setState(() { _results = res; _loading = false; _error = null; _degraded = false; });
      _loadHistory();
    } on ProviderDegradedException catch (e) {
      if (!mounted || myToken != _token) return;
      setState(() { _loading = false; _degraded = true; _error = e.message; _results = null; });
    } catch (e) {
      if (!mounted || myToken != _token) return;
      setState(() { _loading = false; _error = context.l10n.searchNetworkError; _degraded = false; _results = null; });
    }
  }

  /// Butir 6 F2.5: pintu Tangkap terpadu — satu lembar pilihan dengan
  /// dua masukan menuju pipa Tangkap yang sama: tempel tautan/teks
  /// (dialog bersama dengan pintu Pengaturan) atau pilih gambar dari
  /// galeri (pemilih foto Android; gerbang model OCR di lembar
  /// Tangkapan berlaku sama). Kini pintunya adalah ikon Tangkap di
  /// kepala layar (papan 04); lembarnya memakai tata bahasa lembar baku
  /// (pegangan + judul seksi).
  Future<void> _openCaptureDoor() async {
    final choice = await showModalBottomSheet<String>(
      context: claiRootContext(context),
      backgroundColor: ClaiColors.surface1,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 8),
          const SheetHandle(),
          const SizedBox(height: 6),
          ListTile(
            minTileHeight: 56,
            contentPadding: const EdgeInsets.symmetric(horizontal: 20),
            leading: tonalIconBox(ClaiIcons.link, size: 40, iconSize: 20),
            title: Text(ctx.l10n.captureLinkTitle,
                style: const TextStyle(color: ClaiColors.ink, fontSize: 17)),
            onTap: () => Navigator.of(ctx).pop('text'),
          ),
          ListTile(
            minTileHeight: 56,
            contentPadding: const EdgeInsets.symmetric(horizontal: 20),
            leading: tonalIconBox(ClaiIcons.album, size: 40, iconSize: 20),
            title: Text(ctx.l10n.capturePickImage,
                style: const TextStyle(color: ClaiColors.ink, fontSize: 17)),
            onTap: () => Navigator.of(ctx).pop('image'),
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (!mounted || choice == null) return;
    if (choice == 'text') {
      await openCaptureTextInput(context);
    } else {
      final picked = await CaptureService.pickCaptureImage();
      if (picked != null && mounted) {
        openCaptureSheet(context, imageUri: picked);
      }
    }
  }

  @override
  void dispose() { _debounce?.cancel(); _controller.dispose(); _focusNode.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final handler = ref.watch(audioHandlerProvider);
    // DS v4.0: kolom cari = kaca bertinta saat Tema Dinamis menyala;
    // tema mati → isian surface-1 v3.1 persis. Bentuknya kini PIL
    // stadium (papan 04), bukan persegi membulat 12.
    final ambOn =
        ref.watch(ambientControllerProvider.select((s) => s.enabled));
    final hasQuery = _controller.text.trim().isNotEmpty;
    final field = TextField(
          controller: _controller,
          focusNode: _focusNode,
          onChanged: _onChanged,
          onSubmitted: (v) { if (v.trim().isNotEmpty) _run(v.trim()); },
          style: const TextStyle(color: ClaiColors.ink),
          decoration: InputDecoration(
            hintText: context.l10n.searchHint,
            hintStyle: const TextStyle(color: ClaiColors.inkFaint),
            prefixIcon: ClaiIcon(ClaiIcons.search, color: ClaiColors.inkSecondary),
            suffixIcon: _controller.text.isEmpty ? null : IconButton(
                icon: ClaiIcon(ClaiIcons.close, color: ClaiColors.inkSecondary),
                onPressed: () { _controller.clear(); _onChanged(''); }),
            filled: true, fillColor: ambOn ? Colors.transparent : ClaiColors.surface1,
            contentPadding: const EdgeInsets.symmetric(vertical: 16),
            border: const OutlineInputBorder(borderSide: BorderSide.none, borderRadius: BorderRadius.all(Radius.circular(999))),
          ),
        );
    return Column(children: [
      // Kepala papan 04: judul display + ikon Tangkap (pintu Tangkap
      // terpadu kini tinggal di sini; kartu pintunya pensiun).
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 2),
        child: Row(children: [
          Expanded(
            child: Text(context.l10n.navSearch, style: displayStyle(36)),
          ),
          IconButton(
            icon: ClaiIcon(ClaiIcons.capture, color: ClaiColors.ink, size: 26),
            tooltip: context.l10n.searchCaptureTitle,
            onPressed: _openCaptureDoor,
          ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: ambOn
            ? GlassSurface(radius: 999, child: field)
            : field,
      ),
      // Chip tipe hasil: hanya pada keadaan mengetik/hasil. Keadaan
      // telusur bebas chip — chip sumber papan (Katalog Utama/Indie)
      // ditunda sampai sumber indie benar-benar ada (Workstream B).
      if (hasQuery)
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            for (final c in ['all', 'songs', 'albums', 'artists', 'playlists'])
              Padding(padding: const EdgeInsets.only(right: 8), child: ChoiceChip(
                label: Text(switch (c) {
                  'songs' => context.l10n.searchSongs,
                  'albums' => context.l10n.searchAlbums,
                  'artists' => context.l10n.searchArtists,
                  'playlists' => context.l10n.searchPlaylists,
                  _ => context.l10n.searchAll,
                }),
                selected: _category == c,
                onSelected: (_) => setState(() => _category = c),
                selectedColor: ClaiColors.accent,
                labelStyle: TextStyle(color: _category == c ? ClaiColors.onAccent : ClaiColors.ink, fontSize: 13, fontWeight: FontWeight.w500),
                backgroundColor: ClaiColors.surface2, side: BorderSide.none,
              )),
          ]),
        ),
      const SizedBox(height: 8),
      Expanded(child: _body(handler)),
    ]);
  }

  Widget _body(dynamic handler) {
    // D-23: daftar saran saat mengetik (sebelum hasil penuh tiba).
    if (_results == null && _suggestions.isNotEmpty && _error == null && !_degraded) {
      return FiniteScrollPage(children: [
        SectionHeader(context.l10n.searchSuggestions,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4)),
        for (final s in _suggestions)
          EntityRow(
            leading: tonalIconBox(ClaiIcons.search,
                size: 38, iconSize: 18, color: ClaiColors.inkSecondary),
            title: s,
            onTap: () {
              _controller.text = s;
              _run(s);
            },
          ),
        if (_loading) const LinearProgressIndicator(color: ClaiColors.accent, backgroundColor: ClaiColors.surface3),
        SizedBox(height: bottomChromeClearance(context)),
      ]);
    }
    if (_loading && _results == null) return const LoadingSkeleton();
    if (_degraded) {
      return ErrorState(message: context.l10n.searchSourceBroken, onRetry: () => _run(_controller.text.trim()));
    }
    if (_error != null) return ErrorState(message: _error!, onRetry: () => _run(_controller.text.trim()));
    final res = _results;
    if (res == null) {
      return _browseBody();
    }
    if (res.isEmpty) {
      // Audit UX 2017: keadaan kosong kini memberi jalan keluar satu ketuk
      // (hapus kata kunci & kembali ke keadaan awal Cari), bukan jalan buntu.
      return EmptyState(
        icon: ClaiIcons.searchOff,
        message: context.l10n.searchNoResults,
        actionLabel: context.l10n.searchClearQuery,
        onAction: () { _controller.clear(); _onChanged(''); },
      );
    }
    if (_category != 'all' && selectedSearchSectionEmpty(_category, res)) {
      // A-3 lanjutan (build 2018): seksi filter terpilih kosong padahal
      // hasil lain ada — EmptyState yang sama, bukan daftar nol baris.
      return EmptyState(
        icon: ClaiIcons.searchOff,
        message: context.l10n.searchNoResults,
        actionLabel: context.l10n.searchClearQuery,
        onAction: () { _controller.clear(); _onChanged(''); },
      );
    }
    final showSongs = _category == 'all' || _category == 'songs';
    final showAlbums = _category == 'all' || _category == 'albums';
    final showArtists = _category == 'all' || _category == 'artists';
    final showPlaylists = _category == 'all' || _category == 'playlists';
    // Kepala seksi bersama: kicker Volt saat tema menyala, headline
    // klasik saat mati — sama seperti Beranda.
    Widget header(String s) => SectionHeader(s,
        padding: const EdgeInsets.fromLTRB(16, 22, 16, 6));
    Widget albumRow(Album a, String kind) {
      // Byline baris playlist = nama kurator/kanal; nama kanal platform
      // sendiri disaring (aturan merek) → label jenis yang jujur.
      var sub = a.artistNames;
      if (kind == 'playlist' && brandSafeByline(sub).isEmpty) {
        sub = context.l10n.searchPlaylists;
      }
      return EntityRow(
        artworkUrl: a.artworkUrl,
        title: a.title,
        subtitle: sub,
        onTap: () => openContent(context, ref, kind, a.id, a.title),
      );
    }
    return FiniteScrollPage(children: [
      if (_loading) const LinearProgressIndicator(color: ClaiColors.accent, backgroundColor: ClaiColors.surface3),
      if (showSongs && res.songs.isNotEmpty) ...[
        header(context.l10n.searchSongs),
        for (final t in res.songs)
          SongRow(track: t, onTap: () => handler.playTracks(searchTapTracks(t), 0, kind: 'search', label: context.l10n.searchResultsLabel)),
      ],
      if (showAlbums && res.albums.isNotEmpty) ...[
        header(context.l10n.searchAlbums),
        for (final a in res.albums) albumRow(a, 'album'),
      ],
      if (showArtists && res.artists.isNotEmpty) ...[
        header(context.l10n.searchArtists),
        for (final a in res.artists)
          EntityRow(
            artworkUrl: a.artworkUrl,
            title: a.name,
            // Audit 8047: subjudul "Artists" yang sama di SETIAP baris
            // bukan data — provider tak memberi data pendengar, jadi
            // subjudul disembunyikan daripada diisi kata berulang.
            round: true,
            onTap: () => openContent(context, ref, 'artist', a.id, a.name),
          ),
      ],
      if (showPlaylists && res.playlists.isNotEmpty) ...[
        header(context.l10n.searchPlaylists),
        for (final a in res.playlists) albumRow(a, 'playlist'),
      ],
      SizedBox(height: bottomChromeClearance(context)),
    ]);
  }

  /// Keadaan telusur = JELAJAH (papan 04; urutan diperbarui butir
  /// (b) Ronde Sapuan 8045): pintu Spotify → Charts → Mood & Genre
  /// → Riwayat. Tiap umpan menyatakan keadaan
  /// muat/gagalnya sendiri (DS 6.12 sebagian); tidak ada kartu/ubin
  /// yang menunjuk konten karangan — semua label & tujuan dari sumber.
  Widget _browseBody() {
    final l = context.l10n;
    final chartCards =
        _chartShelves == null ? const <ChartCard>[] : chartCardsOf(_chartShelves!);
    final moodItems = <MoodGenreItem>[
      if (_moodSections != null)
        for (final s in _moodSections!) ...s.items,
    ];
    Widget feedFail(String sourceName, VoidCallback retry) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
          child: Row(children: [
            ClaiIcon(ClaiIcons.warning, size: 16, color: ClaiColors.warning),
            const SizedBox(width: 8),
            Expanded(
              child: Text(l.jelajahShelfFail(sourceName),
                  style: const TextStyle(color: ClaiColors.inkSecondary, fontSize: 13)),
            ),
            TextButton(
              onPressed: retry,
              child: Text(l.commonRetry, style: const TextStyle(color: ClaiColors.accent)),
            ),
          ]),
        );
    Widget feedLoading() => Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Row(children: [
            const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: ClaiColors.accent)),
            const SizedBox(width: 10),
            Text(l.jelajahLoading,
                style: const TextStyle(color: ClaiColors.inkSecondary, fontSize: 13)),
          ]),
        );
    // Rak tangga lagu tanpa kartu (wilayah yang charts-nya berbentuk
    // daftar trek): tampilkan trek rak pertamanya — konten NYATA yang
    // sama, bukan klaim gagal palsu dan bukan seksi yang hilang diam-diam.
    final chartTrackShelf = _chartShelves
        ?.where((s) => s.tracks.isNotEmpty)
        .firstOrNull;
    final chartsVisible =
        _chartsLoading || _chartsFailed || chartCards.isNotEmpty || chartTrackShelf != null;
    return FiniteScrollPage(children: [
      // ---- Pintu Spotify (butir terbawa (b), Ronde Sapuan 8045):
      // pemilik memvonis letak lama (paling bawah telusur) "gaakan
      // keliatan" — pintu kini TEPAT di bawah bidang cari pil,
      // sebelum Charts. Mengetuknya tetap memfokuskan bidang cari
      // untuk menempel tautan (perilaku Audit UX 2017). ----
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 2, 16, 4),
        child: Material(
          color: ClaiColors.surface1,
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          child: ListTile(
            leading: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: ClaiColors.surface2,
                borderRadius: BorderRadius.circular(12),
              ),
              child: ClaiIcon(ClaiIcons.link, color: ClaiColors.accent),
            ),
            title: Text(l.searchSpotifyCardTitle,
                style: const TextStyle(fontWeight: FontWeight.w600, color: ClaiColors.ink)),
            subtitle: Text(l.searchSpotifyCardSub,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: ClaiColors.inkSecondary, fontSize: 13)),
            onTap: () => _focusNode.requestFocus(),
          ),
        ),
      ),
      // ---- Charts · Minggu Ini (papan 04) ----
      if (chartsVisible) ...[
        SectionHeader(l.searchChartsKicker,
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10)),
        if (_chartsLoading)
          feedLoading()
        else if (_chartsFailed)
          feedFail(l.jelajahCharts, _loadCharts)
        else if (chartCards.isNotEmpty)
          SizedBox(
            height: 226,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: chartCards.length,
              separatorBuilder: (_, __) => const SizedBox(width: 14),
              itemBuilder: (context, i) => _chartCard(chartCards[i], i),
            ),
          )
        else if (chartTrackShelf != null)
          for (var i = 0; i < chartTrackShelf.tracks.length && i < 5; i++)
            SongRow(
              track: chartTrackShelf.tracks[i],
              onTap: () => ref.read(audioHandlerProvider).playTracks(
                  chartTrackShelf.tracks, i,
                  kind: 'search',
                  label: l.jelajahShelfTitle(exploreTitleId(chartTrackShelf.title))),
            ),
      ],
      // ---- Mood & Genre (papan 04) ----
      SectionHeader(l.searchMoodGenreKicker,
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 10)),
      if (_moodsLoading)
        feedLoading()
      else if (_moodsFailed || moodItems.isEmpty)
        feedFail(l.searchMoodGenreKicker, _loadMoods)
      else
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.95,
            ),
            itemCount: moodItems.length,
            itemBuilder: (context, i) => _moodTile(moodItems[i]),
          ),
        ),
      // ---- Riwayat pencarian (tetap ada; di bawah rak penemuan) ----
      if (_history.isNotEmpty) ...[
        SectionHeader(l.searchRecent,
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 4),
            trailing: TextButton(
                onPressed: () async {
                  await ref.read(appDbProvider).clearSearchHistory();
                  _loadHistory();
                },
                child: Text(l.searchClearAll,
                    style: const TextStyle(color: ClaiColors.inkFaint, fontSize: 13)))),
        for (final h in _history)
          EntityRow(
            leading: tonalIconBox(ClaiIcons.history,
                size: 38, iconSize: 18, color: ClaiColors.inkSecondary),
            title: h,
            trailing: IconButton(
                icon: ClaiIcon(ClaiIcons.close, size: 18, color: ClaiColors.inkFaint),
                onPressed: () async {
                  await ref.read(appDbProvider).removeSearchHistory(h);
                  _loadHistory();
                }),
            onTap: () {
              _controller.text = h;
              _run(h);
            },
          ),
      ] else if (!_chartsLoading && !_moodsLoading && _chartsFailed && _moodsFailed)
        Padding(
          padding: const EdgeInsets.only(top: 24),
          child: EmptyState(icon: ClaiIcons.search, message: l.searchEmpty),
        ),
      SizedBox(height: bottomChromeClearance(context)),
    ]);
  }

  /// Kartu tangga lagu besar bertipografi (papan 04): wajah kartu =
  /// judul NYATA item dalam huruf display besar; di bawahnya judul +
  /// byline sumber (atau judul raknya). Ketuk membuka halaman kontennya.
  Widget _chartCard(ChartCard card, int index) {
    final (top, bottom) = chartCardGradients[index % chartCardGradients.length];
    final item = card.item;
    final byline = brandSafeByline(item.artistNames.trim());
    final sub = byline.isNotEmpty ? byline : exploreTitleId(card.shelfTitle);
    final hasArt = item.artworkUrl != null && item.artworkUrl!.isNotEmpty;
    return PressableScale(
      child: GestureDetector(
        onTap: () => openContent(context, ref, card.kind, item.id, item.title),
        child: SizedBox(
          width: 168,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Wajah kartu (butir terbawa (c), putusan pemilik
              // 2026-11-10 09:28 "Kartu Charts pakai sampul asli"):
              // sampul NYATA item dari umpan Charts. Gradasi tipografi
              // papan 04 kini HANYA cadangan untuk item tanpa sampul —
              // dan judul cadangannya diskalakan FittedBox agar tidak
              // lagi patah di tengah kata ("INDONESI A").
              if (hasArt)
                CoverArt(url: item.artworkUrl, size: 168, label: item.title, radius: 20)
              else
                Container(
                  width: 168,
                  height: 168,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [top, bottom],
                    ),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: Text(
                      item.title.toUpperCase(),
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: displayStyle(chartFallbackTitleSize(item.title))
                          .copyWith(
                        color: Colors.white.withValues(alpha: 0.92),
                        height: 1.12,
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 10),
              Text(
                item.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: ClaiColors.ink,
                ),
              ),
              Text(
                sub,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, color: ClaiColors.inkSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Ubin Mood & Genre (papan 04): gradasi dari warna garis khas sumber,
  /// label = judul kategori sumber; ketuk membuka halaman kategorinya.
  Widget _moodTile(MoodGenreItem item) {
    final (top, bottom) = moodTileGradient(item.stripeColor);
    return PressableScale(
      child: GestureDetector(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => MoodScreen(item: item)),
        ),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [top, bottom],
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Align(
            alignment: Alignment.bottomLeft,
            child: Text(
              item.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.white,
                shadows: [Shadow(color: Color(0x66000000), blurRadius: 6)],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
