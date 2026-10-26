import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app.dart';
import '../core/clai_icons.dart';
import '../core/tokens.dart';
import '../l10n/l10n.dart';
import 'voice_sheet.dart';

/// Layar Mode Berkendara (F2 Batch 2, PRD 5.14 A): permukaan sentuh raksasa.
/// - Tombol ≥ 72dp (putar 120dp, sebelum/berikutnya 96dp).
/// - Usap horizontal di mana saja: kiri → berikutnya, kanan → sebelumnya.
/// - Sakelar pengumuman & volume-kecepatan di tempat (tanpa ke Pengaturan).
class DrivingScreen extends ConsumerWidget {
  const DrivingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final handler = ref.watch(audioHandlerProvider);
    final driving = ref.watch(drivingServiceProvider);
    return Scaffold(
      backgroundColor: ClaiColors.surface1,
      body: SafeArea(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragEnd: (d) {
            final v = d.primaryVelocity ?? 0;
            if (v < -200) {
              handler.skipToNext();
            } else if (v > 200) {
              handler.skipToPrevious();
            }
          },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: Column(children: [
              Row(children: [
                Expanded(
                    child: Text(context.l10n.drvMode,
                        style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: ClaiColors.ink))),
                TextButton(
                  onPressed: () async {
                    await driving.setOn(false);
                    if (context.mounted) Navigator.of(context).pop();
                  },
                  child: Text(context.l10n.drvExit,
                      style: const TextStyle(color: ClaiColors.accent)),
                ),
              ]),
              const SizedBox(height: 8),
              Text(context.l10n.drvSwipeHint,
                  style: const TextStyle(color: ClaiColors.inkSecondary, fontSize: 13)),
              const Spacer(),
              StreamBuilder<MediaItem?>(
                stream: handler.mediaItem.stream,
                initialData: handler.mediaItem.valueOrNull,
                builder: (context, snap) {
                  final item = snap.data;
                  return Column(children: [
                    Text(item?.title ?? context.l10n.drvNoSong,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w700,
                            color: ClaiColors.ink)),
                    const SizedBox(height: 8),
                    Text(item?.artist ?? '',
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 18, color: ClaiColors.inkSecondary)),
                  ]);
                },
              ),
              const Spacer(),
              StreamBuilder<PlaybackState>(
                stream: handler.playbackState.stream,
                initialData: handler.playbackState.valueOrNull,
                builder: (context, ps) {
                  final playing = ps.data?.playing ?? false;
                  return Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _giantButton(
                            size: 96,
                            icon: ClaiIcons.prev,
                            label: context.l10n.a11yPrevious,
                            onTap: () => handler.skipToPrevious()),
                        const SizedBox(width: 20),
                        _giantButton(
                            size: 120,
                            filled: true,
                            icon: playing ? ClaiIcons.pause : ClaiIcons.play,
                            label: playing ? context.l10n.a11yPause : context.l10n.a11yPlay,
                            onTap: () =>
                                playing ? handler.pauseNow() : handler.playNow()),
                        const SizedBox(width: 20),
                        _giantButton(
                            size: 96,
                            icon: ClaiIcons.next,
                            label: context.l10n.a11yNext,
                            onTap: () => handler.skipToNext()),
                      ]);
                },
              ),
              const SizedBox(height: 28),
              SwitchListTile(
                title: Text(context.l10n.drvAnnounce,
                    style: const TextStyle(color: ClaiColors.ink)),
                subtitle: Text(context.l10n.drvAnnounceSubShort,
                    style: const TextStyle(color: ClaiColors.inkSecondary)),
                value: driving.announceOn,
                activeThumbColor: ClaiColors.accent,
                onChanged: (v) => driving.setAnnounce(v),
              ),
              SwitchListTile(
                title: Text(context.l10n.drvSpeedVolume,
                    style: const TextStyle(color: ClaiColors.ink)),
                subtitle: Text(context.l10n.drvSpeedVolumeNote,
                    style: const TextStyle(color: ClaiColors.inkSecondary)),
                value: driving.speedVolumeOn,
                activeThumbColor: ClaiColors.accent,
                onChanged: (v) => driving.setSpeedVolume(v),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                    backgroundColor: ClaiColors.accent,
                    foregroundColor: ClaiColors.onAccent,
                    minimumSize: const Size.fromHeight(72)),
                onPressed: () => openVoiceSheet(context),
                icon: ClaiIcon(ClaiIcons.mic, size: 26),
                label: Text(context.l10n.drvSchemeVoice,
                    style: const TextStyle(fontSize: 18)),
              ),
              SizedBox(height: bottomChromeClearance(context)),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _giantButton(
      {required double size,
      required ClaiIconData icon,
      required String label,
      required VoidCallback onTap,
      bool filled = false}) {
    // D-01: tombol raksasa berkendara wajib bernama untuk TalkBack.
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
              color: filled ? ClaiColors.accent : ClaiColors.surface2,
              shape: BoxShape.circle),
          child: ClaiIcon(icon,
              color: filled ? ClaiColors.onAccent : ClaiColors.ink,
              size: size * 0.42),
        ),
      ),
    );
  }
}
