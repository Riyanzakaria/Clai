import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app.dart';
import '../core/clai_icons.dart';
import '../core/tokens.dart';
import '../l10n/l10n.dart';
import '../services/update_service.dart';
import 'queue_screen.dart';
import 'session_vault_screen.dart';
import 'share_playlist_sheet.dart';
import 'taste_control_screen.dart';

/// Pengumuman sesudah update (Ronde 8079, maket B1/B2 yang diterima
/// riyan 22 Nov — spec `desain-f3/pisah-pengaturan/BANNER-UPDATE.md`).
///
/// Isi SELALU dari mesin 8069 yang sama: blok `## Yang baru` badan
/// rilis lewat `userFacingNotes` — tidak ada teks pengumuman yang
/// dikarang di klien. Judul B1 adalah bacaan polos "Yang baru di Clai":
/// data updater tidak membawa codename di mana pun (badan rilis mulai
/// di `## Yang baru`, tag hanya `v<name>+<build>`, judul rilis GitHub
/// tidak di-parse) — versi hidup di kicker.
///
/// B1 (rilis fitur): overlay kartu PADAT surface-1 radius 20 di atas
/// Beranda yang teredup, SEKALI per versi. Hanya dua tombolnya yang
/// menghitung sebagai "terjawab" (CTA / "Nanti saja" → basis
/// tampil-sekali dimajukan di UpdateController.dismissAnnouncement);
/// menutup lewat Kembali atau aplikasi mati sebelum menjawab berarti
/// tampil lagi pada buka dingin berikutnya. B2 (rilis tambalan):
/// spanduk ramping surface-2 di bawah sapaan Beranda.

bool _featureAnnouncementShownThisSession = false;

/// Pemicu overlay B1 yang tinggal di Beranda: mengawasi
/// UpdateController — kapan pun pengumuman tingkat fitur bersenjata
/// (evaluasi penyalaan bersifat asinkron dan bisa selesai sesudah
/// bingkai pertama Beranda), overlay ditampilkan lewat penjaga sesi
/// di [maybeShowFeatureAnnouncement].
class FeatureAnnouncementTrigger extends ConsumerWidget {
  const FeatureAnnouncementTrigger({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final upd = ref.watch(updateControllerProvider);
    if (upd.hasAnnouncement &&
        upd.announceTier == AnnouncementTier.feature) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) maybeShowFeatureAnnouncement(context, ref);
      });
    }
    return const SizedBox.shrink();
  }
}

/// Panggil dari Beranda (kedua varian) sesudah bingkai pertama: tampil
/// overlay B1 bila mesin pengumuman bersenjata di tingkat fitur.
/// Penjaga sesi mencegah tampil ganda saat Beranda dibangun ulang;
/// penjaga per-versi hidup di UpdateController.
Future<void> maybeShowFeatureAnnouncement(
    BuildContext context, WidgetRef ref) async {
  if (_featureAnnouncementShownThisSession) return;
  final upd = ref.read(updateControllerProvider);
  if (!upd.hasAnnouncement ||
      upd.announceTier != AnnouncementTier.feature) {
    return;
  }
  _featureAnnouncementShownThisSession = true;
  await showDialog<void>(
    context: claiRootContext(context),
    barrierDismissible: false,
    barrierColor: ClaiColors.scrim,
    builder: (_) => const _FeatureAnnouncementCard(),
  );
}

ClaiIconData _iconForSurface(AnnounceSurface? surface) {
  switch (surface) {
    case AnnounceSurface.vault:
      return ClaiIcons.history;
    case AnnounceSurface.share:
      return ClaiIcons.share;
    case AnnounceSurface.taste:
      return ClaiIcons.pulse;
    case AnnounceSurface.shuffle:
      return ClaiIcons.shuffle;
    case null:
      return ClaiIcons.check;
  }
}

/// Kartu B1. Keadaan pengumuman DITANGKAP SEKALI saat kartu lahir
/// (snapshot): menutup pengumuman mengosongkan keadaan di controller,
/// dan kartu yang masih beranimasi keluar tidak boleh ikut kosong.
class _FeatureAnnouncementCard extends ConsumerStatefulWidget {
  const _FeatureAnnouncementCard();

  @override
  ConsumerState<_FeatureAnnouncementCard> createState() =>
      _FeatureAnnouncementCardState();
}

