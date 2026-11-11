import 'dart:async';
import 'dart:ui' as ui;

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/l10n.dart';

import '../app.dart';
import '../core/artwork.dart';
import '../core/clai_icons.dart';
import '../core/tokens.dart';
import '../domain/models.dart';
import '../player/audio_handler.dart';
import '../services/ambient_theme.dart';
import '../services/lyrics_service.dart';
import 'glass.dart';
import 'widgets.dart';

/// Lirik Penuh (keputusan pemilik 2026-11-10 18:01 — Varian B, menggantikan
/// lembar Varian A): pandangan lirik IMERSIF layar-penuh. Latar = sampul
/// lagu aktif ter-blur pekat + digelapkan memenuhi layar (vinyet atas-bawah,
/// pita tengah lebih jernih), warna ruangan mengikuti trek lewat Sampul
/// Hidup. Baris aktif = Clash Display 30/700 putih primer (BUKAN Volt —
/// Volt di ruangan ini hanya pemutar memuat & teks "Coba lagi"), baris
/// tetangga memudar + blur menurut jarak. Perilaku terkunci tidak berubah:
/// lead 250 ms, gulir otomatis (jeda 4 dtk sesudah seret manual), ketuk
/// baris = seek, kredit LRCLIB, cache lirik. Menutup: chip kaca chevron,
/// seret-turun di zona tetap, atau tombol kembali sistem.
Future<void> openLyricsScreen(BuildContext context) {
  return Navigator.of(claiRootContext(context)).push(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => const LyricsScreen(),
    ),
  );
}

/// Keadaan lembar lirik (publik agar keputusan keadaannya bisa diuji
/// sebagai fungsi murni — handler konkret menyentuh kanal platform).
enum LyricsViewState { loading, synced, plain, instrumental, notFound, netError, noTrack }

/// Pemetaan data lirik → keadaan tampil (murni).
LyricsViewState lyricsStateFor(LyricsData? data) => data == null
    ? LyricsViewState.notFound
    : data.source == 'error'
        ? LyricsViewState.netError
        : data.instrumental
            ? LyricsViewState.instrumental
            : data.synced
                ? LyricsViewState.synced
                : LyricsViewState.plain;

/// Keadaan gerbang dari sinyal trek berjalan (murni). Regresi 8048:
/// membuka lirik TANPA lagu dulu berputar di keadaan memuat selamanya
/// karena tak ada jalur kode yang menetapkan noTrack — kini gerbangnya
/// eksplisit: tanpa trek berarti noTrack, bukan loading.
LyricsViewState lyricsGateState({required bool hasTrack}) =>
    hasTrack ? LyricsViewState.loading : LyricsViewState.noTrack;

/// Tangga ukuran baris aktif Lirik Penuh: pahlawan 30 (DS) menurun
/// sampai lantai 18. Baris aktif TIDAK BOLEH terpotong (vonis perangkat
/// pemilik 2026-11-11: "We are just enough to stay and it's alright"
/// terpotong "…alrig…" pada 30/700 maks 2 baris + ellipsis) — jadi
/// ukurannya menyusut sampai barisnya MUAT UTUH, bukan teksnya yang
/// dikorbankan.
const List<double> kLyricActiveSizes = [30, 28, 26, 24, 22, 20, 18];

/// Hasil pengukuran baris aktif: [size] terbesar dari
/// [kLyricActiveSizes] yang membuat teks muat dalam [lines] baris
/// (≤2 selama tangga mencukupi; di lantai, [lines] = kebutuhan nyata
/// barisnya — baris aktif boleh tumbuh, tidak boleh terpotong).
({double size, int lines}) fitActiveLyricLine(
  String text,
  double maxWidth,
  TextScaler scaler,
) {
  TextPainter measure(double size, int maxLines) => TextPainter(
        text: TextSpan(
          text: text,
          style: displayStyle(size).copyWith(
            fontWeight: FontWeight.w700,
            height: 1.25,
          ),
        ),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
        maxLines: maxLines,
      )..layout(maxWidth: maxWidth);
  for (final size in kLyricActiveSizes) {
    final tp = measure(size, 2);
    final lines = tp.computeLineMetrics().length;
    if (!tp.didExceedMaxLines && lines <= 2) {
      return (size: size, lines: lines);
    }
  }
  final floor = kLyricActiveSizes.last;
  final tp = measure(floor, 1 << 30);
  return (size: floor, lines: tp.computeLineMetrics().length);
}

class LyricsScreen extends ConsumerStatefulWidget {
  const LyricsScreen({super.key});
  @override
  ConsumerState<LyricsScreen> createState() => _LyricsScreenState();
}

