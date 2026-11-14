import 'dart:io';

import 'package:clai/core/clai_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ronde 8061 — glif timer tidur diganti ke ikon PERSIS dari struktur
/// halaman Stitch: baris durasi = Material "bedtime" resmi, blok
/// pahlawan lembar aktif = "dark_mode" resmi (sabit terisi). Sapuan
/// sumber mengunci tidak ada lagi ClaiIcons.moon di permukaan timer.
void main() {
  group('sapuan sumber permukaan timer', () {
    final surfaces = <String, List<String>>{
      'lib/ui/sleep_timer_sheet.dart': ['ClaiIcons.bedtime', 'ClaiIcons.darkMode'],
      'lib/ui/player_sheet.dart': ['ClaiIcons.bedtime'],
      'lib/ui/mini_player.dart': ['ClaiIcons.bedtime'],
      'lib/ui/sleep_resume_card.dart': ['ClaiIcons.bedtime'],
    };
    for (final e in surfaces.entries) {
      test('${e.key} memakai glif Stitch, bukan moon lama', () {
        final src = File(e.key).readAsStringSync();
        expect(src.contains('ClaiIcons.moon'), isFalse,
            reason: '${e.key} masih memakai ClaiIcons.moon');
        for (final g in e.value) {
          expect(src.contains(g), isTrue, reason: '${e.key} belum memakai $g');
        }
      });
    }
    test('tidak ada rujukan ClaiIcons.moon tersisa di seluruh lib/', () {
      final offenders = <String>[];
      for (final f in Directory('lib').listSync(recursive: true)) {
        if (f is File && f.path.endsWith('.dart')) {
          if (f.readAsStringSync().contains('ClaiIcons.moon')) {
            offenders.add(f.path);
          }
        }
      }
      expect(offenders, isEmpty, reason: 'masih merujuk moon: $offenders');
    });
  });

  group('geometri glif resmi', () {
    test('bedtime = jalur isi sabit resmi, terdaftar di kisi 24', () {
      final fill = ClaiIcons.bedtime.fill;
      expect(fill, isNotNull);
      expect(ClaiIcons.bedtime.stroke, isNull);
      final b = fill!.getBounds();
      expect(b.left, closeTo(3, 0.01));
      expect(b.top, closeTo(3, 0.01));
      expect(b.right, closeTo(23, 0.01));
      expect(b.bottom, closeTo(23, 0.01));
      // Bukan tetesan lama: moon jauh lebih sempit & berupa coretan.
      expect(b.width, greaterThan(19));
      expect(b.height, greaterThan(19));
    });
    test('darkMode = sabit terisi resmi untuk blok pahlawan', () {
      final fill = ClaiIcons.darkMode.fill;
      expect(fill, isNotNull);
      expect(ClaiIcons.darkMode.stroke, isNull);
      final b = fill!.getBounds();
      expect(b.left, closeTo(3, 0.01));
      expect(b.top, closeTo(3, 0.01));
      expect(b.right, closeTo(21, 0.01));
      expect(b.bottom, closeTo(21, 0.01));
    });
    testWidgets('kedua glif me-render tanpa exception', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Row(children: [
            ClaiIcon(ClaiIcons.bedtime, size: 24),
            ClaiIcon(ClaiIcons.darkMode, size: 24),
          ]),
        ),
      ));
      expect(tester.takeException(), isNull);
    });
  });
}
