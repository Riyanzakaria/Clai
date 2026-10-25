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
  final Widget Function(BuildContext context, Track track, Widget dragHandle) rowBuilder;

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

  @override
  Widget build(BuildContext context) {
    final handler = ref.watch(audioHandlerProvider);
    final engine = handler.engine;
    return ScaffoldMessenger(
      key: _messengerKey,
      child: Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.queueTitle),
        actions: [
          IconButton(icon: ClaiIcon(ClaiIcons.clearAll), tooltip: context.l10n.queueClear,
              onPressed: engine.effectiveQueue.isEmpty ? null : () => handler.clearQueue()),
          IconButton(icon: ClaiIcon(ClaiIcons.close), tooltip: context.l10n.a11yClose, onPressed: () => Navigator.of(context).pop()),
        ],
      ),
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
          Widget sectionList(String section, List<Track> tracks) {
            final idxs = visibleIdx(tracks);
            return QueueSectionList(
              section: section,
              items: [for (final i in idxs) tracks[i]],
              itemIndices: idxs,
              rowBuilder: (ctx, t, handle) => SongRow(
                track: t,
                showMenu: false,
                onTap: () => handler.jumpTo(t.key),
                trailing: handle,
              ),
              onReorder: (o, n) => handler.moveInQueue(section, o, n),
              onDismissed: (index, t) => _onRemoved(section, index, t),
            );
          }

          Widget dismissibleRow(String section, Track t, int index, {bool auto = false}) {
            final row = SongRow(
              track: t, showMenu: false,
              onTap: () => handler.jumpTo(t.key),
              trailing: auto
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
