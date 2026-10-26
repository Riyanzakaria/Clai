import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import '../app.dart';
import '../core/clai_icons.dart';
import '../core/tokens.dart';
import '../domain/models.dart';
import '../services/observability.dart';
import 'downloads_screen.dart';
import 'capture_sheet.dart';
import 'driving_section.dart';
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
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.settingsTitle)),
      body: ListView(children: [
        _group(context, ClaiIcons.playCircle, context.l10n.groupPlayback,
            context.l10n.groupPlaybackSum, const _PlaybackPage()),
        _group(context, ClaiIcons.musicNote, context.l10n.groupAudio,
            context.l10n.groupAudioSum, const _AudioPage()),
        _group(context, ClaiIcons.download, context.l10n.groupDownloads,
            context.l10n.groupDownloadsSum, const _DownloadsPage()),
        _group(context, ClaiIcons.album, context.l10n.groupAppearance,
            context.l10n.groupAppearanceSum, const _AppearancePage()),
        _group(context, ClaiIcons.radio, context.l10n.groupDriving,
            context.l10n.groupDrivingSum,
            _GroupPage(context.l10n.groupDriving, const [DrivingSection()])),
        _group(context, ClaiIcons.link, context.l10n.groupCapture,
            context.l10n.groupCaptureSum,
            _GroupPage(context.l10n.groupCapture, const [_CaptureLinkTile(), OcrModelSettingsSection()])),
        _group(context, ClaiIcons.battery, context.l10n.groupBackground,
            context.l10n.groupBackgroundSum, const _BackgroundPage()),
        _group(context, ClaiIcons.folder, context.l10n.groupData,
            context.l10n.groupDataSum, const _DataPage()),
        _group(context, ClaiIcons.refresh, context.l10n.groupUpdates,
            context.l10n.groupUpdatesSum,
            _GroupPage(context.l10n.groupUpdates, const [UpdateSettingsSection()])),
        _group(context, ClaiIcons.history, context.l10n.groupListenBrainz,
            context.l10n.groupListenBrainzSum,
            _GroupPage(context.l10n.groupListenBrainz, const [ListenBrainzSettingsSection()])),
        _group(context, ClaiIcons.shield, context.l10n.groupDiagnostics,
            context.l10n.groupDiagnosticsSum, const _DiagnosisPage()),
        _group(context, ClaiIcons.info, context.l10n.groupAbout,
            context.l10n.groupAboutSum, const _AboutPage()),
        SizedBox(height: bottomChromeClearance(context)),
      ]),
    );
  }

  Widget _group(BuildContext context, ClaiIconData icon, String title,
      String summary, Widget page) {
    return ListTile(
      leading: ClaiIcon(icon, color: ClaiColors.accent),
      title: Text(title, style: const TextStyle(color: ClaiColors.ink)),
      subtitle: Text(summary,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: ClaiColors.inkSecondary)),
      trailing: ClaiIcon(ClaiIcons.chevronRight, color: ClaiColors.inkFaint),
      onTap: () => Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => page)),
    );
  }
}

/// Kerangka halaman sub kelompok: judul di AppBar + daftar gulir.
class _GroupPage extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _GroupPage(this.title, this.children);
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(children: [
        ...children,
        SizedBox(height: bottomChromeClearance(context)),
      ]),
    );
  }
}

