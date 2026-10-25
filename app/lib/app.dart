import 'dart:convert';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'core/clai_icons.dart';
import 'core/tokens.dart';
import 'l10n/l10n.dart';
import 'data/app_db.dart';
import 'player/audio_handler.dart';
import 'providers/ytmusic/ytmusic_provider.dart';
import 'providers/spotify/spotify_provider.dart';
import 'services/download_service.dart';
import 'services/driving_service.dart';
import 'services/capture_service.dart';
import 'services/enrichment_service.dart';
import 'services/voice_service.dart';
import 'services/sleep_service.dart';
import 'services/library_controller.dart';
import 'services/listenbrainz_service.dart';
import 'services/local_files.dart';
import 'services/lyrics_service.dart';
import 'services/ocr_model_service.dart';
import 'services/track_matcher.dart';
import 'services/update_service.dart';
import 'ui/collection_screen.dart';
import 'ui/cover_accent_glow.dart';
import 'ui/capture_sheet.dart';
import 'ui/home_screen.dart';
import 'ui/mini_player.dart';
import 'ui/search_screen.dart';

final appDbProvider = Provider<AppDb>((_) => AppDb());
final ytMusicProvider = Provider<YtMusicProvider>(
  (ref) => YtMusicProvider(ref.watch(appDbProvider)),
);
final localFilesProvider = Provider<LocalFilesService>(
  (_) => LocalFilesService(),
);

/// Diisi oleh bootstrap (bootstrap.dart) dari AudioService.init — satu-satunya handler (L-01).
final audioHandlerProvider = Provider<ClaiAudioHandler>(
  (_) => throw UnimplementedError('handler belum diinisialisasi'),
);

final libraryProvider = ChangeNotifierProvider<LibraryController>(
  (ref) => LibraryController(ref.watch(appDbProvider)),
);

/// Pembaruan Dalam Aplikasi F2 (cek GitHub Releases; lihat services/update_service.dart).
final updateControllerProvider = ChangeNotifierProvider<UpdateController>(
  (ref) => UpdateController(ref.watch(appDbProvider)),
);

/// Layanan F2 Batch 1 di atas AppDb yang sama.
final lyricsServiceProvider = Provider<LyricsService>(
  (ref) => LyricsService(ref.watch(appDbProvider)),
);
final listenBrainzServiceProvider = Provider<ListenBrainzService>(
  (ref) => ListenBrainzService(ref.watch(appDbProvider)),
);
final enrichmentServiceProvider = Provider<EnrichmentService>(
  (ref) => EnrichmentService(ref.watch(appDbProvider)),
);

/// Layanan F2 Batch 2: unduhan/offline (butuh provider musik + DB).
final downloadServiceProvider = ChangeNotifierProvider<DownloadService>(
  (ref) =>
      DownloadService(ref.watch(appDbProvider), ref.watch(ytMusicProvider)),
);

/// Timer tidur & Lanjut Besok (F2 Batch 2) — dipasang bootstrap ke handler.
final sleepServiceProvider = ChangeNotifierProvider<SleepService>(
  (_) => SleepService(),
);

/// Mode Berkendara (F2 Batch 2) — dipasang initState ke handler.
final drivingServiceProvider = ChangeNotifierProvider<DrivingService>(
  (ref) => DrivingService(ref.watch(appDbProvider)),
);

/// Antrean Suara (F2 Batch 2) — handler dipasang initState.
final voiceServiceProvider = ChangeNotifierProvider<VoiceService>(
  (ref) => VoiceService(ref.watch(appDbProvider), ref.watch(ytMusicProvider)),
);

/// Model OCR unduh-di-dalam-aplikasi untuk Tangkap-gambar (F2 Batch 2.1,
/// cara ketiga — model TIDAK terbundel di APK; lihat ocr_model_service.dart).
final ocrModelControllerProvider = ChangeNotifierProvider<OcrModelController>(
  (ref) => OcrModelController(ref.watch(appDbProvider)),
);

/// Tangkap dari Mana Saja (F2 Batch 2).
final captureServiceProvider = ChangeNotifierProvider<CaptureService>(
  (ref) => CaptureService(
    ref.watch(appDbProvider),
    ref.watch(ytMusicProvider),
    ref.watch(spotifyProvider),
    ref.watch(trackMatcherProvider),
  )..ocrModels = ref.watch(ocrModelControllerProvider),
);

