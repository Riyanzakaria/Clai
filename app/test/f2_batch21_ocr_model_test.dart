import 'dart:convert';
import 'dart:io';

import 'package:clai/data/app_db.dart';
import 'package:clai/services/ocr_model_service.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// F2 Batch 2.1 (cara ketiga): model OCR diunduh di dalam aplikasi —
/// manifest, checksum, tukar atomik, dan keadaan bersih sesudah gagal.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('parseOcrModelManifest', () {
    test('manifest sah terurai', () {
      final m = parseOcrModelManifest({
        'lang': 'eng',
        'file': 'eng.traineddata',
        'size': 4113088,
        'sha256':
            '7d4322bd2a7749724879683fc3912cb542f19906c83bcc1a52132556427170b2',
        'version': 'tessdata_fast 4.1.0 (eng)',
      });
      expect(m, isNotNull);
      expect(m!.lang, 'eng');
      expect(m.size, 4113088);
    });
    test('sha bukan 64 hex → ditolak', () {
      expect(
          parseOcrModelManifest({
            'lang': 'eng',
            'file': 'eng.traineddata',
            'size': 10,
            'sha256': 'abc',
          }),
          isNull);
    });
    test('ukuran hilang / berkas hilang → ditolak', () {
      expect(
          parseOcrModelManifest({
            'lang': 'eng',
            'file': 'eng.traineddata',
            'sha256': 'a' * 64,
          }),
          isNull);
      expect(
          parseOcrModelManifest({
            'lang': 'eng',
            'size': 10,
            'sha256': 'a' * 64,
          }),
          isNull);
    });
  });

  test('sha256OfFile cocok dengan vektor yang dikenal', () async {
    final dir = await Directory.systemTemp.createTemp('clai-ocr-sha');
    final f = File('${dir.path}/x.bin');
    await f.writeAsString('abc');
    expect(await sha256OfFile(f),
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
    await dir.delete(recursive: true);
  });

  group('OcrModelController melawan umpan simulasi lokal', () {
    late HttpServer server;
    late List<int> goodBytes;
    late String goodSha;
    var corrupt = false;
    late Directory support;

    setUp(() async {
      corrupt = false;
      goodBytes = List<int>.generate(8192, (i) => (i * 7 + 13) % 251);
      goodSha = sha256.convert(goodBytes).toString();
      support = await Directory.systemTemp.createTemp('clai-ocr-ctl');
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final base = 'http://127.0.0.1:${server.port}';
      server.listen((req) {
        final path = req.uri.path;
        if (path == '/latest.json') {
          req.response.headers.contentType = ContentType.json;
          req.response.write(jsonEncode({
            'tag_name': 'v1.0.0+6',
            'draft': false,
            'body': '',
            'assets': [
              {
                'name': 'clai-ocr-model.json',
                'browser_download_url': '$base/assets/clai-ocr-model.json',
                'size': 200,
              },
              {
                'name': 'eng.traineddata',
                'browser_download_url': '$base/assets/eng.traineddata',
                'size': goodBytes.length,
              },
            ],
          }));
        } else if (path == '/assets/clai-ocr-model.json') {
          req.response.headers.contentType = ContentType.json;
          req.response.write(jsonEncode({
            'lang': 'eng',
            'file': 'eng.traineddata',
            'size': goodBytes.length,
            'sha256': goodSha,
            'version': 'uji-eng',
          }));
        } else if (path == '/assets/eng.traineddata') {
          final bytes = corrupt
              ? (List<int>.from(goodBytes)..[100] ^= 0xFF)
              : goodBytes;
          req.response.headers.contentLength = bytes.length;
          req.response.add(bytes);
        } else {
          req.response.statusCode = 404;
        }
        req.response.close();
      });
    });

    tearDown(() async {
      await server.close(force: true);
      if (await support.exists()) await support.delete(recursive: true);
    });

    OcrModelController ctl() => OcrModelController(AppDb(),
        supportDir: () async => support,
        feedUrlOverride: 'http://127.0.0.1:${server.port}/latest.json');

    test('unduh → checksum cocok → model aktif & meta tertulis', () async {
      final c = ctl();
      await c.refresh();
      expect(c.status, OcrModelStatus.notDownloaded);
      await c.download();
      expect(c.status, OcrModelStatus.ready);
      expect(c.modelVersion, 'uji-eng');
      final f = File('${support.path}/ocr-model/tessdata/eng.traineddata');
      expect(await f.exists(), isTrue);
      expect(await f.readAsBytes(), goodBytes);
      expect(c.dataPath, '${support.path}/ocr-model');
      // Segarkan dari disk: tetap ready (meta konsisten).
      final c2 = ctl();
      await c2.refresh();
      expect(c2.status, OcrModelStatus.ready);
      expect(c2.installedSize, goodBytes.length);
    });

    test('unduhan rusak → checksum menolak, tidak ada berkas setengah',
        () async {
      corrupt = true;
      final c = ctl();
      await c.download();
      expect(c.status, OcrModelStatus.error);
      final dir = Directory('${support.path}/ocr-model/tessdata');
      final leftovers = await dir.exists()
          ? await dir.list().toList()
          : const <FileSystemEntity>[];
      expect(leftovers.where((e) => e.path.endsWith('.part')), isEmpty,
          reason: 'berkas .part harus dibuang');
      expect(
          await File('${support.path}/ocr-model/tessdata/eng.traineddata')
              .exists(),
          isFalse,
          reason: 'berkas final tidak boleh lahir dari unduhan rusak');
      // Unduh ulang dari umpan sehat harus bisa (keadaan bersih).
      corrupt = false;
      await c.download();
      expect(c.status, OcrModelStatus.ready);
    });

    test('hapus model → kembali belum-diunduh yang jujur', () async {
      final c = ctl();
      await c.download();
      expect(c.status, OcrModelStatus.ready);
      await c.deleteModel();
      expect(c.status, OcrModelStatus.notDownloaded);
      expect(
          await Directory('${support.path}/ocr-model').exists(), isFalse);
    });
  });
}
