import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../app.dart';
import '../core/clai_icons.dart';
import '../core/artwork.dart';
import '../core/tokens.dart';
import '../services/ambient_theme.dart';
import '../services/waveform.dart';
import '../player/queue_engine.dart' as qe;
import '../l10n/l10n.dart';
import 'cover_accent_glow.dart';
import 'glass.dart';
import 'haptics.dart';
import 'lyrics_sheet.dart';
import 'queue_screen.dart';
import 'shuffle_button_state.dart';
import 'sleep_timer_sheet.dart';
import 'voice_sheet.dart';
import 'widgets.dart';

Future<void> openPlayerSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: claiRootContext(context), isScrollControlled: true, backgroundColor: ClaiColors.surface1,
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

/// Tata letak Player B (murni, diuji unit) — komposisi papan B
/// (keputusan pemilik 2026-11-09 22:22): baris kaca atas · sampul
/// persegi beradius dengan jalur intip vinil di kanan · blok judul ·
/// waveform + baris waktu · transportasi melayang · bilah dok
/// berlabel · strip status Putar Otomatis (Sisipan G-3). Sampul ELASTIS: ukurannya sisa
/// ruang sesudah elemen tetap, dibatasi lebar (margin 16 kiri +
/// jalur intip ±68 + margin kanan 16 → lebar − 100) dan dijepit
/// [170, 470]. Sisa ruang menjadi spacer di atas bilah dok (dok
/// berlabuh di dasar seperti papan); bila total melebihi ruang,
/// kolom digulir — tidak pernah luapan.
({double cover, double spacer, double contentHeight}) playerBoardLayout({
  required double maxWidth,
  required double maxHeight,
  required double textScale,
  required bool autoplay,
}) {
  final ts = textScale;
  const topPad = 8.0;
  const header = 40.0; // baris keping kaca (gaya 8038 dipertahankan)
  const gapHeader = 16.0;
  const gapCoverTitle = 20.0;
  // Blok judul: display 38 (menyusut lewat skala muat) + artis 16.
  final titleBlock = (38 * 1.16 + 5 + 16 * 1.3) * ts;
  const gapTitleWave = 18.0;
  const waveBlock = 48.0; // zona sentuh waveform ukur
  const gapWaveTime = 2.0;
  final timeRow = math.max(18.0, 15.0 * ts);
  const gapTimeTransport = 14.0;
  const transport = 76.0; // tombol putar raksasa 76 mendominasi
  const gapTransportDock = 16.0;
  const dock = 64.0; // bilah dok berlabel
  const bottomPad = 16.0;
  var banner = 0.0;
  if (autoplay) {
    // Sisipan G-3 (kritik pemilik 2026-11-10 00:24 — kartu penuh 3
    // baris memakan ±12% lembar dan mendempetkan seluruh tumpukan):
    // strip status SATU baris — tinggi tetap (margin atas 12 + strip
    // ±22 diskalakan teks), tidak lagi dihitung dari teks 124
    // karakter. Ruang yang pulih kembali ke sampul lewat sisa ruang
    // di bawah: pada metrik pemilik sampul naik ±51 dp sampai batas
    // lebarnya (proporsi papan B pulih).
    banner = 12 + 22 * ts;
  }
  final reserved = topPad +
      header +
      gapHeader +
      gapCoverTitle +
      titleBlock +
      gapTitleWave +
      waveBlock +
      gapWaveTime +
      timeRow +
      gapTimeTransport +
      transport +
      gapTransportDock +
      dock +
      bottomPad +
      banner;
  final coverByHeight = maxHeight - reserved;
  final coverByWidth = maxWidth - 100.0;
  final cover =
      math.min(coverByHeight, coverByWidth).clamp(170.0, 470.0);
  final spacer = math.max(0.0, maxHeight - reserved - cover);
  return (
    cover: cover,
    spacer: spacer,
    contentHeight: reserved + cover + spacer
  );
}

/// Skala muat judul Player (murni, diuji): judul display menyusut
/// sebanding kebutuhan lebarnya, dilantai 0,68 — di bawah itu elipsis
/// anggun yang mengambil alih (perbaikan cacat 8038: judul panjang
/// terpotong di tengah kata di tepi lembar tanpa elipsis).
double titleScaleForWidth(double textWidth, double maxWidth) {
  if (textWidth <= 0 || maxWidth <= 0) return 1.0;
  return (maxWidth / textWidth).clamp(0.68, 1.0);
}

