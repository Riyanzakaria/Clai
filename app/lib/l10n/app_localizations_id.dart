// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Indonesian (`id`).
class AppLocalizationsId extends AppLocalizations {
  AppLocalizationsId([String locale = 'id']) : super(locale);

  @override
  String get appTitle => 'Clai';

  @override
  String get navHome => 'Beranda';

  @override
  String get navSearch => 'Cari';

  @override
  String get navLibrary => 'Koleksi';

  @override
  String get offlineBarText => 'Mode offline — hanya unduhan & file lokal';

  @override
  String get eqTitle => 'Equalizer';

  @override
  String get eqChecking => 'Memeriksa dukungan perangkat…';

  @override
  String get eqUnavailable =>
      'Equalizer tidak tersedia di perangkat ini — efek Equalizer Android menolak dibuat pada sesi pemain yang sedang hidup. Detail teknisnya tercatat di Log insiden (Pengaturan → Diagnosis Lokal).';

  @override
  String get eqWaitingSession => 'Mulai putar lagu agar EQ dapat diterapkan.';

  @override
  String get eqPreset => 'Preset';

  @override
  String get eqCustom => 'Kustom';

  @override
  String eqBandLabel(Object db, Object freq) {
    return '$freq — $db dB';
  }

  @override
  String get ocrModelTitle => 'Model pembaca teks (Tangkap gambar)';

  @override
  String ocrModelInstalled(Object size, Object versionPart) {
    return 'Terpasang · $size$versionPart';
  }

  @override
  String ocrModelVersionPart(Object version) {
    return ' · $version';
  }

  @override
  String commonDownloadingPct(int pct) {
    return 'Mengunduh… $pct%';
  }

  @override
  String get ocrModelVerifying => 'Memeriksa keutuhan berkas (checksum)…';

  @override
  String get ocrModelNotDownloaded => 'Belum diunduh · unduhan sekali ±4 MB.';

  @override
  String get ocrModelDeleteTitle => 'Hapus model pembaca teks?';

  @override
  String get ocrModelDeleteBody =>
      'Tangkap gambar akan menawarkan unduhan lagi saat berikutnya dipakai. Lagu, antrean, dan unduhan lagu tidak terpengaruh.';

  @override
  String get commonCancel => 'Batal';

  @override
  String get commonDelete => 'Hapus';

  @override
  String get commonRetry => 'Coba lagi';

  @override
  String get commonDownload => 'Unduh';

  @override
  String get updateCheck => 'Periksa pembaruan';

  @override
  String get commonChecking => 'Memeriksa…';

  @override
  String get updateInstalling => 'Menyerahkan ke pemasang sistem…';

  @override
  String updateInstalledLabel(Object label, Object status) {
    return 'Terpasang: $label · $status';
  }

  @override
  String updateDownloadTag(Object tag) {
    return 'Unduh $tag';
  }

  @override
  String get updateInstall => 'Pasang pembaruan';

  @override
  String get updateAutoCheck => 'Periksa otomatis';

  @override
  String get updateAutoDownload => 'Perbarui otomatis (unduh di latar)';

  @override
  String get updateWifiOnly => 'Unduh hanya via Wi-Fi';

  @override
  String get updateInstallPermTitle => 'Izin pasang belum diberikan';

  @override
  String updateBannerTitle(Object version) {
    return 'Clai $version tersedia';
  }

  @override
  String get updateBannerReady =>
      'Sudah terunduh — tinggal dipasang lewat konfirmasi sistem.';

  @override
  String get updateBannerDefault =>
      'Unduh di dalam aplikasi, pasang lewat konfirmasi sistem.';

  @override
  String get updateWhatsNewBtn => 'Yang baru';

  @override
  String updateWhatsNewTitle(Object version) {
    return 'Yang baru di $version';
  }

  @override
  String updateBuildLabel(int build) {
    return 'Bangun $build';
  }

  @override
  String get commonInstall => 'Pasang';

  @override
  String get commonLater => 'Nanti saja';

  @override
  String get settingsTitle => 'Pengaturan';

  @override
  String get groupPlayback => 'Pemutaran';

  @override
  String get groupPlaybackSum =>
      'Kualitas, Putar Otomatis, Acak & Acak Cerdas, transisi';

  @override
  String get groupAudio => 'Audio';

  @override
  String get groupAudioSum => 'Equalizer & normalisasi kenyaringan';

  @override
  String get groupDownloads => 'Unduhan & Offline';

  @override
  String get groupDownloadsSum => 'Mode offline & lagu terunduh';

  @override
  String get groupAppearance => 'Tampilan';

  @override
  String get groupAppearanceSum => 'Tema sampul, nama sapaan & bahasa';

  @override
  String get groupDriving => 'Berkendara';

  @override
  String get groupDrivingSum => 'Layar besar & kendali sederhana saat menyetir';

  @override
  String get groupCapture => 'Tangkap';

  @override
  String get groupCaptureSum => 'Tautan/gambar dari aplikasi lain jadi antrean';

  @override
  String get groupBackground => 'Jalan di Latar';

  @override
  String get groupBackgroundSum => 'Izin notifikasi & baterai';

  @override
  String get groupData => 'Data & Penyimpanan';

  @override
  String get groupDataSum => 'Cache aliran & riwayat putar';

  @override
  String get groupUpdates => 'Pembaruan';

  @override
  String get groupUpdatesSum => 'Versi terpasang & rilis baru dari GitHub';

  @override
  String get groupListenBrainzSum => 'Scrobble opsional dengan token milikmu';

  @override
  String get groupDiagnostics => 'Diagnosis';

  @override
  String get groupDiagnosticsSum =>
      'Uji rantai putar & log insiden di perangkat';

  @override
  String get groupAbout => 'Tentang';

  @override
  String get groupAboutSum => 'Versi, lisensi, dan cara Clai bekerja';

  @override
  String get groupExtras => 'Fitur Tambahan';

  @override
  String get groupExtrasSum => 'Berkendara, tangkap & ListenBrainz';

  @override
  String get groupSystem => 'Sistem';

  @override
  String get groupSystemSum => 'Jalan di latar, data, pembaruan & diagnosis';

  @override
  String get settingsSearchHint => 'Cari pengaturan';

  @override
  String settingsSearchEmpty(String query) {
    return 'Tidak ada pengaturan untuk \"$query\"';
  }

  @override
  String get setQuality => 'Kualitas streaming';

  @override
  String get qualityLow => 'Rendah · ≤70 kbps';

  @override
  String get qualityNormal => 'Normal · ≤160 kbps';

  @override
  String get qualityHigh => 'Tinggi · terbaik tersedia (sumber maks ±256 kbps)';

  @override
  String get setAutoplay => 'Putar Otomatis';

  @override
  String get setSmartShuffle => 'Acak Cerdas (Smart Shuffle)';

  @override
  String get setAutoResume => 'Lanjut otomatis setelah interupsi';

  @override
  String get setTransition => 'Mode transisi';

  @override
  String get transitionSnack => 'Mode baru berlaku di lagu berikutnya.';

  @override
  String get setCrossfadeDur => 'Durasi crossfade';

  @override
  String crossfadeDurVal(Object secs) {
    return '$secs detik';
  }

  @override
  String get setNormalization => 'Normalisasi kenyaringan';

  @override
  String get normMicSnack =>
      'Tanpa izin mikrofon, Visualizer Android tidak boleh mengukur — gain semua lagu tetap netral. Izinnya hanya untuk mengukur level, tidak merekam.';

  @override
  String get setOfflineMode => 'Mode offline';

  @override
  String get setManageDownloads => 'Kelola unduhan';

  @override
  String get setDynamicAccent => 'Aksen cover dinamis';

  @override
  String get languageTitle => 'Bahasa';

  @override
  String get languageSystem => 'Sistem';

  @override
  String get captureLinkTitle => 'Tangkap tautan/teks';

  @override
  String get captureHint => 'Tempel tautan atau ketik kata kunci…';

  @override
  String get captureAction => 'Tangkap';

  @override
  String get searchCaptureTitle => 'Tangkap daftar lagu';

  @override
  String get capturePickImage => 'Pilih gambar dari galeri';

  @override
  String get setBgStatus => 'Status izin latar';

  @override
  String bgStatusLine(Object battery, Object notif) {
    return 'Notifikasi: $notif · Baterai: $battery';
  }

