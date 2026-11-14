import 'dart:async';
import '../l10n/l10n.dart';
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import '../core/artwork.dart';
import '../core/display_text.dart';
import '../core/error_describe.dart';
import '../data/app_db.dart';
import '../domain/models.dart';
import '../providers/music_provider.dart';
import '../providers/ytmusic/direct_types.dart';
import '../services/ambient_theme.dart';
import '../services/audio_fx_service.dart';
import '../services/gate_metrics.dart';
import '../services/observability.dart';
import '../services/sys_channel.dart';
import 'crossfade.dart';
import 'interruption_policy.dart';
import 'load_ladder.dart';
import 'queue_engine.dart';
import 'similarity.dart';
import 'session_coherence.dart';
import 'session_fx_tracker.dart';
import 'source_sync.dart';
import 'stall_watchdog.dart';
import 'test_tone.dart';

/// Pembangunan sumber yang dikalahkan perintah putar lebih baru (v4.4):
/// gugur diam-diam di titik komit — bukan galat, bukan insiden.
class _Superseded implements Exception {
  const _Superseded();
}

/// Pemetaan mode acak engine → mode acak audio_service (satu-satunya
/// pemetaan; dipakai _transformState dan syncShuffleState). audio_service
/// hanya mengenal acak penuh / mati — pure dan smart sama-sama 'all';
/// pembeda pure-vs-smart hidup di engine & sakelar UI, bukan di status.
AudioServiceShuffleMode audioServiceShuffleMode(ShuffleMode mode) =>
    mode != ShuffleMode.off
    ? AudioServiceShuffleMode.all
    : AudioServiceShuffleMode.none;

/// Langkah Mundur gapless pada posisi ≤ 3 dtk (PRD 5.4 + Ronde 8055).
/// Urutan tetap: pendahulu DI JENDELA sumber selalu dipakai dulu (rantai
/// Maju/Mundur murni tidak berubah); bila jendela tidak memuatnya — sumber
/// dibangun ulang berjangkar di trek berjalan oleh ketuk-lompat, eskalasi
/// _verifyAdvance, bangun ekor, atau pulih sesi — Mundur jatuh ke RIWAYAT
/// SESI (engine.played), sumber yang sama dengan jalur crossfade; keduanya
/// kosong → ulang trek berjalan dari awal.
enum GaplessPreviousStep { windowPrevious, historyPrevious, restartCurrent }

GaplessPreviousStep gaplessPreviousStep({
  required bool hasPreviousInWindow,
  required bool hasSessionHistory,
}) =>
    hasPreviousInWindow
        ? GaplessPreviousStep.windowPrevious
        : hasSessionHistory
            ? GaplessPreviousStep.historyPrevious
            : GaplessPreviousStep.restartCurrent;

/// Keputusan putar-balik sebelum putar (Ronde 8057): true HANYA pada
/// keadaan completed. just_audio/ExoPlayer MENGABAIKAN play() pada
/// keadaan completed — pemain tetap parkir di posisi == durasi dan
/// tekanan Putar menjadi no-op senyap. Pemulihannya adalah seek ke
/// awal SEBELUM play(). Trek terakhir antrean tidak pernah diselamatkan
/// peristiwa indeks-berikutnya, dan _onPlaybackCompleted hanya memajukan
/// bila ada sambungan/Putar Otomatis — jadi tanpa putar-balik ini,
/// lagu terakhir yang selesai alami tidak bisa diputar lagi dari awal.
/// Keadaan lain (idle/loading/buffering/ready) TIDAK diputar-balik:
/// play() di sana sah melanjutkan dari posisi berjalan (jeda biasa).
bool shouldRewindBeforePlay(ProcessingState state) =>
    state == ProcessingState.completed;

/// Kumpulkan kunci trek dari peta snapshot secara DEFENSIF (Ronde Bug
/// Notifikasi): entri yang bukan Map atau tak punya 'p'/'i' String DILEWATI,
/// bukan melempar — satu entri cacat tidak boleh membunuh seluruh restorasi.
/// (Terbukti di emulator: entri manual tanpa 'i' membuat restore gagal dengan
/// TypeError di SETIAP start dingin, dan keadaan itu hanya sembuh oleh hapus
/// data — persis riwayat cacat notifikasi di HP pemilik.)
Set<TrackKey> collectSnapshotKeys(Map<String, Object?> snap) {
  final keys = <TrackKey>{};
  for (final section in ['seeds', 'manual', 'continuation', 'autoplay', 'played']) {
    final raw = snap[section];
    if (raw is! List) continue;
    for (final e in raw) {
      if (e is Map && e['p'] is String && e['i'] is String) {
        keys.add(TrackKey(e['p'] as String, e['i'] as String));
      }
    }
  }
  final cur = snap['currentRef'];
  if (cur is String && cur.contains('|')) {
    final parts = cur.split('|');
    final head = parts.first;
    final tail = parts.sublist(1).join('|');
    if (head.isNotEmpty && tail.isNotEmpty) keys.add(TrackKey(head, tail));
  }
  return keys;
}

