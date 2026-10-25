import 'package:clai/core/error_describe.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';

/// describeError (v4.1): log insiden & Diagnostik Putar harus memuat rantai galat
/// lengkap — bukan lagi "(0) Source error" generik seperti bukti perangkat v4.
void main() {
  test('PlayerException: kode + pesan + indeks tampil', () {
    final s = describeError(PlayerException(0, 'Source error', 2));
    expect(s, contains('code=0'));
    expect(s, contains('Source error'));
    expect(s, contains('index=2'));
  });

  test('PlatformException: details mentah ikut (rantai ExoPlayer)', () {
    final s = describeError(PlatformException(
        code: 'Platform player error', message: 'Source error',
        details: 'HttpDataSource.InvalidResponseCodeException: 403'));
    expect(s, contains('403'));
  });

  test('DioException: jenis + status + potongan badan', () {
    final e = DioException(
      requestOptions: RequestOptions(path: 'https://musik/contoh'),
      type: DioExceptionType.badResponse,
      response: Response(requestOptions: RequestOptions(path: 'x'), statusCode: 403, data: 'Forbidden oleh sumber'),
    );
    final s = describeError(e);
    expect(s, contains('badResponse'));
    expect(s, contains('403'));
    expect(s, contains('Forbidden'));
  });

  test('galat umum: tipe runtime tampil', () {
    expect(describeError(StateError('rusak')), contains('StateError'));
  });

  test('tumpukan: maksimal 3 baris dilampirkan', () {
    final s = describeError(Exception('x'), StackTrace.fromString('a\nb\nc\nd\ne'));
    expect(s, contains('a | b | c'));
    expect(s, isNot(contains('| d')));
  });

  group('v4.2: nama kode ExoPlayer & describePlayerError', () {
    test('kode 0 terbaca sebagai TYPE_SOURCE (keluarga ExoPlaybackException)', () {
      expect(exoErrorCodeName(0), contains('TYPE_SOURCE'));
      expect(exoErrorCodeName(1), contains('TYPE_RENDERER'));
      expect(exoErrorCodeName(2004), 'ERROR_CODE_IO_BAD_HTTP_STATUS');
      expect(exoErrorCodeName(2001), 'ERROR_CODE_IO_NETWORK_CONNECTION_FAILED');
      expect(exoErrorCodeName(424242), isNull);
    });

    test('describeError PlayerException kini memuat nama kodenya', () {
      final s = describeError(PlayerException(0, 'Source error', 0));
      expect(s, contains('code=0'));
      expect(s, contains('TYPE_SOURCE'));
    });

    test('describePlayerError: details PlatformException digali mentah per kunci', () {
      final s = describePlayerError(PlatformException(
          code: '0', message: 'Source error', details: {'index': 0, 'sebab': 'HTTP 403'}));
      expect(s, contains('code=0'));
      expect(s, contains('index: 0'));
      expect(s, contains('HTTP 403'));
    });
  });

  group('isInterruptionError (v4.3) — muat disela BUKAN insiden', () {
    test('PlayerInterruptedException dikenali dari tipenya', () {
      expect(isInterruptionError(PlayerInterruptedException('Connection aborted')), isTrue);
      expect(isInterruptionError(PlayerInterruptedException('Loading interrupted')), isTrue);
    });

    test('bentuk teks insiden perangkat v4.2 dikenali ("PlayerInterruptedException: Connection aborted")', () {
      // describeError untuk tipe tak dikenal mencetak "runtimeType: pesan" —
      // itulah persis yang tercatat di log pemilik; penjaga harus menangkapnya
      // juga saat galat tiba terbungkus tipe lain.
      final wrapped = StateError('PlayerInterruptedException: Connection aborted');
      expect(isInterruptionError(wrapped), isTrue);
    });

    test('kegagalan sungguhan TIDAK ikut tertelan', () {
      expect(isInterruptionError(PlayerException(0, 'Source error', 0)), isFalse);
      expect(isInterruptionError(PlatformException(code: '0', message: 'Source error')), isFalse);
      expect(isInterruptionError(Exception('jaringan putus')), isFalse);
    });
  });
}
