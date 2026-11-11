import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app.dart';
import '../core/tokens.dart';
import '../l10n/l10n.dart';
import 'eq_section.dart';
import 'widgets.dart';

/// Layar Ekualiser penuh (Gelombang 2, papan EQ): panggung slider
/// vertikal EqSection dalam mode panggung + panel Normalisasi yang
/// tenang di bawahnya (tetangga satu grup Audio, seperti papan).
/// Dibuka dari baris navigasi EQ di halaman Pengaturan → Audio.
class EqScreen extends ConsumerWidget {
  const EqScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: SafeArea(
        child: FiniteScrollPage(
          padding: EdgeInsets.zero,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                  16, MediaQuery.paddingOf(context).top > 0 ? 4 : 12, 16, 0),
              child: const Align(
                alignment: Alignment.centerLeft,
                child: GlassBackChip(),
              ),
            ),
            const EqSection(stage: true),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 8),
              child: DimKicker(context.l10n.setNormalization),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                decoration: BoxDecoration(
                  color: ClaiColors.surface1,
                  borderRadius: BorderRadius.circular(20),
                ),
                clipBehavior: Clip.antiAlias,
                child: const NormalizationTile(),
              ),
            ),
            SizedBox(height: bottomChromeClearance(context)),
          ],
        ),
      ),
    );
  }
}
