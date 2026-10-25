import 'dart:io';

import 'package:clai/player/audio_handler.dart';
import 'package:flutter_test/flutter_test.dart';

/// Penjaga regresi akar "Source error" v4–v4.2 (terbukti logcat emulator
/// 2026-10-23: "Cleartext HTTP traffic to 127.0.0.1 not permitted").
///
/// just_audio menyajikan StreamAudioSource lewat proxy HTTP lokal 127.0.0.1;
/// Android memblokir cleartext bahkan ke loopback sejak targetSdk 28. Tanpa
/// konfigurasi keamanan jaringan khusus loopback, SETIAP pemutaran lewat proxy
/// mati sebelum mengambil satu byte — dan gejalanya generik ("(0) Source
/// error"), sehingga penghapusan berkas ini akan tampak seperti "lagu tiba-tiba
/// tidak bunyi lagi" tanpa sebab yang jelas. Uji ini membuat penghapusannya
/// berisik di CI, bukan senyap di perangkat pengguna.
void main() {
  test('network_security_config: cleartext HANYA untuk loopback', () {
    final xml = File('android/app/src/main/res/xml/network_security_config.xml').readAsStringSync();
    expect(xml, contains('127.0.0.1'));
    expect(xml, contains('localhost'));
    expect(xml, contains('cleartextTrafficPermitted="true"'));
    // Basis tetap tertutup: cleartext tidak dibuka untuk sembarang host.
    expect(xml, contains('<base-config cleartextTrafficPermitted="false"'));
  });

  test('AndroidManifest merujuk konfigurasi itu', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    expect(manifest, contains('android:networkSecurityConfig="@xml/network_security_config"'));
  });

  test('handler mengirim header TANPA proxy (transport langsung ExoPlayer)', () {
    expect(ClaiAudioHandler.useProxyForRequestHeaders, isFalse);
  });
}
