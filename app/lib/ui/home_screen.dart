import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import '../app.dart';
import '../core/clai_icons.dart';
import '../core/display_text.dart';
import '../core/tokens.dart';
import '../domain/models.dart';
import '../l10n/l10n.dart';
import '../services/ambient_theme.dart';
import 'cover_accent_glow.dart';
import 'glass.dart';
import 'haptics.dart';
import 'jelajah_section.dart';
import 'personal_shelves_section.dart';
import 'playlist_screen.dart';
import 'sleep_resume_card.dart';
import 'player_sheet.dart';
import 'queue_screen.dart';
import 'update_section.dart';
import 'settings_screen.dart';
import 'widgets.dart';

/// Keputusan tampil strip pengingat izin latar (murni, diuji unit):
/// hanya bila pengguna SUDAH pernah memutar, belum pernah menekan
/// "Nanti saja", dan izin latar belum lengkap. Sekali ditolak, strip
/// tidak muncul lagi sampai kondisi izin berubah (Poles Beranda butir 2).
bool bgReminderVisible({
  required bool everPlayed,
  required bool dismissed,
  required bool notifGranted,
  required bool batteryGranted,
}) => everPlayed && !dismissed && !(notifGranted && batteryGranted);

/// Awal minggu berjalan — Senin 00:00 waktu setempat (Kampanye
/// Rombak UI: jendela rak "Paling sering minggu ini"). MURNI & diuji:
/// Minggu masuk minggu yang SEDANG berjalan (awal = Senin sebelumnya),
/// bukan minggu berikutnya.
DateTime weekStartMonday(DateTime now) {
  final d = DateTime(now.year, now.month, now.day);
  return d.subtract(Duration(days: d.weekday - DateTime.monday));
}

/// Baris tanggal kepala Beranda modern (papan B: "SENIN · 9 NOV") —
/// huruf besar, untuk dua locale aplikasi. Tanpa dependensi intl:
/// nama hari/bulan adalah data kalender, dinyatakan sebagai tabel
/// per locale di sini dan diuji. MURNI.
String homeDateKicker(DateTime d, String languageCode) {
  const idDays = ['SENIN', 'SELASA', 'RABU', 'KAMIS', 'JUMAT', 'SABTU', 'MINGGU'];
  const enDays = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
  const idMonths = [
    'JAN', 'FEB', 'MAR', 'APR', 'MEI', 'JUN',
    'JUL', 'AGU', 'SEP', 'OKT', 'NOV', 'DES',
  ];
  const enMonths = [
    'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN',
    'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC',
  ];
  final id = languageCode == 'id';
  final day = (id ? idDays : enDays)[d.weekday - 1];
  final mon = (id ? idMonths : enMonths)[d.month - 1];
  return id ? '$day · ${d.day} $mon' : '$day · $mon ${d.day}';
}

/// Beranda player-first (PRD 5.1; pola diperbarui Ronde Poles Beranda —
/// keputusan riyan 24 Okt 2026, amendemen DS 7.1 tercatat): baris judul
/// ramping → kartu Lanjutkan Sesi (hanya saat tidak aktif memutar) → rel
/// sampul riwayat & personal → Koleksi → rak personal → Jelajah →
/// "Antrian Berikutnya" di paling bawah.
class HomeScreen extends ConsumerStatefulWidget {
  final VoidCallback onGoSearch;
  final VoidCallback? onGoCollection;
  const HomeScreen({super.key, required this.onGoSearch, this.onGoCollection});
  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  List<Track> _recent = [];
  List<Track> _frequent = [];

  /// Rak "Paling sering minggu ini" (Kampanye Rombak UI): hitungan
  /// putar mentah playback_events sejak Senin 00:00 — data nyata;
  /// minggu kosong = daftar kosong = keadaan kosong jujur di layar.
  List<({Track track, int count})> _topWeek = [];

  /// Nama sapaan Beranda (pref `ui.greetingName`, diatur di
  /// Pengaturan → Tampilan). Kosong = sapaan tanpa nama.
  String _greetingName = '';

