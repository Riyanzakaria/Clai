/// Layanan jalur DIRECT-1 (Tahap 3, Mesin Penyeberangan 2.0) — orkestrasi
/// produksi konstruksi E3 yang LULUS lagu utuh di Tahap 2:
///
///   konteks watch (sts + visitorData + jsUrl, ter-cache)
///     → sesi minter BotGuard dari halaman yang sama (TTL-sadar)
///     → resolusi player WEB_REMIX membawa sts (tanpa token dulu;
///       direktur-2 dengan token player terikat visitorData bila perlu)
///     → pilih format per tingkat kualitas → decipher EJS worker-per-solve
///       bila tercipher (atau transformasi `n` untuk URL langsung)
///     → tempel `&pot=` (token terikat VIDEO_ID) + cpn → StreamInfo
///       berpasangan UA Firefox/140 untuk pipa putar yang ada.
///
/// Semua kegagalan bersifat LOKAL pada jalur ini: metode publik tidak
/// pernah melempar — pemanggil (resolveStream) jatuh ke rantai warisan
/// itag-18/adaptif lama tanpa jeda/error yang terlihat pengguna.
///
/// Penanganan error (pola upstream + instruksi riyan 2026-11-08 23:00):
///  - minter gagal cetak/kedaluwarsa → sesi disegarkan SATU kali, cetak ulang;
///  - URL ditolak edge (dilaporkan pipa putar lewat [markFetchRejected]):
///    penolakan ke-1 membuang cache trek + menandai sesi basi (resolusi
///    berikutnya menyegarkan sesi sekali); penolakan ke-2 mengecualikan
///    trek ±5 menit (pola pengecualian per-video upstream);
///  - solver gagal (termasuk generasi basi) → jalur gugur bersih, tercatat;
///  - ≥3 kegagalan beruntun lintas trek → jalur didemosi 10 menit (pola
///    bucket kesehatan direktur klien upstream); sukses meng-nol-kan;
///  - kill-switch pref `playback.direct1` (bawaan menyala).
///
/// Keterukuran: setiap hasil dicatat lewat [onEvent] ke log insiden lokal
/// (`direct-ok`, `direct-jatuh` + sebab, `direct-sesi-segar`,
/// `direct-trek-dikecualikan`, `direct-demosi`, `direct-pulih`) dan
/// diringkas di [stats] untuk layar Diagnostik. Nilai token/visitorData
/// TIDAK pernah masuk log/statistik — hanya nama, panjang, itag, bitrate.
///
/// SABR (E1) TIDAK di-porting ke produksi — cadangan terdokumentasi saja.
library;

import 'dart:async';

import '../domain/models.dart';
import '../providers/ytmusic/direct_types.dart';
import 'direct_web_engine.dart';

typedef DirectWatchFetcher = Future<WatchPageData> Function(String videoId);
typedef DirectFormatsResolver = Future<DirectResolveData> Function(
  Track track, {
  String? visitorData,
  int? signatureTimestamp,
  String? playerPoToken,
});
typedef DirectTextFetcher = Future<String?> Function(String url);
typedef DirectSessionBuilder = Future<DirectSessionResult> Function(String watchHtml);
typedef DirectTokenMinter = Future<DirectMintResult> Function(String videoId);
typedef DirectSolver = Future<EjsSolveOutcome> Function({
  required String playerJs,
  List<String> nChallenges,
  List<String> sigChallenges,
  String? playerKey,
});
typedef DirectEnabledReader = Future<bool> Function();
typedef DirectEventSink = void Function(String kind, String detail);

/// Sebab gugurnya SATU percobaan jalur DIRECT (untuk log + statistik).
enum DirectFailCause {
  disabled('kill-switch'),
  demoted('demosi-kesehatan'),
  excluded('trek-dikecualikan'),
  context('konteks-watch'),
  session('sesi-minter'),
  resolution('resolusi-player'),
  noFormat('tanpa-format'),
  solver('solver'),
  minter('minter'),
  rejected('url-ditolak-403'),
  timeout('lewat-waktu'),
  engine('mesin-webview'),
  unknown('lainnya');

  const DirectFailCause(this.label);
  final String label;
}

