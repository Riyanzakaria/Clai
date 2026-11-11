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

/// Pengaturan (F2 Batch 2.1 — reorganisasi dua tingkat atas keluhan riyan
/// "panjang banget, susah dibaca"): layar atas hanya DAFTAR KELOMPOK pendek
/// dengan ringkasan satu baris; tiap kelompok membuka halaman sub berisi
/// kendalinya. TIDAK ada pengaturan yang hilang — yang berubah hanya
/// tempatnya (pemetaan lama → baru tercatat di RINGKASAN bukti f2b21) dan
/// panjang teks baris (penjelasan panjang pindah ke catatan kaki halaman
/// kelompoknya).
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l.settingsTitle)),
      // Ronde 8052: hub finite → FiniteScrollPage (extent eksak, tanpa
      // koreksi offset yang melawan seretan lambat).
      body: FiniteScrollPage(children: [
        // Hub KELOMPOK KARTU (papan 06, Ronde Koreksi Komposisi F3):
        // label kelompok = kicker huruf-besar redup di atas SATU kartu
        // tonal radius 20 berisi baris-barisnya. Grup TAMPILAN pertama
        // (urutan papan) dengan kendali SEBARIS di hub; kelompok lain
        // baris berikon-kotak + chevron di kartu kelompoknya, membuka
        // sub-halaman yang sama seperti sebelumnya. Tidak ada
        // pengaturan yang hilang atau ganda.
        _groupCard(
          context,
          l.groupAppearance,
          const _TampilanCard(),
        ),
        _footnote(l.appearanceFootnote),
        _groupCard(
          context,
          l.groupPlayback,
          _groupRow(context, ClaiIcons.playCircle, l.groupPlayback,
              l.groupPlaybackSum, const _PlaybackPage()),
        ),
        _groupCard(
          context,
          l.groupAudio,
          _groupRow(context, ClaiIcons.musicNote, l.groupAudio,
              l.groupAudioSum, const _AudioPage()),
        ),
        _groupCard(
          context,
          l.groupDownloads,
          _groupRow(context, ClaiIcons.download, l.groupDownloads,
              l.groupDownloadsSum, const _DownloadsPage()),
        ),
        _groupCard(
          context,
          l.groupDriving,
          _groupRow(context, ClaiIcons.radio, l.groupDriving,
              l.groupDrivingSum,
              _GroupPage(l.groupDriving, [const DrivingSection()], icon: ClaiIcons.radio, summary: l.groupDrivingSum)),
        ),
        _groupCard(
          context,
          l.groupCapture,
          _groupRow(context, ClaiIcons.link, l.groupCapture,
              l.groupCaptureSum,
              _GroupPage(l.groupCapture, [settingsSection(l.captureLinkTitle, [const _CaptureLinkTile()]), settingsSectionWidget(l.ocrModelTitle, const OcrModelSettingsSection())], icon: ClaiIcons.link, summary: l.groupCaptureSum)),
        ),
        _groupCard(
          context,
          l.groupBackground,
          _groupRow(context, ClaiIcons.battery, l.groupBackground,
              l.groupBackgroundSum, const _BackgroundPage()),
        ),
        _groupCard(
          context,
          l.groupData,
          _groupRow(context, ClaiIcons.folder, l.groupData, l.groupDataSum,
              const _DataPage()),
        ),
        _groupCard(
          context,
          l.groupUpdates,
          _groupRow(context, ClaiIcons.refresh, l.groupUpdates,
              l.groupUpdatesSum,
              _GroupPage(l.groupUpdates, [settingsSectionPanel(const UpdateSettingsSection())], icon: ClaiIcons.refresh, summary: l.groupUpdatesSum)),
        ),
        _groupCard(
          context,
          l.groupListenBrainz,
          _groupRow(context, ClaiIcons.history, l.groupListenBrainz,
              l.groupListenBrainzSum,
              _GroupPage(l.groupListenBrainz, [settingsSectionPanel(const ListenBrainzSettingsSection())], icon: ClaiIcons.history, summary: l.groupListenBrainzSum)),
        ),
        _groupCard(
          context,
          l.groupDiagnostics,
          _groupRow(context, ClaiIcons.shield, l.groupDiagnostics,
              l.groupDiagnosticsSum, const _DiagnosisPage()),
        ),
        _groupCard(
          context,
          l.groupAbout,
          _groupRow(context, ClaiIcons.info, l.groupAbout, l.groupAboutSum,
              const _AboutPage()),
        ),
        SizedBox(height: bottomChromeClearance(context)),
      ]),
    );
  }

  /// Satu kelompok hub: kicker redup huruf-besar + kartu tonal radius 20.
  Widget _groupCard(BuildContext context, String label, Widget child) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              label.toUpperCase(),
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.8,
                color: ClaiColors.inkSecondary,
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: ClaiColors.surface1,
              borderRadius: BorderRadius.circular(20),
            ),
            clipBehavior: Clip.antiAlias,
            child: child,
          ),
        ],
      ),
    );
  }

  /// Baris pintu kelompok di dalam kartunya: ikon-kotak tonal + judul +
  /// ringkasan + chevron, membuka sub-halaman kelompok yang sama.
  Widget _groupRow(BuildContext context, ClaiIconData icon, String title,
      String summary, Widget page) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: ClaiColors.surface2,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(child: ClaiIcon(icon, color: ClaiColors.accent, size: 22)),
      ),
      title: Text(title,
          style: const TextStyle(
              color: ClaiColors.ink, fontSize: 15, fontWeight: FontWeight.w500)),
      subtitle: Text(summary,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: ClaiColors.inkSecondary, fontSize: 13)),
      trailing: ClaiIcon(ClaiIcons.chevronRight, color: ClaiColors.inkFaint),
      onTap: () => Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => page)),
    );
  }
}

