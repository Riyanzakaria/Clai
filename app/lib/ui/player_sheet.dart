import 'dart:async';
import 'dart:math' as math;

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../app.dart';
import '../core/clai_icons.dart';
import '../core/tokens.dart';
import '../player/queue_engine.dart' as qe;
import '../l10n/l10n.dart';
import 'cover_accent_glow.dart';
import 'lyrics_sheet.dart';
import 'queue_screen.dart';
import 'sleep_timer_sheet.dart';
import 'voice_sheet.dart';
import 'widgets.dart';

Future<void> openPlayerSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context, isScrollControlled: true, backgroundColor: ClaiColors.surface1,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    // Scaffold transparan di dalam sheet: SnackBar dari tombol di dalam Player
    // (placeholder Lirik/Timer) harus tampil DI DALAM sheet — tanpa ini ia
    // dirender di Scaffold akar yang tertutup sheet modal (audit v4.4).
    builder: (_) => const FractionallySizedBox(heightFactor: 0.94,
        child: Scaffold(backgroundColor: Colors.transparent, body: PlayerSheet())),
  );
}

/// Tata letak sampul Player (murni, diuji unit) — v4.4, akar luapan 23px di
/// perangkat pemilik: sejak sampul selebar konten (v4.3-E), kolom Player adalah
/// rangkaian tetap; pada metrik layar+font pemilik totalnya melebihi tinggi
/// sheet dan banner Putar Otomatis di dasar tertutup pita overflow.
///
/// Perbaikan: sampul ELASTIS — tingginya = ruang yang tersisa sesudah semua
/// elemen tetap dihitung (dibatasi [120, lebar konten]); sisa ruang menjadi
/// spacer di atas baris aksi. Bila ruang benar-benar tidak cukup (layar sangat
/// pendek), sampul berhenti di batas bawah 120 dan kolom digulir (jaring
/// pengaman di widget) — tidak pernah lagi overflow.
({double cover, double spacer, double contentHeight}) playerCoverLayout({
  required double maxWidth,
  required double maxHeight,
  required double textScale,
  required bool autoplay,
}) {
  final ts = textScale;
  // Elemen tetap (dp), sesuai susunan widget di bawah.
  const handle = 4.0 + 12; // pegangan + jarak
  const header = 48.0; // baris tutup/konteks/menu
  const gapHeader = 8.0;
  const gapCover = 22.0;
  // D-25: judul display DS 6.9 adalah 28 (kode lama memakai 26).
  final titleBlock = math.max((28 * 1.18 * 2 + 4 + 16 * 1.25) * ts, 48.0);
  const gapTitle = 10.0;
  final seekBlock = 48.0 + 16.0 * ts; // slider + baris waktu/status
  const gapSeek = 6.0;
  const controls = 64.0; // tombol putar 64 mendominasi deret kontrol
  final actions = 16.0 + 20.0 * ts; // Lirik/Antrian/Timer
  var banner = 0.0;
  if (autoplay) {
    final textWidth = math.max(80.0, maxWidth - 56); // padding banner + ikon + celah
    final charsPerLine = math.max(10.0, textWidth / (6.76 * ts));
    final lines = (124 / charsPerLine).ceil().clamp(2, 6); // 117 karakter teks banner + margin
    banner = 18 + 28 + lines * 13 * 1.45 * ts;
  }
  final reserved = handle + header + gapHeader + gapCover + titleBlock + gapTitle + seekBlock + gapSeek + controls + actions + banner;
  final cover = (maxHeight - reserved).clamp(120.0, maxWidth);
  final spacer = math.max(0.0, maxHeight - reserved - cover);
  return (cover: cover, spacer: spacer, contentHeight: reserved + cover);
}