/// Mode sabotase untuk pementasan bukti di Diagnostik (in-memori saja,
/// tidak pernah persisten): merusak sig URL hasil resolusi berikutnya
/// (sekali) atau setiap resolusi (selalu) → edge menolak 403.
enum DirectSabotage { off, once, always }

/// Ringkasan kesehatan jalur untuk layar Diagnostik — data, bukan tebakan.
class DirectPathStats {
  int okCount = 0;
  int fallbackCount = 0;
  final Map<String, int> fallbackByCause = {};
  String? lastPath; // 'direct' | 'legacy'
  String? lastCause;
  int? lastItag;
  int? lastBitrate;
  int? lastContentLength;
  String? lastTrackId;
  String? lastTitle;
  String? lastError;
  DateTime? lastAt;
  int consecutiveFailures = 0;
  DateTime? cooldownUntil;

  bool get inCooldown =>
      cooldownUntil != null && DateTime.now().isBefore(cooldownUntil!);
}

/// Potong teks galat untuk log (satu baris, maks 160 karakter).
String _clip(String s) {
  final oneLine = s.replaceAll('\n', ' ');
  return oneLine.length <= 160 ? oneLine : '${oneLine.substring(0, 160)}…';
}

class _AttemptOutcome {
  final StreamInfo? info;
  final DirectFailCause? cause;

  /// Rincian teknis kegagalan (teks galat / langkah terakhir) — hanya
  /// untuk log insiden + Diagnostik, tidak pernah ke UI pengguna.
  final String? debug;

  /// true bila percobaan dilewati gerbang (kill-switch/demosi/
  /// pengecualian) — dicatat sebagai lewatan, BUKAN kegagalan kesehatan.
  final bool isSkip;
  const _AttemptOutcome.ok(this.info) : cause = null, debug = null, isSkip = false;
  const _AttemptOutcome.fail(this.cause, {this.debug}) : info = null, isSkip = false;
  const _AttemptOutcome.skip(this.cause) : info = null, debug = null, isSkip = true;
}

class DirectStreamService {
  /// Kunci pref kill-switch jalur (bawaan: menyala).
  static const killSwitchPrefKey = 'playback.direct1';

  static const _contextTtl = Duration(minutes: 30);
  static const _exclusionTtl = Duration(minutes: 5);
  static const _cooldownTtl = Duration(minutes: 10);
  static const _demoteThreshold = 3;
  static const _totalBudget = Duration(seconds: 75);
  static const _sessionSafetyMarginSecs = 600;

  final DirectWatchFetcher _fetchWatch;
  final DirectFormatsResolver _resolveFormats;
  final DirectTextFetcher _fetchText;
  final DirectSessionBuilder _buildSession;
  final DirectTokenMinter _mintToken;
  final DirectSolver _solve;
  final DirectEnabledReader _readEnabled;
  final DirectEventSink? _onEvent;
  final DateTime Function() _now;

  final DirectPathStats stats = DirectPathStats();

  /// Mode sabotase pementasan bukti (diatur dari Diagnostik saja).
  DirectSabotage sabotage = DirectSabotage.off;

  /// Dipanggil saat sebuah trek yang URL DIRECT-nya sempat ditolak
  /// kemudian berhasil teresolusi DIRECT lagi (jalur terbukti pulih).
  /// Bootstrap mengkabelnya ke reset pemenang lengket tangga muat —
  /// tanpa ini satu 403 transien mendemosi jalur adaptif satu sesi.
  void Function()? onRecovered;

  /// Trek dengan penolakan yang menunggu bukti pulih (untuk
  /// [onRecovered]). Terpisah dari _trackSuspects: status tersangka
  /// eskalasi TIDAK dibersihkan oleh keberhasilan resolusi.
  final Set<String> _recoveryPending = {};

  WatchPageData? _context;
  DateTime? _contextAt;
  DirectSessionResult? _session;
  DateTime? _sessionBornAt;
  bool _sessionStale = true;
  final Map<String, String> _playerJsByUrl = {};
  final Map<String, String> _solveCache = {};
  final Map<String, StreamInfo> _memoryCache = {};
  String? _lastSolveError;
  final Map<String, DateTime> _trackExclusions = {};

