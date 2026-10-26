import '../../domain/models.dart';

/// Fungsi murni pengurai renderer InnerTube (WEB_REMIX) — diuji dengan fixture (Blueprint 5.6).
/// Toleran struktur: menelusuri JSON secara rekursif mencari renderer yang dikenal,
/// sehingga perubahan susunan sumber menjadi hasil kosong terdeteksi, bukan crash.

Map<String, dynamic>? asMap(Object? v) => v is Map ? v.cast<String, dynamic>() : null;
List<dynamic> asList(Object? v) => v is List ? v : const [];

String? runsText(Object? node) {
  final m = asMap(node);
  if (m == null) return null;
  final runs = asList(m['runs']);
  if (runs.isEmpty) return null;
  return runs.map((r) => (asMap(r)?['text'] as String?) ?? '').join();
}

String? simpleText(Object? node) {
  final m = asMap(node);
  if (m == null) return null;
  return (m['simpleText'] as String?) ?? runsText(m);
}

String? browseIdOf(Object? node) {
  final m = asMap(node);
  if (m == null) return null;
  final nav = asMap(m['navigationEndpoint']);
  final browse = asMap(nav?['browseEndpoint']);
  return browse?['browseId'] as String?;
}

String? thumbUrl(Object? node, {int minWidth = 120}) {
  // Bentuk sumber berlapis: {musicThumbnailRenderer: {thumbnail: {thumbnails: [...]}}}.
  // Versi lama hanya melihat satu tingkat sehingga SELALU null untuk bentuk standar ini
  // (bukti fixture v4: 0/14 trek ber-artwork). Telusuri pembungkus yang dikenal sampai
  // daftar thumbnails ditemukan (maks 5 tingkat).
  //
  // v4.4: pilih varian TERBESAR dalam larik sebagai URL kanonik yang disimpan.
  // Ukuran tampil diatur belakangan oleh pemilih sadar-ukuran (core/artwork.dart)
  // yang menulis ulang parameter ukuran URL per permukaan — baris daftar tetap
  // meminta varian kecil, Player meminta yang besar. Dulu di sini dipilih varian
  // kecil (>= minWidth) sehingga Player merentangkan gambar mungil = buram.
  Object? cur = node;
  List<dynamic> thumbs = const [];
  for (var depth = 0; depth < 6; depth++) {
    final m = asMap(cur);
    if (m == null) break;
    thumbs = asList(m['thumbnails']);
    if (thumbs.isNotEmpty) break;
    // Pembungkus yang dikenal. CACAT v4.4 (bukti probe hidup halaman artis):
    // musicTwoRowItemRenderer di halaman artis membungkus gambar sebagai
    // {thumbnailRenderer: {musicThumbnailRenderer: {thumbnail: {thumbnails}}}}
    // — kunci 'thumbnailRenderer' tidak pernah dituruni sehingga diskografi &
    // artis terkait SELALU tanpa sampul (ubin inisial), sementara hasil cari
    // (kunci 'thumbnail') bekerja. 'croppedSquareThumbnailRenderer' = varian header.
    cur = m['musicThumbnailRenderer'] ??
        m['thumbnailRenderer'] ??
        m['croppedSquareThumbnailRenderer'] ??
        m['thumbnail'];
  }
  String? best;
  var bestW = -1;
  String? fallback;
  for (final t in thumbs) {
    final tm = asMap(t);
    final url = tm?['url'] as String?;
    if (url == null) continue;
    fallback ??= url;
    final w = (tm?['width'] as num?)?.toInt() ?? 0;
    if (w > bestW) { best = url; bestW = w; }
  }
  return best ?? fallback;
}

Duration? parseDurationText(String? s) {
  if (s == null) return null;
  final parts = s.split(':').map((e) => int.tryParse(e.trim())).toList();
  if (parts.any((e) => e == null)) return null;
  var sec = 0;
  for (final p in parts) { sec = sec * 60 + p!; }
  return Duration(seconds: sec);
}