  @override
  String get bgPermGranted => 'Diizinkan';

  @override
  String get bgPermNotYet => 'Belum';

  @override
  String get bgBatteryExempt => 'Diabaikan optimasi';

  @override
  String get bgBatteryNotYet => 'Belum diizinkan';

  @override
  String get setAllow => 'Izinkan';

  @override
  String get setXiaomi => 'Khusus Xiaomi / HyperOS';

  @override
  String get setXiaomiSub =>
      'Aktifkan \"Mulai otomatis\", baterai \"Tanpa batasan\".';

  @override
  String get setOtherBrands => 'Merek lain';

  @override
  String get setOtherBrandsSub =>
      'Samsung: jangan masukkan Clai ke \"Aplikasi tidur\".';

  @override
  String get setClearCache => 'Hapus cache aliran';

  @override
  String get cacheClearedSnack => 'Cache aliran dihapus.';

  @override
  String get setClearHistory => 'Hapus riwayat putar';

  @override
  String get historyClearedSnack => 'Riwayat putar dihapus.';

  @override
  String get setDiagTitle => 'Diagnostik Putar';

  @override
  String get setLogTitle => 'Log insiden (di perangkat)';

  @override
  String setLogCount(int count) {
    return '$count catatan';
  }

  @override
  String aboutVersion(String version) {
    return 'Clai $version';
  }

  @override
  String get logTitle => 'Log insiden';

  @override
  String get logEmpty => 'Belum ada insiden tercatat.';

  @override
  String get groupListenBrainz => 'ListenBrainz';

  @override
  String get drvMode => 'Mode Berkendara';

  @override
  String get drvScheme => 'Skema kendali';

  @override
  String get drvSchemeButtons => 'Tombol media';

  @override
  String get drvSchemePatterns => 'Pola tekan';

  @override
  String get drvSchemeVoice => 'Perintah suara';

  @override
  String get drvAnnounce => 'Pengumuman suara';

  @override
  String get drvSpeedVolume => 'Volume ikut kecepatan';

  @override
  String get drvVolStop => 'Volume saat berhenti';

  @override
  String get drvVolFast => 'Volume tercepat';

  @override
  String drvVolFastSub(int pct) {
    return '$pct%';
  }

  @override
  String drvVolPct(int pct) {
    return '$pct%';
  }

  @override
  String get drvAnchor => 'Kecepatan jangkar';

  @override
  String drvAnchorSub(int kmh) {
    return '$kmh km/jam';
  }

  @override
  String get drvVehicles => 'Perangkat kendaraan (Bluetooth)';

  @override
  String get drvVehiclesNone =>
      'Tidak ada perangkat Bluetooth terpasang di perangkat ini.';

  @override
  String drvVehiclesCount(int count) {
    return '$count perangkat terpasang.';
  }

  @override
  String get lbTitle => 'Kirim riwayat dengar ke ListenBrainz';

  @override
  String get lbTokenLabel => 'Token pengguna ListenBrainz';

  @override
  String get lbTokenHint => 'Dari listenbrainz.org → Settings → User Token';

  @override
  String get lbTokenValid => 'Token valid — tersimpan.';

  @override
  String get lbTokenInvalid => 'Token tidak valid atau jaringan bermasalah.';

  @override
  String get lbSaveCheck => 'Simpan & periksa token';

  @override
  String get greetMorning => 'Selamat pagi';

  @override
  String get greetAfternoon => 'Selamat siang';

  @override
  String get greetEvening => 'Selamat sore';

  @override
  String get greetNight => 'Selamat malam';

  @override
  String get homeBgCardTitle => 'Agar musik tidak dibunuh sistem';

  @override
  String get homeSetupNow => 'Atur sekarang';

  @override
  String get homeEmptyTitle => 'Mau dengar apa hari ini?';

  @override
  String get homeEmptySub => 'Cari lagu pertamamu.';

  @override
  String get homeSearchSong => 'Cari lagu';

  @override
  String get homeUpNext => 'Antrian Berikutnya';

  @override
  String get homeOpenQueue => 'Buka Antrian';

  @override
  String get homeRecent => 'Terakhir Diputar';

  @override
  String get homePlayAgain => 'Putar Lagi';

  @override
  String get homeYourCollection => 'Koleksi Kamu';

  @override
  String get homeSavedSongs => 'Lagu Tersimpan';

  @override
  String homeResumeFrom(Object time) {
    return 'Lanjut dari $time';
  }

  @override
  String get homeQuickPlay => 'Cepat putar';

  @override
  String get homeTopWeek => 'Paling sering minggu ini';

  @override
  String get homeTopWeekEmpty =>
      'Belum ada lagu yang sering diputar minggu ini.';

  @override
  String homePlayCount(int count) {
    return '$count× diputar';
  }

  @override
  String songCount(int count) {
    return '$count lagu';
  }

  @override
  String shelfBecauseArtist(Object artist) {
    return 'Karena kamu sering memutar $artist';
  }

  @override
  String get shelfRarelyPlayed => 'Tersimpan tapi jarang diputar';

  @override
  String get jelajahTitle => 'Jelajah';

  @override
  String get jelajahYtmHome => 'Beranda';

  @override
  String get jelajahCharts => 'Tangga Lagu';

  @override
  String get jelajahArtists => 'Artis';

  @override
  String get jelajahLoadFail => 'Jelajah tidak dapat dimuat saat ini.';

  @override
  String jelajahShelfFail(Object source) {
    return 'Rak $source gagal dimuat.';
  }

  @override
  String get jelajahLoading => 'Memuat rak penemuan…';

  @override
  String jelajahShelfTitle(Object title) {
    return 'Jelajah • $title';
  }

  @override
  String get sleepCardTitle => 'Lanjutkan dari semalam';

  @override
  String sleepCardSub(Object artist, Object pos, Object title) {
    return '$title — $artist · dari $pos';
  }

  @override
  String get sleepCardResume => 'Lanjutkan';

  @override
  String get sleepContextLabel => 'Lanjut Besok';

  @override
  String get playerNowPlaying => 'Sedang Diputar';

  @override
  String get playerEmpty => 'Belum ada lagu yang diputar.';

  @override
  String get playerBuffering => 'Buffering…';

  @override
  String get commonLoading => 'Memuat…';

  @override
  String get playerLyrics => 'Lirik';

  @override
  String get queueTitle => 'Antrian';

  @override
  String get playerTimer => 'Timer';

  @override
  String get playerVoice => 'Suara';

  @override
  String get queueEmpty => 'Antrean kosong. Putar sebuah lagu untuk memulai.';

  @override
  String get queueNowPlaying => 'Sedang Diputar';

  @override
  String get queueUpNext => 'Berikutnya';

  @override
  String queueContinuation(Object label) {
    return 'Lanjutan — $label';
  }

  @override
  String get queueContextFallback => 'konteks';

  @override
  String queueCountLine(int count) {
    return '$count trek';
  }

  @override
  String queueCountLineDur(int count, Object duration, Object totalPart) {
    return '$count trek · $duration$totalPart';
  }

  @override
  String queueTotalPart(Object plus) {
    return '$plus total';
  }

  @override
  String queueRemovedSnack(Object title) {
    return 'Dihapus: $title';
  }

  @override
  String get commonUndo => 'Urungkan';

  @override
  String get queueClear => 'Kosongkan antrean';

  @override
  String get queueFilterHint => 'Saring antrean ini…';

  @override
  String get queueAutoplayOff =>
      'Putar Otomatis mati di Pengaturan — konteks habis berarti berhenti.';

  @override
  String queueAutoplayHeader(Object seed) {
    return 'Putar Otomatis — karena kamu memutar $seed';
  }

  @override
  String get queueAutoplayLimited =>
      'terbatas — offline: sambungan hanya dari lagu yang sudah kamu unduh.';

  @override
  String get queuePreparing =>
      'Menyiapkan sambungan dari lagu-lagu benih sesi ini…';

  @override
  String get queueContinuationReady =>
      'Sambungan disiapkan dari lagu-lagu benih sesi ini.';

  @override
  String get queueContinuationPending =>
      'Sambungan belum tersedia (jaringan lambat?). Musik tetap menyambung begitu sambungan siap.';

  @override
  String get queueAutoBadge => 'AUTO';

