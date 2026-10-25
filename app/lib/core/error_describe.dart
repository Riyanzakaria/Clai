import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';

/// Uraian galat LENGKAP untuk log insiden & Diagnostik Putar (v4.1).
///
/// Bukti perangkat v4: log hanya memuat `"(0) Source error"` — kode generik ExoPlayer
/// tanpa sebab di bawahnya — sehingga putaran perbaikan terbang buta. Fungsi ini membongkar
/// rantai yang tersedia di sisi Dart: PlayerException (kode + pesan + indeks sumber),
/// PlatformException (kode + pesan + details mentah dari ExoPlayer/Android),
/// DioException (jenis + status HTTP + potongan badan respons), SocketException,
/// TimeoutException — ditutup 3 baris pertama tumpukan bila diberikan.
/// Nama terbaca untuk kode galat pemutar (v4.2).
///
/// just_audio Android mengirim DUA keluarga kode (dibaca dari AudioPlayer.java 0.10.6):
/// jalur ExoPlaybackException lama mengirim `type` (0–4), jalur PlaybackException media3
/// mengirim `errorCode` (seri 1000–6000). PlayerException(0, "Source error") yang selama
/// ini buta adalah keluarga pertama: TYPE_SOURCE — kesalahan di lapisan sumber data,
/// yang sebab fisiknya (kode HTTP dsb.) hanya ada di logcat proses (lihat Diagnostik
/// Putar langkah "natif↳"). Null bila kode tak dikenal.
String? exoErrorCodeName(int code) => switch (code) {
      0 => 'ExoPlaybackException.TYPE_SOURCE',
      1 => 'ExoPlaybackException.TYPE_RENDERER',
      2 => 'ExoPlaybackException.TYPE_UNEXPECTED',
      3 => 'ExoPlaybackException.TYPE_REMOTE',
      4 => 'ExoPlaybackException.TYPE_OUT_OF_MEMORY',
      1000 => 'ERROR_CODE_UNSPECIFIED',
      1001 => 'ERROR_CODE_REMOTE_ERROR',
      1002 => 'ERROR_CODE_BEHIND_LIVE_WINDOW',
      1003 => 'ERROR_CODE_TIMEOUT',
      1004 => 'ERROR_CODE_FAILED_RUNTIME_CHECK',
      2000 => 'ERROR_CODE_IO_UNSPECIFIED',
      2001 => 'ERROR_CODE_IO_NETWORK_CONNECTION_FAILED',
      2002 => 'ERROR_CODE_IO_NETWORK_CONNECTION_TIMEOUT',
      2003 => 'ERROR_CODE_IO_INVALID_HTTP_CONTENT_TYPE',
      2004 => 'ERROR_CODE_IO_BAD_HTTP_STATUS',
      2005 => 'ERROR_CODE_IO_FILE_NOT_FOUND',
      2006 => 'ERROR_CODE_IO_NO_PERMISSION',
      2007 => 'ERROR_CODE_IO_CLEARTEXT_NOT_PERMITTED',
      2008 => 'ERROR_CODE_IO_READ_POSITION_OUT_OF_RANGE',
      3001 => 'ERROR_CODE_DECODER_INIT_FAILED',
      3002 => 'ERROR_CODE_DECODER_QUERY_FAILED',
      3003 => 'ERROR_CODE_DECODING_FAILED',
      3004 => 'ERROR_CODE_DECODING_FORMAT_UNSUPPORTED',
      3005 => 'ERROR_CODE_DECODING_FORMAT_EXCEEDS_CAPABILITIES',
      4001 => 'ERROR_CODE_DRM_UNSPECIFIED',
      4003 => 'ERROR_CODE_DRM_LICENSE_EXPIRED',
      5001 => 'ERROR_CODE_AUDIO_TRACK_INIT_FAILED',
      5002 => 'ERROR_CODE_AUDIO_TRACK_WRITE_FAILED',
      6000 => 'ERROR_CODE_DRM_SYSTEM_ERROR',
      _ => null,
    };

/// Uraian galat PEMUTAR yang digali lebih dalam (v4.2, untuk Diagnostik Putar):
/// PlatformException ditampilkan dengan details MENTAH apa adanya (rantai natif
/// ExoPlayer yang sempat dikirim platform), PlayerException dengan nama kodenya.
String describePlayerError(Object e, [StackTrace? st]) {
  if (e is PlatformException) {
    final b = StringBuffer(
        'PlatformException(code=${e.code}, message=${e.message ?? '-'}, details=${_rawDetails(e.details)})');
    if (st != null) {
      final lines = st.toString().split('\n').where((l) => l.trim().isNotEmpty).take(3).toList();
      if (lines.isNotEmpty) b.write('\n  tumpukan: ${lines.join(' | ')}');
    }
    return b.toString();
  }
  return describeError(e, st);
}

String _rawDetails(Object? d) {
  if (d == null) return '-';
  if (d is Map) {
    return '{${d.entries.map((en) => '${en.key}: ${en.value}').join(', ')}}';
  }
  return d.toString();
}

/// Galat "muat disela muat yang lebih baru" (v4.3) — perilaku NORMAL, bukan insiden.
///
/// Bukti perangkat v4.2: log insiden pemilik memuat `tangga-muat-gagal` /
/// `build-source-gagal` untuk "sesi yang dipulihkan" berisi
/// `PlayerInterruptedException: Connection aborted`. Itu just_audio membatalkan
/// setAudioSource yang sedang berjalan karena pemuatan yang lebih baru datang —
/// persis yang diharapkan saat pengguna/restorasi mengganti sumber dengan cepat.
/// Memperlakukan interupsi sebagai kegagalan sungguhan mencemari log insiden dan
/// mengaburkan kegagalan asli, jadi pemanggil WAJIB melewatinya diam-diam.
bool isInterruptionError(Object e) {
  if (e is PlayerInterruptedException) return true;
  // PlatformException/PlayerException pembungkus: kenali dari teksnya.
  final s = e.toString();
  return s.contains('PlayerInterruptedException') || s.contains('Loading interrupted');
}

String describeError(Object e, [StackTrace? st]) {
  final b = StringBuffer();
  if (e is PlayerException) {
    final name = exoErrorCodeName(e.code);
    b.write('PlayerException(code=${e.code}${name != null ? ' ($name)' : ''}, message=${e.message ?? '-'}, index=${e.index ?? '-'})');
  } else if (e is PlatformException) {
    b.write('PlatformException(code=${e.code}, message=${e.message ?? '-'}, details=${e.details})');
  } else if (e is DioException) {
    b.write('DioException(type=${e.type.name}, status=${e.response?.statusCode ?? '-'}, message=${e.message ?? '-'})');
    final data = e.response?.data;
    if (data != null) {
      var s = data.toString().replaceAll(RegExp(r'\s+'), ' ');
      if (s.length > 200) s = '${s.substring(0, 200)}…';
      b.write(' body=$s');
    }
    if (e.error != null) b.write(' sebab=${e.error}');
  } else if (e is SocketException) {
    b.write('SocketException(${e.message}, address=${e.address?.address ?? '-'}, osError=${e.osError?.message ?? '-'})');
  } else if (e is TimeoutException) {
    b.write('TimeoutException(${e.message ?? 'batas waktu terlampaui'}, durasi=${e.duration ?? '-'})');
  } else {
    b.write('${e.runtimeType}: $e');
  }
  if (st != null) {
    final lines = st.toString().split('\n').where((l) => l.trim().isNotEmpty).take(3).toList();
    if (lines.isNotEmpty) b.write('\n  tumpukan: ${lines.join(' | ')}');
  }
  return b.toString();
}
