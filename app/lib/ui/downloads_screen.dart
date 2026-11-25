import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../app.dart';
import '../core/clai_icons.dart';
import '../core/tokens.dart';
import '../services/download_service.dart';
import 'collection_screen.dart';
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
///
/// Gelombang 2 (8048): komposisi papan — kartu penyimpanan (angka besar
/// tabular + bilah Volt terhadap kuota bila kuota disetel + penjelasan
/// penyimpanan privat), baris unduhan-berjalan lebih dulu (garis
/// progres Volt 3 dp + status tabular + jeda/lanjut; batal & hapus
/// HANYA lewat menu luapan — ikon sampah berdiri dibuang), lalu baris
/// terunduh sebagai SongRow (menu trek penuhnya tetap membawa "Hapus
/// unduhan"). Ronde 8084: baris-baris itu kini DATAR ber-hairline
/// (cangkang kartu per baris pensiun); kartu penyimpanan tetap.
/// Ronde 8089 (Bagian C): layar mandiri ini layar DORONG — kepalanya
/// kini pola kepala baku (chevron telanjang + judul TENGAH
/// displayStyle(20) + penyeimbang 48), menggantikan judul display 34
/// kiri tanpa tombol kembali. Sebagai badan tab Koleksi yang dipakai
/// hanya [DownloadsBody] (judul tidak digandakan, KG-9) — DownloadsScreen
/// hanya dipanggil sebagai layar dorong dari Pengaturan.
class DownloadsScreen extends ConsumerWidget {
  const DownloadsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
              child: Row(
                children: [
                  const ClaiBackButton(),
                  Expanded(
                    child: Text(
                      context.l10n.dlTitle,
                      textAlign: TextAlign.center,
                      style: displayStyle(20),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
            ),
            const Expanded(child: DownloadsBody()),
          ],
        ),
      ),
    );
  }
}

