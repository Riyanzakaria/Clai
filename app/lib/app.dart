import 'dart:convert';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart' show listEquals;
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
import 'domain/models.dart';
import 'player/audio_handler.dart';
import 'providers/ytmusic/ytmusic_provider.dart';
import 'providers/spotify/spotify_provider.dart';
import 'services/direct_web_engine.dart';
import 'services/ambient_controller.dart';
import 'services/ambient_theme.dart';
import 'services/waveform.dart';
import 'services/waveform_recorder.dart';
import 'services/audio_fx_service.dart';
import 'services/cover_accent_service.dart';
import 'services/download_service.dart' hide unawaited;
import 'services/driving_service.dart';
import 'services/capture_service.dart';
import 'services/enrichment_service.dart';
import 'services/voice_service.dart';
import 'services/sleep_service.dart';
import 'services/library_controller.dart';
import 'services/listenbrainz_service.dart';
import 'services/track_metadata_healer.dart';
import 'services/local_files.dart';
import 'services/lyrics_service.dart';
import 'services/ocr_model_service.dart';
import 'services/track_matcher.dart';
import 'services/update_service.dart';
import 'ui/collection_screen.dart';
import 'ui/cover_accent_glow.dart';
import 'ui/glass.dart';
import 'ui/haptics.dart';
import 'ui/capture_sheet.dart';
import 'ui/home_screen.dart';
import 'ui/mini_player.dart';
import 'ui/search_screen.dart';

final appDbProvider = Provider<AppDb>((_) => AppDb());

/// Mesin tema "Sampul Hidup" (DS v4.0, Workstream E F3): keadaan tema
/// suasana untuk seluruh aplikasi — lihat services/ambient_theme.dart.
final ambientControllerProvider =
    StateNotifierProvider<AmbientController, AmbientState>(
      (ref) => AmbientController(ref.watch(appDbProvider)),
    );

/// Irisan keadaan ambien untuk konsumen UI (Ronde Optimasi 8053, kelas
/// B(i)): SEMUA field [AmbientState] KECUALI `breathFactor`. Terbitan
/// napas hanya mengubah `breathFactor` (umpan RMS ±2 dtk + peluruhan
/// 300 md) — sebelum ronde ini setiap terbitan napas membangun ulang
/// SELURUH penonton keadaan ambien (akar, kaca chrome, semua layar),
/// padahal faktor napas hanya dikonsumsi SATU tempat: modulasi alfa
/// wash papan Player. Konsumen menonton irisan ini lewat select()
/// langsung di situs watch-nya → nol pembangunan ulang dari napas.
/// Kesetaraan
/// rekaman bersifat struktural: irisan berubah HANYA bila field visual
/// sungguh berubah (palet berganti objek hanya saat warna berubah).
typedef AmbientUiState = ({
  bool enabled,
  AmbientStrength strength,
  bool breathing,
  bool reduceEffects,
  AmbientPalette palette,
});

AmbientUiState ambientUiSlice(AmbientState s) => (
  enabled: s.enabled,
  strength: s.strength,
  breathing: s.breathing,
  reduceEffects: s.reduceEffects,
  palette: s.palette,
);

// CATATAN BENTUK (terukur, tes 8053): konsumen memakai select()
// LANGSUNG di situs watch-nya —
//   ref.watch(ambientControllerProvider.select(ambientUiSlice))
// BUKAN provider perantara yang membungkus select: perantara terbukti
// menelan notifikasi perubahan nyata yang datang SETELAH rangkaian
// emisi tanpa-perubahan (kasus napas → ganti strength tak menyebar).
// Faktor napas dibaca papan Player dengan pola yang sama:
//   ref.watch(ambientControllerProvider.select((s) => s.breathFactor))

/// Perekam waveform ukur (Ronde Player B): ember energi nyata per trek
/// dari aliran RMS Visualizer, persisten di DB — lihat
/// services/waveform_recorder.dart.
final waveformRecorderProvider = ChangeNotifierProvider<WaveformRecorder>(
  (ref) => WaveformRecorder(ref.watch(appDbProvider)),
);
final ytMusicProvider = Provider<YtMusicProvider>(
  (ref) => YtMusicProvider(ref.watch(appDbProvider)),
);
final localFilesProvider = Provider<LocalFilesService>(
  (_) => LocalFilesService(),
);

/// Cache hasil pindai File Lokal sesi ini (Ronde Koreksi Komposisi F3):
/// diisi LocalFilesBody sesudah pengguna memindai di tab Berkas, dibaca
/// baris Berkas Lokal Koleksi untuk meta hitungan NYATA. Null = belum
/// pernah dipindai sesi ini — Koleksi TIDAK memicu pindai/izin sendiri;
/// metanya jatuh ke label tanpa hitungan, bukan angka karangan.
final localScanCacheProvider = StateProvider<List<Track>?>((_) => null);

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

