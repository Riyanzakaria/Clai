import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import '../app.dart';
import '../core/clai_icons.dart';
import '../core/tokens.dart';
import '../domain/models.dart';
import '../services/ambient_controller.dart';
import '../services/ambient_theme.dart';
import '../services/observability.dart';
import '../services/sys_channel.dart';
import 'downloads_screen.dart';
import 'capture_sheet.dart';
import 'driving_section.dart';
import 'glass.dart';
import 'import_flow.dart';
import 'ownership_sheets.dart';
import 'qr_scan_screen.dart';
import 'session_vault_screen.dart';
import 'taste_control_screen.dart';
import 'share_playlist_sheet.dart';
import 'eq_screen.dart';
import 'eq_section.dart';
import '../l10n/l10n.dart';
import 'listenbrainz_section.dart';
import 'ocr_model_section.dart';
import 'playback_diagnostics.dart';
import 'update_section.dart';
import 'widgets.dart';

/// Label kualitas aliran terlokalisasi (dulu getter di model domain —
/// kini string UI tinggal di ARB sesuai gerbang i18n PRD Bab 3).
String qualityLabel(BuildContext context, StreamQuality q) => switch (q) {
  StreamQuality.low => context.l10n.qualityLow,
  StreamQuality.normal => context.l10n.qualityNormal,
  StreamQuality.high => context.l10n.qualityHigh,
};

/// Pengaturan — Ronde 8076 (Perapian Pengaturan; desain Stitch yang
/// diterima riyan 21 Nov 17:43): hub dipadatkan dari 14 pintu menjadi
/// TUJUH kelompok desain — Tampilan (kini sub-halaman seperti kelompok
/// lain), Pemutaran, Audio, Unduhan & Offline, Kepemilikan, Fitur
/// Tambahan (Berkendara + Tangkap + ListenBrainz), Sistem (Jalan di
/// Latar + Data & Penyimpanan + Pembaruan + Diagnosis) — ditambah
/// Selera (permukaan 2.1.0 yang lebih muda dari desain; kelompok
/// sendiri, keputusan tercatat di PROGRES bukti 8076) dan Tentang
/// sebagai penutup. Di puncak hub: pil kaca "Cari pengaturan" (chrome
/// melayang → kaca, meniru pil pencarian lagu) yang menyaring SELURUH
/// baris pengaturan lewat [settingsSearchIndex]. Reorganisasi murni:
/// tidak ada kunci pref, nilai bawaan, atau perilaku yang berubah —
/// kendali yang sama, rumah yang baru (pemetaan lama → baru di
/// RINGKASAN bukti ronde 8076).
///
/// Ronde 8079 (Pisah Pengaturan; vonis riyan "bagus" 22 Nov): pintu
/// Selera dan Kepemilikan KELUAR dari hub — keduanya kini pintu laci
/// Menu (menu_drawer.dart) sejajar Pengaturan. Hub tinggal TUJUH pintu
/// murni preferensi: Tampilan, Pemutaran, Audio, Unduhan & Offline,
/// Fitur Tambahan, Sistem, Tentang. "Cari pengaturan" tetap mengindeks
/// SEMUA baris termasuk yang pindah, dengan label lokasi jujur dan
/// deep-link ke halaman sebenarnya.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _searchCtrl = TextEditingController();
  final _searchFocus = FocusNode();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    // Pil Cari pengaturan: kaca bertinta saat Tema Dinamis menyala
    // (resep yang sama dengan pil pencarian lagu, papan 04); tema
    // mati → isian surface-1 polos. Bentuk PIL stadium radius 999.
    final ambOn = ref.watch(ambientControllerProvider.select((s) => s.enabled));
    final field = TextField(
      controller: _searchCtrl,
      focusNode: _searchFocus,
      onChanged: (v) => setState(() => _query = v),
      style: const TextStyle(color: ClaiColors.ink),
      decoration: InputDecoration(
        hintText: l.settingsSearchHint,
        hintStyle: const TextStyle(color: ClaiColors.inkFaint),
        prefixIcon: ClaiIcon(ClaiIcons.search, color: ClaiColors.inkSecondary),
        suffixIcon: _searchCtrl.text.isEmpty
            ? null
            : IconButton(
                icon: ClaiIcon(ClaiIcons.close, color: ClaiColors.inkSecondary),
                onPressed: () {
                  _searchCtrl.clear();
                  setState(() => _query = '');
                },
              ),
        filled: true,
        fillColor: ambOn ? Colors.transparent : ClaiColors.surface1,
        contentPadding: const EdgeInsets.symmetric(vertical: 16),
        border: const OutlineInputBorder(
          borderSide: BorderSide.none,
          borderRadius: BorderRadius.all(Radius.circular(999)),
        ),
      ),
    );
    return Scaffold(
      appBar: claiPushedAppBar(context, l.settingsTitle),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: ambOn ? GlassSurface(radius: 999, child: field) : field,
          ),
          Expanded(
            child: _query.trim().isEmpty
                ? _hub(context)
                : _searchResults(context),
          ),
        ],
      ),
    );
  }

  /// Hub kelompok — Ronde 8083 (Pola Pengaturan baru, R1): TUJUH
  /// pintu kini BARIS DATAR langsung di atas latar halaman — tanpa
  /// kartu tonal, tanpa label kelompok kapital di atasnya (label lama
  /// menduplikasi judul pintu; barisnya sendiri yang berbicara).
  /// Baris 60 + hairline 1 + napas 7 = pitch ±68 antar pintu.
  Widget _hub(BuildContext context) {
    final l = context.l10n;
    // Ronde 8052: hub finite → FiniteScrollPage (extent eksak, tanpa
    // koreksi offset yang melawan seretan lambat).
    final doors = <Widget>[
      _groupRow(
        context,
        ClaiIcons.contrast,
        l.groupAppearance,
        l.groupAppearanceSum,
        const _AppearancePage(),
      ),
      _groupRow(
        context,
        ClaiIcons.playCircle,
        l.groupPlayback,
        l.groupPlaybackSum,
        const _PlaybackPage(),
      ),
      _groupRow(
        context,
        ClaiIcons.musicNote,
        l.groupAudio,
        l.groupAudioSum,
        const _AudioPage(),
      ),
      _groupRow(
        context,
        ClaiIcons.download,
        l.groupDownloads,
        l.groupDownloadsSum,
        const _DownloadsPage(),
      ),
      _groupRow(
        context,
        ClaiIcons.flash,
        l.groupExtras,
        l.groupExtrasSum,
        const _ExtrasPage(),
      ),
      _groupRow(
        context,
        ClaiIcons.settings,
        l.groupSystem,
        l.groupSystemSum,
        const _SystemPage(),
      ),
      _groupRow(
        context,
        ClaiIcons.info,
        l.groupAbout,
        l.groupAboutSum,
        const _AboutPage(),
      ),
    ];
    return FiniteScrollPage(
      children: [
        const SizedBox(height: 8),
        for (var i = 0; i < doors.length; i++) ...[
          if (i > 0) ...[
            const Padding(
              // Hairline sejajar awal teks pintu: margin halaman 20 +
              // slot ikon 28 + celah 12 = 60.
              padding: EdgeInsets.only(left: 60, right: 20),
              child: Divider(height: 1, color: ClaiColors.divider),
            ),
            const SizedBox(height: 7),
          ],
          doors[i],
        ],
        SizedBox(height: bottomChromeClearance(context)),
      ],
    );
  }

  /// Hasil "Cari pengaturan": baris yang judul/kelompok/kata kuncinya
  /// memuat kata kunci; ketuk = deep-link ke permukaan terdalam yang
  /// relevan (keputusan tercatat di PROGRES bukti 8076 — desain diam
  /// soal scroll-to/highlight). Keadaan kosong jujur, bukan jalan buntu.
  Widget _searchResults(BuildContext context) {
    final l = context.l10n;
    final q = _query.trim().toLowerCase();
    final hits = settingsSearchIndex(context)
        .where(
          (e) =>
              e.title.toLowerCase().contains(q) ||
              e.group.toLowerCase().contains(q) ||
              e.keywords.toLowerCase().contains(q),
        )
        .toList();
    if (hits.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ClaiIcon(ClaiIcons.searchOff, size: 56, color: ClaiColors.inkFaint),
            const SizedBox(height: 16),
            Text(
              l.settingsSearchEmpty(_query.trim()),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: ClaiColors.ink,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }
    return FiniteScrollPage(
      children: [
        settingsPanel([
          for (final e in hits)
            ListTile(
              minTileHeight: 60,
              titleTextStyle: _panelTitleStyle,
              subtitleTextStyle: _panelSubtitleStyle,
              leading: rowLeadIcon(e.icon, size: 40, iconSize: 24),
              title: Text(
                e.title,
                style: const TextStyle(color: ClaiColors.ink),
              ),
              subtitle: Text(
                e.group,
                style: const TextStyle(color: ClaiColors.inkSecondary),

                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: ClaiIcon(
                ClaiIcons.chevronRight,
                color: ClaiColors.inkFaint,
              ),
              // F-20: kueri dibersihkan SEBELUM halaman tujuan dibuka, jadi
              // Kembali mendarat di hub bersih tanpa keyboard yang membuka
              // lagi sendiri (cacat ronde 8076: kueri + fokus bertahan).
              onTap: () {
                final target = e.target;
                _searchCtrl.clear();
                setState(() => _query = '');
                // Lepas fokus dari node kolom cari itu sendiri —
                // FocusScope.unfocus terbukti tidak cukup (keyboard
                // membuka lagi saat Kembali, temuan live ronde 8076).
                _searchFocus.unfocus();
                Navigator.of(context).push(MaterialPageRoute(builder: target));
              },
            ),
        ]),
        SizedBox(height: bottomChromeClearance(context)),
      ],
    );
  }

  /// Baris pintu hub (Ronde 8083, R1): ikon TELANJANG 24 dalam slot
  /// 28 + judul 15 w600 + SATU baris state pendek 13 inkSecondary
  /// (ringkasan kelompok yang sudah ada) + chevron — tinggi baris 60,
  /// tanpa kartu, membuka sub-halaman kelompok yang sama. Badan
  /// barisnya hidup di [_settingsDoorRow] agar Kepemilikan (Ronde
  /// 8084) memakai baris yang PERSIS sama dengan onTap-nya sendiri.
  Widget _groupRow(
    BuildContext context,
    ClaiIconData icon,
    String title,
    String summary,
    Widget page,
  ) {
    return _settingsDoorRow(
      context,
      icon,
      title,
      summary,
      () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => page)),
    );
  }
}

