import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app.dart';
import '../core/clai_icons.dart';
import '../core/tokens.dart';
import '../domain/models.dart';
import '../providers/spotify/spotify_web.dart';
import '../l10n/l10n.dart';
import 'widgets.dart';

/// Halaman playlist publik Spotify (F2 butir 4): metadata dibaca TANPA akun
/// lewat token web anonim; audio TIDAK dari Spotify — setiap trek dicocokkan
/// ke YouTube Music dan yang diputar adalah hasil cocoknya. Trek yang tidak
/// tercocokkan DITANDAI jujur, tidak pernah diganti lagu lain diam-diam.
class SpotifyPlaylistScreen extends ConsumerStatefulWidget {
  final String playlistId;
  const SpotifyPlaylistScreen({super.key, required this.playlistId});
  @override
  ConsumerState<SpotifyPlaylistScreen> createState() => _SpotifyPlaylistScreenState();
}

enum _MState { unknown, matching, matched, unmatched }

class _SpotifyPlaylistScreenState extends ConsumerState<SpotifyPlaylistScreen> {
  SpotifyPlaylistData? _pl;
  String? _error;
  bool _loading = true;
  final List<_MState> _states = [];
  final List<Track?> _matched = [];
  final Queue<int> _pending = Queue<int>();
  bool _pumping = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final pl = await ref.read(spotifyProvider).getPlaylist(widget.playlistId);
      if (!mounted) return;
      setState(() {
        _pl = pl;
        _loading = false;
        _states.clear();
        _matched.clear();
        for (var i = 0; i < pl.tracks.length; i++) {
          _states.add(_MState.unknown);
          _matched.add(null);
          _pending.add(i);
        }
      });
      _pump();
    } on SpotifyProviderException catch (e) {
      if (mounted) setState(() { _loading = false; _error = e.message; });
    } catch (_) {
      if (mounted) setState(() { _loading = false; _error = context.l10n.spLoadFail; });
    }
  }

  /// Mesin pencocokan: 3 pekerja paralel atas antrean indeks; baris yang
  /// diketuk pengguna didahulukan (dimasukkan ke depan antrean oleh _matchOne
  /// lewat _prioritize).
  void _pump() {
    if (_pumping) return;
    _pumping = true;
    Future<void> worker() async {
      while (mounted && _pending.isNotEmpty) {
        final idx = _pending.removeFirst();
        if (_states[idx] != _MState.unknown) continue;
        await _matchOne(idx);
      }
    }
    Future.wait([worker(), worker(), worker()]).whenComplete(() => _pumping = false);
  }

  Future<void> _matchOne(int idx, {bool force = false}) async {
    final pl = _pl;
    if (pl == null || idx < 0 || idx >= pl.tracks.length) return;
    if (_states[idx] == _MState.matching) return;
    setState(() => _states[idx] = _MState.matching);
    final m = await ref.read(trackMatcherProvider).match(pl.tracks[idx], forceRetry: force);
    if (!mounted) return;
    setState(() {
      _matched[idx] = m;
      _states[idx] = m == null ? _MState.unmatched : _MState.matched;
    });
  }

  void _prioritize(int idx) {
    if (_states[idx] != _MState.unknown) return;
    _pending.remove(idx);
    _pending.addFirst(idx);
    _pump();
  }

  Future<void> _onRowTap(int idx) async {
    switch (_states[idx]) {
      case _MState.matched:
        _playFrom(idx);
        break;
      case _MState.unknown:
        _prioritize(idx);
        await _matchOne(idx);
        if (_states[idx] == _MState.matched) { _playFrom(idx); } else { _snack(context.l10n.spNotFound); }
        break;
      case _MState.matching:
        _snack(context.l10n.spMatchingThis);
        break;
      case _MState.unmatched:
        _snack(context.l10n.spNotFoundRetry);
        break;
    }
  }

  void _playFrom(int idx) {
    final pl = _pl!;
    final handler = ref.read(audioHandlerProvider);
    final playable = <Track>[];
    var startAt = 0;
    for (var i = 0; i < pl.tracks.length; i++) {
      if (_states[i] == _MState.matched && _matched[i] != null) {
        if (i == idx) startAt = playable.length;
        playable.add(_matched[i]!);
      }
    }
    if (playable.isEmpty) { _snack(context.l10n.spNoneMatched); return; }
    handler.playTracks(playable, startAt, kind: 'playlist', id: 'spotify:${pl.id}', label: context.l10n.spContext(pl.name));
  }

  void _playAll() {
    final firstMatched = _states.indexWhere((s) => s == _MState.matched);
    if (firstMatched < 0) {
      _pump();
      _snack(context.l10n.spPlayWhileMatching);
      return;
    }
    _playFrom(firstMatched);
  }

  void _snack(String msg) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 3)));
  }

  @override
  Widget build(BuildContext context) {
    final pl = _pl;
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.spTitle, maxLines: 1, overflow: TextOverflow.ellipsis)),
      body: _loading
          ? const LoadingSkeleton()
          : _error != null
              ? ErrorState(message: _error!, onRetry: _load)
              : pl == null
                  ? EmptyState(icon: ClaiIcons.queue, message: context.l10n.spUnavailable)
                  : Column(children: [
                      _header(pl),
                      Expanded(child: ListView.builder(
                        padding: EdgeInsets.only(bottom: bottomChromeClearance(context)),
                        itemCount: pl.tracks.length,
                        itemBuilder: (context, i) => _row(pl, i),
                      )),
                    ]),
    );
  }

  Widget _header(SpotifyPlaylistData pl) {
    final matchedCount = _states.where((s) => s == _MState.matched).length;
    final doneCount = _states.where((s) => s == _MState.matched || s == _MState.unmatched).length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          CoverArt(url: pl.imageUrl, size: 110, label: pl.name, radius: 12),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(pl.name, maxLines: 3, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: ClaiColors.ink, height: 1.2)),
            const SizedBox(height: 6),
            Text(context.l10n.spOwnerLine(pl.totalCount, pl.ownerName.isEmpty ? 'Spotify' : pl.ownerName),
                style: const TextStyle(color: ClaiColors.inkSecondary, fontSize: 13)),
            const SizedBox(height: 6),
            Text(context.l10n.spMeta,
                style: const TextStyle(color: ClaiColors.inkFaint, fontSize: 12, height: 1.4)),
          ])),
        ]),
        if (pl.description.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(pl.description, maxLines: 3, overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: ClaiColors.inkSecondary, fontSize: 13, height: 1.45)),
        ],
        const SizedBox(height: 10),
        Row(children: [
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: ClaiColors.accent, foregroundColor: ClaiColors.onAccent),
            onPressed: _playAll,
            icon: ClaiIcon(ClaiIcons.play, size: 18, color: ClaiColors.onAccent),
            label: Text(context.l10n.spPlayMatched),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(
              doneCount < pl.tracks.length
                  ? context.l10n.spMatching(matchedCount, pl.tracks.length)
                  : context.l10n.spMatched(matchedCount, pl.tracks.length),
              style: const TextStyle(color: ClaiColors.inkSecondary, fontSize: 12.5))),
        ]),
        if (pl.nonTrackItems > 0)
          Padding(padding: const EdgeInsets.only(top: 6),
              child: Text(context.l10n.spSkippedItems(pl.nonTrackItems),
                  style: const TextStyle(color: ClaiColors.inkFaint, fontSize: 12))),
        if (pl.truncated)
          Padding(padding: const EdgeInsets.only(top: 6),
              child: Text(context.l10n.spHuge,
                  style: const TextStyle(color: ClaiColors.inkFaint, fontSize: 12))),
      ]),
    );
  }

  Widget _row(SpotifyPlaylistData pl, int i) {
    final t = pl.tracks[i];
    final st = _states[i];
    return ListTile(
      leading: CoverArt(url: t.artworkUrl, size: 48, label: t.title, radius: 6),
      title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: ClaiColors.ink, fontWeight: FontWeight.w500)),
      subtitle: Text(t.artistNames, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: ClaiColors.inkSecondary)),
      trailing: switch (st) {
        _MState.matching => const SizedBox(width: 18, height: 18,
            child: CircularProgressIndicator(strokeWidth: 2, color: ClaiColors.accent)),
        _MState.unmatched => ActionChip(
            label: Text(context.l10n.spNoMatch, style: const TextStyle(fontSize: 11.5, color: ClaiColors.warning)),
            backgroundColor: ClaiColors.surface2, side: BorderSide.none,
            onPressed: () => _matchOne(i, force: true)),
        _MState.matched => ClaiIcon(ClaiIcons.check, size: 18, color: ClaiColors.accent),
        _MState.unknown => Text(t.duration == null ? '' : formatDuration(t.duration!),
            style: const TextStyle(color: ClaiColors.inkFaint, fontSize: 12)),
      },
      onTap: () => _onRowTap(i),
    );
  }
}