String _flexText(Map<String, dynamic> item, int col) {
  final cols = asList(item['flexColumns']);
  if (col >= cols.length) return '';
  final colMap = asMap(asMap(cols[col])?['musicResponsiveListItemFlexColumnRenderer']);
  return runsText(colMap?['text']) ?? '';
}

List<String> _flexArtistIds(Map<String, dynamic> item, int col) {
  final cols = asList(item['flexColumns']);
  if (col >= cols.length) return const [];
  final colMap = asMap(asMap(cols[col])?['musicResponsiveListItemFlexColumnRenderer']);
  final ids = <String>[];
  for (final r in asList(asMap(colMap?['text'])?['runs'])) {
    final id = browseIdOf(r);
    if (id != null && id.startsWith('UC')) ids.add(id);
  }
  return ids;
}

String? _flexAlbumId(Map<String, dynamic> item, int col) {
  final cols = asList(item['flexColumns']);
  if (col >= cols.length) return null;
  final colMap = asMap(asMap(cols[col])?['musicResponsiveListItemFlexColumnRenderer']);
  for (final r in asList(asMap(colMap?['text'])?['runs'])) {
    final id = browseIdOf(r);
    if (id != null && (id.startsWith('MPRE') || id.startsWith('OLAK'))) return id;
  }
  return null;
}


String? _extractVideoId(Map<String, dynamic> m) {
  String? fromNav(Object? nav) {
    final n = asMap(nav);
    if (n == null) return null;
    final watch = asMap(n['watchEndpoint']);
    if (watch?['videoId'] is String) return watch!['videoId'] as String;
    final watchEp = asMap(n['watchPlaylistEndpoint']);
    if (watchEp != null) return null;
    return null;
  }
  var v = fromNav(m['navigationEndpoint']);
  if (v != null) return v;
  final playBtn = asMap(asMap(asMap(m['overlay'])?['musicItemThumbnailOverlayRenderer'])?['content'])?['musicPlayButtonRenderer'];
  final pne = asMap(playBtn)?['playNavigationEndpoint'];
  v = asMap(pne)?['videoId'] as String? ?? fromNav(pne);
  if (v != null) return v;
  // Jalur: endpoint pada run judul.
  for (final col in asList(m['flexColumns'])) {
    final colMap = asMap(asMap(col)?['musicResponsiveListItemFlexColumnRenderer']);
    for (final r in asList(asMap(colMap?['text'])?['runs'])) {
      v = fromNav(asMap(r)?['navigationEndpoint']);
      if (v != null) return v;
    }
  }
  final menu = asMap(m['menu']);
  v = fromNav(asMap(asMap(menu?['menuRenderer'])?['items']) == null ? null : null);
  return v;
}

/// Nama artis bersih dari byline sumber mentah (segmen berpisah " • ").
///
/// Dua bentuk sumber terbukti merusak nama artis (Ronde Cacat Metadata,
/// bukti hidup 25 Okt 2026):
/// 1. Byline panel/daftar PENUH "Artis • Album • Tahun" (longBylineText) —
///    yang benar sebagai nama artis hanya segmen pertamanya. Utuh apa adanya,
///    string ini sempat menjadi JUDUL RAK personal di HP pemilik
///    ("Karena kamu sering memutar sombr • I Barely Know Her • 2025").
/// 2. Byline berisi kata kategori SAJA ("Song"/"Video"/"Episode") — artis
///    memang tidak dibawa item itu; kembalikan '' (jujur kosong, diisi
///    lapisan pewarisan/penyembuhan), BUKAN kata kategorinya — kata itu
///    sempat tersimpan harfiah sebagai nama artis ("back to friends" →
///    artis "Song").
String artistNameFromByline(String byline) {
  final segs = byline
      .split('•')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
  if (segs.isEmpty) return '';
  if (segs.length == 1 &&
      const {'Song', 'Video', 'Episode'}.contains(segs.first)) {
    return '';
  }
  // Ekor statistik item video ("… • 552K views • 8.1K likes", "… • 3.8M
  // plays") bukan bagian nama — 366 baris katalog pentasan membawa bentuk
  // ini. Buang selama masih ada segmen di depannya.
  final statTail =
      RegExp(r'^[\d.,]+\s*[KMB]?\+?\s+(views|likes|plays)$', caseSensitive: false);
  while (segs.length > 1 && statTail.hasMatch(segs.last)) {
    segs.removeLast();
  }
  // "Artis • Album • Tahun" (atau "Artis • Tahun"): nama artisnya segmen awal.
  if (segs.length >= 2 && RegExp(r'^(19|20)\d{2}$').hasMatch(segs.last)) {
    return segs.first;
  }
  return segs.join(' • ');
}

