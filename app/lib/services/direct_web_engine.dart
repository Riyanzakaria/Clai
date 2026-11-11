import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Mesin WebView jalur DIRECT-1 (Tahap 3, Mesin Penyeberangan 2.0) —
/// mencetak token BotGuard (platform WEB) dan menjalankan solver EJS di
/// dalam WebView anonim, tanpa login. Lahir sebagai laboratorium diagnostik
/// (Ronde Probe PoToken → Tahap 2) dan DIPRODUKSIKAN apa adanya: logika JS
/// dan pola panggilnya persis yang terbukti memutar lagu utuh di Tahap 2.
///
/// Dua kemampuan:
///  1. Sesi minter BotGuard: halaman lokal kosong dimuat dengan baseUrl
///     https://www.youtube.com/ (origin sama dengan API jnn, tanpa CSP
///     halaman asli), lalu port JS BgUtils dijalankan apa adanya:
///       tantangan (HTML halaman watch `ytAtN` / jnn Create / WAA Create)
///         → interpreter BotGuard dimuat → snapshot({ webPoSignalOutput })
///         → GenerateIT → WebPoMinter.mintAsWebsafeString(identifier)
///     Token pengikat VIDEO_ID ditempel pemanggil sebagai `&pot=`; token
///     pengikat visitorData dipakai pemanggil sebagai token player.
///  2. Solver EJS (yt-dlp-ejs): aset `assets/solver/` (ejs_lib + ejs_core)
///     dimuat sekali; solve berjalan di Web Worker (solve di utas
///     halaman terbukti menggantung pada panggilan berulang, Tahap 2
///     lari 4). Worker PERSISTEN lintas solve sejak ronde vonis
///     perangkat Tahap 3 (player dipraproses sekali per versi);
///     kegagalan apa pun membuangnya dan mengulang sekali dari worker
///     segar — perilaku worker-per-solve asli sebagai jalan jatuh.
///
/// ATRIBUSI: port JS BotGuard dari BgUtils (© LuanRT, lisensi MIT);
/// solver dari proyek yt-dlp-ejs (lisensi Unlicense), versi aset 0.8.0.
///
/// Token adalah KREDENSIAL SESI: nilai token & visitorData hanya hidup di
/// memori proses (bidang privat kelas ini + pesan kanal sesaat), TIDAK
/// PERNAH ditulis ke laporan/log/berkas. Yang boleh dicatat pemanggil:
/// berhasil/gagal, rute, panjang token, durasi cetak, kelas kegagalan.
class DirectSessionResult {
  final bool ok;
  final String route; // PAGE / JNN / WAA / '-'
  final String interpreter; // script-tag / fetch-eval / inline / '-'
  final int mintMs; // waktu bangun minter (tantangan→snapshot→GenerateIT)
  final int? ttlSecs;
  final String? visitorData; // memori saja
  final String? visitorToken; // memori saja (terikat visitorData sesi)
  final List<String> errors; // kelas kegagalan per rute

  const DirectSessionResult({
    required this.ok,
    this.route = '-',
    this.interpreter = '-',
    this.mintMs = 0,
    this.ttlSecs,
    this.visitorData,
    this.visitorToken,
    this.errors = const [],
  });

  int get visitorDataLen => visitorData?.length ?? 0;
  int get visitorTokenLen => visitorToken?.length ?? 0;
}

class DirectMintResult {
  final bool ok;
  final String? token; // memori saja (terikat videoId yang diminta)
  final int mintMs;
  final String? errorClass;

  const DirectMintResult({required this.ok, this.token, this.mintMs = 0, this.errorClass});

  int get tokenLen => token?.length ?? 0;
}

/// Hasil solver EJS (yt-dlp/ejs `jsc`) untuk tantangan n/sig — nilai
/// hasil hanya hidup di memori (Tahap 2, E1/E3). Peta tantangan→hasil.
class EjsSolveOutcome {
  final bool ok;
  final Map<String, String> n;
  final Map<String, String> sig;
  final String? nError;
  final String? sigError;
  final String? error;

  const EjsSolveOutcome({
    required this.ok,
    this.n = const {},
    this.sig = const {},
    this.nError,
    this.sigError,
    this.error,
  });
}

class DirectWebEngine extends StatefulWidget {
  /// Penanda tahap aman-untuk-log (nama tahap + kelas galat; TIDAK PERNAH
  /// memuat nilai token/visitorData).
  final void Function(String stage)? onProgress;

  const DirectWebEngine({super.key, this.onProgress});

  @override
  State<DirectWebEngine> createState() => DirectWebEngineState();
}

class DirectWebEngineState extends State<DirectWebEngine> {
  static const _desktopUa =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';

  late final WebViewController _controller;
  final Completer<void> _ready = Completer<void>();
  bool _injected = false;

  DirectSessionResult? _session;
  Completer<DirectSessionResult>? _sessionWaiter;
  Completer<DirectMintResult>? _mintWaiter;
  Completer<EjsSolveOutcome>? _ejsWaiter;
  bool _ejsLoaded = false;

  @override
  void initState() {
    super.initState();
    DirectEngineRegistry._attach(this);
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      // Ronde vonis perangkat Tahap 3: WebView tanpa warna latar mengecat
      // PUTIH bawaan Android — host tak terlihat ini (320×96 dp di kiri
      // atas tumpukan akar) menembus header transparan semua layar
      // sebagai "pita putih" di HP pemilik. Latar WAJIB transparan.
      ..setBackgroundColor(Colors.transparent)
      ..setUserAgent(_desktopUa)
      ..addJavaScriptChannel('ClaiPoToken', onMessageReceived: _onChannelMessage)
      ..setNavigationDelegate(NavigationDelegate(onPageFinished: _onPageFinished))
      ..loadHtmlString(_labHtml, baseUrl: 'https://www.youtube.com/');
  }

  Future<void> _onPageFinished(String url) async {
    if (_injected) return;
    _injected = true;
    try {
      await _controller.runJavaScript(_labJs);
      if (!_ready.isCompleted) _ready.complete();
    } catch (e) {
      if (!_ready.isCompleted) _ready.completeError(e);
    }
  }

