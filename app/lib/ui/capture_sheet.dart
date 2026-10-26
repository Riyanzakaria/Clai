import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/l10n.dart';

import '../app.dart';
import '../core/clai_icons.dart';
import '../core/tokens.dart';
import '../services/ocr_model_service.dart';

Future<void> openCaptureSheet(BuildContext context, {String? text, String? imageUri}) {
  return showModalBottomSheet<void>(
    context: claiRootContext(context),
    isScrollControlled: true,
    backgroundColor: ClaiColors.surface1,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => FractionallySizedBox(
        heightFactor: 0.85,
        child: CaptureSheet(text: text, imageUri: imageUri)),
  );
}

/// Lembar masukan teks Tangkap (dialog tempel tautan/teks) — SATU
/// implementasi untuk semua pintu: Pengaturan ("Tangkap tautan/teks")
/// dan pintu Tangkap terpadu di layar Cari (butir 6 F2.5). Teks yang
/// dikirim (termasuk tautan playlist Spotify) mengalir ke lembar
/// Tangkapan yang sama lewat [openCaptureSheet].
Future<void> openCaptureTextInput(BuildContext context) async {
  final l10n = context.l10n;
  final ctrl = TextEditingController();
  final input = await showDialog<String>(
    // Audit UX 2017: dialog memakai konteks AKAR seperti semua lembar
    // lain (openCaptureSheet di atas) — dari konten cangkang, konteks
    // pemanggil menaruh dialog di navigator dalam: penghalangnya tidak
    // menutupi chrome melayang dan ganti tab bisa membuangnya diam-diam.
    context: claiRootContext(context),
    builder: (ctx) => AlertDialog(
      title: Text(l10n.captureLinkTitle),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        decoration: InputDecoration(hintText: l10n.captureHint),
        onSubmitted: (v) => Navigator.of(ctx).pop(v),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l10n.commonCancel)),
        FilledButton(
            onPressed: () => Navigator.of(ctx).pop(ctrl.text),
            child: Text(l10n.captureAction)),
      ],
    ),
  );
  if (input != null && input.trim().isNotEmpty && context.mounted) {
    openCaptureSheet(context, text: input.trim());
  }
}

/// Lembar hasil tangkapan (F2 Batch 2): tiap item berstatus ditemukan / tidak
/// — pengguna melihat daftarnya SEBELUM memutar massal.
class CaptureSheet extends ConsumerStatefulWidget {
  final String? text;
  final String? imageUri;
  const CaptureSheet({super.key, this.text, this.imageUri});
  @override
  ConsumerState<CaptureSheet> createState() => _CaptureSheetState();
}

class _CaptureSheetState extends ConsumerState<CaptureSheet> {
  bool _started = false;
  bool _gateShown = false;