/// Lapisan penyembuhan metadata (Ronde Cacat Metadata): rekam trek ber-artis
/// kosong / tanpa sampul diselesaikan sekali dari provider saat ditampilkan.
final trackMetadataHealerProvider = Provider<TrackMetadataHealer>(
  (ref) => TrackMetadataHealer(
    ref.watch(appDbProvider),
    resolveById: ref.watch(ytMusicProvider).resolveTrackById,
  ),
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
    appBarTheme: AppBarTheme(
      backgroundColor: ClaiColors.base,
      foregroundColor: ClaiColors.ink,
      elevation: 0,
      // DS Bab 3: judul layar = type/title (Clash Display 20/26 600).
      // Satu ketetapan tema untuk SEMUA AppBar — Antrian, Pengaturan +
      // halaman kelompoknya, konten/playlist/radio/unduhan/Spotify,
      // Diagnostik, Log — menggantikan Inter bawaan tema teks.
      // (Kampanye Rombak UI Total — Batch 2.)
      titleTextStyle: displayStyle(20),
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
      // Part terkecil (Ronde Koreksi Komposisi F3): sudut snackbar selaras
      // radius kartu kecil DS, bukan persegi bawaan Material.
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
      ),
    ),
    // Dialog baku DS (Ronde Koreksi Komposisi F3): SATU resep untuk semua
    // AlertDialog — permukaan surface-2 + radius 20 (ClaiRadius.sheet).
    // Dialog yang sudah menyebut backgroundColor sendiri tetap menang;
    // tema ini menambal yang polos agar tak ada dialog Material mentah.
    dialogTheme: const DialogThemeData(
      backgroundColor: ClaiColors.surface2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(ClaiRadius.sheet)),
      ),
      titleTextStyle: TextStyle(
        color: ClaiColors.ink,
        fontSize: 17,
        fontWeight: FontWeight.w600,
      ),
      contentTextStyle: TextStyle(color: ClaiColors.inkSecondary, fontSize: 14),
    ),
    dividerTheme: const DividerThemeData(color: ClaiColors.divider),
    // Kelas kontrol baku DS (Ronde Sapuan Part Kecil Total 8045): SATU
    // resep tema untuk sakelar, geser, centang, menu popup, dan tombol
    // isi/tepi — permukaan yang tidak menyebut gayanya sendiri (baris
    // Pengaturan, Diagnostik, lembar) tidak lagi jatuh ke Material
    // mentah. Gaya eksplisit di titik pakai tetap menang atas tema.
    switchTheme: SwitchThemeData(
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected)
            ? ClaiColors.accent
            : ClaiColors.surface3,
      ),
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected)
            ? ClaiColors.onAccent
            : ClaiColors.inkSecondary,
      ),
      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
    ),
    sliderTheme: const SliderThemeData(
      activeTrackColor: ClaiColors.accent,
      inactiveTrackColor: ClaiColors.surface3,
      thumbColor: ClaiColors.accent,
      overlayColor: Color(0x29B8F135),
      trackHeight: 3,
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected)
            ? ClaiColors.accent
            : Colors.transparent,
      ),
      checkColor: WidgetStateProperty.all(ClaiColors.onAccent),
      side: const BorderSide(color: ClaiColors.inkFaint, width: 1.5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(5)),
      ),
    ),
    popupMenuTheme: const PopupMenuThemeData(
      color: ClaiColors.surface2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
      ),
      textStyle: TextStyle(color: ClaiColors.ink, fontSize: 15),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(999)),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: ClaiColors.ink,
        side: const BorderSide(color: ClaiColors.divider),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(999)),
        ),
      ),
    ),
  );
}

/// Family font tampilan (DS Bab 3; keputusan pemilik 2026-11-10,
/// staging 8049): **Clash Display** terbundel — menggantikan Space
/// Grotesk yang sebelumnya dimuat GoogleFonts. SATU nama untuk semua
/// gaya tampilan agar tak ada rujukan font lama yang tertinggal.
const String kDisplayFontFamily = 'Clash Display';

/// Judul display Clash Display (DS Bab 3).
TextStyle displayStyle(double size) => TextStyle(
  fontFamily: kDisplayFontFamily,
  fontSize: size,
  fontWeight: FontWeight.w600,
  color: ClaiColors.ink,
  height: 1.18,
);

