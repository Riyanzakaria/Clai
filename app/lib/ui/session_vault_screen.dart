import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app.dart';
import '../core/clai_icons.dart';
import '../core/tokens.dart';
import '../domain/models.dart';
import '../l10n/l10n.dart';
import '../player/audio_handler.dart' show collectSnapshotKeys;
import '../player/queue_engine.dart';
import '../services/session_vault.dart';
import 'glass.dart';
import 'widgets.dart';

/// Brankas Sesi (Ronde 8072, Workstream D / KOMPOSISI-F3 Paket Pertama
/// butir 6): arsip permanen sesi putar. Simpan menangkap snapshot
/// antrean penuh lewat jahitan yang sama dengan Lanjut Besok (D-15);
/// pulih menggantikan antrean berjalan HANYA sesudah lembar konfirmasi
/// di berkas ini. Semua permukaan PADAT (aturan kaca: kaca hanya untuk
/// chrome melayang).

// ---------------------------------------------------------------- simpan

/// Lembar Simpan sesi: nama terisi nama bawaan berpola waktu
/// ("Jumat malam, 21 Nov"), boleh diubah; kosong → nama bawaan.
Future<void> showSaveSessionSheet(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet<void>(
    context: claiRootContext(context),
    isScrollControlled: true,
    backgroundColor: ClaiColors.surface1,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(ClaiRadius.sheet),
      ),
    ),
    builder: (_) => _SaveSessionSheet(ref: ref),
  );
}

class _SaveSessionSheet extends StatefulWidget {
  final WidgetRef ref;
  const _SaveSessionSheet({required this.ref});

  @override
  State<_SaveSessionSheet> createState() => _SaveSessionSheetState();
}

class _SaveSessionSheetState extends State<_SaveSessionSheet> {
  late final TextEditingController _nameCtl;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameCtl = TextEditingController();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_nameCtl.text.isEmpty) {
      _nameCtl.text = defaultSessionName(
        DateTime.now(),
        Localizations.localeOf(context).languageCode,
      );
    }
  }

  @override
  void dispose() {
    _nameCtl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return; // penjaga masuk-ulang: satu ketuk = satu sesi
    final handler = widget.ref.read(audioHandlerProvider);
    if (handler.engine.current == null) return;
    setState(() => _saving = true);
    var name = _nameCtl.text.trim();
    if (name.isEmpty) {
      name = defaultSessionName(
        DateTime.now(),
        Localizations.localeOf(context).languageCode,
      );
    }
    final id = await widget.ref
        .read(sessionVaultProvider)
        .saveCurrent(
          engine: handler.engine,
          position: handler.position,
          name: name,
        );
    if (!mounted) return;
    if (id != null) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        claiSnackAboveChrome(context, context.l10n.vaultSavedSnack),
      );
    } else {
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    final handler = widget.ref.read(audioHandlerProvider);
    final current = handler.engine.current;
    return ClaiSheetScaffold(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Center(child: SheetHandle()),
              const SizedBox(height: 18),
              Text(s.vaultSaveTitle, style: displayStyle(20)),
              const SizedBox(height: 6),
              if (current != null)
                Text(
                  '${current.title} — ${current.artistNames}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: ClaiColors.inkSecondary,
                    fontSize: 13,
                  ),
                ),
              const SizedBox(height: 16),
              TextField(
                controller: _nameCtl,
                autofocus: true,
                maxLength: 120,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _save(),
                style: const TextStyle(color: ClaiColors.ink),
                decoration: InputDecoration(
                  labelText: s.vaultNameLabel,
                  labelStyle: const TextStyle(color: ClaiColors.inkSecondary),
                  filled: true,
                  fillColor: ClaiColors.surface2,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: ClaiColors.signal,
                  foregroundColor: ClaiColors.onSignal,
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(ClaiRadius.pill),
                  ),
                ),
                onPressed: _saving ? null : _save,
                child: Text(s.commonSave),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- pulih

/// Lembar konfirmasi Pulihkan Sesi (turunan wajib: aksi mengganti
/// antrean berjalan tidak pernah langsung jalan). PADAT.
Future<void> showRestoreSessionSheet(
  BuildContext context,
  WidgetRef ref,
  VaultSessionInfo info,
) {
  return showModalBottomSheet<void>(
    context: claiRootContext(context),
    isScrollControlled: true,
    backgroundColor: ClaiColors.surface1,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(ClaiRadius.sheet),
      ),
    ),
    builder: (_) => _RestoreSessionSheet(ref: ref, info: info),
  );
}

