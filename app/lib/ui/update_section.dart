import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../app.dart';
import '../core/clai_icons.dart';
import '../core/tokens.dart';
import '../services/sys_channel.dart';
import '../l10n/l10n.dart';
import '../services/update_service.dart';
import 'widgets.dart';

/// Seksi Pengaturan: Pembaruan (PETA-JALAN butir 6). Semua status datang dari
/// [UpdateController] — layar ini tidak menebak apa pun.
class UpdateSettingsSection extends ConsumerStatefulWidget {
  const UpdateSettingsSection({super.key});
  @override
  ConsumerState<UpdateSettingsSection> createState() => _UpdateSettingsSectionState();
}

class _UpdateSettingsSectionState extends ConsumerState<UpdateSettingsSection> {
  bool? _canInstall;

  @override
  void initState() {
    super.initState();
    SysChannel.canInstallPackages().then((v) { if (mounted) setState(() => _canInstall = v); });
  }

  @override
  Widget build(BuildContext context) {
    final upd = ref.watch(updateControllerProvider);
    return ListenableBuilder(
      listenable: upd,
      builder: (context, _) {
        final s = context.l10n;
        final statusText = switch (upd.status) {
          UpdateStatus.checking => s.commonChecking,
          UpdateStatus.downloading => s.commonDownloadingPct((upd.progress * 100).round()),
          UpdateStatus.installing => s.updateInstalling,
          _ => upd.message.isEmpty ? s.updateTapToCheck : upd.message,
        };
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          ListTile(
            leading: tonalIconBox(ClaiIcons.refresh, size: 40, iconSize: 20, color: ClaiColors.accent),
            title: Text(s.updateCheck, style: const TextStyle(color: ClaiColors.ink)),
            subtitle: Text(upd.currentLabel.isEmpty ? statusText : s.updateInstalledLabel(upd.currentLabel, statusText),
                style: const TextStyle(color: ClaiColors.inkSecondary)),
            trailing: upd.status == UpdateStatus.checking
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: ClaiColors.accent))
                : null,
            onTap: upd.status == UpdateStatus.checking ? null : () => upd.check(manual: true),
          ),
          if (upd.status == UpdateStatus.downloading)
            Padding(padding: const EdgeInsets.symmetric(horizontal: 16),
                child: LinearProgressIndicator(value: upd.progress, color: ClaiColors.accent, backgroundColor: ClaiColors.surface3)),
          if (upd.status == UpdateStatus.available)
            ListTile(
              leading: tonalIconBox(ClaiIcons.download, size: 40, iconSize: 20, color: ClaiColors.accent),
              title: Text(s.updateDownloadTag(upd.release?.tag ?? ''), style: const TextStyle(color: ClaiColors.ink, fontWeight: FontWeight.w600)),
              subtitle: Text(s.updateDownloadSub,
                  style: const TextStyle(color: ClaiColors.inkSecondary)),
              onTap: () => upd.download(),
            ),
          if (upd.status == UpdateStatus.readyToInstall)
            ListTile(
              leading: tonalIconBox(ClaiIcons.checkCircle, size: 40, iconSize: 20, color: ClaiColors.accent),
              title: Text(s.updateInstall, style: const TextStyle(color: ClaiColors.ink, fontWeight: FontWeight.w600)),
              subtitle: Text(s.updateInstallSub,
                  style: const TextStyle(color: ClaiColors.inkSecondary)),
              onTap: () => upd.install(),
            ),
          SwitchListTile(
            secondary: tonalIconBox(ClaiIcons.refresh, size: 40, iconSize: 20),
            title: Text(s.updateAutoCheck, style: const TextStyle(color: ClaiColors.ink)),
            subtitle: Text(s.updateAutoCheckSub,
                style: const TextStyle(color: ClaiColors.inkSecondary)),
            value: upd.autoCheck,
            onChanged: (v) => upd.setAutoCheck(v),
          ),
          SwitchListTile(
            secondary: tonalIconBox(ClaiIcons.download, size: 40, iconSize: 20),
            title: Text(s.updateAutoDownload, style: const TextStyle(color: ClaiColors.ink)),
            subtitle: Text(s.updateAutoDownloadSub,
                style: const TextStyle(color: ClaiColors.inkSecondary)),
            value: upd.autoDownload,
            onChanged: (v) => upd.setAutoDownload(v),
          ),
          SwitchListTile(
            secondary: tonalIconBox(ClaiIcons.wifiOff, size: 40, iconSize: 20),
            title: Text(s.updateWifiOnly, style: const TextStyle(color: ClaiColors.ink)),
            subtitle: Text(s.updateWifiOnlySub,
                style: const TextStyle(color: ClaiColors.inkSecondary)),
            value: upd.wifiOnly,
            onChanged: upd.autoDownload ? (v) => upd.setWifiOnly(v) : null,
          ),
          if (_canInstall == false)
            ListTile(
              leading: tonalIconBox(ClaiIcons.shield, size: 40, iconSize: 20, color: ClaiColors.warning),
              title: Text(s.updateInstallPermTitle, style: const TextStyle(color: ClaiColors.ink)),
              subtitle: Text(s.updateInstallPermSub,
                  style: const TextStyle(color: ClaiColors.inkSecondary)),
              onTap: () async {
                await SysChannel.openInstallPermissionSettings();
                final v = await SysChannel.canInstallPackages();
                if (mounted) setState(() => _canInstall = v);
              },
            ),
        ]);
      },
    );
  }
}