/// Isi layar unduhan — dipakai juga sebagai tab Koleksi (tanpa judul sendiri).
class DownloadsBody extends ConsumerWidget {
  /// Audit UX 2017: jalan keluar dari keadaan kosong menuju tab Cari
  /// (hanya disambungkan tuan rumah tab Koleksi; layar mandiri = null).
  final VoidCallback? onGoSearch;
  const DownloadsBody({super.key, this.onGoSearch});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final svc = ref.watch(downloadServiceProvider);
    final items = svc.items;
    final done = items.where((i) => i.status == DownloadStatus.done).toList();
    final pending = items
        .where((i) => i.status != DownloadStatus.done)
        .toList();
    // Audit Ronde 8084: baris-baris unduhan kini DATAR dipisah
    // hairline (wadah kartu surface1 per baris pensiun — lihat
    // _pendingCard/_doneCard); kartu ringkasan penyimpanan di atas
    // tetap (pahlawan data papan 8048, bukan wadah baris).
    final rows = <Widget>[
      for (final item in pending) _pendingCard(context, ref, svc, item),
      for (final item in done) _doneCard(context, ref, svc, item),
    ];
    return FiniteScrollPage(children: [
      _storageCard(context, ref, svc, done.length),
      if (items.isEmpty)
        SizedBox(
          height: 300,
          child: EmptyState(
            icon: ClaiIcons.download,
            message: l.dlEmpty,
            actionLabel: onGoSearch == null ? null : l.collectionGoSearch,
            onAction: onGoSearch,
          ),
        )
      else ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
          child: DimKicker(l.dlSectionDownloaded),
        ),
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Divider(height: 1, color: ClaiColors.divider),
            ),
          rows[i],
        ],
      ],
      SizedBox(height: bottomChromeClearance(context)),
    ]);
  }

  Widget _storageCard(BuildContext context, WidgetRef ref,
      DownloadService svc, int doneCount) {
    final l = context.l10n;
    final anyActive = svc.items.any((i) =>
        i.status == DownloadStatus.downloading ||
        i.status == DownloadStatus.queued);
    final anyPaused = svc.items.any((i) => i.status == DownloadStatus.paused);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: ClaiColors.surface1,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              formatStorageSize(
                svc.usedBytes,
                commaDecimal:
                    Localizations.localeOf(context).languageCode == 'id',
              ),
              style: heroStyle(28),
            ),
            const SizedBox(height: 4),
            Text(
              l.dlStorageUsedBy(doneCount),
              style: const TextStyle(
                  color: ClaiColors.inkSecondary, fontSize: 13),
            ),
            FutureBuilder<int>(
              future: svc.quotaBytes(),
              builder: (context, snap) {
                final quota = snap.data ?? 0;
                if (quota <= 0) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: (svc.usedBytes / quota).clamp(0.0, 1.0),
                      minHeight: 6,
                      backgroundColor: ClaiColors.surface3,
                      valueColor: const AlwaysStoppedAnimation<Color>(
                          ClaiColors.signal),
                    ),
                  ),
                );
              },
            ),
            if (anyActive || anyPaused)
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (anyActive)
                    TextButton(
                      onPressed: () => svc.pauseAll(),
                      child: Text(l.dlPauseAll,
                          style:
                              const TextStyle(color: ClaiColors.signal)),
                    ),
                  if (anyPaused)
                    TextButton(
                      onPressed: () => svc.resumeAll(),
                      child: Text(l.dlResumeAll,
                          style:
                              const TextStyle(color: ClaiColors.signal)),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  /// Baris unduhan belum selesai (berjalan/antre/jeda/gagal/korup):
  /// satu bentuk baris datar untuk semua keadaan belum-putar.
  Widget _pendingCard(BuildContext context, WidgetRef ref,
      DownloadService svc, DownloadItemState item) {
    final l = context.l10n;
    final handler = ref.read(audioHandlerProvider);
    final t = item.track;
    final total = item.bytesTotal ?? 0;
    final frac = total > 0 ? (item.bytesDone / total).clamp(0.0, 1.0) : null;
    final pct = frac == null ? null : (frac * 100).round();
    final (statusText, showBar) = switch (item.status) {
      DownloadStatus.downloading => (
          pct != null
              ? '$pct% · ${l.dlProgressOf(formatBytes(item.bytesDone), formatBytes(total))}'
              : l.dlProgressDone(formatBytes(item.bytesDone)),
          true
        ),
      DownloadStatus.queued => (
          pct != null
              ? '$pct% · ${l.dlProgressOf(formatBytes(item.bytesDone), formatBytes(total))}'
              : l.dlProgressDone(formatBytes(item.bytesDone)),
          true
        ),
      DownloadStatus.paused => (
          total > 0
              ? l.dlPausedState(
                  formatBytes(item.bytesDone), formatBytes(total))
              : l.dlProgressDone(formatBytes(item.bytesDone)),
          true
        ),
      DownloadStatus.corrupt => (item.error ?? l.dlErrCorrupt, false),
      _ => (item.error ?? l.dlFailed, false),
    };
    // Ronde 8084: cangkang kartu surface1 r16 DIBUANG — baris tampil
    // datar di latar halaman (isi, progres, & aksi persis sama).
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Row(
          children: [
            if (item.status == DownloadStatus.corrupt ||
                item.status == DownloadStatus.failed)
              rowLeadIcon(
                item.status == DownloadStatus.corrupt
                    ? ClaiIcons.warning
                    : ClaiIcons.cloudOff,
                size: 52,
                iconSize: 24,
                color: ClaiColors.error,
              )
            else
              CoverArt(url: t.artworkUrl, size: 52, label: t.title, radius: 8),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: ClaiColors.ink),
                  ),
                  Text(
                    t.artistNames,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13, color: ClaiColors.inkSecondary),
                  ),
                  if (showBar) ...[
                    const SizedBox(height: 7),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: frac,
                        minHeight: 3,
                        backgroundColor: ClaiColors.surface3,
                        valueColor: const AlwaysStoppedAnimation<Color>(
                            ClaiColors.signal),
                      ),
                    ),
                  ],
                  const SizedBox(height: 5),
                  Text(
                    statusText,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: ClaiColors.inkFaint,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            switch (item.status) {
              DownloadStatus.downloading => IconButton(
                  icon: ClaiIcon(ClaiIcons.pause, color: ClaiColors.ink),
                  tooltip: l.dlPause,
                  onPressed: () => svc.pauseDownload(t.key),
                ),
              DownloadStatus.paused => IconButton(
                  icon: ClaiIcon(ClaiIcons.play, color: ClaiColors.ink),
                  tooltip: l.dlResume,
                  onPressed: () =>
                      svc.download(t, handler.effectiveQuality),
                ),
              DownloadStatus.corrupt => TextButton(
                  onPressed: () async {
                    await svc.deleteDownload(t.key);
                    await svc.download(t, handler.effectiveQuality);
                  },
                  child: Text(l.dlRedownload,
                      style: const TextStyle(color: ClaiColors.signal)),
                ),
              DownloadStatus.failed => TextButton(
                  onPressed: () =>
                      svc.download(t, handler.effectiveQuality),
                  child: Text(l.dlRetry,
                      style: const TextStyle(color: ClaiColors.signal)),
                ),
              _ => const SizedBox(width: 8),
            },
            PopupMenuButton<String>(
              // Ronde 8088: menu di navigator akar — pola cacat yang
              // sama dengan dropdown Mode transisi (menu pada navigator
              // tab jatuh di bawah chrome melayang; baris unduhan aktif
              // terbawah bisa mengistirahatkan item kedua menunya di
              // zona mini player).
              useRootNavigator: true,
              icon: ClaiIcon(ClaiIcons.moreVert,
                  color: ClaiColors.inkSecondary),
              color: ClaiColors.surface2,
              onSelected: (v) {
                switch (v) {
                  case 'cancel':
                    svc.cancelDownload(t.key);
                  case 'delete':
                    svc.deleteDownload(t.key);
                }
              },
              itemBuilder: (_) => [
                if (item.status == DownloadStatus.downloading ||
                    item.status == DownloadStatus.queued)
                  PopupMenuItem(
                      value: 'cancel', child: Text(l.commonCancel)),
                PopupMenuItem(
                  value: 'delete',
                  child: Text(l.ctxDeleteDownload,
                      style: const TextStyle(color: ClaiColors.error)),
                ),
              ],
            ),
          ],
        ),
    );
  }

  /// Baris terunduh: SongRow BAKU 60 langsung di latar halaman —
  /// putar, keadaan sedang-diputar, dan menu trek penuh (termasuk
  /// Hapus unduhan) dipertahankan; ukuran berkas tabular di kanan.
  /// (Ronde 8084: cangkang kartu surface1 r16 pensiun.)
  Widget _doneCard(BuildContext context, WidgetRef ref, DownloadService svc,
      DownloadItemState item) {
    final handler = ref.read(audioHandlerProvider);
    return SongRow(
      track: item.track,
      trailing: Padding(
        padding: const EdgeInsets.only(left: 8),
        child: Text(
          formatBytes(item.bytesTotal ?? item.bytesDone),
          style: const TextStyle(
            fontSize: 12,
            color: ClaiColors.inkFaint,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
      ),
      onTap: () => handler.playTracks([item.track], 0,
          kind: 'download', label: context.l10n.dlTitle),
    );
  }
}
