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
    // Gelombang 2 (pola pengaturan.md): seksi ini kini menyusun
    // keluarganya sendiri — Mode & Skema / Kalibrasi / Kendaraan —
    // masing-masing berkicker + panel; slider kalibrasi menjadi blok
    // lebar-penuh (dulu terjepit 160 dp di trailing). Perilaku semua
    // kendali (izin lokasi, buka layar Menyetir, tanda kendaraan)
    // tidak berubah.
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _section(s.drvMode, [
        SwitchListTile(
          secondary: tonalIconBox(ClaiIcons.radio, size: 40, iconSize: 20),
          title: Text(s.drvMode, style: const TextStyle(color: ClaiColors.ink)),
          subtitle: Text(s.drvModeSub,
              style: const TextStyle(color: ClaiColors.inkSecondary)),
          value: driving.on,
          onChanged: (v) async {
            await driving.setOn(v);
            if (v && context.mounted) {
              // Audit 8047 (#16): layar Menyetir tetap didorong pada
              // navigator CANGKANG — navigator akar berada di LUAR
              // ProviderScope aplikasi (log insiden membuktikan
              // "No ProviderScope found" saat dicoba). Chrome cangkang
              // ditekan dari dalam app.dart lewat bendera
              // claiChromeSuppressed (Opacity + IgnorePointer).
              Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const DrivingScreen()));
            }
          },
        ),
        DropdownTile<String>(
          title: s.drvScheme,
          leading: tonalIconBox(ClaiIcons.settings, size: 40, iconSize: 20),
          subtitle: s.drvSchemeSub,
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
        SwitchListTile(
          secondary: tonalIconBox(ClaiIcons.mic, size: 40, iconSize: 20),
          title: Text(s.drvAnnounce, style: const TextStyle(color: ClaiColors.ink)),
          subtitle: Text(s.drvAnnounceSub,
              style: const TextStyle(color: ClaiColors.inkSecondary)),
          value: driving.announceOn,
          onChanged: (v) => driving.setAnnounce(v),
        ),
        SwitchListTile(
          secondary: tonalIconBox(ClaiIcons.gauge, size: 40, iconSize: 20),
          title: Text(s.drvSpeedVolume, style: const TextStyle(color: ClaiColors.ink)),
          subtitle: Text(s.drvSpeedVolumeSub,
              style: const TextStyle(color: ClaiColors.inkSecondary)),
          value: driving.speedVolumeOn,
          onChanged: (v) async {
            if (v) {
              final granted = await Permission.location.isGranted ||
                  await Permission.location.request().isGranted;
              if (!granted) return;
            }
            await driving.setSpeedVolume(v);
          },
        ),
      ]),
      if (driving.speedVolumeOn)
        _section(s.drvSpeedVolume, [
          SettingsSliderBlock(
            title: s.drvVolStop,
            subtitle: s.drvVolPct((driving.stopVolume * 100).round()),
            value: driving.stopVolume,
            min: 0.1,
            max: 1.0,
            onChanged: (v) => driving.setCalibration(
                stop: v, fast: driving.fastVolume, anchor: driving.anchorKmh),
          ),
          SettingsSliderBlock(
            title: s.drvVolFast,
            subtitle: s.drvVolFastSub((driving.fastVolume * 100).round()),
            value: driving.fastVolume,
            min: 0.1,
            max: 1.0,
            onChanged: (v) => driving.setCalibration(
                stop: driving.stopVolume, fast: v, anchor: driving.anchorKmh),
          ),
          SettingsSliderBlock(
            title: s.drvAnchor,
            subtitle: s.drvAnchorSub(driving.anchorKmh.round()),
            value: driving.anchorKmh,
            min: 40,
            max: 120,
            divisions: 16,
            onChanged: (v) => driving.setCalibration(
                stop: driving.stopVolume,
                fast: driving.fastVolume,
                anchor: v),
          ),
        ]),
      _section(s.drvVehicles, [
        ListTile(
          leading: tonalIconBox(ClaiIcons.phone, size: 40, iconSize: 20, color: ClaiColors.inkSecondary),
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
      ]),
    ]);
  }

  /// Seksi berkicker + panel, gaya yang sama seperti settingsSection
  /// di settings_screen (disalin kecil di sini agar seksi ini tetap
  /// mandiri — settings_screen mengimpor berkas ini, bukan sebaliknya).
  Widget _section(String kicker, List<Widget> rows) {
    final children = <Widget>[];
    for (var i = 0; i < rows.length; i++) {
      if (i > 0) {
        children.add(const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Divider(height: 1, color: ClaiColors.divider),
        ));
      }
      children.add(rows[i]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 0),
        child: Text(
          kicker.toUpperCase(),
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.8,
            color: ClaiColors.inkSecondary,
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Container(
          decoration: BoxDecoration(
            color: ClaiColors.surface1,
            borderRadius: BorderRadius.circular(20),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(children: children),
        ),
      ),
    ]);
  }
}