/// Baris pintu datar kanonik (pola hub Pengaturan): ikon TELANJANG 24
/// dalam slot 28 + label font tampilan [kRowTitleSize]/700 (Ronde 8089 Bagian D;
/// ukuran dikoreksi Ronde 8090) + SATU baris state 13 inkSecondary +
/// chevron, tinggi tepat 60, padding horizontal 20. Satu-satunya
/// implementasi baris pintu di berkas ini — hub memakai-nya lewat
/// _groupRow, Kepemilikan langsung dengan tujuan ketuknya sendiri.
Widget _settingsDoorRow(
  BuildContext context,
  ClaiIconData icon,
  String title,
  String state,
  VoidCallback onTap,
) {
  return InkWell(
    onTap: onTap,
    child: SizedBox(
      height: 60,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(
          children: [
            SizedBox(
              width: 28,
              child: Center(
                child: ClaiIcon(icon, color: ClaiColors.signal, size: 24),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: rowTitleStyle(),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    state,
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
            const SizedBox(width: 12),
            ClaiIcon(ClaiIcons.chevronRight, color: ClaiColors.inkFaint),
          ],
        ),
      ),
    ),
  );
}

/// Satu entri indeks "Cari pengaturan" (Ronde 8076): judul baris persis
/// seperti yang dibaca pengguna, kelompok rumahnya, kata kunci alias,
/// dan pembangun halaman tujuannya.
class SettingsSearchEntry {
  final ClaiIconData icon;
  final String title;
  final String group;
  final String keywords;
  final WidgetBuilder target;
  const SettingsSearchEntry({
    required this.icon,
    required this.title,
    required this.group,
    this.keywords = '',
    required this.target,
  });
}

/// Indeks pencarian pengaturan: SATU entri per baris kendali nyata di
/// seluruh Pengaturan — termasuk permukaan 2.1.0 (Selera, panel Acak di
/// Pemutaran, Brankas Sesi). Kelengkapannya dijaga tes
/// perapian_pengaturan_8076_test.dart: setiap entri wajib ketemu lewat
/// judulnya sendiri. Baris bersyarat (durasi crossfade, unduh/pasang
/// pembaruan) tetap terindeks — halamannya yang menampung keadaannya.
List<SettingsSearchEntry> settingsSearchIndex(BuildContext context) {
  final l = context.l10n;
  SettingsSearchEntry e(
    ClaiIconData icon,
    String title,
    String group,
    WidgetBuilder target, [
    String keywords = '',
  ]) => SettingsSearchEntry(
    icon: icon,
    title: title,
    group: group,
    keywords: keywords,
    target: target,
  );
  // Ronde 8079: subjudul hasil cari = label LOKASI yang jujur. Baris
  // yang menetap di Pengaturan berlabel "Pengaturan · <grup>"; baris
  // yang pindah ke laci Menu berlabel nama halamannya sendiri
  // ("Selera kamu", "Kepemilikan", "Brankas Sesi").
  final locAppearance = '${l.settingsTitle} · ${l.groupAppearance}';
  final locPlayback = '${l.settingsTitle} · ${l.groupPlayback}';
  final locAudio = '${l.settingsTitle} · ${l.groupAudio}';
  final locDownloads = '${l.settingsTitle} · ${l.groupDownloads}';
  final locExtras = '${l.settingsTitle} · ${l.groupExtras}';
  final locSystem = '${l.settingsTitle} · ${l.groupSystem}';
  final locAbout = '${l.settingsTitle} · ${l.groupAbout}';
  return [
    // ---- Tampilan
    e(
      ClaiIcons.contrast,
      l.setThemeDynamic,
      locAppearance,
      (_) => const _AppearancePage(),
    ),
    e(
      ClaiIcons.sun,
      l.setAmbientStrength,
      locAppearance,
      (_) => const _AppearancePage(),
    ),
    e(
      ClaiIcons.pulse,
      l.setAmbientBreathing,
      locAppearance,
      (_) => const _AppearancePage(),
    ),
    e(
      ClaiIcons.gauge,
      l.setReduceEffects,
      locAppearance,
      (_) => const _AppearancePage(),
    ),
    e(
      ClaiIcons.person,
      l.setGreetingName,
      locAppearance,
      (_) => const _AppearancePage(),
    ),
    e(
      ClaiIcons.album,
      l.setDynamicAccent,
      locAppearance,
      (_) => const _AppearancePage(),
    ),
    e(
      ClaiIcons.globe,
      l.languageTitle,
      locAppearance,
      (_) => const _AppearancePage(),
      'language bahasa',
    ),
    // ---- Pemutaran
    e(
      ClaiIcons.gauge,
      l.setQuality,
      locPlayback,
      (_) => const _PlaybackPage(),
      'kualitas streaming quality',
    ),
    e(
      ClaiIcons.wifiOff,
      l.setDataSaver,
      locPlayback,
      (_) => const _PlaybackPage(),
      'hemat data saver',
    ),
    e(
      ClaiIcons.pulse,
      l.setFocusBehavior,
      locPlayback,
      (_) => const _PlaybackPage(),
    ),
    e(
      ClaiIcons.playCircle,
      l.setAutoplay,
      locPlayback,
      (_) => const _PlaybackPage(),
    ),
    e(
      ClaiIcons.shuffle,
      l.setShuffle,
      locPlayback,
      (_) => const _PlaybackPage(),
      'acak shuffle',
    ),
    e(
      ClaiIcons.pulse,
      l.setSmartShuffle,
      locPlayback,
      (_) => const _PlaybackPage(),
      'acak cerdas smart shuffle',
    ),
    e(
      ClaiIcons.history,
      l.setAutoResume,
      locPlayback,
      (_) => const _PlaybackPage(),
    ),
    e(
      ClaiIcons.repeat,
      l.setTransition,
      locPlayback,
      (_) => const _PlaybackPage(),
    ),
    e(
      ClaiIcons.infinity,
      l.setCrossfadeDur,
      locPlayback,
      (_) => const _PlaybackPage(),
    ),
    // ---- Audio
    e(
      ClaiIcons.musicNote,
      l.eqTitle,
      locAudio,
      (_) => const EqScreen(),
      'eq equalizer',
    ),
    e(
      ClaiIcons.gauge,
      l.setNormalization,
      locAudio,
      (_) => const _AudioPage(),
      'normalisasi kenyaringan loudness',
    ),
    // ---- Unduhan & Offline
    e(
      ClaiIcons.folder,
      l.dlQuotaLabel,
      locDownloads,
      (_) => const _DownloadsPage(),
    ),
    e(
      ClaiIcons.cloudOff,
      l.setOfflineMode,
      locDownloads,
      (_) => const _DownloadsPage(),
      'offline luring',
    ),
    e(
      ClaiIcons.download,
      l.setManageDownloads,
      locDownloads,
      (_) => const DownloadsScreen(),
    ),
    // ---- Selera
    e(
      ClaiIcons.eyeOff,
      l.tasteSamaranTitle,
      l.tasteTitle,
      (_) => const TasteControlScreen(),
      'samaran incognito penyamaran',
    ),
    e(
      ClaiIcons.pulse,
      l.tasteMirrorTitle,
      l.tasteTitle,
      (_) => const TasteControlScreen(),
      'cermin mirror',
    ),
    e(
      ClaiIcons.gauge,
      l.tasteWeightsTitle,
      l.tasteTitle,
      (_) => const TasteControlScreen(),
      'bobot weights',
    ),
    e(
      ClaiIcons.clearAll,
      l.tasteExcludeTitle,
      l.tasteTitle,
      (_) => const TasteExclusionsScreen(),
      'keluarkan rekomendasi',
    ),
    e(
      ClaiIcons.trash,
      l.tasteResetTitle,
      l.tasteTitle,
      (_) => const TasteControlScreen(),
    ),
    // ---- Kepemilikan
    e(
      ClaiIcons.upload,
      l.ownExportTitle,
      l.groupOwnership,
      (_) => const OwnershipPage(),
      'ekspor export',
    ),
    e(
      ClaiIcons.download,
      l.ownImportTitle,
      l.groupOwnership,
      (_) => const OwnershipPage(),
      'impor import',
    ),
    e(
      ClaiIcons.share,
      l.ownShareTitle,
      l.groupOwnership,
      (_) => const OwnershipPage(),
      'bagikan share playlist',
    ),
    e(
      ClaiIcons.capture,
      l.ownReceiveTitle,
      l.groupOwnership,
      (_) => const QrScanScreen(),
      'qr pindai scan terima',
    ),
    e(
      ClaiIcons.queue,
      l.vaultTitle,
      l.vaultTitle,
      (_) => const SessionVaultScreen(),
      'brankas sesi session vault',
    ),
    // ---- Fitur Tambahan
    e(
      ClaiIcons.radio,
      l.drvMode,
      locExtras,
      (_) => const _ExtrasPage(),
      'berkendara driving menyetir',
    ),
    e(
      ClaiIcons.sort,
      l.drvScheme,
      locExtras,
      (_) => const _ExtrasPage(),
      'berkendara driving',
    ),
    e(
      ClaiIcons.pulse,
      l.drvAnnounce,
      locExtras,
      (_) => const _ExtrasPage(),
      'berkendara driving pengumuman',
    ),
    e(
      ClaiIcons.gauge,
      l.drvSpeedVolume,
      locExtras,
      (_) => const _ExtrasPage(),
      'berkendara driving volume kecepatan',
    ),
    e(
      ClaiIcons.gauge,
      l.drvVolStop,
      locExtras,
      (_) => const _ExtrasPage(),
      'berkendara driving volume',
    ),
    e(
      ClaiIcons.gauge,
      l.drvVolFast,
      locExtras,
      (_) => const _ExtrasPage(),
      'berkendara driving volume',
    ),
    e(
      ClaiIcons.gauge,
      l.drvAnchor,
      locExtras,
      (_) => const _ExtrasPage(),
      'berkendara driving kecepatan',
    ),
    e(
      ClaiIcons.phone,
      l.drvVehicles,
      locExtras,
      (_) => const _ExtrasPage(),
      'berkendara driving kendaraan bluetooth',
    ),
    e(
      ClaiIcons.link,
      l.captureLinkTitle,
      locExtras,
      (_) => const _ExtrasPage(),
      'tangkap capture tautan link',
    ),
    e(
      ClaiIcons.image,
      l.ocrModelTitle,
      locExtras,
      (_) => const _ExtrasPage(),
      'ocr tangkap gambar model',
    ),
    e(
      ClaiIcons.history,
      l.lbTitle,
      locExtras,
      (_) => const _ExtrasPage(),
      'listenbrainz scrobble',
    ),
    // ---- Sistem
    e(
      ClaiIcons.battery,
      l.setBgStatus,
      locSystem,
      (_) => const _SystemPage(),
      'latar background baterai izin',
    ),
    e(
      ClaiIcons.phone,
      l.setXiaomi,
      locSystem,
      (_) => const _SystemPage(),
      'latar background panduan',
    ),
    e(
      ClaiIcons.phone,
      l.setSamsung,
      locSystem,
      (_) => const _SystemPage(),
      'latar background panduan',
    ),
    e(
      ClaiIcons.phone,
      l.setOppo,
      locSystem,
      (_) => const _SystemPage(),
      'latar background panduan',
    ),
    e(
      ClaiIcons.phone,
      l.setHuawei,
      locSystem,
      (_) => const _SystemPage(),
      'latar background panduan',
    ),
    e(
      ClaiIcons.history,
      l.setHistoryRetention,
      locSystem,
      (_) => const _SystemPage(),
      'retensi riwayat history',
    ),
    e(
      ClaiIcons.clearAll,
      l.setClearHistory,
      locSystem,
      (_) => const _SystemPage(),
      'hapus riwayat clear history',
    ),
    e(
      ClaiIcons.trash,
      l.setClearCache,
      locSystem,
      (_) => const _SystemPage(),
      'hapus cache bersih',
    ),
    e(
      ClaiIcons.refresh,
      l.updateCheck,
      locSystem,
      (_) => const _SystemPage(),
      'pembaruan update periksa versi',
    ),
    e(
      ClaiIcons.refresh,
      l.updateAutoCheck,
      locSystem,
      (_) => const _SystemPage(),
      'pembaruan update otomatis',
    ),
    e(
      ClaiIcons.download,
      l.updateAutoDownload,
      locSystem,
      (_) => const _SystemPage(),
      'pembaruan update unduh otomatis',
    ),
    e(
      ClaiIcons.wifiOff,
      l.updateWifiOnly,
      locSystem,
      (_) => const _SystemPage(),
      'pembaruan update wifi',
    ),
    e(
      ClaiIcons.shield,
      l.setDiagTitle,
      locSystem,
      (_) => const PlaybackDiagnosticsScreen(),
      'diagnosis diagnostik uji',
    ),
    e(
      ClaiIcons.history,
      l.setLogTitle,
      locSystem,
      (_) => const _LogScreen(),
      'log insiden',
    ),
    // ---- Tentang
    e(
      ClaiIcons.info,
      l.groupAbout,
      locAbout,
      (_) => const _AboutPage(),
      'versi version tentang about lisensi',
    ),
  ];
}

/// Kerangka halaman sub kelompok — Gelombang 2 (pola pengaturan.md).
/// Ronde 8089 (Bagian C): kepala tangan lama (baris tombol kembali +
/// blok judul di bawah) diganti SATU baris pola kepala baku layar
/// dorong: [ClaiBackButton] + judul font tampilan DI TENGAH
/// (displayStyle(20), satu baris ellipsis) + penyeimbang 48. Parameter
/// `icon` lama dibuang — ikon kelompok tetap hidup di pintu hub.
/// Perilaku & nilai kendali tidak berubah.
class _GroupPage extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _GroupPage(this.title, this.children);
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FiniteScrollPage(
        padding: EdgeInsets.zero,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              8,
              MediaQuery.paddingOf(context).top + 8,
              8,
              0,
            ),
            child: Row(
              children: [
                const ClaiBackButton(),
                Expanded(
                  child: Text(
                    title,
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
          ...children,
          SizedBox(height: bottomChromeClearance(context)),
        ],
      ),
    );
  }
}