/// Metadata Spotify publik (anonim, clean-room) + pencocok trek ke YouTube Music.
final spotifyProvider = Provider<SpotifyMetadataProvider>(
  (_) => SpotifyMetadataProvider(),
);
final trackMatcherProvider = Provider<TrackMatcher>(
  (ref) => TrackMatcher(ref.watch(ytMusicProvider), ref.watch(appDbProvider)),
);

ThemeData buildClaiTheme() {
  final base = ThemeData.dark(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: ClaiColors.base,
    colorScheme: base.colorScheme.copyWith(
      primary: ClaiColors.accent,
      onPrimary: ClaiColors.onAccent,
      surface: ClaiColors.surface1,
      onSurface: ClaiColors.ink,
      error: ClaiColors.error,
    ),
    textTheme: GoogleFonts.interTextTheme(
      base.textTheme,
    ).apply(bodyColor: ClaiColors.ink, displayColor: ClaiColors.ink),
    appBarTheme: const AppBarTheme(
      backgroundColor: ClaiColors.base,
      foregroundColor: ClaiColors.ink,
      elevation: 0,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: ClaiColors.base,
      indicatorColor: Colors.transparent,
      labelTextStyle: WidgetStateProperty.all(
        const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          letterSpacing: .4,
        ),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: ClaiColors.surface3,
      contentTextStyle: TextStyle(color: ClaiColors.ink),
    ),
    dividerTheme: const DividerThemeData(color: ClaiColors.divider),
  );
}

/// Judul display Space Grotesk (DS Bab 3).
TextStyle displayStyle(double size) => GoogleFonts.spaceGrotesk(
  fontSize: size,
  fontWeight: FontWeight.w600,
  color: ClaiColors.ink,
  height: 1.18,
);

/// Geometri chrome bawah (v4.4.2, cacat jarak mini player ↔ nav).
///
/// Pelajaran v4.4.1: konstanta dihitung dari angka DEKLARASI (NavigationBar
/// height: 56) — padahal piksel emulator membuktikan bar bawaan Material
/// merender ~80dp dengan ikon tenggelam ~38dp di bawah tepi bawah kartu
/// mini: persis "pita kosong besar" pada foto perangkat pemilik, dan di HP
/// pemilik inset sistem HyperOS menumpuknya lebih jauh. Kini geometri
/// dinyatakan sekali di sini, nav DIGAMBAR SENDIRI pada tinggi persis ini
/// (bukan widget stok yang tingginya tak bisa dipegang), dan jarak bebas
/// daftar dihitung dari inset sistem AKTUAL perangkat — bukan cadangan
/// tebakan 36dp. Bentuk kartu melayang dipertahankan (keputusan PRD/v4.4);
/// yang disamakan dengan referensi pemilik adalah JARAKnya: tepi bawah
/// kartu → tepi atas zona nav = margin kartu 1 + bantalan atas nav 1 ≈ 2dp.
const double kChromeTopGap = 2;
const double kMiniPlayerHeight = 64;
const double kMiniPlayerBottomMargin = 1;
const double kNavBarHeight = 54;
const double kNavBarTopPad = 1;

/// ~~Tinggi pita pudar scrim di atas gugus~~ — DIHAPUS pada Ronde Koreksi
/// Gradasi (perintah pemilik 25 Okt 12:17 WIB atas build 2010): gradasi
/// dinilai KETINGGIAN karena pita +56 dp ini melukis lapisan sampai di
/// atas mini player. Perintahnya: gradasi hanya boleh hidup DI BAWAH mini
/// player — "dibawah miniplayer, ga sampe miniplayer". Kini lukisan scrim
/// hanya menaungi margin bawah kartu + bilah navigasi + inset bawah
/// (lihat [chromeScrimHeight]); konten yang digulir tampil jernih sampai
/// menyentuh tepi atas kartu. Geometri gugus tidak berubah sama sekali.
///
/// Hentian gradasi scrim — kini dipetakan pada ruas pendek di bawah
/// kartu itu saja (bukan lagi seluruh tinggi gugus + pita seperti desain
/// 2006/2010). Hentian terakhir memudarkan tinta sampul kembali ke arah
/// [ClaiColors.base] di tepi paling bawah.
const List<double> kChromeScrimStops = [0, 0.5, 1.0];

