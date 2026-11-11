import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../core/tokens.dart';

/// Laboratorium Login — permukaan DIAGNOSTIK murni (Probe Login
/// "Pintu Terakhir", Batch 0.7 F3, harness v3.12). TIDAK dipakai jalur
/// produksi mana pun.
///
/// Meniru pola sesi Auralys (§2b laporan RE): WebView membuka formulir
/// masuk Google; pengguna masuk dengan akunnya SENDIRI di dalam WebView
/// ini. Sesudah halaman terautentikasi terdeteksi, sesi dipanen PERSIS
/// pola §2b:
///
///   1. string cookie dari CookieManager (WebViewCookieManager — sumber
///      yang sama dengan android.webkit.CookieManager milik Auralys),
///      digabung untuk domain music/www/accounts/google;
///   2. VISITOR_DATA / DATASYNC_ID / SESSION_INDEX via JS suntikan
///      (ytcfg / yt.config_ pada halaman music.youtube.com);
///   3. SAPISID diuraikan dari peta cookie; header otorisasi
///      SAPISIDHASH dibentuk DI MEMORI —
///      `SAPISIDHASH <ts>_<sha1("<ts> <SAPISID> <origin>")>` dengan
///      origin https://music.youtube.com.
///
/// Cookie sesi adalah KREDENSIAL: semua nilai hanya hidup di memori
/// proses (bidang privat + [AuthSessionStore]); TIDAK PERNAH ditulis ke
/// laporan/log/berkas/papan klip. Yang boleh tampil & tercatat hanya
/// NAMA cookie/parameter + PANJANG nilai (lihat [AuthSessionMeta]).
///
/// KONFIGURASI WEBVIEW — diselaraskan ke resep login Auralys 4.3.0
/// (bukti artefak RE: dexdump kelas
/// `Lcom/metrolist/music/ui/screens/LoginScreenKt$$ExternalSyntheticLambda0;`,
/// pabrik WebView layar login Metrolist). Percobaan pertama riyan
/// (2026-11-08) ditolak Google "This browser or app may not be secure";
/// resep Auralys terbaca sebagai berikut dan diikuti persis:
///   * User-Agent TIDAK disetel sama sekali — UA bawaan WebView
///     Android. (`setUserAgentString` di seluruh DEX Auralys hanya ada
///     di PoTokenWebView, bukan layar login.) Versi v3.11 lab ini
///     menyetel UA desktop Windows kustom — dicabut.
///   * URL masuk login segar dimuat LANGSUNG:
///     `https://accounts.google.com/ServiceLogin?continue=https%3A%2F%2Fmusic.youtube.com`
///     — tanpa parameter `service=`/`hl=` tambahan. (Cabang lain di
///     kelas yang sama — sesi tersimpan — menyuntik ulang cookie ke
///     music.youtube.com; tidak relevan untuk login segar.)
///   * JavaScript aktif + DOM storage aktif (kita: JavaScriptMode
///     unrestricted; DOM storage diterapkan plugin
///     webview_flutter_android saat controller dibuat — sama).
///   * CookieManager.setAcceptCookie(true); setAcceptThirdPartyCookies
///     TIDAK dipanggil di mana pun di DEX — kita pun tidak menyetelnya
///     (bawaan platform di kedua sisi).

/// Sesi terautentikasi terpanen — nilai sesungguhnya, MEMORI SAJA.
class AuthSession {
  /// Peta nama→nilai cookie dari CookieManager (gabungan domain).
  final Map<String, String> cookies;
  final String? visitorData;
  final String? datasyncId;
  final String? sessionIndex;

  const AuthSession({
    required this.cookies,
    this.visitorData,
    this.datasyncId,
    this.sessionIndex,
  });

  /// Nilai header Cookie utuh untuk permintaan youtubei (memori saja).
  String get cookieHeader =>
      cookies.entries.map((e) => '${e.key}=${e.value}').join('; ');

