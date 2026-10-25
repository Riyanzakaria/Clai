import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:just_audio/just_audio.dart';

import 'resolving_audio_source.dart';

/// Nada uji lokal untuk Diagnostik Putar langkah E (v4.2): membuktikan kesehatan
/// PIPA pemutar (ExoPlayer → proxy just_audio → StreamAudioSource) di perangkat
/// TANPA jaringan sama sekali — memisahkan "pipa rusak" dari "URL/jaringan ditolak".
/// Semua bagian murni/dapat disuntik agar teruji unit.

/// Bangun WAV PCM 16-bit mono berisi gelombang sinus murni.
/// [milliseconds] mengalahkan [seconds] bila diisi (untuk earcon pendek).
Uint8List buildSineWav({
  int seconds = 2,
  int? milliseconds,
  int frequencyHz = 440,
  int sampleRate = 16000,
  double gain = 0.25,
}) {
  final samples = milliseconds != null
      ? (milliseconds * sampleRate / 1000).round()
      : seconds * sampleRate;
  final dataBytes = samples * 2;
  final bytes = Uint8List(44 + dataBytes);
  final view = ByteData.view(bytes.buffer);
  void ascii(int offset, String s) {
    for (var i = 0; i < s.length; i++) {
      bytes[offset + i] = s.codeUnitAt(i);
    }
  }

  ascii(0, 'RIFF');
  view.setUint32(4, 36 + dataBytes, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  view.setUint32(16, 16, Endian.little);
  view.setUint16(20, 1, Endian.little); // PCM
  view.setUint16(22, 1, Endian.little); // mono
  view.setUint32(24, sampleRate, Endian.little);
  view.setUint32(28, sampleRate * 2, Endian.little); // byte rate (mono 16-bit)
  view.setUint16(32, 2, Endian.little); // block align
  view.setUint16(34, 16, Endian.little); // bits per sample
  ascii(36, 'data');
  view.setUint32(40, dataBytes, Endian.little);
  for (var i = 0; i < samples; i++) {
    final v = (math.sin(2 * math.pi * frequencyHz * i / sampleRate) * gain * 32767).round();
    view.setInt16(44 + i * 2, v, Endian.little);
  }
  return bytes;
}

/// Sumber aliran yang menyajikan byte memori apa adanya (langkah E1: pipa TANPA
/// ResolvingAudioSource — jalur StreamAudioSource paling polos).
// ignore: experimental_member_use
class MemoryAudioSource extends StreamAudioSource {
  final Uint8List bytes;
  final String mimeType;
  MemoryAudioSource(this.bytes, {this.mimeType = 'audio/wav', super.tag});

  @override
  // ignore: experimental_member_use
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    final s = (start ?? 0).clamp(0, bytes.length);
    final e = (end ?? bytes.length).clamp(s, bytes.length);
    // ignore: experimental_member_use
    return StreamAudioResponse(
      rangeRequestsSupported: true,
      sourceLength: bytes.length,
      contentLength: e - s,
      offset: s,
      contentType: mimeType,
      stream: Stream.value(bytes.sublist(s, e)),
    );
  }
}

/// Fetcher rintisan untuk ResolvingAudioSource (langkah E2): berperilaku seperti
/// server range yang sopan (206 + Content-Range) di atas byte memori — URL resolusi
/// tidak pernah benar-benar diambil karena fetcher ini yang melayani.
RangeFetcher wavStubFetcher(Uint8List bytes, {String contentType = 'audio/wav'}) {
  return (uri, {required start, required endInclusive}) async {
    final s = start.clamp(0, bytes.length);
    final e = (endInclusive + 1).clamp(s, bytes.length);
    return FetchedBytes(
      statusCode: 206,
      contentLength: e - s,
      contentRange: e > s ? 'bytes $s-${e - 1}/${bytes.length}' : null,
      contentType: contentType,
      body: Stream.value(bytes.sublist(s, e)),
    );
  };
}
