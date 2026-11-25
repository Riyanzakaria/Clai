import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../app.dart';
import '../core/clai_icons.dart';
import '../core/tokens.dart';
import '../services/sys_channel.dart';
import '../l10n/l10n.dart';
import '../services/update_service.dart';
import 'whats_new_sheet.dart';
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
        // Ronde 8084: status baris Periksa. Keadaan hidup (memeriksa /
        // mengunduh / memasang) + pesan fungsional kontroler tetap;
        // keadaan diam TANPA pesan kini menampilkan VERSI TERPASANG
        // sebagai state — instruksi updateTapToCheck ("ketuk untuk
        // memeriksa") pensiun (§13.2: instruksi bukan state). Bila ada
        // status hidup, label+status dikomposisi updateInstalledLabel
        // seperti sebelumnya.
        final statusText = switch (upd.status) {
          UpdateStatus.checking => s.commonChecking,
          UpdateStatus.downloading => s.commonDownloadingPct((upd.progress * 100).round()),
          UpdateStatus.installing => s.updateInstalling,
          _ => upd.message,
        };
        final subtitleText = upd.currentLabel.isEmpty
            ? statusText
            : statusText.isEmpty
                ? upd.currentLabel
                : s.updateInstalledLabel(upd.currentLabel, statusText);
        // Ronde 8089 (Bagian D): judul baris utilitas = font tampilan
        // [kRowTitleSize]/700 (14 sejak koreksi Ronde 8090).
        const rowTitleStyle = TextStyle(
            fontFamily: kDisplayFontFamily,
            fontSize: kRowTitleSize,
            fontWeight: FontWeight.w700,
            color: ClaiColors.ink);
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          ListTile(
            minTileHeight: 60,
            titleTextStyle: rowTitleStyle,
            subtitleTextStyle: const TextStyle(
                fontSize: 13, color: ClaiColors.inkSecondary),
            leading: rowLeadIcon(ClaiIcons.refresh, size: 40, iconSize: 24, color: ClaiColors.signal),
            title: Text(s.updateCheck, style: rowTitleStyle),
            subtitle: subtitleText.isEmpty
                ? null
                : Text(subtitleText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13, color: ClaiColors.inkSecondary)),
            trailing: upd.status == UpdateStatus.checking
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: ClaiColors.signal))
                : null,
            onTap: upd.status == UpdateStatus.checking ? null : () => upd.check(manual: true),
          ),
          if (upd.status == UpdateStatus.downloading)
            Padding(padding: const EdgeInsets.only(left: 72, right: 16),
                child: LinearProgressIndicator(value: upd.progress, color: ClaiColors.signal, backgroundColor: ClaiColors.surface3)),
          if (upd.status == UpdateStatus.available)
            ListTile(
              minTileHeight: 60,
              titleTextStyle: rowTitleStyle,
              leading: rowLeadIcon(ClaiIcons.download, size: 40, iconSize: 24, color: ClaiColors.signal),
              title: Text(maxLines: 1, overflow: TextOverflow.ellipsis, s.updateDownloadTag(upd.release?.tag ?? ''), style: rowTitleStyle),
              onTap: () => upd.download(),
            ),
          if (upd.status == UpdateStatus.readyToInstall)
            ListTile(
              minTileHeight: 60,
              titleTextStyle: rowTitleStyle,
              leading: rowLeadIcon(ClaiIcons.checkCircle, size: 40, iconSize: 24, color: ClaiColors.signal),
              title: Text(maxLines: 1, overflow: TextOverflow.ellipsis, s.updateInstall, style: rowTitleStyle),
              onTap: () => upd.install(),
            ),
          // Ronde 8069: baris "Yang baru" — hanya bila rilis yang
          // ditawarkan membawa blok pengguna (daftar poin non-kosong);
          // rilis warisan tanpa blok tidak memunculkan pintu apa pun.
          if ((upd.status == UpdateStatus.available ||
                  upd.status == UpdateStatus.downloading ||
                  upd.status == UpdateStatus.readyToInstall) &&
              upd.release != null &&
              userFacingNotes(upd.release!.notes).isNotEmpty)
            // Ronde 8084: subjudul penjelas updateWhatsNewSub DIBUANG —
            // baris tetap membuka lembar Yang baru, tanpa teks kedua.
            ListTile(
              minTileHeight: 60,
              titleTextStyle: rowTitleStyle,
              leading: rowLeadIcon(ClaiIcons.info, size: 40, iconSize: 24, color: ClaiColors.signal),
              title: Text(maxLines: 1, overflow: TextOverflow.ellipsis, s.updateWhatsNewTitle(upd.release!.versionName),
                  style: rowTitleStyle),
              onTap: () => openWhatsNewSheet(context),
            ),
          SwitchListTile(
            minTileHeight: 60,
            secondary: rowLeadIcon(ClaiIcons.refresh, size: 40, iconSize: 24),
            title: Text(maxLines: 1, overflow: TextOverflow.ellipsis, s.updateAutoCheck, style: rowTitleStyle),
            value: upd.autoCheck,
            onChanged: (v) => upd.setAutoCheck(v),
          ),
          SwitchListTile(
            minTileHeight: 60,
            secondary: rowLeadIcon(ClaiIcons.download, size: 40, iconSize: 24),
            title: Text(maxLines: 1, overflow: TextOverflow.ellipsis, s.updateAutoDownload, style: rowTitleStyle),
            value: upd.autoDownload,
            onChanged: (v) => upd.setAutoDownload(v),
          ),
          SwitchListTile(
            minTileHeight: 60,
            secondary: rowLeadIcon(ClaiIcons.wifiOff, size: 40, iconSize: 24),
            title: Text(maxLines: 1, overflow: TextOverflow.ellipsis, s.updateWifiOnly, style: rowTitleStyle),
            value: upd.wifiOnly,
            onChanged: upd.autoDownload ? (v) => upd.setWifiOnly(v) : null,
          ),
          if (_canInstall == false)
            ListTile(
              minTileHeight: 60,
              titleTextStyle: rowTitleStyle,
              leading: rowLeadIcon(ClaiIcons.shield, size: 40, iconSize: 24, color: ClaiColors.warning),
              title: Text(maxLines: 1, overflow: TextOverflow.ellipsis, s.updateInstallPermTitle, style: rowTitleStyle),
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
                  rowLeadIcon(ClaiIcons.refresh, size: 40, iconSize: 20),
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
                    // Ronde 8069: deret aksi kini bisa berisi TIGA tombol
                    // (Unduh/Pasang + Yang baru + Nanti saja) — pada lebar
                    // HP 360dp label Indonesia tidak muat sebaris (luapan
                    // 162px terbukti di tes widget), jadi deretnya Wrap:
                    // tombol ketiga turun ke baris berikut bila perlu.
                    Wrap(children: [
                      TextButton(
                        onPressed: upd.status == UpdateStatus.readyToInstall
                            ? () => upd.install()
                            : upd.status == UpdateStatus.downloading ? null : () => upd.download(),
                        child: Text(upd.status == UpdateStatus.readyToInstall ? s.commonInstall : s.commonDownload,
                            style: const TextStyle(color: ClaiColors.signal)),
                      ),
                      // Ronde 8069: tombol "Yang baru" membuka lembar
                      // catatan rilis pengguna — hanya bila blok
                      // pengguna rilis ini menghasilkan poin.
                      if (userFacingNotes(r.notes).isNotEmpty)
                        TextButton(
                          onPressed: () => openWhatsNewSheet(context),
                          child: Text(s.updateWhatsNewBtn,
                              style: const TextStyle(color: ClaiColors.signal)),
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