/// Mengurai satu musicResponsiveListItemRenderer / playlistVideoRenderer menjadi Track (ytmusic).
Track? parseTrackItem(Object? node, {String providerId = 'ytmusic'}) {
  final m = asMap(node);
  if (m == null) return null;
  String? videoId = m['videoId'] as String?;
  videoId ??= asMap(asMap(m['playlistItemData'])?['videoId']) != null ? m['playlistItemData']['videoId'] as String? : null;
  String title = '';
  String artists = '';
  String? albumId;
  List<String> artistIds = const [];
  Duration? duration;
  if (m.containsKey('flexColumns')) {
    title = _flexText(m, 0);
    artistIds = _flexArtistIds(m, 1);
    albumId = _flexAlbumId(m, 2);
    duration = parseDurationText(_flexText(m, 2).isEmpty ? null : _flexText(m, 2)) ??
        parseDurationText(_flexText(m, 3));
    // durasi sering berada di fixedColumns
    for (final fc in asList(m['fixedColumns'])) {
      duration ??= parseDurationText(runsText(asMap(asMap(fc)?['musicResponsiveListItemFixedColumnRenderer'])?['text']));
    }
    // Byline (kolom 1) adalah segmen-segmen berpisah " • ". Dua perbaikan dari bukti fixture
    // hidup pencarian "Semua" (putaran v4): (1) buang prefiks kategori ("Song • ",
    // "Video • ", "Episode • ") agar nama artis bersih; (2) item bergaya Video tidak punya
    // kolom durasi terpisah — durasinya adalah segmen ekor byline ("Artis • 16M views • 4:31"),
    // pulihkan dari sana agar antrean punya durasi & total yang benar.
    final segs = _flexText(m, 1).split('•').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    if (duration == null && segs.length >= 2 && RegExp(r'^\d{1,3}:\d{2}(:\d{2})?$').hasMatch(segs.last)) {
      duration = parseDurationText(segs.last);
      if (duration != null) segs.removeLast();
    }
    if (segs.length >= 2 && const {'Song', 'Video', 'Episode'}.contains(segs.first)) segs.removeAt(0);
    artists = artistNameFromByline(segs.join(' • '));
  } else if (m.containsKey('title')) {
    // playlistVideoRenderer
    title = runsText(m['title']) ?? '';
    artists = artistNameFromByline(runsText(m['shortBylineText']) ?? runsText(m['longBylineText']) ?? '');
    duration = parseDurationText(simpleText(m['lengthText']));
  }
  videoId ??= _extractVideoId(m);
  if (videoId == null || title.isEmpty) return null;
  final art = thumbUrl(m['thumbnail']);
  return Track(
    key: TrackKey(providerId, videoId),
    title: title, artistNames: artists, albumId: albumId, artistIds: artistIds,
    duration: duration, artworkUrl: art, playableRef: videoId,
  );
}

