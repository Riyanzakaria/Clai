import 'dart:async';
import 'dart:io';

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
import '../player/load_ladder.dart';
import '../player/resolving_audio_source.dart';
import '../player/test_tone.dart';
import '../services/gate_metrics.dart';

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
    _line('DIAGNOSTIK PUTAR CLAI v2 — ${DateTime.now().toIso8601String()}');
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
    {
      final rung = handler.debugLoadRung;
      final p2 = AudioPlayer(useProxyForRequestHeaders: ClaiAudioHandler.useProxyForRequestHeaders);
      try {
        final child = await handler.debugChildSource(track);
        final src = ConcatenatingAudioSource(children: [child]);
        final r = await _captureLoad(p2, () => p2.setAudioSource(src));
        final viaFallback = child is ResolvingAudioSource && child.fallbackActive;
        _reportLoad('D · jalur aplikasi (anak ${rung + 1}: ${LoadLadder.rungLabel(rung)})', r);
        if (viaFallback) _line('   catatan: sumber D beralih ke CADANGAN MUXED di dalam proxy.');
      } catch (e, st) {
        _line('D · jalur aplikasi GAGAL bangun — ${describePlayerError(e, st)}');
      } finally {
        await p2.dispose();
      }
      await _printNative('D');
    }
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.diagTitle)),
      body: Column(children: [
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
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: ClaiColors.surface2, borderRadius: BorderRadius.circular(12)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(context.l10n.diagGatesTitle,
                  style: const TextStyle(color: ClaiColors.ink, fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(height: 6),
              if (GateMetrics.instance.coldStartMs != null)
                Text(context.l10n.diagGateCold(GateMetrics.instance.coldStartMs!),
                    style: const TextStyle(color: ClaiColors.inkSecondary, fontSize: 12.5)),
              if (GateMetrics.instance.tapToSoundSamples.isEmpty)
                Text(context.l10n.diagGateNone,
                    style: const TextStyle(color: ClaiColors.inkSecondary, fontSize: 12.5))
              else ...[
                Text(context.l10n.diagGateTap(
                    GateMetrics.instance.tapToSoundMedian ?? 0,
                    GateMetrics.instance.tapToSoundP95 ?? 0,
                    GateMetrics.instance.tapToSoundSamples.length),
                    style: const TextStyle(color: ClaiColors.inkSecondary, fontSize: 12.5)),
                Text(context.l10n.diagGateFail(
                    GateMetrics.instance.playbackAttempts,
                    GateMetrics.instance.playbackFailures,
                    (GateMetrics.instance.failureRatio * 100).toStringAsFixed(1)),
                    style: const TextStyle(color: ClaiColors.inkSecondary, fontSize: 12.5)),
              ],
            ]),
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
            OutlinedButton.icon(
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
        const Divider(height: 1),
        Expanded(
          child: _report.isEmpty
              ? Center(child: Text(context.l10n.diagEmpty,
                  style: TextStyle(color: ClaiColors.inkFaint)))
              : SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                      16, 16, 16, bottomChromeClearance(context)),
                  child: SelectableText(_report.toString(),
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 12, height: 1.5, color: ClaiColors.ink)),
                ),
        ),
      ]),
    );
  }
}
