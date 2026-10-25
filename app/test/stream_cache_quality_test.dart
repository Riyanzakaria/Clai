import 'package:flutter_test/flutter_test.dart';
import 'package:clai/domain/models.dart';

/// Regresi temuan emulator Ronde Poles: hemat data tidak berpengaruh
/// pada trek tercache karena cache aliran buta-tingkat.
void main() {
  StreamInfo info(int? b) => StreamInfo(
      url: 'https://x', mimeType: 'audio/mp4', bitrate: b,
      expiresAt: DateTime.now().add(const Duration(hours: 1)));

  test('cache cocok hanya di pita tingkatnya', () {
    expect(streamCacheFitsQuality(info(48000), StreamQuality.low), isTrue);
    expect(streamCacheFitsQuality(info(70000), StreamQuality.low), isTrue);
    expect(streamCacheFitsQuality(info(144000), StreamQuality.low), isFalse);
    expect(streamCacheFitsQuality(info(144000), StreamQuality.normal), isTrue);
    expect(streamCacheFitsQuality(info(48000), StreamQuality.normal), isFalse);
    expect(streamCacheFitsQuality(info(256000), StreamQuality.normal), isFalse);
    expect(streamCacheFitsQuality(info(256000), StreamQuality.high), isTrue);
    expect(streamCacheFitsQuality(info(144000), StreamQuality.high), isFalse);
    expect(streamCacheFitsQuality(info(null), StreamQuality.low), isFalse);
  });
}