/// Panel baris kelompok di halaman sub — Ronde 8083 (Pola Pengaturan
/// baru): BUKAN lagi kartu tonal surface-1 radius 20. Baris tampil
/// langsung di atas latar halaman dengan padding horizontal 20,
/// diselingi hairline [ClaiColors.divider] yang inset kirinya sejajar
/// awal teks baris (bantalan ListTile 16 + ikon 40 + celah 16 = 72),
/// diikuti napas 7 sehingga pitch antar baris 68 (Ronde 8084).
/// Tanda tangan fungsi dipertahankan persis dari era kartu.
Widget settingsPanel(List<Widget> rows, {double top = 18}) {
  final children = <Widget>[];
  for (var i = 0; i < rows.length; i++) {
    if (i > 0) {
      children.add(
        const Padding(
          padding: EdgeInsets.only(left: 72),
          child: Divider(height: 1, color: ClaiColors.divider),
        ),
      );
      // Ronde 8084: napas 7 sesudah hairline — baris terkunci 60 +
      // hairline + 7 = pitch 68, pola yang sama dengan hub.
      children.add(const SizedBox(height: 7));
    }
    children.add(rows[i]);
  }
  return Padding(
    padding: EdgeInsets.fromLTRB(20, top, 20, 0),
    child: Column(children: children),
  );
}

