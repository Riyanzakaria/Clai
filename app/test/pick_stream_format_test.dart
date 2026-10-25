import 'dart:convert';
import 'dart:io';

import 'package:clai/domain/models.dart';
import 'package:clai/providers/ytmusic/innertube.dart';
import 'package:flutter_test/flutter_test.dart';

/// Uji pemilihan format aliran terhadap fixture HIDUP respons player klien ANDROID
/// (video uji qU9mHegkTc4, diambil dari PC 2026-10-23, putaran v4; subpohon
/// playabilityStatus + streamingData verbatim). Inilah bukti sisi-Dart dari cacat v4-1:
/// rantai klien yang kini di depan (ANDROID) benar-benar menghasilkan URL audio langsung.
Map<String, dynamic> fixture(String name) =>
    jsonDecode(File('test/fixtures/$name').readAsStringSync()) as Map<String, dynamic>;

void main() {
  test('respons ANDROID: URL audio langsung terpilih pada kualitas normal', () {
    final info = pickStreamFormat(fixture('player_android.json'), StreamQuality.normal);
    expect(info, isNotNull);
    expect(info!.url, startsWith('https://'));
    expect(info.mimeType, startsWith('audio/'));
    expect(info.bitrate, isNotNull);
    expect(info.bitrate!, lessThanOrEqualTo(StreamQuality.normal.maxBitrate));
    expect(info.expiresAt.isAfter(DateTime.now()), isTrue);
  });

  test('kualitas rendah memilih bitrate di bawah batasnya', () {
    final info = pickStreamFormat(fixture('player_android.json'), StreamQuality.low);
    expect(info, isNotNull);
    expect(info!.bitrate!, lessThanOrEqualTo(StreamQuality.low.maxBitrate));
  });

  test('status bukan OK menghasilkan null (rantai lanjut ke klien berikutnya)', () {
    final bad = fixture('player_android.json');
    bad['playabilityStatus'] = {'status': 'LOGIN_REQUIRED'};
    expect(pickStreamFormat(bad, StreamQuality.normal), isNull);
  });
}
