import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../app.dart';
import '../core/clai_icons.dart';
import '../core/tokens.dart';
import '../domain/models.dart';
import '../l10n/l10n.dart';
import '../player/queue_engine.dart' as qe;
import 'widgets.dart';

/// Daftar satu seksi antrean yang bisa diurut-ulang (putaran v4, cacat 3).
///
/// Pola yang benar: [ReorderableDragStartListener] membungkus HANYA pegangan ≡ yang
/// diberikan ke [rowBuilder] — bukan seluruh baris. Versi lama membungkus seluruh baris,
/// sehingga geser vertikal apa pun pada badan baris memulai seret-urut dan daftar tidak
/// bisa digulir. Kini: geser pada badan baris = gulir normal (daftar luar), seret pada
/// pegangan = urut-ulang. Geser horizontal tetap menghapus (Dismissible).
class QueueSectionList extends StatelessWidget {
  /// Nama seksi di handler ('manual' | 'continuation') — dipakai untuk kunci baris.
  final String section;

  /// Item yang tampil (sudah disaring layar) dan indeks engine asalnya, sejajar.
  final List<Track> items;
  final List<int> itemIndices;

  /// Membangun isi baris; [dragHandle] WAJIB ditempatkan pembangun (di kanan baris).
  /// [engineIndex] = indeks asal item di seksi engine-nya (untuk menu konteks).
  final Widget Function(BuildContext context, Track track, int engineIndex, Widget dragHandle) rowBuilder;

  /// Indeks engine asal & tujuan akhir (onReorderItem sudah memberi indeks final).
  final void Function(int fromIndex, int toIndex) onReorder;
  final void Function(int index, Track track) onDismissed;

  const QueueSectionList({
    super.key,
    required this.section,
    required this.items,
    required this.itemIndices,
    required this.rowBuilder,
    required this.onReorder,
    required this.onDismissed,
  });

  @override
  Widget build(BuildContext context) {
    return ReorderableListView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      onReorderItem: (o, n) {
        if (n != o) onReorder(itemIndices[o], itemIndices[n]);
      },
      children: [
        for (var pos = 0; pos < items.length; pos++)
          Dismissible(
            key: ValueKey('${section}_${items[pos].providerId}_${items[pos].id}_${itemIndices[pos]}'),
            direction: DismissDirection.endToStart,
            background: Container(
                color: ClaiColors.error,
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 20),
                child: ClaiIcon(ClaiIcons.trash, color: Colors.white)),
            onDismissed: (_) => onDismissed(itemIndices[pos], items[pos]),
            child: rowBuilder(
              context,
              items[pos],
              itemIndices[pos],
              ReorderableDragStartListener(
                index: pos,
                child: ClaiIcon(ClaiIcons.dragHandle, color: ClaiColors.inkFaint, size: 20),
              ),
            ),
          ),
      ],
    );
  }
}

/// Layar Antrian (DS 6.10 v3.1): ringkasan skala, saring > 50 trek, empat seksi selalu terpisah & berlabel asal.
class QueueScreen extends ConsumerStatefulWidget {
  const QueueScreen({super.key});
  @override
  ConsumerState<QueueScreen> createState() => _QueueScreenState();
}

class _QueueScreenState extends ConsumerState<QueueScreen> {
  String _filter = '';

  /// Messenger LOKAL layar Antrian (cacat v4.4.2-3): SnackBar "Urungkan"
  /// yang ditampilkan lewat messenger akar — dari halaman yang didorong di
  /// atas sheet modal — terbukti menggantung permanen di emulator
  /// (terlihat > 2 menit, hanya hilang diusap manual; laporan pemilik sama).
  /// Messenger lokal mengikat SnackBar ke Scaffold halaman ini sendiri.
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();
  Timer? _snackTimer;
  ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? _snackController;

  @override
  void dispose() {
    _snackTimer?.cancel();
    super.dispose();
  }

  void _closeUndoSnack() {
    _snackTimer?.cancel();
    _snackTimer = null;
    final c = _snackController;
    _snackController = null;
    c?.close();
  }

  void _showUndoSnack(String section, int index, Track t) {
    final handler = ref.read(audioHandlerProvider);
    final messenger = _messengerKey.currentState;
    if (messenger == null) return;
    _closeUndoSnack();
    messenger.hideCurrentSnackBar(); // ganti, jangan menumpuk
    _snackController = messenger.showSnackBar(SnackBar(
      content: Text(l10n.queueRemovedSnack(t.title)),
      duration: const Duration(seconds: 5),
      action: SnackBarAction(label: l10n.commonUndo, onPressed: () {
        _closeUndoSnack();
        handler.insertInQueue(section, index, t);
      }),
    ));
    final mine = _snackController!;
    mine.closed.then((_) { if (identical(_snackController, mine)) _snackController = null; });
    // Jaminan tutup-otomatis: timer bawaan SnackBar pada permukaan ini
    // terbukti tidak berjalan — tutup eksplisit dengan timer sendiri
    // (timer Dart tidak bergantung rantai animasi/vsync permukaan).
    _snackTimer = Timer(const Duration(seconds: 5), _closeUndoSnack);
  }

