import 'dart:io';

import 'package:clai/data/app_db.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  AppDb? appDb;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    appDb = null;
    tmp = await Directory.systemTemp.createTemp('clai_db_test');
    // path_provider dialihkan ke direktori sementara uji.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => tmp.path,
    );
  });

  tearDown(() async {
    // Tutup DB SEBELUM menghapus folder: di Windows berkas SQLite yang masih
    // terbuka tidak bisa dihapus (PathAccessException, errno 32).
    await appDb?.close();
    appDb = null;
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  test('getter db: banyak pemanggil bersamaan berbagi SATU instance terbuka', () async {
    final db = appDb = AppDb();
    final results = await Future.wait(List.generate(8, (_) => db.db));
    for (final d in results) {
      expect(identical(d, results.first), isTrue,
          reason: 'semua pemanggil harus menerima instance yang sama (single-flight)');
    }
    expect(await File(p.join(tmp.path, AppDb.dbName)).exists(), isTrue);
    // Panggilan berikutnya memakai instance yang sudah terbuka.
    expect(identical(await db.db, results.first), isTrue);
  });

  test('openAt ikut single-flight yang sama dengan getter', () async {
    final db = appDb = AppDb();
    final f1 = db.openAt(p.join(tmp.path, 'uji.db'));
    final f2 = db.db; // bersamaan dengan openAt di atas
    final d1 = await f1;
    final d2 = await f2;
    expect(identical(d1, d2), isTrue);
    expect(await d1.getVersion(), AppDb.schemaVersion);
  });
}
