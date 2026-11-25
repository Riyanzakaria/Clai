import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app.dart';
import '../core/tokens.dart';
import '../l10n/l10n.dart';
import '../services/update_service.dart';
import 'widgets.dart';

/// Buka lembar "Yang baru" (Ronde 8069; rujukan desain: versi Stitch,
/// vonis pemilik 2026-11-21). Isi lembar HANYA blok pengguna catatan
/// rilis — hasil [userFacingNotes] atas [ReleaseInfo.notes]; lapis
/// teknis tidak pernah menyeberang ke layar ini. Pemanggil (banner
/// Beranda & seksi Pembaruan) hanya menawarkan pintu masuknya bila
/// daftar poin pengguna tidak kosong.
Future<void> openWhatsNewSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: claiRootContext(context),
    isScrollControlled: true,
    backgroundColor: ClaiColors.surface1,
    shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(ClaiRadius.sheet))),
    builder: (_) => const WhatsNewSheet(),
  );
}

/// Lembar catatan rilis pengguna: judul Inter Tight, nomor bangun
/// redup, daftar poin bertanda titik Volt, kaki berisi tombol utama
/// pill Volt terisi (Unduh/Pasang mengikuti status pembaruan) dan
/// tombol hantu "Nanti saja" yang menutup lembar SAJA — tidak
/// menyingkirkan tawaran pembaruan seperti tombol banner.
class WhatsNewSheet extends ConsumerWidget {
  const WhatsNewSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final upd = ref.watch(updateControllerProvider);
    return ListenableBuilder(
      listenable: upd,
      builder: (context, _) {
        final s = context.l10n;
        final r = upd.release;
        if (r == null) return const SizedBox.shrink();
        final bullets = userFacingNotes(r.notes);
        final ready = upd.status == UpdateStatus.readyToInstall;
        final downloading = upd.status == UpdateStatus.downloading;
        return ConstrainedBox(
          constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.78),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Center(child: SheetHandle()),
                  const SizedBox(height: 18),
                  Text(s.updateWhatsNewTitle(r.versionName),
                      style: displayStyle(20)),
                  const SizedBox(height: 4),
                  Text(s.updateBuildLabel(r.build),
                      style: const TextStyle(
                          color: ClaiColors.inkFaint, fontSize: 13)),
                  const SizedBox(height: 14),
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (final b in bullets)
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 6),
                                child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Padding(
                                        padding:
                                            const EdgeInsets.only(top: 8),
                                        child: Container(
                                          width: 6,
                                          height: 6,
                                          decoration: const BoxDecoration(
                                              color: ClaiColors.signal,
                                              shape: BoxShape.circle),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(b,
                                            style: const TextStyle(
                                                color: ClaiColors.ink,
                                                fontSize: 15,
                                                height: 1.45)),
                                      ),
                                    ]),
                              ),
                          ]),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(children: [
                    Expanded(
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                            backgroundColor: ClaiColors.signal,
                            foregroundColor: ClaiColors.onSignal,
                            minimumSize: const Size.fromHeight(48),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                    ClaiRadius.pill))),
                        onPressed: downloading
                            ? null
                            : () {
                                if (ready) {
                                  upd.install();
                                } else {
                                  upd.download();
                                }
                                Navigator.of(context).pop();
                              },
                        child: Text(
                            downloading
                                ? s.commonDownloadingPct(
                                    (upd.progress * 100).round())
                                : ready
                                    ? s.commonInstall
                                    : s.commonDownload,
                            style:
                                const TextStyle(fontWeight: FontWeight.w600)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(s.commonLater,
                          style:
                              const TextStyle(color: ClaiColors.inkSecondary)),
                    ),
                  ]),
                ]),
          ),
        );
      },
    );
  }
}