/// Catatan kaki penjelasan panjang di halaman kelompok — pengganti paragraf
/// multi-baris yang dulu menempel di tiap baris daftar atas.
Widget _footnote(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Text(text,
          style: const TextStyle(
              color: ClaiColors.inkFaint, fontSize: 12.5, height: 1.5)),
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
      ListTile(
        title: Text(context.l10n.setQuality, style: const TextStyle(color: ClaiColors.ink)),
        subtitle: Text(qualityLabel(context, _quality), style: const TextStyle(color: ClaiColors.inkSecondary)),
        trailing: BoundedDropdown<StreamQuality>(
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
      ),
      SwitchListTile(
        title: Text(context.l10n.setDataSaver, style: const TextStyle(color: ClaiColors.ink)),
        subtitle: Text(context.l10n.setDataSaverSub, style: const TextStyle(color: ClaiColors.inkSecondary)),
        value: _dataSaver, activeThumbColor: ClaiColors.accent,
        onChanged: (v) async {
          setState(() => _dataSaver = v);
          await handler.setDataSaver(v);
        },
      ),
      ListTile(
        title: Text(context.l10n.setFocusBehavior, style: const TextStyle(color: ClaiColors.ink)),
        trailing: BoundedDropdown<String>(
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
      ),
      SwitchListTile(
        title: Text(context.l10n.setAutoplay, style: const TextStyle(color: ClaiColors.ink)),
        subtitle: Text(context.l10n.setAutoplaySub, style: const TextStyle(color: ClaiColors.inkSecondary)),
        value: _autoplay, activeThumbColor: ClaiColors.accent,
        onChanged: (v) async { setState(() => _autoplay = v); await handler.setAutoplayGlobal(v); },
      ),
      SwitchListTile(
        title: Text(context.l10n.setSmartShuffle, style: const TextStyle(color: ClaiColors.ink)),
        subtitle: Text(context.l10n.setSmartShuffleSub, style: const TextStyle(color: ClaiColors.inkSecondary)),
        value: _smartShuffle, activeThumbColor: ClaiColors.accent,
        onChanged: (v) async { setState(() => _smartShuffle = v); await handler.setSmartShuffle(v); },
      ),
      SwitchListTile(
        title: Text(context.l10n.setAutoResume, style: const TextStyle(color: ClaiColors.ink)),
        subtitle: Text(context.l10n.setAutoResumeSub, style: const TextStyle(color: ClaiColors.inkSecondary)),
        value: _autoResume, activeThumbColor: ClaiColors.accent,
        onChanged: (v) async {
          setState(() => _autoResume = v);
          handler.autoResume = v;
          await db.setPref('playback.autoResume', v);
        },
      ),
      ListTile(
        title: Text(context.l10n.setTransition, style: const TextStyle(color: ClaiColors.ink)),
        subtitle: Text(context.l10n.setTransitionSub, style: const TextStyle(color: ClaiColors.inkSecondary)),
        trailing: BoundedDropdown<String>(
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
      ),
      if (_transition == 'crossfade')
        ListTile(
          title: Text(context.l10n.setCrossfadeDur, style: const TextStyle(color: ClaiColors.ink)),
          subtitle: Text(context.l10n.crossfadeDurVal(_xfSecs.toStringAsFixed(0)),
              style: const TextStyle(color: ClaiColors.inkSecondary)),
          trailing: SizedBox(
            width: 160,
            child: Slider(
              value: _xfSecs, min: 1, max: 12, divisions: 11, activeColor: ClaiColors.accent,
              onChanged: (v) => setState(() => _xfSecs = v),
              onChangeEnd: (v) async => handler.setCrossfadeSecs(v),
            ),
          ),
        ),
      _footnote(context.l10n.playbackFootnote),
    ]);
  }
}

// -------------------------------------------------------------------- Audio
class _AudioPage extends ConsumerStatefulWidget {
  const _AudioPage();
  @override
  ConsumerState<_AudioPage> createState() => _AudioPageState();
}

class _AudioPageState extends ConsumerState<_AudioPage> {
  bool _norm = false;

  @override
  void initState() {
    super.initState();
    ref.read(appDbProvider).pref<bool>('playback.normalization').then((n) {
      if (mounted && n != null) setState(() => _norm = n);
    });
  }

