import 'package:flutter/services.dart';

/// Jembatan sistem 'clai/sys' (F2): versi aplikasi terpasang, ABI perangkat,
/// jenis jaringan, dan pemasangan APK lewat PackageInstaller.
///
/// Semua metode GAGAL-AMAN: di platform tanpa implementasi (uji widget, desktop)
/// mereka mengembalikan nilai netral — fitur yang memakainya (Pembaruan Dalam
/// Aplikasi) menyatakan dirinya tidak tersedia, bukan crash.
class SysChannel {
  static const _ch = MethodChannel('clai/sys');

  /// Versi dari PackageManager — sumber kebenaran versi TERPASANG (bukan konstanta Dart).
  static Future<({String name, int code})?> appVersion() async {
    try {
      final r = await _ch.invokeMapMethod<String, Object>('appVersion');
      if (r == null) return null;
      return (name: (r['versionName'] as String?) ?? '0.0.0', code: (r['versionCode'] as num?)?.toInt() ?? 0);
    } catch (_) {
      return null;
    }
  }

  /// Nomor bangun dasar Clai: versionCode terpasang memuat offset ABI build
  /// split (arm64 +2000, x86_64 +4000); sisanya (mod 1000) adalah nomor urut rilis.
  static int baseBuildOf(int versionCode) => versionCode % 1000;

  static Future<List<String>> deviceAbis() async {
    try {
      final r = await _ch.invokeListMethod<String>('deviceAbis');
      return r ?? const [];
    } catch (_) {
      return const [];
    }
  }

  /// 'wifi' | 'mobile' | 'ethernet' | 'none' | 'unknown' (saluran tak tersedia).
  static Future<String> networkType() async {
    try {
      return await _ch.invokeMethod<String>('networkType') ?? 'unknown';
    } catch (_) {
      return 'unknown';
    }
  }

  /// Izin "pasang aplikasi tak dikenal" untuk Clai (Android 8+).
  static Future<bool> canInstallPackages() async {
    try {
      return await _ch.invokeMethod<bool>('canInstallPackages') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> openInstallPermissionSettings() async {
    try {
      await _ch.invokeMethod<void>('openInstallPermissionSettings');
    } catch (_) {/* pengguna diarahkan manual oleh teks UI */}
  }

  /// Pasang APK lewat PackageInstaller. Melempar PlatformException dengan kode:
  /// 'izin' (perlu izin pasang), 'gagal' (sesi ditolak sistem), atau kode status lain.
  /// Konfirmasi sistem bisa muncul — itu perilaku Android yang jujur, bukan kegagalan.
  static Future<void> installApk(String path) async {
    await _ch.invokeMethod<void>('installApk', {'path': path});
  }
}
