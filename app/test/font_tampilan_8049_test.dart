import 'dart:io';

import 'package:clai/app.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tes regresi Ronde Ganti Font Tampilan 8049 — keputusan pemilik
/// 2026-11-10 19:38: font tampilan Space Grotesk DIGANTI Clash Display
/// (terbundel), Inter tetap untuk isi/label. Tes ini mengunci fakta
/// barunya: gaya tampilan menunjuk family yang benar, aset font
/// terdaftar di pubspec, dan tidak ada rujukan Space Grotesk yang
/// tertinggal di lib/ (komentar sejarah di berkas ini sendiri dikecualikan
/// karena menyebut nama lama sebagai catatan keputusan).
void main() {
  group('font tampilan 8049 (Clash Display)', () {
    test('displayStyle & heroStyle memakai Clash Display', () {
      expect(displayStyle(20).fontFamily, 'Clash Display');
      expect(heroStyle(30).fontFamily, 'Clash Display');
      expect(kDisplayFontFamily, 'Clash Display');
    });

    test('pubspec mendaftarkan family Clash Display terbundel', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      expect(pubspec, contains('family: Clash Display'));
      expect(pubspec, contains('assets/fonts/ClashDisplay-Medium.ttf'));
      expect(pubspec, contains('assets/fonts/ClashDisplay-Semibold.ttf'));
      expect(pubspec, contains('assets/fonts/ClashDisplay-Bold.ttf'));
      for (final name in [
        'ClashDisplay-Medium.ttf',
        'ClashDisplay-Semibold.ttf',
        'ClashDisplay-Bold.ttf',
      ]) {
        expect(File('assets/fonts/$name').existsSync(), isTrue,
            reason: 'aset font $name harus ada');
      }
    });

    test('tidak ada rujukan Space Grotesk tersisa di lib/', () {
      final offenders = <String>[];
      for (final f in Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
        final src = f.readAsStringSync();
        if (src.contains('spaceGrotesk') || src.contains('GoogleFonts.space')) {
          offenders.add(f.path);
        }
        // Nama tampilannya hanya boleh hidup sebagai catatan keputusan
        // di app.dart & riwayat faktor lebar di search_screen.dart.
        if (src.contains('Space Grotesk') &&
            !f.path.endsWith('app.dart') &&
            !f.path.endsWith('search_screen.dart')) {
          offenders.add('${f.path} (nama lama di komentar)');
        }
      }
      expect(offenders, isEmpty,
          reason: 'rujukan Space Grotesk tertinggal: $offenders');
    });
  });
}