/// Mengurai satu playlistPanelVideoRenderer (daftar tonton/automix dari endpoint
/// `next`) menjadi Track (v4.3). Bentuknya berbeda total dari item daftar musik:
/// title/byline berupa runs polos, durasi di lengthText, videoId di field langsung.
///
/// Bukti probe hidup (putaran v4.3): respons `next` untuk radio TIDAK mengandung
/// satu pun renderer yang dikenal collectTracks lama — hanya
/// playlistPanelVideoRenderer (+ automix*) — sehingga getRelated selalu
/// mengembalikan daftar kosong dan tangga kemiripan ke-2 mati total.
Track? parsePanelTrackItem(Object? node, {String providerId = 'ytmusic'}) {
  final m = asMap(node);
  if (m == null) return null;
  final videoId = (m['videoId'] as String?) ?? _extractVideoId(m);
  final title = runsText(m['title']) ?? '';
  if (videoId == null || title.isEmpty) return null;
  final artists = artistNameFromByline(runsText(m['longBylineText']) ?? runsText(m['shortBylineText']) ?? '');
  final artistIds = <String>[];
  for (final src in [m['longBylineText'], m['shortBylineText']]) {
    for (final r in asList(asMap(src)?['runs'])) {
      final id = browseIdOf(r);
      if (id != null && id.startsWith('UC') && !artistIds.contains(id)) artistIds.add(id);
    }
    if (artistIds.isNotEmpty) break;
  }
  final duration = parseDurationText(runsText(m['lengthText']) ?? simpleText(m['lengthText']));
  final art = thumbUrl(m['thumbnail']);
  return Track(
    key: TrackKey(providerId, videoId),
    title: title, artistNames: artists, artistIds: artistIds,
    duration: duration, artworkUrl: art, playableRef: videoId,
  );
}

/// Cari browseId playlist "lagu teratas" pada respons halaman artis
/// (Ronde Poles Beranda, cacat B — terbukti dari probe hidup 24 Okt 2026):
/// item lagu halaman artis TIDAK membawa durasi sama sekali (kolom
/// fleksibelnya berisi jumlah putar "47M plays", tanpa kolom tetap) —
/// durasi hanya ada di item playlist lagu-lagu artis itu, yang ditautkan
/// judul raknya (musicShelfRenderer → endpoint telusur "VL…"). Mengembalikan
/// null bila tak ada rak lagu yang menautkan playlist.
String? topSongsPlaylistId(Object? node) {
  String? found;
  void walk(Object? n) {
    if (found != null) return;
    if (n is Map) {
      for (final e in n.entries) {
        if (e.key == 'musicShelfRenderer') {
          final shelf = asMap(e.value);
          final contents = asList(shelf?['contents']);
          final hasTracks = contents.any((c) =>
              asMap(c)?.containsKey('musicResponsiveListItemRenderer') ??
              false);
          if (hasTracks) {
            for (final r in asList(asMap(shelf?['title'])?['runs'])) {
              final id = browseIdOf(r);
              if (id != null && id.startsWith('VL')) {
                found = id;
                return;
              }
            }
          }
        }
        walk(e.value);
        if (found != null) return;
      }
    } else if (n is List) {
      for (final v in n) {
        walk(v);
        if (found != null) return;
      }
    }
  }

  walk(node);
  return found;
}

/// Isi durasi [tracks] yang kosong dari [source] (peta videoId → durasi).
/// Trek yang sudah berdurasi tidak diubah; sumber tanpa durasi diabaikan.
List<Track> fillDurations(List<Track> tracks, List<Track> source) {
  final byId = <String, Duration>{
    for (final t in source)
      if (t.duration != null) t.id: t.duration!,
  };
  if (byId.isEmpty) return tracks;
  return [
    for (final t in tracks)
      if (t.duration == null && byId.containsKey(t.id))
        t.copyWith(duration: byId[t.id])
      else
        t,
  ];
}

