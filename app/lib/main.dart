import 'package:flutter/material.dart';
import 'bootstrap.dart';
import 'services/observability.dart';

/// Titik masuk. TIDAK ada await sebelum runApp: frame pertama (splash) harus
/// selalu tergambar lebih dulu. Semua inisialisasi berat berjalan di dalam
/// ClaiBootstrapApp sesudah frame pertama, per langkah dengan batas waktu —
/// satu langkah macet kini menghasilkan layar kesalahan yang jujur,
/// bukan layar hitam + ANR seperti urutan lama.
void main() {
  appStartStamp; // B-01: paksa cap waktu mulai sedini mungkin (lihat bootstrap.dart)
  WidgetsFlutterBinding.ensureInitialized();
  configureImageCache();
  FlutterError.onError = (details) {
    Observability.instance.log('flutter-error', details.exceptionAsString());
    FlutterError.presentError(details);
  };
  runApp(const ClaiBootstrapApp());
}