  /// Trek tersangka penolakan (kunci trek → kapan ditandai). Sengaja
  /// TIDAK dibersihkan oleh resolusi yang sukses: resolusi bukan bukti
  /// putar — hanya penolakan kedua (atau kedaluwarsa ±5 mnt) yang
  /// menutup status ini.
  final Map<String, DateTime> _trackSuspects = {};
  Future<void> _chain = Future<void>.value();

  /// Percobaan yang sedang berjalan per (trek|kualitas): pemanggil
  /// serentak untuk trek yang sama (tangga + penyegaran proaktif +
  /// pemanasan antrean) BERBAGI satu percobaan, bukan menumpuk antrean
  /// berseri — pelajaran emulator Tahap 3: badai prefetch autoplay
  /// menumpuk backlog ±9 menit dan trek yang sama teresolusi 8×.
  final Map<String, Future<StreamInfo?>> _inFlight = {};

  DirectStreamService({
    required DirectWatchFetcher fetchWatchContext,
    required DirectFormatsResolver resolveDirectFormats,
    required DirectTextFetcher fetchText,
    required DirectEnabledReader readEnabled,
    DirectEventSink? onEvent,
    DirectSessionBuilder? buildSession,
    DirectTokenMinter? mintToken,
    DirectSolver? solve,
    DateTime Function()? now,
  })  : _fetchWatch = fetchWatchContext,
        _resolveFormats = resolveDirectFormats,
        _fetchText = fetchText,
        _readEnabled = readEnabled,
        _onEvent = onEvent,
        _now = now ?? DateTime.now,
        _buildSession = buildSession ?? _engineBuildSession,
        _mintToken = mintToken ?? _engineMintToken,
        _solve = solve ?? _engineSolve;

  // ----- mesin WebView bawaan (lewat registri host produksi) -----

  static Future<DirectSessionResult> _engineBuildSession(String html) async {
    final engine = await DirectEngineRegistry.obtain();
    if (engine == null) {
      return const DirectSessionResult(ok: false, errors: ['mesin WebView tidak terpasang']);
    }
    return engine.ensurePageSession(html);
  }

  static Future<DirectMintResult> _engineMintToken(String videoId) async {
    final engine = await DirectEngineRegistry.obtain(timeout: const Duration(seconds: 3));
    if (engine == null) {
      return const DirectMintResult(ok: false, errorClass: 'mesin WebView tidak terpasang');
    }
    return engine.mintContentToken(videoId);
  }

  static Future<EjsSolveOutcome> _engineSolve({
    required String playerJs,
    List<String> nChallenges = const [],
    List<String> sigChallenges = const [],
    String? playerKey,
  }) async {
    final engine = await DirectEngineRegistry.obtain(timeout: const Duration(seconds: 3));
    if (engine == null) {
      return const EjsSolveOutcome(ok: false, error: 'mesin WebView tidak terpasang');
    }
    return engine.ejsSolveWorker(
        playerJs: playerJs,
        nChallenges: nChallenges,
        sigChallenges: sigChallenges,
        playerKey: playerKey);
  }

  // ----- API publik -----

  /// Satu percobaan resolusi DIRECT untuk [track] pada [quality].
  /// StreamInfo keberhasilan (berpasangan UA jalur), atau null dengan
  /// sebab tercatat di [stats]/log. TIDAK pernah melempar. Pemanggil
  /// serentak untuk (trek, kualitas) yang sama berbagi satu percobaan.
  Future<StreamInfo?> tryResolve(Track track, StreamQuality quality) {
    final key = '${track.key}|${quality.name}';
    final running = _inFlight[key];
    if (running != null) return running;
    final fut = _resolvePipeline(track, quality, key);
    _inFlight[key] = fut;
    return fut;
  }