/// Player penuh: gerbang komposisi. Tema Dinamis menyala → komposisi
/// papan B dalam bahasa kita ([PlayerBoardBody]; keputusan pemilik
/// 2026-11-09 22:22 menggantikan P1 "Sampul Panggung" build 8038);
/// mati → komposisi warisan v3.1 PERSIS ([_LegacyPlayerSheet]) —
/// pola gerbang yang sama seperti Beranda dan chrome di ronde UI.
class PlayerSheet extends ConsumerWidget {
  const PlayerSheet({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final amb = ref.watch(ambientControllerProvider.select(ambientUiSlice)); // 8053 B(i): irisan tanpa napas
    if (!amb.enabled) return const _LegacyPlayerSheet();
    final handler = ref.watch(audioHandlerProvider);
    final engine = handler.engine;
    final recorder = ref.watch(waveformRecorderProvider);
    return StreamBuilder<MediaItem?>(
      stream: handler.mediaItem.stream,
      initialData: handler.mediaItem.valueOrNull,
      builder: (context, snap) {
        final item = snap.data;
        if (item == null) {
          return EmptyState(
              icon: ClaiIcons.musicOff, message: context.l10n.playerEmpty);
        }
        final current = engine.current;
        final liked =
            current != null && ref.watch(libraryProvider).isLiked(current.key);
        return PlayerBoardBody(
          item: item,
          engine: engine,
          contextLabel:
              engine.context?.label ?? context.l10n.playerNowPlaying,
          liked: liked,
          amb: amb,
          positionStream: handler.positionStream,
          initialPosition: handler.position,
          playbackStateStream: handler.playbackState.stream,
          initialPlaybackState: handler.playbackState.valueOrNull,
          bitrateKbps: handler.currentBitrate == null
              ? null
              : (handler.currentBitrate! / 1000).round(),
          waveformData:
              current == null ? null : recorder.dataFor(current.key),
          onClose: () => Navigator.of(context).pop(),
          onMore: () {
            if (current != null) showTrackContextSheet(context, ref, current);
          },
          onLike: () {
            if (current != null) {
              ClaiHaptics.like();
              ref.read(libraryProvider).toggleLike(current);
            }
          },
          artistTappable: current != null && canOpenArtist(current),
          onArtistTap: () {
            if (current != null) openArtistFromTrack(context, ref, current);
          },
          onPlayPause: (playing) =>
              playing ? handler.pauseNow() : handler.playNow(),
          onPrev: () {
            ClaiHaptics.armSkipLanding();
            handler.skipToPrevious();
          },
          onNext: () {
            ClaiHaptics.armSkipLanding();
            handler.skipToNext();
          },
          onShuffleToggle: () =>
              handler.setShuffleMode(shuffleTapTarget(engine.shuffle)),
          onRepeatCycle: () {
            final next = switch (engine.repeat) {
              qe.RepeatMode.off => AudioServiceRepeatMode.all,
              qe.RepeatMode.all => AudioServiceRepeatMode.one,
              qe.RepeatMode.one => AudioServiceRepeatMode.none,
            };
            handler.setRepeatMode(next);
          },
          onSeek: (d) => handler.seek(d),
          onLyrics: () => openLyricsScreen(context),
          onQueue: () => Navigator.of(claiRootContext(context))
              .push(MaterialPageRoute(builder: (_) => const QueueScreen())),
          onTimer: () => openSleepTimerSheet(context),
          onVoice: () => openVoiceSheet(context),
        );
      },
    );
  }
}

/// Komposisi warisan v3.1 (DS 6.9 lama): tipografi memimpin, rata
/// kiri; suka di blok judul; slot status di bawah seek. Dirender
/// PERSIS seperti sebelum ronde Player F3 bila Tema Dinamis mati —
/// satu-satunya perbedaan dari kode lama: cabang bingkai kaca tema
/// menyala kini hidup di [PlayerStageBody], bukan di sini.
class _LegacyPlayerSheet extends ConsumerWidget {
  const _LegacyPlayerSheet();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final handler = ref.watch(audioHandlerProvider);
    final engine = handler.engine;
    return Stack(
      children: [
        const Positioned(
          left: 0,
          right: 0,
          top: 0,
          child: AmbientWashLayer(
            kind: AmbientSurfaceKind.player,
            heightFraction: 0.66,
          ),
        ),
        StreamBuilder<MediaItem?>(
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
                child: CoverArt(
                  url: item.artUri?.toString(),
                  size: layout.cover,
                  label: item.title,
                  radius: 16,
                ),
              ),
            ),
            const SizedBox(height: 22),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // D-25: judul display 28 (DS 6.9) + marquee untuk judul
                // panjang (bergeser sesudah 3 dtk diam; mati saat
                // gerak-reduksi — D-05).
                MarqueeText(item.title, style: displayStyle(28)),
                const SizedBox(height: 4),
                // UX2 (build 2018): nama artis bisa diketuk membuka halaman
                // artis — pola navigasi yang sama seperti "Buka Artis" di
                // lembar konteks (canOpenArtist/openArtistFromTrack). Trek
                // yang artisnya tak bisa dinavigasi (mis. file lokal tanpa
                // artis) tetap teks biasa.
                if (current != null && canOpenArtist(current))
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => openArtistFromTrack(context, ref, current),
                    child: Text(item.artist ?? '', style: const TextStyle(fontSize: 16, color: ClaiColors.inkSecondary), maxLines: 1, overflow: TextOverflow.ellipsis),
                  )
                else
                  Text(item.artist ?? '', style: const TextStyle(fontSize: 16, color: ClaiColors.inkSecondary), maxLines: 1, overflow: TextOverflow.ellipsis),
              ])),
              IconButton(
                iconSize: 48,
                tooltip: liked ? context.l10n.a11yUnlike : context.l10n.a11yLike,
                icon: ClaiIcon(liked ? ClaiIcons.heartFill : ClaiIcons.heart, color: liked ? ClaiColors.liked : ClaiColors.inkSecondary, size: 28),
                onPressed: () { if (current != null) { ClaiHaptics.like(); ref.read(libraryProvider).toggleLike(current); } },
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
                    icon: ClaiIcons.shuffle,
                    active: shuffleButtonLook(shuffle) != ShuffleButtonLook.off,
                    dot: shuffleButtonLook(shuffle) != ShuffleButtonLook.off,
                    smartBadge: shuffleButtonLook(shuffle) == ShuffleButtonLook.smart,
                    semanticLabel: context.l10n.a11yShuffle,
                    // Tiga keadaan jujur (8051): cerdas memakai lencana
                    // berlian agar tak tertukar murni; ketuk mematikan
                    // mode aktif apa pun, dari mati menyalakan murni
                    // (shuffle_button_state.dart — satu sumber kebenaran).
                    onTap: () => handler.setShuffleMode(shuffleTapTarget(shuffle))),
                  _CtrlButton(icon: ClaiIcons.prev, big: true, semanticLabel: context.l10n.a11yPrevious, onTap: () { ClaiHaptics.armSkipLanding(); handler.skipToPrevious(); }),
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
                  _CtrlButton(icon: ClaiIcons.next, big: true, semanticLabel: context.l10n.a11yNext, onTap: () { ClaiHaptics.armSkipLanding(); handler.skipToNext(); }),
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
              _TextAction(icon: ClaiIcons.lyrics, label: context.l10n.playerLyrics, onTap: () => openLyricsScreen(context)),
              _TextAction(icon: ClaiIcons.queue, label: context.l10n.queueTitle, onTap: () =>
                  Navigator.of(claiRootContext(context)).push(MaterialPageRoute(builder: (_) => const QueueScreen()))),
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
        ),
      ],
    );
  }
}