  void _startImage() {
    if (_started || widget.imageUri == null) return;
    _started = true;
    ref.read(captureServiceProvider).captureImage(widget.imageUri!);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.imageUri != null) {
        final ocr = ref.read(ocrModelControllerProvider);
        if (ocr.status == OcrModelStatus.ready) {
          _startImage();
        } else {
          // Gerbang model (cara ketiga): gambar TIDAK dibaca sebelum model
          // OCR terpasang — tampilkan keadaan jujur + tawaran unduh.
          setState(() => _gateShown = true);
          ocr.refresh();
        }
      } else if (widget.text != null) {
        ref.read(captureServiceProvider).captureText(widget.text!);
      }
    });
  }

  Widget _modelGate() {
    final ocr = ref.read(ocrModelControllerProvider);
    return ListenableBuilder(
      listenable: ocr,
      builder: (context, _) {
        if (ocr.status == OcrModelStatus.ready && !_started) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() => _gateShown = false);
              _startImage();
            }
          });
        }
        final busy = ocr.status == OcrModelStatus.downloading ||
            ocr.status == OcrModelStatus.verifying;
        return SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              ClaiIcon(ClaiIcons.lyrics, color: ClaiColors.accent),
              const SizedBox(width: 10),
              Expanded(
                child: Text(context.l10n.capGateTitle,
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: ClaiColors.ink)),
              ),
            ]),
            const SizedBox(height: 10),
            Text(context.l10n.capGateBody,
                style: const TextStyle(color: ClaiColors.inkSecondary, height: 1.5)),
            const SizedBox(height: 12),
            Text(ocr.message,
                style: TextStyle(
                    color: ocr.status == OcrModelStatus.error
                        ? ClaiColors.error
                        : ClaiColors.inkSecondary,
                    height: 1.45)),
            if (busy) ...[
              const SizedBox(height: 12),
              LinearProgressIndicator(
                  value: ocr.status == OcrModelStatus.downloading
                      ? ocr.progress
                      : null,
                  color: ClaiColors.accent,
                  backgroundColor: ClaiColors.surface3),
              const SizedBox(height: 6),
              Text(
                  ocr.status == OcrModelStatus.downloading
                      ? context.l10n.commonDownloadingPct((ocr.progress * 100).round())
                      : context.l10n.capVerifying,
                  style: const TextStyle(
                      color: ClaiColors.inkSecondary, fontSize: 13)),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                  backgroundColor: ClaiColors.accent,
                  foregroundColor: ClaiColors.onAccent),
              onPressed: busy ? null : () => ocr.download(),
              icon: ClaiIcon(ClaiIcons.download,
                  color: ClaiColors.onAccent, size: 18),
              label: Text(ocr.status == OcrModelStatus.error
                  ? context.l10n.capRetryDownload
                  : ocr.status == OcrModelStatus.unavailable
                      ? context.l10n.ocrCheckAgain
                      : context.l10n.capDownloadModel),
            ),
          ]),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final cap = ref.watch(captureServiceProvider);
    final handler = ref.read(audioHandlerProvider);
    final found = cap.foundTracks;
    final gateActive = _gateShown && !_started;
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
        Text(context.l10n.capFromOtherApp,
            style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: ClaiColors.ink)),
        const SizedBox(height: 4),
        Text(
            cap.inputSummary.isEmpty
                ? (gateActive ? context.l10n.capImageList : context.l10n.capMatchingShort)
                : cap.inputSummary,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: ClaiColors.inkSecondary, height: 1.45)),
        if (cap.error != null) ...[
          const SizedBox(height: 8),
          Text(cap.error!,
              style: const TextStyle(color: ClaiColors.error, height: 1.45)),
        ],
        const SizedBox(height: 12),
        if (gateActive)
          Expanded(child: _modelGate())
        else ...[
        if (cap.working && cap.items.isEmpty)
          const Center(child: CircularProgressIndicator(color: ClaiColors.accent)),
        Expanded(
          child: ListView.builder(
            itemCount: cap.items.length,
            itemBuilder: (context, i) {
              final item = cap.items[i];
              final ok = item.track != null;
              return ListTile(
                leading: ClaiIcon(
                    ok ? ClaiIcons.checkCircle : ClaiIcons.musicOff,
                    color: ok ? ClaiColors.accent : ClaiColors.inkFaint),
                title: Text(
                    ok
                        ? '${item.track!.title} — ${item.track!.artistNames}'
                        : item.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: ClaiColors.ink)),
                subtitle: ok
                    ? Text(context.l10n.capFrom(item.label),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: ClaiColors.inkSecondary))
                    : Text(item.error ?? context.l10n.capNotFound,
                        style: const TextStyle(color: ClaiColors.inkSecondary)),
                onTap: ok
                    ? () async {
                        await handler.playTracks([item.track!], 0,
                            kind: 'search', label: context.l10n.capTitle);
                        if (context.mounted) Navigator.of(context).pop();
                      }
                    : null,
              );
            },
          ),
        ),
        if (!cap.working && found.isNotEmpty) ...[
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: FilledButton(
                style: FilledButton.styleFrom(
                    backgroundColor: ClaiColors.accent,
                    foregroundColor: ClaiColors.onAccent),
                onPressed: () async {
                  await handler.playTracks(found, 0,
                      kind: 'search', label: context.l10n.capTitle);
                  if (context.mounted) Navigator.of(context).pop();
                },
                child: Text(context.l10n.capPlayAll(found.length)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton(
                onPressed: () async {
                  for (final t in found) {
                    await handler.enqueue(t, next: false);
                  }
                  if (context.mounted) Navigator.of(context).pop();
                },
                child: Text(context.l10n.capAddAll),
              ),
            ),
          ]),
        ],
        if (cap.working)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(context.l10n.capMatching,
                style: TextStyle(color: ClaiColors.inkSecondary, fontSize: 13)),
          ),
        ],
      ]),
    );
  }
}