  Future<StreamInfo?> _resolvePipeline(
      Track track, StreamQuality quality, String key) async {
    try {
      try {
        if (!await _readEnabled()) {
          _recordSkip(track, DirectFailCause.disabled);
          return null;
        }
      } catch (_) {
        // pref tak terbaca tidak boleh mematikan jalur maupun putar.
      }
      if (stats.inCooldown) {
        _recordSkip(track, DirectFailCause.demoted);
        return null;
      }
      final excludedUntil = _trackExclusions[track.key.toString()];
      if (excludedUntil != null && _now().isBefore(excludedUntil)) {
        _recordSkip(track, DirectFailCause.excluded);
        return null;
      }
      final cached = _memoryCache[key];
      if (cached != null && cached.expiresAt.isAfter(_now().add(const Duration(seconds: 30)))) {
        stats.lastPath = 'direct';
        stats.lastAt = _now();
        return cached;
      }
      // Gerbang diperiksa ULANG di dalam rantai berseri, pada saat
      // eksekusi: antrean bisa panjang (prefetch autoplay), dan
      // kill-switch/demosi/pengecualian yang berubah saat percobaan
      // MENUNGGU harus tetap berlaku — pelajaran emulator Tahap 3:
      // antrean pra-balik saklar mengeksekusi resolusi penuh ±9 menit
      // sesudah kill-switch dimatikan. Waktu tercatat = waktu eksekusi,
      // bukan waktu tunggu antrean.
      _AttemptOutcome? outcome;
      var execMs = 0;
      await _serialized(() async {
        final esw = Stopwatch()..start();
        outcome = await _gateThenAttempt(track, quality);
        execMs = esw.elapsedMilliseconds;
      });
      final o = outcome!;
      if (o.isSkip) {
        _recordSkip(track, o.cause ?? DirectFailCause.unknown);
        return null;
      }
      if (o.info != null) {
        _recordSuccess(track, quality, o.info!, execMs);
        return o.info;
      }
      _recordFailure(track, o.cause ?? DirectFailCause.unknown, debug: o.debug);
      return null;
    } finally {
      _inFlight.remove(key);
    }
  }

  /// Pemeriksaan gerbang pada saat eksekusi + satu percobaan penuh
  /// dengan anggaran waktu keras.
  Future<_AttemptOutcome> _gateThenAttempt(Track track, StreamQuality quality) async {
    try {
      if (!await _readEnabled()) {
        return const _AttemptOutcome.skip(DirectFailCause.disabled);
      }
    } catch (_) {/* pref tak terbaca: lanjut */}
    if (stats.inCooldown) {
      return const _AttemptOutcome.skip(DirectFailCause.demoted);
    }
    final excludedUntil = _trackExclusions[track.key.toString()];
    if (excludedUntil != null && _now().isBefore(excludedUntil)) {
      return const _AttemptOutcome.skip(DirectFailCause.excluded);
    }
    _lastAttemptSteps = null;
    final o = await _attempt(track, quality).timeout(_totalBudget,
        onTimeout: () => const _AttemptOutcome.fail(DirectFailCause.timeout));
    _lastAttemptSteps = _stepsSummary();
    return o;
  }

  /// Laporan pipa putar: URL DIRECT trek ini ditolak edge (403 sesudah
  /// coba-ulang jendela). Penolakan ke-1: buang cache trek + tandai sesi
  /// basi (resolusi berikutnya menyegarkan sesi SATU kali). Penolakan
  /// ke-2 (sudah tersangka): kecualikan trek ±5 menit + hitung sebagai
  /// kegagalan kesehatan jalur.
  void markFetchRejected(TrackKey key) {
    final k = key.toString();
    _recoveryPending.add(k);
    _memoryCache.removeWhere((cacheKey, _) => cacheKey.startsWith('$k|'));
    final markedAt = _trackSuspects[k];
    if (markedAt != null && _now().difference(markedAt) < _exclusionTtl) {
      _trackSuspects.remove(k);
      _trackExclusions[k] = _now().add(_exclusionTtl);
      _event('direct-trek-dikecualikan',
          'penolakan 403 berulang · pengecualian ${_exclusionTtl.inMinutes} mnt');
      _registerHealthFailure();
    } else {
      _trackSuspects[k] = _now();
      _sessionStale = true;
      _event('direct-sesi-segar', 'sesi minter ditandai basi · sebab penolakan 403');
    }
  }

