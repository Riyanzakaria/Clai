import 'dart:async';

import 'package:just_audio/just_audio.dart';

import '../domain/models.dart';
import 'resolving_audio_source.dart';

/// Tangga strategi muat (v4.2) — jawaban atas vonis Diagnostik Putar v4.1 di perangkat.
///
/// Bukti perangkat (2026-10-23): resolusi (A) dan unduh range mentah (B) SEHAT dari HP,
/// tetapi ExoPlayer gagal memuat dengan PlayerException(0, "Source error") BAIK lewat
/// setUrl polos (C) maupun jalur proxy aplikasi (D) — dan pesan Dart-nya tidak memuat
/// sebab natif. Karena konfigurasi muat yang belum teruji masih ada, pemuatan kini
/// menaiki TANGGA tiga anak, per trek, maju saat setAudioSource gagal:
///
///   Anak 1 — AudioSource.uri ADAPTIF + header (UA pasangan klien ANDROID yang dipakai
///            resolusi + Referer music.youtube.com). C v4.1 menguji setUrl TANPA header;
///            googlevideo diketahui menolak/melayani berbeda menurut pasangan UA-URL.
///   Anak 2 — AudioSource.uri MUXED itag 18 + header sama. Format progresif ini terbukti
///            (probe PC dart:io, putaran v4.1) menerima pola Range TERBUKA ExoPlayer
///            (GET penuh 200, range terbuka 206, start>0 206) — pola yang ditolak 403
///            oleh URL audio adaptif.
///   Anak 3 — ResolvingAudioSource (proxy terbatas v4.1 + cadangan muxed lengket).
///
/// Anak yang pertama berhasil menjadi PEMENANG LENGKET sesi: trek berikutnya mulai dari
/// anak itu (urutan percobaan = rotasi mulai dari pemenang, ketiga anak tetap dicoba
/// sebelum satu lagu dinyatakan gagal). Setiap kegagalan anak dicatat pemanggil ke log
/// insiden dengan rantai galat lengkap.
class LoadLadder {
  static const int rungAdaptiveUri = 0;
  static const int rungMuxedUri = 1;
  static const int rungProxy = 2;
  static const int rungCount = 3;

  /// Header pasangan aliran googlevideo: UA klien ANDROID penerbit URL + Referer asal.
  static const Map<String, String> streamHeaders = {
    'User-Agent': ResolvingAudioSource.playerUserAgent,
    'Referer': 'https://music.youtube.com/',
  };

  static String rungLabel(int rung) => switch (rung) {
        rungAdaptiveUri => 'URI adaptif + header',
        rungMuxedUri => 'URI muxed (itag 18) + header',
        rungProxy => 'proxy ResolvingAudioSource',
        _ => 'anak $rung',
      };

  /// Resolusi URL adaptif (provider) — juga dipakai anak proxy sebagai resolusi malasnya.
  final Future<StreamInfo> Function(Track track) resolveAdaptive;

  /// Resolusi URL muxed cadangan (provider) — null bila tak tersedia.
  final Future<StreamInfo?> Function(Track track) resolveMuxed;

  /// Tag sumber (MediaItem) untuk trek.
  final Object? Function(Track track) tagFor;

  /// Apakah trek diputar dari berkas lokal (melewati tangga seluruhnya).
  final bool Function(Track track) isLocal;

  /// Berkas unduhan untuk trek (F2 Batch 2): bila ada, trek diputar dari
  /// berkas ini tanpa menyentuh tangga — berlaku juga di mode offline.
  final String? Function(Track track)? localFileFor;

  int _sticky = rungAdaptiveUri;

  LoadLadder({
    required this.resolveAdaptive,
    required this.resolveMuxed,
    required this.tagFor,
    required this.isLocal,
    this.localFileFor,
  });

  /// Anak tangga pemenang sesi saat ini — titik mulai setiap pemuatan berikutnya.
  int get stickyRung => _sticky;

  /// Urutan percobaan satu pemuatan: rotasi mulai dari pemenang lengket.
  List<int> orderForAttempt() =>
      [for (var i = 0; i < rungCount; i++) (_sticky + i) % rungCount];

  /// Majukan pemenang lengket satu anak (dipakai jalur galat putar per trek).
  int advance() {
    _sticky = (_sticky + 1) % rungCount;
    return _sticky;
  }

  /// Jalankan satu pemuatan menaiki tangga: [attempt] membangun & memasang sumber
  /// untuk anak yang diberikan dan MELEMPAR bila pemasangan gagal. Berhenti di anak
  /// pertama yang berhasil (anak itu menjadi pemenang lengket) dan mengembalikan
  /// nomornya; melempar galat anak terakhir bila ketiga anak gugur.
  Future<int> run({
    required Future<void> Function(int rung) attempt,
    void Function(int rung, Object error, StackTrace stackTrace)? onRungFailed,
  }) async {
    Object? lastError;
    StackTrace? lastStack;
    for (final rung in orderForAttempt()) {
      try {
        await attempt(rung);
        _sticky = rung;
        return rung;
      } catch (e, st) {
        lastError = e;
        lastStack = st;
        onRungFailed?.call(rung, e, st);
      }
    }
    Error.throwWithStackTrace(
        lastError ?? StateError('tangga muat kosong'), lastStack ?? StackTrace.current);
  }

  /// Bangun anak sumber untuk [t] pada anak tangga [rung].
  ///
  /// [strict] = trek yang menentukan keberhasilan pemasangan (trek awal jendela /
  /// subjek diagnostik): kegagalan resolusinya DILEMPAR agar tangga melihat anak ini
  /// gugur dan maju. Non-ketat (trek lanjutan jendela): kegagalan resolusi menurun
  /// diam-diam ke anak proxy untuk trek itu saja, agar satu trek buruk tidak membunuh
  /// seluruh jendela — kegagalannya akan muncul saat trek itu sendiri dimainkan
  /// (dan jalur galat putar menaikkan tangga untuknya).
  Future<AudioSource> childFor(Track t, int rung, {bool strict = false}) async {
    final downloaded = localFileFor?.call(t);
    if (downloaded != null) {
      return AudioSource.uri(Uri.file(downloaded), tag: tagFor(t));
    }
    if (isLocal(t)) {
      return AudioSource.uri(Uri.parse(t.playableRef), tag: tagFor(t));
    }
    switch (rung) {
      case rungAdaptiveUri:
        try {
          final info = await resolveAdaptive(t);
          return AudioSource.uri(Uri.parse(info.url),
              headers: streamHeaders, tag: tagFor(t));
        } catch (e) {
          if (strict) rethrow;
          return _proxyChild(t);
        }
      case rungMuxedUri:
        StreamInfo? info;
        Object? muxError;
        try {
          info = await resolveMuxed(t);
        } catch (e) {
          muxError = e;
        }
        if (info != null) {
          return AudioSource.uri(Uri.parse(info.url),
              headers: streamHeaders, tag: tagFor(t));
        }
        if (strict) {
          throw StateError('aliran muxed tidak tersedia untuk "${t.title}"'
              '${muxError != null ? ': $muxError' : ''}');
        }
        return _proxyChild(t);
      default: // rungProxy
        return _proxyChild(t);
    }
  }

  AudioSource _proxyChild(Track t) => ResolvingAudioSource(
        t,
        () => resolveAdaptive(t),
        resolveFallback: () => resolveMuxed(t),
        tag: tagFor(t),
      );
}
