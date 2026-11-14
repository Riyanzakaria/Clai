import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/l10n.dart';

import '../app.dart';
import '../core/clai_icons.dart';
import '../core/tokens.dart';
import 'haptics.dart';
import 'widgets.dart';

/// Format sisa hitung mundur timer tidur "MM:SS" (Ronde 8059, frame
/// Stitch "Sleep Timer — Active Countdown State": sisa waktu tampil
/// BESAR sebagai angka pahlawan, bukan hanya di dalam kalimat subjudul).
/// Murni & teruji unit: negatif dijepit ke nol, detik pecahan dibuang,
/// menit tidak dibatasi dua digit (preset maksimum 60 → "60:00").
String formatSleepCountdown(Duration d) {
  final clamped = d.isNegative ? Duration.zero : d;
  final m = clamped.inMinutes;
  final s = clamped.inSeconds % 60;
  return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
}

Future<void> openSleepTimerSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: claiRootContext(context),
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
    return context.l10n.sleepRemaining(formatSleepCountdown(d));
  }

  @override
  Widget build(BuildContext context) {
    final sleep = ref.watch(sleepServiceProvider);
    final active = sleep.active;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
      // Ronde 8059: isi kini bisa digulir (pola rangka lembar DS) —
      // blok hitung mundur keadaan aktif menambah tinggi, dan sheet
      // 55% NYATA pada layar pendek tidak boleh meluap; gulir hanya
      // terpakai bila isi memang melebihi tinggi lembar.
      child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Center(child: SheetHandle()),
        const SizedBox(height: 18),
        Text(context.l10n.sleepTitle, style: displayStyle(20)),
        const SizedBox(height: 6),
        Text(
            active == null
                ? context.l10n.sleepSubOff
                : active.mode == 'minutes'
                    ? context.l10n.sleepSubMinutes(_remainingLabel(sleep.remaining))
                    : context.l10n.sleepSubEndOfSong,
            style: const TextStyle(color: ClaiColors.inkSecondary, height: 1.45)),
        const SizedBox(height: 18),
        if (active?.mode == 'minutes') ...[
          // Frame Stitch "Sleep Timer — Active Countdown State"
          // dipadatkan ke sheet 55% nyata (kanvas frame lebih tinggi
          // dari layar): sisa waktu tampil BESAR (angka pahlawan
          // tabular, berdetak tiap detik lewat ticker lembar) di
          // bawah subjudul; ikon di titik ini = "dark_mode" resmi
          // (padanan ikon header frame Active Stitch), sedangkan
          // baris preset, dok Player & kartu Lanjut Besok memakai
          // "bedtime" resmi (Ronde 8061).
          Center(
            child: Column(children: [
              ClaiIcon(ClaiIcons.darkMode, color: ClaiColors.accent, size: 24),
              const SizedBox(height: 6),
              Text(
                formatSleepCountdown(sleep.remaining ?? Duration.zero),
                key: const Key('sleepCountdownHero'),
                style: heroStyle(40),
              ),
            ]),
          ),
          const SizedBox(height: 18),
        ],
        // Baris pilihan (Ronde Sapuan 8045): tata bahasa baris
        // lembar DS — tinggi 52, label 17, ikon berkotak tonal;
        // centang tetap glif Clai sendiri (D-35).
        for (final m in [15, 30, 45, 60])
          _timerRow(
            icon: ClaiIcons.bedtime,
            label: context.l10n.sleepMinutes(m),
            checked: active?.mode == 'minutes' && active?.minutes == m,
            onTap: () {
              ClaiHaptics.timerSet();
              ref.read(sleepServiceProvider).startMinutes(m);
              Navigator.of(context).pop();
            },
          ),
        _timerRow(
          icon: ClaiIcons.musicNote,
          label: context.l10n.sleepEndOfSong,
          checked: active?.mode == 'endOfSong',
          onTap: () {
            ClaiHaptics.timerSet();
            ref.read(sleepServiceProvider).startEndOfSong();
            Navigator.of(context).pop();
          },
        ),
        if (active != null)
          _timerRow(
            icon: ClaiIcons.close,
            label: context.l10n.sleepCancel,
            labelColor: ClaiColors.warning,
            iconColor: ClaiColors.warning,
            onTap: () {
              ref.read(sleepServiceProvider).cancel();
              Navigator.of(context).pop();
            },
          ),
          ])),
    );
  }
}


/// Satu baris pilihan lembar Timer (DS 6.8): kotak ikon tonal 40,
/// label 17, centang Volt di kanan bila pilihan ini yang aktif.
Widget _timerRow({
  required ClaiIconData icon,
  required String label,
  bool checked = false,
  Color labelColor = ClaiColors.ink,
  Color iconColor = ClaiColors.accent,
  required VoidCallback onTap,
}) {
  return InkWell(
    onTap: onTap,
    child: Container(
      constraints: const BoxConstraints(minHeight: 52),
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        tonalIconBox(icon, size: 40, iconSize: 20, color: iconColor),
        const SizedBox(width: 14),
        Expanded(
          child: Text(label,
              style: TextStyle(color: labelColor, fontSize: 17)),
        ),
        if (checked) ClaiIcon(ClaiIcons.check, color: ClaiColors.accent),
      ]),
    ),
  );
}