  void _onChannelMessage(JavaScriptMessage message) {
    // Pesan 'session'/'mint' MEMUAT nilai token — jangan pernah dicetak.
    Map<String, dynamic> m;
    try {
      final decoded = jsonDecode(message.message);
      if (decoded is! Map) return;
      m = decoded.cast<String, dynamic>();
    } catch (_) {
      return;
    }
    switch (m['t']) {
      case 'progress':
        widget.onProgress?.call('${m['stage'] ?? ''}');
      case 'session':
        final ok = m['ok'] == true;
        final result = DirectSessionResult(
          ok: ok,
          route: '${m['route'] ?? '-'}',
          interpreter: '${m['interpreter'] ?? '-'}',
          mintMs: (m['mintMs'] as num?)?.toInt() ?? 0,
          ttlSecs: (m['ttl'] as num?)?.toInt(),
          visitorData: ok && (m['visitorData'] as String?)?.isNotEmpty == true
              ? m['visitorData'] as String
              : null,
          visitorToken: ok && (m['visitorToken'] as String?)?.isNotEmpty == true
              ? m['visitorToken'] as String
              : null,
          errors: [
            for (final e in (m['errors'] as List? ?? const [])) '$e',
          ],
        );
        if (ok) _session = result;
        final w = _sessionWaiter;
        _sessionWaiter = null;
        if (w != null && !w.isCompleted) w.complete(result);
      case 'mint':
        final ok = m['ok'] == true;
        final result = DirectMintResult(
          ok: ok,
          token: ok ? m['token'] as String? : null,
          mintMs: (m['mintMs'] as num?)?.toInt() ?? 0,
          errorClass: ok ? null : '${m['cls'] ?? 'galat tak dikenal'}',
        );
        final w = _mintWaiter;
        _mintWaiter = null;
        if (w != null && !w.isCompleted) w.complete(result);
      case 'ejs':
        // Hasil solver memuat nilai sig/n — jangan pernah dicetak.
        final ok = m['ok'] == true;
        Map<String, String> conv(Object? v) => {
              for (final e in (v as Map? ?? const {}).entries) '${e.key}': '${e.value}',
            };
        final result = EjsSolveOutcome(
          ok: ok,
          n: ok ? conv(m['n']) : const {},
          sig: ok ? conv(m['sig']) : const {},
          nError: (m['nError'] as String?)?.isNotEmpty == true ? m['nError'] as String : null,
          sigError: (m['sigError'] as String?)?.isNotEmpty == true ? m['sigError'] as String : null,
          error: ok ? null : '${m['error'] ?? 'galat solver'}',
        );
        final w = _ejsWaiter;
        _ejsWaiter = null;
        if (w != null && !w.isCompleted) w.complete(result);
    }
  }

  /// Bangun sesi pencetak (tantangan → BotGuard → GenerateIT) bila belum
  /// ada. Sesi yang sudah jadi dipakai ulang (minter berlaku sampai TTL).
  Future<DirectSessionResult> ensureSession() async {
    final existing = _session;
    if (existing != null && existing.ok) return existing;
    if (_sessionWaiter != null) return _sessionWaiter!.future;
    final waiter = Completer<DirectSessionResult>();
    _sessionWaiter = waiter;
    try {
      await _ready.future.timeout(const Duration(seconds: 60));
      await _controller.runJavaScript('window.__claiEnsure && window.__claiEnsure()');
    } catch (e) {
      _sessionWaiter = null;
      return DirectSessionResult(ok: false, errors: ['webview tidak siap: $e']);
    }
    return waiter.future.timeout(
      const Duration(seconds: 300),
      onTimeout: () {
        _sessionWaiter = null;
        return const DirectSessionResult(ok: false, errors: ['timeout 300 dtk menunggu sesi JS']);
      },
    );
  }

  /// Cetak token terikat [videoId] dari sesi yang sudah jadi.
  Future<DirectMintResult> mintContentToken(String videoId) async {
    if (_session?.ok != true) {
      return const DirectMintResult(ok: false, errorClass: 'sesi belum terbangun');
    }
    if (_mintWaiter != null) {
      return const DirectMintResult(ok: false, errorClass: 'cetak lain sedang berjalan');
    }
    final waiter = Completer<DirectMintResult>();
    _mintWaiter = waiter;
    try {
      await _controller
          .runJavaScript('window.__claiMint && window.__claiMint(${jsonEncode(videoId)})');
    } catch (e) {
      _mintWaiter = null;
      return DirectMintResult(ok: false, errorClass: 'panggil JS gagal: $e');
    }
    return waiter.future.timeout(
      const Duration(seconds: 90),
      onTimeout: () {
        _mintWaiter = null;
        return const DirectMintResult(ok: false, errorClass: 'timeout 90 dtk menunggu cetak token');
      },
    );
  }

  /// Bangun sesi pencetak dari HTML halaman WATCH yang diberikan
  /// (Tahap 2, E1 — atestasi-halaman ala sumber): tantangan ytAtN +
  /// ytcfg (VISITOR_DATA/EVENT_ID) halaman ITU, bukan beranda. Sesi
  /// menggantikan sesi generik di laboratorium (pemanggilan matriks
  /// berurutan). HTML hanya transit ke WebView per potongan.
  Future<DirectSessionResult> ensurePageSession(String html) async {
    if (_sessionWaiter != null) {
      return const DirectSessionResult(ok: false, errors: ['sesi lain sedang dibangun']);
    }
    final waiter = Completer<DirectSessionResult>();
    _sessionWaiter = waiter;
    try {
      await _ready.future.timeout(const Duration(seconds: 60));
      await _controller.runJavaScript('window.__claiHtmlBegin && window.__claiHtmlBegin()');
      const chunk = 200000;
      for (var i = 0; i < html.length; i += chunk) {
        final end = i + chunk > html.length ? html.length : i + chunk;
        await _controller.runJavaScript(
            'window.__claiHtmlChunk && window.__claiHtmlChunk(${jsonEncode(html.substring(i, end))})');
      }
      await _controller.runJavaScript('window.__claiEnsurePage && window.__claiEnsurePage()');
    } catch (e) {
      _sessionWaiter = null;
      return DirectSessionResult(ok: false, errors: ['webview tidak siap: $e']);
    }
    return waiter.future.timeout(
      const Duration(seconds: 300),
      onTimeout: () {
        _sessionWaiter = null;
        return const DirectSessionResult(ok: false, errors: ['timeout 300 dtk menunggu sesi halaman']);
      },
    );
  }