  Future<void> _onRemoved(String section, int index, Track t) async {
    // Tampilkan umpan balik SEKETIKA pada gestur — jangan menunggu rebuild
    // ekor antrean selesai (jalur lama: SnackBar baru muncul detik-detik
    // kemudian, setelah baris lama hilang tanpa penjelasan).
    _showUndoSnack(section, index, t);
    await ref.read(audioHandlerProvider).removeFromQueue(section, index);
  }

  // ---------- Mode pilih-banyak (Ronde Tambahan 2015, Butir 2) ----------
  // Seleksi diikat ke KUNCI trek per seksi (bukan indeks): urut-ulang oleh
  // Smart Shuffle / isi-ulang Putar Otomatis tidak menggeser identitas
  // pilihan. Trek yang sedang diputar TIDAK termasuk alam seleksi (tidak
  // tinggal di seksi mana pun) — ia tak bisa dipilih untuk dihapus.
  bool _selecting = false;
  final Map<String, Set<TrackKey>> _selected = {
    'manual': {},
    'continuation': {},
    'autoplay': {},
  };

  int get _selectedCount =>
      _selected.values.fold(0, (a, s) => a + s.length);

  bool _isSelected(String section, Track t) =>
      _selected[section]?.contains(t.key) ?? false;

  void _toggleSelected(String section, Track t) {
    setState(() {
      final set = _selected[section]!;
      if (!set.add(t.key)) set.remove(t.key);
    });
  }

  void _enterSelection(String section, Track t) {
    setState(() {
      _selecting = true;
      _selected[section]!.add(t.key);
    });
  }

  void _exitSelection() {
    setState(() {
      _selecting = false;
      for (final s in _selected.values) {
        s.clear();
      }
    });
  }

  void _selectAll(qe.QueueEngine engine) {
    setState(() {
      _selected['manual']!.addAll(engine.manual.map((t) => t.key));
      _selected['continuation']!
          .addAll(engine.continuation.map((t) => t.key));
      _selected['autoplay']!.addAll(engine.autoplay.map((t) => t.key));
    });
  }

  /// Trek terpilih dalam urutan putar efektif (Berikutnya → Lanjutan →
  /// Putar Otomatis, urutan daftar masing-masing) untuk aksi massal.
  List<Track> _selectedTracksInOrder(qe.QueueEngine engine) {
    List<Track> pick(List<Track> list, String section) =>
        [for (final t in list) if (_isSelected(section, t)) t];
    return [
      ...pick(engine.manual, 'manual'),
      ...pick(engine.continuation, 'continuation'),
      ...pick(engine.autoplay, 'autoplay'),
    ];
  }

  /// SnackBar lewat messenger LOKAL layar ini (alasan yang sama seperti
  /// _showUndoSnack: messenger akar terbukti menggantung di permukaan ini).
  void _showLocalSnack(String message) {
    final messenger = _messengerKey.currentState;
    if (messenger == null) return;
    _closeUndoSnack();
    messenger.hideCurrentSnackBar();
    _snackController = messenger.showSnackBar(SnackBar(
      content: Text(message),
      duration: const Duration(seconds: 4),
    ));
    final mine = _snackController!;
    mine.closed.then((_) {
      if (identical(_snackController, mine)) _snackController = null;
    });
    _snackTimer = Timer(const Duration(seconds: 4), _closeUndoSnack);
  }

  /// Menu konteks PENUH untuk item lanjutan (Ronde Tambahan 2015,
  /// Butir 3): lembar yang sama seperti di semua layar, bertindak atas
  /// ITEM itu — dengan "Putar Berikutnya"/"Tambah ke Antrian" berwujud
  /// PINDAH (item sudah di antrean; tanpa duplikat) dan "Hapus dari
  /// Antrian" yang sama seperti geser-hapus (dengan Urungkan).
  void _openItemMenu(String section, int index, Track t) {
    final handler = ref.read(audioHandlerProvider);
    showTrackContextSheet(
      context,
      ref,
      t,
      fromQueue: true,
      onRemoveFromQueue: () => _onRemoved(section, index, t),
      onPlayNextOverride: () =>
          handler.playNextQueued(section, index, t.key),
      onAddToQueueOverride: () =>
          handler.sendQueuedToEnd(section, index, t.key),
    );
  }