class _CtrlButton extends StatelessWidget {
  final ClaiIconData icon;
  final bool active, dot, big;

  /// Lencana pembeda mode CERDAS (Ronde 8051): berlian Volt 7 dp di
  /// sudut kanan-atas ikon — tombol acak kini punya tiga wujud yang bisa
  /// dibedakan sekilas (mati redup / murni Volt+titik / cerdas
  /// Volt+titik+berlian), bukan lagi dua.
  final bool smartBadge;
  final VoidCallback onTap;
  final String? semanticLabel;
  const _CtrlButton({required this.icon, required this.onTap, this.active = false, this.dot = false, this.big = false, this.smartBadge = false, this.semanticLabel});
  @override
  Widget build(BuildContext context) => Semantics(
        button: true, label: semanticLabel, toggled: active,
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: onTap,
          child: Padding(padding: const EdgeInsets.all(8), child: Column(mainAxisSize: MainAxisSize.min, children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                ClaiIcon(icon, size: big ? 30 : 24, color: active ? ClaiColors.accent : ClaiColors.ink),
                if (smartBadge)
                  Positioned(
                    right: -3,
                    top: -3,
                    child: Transform.rotate(
                      angle: math.pi / 4,
                      child: Container(width: 7, height: 7, color: ClaiColors.accent),
                    ),
                  ),
              ],
            ),
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

// =====================================================================
// Player B — komposisi papan B dalam bahasa kita (keputusan pemilik
// 2026-11-09 22:22, menggantikan P1 "Sampul Panggung" build 8038;
// kemudi 22:31: baris atas TETAP keping kaca melayang gaya 8038 —
// lingkaran kaca chevron · pil kaca konteks · lingkaran kaca ⋮ —
// baris polos papan B TIDAK diadopsi). Bentuk dari papan: sampul
// persegi beradius bermargin + vinil besar mengintip kanan, blok
// judul di bawah sampul, seek WAVEFORM, transportasi melayang tanpa
// dok kaca dengan tombol putar raksasa, bilah dok berlabel gelap.
// Warna bahasa kita: ruangan mengikuti sampul (Sampul Hidup), tombol
// putar & waveform terputar = nada sampul pekat (Bab 11.9), dok
// berlabel hanya fungsi nyata (Lirik/Antrean/Timer/Suara — tombol
// "Perangkat" papan tidak dibuat; fitur pemilih perangkat keluar
// belum ada). Seluruh badan digerakkan NILAI (bukan provider) agar
// teruji widget mandiri; PlayerSheet mengikatnya ke handler/engine/
// pustaka/perekam waveform.
// =====================================================================

class PlayerBoardBody extends ConsumerWidget {
  final MediaItem item;
  final qe.QueueEngine engine;
  final String contextLabel;
  final bool liked;
  final AmbientUiState amb;
  final Stream<Duration> positionStream;
  final Duration initialPosition;
  final Stream<PlaybackState> playbackStateStream;
  final PlaybackState? initialPlaybackState;
  final int? bitrateKbps;
  final WaveformData? waveformData;
  final VoidCallback onClose;
  final VoidCallback onMore;
  final VoidCallback onLike;
  final bool artistTappable;
  final VoidCallback onArtistTap;
  final ValueChanged<bool> onPlayPause;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onShuffleToggle;
  final VoidCallback onRepeatCycle;
  final ValueChanged<Duration> onSeek;
  final VoidCallback onLyrics;
  final VoidCallback onQueue;
  final VoidCallback onTimer;
  final VoidCallback onVoice;

  const PlayerBoardBody({
    super.key,
    required this.item,
    required this.engine,
    required this.contextLabel,
    required this.liked,
    required this.amb,
    required this.positionStream,
    required this.initialPosition,
    required this.playbackStateStream,
    required this.initialPlaybackState,
    required this.bitrateKbps,
    required this.waveformData,
    required this.onClose,
    required this.onMore,
    required this.onLike,
    required this.artistTappable,
    required this.onArtistTap,
    required this.onPlayPause,
    required this.onPrev,
    required this.onNext,
    required this.onShuffleToggle,
    required this.onRepeatCycle,
    required this.onSeek,
    required this.onLyrics,
    required this.onQueue,
    required this.onTimer,
    required this.onVoice,
  });

  bool _reduceFx(BuildContext context) =>
      amb.reduceEffects ||
      (MediaQuery.maybeDisableAnimationsOf(context) ?? false);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reduceFx = _reduceFx(context);
    // Faktor napas sasaran: keadaan mati total (napas mati / efek
    // dikurangi) = 1,0 persis — nol modulasi, bukan modulasi kecil.
    // 8053 B(i): faktor napas ditonton DI SINI (papan = satu-satunya
    // konsumen napas) lewat select() faktor napas — lembar di atasnya
    // dan seluruh aplikasi tidak lagi dibangun ulang oleh napas.
    final breathFactor =
        ref.watch(ambientControllerProvider.select((s) => s.breathFactor));
    final breathTarget = (amb.breathing && !reduceFx) ? breathFactor : 1.0;
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      child: TweenAnimationBuilder<double>(
        // Interpolasi kontinu antar terbitan amplop (±0,5 Hz): luncuran
        // 900 md mengejar sasaran — bukan tangga diskret (perbaikan U1).
        tween: Tween<double>(begin: 1.0, end: breathTarget),
        duration: reduceFx ? Duration.zero : const Duration(milliseconds: 900),
        curve: Curves.linear,
        builder: (context, bf, _) => LayoutBuilder(
          builder: (context, box) {
            final ts = MediaQuery.textScalerOf(context).scale(1);
            final tone = progressToneFor(amb.palette);
            final layout = playerBoardLayout(
              maxWidth: box.maxWidth,
              maxHeight: box.maxHeight,
              textScale: ts,
              autoplay: engine.autoplayActive,
            );
            return Stack(
              children: [
                // Wash Sampul Hidup di belakang segalanya, alfanya ikut
                // dimodulasi napas (bidang luas yang terlihat).
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  child: AmbientWashLayer(
                    kind: AmbientSurfaceKind.player,
                    heightFraction: 0.66,
                    alphaFactor: bf,
                  ),
                ),
                // Kolom TANPA IntrinsicHeight (pola lembar warisan):
                // sampul & waveform memakai LayoutBuilder, yang
                // dilarang di dalam IntrinsicHeight. Spacer EKSPLISIT
                // dari playerBoardLayout menyerap sisa ruang di atas
                // bilah dok; isi nyata yang lebih tinggi dari taksiran
                // membuat kolom tumbuh & digulir — tidak pernah luapan.
                SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: box.maxHeight),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 8),
                        Padding(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 14),
                          child: _glassHeader(context, reduceFx),
                        ),
                        const SizedBox(height: 16),
                        _coverBlock(context, layout.cover, bf, reduceFx, tone),
                        const SizedBox(height: 20),
                        Padding(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 20),
                          child: _titleRow(context,
                              titleMaxWidth: box.maxWidth - 40 - 56),
                        ),
                        const SizedBox(height: 18),
                        Padding(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 20),
                          child: _waveAndTime(context, tone),
                        ),
                        const SizedBox(height: 14),
                        Padding(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 20),
                          child: _transport(context, tone),
                        ),
                        SizedBox(height: layout.spacer),
                        Padding(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 16),
                          child: _dockBar(context),
                        ),
                        if (engine.autoplayActive)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                            child: _autoplayStrip(context),
                          ),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Baris atas: keping kaca melayang gaya 8038 (kemudi pemilik
  /// 2026-11-09 22:31 — dipertahankan persis, BUKAN baris polos papan
  /// B): lingkaran kaca tutup · pil kaca konteks · lingkaran kaca ⋮.
  Widget _glassHeader(BuildContext context, bool reduceFx) {
    return Row(
      children: [
        _glassChip(
          size: 40,
          reduceFx: reduceFx,
          tooltip: context.l10n.a11yClosePlayer,
          onTap: onClose,
          child: ClaiIcon(ClaiIcons.chevronDown,
              size: 21, color: ClaiColors.ink),
        ),
        const SizedBox(width: 10),
        Expanded(child: _contextPill(context, reduceFx)),
        const SizedBox(width: 10),
        _glassChip(
          size: 40,
          reduceFx: reduceFx,
          tooltip: context.l10n.a11yTrackOptions,
          onTap: onMore,
          child: ClaiIcon(ClaiIcons.moreVert,
              size: 21, color: ClaiColors.ink),
        ),
      ],
    );
  }

  /// Keping kaca gelap melayang (resep 8038: hitam 34%, blur 14, tepi
  /// putih 16%); efek dikurangi → cakram tonal.
  Widget _glassChip({
    required double size,
    required bool reduceFx,
    required String tooltip,
    required VoidCallback onTap,
    required Widget child,
  }) {
    final disc = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: reduceFx
            ? ClaiColors.surface2
            : Colors.black.withValues(alpha: 0.34),
        border: Border.all(
            color: reduceFx
                ? ClaiColors.divider
                : Colors.white.withValues(alpha: 0.16)),
      ),
      child: child,
    );
    return Semantics(
      container: true,
      button: true,
      label: tooltip,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: reduceFx
            ? disc
            : ClipOval(
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                  child: disc,
                ),
              ),
      ),
    );
  }

  /// Pil kaca konteks (label antrean/sumber) — resep 8038.
  Widget _contextPill(BuildContext context, bool reduceFx) {
    final box = Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 13),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: reduceFx
            ? ClaiColors.surface2
            : Colors.black.withValues(alpha: 0.34),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
            color: reduceFx
                ? ClaiColors.divider
                : Colors.white.withValues(alpha: 0.16)),
      ),
      child: Text(
        contextLabel,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: const TextStyle(
            fontSize: 12, fontWeight: FontWeight.w500, color: ClaiColors.ink),
      ),
    );
    if (reduceFx) return box;
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: box,
      ),
    );
  }

  /// Blok sampul papan B: kartu PERSEGI beradius 22 bermargin kiri 16
  /// (bukan tepi-ke-tepi), piringan besar mengintip dari balik sisi
  /// kanan, halo glow bernapas di balik kartu, bayangan kartu jatuh
  /// ke piringan. Tanpa sampul: panel tonal [_StageArt] di kartu yang
  /// sama — piringan tetap mengintip, tetap bermartabat.
  Widget _coverBlock(BuildContext context, double cover, double bf,
      bool reduceFx, Color tone) {
    final palette = amb.palette;
    // Modulasi napas pada ALFA halo glow di balik kartu sampul:
    // bidang radial luas yang terlihat — permukaan U1 di komposisi B.
    final glowColor = palette.glowColor.withValues(
        alpha: breathModulatedAlpha(palette.glowColor.a, bf));
    final discD = cover * 0.97;
    return SizedBox(
      height: cover,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 16 - cover * 0.17,
            top: -cover * 0.17,
            width: cover * 1.34,
            height: cover * 1.34,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    colors: [glowColor, glowColor.withValues(alpha: 0)],
                    stops: const [0, 0.62],
                  ),
                ),
              ),
            ),
          ),
          // Piringan: tepi kanannya 14 dp dari tepi lembar, pusat
          // vertikal sejajar pusat kartu — busur + label menyelinap
          // keluar dari balik kartu (mesin putar 8038, tak berubah).
          Positioned(
            right: 14,
            top: (cover - discD) / 2,
            width: discD,
            height: discD,
            child: StreamBuilder<PlaybackState>(
              stream: playbackStateStream,
              initialData: initialPlaybackState,
              builder: (context, ps) => SpinningVinyl(
                size: discD,
                labelColor: tone,
                active: (ps.data?.playing ?? false) && !reduceFx,
              ),
            ),
          ),
          Positioned(
            left: 16,
            top: 0,
            width: cover,
            height: cover,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                boxShadow: const [
                  BoxShadow(
                    color: Color.fromRGBO(0, 0, 0, 0.45),
                    blurRadius: 24,
                    offset: Offset(8, 10),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: _StageArt(
                    url: item.artUri?.toString(), label: item.title),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Blok judul di BAWAH sampul (papan B): judul display 38 yang
  /// MENYUSUT agar muat (lantai skala 0,68, lalu elipsis — tidak
  /// pernah terpotong tengah kata seperti cacat 8038), artis redup
  /// di bawahnya, hati di kanan baris. [titleMaxWidth] dihitung
  /// pemanggil dari lebar lembar (padding 40 + hati & celah 56).
  Widget _titleRow(BuildContext context, {required double titleMaxWidth}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _FittedTitle(text: item.title, maxWidth: titleMaxWidth),
              const SizedBox(height: 5),
              _artistLine(context),
            ],
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          iconSize: 48,
          tooltip: liked ? context.l10n.a11yUnlike : context.l10n.a11yLike,
          icon: ClaiIcon(
            liked ? ClaiIcons.heartFill : ClaiIcons.heart,
            color: liked ? ClaiColors.liked : ClaiColors.inkSecondary,
            size: 27,
          ),
          onPressed: onLike,
        ),
      ],
    );
  }

  Widget _artistLine(BuildContext context) {
    final palette = amb.palette;
    final text = Text(
      item.artist ?? '',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 16,
        color: palette.active
            ? palette.inkSoftOver(ClaiColors.base)
            : ClaiColors.inkSecondary,
      ),
    );
    if (!artistTappable) return text;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onArtistTap,
      child: text,
    );
  }

  /// Waveform ukur + baris waktu (posisi · slot status jujur · sisa).
  Widget _waveAndTime(BuildContext context, Color tone) {
    final dur = item.duration ?? Duration.zero;
    const numStyle = TextStyle(
      fontSize: 12,
      color: ClaiColors.inkSecondary,
      fontFeatures: [FontFeature.tabularFigures()],
    );
    return StreamBuilder<Duration>(
      stream: positionStream,
      initialData: initialPosition,
      builder: (context, posSnap) {
        final pos = posSnap.data ?? initialPosition;
        final remaining = dur > pos ? dur - pos : Duration.zero;
        return Column(
          children: [
            WaveformSeekBar(
              position: pos,
              duration: dur,
              onSeek: onSeek,
              tone: tone,
              data: waveformData ?? WaveformData.empty,
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                Text(formatDuration(pos), style: numStyle),
                Expanded(
                  child: Center(
                    child: StreamBuilder<PlaybackState>(
                      stream: playbackStateStream,
                      initialData: initialPlaybackState,
                      builder: (context, psSnap) {
                        final st = psSnap.data?.processingState;
                        return _StatusSlot(
                          buffering: st == AudioProcessingState.buffering ||
                              st == AudioProcessingState.loading,
                          bufferingLabel: st == AudioProcessingState.loading
                              ? context.l10n.commonLoading
                              : context.l10n.playerBuffering,
                          bitrateKbps: bitrateKbps,
                        );
                      },
                    ),
                  ),
                ),
                Text(
                    dur == Duration.zero
                        ? '–'
                        : '-${formatDuration(remaining)}',
                    style: numStyle),
              ],
            ),
          ],
        );
      },
    );
  }

  /// Transportasi melayang TANPA dok kaca (papan B): acak · prev ·
  /// PUTAR RAKSASA 76 nada sampul pekat · next · ulang. Keadaan
  /// aktif acak/ulang tetap Volt + titik (domain Volt Bab 11.9).
  Widget _transport(BuildContext context, Color tone) {
    final l10n = context.l10n;
    return StreamBuilder<PlaybackState>(
      stream: playbackStateStream,
      initialData: initialPlaybackState,
      builder: (context, psSnap) {
        final playing = psSnap.data?.playing ?? false;
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _CtrlButton(
              icon: ClaiIcons.shuffle,
              active: shuffleButtonLook(engine.shuffle) != ShuffleButtonLook.off,
              dot: shuffleButtonLook(engine.shuffle) != ShuffleButtonLook.off,
              smartBadge:
                  shuffleButtonLook(engine.shuffle) == ShuffleButtonLook.smart,
              semanticLabel: l10n.a11yShuffle,
              onTap: onShuffleToggle,
            ),
            _CtrlButton(
              icon: ClaiIcons.prev,
              big: true,
              semanticLabel: l10n.a11yPrevious,
              onTap: onPrev,
            ),
            Semantics(
              container: true,
              button: true,
              toggled: playing,
              label: playing ? l10n.a11yPause : l10n.a11yPlay,
              child: PressableScale(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onPlayPause(playing),
                  child: Container(
                    width: 76,
                    height: 76,
                    decoration:
                        BoxDecoration(shape: BoxShape.circle, color: tone),
                    child: ClaiIcon(
                      playing ? ClaiIcons.pause : ClaiIcons.play,
                      size: 38,
                      color: onProgressTone(tone),
                    ),
                  ),
                ),
              ),
            ),
            _CtrlButton(
              icon: ClaiIcons.next,
              big: true,
              semanticLabel: l10n.a11yNext,
              onTap: onNext,
            ),
            _CtrlButton(
              icon: engine.repeat == qe.RepeatMode.one
                  ? ClaiIcons.repeatOne
                  : ClaiIcons.repeat,
              active: engine.repeat != qe.RepeatMode.off,
              dot: engine.repeat != qe.RepeatMode.off,
              semanticLabel: l10n.a11yRepeat,
              onTap: onRepeatCycle,
            ),
          ],
        );
      },
    );
  }

  /// Bilah dok berlabel gelap (papan B): ikon + label untuk fungsi
  /// NYATA saja — Lirik · Antrean · Timer · Suara.
  Widget _dockBar(BuildContext context) {
    final l10n = context.l10n;
    return Container(
      height: 64,
      decoration: BoxDecoration(
        color: ClaiColors.surface2,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: ClaiColors.divider),
      ),
      child: Row(
        children: [
          _DockItem(
              icon: ClaiIcons.lyrics, label: l10n.playerLyrics, onTap: onLyrics),
          _DockItem(
              icon: ClaiIcons.queue, label: l10n.queueTitle, onTap: onQueue),
          _DockItem(
              icon: ClaiIcons.moon, label: l10n.playerTimer, onTap: onTimer),
          _DockItem(
              icon: ClaiIcons.mic, label: l10n.playerVoice, onTap: onVoice),
        ],
      ),
    );
  }

  /// Strip status Putar Otomatis (Sisipan G-3 — kritik pemilik
  /// 2026-11-10 00:24): SATU baris ramping (ikon ∞ Volt + satu baris
  /// teks) menggantikan kartu penuh 3 baris warisan brief 8038 yang
  /// memakan ±12% tinggi lembar dan mendempetkan sampul jauh dari
  /// proporsi papan B. Pengungkapan jujur PRD tidak berubah: strip
  /// hanya tampil saat Putar Otomatis aktif (perilaku tampil kartu
  /// lama), label AUTO di antrean tetap menjadi penanda sambungan,
  /// dan teks penjelasan panjang kini hidup hanya di Player warisan
  /// (tema mati). Lihat DS §6.9.
  Widget _autoplayStrip(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        ClaiIcon(ClaiIcons.infinity, size: 16, color: ClaiColors.accent),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            context.l10n.playerAutoplayStrip,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                fontSize: 13, color: ClaiColors.inkSecondary),
          ),
        ),
      ],
    );
  }
}

