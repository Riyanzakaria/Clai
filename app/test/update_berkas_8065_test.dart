import 'dart:io';

import 'package:clai/services/update_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ronde 8065 — regresi cacat yang terbukti di HP riyan 14 Nov 2026:
/// pembaruan dalam aplikasi dari 2.0.2 (staging 8063) ke rilis 2.0.2
/// ditolak Android sebagai INSTALL_FAILED_VERSION_DOWNGRADE karena
/// berkas yang dipasang adalah APK 2.0.1 SISA unduhan lama. Akarnya:
/// nama berkas selalu 'clai.apk' untuk semua rilis + pakai-ulang hanya
/// mencocokkan ukuran, dan aset 2.0.1/2.0.2 sama-sama 30.884.225 byte.
/// Perbaikan: nama terikat rilis, sisa lintas versi dibersihkan,
/// pakai-ulang hanya untuk berkas rilis yang sama.
void main() {
  ReleaseInfo rel(int build) => ReleaseInfo(
      tag: 'v2.0.2+$build',
      versionName: '2.0.2',
      build: build,
      notes: '',
      assets: const []);

  group('updateFileNameForRelease — nama terikat rilis', () {
    test('nama memuat nomor bangun dan berbeda antar build', () {
      expect(updateFileNameForRelease(rel(8064)), 'clai-8064.apk');
      expect(updateFileNameForRelease(rel(8065)), 'clai-8065.apk');
      expect(updateFileNameForRelease(rel(8064)),
          isNot(updateFileNameForRelease(rel(8065))));
      // Rilis yang sama → nama yang sama (syarat pakai-ulang yang sah).
      expect(updateFileNameForRelease(rel(8065)),
          updateFileNameForRelease(rel(8065)));
    });

    test('tag tanpa bangun → nama dari tag yang disanitasi', () {
      const r = ReleaseInfo(
          tag: 'v9.9.9', versionName: '9.9.9', build: 0, notes: '', assets: []);
      expect(updateFileNameForRelease(r), 'clai-v9.9.9.apk');
      const aneh = ReleaseInfo(
          tag: 'v2.0.2+abc',
          versionName: '2.0.2',
          build: 0,
          notes: '',
          assets: []);
      expect(updateFileNameForRelease(aneh), 'clai-v2.0.2-abc.apk');
    });
  });

  group('isUpdateFileName — pola milik updater', () {
    test('nama terikat + nama warisan dikenali; berkas asing tidak', () {
      expect(isUpdateFileName('clai.apk'), isTrue); // warisan pra-8065
      expect(isUpdateFileName('clai-8065.apk'), isTrue);
      expect(isUpdateFileName('clai-v9.9.9.apk'), isTrue);
      expect(isUpdateFileName('clai-8065.txt'), isFalse);
      expect(isUpdateFileName('lagu.apk'), isFalse);
      expect(isUpdateFileName('xclai-8065.apk'), isFalse);
    });
  });

  group('shouldReuseUpdateFile — keputusan pakai-ulang murni', () {
    test('hanya ada + ukuran persis aset → pakai ulang', () {
      expect(
          shouldReuseUpdateFile(exists: true, fileLength: 100, assetSize: 100),
          isTrue);
      expect(
          shouldReuseUpdateFile(exists: true, fileLength: 99, assetSize: 100),
          isFalse);
      expect(
          shouldReuseUpdateFile(exists: false, fileLength: -1, assetSize: 100),
          isFalse);
      // Ukuran aset tak dikenal (0) tidak pernah jadi dasar pakai-ulang.
      expect(shouldReuseUpdateFile(exists: true, fileLength: 0, assetSize: 0),
          isFalse);
    });
  });

  group('pruneStaleUpdateFiles — pembersihan folder sementara', () {
    late Directory dir;
    setUp(() async {
      dir = await Directory.systemTemp.createTemp('clai-upd-8065-');
    });
    tearDown(() async {
      try {
        await dir.delete(recursive: true);
      } catch (_) {}
    });

    Future<void> seed(String name, [int bytes = 8]) =>
        File('${dir.path}/$name').writeAsBytes(List.filled(bytes, 7));

    test('berkas rilis lain + warisan terhapus; milik rilis ini & berkas '
        'asing utuh', () async {
      await seed('clai.apk'); // sisa 2.0.1 pola lama
      await seed('clai-8064.apk'); // sisa build sebelumnya
      await seed('clai-8065.apk'); // milik rilis ini — jangan disentuh
      await seed('catatan.txt');
      final deleted = await pruneStaleUpdateFiles(dir, 'clai-8065.apk');
      expect(deleted.toSet(), {'clai.apk', 'clai-8064.apk'});
      expect(await File('${dir.path}/clai.apk').exists(), isFalse);
      expect(await File('${dir.path}/clai-8064.apk').exists(), isFalse);
      expect(await File('${dir.path}/clai-8065.apk').exists(), isTrue);
      expect(await File('${dir.path}/catatan.txt').exists(), isTrue);
    });

    test('folder belum ada → daftar kosong, tanpa galat', () async {
      final takAda = Directory('${dir.path}/belum-ada');
      expect(await pruneStaleUpdateFiles(takAda, 'clai-8065.apk'), isEmpty);
    });

    test('skenario cacat 14 Nov: berkas build lain berukuran SAMA tidak '
        'dipakai-ulang untuk rilis ini', () async {
      const ukuranAset = 30884225; // ukuran bersama 2.0.1 & 2.0.2
      await seed('clai-8064.apk', 64); // isinya bukan aset; ukurannya dimodelkan di bawah
      // Berkas yang akan diperiksa download() untuk rilis 8065 bernama
      // clai-8065.apk — berkas 8064 TIDAK menempati nama itu, jadi walau
      // ukurannya disamakan dengan aset, keputusan pakai-ulang atas nama
      // rilis ini tetap "tidak ada berkas".
      final target = File('${dir.path}/${updateFileNameForRelease(rel(8065))}');
      expect(await target.exists(), isFalse);
      expect(
          shouldReuseUpdateFile(
              exists: await target.exists(),
              fileLength: ukuranAset,
              assetSize: ukuranAset),
          isFalse);
      // Dan pembersihan membuang berkas asing itu dari folder.
      final deleted =
          await pruneStaleUpdateFiles(dir, updateFileNameForRelease(rel(8065)));
      expect(deleted, ['clai-8064.apk']);
    });
  });
}