  @override
  Widget build(BuildContext context) {
    final handler = ref.read(audioHandlerProvider);
    return _GroupPage(context.l10n.groupAudio, [
      const EqSection(),
      SwitchListTile(
        title: Text(context.l10n.setNormalization, style: const TextStyle(color: ClaiColors.ink)),
        subtitle: Text(context.l10n.setNormalizationSub, style: const TextStyle(color: ClaiColors.inkSecondary)),
        value: _norm, activeThumbColor: ClaiColors.accent,
        onChanged: (v) async {
          setState(() => _norm = v);
          if (v) {
            // Pengukuran memakai Visualizer Android, yang MEWAJIBKAN izin
            // mikrofon walau tidak merekam apa pun (F2 Batch 2.1 — dulu
            // izin ini tidak pernah diminta dari sakelar ini, sehingga di
            // perangkat yang belum pernah memberi izin, pengukuran mati
            // senyap dan semua gain tetap netral).
            final st = await Permission.microphone.request();
            if (!st.isGranted && mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(context.l10n.normMicSnack)));
            }
          }
          await handler.setNormalization(v);
        },
      ),
      _footnote(context.l10n.audioFootnote),
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
      if (mounted && b != null) setState(() => _quotaGb = b <= 0 ? 0 : (b / (1024 * 1024 * 1024)).round());
    });
  }

  @override
  Widget build(BuildContext context) {
    final handler = ref.read(audioHandlerProvider);
    return _GroupPage(context.l10n.groupDownloads, [
      ListTile(
        title: Text(context.l10n.dlQuotaLabel, style: const TextStyle(color: ClaiColors.ink)),
        trailing: BoundedDropdown<int>(
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
      ),
      SwitchListTile(
        title: Text(context.l10n.setOfflineMode, style: const TextStyle(color: ClaiColors.ink)),
        subtitle: Text(context.l10n.setOfflineModeSub, style: const TextStyle(color: ClaiColors.inkSecondary)),
        value: _offline, activeThumbColor: ClaiColors.accent,
        onChanged: (v) async { setState(() => _offline = v); await handler.setOfflineMode(v); },
      ),
      ListTile(
        title: Text(context.l10n.setManageDownloads, style: const TextStyle(color: ClaiColors.ink)),
        subtitle: Text(context.l10n.setManageDownloadsSub, style: const TextStyle(color: ClaiColors.inkSecondary)),
        trailing: ClaiIcon(ClaiIcons.chevronRight, color: ClaiColors.inkFaint),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DownloadsScreen())),
      ),
      _footnote(context.l10n.downloadsFootnote),
    ]);
  }
}

// ----------------------------------------------------------------- Tampilan
class _AppearancePage extends ConsumerStatefulWidget {
  const _AppearancePage();
  @override
  ConsumerState<_AppearancePage> createState() => _AppearancePageState();
}

class _AppearancePageState extends ConsumerState<_AppearancePage> {
  bool _dynamicAccent = true;

  @override
  void initState() {
    super.initState();
    ref.read(appDbProvider).pref<bool>('ui.dynamicAccent').then((da) {
      if (mounted && da != null) setState(() => _dynamicAccent = da);
    });
  }

  @override
  Widget build(BuildContext context) {
    final db = ref.read(appDbProvider);
    return _GroupPage(context.l10n.groupAppearance, [
      SwitchListTile(
        title: Text(context.l10n.setDynamicAccent, style: const TextStyle(color: ClaiColors.ink)),
        subtitle: Text(context.l10n.setDynamicAccentSub, style: const TextStyle(color: ClaiColors.inkSecondary)),
        value: _dynamicAccent, activeThumbColor: ClaiColors.accent,
        onChanged: (v) async { setState(() => _dynamicAccent = v); await db.setPref('ui.dynamicAccent', v); },
      ),
      ListTile(
        title: Text(context.l10n.languageTitle, style: const TextStyle(color: ClaiColors.ink)),
        subtitle: Text(context.l10n.languageSub, style: const TextStyle(color: ClaiColors.inkSecondary)),
        trailing: BoundedDropdown<String>(
          value: ref.watch(localeOverrideProvider) ?? 'system',
          items: [
            DropdownMenuItem(value: 'system', child: Text(context.l10n.languageSystem)),
            const DropdownMenuItem(value: 'id', child: Text('Bahasa Indonesia')),
            const DropdownMenuItem(value: 'en', child: Text('English')),
          ],
          onChanged: (v) async {
            if (v == null) return;
            ref.read(localeOverrideProvider.notifier).state = v == 'system' ? null : v;
            if (v == 'system') {
              await db.setPref('ui.language', '');
            } else {
              await db.setPref('ui.language', v);
            }
          },
        ),
      ),
      _footnote(context.l10n.appearanceFootnote),
    ]);
  }
}