  @override
  String get ctxPlayNext => 'Putar Berikutnya';

  @override
  String get ctxAddToQueue => 'Tambah ke Antrian';

  @override
  String get ctxStartRadio => 'Mulai Radio Lagu';

  @override
  String get ctxRemoveFromCollection => 'Hapus dari Koleksi';

  @override
  String get ctxSaveToCollection => 'Simpan ke Koleksi';

  @override
  String get ctxAddToPlaylist => 'Tambah ke Playlist';

  @override
  String get ctxDeleteDownload => 'Hapus unduhan';

  @override
  String get ctxOpenAlbum => 'Buka Album';

  @override
  String get ctxOpenArtist => 'Buka Artis';

  @override
  String get ctxShare => 'Bagikan';

  @override
  String ctxShareCredit(Object url) {
    return 'Dibagikan lewat Clai — unduh aplikasinya: $url';
  }

  @override
  String radioPageTitle(Object title) {
    return 'Radio — $title';
  }

  @override
  String get radioGeneratedFrom => 'Bangkitan radio dari lagu ini';

  @override
  String get radioEmpty =>
      'Belum ada lagu radio yang dapat dibuat dari lagu ini.';

  @override
  String get radioLoadFailed =>
      'Tidak dapat memuat radio lagu ini. Periksa koneksimu lalu coba lagi.';

  @override
  String get ctxRemoveFromQueue => 'Hapus dari Antrian';

  @override
  String get queueSelect => 'Pilih';

  @override
  String queueSelectedCount(Object count) {
    return '$count dipilih';
  }

  @override
  String get queueBulkRemove => 'Hapus';

  @override
  String get queueBulkPlaylist => 'Ke Playlist';

  @override
  String get queueBulkSave => 'Simpan';

  @override
  String get queueSelectAll => 'Pilih Semua';

  @override
  String get queueUnselectAll => 'Batalkan Semua';

  @override
  String bulkQueueAdded(Object count) {
    return '$count lagu ditambahkan ke Antrian.';
  }

  @override
  String bulkSaved(Object count) {
    return '$count lagu disimpan ke Koleksi.';
  }

  @override
  String get bulkSavedNone => 'Semua lagu ini sudah ada di Koleksi.';

  @override
  String bulkPlaylistAdded(Object count) {
    return '$count lagu ditambahkan ke playlist.';
  }

  @override
  String get bulkPlaylistNone => 'Semua lagu ini sudah ada di playlist itu.';

  @override
  String bulkRemovedFromQueue(Object count) {
    return '$count lagu dihapus dari Antrian.';
  }

  @override
  String get ctxNewPlaylist => 'Playlist baru';

  @override
  String get ctxPlaylistName => 'Nama playlist';

  @override
  String get ctxAlreadyInPlaylist => 'Sudah ada di playlist';

  @override
  String get ctxAlreadyInPlaylistBody =>
      'Lagu ini sudah ada di playlist itu. Tetap tambahkan sebagai duplikat?';

  @override
  String get ctxSkip => 'Lewati';

  @override
  String get ctxAddAnyway => 'Tetap tambahkan';

  @override
  String get commonSave => 'Simpan';

  @override
  String get searchHint => 'Cari lagu, album, artis…';

  @override
  String get searchSpotifyOnlySnack =>
      'Baru tautan PLAYLIST Spotify yang didukung — tempel tautan playlist publiknya.';

  @override
  String get searchSourceBroken =>
      'Sumber sedang bermasalah — bentuk datanya berubah. Ini bukan salah koneksimu.';

  @override
  String get searchNetworkError =>
      'Tidak dapat menjangkau sumber. Periksa koneksimu.';

  @override
  String get searchSpotifyCardTitle => 'Buka playlist Spotify';

  @override
  String get searchEmpty => 'Ketik untuk mencari di katalog.';

  @override
  String get searchRecent => 'Terakhir dicari';

  @override
  String get searchClearAll => 'Hapus semua';

  @override
  String get searchClearQuery => 'Hapus kata kunci';

  @override
  String get searchNoResults => 'Tidak ditemukan. Coba kata kunci lain.';

  @override
  String get searchResultsLabel => 'Hasil cari';

  @override
  String get searchSongs => 'Lagu';

  @override
  String get searchAlbums => 'Album';

  @override
  String get searchArtists => 'Artis';

  @override
  String get searchPlaylists => 'Playlist';

  @override
  String get searchAll => 'Semua';

  @override
  String get collectionTitle => 'Koleksi';

  @override
  String get collectionSortRecent => 'Terbaru disimpan';

  @override
  String get collectionFilterHint => 'Saring koleksimu…';

  @override
  String get collectionPlaylists => 'Playlist';

  @override
  String get collectionDownloads => 'Unduhan';

  @override
  String get collectionLocalFiles => 'File Lokal';

  @override
  String collectionSavedCount(int count) {
    return '$count lagu tersimpan';
  }

  @override
  String get collectionEmptyPlaylists =>
      'Belum ada playlist. Buat satu dengan tombol + di bawah.';

  @override
  String get collectionGoSearch => 'Cari lagu';

  @override
  String get collectionEmptySaved =>
      'Belum ada lagu tersimpan. Ketuk hati pada lagu mana pun — dari baris lagu atau Player.';

  @override
  String get collectionNewPlaylistName => 'Nama playlist baru';

  @override
  String get contentUnavailable => 'Konten tidak tersedia.';

  @override
  String get contentLoadFail => 'Tidak dapat memuat halaman ini dari sumber.';

  @override
  String get contentShuffle => 'Acak';

  @override
  String contentShuffleContext(Object title) {
    return '$title (acak)';
  }

  @override
  String get contentPopular => 'Lagu populer';

  @override
  String get contentDiscography => 'Diskografi';

  @override
  String get contentSimilar => 'Artis serupa';

  @override
  String contentCountLine(int count, Object duration) {
    return '$count lagu · $duration';
  }

  @override
  String plRemovedSnack(Object title) {
    return 'Dihapus dari playlist: $title';
  }

  @override
  String get plRename => 'Ganti nama';

  @override
  String get plNewName => 'Nama baru';

  @override
  String get plDelete => 'Hapus playlist';

  @override
  String get plDeleteTitle => 'Hapus playlist?';

  @override
  String get plDeleteBody =>
      'Playlist dihapus permanen dari perangkat ini. Lagu-lagunya sendiri tidak ikut terhapus.';

  @override
  String get plEmpty =>
      'Playlist ini masih kosong. Tambahkan lagu dari menu konteks lagu mana pun.';

  @override
  String get spTitle => 'Playlist Spotify';

  @override
  String get spUnavailable => 'Playlist tidak tersedia.';

  @override
  String get spLoadFail =>
      'Tidak dapat memuat playlist Spotify. Periksa koneksimu.';

  @override
  String get spMeta =>
      'Metadata: Spotify (tanpa akun) • Audio: hasil pencocokan katalog';

  @override
  String get spPlayMatched => 'Putar yang cocok';

  @override
  String spMatching(int matched, int total) {
    return 'Mencocokkan… $matched dari $total lagu';
  }

  @override
  String spMatched(int matched, int total) {
    return '$matched dari $total lagu tercocokkan';
  }

  @override
  String get spNoneMatched => 'Belum ada lagu yang tercocokkan.';

  @override
  String spSkippedItems(int count) {
    return '$count item non-lagu (mis. episode) dilewati.';
  }

  @override
  String get spHuge => 'Playlist sangat besar — ditampilkan 1000 lagu pertama.';

  @override
  String spContext(Object name) {
    return 'Spotify • $name';
  }

  @override
  String spOwnerLine(int count, Object owner) {
    return '$owner • $count lagu';
  }

  @override
  String get spNotFound => 'Lagu ini tidak ditemukan di katalog.';

  @override
  String get spNotFoundRetry =>
      'Lagu ini tidak ditemukan di katalog — ketuk label \"Tak cocok\" untuk mencoba lagi.';

  @override
  String get spMatchingThis => 'Sedang mencocokkan lagu ini…';

  @override
  String get spNoMatch => 'Tak cocok';

  @override
  String get spPlayWhileMatching =>
      'Pencocokan sedang berjalan — putar lagi sesaat.';

  @override
  String get localTitle => 'File Lokal';

