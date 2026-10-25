import 'package:clai/data/app_db.dart';
import 'package:clai/services/driving_service.dart';
import 'package:clai/services/speed_volume.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('speedVolumeTarget (murni)', () {
    test('berhenti → titik berhenti; jangkar → titik tercepat; tengah → lerp', () {
      expect(
          speedVolumeTarget(
              medianKmh: 0,
              stopVolume: 0.7,
              fastVolume: 1.0,
              anchorKmh: 80,
              poorAccuracy: false,
              interrupted: false,
              stoppedLong: false),
          0.7);
      expect(
          speedVolumeTarget(
              medianKmh: 80,
              stopVolume: 0.7,
              fastVolume: 1.0,
              anchorKmh: 80,
              poorAccuracy: false,
              interrupted: false,
              stoppedLong: false),
          1.0);
      expect(
          speedVolumeTarget(
              medianKmh: 40,
              stopVolume: 0.7,
              fastVolume: 1.0,
              anchorKmh: 80,
              poorAccuracy: false,
              interrupted: false,
              stoppedLong: false),
          closeTo(0.85, 1e-9));
    });
    test('plafon dijepit; beku saat akurasi buruk / interupsi; berhenti-lama → titik berhenti', () {
      expect(
          speedVolumeTarget(
              medianKmh: 200,
              stopVolume: 0.7,
              fastVolume: 1.0,
              anchorKmh: 80,
              poorAccuracy: false,
              interrupted: false,
              stoppedLong: false),
          1.0);
      expect(
          speedVolumeTarget(
              medianKmh: 40,
              stopVolume: 0.7,
              fastVolume: 1.0,
              anchorKmh: 80,
              poorAccuracy: true,
              interrupted: false,
              stoppedLong: false),
          null);
      expect(
          speedVolumeTarget(
              medianKmh: 40,
              stopVolume: 0.7,
              fastVolume: 1.0,
              anchorKmh: 80,
              poorAccuracy: false,
              interrupted: true,
              stoppedLong: false),
          null);
      expect(
          speedVolumeTarget(
              medianKmh: 0,
              stopVolume: 0.7,
              fastVolume: 1.0,
              anchorKmh: 80,
              poorAccuracy: false,
              interrupted: false,
              stoppedLong: true),
          0.7);
    });
    test('median benar (ganjil/genap)', () {
      expect(median([10, 30, 20]), 20);
      expect(median([10, 30]), 20);
      expect(median([]), 0);
    });
  });

  group('DrivingService', () {
    test('penanda kendaraan & pemicu otomatis', () async {
      final db = AppDb();
      await db.openAt(':memory:');
      final d = DrivingService(db);
      await d.markVehicle('Headunit Mobil');
      expect(d.shouldAutoEnter('Headunit Mobil'), isTrue);
      expect(d.shouldAutoEnter('Speaker Rumah'), isFalse);
      await d.unmarkVehicle('Headunit Mobil');
      expect(d.shouldAutoEnter('Headunit Mobil'), isFalse);
    });
    test('sampel kecepatan: satu langkah ramp lalu beku saat akurasi buruk/panggilan', () async {
      final db = AppDb();
      await db.openAt(':memory:');
      final d = DrivingService(db);
      d.on = true;
      d.speedVolumeOn = true;
      d.stopVolume = 0.7;
      d.fastVolume = 1.0;
      d.anchorKmh = 80;
      final applied = <double>[];
      d.onVolumeTarget = (v) async {
        applied.add(v);
      };
      // Median 0 km/jam → target 0.7; langkah = 5% × 0.3 = 0.015; dari 1.0 → 0.985.
      d.injectSpeedSample(0, 10);
      expect(applied, [closeTo(0.985, 1e-9)]);
      // Akurasi buruk (>50 m) → beku, tidak ada penerapan baru.
      d.injectSpeedSample(0, 120);
      expect(applied.length, 1);
      // Panggilan aktif → beku juga (sampel bersih sekalipun).
      d.injectCallState(true);
      d.injectSpeedSample(0, 10);
      expect(applied.length, 1);
    });
  });
}
