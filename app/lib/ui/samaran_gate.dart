import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app.dart';
import '../core/clai_icons.dart';
import '../core/tokens.dart';
import '../data/app_db.dart';
import '../l10n/l10n.dart';

/// Gerbang penjelas Mode Samaran (Ronde 8079, maket S1 yang diterima
/// riyan 22 Nov — spec `desain-f3/pisah-pengaturan/DIALOG-SAMARAN.md`).
///
/// SATU gerbang untuk DUA pintu masuk — pil Samaran di Player dan
/// saklar di layar Selera kamu — supaya penjelasnya tidak pernah
/// berbeda perilaku: menyalakan Samaran menampilkan lembar penjelas
/// DULU; "Aktifkan Samaran" di lembar yang menyalakan; "Batal" menutup
/// dan Samaran tetap mati. Mematikan tidak pernah menampilkan lembar.
/// Centang "Jangan tampilkan lagi" menulis pref
/// [AppDb.prefTasteSamaranHowSeen]; sesudah itu pengaktifan langsung
/// tanpa lembar di kedua pintu. Keadaan Samaran sendiri tetap SATU
/// sumber (`TasteService`, doktrin 8074) — gerbang ini hanya mengatur
/// jalan menyalanya, tidak memegang keadaan kedua.
Future<void> requestSamaranOn(BuildContext context, WidgetRef ref) async {
  final taste = ref.read(tasteServiceProvider);
  if (taste.samaranOn) return;
  final db = ref.read(appDbProvider);
  final seen =
      await db.pref<bool>(AppDb.prefTasteSamaranHowSeen) ?? false;
  if (seen) {
    await taste.setSamaran(true);
    return;
  }
  if (!context.mounted) return;
  final activate = await showModalBottomSheet<bool>(
    context: claiRootContext(context),
    isScrollControlled: true,
    backgroundColor: ClaiColors.surface1,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
          top: Radius.circular(ClaiRadius.sheet)),
    ),
    builder: (sheetContext) => const _SamaranHowSheet(),
  );
  if (activate == true) await taste.setSamaran(true);
}

/// Jalan saklar Selera kamu: nilai true lewat gerbang penjelas, nilai
/// false langsung mati tanpa lembar (S1: mematikan tidak pernah
/// menampilkan dialog).
Future<void> handleSamaranSwitch(
    BuildContext context, WidgetRef ref, bool value) async {
  if (value) {
    await requestSamaranOn(context, ref);
  } else {
    await ref.read(tasteServiceProvider).setSamaran(false);
  }
}

/// Lembar penjelas S1: permukaan PADAT surface-1 (bukan kaca — lembar
/// modal tetap padat, aturan kaca), radius 20 di atas, gagang seret,
/// empat baris JUJUR dengan ikon garis polos tanpa kotak tonal:
/// riwayat, cermin, ListenBrainz, dan — pembeda jujur dari sesi
/// pribadi Spotify — TANPA batas waktu.
class _SamaranHowSheet extends ConsumerStatefulWidget {
  const _SamaranHowSheet();

  @override
  ConsumerState<_SamaranHowSheet> createState() => _SamaranHowSheetState();
}

class _SamaranHowSheetState extends ConsumerState<_SamaranHowSheet> {
  bool _dontShow = false;

  Widget _row(ClaiIconData icon, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClaiIcon(icon, size: 20, color: ClaiColors.ink),
        const SizedBox(width: 12),
        Expanded(
          child: Text(text,
              style: const TextStyle(
                  color: ClaiColors.ink, fontSize: 14, height: 1.45)),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: ClaiColors.surface3,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(l.samaranHowTitle, style: displayStyle(20)),
            const SizedBox(height: 16),
            _row(ClaiIcons.history, l.samaranHowRowHistory),
            const SizedBox(height: 14),
            _row(ClaiIcons.pulse, l.samaranHowRowTaste),
            const SizedBox(height: 14),
            _row(ClaiIcons.link, l.samaranHowRowListenBrainz),
            const SizedBox(height: 14),
            _row(ClaiIcons.infinity, l.samaranHowRowNoLimit),
            const SizedBox(height: 8),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              dense: true,
              value: _dontShow,
              onChanged: (v) => setState(() => _dontShow = v ?? false),
              title: Text(l.samaranHowDontShow,
                  style: const TextStyle(
                      color: ClaiColors.inkSecondary, fontSize: 13)),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: () async {
                if (_dontShow) {
                  await ref
                      .read(appDbProvider)
                      .setPref(AppDb.prefTasteSamaranHowSeen, true);
                }
                if (context.mounted) Navigator.of(context).pop(true);
              },
              child: Text(l.samaranHowActivate),
            ),
            const SizedBox(height: 4),
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l.commonCancel),
            ),
          ],
        ),
      ),
    );
  }
}
