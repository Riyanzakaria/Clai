import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/l10n.dart';

import '../app.dart';
import '../core/display_text.dart';
import '../core/tokens.dart';
import '../services/track_metadata_healer.dart';
import '../domain/models.dart';
import '../domain/taste_mirror.dart';
import 'glass.dart';
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

  /// Hitungan putar NYATA artis teratas (dari artistPlayCounts —
  /// jumlah peristiwa putar tercatat), untuk byline pita fitur.
  int _topArtistPlays = 0;
  List<Track> _artistTracks = [];
  bool _healedOnce = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = ref.read(appDbProvider);
    final artists = await db.artistPlayCounts(limit: 5);
    String? top;
    var plays = 0;
    List<Track> artistTracks = [];
    if (artists.isNotEmpty && artists.first.count >= 3) {
      top = artists.first.artistNames;
      plays = artists.first.count;
      artistTracks = (await db.tracksByArtists([
        top,
      ], limit: 10)).take(10).toList();
      if (artistTracks.isEmpty) top = null;
    }
    if (mounted) {
      setState(() {
        _topArtist = top;
        _topArtistPlays = plays;
        _artistTracks = artistTracks;
      });
    }
    // Penyembuhan metadata (Ronde Cacat Metadata): kartu rak yang artisnya
    // kosong / tanpa sampul diselesaikan sekali dari provider, lalu rak
    // dimuat ulang SEKALI — rekam lama sembuh di tempat, tanpa hapus data.
    if (!_healedOnce && artistTracks.any(TrackMetadataHealer.needsHeal)) {
      _healedOnce = true;
      final healer = ref.read(trackMetadataHealerProvider);
      final healed = await Future.wait(artistTracks.map(healer.healIfNeeded));
      if (healed.any((h) => h != null) && mounted) await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_topArtist == null || _artistTracks.isEmpty) {
      return const SizedBox.shrink();
    }
    final handler = ref.read(audioHandlerProvider);
    final title = context.l10n.shelfBecauseArtist(_topArtist ?? '');
    final artist = cleanDisplayArtist(_topArtist ?? '');
    // Ronde 8083 butir 4: pita FITUR berwajah artis (bukan rel sampul
    // biasa) — sampul besar di kiri dari trek artis itu sendiri, nama
    // artis font tampilan tegas, byline data nyata (hitungan putar tercatat),
    // lalu baris lagu-lagu artis itu (maks 3). Ketuk baris memutar
    // dengan konteks & label yang sama seperti rel lama.
    final rows = _artistTracks.take(3).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CoverArt(
                url: _artistTracks.first.artworkUrl,
                size: 96,
                label: artist,
                radius: 12,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      artist,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: displayStyle(20),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      context.l10n.homePlayCount(_topArtistPlays),
                      style: const TextStyle(
                        fontSize: 13,
                        color: ClaiColors.inkSecondary,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        for (final t in rows)
          SongRow(
            track: t,
            onTap: () => handler.playTracks(
              _artistTracks,
              _artistTracks.indexWhere((x) => x.key == t.key),
              kind: 'search',
              label: title,
            ),
          ),
      ],
    );
  }
}

class PersonalShelvesSection extends ConsumerStatefulWidget {
  const PersonalShelvesSection({super.key});
  @override
  ConsumerState<PersonalShelvesSection> createState() =>
      _PersonalShelvesSectionState();
}

class _PersonalShelvesSectionState
    extends ConsumerState<PersonalShelvesSection> {
  List<Track> _forgotten = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = ref.read(appDbProvider);
    final liked = await db.likedWithPlayCounts();
    // Ronde 8074: rak saran ini juga menghormati pengecualian selera.
    final excl = await db.tasteExclusions();
    final forgotten = liked
        .where((e) => e.plays == 0)
        .map((e) => e.track)
        .where((t) => !isTrackExcluded(t, excl))
        .take(5)
        .toList();
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title),
        for (final t in _forgotten)
          SongRow(
            track: t,
            onTap: () => handler.playTracks(
              _forgotten,
              _forgotten.indexWhere((x) => x.key == t.key),
              kind: 'search',
              label: title,
            ),
          ),
      ],
    );
  }
}
