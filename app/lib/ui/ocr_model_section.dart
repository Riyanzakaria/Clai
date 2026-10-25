import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app.dart';
import '../core/clai_icons.dart';
import '../core/tokens.dart';
import '../l10n/l10n.dart';
import '../services/ocr_model_service.dart';

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
          ListTile(
            leading: ClaiIcon(
                ocr.status == OcrModelStatus.ready
                    ? ClaiIcons.checkCircle
                    : ClaiIcons.lyrics,
                color: ocr.status == OcrModelStatus.ready
                    ? ClaiColors.accent
                    : ClaiColors.inkFaint),
            title: Text(s.ocrModelTitle,
                style: const TextStyle(color: ClaiColors.ink)),
            subtitle: Text(subtitle,
                style: TextStyle(
                    color: ocr.status == OcrModelStatus.error
                        ? ClaiColors.error
                        : ClaiColors.inkSecondary)),
            trailing: busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: ClaiColors.accent))
                : ocr.status == OcrModelStatus.ready
                    ? TextButton(
                        onPressed: () async {
                          final ok = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: Text(s.ocrModelDeleteTitle),
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
                            style: const TextStyle(color: ClaiColors.accent)),
                      ),
          ),
          if (busy)
            Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: LinearProgressIndicator(
                    value: ocr.status == OcrModelStatus.downloading
                        ? ocr.progress
                        : null,
                    color: ClaiColors.accent,
                    backgroundColor: ClaiColors.surface3)),
        ]);
      },
    );
  }
}