  /// Pengendali gulir Beranda modern (dulu juga menggerakkan
  /// parallax panggung U7 — pensiun bersama Panggung Sampul).
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }
  // Strip pengingat izin latar: tampil hanya bila pengguna sudah pernah
  // memutar lagu DAN izin latar belum lengkap; "Nanti saja" menyembunyikan
  // secara persisten (pref ui.bgReminderDismissed).
  bool _showBgCard = false;
  bool _bgExpanded = false;

  Future<void> _load() async {
    final db = ref.read(appDbProvider);
    final recent = await db.recentTracks(limit: 10);
    final frequent = await db.frequentTracks(limit: 10);
    final topWeek = await db.topPlayedSince(
      weekStartMonday(DateTime.now()).millisecondsSinceEpoch,
      limit: 3,
    );
    final greetingName =
        ((await db.pref<String>('ui.greetingName')) ?? '').trim();
    final everPlayed = await db.pref<bool>('playback.everPlayed') ?? false;
    final dismissed = await db.pref<bool>('ui.bgReminderDismissed') ?? false;
    var showBg = false;
    if (everPlayed && !dismissed) {
      final notif = await Permission.notification.isGranted;
      final battery = await Permission.ignoreBatteryOptimizations.isGranted;
      showBg = bgReminderVisible(
        everPlayed: everPlayed,
        dismissed: dismissed,
        notifGranted: notif,
        batteryGranted: battery,
      );
    }
    if (mounted)
      setState(() {
        _recent = recent;
        _frequent = frequent;
        _topWeek = topWeek;
        _greetingName = greetingName;
        _showBgCard = showBg;
      });
  }

  String _greeting(BuildContext context) {
    final h = DateTime.now().hour;
    if (h < 11) return context.l10n.greetMorning;
    if (h < 15) return context.l10n.greetAfternoon;
    if (h < 19) return context.l10n.greetEvening;
    return context.l10n.greetNight;
  }

  /// Strip izin ramping & bisa diperluas (Poles Beranda butir 2): satu
  /// baris dalam keadaan normal; ketuk membuka penjelasan + aksi.
  Widget _bgStrip(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Container(
        // 8045: strip izin selaras kartu Beranda lain — tonal
        // surface-1 radius 16, TANPA garis tepi peringatan (hukum DS:
        // kedalaman dari tonal, bukan garis); status peringatan
        // tetap terbaca dari ikon + judulnya.
        decoration: BoxDecoration(
          color: ClaiColors.surface1,
          borderRadius: BorderRadius.circular(16),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: () => setState(() => _bgExpanded = !_bgExpanded),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        ClaiIcon(
                          ClaiIcons.batteryAlert,
                          size: 20,
                          color: ClaiColors.warning,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            context.l10n.homeBgCardTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: ClaiColors.ink,
                            ),
                          ),
                        ),
                        Transform.rotate(
                          angle: _bgExpanded ? 3.14159 : 0,
                          child: ClaiIcon(
                            ClaiIcons.chevronDown,
                            size: 20,
                            color: ClaiColors.inkSecondary,
                          ),
                        ),
                      ],
                    ),
                    if (_bgExpanded) ...[
                      const SizedBox(height: 6),
                      Text(
                        context.l10n.homeBgCardSub,
                        style: const TextStyle(
                          color: ClaiColors.inkSecondary,
                          fontSize: 13,
                          height: 1.35,
                        ),
                      ),
                      Row(
                        children: [
                          TextButton(
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const SettingsScreen(),
                              ),
                            ),
                            child: Text(
                              context.l10n.homeSetupNow,
                              style: const TextStyle(color: ClaiColors.accent),
                            ),
                          ),
                          TextButton(
                            onPressed: () async {
                              await ref
                                  .read(appDbProvider)
                                  .setPref('ui.bgReminderDismissed', true);
                              if (mounted) setState(() => _showBgCard = false);
                            },
                            child: Text(
                              context.l10n.commonLater,
                              style: const TextStyle(
                                color: ClaiColors.inkSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Permukaan kartu Lanjutkan Sesi (Poles Beranda butir 5): aksen sampul
  /// yang berona mewarnai permukaan sebagai gradasi diagonal; aksen
  /// monokrom/tak tersedia jatuh ke gradasi NETRAL halus (surface-3 →
  /// surface-2) — permukaan tidak pernah flat, tanpa memalsukan warna.
  BoxDecoration _nowCardDecoration(Color? tonal) {
    if (tonal != null && !tonalIsNeutral(tonal)) {
      return BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [tonal, ClaiColors.surface2],
        ),
      );
    }
    return const BoxDecoration(
      borderRadius: BorderRadius.all(Radius.circular(16)),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF23232C), ClaiColors.surface2],
      ),
    );
  }

  Widget _emptyCard(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: claiCardDecoration(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(context.l10n.homeEmptyTitle, style: displayStyle(17)),
            const SizedBox(height: 6),
            Text(
              context.l10n.homeEmptySub,
              style: const TextStyle(
                color: ClaiColors.inkSecondary,
                fontSize: 13,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: ClaiColors.accent,
                foregroundColor: ClaiColors.onAccent,
              ),
              onPressed: widget.onGoSearch,
              icon: ClaiIcon(ClaiIcons.search, size: 18),
              label: Text(context.l10n.homeSearchSong),
            ),
          ],
        ),
      ),
    );
  }

  /// Kartu "Lanjutkan Sesi" (Poles Beranda butir 1): bentuk kartu Sedang
  /// Diputar lama (DS 6.2) tetapi HANYA tampil saat pemutaran tidak aktif —
  /// saat lagu berputar/memuat, mini player adalah pemilik tunggal info
  /// trek berjalan dan kartu besar tidak ikut tampil (anti-duplikasi).
  /// Kolom kanan diserahkan ke [SessionCardInfo] (tata letak anti-potong:
  /// Ronde Putusan Desain butir A).
  Widget _resumeCard(BuildContext context, MediaItem item) {
    final handler = ref.read(audioHandlerProvider);
    final engine = handler.engine;
    final lib = ref.read(libraryProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => openPlayerSheet(context),
        child: CoverAccentBuilder(
          key: ValueKey('nowcard-${item.id}'),
          artworkUrl: item.artUri?.toString(),
          builder: (context, tonal) => Container(
            padding: const EdgeInsets.all(14),
            decoration: _nowCardDecoration(tonal),
            child: Row(
              children: [
                CoverAccentGlow(
                  key: ValueKey(item.id),
                  artworkUrl: item.artUri?.toString(),
                  pad: 8,
                  radius: 16,
                  child: CoverArt(
                    url: item.artUri?.toString(),
                    size: 96,
                    label: item.title,
                    radius: 12,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: StreamBuilder<PlaybackState>(
                    stream: handler.playbackState.stream,
                    initialData: handler.playbackState.valueOrNull,
                    builder: (context, ps) {
                      final playing = ps.data?.playing ?? false;
                      final cur = engine.current;
                      final likedNow = cur != null && lib.isLiked(cur.key);
                      return StreamBuilder<Duration>(
                        stream: handler.positionStream,
                        builder: (context, pos) => SessionCardInfo(
                          title: cleanDisplayTitle(item.title),
                          artist: cleanDisplayArtist(item.artist ?? ''),
                          position: pos.data ?? Duration.zero,
                          duration: item.duration,
                          playing: playing,
                          liked: likedNow,
                          onPrevious: () => handler.skipToPrevious(),
                          onNext: () => handler.skipToNext(),
                          onPlayPause: () =>
                              playing ? handler.pauseNow() : handler.playNow(),
                          onToggleLike: cur == null
                              ? null
                              : () {
                                  ClaiHaptics.like();
                                  lib.toggleLike(cur);
                                },
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // DS v4.0 (Workstream E): Beranda "Panggung Sampul" (Varian A,
    // keputusan pemilik 2026-11-09 06:51) saat Tema Dinamis menyala;
    // tema mati → Beranda v3.1 persis (_buildLegacy).
    final ambOn =
        ref.watch(ambientControllerProvider.select((s) => s.enabled));
    if (ambOn) return _buildModern(context);
    return _buildLegacy(context);
  }

  Widget _buildLegacy(BuildContext context) {
    final handler = ref.watch(audioHandlerProvider);
    final engine = handler.engine;
    final lib = ref.watch(libraryProvider);
    return RefreshIndicator(
      onRefresh: () async {
        await lib.load();
        await _load();
      },
      child: FiniteScrollPage(
        padding: EdgeInsets.only(bottom: bottomChromeClearance(context)),
        children: [
          // Poles Beranda butir 4: sapaan dilebur ke baris judul ramping —
          // bukan lagi judul display besar yang mendorong konten ke bawah.
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 2),
            child: Row(
              children: [
                Expanded(
                  child: Text(_greeting(context), style: displayStyle(17)),
                ),
                IconButton(
                  icon: ClaiIcon(
                    ClaiIcons.settings,
                    color: ClaiColors.inkSecondary,
                  ),
                  tooltip: context.l10n.a11ySettings,
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SettingsScreen()),
                  ),
                ),
              ],
            ),
          ),
          const UpdateHomeBanner(),
          if (_showBgCard) _bgStrip(context),
          // F2 Batch 2: kartu resume tidur sebelum kartu sesi.
          const SleepResumeCard(),
          StreamBuilder<MediaItem?>(
            stream: handler.mediaItem.stream,
            initialData: handler.mediaItem.valueOrNull,
            builder: (context, snap) {
              final item = snap.data;
              if (item == null) return _emptyCard(context);
              return StreamBuilder<PlaybackState>(
                stream: handler.playbackState.stream,
                initialData: handler.playbackState.valueOrNull,
                builder: (context, ps) {
                  final st = ps.data;
                  final active =
                      (st?.playing ?? false) ||
                      st?.processingState == AudioProcessingState.loading ||
                      st?.processingState == AudioProcessingState.buffering;
                  // Butir 1: saat aktif, mini player pemilik tunggal — kartu
                  // besar tidak tampil. Saat jeda/selesai, kartu kembali
                  // sebagai "Lanjutkan Sesi".
                  if (active) return const SizedBox.shrink();
                  return _resumeCard(context, item);
                },
              );
            },
          ),
          // Butir 4: layar pertama wajib memuat sampul — riwayat & putar-lagi
          // kini REL SAMPUL horizontal, bukan daftar vertikal di bawah.
          if (_recent.isNotEmpty)
            CoverRail(
              title: context.l10n.homeRecent,
              tracks: _recent,
              onPlay: (tracks, i) => handler.playTracks(
                tracks,
                i,
                kind: 'search',
                label: context.l10n.homeRecent,
              ),
            ),
          if (_frequent.isNotEmpty)
            CoverRail(
              title: context.l10n.homePlayAgain,
              tracks: _frequent,
              onPlay: (tracks, i) => handler.playTracks(
                tracks,
                i,
                kind: 'search',
                label: context.l10n.homePlayAgain,
              ),
            ),
          // Rak personal artis teratas sebagai rel sampul (data lokal).
          const PersonalArtistRail(),
          // "Koleksi Kamu" (DS 7.1): ubin bisa diketuk menuju Koleksi.
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 26, 16, 6),
            child: Text(
              context.l10n.homeYourCollection,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: ClaiColors.ink,
              ),
            ),
          ),
          ListTile(
            leading: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: ClaiColors.surface2,
                borderRadius: BorderRadius.circular(8),
              ),
              child: ClaiIcon(ClaiIcons.heartFill, color: ClaiColors.liked),
            ),
            title: Text(
              context.l10n.homeSavedSongs,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: ClaiColors.ink,
              ),
            ),
            subtitle: Text(
              context.l10n.songCount(lib.likedKeys.length),
              style: const TextStyle(color: ClaiColors.inkSecondary),
            ),
            trailing: ClaiIcon(
              ClaiIcons.chevronRight,
              color: ClaiColors.inkFaint,
            ),
            onTap: widget.onGoCollection,
          ),
          for (final pl in lib.playlists.take(3))
            ListTile(
              leading: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: ClaiColors.surface2,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ClaiIcon(
                  ClaiIcons.queue,
                  color: ClaiColors.inkSecondary,
                ),
              ),
              title: Text(
                pl.name,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  color: ClaiColors.ink,
                ),
              ),
              subtitle: Text(
                context.l10n.songCount(pl.count),
                style: const TextStyle(color: ClaiColors.inkSecondary),
              ),
              trailing: ClaiIcon(
                ClaiIcons.chevronRight,
                color: ClaiColors.inkFaint,
              ),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      PlaylistScreen(playlistId: pl.id, name: pl.name),
                ),
              ),
            ),
          // Rak personal daftar (tersimpan tapi jarang diputar).
          const PersonalShelvesSection(),
          // F2 Jelajah (PRD 5.1): rak penemuan di bawah rak dasar.
          const JelajahSection(),
          // Butir 3: "Antrian Berikutnya" turun ke paling bawah Beranda —
          // rumah utamanya tetap Player & layar Antrian. Barisnya memakai
          // SongRow yang kini dibersihkan tampilannya.
          StreamBuilder(
            stream: handler.queueStream,
            initialData: engine,
            builder: (context, _) {
              final upcoming = [
                ...engine.manual,
                ...engine.continuation,
              ].take(3).toList();
              if (upcoming.isEmpty) return const SizedBox.shrink();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 26, 16, 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            context.l10n.homeUpNext,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                              color: ClaiColors.ink,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () => Navigator.of(claiRootContext(context)).push(
                            MaterialPageRoute(
                              builder: (_) => const QueueScreen(),
                            ),
                          ),
                          child: Text(
                            context.l10n.homeOpenQueue,
                            style: const TextStyle(color: ClaiColors.accent),
                          ),
                        ),
                      ],
                    ),
                  ),
                  for (var i = 0; i < upcoming.length; i++)
                    SongRow(
                      track: upcoming[i],
                      number: i + 1,
                      onTap: () => handler.jumpTo(upcoming[i].key),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
  // ------------------------------------------------------------ v4.0
  /// Beranda modern. Wujud awal v4.0 = "Panggung Sampul" (Varian A);
  /// Kampanye Rombak UI Total (putusan pemilik 2026-11-09 11:23)
  /// mengganti komposisinya mengikuti papan Beranda B dalam bahasa
  /// kita: kepala sapaan bernama + tanggal → hero **Kartu Lanjutkan
  /// ala B** berwarna sampul (gerbang anti-duplikasi yang sama seperti
  /// kartu Lanjutkan Sesi lama: saat putar aktif, mini player pemilik
  /// tunggal dan hero tidak tampil) → **Cepat putar** 2×2 dari riwayat
  /// nyata → **Paling sering minggu ini** dari playback_events →
  /// rel riwayat & putar-lagi → artis → Koleksi → rak personal →
  /// Jelajah → Antrian Berikutnya. Kepala seksi tetap kicker Volt
  /// lewat SectionHeader (KD-6).
  Widget _buildModern(BuildContext context) {
    final handler = ref.watch(audioHandlerProvider);
    final lib = ref.watch(libraryProvider);
    return RefreshIndicator(
      onRefresh: () async {
        await lib.load();
        await _load();
      },
      // Ronde 8052: Beranda finite → FiniteScrollPage (extent eksak).
      child: FiniteScrollPage(
        controller: _scroll,
        padding: EdgeInsets.only(bottom: bottomChromeClearance(context)),
        children: [
          _greetingHeader(context),
          const UpdateHomeBanner(),
          if (_showBgCard) _bgStrip(context),
          const SleepResumeCard(),
          StreamBuilder<MediaItem?>(
            stream: handler.mediaItem.stream,
            initialData: handler.mediaItem.valueOrNull,
            builder: (context, snap) {
              final item = snap.data;
              if (item == null) return _emptyCard(context);
              return StreamBuilder<PlaybackState>(
                stream: handler.playbackState.stream,
                initialData: handler.playbackState.valueOrNull,
                builder: (context, ps) {
                  final st = ps.data;
                  final active =
                      (st?.playing ?? false) ||
                      st?.processingState == AudioProcessingState.loading ||
                      st?.processingState == AudioProcessingState.buffering;
                  if (active) return const SizedBox.shrink();
                  return _continueCard(context, item);
                },
              );
            },
          ),
          _quickPlaySection(context),
          _topWeekSection(context),
          if (_recent.isNotEmpty)
            CoverRail(
              title: context.l10n.homeRecent,
              tracks: _recent,
              onPlay: (tracks, i) => handler.playTracks(
                tracks,
                i,
                kind: 'search',
                label: context.l10n.homeRecent,
              ),
            ),
          if (_frequent.isNotEmpty)
            CoverRail(
              title: context.l10n.homePlayAgain,
              tracks: _frequent,
              onPlay: (tracks, i) => handler.playTracks(
                tracks,
                i,
                kind: 'search',
                label: context.l10n.homePlayAgain,
              ),
            ),
          const PersonalArtistRail(),
          SectionHeader(context.l10n.homeYourCollection),
          ListTile(
            leading: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: ClaiColors.surface2,
                borderRadius: BorderRadius.circular(8),
              ),
              child: ClaiIcon(ClaiIcons.heartFill, color: ClaiColors.liked),
            ),
            title: Text(
              context.l10n.homeSavedSongs,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: ClaiColors.ink,
              ),
            ),
            subtitle: Text(
              context.l10n.songCount(lib.likedKeys.length),
              style: const TextStyle(color: ClaiColors.inkSecondary),
            ),
            trailing: ClaiIcon(
              ClaiIcons.chevronRight,
              color: ClaiColors.inkFaint,
            ),
            onTap: widget.onGoCollection,
          ),
          for (final pl in lib.playlists.take(3))
            ListTile(
              leading: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: ClaiColors.surface2,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ClaiIcon(
                  ClaiIcons.queue,
                  color: ClaiColors.inkSecondary,
                ),
              ),
              title: Text(
                pl.name,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  color: ClaiColors.ink,
                ),
              ),
              subtitle: Text(
                context.l10n.songCount(pl.count),
                style: const TextStyle(color: ClaiColors.inkSecondary),
              ),
              trailing: ClaiIcon(
                ClaiIcons.chevronRight,
                color: ClaiColors.inkFaint,
              ),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      PlaylistScreen(playlistId: pl.id, name: pl.name),
                ),
              ),
            ),
          const PersonalShelvesSection(),
          const JelajahSection(),
          _upNextModern(context),
        ],
      ),
    );
  }

  /// Kepala Beranda modern (Kampanye Rombak UI, papan B): baris
  /// tanggal huruf-besar → sapaan display (bernama bila pref
  /// `ui.greetingName` terisi; tanpa nama karangan bila kosong) →
  /// gir Pengaturan di kanan (dipertahankan dari baris wordmark lama;
  /// avatar dekoratif papan B tidak diadopsi).
  Widget _greetingHeader(BuildContext context) {
    final name = _greetingName;
    final greet = name.isEmpty
        ? _greeting(context)
        : '${_greeting(context)}, $name';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  homeDateKicker(
                    DateTime.now(),
                    Localizations.localeOf(context).languageCode,
                  ),
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.6,
                    color: ClaiColors.inkFaint,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  greet,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: displayStyle(26),
                ),
              ],
            ),
          ),
          IconButton(
            icon: ClaiIcon(
              ClaiIcons.settings,
              color: ClaiColors.inkSecondary,
            ),
            tooltip: context.l10n.a11ySettings,
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
    );
  }

  /// Hero Beranda modern (Kampanye Rombak UI — putusan pemilik
  /// 2026-11-09 11:23): **Kartu Lanjutkan ala papan B dalam bahasa
  /// kita**, menggantikan Panggung Sampul. Permukaan mengikuti sampul
  /// trek (gradasi tonal pipa yang sama dengan kartu Lanjutkan Sesi,
  /// radius 20); kicker LANJUTKAN; judul display besar; sampul kecil
  /// di kanan; slot waveform diisi **waveform ukur** trek ini bila
  /// sudah terukur — bila belum, **garis progres jujur** berwarna
  /// nada sampul (§11.9); tombol putar **nada sampul pekat** (§11.9,
  /// bukan hitam papan B, bukan Volt); label "Lanjut dari …"; hati
  /// dan antrean adalah fungsi nyata. Gerbang tampil sama persis
  /// dengan kartu lama: hanya saat pemutaran TIDAK aktif.
  Widget _continueCard(BuildContext context, MediaItem item) {
    final handler = ref.read(audioHandlerProvider);
    final engine = handler.engine;
    final lib = ref.read(libraryProvider);
    final tone = progressToneFor(
      ref.watch(ambientControllerProvider.select((s) => s.palette)),
    );
    final artist = cleanDisplayArtist(item.artist ?? '');
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: CoverAccentBuilder(
        key: ValueKey('continue-card-${item.id}'),
        artworkUrl: item.artUri?.toString(),
        builder: (context, tonal) => Container(
          decoration: _nowCardDecoration(tonal)
              .copyWith(borderRadius: BorderRadius.circular(20)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => openPlayerSheet(context),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            KickerLabel(context.l10n.homeContinue),
                            const SizedBox(height: 8),
                            Text(
                              cleanDisplayTitle(item.title),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: heroStyle(30),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14,
                                color: tonal == null
                                    ? ClaiColors.inkSecondary
                                    : ClaiColors.ink
                                        .withValues(alpha: 0.85),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      CoverArt(
                        url: item.artUri?.toString(),
                        size: 84,
                        label: item.title,
                        radius: 14,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                StreamBuilder<PlaybackState>(
                  stream: handler.playbackState.stream,
                  initialData: handler.playbackState.valueOrNull,
                  builder: (context, ps) {
                    final playing = ps.data?.playing ?? false;
                    final cur = engine.current;
                    final likedNow = cur != null && lib.isLiked(cur.key);
                    return StreamBuilder<Duration>(
                      stream: handler.positionStream,
                      builder: (context, pos) {
                        final position = pos.data ?? Duration.zero;
                        final dur = item.duration ?? Duration.zero;
                        final frac = dur.inMilliseconds == 0
                            ? 0.0
                            : (position.inMilliseconds /
                                    dur.inMilliseconds)
                                .clamp(0.0, 1.0);
                        const timeStyle = TextStyle(
                          fontSize: 12,
                          color: ClaiColors.inkSecondary,
                          fontFeatures: [FontFeature.tabularFigures()],
                        );
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _continueWaveOrProgress(context, frac, tone),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Text(formatDuration(position),
                                    style: timeStyle),
                                const Spacer(),
                                Text(
                                  dur == Duration.zero
                                      ? '–'
                                      : '-${formatDuration(dur - position)}',
                                  style: timeStyle,
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Semantics(
                                  button: true,
                                  label: playing
                                      ? context.l10n.a11yPause
                                      : context.l10n.a11yPlay,
                                  child: PressableScale(
                                    child: GestureDetector(
                                      onTap: () => playing
                                          ? handler.pauseNow()
                                          : handler.playNow(),
                                      child: Container(
                                        width: 52,
                                        height: 52,
                                        decoration: BoxDecoration(
                                          color: tone,
                                          shape: BoxShape.circle,
                                        ),
                                        child: ClaiIcon(
                                          playing
                                              ? ClaiIcons.pause
                                              : ClaiIcons.play,
                                          color: onProgressTone(tone),
                                          size: 24,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    position > Duration.zero
                                        ? context.l10n.homeResumeFrom(
                                            formatDuration(position))
                                        : (dur == Duration.zero
                                            ? ''
                                            : formatDuration(dur)),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: ClaiColors.ink,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  icon: ClaiIcon(
                                    likedNow
                                        ? ClaiIcons.heartFill
                                        : ClaiIcons.heart,
                                    color: likedNow
                                        ? ClaiColors.liked
                                        : ClaiColors.inkSecondary,
                                  ),
                                  tooltip: likedNow
                                      ? context.l10n.a11yUnlike
                                      : context.l10n.a11yLike,
                                  onPressed: cur == null
                                      ? null
                                      : () {
                                          ClaiHaptics.like();
                                          lib.toggleLike(cur);
                                        },
                                ),
                                IconButton(
                                  icon: ClaiIcon(
                                    ClaiIcons.queue,
                                    color: ClaiColors.inkSecondary,
                                  ),
                                  tooltip: context.l10n.queueTitle,
                                  onPressed: () => Navigator.of(
                                          claiRootContext(context))
                                      .push(
                                    MaterialPageRoute(
                                      builder: (_) => const QueueScreen(),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        );
                      },
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Slot waveform kartu Lanjutkan: waveform ukur trek berjalan
  /// bila SUDAH terukur (sebagian pun tampil jujur — batang terukur
  /// + garis datar untuk yang belum); belum terukur sama sekali →
  /// garis progres jujur berwarna nada sampul (perintah spesifikasi
  /// hero 11:23). Bukan kontrol seek — ketukan kartu membuka Player.
  Widget _continueWaveOrProgress(
    BuildContext context,
    double frac,
    Color tone,
  ) {
    final cur = ref.read(audioHandlerProvider).engine.current;
    if (cur == null) return _continueProgressLine(frac, tone);
    final recorder = ref.read(waveformRecorderProvider);
    return ListenableBuilder(
      listenable: recorder,
      builder: (context, _) {
        final data = recorder.dataFor(cur.key);
        if (data.measuredCount == 0) {
          return _continueProgressLine(frac, tone);
        }
        return WaveformStrip(
          data: data,
          fraction: frac,
          playedColor: tone,
          unplayedColor: ClaiColors.ink.withValues(alpha: 0.38),
          flatColor: ClaiColors.ink.withValues(alpha: 0.22),
        );
      },
    );
  }

  Widget _continueProgressLine(double frac, Color tone) =>
      LinearProgressIndicator(
        value: frac.clamp(0.0, 1.0),
        minHeight: 3,
        color: tone,
        backgroundColor: ClaiColors.surface3,
      );

  /// Seksi "Cepat putar" (Kampanye Rombak UI, papan B): kisi 2×2
  /// dari RIWAYAT PUTAR NYATA (trek terakhir yang benar-benar
  /// diputar, urutan terbaru). Tampil hanya bila riwayat ≥ 2 —
  /// di bawah itu rel Terakhir Diputar di bawahnya sudah cukup.
  /// Ketuk ubin memutar trek itu dalam konteks daftar riwayat
  /// (perilaku yang sama dengan rel sampul).
  Widget _quickPlaySection(BuildContext context) {
    if (_recent.length < 2) return const SizedBox.shrink();
    final handler = ref.read(audioHandlerProvider);
    final tiles = _recent.take(4).toList();
    Widget tile(Track t) {
      final idx = _recent.indexOf(t);
      return Material(
        color: ClaiColors.surface2,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => handler.playTracks(
            _recent,
            idx,
            kind: 'search',
            label: context.l10n.homeQuickPlay,
          ),
          child: SizedBox(
            height: 64,
            child: Row(
              children: [
                CoverArt(url: t.artworkUrl, size: 64, label: t.title, radius: 0),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        cleanDisplayTitle(t.title),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: ClaiColors.ink,
                        ),
                      ),
                      Text(
                        cleanDisplayArtist(t.artistNames),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: ClaiColors.inkSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
              ],
            ),
          ),
        ),
      );
    }

    final rows = <Widget>[];
    for (var i = 0; i < tiles.length; i += 2) {
      rows.add(
        Row(
          children: [
            Expanded(child: tile(tiles[i])),
            const SizedBox(width: 10),
            Expanded(
              child: i + 1 < tiles.length
                  ? tile(tiles[i + 1])
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      );
      if (i + 2 < tiles.length) rows.add(const SizedBox(height: 10));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          context.l10n.homeQuickPlay,
          padding: const EdgeInsets.fromLTRB(16, 26, 16, 10),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(children: rows),
        ),
      ],
    );
  }

  /// Seksi "Paling sering minggu ini" (Kampanye Rombak UI, papan B):
  /// peringkat hitungan putar MENTAH playback_events sejak Senin
  /// 00:00 (AppDb.topPlayedSince) — angka raksasa ber-outline 1-2-3
  /// menumpang di kiri sampul, hitungan putar dinyatakan apa adanya.
  /// Minggu tanpa putar = keadaan kosong JUJUR (satu baris keterangan),
  /// bukan juara sepanjang masa yang disamarkan. Tautan "Semua"
  /// papan B tidak dibuat: belum ada layar tujuannya.
  Widget _topWeekSection(BuildContext context) {
    final handler = ref.read(audioHandlerProvider);
    final tracks = [for (final e in _topWeek) e.track];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          context.l10n.homeTopWeek,
          padding: const EdgeInsets.fromLTRB(16, 26, 16, 10),
        ),
        if (_topWeek.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 2),
            child: Text(
              context.l10n.homeTopWeekEmpty,
              style: const TextStyle(
                fontSize: 13,
                height: 1.4,
                color: ClaiColors.inkSecondary,
              ),
            ),
          )
        else
          SizedBox(
            height: 198,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _topWeek.length,
              separatorBuilder: (_, __) => const SizedBox(width: 14),
              itemBuilder: (context, i) {
                final e = _topWeek[i];
                final t = e.track;
                return SizedBox(
                  width: 150,
                  child: GestureDetector(
                    onTap: () => handler.playTracks(
                      tracks,
                      i,
                      kind: 'search',
                      label: context.l10n.homeTopWeek,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          height: 124,
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Positioned(
                                left: 0,
                                bottom: -6,
                                child: Text(
                                  '${i + 1}',
                                  style: displayStyle(76).copyWith(
                                    foreground: Paint()
                                      ..style = PaintingStyle.stroke
                                      ..strokeWidth = 1.6
                                      ..color = ClaiColors.inkFaint,
                                  ),
                                ),
                              ),
                              Positioned(
                                left: 28,
                                top: 2,
                                child: CoverArt(
                                  url: t.artworkUrl,
                                  size: 120,
                                  label: t.title,
                                  radius: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Padding(
                          padding: const EdgeInsets.only(left: 28),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                cleanDisplayTitle(t.title),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: ClaiColors.ink,
                                ),
                              ),
                              Text(
                                cleanDisplayArtist(t.artistNames),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: ClaiColors.inkSecondary,
                                ),
                              ),
                              Text(
                                context.l10n.homePlayCount(e.count),
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: ClaiColors.inkSecondary,
                                  fontFeatures: [
                                    FontFeature.tabularFigures()
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  /// "Antrian Berikutnya" versi modern: kepala kicker + tombol buka
  /// antrean (isi & perilaku sama dengan versi lama).
  Widget _upNextModern(BuildContext context) {
    final handler = ref.watch(audioHandlerProvider);
    final engine = handler.engine;
    return StreamBuilder(
      stream: handler.queueStream,
      initialData: engine,
      builder: (context, _) {
        final upcoming = [
          ...engine.manual,
          ...engine.continuation,
        ].take(3).toList();
        if (upcoming.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeader(
              context.l10n.homeUpNext,
              trailing: TextButton(
                onPressed: () =>
                    Navigator.of(claiRootContext(context)).push(
                  MaterialPageRoute(builder: (_) => const QueueScreen()),
                ),
                child: Text(
                  context.l10n.homeOpenQueue,
                  style: const TextStyle(color: ClaiColors.accent),
                ),
              ),
            ),
            for (var i = 0; i < upcoming.length; i++)
              SongRow(
                track: upcoming[i],
                number: i + 1,
                onTap: () => handler.jumpTo(upcoming[i].key),
              ),
          ],
        );
      },
    );
  }
}

/// Kolom info kartu "Lanjutkan Sesi" (judul, artis, progres + waktu,
/// kontrol) — dipisah dari kartu agar tata letaknya teruji widget.
///
/// Ronde Putusan Desain butir A (laporan pemilik atas build 2009): tata
/// letak lama menaruh kontrol (4 × 48dp) dan teks waktu SEBARIS di kolom
/// yang hanya ±225dp pada lebar 411 — teks waktu terdorong keluar tepi
/// kanan kartu ("3:24" terpotong pada tangkapan HP pemilik; pada lebar
/// 360 kolomnya tinggal ±174dp sehingga baris lama mustahil muat).
/// Kini: teks waktu duduk di baris progres (progreslah elemen fleksibel
/// yang menyusut — waktu tidak pernah jadi korban), dan kontrol memakai
/// target ringkas 42dp + lingkaran putar 44dp (total 170dp ≤ kolom
/// tersempit 360dp). Judul/artis tetap ellipsis satu baris.
class SessionCardInfo extends StatelessWidget {
  final String title;
  final String artist;
  final Duration position;
  final Duration? duration;
  final bool playing;
  final bool liked;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onPlayPause;
  final VoidCallback? onToggleLike;

  const SessionCardInfo({
    super.key,
    required this.title,
    required this.artist,
    required this.position,
    required this.duration,
    required this.playing,
    required this.liked,
    required this.onPrevious,
    required this.onNext,
    required this.onPlayPause,
    required this.onToggleLike,
  });

  Widget _control(
    BuildContext context, {
    required ClaiIconData icon,
    required String tooltip,
    required VoidCallback? onPressed,
    Color color = ClaiColors.ink,
  }) {
    return IconButton(
      icon: ClaiIcon(icon, color: color, size: 23),
      tooltip: tooltip,
      onPressed: onPressed,
      style: IconButton.styleFrom(
        fixedSize: const Size(42, 42),
        minimumSize: const Size(42, 42),
        maximumSize: const Size(42, 42),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: EdgeInsets.zero,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dur = duration ?? Duration.zero;
    final frac = dur.inMilliseconds == 0
        ? 0.0
        : position.inMilliseconds / dur.inMilliseconds;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: ClaiColors.ink,
          ),
        ),
        Text(
          artist,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 13, color: ClaiColors.inkSecondary),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: LinearProgressIndicator(
                value: frac.clamp(0, 1),
                minHeight: 3,
                color: ClaiColors.accent,
                backgroundColor: ClaiColors.surface3,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${formatDuration(position)} / ${duration == null ? '–' : formatDuration(duration!)}',
              key: const ValueKey('session-card-time'),
              style: const TextStyle(
                fontSize: 12,
                color: ClaiColors.inkSecondary,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _control(
              context,
              icon: ClaiIcons.prev,
              tooltip: context.l10n.a11yPrevious,
              onPressed: onPrevious,
            ),
            Semantics(
              button: true,
              label: playing ? context.l10n.a11yPause : context.l10n.a11yPlay,
              child: PressableScale(
                child: GestureDetector(
                  onTap: onPlayPause,
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: const BoxDecoration(
                      color: ClaiColors.accent,
                      shape: BoxShape.circle,
                    ),
                    child: ClaiIcon(
                      playing ? ClaiIcons.pause : ClaiIcons.play,
                      color: ClaiColors.onAccent,
                      size: 22,
                    ),
                  ),
                ),
              ),
            ),
            _control(
              context,
              icon: ClaiIcons.next,
              tooltip: context.l10n.a11yNext,
              onPressed: onNext,
            ),
            _control(
              context,
              icon: liked ? ClaiIcons.heartFill : ClaiIcons.heart,
              tooltip: liked ? context.l10n.a11yUnlike : context.l10n.a11yLike,
              onPressed: onToggleLike,
              color: liked ? ClaiColors.liked : ClaiColors.inkSecondary,
            ),
          ],
        ),
      ],
    );
  }
}
