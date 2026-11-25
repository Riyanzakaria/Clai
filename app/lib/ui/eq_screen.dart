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
            // Ronde 8084: wadah kartu surface1 r20 DIBUANG — seksi
            // Normalisasi kini datar pola settingsSection (label
            // sentence-case 13/600 inkSecondary, atas 18, jarak ke
            // baris 4, baris langsung di latar halaman padding 20).
            // Pola ditiru lokal persis seperti driving_section._section:
            // settings_screen mengimpor berkas ini, bukan sebaliknya.
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
              child: Text(
                context.l10n.setNormalization,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: ClaiColors.inkSecondary,
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 4, 20, 0),
              child: NormalizationTile(),
            ),
            SizedBox(height: bottomChromeClearance(context)),
          ],
        ),
      ),
    );
  }
}
