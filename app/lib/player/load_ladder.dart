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
///
/// Ronde 8093 — MASA PERCOBAAN (memutus "tangga pemenang lengket", dossier
/// REPRO 23 Nov 2026): kelengketan di atas pernah menjadi kebuntuan — sesudah
/// SATU 403, pemenang pindah ke muxed dan anak adaptif tidak pernah dicoba
/// lagi, sebab satu-satunya jalan pulih lama (onRecovered resolver DIRECT)
/// mensyaratkan direct-ok untuk trek korban persis, yang mustahil terjadi
/// selama tak ada pemuatan melewati resolveAdaptive. Kini tangga menghitung
/// kemenangan di anak ter-demosi; sesudah [probeInitialThreshold] kemenangan
/// beruntun, SATU pemuatan berikutnya menjadi masa percobaan: anak adaptif
/// dicoba pertama (anak lain menyusul seperti biasa). Berhasil → lengket
/// kembali ke adaptif penuh dan hitungan direset. Gagal → hitungan direset
/// dan ambang percobaan DIGANDAKAN (5→10→20→40, dibatasi
/// [probeMaxThreshold]) — sumber yang sungguh mati tidak dihajar, dan tidak
/// ada loop: percobaan berikutnya menunggu ambang baru terpenuhi penuh.
/// Backoff dipilih berbasis HITUNGAN muatan, bukan jam dinding: tangga ini
/// murni digerakkan peristiwa run(), dan yang menyembuhkan 403 adalah
/// resolusi yang dicoba lagi (sesi minter disegarkan resolver pada resolusi
/// pertama sesudah ditandai basi), bukan waktu yang berlalu.
class LoadLadder {
  static const int rungAdaptiveUri = 0;
  static const int rungMuxedUri = 1;
  static const int rungProxy = 2;
  static const int rungCount = 3;

  /// Kemenangan beruntun di anak ter-demosi yang memicu masa percobaan
  /// pertama (Ronde 8093).
  static const int probeInitialThreshold = 5;

  /// Batas atas ambang masa percobaan sesudah penggandaan beruntun.
  static const int probeMaxThreshold = 40;

  /// Header pasangan aliran googlevideo: UA klien ANDROID penerbit URL + Referer asal.
  static const Map<String, String> streamHeaders = {
    'User-Agent': ResolvingAudioSource.playerUserAgent,
    'Referer': 'https://music.youtube.com/',
  };

  /// Header untuk SATU info aliran: pasangan UA–URL dihormati — info yang
  /// membawa [StreamInfo.userAgent] sendiri (jalur DIRECT-1) diambil
  /// dengan UA penerbitnya, info lain dengan UA bawaan di atas.
  static Map<String, String> headersFor(StreamInfo info) => {
        ...streamHeaders,
        if (info.userAgent != null) 'User-Agent': info.userAgent!,
      };

  static String rungLabel(int rung) => switch (rung) {
        rungAdaptiveUri => 'URI adaptif + header',
        rungMuxedUri => 'URI muxed (itag 18) + header',
        rungProxy => 'proxy ResolvingAudioSource',
        _ => 'anak $rung',
      };

  /// Resolusi URL adaptif (provider) — juga dipakai anak proxy sebagai resolusi malasnya.
  /// [stillWanted] diteruskan dari [childFor]: pemeriksaan kehendak yang
  /// dinilai ulang tepat sebelum resolusi berat dieksekusi (Ronde 8054).
  final Future<StreamInfo> Function(Track track,
      {bool Function()? stillWanted}) resolveAdaptive;

  /// Resolusi URL muxed cadangan (provider) — null bila tak tersedia.
  final Future<StreamInfo?> Function(Track track) resolveMuxed;

  /// Tag sumber (MediaItem) untuk trek.
  final Object? Function(Track track) tagFor;

  /// Apakah trek diputar dari berkas lokal (melewati tangga seluruhnya).
  final bool Function(Track track) isLocal;

  /// Berkas unduhan untuk trek (F2 Batch 2): bila ada, trek diputar dari
  /// berkas ini tanpa menyentuh tangga — berlaku juga di mode offline.
  final String? Function(Track track)? localFileFor;

  /// Kabel pemulihan penolakan (Tahap 3): dipanggil anak proxy saat URL
  /// adaptif sebuah trek ditolak edge (403 sesudah coba-ulang) dan proxy
  /// beralih ke cadangan muxed — resolver menyegarkan sesi/mengecualikan
  /// trek dari laporan ini.
  final void Function(Track track)? onAdaptiveRejected;