/// Gaya baris konten panel TERKUNCI (Ronde 8089, Bagian D — pola
/// baris utilitas gaya Figma): judul font tampilan (Inter Tight)
/// [kRowTitleSize]/700 tinta SATU baris (14 sejak Ronde 8090;
/// 17 pada 8089), state/subjudul 13 inkSecondary SATU baris.
/// Dipakai sebagai titleTextStyle/subtitleTextStyle ListTile wilayah
/// Pengaturan; SwitchListTile tidak punya properti itu, jadi gaya
/// labelnya dipasang langsung pada Text judulnya.
const TextStyle _panelTitleStyle = TextStyle(
  fontFamily: kDisplayFontFamily,
  color: ClaiColors.ink,
  fontSize: kRowTitleSize,
  fontWeight: FontWeight.w700,
);
const TextStyle _panelSubtitleStyle = TextStyle(
  color: ClaiColors.inkSecondary,
  fontSize: 13,
);

/// Gaya label seksi Pola Pengaturan baru (Ronde 8083): sentence-case
/// apa adanya — TANPA .toUpperCase() dan TANPA letterSpacing —
/// 13 w600 inkSecondary.
const TextStyle _settingsSectionLabelStyle = TextStyle(
  fontSize: 13,
  fontWeight: FontWeight.w600,
  color: ClaiColors.inkSecondary,
);

/// Satu seksi halaman sub (Pola Pengaturan baru): label seksi
/// sentence-case DI ATAS baris-barisnya — padding atas seksi 18
/// (densitas R5), jarak label → baris pertama 4. Parameter tetap
/// bernama [kicker] demi semua pemanggil lama.
Widget settingsSection(String kicker, List<Widget> rows) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
        child: Text(kicker, style: _settingsSectionLabelStyle),
      ),
      settingsPanel(rows, top: 4),
    ],
  );
}

/// Seperti [settingsSection] tetapi untuk seksi utuh yang membangun
/// barisnya sendiri (EQ formulir lama, Pembaruan, ListenBrainz, OCR).
Widget settingsSectionWidget(String kicker, Widget section) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
        child: Text(kicker, style: _settingsSectionLabelStyle),
      ),
      settingsSectionPanel(section, top: 4),
    ],
  );
}

/// Panel untuk SATU seksi utuh (EQ, Berkendara, Pembaruan, dsb.) yang
/// membangun baris-barisnya sendiri — Ronde 8083: wadah kartunya
/// dibuang; seksi dirender langsung dengan padding halaman yang sama
/// (horizontal 20, atas mengikuti [top]). Isi dan perilaku seksi
/// tidak disentuh.
Widget settingsSectionPanel(Widget section, {double top = 18}) =>
    Padding(padding: EdgeInsets.fromLTRB(20, top, 20, 0), child: section);

// ----------------------------------------------------------------- Tampilan
/// Halaman Tampilan (Ronde 8076): kartu yang dulu SEBARIS di hub kini
/// halaman sub seperti kelompok lain (desain Perapian yang diterima).
/// Isi kartunya — _TampilanCard — tidak berubah satu kendali pun;
/// catatan kaki DS v5.0 pindah ke sini dari hub.
class _AppearancePage extends StatelessWidget {
  const _AppearancePage();

  @override
  Widget build(BuildContext context) {
    return _GroupPage(context.l10n.groupAppearance, [
      settingsSectionPanel(const _TampilanCard()),
    ]);
  }
}

// ---------------------------------------------------------------- Pemutaran
class _PlaybackPage extends ConsumerStatefulWidget {
  const _PlaybackPage();
  @override
  ConsumerState<_PlaybackPage> createState() => _PlaybackPageState();
}

class _PlaybackPageState extends ConsumerState<_PlaybackPage> {
  StreamQuality _quality = StreamQuality.normal;
  bool _autoplay = true;
  bool _autoResume = true;
  bool _shuffle = false;
  bool _smartShuffle = false;
  String _transition = 'gapless';
  double _xfSecs = 6;
  bool _dataSaver = false;
  String _focusBehavior = 'duck';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = ref.read(appDbProvider);
    final q = await db.pref<String>('playback.quality');
    final a = await db.pref<bool>('playback.autoplay');
    final r = await db.pref<bool>('playback.autoResume');
    final sh = await db.pref<bool>('playback.shuffle');
    final s = await db.pref<bool>('playback.smartShuffle');
    final t = await db.pref<String>('playback.transition');
    final x = await db.pref<double>('playback.crossfadeSecs');
    final ds = await db.pref<bool>('playback.dataSaver');
    final fb = await db.pref<String>('playback.focusBehavior');
    if (mounted) {
      setState(() {
        if (q != null) {
          _quality =
              StreamQuality.values.asNameMap()[q] ?? StreamQuality.normal;
        }
        if (a != null) _autoplay = a;
        if (r != null) _autoResume = r;
        // Ronde 8075: sakelar utama Acak + lapisan Cerdas. Pref cerdas
        // yang menyala menyiratkan Acak menyala (keadaan warisan
        // 8066/8067, sebelum pref utama ada).
        if (s != null) _smartShuffle = s;
        _shuffle = sh ?? _smartShuffle;
        if (t != null) _transition = t;
        if (x != null) _xfSecs = x.clamp(1, 12);
        if (ds != null) _dataSaver = ds;
        if (fb != null) _focusBehavior = fb;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final handler = ref.read(audioHandlerProvider);
    final db = ref.read(appDbProvider);
    return _GroupPage(context.l10n.groupPlayback, [
      settingsSection(context.l10n.setQuality, [
        DropdownTile<StreamQuality>(
          flush: true,
          title: context.l10n.setQuality,
          leading: rowLeadIcon(ClaiIcons.gauge, size: 40, iconSize: 24),
          value: _quality,
          items: [
            for (final q in StreamQuality.values)
              DropdownMenuItem(value: q, child: Text(qualityLabel(context, q))),
          ],
          onChanged: (q) async {
            if (q == null) return;
            // D-03: hemat data aktif + jaringan seluler → kualitas Tinggi
            // dicegah (PRD 5.13); nyatakan sebabnya, jangan diam-diam.
            if (q == StreamQuality.high && _dataSaver) {
              await handler.refreshNetworkKind();
              if (handler.networkKind == 'mobile') {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(context.l10n.setDataSaverCellularBlock),
                    ),
                  );
                }
                return;
              }
            }
            setState(() => _quality = q);
            handler.quality = q;
            await db.setPref('playback.quality', q.name);
          },
        ),
        SwitchListTile(
          minTileHeight: 60,
          secondary: rowLeadIcon(ClaiIcons.wifiOff, size: 40, iconSize: 24),
          title: Text(maxLines: 1, overflow: TextOverflow.ellipsis, context.l10n.setDataSaver, style: _panelTitleStyle),
          value: _dataSaver,
          onChanged: (v) async {
            setState(() => _dataSaver = v);
            await handler.setDataSaver(v);
          },
        ),
      ]),
      settingsSection(context.l10n.setFocusBehavior, [
        DropdownTile<String>(
          flush: true,
          title: context.l10n.setFocusBehavior,
          leading: rowLeadIcon(ClaiIcons.pulse, size: 40, iconSize: 24),
          value: _focusBehavior,
          items: [
            DropdownMenuItem(
              value: 'duck',
              child: Text(context.l10n.focusDuck),
            ),
            DropdownMenuItem(
              value: 'pause',
              child: Text(context.l10n.focusPause),
            ),
          ],
          onChanged: (v) async {
            if (v == null) return;
            setState(() => _focusBehavior = v);
            // Terapkan utuh (bidang + konfigurasi sesi): bendera
            // willPauseWhenDucked menentukan peristiwa CAN_DUCK terkirim.
            await handler.applyFocusBehavior(lowersVolume: v != 'pause');
            await db.setPref('playback.focusBehavior', v);
          },
        ),
      ]),
      settingsSection(context.l10n.setSectionFlow, [
        SwitchListTile(
          minTileHeight: 60,
          secondary: rowLeadIcon(ClaiIcons.playCircle, size: 40, iconSize: 24),
          title: Text(maxLines: 1, overflow: TextOverflow.ellipsis, context.l10n.setAutoplay, style: _panelTitleStyle),
          value: _autoplay,
          onChanged: (v) async {
            setState(() => _autoplay = v);
            await handler.setAutoplayGlobal(v);
          },
        ),
        // Ronde 8075: panel Acak gabungan tercermin di Pengaturan
        // sebagai DUA baris — sakelar utama fondasi Jujur + lapisan
        // Cerdas di bawahnya. Mematikan utama mematikan lapisan;
        // menyalakan lapisan menyalakan utama.
        SwitchListTile(
          minTileHeight: 60,
          secondary: rowLeadIcon(ClaiIcons.shuffle, size: 40, iconSize: 24),
          title: Text(maxLines: 1, overflow: TextOverflow.ellipsis, context.l10n.setShuffle, style: _panelTitleStyle),
          value: _shuffle,
          onChanged: (v) async {
            setState(() {
              _shuffle = v;
              if (!v) _smartShuffle = false;
            });
            await handler.setShuffle(v);
          },
        ),
        SwitchListTile(
          minTileHeight: 60,
          secondary: rowLeadIcon(ClaiIcons.pulse, size: 40, iconSize: 24),
          title: Text(maxLines: 1, overflow: TextOverflow.ellipsis, context.l10n.setSmartShuffle, style: _panelTitleStyle),
          value: _smartShuffle,
          onChanged: (v) async {
            setState(() {
              _smartShuffle = v;
              if (v) _shuffle = true;
            });
            await handler.setSmartShuffle(v);
          },
        ),
        SwitchListTile(
          minTileHeight: 60,
          secondary: rowLeadIcon(ClaiIcons.history, size: 40, iconSize: 24),
          title: Text(maxLines: 1, overflow: TextOverflow.ellipsis, context.l10n.setAutoResume, style: _panelTitleStyle),
          value: _autoResume,
          onChanged: (v) async {
            setState(() => _autoResume = v);
            handler.autoResume = v;
            await db.setPref('playback.autoResume', v);
          },
        ),
      ]),
      settingsSection(context.l10n.setTransition, [
        DropdownTile<String>(
          flush: true,
          title: context.l10n.setTransition,
          leading: rowLeadIcon(ClaiIcons.repeat, size: 40, iconSize: 24),
          value: _transition,
          items: const [
            DropdownMenuItem(value: 'gapless', child: Text('Gapless')),
            DropdownMenuItem(value: 'crossfade', child: Text('Crossfade')),
          ],
          onChanged: (v) async {
            if (v == null) return;
            setState(() => _transition = v);
            final pending = await handler.setTransitionMode(v);
            if (pending && mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(context.l10n.transitionSnack)),
              );
            }
          },
        ),
        if (_transition == 'crossfade')
          SettingsSliderBlock(
            icon: ClaiIcons.infinity,
            title: context.l10n.setCrossfadeDur,
            subtitle: context.l10n.crossfadeDurVal(_xfSecs.toStringAsFixed(0)),
            value: _xfSecs,
            min: 1,
            max: 12,
            divisions: 11,
            onChanged: (v) => setState(() => _xfSecs = v),
            onChangeEnd: (v) async => handler.setCrossfadeSecs(v),
          ),
      ]),
    ]);
  }
}

