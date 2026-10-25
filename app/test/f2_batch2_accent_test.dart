import 'package:clai/services/cover_accent.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('cover accent (DS Bab 2)', () {
    test('averageRgb merata-rata & mengabaikan piksel transparan', () {
      // 2 piksel: merah penuh + hijau transparan (alpha 0).
      final avg = averageRgb([255, 0, 0, 255, 0, 255, 0, 0]);
      expect((avg.r, avg.g, avg.b), (255, 0, 0));
    });
    test('desaturate 20% menggerakkan warna ke abu-abu luminansi', () {
      final d = desaturateRgb((r: 255, g: 0, b: 0), 0.20);
      // Luminansi merah ≈ 76; merah 255 → 255 + (76−255)×0.2 ≈ 219.
      expect(d.r, closeTo(219, 1));
      expect(d.g, closeTo(15, 1));
      expect(d.b, closeTo(15, 1));
    });
    test('tonal tetap gelap: 28% aksen ke #0A0A0E', () {
      final t = tonalRgb((r: 200, g: 100, b: 50), (r: 10, g: 10, b: 14), 0.28);
      expect(t.r, closeTo(63, 1));
      expect(t.g, closeTo(35, 1));
      expect(t.b, closeTo(24, 1));
    });
    test('hex bolak-balik stabil', () {
      final back = rgbFromHex(rgbToHex((r: 12, g: 34, b: 56)));
      expect(back?.r, 12);
      expect(back?.g, 34);
      expect(back?.b, 56);
      expect(rgbFromHex('bukan-hex'), null);
    });
    test('dominantSaturatedRgb: lime di atas putih menang atas putihnya', () {
      // Sampul ala NEON: 90% putih nyaris tak jenuh + 10% hijau lime jenuh.
      final px = <int>[];
      for (var i = 0; i < 90; i++) {
        px.addAll([238, 240, 236, 255]);
      }
      for (var i = 0; i < 10; i++) {
        px.addAll([150, 220, 40, 255]);
      }
      final sig = dominantSaturatedRgb(px);
      expect(sig, isNotNull);
      // Hijau harus dominan kuat; hasil TIDAK boleh jatuh ke abu pucat.
      expect(sig!.g, greaterThan(180));
      expect(sig.r, inInclusiveRange(110, 190));
      expect(sig.b, lessThan(90));
    });
    test('dominantSaturatedRgb: sampul abu polos → null (jatuh ke rata-rata)',
        () {
      final px = <int>[];
      for (var i = 0; i < 50; i++) {
        px.addAll([120, 122, 125, 255]);
      }
      expect(dominantSaturatedRgb(px), isNull);
    });
    test('tonal rumus baru (t=0,50) jauh lebih terlihat daripada 0,28', () {
      final sig = desaturateRgb((r: 150, g: 220, b: 40), 0.20);
      final baru = tonalRgb(sig, (r: 10, g: 10, b: 14), 0.50);
      final lama = tonalRgb(sig, (r: 10, g: 10, b: 14), 0.28);
      expect(baru.g, greaterThan(lama.g + 25),
          reason: 'saluran hijau tanda tangan harus naik nyata');
    });
  });
}
