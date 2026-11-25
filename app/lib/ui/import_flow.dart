import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app.dart';
import '../core/clai_icons.dart';
import '../core/tokens.dart';
import '../domain/transfer_data.dart';
import '../l10n/l10n.dart';
import '../services/library_transfer.dart';
import 'widgets.dart';

/// Alur impor berkas (Ronde 8070, D2 / F-12): pilih berkas → urai
/// defensif → ringkasan SEBELUM menerapkan → konfirmasi pengguna →
/// terapkan atomik. Dipakai hub Kepemilikan dan layar Pindai (pintu
/// "Impor dari berkas") — satu alur, dua pintu.

/// Buka pemilih berkas sistem dan jalankan seluruh alur impor atas
/// berkas yang dipilih. Batal memilih = kembali diam-diam.
Future<void> runImportFromFile(BuildContext context, WidgetRef ref) async {
  // file_picker disemat 10.3.x (API FilePicker.platform): seri 11
  // gagal membangun di AGP 9 proyek ini (modul Kotlin-nya tidak
  // terkompilasi — plugin tidak menyalakan built-in Kotlin AGP 9),
  // seri 13 bertabrakan win32 dengan share_plus 11. 10.3.x menerapkan
  // KGP tanpa syarat seperti plugin lain yang terbukti membangun.
  final picked = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['json'],
    withData: true,
  );
  if (picked == null || picked.files.isEmpty) return;
  final file = picked.files.single;
  final bytes = file.bytes;
  if (bytes == null) {
    if (context.mounted) {
      showImportFailureSheet(
        context,
        const TransferParseFailure(TransferFailureKind.corrupt),
      );
    }
    return;
  }
  if (!context.mounted) return;
  handleTransferBytes(context, ref, bytes, fileName: file.name);
}

/// Lanjutkan alur impor dari byte yang sudah terpegang (dipakai juga
/// jalur uji & pemindai): urai, lalu tampilkan lembar yang sesuai.
void handleTransferBytes(
  BuildContext context,
  WidgetRef ref,
  List<int> bytes, {
  required String fileName,
}) {
  final result = parseTransferBytes(bytes);
  switch (result) {
    case ParsedLibrary(:final data):
      showImportPreviewSheet(context, ref, data, fileName: fileName);
    case ParsedSharedPlaylist(:final data):
      showSharedPlaylistSheet(context, ref, data, fromQr: false);
    case ParsedSharedRefs():
      // Payload ringkas hanya sah dari kendaraan QR (decodeQrPayload);
      // tiba lewat jalur berkas berarti isinya bukan berkas Clai.
      showImportFailureSheet(
        context,
        const TransferParseFailure(TransferFailureKind.unrecognized),
      );
    case TransferParseFailure():
      showImportFailureSheet(context, result);
  }
}

/// Rangka lembar bawah baku ronde ini (pola lembar "Yang baru" 8069:
/// surface-1 padat, radius atas sheet, pegangan di tengah).
Future<T?> _showSolidSheet<T>(BuildContext context, Widget child) {
  return showModalBottomSheet<T>(
    context: claiRootContext(context),
    isScrollControlled: true,
    backgroundColor: ClaiColors.surface1,
    shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(ClaiRadius.sheet))),
    builder: (_) => child,
  );
}

Widget _sheetShell({required List<Widget> children}) {
  return ClaiSheetScaffold(children: [
    const Padding(
      padding: EdgeInsets.only(top: 14),
      child: SheetHandle(),
    ),
    Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    ),
  ]);
}

Widget _primaryButton({
  required String label,
  required VoidCallback? onPressed,
}) {
  return FilledButton(
    style: FilledButton.styleFrom(
      backgroundColor: ClaiColors.signal,
      foregroundColor: ClaiColors.onSignal,
      minimumSize: const Size.fromHeight(48),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ClaiRadius.pill)),
    ),
    onPressed: onPressed,
    child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
  );
}

// ---------------------------------------------------------------------------
// Pratinjau Impor (F-12: ringkasan tambah/gabung/ganti sebelum diterapkan)
// ---------------------------------------------------------------------------

Future<void> showImportPreviewSheet(
  BuildContext context,
  WidgetRef ref,
  LibraryTransferData data, {
  required String fileName,
}) {
  return _showSolidSheet(
    context,
    _ImportPreviewSheet(data: data, fileName: fileName, ref: ref),
  );
}