/// Wariskan konteks halaman ke trek yang sumber per-treknya tidak membawa
/// metadata sendiri (Ronde Cacat Metadata, bukti hidup 25 Okt 2026): item
/// daftar trek halaman ALBUM tidak punya kolom byline sama sekali (kosong di
/// sumber) dan tanpa thumbnail — artis hanya hidup di strapline header,
/// sampul di thumbnail header. v4.4 hanya mewariskan sampul sehingga baris
/// album tersimpan dengan artist_names KOSONG permanen (ubin huruf + tanpa
/// nama artis di rak/mini player). Hanya kolom yang KOSONG yang diisi;
/// metadata per-trek yang ada selalu menang.
List<Track> inheritPageArtist(List<Track> tracks,
    {String? artist, List<String> artistIds = const [], String? artworkUrl}) {
  final hasArtist = artist != null && artist.trim().isNotEmpty;
  if (!hasArtist && artworkUrl == null) return tracks;
  return [
    for (final t in tracks)
      t.copyWith(
        artistNames: hasArtist && t.artistNames.trim().isEmpty ? artist : null,
        artistIds: t.artistIds.isEmpty && artistIds.isNotEmpty ? artistIds : null,
        artworkUrl: t.artworkUrl ?? artworkUrl,
      ),
  ];
}

/// Kumpulkan semua Track dari pohon respons apa pun (rekursif, toleran).
List<Track> collectTracks(Object? node, {Set<String>? seen, String providerId = 'ytmusic'}) {
  final out = <Track>[];
  final s = seen ?? <String>{};
  void walk(Object? n) {
    if (n is Map) {
      for (final e in n.entries) {
        if (e.key == 'musicResponsiveListItemRenderer' || e.key == 'playlistVideoRenderer') {
          final t = parseTrackItem(e.value, providerId: providerId);
          if (t != null && s.add(t.id)) out.add(t);
        } else if (e.key == 'playlistPanelVideoRenderer') {
          final t = parsePanelTrackItem(e.value, providerId: providerId);
          if (t != null && s.add(t.id)) out.add(t);
        } else {
          walk(e.value);
        }
      }
    } else if (n is List) {
      for (final v in n) { walk(v); }
    }
  }
  walk(node);
  return out;
}

/// Kumpulkan item dua-baris (album/artis/playlist) dari shelf/carousel.
({List<Album> albums, List<Artist> artists, List<Album> playlists}) collectTwoRow(Object? node, {String providerId = 'ytmusic'}) {
  final albums = <Album>[], playlists = <Album>[], artists = <Artist>[];
  final seen = <String>{};
  void walk(Object? n) {
    if (n is Map) {
      for (final e in n.entries) {
        if (e.key == 'musicTwoRowItemRenderer') {
          final m = asMap(e.value)!;
          final id = browseIdOf(m);
          final title = simpleText(m['title']) ?? '';
          final subtitle = runsText(m['subtitle']) ?? '';
          final art = thumbUrl(m);
          if (id != null && seen.add(id)) {
            if (id.startsWith('UC')) {
              artists.add(Artist(providerId: providerId, id: id, name: title, artworkUrl: art));
            } else if (id.startsWith('VL') || id.startsWith('PL') || id.startsWith('RD') || id.startsWith('OLAK')) {
              playlists.add(Album(providerId: providerId, id: id, title: title, artistNames: subtitle, artworkUrl: art));
            } else {
              albums.add(Album(providerId: providerId, id: id, title: title, artistNames: subtitle, artworkUrl: art));
            }
          }
        } else {
          walk(e.value);
        }
      }
    } else if (n is List) {
      for (final v in n) { walk(v); }
    }
  }
  walk(node);
  return (albums: albums, artists: artists, playlists: playlists);
}