  /// Nama cookie sumber SAPISID yang dipakai (untuk laporan: nama saja).
  String? get sapisidName {
    if (cookies.containsKey('SAPISID')) return 'SAPISID';
    if (cookies.containsKey('__Secure-3PAPISID')) return '__Secure-3PAPISID';
    if (cookies.containsKey('APISID')) return 'APISID';
    return null;
  }

  String? get sapisid {
    final n = sapisidName;
    return n == null ? null : cookies[n];
  }

  /// Header Authorization SAPISIDHASH — dihitung segar di memori setiap
  /// panggilan (stempel waktu detik). Null bila SAPISID tidak ada.
  String? authorization() {
    final sid = sapisid;
    if (sid == null) return null;
    final ts = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final digest =
        sha1.convert(utf8.encode('$ts $sid https://music.youtube.com'));
    return 'SAPISIDHASH ${ts}_$digest';
  }

  AuthSessionMeta get meta => AuthSessionMeta(
        cookieNames: cookies.keys.toList()..sort(),
        cookieHeaderLen: cookieHeader.length,
        sapisidName: sapisidName,
        sapisidLen: sapisid?.length ?? 0,
        visitorDataLen: visitorData?.length ?? 0,
        datasyncAda: datasyncId != null && datasyncId!.isNotEmpty,
        sessionIndexLen: sessionIndex?.length ?? 0,
      );
}

/// Ringkasan AMAN-LOG dari [AuthSession]: nama + panjang saja.
class AuthSessionMeta {
  final List<String> cookieNames;
  final int cookieHeaderLen;
  final String? sapisidName;
  final int sapisidLen;
  final int visitorDataLen;
  final bool datasyncAda;
  final int sessionIndexLen;

  const AuthSessionMeta({
    required this.cookieNames,
    required this.cookieHeaderLen,
    required this.sapisidName,
    required this.sapisidLen,
    required this.visitorDataLen,
    required this.datasyncAda,
    required this.sessionIndexLen,
  });

  bool get lengkap => sapisidName != null;

  String ringkas() => 'cookie ${cookieNames.length} nama '
      '[${cookieNames.join(', ')}] · header $cookieHeaderLen char · '
      'SAPISID via ${sapisidName ?? '(tidak ada)'} ($sapisidLen char) · '
      'VISITOR_DATA $visitorDataLen char · '
      'DATASYNC ${datasyncAda ? 'ada' : 'tidak ada'} · '
      'SESSION_INDEX $sessionIndexLen char';
}

/// Wadah sesi lintas-layar selama proses hidup: layar Lab Login menulis,
/// Matriks L (Diagnostik Putar) membaca. Tidak pernah dipersistenkan.
class AuthSessionStore {
  AuthSessionStore._();
  static final AuthSessionStore instance = AuthSessionStore._();
  AuthSession? session;
}

/// Layar penuh Lab Login: WebView YouTube Music untuk login manual
/// pemilik akun + panen sesi otomatis/manual ke [AuthSessionStore].
class LoginLabScreen extends StatefulWidget {
  const LoginLabScreen({super.key});

  @override
  State<LoginLabScreen> createState() => _LoginLabScreenState();
}

class _LoginLabScreenState extends State<LoginLabScreen> {
  /// URL masuk login segar PERSIS resep Auralys (konstanta string di
  /// pabrik WebView LoginScreenKt, dimuat langsung via loadUrl):
  /// ServiceLogin dengan hanya parameter `continue` ke YouTube Music.
  static const _loginUrl =
      'https://accounts.google.com/ServiceLogin?continue=https%3A%2F%2Fmusic.youtube.com';