  /// Selesaikan tantangan n/sig dengan solver EJS (yt-dlp/ejs) di
  /// WebView: aset solver dimuat sekali — bundel yt-dlp-ejs 0.8.0
  /// (ejs_lib.min.js mengekspor objek `lib` berisi meriyah+astring;
  /// keduanya ditempel ke global lalu ejs_core.min.js membentuk
  /// `jsc`). Kode player diberikan sekali per [playerKey] lalu
  /// dipakai ulang dari hasil praprosesnya. Nilai tantangan & hasil
  /// hanya di memori. (Generasi solver dari APK Auralys terbukti basi
  /// di bangku node 2026-11-08: "found 0 n function possibilities"
  /// pada player live; 0.8.0 memecahkan n+sig player yang sama.)
  Future<EjsSolveOutcome> ejsSolve({
    required String playerKey,
    String? playerJs,
    List<String> nChallenges = const [],
    List<String> sigChallenges = const [],
  }) async {
    if (_ejsWaiter != null) {
      return const EjsSolveOutcome(ok: false, error: 'solve lain sedang berjalan');
    }
    final waiter = Completer<EjsSolveOutcome>();
    _ejsWaiter = waiter;
    try {
      await _ready.future.timeout(const Duration(seconds: 60));
      if (!_ejsLoaded) {
        final libSrc = await rootBundle.loadString('assets/solver/ejs_lib.min.js');
        await _controller.runJavaScript(libSrc);
        await _controller.runJavaScript(
            'window.meriyah = window.lib.meriyah; window.astring = window.lib.astring;');
        final coreSrc = await rootBundle.loadString('assets/solver/ejs_core.min.js');
        await _controller.runJavaScript(coreSrc);
        final has = await evalSolver('(typeof window.jsc === "function") ? "yes" : "no"');
        if (has != 'yes') {
          _ejsWaiter = null;
          return const EjsSolveOutcome(ok: false, error: 'solver EJS tidak termuat (jsc tidak ada)');
        }
        _ejsLoaded = true;
      }
      if (playerJs != null) {
        await _controller.runJavaScript('window.__ejsPlayerBegin && window.__ejsPlayerBegin()');
        const chunk = 200000;
        for (var i = 0; i < playerJs.length; i += chunk) {
          final end = i + chunk > playerJs.length ? playerJs.length : i + chunk;
          await _controller.runJavaScript(
              'window.__ejsPlayerChunk && window.__ejsPlayerChunk(${jsonEncode(playerJs.substring(i, end))})');
        }
      }
      final input = jsonEncode({
        'playerKey': playerKey,
        'hasPlayer': playerJs != null,
        'n': nChallenges,
        'sig': sigChallenges,
      });
      await _controller
          .runJavaScript('window.__claiEjsSolve && window.__claiEjsSolve(${jsonEncode(input)})');
    } catch (e) {
      _ejsWaiter = null;
      return EjsSolveOutcome(ok: false, error: 'panggil JS gagal: $e');
    }
    return waiter.future.timeout(
      const Duration(seconds: 180),
      onTimeout: () {
        _ejsWaiter = null;
        return const EjsSolveOutcome(ok: false, error: 'timeout 180 dtk menunggu solver');
      },
    );
  }

  /// Solver berjalan di Web Worker (bukan benang halaman). Alasan
  /// terukur (Tahap 2, lari 3–4): di WebView, panggilan `jsc` kedua dan
  /// seterusnya pada benang halaman menggantung (timeout 180 dtk) dan
  /// eksekusi fungsi sig menggantung total di DOM halaman nyata —
  /// sedangkan lingkungan tanpa DOM (node, document ter-shim oleh
  /// solver sendiri) memecahkan n+sig dalam ±2 dtk. Worker meniru
  /// lingkungan itu dan mengisolasi tiap solve. Nilai hanya di memori.
  bool _ejsAssetsSet = false;

  // Worker PERSISTEN (ronde vonis perangkat Tahap 3): pola lama membuat
  // worker BARU per solve dan mengirim ulang JS player penuh (±2,6 jt
  // char, ±13 panggilan runJavaScript) + praproses dari nol setiap
  // trek — moda ±15 dtk pada eksekusi DIRECT per trek terukur di log
  // insiden. Kini worker hidup lintas solve: JS player hanya dikirim
  // bila kuncinya (jsUrl) berubah dan dipraproses SEKALI per versi;
  // solve berikutnya hanya mengirim tantangan. Disiplin anti-gantung
  // utuh: kegagalan/timeout apa pun membuang worker dan percobaan
  // diulang SEKALI dari keadaan bersih dengan player penuh — persis
  // perilaku worker-per-solve yang terbukti di Tahap 2/3.
  String? _ejsBufKey; // kunci player yang JS-nya kini mengisi buffer halaman
  String? _ejsWorkerKey; // kunci player yang sudah dipraproses worker hidup

  Future<EjsSolveOutcome> ejsSolveWorker({
    required String playerJs,
    List<String> nChallenges = const [],
    List<String> sigChallenges = const [],
    String? playerKey,
  }) async {
    if (_ejsWaiter != null) {
      return const EjsSolveOutcome(ok: false, error: 'solve lain sedang berjalan');
    }
    var out = await _ejsSolveWorkerOnce(
        playerJs: playerJs,
        nChallenges: nChallenges,
        sigChallenges: sigChallenges,
        playerKey: playerKey,
        forceFresh: false);
    if (!out.ok) {
      out = await _ejsSolveWorkerOnce(
          playerJs: playerJs,
          nChallenges: nChallenges,
          sigChallenges: sigChallenges,
          playerKey: playerKey,
          forceFresh: true);
    }
    return out;
  }