/// Profil alfa scrim zona nav (Ronde Koreksi Gradasi — dikalibrasi pada
/// referensi Spotify kiriman pemilik, 25 Okt 12:21 WIB: "gradasinya tipis
/// aja seperti spotify"). Arahnya berjangkar di BAWAH: paling TIPIS di
/// tepi atas ruas (tepat di bawah kartu), menggelap halus ke bawah,
/// paling pekat hanya di tepi paling bawah. Konten di balik zona nav
/// harus terbaca JELAS menembus (sampul album dikenali), gradasinya
/// hanya penggelapan halus — bukan pita tinta. Jangkar keterbacaan
/// diminimalkan sesuai perintah: cukup gelap agar ikon + label nav
/// (putih/inkFaint) terbaca, setipis yang masih memenuhi itu; bila ragu
/// antara "rona terasa" vs "tipis", referensi menang.
/// - Tepi atas ruas: [kScrimNavTopAlpha] (0.32).
/// - Tengah ruas (zona ikon): [kScrimNavMidAlpha] (0.55).
/// - Tepi paling bawah: [kScrimBottomAlpha] (0.85).
/// (Build 2010 sebagai pembanding: ruas ini alfa 1.0 opak penuh — blok
/// warna; vonis pemilik: "semi transparan? karena yang aku lihat
/// enggak".)
const double kScrimNavTopAlpha = 0.32;
const double kScrimNavMidAlpha = 0.55;
const double kScrimBottomAlpha = 0.85;

/// Tinggi lukisan scrim chrome bawah: HANYA margin bawah kartu mini +
/// bilah navigasi + inset sistem. Bukan tinggi kartu, bukan celah atas
/// kartu, tanpa pita di atas gugus (perintah pemilik, Koreksi Gradasi).
double chromeScrimHeight(double bottomInset) =>
    kMiniPlayerBottomMargin + kNavBarHeight + bottomInset;

/// Warna gradasi scrim chrome bawah (Ronde Putusan Desain butir B —
/// perintah pemilik: "di belakang navigation bar itu gradasi", berwarna
/// mengikuti sampul; Ronde Koreksi Gradasi: ruas lukisannya hanya di
/// bawah mini player dan seluruhnya semi-transparan). Tanpa aksen:
/// gradasi netral [ClaiColors.base]. Dengan aksen: tinta sampul
/// (disaring [readableAccentSurface] agar label nav tetap kontras),
/// memudar ke arah base di tepi bawah. Geometri tidak berubah.
List<Color> chromeScrimColors(Color? tonal) {
  if (tonal == null) {
    return [
      ClaiColors.base.withValues(alpha: kScrimNavTopAlpha),
      ClaiColors.base.withValues(alpha: kScrimNavMidAlpha),
      ClaiColors.base.withValues(alpha: kScrimBottomAlpha),
    ];
  }
  final surface = readableAccentSurface(tonal);
  return [
    surface.withValues(alpha: kScrimNavTopAlpha),
    surface.withValues(alpha: kScrimNavMidAlpha),
    Color.lerp(surface, ClaiColors.base, 0.5)!
        .withValues(alpha: kScrimBottomAlpha),
  ];
}

/// Pengganti bahasa manual (PRD Bab 3): null = ikuti sistem; 'id'/'en' =
/// pilihan eksplisit di Pengaturan → Tampilan. Berlaku tanpa mulai ulang
/// karena MaterialApp dibangun ulang oleh provider ini.
final localeOverrideProvider = StateProvider<String?>((_) => null);

/// Ruang bebas bawah yang wajib disisakan daftar gulir layar tab agar baris
/// terakhir bisa digulir keluar dari balik chrome melayang (gradasi + mini
/// player kartu + nav + inset sistem perangkat ini).
double bottomChromeClearance(BuildContext context) =>
    kChromeTopGap +
    kMiniPlayerHeight +
    kMiniPlayerBottomMargin +
    kNavBarHeight +
    MediaQuery.paddingOf(context).bottom +
    2;

class ClaiApp extends ConsumerStatefulWidget {
  const ClaiApp({super.key});
  @override
  ConsumerState<ClaiApp> createState() => _ClaiAppState();
}

class _ClaiAppState extends ConsumerState<ClaiApp> {
  int _tab = 0;
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _navKey = GlobalKey<NavigatorState>();

  void _openCapture(Map map) {
    final kind = map['kind'] as String?;
    final value = map['value'] as String?;
    final ctx = _navKey.currentContext;
    if (kind == null || value == null || ctx == null || !mounted) return;
    if (kind == 'text') {
      openCaptureSheet(ctx, text: value);
    } else if (kind == 'image') {
      openCaptureSheet(ctx, imageUri: value);
    }
  }