  late final WebViewController _controller;
  Timer? _poll;
  String _status = 'Memuat formulir masuk Google…';
  String _host = '-';
  int _navAttempts = 0;
  bool _directNavDone = false;
  bool _harvesting = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      // User-Agent SENGAJA tidak disetel: resep Auralys membiarkan UA
      // bawaan WebView Android (lihat catatan konfigurasi di atas).
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (url) => _afterPage(url),
        onNavigationRequest: (req) => NavigationDecision.navigate,
      ))
      ..loadRequest(Uri.parse(_loginUrl));
    _poll = Timer.periodic(const Duration(seconds: 3), (_) => _pollSession());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  void _setStatus(String s) {
    if (mounted) setState(() => _status = s);
  }

  Future<String?> _evalString(String js) async {
    try {
      final r = await _controller
          .runJavaScriptReturningResult(js)
          .timeout(const Duration(seconds: 20));
      if (r is String) {
        final t = r.trim();
        if (t.startsWith('"')) {
          try {
            final d = jsonDecode(t);
            if (d is String) return d;
          } catch (_) {/* apa adanya */}
        }
        return r;
      }
      return r.toString();
    } catch (_) {
      return null;
    }
  }

  Future<void> _afterPage(String url) async {
    final uri = Uri.tryParse(url);
    _host = uri?.host ?? '-';
    if (AuthSessionStore.instance.session != null) return;
    // Formulir masuk sudah tampil → berhenti menavigasi; pengguna yang
    // mengetik dari sini.
    if ((await _evalString(_formJs)) == '1') {
      _setStatus('Formulir masuk Google siap — silakan masuk dengan '
          'akunmu. Sesi terpanen otomatis sesudahnya.');
      return;
    }
    if (_host == 'music.youtube.com') {
      if ((await _evalString(_loggedInJs)) == '1') {
        await harvest();
        return;
      }
    }
    // Di dalam alur masuk Google sendiri (accounts.google.com) mesin
    // navigasi TIDAK ikut campur — pengguna yang mengemudi dari sini
    // (selaras resep Auralys: formulir dimuat langsung, tanpa klik
    // otomatis di halaman Google).
    if (_host == 'accounts.google.com') {
      _setStatus('Di alur masuk Google — selesaikan masuk dengan '
          'akunmu. Sesi terpanen otomatis sesudahnya.');
      return;
    }
    // Belum di formulir & belum masuk: ikuti tautan/tombol masuk MILIK
    // SITUS di halaman mana pun kita berada (setara ketukan pengguna).
    // Warisan jalur lama (masuk lewat halaman tamu YouTube Music); kini
    // hanya jaring pengaman bila pendaratan menyimpang dari formulir.
    // TIDAK PERNAH mengisi apa pun.
    if (_navAttempts < 6) {
      _navAttempts++;
      await Future<void>.delayed(const Duration(seconds: 2));
      final how = await _evalString(_signInClickJs);
      if (how != null && how != 'none') {
        _setStatus('Menuju formulir masuk (tautan situs: $how)…');
        return;
      }
    }
    // Jalan terakhir: navigasi langsung ke ServiceLogin PERSIS resep
    // Auralys (hanya parameter continue — tanpa service=/hl=).
    if (!_directNavDone) {
      _directNavDone = true;
      _navAttempts = 0;
      _setStatus('Membuka formulir masuk Google untuk YouTube Music…');
      await _controller.loadRequest(Uri.parse(_loginUrl));
    }
  }

  /// Polling sesi: sinyal JS LOGGED_IN (di host youtube) ATAU kehadiran
  /// SAPISID di CookieManager memicu panen penuh.
  Future<void> _pollSession() async {
    if (_harvesting || AuthSessionStore.instance.session != null) return;
    var signal = false;
    if (_host.contains('youtube.com')) {
      signal = (await _evalString(_loggedInJs)) == '1';
    }
    if (!signal) {
      try {
        final list = await WebViewCookieManager()
            .getCookies(domain: Uri.parse('https://music.youtube.com'));
        signal = list.any((c) =>
            c.name == 'SAPISID' ||
            c.name == '__Secure-3PAPISID' ||
            c.name == 'APISID');
      } catch (_) {/* abaikan — coba lagi siklus berikut */}
    }
    if (signal) await harvest();
  }

  /// Panen sesi PERSIS pola §2b Auralys. Nilai hanya ke memori; status
  /// yang tampil adalah ringkasan aman-log (nama + panjang).
  Future<void> harvest() async {
    if (_harvesting) return;
    _harvesting = true;
    _setStatus('Memamen sesi…');
    try {
      final cm = WebViewCookieManager();
      final merged = <String, String>{};
      for (final u in const [
        'https://music.youtube.com',
        'https://www.youtube.com',
        'https://accounts.google.com',
        'https://www.google.com',
      ]) {
        try {
          final list = await cm.getCookies(domain: Uri.parse(u));
          for (final c in list) {
            merged.putIfAbsent(c.name, () => c.value);
          }
        } catch (_) {/* domain gagal — lanjut */}
      }
      String? vd, ds, si;
      final raw = await _evalString(_harvestJs);
      if (raw != null && raw.isNotEmpty) {
        try {
          final m = (jsonDecode(raw) as Map).cast<String, dynamic>();
          String take(String k) => '${m[k] ?? ''}';
          if (take('vd').isNotEmpty) vd = take('vd');
          if (take('ds').isNotEmpty) ds = take('ds');
          if (take('si').isNotEmpty) si = take('si');
        } catch (_) {/* JS harvest gagal — cookie saja mungkin cukup */}
      }
      final session = AuthSession(
        cookies: merged,
        visitorData: vd,
        datasyncId: ds,
        sessionIndex: (si != null && si.isNotEmpty) ? si : null,
      );
      if (session.sapisid == null) {
        _setStatus('Sesi login belum terbentuk: SAPISID belum ada di '
            'CookieManager (${merged.length} nama cookie terpanen). '
            'Selesaikan login dulu, lalu panen lagi.');
        return;
      }
      AuthSessionStore.instance.session = session;
      _setStatus('SESI TERPANEN ✓ — ${session.meta.ringkas()}. '
          'Kembali ke Diagnostik Putar dan jalankan Matriks L.');
    } finally {
      _harvesting = false;
    }
  }

  Future<void> _clearAll() async {
    try {
      await WebViewCookieManager().clearCookies();
    } catch (_) {/* abaikan */}
    AuthSessionStore.instance.session = null;
    _navAttempts = 0;
    _directNavDone = false;
    _setStatus('Cookie WebView dibersihkan. Memuat ulang formulir masuk…');
    await _controller.loadRequest(Uri.parse(_loginUrl));
  }

  @override
  Widget build(BuildContext context) {
    final meta = AuthSessionStore.instance.session?.meta;
    return Scaffold(
      backgroundColor: ClaiColors.base,
      appBar: AppBar(
        backgroundColor: ClaiColors.surface1,
        foregroundColor: ClaiColors.ink,
        title: const Text('Lab Login — Diagnostik',
            style: TextStyle(fontSize: 16)),
      ),
      body: Column(children: [
        Container(
          width: double.infinity,
          color: ClaiColors.surface2,
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Host: $_host',
                style: const TextStyle(
                    color: ClaiColors.inkSecondary, fontSize: 12)),
            const SizedBox(height: 4),
            Text(_status,
                style: const TextStyle(color: ClaiColors.ink, fontSize: 13)),
            if (meta != null) ...[
              const SizedBox(height: 4),
              Text(meta.ringkas(),
                  style: const TextStyle(
                      color: ClaiColors.inkSecondary,
                      fontSize: 11,
                      fontFamily: 'monospace')),
            ],
            const SizedBox(height: 6),
            const Text(
                'Masuk dengan akunmu sendiri di WebView ini. Nilai cookie '
                'hanya hidup di memori aplikasi — tidak pernah ditulis ke '
                'laporan/log/berkas; yang tampil hanya nama + panjang.',
                style: TextStyle(color: ClaiColors.inkFaint, fontSize: 11)),
          ]),
        ),
        Expanded(child: WebViewWidget(controller: _controller)),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
            child: Wrap(spacing: 8, runSpacing: 8, children: [
              FilledButton(
                style: FilledButton.styleFrom(
                    backgroundColor: ClaiColors.accent,
                    foregroundColor: ClaiColors.onAccent),
                onPressed: _harvesting ? null : harvest,
                child: const Text('Panen Sesi'),
              ),
              OutlinedButton(
                onPressed: () =>
                    _controller.loadRequest(Uri.parse(_loginUrl)),
                child: const Text('Muat Ulang'),
              ),
              OutlinedButton(
                onPressed: _clearAll,
                child: const Text('Bersihkan Cookie'),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}

/// JS: '1' bila halaman menyatakan pengguna sudah masuk.
const _loggedInJs = r'''
(function () {
  try {
    if (window.ytcfg && ytcfg.get && ytcfg.get('LOGGED_IN') === true) return '1';
    var c = (window.yt && window.yt.config_) || {};
    if (c.LOGGED_IN === true || c.LOGGED_IN === 'true') return '1';
  } catch (e) {}
  return '0';
})()
''';

/// JS: '1' bila halaman saat ini adalah formulir masuk Google (ada
/// kolom identifier/email, atau URL jalur signin/ServiceLogin).
const _formJs = r'''
(function () {
  try {
    if (document.querySelector('input[type="email"], input[name="identifier"], #identifierId')) return '1';
    if (location.href.indexOf('/signin/') >= 0 || location.href.indexOf('ServiceLogin') >= 0) return '1';
  } catch (e) {}
  return '0';
})()
''';

/// JS: klik tautan/tombol masuk MILIK SITUS (setara ketukan pengguna).
/// Urutan: jangkar ServiceLogin → jangkar accounts.google.com → teks
/// persis "sign in"/"masuk"/"login". Mengembalikan cara yang dipakai
/// ('anchor'/'text'/'none') — tanpa nilai apa pun selain kelas cara.
const _signInClickJs = r'''
(function () {
  try {
    var s1 = document.querySelectorAll('a[href*="ServiceLogin"]');
    for (var i = 0; i < s1.length; i++) { s1[i].click(); return 'anchor'; }
    var s2 = document.querySelectorAll('a[href*="accounts.google.com"]');
    for (var k = 0; k < s2.length; k++) { s2[k].click(); return 'anchor'; }
    var els = document.querySelectorAll('button, a, tp-yt-paper-button, ytmusic-sign-in-button-renderer, yt-button-renderer');
    for (var j = 0; j < els.length; j++) {
      var t = (els[j].textContent || '').trim().toLowerCase();
      if (t === 'sign in' || t === 'masuk' || t === 'login') { els[j].click(); return 'text'; }
    }
  } catch (e) {}
  return 'none';
})()
''';

/// JS panen nilai konfigurasi sesi dari halaman (VISITOR_DATA /
/// DATASYNC_ID / SESSION_INDEX) — nilai kembali ke Dart lewat hasil
/// evaluasi dan hanya hidup di memori.
const _harvestJs = r'''
(function () {
  var out = { vd: '', ds: '', si: '' };
  function g(k) {
    try { if (window.ytcfg && ytcfg.get) { var v = ytcfg.get(k); if (v !== undefined && v !== null) return '' + v; } } catch (e) {}
    try { var c = (window.yt && window.yt.config_) || {}; if (c[k] !== undefined && c[k] !== null) return '' + c[k]; } catch (e) {}
    return '';
  }
  out.vd = g('VISITOR_DATA');
  out.ds = g('DATASYNC_ID');
  out.si = g('SESSION_INDEX');
  return JSON.stringify(out);
})()
''';
