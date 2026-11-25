import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../app.dart';
import '../core/clai_icons.dart';
import '../data/app_db.dart';
import '../core/tokens.dart';
import '../l10n/l10n.dart';
import '../services/library_transfer.dart';
import 'widgets.dart';

/// Lembar Ekspor (Ronde 8070, D2 / F-12): satu berkas JSON berversi
/// berisi playlist + lagu disukai + riwayat OPSIONAL (saklar pengguna)
/// dibagikan lewat share sheet sistem; di bawahnya ekspor M3U per
/// playlist untuk aplikasi musik lain. Lembar PADAT (aturan kaca).

Future<void> openExportSheet(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet<void>(
    context: claiRootContext(context),
    isScrollControlled: true,
    backgroundColor: ClaiColors.surface1,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(ClaiRadius.sheet),
      ),
    ),
    builder: (_) => _ExportSheet(ref: ref),
  );
}

class _ExportSheet extends StatefulWidget {
  final WidgetRef ref;
  const _ExportSheet({required this.ref});

  @override
  State<_ExportSheet> createState() => _ExportSheetState();
}

class _ExportSheetState extends State<_ExportSheet> {
  bool _includeHistory = true;
  bool _busy = false;
  ({int playlists, int liked, int history})? _counts;
  List<Map<String, Object?>> _playlists = const [];

  @override
  void initState() {
    super.initState();
    final db = widget.ref.read(appDbProvider);
    db.libraryCounts().then((c) {
      if (mounted) setState(() => _counts = c);
    });
    db.playlists().then((rows) {
      if (mounted) {
        setState(
          () => _playlists = rows
              .where((r) => (r['is_system'] as int? ?? 0) == 0)
              .toList(),
        );
      }
    });
  }

  Future<void> _exportJson() async {
    final messenger = ScaffoldMessenger.of(claiRootContext(context));
    final failText = context.l10n.exportFailed;
    setState(() => _busy = true);
    try {
      final svc = widget.ref.read(libraryTransferProvider);
      final data = await svc.gatherExport(includeHistory: _includeHistory);
      final file = await svc.writeShareFile(
        exportFileName(DateTime.now()),
        jsonEncode(exportToJson(data)),
      );
      await SharePlus.instance.share(ShareParams(files: [XFile(file.path)]));
      // Ronde 8074: cap waktu ekspor penuh terakhir yang BERHASIL —
      // dibaca lembar Reset Selera sebagai "Cadangan terakhir" yang
      // jujur (bukan tebakan dari berkas ekspor yang mungkin tak ada).
      await widget.ref
          .read(appDbProvider)
          .setPref(
            AppDb.prefLastExportAt,
            DateTime.now().millisecondsSinceEpoch,
          );
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        setState(() => _busy = false);
        messenger.showSnackBar(SnackBar(content: Text(failText)));
      }
    }
  }

  Future<void> _exportM3u(String playlistId, String name) async {
    final messenger = ScaffoldMessenger.of(claiRootContext(context));
    final failText = context.l10n.exportFailed;
    try {
      final svc = widget.ref.read(libraryTransferProvider);
      final data = await svc.playlistData(playlistId);
      if (data == null) return;
      final file = await svc.writeShareFile(
        '${playlistFileSlug(name)}.m3u',
        buildM3u(data.tracks),
      );
      await SharePlus.instance.share(ShareParams(files: [XFile(file.path)]));
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(failText)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    final c = _counts;
    final isEmpty =
        c != null && c.playlists == 0 && c.liked == 0 && c.history == 0;
    return ClaiSheetScaffold(
      children: [
        const Padding(padding: EdgeInsets.only(top: 14), child: SheetHandle()),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(s.ownExportTitle, style: displayStyle(20)),
              const SizedBox(height: 6),
              Text(
                c == null
                    ? '…'
                    : [
                        s.ownPlaylistsCount(c.playlists),
                        s.ownLikedCount(c.liked),
                        s.ownHistoryCount(c.history),
                      ].join(' · '),
                style: const TextStyle(
                  color: ClaiColors.inkSecondary,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 10),
              // Ronde 8084: baris sakelar terkunci 60, label 15/600 —
              // exportIncludeHistorySub DIBUANG (§13.2).
              ListTile(
                contentPadding: EdgeInsets.zero,
                minTileHeight: 60,
                titleTextStyle: const TextStyle(
                  color: ClaiColors.ink,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
                leading: rowLeadIcon(ClaiIcons.history, size: 40, iconSize: 24),
                title: Text(
                  s.exportIncludeHistory,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: ClaiColors.ink,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                trailing: Switch(
                  value: _includeHistory,
                  onChanged: (v) => setState(() => _includeHistory = v),
                ),
              ),
              const SizedBox(height: 14),
              if (isEmpty)
                Text(
                  s.exportEmpty,
                  style: const TextStyle(
                    color: ClaiColors.inkSecondary,
                    fontSize: 14,
                  ),
                )
              else
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: ClaiColors.signal,
                    foregroundColor: ClaiColors.onSignal,
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(ClaiRadius.pill),
                    ),
                  ),
                  onPressed: _busy ? null : _exportJson,
                  child: Text(
                    s.exportAction,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              if (_playlists.isNotEmpty) ...[
                const SizedBox(height: 26),
                // Ronde 8083 (pola Kulit Baru): label seksi sentence-case
                // 13/600 — TANPA kicker kapital; baris-baris langsung di
                // permukaan lembar dipisah hairline, tanpa wadah tonal.
                Text(
                  s.exportM3uSection,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: ClaiColors.inkSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                for (var i = 0; i < _playlists.length; i++) ...[
                  if (i > 0)
                    const Divider(height: 1, color: ClaiColors.divider),
                  // Ronde 8084: baris M3U terkunci 60, judul 15/600
                  // (exportM3uSub di atas DIBUANG — §13.2).
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    minTileHeight: 60,
                    titleTextStyle: const TextStyle(
                      color: ClaiColors.ink,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                    leading: rowLeadIcon(
                      ClaiIcons.musicNote,
                      size: 40,
                      iconSize: 24,
                    ),
                    title: Text(
                      _playlists[i]['name'] as String,
                      style: const TextStyle(
                        color: ClaiColors.ink,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: ClaiIcon(
                      ClaiIcons.download,
                      color: ClaiColors.inkFaint,
                      size: 20,
                    ),
                    onTap: () => _exportM3u(
                      _playlists[i]['id'] as String,
                      _playlists[i]['name'] as String,
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ],
    );
  }
}