  /// Pemanasan malas: bangun konteks + sesi dari halaman watch [videoId]
  /// tanpa memblokir apa pun (dipanggil sesudah putar pertama). Semua
  /// kegagalan ditelan — jalur tetap malas pada resolusi berikutnya.
  Future<void> prewarm(String videoId) async {
    try {
      if (!await _readEnabled()) return;
      await _serialized(() async {
        try {
          final ctx = await _contextFor(videoId);
          if (ctx != null) await _sessionFor(ctx);
        } catch (_) {/* pemanasan gagal tidak bersuara */}
      });
    } catch (_) {/* tidak bersuara */}
  }

  /// Segarkan sesi minter secara manual (Diagnostik / pemulihan).
  void invalidateSession() {
    _sessionStale = true;
    _event('direct-sesi-segar', 'sesi minter ditandai basi · manual');
  }

  /// Catat bahwa resolusi warisan yang melayani trek ini (statistik
  /// Diagnostik: jalur terakhir yang benar-benar dipakai).
  void noteLegacyPath() {
    stats.lastPath = 'legacy';
    stats.lastAt = _now();
  }

  // ----- inti percobaan -----

  // Pengukur durasi per langkah (ronde vonis perangkat Tahap 3): log
  // direct-ok/jatuh dulu hanya memuat total eksekusi — tak terlihat
  // langkah mana yang mahal. Percobaan berseri → satu bidang aman.
  Stopwatch? _attemptSw;
  final Map<String, int> _stepMarks = {};
  String? _lastAttemptSteps;

  void _markStep(String name) {
    final sw = _attemptSw;
    if (sw != null) _stepMarks[name] = sw.elapsedMilliseconds;
  }

  String _stepsSummary() {
    const order = ['konteks', 'sesi', 'resolusi', 'solver', 'cetak', 'rakit'];
    final hits = [for (final n in order) if (_stepMarks.containsKey(n)) n];
    final parts = <String>[];
    for (var i = 0; i + 1 < hits.length; i++) {
      parts.add('${hits[i]} ${_stepMarks[hits[i + 1]]! - _stepMarks[hits[i]]!}');
    }
    return parts.join(' · ');
  }