/// Player penuh (DS 6.9): tipografi memimpin, rata kiri; suka di blok judul; slot status di bawah seek.
class PlayerSheet extends ConsumerWidget {
  const PlayerSheet({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final handler = ref.watch(audioHandlerProvider);
    final engine = handler.engine;
    return StreamBuilder<MediaItem?>(
      stream: handler.mediaItem.stream,
      initialData: handler.mediaItem.valueOrNull,
      builder: (context, snap) {
        final item = snap.data;
        if (item == null) {
          return EmptyState(icon: ClaiIcons.musicOff, message: context.l10n.playerEmpty);
        }
        final current = engine.current;
        final liked = current != null && ref.watch(libraryProvider).isLiked(current.key);
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
          child: LayoutBuilder(builder: (context, box) {
            // Sampul persegi selebar konten (PRD 5.5) yang ELASTIS (v4.4):
            // menyusut halus mengikuti ruang vertikal yang benar-benar ada,
            // dan kolom bisa digulir sebagai jaring pengaman layar terpendek.
            final layout = playerCoverLayout(
              maxWidth: box.maxWidth,
              maxHeight: box.maxHeight,
              textScale: MediaQuery.textScalerOf(context).scale(1),
              autoplay: engine.autoplayActive,
            );
            return SingleChildScrollView(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SheetHandle(),
            const SizedBox(height: 12),
            Row(children: [
              IconButton(icon: ClaiIcon(ClaiIcons.chevronDown, color: ClaiColors.inkSecondary),
                  tooltip: context.l10n.a11yClosePlayer,
                  onPressed: () => Navigator.of(context).pop()),
              Expanded(child: Text(engine.context?.label ?? context.l10n.playerNowPlaying, textAlign: TextAlign.center, maxLines: 1,
                  overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: ClaiColors.inkSecondary))),
              IconButton(icon: ClaiIcon(ClaiIcons.moreVert, color: ClaiColors.inkSecondary),
                  tooltip: context.l10n.a11yTrackOptions,
                  onPressed: () { if (current != null) showTrackContextSheet(context, ref, current); }),
            ]),
            const SizedBox(height: 8),
            // PRD 5.5 "sampul besar" (koreksi pemilik v4.3): sampul memenuhi lebar
            // konten tepi-ke-tepi, bukan lagi kotak kecil mepet kiri.
            // F2 Batch 2: latar tonal dari sampul (DS Bab 2) — tombol tetap Volt.
            Center(
                child: CoverAccentGlow(
                    key: ValueKey(item.id),
                    artworkUrl: item.artUri?.toString(),
                    child: CoverArt(url: item.artUri?.toString(), size: layout.cover, label: item.title, radius: 16))),
            const SizedBox(height: 22),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // D-25: judul display 28 (DS 6.9) + marquee untuk judul
                // panjang (bergeser sesudah 3 dtk diam; mati saat
                // gerak-reduksi — D-05).
                MarqueeText(item.title, style: displayStyle(28)),
                const SizedBox(height: 4),
                Text(item.artist ?? '', style: const TextStyle(fontSize: 16, color: ClaiColors.inkSecondary), maxLines: 1, overflow: TextOverflow.ellipsis),
              ])),
              IconButton(
                iconSize: 48,
                tooltip: liked ? context.l10n.a11yUnlike : context.l10n.a11yLike,
                icon: ClaiIcon(liked ? ClaiIcons.heartFill : ClaiIcons.heart, color: liked ? ClaiColors.liked : ClaiColors.inkSecondary, size: 28),
                onPressed: () { if (current != null) ref.read(libraryProvider).toggleLike(current); },
              ),
            ]),
            const SizedBox(height: 10),
            StreamBuilder<Duration>(
              stream: handler.positionStream,
              builder: (context, pos) {
                final dur = item.duration ?? Duration.zero;
                final p = pos.data ?? Duration.zero;
                return Column(children: [
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 4, thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                      overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
                      trackShape: const RoundedRectSliderTrackShape(),
                      activeTrackColor: ClaiColors.accent, inactiveTrackColor: ClaiColors.surface3, thumbColor: ClaiColors.accent),
                    child: Semantics(
                      label: context.l10n.a11ySeek,
                      child: Slider(
                        value: dur.inMilliseconds == 0 ? 0 : (p.inMilliseconds / dur.inMilliseconds).clamp(0, 1),
                        onChanged: dur.inMilliseconds == 0 ? null : (v) => handler.seek(Duration(milliseconds: (v * dur.inMilliseconds).round())),
                      ),
                    ),
                  ),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Text(formatDuration(p), style: const TextStyle(fontSize: 12, color: ClaiColors.inkSecondary, fontFeatures: [FontFeature.tabularFigures()])),
                    StreamBuilder<PlaybackState>(
                      stream: handler.playbackState.stream,
                      initialData: handler.playbackState.valueOrNull,
                      builder: (context, ps) {
                        final st = ps.data?.processingState;
                        final buffering = st == AudioProcessingState.buffering ||
                            st == AudioProcessingState.loading;
                        // D-25: slot status hanya bicara bila buffering
                        // bertahan >5 dtk (DS 6.9) — bukan kedip seketika.
                        // D-18: selain itu slot menampilkan bitrate aliran
                        // yang benar-benar diputar (label jujur).
                        return _StatusSlot(
                          buffering: buffering,
                          bufferingLabel: st == AudioProcessingState.loading
                              ? context.l10n.commonLoading
                              : context.l10n.playerBuffering,
                          bitrateKbps: handler.currentBitrate == null
                              ? null
                              : (handler.currentBitrate! / 1000).round(),
                        );
                      },
                    ),
                    Text(dur == Duration.zero ? '–' : '-${formatDuration(dur - p)}', style: const TextStyle(fontSize: 12, color: ClaiColors.inkSecondary, fontFeatures: [FontFeature.tabularFigures()])),
                  ]),
                ]);
              },
            ),
            const SizedBox(height: 6),
            StreamBuilder<PlaybackState>(
              stream: handler.playbackState.stream,
              initialData: handler.playbackState.valueOrNull,
              builder: (context, ps) {
                final playing = ps.data?.playing ?? false;
                final repeat = engine.repeat;
                final shuffle = engine.shuffle;
                return Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  _CtrlButton(
                    icon: ClaiIcons.shuffle, active: shuffle != qe.ShuffleMode.off, dot: shuffle != qe.ShuffleMode.off,
                    semanticLabel: context.l10n.a11yShuffle,
                    // Tombol ini sakelar acak MURNI; bila Smart Shuffle aktif, ketuk
                    // mematikannya (sakelar Smart ada di layar Antrian & Pengaturan).
                    onTap: () => handler.setShuffleMode(shuffle == qe.ShuffleMode.off ? AudioServiceShuffleMode.all : AudioServiceShuffleMode.none)),
                  _CtrlButton(icon: ClaiIcons.prev, big: true, semanticLabel: context.l10n.a11yPrevious, onTap: () => handler.skipToPrevious()),
                  Semantics(
                    button: true,
                    label: playing ? context.l10n.a11yPause : context.l10n.a11yPlay,
                    child: PressableScale(
                      child: GestureDetector(
                        onTap: () => playing ? handler.pauseNow() : handler.playNow(),
                        child: Container(width: 64, height: 64, decoration: const BoxDecoration(color: ClaiColors.accent, shape: BoxShape.circle),
                            child: ClaiIcon(playing ? ClaiIcons.pause : ClaiIcons.play, color: ClaiColors.onAccent, size: 32)),
                      ),
                    ),
                  ),
                  _CtrlButton(icon: ClaiIcons.next, big: true, semanticLabel: context.l10n.a11yNext, onTap: () => handler.skipToNext()),
                  _CtrlButton(
                    icon: repeat == qe.RepeatMode.one ? ClaiIcons.repeatOne : ClaiIcons.repeat,
                    active: repeat != qe.RepeatMode.off, dot: repeat != qe.RepeatMode.off,
                    semanticLabel: context.l10n.a11yRepeat,
                    onTap: () {
                      final next = switch (repeat) {
                        qe.RepeatMode.off => AudioServiceRepeatMode.all,
                        qe.RepeatMode.all => AudioServiceRepeatMode.one,
                        qe.RepeatMode.one => AudioServiceRepeatMode.none,
                      };
                      handler.setRepeatMode(next);
                    }),
                ]);
              },
            ),
            SizedBox(height: layout.spacer),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              _TextAction(icon: ClaiIcons.lyrics, label: context.l10n.playerLyrics, onTap: () => openLyricsSheet(context)),
              _TextAction(icon: ClaiIcons.queue, label: context.l10n.queueTitle, onTap: () =>
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const QueueScreen()))),
              _TextAction(icon: ClaiIcons.moon, label: context.l10n.playerTimer, onTap: () => openSleepTimerSheet(context)),
              _TextAction(icon: ClaiIcons.mic, label: context.l10n.playerVoice, onTap: () => openVoiceSheet(context)),
            ]),
            if (engine.autoplayActive)
              Container(
                margin: const EdgeInsets.only(top: 18), padding: const EdgeInsets.all(14),
                decoration: claiCardDecoration(radius: ClaiRadius.card),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  ClaiIcon(ClaiIcons.infinity, size: 18, color: ClaiColors.accent),
                  const SizedBox(width: 10),
                  Expanded(child: Text(context.l10n.playerAutoplayCard,
                      style: const TextStyle(fontSize: 13, color: ClaiColors.inkSecondary, height: 1.45))),
                ]),
              ),
              ]),
            );
          }),
        );
      },
    );
  }
}

