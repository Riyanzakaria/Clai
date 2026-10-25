import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../app.dart';
import '../core/clai_icons.dart';
import '../core/tokens.dart';
import '../l10n/l10n.dart';
import 'cover_accent_glow.dart';
import 'player_sheet.dart';
import 'widgets.dart';

/// Warna permukaan kartu mini player (Ronde Putusan Desain butir C —
/// perintah pemilik 25 Okt 2026, MEMBATALKAN keadaan netral ronde poles):
/// SELURUH kartu mewarisi tinta sampul trek berjalan lewat pipa aksen
/// dinamis yang sama dengan kartu Beranda/Player, disaring
/// [readableAccentSurface] agar teks & ikon tetap kontras. Tanpa aksen
/// (sakelar mati / tanpa sampul / muat gagal) kartu kembali ke permukaan
/// netral DS. Tombol putar tetap lime Volt — aksen merek tidak digantikan.
Color miniPlayerSurfaceColor(Color? tonal) =>
    tonal == null ? ClaiColors.surface2 : readableAccentSurface(tonal);

/// Mini Player (DS 6.7): 64dp sebagai KARTU melayang di atas nav (v4.4 —
/// margin sisi, radius kartu DS, garis tepi 1px, bayangan tunggal), progres
/// 2dp di tepi atas, geser atas = Player, geser samping = next/prev.
class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final handler = ref.watch(audioHandlerProvider);
    return StreamBuilder<MediaItem?>(
      stream: handler.mediaItem.stream,
      initialData: handler.mediaItem.valueOrNull,
      builder: (context, snap) {
        final item = snap.data;
        if (item == null) return const SizedBox.shrink();
        return Semantics(
          button: true,
          label: context.l10n.a11yOpenPlayer,
          child: GestureDetector(
            onTap: () => openPlayerSheet(context),
            onVerticalDragEnd: (d) {
              if ((d.primaryVelocity ?? 0) < -120) openPlayerSheet(context);
            },
            onHorizontalDragEnd: (d) {
              final v = d.primaryVelocity ?? 0;
              if (v < -200) handler.skipToNext();
              if (v > 200) handler.skipToPrevious();
            },
            child: CoverAccentBuilder(
              key: ValueKey('mini-accent-${item.id}'),
              artworkUrl: item.artUri?.toString(),
              builder: (context, tonal) => Container(
                height: kMiniPlayerHeight,
                margin: const EdgeInsets.fromLTRB(
                  12,
                  0,
                  12,
                  kMiniPlayerBottomMargin,
                ),
                decoration: BoxDecoration(
                  color: miniPlayerSurfaceColor(tonal),
                  borderRadius: BorderRadius.circular(ClaiRadius.card),
                  border: Border.all(color: ClaiColors.divider, width: 1),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x55000000),
                      blurRadius: 16,
                      offset: Offset(0, 6),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(ClaiRadius.card),
                  child: Column(
                    children: [
                      StreamBuilder<Duration>(
                        stream: handler.positionStream,
                        builder: (context, pos) {
                          final dur = item.duration ?? Duration.zero;
                          final frac = dur.inMilliseconds == 0
                              ? 0.0
                              : (pos.data?.inMilliseconds ?? 0) /
                                    dur.inMilliseconds;
                          return LinearProgressIndicator(
                            value: frac.clamp(0, 1),
                            minHeight: 2,
                            color: ClaiColors.accent,
                            // Di atas tinta sampul, rel progres memakai putih
                            // tembus agar garis lime tetap terbaca; di permukaan
                            // netral tetap surface3 seperti semula.
                            backgroundColor: tonal == null
                                ? ClaiColors.surface3
                                : Colors.white.withValues(alpha: 0.16),
                          );
                        },
                      ),
                      Expanded(
                        child: Row(
                          children: [
                            const SizedBox(width: 8),
                            CoverArt(
                              url: item.artUri?.toString(),
                              size: 48,
                              label: item.title,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                      color: ClaiColors.ink,
                                    ),
                                  ),
                                  Text(
                                    item.artist ?? '',
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
                            StreamBuilder<PlaybackState>(
                              stream: handler.playbackState.stream,
                              initialData: handler.playbackState.valueOrNull,
                              builder: (context, ps) {
                                final playing = ps.data?.playing ?? false;
                                final loading =
                                    ps.data?.processingState ==
                                        AudioProcessingState.loading ||
                                    ps.data?.processingState ==
                                        AudioProcessingState.buffering;
                                if (loading) {
                                  return const SizedBox(
                                    width: 40,
                                    height: 40,
                                    child: Center(
                                      child: SizedBox(
                                        width: 22,
                                        height: 22,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: ClaiColors.accent,
                                        ),
                                      ),
                                    ),
                                  );
                                }
                                return Semantics(
                                  button: true,
                                  label: playing
                                      ? context.l10n.a11yPause
                                      : context.l10n.a11yPlay,
                                  child: PressableScale(
                                    child: GestureDetector(
                                      onTap: () => playing
                                          ? handler.pauseNow()
                                          : handler.playNow(),
                                      child: Container(
                                        width: 40,
                                        height: 40,
                                        decoration: const BoxDecoration(
                                          color: ClaiColors.accent,
                                          shape: BoxShape.circle,
                                        ),
                                        child: ClaiIcon(
                                          playing
                                              ? ClaiIcons.pause
                                              : ClaiIcons.play,
                                          color: ClaiColors.onAccent,
                                          size: 20,
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                            IconButton(
                              icon: ClaiIcon(
                                ClaiIcons.next,
                                color: ClaiColors.ink,
                              ),
                              tooltip: context.l10n.a11yNext,
                              onPressed: () => handler.skipToNext(),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