  /// Ronde 8093: tangga ter-demosi — pemenang lengket berpindah dari anak
  /// adaptif ke anak [toRung] lewat satu kemenangan [run]. (Demosi lewat
  /// [advance] tidak lewat sini; situs panggilnya mencatat sendiri.)
  final void Function(int toRung)? onDemoted;

  /// Ronde 8093: satu [run] menjadi masa percobaan — anak adaptif akan
  /// dicoba pertama sesudah [afterWins] kemenangan beruntun di anak
  /// ter-demosi [demotedRung].
  final void Function(int demotedRung, int afterWins)? onProbe;

  /// Ronde 8093: pemenang lengket kembali ke anak adaptif dari anak
  /// [fromRung] di dalam [run] (masa percobaan berhasil atau kemenangan
  /// rotasi alami). Pemulihan lewat [resetSticky] eksternal tidak lewat
  /// sini — jalurnya mencatat sendiri.
  final void Function(int fromRung)? onRecoveredToAdaptive;

  int _sticky = rungAdaptiveUri;

  /// Ronde 8093: kemenangan beruntun di pemenang lengket ter-demosi sejak
  /// demosi / masa percobaan gagal terakhir.
  int _probeWins = 0;

  /// Ronde 8093: ambang masa percobaan berjalan (digandakan tiap
  /// percobaan gagal, direset ke [probeInitialThreshold] tiap pulih).
  int _probeThreshold = probeInitialThreshold;

  bool _lastRunRecoveredToAdaptive = false;

  LoadLadder({
    required this.resolveAdaptive,
    required this.resolveMuxed,
    required this.tagFor,
    required this.isLocal,
    this.localFileFor,
    this.onAdaptiveRejected,
    this.onDemoted,
    this.onProbe,
    this.onRecoveredToAdaptive,
  });

  /// Anak tangga pemenang sesi saat ini — titik mulai setiap pemuatan berikutnya.
  int get stickyRung => _sticky;

  /// Urutan percobaan satu pemuatan: rotasi mulai dari pemenang lengket.
  List<int> orderForAttempt() =>
      [for (var i = 0; i < rungCount; i++) (_sticky + i) % rungCount];

  /// Apakah [run] terakhir mengembalikan pemenang lengket ke anak adaptif
  /// dari anak ter-demosi (Ronde 8093) — diatur ulang di awal tiap [run].
  /// Dipakai situs preload crossfade: kemenangan masa percobaan BUKAN
  /// degradasi (anak yang menang adalah anak terbaik).
  bool get lastRunRecoveredToAdaptive => _lastRunRecoveredToAdaptive;

  /// Majukan pemenang lengket satu anak (dipakai jalur galat putar per trek).
  int advance() {
    _sticky = (_sticky + 1) % rungCount;
    // Ronde 8093: pindah anak = hitungan masa percobaan mulai dari anak
    // baru; kembali penuh ke adaptif = keadaan percobaan bersih. Ambang
    // berjalan TIDAK direset oleh perpindahan antar anak bukan-adaptif —
    // backoff yang sudah berjalan tidak hilang karena demosi bertambah.
    if (_sticky == rungAdaptiveUri) {
      _resetProbe();
    } else {
      _probeWins = 0;
    }
    return _sticky;
  }

  /// Kembalikan pemenang lengket ke anak adaptif (Tahap 3): dipanggil
  /// saat resolver DIRECT terbukti pulih sesudah penolakan — tanpa ini,
  /// SATU 403 transien saat muat mendemosi jalur adaptif untuk seluruh
  /// sesi proses, padahal resolver sudah sehat lagi.
  void resetSticky() {
    _sticky = rungAdaptiveUri;
    _resetProbe();
  }

  void _resetProbe() {
    _probeWins = 0;
    _probeThreshold = probeInitialThreshold;
  }

  void _failProbe() {
    _probeWins = 0;
    final doubled = _probeThreshold * 2;
    _probeThreshold =
        doubled > probeMaxThreshold ? probeMaxThreshold : doubled;
  }