/// Kerangka halaman sub kelompok — Gelombang 2 (pola pengaturan.md):
/// baris kembali sendiri (target 48, tanpa judul di bar atas), lalu
/// BLOK KEPALA (ubin ikon tonal 46 + judul display 20 + ringkasan),
/// lalu seksi-seksi berkicker. Perilaku & nilai kendali tidak berubah.
class _GroupPage extends StatelessWidget {
  final String title;
  final List<Widget> children;
  final ClaiIconData? icon;
  final String? summary;
  const _GroupPage(this.title, this.children, {this.icon, this.summary});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FiniteScrollPage(padding: EdgeInsets.zero, children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
              8, MediaQuery.paddingOf(context).top + 8, 8, 0),
          child: Align(
            alignment: Alignment.centerLeft,
            child: IconButton(
              icon: ClaiIcon(ClaiIcons.arrowBack, color: ClaiColors.ink),
              tooltip: context.l10n.a11yBack,
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
          child: Row(children: [
            if (icon != null) ...[
              tonalIconBox(icon!, size: 46, iconSize: 22),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: displayStyle(20)),
                  if (summary != null) ...[
                    const SizedBox(height: 3),
                    Text(summary!,
                        style: const TextStyle(
                            color: ClaiColors.inkSecondary,
                            fontSize: 13,
                            height: 1.4)),
                  ],
                ],
              ),
            ),
          ]),
        ),
        ...children,
        SizedBox(height: bottomChromeClearance(context)),
      ]),
    );
  }
}

/// Panel kartu kelompok di halaman sub (Ronde Sapuan 8045): bahasa
/// kartu yang sama seperti hub Pengaturan (tonal surface-1, radius
/// 20) — sub-halaman tidak lagi daftar datar di atas latar polos.
/// [rows] diselingi garis pemisah menjorok; catatan kaki tetap di
/// luar panel (lewat _footnote seperti biasa).
Widget settingsPanel(List<Widget> rows, {double top = 18}) {
  final children = <Widget>[];
  for (var i = 0; i < rows.length; i++) {
    if (i > 0) {
      children.add(const Padding(
        padding: EdgeInsets.only(left: 16, right: 16),
        child: Divider(height: 1, color: ClaiColors.divider),
      ));
    }
    children.add(rows[i]);
  }
  return Padding(
    padding: EdgeInsets.fromLTRB(16, top, 16, 0),
    child: Container(
      decoration: BoxDecoration(
        color: ClaiColors.surface1,
        borderRadius: BorderRadius.circular(20),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    ),
  );
}

/// Satu seksi halaman sub (pola pengaturan.md): kicker huruf-besar
/// redup DI ATAS panel (jarak 8), panel surface-1 radius 20 memuat
/// SATU keluarga kendali. Kicker memakai gaya yang sama seperti label
/// kelompok hub papan 06.
Widget settingsSection(String kicker, List<Widget> rows) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 0),
        child: Text(
          kicker.toUpperCase(),
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.8,
            color: ClaiColors.inkSecondary,
          ),
        ),
      ),
      settingsPanel(rows, top: 8),
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
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 0),
        child: Text(
          kicker.toUpperCase(),
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.8,
            color: ClaiColors.inkSecondary,
          ),
        ),
      ),
      settingsSectionPanel(section, top: 8),
    ],
  );
}

