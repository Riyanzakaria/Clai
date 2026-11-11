import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../app.dart';
import '../core/artwork.dart';
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

  /// Mosaik sampul kepala playlist: hingga 4 sampul berbeda dari trek
  /// pertama (pola yang sama seperti baris Koleksi); playlist tanpa
  /// sampul → ubin ikon antrean di surface-2.
  Widget _mosaic(List<Track> tracks) {
    final filled = <String>[];
    for (final t in tracks) {
      final u = t.artworkUrl;
      if (u != null && u.isNotEmpty && !filled.contains(u)) filled.add(u);
      if (filled.length >= 4) break;
    }
    if (filled.isEmpty) {
      return Container(width: 72, height: 72, decoration: BoxDecoration(color: ClaiColors.surface2, borderRadius: BorderRadius.circular(12)),
          child: ClaiIcon(ClaiIcons.queue, color: ClaiColors.inkFaint));
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(width: 72, height: 72, child: GridView.count(crossAxisCount: 2, physics: const NeverScrollableScrollPhysics(), children: [
        for (var i = 0; i < 4; i++)
          Image.network(artworkUrlForSize(filled[i % filled.length], 200)!, fit: BoxFit.cover, cacheWidth: 128, errorBuilder: (_, __, ___) => Container(color: ClaiColors.surface3)),
      ])),
    );
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
              final name = await promptText(
                context,
                context.l10n.plNewName,
                initialValue: widget.name,
              );
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
      // Audit 8047 (§7.4): kepala ringkas tampil juga saat playlist
      // KOSONG — dulu keadaan kosong hanya AppBar + EmptyState polos,
      // nama playlist tak terbaca sebagai kepala halaman.
      body: Column(children: [
                  // Kepala playlist (Kampanye Rombak UI Total, Batch 4):
                  // mosaik sampul 72 + nama display + hitungan lagu —
                  // pola kepala halaman yang sama seperti baris Koleksi
                  // & halaman konten. Hitungan pindah ke sini dari baris
                  // Putar di bawahnya; perilaku tidak berubah.
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
                    child: Row(children: [
                      _mosaic(_tracks),
                      const SizedBox(width: 14),
                      Expanded(child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(widget.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: displayStyle(19)),
                          const SizedBox(height: 3),
                          Text(context.l10n.songCount(_tracks.length), style: const TextStyle(color: ClaiColors.inkSecondary, fontSize: 13)),
                        ],
                      )),
                    ]),
                  ),
                  if (!_loading && _tracks.isNotEmpty) ...[
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
                    ]),
                  ),
                  ],
                  Expanded(child: _loading
                      ? const LoadingSkeleton()
                      : _tracks.isEmpty
                          ? EmptyState(icon: ClaiIcons.queue, message: context.l10n.plEmpty)
                          : ReorderableListView(
                    // Butir 4: daftar kini hidup di bawah chrome melayang
                    // cangkang — baris terakhir wajib bisa keluar dari
                    // balik gugus mini player + nav.
                    padding: EdgeInsets.only(bottom: bottomChromeClearance(context)),
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
                              ScaffoldMessenger.of(context).showSnackBar(claiSnackAboveChrome(
                                context,
                                context.l10n.plRemovedSnack(removed.title),
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
