// Ronde 8053 Kelas C — baris aktif Lirik Penuh TIDAK BOLEH terpotong.
// Kasus nyata pemilik (2026-11-11): "We are just enough to stay and
// it's alright" pada gaya pahlawan 30/700 maks 2 baris + ellipsis
// tampil sebagai "…alrig…". Kunci di sini: fitActiveLyricLine tidak
// pernah mengembalikan kombinasi (ukuran, baris) yang memotong teks —
// dibuktikan font-agnostik dengan pengukuran ulang TextPainter pada
// hasil yang dikembalikan (konsistensi-diri), pada lebar HP pemilik
// (360 dp − bantalan daftar 28×2 = 304).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:clai/app.dart';
import 'package:clai/ui/lyrics_sheet.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const ownerLine = "We are just enough to stay and it's alright";
  const width = 304.0; // 360 dp layar pemilik − padding daftar 56.

  TextPainter layOut(String text, double size, int maxLines) => TextPainter(
        text: TextSpan(
          text: text,
          style: displayStyle(size).copyWith(
            fontWeight: FontWeight.w700,
            height: 1.25,
          ),
        ),
        textDirection: TextDirection.ltr,
        textScaler: TextScaler.noScaling,
        maxLines: maxLines,
      )..layout(maxWidth: width);

  testWidgets('baris pemilik muat UTUH — kombinasi hasil tidak memotong',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    final fit = fitActiveLyricLine(ownerLine, width, TextScaler.noScaling);
    // Konsistensi-diri: pada (size, lines) hasil, teks tampil PENUH.
    final check = layOut(ownerLine, fit.size, fit.lines);
    expect(check.didExceedMaxLines, isFalse,
        reason: 'baris aktif tidak boleh terpotong pada hasil fit mana pun');
    expect(check.computeLineMetrics().length, lessThanOrEqualTo(fit.lines));
    // Anti-regresi langsung: dahulu 30/2 + ellipsis MEMOTONG baris ini.
    final oldWay = layOut(ownerLine, 30, 2);
    if (oldWay.didExceedMaxLines) {
      expect(fit.size < 30 || fit.lines > 2, isTrue,
          reason: 'bila 30/2 memotong, fit wajib menyusut atau menumbuhkan baris');
    }
    // Ukuran hasil tetap di tangga yang sah.
    expect(kLyricActiveSizes, contains(fit.size));
  });

  testWidgets('baris pendek tetap pahlawan penuh 30 dalam ≤2 baris',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    final fit = fitActiveLyricLine('Shine on you', width, TextScaler.noScaling);
    expect(fit.size, 30);
    expect(fit.lines, lessThanOrEqualTo(2));
    final check = layOut('Shine on you', fit.size, fit.lines);
    expect(check.didExceedMaxLines, isFalse);
  });

  testWidgets('baris sangat panjang jatuh ke lantai dan TUMBUH, tak terpotong',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    const longLine =
        'Andainya saja semua kata yang pernah kuucapkan bisa kembali pulang '
        'ke rumahnya masing-masing tanpa ada satu pun yang tertinggal di jalan';
    final fit = fitActiveLyricLine(longLine, width, TextScaler.noScaling);
    expect(fit.size, kLyricActiveSizes.last,
        reason: 'baris ekstrem memakai ukuran lantai tangga');
    expect(fit.lines, greaterThan(2),
        reason: 'di lantai, baris tumbuh — bukan terpotong');
    final check = layOut(longLine, fit.size, fit.lines);
    expect(check.didExceedMaxLines, isFalse);
  });
}
