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
  String get eqWaitingSession =>
      'Start playing a song so the EQ can be applied.';

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
    return 'Installed · $size$versionPart';
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
      'Not downloaded · one-time download ±4 MB.';

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
  String updateInstalledLabel(Object label, Object status) {
    return 'Installed: $label · $status';
  }

  @override
  String updateDownloadTag(Object tag) {
    return 'Download $tag';
  }

  @override
  String get updateInstall => 'Install update';

  @override
  String get updateAutoCheck => 'Automatic checks';

  @override
  String get updateAutoDownload => 'Auto-update (download in background)';

  @override
  String get updateWifiOnly => 'Download on Wi-Fi only';

  @override
  String get updateInstallPermTitle => 'Install permission not granted';

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
  String get updateWhatsNewBtn => 'What\'s new';

  @override
  String updateWhatsNewTitle(Object version) {
    return 'What\'s new in $version';
  }

  @override
  String updateBuildLabel(int build) {
    return 'Build $build';
  }

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
      'Quality, Autoplay, Shuffle & Smart Shuffle, transitions';

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
  String get groupAppearanceSum => 'Cover theme, greeting name & language';

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
  String get groupExtras => 'Extra Features';

  @override
  String get groupExtrasSum => 'Driving, capture & ListenBrainz';

  @override
  String get groupSystem => 'System';

  @override
  String get groupSystemSum => 'Background, data, updates & diagnostics';

  @override
  String get settingsSearchHint => 'Search settings';

  @override
  String settingsSearchEmpty(String query) {
    return 'No settings for \"$query\"';
  }

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
  String get setSmartShuffle => 'Smart Shuffle';

  @override
  String get setAutoResume => 'Resume automatically after interruptions';

  @override
  String get setTransition => 'Transition mode';

  @override
  String get transitionSnack => 'The new mode applies from the next song.';

  @override
  String get setCrossfadeDur => 'Crossfade duration';

  @override
  String crossfadeDurVal(Object secs) {
    return '$secs seconds';
  }

  @override
  String get setNormalization => 'Loudness normalization';

  @override
  String get normMicSnack =>
      'Without microphone permission, Android\'s Visualizer may not measure — every song\'s gain stays neutral. The permission is only for measuring levels, never recording.';

  @override
  String get setOfflineMode => 'Offline mode';

  @override
  String get setManageDownloads => 'Manage downloads';

  @override
  String get setDynamicAccent => 'Dynamic cover accent';

  @override
  String get languageTitle => 'Language';

  @override
  String get languageSystem => 'System';

  @override
  String get captureLinkTitle => 'Capture link/text';

  @override
  String get captureHint => 'Paste a link or type a keyword…';

  @override
  String get captureAction => 'Capture';

  @override
  String get searchCaptureTitle => 'Capture a song list';

  @override
  String get capturePickImage => 'Pick an image from the gallery';

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
  String get setClearCache => 'Clear stream cache';

  @override
  String get cacheClearedSnack => 'Stream cache cleared.';

  @override
  String get setClearHistory => 'Clear play history';

  @override
  String get historyClearedSnack => 'Play history cleared.';

  @override
  String get setDiagTitle => 'Playback Diagnostics';

  @override
  String get setLogTitle => 'Incident log (on device)';

  @override
  String setLogCount(int count) {
    return '$count entries';
  }

  @override
  String aboutVersion(String version) {
    return 'Clai $version';
  }

  @override
  String get logTitle => 'Incident log';

  @override
  String get logEmpty => 'No incidents recorded yet.';

  @override
  String get groupListenBrainz => 'ListenBrainz';

  @override
  String get drvMode => 'Driving Mode';

  @override
  String get drvScheme => 'Control scheme';

  @override
  String get drvSchemeButtons => 'Media buttons';

  @override
  String get drvSchemePatterns => 'Press patterns';

  @override
  String get drvSchemeVoice => 'Voice commands';

  @override
  String get drvAnnounce => 'Voice announcements';

  @override
  String get drvSpeedVolume => 'Speed-based volume';

  @override
  String get drvVolStop => 'Volume when stopped';

  @override
  String get drvVolFast => 'Volume at full speed';

  @override
  String drvVolFastSub(int pct) {
    return '$pct%';
  }

  @override
  String drvVolPct(int pct) {
    return '$pct%';
  }

  @override
  String get drvAnchor => 'Anchor speed';

  @override
  String drvAnchorSub(int kmh) {
    return '$kmh km/h';
  }

  @override
  String get drvVehicles => 'Vehicle devices (Bluetooth)';

  @override
  String get drvVehiclesNone =>
      'No Bluetooth devices are paired with this device.';

  @override
  String drvVehiclesCount(int count) {
    return '$count paired devices.';
  }

  @override
  String get lbTitle => 'Send listening history to ListenBrainz';

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
  String get homeSetupNow => 'Set up now';

  @override
  String get homeEmptyTitle => 'What do you want to hear today?';

  @override
  String get homeEmptySub => 'Find your first song.';

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
  String homeResumeFrom(Object time) {
    return 'Resume from $time';
  }

  @override
  String get homeQuickPlay => 'Quick play';

  @override
  String get homeTopWeek => 'Most played this week';

  @override
  String get homeTopWeekEmpty => 'Nothing on repeat this week yet.';

  @override
  String homePlayCount(int count) {
    return '$count plays';
  }

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
  String ctxShareCredit(Object url) {
    return 'Shared via Clai — get the app: $url';
  }

  @override
  String radioPageTitle(Object title) {
    return 'Radio — $title';
  }

  @override
  String get radioGeneratedFrom => 'Radio generated from this song';

  @override
  String get radioEmpty => 'No radio could be built from this song yet.';

  @override
  String get radioLoadFailed =>
      'Couldn\'t load this song\'s radio. Check your connection and try again.';

  @override
  String get ctxRemoveFromQueue => 'Remove from Queue';

  @override
  String get queueSelect => 'Select';

  @override
  String queueSelectedCount(Object count) {
    return '$count selected';
  }

  @override
  String get queueBulkRemove => 'Remove';

  @override
  String get queueBulkPlaylist => 'To Playlist';

  @override
  String get queueBulkSave => 'Save';

  @override
  String get queueSelectAll => 'Select All';

  @override
  String get queueUnselectAll => 'Clear All';

  @override
  String bulkQueueAdded(Object count) {
    return '$count songs added to the queue.';
  }

  @override
  String bulkSaved(Object count) {
    return '$count songs saved to your Collection.';
  }

  @override
  String get bulkSavedNone =>
      'All of these songs are already in your Collection.';

  @override
  String bulkPlaylistAdded(Object count) {
    return '$count songs added to the playlist.';
  }

  @override
  String get bulkPlaylistNone =>
      'All of these songs are already in that playlist.';

  @override
  String bulkRemovedFromQueue(Object count) {
    return '$count songs removed from the queue.';
  }

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
  String get searchEmpty => 'Type to search the catalogue.';

  @override
  String get searchRecent => 'Recent searches';

  @override
  String get searchClearAll => 'Clear all';

  @override
  String get searchClearQuery => 'Clear search';

  @override
  String get searchNoResults => 'Not found. Try another keyword.';

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
  String get collectionGoSearch => 'Search songs';

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
      'No downloads yet. Download a song from the ⋯ menu on any song row.';

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
  String sleepSubMinutes(Object remaining) {
    return 'Timer active — $remaining. The volume fades out smoothly over the final stretch, then the music pauses.';
  }

  @override
  String get sleepSubEndOfSong =>
      'Timer active — music stops at the end of the current song (fading over its final stretch).';

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
      'Try: \"play [title]\", \"skip\", \"pause\", \"resume\".';

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
  String get drvNoSong => 'No song';

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
  String get diagRun => 'Run Diagnostics';

  @override
  String get diagRunClients => 'Test InnerTube Clients';

  @override
  String get diagPlayWinner => 'Client Playback Proof';

  @override
  String get diagRunPoToken => 'PoToken Probe';

  @override
  String get diagRunCrossing => 'F3 Crossing Probe';

  @override
  String get diagRunDecipher => 'F3 Decipher Probe';

  @override
  String get diagRunSabr => 'F3 SABR Probe';

  @override
  String get diagRunSabrCeiling => 'SABR Ceiling Probe';

  @override
  String get diagRunWebView => 'Guest WebView Probe';

  @override
  String get diagOpenLoginLab => 'Login Lab';

  @override
  String get diagRunLogin => 'Matrix L (Login)';

  @override
  String get diagRunTahap2 => 'Matrix U (Stage 2)';

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
  String diagBreathLine(String text) {
    return 'Breath (U1): $text';
  }

  @override
  String diagWaveformLine(String text) {
    return 'Waveform: $text';
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

  @override
  String get homeContinue => 'Continue';

  @override
  String get setThemeDynamic => 'Dynamic Theme';

  @override
  String get setAmbientStrength => 'Ambient Strength';

  @override
  String get ambientCalm => 'Calm';

  @override
  String get ambientLively => 'Lively';

  @override
  String get setAmbientBreathing => 'Breathing Ambience';

  @override
  String get setReduceEffects => 'Reduce Effects';

  @override
  String get setGreetingName => 'Greeting name';

  @override
  String get greetingNameHint => 'Your name';

  @override
  String get searchChartsKicker => 'Charts · This Week';

  @override
  String get searchMoodGenreKicker => 'Mood & Genres';

  @override
  String collectionStats(int songs, int playlists) {
    return '$songs songs · $playlists playlists · all yours';
  }

  @override
  String get collectionLikedSongs => 'Liked Songs';

  @override
  String get collectionAutoPlaylist => 'Automatic playlist';

  @override
  String collectionDownloadsMeta(int count, String size) {
    return '$count songs · $size on this device';
  }

  @override
  String collectionDownloadsMetaActive(int count, String size, int active) {
    return '$count songs · $size on this device · $active downloading';
  }

  @override
  String collectionLocalMeta(int count) {
    return '$count files on this device';
  }

  @override
  String get collectionYourArtists => 'Your Artists';

  @override
  String get collectionLastPlayedToday => 'last played today';

  @override
  String get collectionLastPlayedYesterday => 'last played yesterday';

  @override
  String collectionLastPlayedDays(int days) {
    return 'last played $days days ago';
  }

  @override
  String collectionLastPlayedWeeks(int weeks) {
    return 'last played $weeks weeks ago';
  }

  @override
  String collectionLastPlayedMonths(int months) {
    return 'last played $months months ago';
  }

  @override
  String collectionLastPlayedYears(int years) {
    return 'last played $years years ago';
  }

  @override
  String collectionStatsFull(int songs, int playlists, int artists) {
    return '$songs songs · $playlists playlists · $artists artists';
  }

  @override
  String get collectionLastPlayedKicker => 'Last Played';

  @override
  String get collectionYours => 'Yours';

  @override
  String get radioKicker => 'Song Radio';

  @override
  String get radioSeedCaption => 'From this song';

  @override
  String get radioResults => 'Radio Results';

  @override
  String get radioComposing => 'Building your radio…';

  @override
  String get catalogWord => 'Catalogue';

  @override
  String get spNoCatalog => 'Not in the catalogue';

  @override
  String get spSectionTracks => 'Tracks';

  @override
  String get dlSectionDownloaded => 'Downloaded';

  @override
  String dlStorageUsedBy(int count) {
    return 'used by $count downloaded songs';
  }

  @override
  String get localFormatsFound => 'formats found';

  @override
  String get localScanning => 'Scanning…';

  @override
  String get localScanningCaption => 'Scanning music folders…';

  @override
  String get collectionAll => 'All';

  @override
  String get spKicker => 'Spotify Playlist';

  @override
  String get localOnDevice => 'files on this device';

  @override
  String get localScanHeadline => 'Your device\'s music folders';

  @override
  String get localResults => 'Scan Results';

  @override
  String get setSectionFlow => 'Playback Flow';

  @override
  String get setSectionDeviceGuides => 'Device Guides';

  @override
  String get a11yBack => 'Back';

  @override
  String get lyrCreditShort => 'Lyrics source: LRCLIB (lrclib.net)';

  @override
  String get commonClose => 'Close';

  @override
  String get groupOwnership => 'Ownership';

  @override
  String get ownSectionData => 'Your data';

  @override
  String get ownSectionShare => 'Share & receive';

  @override
  String get ownExportTitle => 'Export data';

  @override
  String get ownExportSub =>
      'Save playlists, liked songs & history to one file';

  @override
  String get ownImportTitle => 'Import data';

  @override
  String get ownImportSub => 'Restore from a Clai export file';

  @override
  String get ownShareTitle => 'Share a playlist';

  @override
  String get ownShareSub => 'Send one playlist via QR code or file';

  @override
  String get ownReceiveTitle => 'Receive a playlist';

  @override
  String get ownReceiveSub => 'Scan a QR code from a friend\'s Clai';

  @override
  String get ownSectionSessions => 'Saved sessions';

  @override
  String get ownVaultSub => 'Saved listening sessions you can restore anytime';

  @override
  String ownPlaylistsCount(int count) {
    return '$count playlists';
  }

  @override
  String ownLikedCount(int count) {
    return '$count liked songs';
  }

  @override
  String ownHistoryCount(int count) {
    return '$count plays';
  }

  @override
  String get exportIncludeHistory => 'Include listening history';

  @override
  String get exportAction => 'Export & share';

  @override
  String get exportM3uSection => 'Playlists as M3U';

  @override
  String get exportEmpty => 'Nothing to export yet';

  @override
  String get exportFailed => 'Export failed. Try again.';

  @override
  String importFromFile(Object name) {
    return 'File: $name';
  }

  @override
  String get importModeMerge => 'Merge';

  @override
  String get importModeReplace => 'Replace everything';

  @override
  String importSumNewPlaylists(int count) {
    return '$count new playlists added';
  }

  @override
  String importSumMergedPlaylists(int count) {
    return '$count playlists merged into existing ones';
  }

  @override
  String importSumTracksAdded(int count) {
    return '$count songs added to playlists';
  }

  @override
  String importSumLikedAdded(int count) {
    return '$count liked songs added';
  }

  @override
  String importSumHistoryAdded(int count) {
    return '$count plays added';
  }

  @override
  String get importApplyMerge => 'Merge now';

  @override
  String get importApplyReplace => 'Replace everything…';

  @override
  String get importSuccess => 'Import complete';

  @override
  String get importNothingNew =>
      'Nothing new — everything in the file is already here';

  @override
  String get importReplaceTitle => 'Replace all data?';

  @override
  String get importReplaceBody =>
      'Your current playlists, liked songs, and listening history will be deleted and replaced with this file\'s contents. This can\'t be undone.';

  @override
  String get importFailTitle => 'This file can\'t be imported';

  @override
  String get importFailNotJson =>
      'This file\'s contents aren\'t a readable Clai export.';

  @override
  String get importFailUnrecognized =>
      'This file isn\'t a Clai export. Pick a file made by Clai\'s Export data.';

  @override
  String importFailNewer(Object version) {
    return 'This file was made by a newer Clai (format $version) and can\'t be read by this version. Update Clai and try again.';
  }

  @override
  String get importFailCorrupt =>
      'This export file is damaged or incomplete, so nothing was applied.';

  @override
  String get importFailTooBig =>
      'This file is too large to import (max 20 MB).';

  @override
  String get shareTooBigForQr =>
      'This playlist is too large for a QR code — share it as a file instead.';

  @override
  String get shareFileAction => 'Share file';

  @override
  String get sharePickPlaylist => 'Choose a playlist';

  @override
  String get shareNoPlaylists => 'No playlists to share yet';

  @override
  String get scanTitle => 'Scan QR code';

  @override
  String get scanImportFile => 'Import from file';

  @override
  String scanFoundSub(int count) {
    return '$count songs · from QR code';
  }

  @override
  String get scanImportAction => 'Import playlist';

  @override
  String get scanAgain => 'Scan again';

  @override
  String get scanNotClai => 'This code isn\'t a Clai playlist share';

  @override
  String scanImported(Object name) {
    return 'Playlist \"$name\" added';
  }

  @override
  String get scanPermDenied => 'Camera permission is needed to scan';

  @override
  String get scanPermDeniedSub =>
      'Enable the camera permission, or receive the playlist from a file instead.';

  @override
  String get scanOpenSettings => 'Open app settings';

  @override
  String shareFoundFileSub(int count) {
    return '$count songs · from file';
  }

  @override
  String get scanUnavailable => 'Camera is not available on this device';

  @override
  String get shareQrImageAction => 'Share QR image';

  @override
  String get shareQrCardFooter => 'Scan this code from Clai';

  @override
  String get scanPickImage => 'Choose QR image';

  @override
  String get scanImageNoQr => 'No readable QR code in that image';

  @override
  String get scanImageUnreadable => 'That image could not be read';

  @override
  String shareLocalExcluded(int count) {
    return '$count local songs aren\'t included';
  }

  @override
  String scanResolving(int done, int total) {
    return 'Rebuilding songs from the catalog… $done of $total';
  }

  @override
  String get scanRefsNoneFound =>
      'No songs were found in the catalog — check your connection, or these songs are no longer available.';

  @override
  String scanSkippedCount(int count) {
    return '$count songs weren\'t found in the catalog and were skipped';
  }

  @override
  String scanImportedSkips(Object name, int count) {
    return 'Playlist \"$name\" added · $count songs skipped';
  }

  @override
  String get vaultTitle => 'Session Vault';

  @override
  String get vaultSaveAction => 'Save session';

  @override
  String get vaultSaveTitle => 'Save to Session Vault';

  @override
  String get vaultNameLabel => 'Session name';

  @override
  String get vaultSavedSnack => 'Session saved to the Vault';

  @override
  String get vaultEmptyTitle => 'No saved sessions yet';

  @override
  String get vaultSaveCurrent => 'Save current queue';

  @override
  String get vaultRestore => 'Restore session';

  @override
  String get vaultRestoreBody =>
      'Your current queue will be replaced by this session, and it will play from where it stopped. The session stays in the Vault after restoring.';

  @override
  String get vaultRestoredSnack => 'Session restored';

  @override
  String get vaultRestoreFailed =>
      'This session can\'t be restored — its tracks are no longer in the local catalog.';

  @override
  String get vaultDeleteTitle => 'Delete session?';

  @override
  String vaultDeleteBody(Object name) {
    return 'The session \"$name\" will be permanently deleted from the Vault.';
  }

  @override
  String get vaultSeeAll => 'See all';

  @override
  String get vaultPlayedSection => 'Already played';

  @override
  String get vaultCurrentBadge => 'Stopped here';

  @override
  String get groupTaste => 'Taste';

  @override
  String get groupTasteSum =>
      'Taste mirror, incognito mode, recommendation exclusions, and taste reset';

  @override
  String get tasteBalanceLifetime => 'All time';

  @override
  String get tasteBalanceRecent => 'Last 30 days';

  @override
  String get tasteBalanceTitle => 'Taste balance';

  @override
  String get tasteDayFri => 'Fri';

  @override
  String get tasteDayMon => 'Mon';

  @override
  String get tasteDaySat => 'Sat';

  @override
  String get tasteDaySun => 'Sun';

  @override
  String get tasteDayThu => 'Thu';

  @override
  String get tasteDayTue => 'Tue';

  @override
  String get tasteDayWed => 'Wed';

  @override
  String get tasteDaypartDiniHari => 'late night';

  @override
  String get tasteDaypartMalam => 'evening';

  @override
  String get tasteDaypartPagi => 'morning';

  @override
  String get tasteDaypartSiang => 'midday';

  @override
  String get tasteDaypartSore => 'afternoon';

  @override
  String get tasteExcludeAction => 'Exclude';

  @override
  String get tasteExcludeEmpty => 'Nothing excluded yet.';

  @override
  String get tasteExcludeTitle => 'Exclude from Recommendations';

  @override
  String tasteExcludedDone(Object name) {
    return '$name excluded from recommendations';
  }

  @override
  String get tasteExportFirst => 'Export first';

  @override
  String tasteGenreEstimate(Object tags) {
    return 'Estimated genres · MusicBrainz: $tags';
  }

  @override
  String get tasteKindArtist => 'Artist';

  @override
  String get tasteKindTrack => 'Track';

  @override
  String get tasteMirrorEmpty =>
      'Your taste has not taken shape yet. Play a few tracks first.';

  @override
  String get tasteMirrorTitle => 'Taste Mirror';

  @override
  String get tastePatternsTitle => 'Listening patterns';

  @override
  String tastePeakDaypart(Object label) {
    return 'You listen most: $label';
  }

  @override
  String get tastePickArtists => 'From your top artists';

  @override
  String get tastePickTracks => 'From your most played tracks';

  @override
  String tastePlaysCount(int count) {
    return '$count plays';
  }

  @override
  String tasteResetBackup(Object date) {
    return 'Last backup: $date';
  }

  @override
  String get tasteResetConfirm => 'Reset taste';

  @override
  String get tasteResetDone => 'Your taste has been reset';

  @override
  String get tasteResetNoBackup => 'Last backup: none yet';

  @override
  String get tasteResetSheetBody =>
      'Listening history, recommendation exclusions, and recommendation weight will be permanently erased. Your library, playlists, downloads, Session Vault, and liked tracks will NOT be touched.';

  @override
  String get tasteResetSheetTitle => 'Reset your taste?';

  @override
  String get tasteResetTitle => 'Reset Taste';

  @override
  String get tasteSamaranPill => 'Incognito';

  @override
  String get tasteSamaranTitle => 'Incognito Mode';

  @override
  String get tasteTitle => 'Your Taste';

  @override
  String get tasteTopArtists => 'Top artists';

  @override
  String get tasteUndo => 'Undo';

  @override
  String get tasteWeightLifetime => 'All time';

  @override
  String get tasteWeightRecent => 'Recent';

  @override
  String get tasteWeightsTitle => 'Recommendation weight';

  @override
  String get shufflePanelTitle => 'Shuffle';

  @override
  String get shufflePanelWhy =>
      'Every song plays once before anything repeats. The order below is the real play order.';

  @override
  String get shuffleSmartSub =>
      'Spread artists apart & put the rarely played first';

  @override
  String shuffleCycleProgress(int done, int total) {
    return '$done of $total played in this cycle';
  }

  @override
  String get shuffleReshuffle => 'Shuffle again';

  @override
  String get shuffleOrderTitle => 'Play order, up next';

  @override
  String get shuffleCardOffSub => 'Off — songs follow their original order';

  @override
  String get setShuffle => 'Shuffle';

  @override
  String get menuButtonLabel => 'Menu';

  @override
  String get menuTasteSub => 'Taste mirror, incognito mode & recommendations';

  @override
  String get menuVaultSub => 'Queues you saved for later';

  @override
  String get menuOwnershipSub => 'Export, import, share & receive playlists';

  @override
  String get menuSettingsSub => 'Appearance, playback, audio & more';

  @override
  String announceKicker(Object version) {
    return 'NEW IN CLAI $version';
  }

  @override
  String get announceTitle => 'What\'s new in Clai';

  @override
  String get announceStart => 'Start';

  @override
  String get announceCtaVault => 'Open Session Vault';

  @override
  String get announceCtaShare => 'Share a playlist';

  @override
  String get announceCtaTaste => 'See your taste';

  @override
  String get announceCtaShuffle => 'Open the Shuffle Panel';

  @override
  String announceMoreCount(int count) {
    return 'and $count more new things';
  }

  @override
  String patchInstalledTitle(Object version) {
    return 'Clai $version is installed';
  }

  @override
  String get patchInstalledSub => 'Small fixes behind the scenes';

  @override
  String get patchInstalledSee => 'View';

  @override
  String get samaranHowTitle => 'How Incognito Mode works';

  @override
  String get samaranHowRowHistory =>
      'What you listen to stays out of your Play history.';

  @override
  String get samaranHowRowTaste =>
      'It doesn\'t affect your Taste Mirror or recommendations.';

  @override
  String get samaranHowRowListenBrainz => 'Nothing is sent to ListenBrainz.';

  @override
  String get samaranHowRowNoLimit =>
      'It stays on until you turn it off yourself — there\'s no time limit.';

  @override
  String get samaranHowDontShow => 'Don\'t show again';

  @override
  String get samaranHowActivate => 'Turn on Incognito';
}