  @override
  void initState() {
    super.initState();
    final handler = ref.read(audioHandlerProvider);
    // Cacat A (2008): izin notifikasi diminta pada MOMEN YANG BENAR —
    // pemutaran aktif pertama (sekali per pemasangan). Tanpa izin
    // POST_NOTIFICATIONS (Android 13+), notifikasi media tidak tampil
    // walau sesi sehat; sebelumnya izin hanya diminta dari Pengaturan/
    // strip Beranda, jadi pengguna yang tak pernah ke sana kehilangan
    // kontrol latar dalam diam. Status jujur tetap terbaca di
    // Pengaturan > Aplikasi dan strip izin Beranda (yang hanya muncul
    // selama izin belum diberikan).
    var notifAskedHandled = false;
    handler.playbackState.listen((state) {
      if (notifAskedHandled || !state.playing) return;
      notifAskedHandled = true;
      () async {
        final db = ref.read(appDbProvider);
        if (await db.pref<bool>('ui.notifPermAsked') == true) return;
        if (!await Permission.notification.isGranted) {
          await Permission.notification.request();
        }
        await db.setPref('ui.notifPermAsked', true);
      }();
    });
    handler.notices.stream.listen((msg) {
      final ctx = _scaffoldKey.currentContext;
      if (ctx != null && mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(content: Text(msg), duration: const Duration(seconds: 4)),
        );
      }
    });
    ref.read(libraryProvider).load();
    // Bahasa (PRD Bab 3): muat pengganti manual tersimpan; bawaan = sistem.
    ref.read(appDbProvider).pref<String>('ui.language').then((v) {
      if (v == 'id' || v == 'en')
        ref.read(localeOverrideProvider.notifier).state = v;
    });
    // F2 Batch 2.1: status model OCR dari disk (murah) — lembar Tangkap dan
    // Pengaturan membaca keadaan yang sebenarnya, bukan tebakan.
    ref.read(ocrModelControllerProvider).refresh();
    final upd = ref.read(updateControllerProvider);
    upd.loadPrefs().then((_) => upd.maybeAutoCheck());
    // F2 Batch 2: unduhan — satu instans layanan (provider) disambungkan ke
    // handler: peta path untuk sumber berkas lokal + sumber isi ulang offline.
    final dl = ref.read(downloadServiceProvider);
    handler.offlineRefillSource = () => dl.downloadedTracks();
    dl.addListener(() {
      handler.downloadedPaths = dl.downloadedPaths;
    });
    dl.load().then((_) {
      handler.downloadedPaths = dl.downloadedPaths;
    });
    // F2 Batch 2: Lanjut Besok — kait timer tidur ke handler.
    // D-15 (Sapuan): yang disimpan kini SNAPSHOT ANTREAN PENUH (konteks +
    // manual + lanjutan + autoplay + riwayat + sinyal + posisi), bukan
    // satu lagu + posisi saja — Lanjut Besok memulihkan SESI semalam,
    // persis janji USER-FLOW F-10. savedAt diperiksa kartu (kedaluwarsa
    // 48 jam). Sesudah itu pudar 30 detik + jeda.
    final sleep = ref.read(sleepServiceProvider);
    sleep.onFire = () async {
      if (handler.engine.current != null) {
        final snap = handler.engine.snapshot(
          positionMs: handler.position.inMilliseconds,
        );
        await ref
            .read(appDbProvider)
            .setPref(
              'sleep.last',
              jsonEncode(<String, Object?>{
                'v': 2,
                'savedAt': DateTime.now().millisecondsSinceEpoch,
                'snapshot': snap,
              }),
            );
      }
      await handler.fadeOutAndPause();
    };
    // D-15: interaksi manual ≤10 menit sesudah timer berbunyi membatalkan
    // simpanan Lanjut Besok (pengguna sudah bangun & memilih sendiri).
    sleep.onPostFireInteraction = () {
      ref.read(appDbProvider).setPref('sleep.last', null);
    };
    // D-32: suka dari notifikasi/layar kunci — sakelar suka trek berjalan
    // lewat LibraryController yang sama dengan UI; keadaan suka disinkronkan
    // balik ke handler agar ikon notifikasi selalu jujur.
    final lib = ref.read(libraryProvider);
    handler.onToggleLikeRequest = () {
      final cur = handler.engine.current;
      if (cur != null) lib.toggleLike(cur);
    };
    lib.addListener(() {
      final cur = handler.engine.current;
      if (cur != null) handler.setNotificationLiked(lib.isLiked(cur.key));
    });
    handler.trackStartedListeners.add((t) {
      handler.setNotificationLiked(lib.isLiked(t.key));
    });
    handler.onNaturalTrackEnd = () => sleep.fireEndOfSong();
    handler.onManualPlayAction = () => sleep.cancelOnManualAction();
    // F2 Batch 2: Berkendara — pengumuman lagu berikutnya, pola tekan,
    // volume-kecepatan. load() memulihkan pref; listener menjaga flag handler.
    final driving = ref.read(drivingServiceProvider);
    driving.onVolumeTarget = (v) => handler.setDrivingVolume(v);
    handler.trackStartedListeners.add((t) {
      if (driving.on && driving.announceOn) {
        driving.announce(t).then((_) {}, onError: (_) {});
      }
    });
    driving.addListener(() {
      handler.drivingPatterns = driving.on && driving.scheme == 'patterns';
    });
    driving.load().then((_) {
      handler.drivingPatterns = driving.on && driving.scheme == 'patterns';
    });
    // F2 Batch 2: Antrean Suara — handler untuk aksi perintah.
    ref.read(voiceServiceProvider).handler = handler;
    // F2 Batch 2: Tangkap dari Mana Saja — berbagi masuk (warm) + intent awal (cold).
    const shareEvents = EventChannel('clai/share_events');
    shareEvents.receiveBroadcastStream().listen((event) {
      if (event is Map) _openCapture(event.cast<String, Object?>());
    }, onError: (_) {});
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        const shareCh = MethodChannel('clai/share');
        final initial = await shareCh.invokeMapMethod<String, Object?>(
          'initialShared',
        );
        if (initial != null) _openCapture(initial);
      } catch (_) {}
    });
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      HomeScreen(
        onGoSearch: () => setState(() => _tab = 1),
        onGoCollection: () => setState(() => _tab = 2),
      ),
      const SearchScreen(),
      const CollectionScreen(),
    ];
    final localeOverride = ref.watch(localeOverrideProvider);
    return MaterialApp(
      title: 'Clai',
      debugShowCheckedModeBanner: false,
      theme: buildClaiTheme(),
      navigatorKey: _navKey,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      locale: localeOverride == null ? null : Locale(localeOverride),
      home: Builder(
        builder: (context) {
          // Daftarkan instance aktif untuk service/handler (teks pengguna
          // yang dihasilkan di luar pohon widget).
          setCurrentL10n(AppLocalizations.of(context));
          return Scaffold(
            key: _scaffoldKey,
            // Pola shell yang benar (v4.4.1): resize eksplisit — saat keyboard
            // membuka, body menyusut dan chrome bawah (Positioned bottom: 0)
            // menempel tepat di atas keyboard, tidak tertutup & tidak melompat.
            // Biaya per-frame animasi inset ditekan RepaintBoundary pada chrome
            // dan pada baris daftar (SongRow).
            resizeToAvoidBottomInset: true,
            body: Stack(
              children: [
                Positioned.fill(
                  child: SafeArea(
                    bottom: false,
                    child: IndexedStack(index: _tab, children: screens),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: RepaintBoundary(child: _bottomChrome(context)),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Chrome bawah melayang (v4.4, referensi Spotify dari pemilik): BUKAN balok
  /// solid — lapisan gradasi transparan → warna latar di atas konten yang
  /// digulir (konten memudar di belakangnya), mini player sebagai kartu
  /// melayang, lalu bar navigasi transparan. Gradasi dipilih alih-alih blur:
  /// jauh lebih ringan untuk GPU kelas bawah, tampilan setara.
  ///
  /// Ronde 2006: scrim sempat menjadi lapisan setinggi gugus + pita pudar
  /// 56 dp di atasnya (stops v4.4.1) agar transisinya tidak seluruhnya
  /// jatuh di balik kartu/nav. Geometri gugus (celah 2, kartu 64,
  /// margin 1, nav 54) TIDAK berubah.
  ///
  /// Ronde Putusan Desain butir B: scrim diwarnai [chromeScrimColors]
  /// dari tinta sampul trek berjalan/terakhir (pipa aksen dinamis yang
  /// sama dengan kartu Beranda/Player/mini player); tanpa trek ia netral.
  ///
  /// Ronde Koreksi Gradasi (perintah pemilik atas 2010): DUA koreksi —
  /// (1) seluruh ruas scrim semi-transparan (tak ada ruas opak; lihat
  /// profil alfa di [kScrimNavTopAlpha]); (2) lukisan scrim DIPANGKAS
  /// hanya ke bawah mini player: tepi atasnya duduk di tepi BAWAH kartu,
  /// menaungi margin bawah kartu + bilah navigasi + inset saja
  /// ([chromeScrimHeight]). Pita pudar di atas gugus dihapus — konten
  /// tampil jernih sampai menyentuh tepi atas kartu. Geometri gugus
  /// (posisi kartu, celah, nav) tetap persis; yang berubah hanya luas
  /// lukisan scrim.
  Widget _bottomChrome(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final clusterHeight =
        kChromeTopGap +
        kMiniPlayerHeight +
        kMiniPlayerBottomMargin +
        kNavBarHeight +
        bottomInset;
    final handler = ref.read(audioHandlerProvider);
    return StreamBuilder<MediaItem?>(
      stream: handler.mediaItem.stream,
      initialData: handler.mediaItem.valueOrNull,
      builder: (context, snap) {
        final item = snap.data;
        return CoverAccentBuilder(
          key: ValueKey('chrome-accent-${item?.id}'),
          artworkUrl: item?.artUri?.toString(),
          builder: (context, tonal) => SizedBox(
            height: clusterHeight,
            child: Stack(
              children: [
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: chromeScrimHeight(bottomInset),
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: chromeScrimColors(tonal),
                          stops: kChromeScrimStops,
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: kChromeTopGap),
                      // Bilah offline (DS 6.12): keadaan yang dinyatakan, bukan kesalahan.
                      StreamBuilder(
                        stream: ref.read(audioHandlerProvider).queueStream,
                        builder: (context, _) {
                          if (!ref.read(audioHandlerProvider).offlineMode)
                            return const SizedBox.shrink();
                          return Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: ClaiColors.surface2,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                children: [
                                  ClaiIcon(
                                    ClaiIcons.cloudOff,
                                    size: 18,
                                    color: ClaiColors.warning,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      context.l10n.offlineBarText,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: ClaiColors.inkSecondary,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                      const MiniPlayer(),
                      _navBar(context),
                      SizedBox(height: bottomInset),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Bar navigasi gambar-sendiri pada tinggi persis [kNavBarHeight]
  /// (v4.4.2): widget stok NavigationBar merender ~80dp apa pun nilai
  /// height yang dideklarasikan, dengan ruang mati besar di atas ikonnya —
  /// akar "jarak mini player ke nav terasa jauh". Di sini ikon mulai
  /// [kNavBarTopPad] dari tepi atas zona nav; label selalu utuh.
  Widget _navBar(BuildContext context) {
    final s = context.l10n;
    return SizedBox(
      height: kNavBarHeight,
      child: Row(
        children: [
          _navDestination(0, ClaiIcons.home, ClaiIcons.homeFill, s.navHome),
          _navDestination(1, ClaiIcons.search, ClaiIcons.search, s.navSearch),
          _navDestination(
            2,
            ClaiIcons.library,
            ClaiIcons.libraryFill,
            s.navLibrary,
          ),
        ],
      ),
    );
  }

  Widget _navDestination(
    int index,
    ClaiIconData icon,
    ClaiIconData selectedIcon,
    String label,
  ) {
    final selected = _tab == index;
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        child: InkWell(
          onTap: () => setState(() => _tab = index),
          child: Padding(
            padding: const EdgeInsets.only(top: kNavBarTopPad),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ClaiIcon(
                  selected ? selectedIcon : icon,
                  color: selected ? ClaiColors.ink : ClaiColors.inkFaint,
                ),
                const SizedBox(height: 2),
                // Titik aksen pemilih dipertahankan dari bahasa ikon v4.4;
                // tingginya dipesan juga saat tak terpilih agar label sejajar.
                SizedBox(
                  height: 4,
                  child: selected
                      ? Container(
                          width: 4,
                          height: 4,
                          decoration: const BoxDecoration(
                            color: ClaiColors.accent,
                            shape: BoxShape.circle,
                          ),
                        )
                      : null,
                ),
                const SizedBox(height: 1),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: .4,
                    color: selected ? ClaiColors.ink : ClaiColors.inkFaint,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