  Future<EjsSolveOutcome> _ejsSolveWorkerOnce({
    required String playerJs,
    required List<String> nChallenges,
    required List<String> sigChallenges,
    required String? playerKey,
    required bool forceFresh,
  }) async {
    final waiter = Completer<EjsSolveOutcome>();
    _ejsWaiter = waiter;
    try {
      await _ready.future.timeout(const Duration(seconds: 60));
      if (!_ejsAssetsSet) {
        final lib = await rootBundle.loadString('assets/solver/ejs_lib.min.js');
        final core = await rootBundle.loadString('assets/solver/ejs_core.min.js');
        await _controller.runJavaScript(
            'window.__ejsSetAssets && window.__ejsSetAssets(${jsonEncode(lib)}, ${jsonEncode(core)})');
        _ejsAssetsSet = true;
      }
      if (forceFresh) {
        await _controller.runJavaScript('window.__ejsWorkerReset && window.__ejsWorkerReset()');
        _ejsWorkerKey = null;
        _ejsBufKey = null;
      }
      if (playerKey == null || _ejsBufKey != playerKey) {
        await _controller.runJavaScript('window.__ejsPlayerBegin && window.__ejsPlayerBegin()');
        const chunk = 200000;
        for (var i = 0; i < playerJs.length; i += chunk) {
          final end = i + chunk > playerJs.length ? playerJs.length : i + chunk;
          await _controller.runJavaScript(
              'window.__ejsPlayerChunk && window.__ejsPlayerChunk(${jsonEncode(playerJs.substring(i, end))})');
        }
        _ejsBufKey = playerKey;
      }
      final input = jsonEncode({
        'playerKey': playerKey ?? '',
        'hasBuf': true,
        'needPlayer': playerKey == null || _ejsWorkerKey != playerKey,
        'n': nChallenges,
        'sig': sigChallenges,
      });
      await _controller.runJavaScript(
          'window.__claiEjsSolveWorkerKeep && window.__claiEjsSolveWorkerKeep(${jsonEncode(input)})');
    } catch (e) {
      if (identical(_ejsWaiter, waiter)) _ejsWaiter = null;
      return EjsSolveOutcome(ok: false, error: 'panggil JS gagal: $e');
    }
    final out = await waiter.future.timeout(
      const Duration(seconds: 60),
      onTimeout: () {
        if (identical(_ejsWaiter, waiter)) _ejsWaiter = null;
        return const EjsSolveOutcome(ok: false, error: 'timeout 60 dtk menunggu solver (worker)');
      },
    );
    if (out.ok) {
      _ejsWorkerKey = playerKey;
    } else {
      // Worker yang gagal/timeout tidak dipercaya lagi — buang sekarang;
      // percobaan ulang pemanggil mulai dari worker segar.
      _ejsWorkerKey = null;
      try {
        await _controller.runJavaScript('window.__ejsWorkerReset && window.__ejsWorkerReset()');
      } catch (_) {}
    }
    return out;
  }

  /// Evaluasi JS arbitrer di halaman lab dan kembalikan hasilnya sebagai
  /// string (Diagnostik F3 Batch 0, Tahap 2 — menilai fungsi decipher dari
  /// player JS resmi yang diambil segar). Skrip dan hasil HANYA hidup di
  /// memori; pemanggil dilarang mencatat nilai sig/n apa pun.
  Future<String?> evalSolver(String script) async {
    await _ready.future.timeout(const Duration(seconds: 60));
    final r = await _controller
        .runJavaScriptReturningResult(script)
        .timeout(const Duration(seconds: 60));
    if (r is String) {
      // Di Android hasil string JS dibungkus JSON (terkutip) — urai 1 lapis.
      final t = r.trim();
      if (t.startsWith('"')) {
        try {
          final d = jsonDecode(t);
          if (d is String) return d;
        } catch (_) {/* kembalikan apa adanya */}
      }
      return r;
    }
    return r.toString();
  }

  @override
  void dispose() {
    DirectEngineRegistry._detach(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return WebViewWidget(controller: _controller);
  }
}

/// Registri proses untuk mesin DIRECT-1: host produksi memasang SATU
/// [DirectWebEngine] di pohon widget; layanan resolver menunggu mesin itu
/// lewat registri ini (dengan timeout — mesin tak kunjung terpasang berarti
/// jalur gugur ke fallback, bukan menggantung).
class DirectEngineRegistry {
  DirectEngineRegistry._();

  /// Semua instans hidup (host produksi + instans lab Diagnostik bila
  /// layarnya sedang terbuka). Yang dipakai = yang PALING BARU terpasang
  /// dan masih hidup; dispose satu instans jatuh ke instans berikutnya,
  /// bukan ke kekosongan.
  static final Set<DirectWebEngineState> _attached = {};
  static Completer<DirectWebEngineState?>? _waiter;
  static void Function()? _mountRequest;

  static DirectWebEngineState? get current =>
      _attached.isEmpty ? null : _attached.last;

  static void _attach(DirectWebEngineState state) {
    _attached.add(state);
    final w = _waiter;
    _waiter = null;
    if (w != null && !w.isCompleted) w.complete(state);
  }

  static void _detach(DirectWebEngineState state) {
    _attached.remove(state);
  }

  /// Host mendaftarkan cara meminta pemasangan malas di sini.
  static void registerMountRequest(void Function() request) =>
      _mountRequest = request;

  /// Mesin yang terpasang sekarang; bila belum ada, minta host memasangnya
  /// lalu tunggu paling lama [timeout]. Null = tidak tersedia.
  static Future<DirectWebEngineState?> obtain({
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final cur = current;
    if (cur != null) return cur;
    _mountRequest?.call();
    final after = current;
    if (after != null) return after;
    final w = _waiter ??= Completer<DirectWebEngineState?>();
    try {
      return await w.future.timeout(timeout, onTimeout: () => null);
    } finally {
      if (identical(_waiter, w)) _waiter = null;
    }
  }
}

/// Host malas-muat mesin DIRECT-1 untuk pohon aplikasi produksi: dirender
/// sebagai [SizedBox.shrink] sampai layanan resolver pertama kali meminta
/// mesin (atau pre-warm sesudah putar pertama) — WebView tidak dibuat saat
/// mulai dingin dan widget tes tidak pernah melihatnya. Saat terpasang,
/// mesin hidup di lapisan terbawah tumpukan (tertutup konten, tak menerima
/// sentuhan) dengan ukuran nyata 320×96 dp: BotGuard membaca lingkungan
/// halaman yang nyata, sama seperti di lab diagnostik.
class DirectEngineHost extends StatefulWidget {
  const DirectEngineHost({super.key});

  @override
  State<DirectEngineHost> createState() => _DirectEngineHostState();
}

class _DirectEngineHostState extends State<DirectEngineHost> {
  bool _mounted = false;

  @override
  void initState() {
    super.initState();
    DirectEngineRegistry.registerMountRequest(_mount);
  }

  void _mount() {
    if (_mounted || !mounted) return;
    setState(() => _mounted = true);
  }

