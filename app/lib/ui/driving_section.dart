import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../app.dart';
import '../core/clai_icons.dart';
import '../core/tokens.dart';
import '../l10n/l10n.dart';
import 'driving_screen.dart';
import 'widgets.dart';

/// Seksi Berkendara di Pengaturan (F2 Batch 2): sakelar manual, skema
/// kendali, kalibrasi volume-kecepatan, penanda perangkat kendaraan.
/// Perangkat Bluetooth kosong di emulator — dinyatakan jujur, bukan galat.
class DrivingSection extends ConsumerStatefulWidget {
  const DrivingSection({super.key});
  @override
  ConsumerState<DrivingSection> createState() => _DrivingSectionState();
}

class _DrivingSectionState extends ConsumerState<DrivingSection> {
  List<String>? _bonded;

  Future<void> _loadBonded() async {
    final driving = ref.read(drivingServiceProvider);
    final granted = await Permission.bluetoothConnect.isGranted ||
        await Permission.bluetoothConnect.request().isGranted;
    if (!granted) {
      if (mounted) setState(() => _bonded = []);
      return;
    }
    final list = await driving.bondedDevices();
    if (mounted) setState(() => _bonded = list);
  }

  @override
  Widget build(BuildContext context) {
    final driving = ref.watch(drivingServiceProvider);
    final s = context.l10n;
    return Column(children: [
      SwitchListTile(
        title: Text(s.drvMode, style: const TextStyle(color: ClaiColors.ink)),
        subtitle: Text(s.drvModeSub,
            style: const TextStyle(color: ClaiColors.inkSecondary)),
        value: driving.on,
        activeThumbColor: ClaiColors.accent,
        onChanged: (v) async {
          await driving.setOn(v);
          if (v && context.mounted) {
            Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const DrivingScreen()));
          }
        },
      ),
      ListTile(
        title: Text(s.drvScheme, style: const TextStyle(color: ClaiColors.ink)),
        subtitle: Text(s.drvSchemeSub,
            style: const TextStyle(color: ClaiColors.inkSecondary)),
        trailing: BoundedDropdown<String>(
          value: driving.scheme,
          items: [
            DropdownMenuItem(value: 'buttons', child: Text(s.drvSchemeButtons)),
            DropdownMenuItem(value: 'patterns', child: Text(s.drvSchemePatterns)),
            DropdownMenuItem(value: 'voice', child: Text(s.drvSchemeVoice)),
          ],
          onChanged: (v) async {
            if (v == null) return;
            await driving.setScheme(v);
          },
        ),
      ),
      SwitchListTile(
        title: Text(s.drvAnnounce, style: const TextStyle(color: ClaiColors.ink)),
        subtitle: Text(s.drvAnnounceSub,
            style: const TextStyle(color: ClaiColors.inkSecondary)),
        value: driving.announceOn,
        activeThumbColor: ClaiColors.accent,
        onChanged: (v) => driving.setAnnounce(v),
      ),
      SwitchListTile(
        title: Text(s.drvSpeedVolume, style: const TextStyle(color: ClaiColors.ink)),
        subtitle: Text(s.drvSpeedVolumeSub,
            style: const TextStyle(color: ClaiColors.inkSecondary)),
        value: driving.speedVolumeOn,
        activeThumbColor: ClaiColors.accent,
        onChanged: (v) async {
          if (v) {
            final granted = await Permission.location.isGranted ||
                await Permission.location.request().isGranted;
            if (!granted) return;
          }
          await driving.setSpeedVolume(v);
        },
      ),
      if (driving.speedVolumeOn) ...[
        ListTile(
          title: Text(s.drvVolStop, style: const TextStyle(color: ClaiColors.ink)),
          subtitle: Text(s.drvVolPct((driving.stopVolume * 100).round()),
              style: const TextStyle(color: ClaiColors.inkSecondary)),
          trailing: SizedBox(
            width: 160,
            child: Slider(
              value: driving.stopVolume,
              min: 0.1,
              max: 1.0,
              activeColor: ClaiColors.accent,
              onChanged: (v) => driving.setCalibration(
                  stop: v, fast: driving.fastVolume, anchor: driving.anchorKmh),
            ),
          ),
        ),
        ListTile(
          title: Text(s.drvVolFast, style: const TextStyle(color: ClaiColors.ink)),
          subtitle: Text(s.drvVolFastSub((driving.fastVolume * 100).round()),
              style: const TextStyle(color: ClaiColors.inkSecondary)),
          trailing: SizedBox(
            width: 160,
            child: Slider(
              value: driving.fastVolume,
              min: 0.1,
              max: 1.0,
              activeColor: ClaiColors.accent,
              onChanged: (v) => driving.setCalibration(
                  stop: driving.stopVolume, fast: v, anchor: driving.anchorKmh),
            ),
          ),
        ),
        ListTile(
          title: Text(s.drvAnchor, style: const TextStyle(color: ClaiColors.ink)),
          subtitle: Text(s.drvAnchorSub(driving.anchorKmh.round()),
              style: const TextStyle(color: ClaiColors.inkSecondary)),
          trailing: SizedBox(
            width: 160,
            child: Slider(
              value: driving.anchorKmh,
              min: 40,
              max: 120,
              divisions: 16,
              activeColor: ClaiColors.accent,
              onChanged: (v) => driving.setCalibration(
                  stop: driving.stopVolume,
                  fast: driving.fastVolume,
                  anchor: v),
            ),
          ),
        ),
      ],
      ListTile(
        leading: ClaiIcon(ClaiIcons.phone, color: ClaiColors.inkSecondary),
        title: Text(s.drvVehicles,
            style: const TextStyle(color: ClaiColors.ink)),
        subtitle: Text(
            _bonded == null
                ? s.drvVehiclesHint
                : _bonded!.isEmpty
                    ? s.drvVehiclesNone
                    : s.drvVehiclesCount(_bonded!.length),
            style: const TextStyle(color: ClaiColors.inkSecondary)),
        trailing: ClaiIcon(ClaiIcons.chevronRight, color: ClaiColors.inkFaint),
        onTap: _loadBonded,
      ),
      if (_bonded != null)
        for (final name in _bonded!)
          CheckboxListTile(
            title: Text(name, style: const TextStyle(color: ClaiColors.ink)),
            subtitle: Text(s.drvMarkVehicle,
                style: const TextStyle(color: ClaiColors.inkSecondary)),
            value: driving.vehicles.contains(name),
            activeColor: ClaiColors.accent,
            onChanged: (v) async {
              if (v == true) {
                await driving.markVehicle(name);
              } else {
                await driving.unmarkVehicle(name);
              }
            },
          ),
    ]);
  }
}
