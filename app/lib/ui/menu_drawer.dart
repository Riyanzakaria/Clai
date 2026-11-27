import 'package:flutter/material.dart';

import '../app.dart';
import '../core/clai_icons.dart';
import '../core/tokens.dart';
import '../l10n/l10n.dart';
import 'session_vault_screen.dart';
import 'settings_screen.dart';
import 'taste_control_screen.dart';

/// Laci Menu Clai (Ronde 8079 — "Pisah Pengaturan", varian L7/L8 yang
/// MENANG atas vonis riyan "bagus" 22 Nov; spec
/// `desain-f3/pisah-pengaturan/ADDENDUM-L7-L8.md`).
///
/// Prinsip riyan 22 Nov 16:46 yang mengikat: **"drawer hanya berisi
/// pintu, bukan isi halaman"** — satu daftar datar EMPAT pintu tanpa
/// kicker kelompok dan tanpa baris yang meledak; ruang kosong di bawah
/// daftar memang dibiarkan kosong. Pintu yang menampung fitur yang
/// akan datang: fitur masa depan menyatu ke halaman berpintu yang ada
/// atau menjadi SATU pintu baru — bukan baris baru di laci.
///
/// Penempatan: laci disajikan di navigator AKAR (menutupi seluruh
/// cangkang termasuk chrome melayang — di maket navbar & mini player
/// ikut teredup di balik kerudung), meluncur dari KANAN (sisi yang
/// sama dengan tombolnya), permukaan PADAT surface-1 (aturan kaca:
/// lembar/laci tetap padat). Dibuka HANYA lewat ketukan tombol markah
/// — tidak ada gestur geser-tepi untuk membuka (di Android tepi layar
/// milik gestur Kembali). Menutup: ✕, ketuk kerudung, atau Kembali.
bool _claiMenuOpen = false;

/// Atom wordmark Clai: kata "Clai" Inter Tight ditutup TITIK VOLT di
/// AKHIR — "Clai." (keputusan pemilik 26 Nov 2026; DS 6.6 Bab 12.2
/// butir 1). Titiknya adalah glif titik milik font tampilan itu sendiri
/// (span berwarna Volt): ukuran, jarak, dan garis dasarnya persis titik
/// kalimat fontnya — bukan lingkaran gambar terpisah. Tanda tangan yang
/// sama dirender kartu bagikan QR. Rumah atom ini: kepala laci di bawah
/// + kartu bagikan QR (tombol markah TIDAK lagi membawanya — Ronde 8094).
class ClaiWordmark extends StatelessWidget {
  final double fontSize;
  const ClaiWordmark({super.key, this.fontSize = 21});

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        style: displayStyle(fontSize),
        children: [
          const TextSpan(text: 'Clai'),
          TextSpan(
            text: '.',
            style: TextStyle(color: ClaiColors.accent),
          ),
        ],
      ),
    );
  }
}

/// Tombol markah pengganti gir Pengaturan di kepala Beranda & Koleksi:
/// lingkaran tonal surface-2 40dp berisi MARKAH LOGO Clai asli
/// (busur C + segitiga putar, [ClaiMark]) dalam putih signal netral —
/// keputusan pemilik 26 Nov 2026 menggantikan atom mini ("C" + titik
/// Volt) ronde 8079. BUKAN abu redup, BUKAN Volt: pagar DS 6.6 Bab 12.2
/// butir 1. Lingkaran tonal memberi daya tangkap ketuk yang tidak
/// dimiliki logo polos (amendemen ayu yang dipertahankan riyan pada
/// vonis L7/L8).
class ClaiMarkButton extends StatelessWidget {
  final VoidCallback onPressed;
  const ClaiMarkButton({super.key, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: context.l10n.menuButtonLabel,
      child: Material(
        color: ClaiColors.surface2,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: 40,
            height: 40,
            child: Center(
              child: ClaiMark(size: 21, color: ClaiColors.ink),
            ),
          ),
        ),
      ),
    );
  }
}