/// Panel untuk SATU seksi utuh (EQ, Berkendara, Pembaruan, dsb.) yang
/// membangun baris-barisnya sendiri: bungkus kartunya saja, isi dan
/// perilaku seksi tidak disentuh.
Widget settingsSectionPanel(Widget section, {double top = 18}) => Padding(
      padding: EdgeInsets.fromLTRB(16, top, 16, 0),
      child: Container(
        decoration: BoxDecoration(
          color: ClaiColors.surface1,
          borderRadius: BorderRadius.circular(20),
        ),
        clipBehavior: Clip.antiAlias,
        child: section,
      ),
    );

/// Catatan kaki penjelasan panjang di halaman kelompok — pengganti paragraf
/// multi-baris yang dulu menempel di tiap baris daftar atas.
Widget _footnote(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Text(text,
          style: const TextStyle(
              color: ClaiColors.inkFaint, fontSize: 13, height: 1.5)),
    );

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
    final s = await db.pref<bool>('playback.smartShuffle');
    final t = await db.pref<String>('playback.transition');
    final x = await db.pref<double>('playback.crossfadeSecs');
    final ds = await db.pref<bool>('playback.dataSaver');
    final fb = await db.pref<String>('playback.focusBehavior');
    if (mounted) {
      setState(() {
        if (q != null) _quality = StreamQuality.values.asNameMap()[q] ?? StreamQuality.normal;
        if (a != null) _autoplay = a;
        if (r != null) _autoResume = r;
        if (s != null) _smartShuffle = s;
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
          title: context.l10n.setQuality,
          leading: tonalIconBox(ClaiIcons.gauge, size: 40, iconSize: 20),
          value: _quality,
          items: [for (final q in StreamQuality.values) DropdownMenuItem(value: q, child: Text(qualityLabel(context, q)))],
          onChanged: (q) async {
            if (q == null) return;
            // D-03: hemat data aktif + jaringan seluler → kualitas Tinggi
            // dicegah (PRD 5.13); nyatakan sebabnya, jangan diam-diam.
            if (q == StreamQuality.high && _dataSaver) {
              await handler.refreshNetworkKind();
              if (handler.networkKind == 'mobile') {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(context.l10n.setDataSaverCellularBlock)));
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
        secondary: tonalIconBox(ClaiIcons.wifiOff, size: 40, iconSize: 20),
        title: Text(context.l10n.setDataSaver, style: const TextStyle(color: ClaiColors.ink)),
        subtitle: Text(context.l10n.setDataSaverSub, style: const TextStyle(color: ClaiColors.inkSecondary)),
        value: _dataSaver,
        onChanged: (v) async {
          setState(() => _dataSaver = v);
          await handler.setDataSaver(v);
        },
      ),
      ]),
      settingsSection(context.l10n.setFocusBehavior, [
      DropdownTile<String>(
          title: context.l10n.setFocusBehavior,
          leading: tonalIconBox(ClaiIcons.pulse, size: 40, iconSize: 20),
          value: _focusBehavior,
          items: [
            DropdownMenuItem(value: 'duck', child: Text(context.l10n.focusDuck)),
            DropdownMenuItem(value: 'pause', child: Text(context.l10n.focusPause)),
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
        secondary: tonalIconBox(ClaiIcons.playCircle, size: 40, iconSize: 20),
        title: Text(context.l10n.setAutoplay, style: const TextStyle(color: ClaiColors.ink)),
        subtitle: Text(context.l10n.setAutoplaySub, style: const TextStyle(color: ClaiColors.inkSecondary)),
        value: _autoplay,
        onChanged: (v) async { setState(() => _autoplay = v); await handler.setAutoplayGlobal(v); },
      ),
      SwitchListTile(
        secondary: tonalIconBox(ClaiIcons.shuffle, size: 40, iconSize: 20),
        title: Text(context.l10n.setSmartShuffle, style: const TextStyle(color: ClaiColors.ink)),
        subtitle: Text(context.l10n.setSmartShuffleSub, style: const TextStyle(color: ClaiColors.inkSecondary)),
        value: _smartShuffle,
        onChanged: (v) async { setState(() => _smartShuffle = v); await handler.setSmartShuffle(v); },
      ),
      SwitchListTile(
        secondary: tonalIconBox(ClaiIcons.history, size: 40, iconSize: 20),
        title: Text(context.l10n.setAutoResume, style: const TextStyle(color: ClaiColors.ink)),
        subtitle: Text(context.l10n.setAutoResumeSub, style: const TextStyle(color: ClaiColors.inkSecondary)),
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
          title: context.l10n.setTransition,
          leading: tonalIconBox(ClaiIcons.repeat, size: 40, iconSize: 20),
          subtitle: context.l10n.setTransitionSub,
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
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(context.l10n.transitionSnack)));
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
      _footnote(context.l10n.playbackFootnote),
    ], icon: ClaiIcons.playCircle, summary: context.l10n.groupPlaybackSum);
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
          leading: tonalIconBox(ClaiIcons.musicNote, size: 40, iconSize: 20),
          title: Text(context.l10n.eqTitle,
              style: const TextStyle(color: ClaiColors.ink)),
          subtitle: Text(context.l10n.eqSubtitle,
              style: const TextStyle(color: ClaiColors.inkSecondary)),
          trailing: ClaiIcon(ClaiIcons.chevronRight, color: ClaiColors.inkFaint),
          onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const EqScreen())),
        ),
      ]),
      settingsSection(context.l10n.setNormalization, [
        const NormalizationTile(),
      ]),
      _footnote(context.l10n.audioFootnote),
    ], icon: ClaiIcons.musicNote, summary: context.l10n.groupAudioSum);
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
      if (mounted && b != null) setState(() => _quotaGb = b <= 0 ? 0 : (b / (1024 * 1024 * 1024)).round());
    });
  }

  @override
  Widget build(BuildContext context) {
    final handler = ref.read(audioHandlerProvider);
    return _GroupPage(context.l10n.groupDownloads, [
      settingsSection(context.l10n.dlQuotaLabel, [
      DropdownTile<int>(
          title: context.l10n.dlQuotaLabel,
          leading: tonalIconBox(ClaiIcons.folder, size: 40, iconSize: 20),
          value: _quotaGb,
          items: [
            DropdownMenuItem(value: 0, child: Text(context.l10n.dlQuotaUnlimited)),
            for (final gb in [2, 4, 8])
              DropdownMenuItem(value: gb, child: Text(context.l10n.dlQuotaGb(gb))),
          ],
          onChanged: (v) async {
            if (v == null) return;
            setState(() => _quotaGb = v);
            await ref.read(appDbProvider).setPref(
                'downloads.quotaBytes', v <= 0 ? 0 : v * 1024 * 1024 * 1024);
          },
      ),
      ]),
      settingsSection(context.l10n.setOfflineMode, [
      SwitchListTile(
        secondary: tonalIconBox(ClaiIcons.cloudOff, size: 40, iconSize: 20),
        title: Text(context.l10n.setOfflineMode, style: const TextStyle(color: ClaiColors.ink)),
        subtitle: Text(context.l10n.setOfflineModeSub, style: const TextStyle(color: ClaiColors.inkSecondary)),
        value: _offline,
        onChanged: (v) async { setState(() => _offline = v); await handler.setOfflineMode(v); },
      ),
      ]),
      settingsSection(context.l10n.dlTitle, [
      ListTile(
        leading: tonalIconBox(ClaiIcons.download, size: 40, iconSize: 20),
        title: Text(context.l10n.setManageDownloads, style: const TextStyle(color: ClaiColors.ink)),
        subtitle: Text(context.l10n.setManageDownloadsSub, style: const TextStyle(color: ClaiColors.inkSecondary)),
        trailing: ClaiIcon(ClaiIcons.chevronRight, color: ClaiColors.inkFaint),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DownloadsScreen())),
      ),
      ]),
      _footnote(context.l10n.downloadsFootnote),
    ], icon: ClaiIcons.download, summary: context.l10n.groupDownloadsSum);
  }
}