  @override
  String get localScan => 'Pindai file lokal';

  @override
  String get localRescan => 'Pindai ulang';

  @override
  String get localDenied =>
      'Izin audio ditolak. File lokal tidak dapat dipindai tanpa izin itu.';

  @override
  String get localNone =>
      'Tidak ada berkas audio ≥ 30 detik ditemukan di perangkat.';

  @override
  String localCount(int count) {
    return '$count berkas audio di perangkat';
  }

  @override
  String get dlTitle => 'Unduhan';

  @override
  String get dlEmpty =>
      'Belum ada unduhan. Unduh lagu dari menu ⋯ di baris lagu mana pun.';

  @override
  String get dlFailed => 'Unduhan gagal.';

  @override
  String get dlRetry => 'Ulangi';

  @override
  String dlProgressOf(Object done, Object tot) {
    return '$done / $tot';
  }

  @override
  String dlProgressDone(Object done) {
    return '$done diunduh…';
  }

  @override
  String get capGateTitle => 'Model pembaca teks belum diunduh';

  @override
  String get capGateBody =>
      'Tangkap dari gambar membaca daftar lagu dari tangkapan layar atau foto. Model pembacanya (±4 MB) sengaja tidak ikut di dalam APK agar aplikasi tetap ramping — unduh sekali dari GitHub Releases, sesudah itu membaca gambar bekerja offline penuh. Tangkap lewat tautan tidak membutuhkannya sama sekali.';

  @override
  String get capVerifying => 'Memeriksa keutuhan berkas…';

  @override
  String get capDownloadModel => 'Unduh model';

  @override
  String get capRetryDownload => 'Coba unduh lagi';

  @override
  String get capTitle => 'Tangkapan';

  @override
  String get capFromOtherApp => 'Tangkapan dari aplikasi lain';

  @override
  String capFrom(Object label) {
    return 'Dari: $label';
  }

  @override
  String get capNotFound => 'Tidak ditemukan.';

  @override
  String capPlayAll(int count) {
    return 'Putar semua yang ditemukan ($count)';
  }

  @override
  String get capAddAll => 'Tambah semua ke antrean';

  @override
  String get capMatching => 'Mencocokkan… item muncul satu per satu.';

  @override
  String get capMatchingShort => 'Mencocokkan…';

  @override
  String get capImageList => 'Gambar daftar lagu';

  @override
  String get lyrTitle => 'Lirik';

  @override
  String get lyrNoTrack => 'Tidak ada lagu yang sedang diputar.';

  @override
  String get lyrInstrumental =>
      'Lagu ini instrumental — memang tidak ada liriknya.';

  @override
  String get lyrNotFound => 'Lirik tidak ditemukan di LRCLIB untuk lagu ini.';

  @override
  String get lyrNetError => 'Tidak dapat memeriksa lirik — koneksi bermasalah.';

  @override
  String get lyrSource =>
      'Sumber lirik: LRCLIB (lrclib.net) — tersimpan lokal sesudah ditemukan.';

  @override
  String get lyrPlainNote => 'Lirik tersedia tanpa sinkronisasi waktu.';

  @override
  String lyrTrackLine(Object artist, Object title) {
    return '$title — $artist';
  }

  @override
  String get sleepTitle => 'Timer tidur';

  @override
  String sleepSubMinutes(Object remaining) {
    return 'Timer aktif — $remaining. Volume memudar halus di bentang akhir, lalu musik jeda.';
  }

  @override
  String get sleepSubEndOfSong =>
      'Timer aktif — musik berhenti di akhir lagu yang sedang berjalan (memudar di bentang akhirnya).';

  @override
  String sleepMinutes(int m) {
    return '$m menit';
  }

  @override
  String get sleepEndOfSong => 'Akhir lagu ini';

  @override
  String get sleepCancel => 'Batalkan timer';

  @override
  String sleepRemaining(Object time) {
    return 'Sisa $time';
  }

  @override
  String get voiceTitle => 'Antrean Suara';

  @override
  String get voiceHintIdle => 'Ketuk mikrofon, atau ketik perintah di bawah.';

  @override
  String get voiceListening => 'Mendengarkan… ketuk mikrofon untuk berhenti.';

  @override
  String get voiceMicDenied =>
      'Izin mikrofon ditolak — ketik perintah di bawah.';

  @override
  String get voiceExamples =>
      'Coba: \"putar [judul]\", \"lewati\", \"jeda\", \"lanjut\".';

  @override
  String get voiceInputHint => 'Ketik perintah (simulasi suara)…';

  @override
  String get voiceSend => 'Kirim';

  @override
  String get voiceSearching => 'Mencari…';

  @override
  String get voiceWhichOne => 'Yang mana maksudmu?';

  @override
  String get drvExit => 'Keluar';

  @override
  String get drvNoSong => 'Tidak ada lagu';

  @override
  String get vcDisconnected =>
      'Pengenal suara terputus — ketik perintah di bawah.';

  @override
  String vcFailed(Object error) {
    return 'Pengenal suara gagal ($error) — ketik perintah di bawah.';
  }

  @override
  String get vcAnswerChoice =>
      'Jawab \"yang pertama\" atau \"yang kedua\", atau \"batal\".';

  @override
  String get vcCancelled => 'Baik, dibatalkan.';

  @override
  String get vcUnclear => 'Maaf, saya kurang jelas — bisa diulangi?';

  @override
  String get vcStopped => 'Baik, saya berhenti mendengarkan.';

  @override
  String get vcUnknown =>
      'Maaf, perintah tidak dikenali. Coba: putar [judul lagu].';

  @override
  String get vcSkipped => 'Dilewati.';

  @override
  String get vcPaused => 'Dijeda.';

  @override
  String get vcResumed => 'Dilanjutkan.';

  @override
  String get vcSayTitle =>
      'Sebut judul lagunya — misalnya: putar [judul lagu].';

  @override
  String vcNotFound(Object query) {
    return 'Tidak ditemukan lagu untuk \"$query\".';
  }

  @override
  String vcNoMatch(Object query) {
    return 'Tidak ditemukan lagu yang cocok untuk \"$query\".';
  }

  @override
  String vcWhich(Object a1, Object a2, Object t1, Object t2) {
    return 'Maksudmu $t1 — $a1, atau $t2 — $a2?';
  }

  @override
  String get vcSearchFailed =>
      'Pencarian gagal — periksa jaringan lalu coba lagi.';

  @override
  String vcPlaying(Object artist, Object title) {
    return 'Memutar $title — $artist.';
  }

  @override
  String vcAddedNext(Object artist, Object title) {
    return 'Menambahkan $title — $artist setelah lagu ini.';
  }

  @override
  String vcAddedQueue(Object artist, Object title) {
    return 'Menambahkan $title — $artist ke antrean.';
  }

  @override
  String get vcContextLabel => 'Suara';

  @override
  String get diagTitle => 'Diagnostik Putar';

  @override
  String get diagRun => 'Jalankan Diagnostik';

  @override
  String get diagRunClients => 'Uji Klien InnerTube';

  @override
  String get diagPlayWinner => 'Bukti Putar Klien';

  @override
  String get diagRunPoToken => 'Uji PoToken';

  @override
  String get diagRunCrossing => 'Uji Penyeberangan F3';

  @override
  String get diagRunDecipher => 'Uji Decipher F3';

  @override
  String get diagRunSabr => 'Uji SABR F3';

  @override
  String get diagRunSabrCeiling => 'Uji Plafon SABR';

  @override
  String get diagRunWebView => 'Probe WebView Tamu';

  @override
  String get diagOpenLoginLab => 'Lab Login';

  @override
  String get diagRunLogin => 'Matriks L (Login)';

  @override
  String get diagRunTahap2 => 'Matriks U (Tahap 2)';

  @override
  String get diagRunning => 'Berjalan…';

  @override
  String get diagCopy => 'Salin Laporan';

  @override
  String get diagCopied => 'Laporan disalin.';

  @override
  String get diagEmpty => 'Belum ada laporan. Ketuk \"Jalankan Diagnostik\".';

  @override
  String get updNoReleases => 'Belum ada rilis resmi yang diterbitkan.';

  @override
  String get updBadShape => 'Bentuk data rilis tidak dikenal.';

  @override
  String get updVersionUnreadable =>
      'Versi terpasang tidak terbaca di perangkat ini.';