  Future<void> _bulkRemove() async {
    final handler = ref.read(audioHandlerProvider);
    final removed = await handler.removeManyFromQueue(
      manual: Set.of(_selected['manual']!),
      continuation: Set.of(_selected['continuation']!),
      autoplay: Set.of(_selected['autoplay']!),
    );
    if (!mounted) return;
    _exitSelection();
    _showLocalSnack(l10n.bulkRemovedFromQueue(removed));
  }

  Future<void> _bulkSave() async {
    final engine = ref.read(audioHandlerProvider).engine;
    final tracks = _selectedTracksInOrder(engine);
    final n = await ref.read(libraryProvider).saveAllToCollection(tracks);
    if (!mounted) return;
    _exitSelection();
    _showLocalSnack(n > 0 ? l10n.bulkSaved(n) : l10n.bulkSavedNone);
  }

  Future<void> _bulkPlaylist() async {
    final engine = ref.read(audioHandlerProvider).engine;
    final tracks = _selectedTracksInOrder(engine);
    final acted = await showAddTracksToPlaylistSheet(
      context,
      ref,
      tracks,
      onFeedback: _showLocalSnack,
    );
    if (acted && mounted) _exitSelection();
  }

  @override
  Widget build(BuildContext context) {
    final handler = ref.watch(audioHandlerProvider);
    final engine = handler.engine;
    return ScaffoldMessenger(
      key: _messengerKey,
      child: Scaffold(
      appBar: _selecting
          ? AppBar(
              leading: IconButton(
                icon: ClaiIcon(ClaiIcons.close),
                tooltip: context.l10n.a11yClose,
                onPressed: _exitSelection,
              ),
              title: Text(context.l10n.queueSelectedCount(_selectedCount)),
              actions: [
                TextButton(
                  onPressed: () {
                    final all = _selectedCount >=
                        engine.effectiveQueue.length;
                    if (all) {
                      setState(() {
                        for (final s in _selected.values) {
                          s.clear();
                        }
                      });
                    } else {
                      _selectAll(engine);
                    }
                  },
                  child: Text(
                    _selectedCount >= engine.effectiveQueue.length
                        ? context.l10n.queueUnselectAll
                        : context.l10n.queueSelectAll,
                    style: const TextStyle(color: ClaiColors.accent),
                  ),
                ),
              ],
            )
          : AppBar(
              title: Text(context.l10n.queueTitle),
              actions: [
                TextButton(
                  onPressed: engine.effectiveQueue.isEmpty
                      ? null
                      : () => setState(() => _selecting = true),
                  child: Text(
                    context.l10n.queueSelect,
                    style: TextStyle(
                      color: engine.effectiveQueue.isEmpty
                          ? ClaiColors.inkFaint
                          : ClaiColors.accent,
                    ),
                  ),
                ),
                IconButton(icon: ClaiIcon(ClaiIcons.clearAll), tooltip: context.l10n.queueClear,
                    onPressed: engine.effectiveQueue.isEmpty ? null : () => handler.clearQueue()),
                IconButton(icon: ClaiIcon(ClaiIcons.close), tooltip: context.l10n.a11yClose, onPressed: () => Navigator.of(context).pop()),
              ],
            ),
      bottomNavigationBar: _selecting
          ? SafeArea(
              child: Container(
                decoration: const BoxDecoration(
                  border: Border(
                    top: BorderSide(color: ClaiColors.divider),
                  ),
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: _BulkAction(
                        icon: ClaiIcons.trash,
                        // Audit UX 2017: label tampak PENDEK khusus massal —
                        // label konteks penuh ("Tambahkan ke Playlist",
                        // 22 huruf pada 11px di sepertiga lebar 360dp)
                        // pasti terpotong elipsis; label semantik tetap
                        // memakai kalimat utuh untuk pembaca layar.
                        label: context.l10n.queueBulkRemove,
                        semanticLabel: context.l10n.ctxRemoveFromQueue,
                        color: ClaiColors.error,
                        onTap: _selectedCount == 0 ? null : _bulkRemove,
                      ),
                    ),
                    Expanded(
                      child: _BulkAction(
                        icon: ClaiIcons.playlistAdd,
                        label: context.l10n.queueBulkPlaylist,
                        semanticLabel: context.l10n.ctxAddToPlaylist,
                        onTap: _selectedCount == 0 ? null : _bulkPlaylist,
                      ),
                    ),
                    Expanded(
                      child: _BulkAction(
                        icon: ClaiIcons.heart,
                        label: context.l10n.queueBulkSave,
                        semanticLabel: context.l10n.ctxSaveToCollection,
                        onTap: _selectedCount == 0 ? null : _bulkSave,
                      ),
                    ),
                  ],
                ),
              ),
            )
          : null,
      body: StreamBuilder(
        stream: handler.queueStream,
        initialData: engine,
        builder: (context, _) {
          final full = engine.fullQueue;
          if (engine.current == null) {
            return EmptyState(icon: ClaiIcons.queue, message: context.l10n.queueEmpty);
          }
          final totalDur = full.fold<Duration>(Duration.zero, (a, t) => a + (t.duration ?? Duration.zero));
          // Kejujuran header (v4): "0:00 total" menipu bila durasi sumber memang kosong.
          // Tampilkan total hanya dari durasi yang diketahui; "+" = sebagian belum diketahui.
          final knownDur = full.where((t) => t.duration != null).length;
          final summary = knownDur == 0
              ? context.l10n.queueCountLine(full.length)
              : context.l10n.queueCountLineDur(full.length, formatDuration(totalDur), knownDur < full.length ? context.l10n.queueTotalPart('+') : '');
          bool match(Track t) => _filter.isEmpty ||
              t.title.toLowerCase().contains(_filter) || t.artistNames.toLowerCase().contains(_filter);
          List<int> visibleIdx(List<Track> section) =>
              [for (var i = 0; i < section.length; i++) if (match(section[i])) i];
          Widget sectionHeader(String label, {Widget? trailing}) => Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
                child: Row(children: [
                  Expanded(child: Text(label.toUpperCase(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: .6, color: ClaiColors.inkFaint))),
                  if (trailing != null) trailing,
                ]),
              );
          // Satu baris item lanjutan, sadar mode:
          // - normal: ketuk = lompat putar; ⋮ = menu konteks penuh atas
          //   item itu (Butir 3); tekan-lama = masuk mode pilih (Butir 2);
          //   trailing per seksi (gagang seret / lencana AUTO) dari
          //   pemanggil lewat [trail].
          // - pilih: ketuk = alih centang; ⋮ dan gagang disembunyikan
          //   agar ketukan murni untuk memilih (Butir 3c).
          Widget queueRow(String section, int index, Track t,
              {Widget? trail, bool auto = false}) {
            if (_selecting) {
              return SongRow(
                track: t,
                showMenu: false,
                selected: _isSelected(section, t),
                onTap: () => _toggleSelected(section, t),
                trailing: auto
                    ? Text(context.l10n.queueAutoBadge,
                        style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: ClaiColors.accent))
                    : null,
              );
            }
            return SongRow(
              track: t,
              showMenu: true,
              onTap: () => handler.jumpTo(t.key),
              onLongPress: () => _enterSelection(section, t),
              onMenuPressed: () => _openItemMenu(section, index, t),
              trailing: trail,
            );
          }

          Widget sectionList(String section, List<Track> tracks) {
            final idxs = visibleIdx(tracks);
            if (_selecting) {
              return Column(children: [
                for (final i in idxs) queueRow(section, i, tracks[i]),
              ]);
            }
            return QueueSectionList(
              section: section,
              items: [for (final i in idxs) tracks[i]],
              itemIndices: idxs,
              rowBuilder: (ctx, t, engineIndex, handle) => queueRow(
                section,
                engineIndex,
                t,
                trail: handle,
              ),
              onReorder: (o, n) => handler.moveInQueue(section, o, n),
              onDismissed: (index, t) => _onRemoved(section, index, t),
            );
          }

          Widget dismissibleRow(String section, Track t, int index, {bool auto = false}) {
            if (_selecting) return queueRow(section, index, t, auto: auto);
            final row = queueRow(
              section,
              index,
              t,
              auto: auto,
              trail: auto
                  ? Text(context.l10n.queueAutoBadge, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: ClaiColors.accent))
                  : ClaiIcon(ClaiIcons.dragHandle, color: ClaiColors.inkFaint, size: 20),
            );
            return Dismissible(
              key: ValueKey('${section}_${t.providerId}_${t.id}_$index'),
              direction: DismissDirection.endToStart,
              background: Container(color: ClaiColors.error, alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 20), child: ClaiIcon(ClaiIcons.trash, color: Colors.white)),
              onDismissed: (_) => _onRemoved(section, index, t),
              child: row,
            );
          }

          return ListView(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Text(summary,
                  style: const TextStyle(fontSize: 13, color: ClaiColors.inkSecondary, fontFeatures: [FontFeature.tabularFigures()])),
            ),
            // Smart Shuffle (F2): hanya mengurut ulang Lanjutan — tidak menambah lagu.
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(children: [
                Expanded(child: Text(
                    context.l10n.queueSmartShuffleNote,
                    style: const TextStyle(fontSize: 13, color: ClaiColors.inkSecondary, height: 1.4))),
                Switch(
                  value: engine.shuffle == qe.ShuffleMode.smart,
                  activeThumbColor: ClaiColors.accent,
                  onChanged: (v) => handler.setSmartShuffle(v),
                ),
              ]),
            ),
            if (full.length > 50)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: TextField(
                  decoration: InputDecoration(hintText: context.l10n.queueFilterHint, prefixIcon: ClaiIcon(ClaiIcons.search),
                      filled: true, fillColor: ClaiColors.surface1, border: const OutlineInputBorder(borderSide: BorderSide.none, borderRadius: BorderRadius.all(Radius.circular(10)))),
                  onChanged: (v) => setState(() => _filter = v.trim().toLowerCase()),
                ),
              ),
            sectionHeader(context.l10n.queueNowPlaying),
            SongRow(track: engine.current!, showMenu: true),
            if (engine.manual.isNotEmpty) ...[
              sectionHeader(context.l10n.queueUpNext),
              sectionList('manual', engine.manual),
            ],
            if (engine.continuation.isNotEmpty) ...[
              sectionHeader(context.l10n.queueContinuation(engine.context?.label ?? context.l10n.queueContextFallback)),
              sectionList('continuation', engine.continuation),
            ],
            sectionHeader(context.l10n.queueAutoplayHeader(engine.seeds.isNotEmpty ? engine.seeds.first.title : (engine.current?.title ?? '')),
                trailing: Switch(
                  value: engine.autoplaySessionOn,
                  activeThumbColor: ClaiColors.accent,
                  onChanged: (v) => handler.setAutoplaySession(v),
                )),
            if (!engine.autoplayEnabled)
              Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Text(context.l10n.queueAutoplayOff, style: const TextStyle(fontSize: 13, color: ClaiColors.inkFaint))),
            // L-11: label offline jujur pada seksi Putar Otomatis (DS 6.10).
            if (handler.offlineMode)
              Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Text(context.l10n.queueAutoplayLimited, style: const TextStyle(fontSize: 13, color: ClaiColors.warning))),
            if (engine.autoplay.isEmpty && engine.autoplayActive && engine.autoplayPreparing)
              Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(children: [
                    const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: ClaiColors.accent)),
                    const SizedBox(width: 10),
                    Expanded(child: Text(context.l10n.queuePreparing, style: const TextStyle(fontSize: 13, color: ClaiColors.inkFaint))),
                  ])),
            if (engine.autoplay.isEmpty && engine.autoplayActive && !engine.autoplayPreparing && engine.autoplayRefillFailed)
              Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Row(children: [
                    Expanded(child: Text(context.l10n.queueContinuationPending, style: const TextStyle(fontSize: 13, color: ClaiColors.inkFaint))),
                    TextButton(onPressed: () => handler.retryAutoplayRefill(), child: Text(context.l10n.commonRetry, style: const TextStyle(color: ClaiColors.accent))),
                  ])),
            if (engine.autoplay.isEmpty && engine.autoplayActive && !engine.autoplayPreparing && !engine.autoplayRefillFailed)
              Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Text(context.l10n.queueContinuationReady, style: const TextStyle(fontSize: 13, color: ClaiColors.inkFaint))),
            for (var i = 0; i < engine.autoplay.length; i++)
              if (match(engine.autoplay[i])) dismissibleRow('autoplay', engine.autoplay[i], i, auto: true),
            const SizedBox(height: 32),
          ]);
        },
      ),
      ),
    );
  }
}

/// Satu tombol aksi massal di bar bawah mode pilih-banyak: ikon di atas
/// label kecil, area ketuk lebar penuh bagiannya. Nonaktif (onTap null)
/// tampil samar.
class _BulkAction extends StatelessWidget {
  final ClaiIconData icon;
  final String label;
  final String? semanticLabel;
  final Color? color;
  final VoidCallback? onTap;
  const _BulkAction({
    required this.icon,
    required this.label,
    this.semanticLabel,
    this.color,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final c = enabled ? (color ?? ClaiColors.ink) : ClaiColors.inkFaint;
    return Semantics(
      button: true,
      enabled: enabled,
      label: semanticLabel ?? label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClaiIcon(icon, size: 22, color: c),
              const SizedBox(height: 3),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: c),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
