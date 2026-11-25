import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app.dart';
import '../core/clai_icons.dart';
import '../core/tokens.dart';
import '../l10n/l10n.dart';
import 'glass.dart';
import 'haptics.dart';
import 'samaran_gate.dart';

/// Pil Mode Samaran di Player (Ruang Kendali Selera, Ronde 8074).
///
/// Keputusan riyan 2026-11-21 18:21: turunan kecil dari layar yang SUDAH
/// ADA tidak digambar di alat desain — pil ini dibangun langsung di atas
/// Player asli. Pil adalah chrome MELAYANG di atas panggung sampul →
/// kaca (aturan kaca); keadaan MENYALA memakai isian `signal` (pagar
/// Sinyal Putih DS v5.0: keadaan aktif fungsional = putih tinta, bukan
/// Volt). Saklar yang sama hidup di layar Kendali Selera; keduanya
/// membaca/menulis TasteService yang satu.
class SamaranPill extends ConsumerWidget {
  const SamaranPill({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final taste = ref.watch(tasteServiceProvider);
    final on = taste.samaranOn;
    final label = context.l10n.tasteSamaranPill;
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClaiIcon(
            ClaiIcons.eyeOff,
            size: 15,
            color: on ? ClaiColors.onSignal : ClaiColors.ink,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: on ? ClaiColors.onSignal : ClaiColors.ink,
            ),
          ),
          if (on) ...[
            const SizedBox(width: 6),
            ClaiIcon(ClaiIcons.check,
                size: 13, color: ClaiColors.onSignal),
          ],
        ],
      ),
    );
    final pill = on
        ? DecoratedBox(
            decoration: const BoxDecoration(
              color: ClaiColors.signal,
              borderRadius: BorderRadius.all(Radius.circular(ClaiRadius.pill)),
            ),
            child: content,
          )
        : GlassSurface(radius: ClaiRadius.pill, child: content);
    return Semantics(
      button: true,
      toggled: on,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          ClaiHaptics.timerSet();
          // Ronde 8079: menyalakan lewat gerbang penjelas S1 bersama
          // (samaran_gate.dart); mematikan langsung, tanpa lembar.
          if (on) {
            ref.read(tasteServiceProvider).setSamaran(false);
          } else {
            requestSamaranOn(context, ref);
          }
        },
        child: pill,
      ),
    );
  }
}
