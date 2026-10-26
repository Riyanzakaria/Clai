import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../app.dart';
import '../core/clai_icons.dart';
import '../core/spring.dart';
import '../core/tokens.dart';
import '../l10n/l10n.dart';
import '../player/audio_handler.dart';
import 'cover_accent_glow.dart';
import 'player_sheet.dart';
import 'sleep_timer_sheet.dart';
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

/// Aksi geser mini player (F2.5).
enum MiniSwipeAction { none, next, previous }

/// Ambang geser mini player: 35% lebar kartu (komposisi F2.5 terkunci).
const double kMiniSwipeThresholdFraction = 0.35;

/// Keputusan geser mini player — MURNI & diuji unit. Geser kiri jauh =
/// berikutnya, kanan jauh = sebelumnya. Di bawah ambang jarak, lemparan
/// cepat warisan DS 6.7 (fling searah ≥40dp dengan kecepatan ≥500)
/// tetap diakui; sisanya none (kartu berpegas kembali).
MiniSwipeAction miniSwipeDecision({
  required double offsetX,
  required double width,
  double velocityX = 0,
}) {
  if (width <= 0) return MiniSwipeAction.none;
  final threshold = width * kMiniSwipeThresholdFraction;
  if (offsetX <= -threshold) return MiniSwipeAction.next;
  if (offsetX >= threshold) return MiniSwipeAction.previous;
  if (offsetX <= -40 && velocityX < -500) return MiniSwipeAction.next;
  if (offsetX >= 40 && velocityX > 500) return MiniSwipeAction.previous;
  return MiniSwipeAction.none;
}

/// Alfa petunjuk tepi geser mini player (U-1): cukup terlihat sebagai
/// petunjuk, cukup samar agar tak bersaing dengan teks/tombol.
const double kMiniSwipeHintAlpha = 0.2;

/// U-1 (Audit UX, diterapkan build 2018): chevron samar PERMANEN di tepi
/// dalam kartu mini player — gestur geser samping (F2.5) selalu terlihat,
/// melengkapi petunjuk satu-kali A-6. Berada di dalam batas kartu yang
/// ada; geometri chrome terkunci (tinggi kartu, margin) tidak berubah.
class MiniSwipeEdgeHint extends StatelessWidget {
  final bool left;
  const MiniSwipeEdgeHint({super.key, required this.left});
  @override
  Widget build(BuildContext context) {
    final icon = ClaiIcon(
      ClaiIcons.chevronRight,
      size: 14,
      color: ClaiColors.ink.withValues(alpha: kMiniSwipeHintAlpha),
    );
    return IgnorePointer(
      child: left ? Transform.scale(scaleX: -1, child: icon) : icon,
    );
  }
}

/// Format sisa timer tidur ringkas untuk chip mini player: m:ss.
String formatSleepRemaining(Duration d) {
  final s = d.inSeconds < 0 ? 0 : d.inSeconds;
  final m = s ~/ 60;
  final r = s % 60;
  return '$m:${r.toString().padLeft(2, '0')}';
}