// ----------------------------------------------------------------- Tampilan
/// Isi kartu TAMPILAN di hub Pengaturan (papan 06): kendali grup ini
/// SEBARIS di hub — bukan pintu ke sub-halaman — dan semuanya berfungsi
/// dari sini (saklar tema, segmen kekuatan, napas, kurangi efek, nama
/// sapaan, aksen dinamis, bahasa). Bekas halaman _AppearancePage pensiun;
/// tidak ada kendali yang hilang, tempatnya saja yang pindah ke hub.
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
        title: Text(l10n.setGreetingName,
            style: const TextStyle(color: ClaiColors.ink)),
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

  /// Satu baris kendali kartu Tampilan (papan 06): ikon-kotak tonal +
  /// judul + keterangan + kendali kanan. [onTap] membuat seluruh baris
  /// bisa diketuk (baris Nama Sapaan).
  Widget _hubRow({
    required ClaiIconData icon,
    required String title,
    String? sub,
    required Widget trailing,
    VoidCallback? onTap,
  }) {
    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Row(children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: ClaiColors.surface2,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(child: ClaiIcon(icon, color: ClaiColors.accent, size: 22)),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      color: ClaiColors.ink,
                      fontSize: 16,
                      fontWeight: FontWeight.w600)),
              if (sub != null) ...[
                const SizedBox(height: 2),
                Text(sub,
                    style: const TextStyle(
                        color: ClaiColors.inkSecondary,
                        fontSize: 13,
                        height: 1.35)),
              ],
            ],
          ),
        ),
        const SizedBox(width: 12),
        trailing,
      ]),
    );
    if (onTap == null) return row;
    return InkWell(onTap: onTap, child: row);
  }

  Widget _hubDivider() => const Padding(
        padding: EdgeInsets.only(left: 74, right: 16),
        child: Divider(height: 1, color: ClaiColors.divider),
      );

  /// Segmen Tenang/Hidup papan 06 (menggantikan dropdown Kekuatan
  /// Ambien): pil terpilih Volt; nonaktif saat Tema Dinamis mati —
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
            color: selected ? ClaiColors.accent : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: selected
                      ? ClaiColors.onAccent
                      : ClaiColors.inkSecondary)),
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
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          seg(l.ambientCalm, AmbientStrength.tenang),
          seg(l.ambientLively, AmbientStrength.hidup),
        ]),
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
    final amb = ref.watch(ambientControllerProvider.select(ambientUiSlice)); // 8053 B(i): irisan tanpa napas
    final ctrl = ref.read(ambientControllerProvider.notifier);
    return Column(children: [
      _hubRow(
        icon: ClaiIcons.contrast,
        title: l.setThemeDynamic,
        sub: l.setThemeDynamicSub,
        trailing: Switch(
          value: amb.enabled,
          onChanged: (v) => ctrl.setEnabled(v),
        ),
      ),
      _hubDivider(),
      _hubRow(
        icon: ClaiIcons.sun,
        title: l.setAmbientStrength,
        sub: l.setAmbientStrengthSub,
        trailing: const SizedBox.shrink(),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(74, 0, 16, 14),
        child: Align(
          alignment: Alignment.centerRight,
          child: _ambientSegment(amb, ctrl),
        ),
      ),
      _hubDivider(),
      _hubRow(
        icon: ClaiIcons.pulse,
        title: l.setAmbientBreathing,
        sub: l.setAmbientBreathingSub,
        trailing: Switch(
          value: amb.breathing,
          onChanged: amb.enabled ? (v) => ctrl.setBreathing(v) : null,
        ),
      ),
      _hubDivider(),
      _hubRow(
        icon: ClaiIcons.gauge,
        title: l.setReduceEffects,
        sub: l.setReduceEffectsSub,
        trailing: Switch(
          value: amb.reduceEffects,
          onChanged: (v) => ctrl.setReduceEffects(v),
        ),
      ),
      _hubDivider(),
      _hubRow(
        icon: ClaiIcons.person,
        title: l.setGreetingName,
        sub: _greetingName.isEmpty ? l.setGreetingNameSub : _greetingName,
        trailing: ClaiIcon(ClaiIcons.chevronRight, color: ClaiColors.inkFaint),
        onTap: () => _editGreetingName(context),
      ),
      _hubDivider(),
      _hubRow(
        icon: ClaiIcons.album,
        title: l.setDynamicAccent,
        sub: l.setDynamicAccentSub,
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
        sub: l.languageSub,
        trailing: const SizedBox.shrink(),
      ),
      // Audit 8047 (pola bertumpuk §6.14, preseden baris Kekuatan
      // Ambien): dropdown Bahasa pindah ke baris lebar-penuh di bawah
      // barisnya — pola trailing lama meremas kolom teks jadi ±82 dp
      // ("Langu/age", subjudul 5 baris).
      Padding(
        padding: const EdgeInsets.fromLTRB(74, 0, 16, 14),
        child: BoundedDropdown<String>(
          value: ref.watch(localeOverrideProvider) ?? 'system',
          maxWidth: double.infinity,
          items: [
            DropdownMenuItem(value: 'system', child: Text(l.languageSystem)),
            const DropdownMenuItem(value: 'id', child: Text('Bahasa Indonesia')),
            const DropdownMenuItem(value: 'en', child: Text('English')),
          ],
          onChanged: (v) async {
            if (v == null) return;
            ref.read(localeOverrideProvider.notifier).state =
                v == 'system' ? null : v;
            if (v == 'system') {
              await db.setPref('ui.language', '');
            } else {
              await db.setPref('ui.language', v);
            }
          },
        ),
      ),
    ]);
  }
}