/// Kategori (album/artis/playlist) dari item daftar yang BUKAN trek — cacat v4-2.
/// Bukti fixture hidup (pencarian "Semua" tak terfilter, 2026-10-23): respons hanya berisi
/// SATU daftar campuran musicResponsiveListItemRenderer; musicTwoRowItemRenderer TIDAK
/// muncul sama sekali, sehingga collectTwoRow selalu kosong dan playlist tak pernah tampil.
/// Kategori dikenali dari navigationEndpoint item itu sendiri:
/// VL*/PL* = playlist, MPRE*/OLAK* = album, UC* = artis. Item yang terurai sebagai trek
/// (punya videoId) tidak pernah masuk sini — trek selalu didahulukan oleh pemanggil.
({List<Album> albums, List<Artist> artists, List<Album> playlists}) collectListItemCategories(Object? node, {String providerId = 'ytmusic'}) {
  final albums = <Album>[], playlists = <Album>[], artists = <Artist>[];
  final seen = <String>{};
  void walk(Object? n) {
    if (n is Map) {
      for (final e in n.entries) {
        if (e.key == 'musicResponsiveListItemRenderer') {
          final item = asMap(e.value);
          if (item == null) continue;
          if (parseTrackItem(item, providerId: providerId) != null) continue; // ini trek
          final id = browseIdOf(item);
          if (id == null || !seen.add(id)) continue;
          final title = _flexText(item, 0);
          if (title.isEmpty) continue;
          var sub = _flexText(item, 1);
          // Buang segmen kategori di awal byline ("Playlist • YouTube Music • 68 songs").
          final segs = sub.split('•').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
          if (segs.length >= 2 && const {'Playlist', 'Album', 'Artist', 'Profile', 'Single', 'EP'}.contains(segs.first)) {
            sub = segs.sublist(1).join(' • ');
          }
          final art = thumbUrl(item['thumbnail']);
          if (id.startsWith('UC')) {
            artists.add(Artist(providerId: providerId, id: id, name: title, artworkUrl: art));
          } else if (id.startsWith('VL') || id.startsWith('PL')) {
            playlists.add(Album(providerId: providerId, id: id, title: title, artistNames: sub, artworkUrl: art));
          } else if (id.startsWith('MPRE') || id.startsWith('OLAK')) {
            albums.add(Album(providerId: providerId, id: id, title: title, artistNames: sub, artworkUrl: art));
          }
        } else {
          walk(e.value);
        }
      }
    } else if (n is List) {
      for (final v in n) { walk(v); }
    }
  }
  walk(node);
  return (albums: albums, artists: artists, playlists: playlists);
}

/// Judul rak Jelajah dikenal → Bahasa Indonesia (PRD: UI Indonesia). Judul lain
/// diteruskan apa adanya — sumber boleh menambah rak baru tanpa merusak UI.
String exploreTitleId(String raw) {
  const map = {
    'new releases': 'Rilis Baru',
    'charts': 'Tangga Lagu',
    'top songs': 'Lagu Teratas',
    'top albums': 'Album Teratas',
    'top artists': 'Artis Teratas',
    'top music videos': 'Video Musik Teratas',
    'trending': 'Sedang Tren',
    'quick picks': 'Pilihan Cepat',
    'mixed for you': 'Campuran Untukmu',
    'music videos': 'Video Musik',
    'new albums & singles': 'Album & Singel Baru',
    'popular artists': 'Artis Populer',
    'popular playlists': 'Playlist Populer',
  };
  return map[raw.trim().toLowerCase()] ?? raw;
}

