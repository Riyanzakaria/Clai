import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app.dart';
import '../core/clai_icons.dart';
import '../core/tokens.dart';
import '../domain/models.dart';
import '../providers/spotify/spotify_web.dart';
import '../l10n/l10n.dart';
import '../services/ambient_theme.dart';
import 'cover_accent_glow.dart';
import 'widgets.dart';

/// Halaman playlist publik Spotify (F2 butir 4): metadata dibaca TANPA akun
/// lewat token web anonim; audio TIDAK dari Spotify — setiap trek dicocokkan
/// ke katalog dan yang diputar adalah hasil cocoknya. Trek yang tidak
/// tercocokkan DITANDAI jujur, tidak pernah diganti lagu lain diam-diam.
///
/// Gelombang 2 (8048): komposisi papan — kepala (kicker + nama display
/// 28 + garis asal + garis kejujuran), PANEL pencocokan (hitungan besar
/// tabular, bilah Volt = proporsi cocok persis, tombol Putar yang Cocok
/// bernada sampul diperdalam), lalu daftar Trek. Perilaku mesin
/// pencocokan (3 pekerja, prioritaskan ketukan, coba-lagi paksa) utuh;
/// tombol Putar tetap bisa diketuk selama pencocokan berjalan (perilaku
/// terbangun: memutar yang sudah cocok) — papan menggambarnya redup,
/// tetapi mengunci fungsi yang hidup bukan penyesuaian komposisi.
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
      body: _loading
          ? _withBackChip(context, const LoadingSkeleton())
          : _error != null
              ? _withBackChip(
                  context, ErrorState(message: _error!, onRetry: _load))
              : pl == null
                  ? _withBackChip(
                      context,
                      EmptyState(
                          icon: ClaiIcons.queue,
                          message: context.l10n.spUnavailable))
                  : Column(children: [
                      _header(context, pl),
                      Expanded(
                        child: ListView.builder(
                          padding: EdgeInsets.only(
                              bottom: bottomChromeClearance(context)),
                          itemCount: pl.tracks.length,
                          itemBuilder: (context, i) => _row(pl, i),
                        ),
                      ),
                    ]),
    );
  }

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

  Widget _header(BuildContext context, SpotifyPlaylistData pl) {
    final l = context.l10n;
    final matchedCount = _states.where((s) => s == _MState.matched).length;
    final doneCount = _states
        .where((s) => s == _MState.matched || s == _MState.unmatched)
        .length;
    final matching = doneCount < pl.tracks.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
              16, MediaQuery.paddingOf(context).top + 12, 16, 0),
          child: const GlassBackChip(),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DimKicker(l.spKicker),
              const SizedBox(height: 8),
              Text(
                pl.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: displayStyle(28),
              ),
              const SizedBox(height: 8),
              Text(
                l.spOwnerLine(
                    pl.totalCount, pl.ownerName.isEmpty ? 'Spotify' : pl.ownerName),
                style: const TextStyle(
                    color: ClaiColors.inkSecondary, fontSize: 13),
              ),
              const SizedBox(height: 4),
              Text(
                l.spMeta,
                style: const TextStyle(
                    color: ClaiColors.inkFaint, fontSize: 12, height: 1.4),
              ),
              if (pl.description.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  pl.description,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: ClaiColors.inkSecondary, fontSize: 13, height: 1.45),
                ),
              ],
            ],
          ),
        ),
        // PANEL PENCOCOKAN.
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: ClaiColors.surface1,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    matching
                        ? l.spMatching(matchedCount, pl.tracks.length)
                        : l.spMatched(matchedCount, pl.tracks.length),
                    maxLines: 1,
                    style: heroStyle(28),
                  ),
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: pl.tracks.isEmpty
                        ? 0
                        : matchedCount / pl.tracks.length,
                    minHeight: 6,
                    backgroundColor: ClaiColors.surface3,
                    valueColor:
                        const AlwaysStoppedAnimation<Color>(ClaiColors.accent),
                  ),
                ),
                if (pl.nonTrackItems > 0) ...[
                  const SizedBox(height: 10),
                  Text(
                    l.spSkippedItems(pl.nonTrackItems),
                    style: const TextStyle(
                        color: ClaiColors.inkFaint, fontSize: 12),
                  ),
                ],
                if (pl.truncated) ...[
                  const SizedBox(height: 6),
                  Text(
                    l.spHuge,
                    style: const TextStyle(
                        color: ClaiColors.inkFaint, fontSize: 12),
                  ),
                ],
                const SizedBox(height: 16),
                CoverAccentBuilder(
                  artworkUrl: pl.imageUrl,
                  builder: (context, tonal) {
                    final tone = tonal == null
                        ? ClaiColors.accent
                        : deepToneFromColor(tonal);
                    final onTone = onProgressTone(tone);
                    return Material(
                      color: tone,
                      borderRadius: BorderRadius.circular(999),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: _playAll,
                        child: SizedBox(
                          height: 52,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              ClaiIcon(ClaiIcons.play, size: 20, color: onTone),
                              const SizedBox(width: 8),
                              Text(
                                l.spPlayMatched,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: onTone,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 6),
          child: DimKicker(l.spSectionTracks),
        ),
      ],
    );
  }

  Widget _row(SpotifyPlaylistData pl, int i) {
    final t = pl.tracks[i];
    final st = _states[i];
    if (st == _MState.unmatched) {
      // Baris tak-cocok: diredupkan, keterangan jujur di bawah artis,
      // TIDAK pernah disembunyikan; coba-lagi paksa tetap satu ketuk
      // (dulu chip "Tak cocok", kini tombol teks di kanan).
      return InkWell(
        onTap: () => _onRowTap(i),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Row(
            children: [
              Opacity(
                opacity: 0.55,
                child: CoverArt(url: t.artworkUrl, size: 48, label: t.title, radius: 8),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Opacity(
                  opacity: 0.55,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: ClaiColors.ink),
                      ),
                      Text(
                        t.artistNames,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 13, color: ClaiColors.inkSecondary),
                      ),
                      Text(
                        context.l10n.spNoCatalog,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 12, color: ClaiColors.inkFaint),
                      ),
                    ],
                  ),
                ),
              ),
              TextButton(
                onPressed: () => _matchOne(i, force: true),
                child: Text(
                  context.l10n.commonRetry,
                  style: const TextStyle(color: ClaiColors.accent),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return EntityRow(
      artworkUrl: t.artworkUrl,
      title: t.title,
      subtitle: t.artistNames,
      trailing: switch (st) {
        _MState.matching => const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: ClaiColors.accent)),
        _MState.matched => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (t.duration != null) ...[
                Text(
                  formatDuration(t.duration!),
                  style: const TextStyle(
                    color: ClaiColors.inkFaint,
                    fontSize: 12,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(width: 8),
              ],
              ClaiIcon(ClaiIcons.check, size: 18, color: ClaiColors.accent),
            ],
          ),
        _ => Text(
            t.duration == null ? '' : formatDuration(t.duration!),
            style:
                const TextStyle(color: ClaiColors.inkFaint, fontSize: 12),
          ),
      },
      onTap: () => _onRowTap(i),
    );
  }
}
