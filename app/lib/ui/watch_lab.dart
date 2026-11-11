import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Laboratorium Halaman Watch — permukaan DIAGNOSTIK murni (Probe Sesi
/// Tamu WebView, Batch 0.6 F3, harness v3.10). TIDAK dipakai jalur
/// produksi mana pun.
///
/// Berbeda dari [PoTokenLab] (halaman lokal berorigin youtube), lab ini
/// memuat HALAMAN WATCH SUNGGUHAN sebagai tamu anonim — tanpa login,
/// tanpa akun — agar sesi tamu yang dibentuk halaman sendiri (cookie
/// halaman, yt.config_, pemutar halaman) bisa dipanen dan dipakai:
///
///   E1 panen ringkasan aman-log (VISITOR_DATA: nama+panjang saja;
///      nama cookie; ringkasan ytInitialPlayerResponse milik halaman).
///   E2 URL terbitan halaman (dari ytInitialPlayerResponse atau entri
///      performance pemutar) diteruskan ke pemanggil untuk diuji di
///      luar WebView — nilainya hanya hidup di memori, TIDAK PERNAH
///      ditulis ke laporan/log/berkas (yang dicatat: host, nama
///      parameter, panjang).
///   E3 pemutar halaman dipantau lewat JS (currentTime/buffered).
///   E4 fetch SABR dari dalam halaman (credentials: include) sebagai
///      transport yang dapat disuntikkan ke mesin SABR diagnostik.
class WatchPageFormat {
  final int itag;
  final int bitrate;
  final int contentLength;
  final bool hasUrl;
  final bool hasCipher;
  final String mime;
  const WatchPageFormat({
    required this.itag,
    required this.bitrate,
    required this.contentLength,
    required this.hasUrl,
    required this.hasCipher,
    required this.mime,
  });
}

class WatchPageSummary {
  final bool loaded;
  final String host;
  final int visitorDataLen;
  final bool datasyncAda;
  final List<String> cookieNames;
  final bool iprAda;
  final String playability;
  final List<WatchPageFormat> audioFormats;
  final bool abrUrlAda;
  final String note;
  const WatchPageSummary({
    required this.loaded,
    required this.host,
    required this.visitorDataLen,
    required this.datasyncAda,
    required this.cookieNames,
    required this.iprAda,
    required this.playability,
    required this.audioFormats,
    required this.abrUrlAda,
    required this.note,
  });
  factory WatchPageSummary.galat(String host, String note) => WatchPageSummary(
        loaded: false,
        host: host,
        visitorDataLen: 0,
        datasyncAda: false,
        cookieNames: const [],
        iprAda: false,
        playability: '-',
        audioFormats: const [],
        abrUrlAda: false,
        note: note,
      );
}

class WatchPlayState {
  final double currentTime;
  final double duration;
  final double bufferedEnd;
  final bool paused;
  final int readyState;
  final String mediaError; // kelas galat media saja ('-' bila tidak ada)
  const WatchPlayState({
    required this.currentTime,
    required this.duration,
    required this.bufferedEnd,
    required this.paused,
    required this.readyState,
    required this.mediaError,
  });
  factory WatchPlayState.kosong(String err) => WatchPlayState(
      currentTime: 0,
      duration: 0,
      bufferedEnd: 0,
      paused: true,
      readyState: 0,
      mediaError: err);
}

/// Meta aman-log tentang URL yang dipilih dari konteks halaman —
/// nilainya sendiri tidak pernah keluar dari pasangan (JS, memori Dart).
class PickedUrlMeta {
  final bool ok;
  final String source; // ipr / perf / '-'
  final String host;
  final int len;
  final List<String> paramNames;
  const PickedUrlMeta(
      {required this.ok,
      required this.source,
      required this.host,
      required this.len,
      required this.paramNames});
}

class WatchLab extends StatefulWidget {
  final void Function(String stage)? onProgress;
  const WatchLab({super.key, this.onProgress});

  @override
  State<WatchLab> createState() => WatchLabState();
}

class WatchLabState extends State<WatchLab> {
  static const desktopUa =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';

  late final WebViewController _controller;
  Completer<void>? _pageDone;
  String? _pickedUrl; // memori saja — TIDAK PERNAH dicatat
  Completer<String?>? _urlWaiter;
  bool _utilsInjected = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      // Vonis T3 lengan A (perluasan sapuan): tanpa ini WebView mengecat
      // PUTIH bawaan Android di area panel lab pada halaman Diagnostik —
      // akar yang sama dengan pita putih Beranda (DirectWebEngine sudah
      // diobati lebih dulu). Transparan = wadah surface2 yang terlihat
      // saat lab diam; halaman watch asli tetap mengecat isinya sendiri
      // saat matriks berjalan.
      ..setBackgroundColor(Colors.transparent)
      ..setUserAgent(desktopUa)
      ..addJavaScriptChannel('ClaiWatch', onMessageReceived: _onChannelMessage)
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) {
          final w = _pageDone;
          if (w != null && !w.isCompleted) w.complete();
        },
      ));
  }

  void _onChannelMessage(JavaScriptMessage message) {
    // Pesan 'url' MEMUAT nilai URL bertanda tangan — jangan pernah dicetak.
    try {
      final decoded = jsonDecode(message.message);
      if (decoded is! Map) return;
      final m = decoded.cast<String, dynamic>();
      if (m['t'] == 'url') {
        final u = m['url'] as String?;
        _pickedUrl = (u != null && u.isNotEmpty) ? u : null;
        final w = _urlWaiter;
        _urlWaiter = null;
        if (w != null && !w.isCompleted) w.complete(_pickedUrl);
      }
    } catch (_) {
      // pesan tak dikenal — abaikan
    }
  }

  Future<String?> _evalString(String js) async {
    try {
      final r = await _controller
          .runJavaScriptReturningResult(js)
          .timeout(const Duration(seconds: 30));
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

  Future<void> _runJs(String js) async {
    try {
      await _controller.runJavaScript(js);
    } catch (_) {/* halaman belum siap — pemanggil memancing ulang */}
  }

  /// Muat halaman watch [videoId] (www atau music) dan tunggu sampai
  /// ytInitialPlayerResponse muncul (maks ±30 dtk), lalu suntik utilitas.
  Future<void> loadWatch(String videoId, {bool music = false}) async {
    _utilsInjected = false;
    _pickedUrl = null;
    final host = music ? 'music.youtube.com' : 'www.youtube.com';
    final done = Completer<void>();
    _pageDone = done;
    await _controller.loadRequest(Uri.parse('https://$host/watch?v=$videoId'));
    try {
      await done.future.timeout(const Duration(seconds: 45));
    } catch (_) {/* lanjut ke polling */}
    // Beri waktu pemutar tamu berinisialisasi; suntik utilitas begitu
    // dokumen cukup stabil, lalu tunggu ipr.
    for (var i = 0; i < 30; i++) {
      if (!_utilsInjected) {
        await _runJs(_utilsJs);
        _utilsInjected = true;
      }
      final ada = await _evalString('window.ytInitialPlayerResponse ? "1" : "0"');
      if (ada == '1') break;
      // Upaya lepas dari dinding persetujuan (consent) bila muncul —
      // hanya tombol persetujuan, TIDAK PERNAH tombol masuk/login.
      if (i == 4) await _runJs(_consentJs);
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    await Future<void>.delayed(const Duration(seconds: 2));
  }

  /// E1 — panen ringkasan aman-log dari halaman yang sedang dimuat.
  Future<WatchPageSummary> harvest(String videoId, {bool music = false}) async {
    final host = music ? 'music.youtube.com' : 'www.youtube.com';
    final raw = await _evalString('window.__claiW ? window.__claiW.summary() : ""');
    if (raw == null || raw.isEmpty) {
      return WatchPageSummary.galat(host, 'utilitas halaman tidak menjawab');
    }
    try {
      final m = (jsonDecode(raw) as Map).cast<String, dynamic>();
      return WatchPageSummary(
        loaded: true,
        host: host,
        visitorDataLen: (m['vdLen'] as num?)?.toInt() ?? 0,
        datasyncAda: m['ds'] == true,
        cookieNames: [
          for (final e in (m['cookies'] as List? ?? const [])) '$e',
        ],
        iprAda: m['ipr'] == true,
        playability: '${m['play'] ?? '-'}',
        audioFormats: [
          for (final e in (m['fmts'] as List? ?? const []))
            if (e is Map)
              WatchPageFormat(
                itag: (e['itag'] as num?)?.toInt() ?? 0,
                bitrate: (e['br'] as num?)?.toInt() ?? 0,
                contentLength: (e['cl'] as num?)?.toInt() ?? 0,
                hasUrl: e['url'] == true,
                hasCipher: e['cipher'] == true,
                mime: '${e['mime'] ?? ''}',
              ),
        ],
        abrUrlAda: m['abr'] == true,
        note: '${m['err'] ?? ''}',
      );
    } catch (e) {
      return WatchPageSummary.galat(host, 'urai ringkasan gagal: $e');
    }
  }

  /// E2 — minta JS memilih URL audio [itag] dari sumber [source]
  /// ('ipr' = ytInitialPlayerResponse langsung; 'perf' = entri
  /// performance pemutar). Kembalikan meta aman-log; URL-nya sendiri
  /// diambil lewat [takePickedUrl] (memori saja).
  Future<PickedUrlMeta> pickUrl(int itag, String source) async {
    _pickedUrl = null;
    await _runJs('window.__claiW && window.__claiW.pick(${jsonEncode(source)}, $itag)');
    final raw = await _evalString('window.__claiW ? window.__claiW.pickMeta() : ""');
    if (raw == null || raw.isEmpty) {
      return const PickedUrlMeta(ok: false, source: '-', host: '-', len: 0, paramNames: []);
    }
    try {
      final m = (jsonDecode(raw) as Map).cast<String, dynamic>();
      return PickedUrlMeta(
        ok: m['ok'] == true,
        source: '${m['src'] ?? '-'}',
        host: '${m['host'] ?? '-'}',
        len: (m['len'] as num?)?.toInt() ?? 0,
        paramNames: [
          for (final e in (m['params'] as List? ?? const [])) '$e',
        ],
      );
    } catch (_) {
      return const PickedUrlMeta(ok: false, source: '-', host: '-', len: 0, paramNames: []);
    }
  }

  /// Ambil URL yang dipilih [pickUrl] lewat kanal (menunggu maks 10 dtk).
  Future<String?> takePickedUrl() async {
    if (_pickedUrl != null) return _pickedUrl;
    final w = Completer<String?>();
    _urlWaiter = w;
    await _runJs('window.__claiW && window.__claiW.sendPicked()');
    try {
      return await w.future.timeout(const Duration(seconds: 10));
    } catch (_) {
      return null;
    }
  }

  /// E3 — perintahkan pemutar halaman memutar.
  Future<String> play() async {
    final r = await _evalString('window.__claiW ? window.__claiW.play() : "no-utils"');
    return r ?? 'eval-gagal';
  }

  Future<WatchPlayState> playState() async {
    final raw = await _evalString('window.__claiW ? window.__claiW.state() : ""');
    if (raw == null || raw.isEmpty) return WatchPlayState.kosong('eval-gagal');
    try {
      final m = (jsonDecode(raw) as Map).cast<String, dynamic>();
      return WatchPlayState(
        currentTime: (m['ct'] as num?)?.toDouble() ?? 0,
        duration: (m['dur'] as num?)?.toDouble() ?? 0,
        bufferedEnd: (m['bufEnd'] as num?)?.toDouble() ?? 0,
        paused: m['paused'] != false,
        readyState: (m['rs'] as num?)?.toInt() ?? 0,
        mediaError: '${m['err'] ?? '-'}',
      );
    } catch (_) {
      return WatchPlayState.kosong('urai-gagal');
    }
  }

  /// E4 — transport SABR dari dalam halaman: POST [body] ke [url] dengan
  /// konteks halaman penuh (cookie halaman ikut via credentials:include,
  /// origin & TLS WebView). Mengembalikan byte respons mentah atau null.
  Future<Uint8List?> sabrFetch(String url, Uint8List body) async {
    final b64 = base64Encode(body);
    await _runJs('window.__claiSabrIn = ""; window.__claiSabrStatus = "run";');
    const chunk = 80000;
    for (var i = 0; i < b64.length; i += chunk) {
      final end = (i + chunk > b64.length) ? b64.length : i + chunk;
      await _runJs('window.__claiSabrIn += ${jsonEncode(b64.substring(i, end))};');
    }
    await _runJs('window.__claiW && window.__claiW.sabrGo(${jsonEncode(url)});');
    var status = '';
    for (var i = 0; i < 150; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      status = await _evalString('window.__claiSabrStatus || ""') ?? '';
      if (status == 'done' || status == 'err') break;
    }
    if (status != 'done') return null;
    final lenStr = await _evalString('(window.__claiSabrB64 || "").length + ""');
    final total = int.tryParse(lenStr ?? '') ?? 0;
    if (total <= 0) return null;
    final sb = StringBuffer();
    const take = 100000;
    for (var i = 0; i < total; i += take) {
      final part = await _evalString(
          '(window.__claiSabrB64 || "").substr($i, $take)');
      if (part == null) return null;
      sb.write(part);
    }
    try {
      return base64Decode(sb.toString());
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return WebViewWidget(controller: _controller);
  }
}

/// Utilitas yang disuntikkan ke halaman watch. Semua fungsi hanya
/// mengembalikan RINGKASAN aman-log, kecuali sendPicked yang meneruskan
/// URL terpilih lewat kanal (memori saja, tidak pernah dicatat).
const _utilsJs = r'''
(function () {
  if (window.__claiW) return;
  function post(o) { try { window.ClaiWatch.postMessage(JSON.stringify(o)); } catch (e) {} }
  var picked = null, pickedMeta = { ok: false, src: '-', host: '-', len: 0, params: [] };
  function metaOf(u, src) {
    var host = '-', params = [];
    try {
      var url = new URL(u);
      host = url.host;
      url.searchParams.forEach(function (v, k) { params.push(k); });
    } catch (e) {}
    return { ok: !!u, src: src, host: host, len: u ? u.length : 0, params: params };
  }
  window.__claiW = {
    summary: function () {
      var out = { vdLen: 0, ds: false, cookies: [], ipr: false, play: '-', fmts: [], abr: false, err: '' };
      try {
        var cfg = (window.yt && window.yt.config_) || {};
        if (cfg.VISITOR_DATA) out.vdLen = cfg.VISITOR_DATA.length;
        out.ds = !!cfg.DATASYNC_ID;
        var ck = document.cookie || '';
        if (ck) out.cookies = ck.split(';').map(function (s) { return s.split('=')[0].trim(); }).filter(Boolean);
        var r = window.ytInitialPlayerResponse;
        if (r) {
          out.ipr = true;
          out.play = (r.playabilityStatus && r.playabilityStatus.status) || '-';
          var sd = r.streamingData;
          if (sd) {
            out.abr = !!sd.serverAbrStreamingUrl;
            var af = sd.adaptiveFormats || [];
            for (var i = 0; i < af.length; i++) {
              var f = af[i];
              if ((f.mimeType || '').indexOf('audio/') === 0) {
                out.fmts.push({ itag: f.itag, br: f.bitrate || 0, cl: parseInt(f.contentLength || '0', 10) || 0, url: !!f.url, cipher: !!f.signatureCipher, mime: (f.mimeType || '').split(';')[0] });
              }
            }
          }
        }
      } catch (e) { out.err = ('' + e).substring(0, 120); }
      return JSON.stringify(out);
    },
    pick: function (src, itag) {
      picked = null; pickedMeta = { ok: false, src: src, host: '-', len: 0, params: [] };
      try {
        if (src === 'ipr') {
          var r = window.ytInitialPlayerResponse;
          var af = (r && r.streamingData && r.streamingData.adaptiveFormats) || [];
          for (var i = 0; i < af.length; i++) {
            if (af[i].itag === itag && af[i].url) { picked = af[i].url; break; }
          }
        } else {
          var es = performance.getEntriesByType('resource') || [];
          for (var j = es.length - 1; j >= 0; j--) {
            var n = es[j].name || '';
            if (n.indexOf('googlevideo.com') >= 0 && n.indexOf('itag=' + itag) >= 0) { picked = n; break; }
          }
        }
        if (picked) pickedMeta = metaOf(picked, src);
      } catch (e) {}
    },
    pickMeta: function () { return JSON.stringify(pickedMeta); },
    sendPicked: function () { if (picked) post({ t: 'url', url: picked }); },
    play: function () {
      var info = [];
      try {
        var p = document.getElementById('movie_player');
        if (p) {
          if (p.mute) p.mute();
          if (p.playVideo) { p.playVideo(); info.push('api'); }
        }
        var v = document.querySelector('video');
        if (v) { var pr = v.play(); if (pr && pr.catch) pr.catch(function () {}); info.push('video'); }
      } catch (e) { info.push('err:' + ('' + e).substring(0, 60)); }
      return info.join('+') || 'none';
    },
    state: function () {
      var out = { ct: 0, dur: 0, bufEnd: 0, paused: true, rs: 0, err: '-' };
      try {
        var v = document.querySelector('video');
        if (v) {
          out.ct = v.currentTime || 0;
          out.dur = v.duration || 0;
          out.paused = !!v.paused;
          out.rs = v.readyState || 0;
          if (v.buffered && v.buffered.length) out.bufEnd = v.buffered.end(v.buffered.length - 1);
          if (v.error) out.err = 'media-' + v.error.code;
        }
      } catch (e) { out.err = 'eval'; }
      return JSON.stringify(out);
    },
    sabrGo: function (url) {
      (async function () {
        try {
          var b64 = window.__claiSabrIn || '';
          var bin = atob(b64);
          var u8 = new Uint8Array(bin.length);
          for (var i = 0; i < bin.length; i++) u8[i] = bin.charCodeAt(i);
          var resp = await fetch(url, { method: 'POST', credentials: 'include', headers: { 'Content-Type': 'application/x-protobuf' }, body: u8 });
          var buf = await resp.arrayBuffer();
          var u = new Uint8Array(buf);
          var s = '';
          var CH = 0x8000;
          for (var j = 0; j < u.length; j += CH) s += String.fromCharCode.apply(null, u.subarray(j, j + CH));
          window.__claiSabrB64 = btoa(s);
          window.__claiSabrHttp = resp.status;
          window.__claiSabrStatus = 'done';
        } catch (e) {
          window.__claiSabrB64 = '';
          window.__claiSabrStatus = 'err';
        }
      })();
    }
  };
})();
''';

/// Klik persetujuan (consent) satu kali bila dinding persetujuan muncul —
/// hanya tombol persetujuan di dialog consent; tidak pernah tombol masuk.
const _consentJs = r'''
(function () {
  try {
    var dlg = document.querySelector('ytd-consent-bump-v2-lightbox, tp-yt-paper-dialog');
    if (!dlg) return;
    var btns = dlg.querySelectorAll('button');
    for (var i = 0; i < btns.length; i++) {
      var t = (btns[i].textContent || '').toLowerCase();
      if (t.indexOf('accept') >= 0 || t.indexOf('terima') >= 0 || t.indexOf('agree') >= 0 || t.indexOf('setuju') >= 0) { btns[i].click(); return; }
    }
  } catch (e) {}
})();
''';