// -------------------------------------------------------------------- Audio
class _AudioPage extends StatelessWidget {
  const _AudioPage();

  @override
  Widget build(BuildContext context) {
    return _GroupPage(context.l10n.groupAudio, [
      settingsSection(context.l10n.eqTitle, [
        ListTile(
          minTileHeight: 60,
          titleTextStyle: _panelTitleStyle,
          subtitleTextStyle: _panelSubtitleStyle,
          leading: rowLeadIcon(ClaiIcons.musicNote, size: 40, iconSize: 24),
          title: Text(maxLines: 1, overflow: TextOverflow.ellipsis, 
            context.l10n.eqTitle,
            style: const TextStyle(color: ClaiColors.ink),
          ),
          trailing: ClaiIcon(
            ClaiIcons.chevronRight,
            color: ClaiColors.inkFaint,
          ),
          onTap: () => Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const EqScreen())),
        ),
      ]),
      settingsSection(context.l10n.setNormalization, [
        const NormalizationTile(),
      ]),
    ]);
  }
}

// ---------------------------------------------------------- Unduhan & Offline
class _DownloadsPage extends ConsumerStatefulWidget {
  const _DownloadsPage();
  @override
  ConsumerState<_DownloadsPage> createState() => _DownloadsPageState();
}

class _DownloadsPageState extends ConsumerState<_DownloadsPage> {
  bool _offline = false;
  int _quotaGb = 0; // 0 = tanpa batas (D-14)

  @override
  void initState() {
    super.initState();
    ref.read(appDbProvider).pref<bool>('offline.enabled').then((o) {
      if (mounted && o != null) setState(() => _offline = o);
    });
    ref.read(appDbProvider).pref<int>('downloads.quotaBytes').then((b) {
      if (mounted && b != null) {
        setState(
          () => _quotaGb = b <= 0 ? 0 : (b / (1024 * 1024 * 1024)).round(),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final handler = ref.read(audioHandlerProvider);
    return _GroupPage(context.l10n.groupDownloads, [
      settingsSection(context.l10n.dlQuotaLabel, [
        DropdownTile<int>(
          flush: true,
          title: context.l10n.dlQuotaLabel,
          leading: rowLeadIcon(ClaiIcons.folder, size: 40, iconSize: 24),
          value: _quotaGb,
          items: [
            DropdownMenuItem(
              value: 0,
              child: Text(context.l10n.dlQuotaUnlimited),
            ),
            for (final gb in [2, 4, 8])
              DropdownMenuItem(
                value: gb,
                child: Text(context.l10n.dlQuotaGb(gb)),
              ),
          ],
          onChanged: (v) async {
            if (v == null) return;
            setState(() => _quotaGb = v);
            await ref
                .read(appDbProvider)
                .setPref(
                  'downloads.quotaBytes',
                  v <= 0 ? 0 : v * 1024 * 1024 * 1024,
                );
          },
        ),
      ]),
      settingsSection(context.l10n.setOfflineMode, [
        SwitchListTile(
          minTileHeight: 60,
          secondary: rowLeadIcon(ClaiIcons.cloudOff, size: 40, iconSize: 24),
          title: Text(maxLines: 1, overflow: TextOverflow.ellipsis, context.l10n.setOfflineMode, style: _panelTitleStyle),
          value: _offline,
          onChanged: (v) async {
            setState(() => _offline = v);
            await handler.setOfflineMode(v);
          },
        ),
      ]),
      settingsSection(context.l10n.dlTitle, [
        ListTile(
          minTileHeight: 60,
          titleTextStyle: _panelTitleStyle,
          subtitleTextStyle: _panelSubtitleStyle,
          leading: rowLeadIcon(ClaiIcons.download, size: 40, iconSize: 24),
          title: Text(maxLines: 1, overflow: TextOverflow.ellipsis, 
            context.l10n.setManageDownloads,
            style: const TextStyle(color: ClaiColors.ink),
          ),
          trailing: ClaiIcon(
            ClaiIcons.chevronRight,
            color: ClaiColors.inkFaint,
          ),
          onTap: () => Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const DownloadsScreen())),
        ),
      ]),
    ]);
  }
}

// ----------------------------------------------------------------- Tampilan
/// Isi kartu TAMPILAN (papan 06): saklar tema, segmen kekuatan, napas,
/// kurangi efek, nama sapaan, aksen dinamis, bahasa. Sejak Ronde 8076
/// kartu ini tinggal di halaman sub _AppearancePage (desain Perapian:
/// Tampilan jadi sub-halaman seperti kelompok lain) — isinya tidak
/// berubah satu kendali pun dari masa ia sebaris di hub.
class _TampilanCard extends ConsumerStatefulWidget {
  const _TampilanCard();
  @override
  ConsumerState<_TampilanCard> createState() => _TampilanCardState();
}

class _TampilanCardState extends ConsumerState<_TampilanCard> {
  bool _dynamicAccent = true;
  String _greetingName = '';

  @override
  void initState() {
    super.initState();
    ref.read(appDbProvider).pref<bool>('ui.dynamicAccent').then((da) {
      if (mounted && da != null) setState(() => _dynamicAccent = da);
    });
    ref.read(appDbProvider).pref<String>('ui.greetingName').then((gn) {
      if (mounted && gn != null) setState(() => _greetingName = gn);
    });
  }

  /// Dialog nama sapaan Beranda (Kampanye Rombak UI): nama yang
  /// ditulis pengguna sendiri di perangkatnya — aplikasi tidak
  /// mengarang nama. Kosong = sapaan tanpa nama.
  Future<void> _editGreetingName(BuildContext context) async {
    final l10n = context.l10n;
    final ctrl = TextEditingController(text: _greetingName);
    final saved = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: ClaiColors.surface2,
        title: Text(maxLines: 1, overflow: TextOverflow.ellipsis, 
          l10n.setGreetingName,
          style: const TextStyle(color: ClaiColors.ink),
        ),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLength: 40,
          style: const TextStyle(color: ClaiColors.ink),
          decoration: claiFieldDecoration(hintText: l10n.greetingNameHint),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, ctrl.text.trim()),
            child: Text(l10n.commonSave),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (saved == null) return;
    setState(() => _greetingName = saved);
    await ref.read(appDbProvider).setPref('ui.greetingName', saved);
  }

  /// Satu baris kendali Tampilan (papan 06; Ronde 8084 disamakan ke
  /// standar panel): padding horizontal 20, tinggi baris TERKUNCI 60,
  /// ikon TELANJANG 28/24 via [rowLeadIcon], label 15/600, sub 13
  /// SATU baris — kotak tonal surface-2-nya pensiun bersama Pola
  /// Pengaturan baru. Celah ikon 24 menjaga awal teks sejajar inset
  /// divider 72 (20 + 28 + 24), sama seperti baris panel lain.
  /// [onTap] membuat seluruh baris bisa diketuk (baris Nama Sapaan).
  Widget _hubRow({
    required ClaiIconData icon,
    required String title,
    String? sub,
    required Widget trailing,
    VoidCallback? onTap,
  }) {
    final row = SizedBox(
      height: 60,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(
          children: [
            rowLeadIcon(icon, size: 28, iconSize: 24),
            const SizedBox(width: 24),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: rowTitleStyle(),
                  ),
                  if (sub != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      sub,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: ClaiColors.inkSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            trailing,
          ],
        ),
      ),
    );
    if (onTap == null) return row;
    return InkWell(onTap: onTap, child: row);
  }