  Future<_AttemptOutcome> _attempt(Track track, StreamQuality quality) async {
    var step = 'konteks';
    _stepMarks.clear();
    _attemptSw = Stopwatch()..start();
    _stepMarks['konteks'] = 0;
    try {
      final suspect = _trackSuspects.containsKey(track.key.toString());
      if (suspect) _sessionStale = true; // segarkan sesi satu kali untuk tersangka
      final ctx = await _contextFor(track.playableRef);
      if (ctx == null || ctx.visitorData == null || ctx.signatureTimestamp == null) {
        return _AttemptOutcome.fail(DirectFailCause.context,
            debug: ctx?.error ?? 'kolom visitorData/sts kosong di halaman watch');
      }
      step = 'sesi-minter';
      _markStep('sesi');
      var session = await _sessionFor(ctx);
      if (session == null || !session.ok) {
        return _AttemptOutcome.fail(DirectFailCause.session,
            debug: session == null
                ? 'HTML konteks hilang'
                : (session.errors.isNotEmpty
                    ? session.errors.first
                    : 'sesi tidak ok'));
      }
      // Resolusi player: direktur-1 tanpa token; direktur-2 membawa token
      // player terikat visitorData sesi bila tak ada format terpakai.
      step = 'resolusi';
      _markStep('resolusi');
      var res = await _resolveFormats(track,
          visitorData: ctx.visitorData, signatureTimestamp: ctx.signatureTimestamp);
      if (res.error != null) {
        return _AttemptOutcome.fail(DirectFailCause.resolution, debug: res.error);
      }
      var pick = pickDirectFormat(res.formats, quality);
      if (pick == null && session.visitorToken != null) {
        res = await _resolveFormats(track,
            visitorData: ctx.visitorData,
            signatureTimestamp: ctx.signatureTimestamp,
            playerPoToken: session.visitorToken);
        if (res.error != null) {
          return _AttemptOutcome.fail(DirectFailCause.resolution, debug: res.error);
        }
        pick = pickDirectFormat(res.formats, quality);
      }
      if (pick == null) {
        return const _AttemptOutcome.fail(DirectFailCause.noFormat,
            debug: 'tak ada format audio terpakai');
      }

      // Susun URL: decipher bila tercipher; transformasi n bila langsung.
      step = 'solver';
      _markStep('solver');
      String? url;
      if (pick.ciphered) {
        final solved = await _solveChallenges(ctx,
            sigChallenge: pick.cipherS!, baseUrl: pick.cipherBaseUrl!);
        if (solved == null) {
          return _AttemptOutcome.fail(DirectFailCause.solver, debug: _lastSolveError);
        }
        var u = pick.cipherBaseUrl!;
        if (solved.n != null) u = replaceQueryParam(u, 'n', solved.n!);
        url = appendSignatureParam(u, pick.cipherSp, solved.sig);
      } else {
        url = pick.directUrl;
        if (url != null) {
          final rawN = Uri.parse(url).queryParameters['n'];
          if (rawN != null) {
            final solvedN = await _solveNOnly(ctx, rawN);
            if (solvedN == null) {
              return _AttemptOutcome.fail(DirectFailCause.solver, debug: _lastSolveError);
            }
            if (solvedN != rawN) url = replaceQueryParam(url, 'n', solvedN);
          }
        }
      }
      if (url == null) return const _AttemptOutcome.fail(DirectFailCause.noFormat);

      // Token konten terikat VIDEO_ID — wajib pada resep direktur;
      // gagal cetak → segarkan sesi SATU kali lalu cetak ulang.
      step = 'cetak-token';
      _markStep('cetak');
      var mint = await _mint(track.playableRef);
      if (!mint.ok) {
        _sessionStale = true;
        _event('direct-sesi-segar', 'sesi minter disegarkan · sebab cetak gagal');
        session = await _sessionFor(ctx, forceRebuild: true);
        if (session == null || !session.ok) {
          return _AttemptOutcome.fail(DirectFailCause.minter, debug: mint.errorClass);
        }
        mint = await _mint(track.playableRef);
        if (!mint.ok) {
          return _AttemptOutcome.fail(DirectFailCause.minter, debug: mint.errorClass);
        }
      }
      step = 'rakit';
      _markStep('rakit');

      var assembled = appendPotToken(url, mint.token!);
      assembled = appendCpn(assembled);
      if (sabotage != DirectSabotage.off) {
        assembled = sabotageStreamUrl(assembled);
        if (sabotage == DirectSabotage.once) sabotage = DirectSabotage.off;
      }
      final info = StreamInfo(
        url: assembled,
        mimeType: pick.mime,
        bitrate: pick.bitrate,
        expiresAt: _now().add(Duration(seconds: res.expiresInSeconds - 300)),
        userAgent: kDirectPathUserAgent,
        viaDirectPath: true,
      );
      stats.lastItag = pick.itag;
      stats.lastBitrate = pick.bitrate;
      stats.lastContentLength = pick.contentLength;
      return _AttemptOutcome.ok(info);
    } catch (e) {
      return _AttemptOutcome.fail(DirectFailCause.unknown,
          debug: 'langkah=$step · ${_clip('$e')}');
    }
  }

  /// Konteks watch ter-cache (TTL 30 mnt); kendaraan pengambilan = videoId
  /// trek yang sedang diresolusi. HTML disimpan hanya sampai sesi lahir.
  Future<WatchPageData?> _contextFor(String videoId) async {
    final ctx = _context;
    final at = _contextAt;
    if (ctx != null && at != null && _now().difference(at) < _contextTtl) return ctx;
    final fresh = await _fetchWatch(videoId);
    if (fresh.error != null || fresh.html == null) return null;
    _context = fresh;
    _contextAt = _now();
    return fresh;
  }

