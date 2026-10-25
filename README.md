<!-- DRAFT — showcase README for github.com/Riyanzakaria/clai, prepared locally (not yet pushed).
     Language: English only — owner decision, 24 Oct 2026 ("repo nya harus berbahasa inggris semua").
     Framing rule — owner decision, 25 Oct 2026: this README explains what the APP is for its
     users, never what the project is (no phases, no process, no internal codenames).
     Lean repo — owner decision, 25 Oct 2026: code + this README + LICENSE only; no docs/,
     no CHANGELOG, no CONTRIBUTING. App name locked final: Clai (25 Oct 2026).
     Image paths point at ./gambar/ in the draft folder; on release day they move to assets/screenshots/. -->

<p align="center">
  <img src="gambar/logo-clai.png" width="120" alt="Clai logo">
</p>

<h1 align="center">Clai</h1>

<p align="center">
  <strong>The music player that asks for nothing.</strong><br>
  No account. No ads. No server. No telemetry. Clai streams from YouTube Music,
  keeps everything on your phone, and is free and open source — forever.
</p>

<p align="center">
  No sign-up · No ads · Offline downloads · Synced lyrics · GPL-3.0
</p>

<p align="center">
  <a href="https://github.com/Riyanzakaria/clai/releases">Download the latest release</a> ·
  <a href="#whats-coming">What's coming</a> ·
  <a href="#for-developers">For developers</a>
</p>

---

## Screenshots

<p align="center">
  <img src="gambar/player.png" width="270" alt="Player">
  <img src="gambar/beranda.png" width="270" alt="Home">
  <img src="gambar/antrian.png" width="270" alt="Queue with Smart Shuffle and Autoplay sections">
</p>
<p align="center">
  <img src="gambar/jelajah.png" width="270" alt="Explore shelves">
  <img src="gambar/lirik.png" width="270" alt="Lyrics">
  <img src="gambar/berkendara.png" width="270" alt="Car Mode">
</p>

## What is Clai?

Clai is a music player for Android that treats the **player itself as the product**: an honest, fully manageable queue, transitions that don't break, and playback that recovers by itself when the network misbehaves. The catalogue and audio come from YouTube Music through a replaceable provider layer, and everything personal — your library, playlists, history — lives only on your phone.

There is no Clai server. There is nothing to sign up for. The app costs nothing to run and nothing to use.

## Only in Clai

Streaming a song is easy — every app does that. These six things are why Clai exists, and you won't find them in Spotify, YouTube Music, or Apple Music:

- **Capture a track list from a screenshot.** Photograph or screenshot a playlist anywhere — another app, a chat, a poster — and Clai reads it with on-device OCR and turns it into a playable queue, reporting per item what matched and what didn't. Links and shared text work too.
- **Continue Tomorrow.** A sleep timer that doesn't just stop the music: it bookmarks your exact position, and the next day a *"Continue from last night"* card on Home resumes the same queue where you drifted off.
- **Autoplay that open-source players don't have — done properly.** In open-source players, "autoplay" usually means YouTube's raw automix handed to you unfiltered: it drifts off-topic within a few songs and lets non-music junk in. Clai's Autoplay continuations sit in their own labelled **AUTO** section, are picked by a similarity ladder anchored to the session you started, pass a quality gate that rejects non-music and wrong-version filler, treat your skips as a negative signal, and reset when you clear the queue. No black box, no silent drift.
- **A shuffle that adds nothing.** Spotify's Smart Shuffle mixes recommendations into your playlist. Clai's Smart Shuffle only reorders the songs you already chose — injecting new music is Autoplay's job, and Autoplay is always labelled.
- **Voice Queue, on-device, in Indonesian & English.** Say *"putar …"* (play …) or *"jeda"* (pause) from inside the app. Ambiguous matches are read back for confirmation, never guessed — no assistant account, no cloud LLM.
- **A real Car Mode.** A giant-touch surface you can swipe anywhere, voice commands, and speed-following volume that stays between two limits *you* calibrate — built in, not a separate app or a discontinued experiment.

## Features

Everything a daily music player should do — done properly, and labelled honestly where a source sets the limit.

### Playback & queue
- **Full queue control** — play next, add to queue, drag to reorder, swipe to remove, undo, clear. Your manual queue always outranks everything else.
- **Smart Autoplay** — when an album, playlist, or search context ends, the music doesn't. Continuations are picked by a similarity ladder (same artist → related tracks → similar artists → genre), anchored to your session so the stream doesn't drift into generic filler. They appear in their own clearly labelled **AUTO** section of the queue, and skips act as a negative signal for the rest of the session.
- **Start Track Radio** — an endless station from any song, from any track's menu.
- **Smart Shuffle** — reorders the list you already have (same-artist tracks spread out, favourites nudged in) and **never injects new songs**. Injecting new music is Autoplay's job, and it is always labelled.
- **Crossfade (1–12 s) and gapless** transitions, loudness normalization, and a 5-band equalizer with presets.
- **Honest interruption handling** — if another app (a call, a video) pauses your music, it resumes afterwards. If *you* paused it, it stays paused. A manual pause is never overridden.
- **Sleep timer**, plus **Continue Tomorrow** below.
- Background playback with full system media controls (notification & lock screen), and your session is restored after the app is restarted, updated, or killed.