// ------------------------------------------------------------------ Tangkap
class _CaptureLinkTile extends StatelessWidget {
  const _CaptureLinkTile();
  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: tonalIconBox(ClaiIcons.link, size: 40, iconSize: 20),
      title: Text(context.l10n.captureLinkTitle, style: const TextStyle(color: ClaiColors.ink)),
      subtitle: Text(context.l10n.captureLinkSub, style: const TextStyle(color: ClaiColors.inkSecondary)),
      trailing: ClaiIcon(ClaiIcons.chevronRight, color: ClaiColors.inkFaint),
      // Dialognya kini implementasi bersama di capture_sheet.dart
      // (dipakai juga pintu Tangkap di layar Cari, butir 6 F2.5).
      onTap: () => openCaptureTextInput(context),
    );
  }
}

// -------------------------------------------------------------- Jalan di Latar
class _BackgroundPage extends ConsumerStatefulWidget {
  const _BackgroundPage();
  @override
  ConsumerState<_BackgroundPage> createState() => _BackgroundPageState();
}

class _BackgroundPageState extends ConsumerState<_BackgroundPage> {
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

  @override
  Widget build(BuildContext context) {
    final ok = _notifGranted && _batteryExempt;
    return _GroupPage(context.l10n.groupBackground, [
      settingsSection(context.l10n.setBgStatus, [
      ListTile(
        leading: tonalIconBox(ok ? ClaiIcons.checkCircle : ClaiIcons.batteryAlert,
            size: 40, iconSize: 20, color: ok ? ClaiColors.accent : ClaiColors.warning),
        title: Text(context.l10n.setBgStatus, style: const TextStyle(color: ClaiColors.ink)),
        subtitle: Text(
            context.l10n.bgStatusLine(_batteryExempt ? context.l10n.bgBatteryExempt : context.l10n.bgBatteryNotYet, _notifGranted ? context.l10n.bgPermGranted : context.l10n.bgPermNotYet),
            style: const TextStyle(color: ClaiColors.inkSecondary)),
      ),
      if (!ok)
        ListTile(
          leading: tonalIconBox(ClaiIcons.shield, size: 40, iconSize: 20),
          title: Text(context.l10n.setAllow, style: const TextStyle(color: ClaiColors.ink, fontWeight: FontWeight.w600)),
          subtitle: Text(context.l10n.setAllowSub, style: const TextStyle(color: ClaiColors.inkSecondary)),
          onTap: _requestBackground,
        ),
      ]),
      settingsSection(context.l10n.setSectionDeviceGuides, [
      ListTile(
        leading: tonalIconBox(ClaiIcons.phone, size: 40, iconSize: 20, color: ClaiColors.inkFaint),
        title: Text(context.l10n.setXiaomi, style: const TextStyle(color: ClaiColors.ink)),
        subtitle: Text(context.l10n.setXiaomiSub, style: const TextStyle(color: ClaiColors.inkSecondary)),
        trailing: ClaiIcon(ClaiIcons.external, color: ClaiColors.inkFaint),
        onTap: () => openAppSettings(),
      ),
      // D-31: panduan per merek LENGKAP (sebelumnya Samsung satu baris,
      // Oppo/vivo catatan kaki, Huawei tidak ada sama sekali).
      ListTile(
        leading: tonalIconBox(ClaiIcons.phone, size: 40, iconSize: 20, color: ClaiColors.inkFaint),
        title: Text(context.l10n.setSamsung, style: const TextStyle(color: ClaiColors.ink)),
        subtitle: Text(context.l10n.setSamsungSub, style: const TextStyle(color: ClaiColors.inkSecondary)),
      ),
      ListTile(
        leading: tonalIconBox(ClaiIcons.phone, size: 40, iconSize: 20, color: ClaiColors.inkFaint),
        title: Text(context.l10n.setOppo, style: const TextStyle(color: ClaiColors.ink)),
        subtitle: Text(context.l10n.setOppoSub, style: const TextStyle(color: ClaiColors.inkSecondary)),
      ),
      ListTile(
        leading: tonalIconBox(ClaiIcons.phone, size: 40, iconSize: 20, color: ClaiColors.inkFaint),
        title: Text(context.l10n.setHuawei, style: const TextStyle(color: ClaiColors.ink)),
        subtitle: Text(context.l10n.setHuaweiSub, style: const TextStyle(color: ClaiColors.inkSecondary)),
      ),
      ListTile(
        leading: tonalIconBox(ClaiIcons.info, size: 40, iconSize: 20, color: ClaiColors.inkFaint),
        title: Text(context.l10n.setOtherBrands, style: const TextStyle(color: ClaiColors.ink)),
        subtitle: Text(context.l10n.setOtherBrandsSub, style: const TextStyle(color: ClaiColors.inkSecondary)),
      ),
      ]),
      // D-31: kejujuran deteksi — autostart TIDAK bisa dideteksi otomatis.
      _footnote(context.l10n.bgAutostartNote),
      _footnote(context.l10n.backgroundFootnote),
    ], icon: ClaiIcons.battery, summary: context.l10n.groupBackgroundSum);
  }
}

