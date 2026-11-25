import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app.dart';
import '../core/clai_icons.dart';
import '../core/tokens.dart';
import '../l10n/l10n.dart';
import '../services/ocr_model_service.dart';
import 'widgets.dart';

String _mb(int bytes) =>
    '${(bytes / 1048576).toStringAsFixed(1).replaceAll('.', ',')} MB';

/// Pengaturan → Tangkap: status model pembaca teks (OCR) untuk
/// Tangkap-dari-gambar. Model TIDAK terbundel di APK (cara ketiga) — di
/// sini pengguna melihat keadaannya, mengunduh, atau menghapusnya.
class OcrModelSettingsSection extends ConsumerWidget {
  const OcrModelSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ocr = ref.watch(ocrModelControllerProvider);
    return ListenableBuilder(
      listenable: ocr,
      builder: (context, _) {
        final s = context.l10n;
        final busy = ocr.status == OcrModelStatus.downloading ||
            ocr.status == OcrModelStatus.verifying;
        final subtitle = switch (ocr.status) {
          OcrModelStatus.ready => s.ocrModelInstalled(_mb(ocr.installedSize),
              ocr.modelVersion != null ? s.ocrModelVersionPart(ocr.modelVersion!) : ''),
          OcrModelStatus.downloading =>
            s.commonDownloadingPct((ocr.progress * 100).round()),
          OcrModelStatus.verifying => s.ocrModelVerifying,
          OcrModelStatus.error => ocr.message,
          // Netral pra-rilis: pesan tenang status (bukan merah — warna galat
          // hanya untuk OcrModelStatus.error di gaya subtitel di bawah).
          OcrModelStatus.unavailable => ocr.message,
          _ => s.ocrModelNotDownloaded,
        };
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // Ronde 8084: baris terkunci 60 / label 15/600 / state 13
          // satu baris (status unduh/pasang tetap fungsional penuh).
          ListTile(
            minTileHeight: 60,
            titleTextStyle: const TextStyle(
                fontFamily: kDisplayFontFamily,
                fontSize: kRowTitleSize,
                fontWeight: FontWeight.w700,
                color: ClaiColors.ink),
            subtitleTextStyle: const TextStyle(
                fontSize: 13, color: ClaiColors.inkSecondary),
            leading: rowLeadIcon(
                ocr.status == OcrModelStatus.ready
                    ? ClaiIcons.checkCircle
                    : ClaiIcons.lyrics,
                size: 40,
                iconSize: 24,
                color: ocr.status == OcrModelStatus.ready
                    ? ClaiColors.signal
                    : ClaiColors.inkFaint),
            title: Text(s.ocrModelTitle, style: rowTitleStyle()),
            subtitle: Text(subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 13,
                    color: ocr.status == OcrModelStatus.error
                        ? ClaiColors.error
                        : ClaiColors.inkSecondary)),
            trailing: busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: ClaiColors.signal))
                : ocr.status == OcrModelStatus.ready
                    ? TextButton(
                        onPressed: () async {
                          final ok = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: Text(maxLines: 1, overflow: TextOverflow.ellipsis, s.ocrModelDeleteTitle),
                              content: Text(s.ocrModelDeleteBody),
                              actions: [
                                TextButton(
                                    onPressed: () =>
                                        Navigator.of(ctx).pop(false),
                                    child: Text(s.commonCancel)),
                                FilledButton(
                                    onPressed: () =>
                                        Navigator.of(ctx).pop(true),
                                    child: Text(s.commonDelete)),
                              ],
                            ),
                          );
                          if (ok == true) await ocr.deleteModel();
                        },
                        child: Text(s.commonDelete,
                            style: const TextStyle(color: ClaiColors.error)),
                      )
                    : TextButton(
                        onPressed: () => ocr.download(),
                        child: Text(
                            ocr.status == OcrModelStatus.error
                                ? s.commonRetry
                                : ocr.status == OcrModelStatus.unavailable
                                    // Bukan "coba lagi": tidak ada yang gagal —
                                    // aksinya memeriksa ulang ketersediaan.
                                    ? s.ocrCheckAgain
                                    : s.commonDownload,
                            style: const TextStyle(color: ClaiColors.signal)),
                      ),
          ),
          if (busy)
            // Ronde 8084: baris lanjutan progres sejajar inset teks
            // panel (72 = padding tile 16 + ikon 40 + celah 16).
            Padding(
                padding: const EdgeInsets.only(left: 72, right: 16),
                child: LinearProgressIndicator(
                    value: ocr.status == OcrModelStatus.downloading
                        ? ocr.progress
                        : null,
                    color: ClaiColors.signal,
                    backgroundColor: ClaiColors.surface3)),
        ]);
      },
    );
  }
}