class _ImportPreviewSheet extends StatefulWidget {
  final LibraryTransferData data;
  final String fileName;
  final WidgetRef ref;
  const _ImportPreviewSheet({
    required this.data,
    required this.fileName,
    required this.ref,
  });

  @override
  State<_ImportPreviewSheet> createState() => _ImportPreviewSheetState();
}

class _ImportPreviewSheetState extends State<_ImportPreviewSheet> {
  bool _replace = false;
  bool _applying = false;
  ImportProjection? _projection;

  @override
  void initState() {
    super.initState();
    widget.ref
        .read(appDbProvider)
        .projectLibraryImport(widget.data)
        .then((p) {
      if (mounted) setState(() => _projection = p);
    });
  }

  LibraryTransferData get data => widget.data;

  Future<void> _apply(bool replace) async {
    // Tangkap navigator/messager/teks SEBELUM await & pop: konteks
    // lembar tidak sah lagi sesudah lembar ditutup.
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(claiRootContext(context));
    final successText = context.l10n.importSuccess;
    setState(() => _applying = true);
    try {
      await widget.ref
          .read(appDbProvider)
          .applyLibraryImport(data, replace: replace);
      await widget.ref.read(libraryProvider).load();
      if (!mounted) return;
      nav.pop();
      messenger.showSnackBar(SnackBar(content: Text(successText)));
    } catch (_) {
      // Penerapan atomik: kegagalan = nol perubahan; nyatakan jujur.
      if (!mounted) return;
      Navigator.of(context).pop();
      showImportFailureSheet(
        context,
        const TransferParseFailure(TransferFailureKind.corrupt),
      );
    }
  }

  Future<void> _onPrimary() async {
    if (!_replace) {
      await _apply(false);
      return;
    }
    // Ganti semua = merusak → konfirmasi kedua, pola dialog Hapus
    // (AlertDialog surface-2, Batal + aksi destruktif berwarna error).
    final s = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        backgroundColor: ClaiColors.surface2,
        title: Text(s.importReplaceTitle,
            style: const TextStyle(color: ClaiColors.ink)),
        content: Text(s.importReplaceBody,
            style: const TextStyle(color: ClaiColors.inkSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d, false),
            child: Text(s.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(d, true),
            child: Text(s.importModeReplace,
                style: const TextStyle(color: ClaiColors.error)),
          ),
        ],
      ),
    );
    if (ok == true && mounted) await _apply(true);
  }

  // Ronde 8084: baris mode terkunci 60, judul 15/600 — sub penjelas
  // mode (importModeMergeSub/importModeReplaceSub) DIBUANG (§13.2);
  // radio + judul tetap, ringkasan hitungan di atas = nilai.
  Widget _modeRow({
    required bool selected,
    required String title,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        height: 60,
        child: Row(children: [
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: selected ? ClaiColors.signal : ClaiColors.inkFaint,
                width: 2,
              ),
            ),
            child: selected
                ? Center(
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: ClaiColors.signal,
                      ),
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: ClaiColors.ink,
                    fontSize: 15,
                    fontWeight: FontWeight.w600)),
          ),
        ]),
      ),
    );
  }

  List<Widget> _summaryLines(BuildContext context) {
    final s = context.l10n;
    const style = TextStyle(color: ClaiColors.ink, fontSize: 14, height: 1.5);
    if (_replace) {
      // Mode ganti: ringkasan = isi berkas itu sendiri.
      return [
        Text('• ${s.ownPlaylistsCount(data.playlists.length)}',
            style: style),
        Text('• ${s.ownLikedCount(data.liked.length)}', style: style),
        if (data.history != null)
          Text('• ${s.ownHistoryCount(data.historyCount)}', style: style),
      ];
    }
    final p = _projection;
    if (p == null) {
      return [
        const Text('• …', style: style),
      ];
    }
    final lines = <Widget>[
      if (p.newPlaylists > 0)
        Text('• ${s.importSumNewPlaylists(p.newPlaylists)}', style: style),
      if (p.mergedPlaylists > 0)
        Text('• ${s.importSumMergedPlaylists(p.mergedPlaylists)}',
            style: style),
      if (p.playlistTracksAdded > 0)
        Text('• ${s.importSumTracksAdded(p.playlistTracksAdded)}',
            style: style),
      if (p.likedAdded > 0)
        Text('• ${s.importSumLikedAdded(p.likedAdded)}', style: style),
      if (p.historyAdded > 0)
        Text('• ${s.importSumHistoryAdded(p.historyAdded)}', style: style),
    ];
    if (lines.isEmpty) {
      lines.add(Text(s.importNothingNew,
          style: const TextStyle(
              color: ClaiColors.inkSecondary, fontSize: 14, height: 1.5)));
    }
    return lines;
  }

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    final nothingToMerge = !_replace &&
        _projection != null &&
        _projection!.newPlaylists == 0 &&
        _projection!.mergedPlaylists == 0 &&
        _projection!.playlistTracksAdded == 0 &&
        _projection!.likedAdded == 0 &&
        _projection!.historyAdded == 0;
    return _sheetShell(children: [
      Text(s.ownImportTitle, style: displayStyle(20)),
      const SizedBox(height: 4),
      Text(s.importFromFile(widget.fileName),
          style: const TextStyle(color: ClaiColors.inkFaint, fontSize: 13),
          maxLines: 1,
          overflow: TextOverflow.ellipsis),
      const SizedBox(height: 16),
      ..._summaryLines(context),
      const SizedBox(height: 14),
      _modeRow(
        selected: !_replace,
        title: s.importModeMerge,
        onTap: () => setState(() => _replace = false),
      ),
      const Divider(height: 1, color: ClaiColors.divider),
      _modeRow(
        selected: _replace,
        title: s.importModeReplace,
        onTap: () => setState(() => _replace = true),
      ),
      const SizedBox(height: 18),
      _primaryButton(
        label: _replace ? s.importApplyReplace : s.importApplyMerge,
        onPressed: (_applying || nothingToMerge) ? null : _onPrimary,
      ),
    ]);
  }
}