/// Kartu Beranda: tampil hanya bila ada pembaruan yang tersedia/terunduh dan
/// belum disingkirkan pengguna untuk versi itu.
class UpdateHomeBanner extends ConsumerStatefulWidget {
  const UpdateHomeBanner({super.key});
  @override
  ConsumerState<UpdateHomeBanner> createState() => _UpdateHomeBannerState();
}

class _UpdateHomeBannerState extends ConsumerState<UpdateHomeBanner> {
  String? _dismissedTag;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    ref.read(appDbProvider).pref<String>('update.dismissedTag').then((v) {
      if (mounted) setState(() { _dismissedTag = v; _loaded = true; });
    });
  }

  @override
  Widget build(BuildContext context) {
    final upd = ref.watch(updateControllerProvider);
    return ListenableBuilder(
      listenable: upd,
      builder: (context, _) {
        final s = context.l10n;
        final r = upd.release;
        final active = r != null &&
            (upd.status == UpdateStatus.available || upd.status == UpdateStatus.downloading || upd.status == UpdateStatus.readyToInstall);
        if (!active || !_loaded || _dismissedTag == r.tag) return const SizedBox.shrink();
        return Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Container(
                padding: const EdgeInsets.all(14),
                // 8045: kartu banner tonal surface-1 radius 16 tanpa
                // garis tepi (claiCardDecoration lama membawa border
                // 1px — hukum DS: kedalaman dari tonal, bukan garis);
                // ikon kini berkotak tonal seperti strip lain.
                decoration: BoxDecoration(
                  color: ClaiColors.surface1,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  tonalIconBox(ClaiIcons.refresh, size: 40, iconSize: 20),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(s.updateBannerTitle(r.versionName), style: const TextStyle(fontWeight: FontWeight.w600, color: ClaiColors.ink)),
                    const SizedBox(height: 4),
                    Text(upd.status == UpdateStatus.readyToInstall
                        ? s.updateBannerReady
                        : upd.status == UpdateStatus.downloading
                            ? s.commonDownloadingPct((upd.progress * 100).round())
                            : s.updateBannerDefault,
                        style: const TextStyle(color: ClaiColors.inkSecondary, fontSize: 13, height: 1.4)),
                    const SizedBox(height: 8),
                    Row(children: [
                      TextButton(
                        onPressed: upd.status == UpdateStatus.readyToInstall
                            ? () => upd.install()
                            : upd.status == UpdateStatus.downloading ? null : () => upd.download(),
                        child: Text(upd.status == UpdateStatus.readyToInstall ? s.commonInstall : s.commonDownload,
                            style: const TextStyle(color: ClaiColors.accent)),
                      ),
                      TextButton(
                        onPressed: () async {
                          await ref.read(appDbProvider).setPref('update.dismissedTag', r.tag);
                          if (mounted) setState(() => _dismissedTag = r.tag);
                        },
                        child: Text(s.commonLater, style: const TextStyle(color: ClaiColors.inkSecondary)),
                      ),
                    ]),
                  ])),
                ]),
              ),
            );
      },
    );
  }
}