  /// Sesi minter yang hidup untuk [ctx]: lahir dari HTML halaman watch
  /// yang sama; kedaluwarsa menurut TTL GenerateIT (43.200 dtk) dikurangi
  /// margin aman; dibangun ulang bila ditandai basi.
  Future<DirectSessionResult?> _sessionFor(WatchPageData ctx, {bool forceRebuild = false}) async {
    final s = _session;
    final born = _sessionBornAt;
    if (!forceRebuild && !_sessionStale && s != null && s.ok && born != null) {
      final ttl = (s.ttlSecs ?? 43200) - _sessionSafetyMarginSecs;
      if (_now().difference(born).inSeconds < ttl) return s;
    }
    final html = ctx.html;
    if (html == null) return null;
    final built = await _buildSession(html);
    if (built.ok) {
      _session = built;
      _sessionBornAt = _now();
      _sessionStale = false;
    }
    return built;
  }

  Future<DirectMintResult> _mint(String videoId) =>
      _mintToken(videoId).timeout(const Duration(seconds: 20),
          onTimeout: () =>
              const DirectMintResult(ok: false, errorClass: 'lewat waktu cetak'));

  /// Solve sig+n untuk format tercipher — hasil ter-cache per
  /// (jsUrl, tantangan); solver gagal = jalur gagal (sebab solver).
  Future<({String sig, String? n})?> _solveChallenges(WatchPageData ctx,
      {required String sigChallenge, required String baseUrl}) async {
    final js = await _playerJs(ctx);
    if (js == null) {
      _lastSolveError = 'js player tidak terambil';
      return null;
    }
    final rawN = Uri.parse(baseUrl).queryParameters['n'];
    final sigKey = '${ctx.jsUrl}|s|$sigChallenge';
    final cachedSig = _solveCache[sigKey];
    String? solvedN;
    var needSolve = cachedSig == null;
    if (rawN != null) {
      final nKey = '${ctx.jsUrl}|n|$rawN';
      final cachedN = _solveCache[nKey];
      if (cachedN != null) {
        solvedN = cachedN;
      } else {
        needSolve = true;
      }
    }
    if (needSolve) {
      final out = await _solve(
        playerJs: js,
        nChallenges: [if (rawN != null && solvedN == null) rawN],
        sigChallenges: [if (cachedSig == null) sigChallenge],
        playerKey: ctx.jsUrl,
      ).timeout(const Duration(seconds: 35),
          onTimeout: () => const EjsSolveOutcome(ok: false, error: 'lewat waktu solver'));
      if (!out.ok) {
        _lastSolveError = out.error ?? 'solver tidak ok';
        return null;
      }
      final sig = out.sig[sigChallenge];
      if (cachedSig == null && sig == null) {
        _lastSolveError = 'sig tidak terpecahkan';
        return null;
      }
      if (sig != null) _cacheSolve(sigKey, sig);
      if (rawN != null && solvedN == null) {
        solvedN = out.n[rawN];
        if (solvedN != null) _cacheSolve('${ctx.jsUrl}|n|$rawN', solvedN);
      }
    }
    final sig = cachedSig ?? _solveCache[sigKey];
    if (sig == null) return null;
    return (sig: sig, n: solvedN);
  }

  /// Transformasi n saja untuk URL langsung. Null = solver gagal (jalur
  /// gugur); nilai sama dengan masukan = solve berhasil tanpa perubahan.
  Future<String?> _solveNOnly(WatchPageData ctx, String rawN) async {
    final nKey = '${ctx.jsUrl}|n|$rawN';
    final cached = _solveCache[nKey];
    if (cached != null) return cached;
    final js = await _playerJs(ctx);
    if (js == null) {
      _lastSolveError = 'js player tidak terambil';
      return null;
    }
    final out = await _solve(playerJs: js, nChallenges: [rawN], playerKey: ctx.jsUrl).timeout(
        const Duration(seconds: 35),
        onTimeout: () => const EjsSolveOutcome(ok: false, error: 'lewat waktu solver'));
    if (!out.ok || out.nError != null) {
      _lastSolveError = out.error ?? out.nError ?? 'solver tidak ok';
      return null;
    }
    final solved = out.n[rawN] ?? rawN;
    _cacheSolve(nKey, solved);
    return solved;
  }

  /// JS player resmi, ter-cache per jsUrl sesi konteks.
  Future<String?> _playerJs(WatchPageData ctx) async {
    final jsUrl = ctx.jsUrl;
    if (jsUrl == null) return null;
    final cached = _playerJsByUrl[jsUrl];
    if (cached != null) return cached;
    final js = await _fetchText('https://www.youtube.com$jsUrl');
    if (js == null || js.isEmpty) return null;
    _playerJsByUrl[jsUrl] = js;
    return js;
  }