  /// Bookkeeping kelengketan sesudah satu kemenangan [run] di anak [to]
  /// (pemenang sebelumnya [from]); [probing] = run ini masa percobaan.
  void _afterWin(int from, int to, {required bool probing}) {
    if (to == rungAdaptiveUri) {
      if (from != rungAdaptiveUri) {
        _lastRunRecoveredToAdaptive = true;
        onRecoveredToAdaptive?.call(from);
      }
      _resetProbe();
      return;
    }
    if (probing) {
      // Masa percobaan gugur di anak adaptif dan anak cadangan yang
      // menang: kembali ter-demosi dengan backoff berganda, tanpa loop.
      _failProbe();
      return;
    }
    if (to != from) {
      // Pindah anak bukan-adaptif: hitungan mulai dari anak baru.
      _probeWins = 0;
      if (from == rungAdaptiveUri) onDemoted?.call(to);
      return;
    }
    // Menang lagi di pemenang lengket ter-demosi yang sama.
    _probeWins++;
  }

  /// Jalankan satu pemuatan menaiki tangga: [attempt] membangun & memasang sumber
  /// untuk anak yang diberikan dan MELEMPAR bila pemasangan gagal. Berhenti di anak
  /// pertama yang berhasil (anak itu menjadi pemenang lengket) dan mengembalikan
  /// nomornya; melempar galat anak terakhir bila ketiga anak gugur.
  ///
  /// [isAbortError] (Ronde 8054): kelas galat BATAL — pembangunan yang sudah
  /// dikalahkan perintah putar lebih baru. Galat kelas ini BUKAN kegagalan
  /// anak tangga: dilempar ulang seketika tanpa menaiki anak berikutnya dan
  /// tanpa memanggil [onRungFailed]. (Sebelumnya pembangunan yang kalah
  /// tetap membakar resolusi muxed + anak proxy sebelum mati, memperpanjang
  /// antrean di belakang ketukan terbaru.)
  Future<int> run({
    required Future<void> Function(int rung) attempt,
    void Function(int rung, Object error, StackTrace stackTrace)? onRungFailed,
    bool Function(Object error)? isAbortError,
  }) async {
    _lastRunRecoveredToAdaptive = false;
    // Ronde 8093: masa percobaan — tangga ter-demosi yang sudah menang
    // _probeThreshold kali beruntun di anak lengketnya mencoba anak
    // adaptif SEKALI di depan pada pemuatan ini; anak-anak lain menyusul
    // dalam rotasi pemenang seperti biasa.
    final probing =
        _sticky != rungAdaptiveUri && _probeWins >= _probeThreshold;
    final order = probing
        ? [
            rungAdaptiveUri,
            ...orderForAttempt().where((r) => r != rungAdaptiveUri),
          ]
        : orderForAttempt();
    if (probing) onProbe?.call(_sticky, _probeWins);
    Object? lastError;
    StackTrace? lastStack;
    for (final rung in order) {
      try {
        await attempt(rung);
        final from = _sticky;
        _sticky = rung;
        _afterWin(from, rung, probing: probing);
        return rung;
      } catch (e, st) {
        if (isAbortError?.call(e) ?? false) {
          // Galat kelas BATAL bukan bukti kesehatan anak mana pun: masa
          // percobaan TIDAK terhitung gagal — ia tetap bersenjata untuk
          // pemuatan berikutnya yang sungguh berjalan.
          Error.throwWithStackTrace(e, st);
        }
        lastError = e;
        lastStack = st;
        onRungFailed?.call(rung, e, st);
      }
    }
    // Semua anak gugur pada run masa percobaan: percobaan tetap terhitung
    // gagal (anak adaptif sungguh dicoba dan gugur) — backoff berganda.
    if (probing) _failProbe();
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
  /// [stillWanted] (Ronde 8054): diteruskan ke resolusi adaptif agar
  /// pekerjaan pembangunan yang sudah dikalahkan bisa dibuang dari antrean
  /// resolusi sebelum dieksekusi. Anak proxy TIDAK menerimanya: resolusinya
  /// malas (saat byte benar-benar diambil trek itu sedang dimainkan).
  Future<AudioSource> childFor(Track t, int rung,
      {bool strict = false, bool Function()? stillWanted}) async {
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
          final info = await resolveAdaptive(t, stillWanted: stillWanted);
          return AudioSource.uri(Uri.parse(info.url),
              headers: headersFor(info), tag: tagFor(t));
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
              headers: headersFor(info), tag: tagFor(t));
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
        onPrimaryRejected:
            onAdaptiveRejected == null ? null : () => onAdaptiveRejected!(t),
      );
}