class _CtrlButton extends StatelessWidget {
  final ClaiIconData icon;
  final bool active, dot, big;
  final VoidCallback onTap;
  final String? semanticLabel;
  const _CtrlButton({required this.icon, required this.onTap, this.active = false, this.dot = false, this.big = false, this.semanticLabel});
  @override
  Widget build(BuildContext context) => Semantics(
        button: true, label: semanticLabel, toggled: active,
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: onTap,
          child: Padding(padding: const EdgeInsets.all(8), child: Column(mainAxisSize: MainAxisSize.min, children: [
            ClaiIcon(icon, size: big ? 30 : 24, color: active ? ClaiColors.accent : ClaiColors.ink),
            const SizedBox(height: 2),
            Container(width: 4, height: 4, decoration: BoxDecoration(color: dot ? ClaiColors.accent : Colors.transparent, shape: BoxShape.circle)),
          ])),
        ),
      );
}

/// Slot status Player (DS 6.9, Sapuan D-25 + D-18): label buffering hanya
/// muncul bila keadaan buffering/loading bertahan LEBIH dari 5 detik;
/// selain itu slot menampilkan bitrate aliran aktif (label jujur D-18)
/// atau kosong.
class _StatusSlot extends StatefulWidget {
  final bool buffering;
  final String bufferingLabel;
  final int? bitrateKbps;
  const _StatusSlot({required this.buffering, required this.bufferingLabel, required this.bitrateKbps});
  @override
  State<_StatusSlot> createState() => _StatusSlotState();
}