// ---------------------------------------------------------------------------
// Lembar playlist bagikan yang diterima (dari berkas)
// ---------------------------------------------------------------------------

Future<void> showSharedPlaylistSheet(
  BuildContext context,
  WidgetRef ref,
  SharedPlaylistData data, {
  required bool fromQr,
}) {
  return _showSolidSheet(
    context,
    _sheetShell(children: [
      Text(data.name, style: displayStyle(20)),
      const SizedBox(height: 4),
      Text(
        fromQr
            ? context.l10n.scanFoundSub(data.tracks.length)
            : context.l10n.shareFoundFileSub(data.tracks.length),
        style: const TextStyle(color: ClaiColors.inkSecondary, fontSize: 13),
      ),
      const SizedBox(height: 20),
      _primaryButton(
        label: context.l10n.scanImportAction,
        onPressed: () async {
          final nav = Navigator.of(context);
          final messenger =
              ScaffoldMessenger.of(claiRootContext(context));
          final name =
              await ref.read(appDbProvider).importSharedPlaylist(data);
          await ref.read(libraryProvider).load();
          if (!context.mounted) return;
          nav.pop();
          messenger.showSnackBar(
            SnackBar(content: Text(context.l10n.scanImported(name))),
          );
        },
      ),
    ]),
  );
}

// ---------------------------------------------------------------------------
// Impor Gagal
// ---------------------------------------------------------------------------

void showImportFailureSheet(
    BuildContext context, TransferParseFailure failure) {
  final s = context.l10n;
  final reason = switch (failure.kind) {
    TransferFailureKind.notJson => s.importFailNotJson,
    TransferFailureKind.unrecognized => s.importFailUnrecognized,
    TransferFailureKind.newerVersion =>
      s.importFailNewer('${failure.foundVersion ?? ''}'),
    TransferFailureKind.corrupt => s.importFailCorrupt,
    TransferFailureKind.tooLarge => s.importFailTooBig,
  };
  _showSolidSheet(
    context,
    _sheetShell(children: [
      rowLeadIcon(ClaiIcons.warning, size: 40, iconSize: 24),
      const SizedBox(height: 16),
      Text(s.importFailTitle, style: displayStyle(20)),
      const SizedBox(height: 8),
      Text(reason,
          style: const TextStyle(
              color: ClaiColors.inkSecondary, fontSize: 14, height: 1.5)),
      const SizedBox(height: 20),
      _primaryButton(
        label: s.commonClose,
        onPressed: () => Navigator.of(context).pop(),
      ),
    ]),
  );
}
