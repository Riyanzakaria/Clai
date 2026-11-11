import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/l10n.dart';
import 'package:just_audio/just_audio.dart';

import '../app.dart';
import '../core/clai_icons.dart';
import '../core/error_describe.dart';
import '../core/tokens.dart';
import '../domain/models.dart';
import '../player/audio_handler.dart';
import '../providers/music_provider.dart';
import '../providers/ytmusic/ytmusic_provider.dart';
import 'direct_path_section.dart';
import '../player/load_ladder.dart';
import '../player/resolving_audio_source.dart';
import '../player/test_tone.dart';
import '../services/gate_metrics.dart';
import 'login_lab.dart';
import 'potoken_lab.dart';
import 'watch_lab.dart';

/// Diagnostik Putar (v4.1; diperdalam v4.2) — alat bukti DI PERANGKAT.
///
/// Vonis v4.1 dari HP pemilik: A (resolusi) & B (unduh range mentah) SEHAT untuk
/// Song, Video, dan trek antrean; C (setUrl polos) & D (jalur proxy) GAGAL identik
/// dengan PlayerException(0, "Source error") — yang dari sumber just_audio berarti
/// ExoPlaybackException.TYPE_SOURCE tanpa sebab natif (sebabnya hanya ditulis ke
/// logcat proses). Gejala UI: durasi tampil, posisi tidak berjalan, tanpa suara.
///
/// v4.2 menambah tiga hal agar putaran berikut tidak terbang buta:
///   C2/C3 — dua konfigurasi muat yang belum teruji di perangkat: URI adaptif +
///           header pasangan, dan URI muxed itag 18 langsung (anak tangga 1 & 2).
///   E     — pipa lokal TANPA jaringan: nada WAV 2 dtk dari memori lewat
///           StreamAudioSource polos (E1) & ResolvingAudioSource rintisan (E2).
///   natif↳ — setiap langkah muat kini menangkap galat MENTAH aliran peristiwa
///           pemutar (errorCode/errorMessage + PlatformException apa adanya) DAN
///           baris logcat proses sendiri sesudah langkah itu (baris "TYPE_SOURCE: …"
///           dari just_audio memuat sebab fisiknya, mis. kode respons HTTP).
/// Subjek tetap Song murni & item tipe Video, plus trek antrean saat ini bila ada.
class PlaybackDiagnosticsScreen extends ConsumerStatefulWidget {
  const PlaybackDiagnosticsScreen({super.key});
  @override
  ConsumerState<PlaybackDiagnosticsScreen> createState() => _PlaybackDiagnosticsScreenState();
}

class _PlaybackDiagnosticsScreenState extends ConsumerState<PlaybackDiagnosticsScreen> {
  final StringBuffer _report = StringBuffer();
  bool _running = false;

  static const _logChannel = MethodChannel('clai/diag_log');
  int _logSeenMatches = 0;

  // Laboratorium PoToken (v3.5): WebView pencetak token, selalu terpasang
  // di pohon layar ini agar siap saat matriks P dijalankan. Sesi (berisi
  // token) hanya hidup di memori state ini — tidak pernah ditulis.
  final GlobalKey<PoTokenLabState> _poLabKey = GlobalKey<PoTokenLabState>();

  // Laboratorium Halaman Watch (v3.10, Probe Sesi Tamu WebView): WebView
  // kedua yang memuat halaman watch SUNGGUHAN sebagai tamu untuk matriks
  // V. Sesi tamu halaman (cookie/konteks) hanya hidup di dalam WebView
  // ini; yang keluar hanya ringkasan aman-log + URL terpilih di memori.
  final GlobalKey<WatchLabState> _watchLabKey = GlobalKey<WatchLabState>();

  void _poProgress(String s) => _line('   lab↳ $s');

  void _line(String s) {
    _report.writeln(s);
    if (mounted) setState(() {});
  }

  Track get _fixedSong => const Track(
        key: TrackKey('ytmusic', 'qU9mHegkTc4'),
        title: '505',
        artistNames: 'Arctic Monkeys',
        playableRef: 'qU9mHegkTc4',
      );

  // ---------------- logcat proses sendiri ----------------
  static bool _isNativeLine(String l) =>
      l.contains('TYPE_SOURCE') ||
      l.contains('TYPE_RENDERER') ||
      l.contains('TYPE_UNEXPECTED') ||
      l.contains('PlaybackException') ||
      l.contains('Response code') ||
      l.contains('HttpDataSource') ||
      l.contains('InvalidResponseCode');

  /// Baris natif BARU sejak panggilan terakhir (atribusi per langkah).
  Future<List<String>> _newNativeLines() async {
    try {
      final text = await _logChannel.invokeMethod<String>('readLogTail') ?? '';
      final matched = text
          .split('\n')
          .where(_isNativeLine)
          .map((l) => l.trim().length > 280 ? '${l.trim().substring(0, 280)}…' : l.trim())
          .where((l) => l.isNotEmpty)
          .toList();
      if (matched.length <= _logSeenMatches) {
        _logSeenMatches = matched.length;
        return const [];
      }
      final fresh = matched.sublist(_logSeenMatches);
      _logSeenMatches = matched.length;
      return fresh.take(6).toList();
    } catch (e) {
      return ['(logcat tidak terbaca: $e)'];
    }
  }

  Future<void> _printNative(String step) async {
    final lines = await _newNativeLines();
    for (final l in lines) {
      _line('   natif↳[$step] $l');
    }
  }

  // ---------------- tangkap galat mentah selama muat ----------------
  /// Jalankan [load] pada [p] sambil mendengarkan aliran peristiwa pemutar:
  /// event ber-errorCode dan galat aliran (PlatformException mentah) dicatat apa
  /// adanya — bukan hanya PlayerException Dart yang selama ini buta.
  Future<({Duration? duration, Object? error, List<String> captured})> _captureLoad(
      AudioPlayer p, Future<Duration?> Function() load) async {
    final captured = <String>[];
    final sub = p.playbackEventStream.listen((ev) {
      if (ev.errorCode != null) {
        final name = exoErrorCodeName(ev.errorCode!);
        final line = 'event: errorCode=${ev.errorCode}${name != null ? ' ($name)' : ''}'
            ' errorMessage=${ev.errorMessage ?? '-'} state=${ev.processingState.name}';
        if (!captured.contains(line)) captured.add(line);
      }
    }, onError: (Object e) {
      final line = 'aliran: ${describePlayerError(e)}';
      if (!captured.contains(line)) captured.add(line);
    });
    try {
      final dur = await load().timeout(const Duration(seconds: 15));
      await Future<void>.delayed(const Duration(milliseconds: 600));
      return (duration: dur, error: null, captured: captured);
    } catch (e) {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      return (duration: null, error: e, captured: captured);
    } finally {
      await sub.cancel();
    }
  }

  void _reportLoad(String step, ({Duration? duration, Object? error, List<String> captured}) r) {
    if (r.error == null) {
      _line('$step · BERHASIL — durasi=${r.duration ?? '-'}');
    } else {
      _line('$step · GAGAL — ${describePlayerError(r.error!)}');
    }
    for (final c in r.captured) {
      _line('   mentah↳ $c');
    }
  }

  Future<void> _run() async {
    if (_running) return;
    setState(() { _running = true; _report.clear(); });
    final provider = ref.read(ytMusicProvider);
    final handler = ref.read(audioHandlerProvider);
    _line('DIAGNOSTIK PUTAR CLAI v3.8 (instrumentasi upstream + matriks jendela + matriks klien + probe potoken + penutup peta klien + penyeberangan F3 + decipher F3) — ${DateTime.now().toIso8601String()}');
    _line('Perangkat: ${Platform.operatingSystemVersion}');
    _line('');
    _logSeenMatches = 0;
    await _newNativeLines(); // garis dasar: baris lama tidak diatribusikan ke langkah mana pun

    // Susun subjek: Song tetap + item Video dari pencarian hidup + trek antrean saat ini.
    final subjects = <(String, Track)>[('Subjek Song (uji tetap)', _fixedSong)];
    try {
      final res = await provider.search('Iwan Fals Berandal Malam Di Bangku Terminal')
          .timeout(const Duration(seconds: 30));
      if (res.songs.isNotEmpty) {
        final video = res.songs.where((t) => t.artistNames.contains('views')).firstOrNull;
        final pick = video ?? res.songs.first;
        subjects.add(('Subjek Video (pencarian hidup${video == null ? ' — tipe tak terdeteksi, hasil pertama' : ''})', pick));
      } else {
        _line('Pencarian subjek Video: 0 hasil — subjek Video dilewati.');
      }
    } catch (e) {
      _line('Pencarian subjek Video gagal: ${describeError(e)} — subjek Video dilewati.');
    }
    // Subjek ke-3 untuk ronde ini: hasil pencarian kedua yang berbeda dari
    // subjek Video (bukan antrean — antrean kosong saat app baru dibuka, dan
    // subjek antrean tetap ditambahkan di bawah bila ada).
    try {
      final res2 = await provider.search('Iwan Fals Berandal Malam Di Bangku Terminal')
          .timeout(const Duration(seconds: 30));
      if (res2.songs.length > 1) {
        final existing = subjects.map((s) => s.$2.key).toSet();
        final second = res2.songs.firstWhere((t) => !existing.contains(t.key),
            orElse: () => res2.songs[1]);
        if (!existing.contains(second.key)) {
          subjects.add(('Subjek Video ke-2 (pencarian hidup, hasil berbeda)', second));
        }
      }
    } catch (_) {
      // Subjek ke-3 opsional: lewati diam-diam bila pencarian ulang gagal.
    }
    // Subjek baku ke-3 ronde instrumentasi: "Duniawi" — rumahsakit
    // (trek insiden HP pemilik), dicari hidup agar ID-nya segar.
    try {
      final res3 = await provider.search('Duniawi rumahsakit')
          .timeout(const Duration(seconds: 30));
      final duniawi = res3.songs
          .where((t) => t.title.toLowerCase().contains('duniawi'))
          .firstOrNull;
      if (duniawi != null && subjects.every((s) => s.$2.key != duniawi.key)) {
        subjects.add(('Subjek Duniawi (pencarian hidup)', duniawi));
      } else if (duniawi == null) {
        _line('Pencarian subjek Duniawi: tidak ketemu — subjek dilewati.');
      }
    } catch (e) {
      _line('Pencarian subjek Duniawi gagal: ${describeError(e)} — subjek dilewati.');
    }
    final current = handler.engine.current;
    if (current != null && subjects.every((s) => s.$2.key != current.key)) {
      subjects.add(('Subjek trek antrean saat ini', current));
    }

    for (final (label, track) in subjects) {
      _line('════════ $label');
      _line('Trek: "${track.title}" — ${track.artistNames} [${track.id}]');
      await _runSubject(track, handler.quality);
      _line('');
    }

    await _runToneSteps();
    _line('');
    _line('SELESAI.');
    // v3.1: cetak laporan penuh ke logcat agar bisa ditarik via adb meski
    // UI menggantung di tengah jalan pada lari berikutnya.
    for (final l in _report.toString().split('\n')) {
      debugPrint('DIAG-REPORT|$l');
    }
    if (mounted) setState(() => _running = false);
  }

