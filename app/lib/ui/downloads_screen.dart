import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../app.dart';
import '../core/clai_icons.dart';
import '../core/tokens.dart';
import '../services/download_service.dart';
import 'widgets.dart';
import '../l10n/l10n.dart';

String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}

/// Kelola unduhan (F2 Batch 2; D-14): daftar unduhan dengan jeda/lanjut
/// per item & global, pemakaian + kuota, keadaan korup dengan unduh ulang.
class DownloadsScreen extends ConsumerWidget {
  const DownloadsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.dlTitle)),
      body: const DownloadsBody(),
    );
  }
}

/// Isi layar unduhan — dipakai juga sebagai tab Koleksi (tanpa AppBar sendiri).
class DownloadsBody extends ConsumerWidget {
  const DownloadsBody({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final svc = ref.watch(downloadServiceProvider);
    final handler = ref.watch(audioHandlerProvider);
    final items = svc.items;
    final anyActive = items.any((i) =>
        i.status == DownloadStatus.downloading || i.status == DownloadStatus.queued);
    final anyPaused = items.any((i) => i.status == DownloadStatus.paused);
    return items.isEmpty
          ? EmptyState(
              icon: ClaiIcons.download,
              message: context.l10n.dlEmpty,
            )
          : ListView(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Text(
                  context.l10n.dlFootnote,
                  style: const TextStyle(color: ClaiColors.inkSecondary, fontSize: 13, height: 1.4),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                child: Row(children: [
                  Expanded(child: Text(
                    context.l10n.dlUsageLine(formatBytes(svc.usedBytes)),
                    style: const TextStyle(color: ClaiColors.inkSecondary, fontSize: 13),
                  )),
                  if (anyActive)
                    TextButton(
                      onPressed: () => svc.pauseAll(),
                      child: Text(context.l10n.dlPauseAll, style: const TextStyle(color: ClaiColors.accent)),
                    ),
                  if (anyPaused)
                    TextButton(
                      onPressed: () => svc.resumeAll(),
                      child: Text(context.l10n.dlResumeAll, style: const TextStyle(color: ClaiColors.accent)),
                    ),
                ]),
              ),
              for (final item in items)
                switch (item.status) {
                  DownloadStatus.done => SongRow(
                      track: item.track,
                      trailing: IconButton(
                        icon: ClaiIcon(ClaiIcons.trash, color: ClaiColors.error),
                        onPressed: () => svc.deleteDownload(item.track.key),
                      ),
                      onTap: () => handler.playTracks(
                          [item.track], 0, kind: 'download', label: context.l10n.dlTitle),
                    ),
                  DownloadStatus.corrupt => ListTile(
                      leading: ClaiIcon(ClaiIcons.warning, color: ClaiColors.error),
                      title: Text(item.track.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: ClaiColors.ink)),
                      subtitle: Text(item.error ?? context.l10n.dlErrCorrupt,
                          style: const TextStyle(color: ClaiColors.error, fontSize: 13)),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        TextButton(
                          onPressed: () async {
                            await svc.deleteDownload(item.track.key);
                            await svc.download(item.track, handler.effectiveQuality);
                          },
                          child: Text(context.l10n.dlRedownload, style: const TextStyle(color: ClaiColors.accent)),
                        ),
                        IconButton(
                          icon: ClaiIcon(ClaiIcons.trash, color: ClaiColors.error),
                          onPressed: () => svc.deleteDownload(item.track.key),
                        ),
                      ]),
                    ),
                  DownloadStatus.failed => ListTile(
                      leading: ClaiIcon(ClaiIcons.cloudOff, color: ClaiColors.error),
                      title: Text(item.track.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: ClaiColors.ink)),
                      subtitle: Text(item.error ?? context.l10n.dlFailed,
                          style: const TextStyle(color: ClaiColors.inkSecondary, fontSize: 13)),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        TextButton(
                          onPressed: () => svc.download(item.track, handler.effectiveQuality),
                          child: Text(context.l10n.dlRetry, style: const TextStyle(color: ClaiColors.accent)),
                        ),
                        IconButton(
                          icon: ClaiIcon(ClaiIcons.trash, color: ClaiColors.error),
                          onPressed: () => svc.deleteDownload(item.track.key),
                        ),
                      ]),
                    ),
                  DownloadStatus.paused => ListTile(
                      leading: CoverArt(url: item.track.artworkUrl, size: 48, label: item.track.title),
                      title: Text(item.track.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: ClaiColors.ink)),
                      subtitle: Text(
                        item.bytesTotal != null && item.bytesTotal! > 0
                            ? context.l10n.dlPausedState(formatBytes(item.bytesDone), formatBytes(item.bytesTotal!))
                            : context.l10n.dlProgressDone(formatBytes(item.bytesDone)),
                        style: const TextStyle(color: ClaiColors.inkSecondary, fontSize: 13),
                      ),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        TextButton(
                          onPressed: () => svc.download(item.track, handler.effectiveQuality),
                          child: Text(context.l10n.dlResume, style: const TextStyle(color: ClaiColors.accent)),
                        ),
                        IconButton(
                          icon: ClaiIcon(ClaiIcons.trash, color: ClaiColors.error),
                          onPressed: () => svc.deleteDownload(item.track.key),
                        ),
                      ]),
                    ),
                  _ => ListTile(
                      leading: SizedBox(
                        width: 48,
                        height: 48,
                        child: Stack(alignment: Alignment.center, children: [
                          CoverArt(url: item.track.artworkUrl, size: 48, label: item.track.title),
                          if (item.status == DownloadStatus.downloading)
                            const SizedBox(
                              width: 26,
                              height: 26,
                              child: CircularProgressIndicator(strokeWidth: 2.5, color: ClaiColors.accent),
                            ),
                        ]),
                      ),
                      title: Text(item.track.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: ClaiColors.ink)),
                      subtitle: Text(
                        item.bytesTotal != null && item.bytesTotal! > 0
                            ? context.l10n.dlProgressOf(formatBytes(item.bytesDone), formatBytes(item.bytesTotal!))
                            : context.l10n.dlProgressDone(formatBytes(item.bytesDone)),
                        style: const TextStyle(color: ClaiColors.inkSecondary, fontSize: 13),
                      ),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        if (item.status == DownloadStatus.downloading)
                          TextButton(
                            onPressed: () => svc.pauseDownload(item.track.key),
                            child: Text(context.l10n.dlPause, style: const TextStyle(color: ClaiColors.accent)),
                          ),
                        IconButton(
                          icon: ClaiIcon(ClaiIcons.close, color: ClaiColors.inkSecondary),
                          onPressed: () => svc.cancelDownload(item.track.key),
                        ),
                      ]),
                    ),
                },
              const SizedBox(height: 32),
            ]);
  }
}
