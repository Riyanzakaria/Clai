import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../app.dart';
import '../core/clai_icons.dart';
import '../core/tokens.dart';
import '../domain/models.dart';
import '../providers/music_provider.dart';
import '../providers/spotify/spotify_web.dart';
import 'spotify_playlist_screen.dart';
import '../l10n/l10n.dart';
import 'widgets.dart';

/// Pencarian (PRD 5.2 + Phase 2 F-02): debounce 300 ms, token L-13, kategori, riwayat lokal,
/// status gagal ≠ status tidak ditemukan.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});
  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
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

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final h = await ref.read(appDbProvider).searchHistory();
    if (mounted) setState(() => _history = h);
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

  @override
  void dispose() { _debounce?.cancel(); _controller.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final handler = ref.watch(audioHandlerProvider);
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        child: TextField(
          controller: _controller,
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
            filled: true, fillColor: ClaiColors.surface1,
            border: const OutlineInputBorder(borderSide: BorderSide.none, borderRadius: BorderRadius.all(Radius.circular(12))),
          ),
        ),
      ),
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
      return ListView(children: [
        Padding(padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
            child: Text(context.l10n.searchSuggestions, style: const TextStyle(fontWeight: FontWeight.w600, color: ClaiColors.ink))),
        for (final s in _suggestions)
          ListTile(
            leading: ClaiIcon(ClaiIcons.search, color: ClaiColors.inkFaint),
            title: Text(s, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: ClaiColors.ink)),
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
      // F2: pintu masuk playlist Spotify — tempel tautan publiknya di bidang Cari.
      final spotifyTile = ListTile(
        leading: Container(width: 48, height: 48, decoration: BoxDecoration(color: ClaiColors.surface2, borderRadius: BorderRadius.circular(8)),
            child: ClaiIcon(ClaiIcons.link, color: ClaiColors.accent)),
        title: Text(context.l10n.searchSpotifyCardTitle, style: const TextStyle(fontWeight: FontWeight.w600, color: ClaiColors.ink)),
        subtitle: Text(context.l10n.searchSpotifyCardSub,
            style: const TextStyle(color: ClaiColors.inkSecondary, fontSize: 12.5)),
      );
      if (_history.isEmpty) {
        return ListView(children: [
          spotifyTile,
          const SizedBox(height: 24),
          EmptyState(icon: ClaiIcons.search, message: context.l10n.searchEmpty),
        ]);
      }
      return ListView(children: [
        spotifyTile,
        Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 4), child: Row(children: [
          Expanded(child: Text(context.l10n.searchRecent, style: const TextStyle(fontWeight: FontWeight.w600, color: ClaiColors.ink))),
          TextButton(onPressed: () async { await ref.read(appDbProvider).clearSearchHistory(); _loadHistory(); },
              child: Text(context.l10n.searchClearAll, style: const TextStyle(color: ClaiColors.inkFaint, fontSize: 13))),
        ])),
        for (final h in _history)
          ListTile(
            leading: ClaiIcon(ClaiIcons.history, color: ClaiColors.inkFaint),
            title: Text(h, style: const TextStyle(color: ClaiColors.ink)),
            trailing: IconButton(icon: ClaiIcon(ClaiIcons.close, size: 18, color: ClaiColors.inkFaint),
                onPressed: () async { await ref.read(appDbProvider).removeSearchHistory(h); _loadHistory(); }),
            onTap: () { _controller.text = h; _run(h); },
          ),
        SizedBox(height: bottomChromeClearance(context)),
      ]);
    }
    if (res.isEmpty) {
      return EmptyState(icon: ClaiIcons.searchOff, message: context.l10n.searchNoResults);
    }
    final showSongs = _category == 'all' || _category == 'songs';
    final showAlbums = _category == 'all' || _category == 'albums';
    final showArtists = _category == 'all' || _category == 'artists';
    final showPlaylists = _category == 'all' || _category == 'playlists';
    Widget header(String s) => Padding(padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
        child: Text(s, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: ClaiColors.ink)));
    Widget albumRow(Album a, String kind) => ListTile(
          leading: CoverArt(url: a.artworkUrl, size: 48, label: a.title),
          title: Text(a.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: ClaiColors.ink, fontWeight: FontWeight.w500)),
          subtitle: Text(a.artistNames, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: ClaiColors.inkSecondary)),
          onTap: () => openContent(context, ref, kind, a.id, a.title),
        );
    return ListView(children: [
      if (_loading) const LinearProgressIndicator(color: ClaiColors.accent, backgroundColor: ClaiColors.surface3),
      if (showSongs && res.songs.isNotEmpty) ...[
        header(context.l10n.searchSongs),
        for (final t in res.songs)
          SongRow(track: t, onTap: () => handler.playTracks(res.songs, res.songs.indexWhere((x) => x.key == t.key), kind: 'search', label: context.l10n.searchResultsLabel)),
      ],
      if (showAlbums && res.albums.isNotEmpty) ...[
        header(context.l10n.searchAlbums),
        for (final a in res.albums) albumRow(a, 'album'),
      ],
      if (showArtists && res.artists.isNotEmpty) ...[
        header(context.l10n.searchArtists),
        for (final a in res.artists)
          ListTile(
            leading: CoverArt(url: a.artworkUrl, size: 48, label: a.name),
            title: Text(a.name, style: const TextStyle(color: ClaiColors.ink, fontWeight: FontWeight.w500)),
            subtitle: Text(context.l10n.searchArtists, style: const TextStyle(color: ClaiColors.inkSecondary)),
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
}