class _RestoreSessionSheet extends StatefulWidget {
  final WidgetRef ref;
  final VaultSessionInfo info;
  const _RestoreSessionSheet({required this.ref, required this.info});

  @override
  State<_RestoreSessionSheet> createState() => _RestoreSessionSheetState();
}

class _RestoreSessionSheetState extends State<_RestoreSessionSheet> {
  bool _busy = false;

  Future<void> _restore() async {
    if (_busy) return; // pulih ganda: ketuk kedua tidak memulai pulih kedua
    setState(() => _busy = true);
    final ref = widget.ref;
    final info = widget.info;
    final vault = ref.read(sessionVaultProvider);
    final handler = ref.read(audioHandlerProvider);
    final snap = await vault.snapshotOf(info.id);
    // Validasi jujur SEBELUM mesin disentuh: snapshot rusak atau lagu
    // berhentinya sudah tak ada di katalog → gagal di sini, antrean
    // berjalan tidak berubah sama sekali. Bacaan toleran + try/catch:
    // snapshot bengkok bentuk (mis. currentRef bukan string — data
    // rusak/dari format lain) TIDAK boleh mengunci lembar dalam
    // keadaan sibuk selamanya; ia harus jatuh ke jalur gagal jujur.
    // (Tertangkap Uji Besar 8072: snapshot uji 60 trek dengan
    // currentRef berbentuk peta membuat tombol Pulihkan mati total.)
    var ok = false;
    try {
      if (snap != null) {
        final keys = collectSnapshotKeys(snap);
        if (keys.isNotEmpty) {
          final tracks = await ref
              .read(appDbProvider)
              .tracksByKeys(keys.toList());
          final byKey = {for (final t in tracks) t.key};
          final rawCur = snap['currentRef'];
          final curRef = rawCur is String ? rawCur : null;
          ok =
              curRef != null &&
              curRef.contains('|') &&
              byKey.contains(
                TrackKey(
                  curRef.split('|').first,
                  curRef.split('|').sublist(1).join('|'),
                ),
              );
        }
      }
    } catch (_) {
      ok = false;
    }
    if (!mounted) return;
    if (!ok) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        claiSnackAboveChrome(context, context.l10n.vaultRestoreFailed),
      );
      return;
    }
    Navigator.of(context).pop();
    var restored = false;
    try {
      await handler.restoreSleepSession(snap!);
      restored = handler.engine.current != null;
    } catch (_) {
      restored = false;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      claiSnackAboveChrome(
        context,
        restored
            ? context.l10n.vaultRestoredSnack
            : context.l10n.vaultRestoreFailed,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    final info = widget.info;
    final lang = Localizations.localeOf(context).languageCode;
    return ClaiSheetScaffold(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Center(child: SheetHandle()),
              const SizedBox(height: 18),
              Text(s.vaultRestore, style: displayStyle(20)),
              const SizedBox(height: 6),
              Text(
                info.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: ClaiColors.ink,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${s.songCount(info.trackCount)} · ${vaultDateLabel(info.savedAt, lang)} ${vaultTimeLabel(info.savedAt)}',
                style: const TextStyle(
                  color: ClaiColors.inkSecondary,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                s.vaultRestoreBody,
                style: const TextStyle(
                  color: ClaiColors.inkSecondary,
                  fontSize: 14,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 18),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: ClaiColors.signal,
                  foregroundColor: ClaiColors.onSignal,
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(ClaiRadius.pill),
                  ),
                ),
                onPressed: _busy ? null : _restore,
                child: Text(s.vaultRestore),
              ),
              const SizedBox(height: 8),
              Center(
                child: TextButton(
                  onPressed: _busy ? null : () => Navigator.of(context).pop(),
                  child: Text(
                    s.commonCancel,
                    style: const TextStyle(color: ClaiColors.inkSecondary),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- daftar

/// Kartu "simpan antrean saat ini" di kepala layar Brankas — hanya bila
/// ada lagu berjalan.
class _SaveCurrentCard extends ConsumerWidget {
  const _SaveCurrentCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final handler = ref.watch(audioHandlerProvider);
    // Berlangganan queueStream: subjudul kartu menyebut lagu yang AKAN
    // disimpan — wajib hidup mengikuti ganti trek selagi layar terbuka
    // (audit emulator 8072 menangkap subjudul basi "Despacito" saat
    // pemain sudah di trek lain).
    return StreamBuilder<QueueEngine>(
      stream: handler.queueStream,
      builder: (context, _) {
        final current = handler.engine.current;
        if (current == null) return const SizedBox.shrink();
        // Ronde 8084: kartu tonal DIBUANG — baris aksi datar terkunci
        // 60 di latar halaman (ikon telanjang glyph 24 + label 15/600
        // + state lagu berjalan 13 satu baris + chevron); ketuk baris
        // membuka lembar Simpan yang sama seperti tombol lama.
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: () => showSaveSessionSheet(context, ref),
              child: SizedBox(
                height: 60,
                child: Row(
                  children: [
                    rowLeadIcon(ClaiIcons.history, size: 40, iconSize: 24),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            context.l10n.vaultSaveCurrent,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: ClaiColors.ink,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${current.title} — ${current.artistNames}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: ClaiColors.inkSecondary,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                    ClaiIcon(
                      ClaiIcons.chevronRight,
                      color: ClaiColors.inkFaint,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Layar Brankas Sesi: daftar sesi permanen, terbaru dulu.
class SessionVaultScreen extends ConsumerStatefulWidget {
  const SessionVaultScreen({super.key});

  @override
  ConsumerState<SessionVaultScreen> createState() => _SessionVaultScreenState();
}

class _SessionVaultScreenState extends ConsumerState<SessionVaultScreen> {
  @override
  void initState() {
    super.initState();
    ref.read(sessionVaultProvider).load();
  }

  @override
  Widget build(BuildContext context) {
    final vault = ref.watch(sessionVaultProvider);
    final s = context.l10n;
    final lang = Localizations.localeOf(context).languageCode;
    return Scaffold(
      appBar: claiPushedAppBar(context, s.vaultTitle),
      body: Column(
        children: [
          const _SaveCurrentCard(),
          Expanded(
            child: !vault.loaded
                ? const Center(child: CircularProgressIndicator())
                : vault.isEmpty
                ? EmptyState(
                    icon: ClaiIcons.history,
                    // Ronde 8084 (§13.2 golongan c): keadaan kosong
                    // SATU baris — vaultEmptyBody dibuang dari sini.
                    message: s.vaultEmptyTitle,
                  )
                : ListView.builder(
                    padding: EdgeInsets.only(
                      bottom: bottomChromeClearance(context),
                    ),
                    itemCount: vault.sessions.length,
                    itemBuilder: (context, i) {
                      final info = vault.sessions[i];
                      // Ronde 8084: kartu sesi DIBUANG — baris datar
                      // terkunci 60/pitch 68 + hairline antar baris;
                      // sampul 44 radius 12, judul 15/600, meta
                      // (hitungan • tanggal) 13 satu baris; ketuk sama.
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 20,
                            ),
                            minTileHeight: 60,
                            titleTextStyle: const TextStyle(
                              fontFamily: kDisplayFontFamily,
                              fontSize: kRowTitleSize,
                              fontWeight: FontWeight.w700,
                              color: ClaiColors.ink,
                            ),
                            subtitleTextStyle: const TextStyle(
                              color: ClaiColors.inkSecondary,
                              fontSize: 13,
                            ),
                            leading: CoverArt(
                              url: info.currentArtwork,
                              size: 44,
                              radius: 12,
                              label: '',
                            ),
                            title: Text(
                              info.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: rowTitleStyle(),
                            ),
                            subtitle: Text(
                              '${s.songCount(info.trackCount)} · ${vaultDateLabel(info.savedAt, lang)} ${vaultTimeLabel(info.savedAt)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: ClaiColors.inkSecondary,
                                fontSize: 13,
                              ),
                            ),
                            trailing: ClaiIcon(
                              ClaiIcons.chevronRight,
                              color: ClaiColors.inkFaint,
                            ),
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => SessionDetailScreen(info: info),
                              ),
                            ),
                          ),
                          if (i < vault.sessions.length - 1) ...[
                            const Padding(
                              padding: EdgeInsets.only(left: 80),
                              child: Divider(
                                height: 1,
                                color: ClaiColors.divider,
                              ),
                            ),
                            const SizedBox(height: 7),
                          ],
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- detail

/// Detail Sesi: kepala + daftar trek urutan putar sesi (riwayat →
/// lagu berhenti → antrean) + aksi Pulihkan / Hapus.
class SessionDetailScreen extends ConsumerStatefulWidget {
  final VaultSessionInfo info;
  const SessionDetailScreen({super.key, required this.info});

  @override
  ConsumerState<SessionDetailScreen> createState() =>
      _SessionDetailScreenState();
}

class _SessionDetailScreenState extends ConsumerState<SessionDetailScreen> {
  /// Baris daftar terlarut: trek + penanda (sudah diputar / titik berhenti).
  List<({Track track, bool played, bool isCurrent})>? _rows;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  Future<void> _resolve() async {
    // try/catch menyeluruh: snapshot bengkok bentuk harus berakhir di
    // keadaan gagal yang jujur (_failed), bukan pemintal abadi —
    // pasangan perbaikan lembar Pulihkan di berkas yang sama (Uji
    // Besar 8072).
    try {
      final vault = ref.read(sessionVaultProvider);
      final snap = await vault.snapshotOf(widget.info.id);
      if (snap == null) {
        if (mounted) setState(() => _failed = true);
        return;
      }
      final keys = collectSnapshotKeys(snap);
      final tracks = await ref.read(appDbProvider).tracksByKeys(keys.toList());
      final byKey = {for (final t in tracks) t.key: t};
      List<Track> pick(String key) {
        final raw = snap[key];
        if (raw is! List) return const [];
        return raw
            .map(
              (e) => (e is Map && e['p'] is String && e['i'] is String)
                  ? byKey[TrackKey(e['p'] as String, e['i'] as String)]
                  : null,
            )
            .whereType<Track>()
            .toList();
      }

      Track? current;
      final rawCur = snap['currentRef'];
      final curRef = rawCur is String ? rawCur : null;
      if (curRef != null && curRef.contains('|')) {
        current =
            byKey[TrackKey(
              curRef.split('|').first,
              curRef.split('|').sublist(1).join('|'),
            )];
      }
      // Tanpa trek berhenti yang terlarut (bengkok bentuk ATAU sudah
      // tak ada di katalog) sesi ini tidak bisa dipulihkan — Detail
      // menyatakannya jujur lewat _failed, bukan menampilkan daftar
      // yang diam-diam pincang.
      if (current == null) {
        if (mounted) setState(() => _failed = true);
        return;
      }
      final rows = <({Track track, bool played, bool isCurrent})>[
        for (final t in pick('played'))
          (track: t, played: true, isCurrent: false),
        (track: current, played: false, isCurrent: true),
        for (final t in [
          ...pick('manual'),
          ...pick('continuation'),
          ...pick('autoplay'),
        ])
          (track: t, played: false, isCurrent: false),
      ];
      if (mounted) setState(() => _rows = rows);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<void> _delete() async {
    final s = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        backgroundColor: ClaiColors.surface2,
        title: Text(
          s.vaultDeleteTitle,
          style: const TextStyle(color: ClaiColors.ink),
        ),
        content: Text(
          s.vaultDeleteBody(widget.info.name),
          style: const TextStyle(color: ClaiColors.inkSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d, false),
            child: Text(s.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(d, true),
            child: Text(
              s.commonDelete,
              style: const TextStyle(color: ClaiColors.error),
            ),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(sessionVaultProvider).delete(widget.info.id);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    final info = widget.info;
    final lang = Localizations.localeOf(context).languageCode;
    final rows = _rows;
    return Scaffold(
      appBar: claiPushedAppBar(context, s.vaultTitle),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  info.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: displayStyle(20),
                ),
                const SizedBox(height: 4),
                Text(
                  [
                    if (info.contextLabel != null &&
                        info.contextLabel!.isNotEmpty)
                      info.contextLabel!,
                    s.songCount(info.trackCount),
                    '${vaultDateLabel(info.savedAt, lang)} ${vaultTimeLabel(info.savedAt)}',
                  ].join(' · '),
                  style: const TextStyle(
                    color: ClaiColors.inkSecondary,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _failed
                ? EmptyState(
                    icon: ClaiIcons.warning,
                    message: s.vaultRestoreFailed,
                  )
                : rows == null
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    padding: EdgeInsets.only(
                      bottom: bottomChromeClearance(context),
                    ),
                    itemCount: rows.length,
                    itemBuilder: (context, i) {
                      final r = rows[i];
                      // Ronde 8084: baris trek terkunci 60, judul
                      // 15/600 (trek berhenti w700), sub 13; placeholder
                      // sampul = slot transparan + glyph inkFaint
                      // (kotak tonal surface2 dibuang); lencana = teks
                      // polos 11/600 inkSecondary tanpa wadah pil.
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                        ),
                        minTileHeight: 60,
                        leading: r.track.artworkUrl != null
                            ? CoverArt(
                                url: r.track.artworkUrl,
                                size: 44,
                                label: '',
                              )
                            : SizedBox(
                                width: 44,
                                height: 44,
                                child: Center(
                                  child: ClaiIcon(
                                    ClaiIcons.musicNote,
                                    color: ClaiColors.inkFaint,
                                    size: 20,
                                  ),
                                ),
                              ),
                        title: Text(
                          r.track.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: r.played
                                ? ClaiColors.inkSecondary
                                : ClaiColors.ink,
                            fontSize: 15,
                            fontWeight: r.isCurrent
                                ? FontWeight.w700
                                : FontWeight.w600,
                          ),
                        ),
                        subtitle: Text(
                          r.track.artistNames,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: ClaiColors.inkFaint,
                            fontSize: 13,
                          ),
                        ),
                        trailing: r.isCurrent
                            ? Text(
                                s.vaultCurrentBadge,
                                style: const TextStyle(
                                  color: ClaiColors.inkSecondary,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              )
                            : null,
                      );
                    },
                  ),
          ),
          Container(
            // Ronde 8084: latar surface1 DIBUANG — bilah aksi transparan
            // di latar halaman + hairline atas saja.
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: ClaiColors.divider)),
            ),
            // Bantalan bawah = ruang bebas chrome terapung (pemain mini +
            // nav): tanpa ini bilah aksi terkubur di balik chrome dan
            // tombol Pulihkan tak terketuk saat ada lagu termuat —
            // keluarga cacat yang sama dengan kartu Terbaca 8071,
            // tertangkap audit emulator 8072 (batas tombol terukur
            // bertumpuk pemain mini & nav).
            padding: EdgeInsets.fromLTRB(
              16,
              10,
              16,
              bottomChromeClearance(context),
            ),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: ClaiColors.signal,
                      foregroundColor: ClaiColors.onSignal,
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(ClaiRadius.pill),
                      ),
                    ),
                    onPressed: _failed
                        ? null
                        : () => showRestoreSessionSheet(context, ref, info),
                    child: Text(s.vaultRestore),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: ClaiIcon(ClaiIcons.trash, color: ClaiColors.error),
                  tooltip: s.commonDelete,
                  onPressed: _delete,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- rak Beranda

/// Rak "Brankas Sesi" di Beranda: kartu sesi tersimpan geser horizontal;
/// kepala rak membuka layar Brankas. Tak tampil bila brankas kosong.
class SessionShelf extends ConsumerStatefulWidget {
  const SessionShelf({super.key});

  @override
  ConsumerState<SessionShelf> createState() => _SessionShelfState();
}

class _SessionShelfState extends ConsumerState<SessionShelf> {
  @override
  void initState() {
    super.initState();
    ref.read(sessionVaultProvider).load();
  }

  @override
  Widget build(BuildContext context) {
    final vault = ref.watch(sessionVaultProvider);
    if (!vault.loaded || vault.isEmpty) return const SizedBox.shrink();
    final s = context.l10n;
    final lang = Localizations.localeOf(context).languageCode;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Ronde 8085: kepala rak lewat SectionHeader (Inter Tight 17,
        // padding bawaan standar) + trailing "Lihat semua" apa adanya.
        SectionHeader(
          s.vaultTitle,
          trailing: TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SessionVaultScreen()),
            ),
            child: Text(
              s.vaultSeeAll,
              style: const TextStyle(color: ClaiColors.signal),
            ),
          ),
        ),
        SizedBox(
          // 130: isi kartu (sampul 36 + nama + meta + bantalan) terukur
          // 124 pada metrik huruf uji — tinggi tetap wajib menampungnya
          // dengan sisa, bukan pas-pasan (pola cacat luapan 8071).
          height: 130,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: vault.sessions.length,
            itemBuilder: (context, i) {
              final info = vault.sessions[i];
              return Padding(
                padding: const EdgeInsets.only(right: 10),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => SessionDetailScreen(info: info),
                    ),
                  ),
                  child: Container(
                    width: 168,
                    // Ronde 8083: padding dalam kartu rak = ritme kartu
                    // hero Beranda (16 horizontal, 12 vertikal ringkas).
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: ClaiColors.surface1,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            info.currentArtwork != null
                                ? CoverArt(
                                    url: info.currentArtwork,
                                    size: 36,
                                    label: '',
                                  )
                                : Container(
                                    width: 36,
                                    height: 36,
                                    decoration: BoxDecoration(
                                      color: ClaiColors.surface2,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Center(
                                      child: ClaiIcon(
                                        ClaiIcons.musicNote,
                                        color: ClaiColors.inkSecondary,
                                        size: 16,
                                      ),
                                    ),
                                  ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                info.currentTitle ?? '',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: ClaiColors.inkSecondary,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          info.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            color: ClaiColors.ink,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${s.songCount(info.trackCount)} · ${vaultDateLabel(info.savedAt, lang)}',
                          style: const TextStyle(
                            color: ClaiColors.inkFaint,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
