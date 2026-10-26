import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/l10n.dart';

import '../app.dart';
import '../core/clai_icons.dart';
import '../core/tokens.dart';
import '../domain/models.dart';
import '../player/audio_handler.dart';
import '../services/lyrics_service.dart';

/// Lirik (F2, PRD 5.8): tersinkron LRCLIB mengikuti posisi putar — baris aktif
/// beraksen Volt; ketuk baris = lompat ke waktu itu (seek). Mode polos bila
/// sumber hanya punya plainLyrics. Keadaan tidak-ditemukan dan gagal-jaringan
/// dinyatakan terpisah dan jujur; trek berganti → lirik dimuat ulang.
Future<void> openLyricsSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: claiRootContext(context), isScrollControlled: true, backgroundColor: ClaiColors.surface1,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => const FractionallySizedBox(heightFactor: 0.92, child: LyricsSheet()),
  );
}

class LyricsSheet extends ConsumerStatefulWidget {
  const LyricsSheet({super.key});
  @override
  ConsumerState<LyricsSheet> createState() => _LyricsSheetState();
}

enum _LyrState { loading, synced, plain, instrumental, notFound, netError, noTrack }

class _LyricsSheetState extends ConsumerState<LyricsSheet> {
  _LyrState _state = _LyrState.loading;
  LyricsData? _data;
  Track? _track;
  StreamSubscription<MediaItem?>? _sub;
  final _scroll = ScrollController();
  int _active = -1;
  DateTime _userScrollUntil = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    final handler = ref.read(audioHandlerProvider);
    _track = handler.engine.current;
    if (_track != null) _load(_track!);
    _sub = handler.mediaItem.listen((item) {
      if (item == null) return;
      final cur = handler.engine.current;
      if (cur != null && cur.key != _track?.key) {
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
    setState(() => _state = _LyrState.loading);
    final data = await ref.read(lyricsServiceProvider).getLyrics(t, forceRefresh: force);
    if (!mounted || _track?.key != t.key) return;
    setState(() {
      _data = data;
      _state = data == null
          ? _LyrState.notFound
          : data.source == 'error'
              ? _LyrState.netError
              : data.instrumental
                  ? _LyrState.instrumental
                  : data.synced
                      ? _LyrState.synced
                      : _LyrState.plain;
    });
  }

  void _onPosition(Duration pos) {
    final lines = _data?.lines;
    if (lines == null || _state != _LyrState.synced) return;
    final lead = pos + const Duration(milliseconds: 250);
    var idx = -1;
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].at <= lead) { idx = i; } else { break; }
    }
    if (idx != _active) {
      _active = idx;
      if (mounted) setState(() {});
      if (idx >= 0 && DateTime.now().isAfter(_userScrollUntil) && _scroll.hasClients) {
        final target = (idx * 44.0 - 160).clamp(0.0, _scroll.position.maxScrollExtent);
        _scroll.animateTo(target, duration: const Duration(milliseconds: 350), curve: Curves.easeOut);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final handler = ref.watch(audioHandlerProvider);
    final t = _track;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SizedBox(height: 10),
      Center(child: Container(width: 38, height: 4,
          decoration: BoxDecoration(color: ClaiColors.surface3, borderRadius: BorderRadius.circular(2)))),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(context.l10n.lyrTitle, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: ClaiColors.ink)),
          if (t != null)
            Text(context.l10n.lyrTrackLine(t.title, t.artistNames), maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: ClaiColors.inkSecondary, fontSize: 13)),
        ]),
      ),
      Expanded(child: switch (_state) {
        _LyrState.loading => const Center(child: CircularProgressIndicator(color: ClaiColors.accent)),
        _LyrState.noTrack => _message(ClaiIcons.lyrics, context.l10n.lyrNoTrack),
        _LyrState.instrumental => _message(ClaiIcons.musicNote, context.l10n.lyrInstrumental),
        _LyrState.notFound => _message(ClaiIcons.lyrics, context.l10n.lyrNotFound,
            retry: t == null ? null : () => _load(t, force: true)),
        _LyrState.netError => _message(ClaiIcons.wifiOff, context.l10n.lyrNetError,
            retry: t == null ? null : () => _load(t, force: true)),
        _LyrState.plain => _plainView(),
        _LyrState.synced => _syncedView(handler),
      }),
      if (_state == _LyrState.synced || _state == _LyrState.plain)
        Padding(padding: const EdgeInsets.fromLTRB(20, 6, 20, 12),
            child: Text(context.l10n.lyrSource,
                style: const TextStyle(color: ClaiColors.inkFaint, fontSize: 11.5))),
    ]);
  }

  Widget _message(ClaiIconData icon, String text, {VoidCallback? retry}) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ClaiIcon(icon, size: 40, color: ClaiColors.inkFaint),
            const SizedBox(height: 14),
            Text(text, textAlign: TextAlign.center,
                style: const TextStyle(color: ClaiColors.inkSecondary, fontSize: 14, height: 1.45)),
            if (retry != null) ...[
              const SizedBox(height: 12),
              TextButton(onPressed: retry, child: Text(context.l10n.commonRetry, style: const TextStyle(color: ClaiColors.accent))),
            ],
          ]),
        ),
      );

  Widget _plainView() {
    final plain = _data?.plain ?? '';
    return ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 24), children: [
      Padding(padding: const EdgeInsets.only(bottom: 10),
          child: Text(context.l10n.lyrPlainNote,
              style: const TextStyle(color: ClaiColors.inkFaint, fontSize: 12.5))),
      SelectableText(plain, style: const TextStyle(color: ClaiColors.ink, fontSize: 15.5, height: 1.65)),
    ]);
  }

  Widget _syncedView(ClaiAudioHandler handler) {
    final lines = _data?.lines ?? const <LyricsLine>[];
    return StreamBuilder<Duration>(
      stream: handler.positionStream,
      builder: (context, snap) {
        _onPosition(snap.data ?? Duration.zero);
        return NotificationListener<ScrollNotification>(
          onNotification: (n) {
            if (n is ScrollStartNotification && n.dragDetails != null) {
              _userScrollUntil = DateTime.now().add(const Duration(seconds: 4));
            }
            return false;
          },
          child: ListView.builder(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 40),
            itemCount: lines.length,
            itemBuilder: (context, i) {
              final line = lines[i];
              final active = i == _active;
              return InkWell(
                onTap: () => handler.seek(line.at),
                child: Container(
                  height: 44,
                  alignment: Alignment.centerLeft,
                  child: Text(line.text.isEmpty ? '· · ·' : line.text,
                      maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: active ? 17.5 : 15.5,
                        fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                        color: active ? ClaiColors.accent : ClaiColors.inkSecondary,
                        height: 1.3,
                      )),
                ),
              );
            },
          ),
        );
      },
    );
  }
}
