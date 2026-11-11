import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app.dart';
import '../core/clai_icons.dart';
import '../core/tokens.dart';
import '../domain/models.dart';
import '../l10n/l10n.dart';
import '../player/similarity.dart';
import '../services/ambient_theme.dart';
import 'cover_accent_glow.dart';
import 'widgets.dart';

/// Halaman Radio Lagu (F2.5, menggantikan radio ambil-alih-antrean):
/// mengetuk "Mulai Radio Lagu" MEMBUKA halaman ini — bangkitan radio dari
/// satu lagu benih, tampil seperti halaman playlist. Membuka halaman TIDAK
/// menyentuh pemutaran yang sedang berjalan sama sekali (pemuatan daftar
/// adalah panggilan provider murni); sesi radio baru dimulai saat pengguna
/// menekan tombol Putar (benih diputar, mesin sesi radio yang ada) atau
/// mengetuk satu item daftar (item itu diputar, jangkar benih tetap lagu
/// asal halaman).
///
/// Gelombang 2 (8048): komposisi Kepala Hidup varian Radio — panggung
/// sampul benih 260 dp + chip kaca + tombol putar sadar-keadaan (A-5,
/// logika tak berubah) bernada sampul benih di sudut panggung; kartu
/// benih; tiga pil aksi tonal; kepala hasil berketerangan jumlah nyata.
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
    final l = context.l10n;
    final handler = ref.watch(audioHandlerProvider);
    final seed = widget.seed;
    return Scaffold(
      body: _error != null
          ? Stack(
              children: [
                Positioned.fill(
                  child: ErrorState(message: _error!, onRetry: _load),
                ),
                Positioned(
                  top: MediaQuery.paddingOf(context).top + 12,
                  left: 16,
                  child: const GlassBackChip(),
                ),
              ],
            )
          : FiniteScrollPage(
              padding: EdgeInsets.zero,
              children: [
                // PANGGUNG benih 260 dp (Kepala Hidup varian Radio).
                SizedBox(
                  height: 260,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      StageArtwork(url: seed.artworkUrl, height: 260),
                      const Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        height: 130,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Color(0x00000000), Color(0x8C000000)],
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        top: MediaQuery.paddingOf(context).top + 12,
                        left: 16,
                        child: const GlassBackChip(),
                      ),
                      Positioned(
                        left: 20,
                        right: 96,
                        bottom: 16,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              l.radioKicker.toUpperCase(),
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 1.6,
                                color: Colors.white.withValues(alpha: 0.85),
                              ),
                            ),
                            const SizedBox(height: 6),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                l.radioPageTitle(seed.title),
                                maxLines: 1,
                                style: displayStyle(26)
                                    .copyWith(color: ClaiColors.ink),
                              ),
                            ),
                            if (seed.artistNames.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                seed.artistNames,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13,
                                  color:
                                      Colors.white.withValues(alpha: 0.75),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      // Tombol Putar/Jeda A-5 di sudut panggung, bernada
                      // sampul benih (§11.9) — logika resolve tetap.
                      Positioned(
                        right: 16,
                        bottom: 16,
                        child: CoverAccentBuilder(
                          artworkUrl: seed.artworkUrl,
                          builder: (context, tonal) {
                            final tone = tonal == null
                                ? ClaiColors.accent
                                : deepToneFromColor(tonal);
                            return StreamBuilder(
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
                                    final playing = thisSession &&
                                        (ps.data?.playing ?? false);
                                    final action = resolveRadioHeaderAction(
                                      thisSession: thisSession,
                                      playing: playing,
                                    );
                                    return RadioHeaderPlayButton(
                                      playing: playing,
                                      size: 56,
                                      fill: tone,
                                      iconColor: onProgressTone(tone),
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
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                // KARTU BENIH: lagu asal bangkitan, apa adanya.
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: ClaiColors.surface1,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        CoverArt(
                          url: seed.artworkUrl,
                          size: 48,
                          label: seed.title,
                          radius: 8,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                l.radioSeedCaption,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: ClaiColors.inkFaint,
                                ),
                              ),
                              Text(
                                seed.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: ClaiColors.ink,
                                ),
                              ),
                              if (seed.artistNames.isNotEmpty)
                                Text(
                                  seed.artistNames,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: ClaiColors.inkSecondary,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        if (seed.duration != null)
                          Text(
                            formatDuration(seed.duration!),
                            style: const TextStyle(
                              fontSize: 12,
                              color: ClaiColors.inkSecondary,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                  child: Text(
                    l.radioGeneratedFrom,
                    style: const TextStyle(
                      fontSize: 12,
                      color: ClaiColors.inkFaint,
                    ),
                  ),
                ),
                if (_loading) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
                    child: Text(
                      l.radioComposing,
                      style: const TextStyle(
                        fontSize: 13,
                        color: ClaiColors.inkSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 320, child: LoadingSkeleton()),
                ] else if (_tracks.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                    child: Text(
                      l.radioEmpty,
                      style: const TextStyle(
                        color: ClaiColors.inkSecondary,
                        height: 1.45,
                      ),
                    ),
                  )
                else ...[
                  // Tiga pil aksi tonal atas seluruh daftar bangkitan —
                  // menambah ke antrean TIDAK membangun ulang pemutaran.
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                    child: Row(
                      children: [
                        Expanded(
                          child: _RadioActionPill(
                            leading: ClaiIcon(
                              ClaiIcons.queue,
                              size: 18,
                              color: ClaiColors.ink,
                            ),
                            label: l.ctxAddToQueue,
                            onTap: () async {
                              final n = await handler.enqueueAll(_tracks);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  claiSnackAboveChrome(
                                    context,
                                    l.bulkQueueAdded(n),
                                  ),
                                );
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _RadioActionPill(
                            leading: ClaiIcon(
                              ClaiIcons.heart,
                              size: 18,
                              color: ClaiColors.ink,
                            ),
                            label: l.ctxSaveToCollection,
                            onTap: () async {
                              final n = await ref
                                  .read(libraryProvider)
                                  .saveAllToCollection(_tracks);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  claiSnackAboveChrome(
                                    context,
                                    n > 0
                                        ? l.bulkSaved(n)
                                        : l.bulkSavedNone,
                                  ),
                                );
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _RadioActionPill(
                            leading: ClaiIcon(
                              ClaiIcons.playlistAdd,
                              size: 18,
                              color: ClaiColors.ink,
                            ),
                            label: l.ctxAddToPlaylist,
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
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 6),
                    child: DimKicker(
                      '${l.radioResults} · ${l.songCount(_tracks.length)}',
                    ),
                  ),
                  for (var i = 0; i < _tracks.length; i++)
                    SongRow(
                      track: _tracks[i],
                      onTap: () =>
                          handler.startRadioFromPage(seed, _tracks, i),
                    ),
                ],
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

/// Tombol Putar/Jeda halaman Radio — widget presentasi murni:
/// ikon mengikuti [playing], ketukan memanggil [onTap]. Keputusan aksi
/// (pause/resume/start) tinggal di [resolveRadioHeaderAction]. Bawaan
/// tampil Volt 48 (perilaku terbangun); panggung Kepala Hidup memakai
/// 56 bernada sampul benih lewat parameter yang sama.
class RadioHeaderPlayButton extends StatelessWidget {
  final bool playing;
  final VoidCallback onTap;
  final double size;
  final Color fill;
  final Color iconColor;
  const RadioHeaderPlayButton({
    super.key,
    required this.playing,
    required this.onTap,
    this.size = 48,
    this.fill = ClaiColors.accent,
    this.iconColor = ClaiColors.onAccent,
  });
  @override
  Widget build(BuildContext context) {
    return PressableScale(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(color: fill, shape: BoxShape.circle),
          child: ClaiIcon(
            playing ? ClaiIcons.pause : ClaiIcons.play,
            color: iconColor,
            size: 26,
          ),
        ),
      ),
    );
  }
}

/// Satu pil aksi tonal halaman Radio (Gelombang 2): permukaan surface-2
/// bentuk pil penuh, tinggi minimum 44, ikon+label rata tengah; label
/// tampil utuh sampai dua baris (larangan elipsis audit 8047 berlaku).
class _RadioActionPill extends StatelessWidget {
  final Widget leading;
  final String label;
  final VoidCallback? onTap;
  const _RadioActionPill({
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
        borderRadius: BorderRadius.circular(999),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  leading,
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 2,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color:
                            enabled ? ClaiColors.ink : ClaiColors.inkFaint,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