// ----------------------------------------------------------- Data & Penyimpanan
class _DataPage extends ConsumerStatefulWidget {
  const _DataPage();
  @override
  ConsumerState<_DataPage> createState() => _DataPageState();
}

class _DataPageState extends ConsumerState<_DataPage> {
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
    return _GroupPage(context.l10n.groupData, [
      settingsSection(context.l10n.setHistoryRetention, [
      DropdownTile<int>(
          title: context.l10n.setHistoryRetention,
          leading: tonalIconBox(ClaiIcons.history, size: 40, iconSize: 20),
          value: _historyDays,
          items: [
            for (final d in [30, 90, 365])
              DropdownMenuItem(value: d, child: Text(context.l10n.histDays(d))),
            DropdownMenuItem(value: -1, child: Text(context.l10n.histForever)),
          ],
          onChanged: (v) async {
            if (v == null) return;
            setState(() => _historyDays = v);
            await db.setPref('data.historyDays', v);
          },
      ),
      ListTile(
        leading: tonalIconBox(ClaiIcons.clearAll, size: 40, iconSize: 20),
        title: Text(context.l10n.setClearHistory, style: const TextStyle(color: ClaiColors.ink)),
        subtitle: Text(context.l10n.setClearHistorySub, style: const TextStyle(color: ClaiColors.inkSecondary)),
        onTap: () async {
          await db.clearHistory();
          if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.l10n.historyClearedSnack)));
        },
      ),
      ]),
      settingsSection(context.l10n.setClearCache, [
      ListTile(
        leading: tonalIconBox(ClaiIcons.trash, size: 40, iconSize: 20),
        title: Text(context.l10n.setClearCache, style: const TextStyle(color: ClaiColors.ink)),
        subtitle: Text(context.l10n.setClearCacheSub, style: const TextStyle(color: ClaiColors.inkSecondary)),
        onTap: () async {
          await db.clearStreamCache();
          if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.l10n.cacheClearedSnack)));
        },
      ),
      ]),
    ], icon: ClaiIcons.folder, summary: context.l10n.groupDataSum);
  }
}