// ------------------------------------------------------------------ Tangkap
class _CaptureLinkTile extends StatelessWidget {
  const _CaptureLinkTile();
  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(context.l10n.captureLinkTitle, style: const TextStyle(color: ClaiColors.ink)),
      subtitle: Text(context.l10n.captureLinkSub, style: const TextStyle(color: ClaiColors.inkSecondary)),
      trailing: ClaiIcon(ClaiIcons.link, color: ClaiColors.inkFaint),
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
      ListTile(
        leading: ClaiIcon(ok ? ClaiIcons.checkCircle : ClaiIcons.batteryAlert,
            color: ok ? ClaiColors.accent : ClaiColors.warning),
        title: Text(context.l10n.setBgStatus, style: const TextStyle(color: ClaiColors.ink)),
        subtitle: Text(
            context.l10n.bgStatusLine(_batteryExempt ? context.l10n.bgBatteryExempt : context.l10n.bgBatteryNotYet, _notifGranted ? context.l10n.bgPermGranted : context.l10n.bgPermNotYet),
            style: const TextStyle(color: ClaiColors.inkSecondary)),
      ),
      if (!ok)
        ListTile(
          leading: ClaiIcon(ClaiIcons.shield, color: ClaiColors.accent),
          title: Text(context.l10n.setAllow, style: const TextStyle(color: ClaiColors.ink, fontWeight: FontWeight.w600)),
          subtitle: Text(context.l10n.setAllowSub, style: const TextStyle(color: ClaiColors.inkSecondary)),
          onTap: _requestBackground,
        ),
      ListTile(
        leading: ClaiIcon(ClaiIcons.phone, color: ClaiColors.inkFaint),
        title: Text(context.l10n.setXiaomi, style: const TextStyle(color: ClaiColors.ink)),
        subtitle: Text(context.l10n.setXiaomiSub, style: const TextStyle(color: ClaiColors.inkSecondary)),
        trailing: ClaiIcon(ClaiIcons.external, color: ClaiColors.inkFaint),
        onTap: () => openAppSettings(),
      ),
      // D-31: panduan per merek LENGKAP (sebelumnya Samsung satu baris,
      // Oppo/vivo catatan kaki, Huawei tidak ada sama sekali).
      ListTile(
        leading: ClaiIcon(ClaiIcons.phone, color: ClaiColors.inkFaint),
        title: Text(context.l10n.setSamsung, style: const TextStyle(color: ClaiColors.ink)),
        subtitle: Text(context.l10n.setSamsungSub, style: const TextStyle(color: ClaiColors.inkSecondary)),
      ),
      ListTile(
        leading: ClaiIcon(ClaiIcons.phone, color: ClaiColors.inkFaint),
        title: Text(context.l10n.setOppo, style: const TextStyle(color: ClaiColors.ink)),
        subtitle: Text(context.l10n.setOppoSub, style: const TextStyle(color: ClaiColors.inkSecondary)),
      ),
      ListTile(
        leading: ClaiIcon(ClaiIcons.phone, color: ClaiColors.inkFaint),
        title: Text(context.l10n.setHuawei, style: const TextStyle(color: ClaiColors.ink)),
        subtitle: Text(context.l10n.setHuaweiSub, style: const TextStyle(color: ClaiColors.inkSecondary)),
      ),
      ListTile(
        leading: ClaiIcon(ClaiIcons.info, color: ClaiColors.inkFaint),
        title: Text(context.l10n.setOtherBrands, style: const TextStyle(color: ClaiColors.ink)),
        subtitle: Text(context.l10n.setOtherBrandsSub, style: const TextStyle(color: ClaiColors.inkSecondary)),
      ),
      // D-31: kejujuran deteksi — autostart TIDAK bisa dideteksi otomatis.
      _footnote(context.l10n.bgAutostartNote),
      _footnote(context.l10n.backgroundFootnote),
    ]);
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
      ListTile(
        title: Text(context.l10n.setHistoryRetention, style: const TextStyle(color: ClaiColors.ink)),
        trailing: BoundedDropdown<int>(
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
      ),
      ListTile(
        title: Text(context.l10n.setClearCache, style: const TextStyle(color: ClaiColors.ink)),
        subtitle: Text(context.l10n.setClearCacheSub, style: const TextStyle(color: ClaiColors.inkSecondary)),
        onTap: () async {
          await db.clearStreamCache();
          if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.l10n.cacheClearedSnack)));
        },
      ),
      ListTile(
        title: Text(context.l10n.setClearHistory, style: const TextStyle(color: ClaiColors.ink)),
        subtitle: Text(context.l10n.setClearHistorySub, style: const TextStyle(color: ClaiColors.inkSecondary)),
        onTap: () async {
          await db.clearHistory();
          if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.l10n.historyClearedSnack)));
        },
      ),
    ]);
  }
}