class _StatusSlotState extends State<_StatusSlot> {
  bool _showBuffering = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(_StatusSlot old) {
    super.didUpdateWidget(old);
    if (old.buffering != widget.buffering) _sync();
  }

  void _sync() {
    _timer?.cancel();
    if (widget.buffering) {
      _timer = Timer(const Duration(seconds: 5), () {
        if (mounted) setState(() => _showBuffering = true);
      });
    } else if (_showBuffering) {
      setState(() => _showBuffering = false);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_showBuffering && widget.buffering) {
      return Text(widget.bufferingLabel,
          style: const TextStyle(fontSize: 12, color: ClaiColors.inkFaint));
    }
    final kbps = widget.bitrateKbps;
    if (kbps != null && !widget.buffering) {
      return Text(context.l10n.playerBitrate(kbps),
          style: const TextStyle(fontSize: 12, color: ClaiColors.inkFaint));
    }
    return const Text('', style: TextStyle(fontSize: 12));
  }
}

class _TextAction extends StatelessWidget {
  final ClaiIconData icon;
  final String label;
  final VoidCallback onTap;
  const _TextAction({required this.icon, required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap, borderRadius: BorderRadius.circular(8),
        child: Padding(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
            child: Row(children: [
              ClaiIcon(icon, size: 20, color: ClaiColors.inkSecondary),
              const SizedBox(width: 6),
              Text(label, style: const TextStyle(fontSize: 13, color: ClaiColors.inkSecondary)),
            ])),
      );
}