  void _cacheSolve(String key, String value) {
    if (_solveCache.length > 256) _solveCache.clear();
    _solveCache[key] = value;
  }

  // ----- pencatatan hasil -----

  void _recordSuccess(Track track, StreamQuality quality, StreamInfo info, int elapsedMs) {
    _memoryCache['${track.key}|${quality.name}'] = info;
    final wasDemoted = stats.consecutiveFailures >= _demoteThreshold;
    stats.okCount++;
    stats.consecutiveFailures = 0;
    stats.cooldownUntil = null;
    stats.lastPath = 'direct';
    stats.lastCause = null;
    stats.lastTrackId = track.playableRef;
    stats.lastTitle = track.title;
    stats.lastAt = _now();
    _event('direct-ok',
        'itag ${stats.lastItag ?? '-'} · ${((info.bitrate ?? 0) / 1000).round()} kbps · ${quality.name} · $elapsedMs mdtk · "${track.title}"${_lastAttemptSteps == null || _lastAttemptSteps!.isEmpty ? '' : ' · langkah $_lastAttemptSteps'}');
    if (wasDemoted) _event('direct-pulih', 'jalur pulih · sukses sesudah demosi');
    if (_recoveryPending.remove(track.key.toString())) {
      _event('direct-pulih', 'trek pulih sesudah penolakan · "${track.title}"');
      onRecovered?.call();
    }
  }

  void _recordFailure(Track track, DirectFailCause cause, {String? debug}) {
    _lastSkipCause = null;
    stats.fallbackCount++;
    stats.fallbackByCause[cause.label] = (stats.fallbackByCause[cause.label] ?? 0) + 1;
    stats.lastCause = cause.label;
    stats.lastError = debug;
    stats.lastAt = _now();
    _event('direct-jatuh',
        'sebab ${cause.label} · "${track.title}"${debug == null ? '' : ' · ${_clip(debug)}'}${_lastAttemptSteps == null || _lastAttemptSteps!.isEmpty ? '' : ' · langkah $_lastAttemptSteps'}');
    // Pengecualian per-trek (pola upstream ±5 mnt) untuk sebab yang
    // menempel pada trek ini — antrean tidak menghantam dinding sama.
    if (cause == DirectFailCause.resolution ||
        cause == DirectFailCause.noFormat ||
        cause == DirectFailCause.solver) {
      _trackExclusions[track.key.toString()] = _now().add(_exclusionTtl);
    }
    _registerHealthFailure();
  }

  String? _lastSkipCause;

  void _recordSkip(Track track, DirectFailCause cause) {
    stats.lastCause = cause.label;
    stats.lastAt = _now();
    // Lewati berulang dengan sebab yang sama (kill-switch mati / demosi /
    // pengecualian) tidak membanjiri log insiden: catat hanya perubahan
    // sebab. Percobaan nyata tetap selalu tercatat di _recordFailure.
    if (_lastSkipCause == cause.label) return;
    _lastSkipCause = cause.label;
    _event('direct-jatuh', 'sebab ${cause.label} · "${track.title}"');
  }

  void _registerHealthFailure() {
    stats.consecutiveFailures++;
    if (stats.consecutiveFailures >= _demoteThreshold && !stats.inCooldown) {
      stats.cooldownUntil = _now().add(_cooldownTtl);
      _event('direct-demosi',
          '${stats.consecutiveFailures} gagal beruntun · cooldown ${_cooldownTtl.inMinutes} mnt');
    }
  }

  void _event(String kind, String detail) => _onEvent?.call(kind, detail);

  /// Serialisasi percobaan: sesi minter & solver adalah sumber daya
  /// bersama satu WebView — dua resolusi bersamaan tidak boleh balapan.
  Future<T> _serialized<T>(Future<T> Function() op) {
    final run = _chain.then((_) => op());
    _chain = run.then((_) {}, onError: (_) {});
    return run;
  }
}