/// Tingkat pahlawan `type/hero` (DS v4.0 §3-P4): Clash Display 34–40
/// HANYA untuk momen pahlawan — sapaan Beranda, angka waktu Player,
/// kelak angka Statistik. Angka tabular agar waktu tidak berjoget.
TextStyle heroStyle(double size) => TextStyle(
  fontFamily: kDisplayFontFamily,
  fontSize: size,
  fontWeight: FontWeight.w600,
  color: ClaiColors.ink,
  height: 1.1,
  fontFeatures: const [FontFeature.tabularFigures()],
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

/// Margin sisi kartu mini player (kiri & kanan) — tapak horizontal
/// kartu. Dipakai lukisan penopang chrome untuk tahu di mana kartu
/// berakhir dan sisi kosongnya mulai (Kampanye Rombak UI, putusan
/// pemilik 2026-11-09 11:18: sisi kosong itu harus TRANSPARAN).
const double kMiniPlayerSideMargin = 12;

/// ~~Tinggi pita pudar scrim di atas gugus~~ — DIHAPUS pada Ronde Koreksi
/// Gradasi (perintah pemilik 25 Okt 12:17 WIB atas build 2010): gradasi
/// dinilai KETINGGIAN karena pita +56 dp ini melukis lapisan sampai di
/// atas mini player. Perintahnya: gradasi hanya boleh hidup DI BAWAH mini
/// player — "dibawah miniplayer, ga sampe miniplayer". Kini lukisan scrim
/// hanya menaungi margin bawah kartu + bilah navigasi + inset bawah
/// (lihat [chromeScrimHeight]); konten yang digulir tampil jernih sampai
/// menyentuh tepi atas kartu. Geometri gugus tidak berubah sama sekali.
///
/// Profil gradasi scrim warisan (tema mati) — Ronde Perbaikan Scrim,
/// vonis pemilik 2026-11-09 10:06 atas tangkapan HP-nya (build 6035):
/// profil lama yang dikalibrasi "tipis seperti Spotify" (25 Okt 2026:
/// 0,32 tepat di bawah kartu → 0,55 zona ikon → 0,85 tepi paling
/// bawah) membiarkan judul rak terang ("Koleksi Kamu") TERBACA
/// menghantui di belakang ikon/label nav, dan alfa awal 0,32 tepat di
/// bawah kartu menggambar garis terang yang bisa ditunjuk di
/// perbatasan kartu. Standar pemilik kini terukur dan menggantikan
/// kalibrasi lama: gradasi mencapai nyaris pekat pada titik yang
/// masih TERTUTUP di balik kartu, melintasi tepi bawah kartu tanpa
/// anak tangga yang bisa ditunjuk, dan teks terang yang terparkir di
/// zona chrome tidak terbaca lagi.
///
/// Lukisan kini mulai [kChromeScrimTuck] dp di atas tepi bawah kartu
/// (tertutup kartu opak; di strip margin 12 dp ia terbaca sebagai
/// bayangan kartu) dan berjangkar pada tepi bawah kartu:
/// - Tepi atas lukisan: alfa 0,88 (pita sudut kartu).
/// - +6 dp: alfa 0,97 — titik nyaris-pekat, masih tertutup kartu.
/// - Tepi bawah kartu (+16 dp): alfa 0,99.
/// - +40 dp dan tepi paling bawah: alfa 1,00, warna menggeser halus
///   ke arah [ClaiColors.base].
/// Wujud klasiknya dipertahankan — gradasi tonal berwarna sampul di
/// bawah kartu melayang dan nav transparan di atasnya; yang diganti
/// hanya kurvanya. Susunan warna+hentian: [chromeScrimGradient].
const double kChromeScrimTuck = 16;
const List<double> kChromeScrimBandDp = [0, 6, 16, 40];
const List<double> kChromeScrimBandAlphas = [0.88, 0.97, 0.99, 1.0];

/// CHROME BERSIH — putusan final pemilik 2026-11-10 11:43 (ronde
/// 8046): pada tema hidup TIDAK ada lagi lukisan penggelap apa pun
/// di sekitar chrome. Falloff panjang di atas kartu mini dan fade
/// penopang zona nav DIHAPUS TOTAL dari kode — bukan dimatikan,
/// dihapus — karena dua ronde perbaikan sebelumnya (penopang
/// dipangkas ke strip nav pada Koreksi Chrome 2; ekor alfa di tepi
/// falloff pada Sapuan 8045) tetap menyisakan pita hitam yang bisa
/// ditunjuk pemilik di HP-nya: "daritadi padahal aku ingin
/// hilangkan itu jadi harusnya BERSIH". Yang menjaga keterbacaan
/// di balik chrome kini HANYA bahan kaca kartu mini & bilah nav
/// itu sendiri (blur + tint permukaannya). Konsekuensi yang
/// dipilih pemilik dan dicatat apa adanya: teks terang yang
/// terparkir di belakang nav dapat tampak menghantui — harga yang
/// ia terima demi chrome yang bersih. Fungsi-fungsi fade yang
/// tersisa di bagian ini kini melayani tema warisan saja (tema
/// mati TIDAK berubah).

/// Wilayah lukisan penopang chrome — sejak ronde 8046 fungsi ini
/// beserta [ChromeBackingPainter] HANYA melayani tema warisan:
/// pada tema hidup tidak ada lukisan penopang sama sekali (putusan
/// final pemilik 2026-11-10 11:43; lihat catatan chrome bersih di
/// atas). Geometri yang dikembalikan tidak berubah dari Koreksi
/// Chrome 2: SATU daerah dari tepi atas strip nav
/// ([cardBottomY] + [kMiniPlayerBottomMargin]) sampai dasar layar —
/// di mode warisan, di daerah itulah fade zona nav tinggal; pita
/// kartu, celahnya, dan kedua sisinya tidak dilukis.
///
/// [cardBottomY] = jarak dari tepi atas lukisan ke tepi bawah kartu
/// (mode warisan: [kChromeScrimTuck]).

List<Rect> chromeBackingRects({
  required double width,
  required double height,
  required double cardBottomY,
}) {
  return [
    Rect.fromLTRB(0, cardBottomY + kMiniPlayerBottomMargin, width, height),
  ];
}

/// Profil alfa fade zona nav (lahir di Koreksi Chrome 2; sejak
/// ronde 8046 hanya dipakai tema warisan).
/// nav, naik monoton di dalam strip (16/30/43 dp), pekat 1,00 di
/// tepi bawah strip (54 dp), terminal sesudahnya. Kenaikan per baris
/// piksel tertahan ≤ ±3/255 bahkan di atas konten putih murni —
/// standar anak tangga kolom margin ronde scrim.
const List<double> kChromeNavFadeAlphas = [0, 0, 0.38, 0.75, 0.95, 1.0, 1.0];

/// Hentian fade zona nav untuk tinggi lukisan [height]; dua hentian
/// pertama (0 dan tepi atas strip) sama-sama alfa 0 — gradasi shader
/// datar-transparan di seluruh pita kartu.
List<double> chromeNavFadeStops(double height, double cardBottomY) {
  final navTop = cardBottomY + kMiniPlayerBottomMargin;
  double f(double dp) => (dp / height).clamp(0.0, 1.0);
  return [
    0,
    f(navTop),
    f(navTop + 16),
    f(navTop + 30),
    f(navTop + 43),
    f(navTop + kNavBarHeight),
    1.0,
  ];
}

/// Fade zona nav mode warisan: permukaan tonal sampul (disaring
/// [readableAccentSurface]) bergeser ke [ClaiColors.base] sambil
/// memekat — terminalnya sama dengan scrim warisan lama, profilnya
/// profil Koreksi Chrome 2.
({List<Color> colors, List<double> stops}) chromeNavFadeLegacyGradient(
  Color? tonal,
  double height,
  double cardBottomY,
) {
  final surface = tonal == null
      ? ClaiColors.base
      : readableAccentSurface(tonal);
  Color at(double lerpToBase, double alpha) => Color.lerp(
    surface,
    ClaiColors.base,
    lerpToBase,
  )!.withValues(alpha: alpha);
  const lerps = [0.0, 0.0, 0.0, 0.15, 0.35, 0.5, 0.5];
  final colors = <Color>[
    for (var i = 0; i < kChromeNavFadeAlphas.length; i++)
      at(lerps[i], kChromeNavFadeAlphas[i]),
  ];
  return (colors: colors, stops: chromeNavFadeStops(height, cardBottomY));
}

/// Pelukis penopang chrome: satu shader gradasi (dibuat atas persegi
/// wilayah lukisan utuh) dilukis hanya pada [chromeBackingRects].
/// Sejak ronde 8046 pelukis ini hanya dipakai tema warisan; tema
/// hidup tidak melukis penopang apa pun di belakang chrome.

class ChromeBackingPainter extends CustomPainter {
  final List<Color> colors;
  final List<double> stops;
  final double cardBottomY;

  const ChromeBackingPainter({
    required this.colors,
    required this.stops,
    required this.cardBottomY,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: colors,
        stops: stops,
      ).createShader(Offset.zero & size);
    for (final r in chromeBackingRects(
      width: size.width,
      height: size.height,
      cardBottomY: cardBottomY,
    )) {
      canvas.drawRect(r, paint);
    }
  }

  @override
  bool shouldRepaint(ChromeBackingPainter old) =>
      old.cardBottomY != cardBottomY ||
      !listEquals(old.colors, colors) ||
      !listEquals(old.stops, stops);
}

/// kartu, bukan celah atas kartu (perintah pemilik, Koreksi Gradasi).
double chromeScrimHeight(double bottomInset) =>
    kMiniPlayerBottomMargin + kNavBarHeight + bottomInset;

/// Tinggi lukisan scrim warisan kini (Ronde Perbaikan Scrim): ruas di
/// bawah kartu ditambah pita sudut [kChromeScrimTuck] yang tertutup
/// kartu — lukisan mulai di atas tepi bawah kartu, BUKAN di atas
/// gugus; tak ada pita pudar di atas kartu.
double chromeScrimPaintHeight(double bottomInset) =>
    kChromeScrimTuck + chromeScrimHeight(bottomInset);

/// Gradasi scrim chrome bawah mode warisan (Ronde Putusan Desain
/// butir B — perintah pemilik: "di belakang navigation bar itu
/// gradasi", berwarna mengikuti sampul; profil alfa diganti total
/// pada Ronde Perbaikan Scrim, lihat [kChromeScrimBandAlphas]).
/// Tanpa aksen: gradasi netral [ClaiColors.base]. Dengan aksen:
/// tinta sampul (disaring [readableAccentSurface] agar label nav
/// tetap kontras), menggeser ke arah base saat menuruni zona nav.
/// [height] = tinggi lukisan ([chromeScrimPaintHeight] perangkat).
({List<Color> colors, List<double> stops}) chromeScrimGradient(
  Color? tonal,
  double height,
) {
  final surface = tonal == null
      ? ClaiColors.base
      : readableAccentSurface(tonal);
  Color at(double lerpToBase, double alpha) => Color.lerp(
    surface,
    ClaiColors.base,
    lerpToBase,
  )!.withValues(alpha: alpha);
  final colors = <Color>[
    at(0, kChromeScrimBandAlphas[0]),
    at(0, kChromeScrimBandAlphas[1]),
    at(0, kChromeScrimBandAlphas[2]),
    at(0.35, kChromeScrimBandAlphas[3]),
    at(0.5, 1.0),
  ];
  final stops = <double>[
    for (final dp in kChromeScrimBandDp) (dp / height).clamp(0.0, 1.0),
    1.0,
  ];
  return (colors: colors, stops: stops);
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

/// Kunci navigator AKAR aplikasi (MaterialApp). Dipakai juga oleh
/// [sheetHostContext].
final GlobalKey<NavigatorState> claiRootNavigatorKey =
    GlobalKey<NavigatorState>();

/// Penekan chrome cangkang (audit 8047, observasi Mode Mobil #16):
/// selama layar Menyetir tampil, kartu mini + nav cangkang disembunyikan
/// — layar itu punya kendali putar raksasanya sendiri, dan chrome ganda
/// di atasnya adalah kendali ganda + banjir cahaya Volt di zona bawah.
///
/// PELAJARAN BISEK 8047 (jangan ulangi dua jalan buntu ini):
/// 1. Menukar anak Stack chrome menjadi SizedBox.shrink() saat bendera
///    naik membuat rute Menyetir HITAM TOTAL di build rilis emulator
///    (tanpa satu pun error terlog; tes widget dengan pola sama lulus —
///    bedanya bangku punya DirectEngineHost (platform view WebView)
///    berbagi Stack yang sama, jadi pertukaran struktur anak Stack
///    adalah pemicu yang konsisten dengan semua bukti).
/// 2. Mendorong DrivingScreen pada navigator akar gagal "No
///    ProviderScope found" (log insiden 2026-11-10 16:31) — scope
///    aplikasi hidup di dalam sub-pohon cangkang.
/// Maka penekanan di sini WAJIB tanpa pertukaran struktur: chrome
/// selalu terpasang persis seperti biasa, hanya dilukis transparan +
/// diabaikan sentuhnya (Opacity + IgnorePointer) selama bendera naik.
final ValueNotifier<bool> claiChromeSuppressed = ValueNotifier<bool>(false);

/// Konteks di dalam overlay navigator aplikasi (MaterialApp ClaiApp) —
/// tuan rumah untuk SEMUA lembar modal dan rute yang wajib menutupi
/// seluruh cangkang (Player, Antrean, lembar-lembar).
///
/// Kenapa tidak `useRootNavigator: true`? Aplikasi ini punya DUA
/// MaterialApp: ProviderScope Riverpod tinggal di dalam `home`
/// MaterialApp bootstrap (bootstrap.dart), DI BAWAH navigator ClaiApp
/// tapi DI ATASNYA tidak ada scope. Flag `useRootNavigator` mengangkat
/// rute ke navigator BOOTSTRAP — di luar ProviderScope — sehingga
/// widget pemakai Riverpod di sana melempar "No ProviderScope found"
/// dan tampil sebagai kotak abu-abu ErrorWidget pada build profile
/// (terbukti di emulator, Ronde Tambahan 2015: Player, Tangkap, dan
/// layar Antrean abu-abu penuh; lembar konteks selamat hanya karena
/// isinya tidak membaca provider). Dari konteks overlay ini,
/// `Navigator.of` menuju navigator ClaiApp — tetap di dalam scope,
/// tetap menutupi cangkang.
BuildContext claiRootContext(BuildContext fallback) =>
    claiRootNavigatorKey.currentState?.overlay?.context ?? fallback;

class ClaiApp extends ConsumerStatefulWidget {
  const ClaiApp({super.key});
  @override
  ConsumerState<ClaiApp> createState() => _ClaiAppState();
}

class _ClaiAppState extends ConsumerState<ClaiApp> with WidgetsBindingObserver {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _navKey = claiRootNavigatorKey;

  /// Navigator DALAM cangkang (Ronde Tambahan 2015, Butir 4): rute konten
  /// yang didorong dari tab (playlist, halaman konten, radio, Pengaturan
  /// + sub-halamannya) hidup di sini — DI BAWAH lapisan chrome melayang —
  /// sehingga navbar + mini player tetap tampil & interaktif di atasnya,
  /// ala Spotify. Yang tetap di navigator AKAR (menutupi penuh seperti
  /// sebelumnya): Player (lembar modal), layar Antrean, dan semua lembar
  /// modal/dialog — pembuka mereka memakai rootNavigator secara eksplisit.
  final _shellNavKey = GlobalKey<NavigatorState>();

  /// Tab aktif sebagai ValueNotifier: halaman akar navigator dalam dan
  /// bilah navigasi sama-sama mendengarkannya, jadi ganti tab tidak
  /// bergantung pada pembangunan ulang pohon navigator.
  final ValueNotifier<int> _tabNotifier = ValueNotifier<int>(0);

  /// Audit UX 2017: petunjuk geser mini player satu-kali (pref
  /// `ui.miniSwipeHintSeen`). Default true = tersembunyi sampai pref
  /// terbaca di initState, supaya tidak berkedip bagi pengguna yang
  /// sudah pernah menutupnya.
  bool _miniSwipeHintSeen = true;

  Future<void> _loadMiniSwipeHint() async {
    final seen =
        await ref.read(appDbProvider).pref<bool>('ui.miniSwipeHintSeen') ??
        false;
    if (mounted && seen != _miniSwipeHintSeen) {
      setState(() => _miniSwipeHintSeen = seen);
    }
  }

  /// Mengubur petunjuk geser untuk selamanya: tombol tutup ATAU geser
  /// pertama yang berhasil (keduanya membuktikan petunjuk tak lagi perlu).
  void _dismissMiniSwipeHint() {
    if (_miniSwipeHintSeen) return;
    setState(() => _miniSwipeHintSeen = true);
    ref
        .read(appDbProvider)
        .setPref('ui.miniSwipeHintSeen', true)
        .catchError((_) {});
  }

  /// Ganti tab ala cangkang: tumpukan rute dalam selalu dipulangkan ke
  /// akar dulu (mengetuk tab dari halaman yang didorong menampilkan tab
  /// itu, bukan mengganti isi di balik halaman).
  void _goTab(int index) {
    final nav = _shellNavKey.currentState;
    if (nav != null && nav.canPop()) {
      nav.popUntil((route) => route.isFirst);
    }
    _tabNotifier.value = index;
  }

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

  /// Tarik berbagi yang menunggu di sisi natif ('initialShared'
  /// mengembalikan + menghapusnya, jadi tarikan ganda aman). Dipanggil
  /// sekali sesudah bingkai pertama (jalur dingin) dan SETIAP aplikasi
  /// kembali ke depan. Inilah perbaikan cacat berbagi hangat F2.5: bila
  /// activity dihancurkan sistem saat aplikasi di latar (umum di ROM
  /// agresif seperti HyperOS, sementara proses + layanan musik tetap
  /// hidup), instance MainActivity yang baru menampung berbagi hangat
  /// sebagai pendingShare dengan sink EventChannel yang sudah mati —
  /// sebelumnya tak ada penarik sesudah initState, jadi berbagi itu
  /// hilang diam-diam dan aplikasi hanya tampil ke depan (laporan
  /// pemilik di build 2014). Kini setiap 'resumed' menariknya.
  Future<void> _pullPendingShare() async {
    try {
      final pending = await CaptureService.takePendingShare();
      if (pending != null) _openCapture(pending);
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _pullPendingShare();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tabNotifier.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadMiniSwipeHint();
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
    // F2.5: peredupan bentang akhir timer tidur — layanan memberi tahu
    // kapan rampa harus mulai/batal; mode akhir-lagu dipicu handler dari
    // posisi trek (gerbang keadaan terpasang dibaca lewat kait ini).
    sleep.onFadeStart = (remaining) => handler.beginSleepFade(remaining);
    sleep.onFadeCancel = () => handler.cancelSleepFade();
    handler.sleepEndOfSongArmed = () => sleep.active?.mode == 'endOfSong';
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
    // Ronde 8063: Berikutnya/Sebelumnya manual TIDAK membatalkan
    // timer tidur aktif — kait navigasi tersendiri di layanan.
    handler.onManualTrackSkip = () => sleep.handleManualTrackSkip();
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
    // Mesin tema "Sampul Hidup" (DS v4.0 §5): tiap trek berjalan memberi
    // warna tanda tangan sampulnya ke kontroler tema; kontroler menahan
    // ganti-cepat (tinta menetap) dan menurunkan palet untuk seluruh UI.
    // Napas (U1) diberi makan aliran RMS Visualizer yang sama dengan
    // estimator kenyaringan — tidak ada Visualizer kedua.
    final amb = ref.read(ambientControllerProvider.notifier);
    handler.mediaItem.listen((item) {
      ClaiHaptics.trackLanded(
        item?.id,
        playing: handler.playbackState.valueOrNull?.playing ?? false,
      );
      if (item == null) return;
      final db = ref.read(appDbProvider);
      CoverAccentService(db)
          .sourceForUrl(item.artUri?.toString())
          .then((src) => amb.setSource(item.id, src))
          .catchError((_) {});
    });
    AudioFxService().rmsEvents.listen(
      (e) {
        final rmsDb = (e['rmsDb'] as num?)?.toDouble();
        if (rmsDb == null) return;
        // Detak untuk penjaga kesehatan Visualizer handler (Ronde
        // 8050): peristiwa ini sendiri adalah bukti rantai hidup.
        handler.noteRmsHeartbeat();
        final playingNow = handler.playbackState.valueOrNull?.playing ?? false;
        amb.feedRms(rmsDb, playing: playingNow);
        // Konsumen ketiga aliran yang sama: waveform ukur Player.
        // Ember diisi dari posisi & durasi trek aktif SAAT sampel tiba
        // (pola atribusi yang sama dengan estimator kenyaringan).
        final cur = handler.engine.current;
        // Instrumentasi atribusi (Ronde Perbaikan Waveform Perangkat):
        // peristiwa RMS membawa sessionId sesi pemiliknya — catat apakah
        // ia berasal dari pemain yang sedang berbunyi dan apakah kunci
        // umpan (engine) sama dengan kunci yang dimuat pemain itu.
        final evSession = (e['sessionId'] as num?)?.toInt();
        final activeSession = handler.activeAudioSessionId;
        ref
            .read(waveformRecorderProvider)
            .noteRmsEvent(
              fromActiveSession:
                  evSession != null && evSession == activeSession,
              hasCurrent: cur != null,
              feedKey: cur?.key,
              soundingKey: handler.soundingKey,
            );
        if (cur != null) {
          ref
              .read(waveformRecorderProvider)
              .feed(
                key: cur.key,
                position: handler.position,
                duration:
                    cur.duration ??
                    handler.mediaItem.valueOrNull?.duration ??
                    Duration.zero,
                rmsDb: rmsDb,
                playing: playingNow,
              );
        }
      },
      onError: (_) {
        /* kanal putus: napas diam, bukan crash */
      },
    );
    // Gerbang konsumen Visualizer untuk napas (perbaikan U1, ronde
    // Player F3): handler menyalakan Visualizer bila normalisasi ATAU
    // napas membutuhkannya. Tanpa kabel ini napas mati biner pada
    // setiap pemasangan yang normalisasinya mati (bawaan) — vonis
    // perangkat 2026-11-09 10:44. Keadaan awal disinkronkan seketika;
    // perubahan pref tema (yang memuat asinkron) tertangkap listener.
    // Ronde 8064 — prasyarat izin rantai ukur: Visualizer Android
    // mewajibkan izin mikrofon walau tidak merekam apa pun; tanpa
    // izin, visStart gagal ("error: -3") dan waveform + napas +
    // gain normalisasi mati senyap sementara penjaga menegaskan
    // ulang ke dinding yang sama (terbukti di emulator: RMS 0,
    // jaga 17+ kali, log penuh 'vis-gagal-mulai'). Sebelumnya izin
    // hanya diminta sakelar normalisasi & lembar suara — permukaan
    // waveform/napas tidak punya jalan minta sendiri, jadi rantai
    // hanya pulih bila izin kebetulan diberikan di tempat lain.
    // Kini: SEKALI per proses, saat ada konsumen yang membutuhkan
    // Visualizer dan aplikasi di depan, cangkang meminta izinnya;
    // pemberian izin menegaskan ulang Visualizer seketika.
    var micAskedForVis = false;
    var micKnownGranted = false;
    Future<void> ensureMicForVisualizer(bool consumerWants) async {
      if (micKnownGranted) return;
      final granted = await AudioFxService().micGranted();
      if (granted) {
        micKnownGranted = true;
        return;
      }
      if (!shouldRequestMicForVisualizer(
        consumerWants: consumerWants,
        alreadyAsked: micAskedForVis,
        granted: granted,
        appResumed:
            WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed,
      )) {
        return;
      }
      micAskedForVis = true;
      if (await AudioFxService().micRequest()) {
        micKnownGranted = true;
        unawaited(handler.reassertVisualizer());
      }
    }

    void syncBreathVis() {
      final s = ref.read(ambientControllerProvider);
      final want = s.enabled && s.breathing && !s.reduceEffects;
      unawaited(handler.setBreathVisWanted(want));
      unawaited(ensureMicForVisualizer(want));
    }

    ref.listenManual(ambientControllerProvider, (_, __) => syncBreathVis());
    syncBreathVis();
    // Suara KETIGA gerbang Visualizer: perekam waveform ukur
    // (Sisipan G-1, 2026-11-10). Cangkang menuliskan kebutuhan
    // perekam dari kelengkapan data trek berjalan — predikat murni
    // waveformWantsVisualizer (data belum lengkap = butuh; penuh =
    // diam, tidak membakar Visualizer). Penilai ulang: ganti trek
    // (listener mediaItem di atas tidak menyentuh ini, jadi kaitnya
    // di sini) dan setiap pemberitahuan perekam (ember terisi / data
    // DB tiba — saat data menjadi penuh, suara padam sendiri).
    final waveformRecorder = ref.read(waveformRecorderProvider);
    void syncWaveformVis() {
      final cur = handler.engine.current;
      if (cur == null) {
        unawaited(handler.setWaveformVisWanted(false));
        return;
      }
      final wants =
          waveformWantsVisualizer(waveformRecorder.dataFor(cur.key));
      unawaited(handler.setWaveformVisWanted(wants));
      unawaited(ensureMicForVisualizer(wants));
    }

    handler.mediaItem.listen((_) => syncWaveformVis());
    waveformRecorder.addListener(syncWaveformVis);
    syncWaveformVis();
    // Unduhan selesai → denyut haptik (U6), lewat kait layanan.
    ref.read(downloadServiceProvider).onDownloadCompleted = (_) {
      ClaiHaptics.downloadDone();
    };
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _pullPendingShare());
  }

  @override
  Widget build(BuildContext context) {
    final localeOverride = ref.watch(localeOverrideProvider);
    // Keadaan tema diamati di sini agar gerbang haptik (U6) selalu sinkron
    // dengan sakelar Kurangi Efek. 8053 B(i): hanya field reduceEffects
    // yang dibutuhkan akar — select() agar terbitan napas tidak membangun
    // ulang seluruh pohon MaterialApp; disableAnimations dibaca lewat
    // aksesor beraspek agar animasi inset keyboard (aspek viewInsets)
    // tidak membangun ulang akar per bingkai (butir A).
    final ambReduceEffects = ref.watch(
      ambientControllerProvider.select((s) => s.reduceEffects),
    );
    ClaiHaptics.reduceEffects =
        ambReduceEffects ||
        (MediaQuery.maybeDisableAnimationsOf(context) ?? false);
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
          // Butir 4: tombol Kembali sistem — navigator akar hanya punya
          // rute cangkang ini, jadi delegasikan ke navigator dalam:
          // pulangkan rute kontennya bila ada; di akar tab, keluar
          // aplikasi seperti sebelumnya.
          return PopScope(
            canPop: false,
            onPopInvokedWithResult: (didPop, _) {
              if (didPop) return;
              final nav = _shellNavKey.currentState;
              if (nav != null && nav.canPop()) {
                nav.pop();
              } else {
                SystemNavigator.pop();
              }
            },
            child: Scaffold(
              key: _scaffoldKey,
              // Pola shell yang benar (v4.4.1): resize eksplisit — saat keyboard
              // membuka, body menyusut dan chrome bawah (Positioned bottom: 0)
              // menempel tepat di atas keyboard, tidak tertutup & tidak melompat.
              // Biaya per-frame animasi inset ditekan RepaintBoundary pada chrome
              // dan pada baris daftar (SongRow).
              resizeToAvoidBottomInset: true,
              body: Stack(
                children: [
                  // Mesin WebView DIRECT-1 (Tahap 3): lapisan terbawah,
                  // malas-muat — kosong sampai resolver pertama meminta
                  // mesin; tertutup penuh oleh konten di atasnya.
                  const Positioned(left: 0, top: 0, child: DirectEngineHost()),
                  // Wash "Sampul Hidup" (DS v4.0 §5) di kepala layar tab:
                  // tinta lagu berjalan mewarnai ruangan di belakang
                  // konten; rute yang didorong menutupinya (Scaffold
                  // opak) sehingga dosis layar tugas tetap milik
                  // halamannya sendiri. Dosis mengikuti tab (DS v4.0
                  // §5.2): Beranda = pahlawan, Cari/Koleksi = tugas 40%.
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 0,
                    child: ValueListenableBuilder<int>(
                      valueListenable: _tabNotifier,
                      builder: (context, tab, _) => AmbientWashLayer(
                        kind: tab == 0
                            ? AmbientSurfaceKind.hero
                            : AmbientSurfaceKind.task,
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: SafeArea(
                      bottom: false,
                      child: Navigator(
                        key: _shellNavKey,
                        onGenerateRoute: (settings) => MaterialPageRoute(
                          settings: settings,
                          builder: (_) => ValueListenableBuilder<int>(
                            valueListenable: _tabNotifier,
                            builder: (context, tab, _) => IndexedStack(
                              index: tab,
                              children: [
                                // 8053 B(ii): gerbang visibilitas ticker.
                                // IndexedStack memasang SEMUA tab; tanpa
                                // gerbang ini ticker efek di tab tersembunyi
                                // (mis. EqualizerBars baris yang sedang
                                // diputar) menjadwalkan bingkai selamanya.
                                // TickerMode HANYA membungkam ticker —
                                // keadaan, gulir, dan isi tab tidak
                                // berubah; ticker hidup lagi seketika saat
                                // tab kembali tampil (tes pengunci:
                                // test/optimasi_8053_test.dart).
                                TickerMode(
                                  enabled: tab == 0,
                                  child: HomeScreen(
                                    onGoSearch: () => _goTab(1),
                                    onGoCollection: () => _goTab(2),
                                  ),
                                ),
                                TickerMode(
                                  enabled: tab == 1,
                                  child: const SearchScreen(),
                                ),
                                TickerMode(
                                  enabled: tab == 2,
                                  child: CollectionScreen(
                                    onGoSearch: () => _goTab(1),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    // Audit 8047 (#16): penekanan TANPA pertukaran
                    // struktur (lihat pelajaran bisek pada deklarasi
                    // claiChromeSuppressed) — sub-pohon chrome diteruskan
                    // sebagai `child` agar elemennya identik di kedua
                    // keadaan; yang berubah hanya lukisan + sentuh.
                    child: ValueListenableBuilder<bool>(
                      valueListenable: claiChromeSuppressed,
                      builder: (context, suppressed, child) => IgnorePointer(
                        ignoring: suppressed,
                        child: Opacity(
                          opacity: suppressed ? 0 : 1,
                          child: child,
                        ),
                      ),
                      child: RepaintBoundary(child: _bottomChrome(context)),
                    ),
                  ),
                ],
              ),
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
  /// Ronde Putusan Desain butir B: scrim diwarnai [chromeScrimGradient]
  /// dari tinta sampul trek berjalan/terakhir (pipa aksen dinamis yang
  /// sama dengan kartu Beranda/Player/mini player); tanpa trek ia netral.
  ///
  /// Ronde Koreksi Gradasi (perintah pemilik atas 2010): DUA koreksi —
  /// (1) seluruh ruas scrim semi-transparan (tak ada ruas opak; profil
  /// alfa saat itu 0,32/0,55/0,85); (2) lukisan scrim DIPANGKAS hanya
  /// ke bawah mini player: tepi atasnya duduk di tepi BAWAH kartu,
  /// menaungi margin bawah kartu + bilah navigasi + inset saja
  /// ([chromeScrimHeight]). Pita pudar di atas gugus dihapus — konten
  /// tampil jernih sampai menyentuh tepi atas kartu. Geometri gugus
  /// (posisi kartu, celah, nav) tetap persis; yang berubah hanya luas
  /// lukisan scrim.
  ///
  /// Ronde Perbaikan Scrim (vonis pemilik 2026-11-09 10:06):
  /// kalibrasi "tipis" koreksi (1) di atas DIGANTIKAN standar terukur
  /// pemilik — gradasi mencapai nyaris pekat tertutup di balik
  /// kartu (mode warisan: profil [kChromeScrimBandAlphas] + pita
  /// sudut [kChromeScrimTuck]), supaya perbatasan gradasi↔mini
  /// player tak bisa ditunjuk dan teks terang tak terbaca
  /// menghantui di belakang nav. Geometri tetap.
  ///
  /// Ronde Chrome Bersih (putusan final pemilik 2026-11-10 11:43):
  /// standar anti-hantu di atas sejak ronde ini berlaku untuk mode
  /// warisan saja. Pada tema hidup SELURUH lukisan latar chrome
  /// dihapus total — pemilik menolak sisa gradasi apa pun di
  /// sekitar kartu mini ("harusnya BERSIH"); keterbacaan di balik
  /// chrome diserahkan ke bahan kaca kartu & nav itu sendiri.
  Widget _bottomChrome(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final handler = ref.read(audioHandlerProvider);
    // Tema Dinamis menyala → chrome bersih tanpa lukisan latar
    // (ronde 8046); mati → lukisan warisan persis di bawah.
    final ambOn = ref.watch(
      ambientControllerProvider.select((s) => s.enabled),
    );
    return StreamBuilder<MediaItem?>(
      stream: handler.mediaItem.stream,
      initialData: handler.mediaItem.valueOrNull,
      builder: (context, snap) {
        final item = snap.data;
        return CoverAccentBuilder(
          key: ValueKey('chrome-accent-${item?.id}'),
          artworkUrl: item?.artUri?.toString(),
          // Audit UX 2017 (perbaikan A-6, revisi 2): gugus chrome TIDAK
          // lagi dikunci ke SizedBox setinggi kartu+nav+inset — bilah
          // petunjuk geser satu-kali dan bilah offline hidup di kolom yang
          // sama, dan tinggi terkunci membuat bilah yang muncul meluap ke
          // atas Stack lalu terpotong habis (terbukti di instal segar
          // 26 Okt 2026: tiga layar, nol bilah; Clip.none saja hanya
          // memperbaiki lukisan, bukan hit-test — tombol tutup tetap
          // mati). Stack kini mengukur dirinya dari kolom (anak
          // non-posisi), jadi bilah yang muncul benar-benar menambah
          // tinggi gugus ke atas, dapat diketuk, dan kartu/nav tetap
          // pada jarak yang sama dari bawah karena induknya
          // Positioned(bottom: 0).
          builder: (context, tonal) => Stack(
            children: [
              // Chrome bersih (ronde 8046, putusan final pemilik
              // 2026-11-10 11:43): saat Tema Dinamis menyala TIDAK
              // ada lukisan latar apa pun di sekitar chrome —
              // falloff di atas kartu dan penopang zona nav dihapus
              // total; keterbacaan diserahkan ke bahan kaca kartu
              // mini & bilah nav itu sendiri. Cabang di bawah ini
              // hanya hidup saat tema MATI (warisan, tak berubah).
              if (!ambOn)
                // Scrim warisan profil baru (Ronde Perbaikan Scrim):
                // lukisan mulai kChromeScrimTuck di atas tepi bawah
                // kartu (tertutup kartu) dan mencapai pekat penuh di
                // zona nav — lihat chromeScrimGradient.
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: chromeScrimPaintHeight(bottomInset),
                  child: IgnorePointer(
                    // Kampanye Rombak UI (putusan pemilik 11:18) +
                    // Koreksi Chrome 2 (putusan pemilik 2026-11-10):
                    // saat kartu ada, lukisan dipangkas ke
                    // chromeBackingRects dengan
                    // profil fade zona nav warisan
                    // [chromeNavFadeLegacyGradient]; pita selipan di
                    // sisi kartu dan strip di balik kartu ikut
                    // dibebaskan. Tanpa kartu: profil scrim lama utuh.
                    child: item == null
                        ? DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: chromeScrimGradient(
                                  tonal,
                                  chromeScrimPaintHeight(bottomInset),
                                ).colors,
                                stops: chromeScrimGradient(
                                  tonal,
                                  chromeScrimPaintHeight(bottomInset),
                                ).stops,
                              ),
                            ),
                          )
                        : CustomPaint(
                            painter: ChromeBackingPainter(
                              colors: chromeNavFadeLegacyGradient(
                                tonal,
                                chromeScrimPaintHeight(bottomInset),
                                kChromeScrimTuck,
                              ).colors,
                              stops: chromeNavFadeLegacyGradient(
                                tonal,
                                chromeScrimPaintHeight(bottomInset),
                                kChromeScrimTuck,
                              ).stops,
                              cardBottomY: kChromeScrimTuck,
                            ),
                          ),
                  ),
                ),
              // Kolom non-posisi: Stack mengukur dirinya dari kolom ini.
              Column(
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
                            borderRadius: BorderRadius.circular(12),
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
                  // Audit UX 2017: petunjuk geser mini player SATU
                  // KALI — gestur geser tidak terlihat sama sekali
                  // bagi pengguna baru. Bilah ramping pola bilah
                  // offline, tepat di atas kartu; geometri chrome
                  // yang dikunci tak berubah (tinggi nol saat tiada).
                  StreamBuilder(
                    stream: ref.read(audioHandlerProvider).mediaItem.stream,
                    initialData: ref
                        .read(audioHandlerProvider)
                        .mediaItem
                        .valueOrNull,
                    builder: (context, snap) {
                      if (snap.data == null || _miniSwipeHintSeen) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                        child: Container(
                          padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
                          decoration: BoxDecoration(
                            color: ClaiColors.surface2,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              ClaiIcon(
                                ClaiIcons.next,
                                size: 18,
                                color: ClaiColors.accent,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  context.l10n.miniSwipeHint,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: ClaiColors.inkSecondary,
                                  ),
                                ),
                              ),
                              IconButton(
                                icon: ClaiIcon(
                                  ClaiIcons.close,
                                  size: 18,
                                  color: ClaiColors.inkSecondary,
                                ),
                                tooltip: context.l10n.a11yClose,
                                onPressed: _dismissMiniSwipeHint,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                  MiniPlayer(onSwipeCommitted: _dismissMiniSwipeHint),
                  _navBar(context),
                  SizedBox(height: bottomInset),
                ],
              ),
            ],
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
    final bar = SizedBox(
      height: kNavBarHeight,
      child: ValueListenableBuilder<int>(
        valueListenable: _tabNotifier,
        builder: (context, tab, _) => Row(
          children: [
            _navDestination(
              0,
              ClaiIcons.home,
              ClaiIcons.homeFill,
              s.navHome,
              tab,
            ),
            _navDestination(
              1,
              ClaiIcons.search,
              ClaiIcons.search,
              s.navSearch,
              tab,
            ),
            _navDestination(
              2,
              ClaiIcons.library,
              ClaiIcons.libraryFill,
              s.navLibrary,
              tab,
            ),
          ],
        ),
      ),
    );
    // v4.0 (KD-1 revisi): bilah nav menjadi KACA pada geometri yang sama
    // persis (54 dp, full-width) — bukan pil mengambang, bukan klasik.
    // Tema mati / Kurangi Efek → GlassSurface jatuh ke transparan:
    // bilah v3.1 persis (transparan di atas scrim lama).
    return GlassSurface(radius: 18, fallback: Colors.transparent, child: bar);
  }

  Widget _navDestination(
    int index,
    ClaiIconData icon,
    ClaiIconData selectedIcon,
    String label,
    int activeTab,
  ) {
    final selected = activeTab == index;
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        child: InkWell(
          onTap: () => _goTab(index),
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