/// Satu sel bilah dok berlabel: ikon di atas, label di bawah.
class _DockItem extends StatelessWidget {
  final ClaiIconData icon;
  final String label;
  final VoidCallback onTap;
  const _DockItem({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Semantics(
        button: true,
        label: label,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(26),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ClaiIcon(icon, size: 21, color: ClaiColors.inkSecondary),
              const SizedBox(height: 3),
              Text(label,
                  style: const TextStyle(
                      fontSize: 11, color: ClaiColors.inkSecondary)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Judul display Player yang MENYUSUT agar muat satu baris: lebar
/// teks diukur pada ukuran dasar 38, skala dari [titleScaleForWidth]
/// (lantai 0,68); bila tetap meluap di lantai itu, elipsis mengambil
/// alih. Judul tidak pernah lagi terpotong tengah kata di tepi
/// lembar (cacat build 8038 pada "Love Me Back (Fayah Beat)").
/// [maxWidth] diserahkan pemanggil dari lebar lembar yang sudah
/// diketahui di badan Player.
class _FittedTitle extends StatelessWidget {
  final String text;
  final double maxWidth;
  const _FittedTitle({required this.text, required this.maxWidth});

  @override
  Widget build(BuildContext context) {
    final base = displayStyle(38);
    final painter = TextPainter(
      text: TextSpan(text: text, style: base),
      maxLines: 1,
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final scale = titleScaleForWidth(painter.width, maxWidth);
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: base.copyWith(fontSize: 38 * scale),
    );
  }
}

/// Sampul kartu Player: memenuhi kotaknya (BoxFit.cover) dengan
/// disiplin cache CoverArt. Tanpa sampul / gagal muat = bidang tonal
/// huruf/glyph besar, tetap bermartabat.
class _StageArt extends StatelessWidget {
  final String? url;
  final String label;
  const _StageArt({required this.url, required this.label});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        Widget placeholder() => Container(
              color: ClaiColors.surface2,
              alignment: Alignment.center,
              child: label.isEmpty
                  ? ClaiIcon(ClaiIcons.musicNote,
                      size: 72, color: ClaiColors.inkFaint)
                  : Text(
                      label.substring(0, 1).toUpperCase(),
                      style: const TextStyle(
                          fontSize: 72,
                          fontWeight: FontWeight.w700,
                          color: ClaiColors.inkFaint),
                    ),
            );
        final u = url;
        if (u == null || u.isEmpty) return placeholder();
        final dpr = MediaQuery.devicePixelRatioOf(context);
        final bucket = artworkBucketFor(math.max(c.maxWidth, c.maxHeight), dpr);
        final sizedUrl = artworkUrlForSize(u, bucket) ?? u;
        // Disiplin cacheWidth CoverArt: ytimg → keranjang penuh;
        // selainnya dibatasi lebar tampil × dpr.
        final cacheWidth = sizedUrl.contains('ytimg.com')
            ? bucket
            : math.min(bucket, math.max((c.maxWidth * dpr).ceil(), 1));
        return Image.network(
          sizedUrl,
          key: ValueKey(sizedUrl),
          width: c.maxWidth,
          height: c.maxHeight,
          fit: BoxFit.cover,
          cacheWidth: cacheWidth,
          errorBuilder: (_, __, ___) => placeholder(),
          loadingBuilder: (_, child, progress) =>
              progress == null ? child : placeholder(),
        );
      },
    );
  }
}

/// Seek WAVEFORM UKUR (Ronde Player B): batang-batangnya adalah ember
/// energi NYATA trek ini ([WaveformData]) — terputar = nada sampul
/// pekat, belum terputar = netral redup, belum terukur = garis datar
/// minimal (bukan batang karangan). Titik playhead putih mengikuti
/// posisi. Ketuk = lompat; seret = gosok + gelembung waktu sasaran;
/// onSeek dilepas di akhir seret. Slider semantik ±5% dipertahankan.
class WaveformSeekBar extends StatefulWidget {
  final Duration position;
  final Duration duration;
  final ValueChanged<Duration> onSeek;
  final Color tone;
  final WaveformData data;
  const WaveformSeekBar({
    super.key,
    required this.position,
    required this.duration,
    required this.onSeek,
    required this.tone,
    required this.data,
  });

  @override
  State<WaveformSeekBar> createState() => _WaveformSeekBarState();
}

class _WaveformSeekBarState extends State<WaveformSeekBar> {
  double? _dragFrac;
  bool _dragging = false;

  double get _frac {
    if (_dragFrac != null) return _dragFrac!;
    final total = widget.duration.inMilliseconds;
    if (total <= 0) return 0;
    return (widget.position.inMilliseconds / total).clamp(0.0, 1.0);
  }

  Duration _targetFor(double frac) =>
      Duration(milliseconds: (widget.duration.inMilliseconds * frac).round());

  void _setDrag(double dx, double width) {
    if (width <= 0) return;
    setState(() => _dragFrac = (dx / width).clamp(0.0, 1.0));
  }

  void _nudge(double deltaFrac) {
    final total = widget.duration.inMilliseconds;
    if (total <= 0) return;
    final base = widget.position.inMilliseconds / total;
    widget.onSeek(_targetFor((base + deltaFrac).clamp(0.0, 1.0)));
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        final frac = _frac;
        final pct = (frac * 100).round();
        return Semantics(
          label: context.l10n.a11ySeek,
          value: '$pct%',
          increasedValue: '${(pct + 5).clamp(0, 100)}%',
          decreasedValue: '${(pct - 5).clamp(0, 100)}%',
          onIncrease: () => _nudge(0.05),
          onDecrease: () => _nudge(-0.05),
          child: SizedBox(
            height: 48,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: _WaveformPainter(
                        heights: widget.data.displayHeights(),
                        progress: frac,
                        tone: widget.tone,
                      ),
                    ),
                  ),
                ),
                // Zona ketuk/seret menutupi seluruh bilah.
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapUp: (d) {
                      if (widget.duration <= Duration.zero) return;
                      _setDrag(d.localPosition.dx, w);
                      widget.onSeek(_targetFor(_dragFrac!));
                      setState(() => _dragFrac = null);
                    },
                    onHorizontalDragStart: (d) {
                      setState(() => _dragging = true);
                      _setDrag(d.localPosition.dx, w);
                    },
                    onHorizontalDragUpdate: (d) =>
                        _setDrag(d.localPosition.dx, w),
                    onHorizontalDragEnd: (_) {
                      if (widget.duration > Duration.zero &&
                          _dragFrac != null) {
                        widget.onSeek(_targetFor(_dragFrac!));
                      }
                      setState(() {
                        _dragging = false;
                        _dragFrac = null;
                      });
                    },
                    onHorizontalDragCancel: () => setState(() {
                      _dragging = false;
                      _dragFrac = null;
                    }),
                    child: const SizedBox.expand(),
                  ),
                ),
                // Gelembung waktu sasaran selama menyeret.
                if (_dragging)
                  Positioned(
                    left: (frac * w - 28).clamp(0.0, math.max(0.0, w - 56)),
                    top: 0,
                    child: IgnorePointer(
                      child: Container(
                        width: 56,
                        padding: const EdgeInsets.symmetric(vertical: 5),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                              color: Colors.white.withValues(alpha: 0.16)),
                        ),
                        child: Text(
                          formatDuration(_targetFor(frac)),
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: ClaiColors.ink,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Pelukis waveform ukur: satu batang membulat per ember. Terukur &
/// sudah terlewati playhead → [tone]; terukur & belum → netral redup;
/// belum terukur → garis datar minimal 3 dp (keadaan jujur, bukan
/// batang karangan). Titik playhead putih di posisi [progress].
class _WaveformPainter extends CustomPainter {
  final List<double?> heights;
  final double progress;
  final Color tone;
  const _WaveformPainter({
    required this.heights,
    required this.progress,
    required this.tone,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final n = heights.length;
    if (n == 0 || size.width <= 0) return;
    final slot = size.width / n;
    final barW = math.min(3.2, slot * 0.52);
    final midY = size.height / 2;
    final maxBar = size.height - 12; // ruang napas titik playhead
    final headX = progress * size.width;
    final unmeasured = Paint()..color = Colors.white.withValues(alpha: 0.14);
    final dim = Paint()..color = Colors.white.withValues(alpha: 0.30);
    final played = Paint()..color = tone;
    for (var i = 0; i < n; i++) {
      final cx = slot * i + slot / 2;
      final h = heights[i];
      final double bh;
      final Paint p;
      if (h == null) {
        bh = 3;
        p = unmeasured;
      } else {
        bh = 3 + h * (maxBar - 3);
        p = cx <= headX ? played : dim;
      }
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(cx, midY), width: barW, height: bh),
          Radius.circular(barW / 2),
        ),
        p,
      );
    }
    // Titik playhead putih (penanda posisi papan B).
    canvas.drawCircle(
      Offset(headX.clamp(5.5, size.width - 5.5), midY),
      5.5,
      Paint()..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(_WaveformPainter old) =>
      old.progress != progress || old.tone != tone || old.heights != heights;
}

/// Piringan hitam berputar (permintaan pemilik 2026-11-09 11:19) —
/// mengintip dari balik tepi kanan sampul panggung P1. Berputar
/// selama [active]; saat jeda kecepatannya MEREDA eksponensial
/// sampai berhenti (bukan rem mendadak), dan berakselerasi lagi saat
/// putar lanjut. Pemanggil mematikan [active] bila efek dikurangi;
/// Ticker bawaan juga membisu bila lembar tertutup rute legap lain
/// (TickerMode) — piringan tidak berputar di luar pandangan.
class SpinningVinyl extends StatefulWidget {
  final double size;

  /// Warna label tengah cakram (nada sampul pekat pemanggil).
  final Color labelColor;
  final bool active;
  const SpinningVinyl({
    super.key,
    required this.size,
    required this.labelColor,
    required this.active,
  });

  @override
  State<SpinningVinyl> createState() => _SpinningVinylState();
}

class _SpinningVinylState extends State<SpinningVinyl>
    with SingleTickerProviderStateMixin {
  /// Periode satu putaran pada kecepatan penuh: 3,6 detik (±16,7 rpm
  /// visual — separuh laju 33⅓ rpm piringan asli; cukup cepat untuk
  /// terbaca sebagai putaran, cukup lambat untuk terasa mewah).
  static const double periodSeconds = 3.6;

  /// Konstanta waktu reda/akselerasi kecepatan (detik).
  static const double _tauSeconds = 0.9;

  late final Ticker _ticker = createTicker(_onTick);
  Duration _last = Duration.zero;
  double _angle = 0;
  double _velocity = 0; // 0 diam .. 1 kecepatan penuh

  @override
  void initState() {
    super.initState();
    _ticker.start();
  }

  void _onTick(Duration now) {
    if (_last == Duration.zero) {
      _last = now;
      return;
    }
    final dt = (now - _last).inMicroseconds / 1e6;
    _last = now;
    if (dt <= 0) return;
    final target = widget.active ? 1.0 : 0.0;
    _velocity += (target - _velocity) * (1 - math.exp(-dt / _tauSeconds));
    if (!widget.active && _velocity < 0.01) {
      // Sudah berhenti secara persepsi (<1% kecepatan penuh = rayapan
      // < 0,02 rad/dtk): bekukan tanpa setState berulang.
      _velocity = 0;
      return;
    }
    setState(() {
      _angle =
          (_angle + _velocity * dt * 2 * math.pi / periodSeconds) %
              (2 * math.pi);
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: _angle,
      child: CustomPaint(
        size: Size.square(widget.size),
        painter: _VinylPainter(widget.labelColor),
      ),
    );
  }
}

/// Lukisan cakram: badan hitam pekat bercahaya radial halus, alur
/// konsentris sangat tipis, satu busur kilau, label tengah bernada
/// sampul, lubang poros. Bahasa DS: gelap, halus, tidak berisik.
/// Statis — yang berputar adalah bingkainya (Transform.rotate).
class _VinylPainter extends CustomPainter {
  final Color labelColor;
  const _VinylPainter(this.labelColor);

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2;
    final body = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.35, -0.35),
        radius: 1.05,
        colors: const [Color(0xFF232329), Color(0xFF0B0B0F)],
        stops: const [0, 0.75],
      ).createShader(Rect.fromCircle(center: c, radius: r));
    canvas.drawCircle(c, r, body);
    final groove = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.white.withValues(alpha: 0.05);
    for (var i = 0; i < 7; i++) {
      canvas.drawCircle(c, r * (0.52 + i * 0.065), groove);
    }
    final sheen = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.16
      ..strokeCap = StrokeCap.round
      ..color = Colors.white.withValues(alpha: 0.045);
    canvas.drawArc(
        Rect.fromCircle(center: c, radius: r * 0.78), -2.2, 0.9, false, sheen);
    canvas.drawCircle(c, r * 0.30, Paint()..color = labelColor);
    canvas.drawCircle(
        c,
        r * 0.30,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = Colors.white.withValues(alpha: 0.14));
    canvas.drawCircle(c, r * 0.045, Paint()..color = const Color(0xFF050507));
    canvas.drawCircle(
        c,
        r * 0.045,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = Colors.white.withValues(alpha: 0.25));
  }

  @override
  bool shouldRepaint(_VinylPainter old) => old.labelColor != labelColor;
}