/// Rak-rak umpan penemuan (F2 Jelajah, PRD 5.1): telusuri pohon browse dan
/// ambil setiap musicCarouselShelfRenderer / musicShelfRenderer BESERTA judul
/// headernya, dalam urutan sumber. Isi diurai memakai pengumpul yang sama
/// dengan pencarian (collectTracks/collectTwoRow) agar bentuk item konsisten
/// dan dedupe per rak berlaku. Rak tanpa judul atau tanpa isi dibuang.
List<ExploreShelf> parseHomeFeedShelves(Map<String, dynamic> json, {String providerId = 'ytmusic'}) {
  final shelves = <ExploreShelf>[];
  void walk(Object? n) {
    if (n is Map) {
      for (final e in n.entries) {
        if (e.key == 'musicCarouselShelfRenderer' || e.key == 'musicShelfRenderer') {
          final shelf = asMap(e.value);
          if (shelf == null) continue;
          final header = asMap(shelf['header']);
          final title = (header == null
                  ? null
                  : simpleText(asMap(header['musicCarouselShelfBasicHeaderRenderer'])?['title']) ??
                      simpleText(asMap(header['musicShelfBasicHeaderRenderer'])?['title'])) ??
              '';
          final tracks = collectTracks(shelf, providerId: providerId);
          final two = collectTwoRow(shelf, providerId: providerId);
          final s = ExploreShelf(title: title, tracks: tracks, albums: two.albums,
              artists: two.artists, playlists: two.playlists);
          if (title.isNotEmpty && !s.isEmpty) shelves.add(s);
        } else {
          walk(e.value);
        }
      }
    } else if (n is List) {
      for (final v in n) { walk(v); }
    }
  }
  walk(json);
  return shelves;
}

/// Pisahkan hasil pencarian mentah menjadi kategori berdasarkan judul shelf.
SearchResults parseSearchResponse(Map<String, dynamic> json) {
  // Toleran: kategorikan dari keseluruhan pohon (shelf sumber dapat bergeser susunannya).
  // Dua jalur digabung & di-dedupe per id: rak dua-baris (pencarian terfilter/kategori)
  // dan kategori item-daftar (pencarian "Semua" — satu-satunya jalur playlist di sana).
  final two = collectTwoRow(json);
  final listed = collectListItemCategories(json);
  final albumIds = two.albums.map((a) => a.id).toSet();
  final artistIds = two.artists.map((a) => a.id).toSet();
  final playlistIds = two.playlists.map((a) => a.id).toSet();
  return SearchResults(
    songs: collectTracks(json),
    albums: [...two.albums, ...listed.albums.where((a) => !albumIds.contains(a.id))],
    artists: [...two.artists, ...listed.artists.where((a) => !artistIds.contains(a.id))],
    playlists: [...two.playlists, ...listed.playlists.where((a) => !playlistIds.contains(a.id))],
  );
}

/// Pilih format audio terbaik dari respons player InnerTube (murni — diuji dengan fixture).
/// Hanya format dengan URL langsung yang dipilih; format signatureCipher dilewati di F1
/// (Blueprint 5.4) karena klien ANDROID/IOS terbukti mengembalikan URL langsung (probe v4).
StreamInfo? pickStreamFormat(Map<String, dynamic> playerRes, StreamQuality quality) {
  final status = asMap(playerRes['playabilityStatus'])?['status'] as String?;
  if (status != null && status != 'OK') return null;
  final sd = asMap(playerRes['streamingData']);
  if (sd == null) return null;
  final formats = <Map<String, dynamic>>[
    ...asList(sd['adaptiveFormats']).map((e) => asMap(e)).whereType<Map<String, dynamic>>(),
    ...asList(sd['formats']).map((e) => asMap(e)).whereType<Map<String, dynamic>>(),
  ];
  final audio = formats.where((f) {
    final mime = (f['mimeType'] as String?) ?? '';
    return mime.startsWith('audio/') && f['url'] is String;
  }).toList();
  if (audio.isEmpty) return null;
  audio.sort((a, b) => ((a['bitrate'] as num?) ?? 0).compareTo((b['bitrate'] as num?) ?? 0));
  // D-19 (Sapuan): cadangan awal adalah bitrate TERENDAH, bukan tertinggi.
  // Bila TIDAK ADA format di bawah plafon kualitas, versi lama diam-diam
  // memilih yang TERTINGGI — persis kebalikan maksud plafon (dan menguras
  // data pengguna mode Rendah). Kini: tertinggi yang masih ≤ plafon bila
  // ada; selain itu terendah yang tersedia.
  Map<String, dynamic> chosen = audio.first;
  for (final f in audio) {
    if (((f['bitrate'] as num?) ?? 0) <= quality.maxBitrate) chosen = f;
  }
  return StreamInfo(
    url: chosen['url'] as String,
    mimeType: ((chosen['mimeType'] as String?) ?? 'audio/mp4').split(';').first,
    bitrate: (chosen['bitrate'] as num?)?.toInt(),
    expiresAt: DateTime.now().add(Duration(seconds: _expiresSeconds(sd) - 300)),
  );
}

