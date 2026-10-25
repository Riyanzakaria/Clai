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
import '../services/audio_fx_service.dart';
import '../services/gate_metrics.dart';
import '../services/observability.dart';
import '../services/sys_channel.dart';
import 'crossfade.dart';
import 'interruption_policy.dart';
import 'load_ladder.dart';
import 'queue_engine.dart';
import 'similarity.dart';
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

  /// Kait F2: aksi putar manual (batalkan timer tidur) & akhir lagu alami.
  VoidCallback? onManualPlayAction;
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
    // Estimator Visualizer mengikuti sakelar: nyala → ukur sesi berjalan;
    // mati → hentikan (tidak ada sampel baru yang teratribusi).
    for (final id in audioSessionIds) {
      if (id == null) continue;
      if (on) {
        final ok = await _fx.visStart(id);
        if (!ok) {
          Observability.instance.log(
            'vis-gagal-mulai',
            'sesi $id (sakelar normalisasi): ${_fx.lastVisError ?? 'alasan tak terbaca'}',
          );
        }
      } else {
        await _fx.visStop(id);
      }
    }
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
    final keys = <TrackKey>{};
    for (final section in [
      'seeds',
      'manual',
      'continuation',
      'autoplay',
      'played',
    ]) {
      final raw = snap[section];
      if (raw is List) {
        for (final e in raw) {
          if (e is Map) keys.add(TrackKey(e['p'] as String, e['i'] as String));
        }
      }
    }
    final cur = snap['currentRef'] as String?;
    if (cur != null && cur.contains('|')) {
      keys.add(
        TrackKey(cur.split('|')[0], cur.split('|').sublist(1).join('|')),
      );
    }
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
      await _xfPlayCurrent(engine.current!);
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
    resolveAdaptive: (t) async {
      final info = await provider.resolveStream(t, effectiveQuality);
      if (info.bitrate != null) _resolvedBitrates[t.key] = info.bitrate!;
      return info;
    },
    resolveMuxed: (t) => provider.resolveMuxedFallback(t),
    tagFor: _toMediaItem,
    isLocal: (t) => t.providerId == 'local',
    // F2 Batch 2: trek terunduh diputar dari berkas lokalnya (juga saat offline).
    localFileFor: (t) => downloadedPaths[t.key],
  );
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
  Future<void> _chain = Future.value();

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

    // F2 Batch 2: sesi audio baru (pemain mulai berbunyi) → terapkan EQ
    // tersimpan + mulai Visualizer bila normalisasi nyala.
    for (final p in [_player, _playerB]) {
      p.androidAudioSessionIdStream.listen((id) async {
        if (id == null) return;
        _sessionAppearances.add(id);
        await _applyEqToSession(id);
        if (normalizationOn) {
          final ok = await _fx.visStart(id);
          if (!ok) {
            Observability.instance.log(
              'vis-gagal-mulai',
              'sesi $id: ${_fx.lastVisError ?? 'alasan tak terbaca'}',
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
      final keys = <TrackKey>{};
      for (final section in ['seeds', 'manual', 'continuation', 'autoplay']) {
        for (final e in (snap[section] as List)) {
          if (e is Map) keys.add(TrackKey(e['p'] as String, e['i'] as String));
        }
      }
      final cur = snap['currentRef'] as String?;
      if (cur != null && cur.contains('|')) {
        keys.add(
          TrackKey(cur.split('|')[0], cur.split('|').sublist(1).join('|')),
        );
      }
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
  Future<void> _buildOrNotify({
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
    } catch (e, st) {
      // v4.3: muat yang disela muat lebih baru = perilaku normal, BUKAN insiden.
      if (isInterruptionError(e)) return;
      // v4.4: pembangunan yang dikalahkan ketukan lebih baru juga normal.
      if (e is _Superseded) return;
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
          children.add(await _ladder.childFor(window[i], rung, strict: i == 0));
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
      onRungFailed: (rung, e, st) {
        // v4.3: anak tangga yang gugur karena disela muat lain bukan kegagalan.
        if (isInterruptionError(e)) return;
        if (e is _Superseded) return;
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
      if (prev != null) _closeTrackEvent(prev, completed: true);
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

  void _closeTrackEvent(Track t, {required bool completed}) {
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
    if (completed) {
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
    try {
      await _rebuildTail();
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
  }

  /// Batalkan preload/ramp yang berjalan (kepala antrean berubah / perintah manual).
  void _xfCancelPreload() {
    _xfRampTimer?.cancel();
    _xfRampTimer = null;
    _xfRamping = false;
    if (_xfPreloaded != null) {
      _idlePlayer.pause();
      _xfPreloaded = null;
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
  Future<void> _xfPlayCurrent(
    Track t, {
    Duration initialPosition = Duration.zero,
  }) async {
    await _xfResetPlayers();
    _xfPreloadFailedKey = null;
    await _gainFor(t);
    final child = await _ladder.childFor(t, _ladder.stickyRung, strict: true);
    _sourceBuiltThisProcess = true;
    await _activePlayer.setAudioSource(child, initialPosition: initialPosition);
    await _activePlayer.setLoopMode(
      engine.repeat == RepeatMode.one ? LoopMode.one : LoopMode.off,
    );
    await _applyVolume();
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
    if (remaining.inMilliseconds <= rampMs) _xfStartRamp();
  }

  Future<void> _xfPreload(Track next) async {
    if (_xfPreloaded != null || _xfRamping) return;
    if (_xfPreloadInFlightKey != null) return; // satu preload pada satu waktu
    _xfPreloadInFlightKey = next.key;
    try {
      await _gainFor(next);
      final child = await _ladder.childFor(
        next,
        _ladder.stickyRung,
        strict: true,
      );
      // Kepala antrean bisa berubah selama resolusi — verifikasi ulang.
      if (_xfHead?.key != next.key) return;
      await _idlePlayer.setAudioSource(child);
      await _idlePlayer.setVolume(0);
      _xfPreloaded = next;
    } catch (e) {
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
    if (next == null || _xfRamping) return;
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
      // Kait F2 (Lanjut Besok): aksi putar manual membatalkan timer tidur
      // yang masih berjalan — kecuali aksi resume (flag satu-kali di layanan).
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
        await _xfPlayCurrent(engine.current!);
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
        await _xfPlayCurrent(seed);
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

  Future<void> _rebuildTail() async {
    if (_xfMode) return; // jalur crossfade tidak memakai sumber gabungan
    // Pertahankan trek berjalan & posisinya; sumber dibangun ulang dari current.
    final pos = _player.position;
    final wasPlaying = _player.playing;
    final idx = _currentFullIndex;
    if (idx < 0) return;
    _lastPosition = pos;
    await _buildSource(
      fromFullIndex: idx,
      autoplay: wasPlaying,
      what: 'bangun ulang ekor antrean',
    );
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
      await _rebuildTail();
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

  Future<void> jumpTo(TrackKey k) {
    // Lanjut otomatis internal (completed) bukan aksi manual — jangan
    // membatalkan timer tidur saat Putar Otomatis berpindah lagu sendiri.
    if (!_advancingFromCompleted) {
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
        await _xfPlayCurrent(target);
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
        await _xfPlayCurrent(engine.current!, initialPosition: seek);
        _pendingRestoreSeek = null;
        if (seek > Duration.zero) {
          try {
            await _activePlayer.seek(seek);
          } catch (_) {}
        }
      } else {
        final audible = _player.audioSource != null ? _player : _playerB;
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
          await _xfPlayCurrent(engine.current!, initialPosition: seek);
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
        await _buildOrNotify(
          fromFullIndex: idx,
          autoplay: false,
          what: 'sesi yang dipulihkan',
        );
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

  /// Pudar tidur: volume turun linear ke 0 selama 30 detik lalu jeda
  /// (USER-FLOW F-10; Sapuan T-10 — implementasi F2 Batch 2 memakai 5 detik,
  /// menyimpang tercatat yang kini ditutup di kode). Faktor pudar dipulihkan
  /// ke 1 agar putaran berikutnya bersuara penuh. Aman dipanggil saat tidak
  /// berbunyi (langsung jeda).
  Future<void> fadeOutAndPause() async {
    if (!_activePlayer.playing) {
      await pause();
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
    await super.stop();
  }

  @override
  Future<void> seek(Duration position) => _activePlayer.seek(position);

  @override
  Future<void> skipToNext() async {
    try {
      onManualPlayAction?.call();
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
    final cur = engine.current;
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
      await _rebuildTail();
      await _player.seekToNext();
    } else {
      // Tidak ada berikutnya & Putar Otomatis aktif: paksa isi ulang lalu putar.
      await _maybeRefill();
      if (engine.effectiveQueue.isNotEmpty) {
        await _rebuildTail();
        await _player.seekToNext();
      }
    }
    if (!hasNext && engine.effectiveQueue.isEmpty)
      notices.add(l10n.noticeQueueEnded);
    if (resumeAfterSkip == true && !_player.playing) await _player.play();
  }

  @override
  Future<void> skipToPrevious() async {
    try {
      onManualPlayAction?.call();
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
    } else if (_player.hasPrevious) {
      await _player.seekToPrevious();
    } else {
      await _player.seek(Duration.zero);
    }
    if (resumeAfterSkip == true && !_player.playing) await _player.play();
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
      Observability.instance.log(
        'player-error-xf',
        '${cur.title}: ${describeError(e)}',
      );
      final attemptKey = cur.key.toString();
      final attempts = (_urlAttempts[attemptKey] ?? 0) + 1;
      _urlAttempts[attemptKey] = attempts;
      if (attempts <= 2 && cur.providerId != 'local') {
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
      // Segarkan URL (buang cache) lalu coba lagi trek yang sama.
      await db.clearStreamCache();
      try {
        await _rebuildTail();
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
        await _rebuildTail();
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