  @override
  Widget build(BuildContext context) {
    if (!_mounted) return const SizedBox.shrink();
    return const IgnorePointer(
      child: SizedBox(width: 320, height: 96, child: DirectWebEngine()),
    );
  }
}

const _labHtml = '<!DOCTYPE html><html><head><meta charset="utf-8">'
    '<meta name="viewport" content="width=device-width, initial-scale=1">'
    '<style>html,body{background:transparent;margin:0;padding:0}</style>'
    '<title>Clai PoToken Lab</title></head><body><div id="ui"></div></body></html>';

/// Port JS BgUtils (LuanRT/BgUtils, MIT) — ChallengeFetcher.parseChallengeData
/// + descrambleChallenge, BotGuardClient.load/snapshot, WebPoMinter, helpers
/// base64 — ditulis ulang setia untuk berjalan di halaman WebView ini.
/// Perbedaan dari sumber: telemetri/logger VM di-noop-kan; kemajuan & galat
/// dilaporkan lewat kanal ClaiPoToken TANPA nilai token.
const _labJs = r'''
(function () {
  var REQUEST_KEY = 'O43z0dpjhgX20SCx4KAo';
  var GOOG_API_KEY = 'AIzaSyDyT5W0Jh49F30Pqqtyfdf7pDLFKLJoAnw';

  function post(o) { try { window.ClaiPoToken.postMessage(JSON.stringify(o)); } catch (e) {} }
  function progress(stage) { post({ t: 'progress', stage: stage }); }
  function errCls(e) {
    if (!e) return 'unknown';
    var m = (e && e.message) ? e.message : String(e);
    return m.length > 140 ? m.substring(0, 140) : m;
  }
  function withTimeout(p, ms, label) {
    return Promise.race([p, new Promise(function (_, rej) {
      setTimeout(function () { rej(new Error(label || 'timeout')); }, ms);
    })]);
  }

  // ---- helpers base64 (port BgUtils) ----
  function b64ToU8(b64) {
    var mod = b64.replace(/[-_.]/g, function (m) {
      return { '-': '+', '_': '/', '.': '=' }[m];
    });
    if (mod.indexOf('=') === -1) { while (mod.length % 4) mod += '='; }
    var bin = atob(mod);
    var u8 = new Uint8Array(bin.length);
    for (var i = 0; i < bin.length; i++) u8[i] = bin.charCodeAt(i);
    return u8;
  }
  function u8ToB64(u8, urlSafe) {
    var s = '';
    var CH = 0x8000;
    for (var i = 0; i < u8.length; i += CH) {
      s += String.fromCharCode.apply(null, u8.subarray(i, i + CH));
    }
    var r = btoa(s);
    if (urlSafe) r = r.replace(/\+/g, '-').replace(/\//g, '_');
    return r;
  }
  // ---- parseLooseJSON (port BgUtils) ----
  function parseLooseJSON(looseJson) {
    var jsonStr = looseJson.replace(/,\s*([\]}])/g, '$1');
    jsonStr = jsonStr.replace(/'((?:[^'\\]|\\[\s\S])*)'/g, function (_m, inner) {
      return JSON.stringify(inner.replace(/\\'/g, "'"));
    });
    jsonStr = jsonStr.replace(/([{,]\s*)([a-zA-Z0-9_$]+)\s*:/g, '$1"$2":');
    var parsed = JSON.parse(jsonStr);
    function decodeHex(v) {
      return v.replace(/\\x([0-9A-Fa-f]{2})/g, function (_m, hex) {
        return String.fromCharCode(parseInt(hex, 16));
      });
    }
    function normalize(value) {
      if (typeof value === 'string') {
        var decoded = decodeHex(value);
        var trimmed = decoded.trim();
        if (trimmed.charAt(0) === '{' || trimmed.charAt(0) === '[') {
          try { return normalize(JSON.parse(decoded)); } catch (e) { return decoded; }
        }
        return decoded;
      }
      if (Array.isArray(value)) return value.map(normalize);
      if (value && typeof value === 'object') {
        for (var k in value) value[k] = normalize(value[k]);
      }
      return value;
    }
    return normalize(parsed);
  }
  // ---- tantangan WAA/JNN (port ChallengeFetcher) ----
  function waaHeaders() {
    return {
      'content-type': 'application/json+protobuf',
      'x-goog-api-key': GOOG_API_KEY,
      'x-user-agent': 'grpc-web-javascript/0.1'
    };
  }
  function descramble(s) {
    var b = b64ToU8(s);
    for (var i = 0; i < b.length; i++) b[i] = (b[i] + 97) & 0xff;
    return new TextDecoder().decode(b);
  }
  function parseChallengeData(raw) {
    var data = [];
    if (raw && raw.length > 1 && typeof raw[1] === 'string') {
      data = JSON.parse(descramble(raw[1]) || '[]');
    } else if (raw && raw.length && typeof raw[0] === 'object') {
      data = raw[0];
    }
    var ch = { program: data[4], globalName: data[5], interpreterHash: data[3] };
    var ws = data[1], wu = data[2], i, v;
    if (Array.isArray(ws)) for (i = 0; i < ws.length; i++) { v = ws[i]; if (v && typeof v === 'string') { ch.interpreterScript = v; break; } }
    if (Array.isArray(wu)) for (i = 0; i < wu.length; i++) { v = wu[i]; if (v && typeof v === 'string') { ch.interpreterUrl = v; break; } }
    return ch;
  }
  async function fetchChallenge(url) {
    var resp = await fetch(url, { method: 'POST', headers: waaHeaders(), body: JSON.stringify([REQUEST_KEY]) });
    if (!resp.ok) throw new Error('HTTP ' + resp.status);
    return parseChallengeData(await resp.json());
  }
  function challengeFromHtml(html) {
    if (!html) throw new Error('HTML beranda tidak tersedia');
    var atM = html.match(/window\.ytAtN\(\s*({[\s\S]*?})\s*\)/);
    if (!atM) throw new Error('ytAtN tidak ditemukan di HTML beranda');
    var data = parseLooseJSON(atM[1]);
    var r = data && data.R;
    if (!r || !r.bgChallenge) throw new Error('bgChallenge tidak ada di ytAtN.R');
    var bg = r.bgChallenge;
    var ch = { program: bg.program, globalName: bg.globalName };
    if (bg.interpreterUrl && bg.interpreterUrl.privateDoNotAccessOrElseTrustedResourceUrlWrappedValue)
      ch.interpreterUrl = bg.interpreterUrl.privateDoNotAccessOrElseTrustedResourceUrlWrappedValue;
    if (bg.interpreterJavascript && bg.interpreterJavascript.privateDoNotAccessOrElseSafeScriptWrappedValue)
      ch.interpreterScript = bg.interpreterJavascript.privateDoNotAccessOrElseSafeScriptWrappedValue;
    return ch;
  }
  // ---- interpreter ----
  async function loadInterpreter(ch) {
    var url = null;
    if (ch.interpreterUrl) url = ch.interpreterUrl.indexOf('http') === 0 ? ch.interpreterUrl : 'https:' + ch.interpreterUrl;
    if (url) {
      try {
        await new Promise(function (res, rej) {
          var s = document.createElement('script');
          s.src = url;
          s.onload = function () { res(); };
          s.onerror = function () { rej(new Error('script-tag onerror')); };
          document.head.appendChild(s);
        });
        if (window[ch.globalName]) return 'script-tag';
      } catch (e) { /* lanjut ke fetch-eval */ }
      var txt = await (await fetch(url)).text();
      new Function(txt)();
      if (window[ch.globalName]) return 'fetch-eval';
      throw new Error('interpreter dimuat tapi global VM tidak muncul');
    }
    if (ch.interpreterScript) {
      var s2 = document.createElement('script');
      s2.textContent = ch.interpreterScript;
      document.head.appendChild(s2);
      if (window[ch.globalName]) return 'inline';
      throw new Error('interpreter inline tidak mendaftarkan global VM');
    }
    throw new Error('tantangan tanpa interpreter');
  }
  // ---- BotGuard (port BotGuardClient.load + snapshot) ----
  async function bgRun(ch) {
    var vm = window[ch.globalName];
    if (!vm) throw new Error('EGOU: BotGuard unavailable');
    if (!vm.a) throw new Error('ELIU: init function unavailable');
    var resolveFns;
    var fnsPromise = new Promise(function (r) { resolveFns = r; });
    var setup = function (a, b, c, d) {
      resolveFns({ asyncSnapshotFunction: a, shutdownFunction: b, passEventFunction: c, checkCameraFunction: d });
    };
    var noop = function () {};
    var loggers = [noop, noop, noop, noop, noop];
    var telemetry = function () {};
    vm.a(ch.program, setup, true, document.body, telemetry, [[], []], undefined, false, loggers);
    var fns = await withTimeout(fnsPromise, 20000, 'VM tidak memanggil callback setup');
    if (!fns || typeof fns.asyncSnapshotFunction !== 'function')
      throw new Error('asyncSnapshotFunction tidak tersedia');
    var webPoSignalOutput = [];
    var botguardResponse = await new Promise(function (resolve, reject) {
      var to = setTimeout(function () { reject(new Error('snapshot timeout')); }, 30000);
      try {
        fns.asyncSnapshotFunction(function (resp) { clearTimeout(to); resolve(resp); },
          [undefined, undefined, webPoSignalOutput, undefined]);
      } catch (e) { clearTimeout(to); reject(e); }
    });
    if (typeof botguardResponse !== 'string' || !botguardResponse)
      throw new Error('botguardResponse kosong');
    return { botguardResponse: botguardResponse, webPoSignalOutput: webPoSignalOutput };
  }
  // ---- GenerateIT ----
  async function generateIT(botguardResponse) {
    var urls = [
      'https://www.youtube.com/api/jnn/v1/GenerateIT',
      'https://jnn-pa.googleapis.com/$rpc/google.internal.waa.v1.Waa/GenerateIT'
    ];
    var lastErr = null;
    for (var i = 0; i < urls.length; i++) {
      try {
        var resp = await fetch(urls[i], { method: 'POST', headers: waaHeaders(), body: JSON.stringify([REQUEST_KEY, botguardResponse]) });
        if (!resp.ok) throw new Error('HTTP ' + resp.status);
        var j = await resp.json();
        if (Array.isArray(j) && typeof j[0] === 'string' && j[0])
          return { integrityToken: j[0], ttl: (typeof j[1] === 'number' ? j[1] : null) };
        throw new Error('bentuk respons tak dikenal');
      } catch (e) {
        lastErr = e;
        progress('GenerateIT via ' + (i === 0 ? 'JNN' : 'WAA') + ' gagal: ' + errCls(e));
      }
    }
    throw lastErr || new Error('GenerateIT gagal');
  }
  // ---- WebPoMinter (port) ----
  async function makeMinter(integrityToken, webPoSignalOutput) {
    var getMinter = webPoSignalOutput[0];
    if (!getMinter) throw new Error('PMD:Undefined');
    var mintCb = await getMinter(b64ToU8(integrityToken));
    if (typeof mintCb !== 'function') throw new Error('APF:Failed');
    return async function (identifier) {
      var out = await mintCb(new TextEncoder().encode(identifier));
      if (!out) throw new Error('YNJ:Undefined');
      return u8ToB64(out, true);
    };
  }

  async function ensureSession() {
    if (window.__claiSession) {
      var s0 = window.__claiSession;
      post({ t: 'session', ok: true, route: s0.route, interpreter: s0.interpreter, mintMs: s0.mintMs, ttl: s0.ttl || 0, visitorData: s0.visitorData || '', visitorToken: s0.visitorToken || '' });
      return;
    }
    var errors = [];
    var html = null, visitorData = null;
    try {
      progress('prep: ambil HTML beranda youtube.com');
      var resp = await fetch('https://www.youtube.com/', { credentials: 'include' });
      html = await resp.text();
      var cfgM = html.match(/ytcfg\.set\(({.+?})\);/s);
      if (cfgM) {
        try {
          var cfg = JSON.parse(cfgM[1]);
          window.yt = { config_: cfg };
          if (cfg.VISITOR_DATA) visitorData = cfg.VISITOR_DATA;
        } catch (e) {}
      }
      progress('prep: ytcfg ' + ((window.yt && window.yt.config_) ? 'terpasang (EVENT_ID ' + (window.yt.config_.EVENT_ID ? 'ada' : 'tidak ada') + ')' : 'tidak ditemukan') + ' · visitorData ' + (visitorData ? 'ada' : 'tidak ada'));
    } catch (e) {
      progress('prep GAGAL: ' + errCls(e));
    }
    var routes = [
      ['PAGE', function () { return challengeFromHtml(html); }],
      ['JNN', function () { return fetchChallenge('https://www.youtube.com/api/jnn/v1/Create'); }],
      ['WAA', function () { return fetchChallenge('https://jnn-pa.googleapis.com/$rpc/google.internal.waa.v1.Waa/Create'); }]
    ];
    for (var i = 0; i < routes.length; i++) {
      var name = routes[i][0];
      try {
        progress('rute ' + name + ': ambil tantangan');
        var t0 = Date.now();
        var ch = await withTimeout(routes[i][1](), 30000, 'tantangan timeout');
        if (!ch.program || !ch.globalName) throw new Error('tantangan tidak lengkap (program/globalName kosong)');
        progress('rute ' + name + ': muat interpreter');
        var interp = await withTimeout(loadInterpreter(ch), 30000, 'interpreter timeout');
        progress('rute ' + name + ': snapshot BotGuard');
        var snap = await withTimeout(bgRun(ch), 60000, 'botguard timeout');
        progress('rute ' + name + ': GenerateIT');
        var it = await withTimeout(generateIT(snap.botguardResponse), 30000, 'GenerateIT timeout');
        var mintFn = await makeMinter(it.integrityToken, snap.webPoSignalOutput);
        var session = {
          route: name, interpreter: interp, mintFn: mintFn,
          ttl: it.ttl, visitorData: visitorData, mintMs: Date.now() - t0, visitorToken: null
        };
        if (visitorData) {
          try { session.visitorToken = await mintFn(visitorData); }
          catch (e) { progress('token visitor GAGAL: ' + errCls(e)); }
        }
        window.__claiSession = session;
        post({ t: 'session', ok: true, route: session.route, interpreter: session.interpreter, mintMs: session.mintMs, ttl: session.ttl || 0, visitorData: session.visitorData || '', visitorToken: session.visitorToken || '' });
        return;
      } catch (e) {
        var cls = errCls(e);
        errors.push(name + ': ' + cls);
        progress('rute ' + name + ' GAGAL: ' + cls);
      }
    }
    post({ t: 'session', ok: false, errors: errors });
  }

  window.__claiEnsure = function () {
    ensureSession().catch(function (e) {
      post({ t: 'session', ok: false, errors: ['fatal: ' + errCls(e)] });
    });
  };
  window.__claiMint = function (videoId) {
    (async function () {
      var s = window.__claiSession;
      if (!s) { post({ t: 'mint', ok: false, videoId: videoId, cls: 'sesi belum ada' }); return; }
      var t0 = Date.now();
      try {
        var tok = await s.mintFn(videoId);
        post({ t: 'mint', ok: true, videoId: videoId, token: tok, mintMs: Date.now() - t0 });
      } catch (e) {
        post({ t: 'mint', ok: false, videoId: videoId, cls: errCls(e) });
      }
    })();
  };

  // ---- Sesi dari HTML halaman watch yang diberikan (Tahap 2, E1) ----
  // Sama seperti rute PAGE ensureSession, tetapi HTML-nya halaman watch
  // subjek (tantangan ytAtN + ytcfg halaman itu) dan hanya rute ini.
  var htmlBuf = '';
  window.__claiHtmlBegin = function () { htmlBuf = ''; };
  window.__claiHtmlChunk = function (s) { htmlBuf += s; };
  window.__claiEnsurePage = function () {
    (async function () {
      var html = htmlBuf; htmlBuf = '';
      try {
        if (!html) throw new Error('HTML watch kosong');
        var visitorData = null;
        var cfgM = html.match(/ytcfg\.set\(({.+?})\);/s);
        if (cfgM) {
          try {
            var cfg = JSON.parse(cfgM[1]);
            window.yt = { config_: cfg };
            if (cfg.VISITOR_DATA) visitorData = cfg.VISITOR_DATA;
          } catch (e) {}
        }
        progress('WATCH: ytcfg ' + (visitorData
          ? 'terpasang (VD ' + visitorData.length + ' char, EVENT_ID ' + ((window.yt && window.yt.config_ && window.yt.config_.EVENT_ID) ? 'ada' : 'tidak ada') + ')'
          : 'tidak ditemukan'));
        var t0 = Date.now();
        var ch = challengeFromHtml(html);
        if (!ch.program || !ch.globalName) throw new Error('tantangan halaman tidak lengkap');
        progress('WATCH: muat interpreter');
        var interp = await withTimeout(loadInterpreter(ch), 30000, 'interpreter timeout');
        progress('WATCH: snapshot BotGuard');
        var snap = await withTimeout(bgRun(ch), 60000, 'botguard timeout');
        progress('WATCH: GenerateIT');
        var it = await withTimeout(generateIT(snap.botguardResponse), 30000, 'GenerateIT timeout');
        var mintFn = await makeMinter(it.integrityToken, snap.webPoSignalOutput);
        var session = {
          route: 'WATCH', interpreter: interp, mintFn: mintFn,
          ttl: it.ttl, visitorData: visitorData, mintMs: Date.now() - t0, visitorToken: null
        };
        if (visitorData) {
          try { session.visitorToken = await mintFn(visitorData); }
          catch (e) { progress('WATCH: token visitor GAGAL: ' + errCls(e)); }
        }
        window.__claiSession = session;
        post({ t: 'session', ok: true, route: 'WATCH', interpreter: interp, mintMs: session.mintMs, ttl: session.ttl || 0, visitorData: visitorData || '', visitorToken: session.visitorToken || '' });
      } catch (e) {
        post({ t: 'session', ok: false, errors: ['WATCH: ' + errCls(e)] });
      }
    })();
  };

  // ---- Solver EJS yt-dlp/ejs (Tahap 2, E1/E3) ----
  // Aset meriyah/astring/yt.solver.core dievaluasi Dart lebih dulu
  // (window.jsc). Kode player dikirim per potongan; hasil praproses
  // di-cache per playerKey di halaman ini.
  var ejsPlayerBuf = '';
  var ejsPrepared = {};
  window.__ejsPlayerBegin = function () { ejsPlayerBuf = ''; };
  window.__ejsPlayerChunk = function (s) { ejsPlayerBuf += s; };
  window.__claiEjsSolve = function (inputJson) {
    try {
      var input = JSON.parse(inputJson);
      if (typeof window.jsc !== 'function') throw new Error('jsc tidak termuat');
      var requests = [];
      if (input.n && input.n.length) requests.push({ type: 'n', challenges: input.n });
      if (input.sig && input.sig.length) requests.push({ type: 'sig', challenges: input.sig });
      var out;
      if (input.hasPlayer) {
        out = window.jsc({ type: 'player', player: ejsPlayerBuf, output_preprocessed: true, requests: requests });
        if (out && out.preprocessed_player) ejsPrepared[input.playerKey] = out.preprocessed_player;
      } else {
        var prep = ejsPrepared[input.playerKey];
        if (!prep) throw new Error('player belum dipraproses untuk kunci ini');
        out = window.jsc({ type: 'preprocessed', preprocessed_player: prep, requests: requests });
      }
      var res = { t: 'ejs', ok: true, n: {}, sig: {}, nError: '', sigError: '' };
      var rs = (out && out.responses) || [];
      for (var i = 0; i < rs.length; i++) {
        var kind = requests[i] && requests[i].type;
        if (!kind) continue;
        if (rs[i].type === 'result') res[kind] = rs[i].data || {};
        else res[kind + 'Error'] = (rs[i].error || 'error solver').substring(0, 200);
      }
      post(res);
    } catch (e) {
      post({ t: 'ejs', ok: false, error: errCls(e) });
    }
  };

  // ---- Solver EJS di Web Worker (Tahap 2, lari 5) ----
  // Satu worker BARU per solve, dihentikan sesudahnya: panggilan jsc
  // berulang di benang halaman menggantung (terukur lari 3-4), dan
  // worker tanpa DOM meniru lingkungan node yang terbukti lulus.
  var ejsAssets = null;
  window.__ejsSetAssets = function (libSrc, coreSrc) { ejsAssets = { lib: libSrc, core: coreSrc }; };
  window.__claiEjsSolveWorker = function (inputJson) {
    try {
      if (!ejsAssets) throw new Error('aset solver belum disetor');
      var input = JSON.parse(inputJson);
      if (window.__ejsWorker) { try { window.__ejsWorker.terminate(); } catch (e) {} window.__ejsWorker = null; }
      var driver =
        'self.onmessage = function (e) {\n' +
        '  var m = e.data;\n' +
        '  try {\n' +
        '    var requests = [];\n' +
        '    if (m.n && m.n.length) requests.push({ type: "n", challenges: m.n });\n' +
        '    if (m.sig && m.sig.length) requests.push({ type: "sig", challenges: m.sig });\n' +
        '    var out = jsc({ type: "player", player: m.player, requests: requests });\n' +
        '    var res = { ok: true, n: {}, sig: {}, nError: "", sigError: "" };\n' +
        '    var rs = (out && out.responses) || [];\n' +
        '    for (var i = 0; i < rs.length; i++) {\n' +
        '      var kind = requests[i] && requests[i].type;\n' +
        '      if (!kind) continue;\n' +
        '      if (rs[i].type === "result") res[kind] = rs[i].data || {};\n' +
        '      else res[kind + "Error"] = (rs[i].error || "error solver").substring(0, 200);\n' +
        '    }\n' +
        '    self.postMessage(res);\n' +
        '  } catch (err) {\n' +
        '    self.postMessage({ ok: false, error: String((err && err.message) || err).substring(0, 200) });\n' +
        '  }\n' +
        '};\n';
      var code = ejsAssets.lib +
        '\n;self.meriyah = lib.meriyah; self.astring = lib.astring;\n' +
        ejsAssets.core + '\n' + driver;
      var url = URL.createObjectURL(new Blob([code], { type: 'text/javascript' }));
      var w = new Worker(url);
      window.__ejsWorker = w;
      w.onmessage = function (e) {
        var d = e.data || {};
        d.t = 'ejs';
        post(d);
        try { w.terminate(); } catch (err) {}
        if (window.__ejsWorker === w) window.__ejsWorker = null;
      };
      w.onerror = function (e) {
        post({ t: 'ejs', ok: false, error: 'worker error: ' + (e.message || 'tidak dikenal') });
        try { w.terminate(); } catch (err) {}
        if (window.__ejsWorker === w) window.__ejsWorker = null;
      };
      w.postMessage({ player: ejsPlayerBuf, n: input.n || [], sig: input.sig || [] });
    } catch (e) {
      post({ t: 'ejs', ok: false, error: errCls(e) });
    }
  };

  // ---- Solver EJS di Web Worker PERSISTEN (ronde vonis perangkat) ----
  // Satu worker melayani banyak solve: player dipraproses SEKALI lalu
  // disimpan sebagai preprocessed_player di dalam worker; solve
  // berikutnya hanya mengirim tantangan (tanpa mengulang kirim ±2,6 jt
  // char + praproses penuh). Worker dibuang lewat __ejsWorkerReset
  // (kegagalan/timeout di sisi Dart) dan dibangun ulang pada solve
  // berikutnya — setara disiplin worker-per-solve sebelumnya.
  var ejsKeepWorker = null;
  window.__ejsWorkerReset = function () {
    if (ejsKeepWorker) { try { ejsKeepWorker.terminate(); } catch (e) {} ejsKeepWorker = null; }
  };
  window.__claiEjsSolveWorkerKeep = function (inputJson) {
    try {
      if (!ejsAssets) throw new Error('aset solver belum disetor');
      var input = JSON.parse(inputJson);
      if (!ejsKeepWorker) {
        var driver =
          'var prep = null;\n' +
          'self.onmessage = function (e) {\n' +
          '  var m = e.data;\n' +
          '  try {\n' +
          '    var requests = [];\n' +
          '    if (m.n && m.n.length) requests.push({ type: "n", challenges: m.n });\n' +
          '    if (m.sig && m.sig.length) requests.push({ type: "sig", challenges: m.sig });\n' +
          '    var out;\n' +
          '    if (m.player != null) {\n' +
          '      out = jsc({ type: "player", player: m.player, output_preprocessed: true, requests: requests });\n' +
          '      if (out && out.preprocessed_player) prep = out.preprocessed_player;\n' +
          '    } else {\n' +
          '      if (!prep) throw new Error("player belum dipraproses di worker");\n' +
          '      out = jsc({ type: "preprocessed", preprocessed_player: prep, requests: requests });\n' +
          '    }\n' +
          '    var res = { ok: true, n: {}, sig: {}, nError: "", sigError: "" };\n' +
          '    var rs = (out && out.responses) || [];\n' +
          '    for (var i = 0; i < rs.length; i++) {\n' +
          '      var kind = requests[i] && requests[i].type;\n' +
          '      if (!kind) continue;\n' +
          '      if (rs[i].type === "result") res[kind] = rs[i].data || {};\n' +
          '      else res[kind + "Error"] = (rs[i].error || "error solver").substring(0, 200);\n' +
          '    }\n' +
          '    self.postMessage(res);\n' +
          '  } catch (err) {\n' +
          '    self.postMessage({ ok: false, error: String((err && err.message) || err).substring(0, 200) });\n' +
          '  }\n' +
          '};\n';
        var code = ejsAssets.lib +
          '\n;self.meriyah = lib.meriyah; self.astring = lib.astring;\n' +
          ejsAssets.core + '\n' + driver;
        var url = URL.createObjectURL(new Blob([code], { type: 'text/javascript' }));
        ejsKeepWorker = new Worker(url);
        ejsKeepWorker.onmessage = function (e) {
          var d = e.data || {};
          d.t = 'ejs';
          post(d);
        };
        ejsKeepWorker.onerror = function (e) {
          post({ t: 'ejs', ok: false, error: 'worker error: ' + (e.message || 'tidak dikenal') });
          window.__ejsWorkerReset();
        };
      }
      if (input.needPlayer && !input.hasBuf) {
        post({ t: 'ejs', ok: false, error: 'buffer player kosong untuk solve ini' });
        return;
      }
      ejsKeepWorker.postMessage({
        player: input.needPlayer ? ejsPlayerBuf : null,
        n: input.n || [],
        sig: input.sig || []
      });
    } catch (e) {
      post({ t: 'ejs', ok: false, error: errCls(e) });
    }
  };
})();
''';