/// Deteksi "tidak tersedia di wilayah ini" dari playabilityStatus
/// (Blueprint 5.5, Sapuan D-22) — murni, diuji unit. Status wilayah harus
/// dibedakan dari kegagalan umum agar UI bisa menyatakan sebab sebenarnya
/// per konten, bukan kegagalan generik.
bool isRegionUnavailable(String? status, String? reason) {
  if (status == null || status == 'OK') return false;
  final r = (reason ?? '').toLowerCase();
  return r.contains('not available in your country') ||
      r.contains('not available in your region') ||
      r.contains('uploader has not made this video available') ||
      r.contains('tidak tersedia di negara') ||
      r.contains('tidak tersedia di wilayah');
}

/// Masa berlaku streamingData dalam detik — toleran string (lihat catatan di pickStreamFormat).
int _expiresSeconds(Map<String, dynamic> sd) {
  final raw = sd['expiresInSeconds'];
  return raw is num ? raw.toInt() : (int.tryParse('$raw') ?? 21600);
}

/// Format CADANGAN muxed (progresif, itag 18 bila ada) dari respons player yang sama (v4.1).
///
/// Bukti probe PC 2026-10-23 (python DAN dart:io — tumpukan HTTP yang sama dengan aplikasi):
/// URL audio adaptif googlevideo saat ini menolak pola ambil yang dibutuhkan pemutar
/// (range terbuka / tanpa Range / sebagian besar range start>0 → HTTP 403; hanya range
/// terbatas kecil di awal berkas yang lolos). URL progresif itag 18 (video/mp4, audio AAC
/// di dalamnya) berperilaku klasik: GET penuh 200, range terbuka 206, range start>0 206.
/// Dipakai ResolvingAudioSource sebagai jalan terakhir SEKALI per sumber bila URL adaptif
/// ditolak — lagu berbunyi mengalahkan kemurnian format di F1.
StreamInfo? pickMuxedFallbackFormat(Map<String, dynamic> playerRes) {
  final status = asMap(playerRes['playabilityStatus'])?['status'] as String?;
  if (status != null && status != 'OK') return null;
  final sd = asMap(playerRes['streamingData']);
  if (sd == null) return null;
  final formats = asList(sd['formats']).map((e) => asMap(e)).whereType<Map<String, dynamic>>()
      .where((f) => f['url'] is String && ((f['mimeType'] as String?) ?? '').startsWith('video/mp4'))
      .toList();
  if (formats.isEmpty) return null;
  formats.sort((a, b) {
    final ai = a['itag'] == 18 ? 0 : 1, bi = b['itag'] == 18 ? 0 : 1;
    if (ai != bi) return ai - bi;
    return ((a['bitrate'] as num?) ?? 0).compareTo((b['bitrate'] as num?) ?? 0);
  });
  final chosen = formats.first;
  return StreamInfo(
    url: chosen['url'] as String,
    mimeType: ((chosen['mimeType'] as String?) ?? 'video/mp4').split(';').first,
    bitrate: (chosen['bitrate'] as num?)?.toInt(),
    expiresAt: DateTime.now().add(Duration(seconds: _expiresSeconds(sd) - 300)),
  );
}