/// Satu-satunya pemilik player (L-01, L-14). UI tidak pernah menyentuh just_audio langsung.
/// Sumber audio = satu ConcatenatingAudioSource yang mencerminkan antrean mesin (Blueprint D-02),
/// dengan jendela materi ±60 trek di sekitar indeks berjalan agar antrean ratusan lagu tetap ringan.
class ClaiAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  final AppDb db;
  final MusicProvider provider;
  final SimilaritySource similaritySource;
  final AudioFxService _fx = AudioFxService();

  /// Header aliran TIDAK lewat proxy lokal just_audio (v4.2, terbukti logcat emulator):
  /// dengan nilai bawaan (true), UriAudioSource ber-header disajikan lewat proxy HTTP
  /// cleartext di 127.0.0.1 — dan Android (targetSdk ≥ 28) memblokir cleartext bahkan
  /// ke loopback, sehingga ExoPlayer mati sebagai TYPE_SOURCE sebelum mengambil byte
  /// apa pun. false = header dikirim langsung oleh ExoPlayer (setUserAgent +
  /// setDefaultRequestProperties). Sumber aliran (anak tangga 3) tetap lewat proxy —
  /// kini diizinkan khusus loopback oleh res/xml/network_security_config.xml.
  static const bool useProxyForRequestHeaders = false;

  // handleInterruptions DIMATIKAN untuk kedua pemain (laporan riyan
  // 2026-10-24): just_audio punya kebijakan interupsi bawaan yang
  // melanjutkan putar sendiri saat fokus kembali (_playInterrupted) —
  // dan pause() eksternal TIDAK bisa membatalkannya karena pause()
  // just_audio kembali dini bila pemain sudah jeda. Kebijakan interupsi
  // Clai (matriks 2.2: hak lanjut hanya dari interupsi, jeda manual
  // lengket) harus menjadi pemilik tunggal lewat listener sesi di _init.
  final AudioPlayer _player = AudioPlayer(
    useProxyForRequestHeaders: useProxyForRequestHeaders,
    handleInterruptions: false,
  );

  /// Pemain kedua jalur crossfade (ADR-002): hanya satu pemain yang aktif
  /// berbunyi pada satu waktu di luar jendela ramp; pemain diam memegang
  /// trek berikutnya yang sudah dimuat (preload).
  final AudioPlayer _playerB = AudioPlayer(
    useProxyForRequestHeaders: useProxyForRequestHeaders,
    handleInterruptions: false,
  );

  /// True bila pemain B yang sedang memegang lagu berjalan (jalur crossfade).
  bool _xfActiveB = false;

  /// Pemain yang memegang lagu berjalan — di jalur gapless selalu [_player].
  AudioPlayer get _activePlayer => _xfActiveB ? _playerB : _player;
  AudioPlayer get _idlePlayer => _xfActiveB ? _player : _playerB;

  // ---------- F2 Batch 2: mode transisi (ADR-002) ----------
  /// 'gapless' (bawaan) | 'crossfade'. Mode aktif; [pendingTransitionMode]
  /// adalah mode yang diminta saat lagu berjalan — berlaku di batas lagu,
  /// tidak pernah di tengah lagu.
  String transitionMode = 'gapless';
  String? pendingTransitionMode;
  double crossfadeSecs = 6;

  bool get _xfMode =>
      transitionMode == 'crossfade' && pendingTransitionMode != 'gapless';

  /// Keadaan monitor crossfade: trek berikutnya yang sudah dimuat di pemain
  /// diam + status ramp yang sedang berjalan.
  Track? _xfPreloaded;

  /// Ronde 8059 (keputusan pemilik 2026-11-13, perubahan semantik
  /// ADR-002): preload trek ini hanya berhasil di anak tangga CADANGAN
  /// (sumber langsungnya gagal di tingkat pemain) → transisinya
  /// terdegradasi menjadi potong biasa: ramp TIDAK dijalankan untuknya;
  /// trek mulai lewat _xfPlayCurrent di akhir trek berjalan (yang juga
  /// menaiki tangga). Ramp untuk trek sehat tidak berubah sama sekali.
  bool _xfPreloadDegraded = false;
  bool _xfRamping = false;
  DateTime _xfRampStart = DateTime.fromMillisecondsSinceEpoch(0);
  double _xfRampSecs = 6;
  Timer? _xfMonitorTimer;
  Timer? _xfRampTimer;
  TrackKey? _xfPreloadFailedKey;

  /// Kunci trek yang preload-nya SEDANG berjalan. Tanpa penjaga ini,
  /// _xfTick (200 mdtk) menembakkan preload baru untuk kepala yang sama
  /// selagi yang lama belum selesai — mereka saling membatalkan di
  /// pemutar idle dan membanjiri log (temuan uji emulator F2B2).
  TrackKey? _xfPreloadInFlightKey;

  // ---------- F2 Batch 2: volume master + normalisasi ----------
  /// Faktor volume master (1.0 normal; 0.35 saat ducking interupsi).
  double _masterVolume = 1.0;

  /// Faktor pudar tidur (1.0 normal → 0 saat timer tidur memudar). Dikalikan
  /// di _volumeFor & ramp crossfade agar pudar tidak tertimpa transisi.
  double _sleepFade = 1.0;

  // ---------- F2.5: peredupan tidur di bentang akhir ----------
  /// Rampa peredupan aktif: faktor diturunkan halus (smoothstep) dari 1 ke
  /// 0 selama jendela akhir timer — lewat faktor [_sleepFade] yang sama,
  /// sehingga rukun dengan volume master, normalisasi, dan crossfade
  /// (semua jalur menerapkan faktor ini secara multiplikatif).
  Timer? _sleepFadeTimer;
  DateTime? _sleepFadeRampStart;
  Duration _sleepFadeRampWindow = Duration.zero;
  bool _sleepFaded = false;
  TrackKey? _sleepSongFadeKey;

  /// Kait F2.5 (disambung app.dart): true saat timer tidur mode akhir-lagu
  /// sedang terpasang — memicu peredupan di bentang akhir trek berjalan.
  bool Function()? sleepEndOfSongArmed;

  /// Mulai rampa peredupan selama [window] menuju nol.
  void beginSleepFade(Duration window) {
    _sleepFadeTimer?.cancel();
    _sleepFadeTimer = null;
    if (window <= Duration.zero) {
      _sleepFade = 0;
      _sleepFaded = true;
      unawaited(_applyVolume());
      return;
    }
    _sleepFadeRampStart = DateTime.now();
    _sleepFadeRampWindow = window;
    _sleepFaded = false;
    Observability.instance.log(
        'tidur-pudar-mulai', 'jendela ${window.inMilliseconds} ms');
    var lastLoggedStep = -1;
    DateTime? notPlayingSince;
    _sleepFadeTimer =
        Timer.periodic(const Duration(milliseconds: 200), (t) {
      if (!_activePlayer.playing) {
        // Jeda sesaat bisa berarti transisi antar-lagu di dalam jendela
        // pudar — beri tenggang 2 detik sebelum menyimpulkan pengguna
        // mengambil alih. Jeda manual yang menetap tetap membatalkan
        // peredupan dan memulihkan faktor (putaran berikutnya tak senyap).
        notPlayingSince ??= DateTime.now();
        final since = notPlayingSince!;
        if (DateTime.now().difference(since) >
            const Duration(seconds: 2)) {
          t.cancel();
          _sleepFadeTimer = null;
          _sleepFade = 1.0;
          _sleepFaded = false;
          unawaited(_applyVolume());
          Observability.instance.log(
              'tidur-pudar-batal', 'jeda menetap di tengah rampa');
        }
        return;
      }
      notPlayingSince = null;
      final elapsed = DateTime.now().difference(_sleepFadeRampStart!);
      final x = (elapsed.inMilliseconds / _sleepFadeRampWindow.inMilliseconds)
          .clamp(0.0, 1.0);
      final smooth = x * x * (3 - 2 * x); // smoothstep: awal & akhir lembut
      _sleepFade = 1 - smooth;
      unawaited(_applyVolume());
      final step = (x * 4).floor();
      if (step != lastLoggedStep) {
        lastLoggedStep = step;
        Observability.instance.log(
            'tidur-pudar', 'faktor ${_sleepFade.toStringAsFixed(2)}');
      }
      if (x >= 1) {
        t.cancel();
        _sleepFadeTimer = null;
        _sleepFade = 0;
        _sleepFaded = true;
        unawaited(_applyVolume());
        Observability.instance.log('tidur-pudar-selesai', 'faktor 0.00');
      }
    });
  }

  /// Batalkan peredupan tidur apa pun yang berjalan & pulihkan volume.
  void cancelSleepFade() {
    _sleepFadeTimer?.cancel();
    _sleepFadeTimer = null;
    _sleepFaded = false;
    _sleepSongFadeKey = null;
    if (_sleepFade != 1.0) {
      _sleepFade = 1.0;
      unawaited(_applyVolume());
    }
  }

  /// Peredupan akhir-lagu untuk mode akhir-lagu: dipanggil dari aliran
  /// posisi pemain aktif; murah (gerbang bool + kunci trek) dan hanya
  /// menyala sekali per trek saat sisa trek memasuki jendela akhir.
  void _maybeSleepSongEndFade(Duration pos) {
    if (_sleepFadeTimer != null || _sleepFaded) return;
    if (!(sleepEndOfSongArmed?.call() ?? false)) return;
    final cur = engine.current;
    if (cur == null || _sleepSongFadeKey == cur.key) return;
    final dur = _activePlayer.duration ?? cur.duration;
    if (dur == null || dur <= Duration.zero) return;
    final remaining = dur - pos;
    if (remaining <= Duration.zero ||
        remaining > const Duration(seconds: 30)) {
      return;
    }
    _sleepSongFadeKey = cur.key;
    beginSleepFade(remaining);
  }

  /// Kait F2: MEMILIH putaran/trek baru secara manual (membatalkan
  /// timer tidur aktif) & akhir lagu alami. Navigasi trek
  /// Berikutnya/Sebelumnya memakai kait terpisah [onManualTrackSkip]
  /// yang TIDAK membatalkan timer aktif (Ronde 8063).
  VoidCallback? onManualPlayAction;
  VoidCallback? onManualTrackSkip;
  VoidCallback? onNaturalTrackEnd;

  /// Faktor volume berkendara (1.0 normal): Volume Ikut Kecepatan menggerakkan
  /// faktor ini di antara titik berhenti & titik tercepat pengguna — plafon
  /// pengguna tidak pernah dilampaui karena layanan menghitung di rentang itu.
  double _drivingVolume = 1.0;

  /// Pola tekan satu tombol (PRD 5.14 A skema ii): bila nyala, play()/pause()
  /// dari tombol media tidak langsung beraksi — hitungan tekan dalam 500 ms
  /// menentukan aksi (1 = putar/jeda, 2 = berikutnya, 3+ = sebelumnya).
  bool drivingPatterns = false;
  int _patternCount = 0;
  Timer? _patternTimer;
  bool _patternResolving = false;

  Future<void> setDrivingVolume(double v) async {
    _drivingVolume = v.clamp(0.0, 1.0);
    await _applyVolume();
  }

  void _patternPress() {
    _patternCount++;
    _patternTimer?.cancel();
    _patternTimer = Timer(const Duration(milliseconds: 500), () async {
      final n = _patternCount;
      _patternCount = 0;
      _patternResolving = true;
      try {
        if (n == 1) {
          if (_activePlayer.playing) {
            await pause();
          } else {
            await play();
          }
        } else if (n == 2) {
          await skipToNext();
        } else if (n >= 3) {
          await skipToPrevious();
        }
      } finally {
        _patternResolving = false;
      }
    });
  }

  /// Normalisasi menyala: volume tiap lagu dikali gain per-lagunya.
  bool normalizationOn = false;

  /// Napas ambien (U1) meminta Visualizer: konsumen KEDUA aliran RMS.
  /// Ditulis cangkang aplikasi dari keadaan tema (tema hidup && napas
  /// hidup && bukan Kurangi Efek). Visualizer menyala bila normalisasi
  /// ATAU napas membutuhkannya — satu Visualizer, dua konsumen
  /// (perbaikan ronde Player F3; sebelumnya napas menumpang sakelar
  /// normalisasi sehingga mati biner di keadaan bawaannya yang mati).
  bool breathVisWanted = false;

  /// Perekam waveform ukur meminta Visualizer: konsumen KETIGA
  /// aliran RMS (Sisipan G-1, 2026-11-10). Ditulis cangkang aplikasi
  /// dari kelengkapan data trek berjalan — menyala hanya selama data
  /// trek itu BELUM lengkap terukur; trek penuh tidak membakar
  /// Visualizer. Tanpa suara ini, waveform kelaparan permanen pada
  /// keadaan bawaan (normalisasi mati + napas mati): bukti perangkat
  /// pemilik atas 8039, waveform berhenti di ±23% ember.
  bool waveformVisWanted = false;

  /// Apakah Visualizer dibutuhkan sesi mana pun saat ini.
  bool get _visNeeded => visualizerNeeded(
        normalizationOn: normalizationOn,
        breathWanted: breathVisWanted,
        waveformWanted: waveformVisWanted,
      );

  /// Rantai serialisasi sinkronisasi Visualizer (Ronde 8050):
  /// semua jalur yang menyentuh keadaan Visualizer — gerbang
  /// konsumen dari cangkang, kemunculan sesi baru, penjaga
  /// kesehatan — masuk SATU antrean futures. Sebelumnya tiap jalur
  /// memanggil mulai/berhenti secara asinkron bebas; dua sinkronisasi
  /// yang tumpang tindih (gerbang berayun saat ganti trek + sesi
  /// muncul bersamaan) bisa saling mendahului dan meninggalkan
  /// Visualizer berhenti padahal gerbang menyala — rantai ukur mati
  /// tanpa satu pun galat. Kini kebutuhan dibaca ulang pada saat
  /// giliran eksekusi tiba, bukan pada saat panggilan dibuat.
  Future<void> _visSyncChain = Future<void>.value();

  /// Selaraskan Visualizer semua sesi dengan kebutuhan konsumen
  /// ([_visNeeded]): nyala → mulai di setiap sesi hidup (kegagalan
  /// tercatat), mati → berhenti di semuanya. [forceRestart] (dari
  /// penjaga kesehatan) menghentikan dulu lalu memulai lagi —
  /// obat untuk Visualizer yang menempel tetapi berhenti mengalir
  /// di perangkat.
  Future<void> _syncVisualizer({bool forceRestart = false}) {
    final run = _visSyncChain.then(
      (_) => _syncVisualizerNow(forceRestart: forceRestart),
    );
    _visSyncChain = run.catchError((_) {});
    return run;
  }

  /// Kunci kegagalan mulai Visualizer terakhir yang SUDAH dicatat
  /// (Ronde 8064): kegagalan yang sama persis (sesi + alasan) tidak
  /// dicatat berulang — dalam keadaan izin mikrofon tertolak,
  /// penjaga menegaskan ulang tiap ±20 detik dan setiap penegasan
  /// menulis entri yang sama, membanjiri Log insiden (retensi 200)
  /// dan mengubur insiden lain. Kegagalan BERBEDA atau keberhasilan
  /// sesudah gagal tetap tercatat lewat kunci yang berubah/terhapus.
  String? _lastVisFailKey;

  Future<void> _syncVisualizerNow({bool forceRestart = false}) async {
    final on = _visNeeded;
    for (final id in audioSessionIds) {
      if (id == null) continue;
      if (on) {
        if (forceRestart) await _fx.visStop(id);
        final ok = await _fx.visStart(id);
        if (!ok) {
          final failKey = '$id|${_fx.lastVisError ?? ''}';
          if (failKey != _lastVisFailKey) {
            _lastVisFailKey = failKey;
            Observability.instance.log(
              'vis-gagal-mulai',
              'sesi $id (gerbang konsumen): ${_fx.lastVisError ?? 'alasan tak terbaca'}',
            );
          }
        } else if (_lastVisFailKey != null &&
            _lastVisFailKey!.startsWith('$id|')) {
          _lastVisFailKey = null;
        }
      } else {
        await _fx.visStop(id);
      }
    }
  }

  /// Tegaskan ulang Visualizer dari luar handler (Ronde 8064):
  /// dipakai cangkang sesudah izin mikrofon diberikan, agar rantai
  /// ukur pulih SEKETIKA — tanpa menunggu penjaga (±20 detik) dan
  /// tanpa ganti trek. Inilah jalan pulih mandiri untuk keadaan
  /// izin yang baru terpasang di tengah sesi.
  Future<void> reassertVisualizer() => _syncVisualizer(forceRestart: true);

  // ---- Penjaga kesehatan Visualizer (Ronde 8050) ----
  /// Detak peristiwa RMS terakhir (diberi makan cangkang dari
  /// pendengar alirannya — sumber yang sama dengan perekam).
  DateTime? _lastRmsAt;

  /// Penegasan ulang terakhir oleh penjaga (untuk jeda pendinginan).
  DateTime? _lastVisReassertAt;

  /// Berapa kali penjaga menegaskan ulang sesi ini — terbaca di
  /// Diagnostik Putar (ekor baris "Waveform:") & Log insiden
  /// ('vis-jaga-ulang'), agar perilaku perangkat terbukti dari angka.
  int visReassertCount = 0;

  Timer? _visWatchdogTimer;

  /// Catat satu detak RMS (dipanggil cangkang per peristiwa).
  void noteRmsHeartbeat() => _lastRmsAt = DateTime.now();

  /// Nyalakan penjaga berkala: selama gerbang menyatakan Visualizer
  /// dibutuhkan dan pemain berbunyi tetapi RMS diam melewati ambang
  /// predikat [visWatchdogDue], tegaskan ulang (berhenti → mulai)
  /// lewat jalur terserialisasi yang sama. Rantai yang mati
  /// diam-diam di perangkat kini menyembuhkan dirinya dalam
  /// ±15–20 detik putar, bukan pada pemasangan build berikutnya.
  void _startVisWatchdog() {
    _visWatchdogTimer?.cancel();
    _visWatchdogTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      final now = DateTime.now();
      final due = visWatchdogDue(
        needed: _visNeeded,
        playing: _player.playing || _playerB.playing,
        msSinceLastRms: _lastRmsAt == null
            ? null
            : now.difference(_lastRmsAt!).inMilliseconds,
        msSinceLastReassert: _lastVisReassertAt == null
            ? null
            : now.difference(_lastVisReassertAt!).inMilliseconds,
      );
      if (!due) return;
      _lastVisReassertAt = now;
      visReassertCount++;
      Observability.instance.log(
        'vis-jaga-ulang',
        'RMS diam padahal gerbang butuh & pemain berbunyi — '
            'Visualizer ditegaskan ulang (ke-$visReassertCount)',
      );
      unawaited(_syncVisualizer(forceRestart: true));
    });
  }

  /// Konsumen napas berubah (dari cangkang): hitung ulang kebutuhan
  /// Visualizer. Tanpa perubahan keadaan, tidak ada kerja kanal.
  Future<void> setBreathVisWanted(bool want) async {
    if (breathVisWanted == want) return;
    breathVisWanted = want;
    await _syncVisualizer();
  }

  /// Konsumen waveform berubah (dari cangkang): pola yang sama
  /// persis dengan napas (Sisipan G-1).
  Future<void> setWaveformVisWanted(bool want) async {
    if (waveformVisWanted == want) return;
    waveformVisWanted = want;
    await _syncVisualizer();
  }

  /// Cache gain per-lagu (1.0 = netral) + override diagnostik sementara.
  final Map<TrackKey, double> _gainCache = {};
  double? _probeGain;
  TrackKey? _probeKey;

  /// Volume yang sedang diterapkan pemain aktif (diagnostik & bukti uji).
  double get appliedVolume => _activePlayer.volume;

  /// Jeda transisi gapless terakhir (ms) — null bila belum pernah terukur.
  int? lastTransitionGapMs;
  DateTime? _completedAt;

  /// Faktor gain murni untuk [t] (tanpa master): 1.0 bila normalisasi mati.
  double _gainFactor(Track? t) {
    if (!normalizationOn || t == null) return 1.0;
    if (_probeKey == t.key && _probeGain != null) return _probeGain!;
    return _gainCache[t.key] ?? 1.0;
  }

  /// D-33: gerakkan _masterVolume ke [to] lewat rampa 300 ms (10 langkah ×
  /// 30 ms) — bukan lompatan seketika. Saat ramp crossfade berjalan, volume
  /// dikelola ramp itu sendiri: tetapkan langsung seperti perilaku lama.
  void _rampMasterVolume({required double to}) {
    _duckRampTimer?.cancel();
    if (_xfRamping) {
      _masterVolume = to;
      return;
    }
    final from = _masterVolume;
    if (from == to) return;
    var step = 0;
    _duckRampTimer = Timer.periodic(const Duration(milliseconds: 30), (t) {
      step++;
      _masterVolume = from + (to - from) * (step / 10);
      if (step >= 10) {
        _masterVolume = to;
        t.cancel();
      }
      if (!_xfRamping) unawaited(_applyVolume());
    });
  }

  /// Volume efektif untuk [t]: master × gain (bila normalisasi menyala).
  double _volumeFor(Track? t) =>
      (_masterVolume * _sleepFade * _drivingVolume * _gainFactor(t)).clamp(
        0.0,
        1.0,
      );
  Future<void> _applyVolume() async {
    final cur = engine.current;
    final v = _volumeFor(cur);
    await _activePlayer.setVolume(v);
    if (_xfMode) await _idlePlayer.setVolume(0);
  }

  /// Muat gain trek dari DB ke cache (netral bila belum tercatat).
  Future<double> _gainFor(Track t) async {
    final cached = _gainCache[t.key];
    if (cached != null) return cached;
    final g = await db.trackGain(t.key) ?? 1.0;
    _gainCache[t.key] = g;
    return g;
  }

  /// Probe diagnostik: paksa gain trek berjalan sementara (TIDAK disimpan) —
  /// dipakai layar Diagnostik Putar untuk membuktikan tahap gain bekerja.
  Future<void> probeNormalizationGain(double gain) async {
    final cur = engine.current;
    if (cur == null) return;
    _probeKey = cur.key;
    _probeGain = gain.clamp(0.0, 2.0);
    await _applyVolume();
  }

  void clearNormalizationProbe() {
    _probeKey = null;
    _probeGain = null;
  }

  /// Ganti mode transisi (ADR-002). Mengembalikan true bila berlaku mulai
  /// lagu berikutnya (ada lagu berjalan), false bila berlaku seketika.
  Future<bool> setTransitionMode(String mode) async {
    if (mode != 'gapless' && mode != 'crossfade') return false;
    await db.setPref('playback.transition', mode);
    if (engine.current == null || !_activePlayer.playing) {
      transitionMode = mode;
      pendingTransitionMode = null;
      return false;
    }
    if (mode == transitionMode) {
      pendingTransitionMode = null;
      return false;
    }
    pendingTransitionMode = mode;
    return true;
  }

  /// Durasi crossfade (detik, 1–12) — berlaku mulai transisi berikutnya.
  Future<void> setCrossfadeSecs(double secs) async {
    crossfadeSecs = secs.clamp(1, 12);
    await db.setPref('playback.crossfadeSecs', crossfadeSecs);
  }

  Future<void> setNormalization(bool on) async {
    normalizationOn = on;
    await db.setPref('playback.normalization', on);
    await _applyVolume();
    // Visualizer mengikuti GERBANG KONSUMEN (bukan sakelar ini saja):
    // mati di sini tidak memadamkannya bila napas masih membutuhkannya,
    // dan menyala di sini tidak perlu tahu siapa lagi yang memakai.
    await _syncVisualizer();
  }

  /// Gain hasil ukur Visualizer untuk [key] (dipakai mulai putaran berikutnya).
  void noteGainMeasured(TrackKey key, double gain) {
    _gainCache[key] = gain;
  }

  /// ID sesi audio kedua pemain (null bila belum pernah berbunyi).
  List<int?> get audioSessionIds => [
    _player.androidAudioSessionId,
    _playerB.androidAudioSessionId,
  ];

  /// ID sesi pemain yang SEDANG berbunyi (untuk atribusi peristiwa RMS
  /// per sesi — peristiwa Visualizer membawa sessionId-nya sendiri).
  int? get activeAudioSessionId => _activePlayer.androidAudioSessionId;

  /// Kunci trek yang benar-benar dimuat pemain berbunyi pada indeks
  /// berjalannya — "trek berbunyi" versi PEMAIN, pembanding jujur bagi
  /// engine.current versi antrean (Ronde Perbaikan Waveform Perangkat:
  /// atribusi umpan RMS harus bisa dibuktikan sama/berbeda dari layar
  /// Diagnostik). Jalur gapless: indeks sumber gabungan → [_sourceTracks].
  /// Jalur crossfade: pemain aktif memegang trek pada [_currentFullIndex].
  TrackKey? get soundingKey {
    if (_xfMode) {
      final q = engine.fullQueue;
      if (_currentFullIndex < 0 || _currentFullIndex >= q.length) return null;
      return q[_currentFullIndex].key;
    }
    final idx = _activePlayer.currentIndex;
    if (idx == null || idx < 0 || idx >= _sourceTracks.length) return null;
    return _sourceTracks[idx].key;
  }

  /// Terapkan setelan EQ tersimpan ke satu sesi (dipanggil saat sesi baru muncul).
  Future<void> _applyEqToSession(int sessionId) async {
    final enabled = await db.pref<bool>('audiofx.enabled') ?? false;
    if (!enabled) return;
    final preset = await db.pref<int>('audiofx.preset') ?? -1;
    final bandsRaw = await db.pref<List>('audiofx.bands');
    final bands = bandsRaw == null
        ? <int>[]
        : bandsRaw.map((e) => (e as num).toInt()).toList();
    final ok = await _fx.eqApply(
      sessionId: sessionId,
      enabled: true,
      preset: preset,
      bandLevels: bands,
    );
    if (!ok) {
      // Dulu kegagalan ini senyap total (F2 Batch 2.1): kini tercatat agar
      // "EQ tidak jalan" di perangkat nyata punya bukti, bukan tebakan.
      Observability.instance.log(
        'eq-terapkan-gagal',
        'sesi $sessionId — Equalizer menolak dibuat/diterapkan pada sesi pemain.',
      );
    }
  }

  /// Pelacak sesi per pemain untuk higiene efek (Ronde Kresek): memutuskan
  /// sesi lama mana yang efeknya harus dilepas saat session-id berganti.
  final _fxTracker = SessionFxTracker();

  final _sessionAppearances = StreamController<int>.broadcast();

  /// Sesi audio pemain yang baru muncul (untuk UI yang menunggu sesi,
  /// mis. seksi EQ di Pengaturan).
  Stream<int> get audioSessionAppearances => _sessionAppearances.stream;
  final QueueEngine engine = QueueEngine();

  StreamQuality quality = StreamQuality.normal;
  bool autoResume = true;

  // ---------- Sapuan Kepatuhan pra-1.0.0 ----------
  /// D-03: mode hemat data (PRD 5.13). Saat aktif, kualitas EFEKTIF selalu
  /// Rendah — apa pun pilihan pengguna — dan pilihan Tinggi dicegah di
  /// jaringan seluler (penjaga di Pengaturan + kualitas efektif di sini).
  bool dataSaverOn = false;

  /// Jenis jaringan terakhir yang diketahui ('wifi'|'mobile'|…) untuk
  /// keputusan hemat data; diperbarui malas lewat SysChannel.
  String _networkKind = 'unknown';
  String get networkKind => _networkKind;
  Future<void> refreshNetworkKind() async {
    _networkKind = await SysChannel.networkType();
  }

  /// Kualitas yang benar-benar dipakai resolusi aliran.
  StreamQuality get effectiveQuality =>
      dataSaverOn ? StreamQuality.low : quality;

  /// D-33: perilaku saat fokus audio menyusut sebagian (duck). 'duck' =
  /// volume diturunkan (bawaan); 'pause' = jeda penuh dengan hak lanjut
  /// otomatis, seperti interupsi tipe jeda. Setelan PRD 5.13.
  bool duckLowersVolume = true;
  Timer? _duckRampTimer;

  /// D-32: keadaan suka trek berjalan untuk kontrol notifikasi + kait
  /// sakelarnya (dipasang app dari LibraryController).
  bool notificationLiked = false;
  VoidCallback? onToggleLikeRequest;
  void setNotificationLiked(bool liked) {
    if (notificationLiked == liked) return;
    notificationLiked = liked;
    final e = _lastPlaybackEvent;
    if (e != null) playbackState.add(_transformState(e, _activePlayer));
  }

  /// Bitrate aliran trek berjalan yang terakhir teresolusi (untuk label
  /// jujur D-18 di Player); null bila belum diketahui (file lokal dsb.).
  final Map<TrackKey, int> _resolvedBitrates = {};

  /// Asal resolusi terakhir per trek (Tahap 3): true = jalur DIRECT-1 —
  /// dasar keputusan memanggil [directRejectedHook] pada galat putar.
  final Map<TrackKey, bool> _resolvedDirect = {};
  int? get currentBitrate {
    final cur = engine.current;
    return cur == null ? null : _resolvedBitrates[cur.key];
  }

  /// B-01: cap waktu niat putar pengguna (ketuk) untuk sampel ketuk→bunyi.
  DateTime? _playIntentAt;
  PlaybackEvent? _lastPlaybackEvent;

  /// Keadaan `playing` terakhir yang tercatat instrumentasi regresi
  /// interupsi (untuk mencatat hanya flip-nya, bukan setiap emisi).
  bool? _lastPlayingLogged;

  /// D-09: pengawas posisi macet + timernya.
  final StallWatchdog _stallWatchdog = StallWatchdog();
  Timer? _stallTimer;

  /// Pengawas koherensi sesi (Ronde Bug Notifikasi): niat putar tanpa
  /// sumber / idle macet — diberi makan dari detak 1 detik yang sama.
  final SessionCoherenceWatchdog _coherence = SessionCoherenceWatchdog();

  /// Hak lanjut-otomatis pasca-interupsi (matriks interupsi 2.2; laporan
  /// riyan 2026-10-24): hanya lahir bila interupsi sistem menjeda putaran
  /// yang SEDANG berbunyi. Jeda manual pengguna bersifat lengket dan
  /// membatalkan hak ini — lihat pause() dan interruption_policy.dart.
  bool _resumeAfterInterruption = false;
  DateTime? _interruptionPausedAt;

  // ---------- F2 Batch 2: unduhan & mode offline ----------
  /// Kunci → path berkas unduhan (diisi DownloadService lewat bootstrap).
  Map<TrackKey, String> downloadedPaths = {};

  /// Mode offline: hanya unduhan & file lokal yang boleh diputar/diantrekan.
  bool offlineMode = false;

  /// Sumber trek terunduh untuk isi ulang offline (diisi DownloadService).
  Future<List<Track>> Function()? offlineRefillSource;

  /// Dapat diputar tanpa jaringan: file lokal perangkat atau sudah terunduh.
  bool isOfflinePlayable(Track t) =>
      t.providerId == 'local' || downloadedPaths.containsKey(t.key);

  /// Kunci yang bisa diputar offline di seluruh sesi berjalan (dipakai filter).
  Set<TrackKey> get _offlinePlayableKeys {
    final out = downloadedPaths.keys.toSet();
    for (final t in engine.fullQueue) {
      if (t.providerId == 'local') out.add(t.key);
    }
    return out;
  }

  /// Menyalakan/mematikan mode offline. Menyalakan = menyaring antrean berjalan
  /// (lagu yang sedang berbunyi tidak dipotong); mematikan = antrean kembali
  /// menerima lagu streaming pada konteks berikutnya.
  Future<void> setOfflineMode(bool on) async {
    offlineMode = on;
    await db.setPref('offline.enabled', on);
    if (on) {
      final removed = engine.retainOffline(_offlinePlayableKeys);
      await _syncTailAfterMutation('saring offline');
      _emitQueue();
      if (removed > 0) {
        notices.add(l10n.noticeOfflineHidden(removed));
      }
    } else {
      _emitQueue();
    }
  }

  /// Isi ulang Putar Otomatis saat offline (L-11): HANYA dari trek terunduh,
  /// artis benih dulu, sisanya apa saja — dan SELALU berlabel terbatas di UI
  /// (QueueScreen membaca handler.offlineMode). Tidak pernah menyentuh jaringan.
  Future<void> _offlineRefill() async {
    final source = offlineRefillSource;
    if (source == null) return;
    final downloaded = await source();
    final queued = engine.fullQueue.map((t) => t.key).toSet();
    // Temuan vonis 2008 #4 berlaku juga di jalur offline: riwayat sesi
    // dikecualikan lebih dulu; pelonggaran hanya bila kolam unduhan habis.
    final playedKeys = engine.played.map((t) => t.key).toSet();
    var pool = downloaded
        .where(
          (t) =>
              !queued.contains(t.key) &&
              !engine.skippedKeys.contains(t.key) &&
              !playedKeys.contains(t.key),
        )
        .toList();
    if (pool.isEmpty && playedKeys.isNotEmpty) {
      pool = downloaded
          .where(
            (t) =>
                !queued.contains(t.key) && !engine.skippedKeys.contains(t.key),
          )
          .toList();
      if (pool.isNotEmpty) {
        Observability.instance.log(
          'autoplay-isi-ulang',
          'offline: PELONGGARAN riwayat (kolam unduhan habis)',
        );
      }
    }
    final seedArtist = engine.seeds.isEmpty
        ? null
        : engine.seeds.first.artistNames
              .split(RegExp(r'[,&]'))
              .first
              .trim()
              .toLowerCase();
    pool.sort((a, b) {
      final aSame =
          seedArtist != null &&
          a.artistNames.toLowerCase().contains(seedArtist);
      final bSame =
          seedArtist != null &&
          b.artistNames.toLowerCase().contains(seedArtist);
      return (bSame ? 1 : 0).compareTo(aSame ? 1 : 0);
    });
    final batch = pool.take(15).toList();
    if (batch.isNotEmpty) {
      engine.appendAutoplay(batch);
      await _extendSourceToQueue();
      if (!_xfMode &&
          _activePlayer.processingState == ProcessingState.completed &&
          engine.autoplayActive &&
          engine.effectiveQueue.isNotEmpty) {
        await _advanceIntoContinuation();
      }
    } else {
      engine.autoplayRefillFailed = true;
    }
    _emitQueue();
  }

  /// D-03: sakelar mode hemat data — kualitas efektif berubah seketika
  /// untuk resolusi berikutnya; trek berjalan tidak dipotong.
  Future<void> setDataSaver(bool on) async {
    dataSaverOn = on;
    await db.setPref('playback.dataSaver', on);
    if (on) unawaited(refreshNetworkKind());
  }

  /// D-08 (PRD 5.4): refresh URL proaktif — untuk hingga 2 trek terdepan
  /// sesudah trek berjalan, bila URL tercache-nya tersisa <30 menit,
  /// segarkan di latar (buang entri + resolusi ulang ke cache) agar
  /// perpindahan tidak membayar resolusi di titik putar.
  Future<void> _proactiveRefresh() async {
    if (offlineMode || _xfMode) return;
    final upcoming = engine.effectiveQueue.take(2).toList();
    for (final t in upcoming) {
      if (t.providerId == 'local' || downloadedPaths.containsKey(t.key))
        continue;
      try {
        final remaining = await db.streamCacheRemaining(t.key);
        if (!shouldProactivelyRefresh(remaining)) continue;
        await db.clearStreamCacheFor(t.key);
        await provider.resolveStream(t, effectiveQuality);
        Observability.instance.log(
          'refresh-proaktif',
          '"${t.title}": URL disegarkan di latar (sisa ${remaining?.inMinutes} mnt)',
        );
      } catch (e) {
        // Gagal segar di latar BUKAN insiden keras: jalur reaktif L-10 tetap
        // menjadi jaring pengaman saat trek itu benar-benar diputar.
        Observability.instance.log(
          'refresh-proaktif-gagal',
          '"${t.title}": $e',
        );
      }
    }
  }

  /// D-15: pulihkan sesi Lanjut Besok dari snapshot antrean PENUH
  /// (konteks + antrean + riwayat + posisi), lalu putar. Pasangan simpan
  /// ada di app.dart (kait SleepService.onFire).
  Future<void> restoreSleepSession(Map<String, Object?> snap) async {
    final keys = collectSnapshotKeys(snap);
    if (keys.isEmpty) return;
    final tracks = await db.tracksByKeys(keys.toList());
    final byKey = {for (final t in tracks) t.key: t};
    final prev = engine.current;
    if (prev != null) _closeTrackEvent(prev, completed: false);
    engine.restore(snap, byKey);
    // D-07 berlaku juga di sini: pref global menimpa snapshot.
    final autoplayPref = await db.pref<bool>('playback.autoplay');
    if (autoplayPref != null) {
      engine.autoplayEnabled = autoplayPref;
      if (!autoplayPref) engine.clearAutoplay();
    }
    // Butir D: terbitkan mode acak hasil pulih sekarang juga (pemutaran
    // yang menyusul memang menerbitkan lewat peristiwa pemain, tetapi
    // Player bisa dibuka sebelum peristiwa pertama tiba).
    syncShuffleState();
    final savedPosMs = (snap['positionMs'] as num?)?.toInt() ?? 0;
    if (savedPosMs > 0) {
      _pendingRestoreSeek = Duration(milliseconds: savedPosMs);
      _lastPosition = _pendingRestoreSeek!;
    }
    if (engine.current == null) return;
    mediaItem.add(_toMediaItem(engine.current!));
    _emitQueue();
    final gen = ++_playGen;
    if (_xfMode) {
      await _xfPlayCurrent(engine.current!, gen: gen);
    } else {
      await _buildOrNotify(
        fromFullIndex: 0,
        autoplay: true,
        what: '"${engine.current!.title}"',
        gen: gen,
        firstOnly: true,
      );
      if (gen != _playGen) return;
      final seek = _pendingRestoreSeek;
      if (seek != null && seek > Duration.zero) {
        try {
          await _player.seek(seek);
        } catch (_) {}
      }
      _pendingRestoreSeek = null;
      unawaited(_extendSourceToQueue());
    }
    _trackStartedAt = DateTime.now();
    _emitQueue();
    unawaited(_maybeRefill());
  }

  /// Sinkronkan mode acak engine ke playbackState terbit (Ronde Putusan
  /// Desain butir D — temuan vonis pemilik atas build 2009): baris kontrol
  /// Player membaca engine.shuffle LEWAT StreamBuilder playbackState,
  /// yang hanya membangun ulang saat peristiwa playbackState BARU tiba.
  /// Jalur yang menetapkan engine.shuffle tanpa peristiwa pemain —
  /// setSmartShuffle (sakelar Antrian/Pengaturan), pemulihan sesi &
  /// Lanjut Besok, pref boot di bootstrap — WAJIB memanggil ini; kalau
  /// tidak, ikon acak Player yang sedang terbuka basi sampai Player
  /// ditutup/dibuka atau lagu berganti. (Arah sebaliknya terasa seketika
  /// karena setShuffleMode memang menerbitkan status.) Murni sinkronisasi
  /// status terbit — perilaku mode tidak berubah sama sekali.
  void syncShuffleState() {
    playbackState.add(
      playbackState.value.copyWith(
        shuffleMode: audioServiceShuffleMode(engine.shuffle),
      ),
    );
  }

  /// Smart Shuffle (F2): sakelar mode — menyalakan langsung mengurut ulang
  /// Lanjutan berjalan; mematikan mengembalikan mode acak ke mati (bukan ke pure).
  Future<void> setSmartShuffle(bool on) async {
    engine.setSmartSignals(
      likedKeys: await db.likedKeys(),
      playCounts: await db.playCounts(),
    );
    if (on) {
      engine.shuffle = ShuffleMode.smart;
      engine.applySmartShuffle();
    } else if (engine.shuffle == ShuffleMode.smart) {
      engine.shuffle = ShuffleMode.off;
    }
    await db.setPref('playback.smartShuffle', on);
    syncShuffleState();
    _emitQueue();
  }

  ConcatenatingAudioSource? _source;
  List<Track> _sourceTracks =
      []; // trek yang saat ini termuat di _source (jendela)
  // (dulu: _windowStart — dihapus v4.3; pemetaan indeks kini lewat kunci trek
  // potret jendela karena fullQueue bergeser saat seksi terkonsumsi.)

  int _consecutiveFailures = 0;
  final Map<String, int> _urlAttempts = {};
  final Map<String, int> _ladderAdvances = {};

  /// Tangga strategi muat (v4.2): URI adaptif+header → URI muxed+header → proxy.
  /// Pemenang lengket per sesi; kegagalan setAudioSource/per-trek menaikkan tangga.
  late final LoadLadder _ladder = LoadLadder(
    resolveAdaptive: (t, {stillWanted}) async {
      final info = await provider.resolveStream(t, effectiveQuality,
          stillWanted: stillWanted);
      if (info.bitrate != null) _resolvedBitrates[t.key] = info.bitrate!;
      _resolvedDirect[t.key] = info.viaDirectPath;
      return info;
    },
    resolveMuxed: (t) => provider.resolveMuxedFallback(t),
    tagFor: _toMediaItem,
    isLocal: (t) => t.providerId == 'local',
    // F2 Batch 2: trek terunduh diputar dari berkas lokalnya (juga saat offline).
    localFileFor: (t) => downloadedPaths[t.key],
    // Tahap 3: penolakan URL adaptif oleh edge dilaporkan ke resolver
    // (kabel dipasang bootstrap ke layanan DIRECT-1).
    onAdaptiveRejected: (t) => directRejectedHook?.call(t),
  );

  /// Kabel pemulihan DIRECT-1 (Tahap 3, dipasang bootstrap): dipanggil
  /// saat URL DIRECT sebuah trek ditolak edge — dari anak proxy tangga
  /// (sesudah coba-ulang jendelanya) dan dari jalur galat putar di bawah
  /// untuk anak URI (percobaan segar ≤2). Resolver menyegarkan sesi
  /// minter satu kali / mengecualikan trek dari laporan ini.
  void Function(Track track)? directRejectedHook;

  /// Tahap 3: resolver DIRECT terbukti pulih sesudah penolakan —
  /// kembalikan pemenang lengket tangga ke anak adaptif.
  void resetLadderToAdaptive() => _ladder.resetSticky();
  DateTime _trackStartedAt = DateTime.now();
  Duration _lastPosition = Duration.zero;

  /// Penanda D-06: sumber trek berjalan SUDAH dibangun pada proses ini —
  /// membedakan "sesi dipulihkan dari penyimpanan" (sumber memang belum ada)
  /// dari keadaan xf sesaat; play() redundan di tengah putar tidak boleh
  /// membangun ulang trek dari posisi 0.
  bool _sourceBuiltThisProcess = false;

  /// D-06 (audit kepatuhan, L-16): posisi tersimpan sesi yang dipulihkan —
  /// diterapkan sebagai posisi awal saat sumber trek pulih pertama dibangun,
  /// lalu dibersihkan. Selama tertunda, emisi posisi nol dari pemutar yang
  /// belum bersumber TIDAK boleh menimpa _lastPosition (lihat listener).
  Duration? _pendingRestoreSeek;
  Timer? _saveTimer;
  Timer? _refillRetryTimer;
  Timer? _watchdogTimer;
  bool _refilling = false;
  bool _refillPending = false;
  bool _advancingFromCompleted = false;
  bool _advanceVerifyPending = false;
  Future<void> _chain = Future.value();

  /// Ronde 8063: penanda lompatan yang DIPERINTAH skipToNext (manual
  /// atau lewati-galat) — kunci trek tujuan + cap waktunya.
  /// _onIndexChanged menutup trek lama dengan completed:true untuk
  /// SEMUA perpindahan indeks maju, karena selesai alami dan
  /// seekToNext perintah terlihat sama baginya; tanpa penanda ini,
  /// kait akhir alami ikut menembak pada skip manual dan timer tidur
  /// mode akhir-lagu terbakar padahal lagu hanya dilompati.
  TrackKey? _skipTargetKey;
  DateTime? _skipTargetAt;

  /// Token generasi perintah putar (cacat v4.4 — ketukan menumpuk): setiap
  /// perintah putar baru (playTracks/startRadio/jumpTo) menaikkan generasi.
  /// Pembangunan sumber dari generasi lama GUGUR di titik komit (sebelum
  /// setAudioSource & sebelum play) — ketukan cepat berakhir di ketukan
  /// terakhir tanpa antrean resolusi usang yang memutar lagu satu-satu.
  int _playGen = 0;

  /// Jalur putar "yang terbaru menang": perintah putar TIDAK mengantre di
  /// _serial (di sanalah ketukan menumpuk — tiap ketuk menunggu pembangunan
  /// sumber ketuk sebelumnya selesai penuh). Operasi antrean non-putar tetap
  /// di _serial. Galat dicatat, tidak dilempar ke pemanggil (kontrak lama).
  Future<void> _runPlay(Future<void> Function() op) async {
    try {
      await op();
    } catch (e, st) {
      if (isInterruptionError(e)) return;
      Observability.instance.log('perintah-putar-gagal', describeError(e, st));
    }
  }

  // ---------- kait F2 (dipasang bootstrap; semua opsional & gagal-aman) ----------
  /// Dipanggil saat satu trek selesai didengar (selesai alami / dilewati /
  /// diganti) beserta milidetik yang benar-benar didengar — bahan scrobble.
  void Function(Track track, int listenedMs, bool completed)? onListenFinished;

  /// Dipanggil saat trek BARU mulai (berdasarkan emisi mediaItem; dedupe per kunci).
  /// Kait trek-baru-mulai (F2): DAFTAR listener — bootstrap (ListenBrainz)
  /// & app (pengumuman berkendara) sama-sama menempel tanpa saling menimpa.
  final List<void Function(Track track)> trackStartedListeners = [];

  /// Pengaya sampul: kembalikan URL sampul cadangan untuk trek yang sampul
  /// utamanya kosong, atau null. Hasilnya ditempel lewat refreshCurrentArtwork.
  Future<String?> Function(Track track)? artworkEnricher;

  /// Tempel sampul pengayaan ke trek di mana pun ia muncul di antrean + DB,
  /// dan segarkan mediaItem bila ia yang sedang berjalan.
  Future<void> refreshCurrentArtwork(Track t, String url) async {
    if (!engine.noteArtwork(t.key, url)) return;
    final cur = engine.current;
    if (cur != null && cur.key == t.key) mediaItem.add(_toMediaItem(cur));
    unawaited(db.cacheTracks([t.copyWith(artworkUrl: url)]));
    _emitQueue();
  }

  /// Tempel hasil penyembuhan metadata (artis/sampul) ke trek di mana pun ia
  /// muncul di antrean + DB, dan segarkan mediaItem bila ia yang berjalan —
  /// pasangan umum dari [refreshCurrentArtwork] untuk lapisan penyembuhan.
  Future<void> refreshTrackMetadata(Track healed) async {
    if (!engine.noteMetadata(healed)) return;
    final cur = engine.current;
    if (cur != null && cur.key == healed.key) {
      mediaItem.add(_toMediaItem(cur));
    }
    unawaited(db.cacheTracks([healed]));
    _emitQueue();
  }

  /// Pemberitahuan jujur ke UI (snackbar): lagu dilewati, sumber terdegradasi, dsb.
  final StreamController<String> notices = StreamController<String>.broadcast();

  /// Berdenyut setiap antrean berubah (versi engine) untuk UI.
  final StreamController<QueueEngine> queueChanges =
      StreamController<QueueEngine>.broadcast();
  Stream<QueueEngine> get queueStream => queueChanges.stream;

  // Akses baca untuk UI (player tetap privat — L-01). Aliran digabung dari
  // kedua pemain: hanya pemain AKTIF yang diteruskan — saat crossfade
  // bertukar pemain, posisi/durasi/state mengikuti tanpa putus.
  final StreamController<Duration> _positionMerged =
      StreamController<Duration>.broadcast();
  final StreamController<Duration?> _durationMerged =
      StreamController<Duration?>.broadcast();
  final StreamController<PlayerState> _playerStateMerged =
      StreamController<PlayerState>.broadcast();
  Stream<Duration> get positionStream => _positionMerged.stream;
  Stream<Duration?> get durationStream => _durationMerged.stream;
  Stream<PlayerState> get playerStateStream => _playerStateMerged.stream;
  bool get isPlaying => _activePlayer.playing;
  Duration get position => _activePlayer.position;

  /// Menyisipkan kembali trek (untuk Urungkan penghapusan antrean, Phase 2 F-03).
  Future<void> insertInQueue(String section, int index, Track t) {
    return _serial(() async {
      if (section == 'manual')
        engine.manual.insert(index.clamp(0, engine.manual.length), t);
      if (section == 'continuation')
        engine.continuation.insert(
          index.clamp(0, engine.continuation.length),
          t,
        );
      if (section == 'autoplay')
        engine.autoplay.insert(index.clamp(0, engine.autoplay.length), t);
      await _syncTailAfterMutation('urungkan hapus antrean', growTailBy: 1);
      _emitQueue();
    });
  }

  ClaiAudioHandler({
    required this.db,
    required this.provider,
    required this.similaritySource,
  }) {
    _init();
  }

  Future<T> _serial<T>(Future<T> Function() op) {
    final run = _chain.then((_) => op());
    _chain = run.then((_) {}, onError: (_) {});
    return run;
  }

  void _emitQueue() {
    queue.add(_mediaQueue());
    queueChanges.add(engine);
    _scheduleSave();
  }

  List<MediaItem> _mediaQueue() => engine.fullQueue.map(_toMediaItem).toList();

  MediaItem _toMediaItem(Track t) => MediaItem(
    id: '${t.providerId}|${t.id}',
    // Lapisan tampil sistem (mini player, Player, notifikasi media,
    // layar kunci) memakai teks bersih yang sama dengan baris lagu:
    // judul tanpa awalan kurung unggahan, artis tanpa metadata
    // tontonan (butir 3 poles, diperluas ke permukaan MediaItem
    // sesudah temuan emulator: mini player menampilkan
    // "… • 625M plays" mentah). Data trek tidak berubah.
    title: cleanDisplayTitle(t.title),
    artist: cleanDisplayArtist(t.artistNames),
    album: t.albumTitle,
    duration: t.duration,
    // v4.4: artUri sistem (notifikasi/layar kunci) cukup varian 544 —
    // permukaan tampil menulis ulang ukurannya sendiri dari URL ini.
    artUri: t.artworkUrl == null
        ? null
        : Uri.tryParse(artworkUrlForSize(t.artworkUrl, 544) ?? t.artworkUrl!),
    extras: {'providerId': t.providerId},
  );

  /// Terapkan setelan perilaku fokus (PRD 5.13) secara utuh: bendera
  /// kebijakan handler + konfigurasi sesi. Konfigurasi sesi menentukan
  /// apakah framework mengirim peristiwa CAN_DUCK sama sekali (lihat
  /// [willPauseWhenDuckedForFocusBehavior]). Permintaan fokus natif
  /// tersimpan selama dipegang: bila tidak ada yang berbunyi, fokus
  /// dilepas agar permintaan berikutnya dibangun dengan bendera baru;
  /// bila sedang berbunyi, bendera baru berlaku mulai pembangunan
  /// permintaan fokus berikutnya. Dipakai jalur Pengaturan; saat boot,
  /// [_init] membaca pref yang sama dan bootstrap menetapkan bidangnya.
  Future<void> applyFocusBehavior({required bool lowersVolume}) async {
    duckLowersVolume = lowersVolume;
    final session = await AudioSession.instance;
    await session.configure(
      AudioSessionConfiguration.music().copyWith(
        androidWillPauseWhenDucked: !lowersVolume,
      ),
    );
    if (!_player.playing && !_playerB.playing) {
      await session.setActive(false);
    }
  }

  Future<void> _init() async {
    final session = await AudioSession.instance;
    // Regresi interupsi (build 2012): konfigurasi sesi WAJIB menyatakan
    // willPauseWhenDucked mengikuti setelan perilaku fokus — tanpa
    // bendera itu framework tidak pernah mengirim peristiwa CAN_DUCK
    // (lihat willPauseWhenDuckedForFocusBehavior). AudioSessionConfiguration
    // .music() tidak memasangnya (null), jadi dipasang eksplisit di sini.
    final focusBehavior = await db.pref<String>('playback.focusBehavior');
    await session.configure(
      AudioSessionConfiguration.music().copyWith(
        androidWillPauseWhenDucked:
            willPauseWhenDuckedForFocusBehavior(focusBehavior),
      ),
    );
    session.interruptionEventStream.listen((e) {
      // Instrumentasi regresi interupsi (ronde 2012): SETIAP peristiwa yang
      // SAMPAI ke pendengar tercatat — ketiadaan entri ini saat fokus direbut
      // adalah bukti peristiwa tidak terkirim, bukan logika yang salah.
      Observability.instance.log(
        'interupsi',
        'begin=${e.begin} tipe=${e.type.name} '
            'setelan=${duckLowersVolume ? 'duck' : 'jeda'} '
            'playing=${_activePlayer.playing}',
      );
      if (e.begin) {
        switch (e.type) {
          case AudioInterruptionType.duck:
            // D-33: perilaku fokus adalah SETELAN (PRD 5.13) — 'pause'
            // memperlakukan duck persis seperti interupsi tipe jeda
            // (hak lanjut otomatis lahir hanya bila sedang berbunyi).
            if (!duckLowersVolume) {
              if (_activePlayer.playing) {
                _resumeAfterInterruption = true;
                _interruptionPausedAt = DateTime.now();
                unawaited(_pauseFromSystem());
              }
              break;
            }
            _duckRampTimer?.cancel();
            _masterVolume = 0.35;
            if (!_xfRamping) _applyVolume();
            break;
          case AudioInterruptionType.pause:
          case AudioInterruptionType.unknown:
            // Hak lanjut-otomatis HANYA lahir di sini: interupsi menjeda
            // putaran yang sedang berbunyi. Sudah jeda sebelumnya (manual
            // atau apa pun) → tidak ada hak, dan pelepasan fokus nanti
            // tidak boleh menghidupkan putar (cacat laporan riyan
            // 2026-10-24: jeda manual lalu buka/tutup aplikasi lain
            // membuat Clai berbunyi lagi).
            if (_activePlayer.playing) {
              _resumeAfterInterruption = true;
              _interruptionPausedAt = DateTime.now();
              unawaited(_pauseFromSystem());
            }
            break;
        }
      } else {
        switch (e.type) {
          case AudioInterruptionType.duck:
            if (!duckLowersVolume) {
              // Pasangan cabang 'pause' di bawah: konsumsi hak lanjut.
              final granted = _resumeAfterInterruption;
              final pausedAt = _interruptionPausedAt;
              _resumeAfterInterruption = false;
              _interruptionPausedAt = null;
              if (mayAutoResume(
                granted: granted,
                settingEnabled: autoResume,
                pausedAt: pausedAt,
                now: DateTime.now(),
              )) {
                unawaited(play());
              }
              break;
            }
            // D-33: pelepasan duck TIDAK lagi seketika — USER-FLOW §2.2
            // mewajibkan rampa ≥300 ms dari volume duck ke penuh.
            _rampMasterVolume(to: 1.0);
            break;
          case AudioInterruptionType.pause:
            // Konsumsi hak (satu kali pakai). Jeda manual yang terjadi
            // sesudah interupsi mulai sudah menghapus hak di pause().
            final granted = _resumeAfterInterruption;
            final pausedAt = _interruptionPausedAt;
            _resumeAfterInterruption = false;
            _interruptionPausedAt = null;
            if (mayAutoResume(
              granted: granted,
              settingEnabled: autoResume,
              pausedAt: pausedAt,
              now: DateTime.now(),
            )) {
              unawaited(play());
            }
            break;
          case AudioInterruptionType.unknown:
            break;
        }
      }
    });
    session.becomingNoisyEventStream.listen((_) {
      Observability.instance.log(
        'interupsi-noisy',
        'playing=${_activePlayer.playing}',
      );
      if (_activePlayer.playing) unawaited(_pauseFromSystem());
    });

    // Penjaga kesehatan Visualizer (Ronde 8050): rantai ukur yang
    // mati diam-diam di perangkat ditegaskan ulang dari sini.
    _startVisWatchdog();

    // F2 Batch 2: sesi audio baru (pemain mulai berbunyi) → terapkan EQ
    // tersimpan + mulai Visualizer bila ada konsumennya (gerbang tiga
    // konsumen: normalisasi / napas / perekam waveform — Sisipan G-1).
    // Ronde Kresek: sesi dilacak per pemain (SessionFxTracker). Bila id
    // BERGANTI, efek sesi lama WAJIB dilepas sebelum yang baru diterapkan —
    // sebelumnya Equalizer per sesi tidak pernah release() sehingga setiap
    // pergantian sesi meninggalkan instance yatim di sesi mati, dan
    // Visualizer lama tetap menempel. Kemunculan pertama + setiap
    // pergantian dicatat ke Log insiden bersama jumlah instance efek native
    // dan keadaan normalisasi/EQ, supaya perangkat nyata menghasilkan bukti
    // pembeda laju putaran sesi (di emulator id terbukti stabil lintas
    // ganti lagu; hanya berputar saat pemain dibuat ulang penuh).
    var fxSlot = 0;
    for (final p in [_player, _playerB]) {
      final slot = fxSlot++;
      p.androidAudioSessionIdStream.listen((id) async {
        if (id == null) return;
        _sessionAppearances.add(id);
        final decision = _fxTracker.onAppear(slot, id);
        final prev = decision.releasePrevious;
        Map<String, Object?>? countsBefore;
        if (prev != null) {
          countsBefore = await _fx.fxCounts();
          await _fx.eqRelease(prev);
          await _fx.visStop(prev);
        }
        await _applyEqToSession(id);
        // Visualizer lewat sinkronisasi terserialisasi yang sama
        // dengan jalur gerbang (Ronde 8050) — sesi baru otomatis
        // masuk cakupan keadaan terakhir; tidak ada lagi jalur mulai
        // terpisah yang bisa balapan meninggalkan sesi tanpa
        // Visualizer atau sebaliknya.
        await _syncVisualizer();
        if (decision.isFirst || prev != null) {
          final countsAfter = await _fx.fxCounts();
          final eqOn = await db.pref<bool>('audiofx.enabled') ?? false;
          final fxState =
              'normalisasi=${normalizationOn ? 'nyala' : 'mati'} '
              'napasVis=${breathVisWanted ? 'nyala' : 'mati'} '
              'gelombangVis=${waveformVisWanted ? 'nyala' : 'mati'} '
              'eq=${eqOn ? 'nyala' : 'mati'} fx=$countsAfter';
          if (prev != null) {
            Observability.instance.log(
              'sesi-audio-berganti',
              'pemain $slot: $prev -> $id; fxSebelum=$countsBefore; $fxState',
            );
          } else {
            Observability.instance.log(
              'sesi-audio-muncul',
              'pemain $slot: sesi $id; $fxState',
            );
          }
        }
      });
    }

    // Kait F2 di atas emisi mediaItem: trek-baru-mulai (dedupe per kunci —
    // emisi ulang mediaItem yang sama, mis. tempel durasi/sampul, tidak
    // memicu ulang) + pemicu pengayaan sampul bila trek berjalan tak bersampul.
    TrackKey? lastStartedKey;
    final enrichingKeys = <TrackKey>{};
    mediaItem.listen((item) {
      if (item == null) return;
      final parts = item.id.split('|');
      if (parts.length != 2) return;
      final key = TrackKey(parts[0], parts[1]);
      final enricher = artworkEnricher;
      if (enricher != null &&
          item.artUri == null &&
          !enrichingKeys.contains(key)) {
        final t = engine.current;
        if (t != null && t.key == key && t.artworkUrl == null) {
          enrichingKeys.add(key);
          unawaited(
            enricher(t)
                .then((url) {
                  if (url != null) return refreshCurrentArtwork(t, url);
                })
                .catchError((Object _) {})
                .whenComplete(() => enrichingKeys.remove(key)),
          );
        }
      }
      if (key == lastStartedKey) return;
      lastStartedKey = key;
      final t = engine.current;
      if (t != null && t.key == key) {
        for (final l in List.of(trackStartedListeners)) {
          try {
            l(t);
          } catch (_) {
            /* kait luar tidak menjatuhkan pemutar */
          }
        }
      }
    });

    // Kedua pemain didengar; hanya pemain AKTIF yang menggerakkan state
    // (pemain diam crossfade tidak boleh menggeser UI/state antrean).
    for (final p in [_player, _playerB]) {
      p.playbackEventStream.listen(
        (event) {
          if (p != _activePlayer) return;
          _lastPlaybackEvent = event;
          playbackState.add(_transformState(event, p));
          final idx = event.currentIndex;
          // Jalur gapless: indeks sumber gabungan menggerakkan engine.
          // Jalur crossfade: tidak ada sumber gabungan — indeks diabaikan.
          if (idx != null && !_xfMode) _onIndexChanged(idx);
          // v4.4.2 (cacat-2): akhir trek ALAMI adalah peristiwa pemicu tersendiri.
          // Sebelumnya tidak ada kait di sini sama sekali — isi ulang hanya
          // terpicu oleh perintah putar / perubahan indeks / sakelar, sehingga
          // trek tunggal yang berakhir sebelum sambungan mendarat berhenti total
          // dan hanya Next manual atau siklus sakelar yang menghidupkannya lagi.
          if (event.processingState == ProcessingState.completed) {
            _completedAt = DateTime.now();
            if (_xfMode) {
              unawaited(_xfAdvanceAfterEnd());
            } else {
              unawaited(_onPlaybackCompleted());
            }
          }
        },
        onError: (Object e) {
          if (p == _activePlayer) _onPlayerError(e);
        },
      );

      p.positionStream.listen((pos) {
        if (p != _activePlayer) return;
        // B-01: sampel ketuk→bunyi — posisi pertama yang bergerak sesudah
        // niat putar pengguna menutup sampel perintah itu.
        final intent = _playIntentAt;
        if (intent != null && pos > Duration.zero) {
          _playIntentAt = null;
          GateMetrics.instance.recordTapToSound(
            DateTime.now().difference(intent),
          );
        }
        if (p.audioSource != null) _sourceBuiltThisProcess = true;
        if (_pendingRestoreSeek == null || p.audioSource != null) {
          _lastPosition = pos;
        }
        _positionMerged.add(pos);
        _maybePullDuration(pos);
        _maybeSleepSongEndFade(pos);
      });

      p.durationStream.listen((d) {
        if (p != _activePlayer) return;
        _durationMerged.add(d);
        _onPlayerDuration(d);
      });

      p.playerStateStream.listen((st) {
        if (p != _activePlayer) return;
        // Instrumentasi regresi interupsi: garis waktu flip playing agar
        // jeda-yang-dibatalkan-pemanggil-lain terlihat apa adanya.
        if (st.playing != _lastPlayingLogged) {
          _lastPlayingLogged = st.playing;
          Observability.instance.log(
            'status-pemain',
            'playing=${st.playing} proses=${st.processingState.name}',
          );
        }
        _playerStateMerged.add(st);
      });
    }

    // D-34: simpan berkala L-16 adalah 5 detik (Blueprint) — sebelumnya
    // 15 detik, sehingga posisi sesi bisa basi hingga 15 detik saat proses
    // dibunuh paksa di antara dua simpan.
    _saveTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _scheduleSave(immediate: true),
    );
    // D-09: pengawas posisi macet — sampel 1 detik; macet >4 detik di luar
    // buffering memicu jalur pemulihan L-10 yang sama dengan galat pemutar.
    _stallTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final p = _activePlayer;
      final stalled = _stallWatchdog.feed(
        playing: p.playing,
        ready: p.processingState == ProcessingState.ready,
        positionMs: p.position.inMilliseconds,
        now: DateTime.now(),
      );
      if (stalled) {
        final cur = engine.current;
        Observability.instance.log(
          'stall-watchdog',
          '"${cur?.title}" posisi macet >4 dtk pada ${p.position.inMilliseconds} ms — pemulihan L-10',
        );
        unawaited(_onPlayerError(StateError('posisi macet (watchdog)')));
      }
      // Pengawas koherensi sesi (Ronde Bug Notifikasi): niat putar menyala
      // tetapi pemain tak bersumber / proses idle menetap = sesi zombi —
      // keadaan di balik notifikasi polos "Clai sedang berjalan". Sembuhkan
      // di tempat dan catat insiden KHUSUS ('sesi-zombi') agar kejadian
      // berikutnya meninggalkan bukti yang terbaca sebelum data dihapus.
      final fault = _coherence.feed(
        intentPlaying: p.playing,
        hasSource: p.audioSource != null,
        processingIdle: p.processingState == ProcessingState.idle,
        positionMs: p.position.inMilliseconds,
        now: DateTime.now(),
      );
      if (fault == CoherenceFault.sourcelessIntent) {
        Observability.instance.log(
          'sesi-zombi',
          'niat putar tanpa sumber >4 dtk (trek berjalan: ${engine.current?.title ?? 'null'}) — niat dimatikan agar sesi media kembali koheren',
        );
        unawaited(p.stop());
      } else if (fault == CoherenceFault.stuckIdle) {
        Observability.instance.log(
          'sesi-zombi',
          'proses idle macet >10 dtk dengan sumber terpasang ("${engine.current?.title}") — pemulihan L-10',
        );
        unawaited(
          _onPlayerError(StateError('proses idle macet (pengawas koherensi sesi)')),
        );
      }
    });
    // Pengawas isi ulang (v4.4.2): pemicu berbasis peristiwa bisa terlewat
    // dalam interleaving async yang jarang (terbukti di emulator: sesi radio
    // berjalan menit-menit tanpa satu pun isi ulang mendarat). Selama sesi
    // aktif & kelaparan, pengawas memastikan isi ulang dicoba lagi — murah
    // karena needsAutoplayRefill false begitu sambungan cukup.
    _watchdogTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (!_refilling && engine.needsAutoplayRefill) unawaited(_maybeRefill());
      unawaited(_proactiveRefresh());
    });
    await _restoreSession();
  }

  PlaybackState _transformState(PlaybackEvent e, AudioPlayer p) {
    return PlaybackState(
      controls: [
        MediaControl.skipToPrevious,
        p.playing ? MediaControl.pause : MediaControl.play,
        MediaControl.skipToNext,
        // D-32 (PRD 5.6: suka dari mana saja, termasuk notifikasi/layar
        // kunci): kontrol kustom ke-4 — ikon & label mengikuti keadaan
        // suka trek berjalan; aksinya tiba sebagai customAction('toggleLike').
        MediaControl.custom(
          androidIcon: notificationLiked
              ? 'drawable/ic_clai_heart_fill'
              : 'drawable/ic_clai_heart',
          label: notificationLiked ? l10n.notifUnlike : l10n.notifLike,
          name: 'toggleLike',
        ),
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.skipToNext,
        MediaAction.skipToPrevious,
        MediaAction.seekForward,
        MediaAction.seekBackward,
        MediaAction.custom,
      },
      androidCompactActionIndices: const [0, 1, 2],
      processingState: switch (e.processingState) {
        ProcessingState.idle => AudioProcessingState.idle,
        ProcessingState.loading => AudioProcessingState.loading,
        ProcessingState.buffering => AudioProcessingState.buffering,
        ProcessingState.ready => AudioProcessingState.ready,
        ProcessingState.completed => AudioProcessingState.completed,
      },
      playing: p.playing,
      updatePosition: p.position,
      bufferedPosition: e.bufferedPosition,
      speed: p.speed,
      queueIndex: _xfMode
          ? (_currentFullIndex < 0 ? null : _currentFullIndex)
          : (e.currentIndex == null
                ? null
                : _fullIndexOfSource(e.currentIndex!)),
      repeatMode: switch (engine.repeat) {
        RepeatMode.off => AudioServiceRepeatMode.none,
        RepeatMode.all => AudioServiceRepeatMode.all,
        RepeatMode.one => AudioServiceRepeatMode.one,
      },
      shuffleMode: audioServiceShuffleMode(engine.shuffle),
    );
  }

  // ---------------- restorasi sesi (L-16) ----------------
  Future<void> _restoreSession() async {
    try {
      // Mode offline dibaca langsung dari DB (bukan dari bootstrap) agar
      // penyaringan sesi pulih tidak berlomba dengan urutan langkah boot.
      offlineMode = await db.pref<bool>('offline.enabled') ?? false;
      final snap = await db.loadQueueSnapshot();
      if (snap == null) return;
      final keys = collectSnapshotKeys(snap);
      final tracks = await db.tracksByKeys(keys.toList());
      // File lokal tidak ada di katalog tracks (provider 'local' menyimpan metadatanya sendiri di snapshot mendatang);
      // restorasi melewati kunci yang tak ditemukan dengan aman.
      final byKey = {for (final t in tracks) t.key: t};
      engine.restore(snap, byKey);
      // D-07 (audit kepatuhan): pref global Putar Otomatis adalah sumber
      // kebenaran — snapshot bisa basi (sakelar dimatikan lalu proses mati
      // sebelum simpan berkala sempat menulis), jadi pref yang dibaca
      // handler sendiri di sini menimpa nilai snapshot SEBELUM isi-ulang
      // mana pun sempat berjalan; mati = bagian autoplay ikut dibersihkan,
      // sama seperti setAutoplayGlobal.
      final autoplayPref = await db.pref<bool>('playback.autoplay');
      if (autoplayPref != null) {
        engine.autoplayEnabled = autoplayPref;
        if (!autoplayPref) engine.clearAutoplay();
      }
      // Jatuh-bersih (Ronde Bug Notifikasi): snapshot MENYATAKAN sesi
      // (currentRef dan/atau entri seksi) tetapi tak satu pun treknya ada
      // di katalog — sesi itu tidak akan pernah bisa dipulihkan, dan
      // menyimpannya hanya membuat setiap start mengulang kehampaan yang
      // sama. Buang snapshotnya: sesi mulai bersih, insiden tercatat.
      final snapHadContent = snap['currentRef'] is String ||
          ['seeds', 'manual', 'continuation', 'autoplay'].any(
            (s) => snap[s] is List && (snap[s] as List).isNotEmpty,
          );
      if (snapHadContent &&
          engine.current == null &&
          engine.fullQueue.isEmpty) {
        Observability.instance.log(
          'restore-gagal',
          'snapshot menyatakan sesi tetapi tak satu pun treknya ditemukan di katalog — snapshot dibuang agar start berikutnya bersih',
        );
        await db.deleteQueueSnapshot();
        return;
      }
      // D-06 (audit kepatuhan, L-16): positionMs selama ini disimpan tiap
      // ±15 dtk tetapi tak pernah dibaca — sesi pulih selalu mulai 0:00.
      // Terapkan dengan pagar kewajaran: abaikan bila melewati durasi trek
      // yang diketahui atau datanya tak konsisten.
      final savedPosMs = (snap['positionMs'] as num?)?.toInt() ?? 0;
      final restoredDur = engine.current?.duration;
      if (savedPosMs > 0 &&
          (restoredDur == null || savedPosMs < restoredDur.inMilliseconds)) {
        _pendingRestoreSeek = Duration(milliseconds: savedPosMs);
        _lastPosition = _pendingRestoreSeek!;
      }
      // D-34: volume tersimpan dipulihkan (snapshot lama tanpa kolom ini
      // dibiarkan pada bawaan 1.0).
      final savedVol = (snap['volume'] as num?)?.toDouble();
      if (savedVol != null) _masterVolume = savedVol.clamp(0.0, 1.0);
      if (offlineMode) {
        // Sesi pulih di mode offline: saring sisanya (lagu berjalan dipertahankan).
        engine.retainOffline(_offlinePlayableKeys);
      }
      if (engine.current != null) {
        mediaItem.add(_toMediaItem(engine.current!));
        _emitQueue();
      }
      // Butir D: shuffle dari snapshot harus terbit ke playbackState —
      // belum ada peristiwa pemain apa pun pada titik boot ini.
      syncShuffleState();
    } catch (e) {
      Observability.instance.log('restore-gagal', e.toString());
      // Snapshot beracun (galat BENTUK DATA, bukan galat DB/IO sesaat)
      // akan gagal identik di setiap start dingin — buang agar kegagalan
      // tidak menetap sampai pemilik menghapus data aplikasi.
      if (e is FormatException || e is TypeError) {
        try {
          await db.deleteQueueSnapshot();
        } catch (_) {
          /* pembuangan gagal: insiden di atas tetap jadi bukti */
        }
      }
    }
  }

  /// Durasi dari pemutar (v4.3, diperkeras sesudah bukti emulator): emisi
  /// durationStream dikorelasikan ke INDEKS pemutar → trek jendela
  /// [_sourceTracks], BUKAN ke "trek berjalan versi engine". Bukti: trek hasil
  /// sambungan otomatis ("Days", "What You Were") tidak pernah menerima total —
  /// emisinya tiba saat engine masih menunjuk trek sebelumnya, tertempel ke trek
  /// yang salah/lolos, dan tak pernah diulang untuk trek yang benar.
  void _onPlayerDuration(Duration? d) {
    if (d != null) _attributeDuration(d);
  }

  void _attributeDuration(Duration d) {
    if (d <= Duration.zero) return;
    final idx = _activePlayer.currentIndex;
    if (idx == null || idx < 0 || idx >= _sourceTracks.length) return;
    final target = _sourceTracks[idx];
    final known = target.duration;
    if (known != null && (known - d).abs() <= const Duration(seconds: 2))
      return;
    if (engine.noteDuration(target.key, d)) {
      _sourceTracks[idx] = target.copyWith(duration: d);
      if (engine.current?.key == target.key) {
        final updated = engine.current!;
        mediaItem.add(_toMediaItem(updated));
        unawaited(db.cacheTracks([updated]));
      }
      _emitQueue();
    }
  }

  TrackKey? _durationPullKey;
  DateTime _durationPullAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// Penarikan aktif: emisi durasi bisa terlewat saat transisi — pada posisi
  /// ≥ 2 dtk, bila trek berjalan belum berdurasi, tarik langsung dari pemutar
  /// (dijeda maks sekali per 6 dtk per trek).
  void _maybePullDuration(Duration pos) {
    final cur = engine.current;
    if (cur == null || cur.duration != null || pos < const Duration(seconds: 2))
      return;
    final now = DateTime.now();
    if (_durationPullKey == cur.key &&
        now.difference(_durationPullAt) < const Duration(seconds: 6)) {
      return;
    }
    _durationPullKey = cur.key;
    _durationPullAt = now;
    final d = _activePlayer.duration;
    if (d != null) _attributeDuration(d);
  }

  void _scheduleSave({bool immediate = false}) {
    if (engine.current == null) return;
    // D-06: posisi snapshot diturunkan dari posisi LIVE pemain aktif — sumber
    // kebenaran yang sama dengan yang dilihat UI. Field _lastPosition hanya
    // cadangan bila pemain sedang tak bersumber; ia pernah terbukti dinolkan
    // jalur bangun-ulang xf sesaat sebelum simpan jeda, sehingga snapshot
    // persisten 0 dan sesi pulih selalu mulai dari 0:00.
    var posMs = _lastPosition.inMilliseconds;
    if (_activePlayer.audioSource != null) {
      final live = _activePlayer.position.inMilliseconds;
      if (live > 0) posMs = live;
    }
    final snap = engine.snapshot(positionMs: posMs);
    // D-34: volume ikut disimpan L-16 (faktor volume aplikasi — satu-satunya
    // volume milik aplikasi; volume sistem adalah milik perangkat).
    snap['volume'] = _masterVolume;
    db.saveQueueSnapshot(snap).catchError((_) => null);
  }

  // ---------------- sumber audio (jendela) ----------------
  /// Anak sumber untuk trek lanjutan jendela: dibangun pada anak tangga pemenang
  /// lengket, non-ketat (kegagalan resolusi trek itu menurun ke proxy untuknya saja).
  Future<AudioSource> _childFor(Track t) =>
      _ladder.childFor(t, _ladder.stickyRung);

  /// Jalur debug Diagnostik Putar: anak sumber PERSIS seperti yang dibangun handler
  /// untuk trek awal jendela (ketat, pada anak tangga pemenang lengket saat ini) —
  /// langkah D menguji jalur asli, bukan tiruannya.
  Future<AudioSource> debugChildSource(Track t) =>
      _ladder.childFor(t, _ladder.stickyRung, strict: true);

  /// Anak tangga yang sedang menjadi pemenang lengket (untuk laporan Diagnostik D).
  int get debugLoadRung => _ladder.stickyRung;

  /// Pembangunan sumber yang JUJUR (matriks missing-states Phase 2): kegagalan tidak lagi
  /// ditelan diam-diam oleh rantai serial — dicatat & diberitahukan ke UI lewat [notices].
  /// Mengembalikan TRUE hanya bila pembangunan terkomit; pemanggil yang akan
  /// menyalakan putar WAJIB memeriksa ini (Ronde Bug Notifikasi): setAudioSource
  /// yang gagal dapat meninggalkan sumber RUSAK tetap terpasang di pemain,
  /// jadi `audioSource == null` BUKAN bukti kegagalan yang bisa diandalkan.
  Future<bool> _buildOrNotify({
    required int fromFullIndex,
    required bool autoplay,
    required String what,
    int? gen,
    bool firstOnly = false,
  }) async {
    try {
      await _buildSource(
        fromFullIndex: fromFullIndex,
        autoplay: autoplay,
        what: what,
        gen: gen,
        firstOnly: firstOnly,
      );
      return true;
    } catch (e, st) {
      // v4.3: muat yang disela muat lebih baru = perilaku normal, BUKAN insiden.
      if (isInterruptionError(e)) return false;
      // v4.4: pembangunan yang dikalahkan ketukan lebih baru juga normal.
      if (e is _Superseded) return false;
      // Ronde 8054: resolusi dibuang dari antrean DIRECT karena sudah
      // dikalahkan — juga normal, bukan insiden, bukan pemberitahuan.
      if (e is DirectSuperseded) return false;
      // v4.1: catat rantai galat LENGKAP (kode + pesan + sebab) — log v4 hanya memuat
      // "(0) Source error" generik sehingga sebab sebenarnya tak terlihat.
      Observability.instance.log(
        'build-source-gagal',
        '$what: ${describeError(e, st)}',
      );
      // D-22: penolakan wilayah dinyatakan apa adanya, bukan "gagal menyiapkan".
      if (e is RegionUnavailableException) {
        notices.add(l10n.noticeRegionUnavailable);
      } else {
        notices.add(l10n.noticePrepareFail(what));
      }
      return false;
    }
  }

  /// Membangun ulang sumber dari [fromFullIndex] (posisi & status putar dipertahankan).
  /// v4.2: pemasangan menaiki TANGGA MUAT — anak tangga yang gugur saat setAudioSource
  /// dicatat ke log insiden ('tangga-muat-gagal') lalu tangga maju; sumber hanya gagal
  /// setelah ketiga anak gugur (galat anak terakhir dilempar ke pemanggil).
  Future<void> _buildSource({
    required int fromFullIndex,
    required bool autoplay,
    String what = 'sumber',
    int? gen,
    bool firstOnly = false,
  }) async {
    final full = engine.fullQueue;
    if (full.isEmpty) {
      _source = null;
      _sourceTracks = [];
      return;
    }
    final start = fromFullIndex.clamp(0, full.length - 1);
    // v4.4 (cacat ketukan menumpuk): perintah putar membangun jendela DUA TAHAP —
    // tahap 1 hanya trek awal (satu resolusi ketat) sehingga ketuk→bunyi cepat;
    // sisa jendela ditambahkan di latar oleh _extendSourceToQueue. Dulu seluruh
    // jendela (≤60 trek) diresolusi serial sebelum bunyi pertama.
    final end = (start + (firstOnly ? 1 : 60)).clamp(0, full.length);
    final window = full.sublist(start, end);
    await _ladder.run(
      attempt: (rung) async {
        final children = <AudioSource>[];
        for (var i = 0; i < window.length; i++) {
          // Trek awal jendela KETAT: ialah yang dimuat setAudioSource sekarang —
          // kegagalannya pada anak ini harus menggugurkan anak tangganya.
          // Ronde 8054: pembangunan bergenerasi meneruskan pemeriksaan
          // kehendaknya ke resolusi — pekerjaan yang sudah dikalahkan
          // dibuang dari antrean resolusi berseri sebelum dieksekusi,
          // bukan sesudah menghabiskan resolusi penuh.
          children.add(await _ladder.childFor(window[i], rung,
              strict: i == 0,
              stillWanted: gen == null ? null : () => gen == _playGen));
        }
        // Titik komit generasi: pembangunan usang gugur SEBELUM menyentuh pemutar.
        if (gen != null && gen != _playGen) throw const _Superseded();
        _source = ConcatenatingAudioSource(children: children);
        _sourceTracks = window;
        await _player.setAudioSource(
          _source!,
          initialIndex: 0,
          initialPosition: _pendingRestoreSeek ?? _lastPosition,
          preload: true,
        );
        _sourceBuiltThisProcess = true;
        // _pendingRestoreSeek SENGAJA tidak dibersihkan di sini: konsumen
        // (play() sesi pulih) menindaklanjuti dengan seek eksplisit lalu
        // membersihkannya — initialPosition terbukti bisa terbuang senyap
        // untuk anak sumber proxy/resolving (D-06, bukti emulator).
      },
      // Ronde 8054: galat kelas BATAL (pembangunan dikalahkan / resolusi
      // dibuang dari antrean) bukan kegagalan anak tangga — tangga tidak
      // menaiki anak berikutnya untuk pekerjaan yang sudah mati.
      isAbortError: (e) => e is _Superseded || e is DirectSuperseded,
      onRungFailed: (rung, e, st) {
        // v4.3: anak tangga yang gugur karena disela muat lain bukan kegagalan.
        if (isInterruptionError(e)) return;
        if (e is _Superseded) return;
        // Tahap 3: kegagalan anak ADAPTIF di dalam tangga tidak pernah
        // mencapai _onPlayerError (tangga maju sendiri di sini) — tanpa
        // laporan ini resolver DIRECT tak tahu URL-nya ditolak: sesi
        // minter basi tak disegarkan dan cache resolver menyajikan URL
        // tertolak yang sama berulang. Terbukti di emulator build
        // 6030/6031 (sabotase sig: putar pulih lewat muxed, tetapi
        // direct-sesi-segar tak pernah tercatat). Trek ketat jendela
        // ialah yang kegagalannya menggugurkan anak tangga ini.
        if (rung == LoadLadder.rungAdaptiveUri && window.isNotEmpty) {
          final head = window.first;
          if (_resolvedDirect[head.key] == true) {
            directRejectedHook?.call(head);
          }
        }
        Observability.instance.log(
          'tangga-muat-gagal',
          'anak ${rung + 1}/${LoadLadder.rungCount} (${LoadLadder.rungLabel(rung)}) untuk $what: ${describeError(e, st)}',
        );
      },
    );
    if (gen != null && gen != _playGen)
      return; // dikalahkan saat memasang: jangan putar
    if (autoplay) await _player.play();
  }

  /// Menyelaraskan jendela: bila indeks berjalan mendekati tepi, geser jendela tanpa menghentikan bunyi.
  Future<void> _maybeExtendWindow(int currentFullIndex) async {
    final full = engine.fullQueue;
    if (_sourceTracks.isEmpty) return;
    // Ujung jendela dalam koordinat fullQueue SAAT INI — lewat kunci trek
    // terakhir jendela, bukan aritmetika _windowStart (lihat _onIndexChanged).
    final lastIdx = engine.fullIndexOf(_sourceTracks.last.key);
    if (lastIdx < 0) return;
    final loadedEnd = lastIdx + 1;
    if (currentFullIndex >= loadedEnd - 5 && loadedEnd < full.length) {
      final more = full.sublist(
        loadedEnd,
        (loadedEnd + 30).clamp(0, full.length),
      );
      for (final t in more) {
        await _source?.add(await _childFor(t));
        _sourceTracks.add(t);
      }
    }
  }

  int get _currentFullIndex {
    final c = engine.current;
    if (c == null) return -1;
    return engine.fullQueue.indexWhere((t) => t.key == c.key);
  }

  /// Indeks fullQueue SAAT INI untuk indeks jendela pemutar (lewat kunci trek
  /// potret jendela — kekal benar walau seksi antrean terkonsumsi).
  int? _fullIndexOfSource(int sourceIndex) {
    if (sourceIndex < 0 || sourceIndex >= _sourceTracks.length) return null;
    final i = engine.fullIndexOf(_sourceTracks[sourceIndex].key);
    return i < 0 ? null : i;
  }

  void _onIndexChanged(int sourceIndex) {
    // Ukur jeda transisi gapless (F2): completed → indeks baru. Hanya sah
    // bila completed terjadi < 10 dtk lalu (lewat dari itu = peristiwa basi,
    // mis. pengguna menekan Next lama sesudah lagu selesai).
    if (_completedAt != null) {
      final gap = transitionGapMs(_completedAt, DateTime.now());
      _completedAt = null;
      if (gap != null && gap < 10000) {
        lastTransitionGapMs = gap;
        Observability.instance.log('transisi-gapless', '$gap ms');
      }
    }
    // v4.3 — AKAR CACAT UTAMA (terbukti dari log emulator dur-tarik/dur-atribusi):
    // indeks pemutar TIDAK BOLEH dipetakan lewat `_windowStart + indeks` ke
    // fullQueue yang hidup. _syncEngineTo membuang trek yang selesai dari
    // seksi-seksinya, sehingga fullQueue BERGESER di bawah jendela pemutar yang
    // tetap — sesudah ganti trek pertama, seluruh pemetaan meleset satu langkah:
    // engine menunjuk trek TETANGGA dari yang berbunyi (judul/sampul tertukar
    // satu langkah, durasi tak pernah mendarat di trek yang benar). Potret
    // jendela [_sourceTracks] tidak berubah; selaraskan engine ke trek itu
    // lewat kuncinya.
    if (sourceIndex < 0 || sourceIndex >= _sourceTracks.length) return;
    final t = _sourceTracks[sourceIndex];
    if (engine.current?.key != t.key) {
      // Perpindahan alami (selesai / lewati oleh player): tutup buku trek sebelumnya.
      final prev = engine.current;
      final fullIndex = engine.fullIndexOf(t.key);
      if (fullIndex < 0) {
        // v4.4 (audit transport): tujuan TIDAK ada di antrean maju — ini gerak
        // MUNDUR pemutar (Sebelumnya). Trek tujuan sudah terkonsumsi dari
        // seksi-seksinya; dulu cabang ini `return` diam-diam sehingga pemutar
        // memutar trek sebelumnya sementara UI/notifikasi tetap menunjuk trek
        // lama (Sebelumnya tampak mati / judul desinkron). Pulihkan dari
        // riwayat sesi; buku trek yang ditinggalkan ditutup sebagai belum
        // selesai (lompatan manual, bukan penyelesaian alami).
        final p = engine.playedIndexOf(t.key);
        if (p < 0) return;
        if (prev != null) _closeTrackEvent(prev, completed: false);
        engine.restorePlayed(p);
        mediaItem.add(_toMediaItem(t));
        _trackStartedAt = DateTime.now();
        _lastPosition = Duration.zero;
        _consecutiveFailures = 0;
        _ladderAdvances.remove(t.key.toString());
        _emitQueue();
        final dNow = _activePlayer.duration;
        if (dNow != null) _attributeDuration(dNow);
        unawaited(_maybeRefill());
        return;
      }
      // Ronde 8063: perpindahan indeks maju ini bisa merupakan
      // seekToNext PERINTAH yang baru saja dijalankan skipToNext —
      // bagi listener indeks, bentuknya sama dengan selesai alami.
      // Bila trek tujuan cocok dengan penanda perintah yang masih
      // segar, tutup buku seperti biasa (statistik tidak berubah)
      // tetapi JANGAN bangunkan kait akhir alami: timer tidur mode
      // akhir-lagu harus tetap terpasang untuk lagu hasil lompatan.
      var fireNaturalEnd = true;
      final skipKey = _skipTargetKey;
      final skipAt = _skipTargetAt;
      if (skipKey != null &&
          skipKey == t.key &&
          skipAt != null &&
          DateTime.now().difference(skipAt) < const Duration(seconds: 5)) {
        fireNaturalEnd = false;
        _skipTargetKey = null;
        _skipTargetAt = null;
      }
      if (prev != null) {
        _closeTrackEvent(prev,
            completed: true, fireNaturalEnd: fireNaturalEnd);
      }
      // Selaraskan engine: lompat internal tanpa membuang manual (advance semantik ditangani di sini).
      _syncEngineTo(fullIndex);
      mediaItem.add(_toMediaItem(t));
      _trackStartedAt = DateTime.now();
      _lastPosition = Duration.zero;
      _consecutiveFailures = 0;
      _ladderAdvances.remove(t.key.toString());
      _emitQueue();
      // Durasi trek baru mungkin sudah diketahui pemutar saat transisi.
      final dNow = _activePlayer.duration;
      if (dNow != null) _attributeDuration(dNow);
      unawaited(_maybeRefill());
      // ADR-002: batas lagu alami = momen alih mode gapless → crossfade.
      if (pendingTransitionMode == 'crossfade') {
        unawaited(_enterCrossfadeFromCurrent());
      }
    }
    unawaited(_maybeExtendWindow(_currentFullIndex));
  }

  /// Menyelaraskan engine.current ke posisi fullIndex dengan memangkas seksi-seksi secara konsisten.
  void _syncEngineTo(int fullIndex) {
    final full = engine.fullQueue;
    final target = full[fullIndex];
    // Konsumsi dari depan: semua sebelum target dibuang dari seksi asalnya.
    var remaining =
        fullIndex; // jumlah item sebelum target (termasuk current lama di 0)
    // full[0] adalah current lama; item 1..fullIndex-1 berasal dari manual/continuation/autoplay berurutan.
    var toSkip = remaining - 1; // lewati current lama
    if (toSkip > 0) {
      int take(List<Track> s) {
        final n = toSkip <= s.length ? toSkip : s.length;
        s.removeRange(0, n);
        toSkip -= n;
        return n;
      }

      take(engine.manual);
      if (toSkip > 0) take(engine.continuation);
      if (toSkip > 0) take(engine.autoplay);
    }
    if (engine.manual.isNotEmpty && engine.manual.first.key == target.key) {
      engine.manual.removeAt(0);
    } else if (engine.continuation.isNotEmpty &&
        engine.continuation.first.key == target.key) {
      engine.continuation.removeAt(0);
    } else if (engine.autoplay.isNotEmpty &&
        engine.autoplay.first.key == target.key) {
      engine.autoplay.removeAt(0);
    }
    // Current lama masuk riwayat sesi (audit v4.4) — bahan pemulihan gerak mundur.
    final old = engine.current;
    if (old != null && old.key != target.key) engine.played.add(old);
    engine.current = target;
  }

  void _closeTrackEvent(Track t,
      {required bool completed, bool fireNaturalEnd = true}) {
    final listened = DateTime.now().difference(_trackStartedAt).inMilliseconds;
    final dur = t.duration?.inMilliseconds ?? 0;
    final done = completed && (dur == 0 || listened >= dur * 0.8);
    if (done) engine.noteCompleted(t);
    db.logPlayback(
      t,
      listenedMs: listened,
      completed: done,
      contextKind: engine.context?.kind,
      contextId: engine.context?.id,
    );
    // Kait F2 (ListenBrainz): kegagalan kait tidak boleh mengganggu putar.
    final hook = onListenFinished;
    if (hook != null) {
      try {
        hook(t, listened, done);
      } catch (_) {
        /* layanan luar tidak menjatuhkan pemutar */
      }
    }
    // Kait F2 (Lanjut Besok): hanya akhir ALAMI yang membangunkan timer
    // mode akhir-lagu — skip manual menutup trek dengan completed=false.
    // Satu pengecualian bentuk: perpindahan indeks maju perintah
    // skipToNext di _onIndexChanged tetap ditutup completed=true
    // (buku statistik sama seperti sebelumnya) tetapi memanggil
    // dengan fireNaturalEnd: false — lompatan perintah BUKAN akhir
    // alami (Ronde 8063).
    if (completed && fireNaturalEnd) {
      try {
        onNaturalTrackEnd?.call();
      } catch (_) {}
    }
  }

  // ---------------- isi ulang Putar Otomatis ----------------
  /// Status isi ulang diterbitkan ke engine (v4.3): layar Antrian menampilkan
  /// "menyiapkan" selama jaringan bekerja dan "gagal + coba lagi" bila batch
  /// kosong/lempar — sebelumnya jeda ini tak kasatmata sehingga daftar radio
  /// dilaporkan "tidak ada di mana pun". Kegagalan juga dicoba ulang otomatis
  /// sekali sesudah 25 dtk selama antrean masih membutuhkannya.
  Future<void> _maybeRefill({bool force = false}) async {
    if (_refilling) {
      // v4.4.2: permintaan yang datang saat isi ulang lain berjalan TIDAK
      // boleh hilang — dulu ia gugur diam-diam, dan bila yang berjalan itu
      // milik sesi lama, sesi baru tidak pernah terisi sama sekali (keadaan
      // "antrean kosong, tidak menyiapkan, tidak gagal" yang teramati di
      // emulator). Tandai tertunda; dijalankan ulang begitu yang berjalan usai.
      _refillPending = true;
      return;
    }
    if (!engine.autoplayActive) return;
    if (engine.current == null)
      return; // tak ada sesi berjalan: tak ada yang diisi
    if (!force && !engine.needsAutoplayRefill) return;
    _refilling = true;
    final sid = engine.sessionId;
    engine.autoplayPreparing = true;
    engine.autoplayRefillFailed = false;
    _emitQueue();
    // F2 mode offline (L-11): isi ulang HANYA dari unduhan — tanpa jaringan.
    if (offlineMode) {
      try {
        await _offlineRefill();
      } catch (e) {
        Observability.instance.log('autoplay-offline-gagal', e.toString());
        engine.autoplayRefillFailed = true;
      } finally {
        _refilling = false;
        engine.autoplayPreparing = false;
        _emitQueue();
        if (_refillPending) {
          _refillPending = false;
          if (engine.needsAutoplayRefill || engine.starvedAtEnd) {
            unawaited(_maybeRefill());
          }
        }
      }
      return;
    }
    try {
      // Temuan vonis 2008 #4: jalur isi ulang kini menerima sinyal
      // personal ASLI (dulu playCounts diteruskan kosong) dan mengecualikan
      // riwayat sesi dari kandidat — lihat buildRefillBatch.
      final ladder = SimilarityLadder(
        similaritySource,
        likedKeys: await db.likedKeys(),
        playCounts: await db.playCounts(),
      );
      final queued = engine.fullQueue.map((t) => t.key).toSet();
      final playedKeys = engine.played.map((t) => t.key).toSet();
      final refill = await buildRefillBatch(
        ladder,
        seeds: engine.refillSeeds(),
        queuedKeys: queued,
        playedKeys: playedKeys,
        sessionNegative: engine.skippedKeys,
        lastArtistNames: engine.fullQueue.isEmpty
            ? null
            : engine.fullQueue.last.artistNames,
      );
      final batch = refill.batch;
      if (batch.isNotEmpty) {
        Observability.instance.log(
          'autoplay-isi-ulang',
          'batch ${batch.length} trek; antre ${queued.length}, '
              'riwayat dikecualikan ${playedKeys.length}'
              '${refill.relaxed ? ', PELONGGARAN riwayat (kolam habis)' : ''}',
        );
      }
      if (sid != engine.sessionId) {
        // Konteks manual baru mulai di tengah isi ulang: batch ini dihitung
        // dari benih sesi LAMA — membuangnya adalah disiplin anti-drift,
        // bukan kegagalan. Sesi baru diisi oleh jalur tertunda di finally.
        Observability.instance.log(
          'autoplay-refill-basi',
          'sesi $sid → ${engine.sessionId}: batch ${batch.length} trek dibuang',
        );
      } else if (batch.isNotEmpty) {
        engine.appendAutoplay(batch);
        // Tambahkan anak sumber untuk item baru yang masuk jendela.
        await _extendSourceToQueue();
        // Cacat v4.4.2-2 (jalur terakhir): bila trek berjalan SUDAH selesai
        // alami selagi isi ulang ini terbang/mendarat, jendela yang
        // diperpanjang tidak membangunkan pemutar yang completed —
        // majukan di sini agar semua jalur pendaratan batch (pengait
        // completed, retry, isi ulang biasa) menghidupkan lagi putaran.
        if (!_xfMode &&
            _activePlayer.processingState == ProcessingState.completed &&
            engine.autoplayActive &&
            engine.effectiveQueue.isNotEmpty) {
          await _advanceIntoContinuation();
        }
      } else {
        engine.autoplayRefillFailed = true;
        _scheduleRefillRetry();
      }
    } catch (e) {
      Observability.instance.log('autoplay-refill-gagal', e.toString());
      if (sid == engine.sessionId) {
        engine.autoplayRefillFailed = true;
        _scheduleRefillRetry();
      }
    } finally {
      _refilling = false;
      engine.autoplayPreparing = false;
      _emitQueue();
      if (_refillPending) {
        _refillPending = false;
        if (engine.needsAutoplayRefill || engine.starvedAtEnd) {
          unawaited(_maybeRefill());
        }
      }
    }
  }

  void _scheduleRefillRetry() {
    _refillRetryTimer?.cancel();
    _refillRetryTimer = Timer(const Duration(seconds: 25), () async {
      if (engine.needsAutoplayRefill) await _maybeRefill();
      // Isi ulang yang mendarat TERLAMBAT — sesudah trek terakhir terlanjur
      // selesai — tetap wajib menggerakkan pemutar dari keadaan completed
      // (cacat v4.4.2-2: menambah sumber ke pemutar completed tidak pernah
      // cukup; just_audio tidak melanjutkan dengan sendirinya).
      if (!_xfMode &&
          _activePlayer.processingState == ProcessingState.completed &&
          engine.autoplayActive &&
          engine.effectiveQueue.isNotEmpty) {
        await _advanceIntoContinuation();
      }
    });
  }

  /// Akhir trek alami (cacat v4.4.2-2, laporan pemilik 00:20): trek tunggal
  /// ber-Putar Otomatis berakhir → aplikasi diam di trek awal; pemilik harus
  /// menekan Next berulang kali atau mematikan-menyalakan sakelar. Jalur ini
  /// membuat akhir alami mengalir ke sambungan TANPA sentuhan: antrean mesin
  /// yang sudah punya sambungan diselaraskan ke jendela, antrean yang masih
  /// kosong diisi paksa lebih dulu lalu dilanjutkan.
  Future<void> _onPlaybackCompleted() async {
    if (engine.repeat == RepeatMode.one)
      return; // Repeat-Satu: loop pemain menangani sendiri
    if (!engine.autoplayActive || engine.current == null) return;
    // Wilayah Repeat-Semua konteks banyak trek (L-09) bukan jalur cacat ini.
    if (engine.repeat == RepeatMode.all &&
        (engine.context?.tracks.length ?? 0) > 1)
      return;
    if (engine.effectiveQueue.isNotEmpty) {
      await _advanceIntoContinuation();
      return;
    }
    if (engine.starvedAtEnd) {
      await _maybeRefill(force: true);
      if (engine.effectiveQueue.isNotEmpty &&
          _player.processingState == ProcessingState.completed) {
        await _advanceIntoContinuation();
      }
    }
  }

  /// Memindahkan pemutar yang COMPLETED ke sambungan pertama antrean mesin:
  /// bangun ulang ekor dari trek berjalan (kini memuat sambungan), lompat,
  /// putar. Penjaga re-entransi mencegah lompatan ganda bila kait selesai
  /// dan jalur lain (retry / Next manual) berlomba di momen yang sama.
  Future<void> _advanceIntoContinuation() async {
    if (_advancingFromCompleted) return;
    _advancingFromCompleted = true;
    final beforeKey = engine.current?.key;
    final nextKey =
        engine.effectiveQueue.isNotEmpty ? engine.effectiveQueue.first.key : null;
    try {
      // Ronde 8057: generasi BERJALAN diteruskan tanpa klaim baru —
      // lanjut otomatis adalah jalur mesin, bukan perintah pengguna,
      // jadi ia tidak boleh mengalahkan ketukan yang sedang terbang;
      // sebaliknya bila ketukan lebih baru datang di tengah bangun,
      // bangun ini gugur di titik komit dan jalur ini berhenti (perintah
      // pemenang yang memajukan putaran). firstOnly TIDAK dipakai:
      // bangun di sini justru harus memuat kepala sambungan ke jendela
      // agar seekToNext di bawah punya tujuan — jendela satu trek akan
      // memaksa jatuh ke jumpTo pada setiap akhir alami.
      if (!await _rebuildTail(gen: _playGen)) return;
      if (_player.hasNext) {
        await _player.seekToNext();
        await _player.play();
      } else if (engine.effectiveQueue.isNotEmpty) {
        await jumpTo(engine.effectiveQueue.first.key);
      }
    } catch (e) {
      Observability.instance.log('lanjut-otomatis-gagal', e.toString());
    } finally {
      _advancingFromCompleted = false;
    }
    // Verifikasi perpindahan (cacat vonis perangkat Tahap 3, lihat
    // _verifyAdvance): upaya maju di atas terbukti bisa hilang balapan.
    if (beforeKey != null && nextKey != null && nextKey != beforeKey) {
      _verifyAdvance(beforeKey, nextKey, 'lanjut-otomatis');
    }
  }

  /// Penjaga hasil upaya maju (Next manual & sambungan otomatis).
  ///
  /// Cacat terukur di emulator (build 6032, dua episode konteks trek
  /// tunggal dari Pencarian): sesudah trek sambungan-Pertama selesai
  /// secara alami — dan juga saat Next ditekan di tengah trek itu —
  /// upaya maju (bangun ulang ekor + seekToNext, atau seekToNext saja)
  /// hilang balapan dengan pemasangan sumber: pemutar menyiapkan ULANG
  /// trek yang sama dari ±0 dan antrean tak berpindah, tanpa satu pun
  /// catatan galat; trek yang sama lalu berputar ulang di setiap akhir
  /// alaminya. Mesin antrean, resolusi trek berikutnya, dan isi ulang
  /// semuanya terbukti sehat — yang gugur ialah perpindahan periodenya.
  /// jumpTo (bangun sumber penuh dari target) terbukti menyembuhkan
  /// keadaan ini seketika, jadi: bila 1,5 dtk sesudah upaya maju trek
  /// berjalan BELUM berpindah padahal putaran masih hidup (berbunyi
  /// atau completed), eskalasi ke jumpTo menuju target yang sama.
  /// Jeda pengguna yang disengaja (tak berbunyi & tak completed) tidak
  /// pernah dioverride.
  void _verifyAdvance(TrackKey fromKey, TrackKey toKey, String what) {
    if (_advanceVerifyPending) return;
    _advanceVerifyPending = true;
    Future.delayed(const Duration(milliseconds: 1500), () async {
      _advanceVerifyPending = false;
      if (_xfMode) return;
      final nowKey = engine.current?.key;
      if (nowKey == null || nowKey != fromKey) return; // sudah berpindah
      if (!_player.playing &&
          _player.processingState != ProcessingState.completed) {
        return; // jeda disengaja pengguna — jangan dioverride
      }
      Observability.instance.log('eskalasi-lompat',
          '$what: trek tak berpindah 1,5 dtk sesudah upaya maju — lompat paksa ke sambungan');
      try {
        // Eskalasi MEMPERBAIKI lompatan yang sudah diperintah — bukan
        // aksi memilih trek baru: timer tidur tidak boleh batal
        // karenanya (Ronde 8063).
        await jumpTo(toKey, preserveSleepTimer: true);
        await _player.play();
      } catch (_) {}
    });
  }

  /// Coba lagi isi ulang Putar Otomatis (tombol di layar Antrian, v4.3).
  Future<void> retryAutoplayRefill() => _maybeRefill(force: true);

  Future<void> _extendSourceToQueue() async {
    if (_xfMode) return; // jalur crossfade tidak memakai sumber gabungan
    if (_source == null || _sourceTracks.isEmpty) return;
    final full = engine.fullQueue;
    // Ujung jendela lewat kunci (lihat _onIndexChanged) — bukan _windowStart.
    final lastIdx = engine.fullIndexOf(_sourceTracks.last.key);
    if (lastIdx < 0) return;
    final loadedEnd = lastIdx + 1;
    if (loadedEnd < full.length && full.length - loadedEnd <= 60) {
      final more = full.sublist(loadedEnd);
      for (final t in more) {
        try {
          await _source!.add(await _childFor(t));
          _sourceTracks.add(t);
        } catch (_) {
          break;
        }
      }
    }
  }

  // ---------------- jalur crossfade (F2, ADR-002) ----------------
  /// Kepala antrean efektif (null bila kosong).
  Track? get _xfHead =>
      engine.effectiveQueue.isEmpty ? null : engine.effectiveQueue.first;

  void _ensureXfMonitor() {
    _xfMonitorTimer ??= Timer.periodic(
      const Duration(milliseconds: 200),
      (_) => _xfTick(),
    );
  }

  void _stopXfMonitor() {
    _xfMonitorTimer?.cancel();
    _xfMonitorTimer = null;
    _xfRampTimer?.cancel();
    _xfRampTimer = null;
    _xfRamping = false;
    _xfPreloaded = null;
    _xfPreloadDegraded = false;
  }

  /// Batalkan preload/ramp yang berjalan (kepala antrean berubah / perintah manual).
  void _xfCancelPreload() {
    _xfRampTimer?.cancel();
    _xfRampTimer = null;
    _xfRamping = false;
    if (_xfPreloaded != null) {
      _idlePlayer.pause();
      _xfPreloaded = null;
      _xfPreloadDegraded = false;
    }
  }

  /// Hentikan pemain diam sepenuhnya (perintah manual membatalkan urutan crossfade).
  Future<void> _xfResetPlayers() async {
    _xfCancelPreload();
    try {
      await _idlePlayer.stop();
    } catch (_) {
      /* pemain diam memang boleh kosong */
    }
  }

  /// Memutar satu trek di pemain aktif (jalur crossfade): sumber tunggal,
  /// tanpa sumber gabungan. [initialPosition] dipakai handoff batas-mode.
  ///
  /// [gen] (Ronde 8054): generasi perintah putar pemanggil. Jalur ini dulu
  /// TIDAK punya titik komit generasi (jalur gapless punya, di _buildSource):
  /// invokasi yang resolusinya selesai belakangan tetap memasang sumber &
  /// berbunyi. Terbukti di emulator pada APK rilis: ketukan berurutan pada
  /// mode crossfade berbunyi satu-satu mengikuti urutan ketuk sampai
  /// ketukan terakhir — gejala persis laporan pemilik 2026-11-11. Kini
  /// generasi diperiksa ulang sesudah resolusi (sebelum menyentuh pemutar,
  /// pola yang sama dengan verifikasi ulang _xfPreload) dan sekali lagi
  /// tepat sebelum play() — tanpa jeda await di antara periksa & perintah,
  /// jadi tidak ada celah sela. Pemanggil internal tanpa generasi
  /// (lompat/ramp/handoff mode) perilakunya tidak berubah.
  Future<void> _xfPlayCurrent(
    Track t, {
    Duration initialPosition = Duration.zero,
    int? gen,
  }) async {
    bool superseded() => gen != null && gen != _playGen;
    await _xfResetPlayers();
    _xfPreloadFailedKey = null;
    await _gainFor(t);
    // Ronde 8059 (keputusan pemilik 2026-11-13 — perubahan semantik
    // ADR-002): bangun + pasang kini MENAIKI TANGGA MUAT, persis jalur
    // gapless (_buildSource). Sebelumnya jalur crossfade memasang
    // sumber dari SATU anak (pemenang lengket) tanpa cadangan tingkat
    // pemain: saat resolusi DIRECT segar berhasil tetapi ambil byte
    // pemain ditolak 403 (badai jendela terbukti 2026-11-11), trek
    // masuk gugur tanpa jalur lain dan mode ini senyap total, sedang
    // gapless bertahan lewat tangga + proxy + muxed. Kini anak yang
    // gugur saat setAudioSource dicatat ('crossfade-tangga-gagal')
    // lalu tangga maju; trek yang diselamatkan anak cadangan mulai
    // sebagai potong biasa (situs ini memang tanpa ramp — ramp hanya
    // dari preload sehat, lihat _xfPreload). Galat kelas BATAL
    // (_Superseded/DirectSuperseded) menghentikan panjat seketika:
    // hasil cadangan dari niat yang sudah tergantikan TIDAK boleh
    // menghidupkan trek lama. Galat anak terakhir tetap dilempar ke
    // pemanggil, sama seperti kontrak satu-anak sebelumnya.
    try {
      await _ladder.run(
        attempt: (rung) async {
          final child = await _ladder.childFor(t, rung,
              strict: true,
              stillWanted: gen == null ? null : () => gen == _playGen);
          if (superseded()) throw const _Superseded(); // titik komit generasi
          _sourceBuiltThisProcess = true;
          await _activePlayer.setAudioSource(child,
              initialPosition: initialPosition);
        },
        isAbortError: (e) => e is _Superseded || e is DirectSuperseded,
        onRungFailed: (rung, e, st) {
          // Anak tangga yang gugur karena disela muat lain bukan kegagalan.
          if (isInterruptionError(e)) return;
          // Paritas Tahap 3 dengan _buildSource: kegagalan anak ADAPTIF
          // di dalam tangga tidak mencapai _onPlayerError — laporkan
          // penolakan DIRECT agar sesi minter disegarkan.
          if (rung == LoadLadder.rungAdaptiveUri &&
              _resolvedDirect[t.key] == true) {
            directRejectedHook?.call(t);
          }
          Observability.instance.log(
            'crossfade-tangga-gagal',
            'anak ${rung + 1}/${LoadLadder.rungCount} (${LoadLadder.rungLabel(rung)}) untuk "${t.title}": ${describeError(e, st)}',
          );
        },
      );
    } on DirectSuperseded {
      return; // dibuang dari antrean resolusi: sudah dikalahkan
    } on _Superseded {
      return; // dikalahkan sebelum menyentuh pemutar: senyap, bukan galat
    }
    await _activePlayer.setLoopMode(
      engine.repeat == RepeatMode.one ? LoopMode.one : LoopMode.off,
    );
    await _applyVolume();
    if (superseded()) return; // ketukan lebih baru tiba saat memasang
    await _activePlayer.play();
    _trackStartedAt = DateTime.now();
    _lastPosition = initialPosition;
    _sourceBuiltThisProcess = true;
    _ensureXfMonitor();
  }

  /// Satu detak monitor (200 ms): preload trek berikutnya lebih awal, lalu
  /// mulai ramp saat lagu berjalan mendekati akhir.
  void _xfTick() {
    if (!_xfMode || engine.current == null) return;
    final active = _activePlayer;
    if (!active.playing || _xfRamping) return;
    final dur = active.duration;
    if (dur == null || dur == Duration.zero) return;
    final remaining = dur - active.position;
    // Kepala antrean berubah → preload lama batal (lagu itu tak lagi berikutnya).
    if (_xfPreloaded != null) {
      final head = _xfHead;
      if (head == null || head.key != _xfPreloaded!.key) _xfCancelPreload();
    }
    if (engine.repeat == RepeatMode.one) return; // loop ditangani pemutar
    final head = _xfHead;
    if (head == null) {
      if (engine.autoplayActive) unawaited(_maybeRefill());
      return;
    }
    final rampMs = (crossfadeSecs * 1000).round();
    if (_xfPreloaded == null) {
      // Preload 10 detik LEBIH AWAL dari jendela ramp: resolusi + buffering
      // butuh waktu; preload yang baru dimulai di batas ramp pasti telat.
      if (remaining.inMilliseconds <= rampMs + 10000 &&
          _xfPreloadFailedKey != head.key) {
        unawaited(_xfPreload(head));
      }
      return;
    }
    // Ronde 8059: preload terdegradasi (hanya selamat di anak cadangan)
    // TIDAK diramp — treknya mulai sebagai potong biasa lewat
    // _xfAdvanceAfterEnd → _xfPlayCurrent saat trek berjalan berakhir.
    if (remaining.inMilliseconds <= rampMs && !_xfPreloadDegraded) {
      _xfStartRamp();
    }
  }

  Future<void> _xfPreload(Track next) async {
    if (_xfPreloaded != null || _xfRamping) return;
    if (_xfPreloadInFlightKey != null) return; // satu preload pada satu waktu
    _xfPreloadInFlightKey = next.key;
    try {
      await _gainFor(next);
      // Ronde 8059 (perubahan semantik ADR-002): preload kini MENAIKI
      // TANGGA seperti _xfPlayCurrent & jalur gapless — sebelumnya satu
      // anak saja, dan kegagalan tingkat pemainnya mematikan trek ini
      // dari crossfade (kunci gagal lengket, tanpa jalur lain). Anak
      // pertama yang dicoba = pemenang lengket saat preload mulai;
      // kemenangan anak LAIN berarti sumber langsung trek ini ditolak
      // pemain → transisinya terdegradasi (potong biasa, tanpa ramp).
      final firstRung = _ladder.stickyRung;
      var wonRung = firstRung;
      await _ladder.run(
        attempt: (rung) async {
          final child = await _ladder.childFor(next, rung, strict: true);
          // Kepala antrean bisa berubah selama resolusi — batalkan
          // panjat untuk kepala basi (kelas BATAL, bukan kegagalan).
          if (_xfHead?.key != next.key) throw const _Superseded();
          await _idlePlayer.setAudioSource(child);
          wonRung = rung;
        },
        isAbortError: (e) => e is _Superseded || e is DirectSuperseded,
        onRungFailed: (rung, e, st) {
          if (isInterruptionError(e)) return;
          Observability.instance.log(
            'crossfade-preload-tangga-gagal',
            'anak ${rung + 1}/${LoadLadder.rungCount} (${LoadLadder.rungLabel(rung)}) untuk "${next.title}": ${describeError(e, st)}',
          );
        },
      );
      // Kepala antrean bisa berubah selama resolusi — verifikasi ulang.
      if (_xfHead?.key != next.key) return;
      await _idlePlayer.setVolume(0);
      _xfPreloaded = next;
      _xfPreloadDegraded = wonRung != firstRung;
      if (_xfPreloadDegraded) {
        Observability.instance.log(
          'crossfade-preload-degradasi',
          '"${next.title}": sumber langsung gagal di tingkat pemain; selamat di anak ${wonRung + 1} (${LoadLadder.rungLabel(wonRung)}) — transisi jadi potong biasa',
        );
      }
    } on _Superseded {
      // Kepala berubah di tengah panjat: bukan kegagalan — jangan kunci
      // trek ini sebagai preload gagal.
      return;
    } on DirectSuperseded {
      return;
    } catch (e) {
      // Ketiga anak gugur (galat anak terakhir dari tangga).
      _xfPreloadFailedKey = next.key;
      Observability.instance.log(
        'crossfade-preload-gagal',
        '"${next.title}": $e',
      );
    } finally {
      if (_xfPreloadInFlightKey == next.key) _xfPreloadInFlightKey = null;
    }
  }

  void _xfStartRamp() {
    final next = _xfPreloaded;
    // Ronde 8059: ramp tidak pernah dimulai untuk preload terdegradasi
    // (penjaga kedua sesudah _xfTick — situs panggil lain pun aman).
    if (next == null || _xfRamping || _xfPreloadDegraded) return;
    final active = _activePlayer;
    final dur = active.duration;
    if (dur == null || dur == Duration.zero) return;
    final remainingSecs = (dur - active.position).inMilliseconds / 1000.0;
    // Bila preload telat, ramp dipadatkan ke sisa waktu (min 0,5 dtk).
    _xfRampSecs = remainingSecs.clamp(0.5, crossfadeSecs);
    final gainOut = _gainFactor(engine.current);
    final gainIn = _gainFactor(next);
    final outgoing = active;
    final incoming = _idlePlayer;
    _xfRamping = true;
    _xfRampStart = DateTime.now();
    incoming.setVolume(0);
    incoming.play();
    Observability.instance.log(
      'crossfade-mulai',
      '"${engine.current?.title}" → "${next.title}" (${_xfRampSecs.toStringAsFixed(1)} dtk)',
    );
    _xfRampTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      final t =
          DateTime.now().difference(_xfRampStart).inMilliseconds /
          1000.0 /
          _xfRampSecs;
      if (t >= 1) {
        unawaited(_xfFinishRamp());
        return;
      }
      final v = crossfadeVolumes(t);
      outgoing.setVolume(
        _masterVolume * _sleepFade * _drivingVolume * gainOut * v.outgoing,
      );
      incoming.setVolume(
        _masterVolume * _sleepFade * _drivingVolume * gainIn * v.incoming,
      );
    });
  }

  Future<void> _xfFinishRamp() async {
    _xfRampTimer?.cancel();
    _xfRampTimer = null;
    final next = _xfPreloaded;
    if (next == null) {
      _xfRamping = false;
      return;
    }
    // Kepala antrean berubah di tengah ramp → batalkan tukar (jangan tukar sesi).
    if (_xfHead?.key != next.key) {
      await _idlePlayer.pause();
      _xfPreloaded = null;
      _xfPreloadDegraded = false;
      _xfRamping = false;
      return;
    }
    final prev = engine.current;
    final outgoing = _activePlayer;
    final incoming = _idlePlayer;
    await incoming.setVolume(
      _masterVolume * _sleepFade * _drivingVolume * _gainFactor(next),
    );
    await outgoing.pause();
    _xfActiveB = !_xfActiveB;
    _xfPreloaded = null;
    _xfPreloadDegraded = false;
    _xfRamping = false;
    if (prev != null) _closeTrackEvent(prev, completed: true);
    final advanced = engine.takeNextForCrossfade();
    if (advanced == null || advanced.key != next.key) {
      Observability.instance.log(
        'crossfade-tukar-gagal',
        'kepala antrean berubah saat tukar',
      );
      return;
    }
    mediaItem.add(_toMediaItem(next));
    _trackStartedAt = DateTime.now();
    _lastPosition = Duration.zero;
    _consecutiveFailures = 0;
    _emitQueue();
    unawaited(_maybeRefill());
    if (pendingTransitionMode == 'gapless') {
      await _enterGaplessFromCurrent();
    }
  }

  /// Cadangan akhir trek di jalur crossfade (preload gagal / antrean kosong
  /// saat akhir): lanjut segera tanpa ramp, atau isi ulang dulu bila autoplay.
  Future<void> _xfAdvanceAfterEnd() async {
    if (engine.repeat == RepeatMode.one) return;
    final prev = engine.current;
    if (engine.effectiveQueue.isNotEmpty) {
      if (prev != null) _closeTrackEvent(prev, completed: true);
      final next = engine.takeNextForCrossfade();
      if (next != null) {
        mediaItem.add(_toMediaItem(next));
        _emitQueue();
        await _xfPlayCurrent(next);
      }
      return;
    }
    if (engine.autoplayActive && engine.starvedAtEnd) {
      await _maybeRefill(force: true);
      if (engine.effectiveQueue.isNotEmpty) {
        if (prev != null) _closeTrackEvent(prev, completed: true);
        final next = engine.takeNextForCrossfade();
        if (next != null) {
          mediaItem.add(_toMediaItem(next));
          _emitQueue();
          await _xfPlayCurrent(next);
        }
      }
    }
  }

  /// Alih gapless → crossfade di batas lagu (ADR-002): lagu berjalan
  /// dilanjutkan di pemain A sebagai sumber tunggal (posisi dipertahankan).
  Future<void> _enterCrossfadeFromCurrent() async {
    final cur = engine.current;
    if (cur == null) return;
    final pos = _player.position;
    final wasPlaying = _player.playing;
    transitionMode = 'crossfade';
    pendingTransitionMode = null;
    _xfActiveB = false;
    try {
      await _player.pause();
    } catch (_) {
      /* handoff tetap jalan */
    }
    await _xfPlayCurrent(cur, initialPosition: pos);
    if (!wasPlaying) await _activePlayer.pause();
  }

  /// Alih crossfade → gapless di batas lagu (ADR-002): sumber gabungan
  /// dibangun ulang dari lagu berjalan (posisi dipertahankan).
  Future<void> _enterGaplessFromCurrent() async {
    final pos = _activePlayer.position;
    final wasPlaying = _activePlayer.playing;
    transitionMode = 'gapless';
    pendingTransitionMode = null;
    _xfActiveB = false;
    _stopXfMonitor();
    _lastPosition = pos;
    final idx = _currentFullIndex;
    if (idx >= 0) {
      await _buildSource(
        fromFullIndex: idx,
        autoplay: wasPlaying,
        what: 'alih mode ke gapless',
      );
    }
  }

  /// Lompat Berikutnya di jalur crossfade: tanpa ramp (perintah manual =
  /// respons seketika); Repeat-Satu dilepas untuk lompatan eksplisit.
  Future<void> _xfSkipNext() async {
    final cur = engine.current;
    if (cur != null &&
        _activePlayer.position < const Duration(seconds: 30) &&
        _activePlayer.position > const Duration(seconds: 3)) {
      engine.noteSkipped(cur);
    }
    await _xfResetPlayers();
    if (engine.effectiveQueue.isEmpty && engine.autoplayActive) {
      await _maybeRefill();
    }
    final next = engine.takeNextForCrossfade(manualSkip: true);
    if (next == null) {
      notices.add(l10n.noticeQueueEnded);
      return;
    }
    if (cur != null && cur.key != next.key)
      _closeTrackEvent(cur, completed: false);
    mediaItem.add(_toMediaItem(next));
    _emitQueue();
    await _xfPlayCurrent(next);
  }

  /// Lompat Sebelumnya di jalur crossfade: > 3 dtk → ulang dari awal;
  /// ≤ 3 dtk → trek riwayat sesi.
  Future<void> _xfSkipPrevious() async {
    if (_activePlayer.position > const Duration(seconds: 3)) {
      await _activePlayer.seek(Duration.zero);
      return;
    }
    if (engine.played.isEmpty) {
      await _activePlayer.seek(Duration.zero);
      return;
    }
    await _xfResetPlayers();
    final prev = engine.current;
    engine.restorePlayed(engine.played.length - 1);
    final target = engine.current;
    if (target == null) return;
    if (prev != null && prev.key != target.key)
      _closeTrackEvent(prev, completed: false);
    mediaItem.add(_toMediaItem(target));
    _emitQueue();
    await _xfPlayCurrent(target);
  }

  // ---------------- perintah publik (dipanggil UI lewat provider) ----------------
  Future<void> playTracks(
    List<Track> tracks,
    int index, {
    required String kind,
    String? id,
    required String label,
  }) {
    final gen = ++_playGen;
    GateMetrics.instance.recordAttempt();
    _playIntentAt = DateTime.now();
    return _runPlay(() async {
      // Kait F2 (Lanjut Besok): memilih putaran baru membatalkan timer
      // tidur yang masih berjalan — kecuali aksi resume (flag satu-kali
      // di layanan). Navigasi Berikutnya/Sebelumnya tidak lewat sini;
      // ia memakai kait khususnya sendiri dan tidak membatalkan timer.
      try {
        onManualPlayAction?.call();
      } catch (_) {}
      db
          .setPref('playback.everPlayed', true)
          .then(
            (_) {},
            onError: (_) {},
          ); // penanda kartu pengingat latar (v4.1)
      if (tracks.isEmpty) return;
      // F2 mode offline: konteks disaring ke lagu yang bisa diputar tanpa jaringan.
      var playable = tracks;
      if (offlineMode) {
        playable = tracks.where(isOfflinePlayable).toList();
        if (playable.isEmpty) {
          notices.add(l10n.noticeOfflineNonePlayable);
          return;
        }
        if (playable.length < tracks.length) {
          notices.add(
            l10n.noticeOfflineSkipped(tracks.length - playable.length),
          );
        }
      }
      tracks = playable;
      // ADR-002: perintah putar manual = batas lagu — mode tertunda berlaku SEKARANG.
      if (pendingTransitionMode != null) {
        transitionMode = pendingTransitionMode!;
        pendingTransitionMode = null;
        if (!_xfMode) {
          _xfActiveB = false;
          _stopXfMonitor();
        }
      }
      // Indeks tak sah (mis. daftar hasil diganti di bawah baris yang diketuk)
      // TIDAK boleh melempar di dalam rantai yang menelan galat — dulu gejalanya
      // "ketuk tidak berputar sama sekali" tanpa jejak. Jepit & catat.
      final safeIndex = index.clamp(0, tracks.length - 1);
      if (safeIndex != index) {
        Observability.instance.log(
          'playtracks-indeks-dijepit',
          'indeks $index dari ${tracks.length} trek → $safeIndex ("$label")',
        );
      }
      final prev = engine.current;
      if (prev != null) _closeTrackEvent(prev, completed: false);
      // Sinyal selera segar untuk konteks mode smart (liked/hitungan bisa berubah sejak boot).
      if (engine.shuffle == ShuffleMode.smart) {
        engine.setSmartSignals(
          likedKeys: await db.likedKeys(),
          playCounts: await db.playCounts(),
        );
      }
      engine.playContext(
        PlayContext(kind: kind, id: id, label: label, tracks: tracks),
        safeIndex,
      );
      _pendingRestoreSeek = null; // konteks baru: seek pulih tak berlaku lagi
      _lastPosition = Duration.zero;
      // Umpan balik seketika: judul/sampul mini player berubah pada ketukan ini,
      // sebelum resolusi selesai — bukan setelah antrean serial kosong.
      mediaItem.add(_toMediaItem(engine.current!));
      _emitQueue();
      if (_xfMode) {
        await _xfPlayCurrent(engine.current!, gen: gen);
        if (gen != _playGen) return; // dikalahkan ketukan lebih baru
        _trackStartedAt = DateTime.now();
        _emitQueue();
        unawaited(_maybeRefill());
        return;
      }
      await _buildOrNotify(
        fromFullIndex: 0,
        autoplay: true,
        what: '"${engine.current!.title}"',
        gen: gen,
        firstOnly: true,
      );
      if (gen != _playGen) return; // dikalahkan ketukan lebih baru
      _trackStartedAt = DateTime.now();
      _emitQueue();
      unawaited(_extendSourceToQueue()); // tahap 2 jendela: sisa trek di latar
      unawaited(_maybeRefill());
    });
  }

  Future<void> startRadio(Track seed) {
    final gen = ++_playGen;
    return _runPlay(() async {
      db.setPref('playback.everPlayed', true).then((_) {}, onError: (_) {});
      // ADR-002: perintah putar manual = batas lagu.
      if (pendingTransitionMode != null) {
        transitionMode = pendingTransitionMode!;
        pendingTransitionMode = null;
        if (!_xfMode) {
          _xfActiveB = false;
          _stopXfMonitor();
        }
      }
      engine.playRadio(seed);
      _lastPosition = Duration.zero;
      mediaItem.add(_toMediaItem(seed));
      _emitQueue();
      if (_xfMode) {
        await _xfPlayCurrent(seed, gen: gen);
        if (gen != _playGen) return;
        _trackStartedAt = DateTime.now();
        _emitQueue();
        unawaited(_maybeRefill());
        return;
      }
      await _buildOrNotify(
        fromFullIndex: 0,
        autoplay: true,
        what: 'radio "${seed.title}"',
        gen: gen,
        firstOnly: true,
      );
      if (gen != _playGen) return;
      _trackStartedAt = DateTime.now();
      _emitQueue();
      unawaited(_maybeRefill());
    });
  }

  /// Mulai sesi radio dari HALAMAN Radio (F2.5): item halaman yang diketuk
  /// menjadi trek yang diputar; jangkar benih sesi tetap lagu asal halaman
  /// (lihat QueueEngine.playRadioFromPage). Struktur meniru [startRadio].
  Future<void> startRadioFromPage(Track seed, List<Track> page, int startIndex) {
    final gen = ++_playGen;
    return _runPlay(() async {
      db.setPref('playback.everPlayed', true).then((_) {}, onError: (_) {});
      // ADR-002: perintah putar manual = batas lagu.
      if (pendingTransitionMode != null) {
        transitionMode = pendingTransitionMode!;
        pendingTransitionMode = null;
        if (!_xfMode) {
          _xfActiveB = false;
          _stopXfMonitor();
        }
      }
      engine.playRadioFromPage(seed: seed, page: page, startIndex: startIndex);
      final current = engine.current ?? seed;
      _lastPosition = Duration.zero;
      mediaItem.add(_toMediaItem(current));
      _emitQueue();
      if (_xfMode) {
        await _xfPlayCurrent(current, gen: gen);
        if (gen != _playGen) return;
        _trackStartedAt = DateTime.now();
        _emitQueue();
        unawaited(_maybeRefill());
        return;
      }
      await _buildOrNotify(
        fromFullIndex: 0,
        autoplay: true,
        what: 'radio "${seed.title}"',
        gen: gen,
        firstOnly: true,
      );
      if (gen != _playGen) return;
      _trackStartedAt = DateTime.now();
      _emitQueue();
      unawaited(_maybeRefill());
    });
  }

  Future<void> enqueue(Track t, {required bool next}) {
    return _serial(() async {
      // Mode offline menolak lagu streaming masuk antrean (sumbernya takkan bisa dibangun).
      if (offlineMode && !isOfflinePlayable(t)) {
        notices.add(l10n.noticeOfflineNotDownloaded(t.title));
        return;
      }
      final wasIdle = engine.current == null;
      if (next) {
        engine.enqueueNext(t);
      } else {
        engine.enqueueLater(t);
      }
      if (wasIdle) {
        engine.current = t;
        engine.manual.remove(t);
        mediaItem.add(_toMediaItem(t));
        if (_xfMode) {
          await _xfPlayCurrent(t);
        } else {
          await _buildOrNotify(
            fromFullIndex: 0,
            autoplay: true,
            what: '"${t.title}"',
          );
        }
      } else {
        if (_xfMode) {
          // Monitor crossfade membaca kepala antrean secara live — tak ada
          // sumber yang perlu dibangun ulang.
          _emitQueue();
        } else if (next) {
          // Sisipan Berikutnya mengubah urutan tepat sesudah current:
          // sisip bedah pada sumber yang hidup (temuan vonis #3) — trek
          // berjalan tidak disiapkan ulang.
          await _syncTailAfterMutation('putar berikutnya', growTailBy: 1);
        } else {
          await _extendSourceToQueue();
        }
      }
      _emitQueue();
    });
  }

  /// Tambah banyak ke ekor Berikutnya (Ronde Tambahan 2015, halaman
  /// Radio: "Tambah ke antrean" atas seluruh daftar bangkitan).
  /// Mengembalikan jumlah trek yang benar-benar masuk. Semantik mengikuti
  /// [enqueue] satu-satu: mode offline menyaring trek yang tak bisa
  /// diputar luring (dengan satu pemberitahuan ringkas); pemain yang
  /// menganggur memulai trek pertama, sisanya mengantre — pemutaran yang
  /// sedang berjalan tidak pernah dibangun ulang/dijeda oleh tambahan di
  /// ekor (jalur yang sama seperti "Tambah ke Antrian" tunggal).
  Future<int> enqueueAll(List<Track> tracks) {
    return _serial(() async {
      var added = tracks;
      if (offlineMode) {
        added = tracks.where(isOfflinePlayable).toList();
        if (added.length != tracks.length) {
          notices.add(l10n.noticeOfflineSkipped(
              tracks.length - added.length));
        }
      }
      if (added.isEmpty) return 0;
      final wasIdle = engine.current == null;
      engine.enqueueAllLater(added);
      if (wasIdle) {
        final first = added.first;
        engine.current = first;
        engine.manual.remove(first);
        mediaItem.add(_toMediaItem(first));
        if (_xfMode) {
          await _xfPlayCurrent(first);
        } else {
          await _buildOrNotify(
            fromFullIndex: 0,
            autoplay: true,
            what: 'antrean massal "${first.title}"',
          );
        }
      } else if (_xfMode) {
        _emitQueue();
      } else {
        await _extendSourceToQueue();
      }
      _emitQueue();
      return added.length;
    });
  }

  /// Hapus massal mode pilih-banyak (Ronde Tambahan 2015): cabut semua
  /// item berkunci terpilih dari ketiga seksi antrean dalam SATU edit
  /// ekor bedah ([_syncTailAfterMutation]) — trek berjalan tidak pernah
  /// menjadi bagian edit (ia tidak hidup di seksi mana pun) sehingga
  /// pemutaran tidak terjeda. Item Putar Otomatis yang tercabut dicatat
  /// sebagai sinyal negatif sesi, sama seperti hapus geser (L-06).
  /// Mengembalikan jumlah item yang tercabut.
  Future<int> removeManyFromQueue({
    Set<TrackKey> manual = const {},
    Set<TrackKey> continuation = const {},
    Set<TrackKey> autoplay = const {},
  }) {
    return _serial(() async {
      var removed = 0;
      removed += engine.removeAllKeys(engine.manual, manual).length;
      removed += engine.removeAllKeys(engine.continuation, continuation).length;
      final autoRemoved = engine.removeAllKeys(engine.autoplay, autoplay);
      for (final t in autoRemoved) {
        engine.noteSkipped(t); // L-06, sama seperti hapus satu-satu
      }
      removed += autoRemoved.length;
      if (removed > 0) {
        await _syncTailAfterMutation('hapus massal dari antrean');
        _emitQueue();
      }
      return removed;
    });
  }

  /// "Putar Berikutnya" atas item yang SUDAH di antrean (Ronde Tambahan
  /// 2015): PINDAHKAN item ke kepala Berikutnya — bukan menyalinnya.
  Future<void> playNextQueued(String section, int index, TrackKey key) {
    return _serial(() async {
      final t = engine.extractQueued(section, index, key);
      if (t == null) return;
      engine.enqueueNext(t);
      await _syncTailAfterMutation('putar berikutnya dari antrean');
      _emitQueue();
    });
  }

  /// "Tambah ke Antrian" atas item yang SUDAH di antrean (Ronde Tambahan
  /// 2015): PINDAHKAN item ke ekor Berikutnya (semantik L-04 yang sama
  /// seperti dari konteks lain: ekor seksi pengguna).
  Future<void> sendQueuedToEnd(String section, int index, TrackKey key) {
    return _serial(() async {
      final t = engine.extractQueued(section, index, key);
      if (t == null) return;
      engine.enqueueLater(t);
      await _syncTailAfterMutation('pindah ke akhir antrean');
      _emitQueue();
    });
  }

  /// Bangun ulang ekor sumber dari trek berjalan (posisi & status putar
  /// dipertahankan). Mengembalikan TRUE bila pembangunan TERKOMIT, FALSE
  /// bila tidak ada yang dibangun (jalur crossfade / tak ada trek) atau
  /// pembangunan DIKALAHKAN perintah yang lebih baru di tengah jalan —
  /// pemanggil yang akan melanjutkan dengan seek/play di atas hasilnya
  /// WAJIB berhenti pada FALSE, karena sumber yang hidup saat itu sudah
  /// milik perintah pemenang, bukan miliknya.
  ///
  /// Ronde 8057: fungsi ini dulu TANPA generasi & TANPA firstOnly di
  /// semua situs panggil — penyakit yang sama dengan cabang pulih
  /// play(): jendela penuh (≤60 trek) diresolusi serial sebelum situs
  /// panggil boleh melanjutkan (itulah sebabnya Berikutnya terasa hanya
  /// merespons secara kumulatif), dan tanpa [gen] semua penjaga
  /// kalah-ganti _buildSource mati sehingga hasil bangun yang usang
  /// tetap terpasang menimpa apa pun yang dimulai pengguna selama
  /// menunggu. Kini [gen] diteruskan persis seperti situs pembangunan
  /// saudara (jumpTo/playTracks/restoreSleepSession): situs PERINTAH
  /// mengklaim generasi baru, situs otomatis/mutasi/pemulihan
  /// meneruskan generasi berjalan tanpa mengklaim (lihat tiap situs).
  /// Kelas BATAL (_Superseded/DirectSuperseded) ditelan menjadi FALSE
  /// di sini — dikalahkan bukan galat; galat pembangunan lain tetap
  /// DILEMPAR agar rantai jatuh-balik pemanggil (khususnya pemulihan
  /// galat putar) tidak berubah perilakunya.
  Future<bool> _rebuildTail({int? gen, bool firstOnly = false}) async {
    if (_xfMode) return false; // jalur crossfade tidak memakai sumber gabungan
    // Pertahankan trek berjalan & posisinya; sumber dibangun ulang dari current.
    final pos = _player.position;
    final wasPlaying = _player.playing;
    final idx = _currentFullIndex;
    if (idx < 0) return false;
    _lastPosition = pos;
    try {
      await _buildSource(
        fromFullIndex: idx,
        autoplay: wasPlaying,
        what: 'bangun ulang ekor antrean',
        gen: gen,
        firstOnly: firstOnly,
      );
    } on _Superseded {
      return false; // dikalahkan di titik komit: sumber tidak terpasang
    } on DirectSuperseded {
      return false; // resolusi dibuang dari antrean: alasan yang sama
    }
    // _buildSource juga bisa kembali normal sesudah penjaga pasca-pasang
    // (generasi berubah SELAMA setAudioSource): sumber sempat terpasang
    // tetapi bukan lagi milik generasi ini — laporkan belum terkomit.
    if (gen != null && gen != _playGen) return false;
    return true;
  }

  /// Sinkronkan sumber gabungan sesudah mutasi antrean (temuan vonis
  /// 2008 #3): utamakan EDIT BEDAH pada anak-anak sumber sesudah trek
  /// berjalan agar audio yang sedang berbunyi tidak pernah disiapkan
  /// ulang oleh aksi antrean. Bangun ulang penuh ([_rebuildTail]) hanya
  /// menjadi jalan jatuh-balik bila keadaan sumber tidak bisa dipetakan
  /// dengan aman (belum ada sumber, indeks pemutar tak selaras, atau
  /// editnya sendiri gugur).
  Future<void> _syncTailAfterMutation(String what, {int growTailBy = 0}) async {
    if (_xfMode) return; // jalur crossfade tidak memakai sumber gabungan
    if (!await _trySyncTailSurgical(what, growTailBy: growTailBy)) {
      // Ronde 8057: generasi BERJALAN diteruskan tanpa klaim — mutasi
      // antrean bukan perintah putar dan tidak boleh membatalkan
      // pembangunan ketukan yang sedang terbang; tetapi bila perintah
      // putar yang lebih baru datang di tengah bangun jatuh-balik ini,
      // bangunnya gugur di titik komit ketimbang memasang jendela
      // berjangkar trek lama di atas sumber perintah pemenang
      // (mekanisme sentak-balik yang sama dengan cabang pulih play()).
      // Hasil FALSE diabaikan di sini: perintah pemenang membangun
      // sumbernya dari antrean mesin yang SUDAH termutasi, jadi sumber
      // akhir tetap mencerminkan mutasi. firstOnly TIDAK dipakai:
      // maksud sinkron ekor adalah memulihkan seluruh ekor jendela
      // hasil mutasi, bukan memotongnya menjadi satu trek.
      await _rebuildTail(gen: _playGen);
    }
  }

  /// Terapkan rencana [planTailEdits] pada sumber yang hidup. Mengembalikan
  /// false (tanpa mengubah apa pun yang tak bisa dipulihkan) bila prasyarat
  /// petanya tidak terpenuhi — pemanggil lalu jatuh ke bangun ulang.
  Future<bool> _trySyncTailSurgical(String what, {int growTailBy = 0}) async {
    final src = _source;
    if (src == null || _sourceTracks.isEmpty) return false;
    final curIdx = _player.currentIndex;
    if (curIdx == null || curIdx < 0 || curIdx >= _sourceTracks.length) {
      return false;
    }
    final cur = engine.current;
    if (cur == null || _sourceTracks[curIdx].key != cur.key) return false;
    final loadedTail = _sourceTracks.sublist(curIdx + 1);
    final eff = engine.effectiveQueue;
    var target = loadedTail.length + growTailBy;
    if (target > eff.length) target = eff.length;
    if (target < 0) target = 0;
    final desired = eff.sublist(0, target);
    final edits = planTailEdits(loadedTail, desired);
    if (edits.isEmpty) return true;
    // Resolusi anak sisipan SEBELUM menyentuh sumber: jendela waktu di
    // mana sumber dan potretnya bisa berbeda pendapat dibuat sekecil
    // mungkin — sesudah ini hanya operasi daftar yang cepat.
    final removes = edits.whereType<TailRemove>().toList()
      ..sort((a, b) => b.tailIndex.compareTo(a.tailIndex));
    final inserts = edits.whereType<TailInsert>().toList()
      ..sort((a, b) => a.tailIndex.compareTo(b.tailIndex));
    final posBefore = _player.position;
    final stateBefore = _player.processingState;
    try {
      final children = <int, AudioSource>{};
      for (final e in inserts) {
        children[e.tailIndex] = await _childFor(e.track);
      }
      // Hapus menurun: indeks anak di bawah titik cabut tidak bergeser,
      // dan indeks trek berjalan (di bawah semua titik cabut) tak berubah.
      for (final e in removes) {
        await src.removeAt(curIdx + 1 + e.tailIndex);
        _sourceTracks.removeAt(curIdx + 1 + e.tailIndex);
      }
      // Sisip menaik pada koordinat tujuan: setiap sisipan menggeser
      // tepat item-item yang memang harus berada sesudahnya.
      for (final e in inserts) {
        await src.insert(curIdx + 1 + e.tailIndex, children[e.tailIndex]!);
        _sourceTracks.insert(curIdx + 1 + e.tailIndex, e.track);
      }
    } catch (err) {
      Observability.instance.log(
        'bedah-antrean-gagal',
        '$what: $err — jatuh ke bangun ulang ekor',
      );
      return false;
    }
    Observability.instance.log(
      'bedah-antrean',
      '$what: ${removes.length} cabut, ${inserts.length} sisip; '
          'posisi ${posBefore.inMilliseconds}→${_player.position.inMilliseconds} ms; '
          'state $stateBefore→${_player.processingState}',
    );
    return true;
  }

  Future<void> removeFromQueue(String section, int index) {
    return _serial(() async {
      Track? removed;
      if (section == 'manual') removed = engine.removeAt(engine.manual, index);
      if (section == 'continuation')
        removed = engine.removeAt(engine.continuation, index);
      if (section == 'autoplay') {
        removed = engine.removeAt(engine.autoplay, index);
        if (removed != null)
          engine.noteSkipped(
            removed,
          ); // L-06: menghapus dari Putar Otomatis = sinyal negatif sesi
      }
      if (removed != null) {
        await _syncTailAfterMutation('hapus dari antrean');
        _emitQueue();
      }
    });
  }

  Future<void> moveInQueue(String section, int from, int to) {
    return _serial(() async {
      if (section == 'manual') engine.moveIn(engine.manual, from, to);
      if (section == 'continuation')
        engine.moveIn(engine.continuation, from, to);
      await _syncTailAfterMutation('geser antrean');
      _emitQueue();
    });
  }

  Future<void> clearQueue() {
    return _serial(() async {
      // v4.4.3: Bersihkan antrean = sesi baru (keputusan pemilik) — bukan
      // sekadar membuang daftar. Mesin mengakhiri sesi (benih = trek berjalan
      // saja, sinyal sesi direset, sessionId naik sehingga batch lama yang
      // masih terbang tertolak), ekor sumber dibangun ulang dari trek
      // berjalan, lalu sambungan disiapkan ulang dari jangkar baru itu.
      if (_xfMode) _xfCancelPreload(); // preload lama ikut terbuang
      engine.resetSessionToCurrent();
      await _syncTailAfterMutation('bersihkan antrean');
      _emitQueue();
      if (engine.current != null && engine.autoplayActive) {
        unawaited(_maybeRefill(force: true));
      }
    });
  }

  Future<void> jumpTo(TrackKey k, {bool preserveSleepTimer = false}) {
    // Lanjut otomatis internal (completed) bukan aksi manual — jangan
    // membatalkan timer tidur saat Putar Otomatis berpindah lagu sendiri.
    // Eskalasi _verifyAdvance juga bukan aksi memilih trek baru: ia
    // MEMPERBAIKI lompatan yang sudah diperintah (dipakai Next manual
    // maupun lanjut otomatis), jadi pemanggil itu menandai
    // [preserveSleepTimer] agar timer tidak batal secara tidak
    // langsung — untuk Next manual timer memang harus tetap hidup
    // (Ronde 8063). Lompatan langsung dari UI tetap aksi memilih
    // trek baru dan membatalkan timer seperti biasa.
    if (!preserveSleepTimer && !_advancingFromCompleted) {
      try {
        onManualPlayAction?.call();
      } catch (_) {}
    }
    final gen = ++_playGen;
    return _runPlay(() async {
      final prev = engine.current;
      // Guard offline SEBELUM mutasi engine (jumpTo membuang item terdahulu —
      // menolak sesudahnya akan merusak sesi).
      if (offlineMode && prev?.key != k) {
        final probe = engine.fullQueue.where((t) => t.key == k).toList();
        if (probe.isNotEmpty && !isOfflinePlayable(probe.first)) {
          notices.add(l10n.noticeOfflineNotDownloaded(probe.first.title));
          return;
        }
      }
      // ADR-002: perintah putar manual = batas lagu.
      if (pendingTransitionMode != null) {
        transitionMode = pendingTransitionMode!;
        pendingTransitionMode = null;
        if (!_xfMode) {
          _xfActiveB = false;
          _stopXfMonitor();
        }
      }
      final target = engine.jumpTo(k);
      if (target == null) return;
      if (prev != null && prev.key != target.key)
        _closeTrackEvent(prev, completed: false);
      _lastPosition = Duration.zero;
      mediaItem.add(_toMediaItem(target));
      _emitQueue();
      if (_xfMode) {
        await _xfPlayCurrent(target, gen: gen);
        if (gen != _playGen) return;
        _trackStartedAt = DateTime.now();
        _emitQueue();
        return;
      }
      await _buildOrNotify(
        fromFullIndex: _currentFullIndex,
        autoplay: true,
        what: '"${target.title}"',
        gen: gen,
        firstOnly: true,
      );
      if (gen != _playGen) return;
      _trackStartedAt = DateTime.now();
      _emitQueue();
      unawaited(_extendSourceToQueue());
    });
  }

  Future<void> setAutoplaySession(bool on) async {
    engine.autoplaySessionOn = on;
    if (!on) {
      engine.clearAutoplay();
      await _syncTailAfterMutation('putar otomatis sesi mati');
    }
    _emitQueue();
    // Menyalakan saklar = perintah eksplisit: isi sambungan SEKARANG juga,
    // jangan menunggu antrean menipis (cacat v4.4.2-2: tanpa paksa, saklar
    // di tengah sesi berantrean panjang tidak mengisi apa pun).
    if (on) unawaited(_maybeRefill(force: true));
  }

  Future<void> setAutoplayGlobal(bool on) async {
    engine.autoplayEnabled = on;
    await db.setPref('playback.autoplay', on);
    if (!on) {
      engine.clearAutoplay();
      await _syncTailAfterMutation('putar otomatis global mati');
    }
    _emitQueue();
    // Menyalakan saklar = perintah eksplisit: isi sambungan SEKARANG juga,
    // jangan menunggu antrean menipis (cacat v4.4.2-2: tanpa paksa, saklar
    // di tengah sesi berantrean panjang tidak mengisi apa pun).
    if (on) unawaited(_maybeRefill(force: true));
  }

  // ---------------- override audio_service ----------------
  /// Earcon (F2 Batch 2): bip pendek 880 Hz milik handler (L-01: handler
  /// satu-satunya pemilik just_audio — earcon memakai pemain ketiganya
  /// sendiri, bukan menyentuh pemain musik).
  AudioPlayer? _earconPlayer;

  Future<void> playEarcon() async {
    try {
      _earconPlayer ??= AudioPlayer(
        useProxyForRequestHeaders: useProxyForRequestHeaders,
      );
      await _earconPlayer!.setAudioSource(
        MemoryAudioSource(
          buildSineWav(milliseconds: 180, frequencyHz: 880, gain: 0.4),
        ),
      );
      await _earconPlayer!.setVolume(0.5);
      await _earconPlayer!.play();
    } catch (_) {
      /* earcon gagal: konfirmasi TTS tetap jalan */
    }
  }

  /// Putar/jeda LANGSUNG dari UI layar (melewati hitungan pola tekan —
  /// pola hanya untuk tombol media headset yang tak terbedakan sumbernya
  /// bila lewat play()/pause() biasa).
  Future<void> playNow() async {
    _patternResolving = true;
    try {
      await play();
    } finally {
      _patternResolving = false;
    }
  }

  Future<void> pauseNow() async {
    _patternResolving = true;
    try {
      await pause();
    } finally {
      _patternResolving = false;
    }
  }

  @override
  Future<void> play() async {
    // Instrumentasi regresi interupsi: siapa pun yang menghidupkan putar
    // tercatat dengan jejak panggil ringkas — lanjut-otomatis yang sah
    // (cabang akhir interupsi) dapat dibedakan dari penghidupan liar.
    Observability.instance.log(
      'main-putar',
      StackTrace.current.toString().split('\n').take(3).join(' <- '),
    );
    // Skema pola tekan (PRD 5.14 A ii): tekan tombol media dihitung dulu —
    // aksi diputuskan saat jendela 500 ms habis (lihat _patternPress).
    if (drivingPatterns && !_patternResolving) {
      _patternPress();
      return;
    }
    // Penjaga sesi kosong (Ronde Bug Notifikasi): perintah putar TANPA trek
    // berjalan — mis. klik sesi media dari kartu sistem yang hidup lebih
    // lama dari sesi aplikasi (pemulihan media sistem / sesi yang gagal
    // dipulihkan) — tidak boleh menyalakan niat putar pada pemain kosong:
    // niat itu menetap playing=true/proses=idle tanpa batas dan sesi media
    // tampil sebagai notifikasi polos "Clai sedang berjalan" tanpa metadata
    // & tanpa kontrol yang bekerja (terbukti emulator P2 + log HP pemilik
    // 2026-11-04: main-putar → playing=true proses=idle, jeda "null").
    if (engine.current == null) {
      Observability.instance.log(
        'main-putar-tanpa-sesi',
        'perintah putar diabaikan: tidak ada trek berjalan',
      );
      return;
    }
    if (_xfMode) {
      // Sesi yang dipulihkan dari penyimpanan (proses baru) belum punya sumber di
      // pemutar — play() polos pada pemutar kosong adalah no-op SENYAP.
      // D-06: bangun ulang HANYA bila sumber belum pernah dibangun pada proses
      // ini. Sesudah sumber hidup, play() redundan cukup melanjutkan pemain
      // yang bersumber — membangun ulang di sini memulai trek dari 0 dan
      // menolkan posisi tersimpan (jebakan stack terbukti di emulator).
      if (!_sourceBuiltThisProcess &&
          _activePlayer.audioSource == null &&
          engine.current != null) {
        final seek = _pendingRestoreSeek ?? Duration.zero;
        try {
          await _xfPlayCurrent(engine.current!, initialPosition: seek);
        } catch (e) {
          // Pembangunan trek pulih gagal (Ronde Bug Notifikasi): jangan
          // biarkan galat lolos tanpa keadaan — catat, segarkan cache trek
          // ini (URL tersimpan bisa jadi biang TYPE_SOURCE), dan kembali
          // TANPA niat putar pada pemain tak bersumber.
          Observability.instance.log(
            'putar-gagal-tanpa-sumber',
            '"${engine.current!.title}" (crossfade): ${describeError(e)}',
          );
          await db.clearStreamCacheFor(engine.current!.key);
          return;
        }
        _pendingRestoreSeek = null;
        if (seek > Duration.zero) {
          try {
            await _activePlayer.seek(seek);
          } catch (_) {}
        }
      } else {
        final audible = _player.audioSource != null ? _player : _playerB;
        // Ronde 8057: cabang putar-di-tempat yang sama cacatnya dengan
        // jalur gapless — pemain crossfade yang completed (trek terakhir
        // tanpa ramp/sambungan) mengabaikan play(); putar-balik ke awal
        // dulu pada pemain yang AKAN berbunyi itu juga (lihat
        // shouldRewindBeforePlay). Hanya trek berjalan yang diputar-balik;
        // mesin ramp/preload tidak disentuh.
        if (shouldRewindBeforePlay(audible.processingState)) {
          try {
            await audible.seek(Duration.zero);
          } catch (_) {
            /* putar-balik gagal: play() tetap dicoba di bawah */
          }
        }
        await audible.play();
      }
      return;
    }
    // Sesi yang dipulihkan dari penyimpanan (proses baru) belum punya sumber di
    // pemutar — play() polos pada pemutar kosong adalah no-op SENYAP: tidak ada
    // galat, tidak ada bunyi, tombol tampak merespons padahal tak terjadi apa
    // pun (terbukti di emulator v4.2). Bangun sumber dari trek berjalan dulu.
    if (_player.audioSource == null && engine.current != null) {
      // Sumber kosong = batas lagu: mode tertunda boleh berlaku sekarang.
      if (pendingTransitionMode != null) {
        transitionMode = pendingTransitionMode!;
        pendingTransitionMode = null;
        if (_xfMode) {
          final seek = _pendingRestoreSeek ?? Duration.zero;
          try {
            await _xfPlayCurrent(engine.current!, initialPosition: seek);
          } catch (e) {
            Observability.instance.log(
              'putar-gagal-tanpa-sumber',
              '"${engine.current!.title}" (crossfade, mode tertunda): ${describeError(e)}',
            );
            await db.clearStreamCacheFor(engine.current!.key);
            return;
          }
          _pendingRestoreSeek = null;
          if (seek > Duration.zero) {
            try {
              await _activePlayer.seek(seek);
            } catch (_) {}
          }
          return;
        }
      }
      final idx = _currentFullIndex;
      if (idx >= 0) {
        // Ronde 8057: pembangunan pulih ini WAJIB bergenerasi +
        // firstOnly, meniru persis situs saudara (jumpTo/playTracks/
        // restoreSleepSession/_previousViaHistory). Dulu keduanya
        // absen: tanpa firstOnly, _buildSource meresolusi jendela
        // penuh (≤60 trek) secara SERIAL sebelum bunyi pertama — Putar
        // pada sesi pulih tampak mati; dan tanpa gen, semua penjaga
        // kalah-ganti mati (stillWanted, titik komit, pasca-pasang),
        // jadi saat bangun yang lambat itu akhirnya selesai ia MEMASANG
        // jendelanya berjangkar di trek pulih tanpa syarat, menimpa apa
        // pun yang sudah dimulai pengguna selama menunggu — trek pulih
        // menyentak balik berbunyi (playWhenReady selamat dari
        // setAudioSource), bahkan melanjutkan di _lastPosition trek
        // lain. Generasi diklaim DI SINI, bukan di kepala play():
        // play() juga melayani lanjut-di-tempat pada sumber hidup,
        // lanjut pasca-interupsi, dan hitungan pola tekan — klaim di
        // kepala akan membatalkan pembangunan sah yang sedang terbang
        // demi perintah yang bahkan tidak membangun sumber.
        // restoreSleepSession mencontohkan pola yang sama: klaim tepat
        // sebelum pembangunan pulihnya, bukan di pintu fungsi.
        final gen = ++_playGen;
        final built = await _buildOrNotify(
          fromFullIndex: idx,
          autoplay: false,
          what: 'sesi yang dipulihkan',
          gen: gen,
          firstOnly: true,
        );
        // Ronde 8057: dikalahkan perintah yang lebih baru selama
        // membangun (_buildOrNotify melaporkan FALSE untuk kelas
        // batal) — pemilik terbaru yang mengatur pemain dari sini.
        // JANGAN lanjut ke pembersihan gagal-total di bawah: stop() +
        // buang cache di sana bisa mematikan sumber perintah pemenang
        // yang baru terpasang & membuang URL segarnya.
        if (gen != _playGen) return;
        // Ronde Bug Notifikasi: pembangunan gagal di SEMUA anak tangga
        // (galatnya sudah dicatat _buildOrNotify) — memanggil
        // _player.play() di titik ini hanya menyalakan niat zombi
        // playing=true/proses=idle yang tak pernah berbunyi (terbukti
        // emulator P1). Berhenti di sini: catat insiden khusus, bersihkan
        // sisa sumber rusak yang mungkin tertinggal terpasang oleh
        // setAudioSource yang gagal, buang cache aliran trek ini (URL
        // tersimpan kedaluwarsa adalah pemicu anak-1 yang terbukti), dan
        // biarkan ketukan berikutnya mencoba segar.
        if (!built) {
          Observability.instance.log(
            'putar-gagal-tanpa-sumber',
            '"${engine.current!.title}": pembangunan sumber sesi pulih gagal total — niat putar tidak dinyalakan',
          );
          try {
            await _player.stop();
          } catch (_) {
            /* pemain memang belum tentu bersumber */
          }
          await db.clearStreamCacheFor(engine.current!.key);
          return;
        }
        // D-06: terapkan posisi tersimpan dengan seek eksplisit — jangan
        // hanya mengandalkan initialPosition setAudioSource (bisa terbuang
        // senyap untuk sumber proxy/resolving; terbukti di emulator:
        // sesi 2:14 mulai lagi dari 0:00).
        final seek = _pendingRestoreSeek;
        _pendingRestoreSeek = null;
        if (seek != null && seek > Duration.zero) {
          try {
            await _player.seek(seek);
          } catch (_) {
            /* posisi awal gagal: putar dari 0 */
          }
          _lastPosition = seek;
        }
        // Ronde 8057: periksa sekali lagi sesudah seek — perintah yang
        // datang selama seek tidak boleh dihidupkan oleh _player.play()
        // penutup di bawah pada sumber pulih yang sudah bukan milik
        // perintah ini (ekor mekanisme sentak-balik yang sama).
        if (gen != _playGen) return;
        // Ronde 8057: firstOnly di atas hanya memasang trek pulih;
        // sisa jendela menyusul di latar, pola tahap-2 yang sama
        // dengan situs saudara — tanpa ini sesi pulih berhenti sesudah
        // satu trek karena jendelanya tak pernah terisi.
        unawaited(_extendSourceToQueue());
      } else {
        // Trek berjalan tidak ditemukan di antrean penuh: tidak ada yang
        // bisa dibangun — sama seperti di atas, jangan nyalakan niat pada
        // pemain kosong.
        Observability.instance.log(
          'putar-gagal-tanpa-sumber',
          '"${engine.current!.title}": trek berjalan di luar antrean — niat putar tidak dinyalakan',
        );
        return;
      }
    }
    // Ronde 8057: putar-balik WAJIB sebelum play() penutup ini bila
    // pemain completed — just_audio mengabaikan play() pada keadaan itu
    // dan trek terakhir antrean tak punya penyelamat indeks-berikutnya,
    // jadi tanpa seek ini tombol Putar mati sesudah lagu terakhir selesai
    // alami (lihat shouldRewindBeforePlay). Sumber yang baru dibangun di
    // cabang sesi-pulih di atas tidak pernah completed di titik ini,
    // jadi penjaga ini hanya menyala pada putar-di-tempat yang parkir.
    if (shouldRewindBeforePlay(_player.processingState)) {
      try {
        await _player.seek(Duration.zero);
      } catch (_) {
        /* putar-balik gagal: play() tetap dicoba di bawah */
      }
    }
    await _player.play();
  }

  /// Jeda dari SISTEM (interupsi fokus, perangkat audio terputus) — bukan
  /// kehendak pengguna: tidak menyentuh hak lanjut-otomatis, tidak dihitung
  /// pola tekan Mode Berkendara (interupsi harus menjeda seketika).
  Future<void> _pauseFromSystem() async {
    // Instrumentasi regresi interupsi: jeda sistem selalu tercatat agar
    // rantai peristiwa → jeda → (lanjut?) dapat diaudit dari log insiden.
    Observability.instance.log(
      'jeda-sistem',
      '"${engine.current?.title}" playingSebelum=${_activePlayer.playing}',
    );
    await _activePlayer.pause();
    _scheduleSave(immediate: true);
  }

  @override
  Future<void> pause() async {
    // Jeda MANUAL (UI, notifikasi, tombol perangkat, perintah suara):
    // lengket — membatalkan hak lanjut-otomatis dari interupsi yang
    // sedang berjalan, dan tidak ada peristiwa pelepasan fokus yang boleh
    // menghidupkan putar sesudahnya (matriks interupsi 2.2).
    _resumeAfterInterruption = false;
    _interruptionPausedAt = null;
    Observability.instance.log(
      'jeda-manual',
      '"${engine.current?.title}" playingSebelum=${_activePlayer.playing}',
    );
    if (drivingPatterns && !_patternResolving) {
      _patternPress();
      return;
    }
    await _activePlayer.pause();
    _scheduleSave(immediate: true);
  }

  /// Pudar tidur lalu jeda (USER-FLOW F-10). F2.5: jalur utama kini
  /// peredupan di bentang AKHIR timer ([beginSleepFade]) — saat timer
  /// berbunyi volume sudah nol, jadi di sini tinggal jeda + pulihkan
  /// faktor. Jalur warisan 30 detik tetap ada sebagai jaring pengaman
  /// bila berbunyi tanpa peredupan pendahulu (mis. durasi trek tak
  /// diketahui pada mode akhir-lagu). Faktor pudar selalu dipulihkan ke
  /// 1 agar putaran berikutnya bersuara penuh. Aman dipanggil saat tidak
  /// berbunyi (langsung jeda).
  Future<void> fadeOutAndPause() async {
    _sleepFadeTimer?.cancel();
    _sleepFadeTimer = null;
    if (_sleepFaded || _sleepFade <= 0.001) {
      _sleepFaded = false;
      await pause();
      _sleepFade = 1.0;
      await _applyVolume();
      return;
    }
    if (!_activePlayer.playing) {
      await pause();
      return;
    }
    if (_sleepFade < 0.999) {
      // Peredupan pendahulu sedang berjalan saat timer berbunyi lebih
      // dulu: selesaikan singkat (≤1,5 detik) dari nilai sekarang ke 0.
      final from = _sleepFade;
      for (var i = 1; i <= 5; i++) {
        _sleepFade = from * (1 - i / 5);
        await _applyVolume();
        await Future<void>.delayed(const Duration(milliseconds: 300));
        if (!_activePlayer.playing) break;
      }
      await pause();
      _sleepFade = 1.0;
      await _applyVolume();
      return;
    }
    for (var i = 1; i <= 30; i++) {
      _sleepFade = 1 - i / 30;
      await _applyVolume();
      await Future<void>.delayed(const Duration(seconds: 1));
      if (!_activePlayer.playing) break; // pengguna menjeda di tengah pudar
    }
    await pause();
    _sleepFade = 1.0;
    await _applyVolume();
  }

  /// D-32: aksi kustom notifikasi — sakelar suka trek berjalan, disambungkan
  /// app ke LibraryController lewat [onToggleLikeRequest].
  @override
  Future<void> customAction(String name, [Map<String, dynamic>? extras]) async {
    if (name == 'toggleLike') {
      try {
        onToggleLikeRequest?.call();
      } catch (_) {}
      return;
    }
    await super.customAction(name, extras);
  }

  @override
  Future<void> stop() async {
    _saveTimer?.cancel();
    _watchdogTimer?.cancel();
    _stallTimer?.cancel();
    _duckRampTimer?.cancel();
    _stopXfMonitor();
    await _player.stop();
    await _playerB.stop();
    // Ronde Kresek: handler berhenti = semua efek native dilepas (EQ +
    // Visualizer kedua pemain), jangan biarkan instance menempel ke sesi
    // pemain yang sudah berhenti.
    await _fx.fxReleaseAll();
    _fxTracker.clear();
    await super.stop();
  }

  @override
  Future<void> seek(Duration position) => _activePlayer.seek(position);

  @override
  Future<void> skipToNext() async {
    // Ronde 8063: navigasi trek di dalam sesi berjalan — timer tidur
    // aktif TIDAK dibatalkan (kait khusus navigasi; lihat
    // SleepService.handleManualTrackSkip).
    try {
      onManualTrackSkip?.call();
    } catch (_) {}
    // ADR-002: perintah manual = batas lagu. Bila alih ke gapless, _player
    // menganggur (crossfade memakai pemain aktif lain) — catat status putar
    // agar sesudah lompat, putaran dipulihkan (tanpa ini Next berakhir sunyi).
    bool? resumeAfterSkip;
    if (pendingTransitionMode != null) {
      resumeAfterSkip = _activePlayer.playing;
      transitionMode = pendingTransitionMode!;
      pendingTransitionMode = null;
      if (!_xfMode) {
        _xfActiveB = false;
        _stopXfMonitor();
      }
    }
    if (_xfMode) {
      await _xfSkipNext();
      return;
    }
    // Ronde 8057: Berikutnya adalah perintah putar manual — klaim
    // generasi baru seperti jumpTo/playTracks. Klaim diletakkan
    // sesudah pintu crossfade agar jalur xf tidak berubah. Tanpa
    // klaim ini, bangun ekor di bawah berjalan tanpa generasi:
    // tekanan Berikutnya yang beruntun masing-masing membayar bangun
    // jendela penuh yang tidak pernah bisa dikalahkan, sehingga
    // responsnya hanya terasa kumulatif, dan bangun yang selesai
    // belakangan bisa memasang jendela usang di atas perintah yang
    // lebih baru. Dengan klaim ini, tekanan/perintah yang lebih baru
    // menggugurkan bangun tekanan sebelumnya di titik komit.
    final gen = ++_playGen;
    final cur = engine.current;
    final curKey = cur?.key;
    final nextKey =
        engine.effectiveQueue.isNotEmpty ? engine.effectiveQueue.first.key : null;
    // Ronde 8063: tandai lompatan perintah ini agar _onIndexChanged
    // tidak membacanya sebagai akhir alami (lihat _skipTargetKey).
    // Lewati-galat internal (_onPlayerError) ikut tertandai — trek
    // yang gagal memang bukan akhir alami juga.
    if (nextKey != null) {
      _skipTargetKey = nextKey;
      _skipTargetAt = DateTime.now();
    }
    // Prev/next manual: skip < 30 dtk yang diinisiasi pengguna pada trek berjalan = sinyal negatif bila melompat.
    if (cur != null &&
        _player.position < const Duration(seconds: 30) &&
        _player.position > const Duration(seconds: 3)) {
      engine.noteSkipped(cur);
    }
    if (engine.repeat == RepeatMode.one) {
      // Repeat-satu dilepas sementara untuk lompatan eksplisit.
      await _player.seek(Duration.zero);
    }
    final hasNext =
        _player.hasNext ||
        engine.effectiveQueue.length >
            _sourceTracks.length - (_player.currentIndex ?? 0) - 1;
    if (_player.hasNext) {
      await _player.seekToNext();
    } else if (engine.effectiveQueue.isNotEmpty) {
      // Ronde 8057: bangun bergenerasi (klaim di atas); firstOnly
      // SENGAJA tidak dipakai — maksud bangun di sini adalah
      // mematerialkan trek berikutnya ke dalam jendela agar
      // seekToNext punya tujuan; jendela satu trek akan membuat
      // seekToNext tanpa tujuan dan menyerahkan lompatan ke eskalasi
      // _verifyAdvance 1,5 detik kemudian. Bila bangun dikalahkan
      // perintah yang lebih baru (FALSE), jangan seek di atas sumber
      // yang bukan milik tekanan ini — pemilik terbaru yang
      // memajukan putaran dengan caranya sendiri.
      if (await _rebuildTail(gen: gen)) {
        await _player.seekToNext();
      }
    } else {
      // Tidak ada berikutnya & Putar Otomatis aktif: paksa isi ulang lalu putar.
      await _maybeRefill();
      if (engine.effectiveQueue.isNotEmpty) {
        // Ronde 8057: disiplin yang sama persis dengan cabang di atas
        // (generasi tekanan ini, tanpa firstOnly, seek hanya bila
        // bangun terkomit).
        if (await _rebuildTail(gen: gen)) {
          await _player.seekToNext();
        }
      }
    }
    if (!hasNext && engine.effectiveQueue.isEmpty)
      notices.add(l10n.noticeQueueEnded);
    // Verifikasi lompatan (cacat vonis perangkat Tahap 3): satu
    // pencetan Next WAJIB berarti satu lompatan — bila trek berjalan
    // belum berpindah sesudah jeda singkat, eskalasi ke jumpTo
    // (lihat _verifyAdvance).
    if (curKey != null && nextKey != null && nextKey != curKey) {
      _verifyAdvance(curKey, nextKey, 'skip-manual');
    }
    if (resumeAfterSkip == true && !_player.playing) await _player.play();
  }

  @override
  Future<void> skipToPrevious() async {
    // Ronde 8063: navigasi trek di dalam sesi berjalan — timer tidur
    // aktif TIDAK dibatalkan (kait khusus navigasi; lihat
    // SleepService.handleManualTrackSkip).
    try {
      onManualTrackSkip?.call();
    } catch (_) {}
    // ADR-002: perintah manual = batas lagu (pemulihan putar seperti skipToNext).
    bool? resumeAfterSkip;
    if (pendingTransitionMode != null) {
      resumeAfterSkip = _activePlayer.playing;
      transitionMode = pendingTransitionMode!;
      pendingTransitionMode = null;
      if (!_xfMode) {
        _xfActiveB = false;
        _stopXfMonitor();
      }
    }
    if (_xfMode) {
      await _xfSkipPrevious();
      return;
    }
    // Konvensi (PRD 5.4): > 3 dtk → ulang dari awal; ≤ 3 dtk → trek sebelumnya.
    if (_player.position > const Duration(seconds: 3)) {
      await _player.seek(Duration.zero);
    } else {
      switch (gaplessPreviousStep(
        hasPreviousInWindow: _player.hasPrevious,
        hasSessionHistory: engine.played.isNotEmpty,
      )) {
        case GaplessPreviousStep.windowPrevious:
          await _player.seekToPrevious();
        case GaplessPreviousStep.historyPrevious:
          // Ronde 8055: trek yang baru didengar terdampar di luar jendela
          // sumber (dibangun ulang berjangkar di trek berjalan) tetapi sesi
          // mengingatnya — mundur lewat riwayat, bukan mengulang trek ini.
          await _previousViaHistory();
        case GaplessPreviousStep.restartCurrent:
          await _player.seek(Duration.zero);
      }
    }
    if (resumeAfterSkip == true && !_player.playing) await _player.play();
  }

  /// Mundur gapless lewat riwayat sesi (Ronde 8055): dipakai saat trek yang
  /// baru saja didengar tidak lagi berada di jendela sumber berjalan.
  /// Langkahnya meniru [jumpTo] — guard offline SEBELUM mutasi (restorePlayed
  /// mengubah sesi; menolak sesudahnya akan merusak sesi), generasi putar
  /// baru agar pembangunan usang gugur di titik komit (Ronde 8054), bangun
  /// ulang dari trek hasil pulih lalu perluas jendela di latar. Status putar
  /// DIPERTAHANKAN (autoplay: false): seekToPrevious pun tidak mengubahnya —
  /// Mundur saat dijeda tetap dijeda, saat berbunyi tetap berbunyi.
  Future<void> _previousViaHistory() async {
    final target = engine.played.last;
    if (offlineMode && !isOfflinePlayable(target)) {
      await _player.seek(Duration.zero);
      return;
    }
    final gen = ++_playGen;
    final prev = engine.current;
    engine.restorePlayed(engine.played.length - 1);
    final restored = engine.current;
    if (restored == null) return;
    if (prev != null && prev.key != restored.key) {
      _closeTrackEvent(prev, completed: false);
    }
    _pendingRestoreSeek = null; // navigasi eksplisit: seek pulih batal
    _lastPosition = Duration.zero;
    mediaItem.add(_toMediaItem(restored));
    _emitQueue();
    await _buildOrNotify(
      fromFullIndex: _currentFullIndex,
      autoplay: false,
      what: '"${restored.title}"',
      gen: gen,
      firstOnly: true,
    );
    if (gen != _playGen) return;
    _trackStartedAt = DateTime.now();
    _emitQueue();
    unawaited(_extendSourceToQueue());
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    _pendingRestoreSeek = null; // lompatan eksplisit: seek pulih batal
    final full = engine.fullQueue;
    if (index < 0 || index >= full.length) return;
    await jumpTo(full[index].key);
  }

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode mode) async {
    engine.repeat = switch (mode) {
      AudioServiceRepeatMode.one => RepeatMode.one,
      AudioServiceRepeatMode.all ||
      AudioServiceRepeatMode.group => RepeatMode.all,
      AudioServiceRepeatMode.none => RepeatMode.off,
    };
    await _activePlayer.setLoopMode(
      engine.repeat == RepeatMode.one ? LoopMode.one : LoopMode.off,
    );
    playbackState.add(playbackState.value.copyWith(repeatMode: mode));
    _emitQueue();
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode mode) async {
    // Kontrol sistem hanya mengenal acak/mati: mode smart dipertahankan bila
    // sistem meminta 'acak' (sakelar Smart Shuffle di UI yang mengelolanya).
    if (mode == AudioServiceShuffleMode.none) {
      engine.shuffle = ShuffleMode.off;
    } else if (engine.shuffle != ShuffleMode.smart) {
      engine.shuffle = ShuffleMode.pure;
    }
    playbackState.add(playbackState.value.copyWith(shuffleMode: mode));
    _emitQueue();
  }

  // ---------------- pemulihan L-10 ----------------
  Future<void> _onPlayerError(Object e) async {
    // v4.3: galat interupsi (muat disela) bukan kegagalan putar — diamkan.
    if (isInterruptionError(e)) return;
    final cur = engine.current;
    if (cur == null) return;
    GateMetrics.instance.recordFailure();
    if (_xfMode) {
      // Jalur crossfade: sumber gabungan tidak ada — pemulihan lewat putar
      // ulang trek berjalan (≤2×), lalu lewati seperti jalur gapless.
      // Ronde 8059: coba-ulang lewat _xfPlayCurrent kini MENAIKI TANGGA
      // di dalamnya (anak pemenang lengket berputar ke cadangan), jadi
      // cabang ini tidak butuh langkah maju-tangga terpisah seperti
      // cabang gapless — satu putaran tangga penuh terjadi per coba.
      // Galat interupsi sudah disaring di kepala fungsi ini dan jeda/
      // berhenti oleh pengguna tidak membangkitkan peristiwa galat,
      // jadi cadangan tidak pernah terpicu oleh aksi bukan-sumber.
      Observability.instance.log(
        'player-error-xf',
        '${cur.title}: ${describeError(e)}',
      );
      final attemptKey = cur.key.toString();
      final attempts = (_urlAttempts[attemptKey] ?? 0) + 1;
      _urlAttempts[attemptKey] = attempts;
      if (attempts <= 2 && cur.providerId != 'local') {
        // Sama seperti cabang gapless di bawah: trek DIRECT-1 yang
        // ditolak edge dilaporkan dulu (Tahap 3) — tanpa ini, putar
        // ulang crossfade hanya mengambil URL (tersabotase/ditolak)
        // yang sama dari cache resolver dan pemulihan DIRECT tak
        // pernah menyala. Terbukti di emulator build 6030.
        if (_resolvedDirect[cur.key] == true) directRejectedHook?.call(cur);
        await db.clearStreamCache();
        try {
          await _xfPlayCurrent(cur);
          return;
        } catch (_) {
          /* jatuh ke lewati */
        }
      }
      _consecutiveFailures++;
      notices.add(l10n.noticeSkippedUnplayable(cur.title));
      if (_consecutiveFailures >= 3) {
        notices.add(l10n.noticeAutoStop);
        await _activePlayer.pause();
        return;
      }
      await _xfSkipNext();
      return;
    }
    Observability.instance.log(
      'player-error',
      '${cur.title}: ${describeError(e)}',
    );
    final attemptKey = cur.key.toString();
    final attempts = (_urlAttempts[attemptKey] ?? 0) + 1;
    _urlAttempts[attemptKey] = attempts;
    if (attempts <= 2 && cur.providerId != 'local') {
      // Trek DIRECT-1 yang ditolak edge: laporkan dulu agar resolusi
      // ulang menyegarkan sesi minter SATU kali (Tahap 3) — bukan sekadar
      // URL segar dari sesi yang sama-sama ditolak.
      if (_resolvedDirect[cur.key] == true) directRejectedHook?.call(cur);
      // Segarkan URL (buang cache) lalu coba lagi trek yang sama.
      await db.clearStreamCache();
      try {
        // Ronde 8057: generasi BERJALAN diteruskan tanpa klaim —
        // pemulihan galat tidak boleh mengalahkan ketukan pengguna
        // yang lebih baru; bila ketukan itu datang di tengah bangun,
        // bangun gugur (FALSE) dan pemulihan menyerahkan pemain ke
        // perintah pemenang alih-alih memutar sumber lama di sini.
        // firstOnly TIDAK dipakai: coba-ulang harus memulihkan ekor
        // utuh seperti sebelumnya. Galat bangun lain tetap dilempar
        // _rebuildTail dan tertangkap di bawah seperti perilaku lama.
        if (!await _rebuildTail(gen: _playGen)) return;
        await _player.play();
        return;
      } catch (_) {
        /* jatuh ke anak tangga berikutnya */
      }
    }
    // v4.2: sebelum menyerah pada trek ini, NAIKKAN TANGGA — pemenang lengket pindah
    // ke anak berikutnya dan trek dicoba lagi di sana (maks 2 kenaikan per episode
    // trek; pembangunan ekornya sendiri kembali menaiki tangga dari anak baru itu).
    final advances = _ladderAdvances[attemptKey] ?? 0;
    if (attempts > 2 &&
        advances < LoadLadder.rungCount - 1 &&
        cur.providerId != 'local') {
      _ladderAdvances[attemptKey] = advances + 1;
      final from = _ladder.stickyRung;
      final to = _ladder.advance();
      _urlAttempts[attemptKey] = 0; // anggaran coba segar di anak baru
      Observability.instance.log(
        'tangga-muat-maju',
        '"${cur.title}": anak ${from + 1} (${LoadLadder.rungLabel(from)}) → anak ${to + 1} (${LoadLadder.rungLabel(to)}) setelah galat putar berulang',
      );
      notices.add(l10n.noticeTryingOtherPath(cur.title));
      await db.clearStreamCache();
      try {
        // Ronde 8057: disiplin yang sama persis dengan coba-ulang
        // pertama di atas (generasi berjalan tanpa klaim, tanpa
        // firstOnly, FALSE = pemain sudah milik perintah yang lebih
        // baru sehingga coba-ulang tangga berhenti di sini).
        if (!await _rebuildTail(gen: _playGen)) return;
        await _player.play();
        return;
      } catch (_) {
        /* jatuh ke lewati */
      }
    }
    _consecutiveFailures++;
    notices.add(l10n.noticeSkippedUnplayable(cur.title));
    if (_consecutiveFailures >= 3) {
      notices.add(l10n.noticeAutoStop);
      await _player.pause();
      return;
    }
    await skipToNext();
  }

  @override
  Future<void> onTaskRemoved() async {
    // Layanan tetap hidup saat aplikasi ditutup dari recents selama memutar (perilaku pemutar musik).
    if (!_activePlayer.playing) await stop();
  }
}

void unawaited(Future<void> f) {
  f.catchError((_) => null);
}