  Widget _hubDivider() => const Padding(
    padding: EdgeInsets.only(left: 72, right: 20),
    child: Divider(height: 1, color: ClaiColors.divider),
  );

  /// Segmen Tenang/Hidup papan 06 (menggantikan dropdown Kekuatan
  /// Ambien): pil terpilih putih tinta (DS v5.0); nonaktif saat Tema
  /// Dinamis mati —
  /// perilaku gerbang yang sama seperti dropdown lama.
  Widget _ambientSegment(AmbientUiState amb, AmbientController ctrl) {
    final l = context.l10n;
    Widget seg(String label, AmbientStrength value) {
      final selected = amb.strength == value;
      return GestureDetector(
        onTap: amb.enabled ? () => ctrl.setStrength(value) : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? ClaiColors.signal : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: selected ? ClaiColors.onSignal : ClaiColors.inkSecondary,
            ),
          ),
        ),
      );
    }

    return Opacity(
      opacity: amb.enabled ? 1 : 0.45,
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: ClaiColors.surface3,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            seg(l.ambientCalm, AmbientStrength.tenang),
            seg(l.ambientLively, AmbientStrength.hidup),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final db = ref.read(appDbProvider);
    final l = context.l10n;
    // DS v4.0 — kendali Tampilan (tema Sampul Hidup). Tema Dinamis
    // adalah saklar induk: mati → seluruh aplikasi kembali ke
    // tampilan v3.1 persis.
    final amb = ref.watch(
      ambientControllerProvider.select(ambientUiSlice),
    ); // 8053 B(i): irisan tanpa napas
    final ctrl = ref.read(ambientControllerProvider.notifier);
    return Column(
      children: [
        _hubRow(
          icon: ClaiIcons.contrast,
          title: l.setThemeDynamic,
          trailing: Switch(
            value: amb.enabled,
            onChanged: (v) => ctrl.setEnabled(v),
          ),
        ),
        _hubDivider(),
        _hubRow(
          icon: ClaiIcons.sun,
          title: l.setAmbientStrength,
          trailing: const SizedBox.shrink(),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(72, 0, 20, 14),
          child: Align(
            alignment: Alignment.centerRight,
            // Ronde 8071 — perbaikan cacat warisan: segmen Tenang/Hidup
            // meluap 6,8px ke kanan pada lebar 360dp dengan metrik huruf
            // lebar (terbukti sudah ada di pohon pristine, RINGKASAN
            // 8070). FittedBox scaleDown TIDAK mengubah tampilan pada
            // ukuran alaminya (huruf asli jauh di bawah batas); ia hanya
            // menyusutkan segmen sepersekian bila isinya melebihi slot —
            // luapan mustahil, juga untuk terjemahan yang lebih panjang
            // atau skala huruf aksesibilitas.
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: _ambientSegment(amb, ctrl),
            ),
          ),
        ),
        _hubDivider(),
        _hubRow(
          icon: ClaiIcons.pulse,
          title: l.setAmbientBreathing,
          trailing: Switch(
            value: amb.breathing,
            onChanged: amb.enabled ? (v) => ctrl.setBreathing(v) : null,
          ),
        ),
        _hubDivider(),
        _hubRow(
          icon: ClaiIcons.gauge,
          title: l.setReduceEffects,
          trailing: Switch(
            value: amb.reduceEffects,
            onChanged: (v) => ctrl.setReduceEffects(v),
          ),
        ),
        _hubDivider(),
        _hubRow(
          icon: ClaiIcons.person,
          title: l.setGreetingName,
          sub: _greetingName.isEmpty ? null : _greetingName,
          trailing: ClaiIcon(
            ClaiIcons.chevronRight,
            color: ClaiColors.inkFaint,
          ),
          onTap: () => _editGreetingName(context),
        ),
        _hubDivider(),
        _hubRow(
          icon: ClaiIcons.album,
          title: l.setDynamicAccent,
          trailing: Switch(
            value: _dynamicAccent,
            onChanged: (v) async {
              setState(() => _dynamicAccent = v);
              await db.setPref('ui.dynamicAccent', v);
            },
          ),
        ),
        _hubDivider(),
        _hubRow(
          icon: ClaiIcons.globe,
          title: l.languageTitle,
          trailing: const SizedBox.shrink(),
        ),
        // Audit 8047 (pola bertumpuk §6.14, preseden baris Kekuatan
        // Ambien): dropdown Bahasa pindah ke baris lebar-penuh di bawah
        // barisnya — pola trailing lama meremas kolom teks jadi ±82 dp
        // ("Langu/age", subjudul 5 baris).
        Padding(
          padding: const EdgeInsets.fromLTRB(72, 0, 20, 14),
          child: BoundedDropdown<String>(
            value: ref.watch(localeOverrideProvider) ?? 'system',
            maxWidth: double.infinity,
            items: [
              DropdownMenuItem(value: 'system', child: Text(l.languageSystem)),
              const DropdownMenuItem(
                value: 'id',
                child: Text('Bahasa Indonesia'),
              ),
              const DropdownMenuItem(value: 'en', child: Text('English')),
            ],
            onChanged: (v) async {
              if (v == null) return;
              ref.read(localeOverrideProvider.notifier).state = v == 'system'
                  ? null
                  : v;
              if (v == 'system') {
                await db.setPref('ui.language', '');
              } else {
                await db.setPref('ui.language', v);
              }
            },
          ),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------------ Tangkap
class _CaptureLinkTile extends StatelessWidget {
  const _CaptureLinkTile();
  @override
  Widget build(BuildContext context) {
    return ListTile(
      minTileHeight: 60,
      titleTextStyle: _panelTitleStyle,
      subtitleTextStyle: _panelSubtitleStyle,
      leading: rowLeadIcon(ClaiIcons.link, size: 40, iconSize: 24),
      title: Text(maxLines: 1, overflow: TextOverflow.ellipsis, 
        context.l10n.captureLinkTitle,
        style: const TextStyle(color: ClaiColors.ink),
      ),
      trailing: ClaiIcon(ClaiIcons.chevronRight, color: ClaiColors.inkFaint),
      // Dialognya kini implementasi bersama di capture_sheet.dart
      // (dipakai juga pintu Tangkap di layar Cari, butir 6 F2.5).
      onTap: () => openCaptureTextInput(context),
    );
  }
}

// -------------------------------------------------------------- Jalan di Latar
/// Seksi Jalan di Latar di halaman Sistem (Ronde 8076 — dulu halaman
/// kelompok sendiri; isi & perilaku izinnya tidak berubah).
class _BackgroundSections extends ConsumerStatefulWidget {
  const _BackgroundSections();
  @override
  ConsumerState<_BackgroundSections> createState() =>
      _BackgroundSectionsState();
}

class _BackgroundSectionsState extends ConsumerState<_BackgroundSections> {
  bool _batteryExempt = false;
  bool _notifGranted = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final exempt = await Permission.ignoreBatteryOptimizations.isGranted;
    final notif = await Permission.notification.isGranted;
    if (mounted) {
      setState(() {
        _batteryExempt = exempt;
        _notifGranted = notif;
      });
    }
  }

  /// Izin latar ala Spotube (v4.1): cukup ketuk "Izinkan" — dialog sistem
  /// yang tampil, tanpa pengguna mengutak-atik pengaturan sendiri.
  Future<void> _requestBackground() async {
    if (!_notifGranted) await Permission.notification.request();
    if (!_batteryExempt) await Permission.ignoreBatteryOptimizations.request();
    _load();
  }

  /// Pintu panduan per merek (Ronde 8084): baris datar terkunci 60 —
  /// nama merek saja 15/600 + chevron; teks instruksinya hidup di
  /// lembar yang dibuka baris ini (rumah sah §13.2), bukan lagi
  /// subjudul multi-baris yang menumpuk di halaman.
  Widget _brandRow(
    BuildContext context,
    ClaiIconData icon,
    String brand,
    String guide, {
    bool appSettingsAction = false,
  }) {
    return ListTile(
      minTileHeight: 60,
      titleTextStyle: _panelTitleStyle,
      subtitleTextStyle: _panelSubtitleStyle,
      leading: rowLeadIcon(
        icon,
        size: 40,
        iconSize: 24,
        color: ClaiColors.inkFaint,
      ),
      title: Text(maxLines: 1, overflow: TextOverflow.ellipsis, brand, style: const TextStyle(color: ClaiColors.ink)),
      trailing: ClaiIcon(ClaiIcons.chevronRight, color: ClaiColors.inkFaint),
      onTap: () =>
          _openBrandGuide(context, brand, guide, appSettings: appSettingsAction),
    );
  }

  /// Lembar padat panduan satu merek (pola lembar aplikasi: permukaan
  /// surface-1 radius sheet + ClaiSheetScaffold): judul nama merek
  /// display 20 + teks instruksi kunci *Sub yang sama sebagai isi
  /// 14/1.5.
  Future<void> _openBrandGuide(
    BuildContext context,
    String brand,
    String guide, {
    bool appSettings = false,
  }) {
    // Ronde 8084 (penutup deviasi W1): baris Xiaomi dulu berketuk
    // langsung openAppSettings(); aksi itu DIPERTAHANKAN sebagai
    // tombol di dalam lembar panduannya (label kunci yang sudah ada).
    final openLabel = context.l10n.scanOpenSettings;
    return showModalBottomSheet<void>(
      context: claiRootContext(context),
      isScrollControlled: true,
      backgroundColor: ClaiColors.surface1,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(ClaiRadius.sheet),
        ),
      ),
      builder: (_) => ClaiSheetScaffold(
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 14),
            child: SheetHandle(),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(brand, style: displayStyle(20)),
                const SizedBox(height: 10),
                Text(
                  guide,
                  style: const TextStyle(
                    color: ClaiColors.inkSecondary,
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
                if (appSettings) ...[
                  const SizedBox(height: 18),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: ClaiColors.signal,
                      foregroundColor: ClaiColors.onSignal,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(ClaiRadius.pill),
                      ),
                    ),
                    onPressed: () => openAppSettings(),
                    child: Text(
                      openLabel,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ok = _notifGranted && _batteryExempt;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        settingsSection(context.l10n.setBgStatus, [
          ListTile(
            minTileHeight: 60,
            titleTextStyle: _panelTitleStyle,
            subtitleTextStyle: _panelSubtitleStyle,
            leading: rowLeadIcon(
              ok ? ClaiIcons.checkCircle : ClaiIcons.batteryAlert,
              size: 40,
              iconSize: 24,
              color: ok ? ClaiColors.signal : ClaiColors.warning,
            ),
            title: Text(maxLines: 1, overflow: TextOverflow.ellipsis, 
              context.l10n.setBgStatus,
              style: const TextStyle(color: ClaiColors.ink),
            ),
            subtitle: Text(
              context.l10n.bgStatusLine(
                _batteryExempt
                    ? context.l10n.bgBatteryExempt
                    : context.l10n.bgBatteryNotYet,
                _notifGranted
                    ? context.l10n.bgPermGranted
                    : context.l10n.bgPermNotYet,
              ),
              style: const TextStyle(color: ClaiColors.inkSecondary),

              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (!ok)
            ListTile(
              minTileHeight: 60,
              titleTextStyle: _panelTitleStyle,
              subtitleTextStyle: _panelSubtitleStyle,
              leading: rowLeadIcon(ClaiIcons.shield, size: 40, iconSize: 24),
              title: Text(maxLines: 1, overflow: TextOverflow.ellipsis, 
                context.l10n.setAllow,
                style: const TextStyle(
                  color: ClaiColors.ink,
                  fontWeight: FontWeight.w600,
                ),
              ),
              onTap: _requestBackground,
            ),
        ]),
        // Ronde 8084 (§13.2): baris panduan per merek kini PINTU DATAR
        // (nama merek saja, terkunci 60, chevron) — teks instruksinya
        // PINDAH ke lembar padat yang dibuka barisnya, rumah sah teks
        // penjelasan. Kunci *Sub yang sama dipakai ulang di lembar.
        settingsSection(context.l10n.setSectionDeviceGuides, [
          _brandRow(
            context,
            ClaiIcons.phone,
            context.l10n.setXiaomi,
            context.l10n.setXiaomiSub,
            appSettingsAction: true,
          ),
          // D-31: panduan per merek LENGKAP (sebelumnya Samsung satu baris,
          // Oppo/vivo catatan kaki, Huawei tidak ada sama sekali).
          _brandRow(
            context,
            ClaiIcons.phone,
            context.l10n.setSamsung,
            context.l10n.setSamsungSub,
          ),
          _brandRow(
            context,
            ClaiIcons.phone,
            context.l10n.setOppo,
            context.l10n.setOppoSub,
          ),
          _brandRow(
            context,
            ClaiIcons.phone,
            context.l10n.setHuawei,
            context.l10n.setHuaweiSub,
          ),
          _brandRow(
            context,
            ClaiIcons.info,
            context.l10n.setOtherBrands,
            context.l10n.setOtherBrandsSub,
          ),
        ]),
        // D-31: kejujuran deteksi — autostart TIDAK bisa dideteksi otomatis.
        // Ronde 8080: catatan kaki latar kedua (paragraf pemecahan masalah
        // per merek) DIHAPUS atas vonis pemilik. Ronde 8084: langkah tiap
        // merek kini tinggal di lembar pintunya masing-masing (di atas).
      ],
    );
  }
}

// ----------------------------------------------------------- Data & Penyimpanan
/// Seksi Data & Penyimpanan di halaman Sistem (Ronde 8076 — dulu
/// halaman kelompok sendiri; retensi, hapus riwayat & hapus cache
/// tidak berubah perilaku).
class _DataSections extends ConsumerStatefulWidget {
  const _DataSections();
  @override
  ConsumerState<_DataSections> createState() => _DataSectionsState();
}

class _DataSectionsState extends ConsumerState<_DataSections> {
  int _historyDays = 365; // -1 = selamanya (Blueprint 2.4, D-11)

  @override
  void initState() {
    super.initState();
    ref.read(appDbProvider).pref<int>('data.historyDays').then((v) {
      if (mounted && v != null) setState(() => _historyDays = v);
    });
  }

  @override
  Widget build(BuildContext context) {
    final db = ref.read(appDbProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        settingsSection(context.l10n.setHistoryRetention, [
          DropdownTile<int>(
            flush: true,
            title: context.l10n.setHistoryRetention,
            leading: rowLeadIcon(ClaiIcons.history, size: 40, iconSize: 24),
            value: _historyDays,
            items: [
              for (final d in [30, 90, 365])
                DropdownMenuItem(
                  value: d,
                  child: Text(context.l10n.histDays(d)),
                ),
              DropdownMenuItem(
                value: -1,
                child: Text(context.l10n.histForever),
              ),
            ],
            onChanged: (v) async {
              if (v == null) return;
              setState(() => _historyDays = v);
              await db.setPref('data.historyDays', v);
            },
          ),
          ListTile(
            minTileHeight: 60,
            titleTextStyle: _panelTitleStyle,
            subtitleTextStyle: _panelSubtitleStyle,
            leading: rowLeadIcon(ClaiIcons.clearAll, size: 40, iconSize: 24),
            title: Text(maxLines: 1, overflow: TextOverflow.ellipsis, 
              context.l10n.setClearHistory,
              style: const TextStyle(color: ClaiColors.ink),
            ),
            onTap: () async {
              await db.clearHistory();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(context.l10n.historyClearedSnack)),
                );
              }
            },
          ),
        ]),
        settingsSection(context.l10n.setClearCache, [
          ListTile(
            minTileHeight: 60,
            titleTextStyle: _panelTitleStyle,
            subtitleTextStyle: _panelSubtitleStyle,
            leading: rowLeadIcon(ClaiIcons.trash, size: 40, iconSize: 24),
            title: Text(maxLines: 1, overflow: TextOverflow.ellipsis, 
              context.l10n.setClearCache,
              style: const TextStyle(color: ClaiColors.ink),
            ),
            onTap: () async {
              await db.clearStreamCache();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(context.l10n.cacheClearedSnack)),
                );
              }
            },
          ),
        ]),
      ],
    );
  }
}

