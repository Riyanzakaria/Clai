import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../app.dart';
import '../core/clai_icons.dart';
import '../core/tokens.dart';
import '../domain/models.dart';
import '../l10n/l10n.dart';
import 'widgets.dart';

/// Playlist milik pengguna (PRD 5.7): susun ulang seret, hapus geser + urungkan, ganti nama, hapus.
class PlaylistScreen extends ConsumerStatefulWidget {
  final String playlistId;
  final String name;
  const PlaylistScreen({super.key, required this.playlistId, required this.name});
  @override
  ConsumerState<PlaylistScreen> createState() => _PlaylistScreenState();
}

class _PlaylistScreenState extends ConsumerState<PlaylistScreen> {
  List<Track> _tracks = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final tracks = await ref.read(appDbProvider).playlistTracks(widget.playlistId);
    if (mounted) setState(() { _tracks = tracks; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    final handler = ref.watch(audioHandlerProvider);
    final lib = ref.read(libraryProvider);
    return Scaffold(
      appBar: AppBar(title: Text(widget.name), actions: [
        PopupMenuButton<String>(
          color: ClaiColors.surface2,
          onSelected: (v) async {
            if (v == 'rename') {
              final name = await promptText(context, context.l10n.plNewName);
              if (name != null && name.trim().isNotEmpty) {
                await lib.renamePlaylist(widget.playlistId, name.trim());
                if (context.mounted) Navigator.of(context).pop();
              }
            }
            if (v == 'delete') {
              final ok = await showDialog<bool>(context: context, builder: (d) => AlertDialog(
                    backgroundColor: ClaiColors.surface2,
                    title: Text(context.l10n.plDeleteTitle, style: const TextStyle(color: ClaiColors.ink)),
                    content: Text(context.l10n.plDeleteBody, style: const TextStyle(color: ClaiColors.inkSecondary)),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(d, false), child: Text(context.l10n.commonCancel)),
                      TextButton(onPressed: () => Navigator.pop(d, true), child: Text(context.l10n.commonDelete, style: const TextStyle(color: ClaiColors.error))),
                    ]));
              if (ok == true) {
                await lib.deletePlaylist(widget.playlistId);
                if (context.mounted) Navigator.of(context).pop();
              }
            }
          },
          itemBuilder: (_) => [
            PopupMenuItem(value: 'rename', child: Text(context.l10n.plRename)),
            PopupMenuItem(value: 'delete', child: Text(context.l10n.plDelete)),
          ],
        ),
      ]),
      body: _loading
          ? const LoadingSkeleton()
          : _tracks.isEmpty
              ? EmptyState(icon: ClaiIcons.queue, message: context.l10n.plEmpty)
              : Column(children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
                    child: Row(children: [
                      PressableScale(
                        child: GestureDetector(
                          onTap: () => handler.playTracks(_tracks, 0, kind: 'userPlaylist', id: widget.playlistId, label: widget.name),
                          child: Container(width: 48, height: 48, decoration: const BoxDecoration(color: ClaiColors.accent, shape: BoxShape.circle),
                              child: ClaiIcon(ClaiIcons.play, color: ClaiColors.onAccent, size: 26)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(context.l10n.songCount(_tracks.length), style: const TextStyle(color: ClaiColors.inkSecondary)),
                    ]),
                  ),
                  Expanded(child: ReorderableListView(
                    buildDefaultDragHandles: false,
                    onReorder: (o, n) async {
                      final to = n > o ? n - 1 : n;
                      await lib.moveInPlaylist(widget.playlistId, o, to);
                      _load();
                    },
                    children: [
                      for (var i = 0; i < _tracks.length; i++)
                        Dismissible(
                          key: ValueKey('pl_${_tracks[i].providerId}_${_tracks[i].id}_$i'),
                          direction: DismissDirection.endToStart,
                          background: Container(color: ClaiColors.error, alignment: Alignment.centerRight,
                              padding: const EdgeInsets.only(right: 20), child: ClaiIcon(ClaiIcons.trash, color: Colors.white)),
                          onDismissed: (_) async {
                            final removed = _tracks[i];
                            await lib.removeFromPlaylistAt(widget.playlistId, i);
                            _load();
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                content: Text(context.l10n.plRemovedSnack(removed.title)),
                                action: SnackBarAction(label: context.l10n.commonUndo, onPressed: () async {
                                  await lib.addToPlaylist(widget.playlistId, removed, allowDuplicate: true);
                                  _load();
                                }),
                              ));
                            }
                          },
                          // Listener seret HANYA di pegangan (pola queue_screen):
                          // membungkus seluruh baris menelan gestur geser
                          // horizontal Dismissible — trek tak bisa dihapus
                          // geser (temuan audit v4.4).
                          child: SongRow(track: _tracks[i],
                              trailing: ReorderableDragStartListener(
                                index: i,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
                                  child: ClaiIcon(ClaiIcons.dragHandle, color: ClaiColors.inkFaint, size: 20),
                                ),
                              ),
                              onTap: () => handler.playTracks(_tracks, i, kind: 'userPlaylist', id: widget.playlistId, label: widget.name)),
                        ),
                    ],
                  )),
                ]),
    );
  }
}
