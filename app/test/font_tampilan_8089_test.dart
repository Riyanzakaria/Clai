import 'dart:io';

import 'package:clai/app.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tes regresi Ronde Ganti Font Tampilan 8089 — keputusan pemilik
/// 2026-11-25: font tampilan Clash Display DIGANTI Inter Tight
/// (Google Fonts, OFL-1.1, terbundel sebagai instance statis
/// latin + latin-ext), Inter tetap untuk isi/label. Peran utama
/// (displayStyle & heroStyle) naik ke w700; bobot 600 tetap terdaftar
/// untuk pemetaan 1:1 non-utama (kartu QR bagikan). Tes ini mengunci
/// fakta barunya: gaya tampilan menunjuk family + bobot yang benar,
/// aset font terdaftar di pubspec, dan tidak ada rujukan family lama
/// yang tertinggal di lib/ (nama lama hanya boleh hidup sebagai
/// komentar riwayat di app.dart).
void main() {
  group('font tampilan 8089 (Inter Tight)', () {
    test('displayStyle & heroStyle memakai Inter Tight w700', () {
      expect(displayStyle(20).fontFamily, 'Inter Tight');
      expect(heroStyle(30).fontFamily, 'Inter Tight');
      expect(kDisplayFontFamily, 'Inter Tight');
      expect(displayStyle(20).fontWeight, FontWeight.w700);
      expect(heroStyle(30).fontWeight, FontWeight.w700);
    });

    test('pubspec mendaftarkan family Inter Tight terbundel', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      expect(pubspec, contains('family: Inter Tight'));
      expect(pubspec, contains('assets/fonts/InterTight-Medium.ttf'));
      expect(pubspec, contains('assets/fonts/InterTight-SemiBold.ttf'));
      expect(pubspec, contains('assets/fonts/InterTight-Bold.ttf'));
      expect(pubspec, isNot(contains('family: Clash Display')));
      expect(pubspec, isNot(contains('ClashDisplay')));
      for (final name in [
        'InterTight-Medium.ttf',
        'InterTight-SemiBold.ttf',
        'InterTight-Bold.ttf',
      ]) {
        expect(
          File('assets/fonts/$name').existsSync(),
          isTrue,
          reason: 'aset font $name harus ada',
        );
      }
    });

    test('tidak ada rujukan family lama tersisa di lib/', () {
      final offenders = <String>[];
      for (final f in Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
        final src = f.readAsStringSync();
        if (src.contains('spaceGrotesk') || src.contains('GoogleFonts.space')) {
          offenders.add(f.path);
        }
        // Nama tampilan lama hanya boleh hidup sebagai catatan
        // keputusan (komentar riwayat) di app.dart.
        if ((src.contains('Space Grotesk') || src.contains('Clash Display')) &&
            !f.path.endsWith('app.dart')) {
          offenders.add('${f.path} (nama lama di luar app.dart)');
        }
      }
      expect(
        offenders,
        isEmpty,
        reason: 'rujukan font lama tertinggal: $offenders',
      );
    });
  });
}