// ----------------------------------------------------------------- Diagnosis
class _DiagnosisPage extends StatelessWidget {
  const _DiagnosisPage();
  @override
  Widget build(BuildContext context) {
    return _GroupPage(context.l10n.groupDiagnostics, [
      settingsPanel([
      ListTile(
        leading: tonalIconBox(ClaiIcons.shield, size: 40, iconSize: 20),
        title: Text(context.l10n.setDiagTitle, style: const TextStyle(color: ClaiColors.ink)),
        subtitle: Text(context.l10n.setDiagSub, style: const TextStyle(color: ClaiColors.inkSecondary)),
        trailing: ClaiIcon(ClaiIcons.chevronRight, color: ClaiColors.inkFaint),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PlaybackDiagnosticsScreen())),
      ),
      ListTile(
        leading: tonalIconBox(ClaiIcons.history, size: 40, iconSize: 20),
        title: Text(context.l10n.setLogTitle, style: const TextStyle(color: ClaiColors.ink)),
        subtitle: Text(context.l10n.setLogCount(Observability.instance.entries.length),
            style: const TextStyle(color: ClaiColors.inkSecondary)),
        trailing: ClaiIcon(ClaiIcons.chevronRight, color: ClaiColors.inkFaint),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const _LogScreen())),
      ),
      ]),
    ], icon: ClaiIcons.shield, summary: context.l10n.groupDiagnosticsSum);
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
      settingsPanel([
        ListTile(
          title: Text(
              _versionName == null
                  ? 'Clai'
                  : context.l10n.aboutVersion(_versionName!),
              style: const TextStyle(color: ClaiColors.ink)),
          subtitle: Text(context.l10n.aboutBody,
              style: const TextStyle(color: ClaiColors.inkSecondary, height: 1.5)),
        ),
      ]),
    ], icon: ClaiIcons.info, summary: context.l10n.groupAboutSum);
  }
}

class _LogScreen extends StatelessWidget {
  const _LogScreen();
  @override
  Widget build(BuildContext context) {
    final entries = Observability.instance.entries.reversed.toList();
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.logTitle)),
      body: entries.isEmpty
          ? Center(child: Text(context.l10n.logEmpty, style: const TextStyle(color: ClaiColors.inkSecondary)))
          : FiniteScrollPage(children: [
              // Ronde Sapuan 8045: entri log = kartu tonal radius 16
              // (dulu ListTile datar); isi & urutan entri sama persis.
              for (final e in entries)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                  child: Container(
                    decoration: BoxDecoration(
                      color: ClaiColors.surface1,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(e.kind, style: const TextStyle(color: ClaiColors.ink, fontSize: 14, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 3),
                        Text('${e.at.toIso8601String()}\n${e.detail}', style: const TextStyle(color: ClaiColors.inkSecondary, fontSize: 12, height: 1.45)),
                      ],
                    ),
                  ),
                ),
              SizedBox(height: bottomChromeClearance(context)),
            ]),
    );
  }
}