class _FeatureAnnouncementCardState
    extends ConsumerState<_FeatureAnnouncementCard> {
  late final String _version;
  late final List<String> _notes;

  @override
  void initState() {
    super.initState();
    final upd = ref.read(updateControllerProvider);
    _version = upd.announceVersionName;
    _notes = List<String>.of(upd.announceNotes);
  }

  Future<void> _answer() async {
    await ref.read(updateControllerProvider).dismissAnnouncement();
  }

  Future<void> _followCta(AnnounceSurface surface) async {
    final navigator = Navigator.of(context);
    await _answer();
    if (!mounted) return;
    navigator.pop();
    switch (surface) {
      case AnnounceSurface.vault:
        navigator.push(MaterialPageRoute(
            builder: (_) => const SessionVaultScreen()));
      case AnnounceSurface.share:
        await openSharePlaylistPicker(navigator.context, ref);
      case AnnounceSurface.taste:
        navigator.push(MaterialPageRoute(
            builder: (_) => const TasteControlScreen()));
      case AnnounceSurface.shuffle:
        navigator.push(
            MaterialPageRoute(builder: (_) => const QueueScreen()));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final highlights = _notes.take(4).toList();
    final topSurface =
        _notes.isEmpty ? null : announceSurfaceFor(_notes.first);
    final ctaLabel = switch (topSurface) {
      AnnounceSurface.vault => l.announceCtaVault,
      AnnounceSurface.share => l.announceCtaShare,
      AnnounceSurface.taste => l.announceCtaTaste,
      AnnounceSurface.shuffle => l.announceCtaShuffle,
      null => l.announceStart,
    };
    return Dialog(
      backgroundColor: ClaiColors.surface1,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ClaiRadius.sheet)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l.announceKicker(_version),
                style: const TextStyle(
                    color: ClaiColors.inkFaint,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.6)),
            const SizedBox(height: 8),
            Text(l.announceTitle, style: displayStyle(22)),
            const SizedBox(height: 16),
            for (final item in highlights) ...[
              _highlightRow(item),
              const SizedBox(height: 12),
            ],
            if (_notes.length > 4)
              InkWell(
                onTap: () => openInstalledNotesSheet(context, _notes),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(l.announceMoreCount(_notes.length - 4),
                      style: const TextStyle(
                          color: ClaiColors.inkSecondary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600)),
                ),
              ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: () async {
                if (topSurface == null) {
                  final navigator = Navigator.of(context);
                  await _answer();
                  navigator.pop();
                } else {
                  await _followCta(topSurface);
                }
              },
              child: Text(ctaLabel),
            ),
            const SizedBox(height: 4),
            TextButton(
              onPressed: () async {
                final navigator = Navigator.of(context);
                await _answer();
                navigator.pop();
              },
              child: Text(l.commonLater),
            ),
          ],
        ),
      ),
    );
  }

  Widget _highlightRow(String item) {
    final parts = splitAnnounceItem(item);
    final surface = announceSurfaceFor(item);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClaiIcon(_iconForSurface(surface),
            size: 20, color: ClaiColors.ink),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(parts.title,
                  style: const TextStyle(
                      color: ClaiColors.ink,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      height: 1.35)),
              if (parts.subtitle != null) ...[
                const SizedBox(height: 2),
                Text(parts.subtitle!,
                    style: const TextStyle(
                        color: ClaiColors.inkSecondary,
                        fontSize: 13,
                        height: 1.4)),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Lembar catatan versi TERPASANG — pasangan B2 "Lihat" dan baris
/// "+N lainnya" di B1. Catatan diteruskan sebagai snapshot oleh
/// pemanggil (menutup pengumuman mengosongkan keadaan controller).
/// Lembar 8069 (untuk rilis yang TERSEDIA) tidak disentuh.
Future<void> openInstalledNotesSheet(
    BuildContext context, List<String> notes) {
  return showModalBottomSheet<void>(
    context: claiRootContext(context),
    isScrollControlled: true,
    backgroundColor: ClaiColors.surface1,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
          top: Radius.circular(ClaiRadius.sheet)),
    ),
    builder: (_) => _InstalledNotesSheet(notes: notes),
  );
}

class _InstalledNotesSheet extends StatelessWidget {
  final List<String> notes;
  const _InstalledNotesSheet({required this.notes});

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: ClaiColors.surface3,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(l.announceTitle, style: displayStyle(20)),
            const SizedBox(height: 14),
            for (final item in notes) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 7),
                    child: Container(
                      width: 5,
                      height: 5,
                      decoration: const BoxDecoration(
                        color: ClaiColors.signal,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(item,
                        style: const TextStyle(
                            color: ClaiColors.ink,
                            fontSize: 14,
                            height: 1.45)),
                  ),
                ],
              ),
              const SizedBox(height: 10),
            ],
          ],
        ),
      ),
    );
  }
}

/// Spanduk konfirmasi B2 (rilis tambalan): ramping, surface-2, di
/// bawah sapaan Beranda di samping spanduk ketersediaan 8069. "Lihat"
/// hanya bila catatan versi terpasang ada; ✕ menutup untuk selamanya
/// (basis tampil-sekali dimajukan).
class PatchInstalledBanner extends ConsumerWidget {
  const PatchInstalledBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final upd = ref.watch(updateControllerProvider);
    if (!upd.hasAnnouncement ||
        upd.announceTier != AnnouncementTier.patch) {
      return const SizedBox.shrink();
    }
    final l = context.l10n;
    final notes = upd.announceNotes;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Container(
        decoration: BoxDecoration(
          color: ClaiColors.surface2,
          borderRadius: BorderRadius.circular(ClaiRadius.card),
        ),
        padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
        child: Row(
          children: [
            ClaiIcon(ClaiIcons.check, size: 18, color: ClaiColors.ink),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l.patchInstalledTitle(upd.announceVersionName),
                      style: const TextStyle(
                          color: ClaiColors.ink,
                          fontSize: 14,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 1),
                  Text(l.patchInstalledSub,
                      style: const TextStyle(
                          color: ClaiColors.inkSecondary, fontSize: 13)),
                ],
              ),
            ),
            if (notes.isNotEmpty)
              TextButton(
                onPressed: () async {
                  await upd.dismissAnnouncement();
                  if (context.mounted) {
                    openInstalledNotesSheet(context, notes);
                  }
                },
                child: Text(l.patchInstalledSee),
              ),
            IconButton(
              icon: ClaiIcon(ClaiIcons.close,
                  size: 16, color: ClaiColors.inkSecondary),
              tooltip: l.a11yClose,
              onPressed: () => upd.dismissAnnouncement(),
            ),
          ],
        ),
      ),
    );
  }
}
