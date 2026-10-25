import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/l10n.dart';

import '../app.dart';
import '../core/tokens.dart';
import '../domain/models.dart';
import 'widgets.dart';

/// Rak personal Beranda (F2 Batch 2): dirakit SEPENUHNYA dari data lokal —
/// riwayat putar & lagu tersimpan di perangkat. Bukan rekomendasi server.
/// Rak tidak muncul bila sinyalnya belum cukup — Beranda yang jujur tidak
/// mengarang selera dari riwayat kosong.
///
/// Ronde Poles Beranda (butir 4): rak artis teratas kini REL SAMPUL
/// ([PersonalArtistRail]) yang tampil tinggi di Beranda agar layar pertama
/// memuat sampul; seksi ini tinggal memuat rak daftar "Tersimpan tapi
/// jarang diputar".
class PersonalArtistRail extends ConsumerStatefulWidget {
  const PersonalArtistRail({super.key});
  @override
  ConsumerState<PersonalArtistRail> createState() => _PersonalArtistRailState();
}

class _PersonalArtistRailState extends ConsumerState<PersonalArtistRail> {
  String? _topArtist;
  List<Track> _artistTracks = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = ref.read(appDbProvider);
    final artists = await db.artistPlayCounts(limit: 5);
    String? top;
    List<Track> artistTracks = [];
    if (artists.isNotEmpty && artists.first.count >= 3) {
      top = artists.first.artistNames;
      artistTracks =
          (await db.tracksByArtists([top], limit: 10)).take(10).toList();
      if (artistTracks.isEmpty) top = null;
    }
    if (mounted) {
      setState(() {
        _topArtist = top;
        _artistTracks = artistTracks;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_topArtist == null || _artistTracks.isEmpty) {
      return const SizedBox.shrink();
    }
    final handler = ref.read(audioHandlerProvider);
    final title = context.l10n.shelfBecauseArtist(_topArtist ?? '');
    return CoverRail(
      title: title,
      tracks: _artistTracks,
      onPlay: (tracks, i) =>
          handler.playTracks(tracks, i, kind: 'search', label: title),
    );
  }
}

class PersonalShelvesSection extends ConsumerStatefulWidget {
  const PersonalShelvesSection({super.key});
  @override
  ConsumerState<PersonalShelvesSection> createState() => _PersonalShelvesSectionState();
}

class _PersonalShelvesSectionState extends ConsumerState<PersonalShelvesSection> {
  List<Track> _forgotten = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = ref.read(appDbProvider);
    final liked = await db.likedWithPlayCounts();
    final forgotten =
        liked.where((e) => e.plays == 0).map((e) => e.track).take(5).toList();
    if (mounted) {
      setState(() {
        _forgotten = forgotten;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_forgotten.isEmpty) return const SizedBox.shrink();
    final handler = ref.read(audioHandlerProvider);
    final title = context.l10n.shelfRarelyPlayed;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
          padding: const EdgeInsets.fromLTRB(16, 26, 16, 6),
          child: Text(title,
              style: const TextStyle(
                  fontSize: 17, fontWeight: FontWeight.w600, color: ClaiColors.ink))),
      for (final t in _forgotten)
        SongRow(
            track: t,
            onTap: () => handler.playTracks(
                _forgotten, _forgotten.indexWhere((x) => x.key == t.key),
                kind: 'search', label: title)),
    ]);
  }
}