  @override
  String updAvailableMsg(Object version) {
    return 'Versi $version tersedia.';
  }

  @override
  String get updUpToDate => 'Clai sudah versi terbaru.';

  @override
  String updCheckFailedHttp(int code) {
    return 'Pemeriksaan gagal (HTTP $code).';
  }

  @override
  String get updCheckFailed =>
      'Tidak dapat memeriksa pembaruan. Periksa koneksimu.';

  @override
  String updNoApk(Object tag) {
    return 'Rilis $tag tidak membawa berkas APK.';
  }

  @override
  String get updWaitingWifi =>
      'Pembaruan tersedia — unduhan otomatis menunggu Wi-Fi.';

  @override
  String get updAlreadyDownloaded =>
      'Pembaruan sudah terunduh — siap dipasang.';

  @override
  String get updDownloadDone => 'Unduhan selesai — siap dipasang.';

  @override
  String get updDownloadFailed =>
      'Unduhan gagal. Coba lagi saat koneksi stabil.';

  @override
  String get updFollowSystem =>
      'Ikuti konfirmasi sistem untuk menyelesaikan pemasangan.';

  @override
  String get updInstallPermMsg =>
      'Android belum mengizinkan Clai memasang aplikasi. Izinkan \"pasang aplikasi tak dikenal\" untuk Clai, lalu coba lagi.';

  @override
  String get updInstallFailed =>
      'Pemasangan gagal di sistem. Berkas unduhan tetap tersimpan — coba lagi.';

  @override
  String get ocrMsgInstalled =>
      'Model terpasang — Tangkap gambar bekerja offline.';

  @override
  String get ocrMsgNotDownloaded =>
      'Model pembaca teks belum diunduh (sekali saja, ±4 MB).';

  @override
  String get ocrMsgDeleted =>
      'Model dihapus. Tangkap gambar akan menawarkannya lagi.';

  @override
  String get ocrMsgContacting => 'Menghubungi GitHub Releases…';

  @override
  String ocrErrFeed(int code) {
    return 'Umpan rilis tidak dapat dibaca (HTTP $code).';
  }

  @override
  String get ocrErrNoModel => 'Rilis tidak membawa model OCR.';

  @override
  String get ocrErrManifestEmpty => 'Manifest model kosong.';

  @override
  String get ocrErrManifestUnknown => 'Manifest model tidak dikenal.';

  @override
  String ocrErrAssetMissing(Object file) {
    return 'Aset model $file tidak ada di rilis.';
  }

  @override
  String ocrMsgDownloading(Object version) {
    return 'Mengunduh model ($version)…';
  }

  @override
  String get ocrMsgChecksumFail =>
      'Checksum tidak cocok — berkas dibuang sebelum sempat dipakai. Coba unduh lagi.';

  @override
  String get ocrMsgInstalledReady =>
      'Model terpasang — Tangkap gambar siap dipakai, termasuk offline.';

  @override
  String get ocrMsgDownloadFailed =>
      'Unduhan gagal. Periksa koneksimu lalu coba lagi.';

  @override
  String get capSvcModelMissing => 'Model pembaca teks belum diunduh.';

  @override
  String get capSvcNoText => 'Tidak ada teks terbaca dari gambar ini.';

  @override
  String get capSvcNoLines => 'Tidak ada baris teks terbaca dari gambar.';

  @override
  String get capSvcModelMissingLong =>
      'Model pembaca teks belum diunduh. Unduh sekali (panel di atas atau Pengaturan → Tangkap), sesudah itu gambar dibaca offline.';

  @override
  String get capSvcTitleUnreadable => 'Judul halaman tidak dapat dibaca.';

  @override
  String capSvcSpotifySummary(Object name) {
    return 'Playlist Spotify: $name';
  }

  @override
  String capSvcYtSummary(Object title) {
    return 'Daftar putar: $title';
  }

  @override
  String get capSvcNoAudioMatch => 'Tidak tercocokkan ke audio.';

  @override
  String get capSvcMatchFailed => 'Pencocokan gagal.';

  @override
  String get capSvcPlaylistNotFound =>
      'Playlist tidak ditemukan atau tidak publik.';

  @override
  String get capSvcMetaUnreadable => 'Metadata lagu tidak dapat dibaca.';

  @override
  String get capSvcPlaylistLoadFail => 'Playlist tidak dapat dimuat.';

  @override
  String get capSvcVideoMetaUnreadable => 'Metadata video tidak dapat dibaca.';

  @override
  String get capSvcNotFound => 'Tidak ditemukan.';

  @override
  String get capSvcNoGoodMatch => 'Tidak ada yang cukup cocok.';

  @override
  String get capSvcSearchFailed => 'Pencarian gagal.';

  @override
  String get spErrServerTime => 'Waktu server Spotify tidak terbaca.';

  @override
  String get spErrTokenRejected =>
      'Token web Spotify ditolak — skema token mungkin sudah dirotasi Spotify.';

  @override
  String spErrUnreachable(Object type) {
    return 'Tidak dapat menjangkau Spotify: $type';
  }

  @override
  String get spErrHashRotated =>
      'Skema kueri Spotify berubah (hash persisted ditolak) — fitur playlist Spotify perlu diperbarui.';

  @override
  String spErrHttp(int code) {
    return 'Spotify menjawab HTTP $code.';
  }

  @override
  String get spErrShape => 'Bentuk respons Spotify berubah.';

  @override
  String spErrQueryRejected(Object msg) {
    return 'Spotify menolak kueri: $msg';
  }

  @override
  String get spErrShapeV2 =>
      'Bentuk respons Spotify berubah (playlistV2 hilang).';

  @override
  String noticeOfflineHidden(int count) {
    return 'Mode offline: $count lagu streaming disembunyikan dari antrean.';
  }

  @override
  String noticePrepareFail(Object what) {
    return 'Tidak dapat menyiapkan pemutaran $what. Periksa koneksi lalu ketuk putar lagi.';
  }

  @override
  String get noticeQueueEnded =>
      'Antrean habis — tidak ada sambungan tersedia.';

  @override
  String get noticeOfflineNonePlayable =>
      'Mode offline aktif — tidak ada lagu yang bisa diputar offline dalam daftar ini.';

  @override
  String noticeOfflineSkipped(int count) {
    return 'Mode offline: $count lagu dilewati (belum diunduh).';
  }

  @override
  String noticeOfflineNotDownloaded(Object title) {
    return 'Mode offline aktif — \"$title\" belum diunduh.';
  }

  @override
  String noticeSkippedUnplayable(Object title) {
    return 'Melewatkan \"$title\" — tidak dapat diputar dari sumber.';
  }

  @override
  String get noticeAutoStop =>
      'Berhenti otomatis: 3 lagu gagal berturut-turut.';

  @override
  String noticeTryingOtherPath(Object title) {
    return 'Mencoba jalur putar lain untuk \"$title\"…';
  }

  @override
  String get dlErrFileMissing => 'Berkas unduhan tidak ditemukan di perangkat.';

  @override
  String get dlErrTimeout => 'Waktu unduh habis.';

  @override
  String get dlErrNoConnection => 'Tidak ada koneksi.';

  @override
  String dlErrSourceRefused(int code) {
    return 'Sumber menolak unduhan (HTTP $code).';
  }

  @override
  String drvAnnounceNext(Object artist, Object title) {
    return 'Berikutnya: $title — $artist';
  }

  @override
  String get startupStarting => 'Memulai…';

  @override
  String get startupDb => 'Menyiapkan basis data…';

  @override
  String get startupSource => 'Menyiapkan sumber musik…';

  @override
  String get startupPlayer => 'Menyiapkan pemutar…';

  @override
  String get startupPrefs => 'Memulihkan preferensi…';

  @override
  String get startupServices => 'Menyiapkan layanan…';

  @override
  String get startupFailedTitle => 'Clai gagal mulai';

  @override
  String startupFailedStep(Object step) {
    return 'Langkah yang gagal: $step';
  }

  @override
  String get startupRetry => 'Coba Lagi';

  @override
  String get startupReportCopied =>
      'Laporan tersalin — tempel & kirim ke pengembang.';

  @override
  String capSvcFromLink(Object title) {
    return '$title (dari tautan)';
  }

