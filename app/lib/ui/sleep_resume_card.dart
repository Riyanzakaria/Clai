import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app.dart';
import '../core/clai_icons.dart';
import '../core/tokens.dart';
import '../l10n/l10n.dart';
import '../domain/models.dart';

String _fmtPos(int ms) {
  final d = Duration(milliseconds: ms);
  final m = d.inMinutes;
  final s = d.inSeconds % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}

/// Batas umur simpanan Lanjut Besok (USER-FLOW F-10, Sapuan D-15): simpanan
/// lebih tua dari 48 jam kedaluwarsa — dihapus, kartu tidak tampil.
const sleepSaveMaxAge = Duration(hours: 48);

/// Murni (diuji unit): apakah simpanan pada [savedAtMs] masih berlaku pada [nowMs]?
bool sleepSaveValid(int savedAtMs, int nowMs) =>
    savedAtMs > 0 && nowMs - savedAtMs <= sleepSaveMaxAge.inMilliseconds && savedAtMs <= nowMs;

/// Kartu "Lanjutkan dari semalam" (F2 Batch 2; D-15): muncul bila timer
/// tidur pernah berbunyi & menyimpan snapshot. Ketuk → SESI semalam
/// dipulihkan penuh (konteks + antrean + posisi) dan diputar. Tombol ✕
/// menghapus simpanan tanpa memutar.
class SleepResumeCard extends ConsumerStatefulWidget {
  const SleepResumeCard({super.key});
  @override
  ConsumerState<SleepResumeCard> createState() => _SleepResumeCardState();
}

class _SleepResumeCardState extends ConsumerState<SleepResumeCard> {
  Map<String, Object?>? _saved;
  String _title = '';
  String _artist = '';
  int _posMs = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = ref.read(appDbProvider);
    final raw = await db.pref<String>('sleep.last');
    if (raw == null) return;
    try {
      final m = jsonDecode(raw) as Map<String, Object?>;
      final savedAt = (m['savedAt'] as num?)?.toInt() ?? 0;
      if (!sleepSaveValid(savedAt, DateTime.now().millisecondsSinceEpoch)) {
        // D-15: simpanan kedaluwarsa dibuang, bukan ditawarkan basi.
        await db.setPref('sleep.last', null);
        return;
      }
      final snap = m['snapshot'];
      if (snap is Map) {
        _posMs = (snap['positionMs'] as num?)?.toInt() ?? 0;
        final cur = snap['currentRef'] as String?;
        if (cur != null && cur.contains('|')) {
          final parts = cur.split('|');
          final t = await db.trackByKey(
              TrackKey(parts[0], parts.sublist(1).join('|')));
          if (t != null) {
            _title = t.title;
            _artist = t.artistNames;
          }
        }
        _title = _title.isEmpty ? (snap['contextLabel'] as String? ?? '') : _title;
      } else {
        _title = '${m['title'] ?? ''}';
        _artist = '${m['artistNames'] ?? ''}';
        _posMs = (m['positionMs'] as num?)?.toInt() ?? 0;
      }
      if (mounted) setState(() => _saved = m);
    } catch (_) {/* simpanan rusak: kartu tidak tampil */}
  }

  Future<void> _dismiss() async {
    await ref.read(appDbProvider).setPref('sleep.last', null);
    if (mounted) setState(() => _saved = null);
  }

  Future<void> _resume() async {
    final s = _saved;
    if (s == null) return;
    final sleep = ref.read(sleepServiceProvider);
    sleep.resuming = true;
    final snap = s['snapshot'];
    if (snap is Map) {
      // D-15: pulihkan snapshot antrean penuh lewat handler.
      await ref
          .read(audioHandlerProvider)
          .restoreSleepSession(snap.cast<String, Object?>());
    } else {
      // Simpanan format lama (satu lagu + posisi) dari build sebelum sapuan.
      final track = Track(
        key: TrackKey('${s['providerId']}', '${s['id']}'),
        title: '${s['title']}',
        artistNames: '${s['artistNames']}',
        playableRef: '${s['playableRef']}',
      );
      final pos = Duration(milliseconds: (s['positionMs'] as num?)?.toInt() ?? 0);
      await ref
          .read(audioHandlerProvider)
          .playTracks([track], 0, kind: 'search', label: l10n.sleepContextLabel);
      if (pos > Duration.zero) {
        await ref.read(audioHandlerProvider).seek(pos);
      }
    }
    await _dismiss();
  }

  @override
  Widget build(BuildContext context) {
    final s = _saved;
    if (s == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: ClaiColors.surface2,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: ClaiColors.accent.withValues(alpha: 0.35))),
        child: Row(children: [
          ClaiIcon(ClaiIcons.moon, color: ClaiColors.accent),
          const SizedBox(width: 10),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(context.l10n.sleepCardTitle,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, color: ClaiColors.ink)),
                const SizedBox(height: 2),
                Text(
                    context.l10n.sleepCardSub(_artist, _fmtPos(_posMs), _title),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: ClaiColors.inkSecondary, fontSize: 13)),
              ])),
          TextButton(
              onPressed: _resume,
              child: Text(context.l10n.sleepCardResume,
                  style: const TextStyle(color: ClaiColors.accent))),
          IconButton(
              icon: ClaiIcon(ClaiIcons.close, color: ClaiColors.inkFaint),
              onPressed: _dismiss),
        ]),
      ),
    );
  }
}