/// Indikator timer tidur di mini player (UX2, build 2018): ikon bulan +
/// sisa waktu ringkas. Tampil hanya saat timer aktif, di dalam tata
/// letak kartu yang ada (tinggi kartu tak berubah). Ketuk membuka
/// lembar timer tidur seperti biasa.
class SleepTimerChip extends StatelessWidget {
  final Duration remaining;
  final VoidCallback onTap;
  const SleepTimerChip({
    super.key,
    required this.remaining,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: context.l10n.playerTimer,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClaiIcon(ClaiIcons.moon, size: 13, color: ClaiColors.inkSecondary),
              const SizedBox(width: 3),
              Text(
                formatSleepRemaining(remaining),
                style: const TextStyle(
                  fontSize: 11,
                  color: ClaiColors.inkSecondary,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Mini Player (DS 6.7): 64dp sebagai KARTU melayang di atas nav (v4.4 —
/// margin sisi, radius kartu DS, garis tepi 1px, bayangan tunggal), progres
/// 2dp di tepi atas, geser atas = Player, geser samping = next/prev.
/// F2.5: geser samping kini MENGIKUTI JARI — lepas melewati 35% lebar
/// memicu ganti lagu (+haptic), lepas di bawahnya kartu berpegas kembali
/// dengan overshoot tipis (ClaiSprings.listIn).
class MiniPlayer extends ConsumerStatefulWidget {
  /// Audit UX 2017: dipanggil sekali tiap geser samping BERHASIL berpindah
  /// lagu — tuan rumah memakainya mengubur petunjuk geser satu-kali.
  final VoidCallback? onSwipeCommitted;
  const MiniPlayer({super.key, this.onSwipeCommitted});
  @override
  ConsumerState<MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends ConsumerState<MiniPlayer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;
  double _dx = 0;
  double _cardWidth = 0;
  bool _thresholdCrossed = false;
  int _swipeRun = 0;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController.unbounded(vsync: this)
      ..addListener(() {
        if (mounted) setState(() => _dx = _anim.value);
      });
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  void _springTo(double target, double velocity, {VoidCallback? onDone}) {
    if (reducedMotionOf(context)) {
      _anim.stop();
      setState(() => _dx = target);
      onDone?.call();
      return;
    }
    final run = ++_swipeRun;
    _anim
        .animateWith(
          SpringSimulation(ClaiSprings.listIn, _dx, target, velocity),
        )
        .whenComplete(() {
          if (mounted && run == _swipeRun) onDone?.call();
        });
  }

  void _onDragStart(DragStartDetails d) {
    _swipeRun++;
    _anim.stop();
    _thresholdCrossed = false;
  }

  void _onDragUpdate(DragUpdateDetails d) {
    final w = _cardWidth > 0 ? _cardWidth : MediaQuery.of(context).size.width;
    final next = (_dx + d.delta.dx).clamp(-w, w);
    setState(() => _dx = next);
    final over = next.abs() >= w * kMiniSwipeThresholdFraction;
    if (over && !_thresholdCrossed) {
      _thresholdCrossed = true;
      HapticFeedback.selectionClick();
    } else if (!over) {
      _thresholdCrossed = false;
    }
  }

  void _onDragEnd(DragEndDetails d, ClaiAudioHandler handler) {
    final w = _cardWidth > 0 ? _cardWidth : MediaQuery.of(context).size.width;
    final v = d.primaryVelocity ?? 0;
    final action = miniSwipeDecision(offsetX: _dx, width: w, velocityX: v);
    if (action == MiniSwipeAction.none) {
      _springTo(0, v);
      return;
    }
    HapticFeedback.mediumImpact();
    final target = action == MiniSwipeAction.next ? -w : w;
    _springTo(
      target,
      v,
      onDone: () {
        if (action == MiniSwipeAction.next) {
          handler.skipToNext();
        } else {
          handler.skipToPrevious();
        }
        widget.onSwipeCommitted?.call();
        _anim.stop();
        if (mounted) setState(() => _dx = 0);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final handler = ref.watch(audioHandlerProvider);
    // UX2: sisa timer tidur (layanan memberi tahu tiap detik saat aktif;
    // null = tak ada timer → chip tak dirender, tata letak seperti semula).
    final sleepRemaining = ref.watch(sleepServiceProvider).remaining;
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
            onHorizontalDragStart: _onDragStart,
            onHorizontalDragUpdate: _onDragUpdate,
            onHorizontalDragEnd: (d) => _onDragEnd(d, handler),
            onHorizontalDragCancel: () => _springTo(0, 0),
            child: LayoutBuilder(
              builder: (context, constraints) {
                _cardWidth = constraints.maxWidth - 24;
                return Transform.translate(
                  offset: Offset(_dx, 0),
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
                                  const SizedBox(width: 2),
                                  const MiniSwipeEdgeHint(left: true),
                                  const SizedBox(width: 4),
                                  CoverArt(
                                    url: item.artUri?.toString(),
                                    size: 48,
                                    label: item.title,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
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
                                  if (sleepRemaining != null) ...[
                                    const SizedBox(width: 6),
                                    SleepTimerChip(
                                      remaining: sleepRemaining,
                                      onTap: () =>
                                          openSleepTimerSheet(context),
                                    ),
                                    const SizedBox(width: 2),
                                  ],
                                  StreamBuilder<PlaybackState>(
                                    stream: handler.playbackState.stream,
                                    initialData:
                                        handler.playbackState.valueOrNull,
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
                                  const MiniSwipeEdgeHint(left: false),
                                  const SizedBox(width: 2),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}