  Future<void> _runSubject(Track track, StreamQuality quality) async {
    final provider = ref.read(ytMusicProvider);
    final handler = ref.read(audioHandlerProvider);

    // ---- Langkah A: resolusi per klien (tanpa cache) ----
    StreamInfo? info;
    try {
      final attempts = await provider.debugResolveChain(track, quality)
          .timeout(const Duration(seconds: 120));
      for (final a in attempts) {
        _line('A · ${a.client}: ${a.ok ? 'BERHASIL' : 'gagal'} — ${a.detail}');
        info ??= a.info;
      }
      if (info == null) _line('A · KESIMPULAN: tidak ada klien menghasilkan URL.');
    } catch (e) {
      _line('A · GALAT langkah: ${describeError(e)}');
    }

    // ---- Langkah B: unduh range mentah ----
    if (info == null) {
      _line('B · dilewati (tidak ada URL dari langkah A).');
    } else {
      try {
        final dio = Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 15),
          validateStatus: (_) => true,
        ));
        final res = await dio.get<List<int>>(info.url,
            options: Options(responseType: ResponseType.bytes, headers: {
              'Range': 'bytes=0-1023',
              'User-Agent': ResolvingAudioSource.playerUserAgent,
            }));
        _line('B · HTTP ${res.statusCode} · content-type=${res.headers.value('content-type') ?? '-'}'
            ' · content-length=${res.headers.value('content-length') ?? '-'}'
            ' · content-range=${res.headers.value('content-range') ?? '-'}'
            ' · diterima ${res.data?.length ?? 0} byte');
      } catch (e) {
        _line('B · GALAT: ${describeError(e)}');
      }
    }

    // ---- Langkah B2 (v3.1/v3.2, Ronde Anak Tangga 1): fetchHttpRange dart:io
    // LANGSUNG, tanpa proxy just_audio — status upstream apa adanya.
    // v3.2: ambilan yang sama kini lewat pembungkus tercatat (_tracedFetch)
    // agar baris B2 bisa dibandingkan baris-per-baris dengan ambilan di
    // dalam jalur proxy (V5/V6): host, itag, nama parameter, UA & Range
    // persis, status, header respons kunci, byte pertama & total.
    if (info == null) {
      _line('B2 · dilewati (tidak ada URL dari langkah A).');
    } else {
      for (final (wStart, wEnd) in [(0, 1023), (0, 16383), (0, 262143), (0, 1048575)]) {
        try {
          final f = await _tracedFetch('B2', Uri.parse(info.url),
                  start: wStart, endInclusive: wEnd)
              .timeout(const Duration(seconds: 30));
          var received = 0;
          try {
            received = await f.body
                .fold<int>(0, (a, c) => a + c.length)
                .timeout(const Duration(seconds: 30));
          } catch (e) {
            _line('B2 · Range bytes=$wStart-$wEnd → HTTP ${f.statusCode} · '
                'content-length=${f.contentLength} · '
                'content-range=${f.contentRange ?? '-'} · GALAT drain: ${describeError(e)}');
            continue;
          }
          _line('B2 · Range bytes=$wStart-$wEnd → HTTP ${f.statusCode} · '
              'content-length=${f.contentLength} · '
              'content-range=${f.contentRange ?? '-'} · '
              'content-type=${f.contentType ?? '-'} · diterima $received byte');
        } catch (e) {
          _line('B2 · Range bytes=$wStart-$wEnd → GALAT: ${describeError(e)}');
        }
      }
    }

    // ---- Langkah B3 (v3.3, Ronde Instrumentasi Upstream): matriks jendela
    // PENENTU di atas temuan v3.2 — jendela mulai byte 0 selalu 206, jendela
    // mulai >0 pada URL adaptif selalu 403 (di dalam proxy). Yang belum
    // diketahui: apakah SATU jendela mulai-0 yang lebar (sampai seluruh
    // berkas) dilayani? Bila ya, jalur adaptif bisa hidup dari satu ambilan
    // rentang-penuh. Semua ambilan dart:io langsung; tubuh hanya dibaca
    // potongan pertamanya lalu dibatalkan, kecuali jendela terlebar yang
    // di-drain penuh untuk membuktikan byte lengkap benar-benar mengalir.
    if (info != null) {
      _line('── B3 · MATRIKS JENDELA LANGSUNG (penentu rentang-penuh)');
      final uri = Uri.parse(info.url);
      Future<void> probeWindow(String tag, int s, int e, {bool drainAll = false}) async {
        try {
          final f = await _tracedFetch(tag, uri, start: s, endInclusive: e)
              .timeout(const Duration(seconds: 30));
          var n = 0;
          if (drainAll) {
            await for (final c in f.body) {
              n += c.length;
            }
          } else {
            await for (final c in f.body) {
              n += c.length;
              break; // potongan pertama cukup; langganan dibatalkan
            }
          }
          _line('B3 · $tag bytes=$s-$e → status=${f.statusCode} · '
              'cr=${f.contentRange ?? '-'} · cl=${f.contentLength} · terbaca $n byte');
        } catch (err) {
          _line('B3 · $tag bytes=$s-$e → GALAT: ${describeError(err)}');
        }
      }

      await probeWindow('B3a', 0, 2097151);
      await probeWindow('B3b', 0, 4194303);
      await probeWindow('B3c', 0, 16777215);
      await probeWindow('B3d', 0, 67108863, drainAll: true);
      // Kontrol start>0 di LUAR proxy & kolam bersama (HttpClient baru):
      // memastikan 403-nya memang soal posisi mulai, bukan soal kolam/proxy.
      // B4 (v3.3): parameter `range=` DI URL (bukan header Range) — mekanisme
      // lama googlevideo yang masih dipakai beberapa klien. Bila ini membuka
      // jendela tengah, fetcher aplikasi bisa memintanya. Plus kontrol B4c:
      // tanpa Range sama sekali (samakan dengan setUrl polos langkah C).
      for (final (tag, rs) in [('B4a', '1048576-2097151'), ('B4b', '2097152-3145727'), ('B4c', null)]) {
        final sw = Stopwatch()..start();
        final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
        try {
          final u2 = rs == null
              ? uri
              : uri.replace(queryParameters: {...uri.queryParameters, 'range': rs});
          final req = await client.getUrl(u2);
          req.headers.set(HttpHeaders.userAgentHeader, ResolvingAudioSource.playerUserAgent);
          final res = await req.close().timeout(const Duration(seconds: 20));
          var n = 0;
          await for (final c in res) {
            n += c.length;
            break;
          }
          _up('UP $tag GET host=${u2.host} itag=${u2.queryParameters['itag'] ?? '-'} '
              'urlRange=${rs ?? '-'} (tanpa header Range) -> status=${res.statusCode} '
              'cr=${res.headers.value(HttpHeaders.contentRangeHeader) ?? '-'} '
              'cl=${res.contentLength} terbaca $n t=${sw.elapsedMilliseconds}ms');
          _line('B3 · $tag urlRange=${rs ?? '-'} (tanpa header Range) → status=${res.statusCode}');
        } catch (err) {
          _up('UP $tag EXC t=${sw.elapsedMilliseconds}ms :: $err');
          _line('B3 · $tag urlRange=${rs ?? '-'} → GALAT: ${describeError(err)}');
        } finally {
          client.close(force: true);
        }
      }
      for (final (tag, s, e) in [('B3e', 1048576, 2097151), ('B3f', 1, 1048576)]) {
        final sw = Stopwatch()..start();
        final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
        try {
          final req = await client.getUrl(uri);
          req.headers.set(HttpHeaders.userAgentHeader, ResolvingAudioSource.playerUserAgent);
          req.headers.set(HttpHeaders.rangeHeader, 'bytes=$s-$e');
          final res = await req.close().timeout(const Duration(seconds: 20));
          var n = 0;
          await for ( final c in res) {
            n += c.length;
            break;
          }
          _up('UP $tag GET host=${uri.host} itag=${uri.queryParameters['itag'] ?? '-'} '
              'range=bytes=$s-$e (HttpClient BARU) -> status=${res.statusCode} '
              'cr=${res.headers.value(HttpHeaders.contentRangeHeader) ?? '-'} '
              'cl=${res.contentLength} terbaca $n t=${sw.elapsedMilliseconds}ms');
          _line('B3 · $tag bytes=$s-$e (klien baru) → status=${res.statusCode}');
        } catch (err) {
          _up('UP $tag EXC t=${sw.elapsedMilliseconds}ms :: $err');
          _line('B3 · $tag bytes=$s-$e (klien baru) → GALAT: ${describeError(err)}');
        } finally {
          client.close(force: true);
        }
      }
    }

    if (info == null) {
      _line('C/C2/C3/D · dilewati (tidak ada URL dari langkah A).');
      return;
    }
    final streamInfo = info;

    // ---- Langkah C: ExoPlayer polos (setUrl, tanpa header, tanpa proxy) ----
    {
      final p = AudioPlayer();
      try {
        final r = await _captureLoad(p, () => p.setUrl(streamInfo.url));
        _reportLoad('C · setUrl polos', r);
      } finally {
        await p.dispose();
      }
      await _printNative('C');
    }

    // ---- Langkah C2: URI adaptif + header (anak tangga 1, persis — termasuk
    // transport header yang sama dengan handler: langsung via ExoPlayer) ----
    {
      final p = AudioPlayer(useProxyForRequestHeaders: ClaiAudioHandler.useProxyForRequestHeaders);
      try {
        final src = AudioSource.uri(Uri.parse(streamInfo.url), headers: LoadLadder.streamHeaders);
        final r = await _captureLoad(p, () => p.setAudioSource(src));
        _reportLoad('C2 · URI adaptif + header', r);
      } catch (e) {
        _line('C2 · GALAT bangun sumber: ${describeError(e)}');
      } finally {
        await p.dispose();
      }
      await _printNative('C2');
    }

    // ---- Langkah C3: URI muxed itag 18 langsung (anak tangga 2, persis) ----
    {
      StreamInfo? muxed;
      try {
        muxed = await provider.resolveMuxedFallback(track).timeout(const Duration(seconds: 60));
      } catch (e) {
        _line('C3 · resolusi muxed GALAT: ${describeError(e)}');
      }
      if (muxed == null) {
        _line('C3 · dilewati (penyedia tidak memberi aliran muxed untuk trek ini).');
      } else {
        final p = AudioPlayer(useProxyForRequestHeaders: ClaiAudioHandler.useProxyForRequestHeaders);
        try {
          final src = AudioSource.uri(Uri.parse(muxed.url), headers: LoadLadder.streamHeaders);
          final r = await _captureLoad(p, () => p.setAudioSource(src));
          _reportLoad('C3 · URI muxed itag 18 + header', r);
        } catch (e) {
          _line('C3 · GALAT bangun sumber: ${describeError(e)}');
        } finally {
          await p.dispose();
        }
        await _printNative('C3');
      }
    }

    // ---- Langkah D: jalur asli aplikasi (anak tangga pemenang lengket) ----
    // v3: vonis D kini berbasis PUTAR (posisi maju), bukan muat saja — anak
    // sumber malas (proxy) bisa "berhasil dimuat" tanpa pernah mengalirkan
    // byte, jadi bukti muat tidak cukup untuk menyatakan jalur aplikasi sehat.
    {
      final rung = handler.debugLoadRung;
      final p2 = AudioPlayer(useProxyForRequestHeaders: ClaiAudioHandler.useProxyForRequestHeaders);
      ResolvingAudioSource? resolvingChild;
      try {
        final child = await handler.debugChildSource(track);
        if (child is ResolvingAudioSource) resolvingChild = child;
        final src = ConcatenatingAudioSource(children: [child]);
        final r = await _probePlay(p2, src);
        _reportProbe('D · jalur aplikasi (anak ${rung + 1}: ${LoadLadder.rungLabel(rung)})', r);
        if (resolvingChild != null && resolvingChild.fallbackActive) {
          _line('   catatan: sumber D beralih ke CADANGAN MUXED di dalam proxy.');
        }
      } catch (e, st) {
        _line('D · jalur aplikasi GAGAL bangun — ${describePlayerError(e, st)}');
      } finally {
        await p2.dispose();
      }
      await _printNative('D');
    }

    // ---- Langkah V: matriks varian adaptif (Ronde Anak Tangga 1) ----
    await _runVariantMatrix(track, streamInfo);
  }

  // ================= Ronde Klien InnerTube (v3.4) =================
  // Fase A (tombol Uji Klien InnerTube): probe resolusi + jendela byte per
  // klien kandidat dengan ANDROID sebagai kontrol sesi yang sama. Vonis per
  // klien per subjek: MELAYANI->1MiB / TERBATAS-1MiB / TERBLOKIR-DI-RESOLUSI.
  // URL mentah TIDAK pernah masuk laporan — hanya host, itag, nama parameter.
  // Kontrol silang-UA (KX): jendela 2 yang sama dengan UA ANDROID, untuk
  // memutus apakah pasangan UA↔URL ikut menentukan (bahan keputusan Fase B).
  // Fase B-1 (tombol Bukti Putar Klien): klien pertama yang resolusi +
  // jendela-2 lolos membuktikan putar ≥100 dtk melewati batas 1 MiB lewat
  // ExoPlayer (URI langsung + ResolvingAudioSource), TANPA cadangan muxed.
  //
  // Ronde Probe Penutup Peta (v3.6, 2026-11-07): daftar kandidat diganti
  // dua sel rantai yang belum pernah diukur rentangnya — ANDROID_VR dan
  // TVHTML5_SIMPLY_EMBEDDED_PLAYER — dan vonis keempat ditambahkan:
  // TANPA-FORMAT-ADAPTIF-AUDIO (playability OK tetapi audio adaptif
  // ber-URL langsung tidak diterbitkan sama sekali).

  static const _kClients = ['ANDROID_VR', 'TVHTML5_SIMPLY_EMBEDDED_PLAYER'];

  List<(String, Track)> get _kSubjects => const [
        ('Subjek Song (uji tetap)',
            Track(key: TrackKey('ytmusic', 'qU9mHegkTc4'), title: '505', artistNames: 'Arctic Monkeys', playableRef: 'qU9mHegkTc4')),
        ('Subjek Video (uji tetap)',
            Track(key: TrackKey('ytmusic', '8YA4GIudCJY'), title: 'Berandal Malam Di Bangku Terminal', artistNames: 'Iwan Fals', playableRef: '8YA4GIudCJY')),
        ('Subjek Duniawi (trek insiden)',
            Track(key: TrackKey('ytmusic', '4XapGQ9wHgc'), title: 'Duniawi', artistNames: 'rumahsakit', playableRef: '4XapGQ9wHgc')),
        ('Subjek antrean pulih (uji tetap)',
            Track(key: TrackKey('ytmusic', 'O3tnOVideSo'), title: 'Baby Be Mine (Audio)', artistNames: '-', playableRef: 'O3tnOVideSo')),
      ];

  /// Satu ambilan jendela byte langsung (HttpClient BARU per ambilan, pola
  /// kontrol B3e) dengan UA yang diberikan; tubuh di-drain penuh (jendela
  /// ≤1 MiB) agar byte yang benar-benar mengalir terhitung.
  Future<({int status, String? contentRange, int contentLength, int drained, int ms})>
      _kFetch(Uri uri, String userAgent, int start, int endInclusive) async {
    final sw = Stopwatch()..start();
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final req = await client.getUrl(uri);
      if (userAgent.isNotEmpty) {
        req.headers.set(HttpHeaders.userAgentHeader, userAgent);
      }
      req.headers.set(HttpHeaders.rangeHeader, 'bytes=$start-$endInclusive');
      final res = await req.close().timeout(const Duration(seconds: 25));
      var n = 0;
      await for (final c in res) {
        n += c.length;
      }
      return (
        status: res.statusCode,
        contentRange: res.headers.value(HttpHeaders.contentRangeHeader),
        contentLength: res.contentLength,
        drained: n,
        ms: sw.elapsedMilliseconds,
      );
    } finally {
      client.close(force: true);
    }
  }

  /// Satu jendela matriks K; true bila 206, mulai Content-Range cocok, dan
  /// byte yang diterima memenuhi jendela (atau sisa berkas bila jendela
  /// melewati ujung berkas menurut Content-Range).
  Future<bool> _kWindow(Uri uri, String ua, String tag, int s, int e) async {
    try {
      final f = await _kFetch(uri, ua, s, e).timeout(const Duration(seconds: 40));
      final cr = parseContentRange(f.contentRange);
      final expected = cr != null ? cr.end - s + 1 : (e - s + 1);
      final full = f.drained >= expected;
      _line('   $tag · bytes=$s-$e → status=${f.status} · cr=${f.contentRange ?? '-'} · '
          'cl=${f.contentLength} · drained ${f.drained} byte${full ? '' : ' (TIDAK PENUH)'} · ${f.ms}ms');
      return f.status == 206 && full && (cr == null || cr.start == s);
    } catch (err) {
      _line('   $tag · bytes=$s-$e → GALAT: ${describeError(err)}');
      return false;
    }
  }

  Future<String> _kProbeClient(String clientName, Track track) async {
    final provider = ref.read(ytMusicProvider);
    ClientStreamProbe probe;
    try {
      probe = await provider
          .debugProbeNamedClient(clientName, track)
          .timeout(const Duration(seconds: 90));
    } catch (e) {
      _line('K · $clientName: GALAT probe — ${describeError(e)}');
      return 'GALAT-PROBE';
    }
    if (probe.error != null) {
      _line('K · $clientName (v${probe.version}): ${probe.playability} — galat: ${probe.error}');
      return 'TERBLOKIR-DI-RESOLUSI';
    }
    if (!probe.resolved) {
      _line('K · $clientName (v${probe.version}): playability=${probe.playability}'
          '${probe.reason.isEmpty ? '' : ' — ${probe.reason}'} · format total=${probe.totalFormats}'
          ' · URL audio langsung: TIDAK ADA');
      if (probe.playability == 'OK') {
        // Resolusi DITERIMA tetapi tangga tidak dapat bahan (Ronde Probe
        // Penutup Peta): bedakan dari penolakan di resolusi.
        _line('   adaptif total=${probe.adaptiveTotal} · audio adaptif (mime audio/*)=${probe.adaptiveAudioAny}'
            ' · audio adaptif ber-URL langsung=${probe.audioFormats.length}');
        return 'TANPA-FORMAT-ADAPTIF-AUDIO';
      }
      return 'TERBLOKIR-DI-RESOLUSI';
    }
    final info = probe.info!;
    final fmts = probe.audioFormats
        .map((f) => 'itag ${f.itag} (${f.mime.split(';').first}, ${f.bitrate ?? '-'} bps, ${f.contentLength ?? '-'} B)')
        .join(' · ');
    _line('K · $clientName (v${probe.version}): playability=OK · format adaptif audio: $fmts');
    if (probe.audioFormats.isEmpty) {
      // Pilihan Normal ada tetapi BUKAN dari audio adaptif (mis. audio
      // progresif di formats) — tangga tetap tidak dapat bahan.
      _line('   adaptif total=${probe.adaptiveTotal} · audio adaptif (mime audio/*)=${probe.adaptiveAudioAny}'
          ' · ber-URL langsung=0 — pilihan Normal bukan audio adaptif.');
      return 'TANPA-FORMAT-ADAPTIF-AUDIO';
    }
    _line('   tier→itag: Rendah=${probe.tierItags['low'] ?? '-'} · Normal=${probe.tierItags['normal'] ?? '-'}'
        ' · Tinggi=${probe.tierItags['high'] ?? '-'} · pilihan Normal: ${info.mimeType} ${info.bitrate ?? '-'} bps');
    _line('   URL: host=${probe.urlHost ?? '-'} · params=[${probe.urlParams.join(',')}]'
        ' · pot=${probe.urlParams.contains('pot') ? 'ADA' : 'tidak ada'}');
    final uri = Uri.parse(info.url);
    int? total;
    for (final f in probe.audioFormats) {
      if (f.itag == probe.tierItags['normal']) total = f.contentLength;
    }
    final w1 = await _kWindow(uri, probe.userAgent, 'K1', 0, 1048575);
    final w2 = await _kWindow(uri, probe.userAgent, 'K2', 1048576, 2097151);
    bool? w3ok;
    if (total != null && total <= 3000000) {
      _line('   K3 · dilewati (berkas hanya $total byte)');
    } else {
      w3ok = await _kWindow(uri, probe.userAgent, 'K3', 3000000, 4048575);
    }
    if (clientName != 'ANDROID') {
      try {
        final x = await _kFetch(uri, ResolvingAudioSource.playerUserAgent, 1048576, 2097151)
            .timeout(const Duration(seconds: 40));
        _line('   KX · jendela2 dengan UA ANDROID → status=${x.status} · drained ${x.drained} byte · ${x.ms}ms');
      } catch (e) {
        _line('   KX · jendela2 dengan UA ANDROID → GALAT: ${describeError(e)}');
      }
    }
    final beyond = w2 && (w3ok ?? true);
    if (w1 && beyond) return 'MELAYANI->1MiB';
    if (w1) return 'TERBATAS-1MiB';
    return 'LAIN(w1=$w1,w2=$w2,w3=$w3ok)';
  }

  Future<void> _runClientMatrix() async {
    if (_running) return;
    setState(() {
      _running = true;
      _report.clear();
    });
    _line('MATRIKS KLIEN INNERTUBE v3.6 (Ronde Probe Penutup Peta, Fase A) — ${DateTime.now().toIso8601String()}');
    _line('Perangkat: ${Platform.operatingSystemVersion}');
    _line('Kandidat: ${_kClients.join(', ')} · kontrol sesi: ANDROID');
    _line('');
    final verdicts = <String, List<String>>{};
    for (final (label, track) in _kSubjects) {
      _line('════════ $label');
      _line('Trek: "${track.title}" — ${track.artistNames} [${track.id}]');
      for (final clientName in ['ANDROID', ..._kClients]) {
        debugPrint('DIAG-STAGE K $clientName ${track.id} mulai');
        final v = await _kProbeClient(clientName, track);
        verdicts.putIfAbsent(clientName, () => []).add(v);
        debugPrint('DIAG-STAGE K $clientName ${track.id} vonis=$v');
      }
      _line('');
    }
    _line('── RINGKASAN VONIS KLIEN (per subjek, urutan subjek seperti di atas)');
    for (final e in verdicts.entries) {
      _line('K · ${e.key}: ${e.value.join(' | ')}');
    }
    _line('');
    _line('SELESAI.');
    for (final l in _report.toString().split('\n')) {
      debugPrint('DIAG-REPORT|$l');
    }
    if (mounted) setState(() => _running = false);
  }

  /// Fetcher sadar-UA untuk bukti putar KP-2: jendela selalu terbatas
  /// (kontrak ResolvingAudioSource), UA = UA klien pemenang. Tubuh jendela
  /// (≤1 MiB) disalin ke memori agar aliran tetap terbaca sesudah kembali.
  Future<FetchedBytes> _kUaFetch(Uri uri, String userAgent,
      {required int start, required int endInclusive}) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final req = await client.getUrl(uri);
      req.headers.set(HttpHeaders.userAgentHeader, userAgent);
      req.headers.set(HttpHeaders.rangeHeader, 'bytes=$start-$endInclusive');
      final res = await req.close().timeout(const Duration(seconds: 20));
      final bytes = await res.fold<List<int>>(<int>[], (a, c) => a..addAll(c));
      return FetchedBytes(
        statusCode: res.statusCode,
        contentLength: res.contentLength,
        contentRange: res.headers.value(HttpHeaders.contentRangeHeader),
        contentType: res.headers.contentType?.mimeType,
        body: Stream.value(bytes),
      );
    } finally {
      client.close(force: true);
    }
  }

  /// Probe putar PANJANG untuk bukti Fase B-1: vonis BERHASIL hanya bila
  /// posisi mencapai ≥100 dtk (pada bitrate audio ±130 kbps itu berarti
  /// >1,6 MB benar-benar terambil — jauh melewati batas 1 MiB) tanpa satu
  /// pun peristiwa galat. play() tidak ditunggu (pelajaran v3.1).
  Future<({bool ok, Duration? duration, int maxPosMs, Object? error, List<String> captured})>
      _probeLongPlay(AudioPlayer p, AudioSource src, String label, {int targetMs = 100000}) async {
    final captured = <String>[];
    final sub = p.playbackEventStream.listen((ev) {
      if (ev.errorCode != null) {
        final name = exoErrorCodeName(ev.errorCode!);
        final line = 'event: errorCode=${ev.errorCode}${name != null ? ' ($name)' : ''}'
            ' errorMessage=${ev.errorMessage ?? '-'} state=${ev.processingState.name}';
        if (!captured.contains(line)) captured.add(line);
      }
    }, onError: (Object e) {
      final line = 'aliran: ${describePlayerError(e)}';
      if (!captured.contains(line)) captured.add(line);
    });
    try {
      Duration? duration;
      try {
        debugPrint('DIAG-STAGE $label setSrc start');
        await p.setAudioSource(src).timeout(const Duration(seconds: 25));
        duration = p.duration;
        debugPrint('DIAG-STAGE $label setSrc done duration=$duration');
      } catch (e) {
        debugPrint('DIAG-STAGE $label setSrc error: $e');
        await Future<void>.delayed(const Duration(milliseconds: 300));
        return (ok: false, duration: null, maxPosMs: 0, error: e, captured: captured);
      }
      Object? playError;
      p.play().then((_) {
        debugPrint('DIAG-STAGE $label play future selesai');
      }).catchError((Object e) {
        playError = e;
        debugPrint('DIAG-STAGE $label play future galat: $e');
      });
      var maxPos = 0;
      var lastStageSec = -10;
      final sw = Stopwatch()..start();
      while (sw.elapsed < const Duration(seconds: 170)) {
        final pos = p.position.inMilliseconds;
        if (pos > maxPos) maxPos = pos;
        final sec = sw.elapsed.inSeconds;
        if (sec >= lastStageSec + 10) {
          lastStageSec = sec;
          debugPrint('DIAG-STAGE $label t=${sec}s pos=${pos}ms state=${p.processingState.name}');
        }
        if (maxPos >= targetMs) break;
        if (p.processingState == ProcessingState.completed) break;
        if (playError != null) break;
        if (captured.isNotEmpty && maxPos == 0 && sw.elapsed > const Duration(seconds: 20)) break;
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
      debugPrint('DIAG-STAGE $label loop done maxPos=$maxPos captured=${captured.length} playError=$playError');
      final ok = captured.isEmpty && playError == null && maxPos >= targetMs;
      try {
        await p.stop().timeout(const Duration(seconds: 5));
      } catch (_) {}
      return (ok: ok, duration: duration, maxPosMs: maxPos, error: playError, captured: captured);
    } finally {
      await sub.cancel();
    }
  }

  void _reportLongPlay(String step,
      ({bool ok, Duration? duration, int maxPosMs, Object? error, List<String> captured}) r) {
    _line('$step: ${r.ok ? 'BERHASIL' : 'GAGAL'} — durasi=${r.duration ?? '-'} · posisi maks=${r.maxPosMs}ms'
        '${r.error != null ? ' · galat putar: ${describePlayerError(r.error!)}' : ''}');
    for (final c in r.captured) {
      _line('   mentah↳ $c');
    }
  }

  Future<void> _runClientPlayProof() async {
    if (_running) return;
    setState(() {
      _running = true;
      _report.clear();
    });
    final provider = ref.read(ytMusicProvider);
    _line('BUKTI PUTAR KLIEN v3.6 (Ronde Probe Penutup Peta, Fase B) — ${DateTime.now().toIso8601String()}');
    const track = Track(
        key: TrackKey('ytmusic', 'qU9mHegkTc4'),
        title: '505',
        artistNames: 'Arctic Monkeys',
        playableRef: 'qU9mHegkTc4');
    String? winner;
    ClientStreamProbe? winProbe;
    for (final name in _kClients) {
      debugPrint('DIAG-STAGE KP kandidat $name');
      ClientStreamProbe probe;
      try {
        probe = await provider
            .debugProbeNamedClient(name, track)
            .timeout(const Duration(seconds: 90));
      } catch (e) {
        _line('KP · $name: GALAT probe — ${describeError(e)}');
        continue;
      }
      if (!probe.resolved || probe.audioFormats.isEmpty) {
        _line('KP · $name: tidak resolusi ke audio adaptif (playability=${probe.playability}'
            '${probe.error != null ? ' — ${probe.error}' : ''}'
            ' · audio adaptif langsung=${probe.audioFormats.length}) — lanjut.');
        continue;
      }
      final ok2 = await _kWindow(Uri.parse(probe.info!.url), probe.userAgent, 'KP-K2', 1048576, 2097151);
      if (!ok2) {
        _line('KP · $name: jendela 2 gagal — bukan pemenang, lanjut.');
        continue;
      }
      winner = name;
      winProbe = probe;
      _line('KP · PEMENANG: $name (v${probe.version}) — ${probe.info!.mimeType} ${probe.info!.bitrate ?? '-'} bps'
          ' · host=${probe.urlHost ?? '-'}');
      break;
    }
    if (winner == null || winProbe == null) {
      _line('KP · TIDAK ADA klien yang lolos resolusi + jendela 2 — bukti putar gugur.');
    } else {
      final info = winProbe.info!;
      final ua = winProbe.userAgent;
      // KP-1: URI langsung + header pasangan klien pemenang (bentuk anak 1).
      {
        final p = AudioPlayer(useProxyForRequestHeaders: ClaiAudioHandler.useProxyForRequestHeaders);
        try {
          final src = AudioSource.uri(Uri.parse(info.url), headers: {
            'User-Agent': ua,
            'Referer': 'https://music.youtube.com/',
          });
          final r = await _probeLongPlay(p, src, 'KP-1');
          _reportLongPlay('KP-1 · URI langsung adaptif $winner', r);
        } catch (e) {
          _line('KP-1 · GALAT bangun sumber: ${describeError(e)}');
        } finally {
          await p.dispose();
        }
        await _printNative('KP-1');
      }
      // KP-2: ResolvingAudioSource adaptif murni, fetcher sadar-UA pemenang
      // (bentuk anak 3 produksi, TANPA cadangan muxed).
      {
        final src = ResolvingAudioSource(track, () async => info,
            fetcher: (Uri uri, {required int start, required int endInclusive}) =>
                _kUaFetch(uri, ua, start: start, endInclusive: endInclusive));
        final p = AudioPlayer(useProxyForRequestHeaders: false);
        try {
          final r = await _probeLongPlay(p, src, 'KP-2');
          _reportLongPlay('KP-2 · ResolvingAudioSource adaptif $winner (tanpa cadangan)', r);
        } catch (e) {
          _line('KP-2 · GALAT bangun sumber: ${describeError(e)}');
        } finally {
          await p.dispose();
        }
        await _printNative('KP-2');
      }
    }
    _line('');
    _line('SELESAI.');
    for (final l in _report.toString().split('\n')) {
      debugPrint('DIAG-REPORT|$l');
    }
    if (mounted) setState(() => _running = false);
  }

  /// Vonis satu probe putar: BERHASIL hanya bila durasi terbaca DAN posisi
  /// benar-benar maju (≥400 ms) — standar bukti yang sama untuk semua varian.
  Future<({bool ok, Duration? duration, int maxPosMs, Object? error, List<String> captured})>
      _probePlay(AudioPlayer p, AudioSource src) async {
    final captured = <String>[];
    final sub = p.playbackEventStream.listen((ev) {
      if (ev.errorCode != null) {
        final name = exoErrorCodeName(ev.errorCode!);
        final line = 'event: errorCode=${ev.errorCode}${name != null ? ' ($name)' : ''}'
            ' errorMessage=${ev.errorMessage ?? '-'} state=${ev.processingState.name}';
        if (!captured.contains(line)) captured.add(line);
      }
    }, onError: (Object e) {
      final line = 'aliran: ${describePlayerError(e)}';
      if (!captured.contains(line)) captured.add(line);
    });
    try {
      Duration? duration;
      try {
        debugPrint('DIAG-STAGE probePlay setSrc start');
        await p.setAudioSource(src).timeout(const Duration(seconds: 20));
        duration = p.duration;
        debugPrint('DIAG-STAGE probePlay setSrc done duration=$duration');
      } catch (e) {
        debugPrint('DIAG-STAGE probePlay setSrc error: $e');
        await Future<void>.delayed(const Duration(milliseconds: 300));
        return (ok: false, duration: null, maxPosMs: 0, error: e, captured: captured);
      }
      Object? playError;
      try {
        debugPrint('DIAG-STAGE probePlay play start');
        // v3.1: play() tanpa timeout di v3 adalah salah satu kandidat
        // gantungan V6 Video — batasi 10 dtk agar UI tidak membeku selamanya.
        await p.play().timeout(const Duration(seconds: 10));
        debugPrint('DIAG-STAGE probePlay play done');
      } catch (e) {
        debugPrint('DIAG-STAGE probePlay play error: $e');
        playError = e;
      }
      var maxPos = 0;
      final sw = Stopwatch()..start();
      while (sw.elapsed < const Duration(seconds: 8)) {
        final pos = p.position.inMilliseconds;
        if (pos > maxPos) maxPos = pos;
        if (maxPos >= 400 || p.processingState == ProcessingState.completed) break;
        if (playError != null) break;
        if (captured.isNotEmpty && maxPos == 0) break;
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      debugPrint('DIAG-STAGE probePlay loop done maxPos=$maxPos '
          'captured=${captured.length} playError=$playError');
      final ok = playError == null &&
          captured.isEmpty &&
          (maxPos >= 400 || p.processingState == ProcessingState.completed);
      try { await p.stop().timeout(const Duration(seconds: 5)); } catch (_) {}
      debugPrint('DIAG-STAGE probePlay stop done ok=$ok');
      return (ok: ok, duration: duration, maxPosMs: maxPos,
          error: playError, captured: captured);
    } finally {
      await sub.cancel();
    }
  }

  void _reportProbe(String step,
      ({bool ok, Duration? duration, int maxPosMs, Object? error, List<String> captured}) r) {
    if (r.ok) {
      _line('$step: BERHASIL — durasi=${r.duration ?? '-'} · posisi maju s.d. ${r.maxPosMs}ms');
    } else {
      _line('$step: GAGAL — ${r.error != null ? describePlayerError(r.error!) : 'posisi tidak maju (maks ${r.maxPosMs}ms), durasi=${r.duration ?? '-'}'}');
    }
    for (final c in r.captured) {
      _line('   mentah↳ $c');
    }
  }

  // ================= Matriks X — Tahap 2 F3: decipher sig/n =================
  // Rute halaman watch: ytInitialPlayerResponse membawa format audio
  // TERCIPHER (signatureCipher). Fungsi decipher diambil SEGAR dari base.js
  // player resmi dan dinilai di WebView lab. Nilai sig/n/visitorData TIDAK
  // pernah dicatat — hanya panjang, itag, host, keberhasilan.

  static const _uaWatch =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';

  /// Penyeimbang kurung sadar string/komentar untuk kode JS minified.
  /// Mengembalikan teks dari kurung '{' di [openIdx] s.d. pasangannya.
  String? _jsBalanced(String src, int openIdx) {
    var depth = 0;
    String? str;
    var esc = false;
    var lineComment = false;
    var blockComment = false;
    for (var i = openIdx; i < src.length; i++) {
      final c = src[i];
      final next = i + 1 < src.length ? src[i + 1] : '';
      if (lineComment) {
        if (c == '\n') lineComment = false;
        continue;
      }
      if (blockComment) {
        if (c == '*' && next == '/') {
          blockComment = false;
          i++;
        }
        continue;
      }
      if (str != null) {
        if (esc) {
          esc = false;
        } else if (c == '\\') {
          esc = true;
        } else if (c == str) {
          str = null;
        }
        continue;
      }
      if (c == '/' && next == '/') {
        lineComment = true;
        i++;
        continue;
      }
      if (c == '/' && next == '*') {
        blockComment = true;
        i++;
        continue;
      }
      if (c == "'" || c == '"' || c == '`') {
        str = c;
        continue;
      }
      if (c == '{') depth++;
      if (c == '}') {
        depth--;
        if (depth == 0) return src.substring(openIdx, i + 1);
      }
    }
    return null;
  }

  /// Definisi fungsi JS bernama [name] dari [src] (gaya `NAME=function(..){..}`
  /// atau `function NAME(..){..}`), dinormalkan jadi pernyataan utuh.
  String? _jsFunctionDef(String src, String name) {
    final esc = RegExp.escape(name);
    for (final assignStyle in [true, false]) {
      final re = assignStyle
          ? RegExp('$esc\\s*=\\s*function\\s*\\([^)]*\\)\\s*\\{')
          : RegExp('function\\s+$esc\\s*\\([^)]*\\)\\s*\\{');
      final m = re.firstMatch(src);
      if (m == null) continue;
      final body = _jsBalanced(src, m.end - 1);
      if (body == null) continue;
      final head = src.substring(m.start, m.end - 1);
      return assignStyle ? 'var $head$body' : '$head$body';
    }
    return null;
  }

  /// Definisi objek pembantu `var NAME={...}` dari [src].
  String? _jsObjectDef(String src, String name) {
    final m = RegExp('(?:^|[;\\s])${RegExp.escape(name)}\\s*=\\s*\\{').firstMatch(src);
    if (m == null) return null;
    final body = _jsBalanced(src, m.end - 1);
    if (body == null) return null;
    return 'var $name=$body;';
  }

  /// Ekstrak solver (fungsi sig + fungsi n + objek/fungsi pembantu) dari
  /// base.js. Mengembalikan null bila fungsi sig tidak ditemukan; [notes]
  /// diisi jejak penemuan (nama fungsi saja — bukan nilai apa pun).
  ({String defs, String sigName, String? nName})? _extractSolver(
      String baseJs, List<String> notes) {
    String? sigName;
    final sigPatterns = <RegExp>[
      RegExp(r'''([A-Za-z_$][\w$]*)\s*=\s*function\(\s*([A-Za-z_$][\w$]*)\s*\)\s*\{\s*\2\s*=\s*\2\.split\(""\)'''),
      RegExp(r'''function\s+([A-Za-z_$][\w$]*)\(\s*([A-Za-z_$][\w$]*)\s*\)\s*\{\s*\2\s*=\s*\2\.split\(""\)'''),
      RegExp(r"""([A-Za-z_$][\w$]*)\s*=\s*function\(\s*([A-Za-z_$][\w$]*)\s*\)\s*\{\s*\2\s*=\s*\2\.split\(''\)"""),
      RegExp(r"""function\s+([A-Za-z_$][\w$]*)\(\s*([A-Za-z_$][\w$]*)\s*\)\s*\{\s*\2\s*=\s*\2\.split\(''\)"""),
      RegExp(r'''["']signature["']\s*,\s*([A-Za-z_$][\w$]*)\s*\('''),
    ];
    for (var i = 0; i < sigPatterns.length; i++) {
      final m = sigPatterns[i].firstMatch(baseJs);
      if (m != null) {
        sigName = m.group(1);
        notes.add('fungsi sig ditemukan via pola ${i + 1}');
        break;
      }
    }
    if (sigName == null) {
      notes.add('fungsi sig TIDAK ditemukan oleh pola mana pun');
      return null;
    }
    final sigDef = _jsFunctionDef(baseJs, sigName);
    if (sigDef == null) {
      notes.add('definisi fungsi sig "$sigName" gagal diekstrak seimbang');
      return null;
    }
    notes.add('fungsi sig "$sigName" terekstrak (${sigDef.length} char)');

    String? nName;
    final nPatterns = <RegExp>[
      RegExp(r'''get\("n"\)\)&&\(\w+=([A-Za-z_$][\w$]*)\(\w+\)'''),
      RegExp(r'''get\("n"\)\)&&\([^;]{0,60}?=\s*([A-Za-z_$][\w$]*)\('''),
      RegExp(r'''["']n["']\s*,\s*([A-Za-z_$][\w$]*)\('''),
    ];
    for (var i = 0; i < nPatterns.length; i++) {
      final m = nPatterns[i].firstMatch(baseJs);
      if (m != null) {
        nName = m.group(1);
        notes.add('fungsi n ditemukan via pola ${i + 1}');
        break;
      }
    }
    String? nDef;
    if (nName != null) {
      nDef = _jsFunctionDef(baseJs, nName);
      if (nDef == null) {
        notes.add('definisi fungsi n "$nName" gagal diekstrak — lanjut sig saja');
        nName = null;
      } else {
        notes.add('fungsi n "$nName" terekstrak (${nDef.length} char)');
      }
    } else {
      notes.add('fungsi n tidak ditemukan — mode sig saja');
    }

    // Objek & fungsi pembantu yang dirujuk badan fungsi (maks. 6).
    const deny = {'this', 'window', 'document', 'Math', 'JSON', 'Object', 'Array', 'String', 'Number', 'if', 'for', 'while', 'switch', 'return', 'function', 'typeof', 'new', 'in', 'of'};
    final helpers = <String>[];
    final seen = <String>{sigName, if (nName != null) nName};
    final bodies = [sigDef, if (nDef != null) nDef];
    for (final body in bodies) {
      for (final m in RegExp(r'([A-Za-z_$][\w$]*)\s*\.').allMatches(body)) {
        final id = m.group(1)!;
        if (deny.contains(id) || !seen.add(id)) continue;
        final obj = _jsObjectDef(baseJs, id);
        if (obj != null && helpers.length < 6) {
          helpers.add(obj);
          notes.add('objek pembantu "$id" terekstrak (${obj.length} char)');
        }
      }
      for (final m in RegExp(r'(?<![\w$.])([A-Za-z_$][\w$]*)\s*\(').allMatches(body)) {
        final id = m.group(1)!;
        if (deny.contains(id) || !seen.add(id)) continue;
        final fn = _jsFunctionDef(baseJs, id);
        if (fn != null && helpers.length < 6) {
          helpers.add(fn);
          notes.add('fungsi pembantu "$id" terekstrak (${fn.length} char)');
        }
      }
    }
    final defs = [...helpers, sigDef, if (nDef != null) nDef].join('\n');
    return (defs: defs, sigName: sigName, nName: nName);
  }

  /// Nilai decipher untuk daftar tantangan (s, n?) lewat WebView lab.
  Future<_SolveOutcome> _solveChallenges(PoTokenLabState lab,
      ({String defs, String sigName, String? nName}) solver, List<({String s, String? n})> challenges) async {
    final input = jsonEncode([
      for (final c in challenges) {'s': c.s, if (c.n != null) 'n': c.n},
    ]);
    final nExpr = solver.nName == null
        ? 'null'
        : '(ch.n && typeof ${solver.nName} === "function") ? ${solver.nName}(ch.n) : null';
    final script = '(function(){try{${solver.defs}\n'
        'var input=$input;var out=[];'
        'for(var i=0;i<input.length;i++){var ch=input[i];'
        'out.push({sig:${solver.sigName}(ch.s),n:$nExpr});}'
        'return JSON.stringify({ok:true,out:out});'
        '}catch(e){return JSON.stringify({ok:false,error:String(e&&e.message||e)});}})()';
    final String? raw;
    try {
      raw = await lab.evalSolver(script);
    } catch (e) {
      return _SolveOutcome.fail('eval WebView gagal: ${describeError(e)}');
    }
    if (raw == null) return const _SolveOutcome.fail('eval mengembalikan null');
    try {
      final d = jsonDecode(raw);
      if (d is! Map) return const _SolveOutcome.fail('hasil eval bukan objek');
      if (d['ok'] != true) return _SolveOutcome.fail('JS: ${d['error']}');
      final out = <({String sig, String? n})>[];
      for (final e in (d['out'] as List? ?? const [])) {
        final m = (e as Map).cast<String, dynamic>();
        out.add((sig: '${m['sig']}', n: m['n'] as String?));
      }
      if (out.length != challenges.length) {
        return _SolveOutcome.fail('jumlah hasil ${out.length} != tantangan ${challenges.length}');
      }
      return _SolveOutcome.ok(out);
    } catch (e) {
      return _SolveOutcome.fail('urai hasil eval gagal: ${describeError(e)}');
    }
  }

  /// Pilih format tingkat Normal: bitrate tertinggi ≤ cap Normal, kalau
  /// tidak ada ambil yang terendah di atasnya.
  WatchFormat? _xPickNormal(Iterable<WatchFormat> formats) {
    final list = formats.where((f) => f.bitrate != null).toList()
      ..sort((a, b) => a.bitrate!.compareTo(b.bitrate!));
    if (list.isEmpty) return null;
    final cap = StreamQuality.normal.maxBitrate;
    WatchFormat? best;
    for (final f in list) {
      if (f.bitrate! <= cap) best = f;
    }
    return best ?? list.first;
  }

  /// Bangun URL final dari format tercipher + hasil decipher.
  String _xBuildUrl(WatchFormat fmt, String sig, String? nSolved) {
    var base = fmt.cipherBaseUrl!;
    if (nSolved != null) {
      final u = Uri.parse(base);
      final q = Map<String, String>.from(u.queryParameters);
      if (q.containsKey('n')) {
        q['n'] = nSolved;
        base = u.replace(queryParameters: q).toString();
      }
    }
    return '$base&${fmt.cipherSp}=${Uri.encodeComponent(sig)}';
  }

  /// Pastikan solver tersedia di [st] (ambil base.js sekali dari jalur
  /// player milik [probe]). Baris jejak ditambahkan ke [lines].
  Future<bool> _xEnsureSolver(
      YtMusicProvider p, WatchPlayerProbe probe, _SolverState st) async {
    if (st.solver != null) return true;
    if (st.extractFailed) return false;
    final jsPath = probe.jsPath;
    if (jsPath == null) {
      _line('X · jalur player JS tidak ada di halaman watch');
      st.extractFailed = true;
      return false;
    }
    final parts = jsPath.split('/');
    st.playerId = parts.length > 3 ? parts[3] : jsPath;
    _line('X · player JS: $jsPath (id ${st.playerId})');
    final js = await p.debugFetchText('https://www.youtube.com$jsPath');
    if (js == null || js.length < 10000) {
      _line('X · base.js GAGAL diambil (panjang ${js?.length ?? 0})');
      st.extractFailed = true;
      return false;
    }
    st.baseJs = js;
    _line('X · base.js terambil: ${js.length} char');
    final notes = <String>[];
    final solver = _extractSolver(js, notes);
    for (final n in notes) {
      _line('X · ekstrak: $n');
    }
    if (solver == null) {
      st.extractFailed = true;
      return false;
    }
    st.solver = solver;
    return true;
  }

  /// Resolusi segar satu subjek lewat rute watch+decipher untuk bukti
  /// putar. Null bila tahap mana pun gagal.
  Future<({Uri uri, WatchFormat fmt})?> _xResolveForPlay(YtMusicProvider p, Track track,
      PoTokenLabState lab, _SolverState st) async {
    final probe = await p.debugFetchWatchPlayer(track.id);
    if (probe.error != null || probe.playability != 'OK') return null;
    final direct = _xPickNormal(probe.audio.where((f) => f.directUrl != null));
    if (direct != null) return (uri: Uri.parse(direct.directUrl!), fmt: direct);
    final fmt = _xPickNormal(probe.audio.where((f) => f.ciphered));
    if (fmt == null) return null;
    if (!await _xEnsureSolver(p, probe, st)) return null;
    final nRaw = Uri.parse(fmt.cipherBaseUrl!).queryParameters['n'];
    final solved = await _solveChallenges(lab, st.solver!, [(s: fmt.cipherS!, n: nRaw)]);
    final v = solved.values;
    if (v == null || v.isEmpty) return null;
    return (uri: Uri.parse(_xBuildUrl(fmt, v.first.sig, v.first.n)), fmt: fmt);
  }

  /// Resolusi segar satu subjek lewat rute X2 (InnerTube [clientName] +
  /// visitorData konteks tonton + decipher) untuk bukti putar.
  Future<({Uri uri, WatchFormat fmt})?> _xResolveForPlay2(YtMusicProvider p, Track track,
      PoTokenLabState lab, _SolverState st, String clientName) async {
    final wc = await p.debugFetchWatchContext(track.id);
    if (wc.visitorData == null) return null;
    final probe = await p.debugResolveCiphered(clientName, track,
        visitorData: wc.visitorData, signatureTimestamp: wc.signatureTimestamp);
    if (probe.error != null || probe.playability != 'OK') return null;
    final direct = _xPickNormal(probe.audio.where((f) => f.directUrl != null));
    if (direct != null) return (uri: Uri.parse(direct.directUrl!), fmt: direct);
    final fmt = _xPickNormal(probe.audio.where((f) => f.ciphered));
    if (fmt == null) return null;
    final watch = await p.debugFetchWatchPlayer(track.id);
    if (!await _xEnsureSolver(p, watch, st)) return null;
    final nRaw = Uri.parse(fmt.cipherBaseUrl!).queryParameters['n'];
    final solved = await _solveChallenges(lab, st.solver!, [(s: fmt.cipherS!, n: nRaw)]);
    final v = solved.values;
    if (v == null || v.isEmpty) return null;
    return (uri: Uri.parse(_xBuildUrl(fmt, v.first.sig, v.first.n)), fmt: fmt);
  }

  /// Uji satu format pada [uri]: tiga jendela Tahap 2 (penentu jendela 2,
  /// lalu tengah, lalu 1) memakai primitif matriks K.
  Future<bool> _xWindows(Uri uri, int? contentLength, String tag) async {
    final w2 = await _kWindow(uri, _uaWatch, 'X$tag-2', 1048576, 2097151);
    if (!w2) return false;
    var w3ok = true;
    if (contentLength != null && contentLength <= 3000000) {
      _line('   X$tag-3 · dilewati (berkas hanya $contentLength byte)');
    } else {
      w3ok = await _kWindow(uri, _uaWatch, 'X$tag-3', 3000000, 4048575);
    }
    final w1 = await _kWindow(uri, _uaWatch, 'X$tag-1', 0, 1048575);
    return w2 && w3ok && w1;
  }

  /// Coba decipher+rentang untuk pilihan tercipher [pick] dari [track];
  /// true bila rentang penuh lolos.
  Future<bool> _xTryCiphered(YtMusicProvider p, Track track, PoTokenLabState lab,
      _SolverState st, WatchPlayerProbe solverProbe, WatchFormat pick, String tag) async {
    if (!await _xEnsureSolver(p, solverProbe, st)) {
      _line('X · [$tag] solver tidak tersedia.');
      return false;
    }
    final nRaw = Uri.parse(pick.cipherBaseUrl!).queryParameters['n'];
    _line('X · [$tag] tercipher itag ${pick.itag} ${pick.mime} ${pick.bitrate} bps'
        ' · s ${pick.cipherS!.length} char · sp "${pick.cipherSp}"'
        ' · n ${nRaw == null ? 'tidak ada' : '${nRaw.length} char'} pada URL dasar');
    debugPrint('DIAG-STAGE X $tag solve');
    final solved = await _solveChallenges(lab, st.solver!, [(s: pick.cipherS!, n: nRaw)]);
    final v = solved.values;
    if (v == null || v.isEmpty) {
      _line('X · [$tag] DECIPHER GAGAL — ${solved.error}');
      return false;
    }
    final got = v.first;
    _line('X · [$tag] decipher OK — sig hasil ${got.sig.length} char'
        '${got.n == null ? ' · n tidak diubah' : ' · n hasil ${got.n!.length} char'}'
        ' · mode ${st.solver!.nName == null ? 'sig saja' : 'sig+n'}');
    return _xWindows(Uri.parse(_xBuildUrl(pick, got.sig, got.n)), pick.contentLength, tag);
  }

  Future<void> _runDecipherMatrix() async {
    if (_running) return;
    setState(() {
      _running = true;
      _report.clear();
    });
    final p = ref.read(ytMusicProvider);
    final lab = _poLabKey.currentState;
    _line('MATRIKS DECIPHER F3 v3.8 (Batch 0 — Tahap 2: decipher sig/n; X1 halaman watch, X2 InnerTube WEB + visitorData) — ${DateTime.now().toIso8601String()}');
    _line('Perangkat: ${Platform.operatingSystemVersion}');
    _line('Nilai sig/n/visitorData TIDAK dicatat di laporan ini — hanya panjang & keberhasilan.');
    _line('');
    try {
      if (lab == null) {
        _line('X · VONIS TAHAP 2: GAGUR — lab WebView tidak terpasang di pohon diagnostik.');
        _finishReport();
        return;
      }
      final st = _SolverState();
      final wins = <String, String>{}; // id subjek → rute pemenang
      WatchPlayerProbe? firstWatchProbe;

      // ---------- Fase X1: halaman watch ----------
      _line('── FASE X1 · halaman watch (ytInitialPlayerResponse)');
      for (final (label, track) in _kSubjects) {
        _line('════════ $label');
        _line('Trek: "${track.title}" — ${track.artistNames} [${track.id}]');
        debugPrint('DIAG-STAGE X ${track.id} watch');
        WatchPlayerProbe probe;
        try {
          probe = await p.debugFetchWatchPlayer(track.id).timeout(const Duration(seconds: 60));
        } catch (e) {
          _line('X1 · [${track.id}] halaman watch GALAT: ${describeError(e)}');
          continue;
        }
        if (probe.error != null) {
          _line('X1 · [${track.id}] HALAMAN WATCH GAGAL — ${probe.error}');
          continue;
        }
        firstWatchProbe ??= probe;
        final directCount = probe.audio.where((f) => f.directUrl != null).length;
        final cipherCount = probe.audio.where((f) => f.ciphered).length;
        _line('X1 · [${track.id}] playability ${probe.playability}'
            '${probe.reason.isEmpty ? '' : ' "${probe.reason}"'}'
            ' · audio langsung $directCount · audio tercipher $cipherCount'
            ' · sts ${probe.signatureTimestamp == null ? 'tidak ada' : 'ada'}'
            ' · visitorData halaman ${probe.visitorDataLength} char'
            ' · jsUrl ${probe.jsPath == null ? 'tidak ada' : 'ada'}');
        if (probe.playability != 'OK') continue;
        final directPick = _xPickNormal(probe.audio.where((f) => f.directUrl != null));
        if (directPick != null) {
          _line('X1 · [${track.id}] format langsung itag ${directPick.itag} ${directPick.mime} ${directPick.bitrate} bps — uji rentang:');
          if (await _xWindows(Uri.parse(directPick.directUrl!), directPick.contentLength, track.id)) {
            wins[track.id] = 'watch';
            continue;
          }
        }
        final pick = _xPickNormal(probe.audio.where((f) => f.ciphered));
        if (pick == null) {
          _line('X1 · [${track.id}] tidak ada format audio tercipher dari halaman watch.');
          continue;
        }
        if (await _xTryCiphered(p, track, lab, st, probe, pick, track.id)) {
          wins[track.id] = 'watch';
        }
      }
      _line('X · fase X1: rentang LOLOS ${wins.length}/${_kSubjects.length} subjek.');

      // ---------- Fase X2: InnerTube WEB/WEB_EMBEDDED + visitorData ----------
      if (wins.length < 3) {
        _line('');
        _line('── FASE X2 · InnerTube keluarga WEB + visitorData konteks tonton → cipher → decipher');
        for (final (label, track) in _kSubjects) {
          if (wins.containsKey(track.id)) continue;
          _line('════════ $label');
          _line('Trek: "${track.title}" — ${track.artistNames} [${track.id}]');
          debugPrint('DIAG-STAGE X ${track.id} konteks-x2');
          ({String? visitorData, String source, int? signatureTimestamp}) wc;
          try {
            wc = await p.debugFetchWatchContext(track.id).timeout(const Duration(seconds: 60));
          } catch (e) {
            _line('X2 · [${track.id}] konteks tonton GALAT: ${describeError(e)}');
            continue;
          }
          if (wc.visitorData == null) {
            _line('X2 · [${track.id}] visitorData TIDAK didapat (sumber: ${wc.source}) — subjek dilewati.');
            continue;
          }
          _line('X2 · [${track.id}] konteks: sumber=${wc.source} · visitorData=${wc.visitorData!.length} char'
              ' · sts ${wc.signatureTimestamp != null ? 'ada' : 'tidak ada'}');
          for (final clientName in ['WEB', 'WEB_EMBEDDED_PLAYER']) {
            debugPrint('DIAG-STAGE X ${track.id} x2-$clientName');
            WatchPlayerProbe probe2;
            try {
              probe2 = await p
                  .debugResolveCiphered(clientName, track,
                      visitorData: wc.visitorData, signatureTimestamp: wc.signatureTimestamp)
                  .timeout(const Duration(seconds: 60));
            } catch (e) {
              _line('X2 · [$clientName ${track.id}] GALAT: ${describeError(e)}');
              continue;
            }
            if (probe2.error != null) {
              _line('X2 · [$clientName ${track.id}] GAGAL — ${probe2.error}');
              continue;
            }
            final dCount = probe2.audio.where((f) => f.directUrl != null).length;
            final cCount = probe2.audio.where((f) => f.ciphered).length;
            _line('X2 · [$clientName ${track.id}] playability ${probe2.playability}'
                '${probe2.reason.isEmpty ? '' : ' "${probe2.reason}"'}'
                ' · audio langsung $dCount · audio tercipher $cCount');
            if (probe2.playability != 'OK') continue;
            final directPick = _xPickNormal(probe2.audio.where((f) => f.directUrl != null));
            if (directPick != null) {
              _line('X2 · [$clientName ${track.id}] format langsung itag ${directPick.itag} ${directPick.mime} ${directPick.bitrate} bps — uji rentang:');
              if (await _xWindows(Uri.parse(directPick.directUrl!), directPick.contentLength, track.id)) {
                wins[track.id] = clientName;
                break;
              }
            }
            final pick = _xPickNormal(probe2.audio.where((f) => f.ciphered));
            if (pick == null) {
              _line('X2 · [$clientName ${track.id}] tidak ada format audio tercipher.');
              continue;
            }
            final solverProbe = firstWatchProbe ?? await p.debugFetchWatchPlayer(track.id);
            if (await _xTryCiphered(p, track, lab, st, solverProbe, pick, '$clientName ${track.id}')) {
              wins[track.id] = clientName;
              break;
            }
          }
        }
        _line('X · sesudah fase X2: rentang LOLOS total ${wins.length}/${_kSubjects.length} subjek.');
      }

      // ---------- Bukti putar ----------
      if (wins.length >= 3) {
        var playWins = 0;
        for (final (_, track) in _kSubjects.where((e) => wins.containsKey(e.$2.id))) {
          final route = wins[track.id]!;
          debugPrint('DIAG-STAGE X ${track.id} putar-$route');
          final r = route == 'watch'
              ? await _xResolveForPlay(p, track, lab, st)
              : await _xResolveForPlay2(p, track, lab, st, route);
          if (r == null) {
            _line('XP · [${track.id}] resolusi segar untuk putar GAGAL (rute $route).');
            continue;
          }
          final player = AudioPlayer(useProxyForRequestHeaders: ClaiAudioHandler.useProxyForRequestHeaders);
          try {
            final res = await _probeCrossPlay(player, r.uri, {
              'User-Agent': _uaWatch,
              'Referer': 'https://www.youtube.com/watch?v=${track.id}',
            }, 'XP-${track.id}');
            _line('XP · [${track.id}] rute $route · itag ${r.fmt.itag} (${r.fmt.mime}): ${res.ok ? 'LOLOS PUTAR' : 'GAGAL PUTAR'} — ${res.detail}');
            if (res.ok) playWins++;
          } catch (e) {
            _line('XP · [${track.id}] GALAT bukti putar: ${describeError(e)}');
          } finally {
            await player.dispose();
          }
          await _printNative('XP-${track.id}');
        }
        _line('X · bukti putar LOLOS $playWins subjek (syarat ≥3).');
        if (playWins >= 3) {
          _line('X · VONIS TAHAP 2: LOLOS — decipher sig${st.solver?.nName == null ? ' (tanpa n)' : '+n'} dari player ${st.playerId ?? '?'} '
              'membuat URL keluarga WEB melayani rentang penuh & putar berkelanjutan/seek pada $playWins subjek '
              '(rute: ${wins.values.toSet().join(', ')}).');
          _finishReport();
          return;
        }
      }
      // Uji mandiri solver: bila solver tak pernah terlibat (nol bahan
      // tercipher dari semua rute), buktikan mesin ekstrak+eval-nya sendiri
      // pada player JS segar — memisahkan "mesin rusak" dari "bahan tidak ada".
      if (st.solver == null && !st.extractFailed && firstWatchProbe != null) {
        _line('');
        _line('── UJI MANDIRI SOLVER (bukan bukti penyeberangan)');
        if (await _xEnsureSolver(p, firstWatchProbe, st)) {
          const ujiS = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklm';
          const ujiN = 'UjiNilaiN-0123456789_abcdef';
          final solvedUji = await _solveChallenges(lab, st.solver!, [(s: ujiS, n: ujiN)]);
          final vu = solvedUji.values;
          if (vu == null || vu.isEmpty) {
            _line('X · uji mandiri: EVAL GAGAL — ${solvedUji.error}');
          } else {
            _line('X · uji mandiri: eval OK — s ${ujiS.length} char → sig ${vu.first.sig.length} char'
                ' · n ${vu.first.n == null ? 'tidak diubah' : '${ujiN.length} char → ${vu.first.n!.length} char'}'
                ' · mode ${st.solver!.nName == null ? 'sig saja' : 'sig+n'} · player ${st.playerId ?? '?'}');
          }
        } else {
          _line('X · uji mandiri: ekstraksi solver GAGAL pada player segar (lihat baris ekstrak di atas).');
        }
      }
      _line('X · VONIS TAHAP 2: GAGUR — decipher tidak menghasilkan penyeberangan terbukti '
          '(rentang lolos ${wins.length}/4; keadaan solver: ${st.solver != null ? 'terekstrak & terevaluasi, mode ${st.solver!.nName == null ? 'sig saja' : 'sig+n'}' : (st.extractFailed ? 'ekstraksi gagal' : 'tidak terlibat')}). Lanjut Tahap 3 (SABR).');
      _finishReport();
    } catch (e) {
      _line('X · GALAT FATAL matriks: ${describeError(e)}');
      _line('X · VONIS TAHAP 2: GAGUR — galat fatal (lihat baris di atas).');
      _finishReport();
    }
  }

  // ================= Matriks S — Tahap 3 F3: kehadiran SABR =================
  Future<void> _runSabrPresence() async {
    if (_running) return;
    setState(() {
      _running = true;
      _report.clear();
    });
    final p = ref.read(ytMusicProvider);
    _line('MATRIKS SABR F3 v3.8 (Batch 0 — Tahap 3a: kehadiran serverAbrStreamingUrl) — ${DateTime.now().toIso8601String()}');
    _line('URL SABR penuh TIDAK dicatat — hanya kehadiran & host.');
    _line('');
    const combos = <(String, String?)>[
      ('ANDROID', null),
      ('IOS', null),
      ('WEB_REMIX', null),
      ('WEB', null),
      ('TVHTML5', null),
      ('ANDROID_VR', null),
      ('ANDROID', '21.26.364'),
    ];
    var abrCount = 0;
    final abrWhere = <String>[];
    for (final (_, track) in _kSubjects.take(2)) {
      _line('Trek: "${track.title}" [${track.id}]');
      for (final (clientName, version) in combos) {
        debugPrint('DIAG-STAGE S $clientName ${version ?? ''} ${track.id}');
        try {
          final r = await p
              .debugAbrPresence(clientName, track, versionOverride: version)
              .timeout(const Duration(seconds: 60));
          final tag = '$clientName${version == null ? '' : '@$version'}';
          if (r.error != null) {
            _line('S · [$tag ${track.id}] GALAT: ${r.error}');
            continue;
          }
          _line('S · [$tag ${track.id}] playability ${r.playability} · serverAbrStreamingUrl '
              '${r.abrHost == null ? 'TIDAK TERBIT' : 'TERBIT (host ${r.abrHost})'}'
              ' · kunci streamingData: ${r.sdKeys.join(', ')}');
          if (r.abrHost != null) {
            abrCount++;
            abrWhere.add('$tag/${track.id}');
          }
        } catch (e) {
          _line('S · [$clientName ${track.id}] GALAT: ${describeError(e)}');
        }
      }
      _line('');
    }
    if (abrCount > 0) {
      _line('S · HASIL TAHAP 3a: URL SABR TERBIT anonim pada $abrCount kombinasi: ${abrWhere.join('; ')} — PoC permintaan SABR layak dicoba.');
    } else {
      _line('S · HASIL TAHAP 3a: TIDAK ADA URL SABR terbit anonim pada semua kombinasi klien × 2 subjek.');
    }
    // ---------- Tahap 3b: PoC permintaan SABR (klien ANDROID) ----------
    if (abrWhere.any((w) => w.startsWith('ANDROID/'))) {
      _line('');
      _line('── TAHAP 3b · PoC SABR ANDROID (permintaan protobuf + urai UMP; subjek pertama maks 40 putaran untuk bukti lagu utuh, subjek kedua maks 8)');
      // Token sesi (terikat visitorData) dari lab BotGuard untuk streamerContext
      // field 2 — nilai token tidak pernah dicatat, hanya panjangnya.
      Uint8List? sabrPoToken;
      final labS = _poLabKey.currentState;
      if (labS != null) {
        try {
          final sess = await labS.ensureSession().timeout(const Duration(seconds: 90));
          final vt = sess.visitorToken;
          if (sess.ok && vt != null && vt.isNotEmpty) {
            try {
              sabrPoToken = base64Url.decode(base64Url.normalize(vt));
            } catch (_) {
              sabrPoToken = Uint8List.fromList(utf8.encode(vt));
            }
            _line('S · token sesi lab: visitorData ${sess.visitorDataLen} char - token visitor ${sess.visitorTokenLen} char -> ${sabrPoToken.length} byte untuk streamerContext');
          } else {
            _line('S · token sesi lab: GAGAL (${sess.errors.isEmpty ? 'kosong' : sess.errors.first}) - PoC jalan tanpa token');
          }
        } catch (e) {
          _line('S · token sesi lab: GALAT ${e.runtimeType} - PoC jalan tanpa token');
        }
      }
      var pocIdx = 0;
      for (final (_, track) in _kSubjects.take(2)) {
        debugPrint('DIAG-STAGE S poc ${track.id}');
        try {
          final r = await p.debugSabrPoc(track, maxRounds: pocIdx == 0 ? 40 : 8, poToken: sabrPoToken).timeout(const Duration(seconds: 600));
          _line('S · PoC [${track.id}] itag ${r.itag} · putaran ${r.rounds} · segmen ${r.segments}'
              '${r.endSegmentNumber == null ? '' : ' dari ${r.endSegmentNumber}'}'
              ' · byte MEDIA audio ${r.mediaBytesAudio} (total semua format ${r.mediaBytesTotal})'
              ' · contentLength ${r.contentLength}'
              ' · proteksi ${r.protection ?? '-'} · sabrError ${r.sabrError ? 'YA' : 'tidak'}');
          _line('S · PoC [${track.id}] tipe part UMP: ${r.partTypes.entries.map((e) => '${e.key}×${e.value}').join(', ')}');
          _line('S · PoC [${track.id}] rincian: ${r.detail}');
          _line('S · PoC [${track.id}] ${r.mediaBytesAudio > 1048576 ? 'MENEMBUS 1 MiB lewat SABR' : 'belum menembus 1 MiB'}');
          if (r.contentLength > 0 &&
              r.mediaBytesAudio >= r.contentLength) {
            _line('S · PoC [${track.id}] LAGU UTUH tersaji lewat SABR (byte MEDIA >= contentLength)');
          }
        } catch (e) {
          _line('S · PoC [${track.id}] GALAT: ${describeError(e)}');
        }
        pocIdx++;
      }
    }
    _finishReport();
  }


  // ================= Matriks T — Probe Plafon SABR (Batch 0.5 F3) =================
  // Menyerang plafon sesi SABR Batch 0 (±62–70 dtk / ±1,05–1,13 MB):
  // T0 kehadiran URL untuk keluarga SABR lain (identitas innertubex),
  // T1 sesi FIDEL per keluarga (keadaan ABR meniru referensi googlevideo),
  // T2 playhead waktu-dinding, T3 perpanjangan sesi dari posisi plafon.
  // Kriteria lolos: audio utuh ≥95% contentLength, tereproduksi ≥2 lari.
  Future<void> _runSabrCeiling() async {
    if (_running) return;
    setState(() {
      _running = true;
      _report.clear();
    });
    final p = ref.read(ytMusicProvider);
    final s1 = _kSubjects[0].$2;
    final s2 = _kSubjects[1].$2;
    _line('MATRIKS PLAFON SABR v3.9.2 (Batch 0.5 F3) — ${DateTime.now().toIso8601String()}');
    _line('URL SABR penuh & nilai sesi TIDAK dicatat — hanya angka, host, nama field.');
    _line('');

    void logSession(String tag, SabrSessionResult r) {
      _line('T · [$tag] ${r.config} · itag ${r.itag} · putaran ${r.rounds} · media '
          '${r.mediaBytesAudio}/${r.contentLength} byte (${r.pct}%) · segmen ${r.segments} '
          's.d. ${r.maxSegment}${r.endSegmentNumber == null ? '' : '/${r.endSegmentNumber}'} · '
          'frontier ${r.frontierMs}ms/${r.approxDurMs}ms · cakupan ${r.coveragePct}% · proteksi ${r.protection ?? '-'} · '
          'berhenti: ${r.stopReason} · dinding ${r.elapsedMs}ms');
      if (r.policySummary.isNotEmpty) _line('T · [$tag] kebijakan: ${r.policySummary}');
      _line('T · [$tag] tipe part: ${r.partTypes.entries.map((e) => '${e.key}×${e.value}').join(', ')}');
      _line('T · [$tag] rincian: ${r.detail}');
    }

    Future<SabrSessionResult> run(String tag, Track track,
        {required String spec,
        bool faithful = true,
        int mode = 1,
        int maxRounds = 40,
        int startAtMs = 0,
        int preBufferedEndMs = 0,
        int preSegEnd = 0}) async {
      debugPrint('DIAG-STAGE T $tag ${track.id}');
      try {
        final r = await p
            .debugSabrSession(track,
                specKey: spec,
                faithful: faithful,
                playheadMode: mode,
                maxRounds: maxRounds,
                startAtMs: startAtMs,
                preBufferedEndMs: preBufferedEndMs,
                preSegEnd: preSegEnd)
            .timeout(const Duration(seconds: 900));
        logSession(tag, r);
        return r;
      } catch (e) {
        _line('T · [$tag] GALAT: ${describeError(e)}');
        return SabrSessionResult.failure(tag, describeError(e));
      }
    }

    // ---------- T0: kehadiran URL SABR keluarga lain ----------
    _line('── T0 · kehadiran serverAbrStreamingUrl (identitas katalog innertubex)');
    const famCtx = <String, String>{
      'VISIONOS': 'VISIONOS',
      'WEB_REMIX_SABR': 'WEB_REMIX',
      'IOS_SABR': 'IOS',
      'TVHTML5_SABR': 'TVHTML5',
    };
    final published = <String>{};
    for (final e in famCtx.entries) {
      for (final track in [s1, s2]) {
        try {
          final r = await p.debugAbrPresence(e.key, track).timeout(const Duration(seconds: 60));
          _line('T · [${e.key} ${track.id}] playability ${r.playability} · SABR '
              '${r.abrHost == null ? 'TIDAK TERBIT' : 'TERBIT (host ${r.abrHost})'}'
              '${r.error != null ? ' · galat ${r.error}' : ''}');
          if (r.abrHost != null) published.add(e.value);
        } catch (err) {
          _line('T · [${e.key} ${track.id}] GALAT: ${describeError(err)}');
        }
        if (published.contains(e.value)) break;
      }
    }
    _line('T · keluarga terbit: ${published.isEmpty ? '(tidak ada)' : published.join(', ')} (ANDROID terbit sejak Batch 0)');
    _line('');

    // ---------- T1: kontrol BASE + sesi FIDEL per keluarga ----------
    _line('── T1 · kontrol resep PoC (BASE) lalu resep FIDEL-0 per keluarga');
    final ceilings = <String, SabrSessionResult>{};
    SabrSessionResult? winner;
    String? winnerSpec;
    var winnerMode = 1;

    final base = await run('KONTROL', s1, spec: 'ANDROID', faithful: false, maxRounds: 14);
    ceilings['ANDROID/BASE'] = base;
    final fidel = await run('ANDROID', s1, spec: 'ANDROID', mode: 3);
    ceilings['ANDROID/FIDEL-EST'] = fidel;
    if (fidel.complete) {
      winner = fidel;
      winnerSpec = 'ANDROID';
      winnerMode = 3;
    } else {
      // ---------- T2: mode unduh playhead-0 & playhead waktu-dinding ----------
      _line('── T2 · FIDEL-0 deklarasi jujur, lalu playhead waktu-dinding (ANDROID)');
      final zeroT = await run('ANDROID-0T', s1, spec: 'ANDROID', mode: 1);
      ceilings['ANDROID/FIDEL-0'] = zeroT;
      if (zeroT.complete) {
        winner = zeroT;
        winnerSpec = 'ANDROID';
        winnerMode = 1;
      } else {
        final rt = await run('ANDROID-RT', s1, spec: 'ANDROID', mode: 2, maxRounds: 700);
        ceilings['ANDROID/FIDEL-RT'] = rt;
        if (rt.complete) {
          winner = rt;
          winnerSpec = 'ANDROID';
          winnerMode = 2;
        } else {
          for (final spec in ['VISIONOS', 'IOS', 'WEB_REMIX', 'TVHTML5']) {
            if (winner != null) break;
            if (!published.contains(spec)) {
              _line('T · [$spec] dilewati — URL tidak terbit di T0');
              continue;
            }
            final r = await run(spec, s1, spec: spec, mode: 3);
            ceilings['$spec/FIDEL-EST'] = r;
            if (r.complete) {
              winner = r;
              winnerSpec = spec;
              winnerMode = 3;
            }
          }
        }
      }
    }

    if (winner != null) {
      // ---------- Reproduksi konfigurasi pemenang ----------
      _line('── REPRODUKSI · ${winner.config} pada subjek 1 (lari 2) & subjek 2 (lari 1)');
      final w = winner;
      final rep1 = await run('REPRO-1', s1, spec: winnerSpec!, mode: winnerMode);
      final rep2 = await run('REPRO-2', s2, spec: winnerSpec, mode: winnerMode);
      final okCount = [w, rep1, rep2].where((r) => r.complete).length;
      _line('VONIS PLAFON: LAGU UTUH tercapai oleh ${w.config} — lengkap $okCount/3 lari '
          '(subjek1 ×2, subjek2 ×1). Kriteria lolos terpenuhi bila ≥2.');
    } else {
      // ---------- T3: perpanjangan sesi dari posisi plafon ----------
      _line('── T3 · perpanjangan sesi: sesi baru mulai dari posisi plafon sesi terbaik');
      SabrSessionResult? bestA;
      String bestSpec = 'ANDROID';
      for (final e in ceilings.entries) {
        if (e.value.itag == 0) continue;
        if (bestA == null ||
            e.value.coveragePct > bestA.coveragePct ||
            (e.value.coveragePct == bestA.coveragePct && e.value.mediaBytesAudio > bestA.mediaBytesAudio)) {
          bestA = e.value;
          bestSpec = e.key.split('/').first;
        }
      }
      if (bestA != null && bestA.frontierMs > 0 && bestA.maxSegment > 0) {
        final a = bestA;
        _line('T · sesi dasar terbaik: ${a.config} — frontier ${a.frontierMs}ms, segmen '
            's.d. ${a.maxSegment}, cakupan ${a.coveragePct}% (${a.mediaBytesAudio} byte).');
        final ext = await run('LANJUT', s1,
            spec: bestSpec,
            mode: 2,
            startAtMs: a.frontierMs,
            preBufferedEndMs: a.frontierMs,
            preSegEnd: a.maxSegment);
        final combined = a.mediaBytesAudio + ext.mediaBytesAudio;
        final combPct = a.contentLength <= 0 ? 0 : combined * 100 ~/ a.contentLength;
        _line('T · gabungan dua sesi (byte hanya informatif): $combined/${a.contentLength} byte ($combPct%) · segmen '
            'maks gabungan ${ext.maxSegment > a.maxSegment ? ext.maxSegment : a.maxSegment}'
            '${a.endSegmentNumber == null ? '' : '/${a.endSegmentNumber}'}');
        _line('VONIS PLAFON: satu sesi belum utuh. Perpanjangan '
            '${ext.maxSegment > a.maxSegment ? 'BERJALAN — segmen melampaui plafon sesi pertama' : 'TIDAK melampaui plafon sesi pertama'}'
            ' (gabungan $combPct%).');
      } else {
        _line('VONIS PLAFON: tidak ada sesi dasar yang mencapai posisi plafon terukur untuk T3.');
      }
      _line('Peta plafon akhir:');
      for (final e in ceilings.entries) {
        _line('  ${e.key}: ${e.value.mediaBytesAudio}/${e.value.contentLength} byte (${e.value.pct}%) · '
            'frontier ${e.value.frontierMs}ms · cakupan ${e.value.coveragePct}% · berhenti: ${e.value.stopReason}');
      }
    }
    _line('');
    _line('SELESAI MATRIKS PLAFON SABR.');
    if (mounted) setState(() => _running = false);
  }

  // ================= Ronde Probe PoToken (v3.5) =================
  // Fase A (di dalam _runPoTokenMatrix): cetak PoToken lokal lewat WebView
  // (laboratorium PoToken — port JS BgUtils). Fase B: resolusi ulang tiap
  // subjek dengan token terlampir (serviceIntegrityDimensions.poToken)
  // per jalur klien, lalu uji rentang jendela 1/2/tengah per varian URL:
  // RAW (seperti terbit), POT-KONTEN (&pot= token terikat videoId),
  // POT-VISITOR (&pot= token terikat visitorData sesi). Fase C: bukti
  // putar ExoPlayer ≥90 dtk pada jalur+varian pemenang pertama.
  // NILAI TOKEN TIDAK PERNAH MASUK LAPORAN — hanya panjang & kelas hasil.

  static const _pClients = ['ANDROID', 'IOS', 'WEB_REMIX', 'WEB'];

  /// Satu jalur Fase B. Mengembalikan (varian pemenang, probe) atau null.
  Future<({String variant, ClientStreamProbe probe})?> _pProbePath(
      String clientName, Track track, String contentToken, PoSessionResult session) async {
    final provider = ref.read(ytMusicProvider);
    ClientStreamProbe probe;
    try {
      probe = await provider
          .debugProbeWithPoToken(clientName, track,
              playerPoToken: contentToken, visitorData: session.visitorData)
          .timeout(const Duration(seconds: 90));
    } catch (e) {
      _line('P · $clientName: GALAT probe — ${describeError(e)}');
      return null;
    }
    if (probe.error != null) {
      _line('P · $clientName (v${probe.version}): ${probe.playability} — galat: ${probe.error} → TERBLOKIR');
      return null;
    }
    if (!probe.resolved) {
      _line('P · $clientName (v${probe.version}): playability=${probe.playability}'
          '${probe.reason.isEmpty ? '' : ' — ${probe.reason}'} · format total=${probe.totalFormats}'
          ' · URL audio langsung: TIDAK ADA → TERBLOKIR');
      return null;
    }
    final info = probe.info!;
    _line('P · $clientName (v${probe.version}): playability=OK · pilihan Normal itag=${probe.tierItags['normal'] ?? '-'}'
        ' (${info.mimeType}, ${info.bitrate ?? '-'} bps) · host=${probe.urlHost ?? '-'}'
        ' · params=[${probe.urlParams.join(',')}]'
        ' · pot di URL terbitan=${probe.urlParams.contains('pot') ? 'ADA' : 'tidak ada'}');
    int? total;
    for (final f in probe.audioFormats) {
      if (f.itag == probe.tierItags['normal']) total = f.contentLength;
    }
    // Token ditempel MENTAH sebagai parameter kueri — persis perilaku
    // yt-dlp/YouTube.js (token base64-websafe memang aman-kueri).
    final variants = <(String, String)>[
      ('RAW', info.url),
      ('POT-KONTEN', '${info.url}&pot=$contentToken'),
      if (session.visitorToken != null)
        ('POT-VISITOR', '${info.url}&pot=${session.visitorToken}'),
    ];
    for (final (vname, vurl) in variants) {
      final uri = Uri.parse(vurl);
      final w2 = await _kWindow(uri, probe.userAgent, 'P-$vname-W2', 1048576, 2097151);
      if (!w2) {
        _line('   P · $clientName/$vname: jendela 2 GAGAL → varian mati');
        continue;
      }
      bool? w3ok;
      if (total != null && total <= 3000000) {
        _line('   P · $clientName/$vname: jendela tengah dilewati (berkas hanya $total byte)');
      } else {
        w3ok = await _kWindow(uri, probe.userAgent, 'P-$vname-W3', 3000000, 4048575);
      }
      final w1 = await _kWindow(uri, probe.userAgent, 'P-$vname-W1', 0, 1048575);
      if (w1 && (w3ok ?? true)) {
        _line('   P · $clientName/$vname: LULUS — jendela 1, 2, dan tengah melayani penuh');
        return (variant: vname, probe: probe);
      }
      _line('   P · $clientName/$vname: jendela 2 lolos tetapi w1=$w1 w3=$w3ok → tidak konsisten, dicatat mati');
    }
    return null;
  }

  // ================= Matriks V — Probe Sesi Tamu WebView (Batch 0.6 F3) ==
  // Menguji bahan terakhir yang belum pernah diuji: KONTEKS BROWSER YANG
  // HIDUP. WebView memuat halaman watch sungguhan sebagai tamu (TANPA
  // login/akun); sesi tamu halaman dipanen (E1), URL terbitan halaman
  // diuji di luar WebView (E2), pemutar halaman dibiarkan memutar (E3),
  // dan sesi SABR dijalankan dengan transport fetch DARI DALAM halaman
  // (E4). URL/nilai sesi TIDAK PERNAH dicatat — host, itag, nama
  // parameter/cookie, panjang saja. Kriteria tuntas = byte/segmen UNIK
  // (pelajaran positif palsu ronde plafon).
  Future<({int status, int bytes, int ms})> _vDrain(Uri uri, String ua) async {
    final sw = Stopwatch()..start();
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
    var total = 0;
    var status = 0;
    try {
      final req = await client.getUrl(uri);
      req.headers.set('User-Agent', ua);
      final resp = await req.close();
      status = resp.statusCode;
      await for (final chunk in resp) {
        total += chunk.length;
        if (sw.elapsed > const Duration(seconds: 180)) break;
      }
    } catch (_) {
      // status/byte apa adanya dilaporkan pemanggil
    }
    client.close(force: true);
    return (status: status, bytes: total, ms: sw.elapsedMilliseconds);
  }

  Future<bool> _vTestUrl(Uri uri, WatchPageFormat fmt, String videoId, String tag) async {
    final ua = WatchLabState.desktopUa;
    final cl = fmt.contentLength;
    _line('V · $tag uji URL halaman itag ${fmt.itag} (contentLength $cl) dari dart:io:');
    final w2 = await _kWindow(uri, ua, '$tag w2', 1048576, 2097151);
    _line('V · $tag jendela2(1048576-2097151) ${w2 ? 'LOLOS 206' : 'GAGAL'}');
    if (cl > 4194304) {
      final mid = cl ~/ 2;
      final wm = await _kWindow(uri, ua, '$tag wt', mid, mid + 1048575);
      _line('V · $tag jendela-tengah($mid-${mid + 1048575}) ${wm ? 'LOLOS 206' : 'GAGAL'}');
    }
    final w1 = await _kWindow(uri, ua, '$tag w1', 0, 1048575);
    _line('V · $tag jendela1(0-1048575) ${w1 ? 'LOLOS 206' : 'GAGAL'}');
    final d = await _vDrain(uri, ua);
    final pct = cl > 0 ? (d.bytes * 100 / cl).toStringAsFixed(1) : '-';
    _line('V · $tag drain sekuensial: HTTP ${d.status} · ${d.bytes} byte ($pct% dari contentLength) · ${d.ms}ms');
    final ok = cl > 0 && d.bytes >= (cl * 0.95).round();
    _line('V · $tag ${ok ? 'LOLOS ≥95% byte tersaji di luar WebView' : 'belum tuntas (kriteria byte unik sekuensial)'}');
    return ok;
  }

  Future<void> _runWebViewMatrix() async {
    if (_running) return;
    setState(() {
      _running = true;
      _report.clear();
    });
    final p = ref.read(ytMusicProvider);
    final lab = _watchLabKey.currentState;
    _line('MATRIKS SESI TAMU WEBVIEW v3.10 (Batch 0.6 F3) — ${DateTime.now().toIso8601String()}');
    _line('Anonim penuh: halaman tamu saja, tanpa login/akun. URL & nilai sesi TIDAK dicatat.');
    _line('');
    if (lab == null) {
      _line('V · GALAT: lab watch tidak terpasang di pohon layar.');
      _finishReport();
      return;
    }
    final subjects = [_kSubjects[0].$2, _kSubjects[1].$2];
    var e2Wins = 0;
    var e3Win = false;
    var named = '';

    for (final track in subjects) {
      final vid = track.playableRef;
      _line('V · Trek: "${track.title}" [$vid]');
      // ---------------- E1: panen dari halaman hidup ----------------
      debugPrint('DIAG-STAGE V e1 $vid');
      await lab.loadWatch(vid);
      final sum = await lab.harvest(vid);
      _line('V · E1 host ${sum.host} · muat ${sum.loaded ? 'OK' : 'GAGAL'} (${sum.note}) · '
          'VISITOR_DATA len ${sum.visitorDataLen} · DATASYNC_ID ${sum.datasyncAda ? 'ada' : 'tidak'} · '
          'cookie halaman: [${sum.cookieNames.join(', ')}]');
      _line('V · E1 ytInitialPlayerResponse ${sum.iprAda ? 'ada' : 'TIDAK ADA'} · playability ${sum.playability} · '
          'serverAbrStreamingUrl ${sum.abrUrlAda ? 'TERBIT di halaman' : 'tidak'} · format audio ${sum.audioFormats.length}:');
      for (final f in sum.audioFormats) {
        _line('     fmt itag ${f.itag} ${f.mime} br ${f.bitrate} cl ${f.contentLength} '
            '${f.hasUrl ? 'URL-LANGSUNG' : (f.hasCipher ? 'cipher-saja' : 'tanpa-url')}');
      }
      if (sum.playability == 'LOGIN_REQUIRED') {
        _line('V · E1 DINDING LOGIN pada subjek ini — varian halaman dihentikan (mandat: tanpa akun).');
        _line('');
        continue;
      }
      if (sum.audioFormats.isEmpty) {
        _line('V · E1 tidak ada format audio dari halaman — E2/E3 tidak dapat jalan untuk subjek ini.');
        _line('');
        continue;
      }
      // Format target: Opus bitrate tertinggi, fallback audio tertinggi.
      final sorted = [...sum.audioFormats]..sort((a, b) => b.bitrate.compareTo(a.bitrate));
      final fmt = sorted.firstWhere((f) => f.mime.contains('webm'),
          orElse: () => sorted.first);

      // ---------------- E2: URL halaman di luar WebView ----------------
      debugPrint('DIAG-STAGE V e2 $vid');
      var e2ok = false;
      final metaIpr = await lab.pickUrl(fmt.itag, 'ipr');
      _line('V · E2 pick-ipr itag ${fmt.itag}: ok=${metaIpr.ok} host=${metaIpr.host} len=${metaIpr.len} params=[${metaIpr.paramNames.join(',')}]');
      if (metaIpr.ok) {
        final u = await lab.takePickedUrl();
        if (u != null) {
          e2ok = await _vTestUrl(Uri.parse(u), fmt, vid, 'E2-ipr');
        } else {
          _line('V · E2-ipr URL tidak tiba lewat kanal.');
        }
      }

      // ---------------- E3: putar di dalam halaman ----------------
      debugPrint('DIAG-STAGE V e3 $vid');
      final playRes = await lab.play();
      _line('V · E3 play() -> $playRes');
      var maxCt = 0.0;
      var maxBuf = 0.0;
      var lastAdvance = Stopwatch()..start();
      final sw3 = Stopwatch()..start();
      var perfTried = e2ok;
      var e3ok = false;
      while (sw3.elapsed < const Duration(seconds: 215)) {
        await Future<void>.delayed(const Duration(seconds: 5));
        final st = await lab.playState();
        if (st.currentTime > maxCt + 0.5) {
          maxCt = st.currentTime;
          lastAdvance.reset();
        }
        if (st.bufferedEnd > maxBuf) maxBuf = st.bufferedEnd;
        _line('V · E3 t=${sw3.elapsed.inSeconds}s ct=${st.currentTime.toStringAsFixed(1)} '
            'bufEnd=${st.bufferedEnd.toStringAsFixed(1)} paused=${st.paused} rs=${st.readyState} err=${st.mediaError}');
        if (!perfTried && st.currentTime > 15) {
          perfTried = true;
          final metaPerf = await lab.pickUrl(fmt.itag, 'perf');
          _line('V · E2 pick-perf itag ${fmt.itag}: ok=${metaPerf.ok} host=${metaPerf.host} len=${metaPerf.len} params=[${metaPerf.paramNames.join(',')}]');
          if (metaPerf.ok) {
            final u2 = await lab.takePickedUrl();
            if (u2 != null) {
              e2ok = await _vTestUrl(Uri.parse(u2), fmt, vid, 'E2-perf');
            }
          }
        }
        if (st.currentTime >= 150) {
          e3ok = true;
          break;
        }
        if (st.mediaError != '-') break;
        if (lastAdvance.elapsed > const Duration(seconds: 45) && sw3.elapsed > const Duration(seconds: 60)) {
          _line('V · E3 currentTime mandek 45 dtk — hentikan pantauan subjek ini.');
          break;
        }
      }
      _line('V · E3 vonis [$vid]: ctMaks=${maxCt.toStringAsFixed(1)}s bufMaks=${maxBuf.toStringAsFixed(1)}s '
          '${e3ok ? 'LOLOS — pemutar halaman menembus frontier & mencapai ≥150 dtk' : 'tidak mencapai 150 dtk'}');
      if (e2ok) {
        e2Wins++;
        if (named.isEmpty) named = 'E2 (URL terbitan konteks halaman tersaji utuh di luar WebView)';
      }
      if (e3ok) {
        e3Win = true;
        if (named.isEmpty) named = 'E3 (pemutar halaman hidup menyeberang di dalam konteksnya)';
      }
      _line('');
    }

    // ---------------- E4: SABR berkonteks halaman ----------------
    final t1 = subjects[0];
    _line('V · E4 SABR berkonteks halaman — subjek "${t1.title}" [${t1.playableRef}]');
    debugPrint('DIAG-STAGE V e4 ${t1.playableRef}');
    await lab.loadWatch(t1.playableRef);
    final sum4 = await lab.harvest(t1.playableRef);
    _line('V · E4 konteks halaman dimuat ulang: VD len ${sum4.visitorDataLen} · playability ${sum4.playability}');
    void logSabr(String tag, SabrSessionResult r) {
      _line('V · $tag ${r.config} · itag ${r.itag} · putaran ${r.rounds} · media '
          '${r.mediaBytesAudio}/${r.contentLength} (${r.pct}%) · segmen s.d. ${r.maxSegment}'
          '${r.endSegmentNumber == null ? '' : '/${r.endSegmentNumber}'} · frontier ${r.frontierMs}ms '
          '· proteksi ${r.protection ?? '-'} · berhenti: ${r.stopReason}');
      _line('V · $tag rincian: ${r.detail}');
    }

    Future<Uint8List?> pageTransport(String url, Uint8List body) =>
        lab.sabrFetch(url, body);
    var e4ok = false;
    try {
      final r1 = await p
          .debugSabrSession(t1,
              specKey: 'ANDROID', faithful: false, maxRounds: 30, transport: pageTransport)
          .timeout(const Duration(seconds: 1500));
      logSabr('E4-transport', r1);
      e4ok = r1.frontierMs > 70000 ||
          r1.stopReason.startsWith('tuntas');
      if (!e4ok) {
        // Varian + PoToken: token visitor sesi lab BotGuard (halaman
        // utama) di streamerContext — nilai tidak dicatat, hanya panjang.
        Uint8List? po;
        final poLab = _poLabKey.currentState;
        if (poLab != null) {
          try {
            final sess = await poLab.ensureSession().timeout(const Duration(seconds: 120));
            final vt = sess.visitorToken;
            if (sess.ok && vt != null && vt.isNotEmpty) {
              try {
                po = base64Url.decode(base64Url.normalize(vt));
              } catch (_) {
                po = Uint8List.fromList(utf8.encode(vt));
              }
              _line('V · E4 token sesi lab: VD ${sess.visitorDataLen} char · token ${sess.visitorTokenLen} char -> ${po.length} byte');
            } else {
              _line('V · E4 token sesi lab GAGAL — varian token dilewati.');
            }
          } catch (e) {
            _line('V · E4 token sesi lab GALAT ${e.runtimeType} — varian token dilewati.');
          }
        }
        if (po != null) {
          debugPrint('DIAG-STAGE V e4-token ${t1.playableRef}');
          final r2 = await p
              .debugSabrSession(t1,
                  specKey: 'ANDROID',
                  faithful: false,
                  maxRounds: 30,
                  transport: pageTransport,
                  poToken: po)
              .timeout(const Duration(seconds: 1500));
          logSabr('E4-transport+pot', r2);
          e4ok = r2.frontierMs > 70000 || r2.stopReason.startsWith('tuntas');
        }
      }
    } catch (e) {
      _line('V · E4 GALAT: ${describeError(e)}');
    }
    if (e4ok && named.isEmpty) {
      named = 'E4 (SABR berkonteks halaman — proteksi/konteks halaman menggerakkan segmen melewati frontier)';
    }

    _line('');
    _line('V · RINGKASAN: E2 lolos $e2Wins/2 subjek · E3 ${e3Win ? 'LOLOS' : 'gugur'} · E4 ${e4ok ? 'LOLOS' : 'gugur'}');
    _line('V · VONIS: ${named.isEmpty ? 'SEMUA JALUR KONTEKS HALAMAN GUGUR pada ronde ini — lihat per eksperimen.' : 'MEKANISME TERNAMAI: $named'}');
    _finishReport();
  }

  // ================= Matriks U — Tahap 2 Mesin Penyeberangan 2.0 =================
  // Replikasi resep innertubex v0.11.2 (studi-sumber/RESEP-DAN-SELISIH.md)
  // melawan gerbang yang membunuh ronde-rode sebelumnya:
  //   E6 forensik anggaran — dekode field 2 (maxRetries) STREAM_PROTECTION_
  //      STATUS pada sesi ANDROID BASE pola plafon: bagaimana sesi itu mati?
  //   E1 WEB_SABR setia-sumber — bootstrap SATU halaman watch (VD+sts+
  //      jsUrl+EVENT_ID+ytAtN terikat), minter atestasi-halaman, token
  //      VIDEO_ID di field 19.2, bentuk sesi pemutar-penuh, anggaran
  //      proteksi dibaca per respons.
  //   E2 WEB_REMIX_SABR tanpa token — isolasi peran token di keluarga ini.
  //   E3 DIRECT ala aplikasi Metrolist — resolusi WEB_REMIX, URL + &pot=
  //      VIDEO_ID, cpn, n via solver EJS, drain rentang 1 MiB dengan
  //      percobaan-ulang 403 transien.
  // Kriteria lagu utuh = cakupan unik terverifikasi (segmen + byte unik),
  // BUKAN jumlah byte mentah (pelajaran positif palsu ronde plafon).

  static String _uCpn() {
    const alpha = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_';
    final rnd = Random();
    return String.fromCharCodes(
        [for (var i = 0; i < 16; i++) alpha.codeUnitAt(rnd.nextInt(alpha.length))]);
  }

  static String _uAppendCpn(String url) {
    final u = Uri.parse(url);
    if (u.queryParameters.containsKey('cpn')) return url;
    return u.replace(queryParameters: {...u.queryParameters, 'cpn': _uCpn()}).toString();
  }

  /// Pilihan format DIRECT tingkat Normal: bitrate tertinggi <= plafon
  /// Normal, selain itu terendah di atasnya (konvensi harness).
  DirectFormat? _e3Pick(List<DirectFormat> formats) {
    final usable = formats.where((f) => f.directUrl != null || f.ciphered).toList()
      ..sort((a, b) => (a.bitrate ?? 0).compareTo(b.bitrate ?? 0));
    if (usable.isEmpty) return null;
    DirectFormat? best;
    for (final f in usable) {
      if ((f.bitrate ?? 0) <= StreamQuality.normal.maxBitrate) best = f;
    }
    return best ?? usable.first;
  }

  /// Drain sekuensial rentang terbatas (E3): potongan tepat 1.048.576
  /// byte (DEFAULT_BOUNDED_RANGE_CHUNK_BYTES sumber); 403 transien
  /// dicoba ulang maks 3x per potongan dengan jeda membesar (pelajaran
  /// catatan MWEB katalog upstream). Byte terhitung hanya dari potongan
  /// yang tuntas penuh (rentang saling lepas → unik).
  Future<({int bytes, int chunks, int deathChunk, String note})> _uDrainBounded(
      Uri uri, String ua, int total) async {
    var bytes = 0;
    var chunks = 0;
    var start = 0;
    while (start < total) {
      var end = start + 1048576 - 1;
      if (end > total - 1) end = total - 1;
      final want = end - start + 1;
      var attempt = 0;
      while (true) {
        attempt++;
        try {
          final f = await _kFetch(uri, ua, start, end).timeout(const Duration(seconds: 60));
          final cr = parseContentRange(f.contentRange);
          final genuineEof = cr != null && cr.total == start + f.drained;
          if (f.status == 206 && (f.drained >= want || genuineEof)) {
            bytes += f.drained;
            chunks++;
            start = end + 1;
            break;
          }
          if (f.status == 403 && attempt <= 3) {
            _line('   U-E3 · potongan ${chunks + 1} [$start-$end]: 403 (coba $attempt) — '
                'ulang sesudah ${attempt * attempt} dtk');
            await Future<void>.delayed(Duration(seconds: attempt * attempt));
            continue;
          }
          return (
            bytes: bytes,
            chunks: chunks,
            deathChunk: chunks + 1,
            note: 'mati di potongan ${chunks + 1} [$start-$end]: HTTP ${f.status}, '
                'drained ${f.drained}/$want byte (coba ke-$attempt)'
          );
        } catch (e) {
          if (attempt <= 3) {
            await Future<void>.delayed(Duration(seconds: attempt * attempt));
            continue;
          }
          return (
            bytes: bytes,
            chunks: chunks,
            deathChunk: chunks + 1,
            note: 'mati di potongan ${chunks + 1} [$start-$end]: galat ${describeError(e)}'
          );
        }
      }
    }
    return (bytes: bytes, chunks: chunks, deathChunk: 0, note: 'tuntas');
  }

  void _logWebSabr(String tag, WebSabrResult r) {
    _line('$tag · sesi: ${r.requests} permintaan · segmen teremisikan ${r.segments} '
        '(seq ${r.firstSegment ?? '-'}..${r.lastSegment ?? '-'}/${r.endSegmentNumber ?? '-'}) · '
        'byte unik media ${r.mediaBytes}/${r.contentLength} (${r.byteCoveragePct}%) · '
        'byte teremisikan total ${r.emittedBytes} · frontier ${r.frontierMs}ms/${r.durationMs}ms · '
        'dinding ${r.elapsedMs}ms');
    _line('$tag · sensus part: ${r.partTypes.entries.map((e) => '${e.key}×${e.value}').join(', ')}');
    final rs = r.responses;
    final show = rs.length <= 44 ? rs : [...rs.take(20), ...rs.skip(rs.length - 20)];
    _line(rs.length > 44
        ? '$tag · seri respons (${rs.length} total — 20 pertama + 20 terakhir):'
        : '$tag · seri respons:');
    for (final d in show) {
      _line('   r${d.rn} pt${d.requestPlayerTimeMs} +${d.newSegments}seg → ${d.cumSegments}seg/'
          '${d.cumMediaBytes}B · frontier ${d.frontierMs} · prot ${d.protectionStatus ?? '-'}/'
          'mr${d.protectionMaxRetries ?? '-'} · bo ${d.backoffMs} · resp ${d.responseBytes}B');
    }
    _line('$tag · validasi sumber: ${r.validation}');
    _line('$tag · berhenti: ${r.failureKind.isEmpty ? r.stopReason : '${r.failureKind} — ${r.stopReason}'}');
    _line('$tag · VONIS SESI: ${r.complete ? 'LAGU UTUH (cakupan unik + validasi sumber lulus)' : 'TIDAK UTUH'}');
  }

  Future<void> _runTahap2Matrix() async {
    if (_running) return;
    setState(() {
      _running = true;
      _report.clear();
    });
    final p = ref.read(ytMusicProvider);
    final lab = _poLabKey.currentState;
    final s1 = _kSubjects[0].$2;
    final s2 = _kSubjects[1].$2;
    _line('MATRIKS U — TAHAP 2 MESIN PENYEBERANGAN 2.0 v3.13 (resep innertubex v0.11.2) — ${DateTime.now().toIso8601String()}');
    _line('Anonim, diagnostik saja. Nilai token/visitorData/URL bertanda tangan TIDAK dicatat — hanya angka, host, nama parameter, panjang.');
    _line('');
    if (lab == null) {
      _line('U · Lab PoToken tidak terpasang — matriks berhenti.');
      _finishReport();
      return;
    }

    // ---------- E6: forensik anggaran pada sesi ANDROID BASE ----------
    _line('── E6 · forensik anggaran: SATU sesi ANDROID/BASE persis pola plafon (resep PoC, maks 14 putaran)');
    try {
      final r = await p
          .debugSabrSession(s1, specKey: 'ANDROID', faithful: false, maxRounds: 14)
          .timeout(const Duration(seconds: 600));
      _line('E6 · ${r.config} · itag ${r.itag} · putaran ${r.rounds} · media ${r.mediaBytesAudio}/${r.contentLength} byte (${r.pct}%) · '
          'segmen ${r.segments} s.d. ${r.maxSegment}/${r.endSegmentNumber ?? '-'} · frontier ${r.frontierMs}ms/${r.approxDurMs}ms · '
          'cakupan ${r.coveragePct}% · proteksi akhir ${r.protection ?? '-'} · berhenti: ${r.stopReason} · dinding ${r.elapsedMs}ms');
      _line('E6 · seri anggaran proteksi (st/mr per respons): ${r.protectionSeries.isEmpty ? '(tidak ada part 58 terbaca)' : r.protectionSeries}');
      _line('E6 · sensus part: ${r.partTypes.entries.map((e) => '${e.key}×${e.value}').join(', ')}');
      _line('E6 · kebijakan: ${r.policySummary}');
      _line('E6 · rincian: ${r.detail}');
    } catch (e) {
      _line('E6 · GALAT: ${describeError(e)}');
    }
    _line('');

    // ---------- keadaan solver EJS lintas subjek ----------
    String? ejsKey;
    String? ejsJs;
    Future<bool> ejsReady(WatchPageData page) async {
      if (page.jsUrl == null) {
        _line('U · jsUrl halaman tidak ada — solver EJS tidak bisa disiapkan.');
        return false;
      }
      if (ejsKey == page.jsUrl && ejsJs != null) return true;
      final js = await p
          .debugFetchText('https://www.youtube.com${page.jsUrl}')
          .timeout(const Duration(seconds: 60));
      if (js == null || js.length < 10000) {
        _line('U · base.js GAGAL diambil (panjang ${js?.length ?? 0}).');
        return false;
      }
      ejsKey = page.jsUrl;
      ejsJs = js;
      _line('U · base.js terambil: ${js.length} char (player ${page.jsUrl})');
      return true;
    }

    Future<({String url, String note})> solveN(String url, WatchPageData page) async {
      final rawN = Uri.parse(url).queryParameters['n'];
      if (rawN == null) return (url: url, note: 'tanpa parameter n');
      if (!await ejsReady(page)) return (url: url, note: 'n mentah — base.js tidak siap');
      // Semua solve lewat Worker BARU per panggilan (ejsSolveWorker):
      // panggilan jsc berulang di benang halaman terbukti menggantung
      // (lari 3-4: solve pertama lulus, berikutnya timeout 180 dtk dan
      // mengunci benang JS lab); worker mengisolasi tiap solve.
      final out = await lab
          .ejsSolveWorker(playerJs: ejsJs!, nChallenges: [rawN])
          .timeout(const Duration(seconds: 200));
      if (!out.ok) return (url: url, note: 'n mentah — solver: ${out.error}');
      if (out.nError != null) return (url: url, note: 'n mentah — ekstrak n gagal: ${out.nError}');
      final solved = out.n[rawN];
      if (solved == null || solved == rawN) return (url: url, note: 'n tidak berubah oleh solver');
      final u = Uri.parse(url);
      return (
        url: u.replace(queryParameters: {...u.queryParameters, 'n': solved}).toString(),
        note: 'n ditransformasi EJS (${rawN.length}→${solved.length} char)'
      );
    }

    Future<({String sig, String? n})?> ejsSolveSigN(WatchPageData page,
        {required String sig, String? n}) async {
      if (!await ejsReady(page)) return null;
      // Worker juga di sini (lihat solveN): eksekusi sig di DOM
      // halaman nyata menggantung; di worker tanpa DOM ia setara node.
      final out = await lab
          .ejsSolveWorker(
              playerJs: ejsJs!,
              nChallenges: [if (n != null) n],
              sigChallenges: [sig])
          .timeout(const Duration(seconds: 200));
      if (!out.ok) {
        _line('U · solver EJS gagal: ${out.error}');
        return null;
      }
      final s = out.sig[sig];
      if (s == null) {
        _line('U · ekstrak sig gagal: ${out.sigError ?? '(tanpa hasil)'}');
        return null;
      }
      return (sig: s, n: n == null ? null : out.n[n]);
    }

    var e1Pass = 0, e2Pass = 0, e3Pass = 0;
    int? e1Frontier, e2Frontier;
    var e3DiedAtChunk2 = false;
    final e3Jobs = <Future<void> Function()>[];

    for (final track in [s1, s2]) {
      _line('════ SUBJEK ${track.id} ════');
      WatchPageData page;
      try {
        page = await p.debugFetchWatchPage(track.id).timeout(const Duration(seconds: 60));
      } catch (e) {
        _line('U · halaman watch GALAT: ${describeError(e)} — subjek dilewati.');
        continue;
      }
      _line('U · halaman watch (${page.source}): HTML ${page.htmlLen} char · VD ${page.visitorDataLen} char · '
          'sts ${page.signatureTimestamp ?? '-'} · jsUrl ${page.jsUrl ?? '-'} · EVENT_ID ${page.hasEventId ? 'ada' : 'TIDAK ADA'} · '
          'ytAtN ${page.hasYtAtN ? 'ada' : 'TIDAK ADA'}${page.error != null ? ' · galat ${page.error}' : ''}');
      if (page.html == null || page.visitorData == null) {
        _line('U · bahan halaman tidak cukup — subjek dilewati untuk E1/E2/E3.');
        continue;
      }

      // Sesi atestasi-halaman (minter dibangun dari tantangan halaman ini).
      PoSessionResult sess;
      try {
        sess = await lab.ensurePageSession(page.html!).timeout(const Duration(seconds: 330));
      } catch (e) {
        _line('U · sesi halaman GALAT: ${describeError(e)} — subjek dilewati.');
        continue;
      }
      _line('U · sesi atestasi-halaman: ok=${sess.ok} · rute ${sess.route} · interpreter ${sess.interpreter} · '
          'bangun ${sess.mintMs}ms · TTL ${sess.ttlSecs ?? '-'}dtk · VD ${sess.visitorDataLen} char · '
          'tokenVisitor ${sess.visitorTokenLen} char${sess.ok ? '' : ' · galat: ${sess.errors.join(' | ')}'}');
      String? contentToken;
      if (sess.ok) {
        try {
          final mint = await lab.mintContentToken(track.id).timeout(const Duration(seconds: 120));
          _line('U · token konten (terikat VIDEO_ID): ok=${mint.ok} · ${mint.tokenLen} char · ${mint.mintMs}ms'
              '${mint.ok ? '' : ' · kelas: ${mint.errorClass}'}');
          if (mint.ok) contentToken = mint.token;
        } catch (e) {
          _line('U · cetak token konten GALAT: ${describeError(e)}');
        }
      }

      // ---------- E1: WEB_SABR setia-sumber ----------
      _line('── E1 · WEB_SABR (token VIDEO_ID di 19.2; bentuk sesi pemutar-penuh; anggaran dibaca)');
      try {
        var boot = await p
            .debugResolveSabrBootstrap('WEB_SABR', track,
                visitorData: page.visitorData, signatureTimestamp: page.signatureTimestamp)
            .timeout(const Duration(seconds: 90));
        _line('E1 · resolusi direktur-1 (tanpa token): playability=${boot.playability}'
            '${boot.error != null ? ' · ${boot.error}' : ' · ABR terbit · audio itag ${boot.audio!.itag} (${boot.audio!.mime}) · buangan itag ${boot.discard!.itag}@${boot.discard!.height}p'}');
        if (!boot.ready && contentToken != null) {
          boot = await p
              .debugResolveSabrBootstrap('WEB_SABR', track,
                  visitorData: page.visitorData,
                  signatureTimestamp: page.signatureTimestamp,
                  playerPoToken: contentToken)
              .timeout(const Duration(seconds: 90));
          _line('E1 · resolusi direktur-2 (+ token player VIDEO_ID): playability=${boot.playability}'
              '${boot.error != null ? ' · ${boot.error}' : ' · ABR terbit · audio itag ${boot.audio!.itag} · buangan itag ${boot.discard!.itag}@${boot.discard!.height}p'}');
        }
        if (!boot.ready) {
          _line('E1 · bootstrap gugur — sesi tidak lahir.');
          e1Frontier ??= 0;
        } else {
          var url = boot.abrUrl!;
          final solved = await solveN(url, page);
          url = _uAppendCpn(solved.url);
          _line('E1 · URL ABR: host ${Uri.parse(boot.abrUrl!).host} · n ${Uri.parse(boot.abrUrl!).queryParameters.containsKey('n') ? 'ada' : 'tidak ada'} (${solved.note}) · cpn ditempel · param=[${Uri.parse(url).queryParameters.keys.join(',')}]');
          final r = await p
              .debugWebSabrRun(boot,
                  videoId: track.id,
                  poTokenBytes: contentToken == null ? null : SabrTahap2Probe.b64UrlDecode(contentToken),
                  urlOverride: url,
                  origin: 'https://www.youtube.com')
              .timeout(const Duration(seconds: 960));
          _logWebSabr('E1', r);
          if (r.complete) {
            e1Pass++;
          } else {
            e1Frontier = r.frontierMs;
          }
        }
      } catch (e) {
        _line('E1 · GALAT: ${describeError(e)}');
      }

      // ---------- E2: WEB_REMIX_SABR tanpa token ----------
      _line('── E2 · WEB_REMIX_SABR (konstruksi sama, TANPA token — isolasi peran token)');
      try {
        final boot = await p
            .debugResolveSabrBootstrap('WEB_REMIX_SABR', track,
                visitorData: page.visitorData, signatureTimestamp: page.signatureTimestamp)
            .timeout(const Duration(seconds: 90));
        _line('E2 · resolusi tanpa token: playability=${boot.playability}'
            '${boot.error != null ? ' · ${boot.error}' : ' · ABR terbit · audio itag ${boot.audio!.itag} (${boot.audio!.mime}) · buangan itag ${boot.discard!.itag}@${boot.discard!.height}p'}');
        if (!boot.ready) {
          _line('E2 · bootstrap gugur — sesi tidak lahir.');
          e2Frontier ??= 0;
        } else {
          var url = boot.abrUrl!;
          final solved = await solveN(url, page);
          url = _uAppendCpn(solved.url);
          _line('E2 · URL ABR: host ${Uri.parse(boot.abrUrl!).host} · n ${Uri.parse(boot.abrUrl!).queryParameters.containsKey('n') ? 'ada' : 'tidak ada'} (${solved.note}) · cpn ditempel');
          final r = await p
              .debugWebSabrRun(boot,
                  videoId: track.id,
                  urlOverride: url,
                  origin: 'https://music.youtube.com')
              .timeout(const Duration(seconds: 960));
          _logWebSabr('E2', r);
          if (r.complete) {
            e2Pass++;
          } else {
            e2Frontier = r.frontierMs;
          }
        }
      } catch (e) {
        _line('E2 · GALAT: ${describeError(e)}');
      }
      // E3 ditunda ke fase 2 (sesudah E1/E2 semua subjek):
      // mengisolasi decipher E3 dari eksperimen SABR.
      e3Jobs.add(() async {
      // ---------- E3: DIRECT ala aplikasi ----------
      _line('── E3 · DIRECT ala aplikasi (WEB_REMIX + &pot= VIDEO_ID + cpn + drain terbatas 1 MiB)');
      try {
        var res = await p
            .debugResolveDirectRaw(track,
                visitorData: page.visitorData, signatureTimestamp: page.signatureTimestamp)
            .timeout(const Duration(seconds: 90));
        _line('E3 · resolusi direktur-1 (tanpa token): playability=${res.playability} · format audio ${res.formats.length}'
            '${res.error != null ? ' · ${res.error}' : ''}');
        var pick = _e3Pick(res.formats);
        if (pick == null && sess.visitorToken != null) {
          res = await p
              .debugResolveDirectRaw(track,
                  visitorData: page.visitorData,
                  signatureTimestamp: page.signatureTimestamp,
                  playerPoToken: sess.visitorToken)
              .timeout(const Duration(seconds: 90));
          _line('E3 · resolusi direktur-2 (+ token player VISITOR_DATA): playability=${res.playability} · format audio ${res.formats.length}'
              '${res.error != null ? ' · ${res.error}' : ''}');
          pick = _e3Pick(res.formats);
        }
        if (pick == null) {
          _line('E3 · tidak ada format audio terpakai — jalur mati di resolusi.');
          e3DiedAtChunk2 = true; // tidak pernah mencapai jendela mana pun
        } else {
          _line('E3 · pilihan: itag ${pick.itag} ${pick.mime} ${pick.bitrate ?? '-'} bps · contentLength ${pick.contentLength ?? '-'} · '
              'bentuk ${pick.directUrl != null ? 'URL langsung' : 'tercipher (s ${pick.cipherS!.length} char, sp "${pick.cipherSp}")'}');
          String? url = pick.directUrl;
          if (pick.ciphered) {
            final rawN = Uri.parse(pick.cipherBaseUrl!).queryParameters['n'];
            final solved = await ejsSolveSigN(page, sig: pick.cipherS!, n: rawN);
            if (solved == null) {
              _line('E3 · decipher EJS GAGAL — URL tidak tersusun.');
              url = null;
            } else {
              var u = pick.cipherBaseUrl!;
              if (solved.n != null) {
                final uu = Uri.parse(u);
                u = uu.replace(queryParameters: {...uu.queryParameters, 'n': solved.n!}).toString();
              }
              url = '$u&${pick.cipherSp}=${Uri.encodeComponent(solved.sig)}';
              _line('E3 · decipher OK: sig hasil ${solved.sig.length} char · n ${solved.n == null ? 'tidak diubah' : 'hasil ${solved.n!.length} char'}');
            }
          } else if (url != null) {
            final solved = await solveN(url, page);
            url = solved.url;
            _line('E3 · URL langsung terbit: n (${solved.note})');
          }
          if (url != null && contentToken == null) {
            _line('E3 · token konten tidak tersedia — drain dibatalkan (resep direktur menempelkan pot pada URL langsung).');
          } else if (url != null) {
            var u = url;
            if (!u.contains('&pot=') && !u.contains('?pot=')) {
              u = '$u&pot=${Uri.encodeComponent(contentToken!)}';
            }
            u = _uAppendCpn(u);
            final total = pick.contentLength ?? 0;
            _line('E3 · drain: host ${Uri.parse(u).host} · total $total byte · pot ditempel · cpn ditempel · param=[${Uri.parse(u).queryParameters.keys.join(',')}]');
            if (total <= 0) {
              _line('E3 · contentLength tidak diketahui — drain dilewati.');
            } else {
              final d = await _uDrainBounded(
                      Uri.parse(u),
                      'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:140.0) Gecko/20100101 Firefox/140.0',
                      total)
                  .timeout(const Duration(seconds: 900));
              final pct = d.bytes * 100 ~/ total;
              _line('E3 · drain selesai: ${d.bytes}/$total byte unik ($pct%) · potongan tuntas ${d.chunks} · ${d.note}');
              if (pct >= 95) {
                e3Pass++;
              } else if (d.deathChunk == 2) {
                e3DiedAtChunk2 = true;
              }
            }
          }
        }
      } catch (e) {
        _line('E3 · GALAT: ${describeError(e)}');
      }
      });

      _line('');
    }

    // ---------- Fase 2: E3 (DIRECT) untuk semua subjek ----------
    for (final job in e3Jobs) {
      await job();
      _line('');
    }

    _line('════ VONIS MATRIKS U ════');
    _line('U · E1 WEB_SABR setia-sumber: lagu utuh $e1Pass/2 subjek${e1Frontier != null ? ' · frontier lari terakhir ${e1Frontier}ms' : ''}');
    _line('U · E2 WEB_REMIX_SABR tanpa token: lagu utuh $e2Pass/2 subjek${e2Frontier != null ? ' · frontier lari terakhir ${e2Frontier}ms' : ''}');
    _line('U · E3 DIRECT+pot: drain ≥95% pada $e3Pass/2 subjek · mati di jendela 2: ${e3DiedAtChunk2 ? 'YA (setidaknya satu subjek)' : 'tidak'}');
    final sameFrontier =
        e1Frontier != null && e2Frontier != null && (e1Frontier - e2Frontier).abs() <= 5000;
    _line('U · KRITERIA TUTUP (dokumen Tahap 1): E1 mati=${e1Pass == 0} · E2 mati=${e2Pass == 0} · '
        'frontier sama (±5 dtk)=$sameFrontier (${e1Frontier ?? '-'} vs ${e2Frontier ?? '-'}ms) · E3 mati di jendela 2=$e3DiedAtChunk2');
    _line('U · => ${e1Pass == 0 && e2Pass == 0 && sameFrontier && e3DiedAtChunk2 ? 'KRITERIA TUTUP TERPENUHI — program ditutup.' : 'Kriteria tutup TIDAK terpenuhi penuh — lihat vonis per eksperimen.'}');
    _finishReport();
  }

  // ================= Matriks L — Probe Login (Batch 0.7 F3) ==========
  // Pertanyaan terakhir Batch 0: apakah KONTEKS SESI TERAUTENTIKASI ala
  // Auralys §2b (cookie utuh + SAPISIDHASH + X-Goog-AuthUser, dipanen
  // Lab Login dari WebView milik pengguna sendiri) mengubah satu pun
  // dinding terukur?
  //   L1 resolusi WEB_REMIX/WEB ber-auth — format adaptif terbit?
  //   L2 URL terbitan ber-auth — jendela byte + drain; tembus 1 MiB?
  //   L3 SABR dengan resolusi ber-auth — proteksi bergerak dari 2?
  //      segmen melewati frontier 62–65 dtk? (BASE anonim: frontier
  //      61927ms, proteksi 2, media 1049454B)
  //   L4 kontrol: ANDROID adaptif + header auth — plafon berubah?
  // Nilai cookie/token TIDAK PERNAH dicatat — nama + panjang saja.
  // TANPA sesi terpanen, matriks MENOLAK jalan (anti lari palsu).
  Future<void> _runLoginMatrix() async {
    if (_running) return;
    final session = AuthSessionStore.instance.session;
    if (session == null || session.sapisid == null) {
      setState(() => _report.clear());
      _line('L · DITOLAK — sesi terautentikasi BELUM terpanen; matriks L TIDAK dijalankan.');
      _line('L · Langkah: tombol "Lab Login" di layar ini → masuk di WebView dengan akun sendiri → sesi terpanen otomatis (atau tombol Panen Sesi) → kembali ke sini.');
      return;
    }
    setState(() {
      _running = true;
      _report.clear();
    });
    final p = ref.read(ytMusicProvider);
    final auth = session.authorization();
    if (auth == null) {
      _line('L · DITOLAK — SAPISID tidak membentuk SAPISIDHASH.');
      setState(() => _running = false);
      return;
    }
    final meta = session.meta;
    Map<String, String> authHeaders() => {
          'Cookie': session.cookieHeader,
          'Authorization': session.authorization()!,
          if (session.sessionIndex != null)
            'X-Goog-AuthUser': session.sessionIndex!,
          if (session.visitorData != null)
            'X-Goog-Visitor-Id': session.visitorData!,
        };
    _line('MATRIKS L v3.12 (Probe Login — Pintu Terakhir, Batch 0.7 F3) — ${DateTime.now().toIso8601String()}');
    _line('Sesi terpanen (nama + panjang saja): ${meta.ringkas()}');
    _line('Nilai cookie/token TIDAK dicatat. L1 resolusi WEB ber-auth · L2 jendela+drain · L3 SABR ber-auth · L4 kontrol ANDROID ber-auth.');
    _line('');

    // ---------------- L1: resolusi keluarga WEB ber-auth ----------------
    _line('L · L1 resolusi ber-auth keluarga WEB — terbitkah format adaptif?');
    final winners = <({String client, ClientStreamProbe probe, Track track})>[];
    for (final (label, track) in _kSubjects) {
      for (final clientName in const ['WEB_REMIX', 'WEB']) {
        debugPrint('DIAG-STAGE L l1 $clientName ${track.playableRef}');
        try {
          final probe = await p.debugProbeWithAuth(clientName, track,
              cookieHeader: session.cookieHeader,
              authorization: auth,
              authUser: session.sessionIndex,
              visitorData: session.visitorData);
          _line('L · L1 $clientName "$label": playability ${probe.playability}'
              '${probe.reason.isEmpty ? '' : ' — ${probe.reason}'}'
              '${(probe.error ?? '').isEmpty ? '' : ' · galat ${probe.error}'}'
              ' · adaptif audio ber-URL ${probe.audioFormats.length}'
              ' · adaptif audio mentah ${probe.adaptiveAudioAny}'
              ' · params ${probe.urlParams.join(',')}');
          for (final f in probe.audioFormats) {
            _line('L · L1   itag ${f.itag} ${f.mime} ${f.bitrate ?? 0}bps len ${f.contentLength ?? 0}');
          }
          if (probe.resolved) {
            winners.add((client: clientName, probe: probe, track: track));
          }
        } catch (e) {
          _line('L · L1 $clientName "$label" GALAT ${describeError(e)}');
        }
      }
    }
    _line('L · L1 HASIL: ${winners.isEmpty ? 'TIDAK ADA format adaptif ber-URL dari resolusi ber-auth' : '${winners.length} resolusi menerbitkan URL adaptif'}');
    _line('');

    // ---------------- L2: jendela + drain URL terbitan ber-auth ---------
    if (winners.isNotEmpty) {
      _line('L · L2 jendela byte + drain pada URL terbitan ber-auth (pemenang pertama per klien):');
      final seenClients = <String>{};
      for (final w in winners) {
        if (!seenClients.add(w.client)) continue;
        final info = w.probe.info!;
        final uri = Uri.parse(info.url);
        var itag = 0;
        var cl = 0;
        for (final f in w.probe.audioFormats) {
          if (f.bitrate == info.bitrate) {
            itag = f.itag;
            cl = f.contentLength ?? 0;
            break;
          }
        }
        if (cl == 0 && w.probe.audioFormats.isNotEmpty) {
          final best = w.probe.audioFormats
              .reduce((a, b) => (a.bitrate ?? 0) >= (b.bitrate ?? 0) ? a : b);
          itag = best.itag;
          cl = best.contentLength ?? 0;
        }
        _line('L · L2 ${w.client} itag $itag len $cl host ${uri.host} (UA konteks klien penerbit)');
        debugPrint('DIAG-STAGE L l2 ${w.client} ${w.track.playableRef}');
        final w2 = await _kWindow(uri, w.probe.userAgent, 'L2-2', 1048576, 2097151);
        _line('L · L2 ${w.client} jendela2(1048576-2097151) ${w2 ? 'LOLOS 206 — TEMBUS 1 MiB' : 'GAGAL — dinding 1 MiB tetap'}');
        if (w2) {
          final w3 = await _kWindow(uri, w.probe.userAgent, 'L2-3', 3000000, 4048575);
          _line('L · L2 ${w.client} jendela3(3000000-4048575) ${w3 ? 'LOLOS 206' : 'GAGAL'}');
          final d = await _vDrain(uri, w.probe.userAgent);
          final pct = cl > 0 ? (d.bytes * 100 / cl).toStringAsFixed(1) : '-';
          _line('L · L2 ${w.client} drain sekuensial: HTTP ${d.status} · ${d.bytes} byte ($pct% dari contentLength $cl) · ${d.ms}ms');
        }
        final w1 = await _kWindow(uri, w.probe.userAgent, 'L2-1', 0, 1048575);
        _line('L · L2 ${w.client} jendela1(0-1048575) ${w1 ? 'LOLOS 206' : 'GAGAL'}');
      }
      _line('');
    }

    // ---------------- L3: SABR dengan resolusi ber-auth -----------------
    final t1 = _kSubjects.first.$2;
    _line('L · L3 SABR dengan resolusi ber-auth — subjek "${t1.title}" [${t1.playableRef}]');
    _line('L · L3 pembanding BASE anonim ronde plafon: frontier 61927ms · proteksi 2 · media 1049454B');
    debugPrint('DIAG-STAGE L l3 ${t1.playableRef}');
    try {
      final r = await p
          .debugSabrSession(t1,
              specKey: 'ANDROID',
              faithful: false,
              maxRounds: 40,
              resolutionHeaders: authHeaders())
          .timeout(const Duration(seconds: 1500));
      _line('L · L3 ${r.config} · itag ${r.itag} · putaran ${r.rounds} · media '
          '${r.mediaBytesAudio}/${r.contentLength} (${r.pct}%) · segmen s.d. ${r.maxSegment}'
          '${r.endSegmentNumber == null ? '' : '/${r.endSegmentNumber}'} · frontier ${r.frontierMs}ms '
          '· proteksi ${r.protection ?? '-'} · berhenti: ${r.stopReason}');
      _line('L · L3 rincian: ${r.detail}');
      _line('L · L3 VONIS: proteksi ${r.protection != 2 ? 'BERGERAK dari 2' : 'tetap 2 (pending)'} · '
          'frontier ${r.frontierMs > 70000 ? 'LEWAT zona plafon 62–65 dtk' : 'tetap di zona plafon'}');
    } catch (e) {
      _line('L · L3 GALAT: ${describeError(e)}');
    }
    _line('');

    // ---------------- L4: kontrol ANDROID ber-auth ----------------------
    _line('L · L4 kontrol: resolusi ANDROID adaptif + header auth (2 subjek pertama):');
    for (final (label, track) in _kSubjects.take(2)) {
      debugPrint('DIAG-STAGE L l4 ${track.playableRef}');
      try {
        final probe = await p.debugProbeWithAuth('ANDROID', track,
            cookieHeader: session.cookieHeader,
            authorization: auth,
            authUser: session.sessionIndex,
            visitorData: session.visitorData);
        _line('L · L4 ANDROID "$label": playability ${probe.playability}'
            '${(probe.error ?? '').isEmpty ? '' : ' · galat ${probe.error}'}'
            ' · adaptif audio ber-URL ${probe.audioFormats.length}');
        final info = probe.info;
        if (probe.resolved && info != null) {
          final uri = Uri.parse(info.url);
          final w2 = await _kWindow(uri, probe.userAgent, 'L4-2', 1048576, 2097151);
          _line('L · L4 ANDROID jendela2(1048576-2097151) ${w2 ? 'LOLOS 206 — plafon BERUBAH oleh konteks auth' : 'GAGAL — plafon 1 MiB tetap'}');
        }
      } catch (e) {
        _line('L · L4 "$label" GALAT ${describeError(e)}');
      }
    }
    _line('');
    _line('L · Sesi tetap di memori proses sampai aplikasi ditutup atau cookie dibersihkan dari Lab Login.');
    _finishReport();
  }

  Future<void> _runPoTokenMatrix() async {
    if (_running) return;
    setState(() {
      _running = true;
      _report.clear();
    });
    final provider = ref.read(ytMusicProvider);
    _line('MATRIKS POTOKEN v3.5 (Ronde Probe PoToken) — ${DateTime.now().toIso8601String()}');
    _line('Perangkat: ${Platform.operatingSystemVersion}');
    _line('Nilai token TIDAK dicatat di laporan ini — hanya rute, panjang, durasi, kelas kegagalan.');
    _line('');
    final lab = _poLabKey.currentState;
    if (lab == null) {
      _line('P · GALAT: laboratorium WebView tidak terpasang di pohon layar.');
      _finishReport();
      return;
    }

    // ---- Fase A: cetak token ----
    debugPrint('DIAG-STAGE P A ensure mulai');
    final swA = Stopwatch()..start();
    final session = await lab.ensureSession();
    debugPrint('DIAG-STAGE P A ensure selesai ok=${session.ok} route=${session.route}');
    if (!session.ok) {
      _line('P-A · CETAK TOKEN: GAGAL — sesi BotGuard tidak terbangun di perangkat ini.');
      for (final e in session.errors) {
        _line('   galat rute: $e');
      }
      _line('');
      _line('P · VONIS RONDE: TAK-TERPUTUSKAN di lingkungan ini — token tidak tercetak,');
      _line('   jadi pertanyaan rentang tidak bisa dijawab di sini (BUKAN vonis GUGUR).');
      _finishReport();
      return;
    }
    _line('P-A · CETAK TOKEN: BERHASIL — rute=${session.route} · interpreter=${session.interpreter}'
        ' · bangun minter ${session.mintMs}ms · TTL integrity=${session.ttlSecs ?? '-'} dtk'
        ' · visitorData sesi=${session.visitorDataLen} char'
        ' · token visitor=${session.visitorTokenLen} char · total Fase A ${swA.elapsedMilliseconds}ms');
    _line('');

    // ---- Fase B: resolusi + pot per jalur ----
    final winners = <({Track track, String client, String variant})>[];
    for (final (label, track) in _kSubjects) {
      _line('════════ $label');
      _line('Trek: "${track.title}" — ${track.artistNames} [${track.id}]');
      final mint = await lab.mintContentToken(track.id);
      if (!mint.ok) {
        _line('P-B · cetak token konten GAGAL: ${mint.errorClass} — subjek dilewati.');
        _line('');
        continue;
      }
      _line('P-B · token konten [${track.id}]: ${mint.tokenLen} char · cetak ${mint.mintMs}ms');
      for (final clientName in _pClients) {
        debugPrint('DIAG-STAGE P B $clientName ${track.id} mulai');
        final win = await _pProbePath(clientName, track, mint.token!, session);
        debugPrint('DIAG-STAGE P B $clientName ${track.id} vonis=${win?.variant ?? 'MATI'}');
        if (win != null && winners.every((w) => w.track.id != track.id)) {
          winners.add((track: track, client: clientName, variant: win.variant));
        }
      }
      _line('');
    }
    _line('── RINGKASAN FASE B (pemenang pertama per subjek)');
    if (winners.isEmpty) {
      _line('P · tidak ada subjek dengan jalur LULUS.');
    } else {
      for (final w in winners) {
        _line('P · [${w.track.id}] ${w.client}/${w.variant}');
      }
    }
    _line('');

    // ---- Fase C: bukti putar pada pemenang pertama ----
    if (winners.isEmpty) {
      _line('P · FASE C tidak dijalankan (Fase B tanpa pemenang).');
      _line('');
      _line('P · VONIS RONDE: GUGUR — token sah tercetak & terlampir, tetapi 403');
      _line('   di luar 1 MiB pertama bertahan di semua jalur/varian yang terbit.');
    } else {
      final w = winners.first;
      _line('── FASE C · BUKTI PUTAR — subjek [${w.track.id}] · klien ${w.client} · varian ${w.variant}');
      final mint = await lab.mintContentToken(w.track.id);
      if (!mint.ok) {
        _line('PC · cetak ulang token konten GAGAL: ${mint.errorClass} — Fase C gugur.');
      } else {
        ClientStreamProbe? probe;
        try {
          probe = await provider
              .debugProbeWithPoToken(w.client, w.track,
                  playerPoToken: mint.token, visitorData: session.visitorData)
              .timeout(const Duration(seconds: 90));
        } catch (e) {
          _line('PC · resolusi segar GALAT: ${describeError(e)} — Fase C gugur.');
        }
        if (probe != null && probe.resolved) {
          var url = probe.info!.url;
          if (w.variant == 'POT-KONTEN') url = '$url&pot=${mint.token}';
          if (w.variant == 'POT-VISITOR' && session.visitorToken != null) {
            url = '$url&pot=${session.visitorToken}';
          }
          final p = AudioPlayer(useProxyForRequestHeaders: ClaiAudioHandler.useProxyForRequestHeaders);
          try {
            final src = AudioSource.uri(Uri.parse(url), headers: {
              'User-Agent': probe.userAgent,
              'Referer': 'https://music.youtube.com/',
            });
            final r = await _probeLongPlay(p, src, 'PC-1', targetMs: 90000);
            _reportLongPlay('PC-1 · putar adaptif ${w.client}/${w.variant} (target ≥90 dtk)', r);
            _line(r.ok
                ? 'P · VONIS RONDE: LULUS — adaptif+pot berputar berkelanjutan melewati batas 1 MiB.'
                : 'P · VONIS RONDE: Fase B LULUS tetapi Fase C GAGAL — lihat penanda galat PC-1 di atas.');
          } catch (e) {
            _line('PC-1 · GALAT bangun sumber: ${describeError(e)}');
            _line('P · VONIS RONDE: Fase B LULUS tetapi Fase C GAGAL (galat bangun sumber).');
          } finally {
            await p.dispose();
          }
          await _printNative('PC-1');
        } else if (probe != null) {
          _line('PC · resolusi segar tidak menghasilkan URL (playability=${probe.playability}'
              '${probe.error != null ? ' — ${probe.error}' : ''}) — Fase C gugur.');
          _line('P · VONIS RONDE: Fase B LULUS tetapi Fase C GAGAL (resolusi segar mati).');
        }
      }
    }
    _finishReport();
  }

  // ================= Batch 0 F3 — Probe Penentu Penyeberangan (v3.7) =================
  // Tahap 1: visitorData dari KONTEKS TONTON subjek itu sendiri (halaman
  // watch per videoId), TANPA PoToken — bahan diisolasi. Berbeda dari
  // matriks P (2026-11-05): di sana visitorData berasal dari sesi minter
  // halaman utama dan selalu berpasangan dengan token.
  // Varian per subjek (berurutan, berhenti di pemenang pertama):
  //   W1 WEB_REMIX+VD · W2 WEB_REMIX+VD+HDR (header X-Goog-Visitor-Id) ·
  //   W3 WEB+VD (host www.youtube.com + kunci web www + Referer watch) ·
  //   W4 ANDROID+VD (kontrol).
  // Per varian: resolusi → jendela 2 (penentu) → tengah → 1.
  // Tahap LOLOS bila satu varian menang rentang pada ≥3 subjek DAN bukti
  // putar (pra-seek ≥25 dtk + seek ke 55% + maju ≥15 dtk, tanpa galat)
  // lolos pada ≥3 subjek dengan varian yang sama.

  static const _wVariants = <({String tag, String client, bool header, bool webHost})>[
    (tag: 'W1', client: 'WEB_REMIX', header: false, webHost: false),
    (tag: 'W2', client: 'WEB_REMIX', header: true, webHost: false),
    (tag: 'W3', client: 'WEB', header: false, webHost: true),
    (tag: 'W4', client: 'ANDROID', header: false, webHost: false),
  ];

  /// Satu varian Tahap 1 untuk satu subjek; probe pemenang atau null.
  Future<ClientStreamProbe?> _wProbeVariant(
      ({String tag, String client, bool header, bool webHost}) v,
      Track track, String visitorData, int? sts) async {
    final provider = ref.read(ytMusicProvider);
    ClientStreamProbe probe;
    try {
      probe = await provider
          .debugProbeWithVisitor(v.client, track,
              visitorData: visitorData,
              visitorHeader: v.header,
              webHost: v.webHost,
              signatureTimestamp: sts)
          .timeout(const Duration(seconds: 90));
    } catch (e) {
      _line('W · ${v.tag} ${v.client}: GALAT probe — ${describeError(e)}');
      return null;
    }
    final label = '${v.tag} ${v.client}${v.header ? '+HDR' : ''}${v.webHost ? '@www' : ''}';
    if (probe.error != null) {
      _line('W · $label (v${probe.version}): ${probe.playability} — galat: ${probe.error} → MATI');
      return null;
    }
    if (!probe.resolved) {
      _line('W · $label (v${probe.version}): playability=${probe.playability}'
          '${probe.reason.isEmpty ? '' : ' — ${probe.reason}'} · format total=${probe.totalFormats}'
          ' · audio adaptif=${probe.adaptiveAudioAny} · URL langsung=${probe.audioFormats.length} → MATI');
      return null;
    }
    final info = probe.info!;
    _line('W · $label (v${probe.version}): playability=OK · pilihan Normal itag=${probe.tierItags['normal'] ?? '-'}'
        ' (${info.mimeType}, ${info.bitrate ?? '-'} bps) · host=${probe.urlHost ?? '-'}'
        ' · params=[${probe.urlParams.join(',')}]'
        ' · pot di URL=${probe.urlParams.contains('pot') ? 'ADA' : 'tidak ada'}');
    int? total;
    for (final f in probe.audioFormats) {
      if (f.itag == probe.tierItags['normal']) total = f.contentLength;
    }
    final uri = Uri.parse(info.url);
    final w2 = await _kWindow(uri, probe.userAgent, 'W$label-2', 1048576, 2097151);
    if (!w2) {
      _line('   W · $label: jendela 2 GAGAL → varian mati');
      return null;
    }
    bool? w3ok;
    if (total != null && total <= 3000000) {
      _line('   W · $label: jendela tengah dilewati (berkas hanya $total byte)');
    } else {
      w3ok = await _kWindow(uri, probe.userAgent, 'W$label-3', 3000000, 4048575);
    }
    final w1 = await _kWindow(uri, probe.userAgent, 'W$label-1', 0, 1048575);
    if (w1 && (w3ok ?? true)) {
      _line('   W · $label: LULUS RENTANG — jendela 1, 2, tengah melayani penuh');
      return probe;
    }
    _line('   W · $label: jendela 2 lolos tetapi w1=$w1 w3=$w3ok → tidak konsisten, dicatat mati');
    return null;
  }

  /// Bukti putar penyeberangan pada URI adaptif langsung: LOLOS hanya bila
  /// tanpa galat tertangkap, posisi ≥25 dtk sebelum seek, seek ke 55%
  /// durasi tercapai, dan posisi maju lagi ≥15 dtk sesudah seek. Pada
  /// bitrate adaptif, offset 55% trek ≥3 menit berarti byte jauh di atas
  /// 1 MiB benar-benar diambil dari tengah berkas.
  Future<({bool ok, String detail})> _probeCrossPlay(
      AudioPlayer p, Uri uri, Map<String, String> headers, String label) async {
    final captured = <String>[];
    final sub = p.playbackEventStream.listen((ev) {
      if (ev.errorCode != null) {
        final name = exoErrorCodeName(ev.errorCode!);
        final line = 'event: errorCode=${ev.errorCode}${name != null ? ' ($name)' : ''}'
            ' errorMessage=${ev.errorMessage ?? '-'} state=${ev.processingState.name}';
        if (!captured.contains(line)) captured.add(line);
      }
    }, onError: (Object e) {
      final line = 'aliran: ${describePlayerError(e)}';
      if (!captured.contains(line)) captured.add(line);
    });
    try {
      debugPrint('DIAG-STAGE $label setSrc start');
      await p
          .setAudioSource(AudioSource.uri(uri, headers: headers))
          .timeout(const Duration(seconds: 25));
      final duration = p.duration;
      debugPrint('DIAG-STAGE $label setSrc done duration=$duration');
      if (duration == null || duration.inSeconds < 60) {
        return (ok: false, detail: 'durasi tidak terbaca/<60 dtk (${duration ?? '-'})');
      }
      Object? playError;
      p.play().then((_) {
        debugPrint('DIAG-STAGE $label play future selesai');
      }).catchError((Object e) {
        playError = e;
        debugPrint('DIAG-STAGE $label play future galat: $e');
      });
      var okPhase1 = false;
      final sw = Stopwatch()..start();
      while (sw.elapsed < const Duration(seconds: 75)) {
        if (p.position.inMilliseconds >= 25000) {
          okPhase1 = true;
          break;
        }
        if (playError != null || captured.isNotEmpty) break;
        if (p.processingState == ProcessingState.completed) break;
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
      final prePos = p.position.inMilliseconds;
      final preBuf = p.bufferedPosition.inMilliseconds;
      debugPrint('DIAG-STAGE $label fase1 ok=$okPhase1 pos=$prePos buf=$preBuf');
      if (!okPhase1) {
        return (
          ok: false,
          detail: 'fase pra-seek gagal — pos=${prePos}ms buffer=${preBuf}ms'
              '${playError != null ? ' · galat: ${describePlayerError(playError!)}' : ''}'
              '${captured.isNotEmpty ? ' · tertangkap: ${captured.first}' : ''}'
        );
      }
      final seekTarget =
          Duration(milliseconds: (duration.inMilliseconds * 0.55).round());
      await p.seek(seekTarget);
      debugPrint('DIAG-STAGE $label seek ke ${seekTarget.inMilliseconds}ms');
      var postAdvance = 0;
      var lastPos = p.position.inMilliseconds;
      final sw2 = Stopwatch()..start();
      while (sw2.elapsed < const Duration(seconds: 60)) {
        final pos = p.position.inMilliseconds;
        if (pos > lastPos) {
          postAdvance += pos - lastPos;
          lastPos = pos;
        }
        if (postAdvance >= 15000) break;
        if (playError != null || captured.isNotEmpty) break;
        if (p.processingState == ProcessingState.completed) break;
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
      final postBuf = p.bufferedPosition.inMilliseconds;
      debugPrint('DIAG-STAGE $label fase2 maju=${postAdvance}ms buf=$postBuf');
      try {
        await p.stop().timeout(const Duration(seconds: 5));
      } catch (_) {}
      final ok = captured.isEmpty && playError == null && postAdvance >= 15000;
      return (
        ok: ok,
        detail: 'pra-seek pos=${prePos}ms buffer=${preBuf}ms · seek→${seekTarget.inMilliseconds}ms'
            ' · maju sesudah seek=${postAdvance}ms · buffer akhir=${postBuf}ms'
            '${captured.isNotEmpty ? ' · tertangkap: ${captured.first}' : ''}'
            '${playError != null ? ' · galat putar: ${describePlayerError(playError!)}' : ''}'
      );
    } catch (e) {
      return (ok: false, detail: 'galat: ${describePlayerError(e)}');
    } finally {
      await sub.cancel();
    }
  }

  Future<void> _runCrossingMatrix() async {
    if (_running) return;
    setState(() {
      _running = true;
      _report.clear();
    });
    final provider = ref.read(ytMusicProvider);
    _line('MATRIKS PENYEBERANGAN F3 v3.7 (Batch 0 — Tahap 1: visitorData konteks tonton, TANPA PoToken) — ${DateTime.now().toIso8601String()}');
    _line('Perangkat: ${Platform.operatingSystemVersion}');
    _line('Nilai visitorData TIDAK dicatat di laporan ini — hanya sumber & panjangnya.');
    _line('');
    final wins = <String, List<({Track track, ClientStreamProbe probe})>>{};
    for (final (label, track) in _kSubjects) {
      _line('════════ $label');
      _line('Trek: "${track.title}" — ${track.artistNames} [${track.id}]');
      debugPrint('DIAG-STAGE W konteks ${track.id} mulai');
      ({String? visitorData, String source, int? signatureTimestamp}) wc;
      try {
        wc = await provider
            .debugFetchWatchContext(track.id)
            .timeout(const Duration(seconds: 60));
      } catch (e) {
        _line('W · konteks tonton [${track.id}]: GALAT — ${describeError(e)}; subjek dilewati.');
        _line('');
        continue;
      }
      debugPrint('DIAG-STAGE W konteks ${track.id} sumber=${wc.source} len=${wc.visitorData?.length ?? 0}');
      if (wc.visitorData == null) {
        _line('W · konteks tonton [${track.id}]: visitorData TIDAK didapat (sumber: ${wc.source}) — subjek dilewati.');
        _line('');
        continue;
      }
      _line('W · konteks tonton [${track.id}]: sumber=${wc.source}'
          ' · visitorData=${wc.visitorData!.length} char'
          ' · sts watch=${wc.signatureTimestamp != null ? 'ada' : 'tidak ada'}');
      for (final v in _wVariants) {
        debugPrint('DIAG-STAGE W ${v.tag} ${v.client} ${track.id} mulai');
        final win = await _wProbeVariant(v, track, wc.visitorData!, wc.signatureTimestamp);
        debugPrint('DIAG-STAGE W ${v.tag} ${v.client} ${track.id} vonis=${win != null ? 'LULUS' : 'MATI'}');
        if (win != null) {
          wins.putIfAbsent(v.tag, () => []).add((track: track, probe: win));
          break; // pemenang pertama subjek ini — varian berikut tidak perlu
        }
      }
      _line('');
    }
    _line('── RINGKASAN RENTANG TAHAP 1 (kemenangan per varian)');
    String? winTag;
    var winCount = 0;
    for (final v in _wVariants) {
      final n = wins[v.tag]?.length ?? 0;
      _line('W · ${v.tag} ${v.client}: menang di $n subjek'
          '${n > 0 ? ' [${wins[v.tag]!.map((w) => w.track.id).join(', ')}]' : ''}');
      if (n > winCount) {
        winCount = n;
        winTag = v.tag;
      }
    }
    _line('');
    if (winTag == null || winCount < 3) {
      _line('W · VONIS TAHAP 1: GAGUR — tidak ada varian yang menang rentang pada ≥3 subjek'
          ' (terbaik: ${winTag ?? '-'} $winCount subjek). Bukti putar tidak dijalankan.');
      _finishReport();
      return;
    }
    // ---- Bukti putar pada varian pemenang (≥3 subjek) ----
    final wv = _wVariants.firstWhere((v) => v.tag == winTag);
    _line('── BUKTI PUTAR TAHAP 1 · varian $winTag ${wv.client} (target: lolos ≥3 subjek)');
    var playPass = 0;
    for (final w in wins[winTag]!.take(4)) {
      if (playPass >= 3) break;
      final track = w.track;
      debugPrint('DIAG-STAGE W putar ${track.id} mulai');
      ({String? visitorData, String source, int? signatureTimestamp}) wc;
      try {
        wc = await provider
            .debugFetchWatchContext(track.id)
            .timeout(const Duration(seconds: 60));
      } catch (e) {
        _line('WP · [${track.id}] konteks tonton segar GALAT — ${describeError(e)}; bukti putar subjek gugur.');
        continue;
      }
      if (wc.visitorData == null) {
        _line('WP · [${track.id}] konteks tonton segar tanpa visitorData — bukti putar subjek gugur.');
        continue;
      }
      final probe = await _wProbeVariant(wv, track, wc.visitorData!, wc.signatureTimestamp);
      if (probe == null) {
        _line('WP · [${track.id}] resolusi+rentang segar GAGAL — bukti putar subjek gugur.');
        continue;
      }
      final info = probe.info!;
      final p = AudioPlayer(useProxyForRequestHeaders: ClaiAudioHandler.useProxyForRequestHeaders);
      try {
        final r = await _probeCrossPlay(
            p,
            Uri.parse(info.url),
            {
              'User-Agent': probe.userAgent,
              'Referer': wv.webHost
                  ? 'https://www.youtube.com/watch?v=${track.id}'
                  : 'https://music.youtube.com/',
            },
            'WP-${track.id}');
        _line('WP · [${track.id}] itag=${probe.tierItags['normal'] ?? '-'} (${info.mimeType}, ${info.bitrate ?? '-'} bps)'
            ': ${r.ok ? 'LOLOS PUTAR' : 'GAGAL PUTAR'} — ${r.detail}');
        if (r.ok) playPass++;
      } catch (e) {
        _line('WP · [${track.id}] GALAT bukti putar: ${describeError(e)}');
      } finally {
        await p.dispose();
      }
      await _printNative('WP-${track.id}');
      debugPrint('DIAG-STAGE W putar ${track.id} selesai lolos=$playPass');
    }
    _line('');
    if (playPass >= 3) {
      _line('W · VONIS TAHAP 1: LOLOS — varian $winTag ${wv.client} menyeberang:'
          ' rentang menang $winCount subjek, bukti putar lolos $playPass subjek.');
    } else {
      _line('W · VONIS TAHAP 1: GAGUR di bukti putar — rentang menang $winCount subjek'
          ' tetapi putar hanya lolos $playPass subjek (<3).');
    }
    _finishReport();
  }

  void _finishReport() {
    _line('');
    _line('SELESAI.');
    for (final l in _report.toString().split('\n')) {
      debugPrint('DIAG-REPORT|$l');
    }
    if (mounted) setState(() => _running = false);
  }

  // ================= Ronde Instrumentasi Upstream (v3.2) =================
  // Tujuan: menangkap apa yang SEBENARNYA terjadi pada ambilan upstream di
  // dalam jalur proxy (V5/V6) — status upstream persisnya selama ini ditelan
  // lapisan proxy just_audio dan hanya tampak sebagai 500 di ExoPlayer.
  // Setiap ambilan dicatat: metode, host, itag, NAMA parameter URL (bukan
  // URL bertanda tangan), header yang dikirim (UA & Range persis), status,
  // header respons kunci, byte pertama & total, dan waktu tiap tahap.
  // Jalur probe langsung (B2) memakai pembungkus yang sama persis sebagai
  // pembanding yang diketahui baik (206).

  int _upActive = 0;

  void _up(String s) {
    debugPrint('DIAG-UP| $s');
    _line('   up↳ $s');
  }

  /// Bungkus aliran tubuh respons: catat potongan pertama, kemajuan tiap
  /// ±256 KiB, penyelesaian (total byte), dan galat di tengah aliran.
  Stream<List<int>> _tapBody(String tag, Stream<List<int>> src, Stopwatch sw) async* {
    var total = 0;
    var chunks = 0;
    var lastMark = 0;
    try {
      await for (final c in src) {
        total += c.length;
        chunks++;
        if (chunks == 1) {
          _up('UP $tag first-chunk ${c.length}B t=${sw.elapsedMilliseconds}ms');
        } else if (total - lastMark >= 262144) {
          lastMark = total;
          _up('UP $tag progress ${total}B t=${sw.elapsedMilliseconds}ms');
        }
        yield c;
      }
      _up('UP $tag body-done total=${total}B chunks=$chunks t=${sw.elapsedMilliseconds}ms');
    } catch (e) {
      _up('UP $tag body-ERR total=${total}B t=${sw.elapsedMilliseconds}ms :: $e');
      rethrow;
    }
  }

  /// Ambilan tercatat: fungsi yang SAMA dengan yang dipakai produksi
  /// (ResolvingAudioSource.fetchHttpRange) + pencatatan penuh di sekelilingnya.
  Future<FetchedBytes> _tracedFetch(String tag, Uri uri,
      {required int start, required int endInclusive}) async {
    final sw = Stopwatch()..start();
    _upActive++;
    final names = uri.queryParameters.keys.toList()..sort();
    _up('UP $tag GET host=${uri.host} itag=${uri.queryParameters['itag'] ?? '-'} '
        'params=[${names.join(',')}] range=bytes=$start-$endInclusive '
        'ua="${ResolvingAudioSource.playerUserAgent}" active=$_upActive');
    try {
      final f = await ResolvingAudioSource.fetchHttpRange(uri,
          start: start, endInclusive: endInclusive);
      _up('UP $tag -> status=${f.statusCode} ct=${f.contentType ?? '-'} '
          'cr=${f.contentRange ?? '-'} cl=${f.contentLength} '
          't=${sw.elapsedMilliseconds}ms');
      return FetchedBytes(
        statusCode: f.statusCode,
        contentLength: f.contentLength,
        contentRange: f.contentRange,
        contentType: f.contentType,
        body: _tapBody(tag, f.body, sw),
      );
    } catch (e) {
      _up('UP $tag EXC t=${sw.elapsedMilliseconds}ms :: $e');
      rethrow;
    } finally {
      _upActive--;
    }
  }

  RangeFetcher _fetcherFor(String tag) =>
      (Uri uri, {required int start, required int endInclusive}) =>
          _tracedFetch(tag, uri, start: start, endInclusive: endInclusive);

  /// Pengawas denyut: selama varian berjalan, cetak penanda tiap 5 dtk agar
  /// titik berhenti rantai proxy terkurung waktunya dari logcat.
  void Function() _startWatch(String label) {
    final sw = Stopwatch()..start();
    final timer = Timer.periodic(const Duration(seconds: 5), (_) {
      debugPrint('DIAG-UP| WATCH $label t=${sw.elapsed.inSeconds}s activeFetch=$_upActive');
    });
    return () {
      timer.cancel();
      sw.stop();
    };
  }

  /// Probe putar untuk varian tercatat: play() TIDAK ditunggu (future play()
  /// just_audio baru selesai saat putar berhenti/selesai — menunggu-nya adalah
  /// cacat probe v3 yang membuat V6 "menggantung"); vonis dari posisi maju +
  /// peristiwa galat, jendela 20 dtk.
  Future<({bool ok, Duration? duration, int maxPosMs, Object? error, List<String> captured})>
      _probeTraced(AudioPlayer p, AudioSource src, String label) async {
    final captured = <String>[];
    final sub = p.playbackEventStream.listen((ev) {
      if (ev.errorCode != null) {
        final name = exoErrorCodeName(ev.errorCode!);
        final line = 'event: errorCode=${ev.errorCode}${name != null ? ' ($name)' : ''}'
            ' errorMessage=${ev.errorMessage ?? '-'} state=${ev.processingState.name}';
        if (!captured.contains(line)) captured.add(line);
      }
    }, onError: (Object e) {
      final line = 'aliran: ${describePlayerError(e)}';
      if (!captured.contains(line)) captured.add(line);
    });
    final stopWatch = _startWatch(label);
    try {
      Duration? duration;
      try {
        debugPrint('DIAG-STAGE $label setSrc start');
        await p.setAudioSource(src).timeout(const Duration(seconds: 25));
        duration = p.duration;
        debugPrint('DIAG-STAGE $label setSrc done duration=$duration');
      } catch (e) {
        debugPrint('DIAG-STAGE $label setSrc error: $e');
        await Future<void>.delayed(const Duration(milliseconds: 300));
        return (ok: false, duration: null, maxPosMs: 0, error: e, captured: captured);
      }
      Object? playError;
      var playDone = false;
      debugPrint('DIAG-STAGE $label play start (tidak ditunggu)');
      p.play().then((_) {
        playDone = true;
        debugPrint('DIAG-STAGE $label play future selesai');
      }).catchError((Object e) {
        playError = e;
        debugPrint('DIAG-STAGE $label play future galat: $e');
      });
      var maxPos = 0;
      final sw = Stopwatch()..start();
      while (sw.elapsed < const Duration(seconds: 20)) {
        final pos = p.position.inMilliseconds;
        if (pos > maxPos) maxPos = pos;
        if (maxPos >= 400 || p.processingState == ProcessingState.completed) break;
        if (captured.isNotEmpty && maxPos == 0) break;
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      debugPrint('DIAG-STAGE $label loop done maxPos=$maxPos '
          'captured=${captured.length} playDone=$playDone playError=$playError');
      final ok = captured.isEmpty &&
          playError == null &&
          (maxPos >= 400 || p.processingState == ProcessingState.completed);
      try {
        await p.stop().timeout(const Duration(seconds: 5));
      } catch (_) {}
      debugPrint('DIAG-STAGE $label stop done ok=$ok');
      return (ok: ok, duration: duration, maxPosMs: maxPos,
          error: playError, captured: captured);
    } finally {
      stopWatch();
      await sub.cancel();
    }
  }

  /// Matriks varian untuk membuat URI ADAPTIF dapat diputar ExoPlayer.
  /// v3.2 (Ronde Instrumentasi Upstream): V1–V4 dilewati (header terbukti
  /// mati di lari 20:50); yang dijalankan adalah V5 & V6 dengan sumber
  /// tercatat penuh (_TracedSource + _tracedFetch), ditambah dua ambilan
  /// kontrol tepat sesudah V5 untuk pembeda tajam: P1 = HttpClient BARU
  /// (kolam segar) dan P2 = klien bersama — keduanya dart:io langsung pada
  /// URL & jendela yang sama dengan ambilan terakhir V5.
  Future<void> _runVariantMatrix(Track track, StreamInfo info) async {
    final provider = ref.read(ytMusicProvider);
    _line('── V · MATRIKS VARIAN ADAPTIF (vonis = putar: durasi + posisi maju)');
    _line('   v3.2: V5 & V6 berinstrumentasi upstream penuh; B2 = pembanding langsung (206).');

    Future<void> variant(String label, AudioPlayer p, AudioSource src,
        {_TracedSource? watch}) async {
      try {
        debugPrint('DIAG-STAGE variant $label start');
        final r = await _probeTraced(p, src, label);
        _reportProbe('V · $label', r);
        if (watch != null && watch.fallbackActive) {
          _line('   catatan: varian ini beralih ke CADANGAN MUXED (bukan adaptif murni).');
        }
        debugPrint('DIAG-STAGE variant $label probe done');
      } catch (e, st) {
        _line('V · $label: GAGAL bangun — ${describePlayerError(e, st)}');
      } finally {
        try {
          await p.dispose().timeout(const Duration(seconds: 10));
        } catch (_) {}
        debugPrint('DIAG-STAGE variant $label dispose done');
      }
      await _printNative('V');
    }

    // V5 — ResolvingAudioSource adaptif MURNI (tanpa cadangan), tercatat.
    final v5 = _TracedSource(track, () async => info,
        label: 'V5', log: _up, fetcher: _fetcherFor('V5'));
    await variant('V5 ResolvingAudioSource adaptif murni (tercatat)',
        AudioPlayer(useProxyForRequestHeaders: false), v5, watch: v5);

    // Kontrol pasca-V5: ambilan langsung pada URL adaptif yang sama,
    // jendela penuh 0-1048575 (jendela yang dipakai V5 untuk posisi 0).
    _line('── P · KONTROL PASCA-V5 (dart:io langsung, URL & jendela sama)');
    try {
      final f = await _tracedFetch('P2', Uri.parse(info.url),
              start: 0, endInclusive: 1048575)
          .timeout(const Duration(seconds: 30));
      var n = 0;
      await for (final c in f.body) {
        n += c.length;
      }
      _line('P2 · klien bersama: status=${f.statusCode} · drained $n byte');
    } catch (e) {
      _line('P2 · klien bersama GALAT: ${describeError(e)}');
    }
    {
      final sw = Stopwatch()..start();
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
      try {
        final req = await client.getUrl(Uri.parse(info.url));
        req.headers.set(HttpHeaders.userAgentHeader, ResolvingAudioSource.playerUserAgent);
        req.headers.set(HttpHeaders.rangeHeader, 'bytes=0-1048575');
        final res = await req.close().timeout(const Duration(seconds: 20));
        var n = 0;
        await for (final c in res) {
          n += c.length;
        }
        _up('UP P1 GET host=${Uri.parse(info.url).host} itag=${Uri.parse(info.url).queryParameters['itag'] ?? '-'} '
            'range=bytes=0-1048575 (HttpClient BARU) -> status=${res.statusCode} '
            'ct=${res.headers.contentType?.mimeType ?? '-'} '
            'cr=${res.headers.value(HttpHeaders.contentRangeHeader) ?? '-'} '
            'cl=${res.contentLength} drained=$n t=${sw.elapsedMilliseconds}ms');
        _line('P1 · HttpClient baru: status=${res.statusCode} · drained $n byte');
      } catch (e) {
        _up('UP P1 EXC t=${sw.elapsedMilliseconds}ms :: $e');
        _line('P1 · HttpClient baru GALAT: ${describeError(e)}');
      } finally {
        client.close(force: true);
      }
    }

    // V6 — bentuk produksi anak proxy: adaptif + cadangan muxed, tercatat.
    final v6 = _TracedSource(track, () async => info,
        resolveFallback: () => provider.resolveMuxedFallback(track),
        label: 'V6', log: _up, fetcher: _fetcherFor('V6'));
    await variant('V6 ResolvingAudioSource + cadangan muxed (tercatat)',
        AudioPlayer(useProxyForRequestHeaders: false), v6, watch: v6);
  }

  // ---------------- Langkah E: pipa lokal tanpa jaringan ----------------
  Future<void> _runToneSteps() async {
    _line('════════ Uji pipa lokal (TANPA jaringan)');
    final wav = buildSineWav();
    _line('E · nada uji WAV ${wav.length} byte (sinus 440 Hz, 2 dtk, 16 kHz mono 16-bit)');

    // E1: StreamAudioSource polos dari memori.
    {
      final p = AudioPlayer();
      try {
        await _playAndProbe('E1 · StreamAudioSource memori polos', p, MemoryAudioSource(wav));
      } finally {
        await p.dispose();
      }
      await _printNative('E1');
    }

    // E2: ResolvingAudioSource dengan fetcher rintisan atas byte yang sama.
    {
      const stubTrack = Track(
        key: TrackKey('diag', 'nada-uji'),
        title: 'Nada uji',
        artistNames: 'Diagnostik Putar',
        playableRef: 'nada-uji',
      );
      final src = ResolvingAudioSource(
        stubTrack,
        () async => StreamInfo(
          url: 'https://rintisan.invalid/nada.wav',
          mimeType: 'audio/wav',
          expiresAt: DateTime.now().add(const Duration(minutes: 5)),
        ),
        fetcher: wavStubFetcher(wav),
      );
      final p = AudioPlayer();
      try {
        await _playAndProbe('E2 · ResolvingAudioSource + fetcher rintisan', p, src);
      } finally {
        await p.dispose();
      }
      await _printNative('E2');
    }
  }

  /// Muat [src], putar, dan buktikan posisi BERGERAK (atau pemutaran selesai) —
  /// bukan sekadar "load tidak melempar": penyakit v4.1 adalah durasi tampil
  /// tetapi posisi diam & tanpa suara.
  Future<void> _playAndProbe(String label, AudioPlayer p, AudioSource src) async {
    final captured = <String>[];
    final sub = p.playbackEventStream.listen((ev) {
      if (ev.errorCode != null) {
        final name = exoErrorCodeName(ev.errorCode!);
        final line = 'event: errorCode=${ev.errorCode}${name != null ? ' ($name)' : ''}'
            ' errorMessage=${ev.errorMessage ?? '-'} state=${ev.processingState.name}';
        if (!captured.contains(line)) captured.add(line);
      }
    }, onError: (Object e) {
      final line = 'aliran: ${describePlayerError(e)}';
      if (!captured.contains(line)) captured.add(line);
    });
    try {
      await p.setAudioSource(src).timeout(const Duration(seconds: 10));
      await p.play();
      final sw = Stopwatch()..start();
      var moved = false;
      while (sw.elapsed < const Duration(seconds: 6)) {
        if (p.position >= const Duration(milliseconds: 400) ||
            p.processingState == ProcessingState.completed) {
          moved = true;
          break;
        }
        if (captured.isNotEmpty) break;
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      _line('$label: ${moved ? 'BERHASIL' : 'GAGAL'} — posisi=${p.position.inMilliseconds}ms'
          ' · state=${p.processingState.name} · durasi=${p.duration ?? '-'}');
      await p.stop();
    } catch (e) {
      _line('$label: GAGAL muat — ${describePlayerError(e)}');
    } finally {
      await sub.cancel();
    }
    for (final c in captured) {
      _line('   mentah↳ $c');
    }
  }

  /// Tombol alat Diagnostik (Ronde Sapuan 8045): pil tonal
  /// surface-3 — menggantikan OutlinedButton Material mentah;
  /// tombol Jalankan utama tetap pil isi Volt.
  Widget _toolButton({
    required Widget icon,
    required Widget label,
    required VoidCallback? onPressed,
  }) {
    return FilledButton.tonal(
      style: FilledButton.styleFrom(
        backgroundColor: ClaiColors.surface3,
        foregroundColor: ClaiColors.ink,
      ),
      onPressed: onPressed,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [icon, const SizedBox(width: 8), label],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.diagTitle)),
      // Audit 8047: SELURUH badan kini satu gulir dengan cadangan
      // chrome bawah — struktur Kolom-tetap lama menaruh baris alat
      // seksi DIRECT (dropdown sabotase, tombol-tombolnya) DI BALIK
      // kartu mini + nav cangkang sehingga tak terketuk. Kedua lab
      // WebView tetap terpasang eager (SingleChildScrollView membangun
      // anaknya seketika, bukan malas) — invarian "selalu terpasang"
      // milik mereka utuh.
      body: SingleChildScrollView(
        padding: EdgeInsets.only(bottom: bottomChromeClearance(context)),
        child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(
            context.l10n.diagIntro,
            style: const TextStyle(color: ClaiColors.inkSecondary, fontSize: 13, height: 1.4),
          ),
        ),
        // B-01 (Sapuan): angka gerbang Bab 3 dari pemakaian NYATA sesi ini —
        // sebelumnya layar ini hanya uji rantai manual tanpa statistik gerbang.
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: Container(
            padding: const EdgeInsets.all(14),
            // Wajah (Ronde Sapuan 8045): kartu statistik = tonal
            // surface-1 radius 16 seperti kartu aplikasi lain. ISI
            // tidak berubah seinci pun — kepadatan data Diagnostik
            // adalah perilaku terkuncinya; baris Napas (U1) dan
            // Waveform: di dalamnya tetap persis.
            decoration: BoxDecoration(color: ClaiColors.surface1, borderRadius: BorderRadius.circular(16)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(context.l10n.diagGatesTitle,
                  style: const TextStyle(color: ClaiColors.ink, fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(height: 6),
              if (GateMetrics.instance.coldStartMs != null)
                Text(context.l10n.diagGateCold(GateMetrics.instance.coldStartMs!),
                    style: const TextStyle(color: ClaiColors.inkSecondary, fontSize: 12)),
              if (GateMetrics.instance.tapToSoundSamples.isEmpty)
                Text(context.l10n.diagGateNone,
                    style: const TextStyle(color: ClaiColors.inkSecondary, fontSize: 12))
              else ...[
                // URUTAN ARGUMEN (perbaikan Ronde Player B): tanda tangan
                // hasil gen-l10n adalah diagGateTap(median, n, p95) —
                // parameter diurutkan ALFABETIS oleh generator, bukan
                // mengikuti urutan tampil di kalimat. Pemanggilan lama
                // mengoper (median, p95, n) sehingga layar mencetak
                // "median 9349 · p95 1 · 9349 sampel" untuk SATU sampel
                // 9349 md — median > p95 yang mustahil. Matematika
                // persentilnya sendiri benar (teruji); yang salah murni
                // urutan di titik panggil ini.
                Text(context.l10n.diagGateTap(
                    GateMetrics.instance.tapToSoundMedian ?? 0,
                    GateMetrics.instance.tapToSoundSamples.length,
                    GateMetrics.instance.tapToSoundP95 ?? 0),
                    style: const TextStyle(color: ClaiColors.inkSecondary, fontSize: 12)),
                Text(context.l10n.diagGateFail(
                    GateMetrics.instance.playbackAttempts,
                    GateMetrics.instance.playbackFailures,
                    (GateMetrics.instance.failureRatio * 100).toStringAsFixed(1)),
                    style: const TextStyle(color: ClaiColors.inkSecondary, fontSize: 12)),
              ],
              // Instrumentasi napas U1 (Ronde Player B): rantai
              // RMS→amplop→faktor harus bisa DIBUKTIKAN dari layar ini —
              // sampel terlihat/diumpan, rentang dB, level & faktor kini.
              Builder(builder: (context) {
                ref.watch(ambientControllerProvider);
                final ambN = ref.read(ambientControllerProvider.notifier);
                final breathText = ambN.rmsSeen == 0
                    ? 'RMS seen 0'
                    : 'RMS seen ${ambN.rmsSeen} · fed ${ambN.rmsFed} · '
                        '${ambN.rmsMinDb!.toStringAsFixed(0)}..${ambN.rmsMaxDb!.toStringAsFixed(0)} dB · '
                        'level ${ambN.breathLevel.toStringAsFixed(2)} · '
                        'factor ${ambN.breathFactorNow.toStringAsFixed(2)}';
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(context.l10n.diagBreathLine(breathText),
                      style: const TextStyle(color: ClaiColors.inkSecondary, fontSize: 12)),
                );
              }),
              // Instrumentasi perekam waveform (Ronde Perbaikan Waveform
              // Perangkat): nasib setiap peristiwa RMS dibuktikan dari
              // angka — asal sesi, sebab buang, dan ember trek berjalan.
              Builder(builder: (context) {
                final rec = ref.watch(waveformRecorderProvider);
                final handler = ref.read(audioHandlerProvider);
                final curKey = handler.engine.current?.key;
                final measured = curKey == null
                    ? 0
                    : rec.dataFor(curKey).measuredCount;
                String shortKey(TrackKey? k) => k == null
                    ? '-'
                    : (k.id.length <= 6 ? k.id : k.id.substring(k.id.length - 6));
                final waveText = 'RMS ${rec.rmsEvents} '
                    '(aktif ${rec.rmsFromActiveSession} · lain ${rec.rmsFromOtherSession} · '
                    'beda-kunci ${rec.rmsKeyMismatch}) · umpan ${rec.feedCalls} · '
                    'tulis ${rec.acceptedWrites} · buang jeda ${rec.dropNotPlaying} · '
                    'durasi0 ${rec.dropNoDuration} · idx ${rec.dropBadIndex} · '
                    'diam ${rec.dropNoChange} · ember trek ini $measured/56 · '
                    'umpan→${shortKey(rec.lastFeedKey)} bunyi→${shortKey(rec.lastSoundingKey)} '
                    'pos ${rec.lastPosMs} dur ${rec.lastDurMs} · '
                    'jaga ${handler.visReassertCount}';
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(context.l10n.diagWaveformLine(waveText),
                      style: const TextStyle(color: ClaiColors.inkSecondary, fontSize: 12)),
                );
              }),
            ]),
          ),
        ),
        // Bagian DIRECT-1 (Tahap 3): kesehatan jalur produksi + kill-switch
        // + pementasan bukti penolakan. Di atas laboratorium di bawah.
        const DirectPathSection(),
        // Laboratorium PoToken (v3.5): WebView pencetak token untuk matriks
        // P — selalu terpasang & terlihat (BotGuard membaca lingkungan
        // halaman yang nyata). Sejak Tahap 3 widget ini adalah mesin
        // produksi DirectWebEngine itu sendiri (alias kompatibilitas);
        // instans produksi dipasang terpisah oleh DirectEngineHost.
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Container(
            height: 96,
            decoration: BoxDecoration(
                color: ClaiColors.surface1, borderRadius: BorderRadius.circular(16)),
            clipBehavior: Clip.antiAlias,
            child: PoTokenLab(key: _poLabKey, onProgress: _poProgress),
          ),
        ),
        // Laboratorium Halaman Watch (v3.10): WebView halaman watch asli
        // untuk matriks V — selalu terpasang agar pemutar tamu halaman
        // bisa berinisialisasi sebelum matriks dijalankan.
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Container(
            height: 110,
            decoration: BoxDecoration(
                color: ClaiColors.surface1, borderRadius: BorderRadius.circular(16)),
            clipBehavior: Clip.antiAlias,
            child: WatchLab(key: _watchLabKey),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          // Wrap, bukan Row (v4.3): dua tombol berdampingan meluap ±22dp pada
          // lebar HP + skala font pemilik (log flutter-error v4.2) — kini tombol
          // kedua turun ke baris berikutnya bila lebar tidak cukup.
          child: Wrap(spacing: 8, runSpacing: 8, children: [
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: ClaiColors.accent, foregroundColor: ClaiColors.onAccent),
              onPressed: _running ? null : _run,
              icon: ClaiIcon(ClaiIcons.playCircle, size: 18),
              label: Text(_running ? context.l10n.diagRunning : context.l10n.diagRun),
            ),
            _toolButton(
              onPressed: _running ? null : _runClientMatrix,
              icon: ClaiIcon(ClaiIcons.playCircle, size: 18),
              label: Text(context.l10n.diagRunClients),
            ),
            _toolButton(
              onPressed: _running ? null : _runClientPlayProof,
              icon: ClaiIcon(ClaiIcons.playCircle, size: 18),
              label: Text(context.l10n.diagPlayWinner),
            ),
            _toolButton(
              onPressed: _running ? null : _runPoTokenMatrix,
              icon: ClaiIcon(ClaiIcons.playCircle, size: 18),
              label: Text(context.l10n.diagRunPoToken),
            ),
            _toolButton(
              onPressed: _running ? null : _runCrossingMatrix,
              icon: ClaiIcon(ClaiIcons.playCircle, size: 18),
              label: Text(context.l10n.diagRunCrossing),
            ),
            _toolButton(
              onPressed: _running ? null : _runDecipherMatrix,
              icon: ClaiIcon(ClaiIcons.playCircle, size: 18),
              label: Text(context.l10n.diagRunDecipher),
            ),
            _toolButton(
              onPressed: _running ? null : _runSabrPresence,
              icon: ClaiIcon(ClaiIcons.playCircle, size: 18),
              label: Text(context.l10n.diagRunSabr),
            ),
            _toolButton(
              onPressed: _running ? null : _runSabrCeiling,
              icon: ClaiIcon(ClaiIcons.playCircle, size: 18),
              label: Text(context.l10n.diagRunSabrCeiling),
            ),
            _toolButton(
              onPressed: _running ? null : _runWebViewMatrix,
              icon: ClaiIcon(ClaiIcons.playCircle, size: 18),
              label: Text(context.l10n.diagRunWebView),
            ),
            _toolButton(
              onPressed: _running
                  ? null
                  : () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const LoginLabScreen())),
              icon: ClaiIcon(ClaiIcons.playCircle, size: 18),
              label: Text(context.l10n.diagOpenLoginLab),
            ),
            _toolButton(
              onPressed: _running ? null : _runLoginMatrix,
              icon: ClaiIcon(ClaiIcons.playCircle, size: 18),
              label: Text(context.l10n.diagRunLogin),
            ),
            _toolButton(
              onPressed: _running ? null : _runTahap2Matrix,
              icon: ClaiIcon(ClaiIcons.playCircle, size: 18),
              label: Text(context.l10n.diagRunTahap2),
            ),
            _toolButton(
              onPressed: _report.isEmpty
                  ? null
                  : () async {
                      await Clipboard.setData(ClipboardData(text: _report.toString()));
                      if (context.mounted) {
                        ScaffoldMessenger.of(context)
                            .showSnackBar(SnackBar(content: Text(context.l10n.diagCopied)));
                      }
                    },
              icon: ClaiIcon(ClaiIcons.copy, size: 18),
              label: Text(context.l10n.diagCopy),
            ),
          ]),
        ),
        const SizedBox(height: 2),
        // Area laporan kini bagian dari gulir halaman yang sama
        // (dulu Expanded ber-gulir sendiri — akar baris alat tertutup
        // chrome); teks laporan utuh & bisa dipilih seperti semula.
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: _report.isEmpty
              ? SizedBox(
                  height: 120,
                  child: Center(child: Text(context.l10n.diagEmpty,
                      style: TextStyle(color: ClaiColors.inkFaint))),
                )
              : SelectableText(_report.toString(),
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12, height: 1.5, color: ClaiColors.ink)),
        ),
        ]),
      ),
    );
  }
}