/// Buka laci Menu dari konteks pemanggil (Beranda/Koleksi). Konteks
/// pemanggil DITANGKAP sebelum laci tampil: pintu-pintunya didorong ke
/// navigator pemanggil (navigator cangkang — halaman konten hidup di
/// bawah chrome melayang), bukan ke navigator akar tempat laci tinggal.
/// Penjaga buka-ganda: ketukan cepat beruntun pada tombol markah tidak
/// menumpuk dua laci.
Future<void> showClaiMenuDrawer(BuildContext context) async {
  if (_claiMenuOpen) return;
  _claiMenuOpen = true;
  final hostContext = context;
  try {
    await showGeneralDialog<void>(
      context: claiRootContext(context),
      barrierDismissible: true,
      barrierLabel: context.l10n.menuButtonLabel,
      barrierColor: ClaiColors.scrim,
      transitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (dialogContext, animation, secondaryAnimation) =>
          _ClaiMenuDrawer(hostContext: hostContext),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.24, 0),
            end: Offset.zero,
          ).animate(curved),
          child: FadeTransition(opacity: curved, child: child),
        );
      },
    );
  } finally {
    _claiMenuOpen = false;
  }
}

class _ClaiMenuDrawer extends StatelessWidget {
  final BuildContext hostContext;
  const _ClaiMenuDrawer({required this.hostContext});

  void _go(BuildContext dialogContext, Widget page) {
    Navigator.of(dialogContext).pop();
    if (!hostContext.mounted) return;
    Navigator.of(hostContext).push(MaterialPageRoute(builder: (_) => page));
  }

  // Ronde 8089 (Bagian D, pola baris utilitas gaya Figma): pintu =
  // baris datar TEPAT 68 — ikon telanjang 24, judul font tampilan
  // 17/700 SATU baris + subjudul 13 SATU baris ringkas (pola baris
  // 8089 menggantikan wajah R3 ronde 8083: label 15/600, tinggi 64).
  // Prinsip pintu 8079 tetap: laci hanya berisi pintu, bukan isi
  // halaman.
  Widget _door(
    BuildContext dialogContext, {
    required ClaiIconData icon,
    required String title,
    required String subtitle,
    required Widget page,
  }) {
    return InkWell(
      onTap: () => _go(dialogContext, page),
      child: SizedBox(
        height: 68,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              ClaiIcon(icon, size: 24, color: ClaiColors.ink),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: rowTitleStyle(),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      subtitle,
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
              const SizedBox(width: 8),
              ClaiIcon(
                ClaiIcons.chevronRight,
                size: 18,
                color: ClaiColors.inkFaint,
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final width = MediaQuery.sizeOf(context).width * 0.86;
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        width: width,
        height: double.infinity,
        decoration: const BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: Color(0x73000000),
              blurRadius: 28,
              offset: Offset(-10, 0),
            ),
          ],
        ),
        // Material = permukaan padat surface-1 SEKALIGUS leluhur
        // Material yang wajib untuk riak InkWell pintu (rute dialog
        // tidak menyediakan Material sendiri).
        child: Material(
          color: ClaiColors.surface1,
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 12, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const ClaiWordmark(),
                          const Spacer(),
                          IconButton(
                            icon: ClaiIcon(
                              ClaiIcons.close,
                              color: ClaiColors.inkSecondary,
                            ),
                            tooltip: l.a11yClose,
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                _door(
                  context,
                  icon: ClaiIcons.pulse,
                  title: l.tasteTitle,
                  subtitle: l.menuTasteSub,
                  page: const TasteControlScreen(),
                ),
                const Divider(
                  height: 1,
                  indent: 20,
                  endIndent: 20,
                  color: ClaiColors.divider,
                ),
                _door(
                  context,
                  icon: ClaiIcons.history,
                  title: l.vaultTitle,
                  subtitle: l.menuVaultSub,
                  page: const SessionVaultScreen(),
                ),
                const Divider(
                  height: 1,
                  indent: 20,
                  endIndent: 20,
                  color: ClaiColors.divider,
                ),
                _door(
                  context,
                  icon: ClaiIcons.folder,
                  title: l.groupOwnership,
                  subtitle: l.menuOwnershipSub,
                  page: const OwnershipPage(),
                ),
                const Divider(
                  height: 1,
                  indent: 20,
                  endIndent: 20,
                  color: ClaiColors.divider,
                ),
                _door(
                  context,
                  icon: ClaiIcons.settings,
                  title: l.settingsTitle,
                  subtitle: l.menuSettingsSub,
                  page: const SettingsScreen(),
                ),
                // Ruang kosong di bawah daftar memang dibiarkan kosong
                // (prinsip pintu: laci tidak diisi baris tambahan).
                const Spacer(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
