import 'package:clai/services/capture_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CaptureService.classifyUrl', () {
    test('playlist & lagu Spotify', () {
      expect(
          CaptureService.classifyUrl(
              'https://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M'),
          (kind: 'spotify-playlist', id: '37i9dQZF1DXcBWIGoYBM5M'));
      expect(
          CaptureService.classifyUrl(
              'https://open.spotify.com/track/4uLU6hMCjMI75M1A2tKUQC'),
          (kind: 'spotify-track', id: '4uLU6hMCjMI75M1A2tKUQC'));
    });
    test('playlist & watch YouTube (panjang & pendek)', () {
      expect(
          CaptureService.classifyUrl(
              'https://www.youtube.com/playlist?list=PLrAXtmErZgOeiKm4sgNOknGvNjby9efdf'),
          (kind: 'youtube-playlist', id: 'PLrAXtmErZgOeiKm4sgNOknGvNjby9efdf'));
      expect(
          CaptureService.classifyUrl(
              'https://www.youtube.com/watch?v=dQw4w9WgXcQ'),
          (kind: 'youtube-watch', id: 'dQw4w9WgXcQ'));
      expect(
          CaptureService.classifyUrl('https://youtu.be/dQw4w9WgXcQ'),
          (kind: 'youtube-watch', id: 'dQw4w9WgXcQ'));
    });
    test('tautan umum → null (jatuh ke judul halaman)', () {
      expect(CaptureService.classifyUrl('https://example.com/artikel'),
          null);
    });
  });
}
