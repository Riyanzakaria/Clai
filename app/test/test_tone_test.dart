import 'dart:typed_data';

import 'package:clai/domain/models.dart';
import 'package:clai/player/resolving_audio_source.dart';
import 'package:clai/player/test_tone.dart';
import 'package:flutter_test/flutter_test.dart';

/// Nada uji Diagnostik langkah E (v4.2): WAV harus sah secara struktur, sumber
/// memori harus melayani range dengan matematika yang konsisten, dan fetcher
/// rintisan harus meniru server range yang sopan (206 + Content-Range).
void main() {
  group('buildSineWav', () {
    final wav = buildSineWav();
    String tag(int o) => String.fromCharCodes(wav.sublist(o, o + 4));
    final view = ByteData.view(wav.buffer);

    test('kerangka RIFF/WAVE/fmt/data benar', () {
      expect(tag(0), 'RIFF');
      expect(tag(8), 'WAVE');
      expect(tag(12), 'fmt ');
      expect(tag(36), 'data');
      expect(view.getUint32(4, Endian.little), wav.length - 8);
    });

    test('format: PCM mono 16-bit 16 kHz, 2 detik = 32000 sampel', () {
      expect(view.getUint16(20, Endian.little), 1); // PCM
      expect(view.getUint16(22, Endian.little), 1); // mono
      expect(view.getUint32(24, Endian.little), 16000);
      expect(view.getUint16(34, Endian.little), 16);
      expect(view.getUint32(40, Endian.little), 32000 * 2);
      expect(wav.length, 44 + 32000 * 2);
    });

    test('sampel sinus: mulai 0, mencapai puncak ~0.25 amplitudo', () {
      expect(view.getInt16(44, Endian.little), 0);
      var peak = 0;
      for (var i = 0; i < 32000; i++) {
        final v = view.getInt16(44 + i * 2, Endian.little).abs();
        if (v > peak) peak = v;
      }
      expect(peak, greaterThan(7000));
      expect(peak, lessThan(9000)); // 0.25 * 32767 ≈ 8192
    });
  });

  group('MemoryAudioSource', () {
    final bytes = Uint8List.fromList(List.generate(1000, (i) => i % 251));
    final src = MemoryAudioSource(bytes);

    test('permintaan penuh: offset 0, panjang penuh', () async {
      final r = await src.request();
      expect(r.offset, 0);
      expect(r.sourceLength, 1000);
      expect(r.contentLength, 1000);
      expect(r.rangeRequestsSupported, isTrue);
      final got = await r.stream.expand((e) => e).toList();
      expect(got.length, 1000);
    });

    test('permintaan range: potongan persis', () async {
      final r = await src.request(100, 250);
      expect(r.offset, 100);
      expect(r.contentLength, 150);
      expect(r.sourceLength, 1000);
      final got = await r.stream.expand((e) => e).toList();
      expect(got, bytes.sublist(100, 250));
    });
  });

  group('wavStubFetcher', () {
    final bytes = buildSineWav(seconds: 1);
    final fetcher = wavStubFetcher(bytes);

    test('menjawab 206 + Content-Range konsisten', () async {
      final f = await fetcher(Uri.parse('https://rintisan.invalid/nada.wav'),
          start: 0, endInclusive: 999);
      expect(f.statusCode, 206);
      expect(f.contentLength, 1000);
      expect(f.contentRange, 'bytes 0-999/${bytes.length}');
      final got = await f.body.expand((e) => e).toList();
      expect(got, bytes.sublist(0, 1000));
    });

    test('endInclusive di luar berkas ditambatkan', () async {
      final f = await fetcher(Uri.parse('https://rintisan.invalid/nada.wav'),
          start: bytes.length - 10, endInclusive: bytes.length + 5000);
      expect(f.contentLength, 10);
      expect(f.contentRange, 'bytes ${bytes.length - 10}-${bytes.length - 1}/${bytes.length}');
    });

    test('fetcher rintisan mengumpan ResolvingAudioSource sampai tuntas', () async {
      const track = Track(key: TrackKey('diag', 'nada'), title: 'Nada', artistNames: 'D', playableRef: 'nada');
      final src = ResolvingAudioSource(
        track,
        () async => StreamInfo(
            url: 'https://rintisan.invalid/nada.wav',
            mimeType: 'audio/wav',
            expiresAt: DateTime.now().add(const Duration(minutes: 5))),
        fetcher: fetcher,
      );
      final r = await src.request(0, null); // pola ExoPlayer: range terbuka
      expect(r.sourceLength, bytes.length);
      expect(r.contentType, 'audio/wav');
      final got = await r.stream.expand((e) => e).toList();
      expect(got.length, r.contentLength);
      expect(got, bytes.sublist(0, r.contentLength!));
    });
  });
}
