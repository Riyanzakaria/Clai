import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:clai/services/capture_service.dart';

/// F2.5: jembatan kanal 'clai/share' untuk berbagi hangat + pintu
/// Tangkap — sisi Dart dari perbaikan cacat berbagi hangat (tarikan
/// pendingShare) dan pemilih gambar. Sisi natif dibuktikan di layar
/// emulator; di sini kontrak kanalnya dikunci.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('clai/share');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('takePendingShare mengembalikan peta berbagi dari natif', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'initialShared') {
        return <String, Object?>{'kind': 'image', 'value': '/cache/x.jpg'};
      }
      return null;
    });
    final pending = await CaptureService.takePendingShare();
    expect(pending, isNotNull);
    expect(pending!['kind'], 'image');
    expect(pending['value'], '/cache/x.jpg');
  });

  test('takePendingShare null bila tidak ada yang menunggu', () async {
    messenger.setMockMethodCallHandler(channel, (call) async => null);
    expect(await CaptureService.takePendingShare(), isNull);
  });

  test('pickCaptureImage mengembalikan jalur pilihan; galat jadi null',
      () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'pickCaptureImage') return '/cache/pilihan.jpg';
      return null;
    });
    expect(await CaptureService.pickCaptureImage(), '/cache/pilihan.jpg');
    messenger.setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(code: 'pemilih-gagal');
    });
    expect(await CaptureService.pickCaptureImage(), isNull);
  });
}