/// ResolvingAudioSource tercatat (Ronde Instrumentasi Upstream, v3.2):
/// mencatat SETIAP request() yang diterima dari lapisan proxy — (start, end)
/// persis yang diminta ExoPlayer/proxy, rencana respons yang dihasilkan,
/// dan yang terpenting pengecualian apa adanya: pesan lemparan request()
/// produksi memuat status upstream sebenarnya ('ditolak sumber (HTTP …)')
/// yang selama ini ditelan proxy dan hanya tampak sebagai 500 di ExoPlayer.
/// Perilaku sumber tidak diubah sama sekali — hanya pengamatan.
class _TracedSource extends ResolvingAudioSource {
  final String label;
  final void Function(String) log;

  _TracedSource(super.track, super.resolve,
      {super.resolveFallback,
      super.fetcher,
      required this.label,
      required this.log});

  @override
  // ignore: experimental_member_use
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    final sw = Stopwatch()..start();
    log('REQ $label request(start=$start, end=$end)');
    try {
      final r = await super.request(start, end);
      log('REQ $label OK offset=${r.offset} srcLen=${r.sourceLength} '
          'clen=${r.contentLength} rangeSup=${r.rangeRequestsSupported} '
          'ct=${r.contentType} fb=$fallbackActive '
          't=${sw.elapsedMilliseconds}ms');
      return r;
    } catch (e) {
      log('REQ $label EXC t=${sw.elapsedMilliseconds}ms :: $e');
      rethrow;
    }
  }
}

/// Hasil decipher WebView lab (Diagnostik F3, Tahap 2) — nilai sig/n hanya
/// hidup di memori daftar ini.
class _SolveOutcome {
  final List<({String sig, String? n})>? values;
  final String? error;
  const _SolveOutcome.ok(this.values) : error = null;
  const _SolveOutcome.fail(this.error) : values = null;
}

/// Keadaan solver lintas-subjek selama Matriks X berjalan.
class _SolverState {
  String? baseJs;
  ({String defs, String sigName, String? nName})? solver;
  String? playerId;
  bool extractFailed = false;
}
