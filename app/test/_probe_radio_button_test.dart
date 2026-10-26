// PROBE SEMENTARA (Ronde Audit UX 2017): mereplikasi persis sub-pohon tombol
// Putar halaman Radio (ListView > Padding > Row > Column > PressableScale >
// GestureDetector > Container lingkaran > ClaiIcon) dan memeriksa apakah
// ketukan di berbagai titik tombol memicu onTap.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:clai/core/clai_icons.dart';
import 'package:clai/ui/widgets.dart';

void main() {
  testWidgets('probe tombol putar radio: ketukan memicu onTap', (t) async {
    var taps = 0;
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(width: 120, height: 120, color: Colors.grey),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Judul Lagu'),
                          const SizedBox(height: 12),
                          PressableScale(
                            child: GestureDetector(
                              onTap: () => taps++,
                              child: Container(
                                width: 48,
                                height: 48,
                                decoration: const BoxDecoration(
                                  color: Colors.green,
                                  shape: BoxShape.circle,
                                ),
                                child: ClaiIcon(
                                  ClaiIcons.play,
                                  color: Colors.black,
                                  size: 26,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    final center = t.getCenter(find.byType(GestureDetector));
    // tengah tombol
    await t.tapAt(center);
    await t.pump();
    // dekat tepi lingkaran (kiri-atas, masih di dalam lingkaran r=24)
    await t.tapAt(center + const Offset(-14, -14));
    await t.pump();
    // titik pada ikon (tengah glif)
    await t.tapAt(center + const Offset(2, 0));
    await t.pump();
    expect(taps, 3, reason: 'ketukan terdaftar: $taps dari 3 titik');
  });
}