  @override
  String get ctxPreviousSession => 'Sesi sebelumnya';

  @override
  String get notifLike => 'Sukai';

  @override
  String get notifUnlike => 'Sudah disukai';

  @override
  String get dlErrCorrupt => 'Berkas unduhan rusak (checksum tidak cocok).';

  @override
  String get dlErrQuotaFull =>
      'Kuota unduhan penuh — hapus unduhan lama atau naikkan kuota di Pengaturan.';

  @override
  String get dlErrStorageFull => 'Penyimpanan perangkat penuh.';

  @override
  String get dlPause => 'Jeda';

  @override
  String get dlResume => 'Lanjutkan';

  @override
  String get dlPauseAll => 'Jeda Semua';

  @override
  String get dlResumeAll => 'Lanjutkan Semua';

  @override
  String get dlRedownload => 'Unduh Ulang';

  @override
  String dlPausedState(Object done, Object total) {
    return 'Dijeda · $done dari $total';
  }

  @override
  String dlUsageLine(Object used) {
    return 'Terpakai $used';
  }

  @override
  String get dlQuotaLabel => 'Kuota unduhan';

  @override
  String get dlQuotaUnlimited => 'Tanpa batas';

  @override
  String dlQuotaGb(int gb) {
    return '$gb GB';
  }

  @override
  String get setDataSaver => 'Mode hemat data';

  @override
  String get setDataSaverCellularBlock =>
      'Kualitas Tinggi dicegah: mode hemat data aktif dan perangkat memakai jaringan seluler.';

  @override
  String get setFocusBehavior => 'Saat aplikasi lain berbunyi sebentar';

  @override
  String get focusDuck => 'Turunkan volume (duck)';

  @override
  String get focusPause => 'Jeda, lanjut otomatis sesudahnya';

  @override
  String get setHistoryRetention => 'Simpan riwayat putar selama';

  @override
  String histDays(int days) {
    return '$days hari';
  }

  @override
  String get histForever => 'Selamanya';

  @override
  String playerBitrate(int kbps) {
    return '$kbps kbps';
  }

  @override
  String get a11yPlay => 'Putar';

  @override
  String get a11yPause => 'Jeda';

  @override
  String get a11yNext => 'Lagu berikutnya';

  @override
  String get a11yPrevious => 'Lagu sebelumnya';

  @override
  String get a11yShuffle => 'Acak';

  @override
  String get a11yRepeat => 'Ulangi';

  @override
  String get a11yLike => 'Sukai';

  @override
  String get a11yUnlike => 'Batalkan suka';

  @override
  String get a11yClosePlayer => 'Tutup pemutar';

  @override
  String get a11yOpenPlayer => 'Buka pemutar';

  @override
  String get a11yTrackOptions => 'Opsi lagu';

  @override
  String get a11ySeek => 'Posisi putar';

  @override
  String get a11ySettings => 'Pengaturan';

  @override
  String get a11ySort => 'Urutkan';

  @override
  String get contentSave => 'Simpan ke Koleksi';

  @override
  String get contentSaved => 'Tersimpan di Koleksi';

  @override
  String get contentDownloadAll => 'Unduh Semua';

  @override
  String get contentShare => 'Bagikan';

  @override
  String get contentFromCache =>
      'Menampilkan salinan tersimpan — sumber sedang tak terjangkau.';

  @override
  String get collectionAlbums => 'Album';

  @override
  String get collectionArtists => 'Artis';

  @override
  String get collectionEmptyAlbums =>
      'Belum ada album tersimpan. Simpan dari halaman album.';

  @override
  String get collectionEmptyArtists =>
      'Belum ada artis tersimpan. Simpan dari halaman artis.';

  @override
  String get searchSuggestions => 'Saran';

  @override
  String get eqPresetFlat => 'Datar';

  @override
  String get eqPresetBass => 'Bass';

  @override
  String get eqPresetVocal => 'Vokal';

  @override
  String get eqPresetAcoustic => 'Akustik';

  @override
  String get eqNamedPresets => 'Preset Clai';

  @override
  String get setSamsung => 'Samsung';

  @override
  String get setSamsungSub =>
      'Pengaturan → Baterai → Batas penggunaan latar → jangan masukkan Clai ke aplikasi tidur/tidur nyenyak.';

  @override
  String get setOppo => 'Oppo / vivo';

  @override
  String get setOppoSub =>
      'Aktifkan mulai-otomatis (autostart) untuk Clai dan kunci aplikasi di layar terbaru (recents) agar tidak dibersihkan sistem.';

  @override
  String get setHuawei => 'Huawei / Honor';

  @override
  String get setHuaweiSub =>
      'Pengaturan → Baterai → Peluncuran aplikasi → Clai → kelola manual: aktifkan mulai-otomatis, peluncuran sekunder, dan jalan di latar.';

  @override
  String get noticeRegionUnavailable =>
      'Konten ini tidak tersedia di wilayahmu.';

  @override
  String get diagGatesTitle => 'Gerbang kualitas sesi ini (PRD Bab 3)';

  @override
  String diagGateCold(int ms) {
    return 'Mulai dingin terakhir: $ms ms';
  }

  @override
  String diagGateTap(int median, int n, int p95) {
    return 'Ketuk→bunyi: median $median ms · p95 $p95 ms · $n sampel';
  }

  @override
  String diagGateFail(int attempts, int failures, Object pct) {
    return 'Percobaan putar: $attempts · gagal $failures ($pct%)';
  }

  @override
  String diagBreathLine(String text) {
    return 'Napas (U1): $text';
  }

  @override
  String diagWaveformLine(String text) {
    return 'Waveform: $text';
  }

  @override
  String get diagGateNone => 'Belum ada sampel sesi ini.';

  @override
  String get a11yClose => 'Tutup';

  @override
  String contentDownloadQueued(int count) {
    return '$count lagu diantrekan untuk diunduh.';
  }

  @override
  String get contentPlaylistCopied => 'Playlist disalin ke koleksimu.';

  @override
  String get queueDragReorder => 'Seret untuk mengurutkan';

  @override
  String get ocrMsgNotPublished =>
      'Model belum tersedia — unduhan aktif setelah rilis resmi pertama Clai diterbitkan.';

  @override
  String get ocrMsgNoModelInRelease =>
      'Rilis terbaru belum membawa model pembaca teks — unduhan aktif setelah model diterbitkan di rilis.';

  @override
  String get ocrCheckAgain => 'Periksa Lagi';

  @override
  String get artistNotFound => 'Artis tidak ditemukan';

  @override
  String get contentDownloaded => 'Terunduh';

  @override
  String contentDownloadingCount(int done, int total) {
    return '$done/$total';
  }

  @override
  String get homeContinue => 'Lanjutkan';

  @override
  String get setThemeDynamic => 'Tema Dinamis';

  @override
  String get setAmbientStrength => 'Kekuatan Ambien';

  @override
  String get ambientCalm => 'Tenang';

  @override
  String get ambientLively => 'Hidup';

  @override
  String get setAmbientBreathing => 'Ambien Bernapas';

  @override
  String get setReduceEffects => 'Kurangi Efek';

  @override
  String get setGreetingName => 'Nama sapaan';

  @override
  String get greetingNameHint => 'Nama kamu';

  @override
  String get searchChartsKicker => 'Charts · Minggu Ini';

  @override
  String get searchMoodGenreKicker => 'Mood & Genre';

  @override
  String collectionStats(int songs, int playlists) {
    return '$songs lagu · $playlists playlist · semua milikmu';
  }

  @override
  String get collectionLikedSongs => 'Lagu yang Disukai';

  @override
  String get collectionAutoPlaylist => 'Playlist otomatis';

  @override
  String collectionDownloadsMeta(int count, String size) {
    return '$count lagu · $size di perangkat';
  }

  @override
  String collectionDownloadsMetaActive(int count, String size, int active) {
    return '$count lagu · $size di perangkat · $active sedang diunduh';
  }

  @override
  String collectionLocalMeta(int count) {
    return '$count berkas di perangkat ini';
  }

  @override
  String get collectionYourArtists => 'Artis Kamu';

  @override
  String get collectionLastPlayedToday => 'terakhir diputar hari ini';

  @override
  String get collectionLastPlayedYesterday => 'terakhir diputar kemarin';

