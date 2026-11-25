// Ronde 8086 — Putar Lagi 128 (butir 2, keputusan pemilik 24 Nov 2026 07:37).
//
// Kontrak yang diuji (uji sumber BERWILAYAH, meniru preseden tes sumber
// ronde-ronde sebelumnya — wilayah = badan fungsi `_playAgainRail` saja
// di lib/ui/home_screen.dart):
// (a) Lebar ubin Putar Lagi: SizedBox width 156 -> 128.
// (b) CoverArt Putar Lagi: size 156 -> 128 (radius 12 tetap).
// (c) Tinggi rel: SizedBox height 202 -> 174 (proporsional: sampul -28,
//     slack teks dipertahankan).
// (d) Tidak ada lagi angka 156 di wilayah fungsi ini.
// Seksi lain (Paling Sering 120, hero 84) di luar wilayah dan tidak diuji.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _src(String path) => File(path).readAsStringSync();

/// Ekstrak substring fungsi `_playAgainRail` dari home_screen.dart:
/// dari tanda tangan fungsinya sampai tanda tangan fungsi berikutnya
/// (`_collectionMosaicStrip`).
String _playAgainRailSource() {
  final src = _src('lib/ui/home_screen.dart');
  final start = src.indexOf('Widget _playAgainRail(BuildContext context)');
  expect(start, greaterThanOrEqualTo(0),
      reason: 'fungsi _playAgainRail harus ada di home_screen.dart');
  final end =
      src.indexOf('Widget _collectionMosaicStrip(BuildContext context)', start);
  expect(end, greaterThan(start),
      reason: 'fungsi berikutnya (_collectionMosaicStrip) harus ditemukan '
          'sebagai batas akhir wilayah _playAgainRail');
  return src.substring(start, end);
}

void main() {
  group('Ronde 8086 — Putar Lagi 128 (wilayah _playAgainRail)', () {
    test('lebar ubin 128 dan CoverArt size 128, tanpa 156', () {
      final rail = _playAgainRailSource();
      expect(
        rail.contains('width: 128'),
        isTrue,
        reason: 'lebar ubin Putar Lagi harus 128',
      );
      expect(
        rail.contains('size: 128'),
        isTrue,
        reason: 'CoverArt Putar Lagi harus size 128',
      );
      expect(
        rail.contains('156'),
        isFalse,
        reason: 'tidak boleh ada sisa ukuran 156 di _playAgainRail',
      );
    });

    test('tinggi rel 174 dan radius sampul 12 tetap', () {
      final rail = _playAgainRailSource();
      expect(
        rail.contains('height: 174'),
        isTrue,
        reason: 'tinggi rel Putar Lagi harus 174',
      );
      expect(
        rail.contains('radius: 12'),
        isTrue,
        reason: 'radius CoverArt Putar Lagi tetap 12',
      );
    });
  });
}
