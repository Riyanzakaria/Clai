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
import 'cover_accent_glow.dart';
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
  // Strip pengingat izin latar: tampil hanya bila pengguna sudah pernah
  // memutar lagu DAN izin latar belum lengkap; "Nanti saja" menyembunyikan
  // secara persisten (pref ui.bgReminderDismissed).
  bool _showBgCard = false;
  bool _bgExpanded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = ref.read(appDbProvider);
    final recent = await db.recentTracks(limit: 10);
    final frequent = await db.frequentTracks(limit: 10);
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
        decoration: BoxDecoration(
          color: ClaiColors.surface2,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: ClaiColors.warning.withValues(alpha: 0.45)),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
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
                              fontSize: 13.5,
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
                          fontSize: 12.5,
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
                fontSize: 13.5,
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
                              : () => lib.toggleLike(cur),
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
    final handler = ref.watch(audioHandlerProvider);
    final engine = handler.engine;
    final lib = ref.watch(libraryProvider);
    return RefreshIndicator(
      onRefresh: () async {
        await lib.load();
        await _load();
      },
      child: ListView(
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
                          onPressed: () => Navigator.of(context).push(
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
