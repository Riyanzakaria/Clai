import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../app.dart';
import '../core/clai_icons.dart';
import '../core/display_text.dart';
import '../core/tokens.dart';
import '../domain/models.dart';
import '../l10n/l10n.dart';
import '../player/queue_engine.dart' as qe;
import '../services/ambient_theme.dart';
import 'glass.dart';
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

/// Nomor tampil (1-based) sebuah baris antrean pada urutan yang
/// TERLIHAT pemakai (sesudah saring): seksi manual bernomor dari 1;
/// seksi lanjutan MENERUSKAN hitungan sesudah baris manual yang
/// terlihat; seksi lain (Putar Otomatis) tanpa nomor — urutannya saran
/// mesin, bukan susunan pemakai. Murni & teruji (Redesign 8051 mengunci
/// perilaku papan 03 ini sebagai regresi).
int? queueVisibleNumber({
  required String section,
  required int visibleManualCount,
  required int positionInSection,
}) =>
    switch (section) {
      'manual' => positionInSection + 1,
      'continuation' => visibleManualCount + positionInSection + 1,
      _ => null,
    };

/// Layar Antrian (DS 6.10 amendemen 4.10 — Redesign 8051): panggung
/// hero trek berjalan, kapsul ringkasan skala, panel Acak Cerdas di
/// bawah panggung, saring > 50 trek, seksi-seksi selalu terpisah &
/// berlabel asal, penomoran dua digit menerus.
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
  /// Lencana AUTO papan 03 (butir (f), Ronde Sapuan 8045): dulu
  /// teks Volt polos — kini lencana ber-outline Volt sesuai papan.
  Widget _autoBadge() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
        decoration: BoxDecoration(
          border: Border.all(color: ClaiColors.accent, width: 1),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(context.l10n.queueAutoBadge,
            style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
                color: ClaiColors.accent)),
      );

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
    // DS v4.0 (U3): kepala Antrean = kaca bertinta saat Tema Dinamis
    // menyala (flexibleSpace kaca di kedua varian AppBar); tema mati →
    // AppBar tonal v3.1 persis.
    final amb = ref.watch(ambientControllerProvider.select(ambientUiSlice)); // 8053 B(i): irisan tanpa napas
    final ambOn = amb.enabled;
    return ScaffoldMessenger(
      key: _messengerKey,
      child: Scaffold(
      extendBodyBehindAppBar: false,
      appBar: _selecting
          ? AppBar(
              backgroundColor: ambOn ? Colors.transparent : null,
              flexibleSpace: ambOn
                  ? const GlassSurface(
                      radius: 0,
                      darken: 0.35,
                      child: SizedBox.expand(),
                    )
                  : null,
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
              backgroundColor: ambOn ? Colors.transparent : null,
              flexibleSpace: ambOn
                  ? const GlassSurface(
                      radius: 0,
                      darken: 0.35,
                      child: SizedBox.expand(),
                    )
                  : null,
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
                // 8045: bilah pilih-banyak = permukaan tonal, bukan
                // garis rambut di tepi atasnya (bahasa DS: kedalaman
                // dari tonal, bukan garis tepi).
                color: ClaiColors.surface1,
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
          // Label seksi Antrian = type/micro fungsional (DS 6.10); saat
          // Tema Dinamis menyala ia mengambil bahasa kicker KD-6 yang
          // sama seperti kepala seksi layar lain (Volt, renggang 1,6) —
          // Kampanye Rombak UI Total, Batch 2. Tema mati → mikro redup
          // v3.1 persis.
          // Redesign 8051: kicker seksi kini didahului TITIK Volt 6 dp
          // dan boleh membawa HITUNGAN seksi terlihat ("BERIKUTNYA (3)")
          // — bahasa frame Stitch "Antrian — Clai (Redesign)".
          Widget sectionHeader(String label, {Widget? trailing, int? count}) {
            final shown = count != null ? '$label ($count)' : label;
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
              child: Row(children: [
                if (ambOn) ...[
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                        color: ClaiColors.accent, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(child: ambOn
                    ? KickerLabel(shown)
                    : Text(shown.toUpperCase(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: .6, color: ClaiColors.inkFaint))),
                if (trailing != null) trailing,
              ]),
            );
          }
          // Satu baris item lanjutan, sadar mode:
          // - normal: ketuk = lompat putar; ⋮ = menu konteks penuh atas
          //   item itu (Butir 3); tekan-lama = masuk mode pilih (Butir 2);
          //   trailing per seksi (gagang seret / lencana AUTO) dari
          //   pemanggil lewat [trail].
          // - pilih: ketuk = alih centang; ⋮ dan gagang disembunyikan
          //   agar ketukan murni untuk memilih (Butir 3c).
          Widget queueRow(String section, int index, Track t,
              {Widget? trail, bool auto = false, int? number}) {
            if (_selecting) {
              return SongRow(
                track: t,
                showMenu: false,
                number: number,
                twoDigitNumber: number != null,
                dimmed: auto,
                selected: _isSelected(section, t),
                onTap: () => _toggleSelected(section, t),
                trailing: auto ? _autoBadge() : null,
              );
            }
            return SongRow(
              track: t,
              showMenu: true,
              number: number,
              twoDigitNumber: number != null,
              dimmed: auto,
              onTap: () => handler.jumpTo(t.key),
              onLongPress: () => _enterSelection(section, t),
              onMenuPressed: () => _openItemMenu(section, index, t),
              trailing: trail,
            );
          }

          Widget sectionList(String section, List<Track> tracks) {
            final idxs = visibleIdx(tracks);
            // Papan 03 (butir (f)): baris Berikutnya BERNOMOR sesuai
            // urutan putar yang TERLIHAT pemakai: seksi manual dulu,
            // lalu kelanjutan konteks (continuation) meneruskan hitungan
            // yang sama — di kebanyakan konteks daftar manual kosong dan
            // yang terlihat memang continuation-nya. Seksi lain (Putar
            // Otomatis) tanpa nomor: urutannya saran mesin, bukan antrean
            // yang disusun pemakai.
            int? numberFor(int engineIndex) => queueVisibleNumber(
                  section: section,
                  visibleManualCount: visibleIdx(engine.manual).length,
                  positionInSection: idxs.indexOf(engineIndex),
                );
            if (_selecting) {
              return Column(children: [
                for (final i in idxs)
                  queueRow(section, i, tracks[i], number: numberFor(i)),
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
                number: numberFor(engineIndex),
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
                  ? _autoBadge()
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

          // PANGGUNG HERO trek berjalan (Redesign 8051, DS 6.10
          // amendemen 4.10 — frame Stitch "Antrian — Clai (Redesign)",
          // keputusan pemilik 2026-11-10 20:42): trek berjalan bukan
          // lagi kartu kaca berisi SongRow 48, melainkan panel panggung
          // berwarna sampulnya sendiri (wash pahlawan palet ambien di
          // atas surface-1, mengalir lintas-trek via TintCrossfade;
          // tema mati → tonal surface-2), judul BESAR Clash Display
          // berwarna Volt (doktrin Bab 1: judul sedang diputar selalu
          // Volt), sampul 64 TERSARANG dalam wadah gelap, batang EQ
          // menimpa sudut sampul, durasi tabular (disembunyikan bila
          // belum termuat — tidak pernah karangan), dan ⋮ menu konteks
          // trek yang sama persis seperti baris lama. Trek berjalan
          // tetap di LUAR alam seleksi dan tanpa gestur lain —
          // perilaku terkunci tidak berubah, hanya komposisinya.
          Widget nowStage() {
            final cur = engine.current!;
            final panelColor = ambOn
                ? Color.alphaBlend(
                    amb.palette
                        .washColor(AmbientSurfaceKind.hero, amb.strength),
                    ClaiColors.surface1)
                : ClaiColors.surface2;
            Widget stage(Color color) => Container(
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  padding: const EdgeInsets.all(16),
                  child: Row(children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: ClaiColors.base.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Stack(children: [
                        CoverArt(
                          url: cur.artworkUrl,
                          size: 64,
                          label: cur.title,
                          radius: 10,
                        ),
                        Positioned(
                          right: 3,
                          bottom: 3,
                          child: StreamBuilder<dynamic>(
                            stream: handler.playbackState.stream,
                            initialData: handler.playbackState.valueOrNull,
                            builder: (context, ps) => EqualizerBars(
                                animating: ps.data?.playing ?? false),
                          ),
                        ),
                      ]),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            cleanDisplayTitle(cur.title),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: displayStyle(22)
                                .copyWith(color: ClaiColors.accent),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            cleanDisplayArtist(cur.artistNames),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 13,
                                color: ClaiColors.inkSecondary),
                          ),
                        ],
                      ),
                    ),
                    if (cur.duration != null) ...[
                      const SizedBox(width: 8),
                      Text(
                        formatDuration(cur.duration!),
                        style: const TextStyle(
                            fontSize: 12,
                            color: ClaiColors.inkSecondary,
                            fontFeatures: [FontFeature.tabularFigures()]),
                      ),
                    ],
                    IconButton(
                      icon: ClaiIcon(ClaiIcons.moreVert,
                          color: ClaiColors.inkSecondary),
                      tooltip: context.l10n.a11yTrackOptions,
                      onPressed: () =>
                          showTrackContextSheet(context, ref, cur),
                    ),
                  ]),
                );
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 2, 16, 0),
              child: ambOn
                  ? TintCrossfade(
                      target: panelColor,
                      reduceMotion: amb.reduceEffects,
                      builder: (context, c) => stage(c),
                    )
                  : stage(panelColor),
            );
          }

          return FiniteScrollPage(children: [
            // Kicker seksi SEDANG DIPUTAR dipertahankan di atas
            // panggung (penyesuaian arsitektur kita atas frame Stitch:
            // tata bahasa kicker+titik yang sama seperti seksi lain,
            // dan label seksi tetap ada untuk pembaca layar).
            sectionHeader(context.l10n.queueNowPlaying),
            nowStage(),
            // KAPSUL ringkasan skala (Redesign 8051): kartu ringkasan
            // papan 03 menyusut menjadi kapsul telemetri — titik Volt
            // 6 dp + satu baris tabular yang isinya persis sama
            // ("{n} trek · {total}{+}"); kejujuran penanda "+" tidak
            // berubah.
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: ClaiColors.surface2,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                          color: ClaiColors.accent, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 8),
                    Text(summary,
                        style: const TextStyle(fontSize: 13, color: ClaiColors.inkSecondary, fontFeatures: [FontFeature.tabularFigures()])),
                  ]),
                ),
              ),
            ),
            // Panel ACAK CERDAS (Redesign 8051): pindah ke BAWAH
            // panggung & kapsul — panel tonal mandiri dengan kotak ikon
            // tonal (§6.14); isi, sakelar, dan perilaku persis seperti
            // kartu lamanya (hanya mengurut ulang Lanjutan, tidak
            // pernah menambah lagu).
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Container(
                decoration: BoxDecoration(
                  color: ClaiColors.surface1,
                  borderRadius: BorderRadius.circular(20),
                ),
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                child: Row(children: [
                  tonalIconBox(ClaiIcons.shuffle),
                  const SizedBox(width: 12),
                  Expanded(child: Text(
                      context.l10n.queueSmartShuffleNote,
                      style: const TextStyle(fontSize: 13, color: ClaiColors.inkSecondary, height: 1.4))),
                  Switch(
                    value: engine.shuffle == qe.ShuffleMode.smart,
                    onChanged: (v) => handler.setSmartShuffle(v),
                  ),
                ]),
              ),
            ),
            if (full.length > 50)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: TextField(
                  decoration: InputDecoration(hintText: context.l10n.queueFilterHint, prefixIcon: ClaiIcon(ClaiIcons.search),
                      filled: true, fillColor: ClaiColors.surface1, border: const OutlineInputBorder(borderSide: BorderSide.none, borderRadius: BorderRadius.all(Radius.circular(999)))),
                  onChanged: (v) => setState(() => _filter = v.trim().toLowerCase()),
                ),
              ),
            if (engine.manual.isNotEmpty) ...[
              sectionHeader(context.l10n.queueUpNext,
                  count: visibleIdx(engine.manual).length),
              sectionList('manual', engine.manual),
            ],
            if (engine.continuation.isNotEmpty) ...[
              sectionHeader(context.l10n.queueContinuation(engine.context?.label ?? context.l10n.queueContextFallback),
                  count: visibleIdx(engine.continuation).length),
              sectionList('continuation', engine.continuation),
            ],
            sectionHeader(context.l10n.queueAutoplayHeader(engine.seeds.isNotEmpty ? engine.seeds.first.title : (engine.current?.title ?? '')),
                trailing: Switch(
                  value: engine.autoplaySessionOn,
                  onChanged: (v) => handler.setAutoplaySession(v),
                )),
            if (!engine.autoplayEnabled)
              Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Text(context.l10n.queueAutoplayOff, style: const TextStyle(fontSize: 13, color: ClaiColors.inkFaint))),
            // Garis status seksi Putar Otomatis (papan 03, butir (f)):
            // papan menggambar SATU garis status persisten di seksi
            // ini; keadaan aktif-berisi sebelumnya tak punya garis
            // sama sekali. Memakai teks strip yang sama seperti
            // Player (G-3) — satu kalimat, satu makna.
            if (engine.autoplayActive && engine.autoplay.isNotEmpty)
              Padding(padding: const EdgeInsets.fromLTRB(16, 2, 16, 4),
                  child: Row(children: [
                    ClaiIcon(ClaiIcons.infinity, size: 16, color: ClaiColors.accent),
                    const SizedBox(width: 8),
                    Expanded(child: Text(context.l10n.playerAutoplayStrip, style: const TextStyle(fontSize: 13, color: ClaiColors.inkSecondary))),
                  ])),
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
        borderRadius: BorderRadius.circular(12),
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