  @override
  String collectionLastPlayedDays(int days) {
    return 'terakhir diputar $days hari lalu';
  }

  @override
  String collectionLastPlayedWeeks(int weeks) {
    return 'terakhir diputar $weeks minggu lalu';
  }

  @override
  String collectionLastPlayedMonths(int months) {
    return 'terakhir diputar $months bulan lalu';
  }

  @override
  String collectionLastPlayedYears(int years) {
    return 'terakhir diputar $years tahun lalu';
  }

  @override
  String collectionStatsFull(int songs, int playlists, int artists) {
    return '$songs lagu · $playlists playlist · $artists artis';
  }

  @override
  String get collectionLastPlayedKicker => 'Terakhir Diputar';

  @override
  String get collectionYours => 'Milikmu';

  @override
  String get radioKicker => 'Radio Lagu';

  @override
  String get radioSeedCaption => 'Dari lagu ini';

  @override
  String get radioResults => 'Hasil Radio';

  @override
  String get radioComposing => 'Menyusun radio…';

  @override
  String get catalogWord => 'Katalog';

  @override
  String get spNoCatalog => 'Tidak ada di katalog';

  @override
  String get spSectionTracks => 'Trek';

  @override
  String get dlSectionDownloaded => 'Terunduh';

  @override
  String dlStorageUsedBy(int count) {
    return 'dipakai oleh $count lagu unduhan';
  }

  @override
  String get localFormatsFound => 'format ditemukan';

  @override
  String get localScanning => 'Memindai…';

  @override
  String get localScanningCaption => 'Memindai folder musik…';

  @override
  String get collectionAll => 'Semua';

  @override
  String get spKicker => 'Playlist Spotify';

  @override
  String get localOnDevice => 'berkas di perangkat ini';

  @override
  String get localScanHeadline => 'Folder musik perangkatmu';

  @override
  String get localResults => 'Hasil Pindai';

  @override
  String get setSectionFlow => 'Alur Putar';

  @override
  String get setSectionDeviceGuides => 'Panduan Perangkat';

  @override
  String get a11yBack => 'Kembali';

  @override
  String get lyrCreditShort => 'Sumber lirik: LRCLIB (lrclib.net)';

  @override
  String get commonClose => 'Tutup';

  @override
  String get groupOwnership => 'Kepemilikan';

  @override
  String get ownSectionData => 'Data kamu';

  @override
  String get ownSectionShare => 'Bagikan & terima';

  @override
  String get ownExportTitle => 'Ekspor data';

  @override
  String get ownExportSub =>
      'Simpan playlist, lagu disukai & riwayat ke satu berkas';

  @override
  String get ownImportTitle => 'Impor data';

  @override
  String get ownImportSub => 'Pulihkan dari berkas ekspor Clai';

  @override
  String get ownShareTitle => 'Bagikan playlist';

  @override
  String get ownShareSub => 'Kirim satu playlist lewat kode QR atau berkas';

  @override
  String get ownReceiveTitle => 'Terima playlist';

  @override
  String get ownReceiveSub => 'Pindai kode QR dari Clai temanmu';

  @override
  String get ownSectionSessions => 'Sesi tersimpan';

  @override
  String get ownVaultSub =>
      'Sesi putar tersimpan yang bisa dipulihkan kapan saja';

  @override
  String ownPlaylistsCount(int count) {
    return '$count playlist';
  }

  @override
  String ownLikedCount(int count) {
    return '$count lagu disukai';
  }

  @override
  String ownHistoryCount(int count) {
    return '$count riwayat putar';
  }

  @override
  String get exportIncludeHistory => 'Sertakan riwayat putar';

  @override
  String get exportAction => 'Ekspor & bagikan';

  @override
  String get exportM3uSection => 'Playlist sebagai M3U';

  @override
  String get exportEmpty => 'Belum ada data untuk diekspor';

  @override
  String get exportFailed => 'Ekspor gagal. Coba lagi.';

  @override
  String importFromFile(Object name) {
    return 'Berkas: $name';
  }

  @override
  String get importModeMerge => 'Gabungkan';

  @override
  String get importModeReplace => 'Ganti semua';

  @override
  String importSumNewPlaylists(int count) {
    return '$count playlist baru ditambahkan';
  }

  @override
  String importSumMergedPlaylists(int count) {
    return '$count playlist digabungkan ke yang sudah ada';
  }

  @override
  String importSumTracksAdded(int count) {
    return '$count lagu ditambahkan ke playlist';
  }

  @override
  String importSumLikedAdded(int count) {
    return '$count lagu disukai ditambahkan';
  }

  @override
  String importSumHistoryAdded(int count) {
    return '$count riwayat putar ditambahkan';
  }

  @override
  String get importApplyMerge => 'Gabungkan sekarang';

  @override
  String get importApplyReplace => 'Ganti semua…';

  @override
  String get importSuccess => 'Impor selesai';

  @override
  String get importNothingNew =>
      'Tidak ada yang baru — semua isi berkas sudah ada di sini';

  @override
  String get importReplaceTitle => 'Ganti semua data?';

  @override
  String get importReplaceBody =>
      'Playlist, lagu disukai, dan riwayat putar kamu sekarang akan dihapus lalu diganti isi berkas ini. Tindakan ini tidak bisa dibatalkan.';

  @override
  String get importFailTitle => 'Berkas tidak bisa diimpor';

  @override
  String get importFailNotJson =>
      'Isi berkas ini bukan berkas ekspor Clai yang bisa dibaca.';

  @override
  String get importFailUnrecognized =>
      'Berkas ini bukan ekspor Clai. Pilih berkas hasil Ekspor data dari Clai.';

  @override
  String importFailNewer(Object version) {
    return 'Berkas ini dibuat oleh Clai yang lebih baru (format $version) dan tidak bisa dibaca versi ini. Perbarui Clai lalu coba lagi.';
  }

  @override
  String get importFailCorrupt =>
      'Berkas ekspor ini rusak atau tidak lengkap, jadi tidak ada yang diterapkan.';

  @override
  String get importFailTooBig =>
      'Berkas ini terlalu besar untuk diimpor (maks 20 MB).';

  @override
  String get shareTooBigForQr =>
      'Playlist ini terlalu besar untuk kode QR — bagikan sebagai berkas saja.';

  @override
  String get shareFileAction => 'Bagikan berkas';

  @override
  String get sharePickPlaylist => 'Pilih playlist';

  @override
  String get shareNoPlaylists => 'Belum ada playlist untuk dibagikan';

  @override
  String get scanTitle => 'Pindai kode QR';

  @override
  String get scanImportFile => 'Impor dari berkas';

  @override
  String scanFoundSub(int count) {
    return '$count lagu · dari kode QR';
  }

  @override
  String get scanImportAction => 'Impor playlist';

  @override
  String get scanAgain => 'Pindai lagi';

  @override
  String get scanNotClai => 'Kode ini bukan bagikan playlist Clai';

  @override
  String scanImported(Object name) {
    return 'Playlist \"$name\" ditambahkan';
  }

  @override
  String get scanPermDenied => 'Izin kamera diperlukan untuk memindai';

  @override
  String get scanPermDeniedSub =>
      'Aktifkan izin kamera, atau terima playlist lewat berkas.';

  @override
  String get scanOpenSettings => 'Buka pengaturan aplikasi';

  @override
  String shareFoundFileSub(int count) {
    return '$count lagu · dari berkas';
  }

  @override
  String get scanUnavailable => 'Kamera tidak tersedia di perangkat ini';

  @override
  String get shareQrImageAction => 'Bagikan gambar QR';

  @override
  String get shareQrCardFooter => 'Pindai kode ini dari Clai';

  @override
  String get scanPickImage => 'Pilih gambar QR';

  @override
  String get scanImageNoQr => 'Tidak ada kode QR yang terbaca di gambar itu';

  @override
  String get scanImageUnreadable => 'Gambar itu tidak bisa dibaca';

  @override
  String shareLocalExcluded(int count) {
    return '$count lagu lokal tidak ikut';
  }

  @override
  String scanResolving(int done, int total) {
    return 'Membangun ulang lagu dari katalog… $done dari $total';
  }

  @override
  String get scanRefsNoneFound =>
      'Tidak ada lagu yang ditemukan di katalog — periksa koneksimu, atau lagu-lagu ini sudah tidak tersedia.';