// ----------------------------------------------------------------- Kepemilikan (D2, Ronde 8070)
/// Halaman Kepemilikan: pintu Ekspor/Impor (F-12) dan Bagikan/Terima
/// playlist (Berbagi Tanpa Server terlipat ke D2). Semua tindakan
/// tinggal di ui/ownership_sheets.dart, ui/import_flow.dart,
/// ui/share_playlist_sheet.dart, dan ui/qr_scan_screen.dart.
/// Ronde 8079: halaman ini PUBLIK dan dicapai dari pintu laci Menu
/// (bukan lagi sub-halaman hub Pengaturan); isinya tidak berubah.
class OwnershipPage extends ConsumerWidget {
  const OwnershipPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.l10n;
    // Ronde 8084: kelima baris Kepemilikan kini memakai ulang baris
    // pintu hub (_settingsDoorRow — badan yang sama dengan _groupRow):
    // ikon telanjang 28/24, label 15/600, own*Sub sebagai baris STATE
    // pintu 13 satu baris, chevron, tinggi tepat 60 di dalam struktur
    // settingsSection/settingsPanel yang ada. Tujuan ketuk persis sama
    // seperti era ListTile-nya. Bungkus Material transparan warisan
    // gugur bersama ListTile-nya (InkWell pintu membawa riaknya sendiri).
    return _GroupPage(s.groupOwnership, [
      settingsSection(s.ownSectionData, [
        _settingsDoorRow(
          context,
          ClaiIcons.upload,
          s.ownExportTitle,
          s.ownExportSub,
          () => openExportSheet(context, ref),
        ),
        _settingsDoorRow(
          context,
          ClaiIcons.download,
          s.ownImportTitle,
          s.ownImportSub,
          () => runImportFromFile(context, ref),
        ),
      ]),
      settingsSection(s.ownSectionShare, [
        _settingsDoorRow(
          context,
          ClaiIcons.share,
          s.ownShareTitle,
          s.ownShareSub,
          () => openSharePlaylistPicker(context, ref),
        ),
        _settingsDoorRow(
          context,
          ClaiIcons.capture,
          s.ownReceiveTitle,
          s.ownReceiveSub,
          () => Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const QrScanScreen())),
        ),
      ]),
      // Ronde 8076: pintu Brankas Sesi (S-54) — sesi tersimpan adalah
      // data milik pengguna, rumah logisnya kelompok ini. Pintu lama
      // (AppBar Antrean & rak Beranda) tidak berubah.
      settingsSection(s.ownSectionSessions, [
        _settingsDoorRow(
          context,
          ClaiIcons.queue,
          s.vaultTitle,
          s.ownVaultSub,
          () => Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const SessionVaultScreen())),
        ),
      ]),
    ]);
  }
}

