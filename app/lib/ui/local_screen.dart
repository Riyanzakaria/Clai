import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../app.dart';
import '../core/clai_icons.dart';
import '../core/tokens.dart';
import '../domain/models.dart';
import '../l10n/l10n.dart';
import 'widgets.dart';

/// File Lokal (PRD 5.6 / F-11 Phase 2): izin diminta saat fitur dibuka, bukan saat instal.
class LocalFilesBody extends ConsumerStatefulWidget {
  const LocalFilesBody({super.key});
  @override
  ConsumerState<LocalFilesBody> createState() => _LocalFilesBodyState();
}

class _LocalFilesBodyState extends ConsumerState<LocalFilesBody> {
  List<Track>? _tracks;
  bool _loading = false;
  bool _denied = false;

  Future<void> _scan() async {
    setState(() { _loading = true; _denied = false; });
    final svc = ref.read(localFilesProvider);
    final ok = await svc.ensurePermission();
    if (!ok) {
      if (mounted) setState(() { _loading = false; _denied = true; });
      return;
    }
    final tracks = await svc.scan();
    if (mounted) setState(() { _tracks = tracks; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    final handler = ref.watch(audioHandlerProvider);
    if (_denied) {
      return EmptyState(icon: ClaiIcons.folderOff, message: context.l10n.localDenied,
          actionLabel: context.l10n.commonRetry, onAction: _scan);
    }
    if (_tracks == null) {
      return EmptyState(icon: ClaiIcons.folder, message: context.l10n.localSub,
          actionLabel: context.l10n.localScan, onAction: _scan);
    }
    if (_loading) return const LoadingSkeleton();
    if (_tracks!.isEmpty) {
      return EmptyState(icon: ClaiIcons.folder, message: context.l10n.localNone,
          actionLabel: context.l10n.localRescan, onAction: _scan);
    }
    final tracks = _tracks!;
    return ListView(children: [
      Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Text(context.l10n.localCount(tracks.length), style: const TextStyle(color: ClaiColors.inkSecondary, fontSize: 13))),
      for (final t in tracks)
        SongRow(track: t, onTap: () => handler.playTracks(tracks, tracks.indexOf(t), kind: 'local', label: context.l10n.localTitle)),
    ]);
  }
}
