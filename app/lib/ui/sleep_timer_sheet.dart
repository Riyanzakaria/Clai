import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/l10n.dart';

import '../app.dart';
import '../core/clai_icons.dart';
import '../core/tokens.dart';

Future<void> openSleepTimerSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: ClaiColors.surface1,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => const FractionallySizedBox(
        heightFactor: 0.55, child: SleepTimerSheet()),
  );
}

/// Lembar timer tidur (F2 Batch 2): menit, akhir lagu, batalkan.
/// Sisa waktu diperbarui tiap detik selama lembar terbuka.
class SleepTimerSheet extends ConsumerStatefulWidget {
  const SleepTimerSheet({super.key});
  @override
  ConsumerState<SleepTimerSheet> createState() => _SleepTimerSheetState();
}

class _SleepTimerSheetState extends ConsumerState<SleepTimerSheet> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  String _remainingLabel(Duration? d) {
    if (d == null) return '';
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return context.l10n.sleepRemaining('${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}');
  }

  @override
  Widget build(BuildContext context) {
    final sleep = ref.watch(sleepServiceProvider);
    final active = sleep.active;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Center(
            child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: ClaiColors.surface3,
                    borderRadius: BorderRadius.circular(2)))),
        const SizedBox(height: 18),
        Text(context.l10n.sleepTitle,
            style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: ClaiColors.ink)),
        const SizedBox(height: 6),
        Text(
            active == null
                ? context.l10n.sleepSubOff
                : active.mode == 'minutes'
                    ? context.l10n.sleepSubMinutes(_remainingLabel(sleep.remaining))
                    : context.l10n.sleepSubEndOfSong,
            style: const TextStyle(color: ClaiColors.inkSecondary, height: 1.45)),
        const SizedBox(height: 18),
        for (final m in [15, 30, 45, 60])
          ListTile(
            title: Text(context.l10n.sleepMinutes(m),
                style: const TextStyle(color: ClaiColors.ink)),
            // D-35 (DS 6.13): tanda centang memakai glif Clai sendiri,
            // bukan Icons.check Material.
            trailing: active?.mode == 'minutes' && active?.minutes == m
                ? ClaiIcon(ClaiIcons.check, color: ClaiColors.accent)
                : null,
            onTap: () {
              ref.read(sleepServiceProvider).startMinutes(m);
              Navigator.of(context).pop();
            },
          ),
        ListTile(
          title: Text(context.l10n.sleepEndOfSong,
              style: const TextStyle(color: ClaiColors.ink)),
          trailing: active?.mode == 'endOfSong'
              ? ClaiIcon(ClaiIcons.check, color: ClaiColors.accent)
              : null,
          onTap: () {
            ref.read(sleepServiceProvider).startEndOfSong();
            Navigator.of(context).pop();
          },
        ),
        if (active != null)
          ListTile(
            title: Text(context.l10n.sleepCancel,
                style: const TextStyle(color: ClaiColors.warning)),
            onTap: () {
              ref.read(sleepServiceProvider).cancel();
              Navigator.of(context).pop();
            },
          ),
      ]),
    );
  }
}
