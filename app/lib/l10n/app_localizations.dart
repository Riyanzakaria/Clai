import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_id.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('id'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In id, this message translates to:
  /// **'Clai'**
  String get appTitle;

  /// No description provided for @navHome.
  ///
  /// In id, this message translates to:
  /// **'Beranda'**
  String get navHome;

  /// No description provided for @navSearch.
  ///
  /// In id, this message translates to:
  /// **'Cari'**
  String get navSearch;

  /// No description provided for @navLibrary.
  ///
  /// In id, this message translates to:
  /// **'Koleksi'**
  String get navLibrary;

  /// No description provided for @offlineBarText.
  ///
  /// In id, this message translates to:
  /// **'Mode offline — hanya unduhan & file lokal'**
  String get offlineBarText;

  /// No description provided for @miniSwipeHint.
  ///
  /// In id, this message translates to:
  /// **'Geser kartu pemutar untuk ganti lagu'**
  String get miniSwipeHint;

  /// No description provided for @eqTitle.
  ///
  /// In id, this message translates to:
  /// **'Equalizer'**
  String get eqTitle;

  /// No description provided for @eqChecking.
  ///
  /// In id, this message translates to:
  /// **'Memeriksa dukungan perangkat…'**
  String get eqChecking;

  /// No description provided for @eqUnavailable.
  ///
  /// In id, this message translates to:
  /// **'Equalizer tidak tersedia di perangkat ini — efek Equalizer Android menolak dibuat pada sesi pemain yang sedang hidup. Detail teknisnya tercatat di Log insiden (Pengaturan → Diagnosis Lokal).'**
  String get eqUnavailable;

  /// No description provided for @eqSubtitle.
  ///
  /// In id, this message translates to:
  /// **'Membentuk frekuensi audio Clai saja (menempel ke sesi pemain, bukan audio sistem).'**
  String get eqSubtitle;

  /// No description provided for @eqWaitingSession.
  ///
  /// In id, this message translates to:
  /// **'Mulai putar lagu agar EQ dapat diterapkan ke sesi audio; setelan tersimpan dan diterapkan otomatis saat lagu mulai.'**
  String get eqWaitingSession;

  /// No description provided for @eqPreset.
  ///
  /// In id, this message translates to:
  /// **'Preset'**
  String get eqPreset;

  /// No description provided for @eqCustom.
  ///
  /// In id, this message translates to:
  /// **'Kustom'**
  String get eqCustom;

  /// No description provided for @eqBandLabel.
  ///
  /// In id, this message translates to:
  /// **'{freq} — {db} dB'**
  String eqBandLabel(Object db, Object freq);

  /// No description provided for @ocrModelTitle.
  ///
  /// In id, this message translates to:
  /// **'Model pembaca teks (Tangkap gambar)'**
  String get ocrModelTitle;

  /// No description provided for @ocrModelInstalled.
  ///
  /// In id, this message translates to:
  /// **'Terpasang · {size}{versionPart} — membaca gambar bekerja offline.'**
  String ocrModelInstalled(Object size, Object versionPart);

  /// No description provided for @ocrModelVersionPart.
  ///
  /// In id, this message translates to:
  /// **' · {version}'**
  String ocrModelVersionPart(Object version);

  /// No description provided for @commonDownloadingPct.
  ///
  /// In id, this message translates to:
  /// **'Mengunduh… {pct}%'**
  String commonDownloadingPct(int pct);

  /// No description provided for @ocrModelVerifying.
  ///
  /// In id, this message translates to:
  /// **'Memeriksa keutuhan berkas (checksum)…'**
  String get ocrModelVerifying;

  /// No description provided for @ocrModelNotDownloaded.
  ///
  /// In id, this message translates to:
  /// **'Belum diunduh. Diunduh sekali dari GitHub Releases (±4 MB), tersimpan di perangkat, lalu Tangkap gambar bekerja offline. Tangkap lewat tautan tidak membutuhkannya.'**
  String get ocrModelNotDownloaded;

  /// No description provided for @ocrModelDeleteTitle.
  ///
  /// In id, this message translates to:
  /// **'Hapus model pembaca teks?'**
  String get ocrModelDeleteTitle;

  /// No description provided for @ocrModelDeleteBody.
  ///
  /// In id, this message translates to:
  /// **'Tangkap gambar akan menawarkan unduhan lagi saat berikutnya dipakai. Lagu, antrean, dan unduhan lagu tidak terpengaruh.'**
  String get ocrModelDeleteBody;

  /// No description provided for @commonCancel.
  ///
  /// In id, this message translates to:
  /// **'Batal'**
  String get commonCancel;

  /// No description provided for @commonDelete.
  ///
  /// In id, this message translates to:
  /// **'Hapus'**
  String get commonDelete;

  /// No description provided for @commonRetry.
  ///
  /// In id, this message translates to:
  /// **'Coba lagi'**
  String get commonRetry;

  /// No description provided for @commonDownload.
  ///
  /// In id, this message translates to:
  /// **'Unduh'**
  String get commonDownload;

  /// No description provided for @updateCheck.
  ///
  /// In id, this message translates to:
  /// **'Periksa pembaruan'**
  String get updateCheck;

  /// No description provided for @commonChecking.
  ///
  /// In id, this message translates to:
  /// **'Memeriksa…'**
  String get commonChecking;

  /// No description provided for @updateInstalling.
  ///
  /// In id, this message translates to:
  /// **'Menyerahkan ke pemasang sistem…'**
  String get updateInstalling;

  /// No description provided for @updateTapToCheck.
  ///
  /// In id, this message translates to:
  /// **'Ketuk untuk memeriksa rilis terbaru.'**
  String get updateTapToCheck;

  /// No description provided for @updateInstalledLabel.
  ///
  /// In id, this message translates to:
  /// **'Terpasang: {label} · {status}'**
  String updateInstalledLabel(Object label, Object status);

  /// No description provided for @updateDownloadTag.
  ///
  /// In id, this message translates to:
  /// **'Unduh {tag}'**
  String updateDownloadTag(Object tag);

  /// No description provided for @updateDownloadSub.
  ///
  /// In id, this message translates to:
  /// **'APK diunduh di dalam aplikasi, lalu dipasang lewat konfirmasi sistem Android.'**
  String get updateDownloadSub;

  /// No description provided for @updateInstall.
  ///
  /// In id, this message translates to:
  /// **'Pasang pembaruan'**
  String get updateInstall;

  /// No description provided for @updateInstallSub.
  ///
  /// In id, this message translates to:
  /// **'Berkas sudah terunduh. Pemasangan menampilkan konfirmasi sistem — itu batas Android, bukan pilihan Clai.'**
  String get updateInstallSub;

  /// No description provided for @updateAutoCheck.
  ///
  /// In id, this message translates to:
  /// **'Periksa otomatis'**
  String get updateAutoCheck;

  /// No description provided for @updateAutoCheckSub.
  ///
  /// In id, this message translates to:
  /// **'Paling sering sekali sehari, hanya permintaan publik ke GitHub — tanpa data pengguna.'**
  String get updateAutoCheckSub;

  /// No description provided for @updateAutoDownload.
  ///
  /// In id, this message translates to:
  /// **'Perbarui otomatis (unduh di latar)'**
  String get updateAutoDownload;

  /// No description provided for @updateAutoDownloadSub.
  ///
  /// In id, this message translates to:
  /// **'Rilis baru diunduh sendiri; pemasangannya tetap lewat konfirmasi sistem Android.'**
  String get updateAutoDownloadSub;

  /// No description provided for @updateWifiOnly.
  ///
  /// In id, this message translates to:
  /// **'Unduh hanya via Wi-Fi'**
  String get updateWifiOnly;

  /// No description provided for @updateWifiOnlySub.
  ///
  /// In id, this message translates to:
  /// **'Unduhan otomatis menunggu Wi-Fi; unduhan manual tetap bisa memakai data seluler.'**
  String get updateWifiOnlySub;

  /// No description provided for @updateInstallPermTitle.
  ///
  /// In id, this message translates to:
  /// **'Izin pasang belum diberikan'**
  String get updateInstallPermTitle;

  /// No description provided for @updateInstallPermSub.
  ///
  /// In id, this message translates to:
  /// **'Android mewajibkan izin \"pasang aplikasi tak dikenal\" sebelum Clai bisa memasang pembaruannya sendiri.'**
  String get updateInstallPermSub;

  /// No description provided for @updateBannerTitle.
  ///
  /// In id, this message translates to:
  /// **'Clai {version} tersedia'**
  String updateBannerTitle(Object version);

  /// No description provided for @updateBannerReady.
  ///
  /// In id, this message translates to:
  /// **'Sudah terunduh — tinggal dipasang lewat konfirmasi sistem.'**
  String get updateBannerReady;

  /// No description provided for @updateBannerDefault.
  ///
  /// In id, this message translates to:
  /// **'Unduh di dalam aplikasi, pasang lewat konfirmasi sistem.'**
  String get updateBannerDefault;

  /// No description provided for @commonInstall.
  ///
  /// In id, this message translates to:
  /// **'Pasang'**
  String get commonInstall;

  /// No description provided for @commonLater.
  ///
  /// In id, this message translates to:
  /// **'Nanti saja'**
  String get commonLater;

  /// No description provided for @settingsTitle.
  ///
  /// In id, this message translates to:
  /// **'Pengaturan'**
  String get settingsTitle;

  /// No description provided for @groupPlayback.
  ///
  /// In id, this message translates to:
  /// **'Pemutaran'**
  String get groupPlayback;

  /// No description provided for @groupPlaybackSum.
  ///
  /// In id, this message translates to:
  /// **'Kualitas, Putar Otomatis, Acak Cerdas, transisi'**
  String get groupPlaybackSum;

  /// No description provided for @groupAudio.
  ///
  /// In id, this message translates to:
  /// **'Audio'**
  String get groupAudio;

  /// No description provided for @groupAudioSum.
  ///
  /// In id, this message translates to:
  /// **'Equalizer & normalisasi kenyaringan'**
  String get groupAudioSum;

  /// No description provided for @groupDownloads.
  ///
  /// In id, this message translates to:
  /// **'Unduhan & Offline'**
  String get groupDownloads;

  /// No description provided for @groupDownloadsSum.
  ///
  /// In id, this message translates to:
  /// **'Mode offline & lagu terunduh'**
  String get groupDownloadsSum;

  /// No description provided for @groupAppearance.
  ///
  /// In id, this message translates to:
  /// **'Tampilan'**
  String get groupAppearance;

  /// No description provided for @groupAppearanceSum.
  ///
  /// In id, this message translates to:
  /// **'Aksen warna dari sampul lagu'**
  String get groupAppearanceSum;

  /// No description provided for @groupDriving.
  ///
  /// In id, this message translates to:
  /// **'Berkendara'**
  String get groupDriving;

  /// No description provided for @groupDrivingSum.
  ///
  /// In id, this message translates to:
  /// **'Layar besar & kendali sederhana saat menyetir'**
  String get groupDrivingSum;

  /// No description provided for @groupCapture.
  ///
  /// In id, this message translates to:
  /// **'Tangkap'**
  String get groupCapture;

  /// No description provided for @groupCaptureSum.
  ///
  /// In id, this message translates to:
  /// **'Tautan/gambar dari aplikasi lain jadi antrean'**
  String get groupCaptureSum;

  /// No description provided for @groupBackground.
  ///
  /// In id, this message translates to:
  /// **'Jalan di Latar'**
  String get groupBackground;

  /// No description provided for @groupBackgroundSum.
  ///
  /// In id, this message translates to:
  /// **'Izin notifikasi & baterai'**
  String get groupBackgroundSum;

  /// No description provided for @groupData.
  ///
  /// In id, this message translates to:
  /// **'Data & Penyimpanan'**
  String get groupData;

  /// No description provided for @groupDataSum.
  ///
  /// In id, this message translates to:
  /// **'Cache aliran & riwayat putar'**
  String get groupDataSum;

  /// No description provided for @groupUpdates.
  ///
  /// In id, this message translates to:
  /// **'Pembaruan'**
  String get groupUpdates;

  /// No description provided for @groupUpdatesSum.
  ///
  /// In id, this message translates to:
  /// **'Versi terpasang & rilis baru dari GitHub'**
  String get groupUpdatesSum;

  /// No description provided for @groupListenBrainzSum.
  ///
  /// In id, this message translates to:
  /// **'Scrobble opsional dengan token milikmu'**
  String get groupListenBrainzSum;

  /// No description provided for @groupDiagnostics.
  ///
  /// In id, this message translates to:
  /// **'Diagnosis'**
  String get groupDiagnostics;

  /// No description provided for @groupDiagnosticsSum.
  ///
  /// In id, this message translates to:
  /// **'Uji rantai putar & log insiden di perangkat'**
  String get groupDiagnosticsSum;

  /// No description provided for @groupAbout.
  ///
  /// In id, this message translates to:
  /// **'Tentang'**
  String get groupAbout;

  /// No description provided for @groupAboutSum.
  ///
  /// In id, this message translates to:
  /// **'Versi, lisensi, dan cara Clai bekerja'**
  String get groupAboutSum;

  /// No description provided for @setQuality.
  ///
  /// In id, this message translates to:
  /// **'Kualitas streaming'**
  String get setQuality;

  /// No description provided for @qualityLow.
  ///
  /// In id, this message translates to:
  /// **'Rendah · ≤70 kbps'**
  String get qualityLow;

  /// No description provided for @qualityNormal.
  ///
  /// In id, this message translates to:
  /// **'Normal · ≤160 kbps'**
  String get qualityNormal;

  /// No description provided for @qualityHigh.
  ///
  /// In id, this message translates to:
  /// **'Tinggi · terbaik tersedia (sumber maks ±256 kbps)'**
  String get qualityHigh;

  /// No description provided for @setAutoplay.
  ///
  /// In id, this message translates to:
  /// **'Putar Otomatis'**
  String get setAutoplay;

  /// No description provided for @setAutoplaySub.
  ///
  /// In id, this message translates to:
  /// **'Menyambung lagu terkait saat antrean habis.'**
  String get setAutoplaySub;

  /// No description provided for @setSmartShuffle.
  ///
  /// In id, this message translates to:
  /// **'Acak Cerdas (Smart Shuffle)'**
  String get setSmartShuffle;

  /// No description provided for @setSmartShuffleSub.
  ///
  /// In id, this message translates to:
  /// **'Mengurut ulang Lanjutan saja; tidak menambah lagu baru.'**
  String get setSmartShuffleSub;

  /// No description provided for @setAutoResume.
  ///
  /// In id, this message translates to:
  /// **'Lanjut otomatis setelah interupsi'**
  String get setAutoResume;

  /// No description provided for @setAutoResumeSub.
  ///
  /// In id, this message translates to:
  /// **'Mis. sesudah panggilan telepon selesai.'**
  String get setAutoResumeSub;

  /// No description provided for @setTransition.
  ///
  /// In id, this message translates to:
  /// **'Mode transisi'**
  String get setTransition;

  /// No description provided for @setTransitionSub.
  ///
  /// In id, this message translates to:
  /// **'Berlaku mulai batas lagu berikutnya.'**
  String get setTransitionSub;

  /// No description provided for @transitionSnack.
  ///
  /// In id, this message translates to:
  /// **'Mode baru berlaku di lagu berikutnya.'**
  String get transitionSnack;

  /// No description provided for @setCrossfadeDur.
  ///
  /// In id, this message translates to:
  /// **'Durasi crossfade'**
  String get setCrossfadeDur;

  /// No description provided for @crossfadeDurVal.
  ///
  /// In id, this message translates to:
  /// **'{secs} detik — rentang 1–12 detik.'**
  String crossfadeDurVal(Object secs);

  /// No description provided for @playbackFootnote.
  ///
  /// In id, this message translates to:
  /// **'Gapless menyambung lagu tanpa jeda. Crossfade memudarkan ujung lagu sambil awal lagu berikut masuk (equal-power, tanpa jeda sunyi). Alih mode tidak pernah memotong lagu yang sedang berbunyi (ADR-002).'**
  String get playbackFootnote;

  /// No description provided for @setNormalization.
  ///
  /// In id, this message translates to:
  /// **'Normalisasi kenyaringan'**
  String get setNormalization;

  /// No description provided for @setNormalizationSub.
  ///
  /// In id, this message translates to:
  /// **'Samakan keras lagu dari pengukuran putar nyata.'**
  String get setNormalizationSub;

  /// No description provided for @normMicSnack.
  ///
  /// In id, this message translates to:
  /// **'Tanpa izin mikrofon, Visualizer Android tidak boleh mengukur — gain semua lagu tetap netral. Izinnya hanya untuk mengukur level, tidak merekam.'**
  String get normMicSnack;

  /// No description provided for @audioFootnote.
  ///
  /// In id, this message translates to:
  /// **'Keras lagu diukur dari pemutaran nyata (Visualizer), disimpan per lagu, dan dipakai mulai putaran berikutnya — lagu yang belum pernah terukur memakai gain netral.'**
  String get audioFootnote;

  /// No description provided for @setOfflineMode.
  ///
  /// In id, this message translates to:
  /// **'Mode offline'**
  String get setOfflineMode;

  /// No description provided for @setOfflineModeSub.
  ///
  /// In id, this message translates to:
  /// **'Hanya lagu terunduh & file lokal yang diputar.'**
  String get setOfflineModeSub;

  /// No description provided for @setManageDownloads.
  ///
  /// In id, this message translates to:
  /// **'Kelola unduhan'**
  String get setManageDownloads;

  /// No description provided for @setManageDownloadsSub.
  ///
  /// In id, this message translates to:
  /// **'Daftar, progres, putar, dan hapus lagu terunduh.'**
  String get setManageDownloadsSub;

  /// No description provided for @downloadsFootnote.
  ///
  /// In id, this message translates to:
  /// **'Menyalakan mode offline menyaring antrean berjalan tanpa memotong lagu yang sedang berbunyi; sambungan Putar Otomatis menjadi \"terbatas — offline\".'**
  String get downloadsFootnote;

  /// No description provided for @setDynamicAccent.
  ///
  /// In id, this message translates to:
  /// **'Aksen cover dinamis'**
  String get setDynamicAccent;

  /// No description provided for @setDynamicAccentSub.
  ///
  /// In id, this message translates to:
  /// **'Warna sampul mewarnai latar Player & kartu Beranda.'**
  String get setDynamicAccentSub;

  /// No description provided for @appearanceFootnote.
  ///
  /// In id, this message translates to:
  /// **'Nuansa diambil dari warna khas sampul yang sedang tampil dan tetap gelap; tombol putar & indikator status selalu Volt.'**
  String get appearanceFootnote;

  /// No description provided for @languageTitle.
  ///
  /// In id, this message translates to:
  /// **'Bahasa'**
  String get languageTitle;

  /// No description provided for @languageSub.
  ///
  /// In id, this message translates to:
  /// **'Bawaan sistem atau pilihan manual.'**
  String get languageSub;

  /// No description provided for @languageSystem.
  ///
  /// In id, this message translates to:
  /// **'Sistem'**
  String get languageSystem;

  /// No description provided for @captureLinkTitle.
  ///
  /// In id, this message translates to:
  /// **'Tangkap tautan/teks'**
  String get captureLinkTitle;

  /// No description provided for @captureLinkSub.
  ///
  /// In id, this message translates to:
  /// **'Tempel tautan playlist/lagu atau kata kunci.'**
  String get captureLinkSub;

  /// No description provided for @captureHint.
  ///
  /// In id, this message translates to:
  /// **'Tempel tautan atau ketik kata kunci…'**
  String get captureHint;

  /// No description provided for @captureAction.
  ///
  /// In id, this message translates to:
  /// **'Tangkap'**
  String get captureAction;

  /// No description provided for @searchCaptureTitle.
  ///
  /// In id, this message translates to:
  /// **'Tangkap daftar lagu'**
  String get searchCaptureTitle;

  /// No description provided for @searchCaptureSub.
  ///
  /// In id, this message translates to:
  /// **'Tempel tautan/teks (termasuk playlist Spotify) atau pilih gambar — lagunya dicocokkan untukmu.'**
  String get searchCaptureSub;

  /// No description provided for @capturePickImage.
  ///
  /// In id, this message translates to:
  /// **'Pilih gambar dari galeri'**
  String get capturePickImage;

  /// No description provided for @setBgStatus.
  ///
  /// In id, this message translates to:
  /// **'Status izin latar'**
  String get setBgStatus;

  /// No description provided for @bgStatusLine.
  ///
  /// In id, this message translates to:
  /// **'Notifikasi: {notif} · Baterai: {battery}'**
  String bgStatusLine(Object battery, Object notif);

  /// No description provided for @bgPermGranted.
  ///
  /// In id, this message translates to:
  /// **'Diizinkan'**
  String get bgPermGranted;

  /// No description provided for @bgPermNotYet.
  ///
  /// In id, this message translates to:
  /// **'Belum'**
  String get bgPermNotYet;

  /// No description provided for @bgBatteryExempt.
  ///
  /// In id, this message translates to:
  /// **'Diabaikan optimasi'**
  String get bgBatteryExempt;

  /// No description provided for @bgBatteryNotYet.
  ///
  /// In id, this message translates to:
  /// **'Belum diizinkan'**
  String get bgBatteryNotYet;

  /// No description provided for @setAllow.
  ///
  /// In id, this message translates to:
  /// **'Izinkan'**
  String get setAllow;

  /// No description provided for @setAllowSub.
  ///
  /// In id, this message translates to:
  /// **'Minta kedua izin lewat dialog sistem.'**
  String get setAllowSub;

  /// No description provided for @setXiaomi.
  ///
  /// In id, this message translates to:
  /// **'Khusus Xiaomi / HyperOS'**
  String get setXiaomi;

  /// No description provided for @setXiaomiSub.
  ///
  /// In id, this message translates to:
  /// **'Aktifkan \"Mulai otomatis\", baterai \"Tanpa batasan\".'**
  String get setXiaomiSub;

  /// No description provided for @setOtherBrands.
  ///
  /// In id, this message translates to:
  /// **'Merek lain'**
  String get setOtherBrands;

  /// No description provided for @setOtherBrandsSub.
  ///
  /// In id, this message translates to:
  /// **'Samsung: jangan masukkan Clai ke \"Aplikasi tidur\".'**
  String get setOtherBrandsSub;

  /// No description provided for @backgroundFootnote.
  ///
  /// In id, this message translates to:
  /// **'Bila putar latar masih dibunuh sistem walau sudah diizinkan di Xiaomi/HyperOS: buka Info aplikasi Clai, aktifkan \"Mulai otomatis\" dan setel Baterai ke \"Tanpa batasan\" — dua sakelar itu hanya ada di halaman sistem, Android tidak mengizinkan aplikasi mengubahnya untukmu. Oppo/Vivo: izinkan aktivitas latar di pengelola baterai merek.'**
  String get backgroundFootnote;

  /// No description provided for @setClearCache.
  ///
  /// In id, this message translates to:
  /// **'Hapus cache aliran'**
  String get setClearCache;

  /// No description provided for @setClearCacheSub.
  ///
  /// In id, this message translates to:
  /// **'URL aliran dibuang; diambil ulang saat diputar.'**
  String get setClearCacheSub;

  /// No description provided for @cacheClearedSnack.
  ///
  /// In id, this message translates to:
  /// **'Cache aliran dihapus.'**
  String get cacheClearedSnack;

  /// No description provided for @setClearHistory.
  ///
  /// In id, this message translates to:
  /// **'Hapus riwayat putar'**
  String get setClearHistory;

  /// No description provided for @setClearHistorySub.
  ///
  /// In id, this message translates to:
  /// **'Riwayat hanya hidup di perangkat ini dan milikmu.'**
  String get setClearHistorySub;

  /// No description provided for @historyClearedSnack.
  ///
  /// In id, this message translates to:
  /// **'Riwayat putar dihapus.'**
  String get historyClearedSnack;

  /// No description provided for @setDiagTitle.
  ///
  /// In id, this message translates to:
  /// **'Diagnostik Putar'**
  String get setDiagTitle;

  /// No description provided for @setDiagSub.
  ///
  /// In id, this message translates to:
  /// **'Uji rantai putar dan salin laporannya.'**
  String get setDiagSub;

  /// No description provided for @setLogTitle.
  ///
  /// In id, this message translates to:
  /// **'Log insiden (di perangkat)'**
  String get setLogTitle;

  /// No description provided for @setLogCount.
  ///
  /// In id, this message translates to:
  /// **'{count} catatan — tidak dikirim ke mana pun.'**
  String setLogCount(int count);

  /// No description provided for @aboutVersion.
  ///
  /// In id, this message translates to:
  /// **'Clai 1.0.1'**
  String get aboutVersion;

  /// No description provided for @aboutBody.
  ///
  /// In id, this message translates to:
  /// **'Pemutar musik sumber terbuka (GPL-3.0) yang dibangun clean-room: tanpa kode atau aset dari layanan lain. Katalog dan lagu berasal dari layanan musik pihak ketiga lewat API tidak resmi — dinyatakan terbuka di README repo; arsitektur provider memungkinkan sumber lain ditambahkan tanpa menyentuh player. Kamu juga bisa menempel tautan playlist publik dari aplikasi musik lain: daftar lagunya dibaca, lalu dicocokkan ke katalog di sini — tanpa akun. Lirik dari LRCLIB; pengayaan sampul dari MusicBrainz/Cover Art Archive; scrobble opsional ke ListenBrainz dengan token milikmu sendiri. Semua data pribadimu — koleksi, riwayat, unduhan — hanya tersimpan di HP-mu.'**
  String get aboutBody;

  /// No description provided for @logTitle.
  ///
  /// In id, this message translates to:
  /// **'Log insiden'**
  String get logTitle;

  /// No description provided for @logEmpty.
  ///
  /// In id, this message translates to:
  /// **'Belum ada insiden tercatat.'**
  String get logEmpty;

  /// No description provided for @groupListenBrainz.
  ///
  /// In id, this message translates to:
  /// **'ListenBrainz'**
  String get groupListenBrainz;

  /// No description provided for @drvMode.
  ///
  /// In id, this message translates to:
  /// **'Mode Berkendara'**
  String get drvMode;

  /// No description provided for @drvModeSub.
  ///
  /// In id, this message translates to:
  /// **'Permukaan sentuh raksasa + kendali audio. Menyalakan membuka layarnya.'**
  String get drvModeSub;

  /// No description provided for @drvScheme.
  ///
  /// In id, this message translates to:
  /// **'Skema kendali'**
  String get drvScheme;

  /// No description provided for @drvSchemeSub.
  ///
  /// In id, this message translates to:
  /// **'Tombol media standar (bawaan) / pola tekan satu tombol (1× putar-jeda, 2× berikutnya, 3× sebelumnya) / perintah suara.'**
  String get drvSchemeSub;

  /// No description provided for @drvSchemeButtons.
  ///
  /// In id, this message translates to:
  /// **'Tombol media'**
  String get drvSchemeButtons;

  /// No description provided for @drvSchemePatterns.
  ///
  /// In id, this message translates to:
  /// **'Pola tekan'**
  String get drvSchemePatterns;

  /// No description provided for @drvSchemeVoice.
  ///
  /// In id, this message translates to:
  /// **'Perintah suara'**
  String get drvSchemeVoice;

  /// No description provided for @drvAnnounce.
  ///
  /// In id, this message translates to:
  /// **'Pengumuman suara'**
  String get drvAnnounce;

  /// No description provided for @drvAnnounceSub.
  ///
  /// In id, this message translates to:
  /// **'Judul lagu berikutnya dibacakan TTS sebelum diputar (bawaan mati).'**
  String get drvAnnounceSub;

  /// No description provided for @drvSpeedVolume.
  ///
  /// In id, this message translates to:
  /// **'Volume ikut kecepatan'**
  String get drvSpeedVolume;

  /// No description provided for @drvSpeedVolumeSub.
  ///
  /// In id, this message translates to:
  /// **'Perlu izin lokasi. Volume hanya bergerak di antara dua titik di bawah; GPS buruk = volume membeku.'**
  String get drvSpeedVolumeSub;

  /// No description provided for @drvVolStop.
  ///
  /// In id, this message translates to:
  /// **'Volume saat berhenti'**
  String get drvVolStop;

  /// No description provided for @drvVolFast.
  ///
  /// In id, this message translates to:
  /// **'Volume tercepat'**
  String get drvVolFast;

  /// No description provided for @drvVolFastSub.
  ///
  /// In id, this message translates to:
  /// **'{pct}% — plafon, tidak pernah dilampaui.'**
  String drvVolFastSub(int pct);

  /// No description provided for @drvVolPct.
  ///
  /// In id, this message translates to:
  /// **'{pct}%'**
  String drvVolPct(int pct);

  /// No description provided for @drvAnchor.
  ///
  /// In id, this message translates to:
  /// **'Kecepatan jangkar'**
  String get drvAnchor;

  /// No description provided for @drvAnchorSub.
  ///
  /// In id, this message translates to:
  /// **'{kmh} km/jam — pada kecepatan ini volume mencapai titik tercepat.'**
  String drvAnchorSub(int kmh);

  /// No description provided for @drvVehicles.
  ///
  /// In id, this message translates to:
  /// **'Perangkat kendaraan (Bluetooth)'**
  String get drvVehicles;

  /// No description provided for @drvVehiclesHint.
  ///
  /// In id, this message translates to:
  /// **'Ketuk untuk memuat perangkat terpasang — yang ditandai memicu Mode Berkendara otomatis saat tersambung.'**
  String get drvVehiclesHint;

  /// No description provided for @drvVehiclesNone.
  ///
  /// In id, this message translates to:
  /// **'Tidak ada perangkat Bluetooth terpasang di perangkat ini.'**
  String get drvVehiclesNone;

  /// No description provided for @drvVehiclesCount.
  ///
  /// In id, this message translates to:
  /// **'{count} perangkat terpasang.'**
  String drvVehiclesCount(int count);

  /// No description provided for @drvMarkVehicle.
  ///
  /// In id, this message translates to:
  /// **'Tandai sebagai kendaraan'**
  String get drvMarkVehicle;

  /// No description provided for @lbTitle.
  ///
  /// In id, this message translates to:
  /// **'Kirim riwayat dengar ke ListenBrainz'**
  String get lbTitle;

  /// No description provided for @lbSub.
  ///
  /// In id, this message translates to:
  /// **'Opsional dan mati secara default. Yang dikirim: judul, artis, album, dan waktu dengar — ke akun ListenBrainz milikmu sendiri.'**
  String get lbSub;

  /// No description provided for @lbTokenLabel.
  ///
  /// In id, this message translates to:
  /// **'Token pengguna ListenBrainz'**
  String get lbTokenLabel;

  /// No description provided for @lbTokenHint.
  ///
  /// In id, this message translates to:
  /// **'Dari listenbrainz.org → Settings → User Token'**
  String get lbTokenHint;

  /// No description provided for @lbTokenValid.
  ///
  /// In id, this message translates to:
  /// **'Token valid — tersimpan.'**
  String get lbTokenValid;

  /// No description provided for @lbTokenInvalid.
  ///
  /// In id, this message translates to:
  /// **'Token tidak valid atau jaringan bermasalah.'**
  String get lbTokenInvalid;

  /// No description provided for @lbSaveCheck.
  ///
  /// In id, this message translates to:
  /// **'Simpan & periksa token'**
  String get lbSaveCheck;

  /// No description provided for @lbSafeTitle.
  ///
  /// In id, this message translates to:
  /// **'Kegagalan kirim tidak mengganggu putar'**
  String get lbSafeTitle;

  /// No description provided for @lbSafeSub.
  ///
  /// In id, this message translates to:
  /// **'Scrobble dikirim di latar sesudah lagu selesai didengar (≥30 detik). Token hanya tersimpan di perangkat ini.'**
  String get lbSafeSub;

  /// No description provided for @greetMorning.
  ///
  /// In id, this message translates to:
  /// **'Selamat pagi'**
  String get greetMorning;

  /// No description provided for @greetAfternoon.
  ///
  /// In id, this message translates to:
  /// **'Selamat siang'**
  String get greetAfternoon;

  /// No description provided for @greetEvening.
  ///
  /// In id, this message translates to:
  /// **'Selamat sore'**
  String get greetEvening;

  /// No description provided for @greetNight.
  ///
  /// In id, this message translates to:
  /// **'Selamat malam'**
  String get greetNight;

  /// No description provided for @homeBgCardTitle.
  ///
  /// In id, this message translates to:
  /// **'Agar musik tidak dibunuh sistem'**
  String get homeBgCardTitle;

  /// No description provided for @homeBgCardSub.
  ///
  /// In id, this message translates to:
  /// **'Izin jalan di latar belum lengkap. Tanpa itu, sebagian ponsel menghentikan putar saat layar mati.'**
  String get homeBgCardSub;

  /// No description provided for @homeSetupNow.
  ///
  /// In id, this message translates to:
  /// **'Atur sekarang'**
  String get homeSetupNow;

  /// No description provided for @homeEmptyTitle.
  ///
  /// In id, this message translates to:
  /// **'Mau dengar apa hari ini?'**
  String get homeEmptyTitle;

  /// No description provided for @homeEmptySub.
  ///
  /// In id, this message translates to:
  /// **'Cari lagu pertamamu — sesudahnya biar Putar Otomatis yang menyambung.'**
  String get homeEmptySub;

  /// No description provided for @homeSearchSong.
  ///
  /// In id, this message translates to:
  /// **'Cari lagu'**
  String get homeSearchSong;

  /// No description provided for @homeUpNext.
  ///
  /// In id, this message translates to:
  /// **'Antrian Berikutnya'**
  String get homeUpNext;

  /// No description provided for @homeOpenQueue.
  ///
  /// In id, this message translates to:
  /// **'Buka Antrian'**
  String get homeOpenQueue;

  /// No description provided for @homeRecent.
  ///
  /// In id, this message translates to:
  /// **'Terakhir Diputar'**
  String get homeRecent;

  /// No description provided for @homePlayAgain.
  ///
  /// In id, this message translates to:
  /// **'Putar Lagi'**
  String get homePlayAgain;

  /// No description provided for @homeYourCollection.
  ///
  /// In id, this message translates to:
  /// **'Koleksi Kamu'**
  String get homeYourCollection;

  /// No description provided for @homeSavedSongs.
  ///
  /// In id, this message translates to:
  /// **'Lagu Tersimpan'**
  String get homeSavedSongs;

  /// No description provided for @songCount.
  ///
  /// In id, this message translates to:
  /// **'{count} lagu'**
  String songCount(int count);

  /// No description provided for @shelfBecauseArtist.
  ///
  /// In id, this message translates to:
  /// **'Karena kamu sering memutar {artist}'**
  String shelfBecauseArtist(Object artist);

  /// No description provided for @shelfRarelyPlayed.
  ///
  /// In id, this message translates to:
  /// **'Tersimpan tapi jarang diputar'**
  String get shelfRarelyPlayed;

  /// No description provided for @jelajahTitle.
  ///
  /// In id, this message translates to:
  /// **'Jelajah'**
  String get jelajahTitle;

  /// No description provided for @jelajahYtmHome.
  ///
  /// In id, this message translates to:
  /// **'Beranda'**
  String get jelajahYtmHome;

  /// No description provided for @jelajahCharts.
  ///
  /// In id, this message translates to:
  /// **'Tangga Lagu'**
  String get jelajahCharts;

  /// No description provided for @jelajahArtists.
  ///
  /// In id, this message translates to:
  /// **'Artis'**
  String get jelajahArtists;

  /// No description provided for @jelajahLoadFail.
  ///
  /// In id, this message translates to:
  /// **'Jelajah tidak dapat dimuat saat ini.'**
  String get jelajahLoadFail;

  /// No description provided for @jelajahShelfFail.
  ///
  /// In id, this message translates to:
  /// **'Rak {source} gagal dimuat.'**
  String jelajahShelfFail(Object source);

  /// No description provided for @jelajahLoading.
  ///
  /// In id, this message translates to:
  /// **'Memuat rak penemuan…'**
  String get jelajahLoading;

  /// No description provided for @jelajahShelfTitle.
  ///
  /// In id, this message translates to:
  /// **'Jelajah • {title}'**
  String jelajahShelfTitle(Object title);

  /// No description provided for @sleepCardTitle.
  ///
  /// In id, this message translates to:
  /// **'Lanjutkan dari semalam'**
  String get sleepCardTitle;

  /// No description provided for @sleepCardSub.
  ///
  /// In id, this message translates to:
  /// **'{title} — {artist} · dari {pos}'**
  String sleepCardSub(Object artist, Object pos, Object title);

  /// No description provided for @sleepCardResume.
  ///
  /// In id, this message translates to:
  /// **'Lanjutkan'**
  String get sleepCardResume;

  /// No description provided for @sleepContextLabel.
  ///
  /// In id, this message translates to:
  /// **'Lanjut Besok'**
  String get sleepContextLabel;

  /// No description provided for @playerNowPlaying.
  ///
  /// In id, this message translates to:
  /// **'Sedang Diputar'**
  String get playerNowPlaying;

  /// No description provided for @playerEmpty.
  ///
  /// In id, this message translates to:
  /// **'Belum ada lagu yang diputar.'**
  String get playerEmpty;

  /// No description provided for @playerBuffering.
  ///
  /// In id, this message translates to:
  /// **'Buffering…'**
  String get playerBuffering;

  /// No description provided for @commonLoading.
  ///
  /// In id, this message translates to:
  /// **'Memuat…'**
  String get commonLoading;

  /// No description provided for @playerLyrics.
  ///
  /// In id, this message translates to:
  /// **'Lirik'**
  String get playerLyrics;

  /// No description provided for @queueTitle.
  ///
  /// In id, this message translates to:
  /// **'Antrian'**
  String get queueTitle;

  /// No description provided for @playerTimer.
  ///
  /// In id, this message translates to:
  /// **'Timer'**
  String get playerTimer;

  /// No description provided for @playerVoice.
  ///
  /// In id, this message translates to:
  /// **'Suara'**
  String get playerVoice;

  /// No description provided for @playerAutoplayCard.
  ///
  /// In id, this message translates to:
  /// **'Putar Otomatis aktif — setelah konteks ini habis, Clai menyambung lagu terkait. Musik tidak berhenti di tengah jalan.'**
  String get playerAutoplayCard;

  /// No description provided for @queueSmartShuffleNote.
  ///
  /// In id, this message translates to:
  /// **'Acak Cerdas — mengurut ulang Lanjutan (artis disebar, favorit didorong). Tidak menambah lagu baru.'**
  String get queueSmartShuffleNote;

  /// No description provided for @queueEmpty.
  ///
  /// In id, this message translates to:
  /// **'Antrean kosong. Putar sebuah lagu untuk memulai.'**
  String get queueEmpty;

  /// No description provided for @queueNowPlaying.
  ///
  /// In id, this message translates to:
  /// **'Sedang Diputar'**
  String get queueNowPlaying;

  /// No description provided for @queueUpNext.
  ///
  /// In id, this message translates to:
  /// **'Berikutnya'**
  String get queueUpNext;

  /// No description provided for @queueContinuation.
  ///
  /// In id, this message translates to:
  /// **'Lanjutan — {label}'**
  String queueContinuation(Object label);

  /// No description provided for @queueContextFallback.
  ///
  /// In id, this message translates to:
  /// **'konteks'**
  String get queueContextFallback;

  /// No description provided for @queueCountLine.
  ///
  /// In id, this message translates to:
  /// **'{count} trek'**
  String queueCountLine(int count);

  /// No description provided for @queueCountLineDur.
  ///
  /// In id, this message translates to:
  /// **'{count} trek · {duration}{totalPart}'**
  String queueCountLineDur(int count, Object duration, Object totalPart);

  /// No description provided for @queueTotalPart.
  ///
  /// In id, this message translates to:
  /// **'{plus} total'**
  String queueTotalPart(Object plus);

  /// No description provided for @queueRemovedSnack.
  ///
  /// In id, this message translates to:
  /// **'Dihapus: {title}'**
  String queueRemovedSnack(Object title);

  /// No description provided for @commonUndo.
  ///
  /// In id, this message translates to:
  /// **'Urungkan'**
  String get commonUndo;

  /// No description provided for @queueClear.
  ///
  /// In id, this message translates to:
  /// **'Kosongkan antrean'**
  String get queueClear;

  /// No description provided for @queueFilterHint.
  ///
  /// In id, this message translates to:
  /// **'Saring antrean ini…'**
  String get queueFilterHint;

  /// No description provided for @queueAutoplayOff.
  ///
  /// In id, this message translates to:
  /// **'Putar Otomatis mati di Pengaturan — konteks habis berarti berhenti.'**
  String get queueAutoplayOff;

  /// No description provided for @queueAutoplayHeader.
  ///
  /// In id, this message translates to:
  /// **'Putar Otomatis — karena kamu memutar {seed}'**
  String queueAutoplayHeader(Object seed);

  /// No description provided for @queueAutoplayLimited.
  ///
  /// In id, this message translates to:
  /// **'terbatas — offline: sambungan hanya dari lagu yang sudah kamu unduh.'**
  String get queueAutoplayLimited;

  /// No description provided for @queuePreparing.
  ///
  /// In id, this message translates to:
  /// **'Menyiapkan sambungan dari lagu-lagu benih sesi ini…'**
  String get queuePreparing;

  /// No description provided for @queueContinuationReady.
  ///
  /// In id, this message translates to:
  /// **'Sambungan disiapkan dari lagu-lagu benih sesi ini.'**
  String get queueContinuationReady;

  /// No description provided for @queueContinuationPending.
  ///
  /// In id, this message translates to:
  /// **'Sambungan belum tersedia (jaringan lambat?). Musik tetap menyambung begitu sambungan siap.'**
  String get queueContinuationPending;

  /// No description provided for @queueAutoBadge.
  ///
  /// In id, this message translates to:
  /// **'AUTO'**
  String get queueAutoBadge;

  /// No description provided for @ctxPlayNext.
  ///
  /// In id, this message translates to:
  /// **'Putar Berikutnya'**
  String get ctxPlayNext;

  /// No description provided for @ctxAddToQueue.
  ///
  /// In id, this message translates to:
  /// **'Tambah ke Antrian'**
  String get ctxAddToQueue;

  /// No description provided for @ctxStartRadio.
  ///
  /// In id, this message translates to:
  /// **'Mulai Radio Lagu'**
  String get ctxStartRadio;

  /// No description provided for @ctxRemoveFromCollection.
  ///
  /// In id, this message translates to:
  /// **'Hapus dari Koleksi'**
  String get ctxRemoveFromCollection;

  /// No description provided for @ctxSaveToCollection.
  ///
  /// In id, this message translates to:
  /// **'Simpan ke Koleksi'**
  String get ctxSaveToCollection;

  /// No description provided for @ctxAddToPlaylist.
  ///
  /// In id, this message translates to:
  /// **'Tambah ke Playlist'**
  String get ctxAddToPlaylist;

  /// No description provided for @ctxDeleteDownload.
  ///
  /// In id, this message translates to:
  /// **'Hapus unduhan'**
  String get ctxDeleteDownload;

  /// No description provided for @ctxOpenAlbum.
  ///
  /// In id, this message translates to:
  /// **'Buka Album'**
  String get ctxOpenAlbum;

  /// No description provided for @ctxOpenArtist.
  ///
  /// In id, this message translates to:
  /// **'Buka Artis'**
  String get ctxOpenArtist;

  /// No description provided for @ctxShare.
  ///
  /// In id, this message translates to:
  /// **'Bagikan'**
  String get ctxShare;

  /// No description provided for @ctxShareCredit.
  ///
  /// In id, this message translates to:
  /// **'Dibagikan lewat Clai — unduh aplikasinya: {url}'**
  String ctxShareCredit(Object url);

  /// No description provided for @radioPageTitle.
  ///
  /// In id, this message translates to:
  /// **'Radio — {title}'**
  String radioPageTitle(Object title);

  /// No description provided for @radioGeneratedFrom.
  ///
  /// In id, this message translates to:
  /// **'Bangkitan radio dari lagu ini'**
  String get radioGeneratedFrom;

  /// No description provided for @radioEmpty.
  ///
  /// In id, this message translates to:
  /// **'Belum ada lagu radio yang dapat dibuat dari lagu ini.'**
  String get radioEmpty;

  /// No description provided for @radioLoadFailed.
  ///
  /// In id, this message translates to:
  /// **'Tidak dapat memuat radio lagu ini. Periksa koneksimu lalu coba lagi.'**
  String get radioLoadFailed;

  /// No description provided for @ctxRemoveFromQueue.
  ///
  /// In id, this message translates to:
  /// **'Hapus dari Antrian'**
  String get ctxRemoveFromQueue;

  /// No description provided for @queueSelect.
  ///
  /// In id, this message translates to:
  /// **'Pilih'**
  String get queueSelect;

  /// No description provided for @queueSelectedCount.
  ///
  /// In id, this message translates to:
  /// **'{count} dipilih'**
  String queueSelectedCount(Object count);

  /// No description provided for @queueBulkRemove.
  ///
  /// In id, this message translates to:
  /// **'Hapus'**
  String get queueBulkRemove;

  /// No description provided for @queueBulkPlaylist.
  ///
  /// In id, this message translates to:
  /// **'Ke Playlist'**
  String get queueBulkPlaylist;

  /// No description provided for @queueBulkSave.
  ///
  /// In id, this message translates to:
  /// **'Simpan'**
  String get queueBulkSave;

  /// No description provided for @queueSelectAll.
  ///
  /// In id, this message translates to:
  /// **'Pilih Semua'**
  String get queueSelectAll;

  /// No description provided for @queueUnselectAll.
  ///
  /// In id, this message translates to:
  /// **'Batalkan Semua'**
  String get queueUnselectAll;

  /// No description provided for @bulkQueueAdded.
  ///
  /// In id, this message translates to:
  /// **'{count} lagu ditambahkan ke Antrian.'**
  String bulkQueueAdded(Object count);

  /// No description provided for @bulkSaved.
  ///
  /// In id, this message translates to:
  /// **'{count} lagu disimpan ke Koleksi.'**
  String bulkSaved(Object count);

  /// No description provided for @bulkSavedNone.
  ///
  /// In id, this message translates to:
  /// **'Semua lagu ini sudah ada di Koleksi.'**
  String get bulkSavedNone;

  /// No description provided for @bulkPlaylistAdded.
  ///
  /// In id, this message translates to:
  /// **'{count} lagu ditambahkan ke playlist.'**
  String bulkPlaylistAdded(Object count);

  /// No description provided for @bulkPlaylistNone.
  ///
  /// In id, this message translates to:
  /// **'Semua lagu ini sudah ada di playlist itu.'**
  String get bulkPlaylistNone;

  /// No description provided for @bulkRemovedFromQueue.
  ///
  /// In id, this message translates to:
  /// **'{count} lagu dihapus dari Antrian.'**
  String bulkRemovedFromQueue(Object count);

  /// No description provided for @ctxNewPlaylist.
  ///
  /// In id, this message translates to:
  /// **'Playlist baru'**
  String get ctxNewPlaylist;

  /// No description provided for @ctxPlaylistName.
  ///
  /// In id, this message translates to:
  /// **'Nama playlist'**
  String get ctxPlaylistName;

  /// No description provided for @ctxAlreadyInPlaylist.
  ///
  /// In id, this message translates to:
  /// **'Sudah ada di playlist'**
  String get ctxAlreadyInPlaylist;

  /// No description provided for @ctxAlreadyInPlaylistBody.
  ///
  /// In id, this message translates to:
  /// **'Lagu ini sudah ada di playlist itu. Tetap tambahkan sebagai duplikat?'**
  String get ctxAlreadyInPlaylistBody;

  /// No description provided for @ctxSkip.
  ///
  /// In id, this message translates to:
  /// **'Lewati'**
  String get ctxSkip;

  /// No description provided for @ctxAddAnyway.
  ///
  /// In id, this message translates to:
  /// **'Tetap tambahkan'**
  String get ctxAddAnyway;

  /// No description provided for @commonSave.
  ///
  /// In id, this message translates to:
  /// **'Simpan'**
  String get commonSave;

  /// No description provided for @searchHint.
  ///
  /// In id, this message translates to:
  /// **'Cari lagu, album, artis…'**
  String get searchHint;

  /// No description provided for @searchSpotifyOnlySnack.
  ///
  /// In id, this message translates to:
  /// **'Baru tautan PLAYLIST Spotify yang didukung — tempel tautan playlist publiknya.'**
  String get searchSpotifyOnlySnack;

  /// No description provided for @searchSourceBroken.
  ///
  /// In id, this message translates to:
  /// **'Sumber sedang bermasalah — bentuk datanya berubah. Ini bukan salah koneksimu.'**
  String get searchSourceBroken;

  /// No description provided for @searchNetworkError.
  ///
  /// In id, this message translates to:
  /// **'Tidak dapat menjangkau sumber. Periksa koneksimu.'**
  String get searchNetworkError;

  /// No description provided for @searchSpotifyCardTitle.
  ///
  /// In id, this message translates to:
  /// **'Buka playlist Spotify'**
  String get searchSpotifyCardTitle;

  /// No description provided for @searchSpotifyCardSub.
  ///
  /// In id, this message translates to:
  /// **'Tempel tautan playlist publik Spotify di bidang cari di atas — tanpa akun, lagu dicocokkan ke katalog.'**
  String get searchSpotifyCardSub;

  /// No description provided for @searchEmpty.
  ///
  /// In id, this message translates to:
  /// **'Ketik untuk mencari di katalog.\nHasil muncul sambil kamu mengetik.'**
  String get searchEmpty;

  /// No description provided for @searchRecent.
  ///
  /// In id, this message translates to:
  /// **'Terakhir dicari'**
  String get searchRecent;

  /// No description provided for @searchClearAll.
  ///
  /// In id, this message translates to:
  /// **'Hapus semua'**
  String get searchClearAll;

  /// No description provided for @searchClearQuery.
  ///
  /// In id, this message translates to:
  /// **'Hapus kata kunci'**
  String get searchClearQuery;

  /// No description provided for @searchNoResults.
  ///
  /// In id, this message translates to:
  /// **'Tidak ditemukan. Coba kata kunci lain — ini bukan gagal jaringan, memang tidak ada hasilnya.'**
  String get searchNoResults;

  /// No description provided for @searchResultsLabel.
  ///
  /// In id, this message translates to:
  /// **'Hasil cari'**
  String get searchResultsLabel;

  /// No description provided for @searchSongs.
  ///
  /// In id, this message translates to:
  /// **'Lagu'**
  String get searchSongs;

  /// No description provided for @searchAlbums.
  ///
  /// In id, this message translates to:
  /// **'Album'**
  String get searchAlbums;

  /// No description provided for @searchArtists.
  ///
  /// In id, this message translates to:
  /// **'Artis'**
  String get searchArtists;

  /// No description provided for @searchPlaylists.
  ///
  /// In id, this message translates to:
  /// **'Playlist'**
  String get searchPlaylists;

  /// No description provided for @searchAll.
  ///
  /// In id, this message translates to:
  /// **'Semua'**
  String get searchAll;

  /// No description provided for @collectionTitle.
  ///
  /// In id, this message translates to:
  /// **'Koleksi'**
  String get collectionTitle;

  /// No description provided for @collectionSortRecent.
  ///
  /// In id, this message translates to:
  /// **'Terbaru disimpan'**
  String get collectionSortRecent;

  /// No description provided for @collectionFilterHint.
  ///
  /// In id, this message translates to:
  /// **'Saring koleksimu…'**
  String get collectionFilterHint;

  /// No description provided for @collectionPlaylists.
  ///
  /// In id, this message translates to:
  /// **'Playlist'**
  String get collectionPlaylists;

  /// No description provided for @collectionDownloads.
  ///
  /// In id, this message translates to:
  /// **'Unduhan'**
  String get collectionDownloads;

  /// No description provided for @collectionLocalFiles.
  ///
  /// In id, this message translates to:
  /// **'File Lokal'**
  String get collectionLocalFiles;

  /// No description provided for @collectionSavedCount.
  ///
  /// In id, this message translates to:
  /// **'{count} lagu tersimpan'**
  String collectionSavedCount(int count);

  /// No description provided for @collectionEmptyPlaylists.
  ///
  /// In id, this message translates to:
  /// **'Belum ada playlist. Buat satu dengan tombol + di bawah.'**
  String get collectionEmptyPlaylists;

  /// No description provided for @collectionGoSearch.
  ///
  /// In id, this message translates to:
  /// **'Cari lagu'**
  String get collectionGoSearch;

  /// No description provided for @collectionEmptySaved.
  ///
  /// In id, this message translates to:
  /// **'Belum ada lagu tersimpan. Ketuk hati pada lagu mana pun — dari baris lagu atau Player.'**
  String get collectionEmptySaved;

  /// No description provided for @collectionNewPlaylistName.
  ///
  /// In id, this message translates to:
  /// **'Nama playlist baru'**
  String get collectionNewPlaylistName;

  /// No description provided for @contentUnavailable.
  ///
  /// In id, this message translates to:
  /// **'Konten tidak tersedia.'**
  String get contentUnavailable;

  /// No description provided for @contentLoadFail.
  ///
  /// In id, this message translates to:
  /// **'Tidak dapat memuat halaman ini dari sumber.'**
  String get contentLoadFail;

  /// No description provided for @contentShuffle.
  ///
  /// In id, this message translates to:
  /// **'Acak'**
  String get contentShuffle;

  /// No description provided for @contentShuffleContext.
  ///
  /// In id, this message translates to:
  /// **'{title} (acak)'**
  String contentShuffleContext(Object title);

  /// No description provided for @contentPopular.
  ///
  /// In id, this message translates to:
  /// **'Lagu populer'**
  String get contentPopular;

  /// No description provided for @contentDiscography.
  ///
  /// In id, this message translates to:
  /// **'Diskografi'**
  String get contentDiscography;

  /// No description provided for @contentSimilar.
  ///
  /// In id, this message translates to:
  /// **'Artis serupa'**
  String get contentSimilar;

  /// No description provided for @contentCountLine.
  ///
  /// In id, this message translates to:
  /// **'{count} lagu · {duration}'**
  String contentCountLine(int count, Object duration);

  /// No description provided for @plRemovedSnack.
  ///
  /// In id, this message translates to:
  /// **'Dihapus dari playlist: {title}'**
  String plRemovedSnack(Object title);

  /// No description provided for @plRename.
  ///
  /// In id, this message translates to:
  /// **'Ganti nama'**
  String get plRename;

  /// No description provided for @plNewName.
  ///
  /// In id, this message translates to:
  /// **'Nama baru'**
  String get plNewName;

  /// No description provided for @plDelete.
  ///
  /// In id, this message translates to:
  /// **'Hapus playlist'**
  String get plDelete;

  /// No description provided for @plDeleteTitle.
  ///
  /// In id, this message translates to:
  /// **'Hapus playlist?'**
  String get plDeleteTitle;

  /// No description provided for @plDeleteBody.
  ///
  /// In id, this message translates to:
  /// **'Playlist dihapus permanen dari perangkat ini. Lagu-lagunya sendiri tidak ikut terhapus.'**
  String get plDeleteBody;

  /// No description provided for @plEmpty.
  ///
  /// In id, this message translates to:
  /// **'Playlist ini masih kosong. Tambahkan lagu dari menu konteks lagu mana pun.'**
  String get plEmpty;

  /// No description provided for @spTitle.
  ///
  /// In id, this message translates to:
  /// **'Playlist Spotify'**
  String get spTitle;

  /// No description provided for @spUnavailable.
  ///
  /// In id, this message translates to:
  /// **'Playlist tidak tersedia.'**
  String get spUnavailable;

  /// No description provided for @spLoadFail.
  ///
  /// In id, this message translates to:
  /// **'Tidak dapat memuat playlist Spotify. Periksa koneksimu.'**
  String get spLoadFail;

  /// No description provided for @spMeta.
  ///
  /// In id, this message translates to:
  /// **'Metadata: Spotify (tanpa akun) • Audio: hasil pencocokan katalog'**
  String get spMeta;

  /// No description provided for @spPlayMatched.
  ///
  /// In id, this message translates to:
  /// **'Putar yang cocok'**
  String get spPlayMatched;

  /// No description provided for @spMatching.
  ///
  /// In id, this message translates to:
  /// **'Mencocokkan… {matched} dari {total} lagu'**
  String spMatching(int matched, int total);

  /// No description provided for @spMatched.
  ///
  /// In id, this message translates to:
  /// **'{matched} dari {total} lagu tercocokkan'**
  String spMatched(int matched, int total);

  /// No description provided for @spNoneMatched.
  ///
  /// In id, this message translates to:
  /// **'Belum ada lagu yang tercocokkan.'**
  String get spNoneMatched;

  /// No description provided for @spSkippedItems.
  ///
  /// In id, this message translates to:
  /// **'{count} item non-lagu (mis. episode) dilewati.'**
  String spSkippedItems(int count);

  /// No description provided for @spHuge.
  ///
  /// In id, this message translates to:
  /// **'Playlist sangat besar — ditampilkan 1000 lagu pertama.'**
  String get spHuge;

  /// No description provided for @spContext.
  ///
  /// In id, this message translates to:
  /// **'Spotify • {name}'**
  String spContext(Object name);

  /// No description provided for @spOwnerLine.
  ///
  /// In id, this message translates to:
  /// **'{owner} • {count} lagu'**
  String spOwnerLine(int count, Object owner);

  /// No description provided for @spNotFound.
  ///
  /// In id, this message translates to:
  /// **'Lagu ini tidak ditemukan di katalog.'**
  String get spNotFound;

  /// No description provided for @spNotFoundRetry.
  ///
  /// In id, this message translates to:
  /// **'Lagu ini tidak ditemukan di katalog — ketuk label \"Tak cocok\" untuk mencoba lagi.'**
  String get spNotFoundRetry;

  /// No description provided for @spMatchingThis.
  ///
  /// In id, this message translates to:
  /// **'Sedang mencocokkan lagu ini…'**
  String get spMatchingThis;

  /// No description provided for @spNoMatch.
  ///
  /// In id, this message translates to:
  /// **'Tak cocok'**
  String get spNoMatch;

  /// No description provided for @spPlayWhileMatching.
  ///
  /// In id, this message translates to:
  /// **'Pencocokan sedang berjalan — putar lagi sesaat.'**
  String get spPlayWhileMatching;

  /// No description provided for @localTitle.
  ///
  /// In id, this message translates to:
  /// **'File Lokal'**
  String get localTitle;

  /// No description provided for @localScan.
  ///
  /// In id, this message translates to:
  /// **'Pindai file lokal'**
  String get localScan;

  /// No description provided for @localRescan.
  ///
  /// In id, this message translates to:
  /// **'Pindai ulang'**
  String get localRescan;

  /// No description provided for @localSub.
  ///
  /// In id, this message translates to:
  /// **'Pindai folder musik perangkatmu. File lokal setara dengan lagu streaming di antrean & playlist.'**
  String get localSub;

  /// No description provided for @localDenied.
  ///
  /// In id, this message translates to:
  /// **'Izin audio ditolak. File lokal tidak dapat dipindai tanpa izin itu.'**
  String get localDenied;

  /// No description provided for @localNone.
  ///
  /// In id, this message translates to:
  /// **'Tidak ada berkas audio ≥ 30 detik ditemukan di perangkat.'**
  String get localNone;

  /// No description provided for @localCount.
  ///
  /// In id, this message translates to:
  /// **'{count} berkas audio di perangkat'**
  String localCount(int count);

  /// No description provided for @dlTitle.
  ///
  /// In id, this message translates to:
  /// **'Unduhan'**
  String get dlTitle;

  /// No description provided for @dlEmpty.
  ///
  /// In id, this message translates to:
  /// **'Belum ada unduhan. Unduh lagu dari menu ⋯ di baris lagu mana pun — lagu terunduh bisa diputar tanpa jaringan.'**
  String get dlEmpty;

  /// No description provided for @dlFailed.
  ///
  /// In id, this message translates to:
  /// **'Unduhan gagal.'**
  String get dlFailed;

  /// No description provided for @dlRetry.
  ///
  /// In id, this message translates to:
  /// **'Ulangi'**
  String get dlRetry;

  /// No description provided for @dlProgressOf.
  ///
  /// In id, this message translates to:
  /// **'{done} / {tot}'**
  String dlProgressOf(Object done, Object tot);

  /// No description provided for @dlProgressDone.
  ///
  /// In id, this message translates to:
  /// **'{done} diunduh…'**
  String dlProgressDone(Object done);

  /// No description provided for @dlFootnote.
  ///
  /// In id, this message translates to:
  /// **'Berkas tinggal di penyimpanan privat aplikasi. Unduhan bisa dijeda dan dilanjutkan dari byte terakhir; pembatalan penuh menghapus berkas sebagian.'**
  String get dlFootnote;

  /// No description provided for @capGateTitle.
  ///
  /// In id, this message translates to:
  /// **'Model pembaca teks belum diunduh'**
  String get capGateTitle;

  /// No description provided for @capGateBody.
  ///
  /// In id, this message translates to:
  /// **'Tangkap dari gambar membaca daftar lagu dari tangkapan layar atau foto. Model pembacanya (±4 MB) sengaja tidak ikut di dalam APK agar aplikasi tetap ramping — unduh sekali dari GitHub Releases, sesudah itu membaca gambar bekerja offline penuh. Tangkap lewat tautan tidak membutuhkannya sama sekali.'**
  String get capGateBody;

  /// No description provided for @capVerifying.
  ///
  /// In id, this message translates to:
  /// **'Memeriksa keutuhan berkas…'**
  String get capVerifying;

  /// No description provided for @capDownloadModel.
  ///
  /// In id, this message translates to:
  /// **'Unduh model'**
  String get capDownloadModel;

  /// No description provided for @capRetryDownload.
  ///
  /// In id, this message translates to:
  /// **'Coba unduh lagi'**
  String get capRetryDownload;

  /// No description provided for @capTitle.
  ///
  /// In id, this message translates to:
  /// **'Tangkapan'**
  String get capTitle;

  /// No description provided for @capFromOtherApp.
  ///
  /// In id, this message translates to:
  /// **'Tangkapan dari aplikasi lain'**
  String get capFromOtherApp;

  /// No description provided for @capFrom.
  ///
  /// In id, this message translates to:
  /// **'Dari: {label}'**
  String capFrom(Object label);

  /// No description provided for @capNotFound.
  ///
  /// In id, this message translates to:
  /// **'Tidak ditemukan.'**
  String get capNotFound;

  /// No description provided for @capPlayAll.
  ///
  /// In id, this message translates to:
  /// **'Putar semua yang ditemukan ({count})'**
  String capPlayAll(int count);

  /// No description provided for @capAddAll.
  ///
  /// In id, this message translates to:
  /// **'Tambah semua ke antrean'**
  String get capAddAll;

  /// No description provided for @capMatching.
  ///
  /// In id, this message translates to:
  /// **'Mencocokkan… item muncul satu per satu.'**
  String get capMatching;

  /// No description provided for @capMatchingShort.
  ///
  /// In id, this message translates to:
  /// **'Mencocokkan…'**
  String get capMatchingShort;

  /// No description provided for @capImageList.
  ///
  /// In id, this message translates to:
  /// **'Gambar daftar lagu'**
  String get capImageList;

  /// No description provided for @lyrTitle.
  ///
  /// In id, this message translates to:
  /// **'Lirik'**
  String get lyrTitle;

  /// No description provided for @lyrNoTrack.
  ///
  /// In id, this message translates to:
  /// **'Tidak ada lagu yang sedang diputar.'**
  String get lyrNoTrack;

  /// No description provided for @lyrInstrumental.
  ///
  /// In id, this message translates to:
  /// **'Lagu ini instrumental — memang tidak ada liriknya.'**
  String get lyrInstrumental;

  /// No description provided for @lyrNotFound.
  ///
  /// In id, this message translates to:
  /// **'Lirik tidak ditemukan di LRCLIB untuk lagu ini.'**
  String get lyrNotFound;

  /// No description provided for @lyrNetError.
  ///
  /// In id, this message translates to:
  /// **'Tidak dapat memeriksa lirik — koneksi bermasalah.'**
  String get lyrNetError;

  /// No description provided for @lyrSource.
  ///
  /// In id, this message translates to:
  /// **'Sumber lirik: LRCLIB (lrclib.net) — tersimpan lokal sesudah ditemukan.'**
  String get lyrSource;

  /// No description provided for @lyrPlainNote.
  ///
  /// In id, this message translates to:
  /// **'Lirik tersedia tanpa sinkronisasi waktu.'**
  String get lyrPlainNote;

  /// No description provided for @lyrTrackLine.
  ///
  /// In id, this message translates to:
  /// **'{title} — {artist}'**
  String lyrTrackLine(Object artist, Object title);

  /// No description provided for @sleepTitle.
  ///
  /// In id, this message translates to:
  /// **'Timer tidur'**
  String get sleepTitle;

  /// No description provided for @sleepSubOff.
  ///
  /// In id, this message translates to:
  /// **'Musik berhenti sendiri — lalu bisa dilanjutkan besok dari posisi yang sama.'**
  String get sleepSubOff;

  /// No description provided for @sleepSubMinutes.
  ///
  /// In id, this message translates to:
  /// **'Timer aktif — {remaining} lagi. Volume memudar halus di bentang akhir, lalu musik jeda.'**
  String sleepSubMinutes(Object remaining);

  /// No description provided for @sleepSubEndOfSong.
  ///
  /// In id, this message translates to:
  /// **'Timer aktif — musik berhenti di akhir lagu yang sedang berjalan (memudar di bentang akhirnya).'**
  String get sleepSubEndOfSong;

  /// No description provided for @sleepMinutes.
  ///
  /// In id, this message translates to:
  /// **'{m} menit'**
  String sleepMinutes(int m);

  /// No description provided for @sleepEndOfSong.
  ///
  /// In id, this message translates to:
  /// **'Akhir lagu ini'**
  String get sleepEndOfSong;

  /// No description provided for @sleepCancel.
  ///
  /// In id, this message translates to:
  /// **'Batalkan timer'**
  String get sleepCancel;

  /// No description provided for @sleepRemaining.
  ///
  /// In id, this message translates to:
  /// **'Sisa {time}'**
  String sleepRemaining(Object time);

  /// No description provided for @voiceTitle.
  ///
  /// In id, this message translates to:
  /// **'Antrean Suara'**
  String get voiceTitle;

  /// No description provided for @voiceHintIdle.
  ///
  /// In id, this message translates to:
  /// **'Ketuk mikrofon, atau ketik perintah di bawah.'**
  String get voiceHintIdle;

  /// No description provided for @voiceListening.
  ///
  /// In id, this message translates to:
  /// **'Mendengarkan… ketuk mikrofon untuk berhenti.'**
  String get voiceListening;

  /// No description provided for @voiceMicDenied.
  ///
  /// In id, this message translates to:
  /// **'Izin mikrofon ditolak — ketik perintah di bawah.'**
  String get voiceMicDenied;

  /// No description provided for @voiceExamples.
  ///
  /// In id, this message translates to:
  /// **'Coba: \"putar [judul lagu]\", \"tambah [judul] setelah ini\", \"lewati\", \"jeda\", \"lanjut\".'**
  String get voiceExamples;

  /// No description provided for @voiceInputHint.
  ///
  /// In id, this message translates to:
  /// **'Ketik perintah (simulasi suara)…'**
  String get voiceInputHint;

  /// No description provided for @voiceSend.
  ///
  /// In id, this message translates to:
  /// **'Kirim'**
  String get voiceSend;

  /// No description provided for @voiceSearching.
  ///
  /// In id, this message translates to:
  /// **'Mencari…'**
  String get voiceSearching;

  /// No description provided for @voiceWhichOne.
  ///
  /// In id, this message translates to:
  /// **'Yang mana maksudmu?'**
  String get voiceWhichOne;

  /// No description provided for @drvExit.
  ///
  /// In id, this message translates to:
  /// **'Keluar'**
  String get drvExit;

  /// No description provided for @drvSwipeHint.
  ///
  /// In id, this message translates to:
  /// **'Usap kiri/kanan di mana saja untuk berikutnya/sebelumnya.'**
  String get drvSwipeHint;

  /// No description provided for @drvNoSong.
  ///
  /// In id, this message translates to:
  /// **'Tidak ada lagu'**
  String get drvNoSong;

  /// No description provided for @drvAnnounceSubShort.
  ///
  /// In id, this message translates to:
  /// **'Judul lagu berikutnya dibacakan sebelum diputar.'**
  String get drvAnnounceSubShort;

  /// No description provided for @drvSpeedVolumeNote.
  ///
  /// In id, this message translates to:
  /// **'Volume bergerak hanya di antara dua titik yang kamu kalibrasi di Pengaturan.'**
  String get drvSpeedVolumeNote;

  /// No description provided for @vcDisconnected.
  ///
  /// In id, this message translates to:
  /// **'Pengenal suara terputus — ketik perintah di bawah.'**
  String get vcDisconnected;

  /// No description provided for @vcFailed.
  ///
  /// In id, this message translates to:
  /// **'Pengenal suara gagal ({error}) — ketik perintah di bawah.'**
  String vcFailed(Object error);

  /// No description provided for @vcAnswerChoice.
  ///
  /// In id, this message translates to:
  /// **'Jawab \"yang pertama\" atau \"yang kedua\", atau \"batal\".'**
  String get vcAnswerChoice;

  /// No description provided for @vcCancelled.
  ///
  /// In id, this message translates to:
  /// **'Baik, dibatalkan.'**
  String get vcCancelled;

  /// No description provided for @vcUnclear.
  ///
  /// In id, this message translates to:
  /// **'Maaf, saya kurang jelas — bisa diulangi?'**
  String get vcUnclear;

  /// No description provided for @vcStopped.
  ///
  /// In id, this message translates to:
  /// **'Baik, saya berhenti mendengarkan.'**
  String get vcStopped;

  /// No description provided for @vcUnknown.
  ///
  /// In id, this message translates to:
  /// **'Maaf, perintah tidak dikenali. Coba: putar [judul lagu].'**
  String get vcUnknown;

  /// No description provided for @vcSkipped.
  ///
  /// In id, this message translates to:
  /// **'Dilewati.'**
  String get vcSkipped;

  /// No description provided for @vcPaused.
  ///
  /// In id, this message translates to:
  /// **'Dijeda.'**
  String get vcPaused;

  /// No description provided for @vcResumed.
  ///
  /// In id, this message translates to:
  /// **'Dilanjutkan.'**
  String get vcResumed;

  /// No description provided for @vcSayTitle.
  ///
  /// In id, this message translates to:
  /// **'Sebut judul lagunya — misalnya: putar [judul lagu].'**
  String get vcSayTitle;

  /// No description provided for @vcNotFound.
  ///
  /// In id, this message translates to:
  /// **'Tidak ditemukan lagu untuk \"{query}\".'**
  String vcNotFound(Object query);

  /// No description provided for @vcNoMatch.
  ///
  /// In id, this message translates to:
  /// **'Tidak ditemukan lagu yang cocok untuk \"{query}\".'**
  String vcNoMatch(Object query);

  /// No description provided for @vcWhich.
  ///
  /// In id, this message translates to:
  /// **'Maksudmu {t1} — {a1}, atau {t2} — {a2}?'**
  String vcWhich(Object a1, Object a2, Object t1, Object t2);

  /// No description provided for @vcSearchFailed.
  ///
  /// In id, this message translates to:
  /// **'Pencarian gagal — periksa jaringan lalu coba lagi.'**
  String get vcSearchFailed;

  /// No description provided for @vcPlaying.
  ///
  /// In id, this message translates to:
  /// **'Memutar {title} — {artist}.'**
  String vcPlaying(Object artist, Object title);

  /// No description provided for @vcAddedNext.
  ///
  /// In id, this message translates to:
  /// **'Menambahkan {title} — {artist} setelah lagu ini.'**
  String vcAddedNext(Object artist, Object title);

  /// No description provided for @vcAddedQueue.
  ///
  /// In id, this message translates to:
  /// **'Menambahkan {title} — {artist} ke antrean.'**
  String vcAddedQueue(Object artist, Object title);

  /// No description provided for @vcContextLabel.
  ///
  /// In id, this message translates to:
  /// **'Suara'**
  String get vcContextLabel;

  /// No description provided for @diagTitle.
  ///
  /// In id, this message translates to:
  /// **'Diagnostik Putar'**
  String get diagTitle;

  /// No description provided for @diagIntro.
  ///
  /// In id, this message translates to:
  /// **'Menguji rantai putar per mata rantai (resolusi → unduh → ExoPlayer polos → +header → muxed → jalur aplikasi → pipa lokal) untuk lagu Song & item Video, lengkap dengan galat natif dari logcat proses. Hasilnya satu laporan teks — salin & kirim ke pengembang bila lagu tidak bunyi.'**
  String get diagIntro;

  /// No description provided for @diagRun.
  ///
  /// In id, this message translates to:
  /// **'Jalankan Diagnostik'**
  String get diagRun;

  /// No description provided for @diagRunning.
  ///
  /// In id, this message translates to:
  /// **'Berjalan…'**
  String get diagRunning;

  /// No description provided for @diagCopy.
  ///
  /// In id, this message translates to:
  /// **'Salin Laporan'**
  String get diagCopy;

  /// No description provided for @diagCopied.
  ///
  /// In id, this message translates to:
  /// **'Laporan disalin.'**
  String get diagCopied;

  /// No description provided for @diagEmpty.
  ///
  /// In id, this message translates to:
  /// **'Belum ada laporan. Ketuk \"Jalankan Diagnostik\".'**
  String get diagEmpty;

  /// No description provided for @updNoReleases.
  ///
  /// In id, this message translates to:
  /// **'Belum ada rilis resmi yang diterbitkan.'**
  String get updNoReleases;

  /// No description provided for @updBadShape.
  ///
  /// In id, this message translates to:
  /// **'Bentuk data rilis tidak dikenal.'**
  String get updBadShape;

  /// No description provided for @updVersionUnreadable.
  ///
  /// In id, this message translates to:
  /// **'Versi terpasang tidak terbaca di perangkat ini.'**
  String get updVersionUnreadable;

  /// No description provided for @updAvailableMsg.
  ///
  /// In id, this message translates to:
  /// **'Versi {version} tersedia.'**
  String updAvailableMsg(Object version);

  /// No description provided for @updUpToDate.
  ///
  /// In id, this message translates to:
  /// **'Clai sudah versi terbaru.'**
  String get updUpToDate;

  /// No description provided for @updCheckFailedHttp.
  ///
  /// In id, this message translates to:
  /// **'Pemeriksaan gagal (HTTP {code}).'**
  String updCheckFailedHttp(int code);

  /// No description provided for @updCheckFailed.
  ///
  /// In id, this message translates to:
  /// **'Tidak dapat memeriksa pembaruan. Periksa koneksimu.'**
  String get updCheckFailed;

  /// No description provided for @updNoApk.
  ///
  /// In id, this message translates to:
  /// **'Rilis {tag} tidak membawa berkas APK.'**
  String updNoApk(Object tag);

  /// No description provided for @updWaitingWifi.
  ///
  /// In id, this message translates to:
  /// **'Pembaruan tersedia — unduhan otomatis menunggu Wi-Fi.'**
  String get updWaitingWifi;

  /// No description provided for @updAlreadyDownloaded.
  ///
  /// In id, this message translates to:
  /// **'Pembaruan sudah terunduh — siap dipasang.'**
  String get updAlreadyDownloaded;

  /// No description provided for @updDownloadDone.
  ///
  /// In id, this message translates to:
  /// **'Unduhan selesai — siap dipasang.'**
  String get updDownloadDone;

  /// No description provided for @updDownloadFailed.
  ///
  /// In id, this message translates to:
  /// **'Unduhan gagal. Coba lagi saat koneksi stabil.'**
  String get updDownloadFailed;

  /// No description provided for @updFollowSystem.
  ///
  /// In id, this message translates to:
  /// **'Ikuti konfirmasi sistem untuk menyelesaikan pemasangan.'**
  String get updFollowSystem;

  /// No description provided for @updInstallPermMsg.
  ///
  /// In id, this message translates to:
  /// **'Android belum mengizinkan Clai memasang aplikasi. Izinkan \"pasang aplikasi tak dikenal\" untuk Clai, lalu coba lagi.'**
  String get updInstallPermMsg;

  /// No description provided for @updInstallFailed.
  ///
  /// In id, this message translates to:
  /// **'Pemasangan gagal di sistem. Berkas unduhan tetap tersimpan — coba lagi.'**
  String get updInstallFailed;

  /// No description provided for @ocrMsgInstalled.
  ///
  /// In id, this message translates to:
  /// **'Model terpasang — Tangkap gambar bekerja offline.'**
  String get ocrMsgInstalled;

  /// No description provided for @ocrMsgNotDownloaded.
  ///
  /// In id, this message translates to:
  /// **'Model pembaca teks belum diunduh (sekali saja, ±4 MB).'**
  String get ocrMsgNotDownloaded;

  /// No description provided for @ocrMsgDeleted.
  ///
  /// In id, this message translates to:
  /// **'Model dihapus. Tangkap gambar akan menawarkannya lagi.'**
  String get ocrMsgDeleted;

  /// No description provided for @ocrMsgContacting.
  ///
  /// In id, this message translates to:
  /// **'Menghubungi GitHub Releases…'**
  String get ocrMsgContacting;

  /// No description provided for @ocrErrFeed.
  ///
  /// In id, this message translates to:
  /// **'Umpan rilis tidak dapat dibaca (HTTP {code}).'**
  String ocrErrFeed(int code);

  /// No description provided for @ocrErrNoModel.
  ///
  /// In id, this message translates to:
  /// **'Rilis tidak membawa model OCR.'**
  String get ocrErrNoModel;

  /// No description provided for @ocrErrManifestEmpty.
  ///
  /// In id, this message translates to:
  /// **'Manifest model kosong.'**
  String get ocrErrManifestEmpty;

  /// No description provided for @ocrErrManifestUnknown.
  ///
  /// In id, this message translates to:
  /// **'Manifest model tidak dikenal.'**
  String get ocrErrManifestUnknown;

  /// No description provided for @ocrErrAssetMissing.
  ///
  /// In id, this message translates to:
  /// **'Aset model {file} tidak ada di rilis.'**
  String ocrErrAssetMissing(Object file);

  /// No description provided for @ocrMsgDownloading.
  ///
  /// In id, this message translates to:
  /// **'Mengunduh model ({version})…'**
  String ocrMsgDownloading(Object version);

  /// No description provided for @ocrMsgChecksumFail.
  ///
  /// In id, this message translates to:
  /// **'Checksum tidak cocok — berkas dibuang sebelum sempat dipakai. Coba unduh lagi.'**
  String get ocrMsgChecksumFail;

  /// No description provided for @ocrMsgInstalledReady.
  ///
  /// In id, this message translates to:
  /// **'Model terpasang — Tangkap gambar siap dipakai, termasuk offline.'**
  String get ocrMsgInstalledReady;

  /// No description provided for @ocrMsgDownloadFailed.
  ///
  /// In id, this message translates to:
  /// **'Unduhan gagal. Periksa koneksimu lalu coba lagi.'**
  String get ocrMsgDownloadFailed;

  /// No description provided for @capSvcModelMissing.
  ///
  /// In id, this message translates to:
  /// **'Model pembaca teks belum diunduh.'**
  String get capSvcModelMissing;

  /// No description provided for @capSvcNoText.
  ///
  /// In id, this message translates to:
  /// **'Tidak ada teks terbaca dari gambar ini.'**
  String get capSvcNoText;

  /// No description provided for @capSvcNoLines.
  ///
  /// In id, this message translates to:
  /// **'Tidak ada baris teks terbaca dari gambar.'**
  String get capSvcNoLines;

  /// No description provided for @capSvcModelMissingLong.
  ///
  /// In id, this message translates to:
  /// **'Model pembaca teks belum diunduh. Unduh sekali (panel di atas atau Pengaturan → Tangkap), sesudah itu gambar dibaca offline.'**
  String get capSvcModelMissingLong;

  /// No description provided for @capSvcTitleUnreadable.
  ///
  /// In id, this message translates to:
  /// **'Judul halaman tidak dapat dibaca.'**
  String get capSvcTitleUnreadable;

  /// No description provided for @capSvcSpotifySummary.
  ///
  /// In id, this message translates to:
  /// **'Playlist Spotify: {name}'**
  String capSvcSpotifySummary(Object name);

  /// No description provided for @capSvcYtSummary.
  ///
  /// In id, this message translates to:
  /// **'Daftar putar: {title}'**
  String capSvcYtSummary(Object title);

  /// No description provided for @capSvcNoAudioMatch.
  ///
  /// In id, this message translates to:
  /// **'Tidak tercocokkan ke audio.'**
  String get capSvcNoAudioMatch;

  /// No description provided for @capSvcMatchFailed.
  ///
  /// In id, this message translates to:
  /// **'Pencocokan gagal.'**
  String get capSvcMatchFailed;

  /// No description provided for @capSvcPlaylistNotFound.
  ///
  /// In id, this message translates to:
  /// **'Playlist tidak ditemukan atau tidak publik.'**
  String get capSvcPlaylistNotFound;

  /// No description provided for @capSvcMetaUnreadable.
  ///
  /// In id, this message translates to:
  /// **'Metadata lagu tidak dapat dibaca.'**
  String get capSvcMetaUnreadable;

  /// No description provided for @capSvcPlaylistLoadFail.
  ///
  /// In id, this message translates to:
  /// **'Playlist tidak dapat dimuat.'**
  String get capSvcPlaylistLoadFail;

  /// No description provided for @capSvcVideoMetaUnreadable.
  ///
  /// In id, this message translates to:
  /// **'Metadata video tidak dapat dibaca.'**
  String get capSvcVideoMetaUnreadable;

  /// No description provided for @capSvcNotFound.
  ///
  /// In id, this message translates to:
  /// **'Tidak ditemukan.'**
  String get capSvcNotFound;

  /// No description provided for @capSvcNoGoodMatch.
  ///
  /// In id, this message translates to:
  /// **'Tidak ada yang cukup cocok.'**
  String get capSvcNoGoodMatch;

  /// No description provided for @capSvcSearchFailed.
  ///
  /// In id, this message translates to:
  /// **'Pencarian gagal.'**
  String get capSvcSearchFailed;

  /// No description provided for @spErrServerTime.
  ///
  /// In id, this message translates to:
  /// **'Waktu server Spotify tidak terbaca.'**
  String get spErrServerTime;

  /// No description provided for @spErrTokenRejected.
  ///
  /// In id, this message translates to:
  /// **'Token web Spotify ditolak — skema token mungkin sudah dirotasi Spotify.'**
  String get spErrTokenRejected;

  /// No description provided for @spErrUnreachable.
  ///
  /// In id, this message translates to:
  /// **'Tidak dapat menjangkau Spotify: {type}'**
  String spErrUnreachable(Object type);

  /// No description provided for @spErrHashRotated.
  ///
  /// In id, this message translates to:
  /// **'Skema kueri Spotify berubah (hash persisted ditolak) — fitur playlist Spotify perlu diperbarui.'**
  String get spErrHashRotated;

  /// No description provided for @spErrHttp.
  ///
  /// In id, this message translates to:
  /// **'Spotify menjawab HTTP {code}.'**
  String spErrHttp(int code);

  /// No description provided for @spErrShape.
  ///
  /// In id, this message translates to:
  /// **'Bentuk respons Spotify berubah.'**
  String get spErrShape;

  /// No description provided for @spErrQueryRejected.
  ///
  /// In id, this message translates to:
  /// **'Spotify menolak kueri: {msg}'**
  String spErrQueryRejected(Object msg);

  /// No description provided for @spErrShapeV2.
  ///
  /// In id, this message translates to:
  /// **'Bentuk respons Spotify berubah (playlistV2 hilang).'**
  String get spErrShapeV2;

  /// No description provided for @noticeOfflineHidden.
  ///
  /// In id, this message translates to:
  /// **'Mode offline: {count} lagu streaming disembunyikan dari antrean.'**
  String noticeOfflineHidden(int count);

  /// No description provided for @noticePrepareFail.
  ///
  /// In id, this message translates to:
  /// **'Tidak dapat menyiapkan pemutaran {what}. Periksa koneksi lalu ketuk putar lagi.'**
  String noticePrepareFail(Object what);

  /// No description provided for @noticeQueueEnded.
  ///
  /// In id, this message translates to:
  /// **'Antrean habis — tidak ada sambungan tersedia.'**
  String get noticeQueueEnded;

  /// No description provided for @noticeOfflineNonePlayable.
  ///
  /// In id, this message translates to:
  /// **'Mode offline aktif — tidak ada lagu yang bisa diputar offline dalam daftar ini.'**
  String get noticeOfflineNonePlayable;

  /// No description provided for @noticeOfflineSkipped.
  ///
  /// In id, this message translates to:
  /// **'Mode offline: {count} lagu dilewati (belum diunduh).'**
  String noticeOfflineSkipped(int count);

  /// No description provided for @noticeOfflineNotDownloaded.
  ///
  /// In id, this message translates to:
  /// **'Mode offline aktif — \"{title}\" belum diunduh.'**
  String noticeOfflineNotDownloaded(Object title);

  /// No description provided for @noticeSkippedUnplayable.
  ///
  /// In id, this message translates to:
  /// **'Melewatkan \"{title}\" — tidak dapat diputar dari sumber.'**
  String noticeSkippedUnplayable(Object title);

  /// No description provided for @noticeAutoStop.
  ///
  /// In id, this message translates to:
  /// **'Berhenti otomatis: 3 lagu gagal berturut-turut.'**
  String get noticeAutoStop;

  /// No description provided for @noticeTryingOtherPath.
  ///
  /// In id, this message translates to:
  /// **'Mencoba jalur putar lain untuk \"{title}\"…'**
  String noticeTryingOtherPath(Object title);

  /// No description provided for @dlErrFileMissing.
  ///
  /// In id, this message translates to:
  /// **'Berkas unduhan tidak ditemukan di perangkat.'**
  String get dlErrFileMissing;

  /// No description provided for @dlErrTimeout.
  ///
  /// In id, this message translates to:
  /// **'Waktu unduh habis.'**
  String get dlErrTimeout;

  /// No description provided for @dlErrNoConnection.
  ///
  /// In id, this message translates to:
  /// **'Tidak ada koneksi.'**
  String get dlErrNoConnection;

  /// No description provided for @dlErrSourceRefused.
  ///
  /// In id, this message translates to:
  /// **'Sumber menolak unduhan (HTTP {code}).'**
  String dlErrSourceRefused(int code);

  /// No description provided for @drvAnnounceNext.
  ///
  /// In id, this message translates to:
  /// **'Berikutnya: {title} — {artist}'**
  String drvAnnounceNext(Object artist, Object title);

  /// No description provided for @startupStarting.
  ///
  /// In id, this message translates to:
  /// **'Memulai…'**
  String get startupStarting;

  /// No description provided for @startupDb.
  ///
  /// In id, this message translates to:
  /// **'Menyiapkan basis data…'**
  String get startupDb;

  /// No description provided for @startupSource.
  ///
  /// In id, this message translates to:
  /// **'Menyiapkan sumber musik…'**
  String get startupSource;

  /// No description provided for @startupPlayer.
  ///
  /// In id, this message translates to:
  /// **'Menyiapkan pemutar…'**
  String get startupPlayer;

  /// No description provided for @startupPrefs.
  ///
  /// In id, this message translates to:
  /// **'Memulihkan preferensi…'**
  String get startupPrefs;

  /// No description provided for @startupServices.
  ///
  /// In id, this message translates to:
  /// **'Menyiapkan layanan…'**
  String get startupServices;

  /// No description provided for @startupFailedTitle.
  ///
  /// In id, this message translates to:
  /// **'Clai gagal mulai'**
  String get startupFailedTitle;

  /// No description provided for @startupFailedStep.
  ///
  /// In id, this message translates to:
  /// **'Langkah yang gagal: {step}'**
  String startupFailedStep(Object step);

  /// No description provided for @startupRetry.
  ///
  /// In id, this message translates to:
  /// **'Coba Lagi'**
  String get startupRetry;

  /// No description provided for @startupReportCopied.
  ///
  /// In id, this message translates to:
  /// **'Laporan tersalin — tempel & kirim ke pengembang.'**
  String get startupReportCopied;

  /// No description provided for @capSvcFromLink.
  ///
  /// In id, this message translates to:
  /// **'{title} (dari tautan)'**
  String capSvcFromLink(Object title);

  /// No description provided for @ctxPreviousSession.
  ///
  /// In id, this message translates to:
  /// **'Sesi sebelumnya'**
  String get ctxPreviousSession;

  /// No description provided for @notifLike.
  ///
  /// In id, this message translates to:
  /// **'Sukai'**
  String get notifLike;

  /// No description provided for @notifUnlike.
  ///
  /// In id, this message translates to:
  /// **'Sudah disukai'**
  String get notifUnlike;

  /// No description provided for @dlErrCorrupt.
  ///
  /// In id, this message translates to:
  /// **'Berkas unduhan rusak (checksum tidak cocok).'**
  String get dlErrCorrupt;

  /// No description provided for @dlErrQuotaFull.
  ///
  /// In id, this message translates to:
  /// **'Kuota unduhan penuh — hapus unduhan lama atau naikkan kuota di Pengaturan.'**
  String get dlErrQuotaFull;

  /// No description provided for @dlErrStorageFull.
  ///
  /// In id, this message translates to:
  /// **'Penyimpanan perangkat penuh.'**
  String get dlErrStorageFull;

  /// No description provided for @dlPause.
  ///
  /// In id, this message translates to:
  /// **'Jeda'**
  String get dlPause;

  /// No description provided for @dlResume.
  ///
  /// In id, this message translates to:
  /// **'Lanjutkan'**
  String get dlResume;

  /// No description provided for @dlPauseAll.
  ///
  /// In id, this message translates to:
  /// **'Jeda Semua'**
  String get dlPauseAll;

  /// No description provided for @dlResumeAll.
  ///
  /// In id, this message translates to:
  /// **'Lanjutkan Semua'**
  String get dlResumeAll;

  /// No description provided for @dlRedownload.
  ///
  /// In id, this message translates to:
  /// **'Unduh Ulang'**
  String get dlRedownload;

  /// No description provided for @dlPausedState.
  ///
  /// In id, this message translates to:
  /// **'Dijeda · {done} dari {total}'**
  String dlPausedState(Object done, Object total);

  /// No description provided for @dlUsageLine.
  ///
  /// In id, this message translates to:
  /// **'Terpakai {used}'**
  String dlUsageLine(Object used);

  /// No description provided for @dlQuotaLabel.
  ///
  /// In id, this message translates to:
  /// **'Kuota unduhan'**
  String get dlQuotaLabel;

  /// No description provided for @dlQuotaUnlimited.
  ///
  /// In id, this message translates to:
  /// **'Tanpa batas'**
  String get dlQuotaUnlimited;

  /// No description provided for @dlQuotaGb.
  ///
  /// In id, this message translates to:
  /// **'{gb} GB'**
  String dlQuotaGb(int gb);

  /// No description provided for @setDataSaver.
  ///
  /// In id, this message translates to:
  /// **'Mode hemat data'**
  String get setDataSaver;

  /// No description provided for @setDataSaverSub.
  ///
  /// In id, this message translates to:
  /// **'Streaming selalu kualitas Rendah saat aktif; kualitas Tinggi dicegah di jaringan seluler.'**
  String get setDataSaverSub;

  /// No description provided for @setDataSaverCellularBlock.
  ///
  /// In id, this message translates to:
  /// **'Kualitas Tinggi dicegah: mode hemat data aktif dan perangkat memakai jaringan seluler.'**
  String get setDataSaverCellularBlock;

  /// No description provided for @setFocusBehavior.
  ///
  /// In id, this message translates to:
  /// **'Saat aplikasi lain berbunyi sebentar'**
  String get setFocusBehavior;

  /// No description provided for @focusDuck.
  ///
  /// In id, this message translates to:
  /// **'Turunkan volume (duck)'**
  String get focusDuck;

  /// No description provided for @focusPause.
  ///
  /// In id, this message translates to:
  /// **'Jeda, lanjut otomatis sesudahnya'**
  String get focusPause;

  /// No description provided for @setHistoryRetention.
  ///
  /// In id, this message translates to:
  /// **'Simpan riwayat putar selama'**
  String get setHistoryRetention;

  /// No description provided for @histDays.
  ///
  /// In id, this message translates to:
  /// **'{days} hari'**
  String histDays(int days);

  /// No description provided for @histForever.
  ///
  /// In id, this message translates to:
  /// **'Selamanya'**
  String get histForever;

  /// No description provided for @playerBitrate.
  ///
  /// In id, this message translates to:
  /// **'{kbps} kbps'**
  String playerBitrate(int kbps);

  /// No description provided for @a11yPlay.
  ///
  /// In id, this message translates to:
  /// **'Putar'**
  String get a11yPlay;

  /// No description provided for @a11yPause.
  ///
  /// In id, this message translates to:
  /// **'Jeda'**
  String get a11yPause;

  /// No description provided for @a11yNext.
  ///
  /// In id, this message translates to:
  /// **'Lagu berikutnya'**
  String get a11yNext;

  /// No description provided for @a11yPrevious.
  ///
  /// In id, this message translates to:
  /// **'Lagu sebelumnya'**
  String get a11yPrevious;

  /// No description provided for @a11yShuffle.
  ///
  /// In id, this message translates to:
  /// **'Acak'**
  String get a11yShuffle;

  /// No description provided for @a11yRepeat.
  ///
  /// In id, this message translates to:
  /// **'Ulangi'**
  String get a11yRepeat;

  /// No description provided for @a11yLike.
  ///
  /// In id, this message translates to:
  /// **'Sukai'**
  String get a11yLike;

  /// No description provided for @a11yUnlike.
  ///
  /// In id, this message translates to:
  /// **'Batalkan suka'**
  String get a11yUnlike;

  /// No description provided for @a11yClosePlayer.
  ///
  /// In id, this message translates to:
  /// **'Tutup pemutar'**
  String get a11yClosePlayer;

  /// No description provided for @a11yOpenPlayer.
  ///
  /// In id, this message translates to:
  /// **'Buka pemutar'**
  String get a11yOpenPlayer;

  /// No description provided for @a11yTrackOptions.
  ///
  /// In id, this message translates to:
  /// **'Opsi lagu'**
  String get a11yTrackOptions;

  /// No description provided for @a11ySeek.
  ///
  /// In id, this message translates to:
  /// **'Posisi putar'**
  String get a11ySeek;

  /// No description provided for @a11ySettings.
  ///
  /// In id, this message translates to:
  /// **'Pengaturan'**
  String get a11ySettings;

  /// No description provided for @a11ySort.
  ///
  /// In id, this message translates to:
  /// **'Urutkan'**
  String get a11ySort;

  /// No description provided for @contentSave.
  ///
  /// In id, this message translates to:
  /// **'Simpan ke Koleksi'**
  String get contentSave;

  /// No description provided for @contentSaved.
  ///
  /// In id, this message translates to:
  /// **'Tersimpan di Koleksi'**
  String get contentSaved;

  /// No description provided for @contentDownloadAll.
  ///
  /// In id, this message translates to:
  /// **'Unduh Semua'**
  String get contentDownloadAll;

  /// No description provided for @contentShare.
  ///
  /// In id, this message translates to:
  /// **'Bagikan'**
  String get contentShare;

  /// No description provided for @contentFromCache.
  ///
  /// In id, this message translates to:
  /// **'Menampilkan salinan tersimpan — sumber sedang tak terjangkau.'**
  String get contentFromCache;

  /// No description provided for @collectionAlbums.
  ///
  /// In id, this message translates to:
  /// **'Album'**
  String get collectionAlbums;

  /// No description provided for @collectionArtists.
  ///
  /// In id, this message translates to:
  /// **'Artis'**
  String get collectionArtists;

  /// No description provided for @collectionEmptyAlbums.
  ///
  /// In id, this message translates to:
  /// **'Belum ada album tersimpan. Simpan dari halaman album.'**
  String get collectionEmptyAlbums;

  /// No description provided for @collectionEmptyArtists.
  ///
  /// In id, this message translates to:
  /// **'Belum ada artis tersimpan. Simpan dari halaman artis.'**
  String get collectionEmptyArtists;

  /// No description provided for @searchSuggestions.
  ///
  /// In id, this message translates to:
  /// **'Saran'**
  String get searchSuggestions;

  /// No description provided for @eqPresetFlat.
  ///
  /// In id, this message translates to:
  /// **'Datar'**
  String get eqPresetFlat;

  /// No description provided for @eqPresetBass.
  ///
  /// In id, this message translates to:
  /// **'Bass'**
  String get eqPresetBass;

  /// No description provided for @eqPresetVocal.
  ///
  /// In id, this message translates to:
  /// **'Vokal'**
  String get eqPresetVocal;

  /// No description provided for @eqPresetAcoustic.
  ///
  /// In id, this message translates to:
  /// **'Akustik'**
  String get eqPresetAcoustic;

  /// No description provided for @eqNamedPresets.
  ///
  /// In id, this message translates to:
  /// **'Preset Clai'**
  String get eqNamedPresets;

  /// No description provided for @setSamsung.
  ///
  /// In id, this message translates to:
  /// **'Samsung'**
  String get setSamsung;

  /// No description provided for @setSamsungSub.
  ///
  /// In id, this message translates to:
  /// **'Pengaturan → Baterai → Batas penggunaan latar → jangan masukkan Clai ke aplikasi tidur/tidur nyenyak.'**
  String get setSamsungSub;

  /// No description provided for @setOppo.
  ///
  /// In id, this message translates to:
  /// **'Oppo / vivo'**
  String get setOppo;

  /// No description provided for @setOppoSub.
  ///
  /// In id, this message translates to:
  /// **'Aktifkan mulai-otomatis (autostart) untuk Clai dan kunci aplikasi di layar terbaru (recents) agar tidak dibersihkan sistem.'**
  String get setOppoSub;

  /// No description provided for @setHuawei.
  ///
  /// In id, this message translates to:
  /// **'Huawei / Honor'**
  String get setHuawei;

  /// No description provided for @setHuaweiSub.
  ///
  /// In id, this message translates to:
  /// **'Pengaturan → Baterai → Peluncuran aplikasi → Clai → kelola manual: aktifkan mulai-otomatis, peluncuran sekunder, dan jalan di latar.'**
  String get setHuaweiSub;

  /// No description provided for @bgAutostartNote.
  ///
  /// In id, this message translates to:
  /// **'Status mulai-otomatis (autostart) tidak dapat dideteksi aplikasi secara otomatis di Android — periksa manual sesuai merek perangkatmu di bawah.'**
  String get bgAutostartNote;

  /// No description provided for @noticeRegionUnavailable.
  ///
  /// In id, this message translates to:
  /// **'Konten ini tidak tersedia di wilayahmu.'**
  String get noticeRegionUnavailable;

  /// No description provided for @diagGatesTitle.
  ///
  /// In id, this message translates to:
  /// **'Gerbang kualitas sesi ini (PRD Bab 3)'**
  String get diagGatesTitle;

  /// No description provided for @diagGateCold.
  ///
  /// In id, this message translates to:
  /// **'Mulai dingin terakhir: {ms} ms'**
  String diagGateCold(int ms);

  /// No description provided for @diagGateTap.
  ///
  /// In id, this message translates to:
  /// **'Ketuk→bunyi: median {median} ms · p95 {p95} ms · {n} sampel'**
  String diagGateTap(int median, int n, int p95);

  /// No description provided for @diagGateFail.
  ///
  /// In id, this message translates to:
  /// **'Percobaan putar: {attempts} · gagal {failures} ({pct}%)'**
  String diagGateFail(int attempts, int failures, Object pct);

  /// No description provided for @diagGateNone.
  ///
  /// In id, this message translates to:
  /// **'Belum ada sampel sesi ini.'**
  String get diagGateNone;

  /// No description provided for @a11yClose.
  ///
  /// In id, this message translates to:
  /// **'Tutup'**
  String get a11yClose;

  /// No description provided for @contentDownloadQueued.
  ///
  /// In id, this message translates to:
  /// **'{count} lagu diantrekan untuk diunduh.'**
  String contentDownloadQueued(int count);

  /// No description provided for @contentPlaylistCopied.
  ///
  /// In id, this message translates to:
  /// **'Playlist disalin ke koleksimu.'**
  String get contentPlaylistCopied;

  /// No description provided for @queueDragReorder.
  ///
  /// In id, this message translates to:
  /// **'Seret untuk mengurutkan'**
  String get queueDragReorder;

  /// No description provided for @ocrMsgNotPublished.
  ///
  /// In id, this message translates to:
  /// **'Model belum tersedia — unduhan aktif setelah rilis resmi pertama Clai diterbitkan.'**
  String get ocrMsgNotPublished;

  /// No description provided for @ocrMsgNoModelInRelease.
  ///
  /// In id, this message translates to:
  /// **'Rilis terbaru belum membawa model pembaca teks — unduhan aktif setelah model diterbitkan di rilis.'**
  String get ocrMsgNoModelInRelease;

  /// No description provided for @ocrCheckAgain.
  ///
  /// In id, this message translates to:
  /// **'Periksa Lagi'**
  String get ocrCheckAgain;

  /// No description provided for @artistNotFound.
  ///
  /// In id, this message translates to:
  /// **'Artis tidak ditemukan'**
  String get artistNotFound;

  /// No description provided for @contentDownloaded.
  ///
  /// In id, this message translates to:
  /// **'Terunduh'**
  String get contentDownloaded;

  /// No description provided for @contentDownloadingCount.
  ///
  /// In id, this message translates to:
  /// **'{done}/{total}'**
  String contentDownloadingCount(int done, int total);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'id'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'id':
      return AppLocalizationsId();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