### Discovery & library
- **Home** with Now Playing card, Recently Played, Play Again, and personal shelves computed locally from your own listening (e.g. *"Because you often play …"*).
- **Explore** shelves from YouTube Music: trending community playlists, quick picks, and video charts.
- **Search** across songs, albums, artists, and playlists, with filters.
- **Album, artist, and playlist pages**, including discography and similar artists.
- **Your library** — liked songs, history, your own playlists (full create/edit/reorder), and **local files** from your device treated as first-class citizens next to streamed tracks.
- **Spotify playlists, metadata only** — paste a public Spotify playlist link and Clai reads its track list (no Spotify account needed) and matches every track to YouTube Music audio. The page says so, honestly, on its face.

### Lyrics & extras
- **Synced lyrics** from LRCLIB (with plain lyrics as fallback, cached on-device), plus cover-art enrichment via MusicBrainz / Cover Art Archive.
- **Optional ListenBrainz scrobbling** — off by default; bring your own token.
- **Dynamic cover accent** — the Player and Home card take a muted tint from the current cover. Play buttons always stay Volt.

### Downloads & offline
- **Download songs for offline play**, with a downloads manager (list, progress, play, delete).
- **Offline mode that tells the truth** — only downloaded tracks and local files play; the queue is filtered and Autoplay is labelled *"limited — offline"* instead of pretending otherwise.

### Signature features
- **Car Mode** — a giant-touch driving surface (swipe anywhere to skip), media-button tap patterns, voice commands, optional spoken track announcements, and speed-following volume that stays between two limits *you* calibrate.
- **Voice Queue** — say *"play …"* or *"pause"*; ambiguous matches are read back to you for confirmation instead of being guessed. No LLM — Android's on-device speech recognizer plus a rule-based parser (Indonesian & English).
- **Capture from Anywhere** — share a link, text, or a screenshot of a track list from any app; Clai matches it into a playable queue and reports per-item what matched and what didn't. List images are read with on-device OCR (the OCR model is a one-time in-app download, not bundled into the APK).

### Updates
- **In-app updates** — Clai checks GitHub Releases (about once a day, can be turned off, sends no user data), downloads the new APK in-app with progress, and installs it. Your library and settings survive every update.

## Download & install

1. Download [**clai.apk**](https://github.com/Riyanzakaria/clai/releases/latest/download/clai.apk) — that link always serves the latest version from [GitHub Releases](https://github.com/Riyanzakaria/clai/releases).
2. Open it and allow installation when Android asks (needed once).
3. Done — future versions arrive inside the app.

**Requirements:** Android 10 or newer. No account, no sign-up, no permissions beyond what each feature needs, asked only when you open that feature.

## The honest part

Clai is upfront about what it is:

- **Unofficial API.** Clai talks to YouTube Music through its unofficial internal API (InnerTube) — the same approach other open-source players use. This is outside the source's official terms, and it means the source **can change or break at any time**. The provider layer exists so another source can be added without rebuilding the player, and failures are surfaced honestly in the app instead of failing silently. Use it with that understanding.
- **The audio is lossy, because the source is.** Streams are Opus/AAC up to roughly 256 kbps — there is no lossless tier to unlock, and Clai will not fake one. Your own local files (e.g. FLAC) are played as-is.
- **Clean-room.** Clai was designed from open specifications and product research. It contains no code, icons, artwork, or assets from Spotify or any other player, and it is not affiliated with, endorsed by, or connected to YouTube, Google, or Spotify.
- **Your data stays yours.** No accounts, no analytics, no telemetry, no ads. Everything personal is stored locally on your device.
- **License: GPL-3.0.** Anyone may use, study, and modify Clai; distributed derivatives must stay open source under the same license.

## What's coming

Clai grows in small, finished steps — here is what future updates will bring you:

- **In 1.1.0** — home-screen widgets and long-press shortcuts, a swipeable mini player, honest data-usage estimates per quality (with a data-saver offer on mobile data), *"Why this song?"* labels on Autoplay picks, a *"Don't play things like this"* block, undo when you skip by accident, and a sleep timer that fades out instead of cutting off.
- **In 2.0.0** — your listening stats and a "Clai Wrapped" made entirely on your phone, exporting and importing your library in open formats (JSON/M3U), Clai Connect on your home network (control one device from another), and an open plug-in system so new music sources can be added.
- **Later** — an iOS build you install by sideloading (via AltStore/SideStore), plus podcasts and audiobooks. The App Store is not a realistic door for this kind of app (third-party-content policy and a paid developer programme), and this page won't pretend otherwise.

Desktop and Android TV versions are **not** planned — Clai is a phone app by decision, not by limitation.

## For developers

Clai is built with **Flutter** and **ExoPlayer** (via `just_audio` / `audio_service`). The design language is **Volt** — a near-black surface (`#0A0A0E`) with a single lime accent (`#B8F135`), Space Grotesk + Inter, and spring-physics motion throughout (no linear easing).

Architecture in one paragraph: the player never talks to a source directly. Every source (YouTube Music today, local files, future plug-ins) implements the same provider contract; the queue engine, autoplay ladder, and UI sit above that contract. Personal data lives in a local database with versioned migrations, and automatic updates pull from GitHub Releases.

Found a bug? Reports that include the app's built-in incident log (in Settings) are dramatically easier to fix.

## License

[GNU General Public License v3.0](LICENSE)

---

<p align="center"><em>Clai is free, open, and yours. If it earns a place on your home screen, tell one person who still pays a monthly fee to rent their own music.</em></p>
