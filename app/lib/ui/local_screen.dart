import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../app.dart';
import '../core/clai_icons.dart';
import '../core/tokens.dart';
import '../domain/models.dart';
import '../l10n/l10n.dart';
import 'widgets.dart';

/// File Lokal (PRD 5.6 / F-11 Phase 2): izin diminta saat fitur dibuka, bukan saat instal.
///
/// Gelombang 2 (8048): komposisi papan — pita statistik dua blok
/// (hitungan berkas + format yang benar-benar ditemukan dari MIME
/// MediaStore), kartu pindai utama (judul + fakta kesetaraan berkas +
/// tombol pindai netral lebar penuh; keadaan memindai jujur tanpa
/// persen karangan), lalu hasil pindai sebagai baris lagu berchip
/// format. Sebelum pindai pertama, kartu pindai adalah elemen utama
/// dan pita statistik membaca nol.
class LocalFilesBody extends ConsumerStatefulWidget {
  const LocalFilesBody({super.key});
  @override
  ConsumerState<LocalFilesBody> createState() => _LocalFilesBodyState();
}

class _LocalFilesBodyState extends ConsumerState<LocalFilesBody> {
  List<Track>? _tracks;
  bool _loading = false;
  bool _denied = false;

  Future<void> _scan() async {
    setState(() { _loading = true; _denied = false; });
    final svc = ref.read(localFilesProvider);
    final ok = await svc.ensurePermission();
    if (!ok) {
      if (mounted) setState(() { _loading = false; _denied = true; });
      return;
    }
    final tracks = await svc.scan();
    // Bagikan hasil pindai sesi ini ke baris Berkas Lokal Koleksi
    // (meta hitungan nyata papan 05) — Koleksi sendiri tidak memindai.
    ref.read(localScanCacheProvider.notifier).state = tracks;
    if (mounted) setState(() { _tracks = tracks; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final handler = ref.watch(audioHandlerProvider);
    if (_denied) {
      return EmptyState(icon: ClaiIcons.folderOff, message: l.localDenied,
          actionLabel: context.l10n.commonRetry, onAction: _scan);
    }
    final svc = ref.read(localFilesProvider);
    final tracks = _tracks;
    final formats = tracks == null ? const <String>[] : svc.scannedFormats;
    return FiniteScrollPage(children: [
      // PITA STATISTIK: dua blok jujur dari hasil pindai terakhir.
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${tracks?.length ?? 0}', style: heroStyle(28)),
                  const SizedBox(height: 2),
                  Text(
                    l.localOnDevice,
                    style: const TextStyle(
                        fontSize: 12, color: ClaiColors.inkFaint),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    formats.isEmpty ? '—' : formats.join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: displayStyle(20),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    l.localFormatsFound,
                    style: const TextStyle(
                        fontSize: 12, color: ClaiColors.inkFaint),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      // KARTU PINDAI UTAMA.
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: ClaiColors.surface1,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                tonalIconBox(ClaiIcons.folder, size: 44, iconSize: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    l.localScanHeadline,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: ClaiColors.ink,
                    ),
                  ),
                ),
              ]),
              const SizedBox(height: 10),
              Text(
                l.localSub,
                style: const TextStyle(
                    color: ClaiColors.inkSecondary, fontSize: 13, height: 1.45),
              ),
              const SizedBox(height: 16),
              Opacity(
                opacity: _loading ? 0.6 : 1,
                child: Material(
                  color: ClaiColors.surface3,
                  borderRadius: BorderRadius.circular(999),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: _loading ? null : _scan,
                    child: SizedBox(
                      height: 48,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          ClaiIcon(ClaiIcons.search,
                              size: 18, color: ClaiColors.ink),
                          const SizedBox(width: 8),
                          Text(
                            _loading
                                ? l.localScanning
                                : (tracks == null
                                    ? l.localScan
                                    : l.localRescan),
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: ClaiColors.ink,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              if (_loading) ...[
                const SizedBox(height: 10),
                Text(
                  l.localScanningCaption,
                  style: const TextStyle(
                      fontSize: 12, color: ClaiColors.inkFaint),
                ),
              ],
            ],
          ),
        ),
      ),
      if (tracks != null && !_loading) ...[
        if (tracks.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(32, 28, 32, 0),
            child: Text(
              l.localNone,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: ClaiColors.inkSecondary, fontSize: 14, height: 1.45),
            ),
          )
        else ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 6),
            child: DimKicker(l.localResults),
          ),
          for (final t in tracks)
            SongRow(
              track: t,
              trailing: svc.formatOf(t) == null
                  ? null
                  : Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: ClaiColors.surface3,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          svc.formatOf(t)!,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: ClaiColors.inkSecondary,
                          ),
                        ),
                      ),
                    ),
              onTap: () => handler.playTracks(tracks, tracks.indexOf(t),
                  kind: 'local', label: l.localTitle),
            ),
        ],
      ],
      SizedBox(height: bottomChromeClearance(context)),
    ]);
  }
}