// ------------------------------------------------------------ Fitur Tambahan
/// Halaman Fitur Tambahan (Ronde 8076; penggabungan desain yang
/// diterima): Berkendara + Tangkap + ListenBrainz dalam satu rumah.
/// Seksi-seksinya membangun panelnya sendiri seperti sebelumnya —
/// yang berubah hanya alamatnya.
class _ExtrasPage extends StatelessWidget {
  const _ExtrasPage();

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return _GroupPage(l.groupExtras, [
      const DrivingSection(),
      settingsSection(l.captureLinkTitle, [const _CaptureLinkTile()]),
      settingsSectionWidget(l.ocrModelTitle, const OcrModelSettingsSection()),
      settingsSectionWidget(
        l.groupListenBrainz,
        const ListenBrainzSettingsSection(),
      ),
    ]);
  }
}

// -------------------------------------------------------------------- Sistem
/// Halaman Sistem (Ronde 8076; penggabungan desain yang diterima):
/// Jalan di Latar + Data & Penyimpanan + Pembaruan + Diagnosis.
class _SystemPage extends StatelessWidget {
  const _SystemPage();

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return _GroupPage(l.groupSystem, [
      const _BackgroundSections(),
      const _DataSections(),
      settingsSectionWidget(l.groupUpdates, const UpdateSettingsSection()),
      settingsSection(l.groupDiagnostics, [
        ListTile(
          minTileHeight: 60,
          titleTextStyle: _panelTitleStyle,
          subtitleTextStyle: _panelSubtitleStyle,
          leading: rowLeadIcon(ClaiIcons.shield, size: 40, iconSize: 24),
          title: Text(maxLines: 1, overflow: TextOverflow.ellipsis, 
            l.setDiagTitle,
            style: const TextStyle(color: ClaiColors.ink),
          ),
          trailing: ClaiIcon(
            ClaiIcons.chevronRight,
            color: ClaiColors.inkFaint,
          ),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const PlaybackDiagnosticsScreen(),
            ),
          ),
        ),
        ListTile(
          minTileHeight: 60,
          titleTextStyle: _panelTitleStyle,
          subtitleTextStyle: _panelSubtitleStyle,
          leading: rowLeadIcon(ClaiIcons.history, size: 40, iconSize: 24),
          title: Text(
            l.setLogTitle,
            style: const TextStyle(color: ClaiColors.ink),
          ),
          subtitle: Text(
            l.setLogCount(Observability.instance.entries.length),
            style: const TextStyle(color: ClaiColors.inkSecondary),

            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: ClaiIcon(
            ClaiIcons.chevronRight,
            color: ClaiColors.inkFaint,
          ),
          onTap: () => Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const _LogScreen())),
        ),
      ]),
    ]);
  }
}

// ------------------------------------------------------------------- Tentang
class _AboutPage extends StatefulWidget {
  const _AboutPage();
  @override
  State<_AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<_AboutPage> {
  String? _versionName;

  @override
  void initState() {
    super.initState();
    // Butir terbawa (e) Ronde Sapuan 8045: label versi TIDAK lagi
    // string terprogram di ARB ("Clai 1.0.1" basi sejak 1.1.0) —
    // dibaca dari paket terpasang lewat kanal sistem yang sama
    // seperti layanan pembaruan. Gagal baca → judul tanpa versi,
    // bukan angka karangan.
    SysChannel.appVersion().then((v) {
      if (mounted) setState(() => _versionName = v?.name);
    });
  }

  @override
  Widget build(BuildContext context) {
    return _GroupPage(context.l10n.groupAbout, [
      // Ronde 8084 (§13.2): paragraf aboutBody DIBUANG — yang
      // tinggal hanya baris keadaan fungsional versi/build yang
      // sudah ada. Tidak ada kunci kredit/lisensi PENDEK khusus
      // Tentang di arb (lyrCreditShort itu kredit lirik, bukan
      // kredit aplikasi), jadi tidak ada baris kredit yang dipasang
      // dan tidak ada kunci baru yang dikarang.
      settingsPanel([
        ListTile(
          minTileHeight: 60,
          titleTextStyle: _panelTitleStyle,
          subtitleTextStyle: _panelSubtitleStyle,
          title: Text(maxLines: 1, overflow: TextOverflow.ellipsis, 
            _versionName == null
                ? 'Clai'
                : context.l10n.aboutVersion(_versionName!),
            style: const TextStyle(color: ClaiColors.ink),
          ),
        ),
      ]),
    ]);
  }
}

class _LogScreen extends StatelessWidget {
  const _LogScreen();
  @override
  Widget build(BuildContext context) {
    final entries = Observability.instance.entries.reversed.toList();
    return Scaffold(
      appBar: claiPushedAppBar(context, context.l10n.logTitle),
      body: entries.isEmpty
          ? Center(
              child: Text(
                context.l10n.logEmpty,
                style: const TextStyle(color: ClaiColors.inkSecondary),
              ),
            )
          : FiniteScrollPage(
              children: [
                // Ronde 8084: kartu entri surface-1 radius 16 (Sapuan
                // 8045) DIBUANG — entri kini DATAR di latar halaman,
                // dipisah hairline, padding halaman 20. Isi & urutan
                // entri sama persis (kind 14/600, detail 12/1.45).
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                  child: Column(
                    children: [
                      for (var i = 0; i < entries.length; i++) ...[
                        if (i > 0)
                          const Divider(height: 1, color: ClaiColors.divider),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                entries[i].kind,
                                style: const TextStyle(
                                  color: ClaiColors.ink,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                '${entries[i].at.toIso8601String()}\n${entries[i].detail}',
                                style: const TextStyle(
                                  color: ClaiColors.inkSecondary,
                                  fontSize: 12,
                                  height: 1.45,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                SizedBox(height: bottomChromeClearance(context)),
              ],
            ),
    );
  }
}
