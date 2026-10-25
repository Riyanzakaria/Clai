// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Clai';

  @override
  String get navHome => 'Home';

  @override
  String get navSearch => 'Search';

  @override
  String get navLibrary => 'Library';

  @override
  String get offlineBarText => 'Offline mode — downloads & local files only';

  @override
  String get eqTitle => 'Equalizer';

  @override
  String get eqChecking => 'Checking device support…';

  @override
  String get eqUnavailable =>
      'Equalizer is not available on this device — the Android Equalizer effect refused to be created on the live player session. Technical details are recorded in the Incident log (Settings → Local Diagnostics).';

  @override
  String get eqSubtitle =>
      'Shapes Clai\'s audio only (attached to the player session, not system audio).';

  @override
  String get eqWaitingSession =>
      'Start playing a song so the EQ can be applied to the audio session; settings are saved and applied automatically when a song starts.';

  @override
  String get eqPreset => 'Preset';

  @override
  String get eqCustom => 'Custom';

  @override
  String eqBandLabel(Object db, Object freq) {
    return '$freq — $db dB';
  }

  @override
  String get ocrModelTitle => 'Text reader model (Capture image)';

  @override
  String ocrModelInstalled(Object size, Object versionPart) {
    return 'Installed · $size$versionPart — image reading works offline.';
  }

  @override
  String ocrModelVersionPart(Object version) {
    return ' · $version';
  }

  @override
  String commonDownloadingPct(int pct) {
    return 'Downloading… $pct%';
  }

  @override
  String get ocrModelVerifying => 'Verifying file integrity (checksum)…';

  @override
  String get ocrModelNotDownloaded =>
      'Not downloaded yet. Downloaded once from GitHub Releases (±4 MB), stored on the device, then Capture image works offline. Capture via link doesn\'t need it.';

  @override
  String get ocrModelDeleteTitle => 'Delete the text reader model?';

  @override
  String get ocrModelDeleteBody =>
      'Capture image will offer the download again next time it\'s used. Songs, the queue, and song downloads are unaffected.';

  @override
  String get commonCancel => 'Cancel';

  @override
  String get commonDelete => 'Delete';

  @override
  String get commonRetry => 'Try again';

  @override
  String get commonDownload => 'Download';

  @override
  String get updateCheck => 'Check for updates';

  @override
  String get commonChecking => 'Checking…';

  @override
  String get updateInstalling => 'Handing over to the system installer…';

  @override
  String get updateTapToCheck => 'Tap to check for the latest release.';

  @override
  String updateInstalledLabel(Object label, Object status) {
    return 'Installed: $label · $status';
  }

  @override
  String updateDownloadTag(Object tag) {
    return 'Download $tag';
  }

  @override
  String get updateDownloadSub =>
      'The APK is downloaded inside the app, then installed through Android\'s system confirmation.';

  @override
  String get updateInstall => 'Install update';

  @override
  String get updateInstallSub =>
      'The file is downloaded. Installation shows a system confirmation — that\'s an Android limit, not Clai\'s choice.';

  @override
  String get updateAutoCheck => 'Automatic checks';

  @override
  String get updateAutoCheckSub =>
      'At most once a day, public requests to GitHub only — no user data.';

  @override
  String get updateAutoDownload => 'Auto-update (download in background)';

  @override
  String get updateAutoDownloadSub =>
      'New releases download themselves; installation still goes through Android\'s system confirmation.';

  @override
  String get updateWifiOnly => 'Download on Wi-Fi only';

  @override
  String get updateWifiOnlySub =>
      'Automatic downloads wait for Wi-Fi; manual downloads can still use mobile data.';

  @override
  String get updateInstallPermTitle => 'Install permission not granted';

  @override
  String get updateInstallPermSub =>
      'Android requires the \"install unknown apps\" permission before Clai can install its own updates.';

  @override
  String updateBannerTitle(Object version) {
    return 'Clai $version is available';
  }

  @override
  String get updateBannerReady =>
      'Downloaded — just install it through the system confirmation.';

  @override
  String get updateBannerDefault =>
      'Download inside the app, install through the system confirmation.';

  @override
  String get commonInstall => 'Install';

  @override
  String get commonLater => 'Later';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get groupPlayback => 'Playback';

  @override
  String get groupPlaybackSum =>
      'Quality, Autoplay, Smart Shuffle, transitions';

  @override
  String get groupAudio => 'Audio';

  @override
  String get groupAudioSum => 'Equalizer & loudness normalization';

  @override
  String get groupDownloads => 'Downloads & Offline';

  @override
  String get groupDownloadsSum => 'Offline mode & downloaded songs';

  @override
  String get groupAppearance => 'Appearance';

  @override
  String get groupAppearanceSum => 'Accent color from song artwork';

  @override
  String get groupDriving => 'Driving';

  @override
  String get groupDrivingSum => 'Big screen & simple controls while driving';

  @override
  String get groupCapture => 'Capture';

  @override
  String get groupCaptureSum => 'Links/images from other apps become a queue';

  @override
  String get groupBackground => 'Background Playback';

  @override
  String get groupBackgroundSum => 'Notification & battery permissions';

  @override
  String get groupData => 'Data & Storage';

  @override
  String get groupDataSum => 'Stream cache & play history';

  @override
  String get groupUpdates => 'Updates';

  @override
  String get groupUpdatesSum => 'Installed version & new GitHub releases';

  @override
  String get groupListenBrainzSum => 'Optional scrobbling with your own token';

  @override
  String get groupDiagnostics => 'Diagnostics';

  @override
  String get groupDiagnosticsSum =>
      'Playback chain test & on-device incident log';

  @override
  String get groupAbout => 'About';

  @override
  String get groupAboutSum => 'Version, license, and how Clai works';

  @override
  String get setQuality => 'Streaming quality';

  @override
  String get qualityLow => 'Low · ≤70 kbps';

  @override
  String get qualityNormal => 'Normal · ≤160 kbps';

  @override
  String get qualityHigh => 'High · best available (source max ≈256 kbps)';

  @override
  String get setAutoplay => 'Autoplay';

  @override
  String get setAutoplaySub =>
      'Continues with related songs when the queue ends.';

  @override
  String get setSmartShuffle => 'Smart Shuffle';

  @override
  String get setSmartShuffleSub =>
      'Reorders Up Next only; never adds new songs.';

  @override
  String get setAutoResume => 'Resume automatically after interruptions';

  @override
  String get setAutoResumeSub => 'E.g. after a phone call ends.';

  @override
  String get setTransition => 'Transition mode';

  @override
  String get setTransitionSub => 'Applies from the next song boundary.';

  @override
  String get transitionSnack => 'The new mode applies from the next song.';

  @override
  String get setCrossfadeDur => 'Crossfade duration';

  @override
  String crossfadeDurVal(Object secs) {
    return '$secs seconds — range 1–12 seconds.';
  }

  @override
  String get playbackFootnote =>
      'Gapless joins songs with no gap. Crossfade fades out the end of a song as the next one comes in (equal-power, no silent gap). Switching modes never cuts the song that\'s playing (ADR-002).';

  @override
  String get setNormalization => 'Loudness normalization';

  @override
  String get setNormalizationSub =>
      'Evens out song loudness from real playback measurements.';

  @override
  String get normMicSnack =>
      'Without microphone permission, Android\'s Visualizer may not measure — every song\'s gain stays neutral. The permission is only for measuring levels, never recording.';

  @override
  String get audioFootnote =>
      'Song loudness is measured from real playback (Visualizer), stored per song, and applied from the next play — songs never measured use a neutral gain.';

  @override
  String get setOfflineMode => 'Offline mode';

  @override
  String get setOfflineModeSub => 'Only downloaded songs & local files play.';

  @override
  String get setManageDownloads => 'Manage downloads';

  @override
  String get setManageDownloadsSub =>
      'List, progress, play, and delete downloaded songs.';

  @override
  String get downloadsFootnote =>
      'Turning on offline mode filters the running queue without cutting the song that\'s playing; Autoplay continuation becomes \"limited — offline\".';

  @override
  String get setDynamicAccent => 'Dynamic cover accent';

  @override
  String get setDynamicAccentSub =>
      'Artwork color tints the Player background & the Home card.';

  @override
  String get appearanceFootnote =>
      'The tint comes from the current artwork\'s signature color and stays dark; the play button & status indicators are always Volt.';

  @override
  String get languageTitle => 'Language';

  @override
  String get languageSub => 'System default or a manual choice.';

  @override
  String get languageSystem => 'System';

  @override
  String get captureLinkTitle => 'Capture link/text';

  @override
  String get captureLinkSub => 'Paste a playlist/song link or a keyword.';

  @override
  String get captureHint => 'Paste a link or type a keyword…';

  @override
  String get captureAction => 'Capture';

  @override
  String get setBgStatus => 'Background permission status';

  @override
  String bgStatusLine(Object battery, Object notif) {
    return 'Notifications: $notif · Battery: $battery';
  }

  @override
  String get bgPermGranted => 'Allowed';

  @override
  String get bgPermNotYet => 'Not yet';

  @override
  String get bgBatteryExempt => 'Exempt from optimization';

  @override
  String get bgBatteryNotYet => 'Not allowed yet';

  @override
  String get setAllow => 'Allow';

  @override
  String get setAllowSub => 'Request both permissions via system dialogs.';

  @override
  String get setXiaomi => 'Xiaomi / HyperOS';

  @override
  String get setXiaomiSub =>
      'Enable \"Auto-start\", battery \"No restrictions\".';

  @override
  String get setOtherBrands => 'Other brands';

  @override
  String get setOtherBrandsSub =>
      'Samsung: don\'t put Clai in \"Sleeping apps\".';

  @override
  String get backgroundFootnote =>
      'If background playback is still killed by the system despite permission on Xiaomi/HyperOS: open Clai\'s App info, enable \"Auto-start\" and set Battery to \"No restrictions\" — those two switches only exist on the system page; Android doesn\'t let apps change them for you. Oppo/Vivo: allow background activity in the brand\'s battery manager.';

  @override
  String get setClearCache => 'Clear stream cache';

  @override
  String get setClearCacheSub =>
      'Stream URLs are discarded; fetched again when played.';

  @override
  String get cacheClearedSnack => 'Stream cache cleared.';

  @override
  String get setClearHistory => 'Clear play history';

  @override
  String get setClearHistorySub =>
      'History lives only on this device and is yours.';

  @override
  String get historyClearedSnack => 'Play history cleared.';

  @override
  String get setDiagTitle => 'Playback Diagnostics';

  @override
  String get setDiagSub => 'Test the playback chain and copy its report.';

  @override
  String get setLogTitle => 'Incident log (on device)';

  @override
  String setLogCount(int count) {
    return '$count entries — never sent anywhere.';
  }

  @override
  String get aboutVersion => 'Clai 1.0.0';

  @override
  String get aboutBody =>
      'An open-source music player (GPL-3.0), built clean-room: no code or assets from other services. The catalogue and songs come from a third-party music service through an unofficial API — declared openly in the repo README; the provider architecture lets other sources be added without touching the player. You can also paste a public playlist link from another music app: its track list is read, then matched to the catalogue here — no account needed. Lyrics from LRCLIB; artwork enrichment from MusicBrainz/Cover Art Archive; optional scrobbling to ListenBrainz with your own token. All your personal data — library, history, downloads — lives only on your phone.';

  @override
  String get logTitle => 'Incident log';

  @override
  String get logEmpty => 'No incidents recorded yet.';

  @override
  String get groupListenBrainz => 'ListenBrainz';

  @override
  String get drvMode => 'Driving Mode';

  @override
  String get drvModeSub =>
      'Giant touch surface + audio controls. Turning it on opens its screen.';

  @override
  String get drvScheme => 'Control scheme';

  @override
  String get drvSchemeSub =>
      'Standard media buttons (default) / single-button press patterns (1× play-pause, 2× next, 3× previous) / voice commands.';

  @override
  String get drvSchemeButtons => 'Media buttons';

  @override
  String get drvSchemePatterns => 'Press patterns';

  @override
  String get drvSchemeVoice => 'Voice commands';

  @override
  String get drvAnnounce => 'Voice announcements';

  @override
  String get drvAnnounceSub =>
      'The next song\'s title is read aloud (TTS) before it plays (off by default).';

  @override
  String get drvSpeedVolume => 'Speed-based volume';

  @override
  String get drvSpeedVolumeSub =>
      'Needs location permission. Volume only moves between the two points below; poor GPS = volume freezes.';

  @override
  String get drvVolStop => 'Volume when stopped';

  @override
  String get drvVolFast => 'Volume at full speed';

  @override
  String drvVolFastSub(int pct) {
    return '$pct% — the ceiling, never exceeded.';
  }

  @override
  String drvVolPct(int pct) {
    return '$pct%';
  }

  @override
  String get drvAnchor => 'Anchor speed';

  @override
  String drvAnchorSub(int kmh) {
    return '$kmh km/h — at this speed the volume reaches its fastest point.';
  }

  @override
  String get drvVehicles => 'Vehicle devices (Bluetooth)';

  @override
  String get drvVehiclesHint =>
      'Tap to load paired devices — marked ones trigger Driving Mode automatically when connected.';

  @override
  String get drvVehiclesNone =>
      'No Bluetooth devices are paired with this device.';

  @override
  String drvVehiclesCount(int count) {
    return '$count paired devices.';
  }

  @override
  String get drvMarkVehicle => 'Mark as vehicle';

  @override
  String get lbTitle => 'Send listening history to ListenBrainz';

  @override
  String get lbSub =>
      'Optional and off by default. What\'s sent: title, artist, album, and listening time — to your own ListenBrainz account.';

  @override
  String get lbTokenLabel => 'ListenBrainz user token';

  @override
  String get lbTokenHint => 'From listenbrainz.org → Settings → User Token';

  @override
  String get lbTokenValid => 'Token valid — saved.';

  @override
  String get lbTokenInvalid => 'Token invalid or a network problem.';

  @override
  String get lbSaveCheck => 'Save & check token';

  @override
  String get lbSafeTitle => 'Send failures never interrupt playback';

  @override
  String get lbSafeSub =>
      'Scrobbles are sent in the background after a song finishes playing (≥30 seconds). The token is stored only on this device.';

  @override
  String get greetMorning => 'Good morning';

  @override
  String get greetAfternoon => 'Good afternoon';

  @override
  String get greetEvening => 'Good evening';

  @override
  String get greetNight => 'Good night';

  @override
  String get homeBgCardTitle => 'So the system doesn\'t kill the music';

  @override
  String get homeBgCardSub =>
      'Background permissions aren\'t complete yet. Without them, some phones stop playback when the screen turns off.';

  @override
  String get homeSetupNow => 'Set up now';

  @override
  String get homeEmptyTitle => 'What do you want to hear today?';

  @override
  String get homeEmptySub =>
      'Find your first song — after that, Autoplay keeps it going.';

  @override
  String get homeSearchSong => 'Search songs';

  @override
  String get homeUpNext => 'Up Next';

  @override
  String get homeOpenQueue => 'Open Queue';

  @override
  String get homeRecent => 'Recently Played';

  @override
  String get homePlayAgain => 'Play Again';

  @override
  String get homeYourCollection => 'Your Collection';

  @override
  String get homeSavedSongs => 'Saved Songs';

  @override
  String songCount(int count) {
    return '$count songs';
  }

  @override
  String shelfBecauseArtist(Object artist) {
    return 'Because you often play $artist';
  }

  @override
  String get shelfRarelyPlayed => 'Saved but rarely played';

  @override
  String get jelajahTitle => 'Explore';

  @override
  String get jelajahYtmHome => 'Home';

  @override
  String get jelajahCharts => 'Charts';

  @override
  String get jelajahArtists => 'Artists';

  @override
  String get jelajahLoadFail => 'Explore can\'t be loaded right now.';

  @override
  String jelajahShelfFail(Object source) {
    return 'The $source shelf failed to load.';
  }

  @override
  String get jelajahLoading => 'Loading discovery shelves…';

  @override
  String jelajahShelfTitle(Object title) {
    return 'Explore • $title';
  }

  @override
  String get sleepCardTitle => 'Continue from last night';

  @override
  String sleepCardSub(Object artist, Object pos, Object title) {
    return '$title — $artist · from $pos';
  }

  @override
  String get sleepCardResume => 'Resume';

  @override
  String get sleepContextLabel => 'Resume Tomorrow';

  @override
  String get playerNowPlaying => 'Now Playing';

  @override
  String get playerEmpty => 'No song has been played yet.';

  @override
  String get playerBuffering => 'Buffering…';

  @override
  String get commonLoading => 'Loading…';

  @override
  String get playerLyrics => 'Lyrics';

  @override
  String get queueTitle => 'Queue';

  @override
  String get playerTimer => 'Timer';

  @override
  String get playerVoice => 'Voice';

  @override
  String get playerAutoplayCard =>
      'Autoplay is on — when this context ends, Clai continues with related songs. The music doesn\'t stop midway.';

  @override
  String get queueSmartShuffleNote =>
      'Smart Shuffle — reorders Up Next (artists spread out, favorites pushed up). Never adds new songs.';

  @override
  String get queueEmpty => 'The queue is empty. Play a song to start.';

  @override
  String get queueNowPlaying => 'Now Playing';

  @override
  String get queueUpNext => 'Up Next';

  @override
  String queueContinuation(Object label) {
    return 'Up Next — $label';
  }

  @override
  String get queueContextFallback => 'context';

  @override
  String queueCountLine(int count) {
    return '$count tracks';
  }

  @override
  String queueCountLineDur(int count, Object duration, Object totalPart) {
    return '$count tracks · $duration$totalPart';
  }

  @override
  String queueTotalPart(Object plus) {
    return '$plus total';
  }

  @override
  String queueRemovedSnack(Object title) {
    return 'Removed: $title';
  }

  @override
  String get commonUndo => 'Undo';

  @override
  String get queueClear => 'Clear queue';

  @override
  String get queueFilterHint => 'Filter this queue…';

  @override
  String get queueAutoplayOff =>
      'Autoplay is off in Settings — when the context ends, playback stops.';

  @override
  String queueAutoplayHeader(Object seed) {
    return 'Autoplay — because you played $seed';
  }

  @override
  String get queueAutoplayLimited =>
      'limited — offline: continuation only from songs you\'ve downloaded.';

  @override
  String get queuePreparing =>
      'Preparing continuation from this session\'s seed songs…';

  @override
  String get queueContinuationReady =>
      'Continuation is ready from this session\'s seed songs.';

  @override
  String get queueContinuationPending =>
      'Continuation isn\'t available yet (slow network?). Music will continue as soon as it\'s ready.';

  @override
  String get queueAutoBadge => 'AUTO';

  @override
  String get ctxPlayNext => 'Play Next';

  @override
  String get ctxAddToQueue => 'Add to Queue';

  @override
  String get ctxStartRadio => 'Start Song Radio';

  @override
  String get ctxRemoveFromCollection => 'Remove from Collection';

  @override
  String get ctxSaveToCollection => 'Save to Collection';

  @override
  String get ctxAddToPlaylist => 'Add to Playlist';

  @override
  String get ctxDeleteDownload => 'Delete download';

  @override
  String get ctxOpenAlbum => 'Open Album';

  @override
  String get ctxOpenArtist => 'Open Artist';

  @override
  String get ctxShare => 'Share';

  @override
  String ctxShareText(Object artist, Object title) {
    return 'Listen to \"$title\" — $artist on Clai';
  }

  @override
  String get ctxRemoveFromQueue => 'Remove from Queue';

  @override
  String get ctxNewPlaylist => 'New playlist';

  @override
  String get ctxPlaylistName => 'Playlist name';

  @override
  String get ctxAlreadyInPlaylist => 'Already in playlist';

  @override
  String get ctxAlreadyInPlaylistBody =>
      'This song is already in that playlist. Add it anyway as a duplicate?';

  @override
  String get ctxSkip => 'Skip';

  @override
  String get ctxAddAnyway => 'Add anyway';

  @override
  String get commonSave => 'Save';

  @override
  String get searchHint => 'Search songs, albums, artists…';

  @override
  String get searchSpotifyOnlySnack =>
      'Only Spotify PLAYLIST links are supported — paste its public playlist link.';

  @override
  String get searchSourceBroken =>
      'The source is having trouble — its data shape changed. This isn\'t your connection\'s fault.';

  @override
  String get searchNetworkError =>
      'Can\'t reach the source. Check your connection.';

  @override
  String get searchSpotifyCardTitle => 'Open a Spotify playlist';

  @override
  String get searchSpotifyCardSub =>
      'Paste a public Spotify playlist link in the search field above — no account needed, songs are matched to the catalogue.';

  @override
  String get searchEmpty =>
      'Type to search the catalogue.\nResults appear as you type.';

  @override
  String get searchRecent => 'Recent searches';

  @override
  String get searchClearAll => 'Clear all';

  @override
  String get searchNoResults =>
      'Not found. Try another keyword — this isn\'t a network failure, there simply are no results.';

  @override
  String get searchResultsLabel => 'Search results';

  @override
  String get searchSongs => 'Songs';

  @override
  String get searchAlbums => 'Albums';

  @override
  String get searchArtists => 'Artists';

  @override
  String get searchPlaylists => 'Playlists';

  @override
  String get searchAll => 'All';

  @override
  String get collectionTitle => 'Library';

  @override
  String get collectionSortRecent => 'Recently saved';

  @override
  String get collectionFilterHint => 'Filter your library…';

  @override
  String get collectionPlaylists => 'Playlists';

  @override
  String get collectionDownloads => 'Downloads';

  @override
  String get collectionLocalFiles => 'Local Files';

  @override
  String collectionSavedCount(int count) {
    return '$count saved songs';
  }

  @override
  String get collectionEmptyPlaylists =>
      'No playlists yet. Create one with the + button below.';

  @override
  String get collectionEmptySaved =>
      'No saved songs yet. Tap the heart on any song — from a song row or the Player.';

  @override
  String get collectionNewPlaylistName => 'New playlist name';

  @override
  String get contentUnavailable => 'Content is not available.';

  @override
  String get contentLoadFail => 'Can\'t load this page from the source.';

  @override
  String get contentShuffle => 'Shuffle';

  @override
  String contentShuffleContext(Object title) {
    return '$title (shuffle)';
  }

  @override
  String get contentPopular => 'Popular songs';

  @override
  String get contentDiscography => 'Discography';

  @override
  String get contentSimilar => 'Similar artists';

  @override
  String contentCountLine(int count, Object duration) {
    return '$count songs · $duration';
  }

  @override
  String plRemovedSnack(Object title) {
    return 'Removed from playlist: $title';
  }

  @override
  String get plRename => 'Rename';

  @override
  String get plNewName => 'New name';

  @override
  String get plDelete => 'Delete playlist';

  @override
  String get plDeleteTitle => 'Delete playlist?';

  @override
  String get plDeleteBody =>
      'The playlist is permanently deleted from this device. Its songs themselves are not deleted.';

  @override
  String get plEmpty =>
      'This playlist is still empty. Add songs from any song\'s context menu.';

  @override
  String get spTitle => 'Spotify Playlist';

  @override
  String get spUnavailable => 'Playlist is not available.';

  @override
  String get spLoadFail =>
      'Can\'t load the Spotify playlist. Check your connection.';

  @override
  String get spMeta =>
      'Metadata: Spotify (no account) • Audio: catalogue matches';

  @override
  String get spPlayMatched => 'Play matched';

  @override
  String spMatching(int matched, int total) {
    return 'Matching… $matched of $total songs';
  }

  @override
  String spMatched(int matched, int total) {
    return '$matched of $total songs matched';
  }

  @override
  String get spNoneMatched => 'No songs matched yet.';

  @override
  String spSkippedItems(int count) {
    return '$count non-song items (e.g. episodes) skipped.';
  }

  @override
  String get spHuge => 'Very large playlist — showing the first 1000 songs.';

  @override
  String spContext(Object name) {
    return 'Spotify • $name';
  }

  @override
  String spOwnerLine(int count, Object owner) {
    return '$owner • $count songs';
  }

  @override
  String get spNotFound => 'This song wasn\'t found in the catalogue.';

  @override
  String get spNotFoundRetry =>
      'This song wasn\'t found in the catalogue — tap the \"No match\" badge to try again.';

  @override
  String get spMatchingThis => 'Matching this song…';

  @override
  String get spNoMatch => 'No match';

  @override
  String get spPlayWhileMatching =>
      'Matching is still running — try playing again in a moment.';

  @override
  String get localTitle => 'Local Files';

  @override
  String get localScan => 'Scan local files';

  @override
  String get localRescan => 'Rescan';

  @override
  String get localSub =>
      'Scan your device\'s music folders. Local files are equal to streaming songs in the queue & playlists.';

  @override
  String get localDenied =>
      'Audio permission denied. Local files can\'t be scanned without it.';

  @override
  String get localNone => 'No audio files ≥ 30 seconds found on this device.';

  @override
  String localCount(int count) {
    return '$count audio files on this device';
  }

  @override
  String get dlTitle => 'Downloads';

  @override
  String get dlEmpty =>
      'No downloads yet. Download a song from the ⋯ menu on any song row — downloaded songs play without a network.';

  @override
  String get dlFailed => 'Download failed.';

  @override
  String get dlRetry => 'Retry';

  @override
  String dlProgressOf(Object done, Object tot) {
    return '$done / $tot';
  }

  @override
  String dlProgressDone(Object done) {
    return '$done downloaded…';
  }

  @override
  String get dlFootnote =>
      'Files live in the app\'s private storage. Downloads can be paused and resumed from the last byte; a full cancel deletes the partial file.';

  @override
  String get capGateTitle => 'Text reader model not downloaded';

  @override
  String get capGateBody =>
      'Capture from image reads a song list from a screenshot or photo. Its reader model (±4 MB) is deliberately not inside the APK so the app stays slim — download it once from GitHub Releases, after that image reading works fully offline. Capture via link doesn\'t need it at all.';

  @override
  String get capVerifying => 'Verifying file integrity…';

  @override
  String get capDownloadModel => 'Download model';

  @override
  String get capRetryDownload => 'Try downloading again';

  @override
  String get capTitle => 'Capture';

  @override
  String get capFromOtherApp => 'Capture from another app';

  @override
  String capFrom(Object label) {
    return 'From: $label';
  }

  @override
  String get capNotFound => 'Not found.';

  @override
  String capPlayAll(int count) {
    return 'Play everything found ($count)';
  }

  @override
  String get capAddAll => 'Add all to queue';

  @override
  String get capMatching => 'Matching… items appear one by one.';

  @override
  String get capMatchingShort => 'Matching…';

  @override
  String get capImageList => 'Image of a song list';

  @override
  String get lyrTitle => 'Lyrics';

  @override
  String get lyrNoTrack => 'No song is playing.';

  @override
  String get lyrInstrumental => 'This song is instrumental — it has no lyrics.';

  @override
  String get lyrNotFound => 'Lyrics not found on LRCLIB for this song.';

  @override
  String get lyrNetError => 'Can\'t check lyrics — connection problem.';

  @override
  String get lyrSource =>
      'Lyrics source: LRCLIB (lrclib.net) — stored locally once found.';

  @override
  String get lyrPlainNote => 'Lyrics available without time sync.';

  @override
  String lyrTrackLine(Object artist, Object title) {
    return '$title — $artist';
  }

  @override
  String get sleepTitle => 'Sleep timer';

  @override
  String get sleepSubOff =>
      'Music stops on its own — then you can resume tomorrow from the same position.';

  @override
  String sleepSubMinutes(Object remaining) {
    return 'Timer active — $remaining left. When it fires, the volume fades for 5 seconds, then the music pauses.';
  }

  @override
  String get sleepSubEndOfSong =>
      'Timer active — music stops at the end of the current song (fades for 5 seconds).';

  @override
  String sleepMinutes(int m) {
    return '$m minutes';
  }

  @override
  String get sleepEndOfSong => 'End of this song';

  @override
  String get sleepCancel => 'Cancel timer';

  @override
  String sleepRemaining(Object time) {
    return '$time left';
  }

  @override
  String get voiceTitle => 'Voice Queue';

  @override
  String get voiceHintIdle => 'Tap the microphone, or type a command below.';

  @override
  String get voiceListening => 'Listening… tap the microphone to stop.';

  @override
  String get voiceMicDenied =>
      'Microphone permission denied — type a command below.';

  @override
  String get voiceExamples =>
      'Try: \"play [song title]\", \"add [title] after this\", \"skip\", \"pause\", \"resume\".';

  @override
  String get voiceInputHint => 'Type a command (voice simulation)…';

  @override
  String get voiceSend => 'Send';

  @override
  String get voiceSearching => 'Searching…';

  @override
  String get voiceWhichOne => 'Which one do you mean?';

  @override
  String get drvExit => 'Exit';

  @override
  String get drvSwipeHint => 'Swipe left/right anywhere for next/previous.';

  @override
  String get drvNoSong => 'No song';

  @override
  String get drvAnnounceSubShort =>
      'The next song\'s title is read aloud before it plays.';

  @override
  String get drvSpeedVolumeNote =>
      'Volume only moves between the two points you calibrated in Settings.';

  @override
  String get vcDisconnected =>
      'Speech recognizer disconnected — type a command below.';

  @override
  String vcFailed(Object error) {
    return 'Speech recognizer failed ($error) — type a command below.';
  }

  @override
  String get vcAnswerChoice =>
      'Answer \"the first\" or \"the second\", or \"cancel\".';

  @override
  String get vcCancelled => 'OK, cancelled.';

  @override
  String get vcUnclear => 'Sorry, I didn\'t catch that — could you repeat it?';

  @override
  String get vcStopped => 'OK, I\'ll stop listening.';

  @override
  String get vcUnknown =>
      'Sorry, command not recognized. Try: play [song title].';

  @override
  String get vcSkipped => 'Skipped.';

  @override
  String get vcPaused => 'Paused.';

  @override
  String get vcResumed => 'Resumed.';

  @override
  String get vcSayTitle =>
      'Say the song title — for example: play [song title].';

  @override
  String vcNotFound(Object query) {
    return 'No song found for \"$query\".';
  }

  @override
  String vcNoMatch(Object query) {
    return 'No matching song found for \"$query\".';
  }

  @override
  String vcWhich(Object a1, Object a2, Object t1, Object t2) {
    return 'Did you mean $t1 — $a1, or $t2 — $a2?';
  }

  @override
  String get vcSearchFailed =>
      'Search failed — check your network and try again.';

  @override
  String vcPlaying(Object artist, Object title) {
    return 'Playing $title — $artist.';
  }

  @override
  String vcAddedNext(Object artist, Object title) {
    return 'Adding $title — $artist after this song.';
  }

  @override
  String vcAddedQueue(Object artist, Object title) {
    return 'Adding $title — $artist to the queue.';
  }

  @override
  String get vcContextLabel => 'Voice';

  @override
  String get diagTitle => 'Playback Diagnostics';

  @override
  String get diagIntro =>
      'Tests the playback chain link by link (resolution → download → plain ExoPlayer → +headers → muxed → app path → local pipeline) for a Song track & a Video item, including native errors from the process logcat. The result is one text report — copy & send it to the developer if a song won\'t play.';

  @override
  String get diagRun => 'Run Diagnostics';

  @override
  String get diagRunning => 'Running…';

  @override
  String get diagCopy => 'Copy Report';

  @override
  String get diagCopied => 'Report copied.';

  @override
  String get diagEmpty => 'No report yet. Tap \"Run Diagnostics\".';

  @override
  String get updNoReleases => 'No official release has been published yet.';

  @override
  String get updBadShape => 'Unknown release data shape.';

  @override
  String get updVersionUnreadable =>
      'The installed version can\'t be read on this device.';

  @override
  String updAvailableMsg(Object version) {
    return 'Version $version is available.';
  }

  @override
  String get updUpToDate => 'Clai is already up to date.';

  @override
  String updCheckFailedHttp(int code) {
    return 'Check failed (HTTP $code).';
  }

  @override
  String get updCheckFailed =>
      'Can\'t check for updates. Check your connection.';

  @override
  String updNoApk(Object tag) {
    return 'Release $tag has no APK file.';
  }

  @override
  String get updWaitingWifi =>
      'Update available — automatic download is waiting for Wi-Fi.';

  @override
  String get updAlreadyDownloaded =>
      'Update already downloaded — ready to install.';

  @override
  String get updDownloadDone => 'Download complete — ready to install.';

  @override
  String get updDownloadFailed =>
      'Download failed. Try again on a stable connection.';

  @override
  String get updFollowSystem =>
      'Follow the system confirmation to finish installing.';

  @override
  String get updInstallPermMsg =>
      'Android hasn\'t allowed Clai to install apps yet. Allow \"install unknown apps\" for Clai, then try again.';

  @override
  String get updInstallFailed =>
      'Installation failed in the system. The downloaded file is kept — try again.';

  @override
  String get ocrMsgInstalled =>
      'Model installed — Capture image works offline.';

  @override
  String get ocrMsgNotDownloaded =>
      'Text reader model not downloaded yet (one time only, ±4 MB).';

  @override
  String get ocrMsgDeleted =>
      'Model deleted. Capture image will offer it again.';

  @override
  String get ocrMsgContacting => 'Contacting GitHub Releases…';

  @override
  String ocrErrFeed(int code) {
    return 'The release feed can\'t be read (HTTP $code).';
  }

  @override
  String get ocrErrNoModel => 'The release carries no OCR model.';

  @override
  String get ocrErrManifestEmpty => 'The model manifest is empty.';

  @override
  String get ocrErrManifestUnknown => 'Unknown model manifest.';

  @override
  String ocrErrAssetMissing(Object file) {
    return 'Model asset $file is not in the release.';
  }

  @override
  String ocrMsgDownloading(Object version) {
    return 'Downloading model ($version)…';
  }

  @override
  String get ocrMsgChecksumFail =>
      'Checksum mismatch — the file was discarded before it could be used. Try downloading again.';

  @override
  String get ocrMsgInstalledReady =>
      'Model installed — Capture image is ready, including offline.';

  @override
  String get ocrMsgDownloadFailed =>
      'Download failed. Check your connection and try again.';

  @override
  String get capSvcModelMissing => 'Text reader model not downloaded.';

  @override
  String get capSvcNoText => 'No readable text in this image.';

  @override
  String get capSvcNoLines => 'No readable text lines in the image.';

  @override
  String get capSvcModelMissingLong =>
      'Text reader model not downloaded. Download it once (panel above or Settings → Capture), then images are read offline.';

  @override
  String get capSvcTitleUnreadable => 'The page title can\'t be read.';

  @override
  String capSvcSpotifySummary(Object name) {
    return 'Spotify Playlist: $name';
  }

  @override
  String capSvcYtSummary(Object title) {
    return 'Playlist: $title';
  }

  @override
  String get capSvcNoAudioMatch => 'Couldn\'t be matched to audio.';

  @override
  String get capSvcMatchFailed => 'Matching failed.';

  @override
  String get capSvcPlaylistNotFound => 'Playlist not found or not public.';

  @override
  String get capSvcMetaUnreadable => 'Song metadata can\'t be read.';

  @override
  String get capSvcPlaylistLoadFail => 'The playlist can\'t be loaded.';

  @override
  String get capSvcVideoMetaUnreadable => 'Video metadata can\'t be read.';

  @override
  String get capSvcNotFound => 'Not found.';

  @override
  String get capSvcNoGoodMatch => 'Nothing matched well enough.';

  @override
  String get capSvcSearchFailed => 'Search failed.';

  @override
  String get spErrServerTime => 'Spotify\'s server time can\'t be read.';

  @override
  String get spErrTokenRejected =>
      'Spotify\'s web token was rejected — Spotify may have rotated its token scheme.';

  @override
  String spErrUnreachable(Object type) {
    return 'Can\'t reach Spotify: $type';
  }

  @override
  String get spErrHashRotated =>
      'Spotify\'s query scheme changed (persisted hash rejected) — the Spotify playlist feature needs an update.';

  @override
  String spErrHttp(int code) {
    return 'Spotify answered HTTP $code.';
  }

  @override
  String get spErrShape => 'Spotify\'s response shape changed.';

  @override
  String spErrQueryRejected(Object msg) {
    return 'Spotify rejected the query: $msg';
  }

  @override
  String get spErrShapeV2 =>
      'Spotify\'s response shape changed (playlistV2 missing).';

  @override
  String noticeOfflineHidden(int count) {
    return 'Offline mode: $count streaming songs hidden from the queue.';
  }

  @override
  String noticePrepareFail(Object what) {
    return 'Couldn\'t prepare playback for $what. Check your connection and tap play again.';
  }

  @override
  String get noticeQueueEnded => 'Queue finished — no continuation available.';

  @override
  String get noticeOfflineNonePlayable =>
      'Offline mode is on — no songs in this list can play offline.';

  @override
  String noticeOfflineSkipped(int count) {
    return 'Offline mode: $count songs skipped (not downloaded).';
  }

  @override
  String noticeOfflineNotDownloaded(Object title) {
    return 'Offline mode is on — \"$title\" hasn\'t been downloaded.';
  }

  @override
  String noticeSkippedUnplayable(Object title) {
    return 'Skipping \"$title\" — can\'t play from the source.';
  }

  @override
  String get noticeAutoStop => 'Auto-stopped: 3 songs failed in a row.';

  @override
  String noticeTryingOtherPath(Object title) {
    return 'Trying another playback path for \"$title\"…';
  }

  @override
  String get dlErrFileMissing =>
      'The downloaded file wasn\'t found on the device.';

  @override
  String get dlErrTimeout => 'Download timed out.';

  @override
  String get dlErrNoConnection => 'No connection.';

  @override
  String dlErrSourceRefused(int code) {
    return 'The source refused the download (HTTP $code).';
  }

  @override
  String drvAnnounceNext(Object artist, Object title) {
    return 'Up next: $title — $artist';
  }

  @override
  String get startupStarting => 'Starting…';

  @override
  String get startupDb => 'Preparing the database…';

  @override
  String get startupSource => 'Preparing the music source…';

  @override
  String get startupPlayer => 'Preparing the player…';

  @override
  String get startupPrefs => 'Restoring preferences…';

  @override
  String get startupServices => 'Preparing services…';

  @override
  String get startupFailedTitle => 'Clai failed to start';

  @override
  String startupFailedStep(Object step) {
    return 'Failed step: $step';
  }

  @override
  String get startupRetry => 'Try Again';

  @override
  String get startupReportCopied =>
      'Report copied — paste & send it to the developer.';

  @override
  String capSvcFromLink(Object title) {
    return '$title (from link)';
  }

  @override
  String get ctxPreviousSession => 'Previous session';

  @override
  String get notifLike => 'Like';

  @override
  String get notifUnlike => 'Liked';

  @override
  String get dlErrCorrupt =>
      'The downloaded file is corrupt (checksum mismatch).';

  @override
  String get dlErrQuotaFull =>
      'Download quota is full — delete old downloads or raise the quota in Settings.';

  @override
  String get dlErrStorageFull => 'Device storage is full.';

  @override
  String get dlPause => 'Pause';

  @override
  String get dlResume => 'Resume';

  @override
  String get dlPauseAll => 'Pause All';

  @override
  String get dlResumeAll => 'Resume All';

  @override
  String get dlRedownload => 'Re-download';

  @override
  String dlPausedState(Object done, Object total) {
    return 'Paused · $done of $total';
  }

  @override
  String dlUsageLine(Object used) {
    return '$used used';
  }

  @override
  String get dlQuotaLabel => 'Download quota';

  @override
  String get dlQuotaUnlimited => 'Unlimited';

  @override
  String dlQuotaGb(int gb) {
    return '$gb GB';
  }

  @override
  String get setDataSaver => 'Data saver mode';

  @override
  String get setDataSaverSub =>
      'Streaming is always Low quality while on; High quality is blocked on mobile networks.';

  @override
  String get setDataSaverCellularBlock =>
      'High quality is blocked: data saver is on and the device is using a mobile network.';

  @override
  String get setFocusBehavior => 'When another app makes a brief sound';

  @override
  String get focusDuck => 'Lower the volume (duck)';

  @override
  String get focusPause => 'Pause, then auto-resume';

  @override
  String get setHistoryRetention => 'Keep playback history for';

  @override
  String histDays(int days) {
    return '$days days';
  }

  @override
  String get histForever => 'Forever';

  @override
  String playerBitrate(int kbps) {
    return '$kbps kbps';
  }

  @override
  String get a11yPlay => 'Play';

  @override
  String get a11yPause => 'Pause';

  @override
  String get a11yNext => 'Next track';

  @override
  String get a11yPrevious => 'Previous track';

  @override
  String get a11yShuffle => 'Shuffle';

  @override
  String get a11yRepeat => 'Repeat';

  @override
  String get a11yLike => 'Like';

  @override
  String get a11yUnlike => 'Unlike';

  @override
  String get a11yClosePlayer => 'Close player';

  @override
  String get a11yOpenPlayer => 'Open player';

  @override
  String get a11yTrackOptions => 'Track options';

  @override
  String get a11ySeek => 'Playback position';

  @override
  String get a11ySettings => 'Settings';

  @override
  String get a11ySort => 'Sort';

  @override
  String get contentSave => 'Save to Collection';

  @override
  String get contentSaved => 'Saved to Collection';

  @override
  String get contentDownloadAll => 'Download All';

  @override
  String get contentShare => 'Share';

  @override
  String get contentFromCache =>
      'Showing the saved copy — the source is unreachable right now.';

  @override
  String get collectionAlbums => 'Albums';

  @override
  String get collectionArtists => 'Artists';

  @override
  String get collectionEmptyAlbums =>
      'No saved albums yet. Save one from an album page.';

  @override
  String get collectionEmptyArtists =>
      'No saved artists yet. Save one from an artist page.';

  @override
  String get searchSuggestions => 'Suggestions';

  @override
  String get eqPresetFlat => 'Flat';

  @override
  String get eqPresetBass => 'Bass';

  @override
  String get eqPresetVocal => 'Vocal';

  @override
  String get eqPresetAcoustic => 'Acoustic';

  @override
  String get eqNamedPresets => 'Clai presets';

  @override
  String get setSamsung => 'Samsung';

  @override
  String get setSamsungSub =>
      'Settings → Battery → Background usage limits → never put Clai in sleeping or deep-sleeping apps.';

  @override
  String get setOppo => 'Oppo / vivo';

  @override
  String get setOppoSub =>
      'Enable auto-start (autostart) for Clai and lock the app in the recents screen so the system does not clean it up.';

  @override
  String get setHuawei => 'Huawei / Honor';

  @override
  String get setHuaweiSub =>
      'Settings → Battery → App launch → Clai → manage manually: enable auto-launch, secondary launch, and run in background.';

  @override
  String get bgAutostartNote =>
      'Auto-start (autostart) status cannot be detected automatically by apps on Android — check it manually for your device brand below.';

  @override
  String get noticeRegionUnavailable =>
      'This content is not available in your region.';

  @override
  String get diagGatesTitle => 'This session\'s quality gates (PRD Ch. 3)';

  @override
  String diagGateCold(int ms) {
    return 'Last cold start: $ms ms';
  }

  @override
  String diagGateTap(int median, int n, int p95) {
    return 'Tap→sound: median $median ms · p95 $p95 ms · $n samples';
  }

  @override
  String diagGateFail(int attempts, int failures, Object pct) {
    return 'Playback attempts: $attempts · failed $failures ($pct%)';
  }

  @override
  String get diagGateNone => 'No samples yet this session.';

  @override
  String get a11yClose => 'Close';

  @override
  String contentDownloadQueued(int count) {
    return '$count tracks queued for download.';
  }

  @override
  String get contentPlaylistCopied => 'Playlist copied to your collection.';

  @override
  String get queueDragReorder => 'Drag to reorder';

  @override
  String get ocrMsgNotPublished =>
      'Model not available yet — downloads open once Clai\'s first official release is published.';

  @override
  String get ocrMsgNoModelInRelease =>
      'The latest release doesn\'t include the text-reader model yet — downloads open once the model ships in a release.';

  @override
  String get ocrCheckAgain => 'Check Again';

  @override
  String get artistNotFound => 'Artist not found';

  @override
  String get contentDownloaded => 'Downloaded';

  @override
  String contentDownloadingCount(int done, int total) {
    return '$done/$total';
  }
}