// ----------------------------------------------------------------- Diagnosis
class _DiagnosisPage extends StatelessWidget {
  const _DiagnosisPage();
  @override
  Widget build(BuildContext context) {
    return _GroupPage(context.l10n.groupDiagnostics, [
      ListTile(
        title: Text(context.l10n.setDiagTitle, style: const TextStyle(color: ClaiColors.ink)),
        subtitle: Text(context.l10n.setDiagSub, style: const TextStyle(color: ClaiColors.inkSecondary)),
        trailing: ClaiIcon(ClaiIcons.chevronRight, color: ClaiColors.inkFaint),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PlaybackDiagnosticsScreen())),
      ),
      ListTile(
        title: Text(context.l10n.setLogTitle, style: const TextStyle(color: ClaiColors.ink)),
        subtitle: Text(context.l10n.setLogCount(Observability.instance.entries.length),
            style: const TextStyle(color: ClaiColors.inkSecondary)),
        trailing: ClaiIcon(ClaiIcons.chevronRight, color: ClaiColors.inkFaint),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const _LogScreen())),
      ),
    ]);
  }
}

// ------------------------------------------------------------------- Tentang
class _AboutPage extends StatelessWidget {
  const _AboutPage();
  @override
  Widget build(BuildContext context) {
    return _GroupPage(context.l10n.groupAbout, [
      ListTile(
        title: Text(context.l10n.aboutVersion, style: const TextStyle(color: ClaiColors.ink)),
        subtitle: Text(context.l10n.aboutBody,
            style: TextStyle(color: ClaiColors.inkSecondary, height: 1.5)),
      ),
    ]);
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
          : ListView(children: [
              for (final e in entries)
                ListTile(
                  title: Text(e.kind, style: const TextStyle(color: ClaiColors.ink, fontSize: 14)),
                  subtitle: Text('${e.at.toIso8601String()}\n${e.detail}', style: const TextStyle(color: ClaiColors.inkSecondary, fontSize: 12)),
                  isThreeLine: true,
                ),
              SizedBox(height: bottomChromeClearance(context)),
            ]),
    );
  }
}
