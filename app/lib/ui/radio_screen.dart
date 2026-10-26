import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app.dart';
import '../core/clai_icons.dart';
import '../core/tokens.dart';
import '../domain/models.dart';
import '../l10n/l10n.dart';
import '../player/similarity.dart';
import 'widgets.dart';

/// Halaman Radio Lagu (F2.5, menggantikan radio ambil-alih-antrean):
/// mengetuk "Mulai Radio Lagu" MEMBUKA halaman ini — bangkitan radio dari
/// satu lagu benih, tampil seperti halaman playlist. Membuka halaman TIDAK
/// menyentuh pemutaran yang sedang berjalan sama sekali (pemuatan daftar
/// adalah panggilan provider murni); sesi radio baru dimulai saat pengguna
/// menekan tombol Putar (benih diputar, mesin sesi radio yang ada) atau
/// mengetuk satu item daftar (item itu diputar, jangkar benih tetap lagu
/// asal halaman).
class RadioScreen extends ConsumerStatefulWidget {
  final Track seed;
  const RadioScreen({super.key, required this.seed});
  @override
  ConsumerState<RadioScreen> createState() => _RadioScreenState();
}

class _RadioScreenState extends ConsumerState<RadioScreen> {
  List<Track> _tracks = [];
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final raw = await ref
          .read(ytMusicProvider)
          .getRelated(widget.seed)
          .timeout(const Duration(seconds: 25));
      final gated = gateRadioBatch(widget.seed, raw);
      if (mounted) {
        setState(() {
          _tracks = gated;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = context.l10n.radioLoadFailed;
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final handler = ref.watch(audioHandlerProvider);
    final seed = widget.seed;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          context.l10n.radioPageTitle(seed.title),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: _loading
          ? const LoadingSkeleton()
          : _error != null
          ? ErrorState(message: _error!, onRetry: _load)
          : ListView(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CoverArt(
                        url: seed.artworkUrl,
                        size: 120,
                        label: seed.title,
                        radius: 12,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(seed.title, style: displayStyle(19)),
                            if (seed.artistNames.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  seed.artistNames,
                                  style: const TextStyle(
                                    color: ClaiColors.inkSecondary,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                context.l10n.radioGeneratedFrom,
                                style: const TextStyle(
                                  color: ClaiColors.inkFaint,
                                  fontSize: 12.5,
                                ),
                              ),
                            ),
                            if (_tracks.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  context.l10n.contentCountLine(
                                    _tracks.length,
                                    formatDuration(
                                      _tracks.fold<Duration>(
                                        Duration.zero,
                                        (a, t) =>
                                            a + (t.duration ?? Duration.zero),
                                      ),
                                    ),
                                  ),
                                  style: const TextStyle(
                                    color: ClaiColors.inkFaint,
                                    fontSize: 12.5,
                                  ),
                                ),
                              ),
                            const SizedBox(height: 12),
                            // A-5 (Ronde Audit UX 2017): tombol Putar sadar-keadaan.
                            // Dibangun ulang oleh dua aliran: queueStream (ganti
                            // sesi) dan playbackState (putar/jeda).
                            StreamBuilder(
                              stream: handler.queueStream,
                              builder: (context, _) {
                                return StreamBuilder(
                                  stream: handler.playbackState.stream,
                                  initialData:
                                      handler.playbackState.valueOrNull,
                                  builder: (context, ps) {
                                    final engine = handler.engine;
                                    final thisSession =
                                        isRadioSessionOfPage(
                                          engine.context?.kind,
                                          engine.context?.id,
                                          seed.id,
                                        );
                                    final playing =
                                        thisSession &&
                                        (ps.data?.playing ?? false);
                                    final action = resolveRadioHeaderAction(
                                      thisSession: thisSession,
                                      playing: playing,
                                    );
                                    return RadioHeaderPlayButton(
                                      playing: playing,
                                      onTap: () {
                                        switch (action) {
                                          case RadioHeaderAction.pause:
                                            handler.pauseNow();
                                          case RadioHeaderAction.resume:
                                            handler.playNow();
                                          case RadioHeaderAction.start:
                                            handler.startRadio(seed);
                                        }
                                      },
                                    );
                                  },
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                // Ronde Tambahan 2015 (Butir 1): baris aksi atas SELURUH
                // daftar bangkitan — pola segmen ikon+label yang sama
                // seperti halaman konten. Menambah ke antrean TIDAK
                // membangun ulang pemutaran (jalur ekor handler).
                if (_tracks.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                    child: Row(
                      children: [
                        Expanded(
                          child: _RadioActionSegment(
                            leading: ClaiIcon(
                              ClaiIcons.queue,
                              size: 18,
                              color: ClaiColors.ink,
                            ),
                            label: context.l10n.ctxAddToQueue,
                            onTap: () async {
                              final n =
                                  await handler.enqueueAll(_tracks);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  claiSnackAboveChrome(
                                    context,
                                    context.l10n.bulkQueueAdded(n),
                                  ),
                                );
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _RadioActionSegment(
                            leading: ClaiIcon(
                              ClaiIcons.heart,
                              size: 18,
                              color: ClaiColors.ink,
                            ),
                            label: context.l10n.ctxSaveToCollection,
                            onTap: () async {
                              final n = await ref
                                  .read(libraryProvider)
                                  .saveAllToCollection(_tracks);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  claiSnackAboveChrome(
                                    context,
                                    n > 0
                                        ? context.l10n.bulkSaved(n)
                                        : context.l10n.bulkSavedNone,
                                  ),
                                );
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _RadioActionSegment(
                            leading: ClaiIcon(
                              ClaiIcons.playlistAdd,
                              size: 18,
                              color: ClaiColors.ink,
                            ),
                            label: context.l10n.ctxAddToPlaylist,
                            onTap: () => showAddTracksToPlaylistSheet(
                              context,
                              ref,
                              _tracks,
                              onFeedback: (m) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    claiSnackAboveChrome(context, m),
                                  );
                                }
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (_tracks.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
                    child: Text(
                      context.l10n.radioEmpty,
                      style: const TextStyle(
                        color: ClaiColors.inkSecondary,
                        height: 1.45,
                      ),
                    ),
                  ),
                for (var i = 0; i < _tracks.length; i++)
                  SongRow(
                    track: _tracks[i],
                    onTap: () => handler.startRadioFromPage(seed, _tracks, i),
                  ),
                SizedBox(height: bottomChromeClearance(context)),
              ],
            ),
    );
  }
}

/// Aksi tombol Putar header halaman Radio (A-5): jeda bila sesi halaman
/// ini sedang berbunyi, lanjutkan bila sesi halaman ini terjeda, dan mulai
/// sesi baru bila belum ada sesi halaman ini — ketukan selalu berakibat
/// terlihat (ikon + bunyi berubah), bukan mulai-ulang diam-diam.
enum RadioHeaderAction { pause, resume, start }

RadioHeaderAction resolveRadioHeaderAction({
  required bool thisSession,
  required bool playing,
}) {
  if (playing) return RadioHeaderAction.pause;
  if (thisSession) return RadioHeaderAction.resume;
  return RadioHeaderAction.start;
}

/// Predikat "sesi radio halaman ini": konteks mesin harus radio dengan id
/// benih halaman ini. Dipakai tombol header agar halaman lain (atau sesi
/// non-radio) tidak pernah dikira sesi halaman ini.
bool isRadioSessionOfPage(String? kind, String? contextId, String seedId) {
  return kind == 'radio' && contextId == seedId;
}

/// Tombol Putar/Jeda header halaman Radio — widget presentasi murni:
/// ikon mengikuti [playing], ketukan memanggil [onTap]. Keputusan aksi
/// (pause/resume/start) tinggal di [resolveRadioHeaderAction].
class RadioHeaderPlayButton extends StatelessWidget {
  final bool playing;
  final VoidCallback onTap;
  const RadioHeaderPlayButton({
    super.key,
    required this.playing,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    return PressableScale(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 48,
          height: 48,
          decoration: const BoxDecoration(
            color: ClaiColors.accent,
            shape: BoxShape.circle,
          ),
          child: ClaiIcon(
            playing ? ClaiIcons.pause : ClaiIcons.play,
            color: ClaiColors.onAccent,
            size: 26,
          ),
        ),
      ),
    );
  }
}

/// Satu segmen baris aksi halaman Radio — pola visual yang sama dengan
/// segmen aksi halaman konten (permukaan surface-2 radius 10, tinggi 46,
/// ikon+label di tengah; label panjang memotong elipsis).
class _RadioActionSegment extends StatelessWidget {
  final Widget leading;
  final String label;
  final VoidCallback? onTap;
  const _RadioActionSegment({
    required this.leading,
    required this.label,
    required this.onTap,
  });
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
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                leading,
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: enabled ? ClaiColors.ink : ClaiColors.inkFaint,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
