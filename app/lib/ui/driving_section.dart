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
    final granted =
        await Permission.bluetoothConnect.isGranted ||
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _section(s.drvMode, [
          // Ronde 8084: baris-baris seksi ini terkunci 60 / label
          // 15/600 / state 13 satu baris, glyph ikon 24.
          SwitchListTile(
            minTileHeight: 60,
            secondary: rowLeadIcon(ClaiIcons.radio, size: 40, iconSize: 24),
            title: Text(maxLines: 1, overflow: TextOverflow.ellipsis, 
              s.drvMode,
              style: rowTitleStyle(),
            ),
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
                  MaterialPageRoute(builder: (_) => const DrivingScreen()),
                );
              }
            },
          ),
          DropdownTile<String>(
            // Ronde 8084 (dari W5): flush — padding horizontal internal
            // 0 agar sejajar panel klon _section di berkas ini.
            flush: true,
            title: s.drvScheme,
            leading: rowLeadIcon(ClaiIcons.settings, size: 40, iconSize: 24),
            value: driving.scheme,
            items: [
              DropdownMenuItem(
                value: 'buttons',
                child: Text(s.drvSchemeButtons),
              ),
              DropdownMenuItem(
                value: 'patterns',
                child: Text(s.drvSchemePatterns),
              ),
              DropdownMenuItem(value: 'voice', child: Text(s.drvSchemeVoice)),
            ],
            onChanged: (v) async {
              if (v == null) return;
              await driving.setScheme(v);
            },
          ),
          SwitchListTile(
            minTileHeight: 60,
            secondary: rowLeadIcon(ClaiIcons.mic, size: 40, iconSize: 24),
            title: Text(maxLines: 1, overflow: TextOverflow.ellipsis, 
              s.drvAnnounce,
              style: rowTitleStyle(),
            ),
            value: driving.announceOn,
            onChanged: (v) => driving.setAnnounce(v),
          ),
          SwitchListTile(
            minTileHeight: 60,
            secondary: rowLeadIcon(ClaiIcons.gauge, size: 40, iconSize: 24),
            title: Text(maxLines: 1, overflow: TextOverflow.ellipsis, 
              s.drvSpeedVolume,
              style: rowTitleStyle(),
            ),
            value: driving.speedVolumeOn,
            onChanged: (v) async {
              if (v) {
                final granted =
                    await Permission.location.isGranted ||
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
                stop: v,
                fast: driving.fastVolume,
                anchor: driving.anchorKmh,
              ),
            ),
            SettingsSliderBlock(
              title: s.drvVolFast,
              subtitle: s.drvVolFastSub((driving.fastVolume * 100).round()),
              value: driving.fastVolume,
              min: 0.1,
              max: 1.0,
              onChanged: (v) => driving.setCalibration(
                stop: driving.stopVolume,
                fast: v,
                anchor: driving.anchorKmh,
              ),
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
                anchor: v,
              ),
            ),
          ]),
        _section(s.drvVehicles, [
          ListTile(
            minTileHeight: 60,
            titleTextStyle: const TextStyle(
              fontFamily: kDisplayFontFamily,
              fontSize: kRowTitleSize,
              fontWeight: FontWeight.w700,
              color: ClaiColors.ink,
            ),
            subtitleTextStyle: const TextStyle(
              fontSize: 13,
              color: ClaiColors.inkSecondary,
            ),
            leading: rowLeadIcon(
              ClaiIcons.phone,
              size: 40,
              iconSize: 24,
              color: ClaiColors.inkSecondary,
            ),
            title: Text(maxLines: 1, overflow: TextOverflow.ellipsis, 
              s.drvVehicles,
              style: rowTitleStyle(),
            ),
            // Keadaan belum dimuat: tanpa subjudul (petunjuk ketuk dibuang
            // oleh sapuan tegas 8081); none/count adalah keadaan, tetap.
            subtitle: _bonded == null
                ? null
                : Text(
                    _bonded!.isEmpty
                        ? s.drvVehiclesNone
                        : s.drvVehiclesCount(_bonded!.length),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      color: ClaiColors.inkSecondary,
                    ),
                  ),
            trailing: ClaiIcon(
              ClaiIcons.chevronRight,
              color: ClaiColors.inkFaint,
            ),
            onTap: _loadBonded,
          ),
          if (_bonded != null)
            for (final name in _bonded!)
              // Ronde 8084: subjudul instruksi drvMarkVehicle DIBUANG
              // (§13.2) — label kendaraan + checkbox tetap persis.
              CheckboxListTile(
                minTileHeight: 60,
                title: Text(maxLines: 1, overflow: TextOverflow.ellipsis, 
                  name,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: ClaiColors.ink,
                  ),
                ),
                value: driving.vehicles.contains(name),
                activeColor: ClaiColors.signal,
                onChanged: (v) async {
                  if (v == true) {
                    await driving.markVehicle(name);
                  } else {
                    await driving.unmarkVehicle(name);
                  }
                },
              ),
        ]),
      ],
    );
  }

  /// Seksi berlabel + baris, gaya Pola Pengaturan baru (Ronde 8083)
  /// yang sama seperti settingsSection di settings_screen (disalin
  /// kecil di sini agar seksi ini tetap mandiri — settings_screen
  /// mengimpor berkas ini, bukan sebaliknya): label sentence-case
  /// 13 w600 inkSecondary (padding atas 18, jarak ke baris 4), baris
  /// langsung di atas latar halaman padding horizontal 20, hairline
  /// antar baris inset 72 sejajar awal teks baris. Wadah kartu tonal
  /// surface-1 radius 20 yang dulu dibangun berkas ini sendiri pensiun.
  Widget _section(String kicker, List<Widget> rows) {
    final children = <Widget>[];
    for (var i = 0; i < rows.length; i++) {
      if (i > 0) {
        children.add(
          const Padding(
            padding: EdgeInsets.only(left: 72),
            child: Divider(height: 1, color: ClaiColors.divider),
          ),
        );
      }
      children.add(rows[i]);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
          child: Text(
            kicker,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: ClaiColors.inkSecondary,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
          child: Column(children: children),
        ),
      ],
    );
  }
}