  @override
  String scanSkippedCount(int count) {
    return '$count lagu tidak ditemukan di katalog dan dilewati';
  }

  @override
  String scanImportedSkips(Object name, int count) {
    return 'Playlist \"$name\" ditambahkan · $count lagu dilewati';
  }

  @override
  String get vaultTitle => 'Brankas Sesi';

  @override
  String get vaultSaveAction => 'Simpan sesi';

  @override
  String get vaultSaveTitle => 'Simpan ke Brankas Sesi';

  @override
  String get vaultNameLabel => 'Nama sesi';

  @override
  String get vaultSavedSnack => 'Sesi tersimpan di Brankas';

  @override
  String get vaultEmptyTitle => 'Belum ada sesi tersimpan';

  @override
  String get vaultSaveCurrent => 'Simpan antrean saat ini';

  @override
  String get vaultRestore => 'Pulihkan sesi';

  @override
  String get vaultRestoreBody =>
      'Antrean yang sekarang akan digantikan oleh sesi ini, dan sesi akan diputar dari titik berhentinya. Sesi tetap tersimpan di Brankas sesudah dipulihkan.';

  @override
  String get vaultRestoredSnack => 'Sesi dipulihkan';

  @override
  String get vaultRestoreFailed =>
      'Sesi ini tidak bisa dipulihkan — lagunya sudah tidak ada di katalog lokal.';

  @override
  String get vaultDeleteTitle => 'Hapus sesi?';

  @override
  String vaultDeleteBody(Object name) {
    return 'Sesi \"$name\" akan dihapus permanen dari Brankas.';
  }

  @override
  String get vaultSeeAll => 'Lihat semua';

  @override
  String get vaultPlayedSection => 'Sudah diputar';

  @override
  String get vaultCurrentBadge => 'Berhenti di sini';

  @override
  String get groupTaste => 'Selera';

  @override
  String get groupTasteSum =>
      'Cermin selera, mode samaran, keluarkan dari rekomendasi, dan reset selera';

  @override
  String get tasteBalanceLifetime => 'Seumur';

  @override
  String get tasteBalanceRecent => '30 hari terakhir';

  @override
  String get tasteBalanceTitle => 'Keseimbangan selera';

  @override
  String get tasteDayFri => 'Jum';

  @override
  String get tasteDayMon => 'Sen';

  @override
  String get tasteDaySat => 'Sab';

  @override
  String get tasteDaySun => 'Min';

  @override
  String get tasteDayThu => 'Kam';

  @override
  String get tasteDayTue => 'Sel';

  @override
  String get tasteDayWed => 'Rab';

  @override
  String get tasteDaypartDiniHari => 'dini hari';

  @override
  String get tasteDaypartMalam => 'malam';

  @override
  String get tasteDaypartPagi => 'pagi';

  @override
  String get tasteDaypartSiang => 'siang';

  @override
  String get tasteDaypartSore => 'sore';

  @override
  String get tasteExcludeAction => 'Keluarkan';

  @override
  String get tasteExcludeEmpty => 'Belum ada yang dikeluarkan.';

  @override
  String get tasteExcludeTitle => 'Keluarkan dari Rekomendasi';

  @override
  String tasteExcludedDone(Object name) {
    return '$name dikeluarkan dari rekomendasi';
  }

  @override
  String get tasteExportFirst => 'Ekspor dulu';

  @override
  String tasteGenreEstimate(Object tags) {
    return 'Perkiraan genre · MusicBrainz: $tags';
  }

  @override
  String get tasteKindArtist => 'Artis';

  @override
  String get tasteKindTrack => 'Lagu';

  @override
  String get tasteMirrorEmpty =>
      'Selera kamu belum terbentuk. Dengarkan beberapa lagu dulu.';

  @override
  String get tasteMirrorTitle => 'Cermin Selera';

  @override
  String get tastePatternsTitle => 'Pola mendengar';

  @override
  String tastePeakDaypart(Object label) {
    return 'Paling sering mendengar: $label';
  }

  @override
  String get tastePickArtists => 'Dari artis teratasmu';

  @override
  String get tastePickTracks => 'Dari lagu yang sering diputar';

  @override
  String tastePlaysCount(int count) {
    return '$count putar';
  }

  @override
  String tasteResetBackup(Object date) {
    return 'Cadangan terakhir: $date';
  }

  @override
  String get tasteResetConfirm => 'Reset selera';

  @override
  String get tasteResetDone => 'Selera sudah direset';

  @override
  String get tasteResetNoBackup => 'Cadangan terakhir: belum ada';

  @override
  String get tasteResetSheetBody =>
      'Riwayat putar, pengecualian rekomendasi, dan bobot rekomendasi akan dihapus permanen. Perpustakaan, playlist, unduhan, Brankas Sesi, dan lagu yang kamu sukai TIDAK ikut terhapus.';

  @override
  String get tasteResetSheetTitle => 'Reset selera kamu?';

  @override
  String get tasteResetTitle => 'Reset Selera';

  @override
  String get tasteSamaranPill => 'Samaran';

  @override
  String get tasteSamaranTitle => 'Mode Samaran';

  @override
  String get tasteTitle => 'Selera kamu';

  @override
  String get tasteTopArtists => 'Artis teratas';

  @override
  String get tasteUndo => 'Urungkan';

  @override
  String get tasteWeightLifetime => 'Seumur';

  @override
  String get tasteWeightRecent => 'Terkini';

  @override
  String get tasteWeightsTitle => 'Bobot rekomendasi';

  @override
  String get shufflePanelTitle => 'Acak';

  @override
  String get shufflePanelWhy =>
      'Setiap lagu diputar sekali sebelum ada yang berulang. Urutan di bawah adalah urutan putar yang sebenarnya.';

  @override
  String get shuffleSmartSub => 'Sebar artis & utamakan yang jarang diputar';

  @override
  String shuffleCycleProgress(int done, int total) {
    return '$done dari $total sudah diputar dalam siklus ini';
  }

  @override
  String get shuffleReshuffle => 'Acak ulang';

  @override
  String get shuffleOrderTitle => 'Urutan putar berikutnya';

  @override
  String get shuffleCardOffSub => 'Mati — lagu mengikuti urutan aslinya';

  @override
  String get setShuffle => 'Acak';

  @override
  String get menuButtonLabel => 'Menu';

  @override
  String get menuTasteSub => 'Cermin selera, mode samaran & rekomendasi';

  @override
  String get menuVaultSub => 'Antrean yang kamu simpan untuk nanti';

  @override
  String get menuOwnershipSub => 'Ekspor, impor, bagikan & terima playlist';

  @override
  String get menuSettingsSub => 'Tampilan, pemutaran, audio & lainnya';

  @override
  String announceKicker(Object version) {
    return 'BARU DI CLAI $version';
  }

  @override
  String get announceTitle => 'Yang baru di Clai';

  @override
  String get announceStart => 'Mulai';

  @override
  String get announceCtaVault => 'Buka Brankas Sesi';

  @override
  String get announceCtaShare => 'Bagikan playlist';

  @override
  String get announceCtaTaste => 'Lihat Selera kamu';

  @override
  String get announceCtaShuffle => 'Buka Panel Acak';

  @override
  String announceMoreCount(int count) {
    return 'dan $count hal baru lainnya';
  }

  @override
  String patchInstalledTitle(Object version) {
    return 'Clai $version sudah terpasang';
  }

  @override
  String get patchInstalledSub => 'Perbaikan kecil di balik layar';

  @override
  String get patchInstalledSee => 'Lihat';

  @override
  String get samaranHowTitle => 'Cara kerja Mode Samaran';

  @override
  String get samaranHowRowHistory =>
      'Yang kamu dengarkan tidak masuk Riwayat putar.';

  @override
  String get samaranHowRowTaste =>
      'Tidak memengaruhi Cermin Selera & rekomendasi.';

  @override
  String get samaranHowRowListenBrainz => 'Tidak dikirim ke ListenBrainz.';

  @override
  String get samaranHowRowNoLimit =>
      'Tetap aktif sampai kamu mematikannya sendiri — tidak ada batas waktu.';

  @override
  String get samaranHowDontShow => 'Jangan tampilkan lagi';

  @override
  String get samaranHowActivate => 'Aktifkan Samaran';
}