class _LyricsScreenState extends ConsumerState<LyricsScreen> {
  LyricsViewState _state = LyricsViewState.loading;
  LyricsData? _data;
  Track? _track;
  StreamSubscription<MediaItem?>? _sub;
  final _scroll = ScrollController();
  List<GlobalKey> _rowKeys = const [];
  int _active = -1;
  DateTime _userScrollUntil = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    final handler = ref.read(audioHandlerProvider);
    _track = handler.engine.current;
    _state = lyricsGateState(hasTrack: _track != null);
    if (_track != null) _load(_track!);
    _sub = handler.mediaItem.listen((item) {
      final cur = handler.engine.current;
      if (item == null || cur == null) {
        // Trek berhenti/hilang saat lirik terbuka → keadaan jujur
        // "tidak ada lagu", bukan sisa keadaan sebelumnya.
        if (_track != null && mounted) {
          _track = null;
          _data = null;
          _active = -1;
          setState(() => _state = LyricsViewState.noTrack);
        }
        return;
      }
      if (cur.key != _track?.key) {
        _track = cur;
        _active = -1;
        _load(cur);
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load(Track t, {bool force = false}) async {
    setState(() => _state = LyricsViewState.loading);
    final data = await ref.read(lyricsServiceProvider).getLyrics(t, forceRefresh: force);
    if (!mounted || _track?.key != t.key) return;
    setState(() {
      _data = data;
      _state = lyricsStateFor(data);
      _rowKeys = List.generate(
          data?.lines?.length ?? 0, (_) => GlobalKey());
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  void _onPosition(Duration pos) {
    final lines = _data?.lines;
    if (lines == null || _state != LyricsViewState.synced) return;
    final lead = pos + const Duration(milliseconds: 250);
    var idx = -1;
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].at <= lead) { idx = i; } else { break; }
    }
    if (idx != _active) {
      _active = idx;
      if (mounted) setState(() {});
      if (idx >= 0 && DateTime.now().isAfter(_userScrollUntil)) {
        _scrollToActive(idx);
      }
    }
  }

  /// Gulir ke baris aktif. Baris yang jauh belum tentu SUDAH dibangun
  /// ListView (kasus nyata bangku 8048: lirik dibuka saat posisi trek
  /// tersimpan di tengah lagu — baris aktif tak punya konteks, gulir
  /// presisi gagal total dan dinding lirik tertinggal ter-blur di atas).
  /// Strategi dua tahap: lompat kasar dari estimasi tinggi baris, lalu
  /// ensureVisible memperhalus sesudah baris terbangun.
  void _scrollToActive(int idx) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final ctx =
          idx < _rowKeys.length ? _rowKeys[idx].currentContext : null;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOut,
          alignment: 0.40,
        );
        return;
      }
      final max = _scroll.position.maxScrollExtent;
      _scroll.jumpTo((idx * 58.0).clamp(0.0, max));
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scroll.hasClients) return;
        final ctx2 =
            idx < _rowKeys.length ? _rowKeys[idx].currentContext : null;
        if (ctx2 != null) {
          Scrollable.ensureVisible(
            ctx2,
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOut,
            alignment: 0.40,
          );
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final handler = ref.watch(audioHandlerProvider);
    final amb = ref.watch(ambientControllerProvider.select(ambientUiSlice)); // 8053 B(i): irisan tanpa napas
    final t = _track;
    final reduceFx = amb.reduceEffects ||
        (MediaQuery.maybeDisableAnimationsOf(context) ?? false);
    return Scaffold(
      backgroundColor: ClaiColors.base,
      body: Stack(
        fit: StackFit.expand,
        children: [
          _roomBackground(context, amb, t, reduceFx),
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _header(context, t),
                Expanded(
                  child: switch (_state) {
                    LyricsViewState.loading => const Center(
                        child: CircularProgressIndicator(
                            color: ClaiColors.accent)),
                    LyricsViewState.noTrack =>
                      _message(ClaiIcons.lyrics, context.l10n.lyrNoTrack),
                    LyricsViewState.instrumental => _message(
                        ClaiIcons.musicNote, context.l10n.lyrInstrumental),
                    LyricsViewState.notFound => _message(
                        ClaiIcons.lyrics, context.l10n.lyrNotFound,
                        retry: t == null
                            ? null
                            : () => _load(t, force: true)),
                    LyricsViewState.netError => _message(
                        ClaiIcons.wifiOff, context.l10n.lyrNetError,
                        retry: t == null
                            ? null
                            : () => _load(t, force: true)),
                    LyricsViewState.plain => _plainView(),
                    LyricsViewState.synced => _syncedView(handler, reduceFx),
                  },
                ),
                _bottom(context, handler, amb),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Latar ruangan: warna dasar cucian Sampul Hidup + sampul ter-blur
  /// pekat + peredup + vinyet. Pergantian trek ber-crossfade ±600 ms
  /// (diredam total saat mode kurangi-efek).
  Widget _roomBackground(BuildContext context, AmbientUiState amb,
      Track? track, bool reduceFx) {
    final url = track?.artworkUrl;
    final base = amb.enabled && amb.palette.active
        ? Color.alphaBlend(
            amb.palette.washColor(AmbientSurfaceKind.player, amb.strength),
            ClaiColors.base)
        : ClaiColors.base;
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: base),
        AnimatedSwitcher(
          duration:
              reduceFx ? Duration.zero : const Duration(milliseconds: 600),
          child: url == null
              ? const SizedBox.expand(key: ValueKey('lirik-tanpa-sampul'))
              : ImageFiltered(
                  key: ValueKey(url),
                  imageFilter: ui.ImageFilter.blur(
                      sigmaX: 42, sigmaY: 42, tileMode: TileMode.clamp),
                  child: Image.network(
                    // 8053 B(iii): latar ruangan selalu ter-blur sigma
                    // 42 + peredup 0x61 + vinyet — detail di atas ±½
                    // lebar layar fisik musnah oleh blur itu sendiri.
                    // Dekode dibatasi ½ lebar piksel perangkat (kunci
                    // cache ResizeImage sadar-ukuran) + varian URL 540:
                    // memori dekode turun ±4x; piksel akhir wajib lolos
                    // beda tangkapan gerbang D ronde ini.
                    artworkUrlForSize(url, 540) ?? url,
                    cacheWidth: (MediaQuery.sizeOf(context).width *
                            MediaQuery.devicePixelRatioOf(context) *
                            0.5)
                        .round(),
                    fit: BoxFit.cover,
                    width: double.infinity,
                    height: double.infinity,
                    errorBuilder: (_, _, _) => const SizedBox.expand(),
                  ),
                ),
        ),
        const ColoredBox(color: Color(0x61000000)),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0x8C000000),
                Color(0x00000000),
                Color(0x00000000),
                Color(0x9E000000),
              ],
              stops: [0, 0.28, 0.70, 1],
            ),
          ),
        ),
      ],
    );
  }

  /// Kepala minimal: sampul kecil + judul/artis kiri; SATU chip kaca
  /// chevron-turun kanan. Seret-turun di zona kepala ini juga menutup.
  Widget _header(BuildContext context, Track? t) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onVerticalDragEnd: (d) {
        if ((d.primaryVelocity ?? 0) > 240) Navigator.of(context).maybePop();
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
        child: Row(children: [
          if (t != null) ...[
            CoverArt(url: t.artworkUrl, size: 40, label: t.title, radius: 8),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: ClaiColors.ink,
                    ),
                  ),
                  Text(
                    t.artistNames,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: ClaiColors.inkSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ] else
            const Spacer(),
          const SizedBox(width: 12),
          SizedBox(
            width: 36,
            height: 36,
            child: GlassSurface(
              radius: 18,
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: () => Navigator.of(context).maybePop(),
                child: Center(
                  child: ClaiIcon(ClaiIcons.chevronDown,
                      size: 20, color: ClaiColors.ink),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  /// Bawah ruangan: garis kemajuan rambut 3 dp (isian nada sampul
  /// diperdalam §11.9), transport terpusat kaca, kredit LRCLIB kecil.
  Widget _bottom(
      BuildContext context, ClaiAudioHandler handler, AmbientUiState amb) {
    final progressTone = progressToneFor(amb.palette);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        StreamBuilder<Duration>(
          stream: handler.positionStream,
          builder: (context, snap) {
            final dur = handler.mediaItem.valueOrNull?.duration ??
                Duration.zero;
            final pos = snap.data ?? Duration.zero;
            final frac = dur.inMilliseconds <= 0
                ? 0.0
                : (pos.inMilliseconds / dur.inMilliseconds)
                    .clamp(0.0, 1.0);
            return SizedBox(
              height: 3,
              child: Stack(children: [
                const ColoredBox(color: Color(0x1FFFFFFF)),
                FractionallySizedBox(
                  widthFactor: frac,
                  child: ColoredBox(color: progressTone),
                ),
              ]),
            );
          },
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: ClaiIcon(ClaiIcons.prev,
                    size: 28, color: ClaiColors.ink.withValues(alpha: 0.7)),
                onPressed:
                    _track == null ? null : () => handler.skipToPrevious(),
              ),
              const SizedBox(width: 26),
              StreamBuilder<dynamic>(
                stream: handler.playbackState.stream,
                initialData: handler.playbackState.valueOrNull,
                builder: (context, ps) {
                  final playing = ps.data?.playing ?? false;
                  return SizedBox(
                    width: 60,
                    height: 60,
                    child: GlassSurface(
                      radius: 30,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(30),
                        onTap: _track == null
                            ? null
                            : () => playing
                                ? handler.pauseNow()
                                : handler.playNow(),
                        child: Center(
                          child: ClaiIcon(
                            playing ? ClaiIcons.pause : ClaiIcons.play,
                            size: 30,
                            color: ClaiColors.ink,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(width: 26),
              IconButton(
                icon: ClaiIcon(ClaiIcons.next,
                    size: 28, color: ClaiColors.ink.withValues(alpha: 0.7)),
                onPressed:
                    _track == null ? null : () => handler.skipToNext(),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Text(
            context.l10n.lyrCreditShort,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 10,
              color: ClaiColors.ink.withValues(alpha: 0.4),
            ),
          ),
        ),
      ],
    );
  }

  Widget _message(ClaiIconData icon, String text, {VoidCallback? retry}) =>
      Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ClaiIcon(icon, size: 40, color: ClaiColors.inkFaint),
            const SizedBox(height: 14),
            Text(text,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: ClaiColors.inkSecondary,
                    fontSize: 14,
                    height: 1.45)),
            if (retry != null) ...[
              const SizedBox(height: 12),
              TextButton(
                  onPressed: retry,
                  child: Text(context.l10n.commonRetry,
                      style: const TextStyle(color: ClaiColors.accent))),
            ],
          ]),
        ),
      );

  Widget _plainView() {
    final plain = _data?.plain ?? '';
    return FiniteScrollPage(
      padding: const EdgeInsets.fromLTRB(28, 16, 28, 24),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            context.l10n.lyrPlainNote,
            style: TextStyle(
              color: ClaiColors.ink.withValues(alpha: 0.5),
              fontSize: 13,
            ),
          ),
        ),
        SelectableText(
          plain,
          style: const TextStyle(
              color: ClaiColors.ink, fontSize: 15, height: 1.65),
        ),
      ],
    );
  }

  Widget _syncedView(ClaiAudioHandler handler, bool reduceFx) {
    final lines = _data?.lines ?? const <LyricsLine>[];
    return StreamBuilder<Duration>(
      stream: handler.positionStream,
      builder: (context, snap) {
        _onPosition(snap.data ?? Duration.zero);
        return NotificationListener<ScrollNotification>(
          onNotification: (n) {
            if (n is ScrollStartNotification && n.dragDetails != null) {
              _userScrollUntil =
                  DateTime.now().add(const Duration(seconds: 4));
            }
            return false;
          },
          child: ListView.builder(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
            itemCount: lines.length,
            itemBuilder: (context, i) {
              final line = lines[i];
              // Jangkar jarak: baris aktif; sebelum stempel pertama
              // (belum ada baris aktif) jangkarnya baris 0 TANPA status
              // pahlawan — dulu semua baris dihitung jarak 99 sehingga
              // seluruh dinding lirik ter-blur maksimum (temuan bangku
              // 8048, g2-lirik pertama).
              final anchor = _active < 0 ? 0 : _active;
              final dist = (i - anchor).abs();
              final isActive = _active >= 0 && dist == 0;
              final text = line.text.isEmpty ? '· · ·' : line.text;
              final TextStyle style;
              // Baris aktif: ukuran menyusut sampai muat UTUH (fitActive-
              // LyricLine) dan jumlah barisnya mengikuti pengukuran —
              // tanpa ellipsis (vonis pemilik 2026-11-11: baris aktif
              // terpotong "…alrig…"). Baris lain tetap pratinjau 2 baris.
              var activeLines = 2;
              if (isActive) {
                final fit = fitActiveLyricLine(
                  text,
                  MediaQuery.sizeOf(context).width - 56,
                  MediaQuery.textScalerOf(context),
                );
                activeLines = fit.lines;
                style = displayStyle(fit.size).copyWith(
                  fontWeight: FontWeight.w700,
                  color: ClaiColors.ink,
                  height: 1.25,
                );
              } else if (dist == 1) {
                style = TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: ClaiColors.ink.withValues(alpha: 0.65),
                  height: 1.3,
                );
              } else {
                style = TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w500,
                  color: ClaiColors.ink.withValues(alpha: 0.32),
                  height: 1.3,
                );
              }
              Widget row = InkWell(
                onTap: () => handler.seek(line.at),
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: isActive ? 14 : 10),
                  child: Text(
                    text,
                    key: i < _rowKeys.length ? _rowKeys[i] : null,
                    maxLines: isActive ? activeLines : 2,
                    overflow: isActive
                        ? TextOverflow.clip
                        : TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: style,
                  ),
                ),
              );
              if (!isActive && dist >= 2 && !reduceFx) {
                final sigma = ((dist - 1) * 1.2).clamp(0.0, 4.8).toDouble();
                row = ImageFiltered(
                  imageFilter:
                      ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
                  child: row,
                );
              }
              return row;
            },
          ),
        );
      },
    );
  }
}
