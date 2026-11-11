import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import '../../core/error_describe.dart';
import '../../data/app_db.dart';
import '../../domain/models.dart';
import '../../services/direct_stream_service.dart';
import '../../services/observability.dart';
import '../music_provider.dart';
import 'direct_types.dart';
import 'innertube.dart';

/// Tipe jalur DIRECT-1 (WatchPageData/DirectFormat/DirectResolveData +
/// helper murni) hidup di direct_types.dart dan di-re-export di sini agar
/// pemanggil lama (harness diagnostik) tidak berubah.
export 'direct_types.dart';

/// Klien publik yang tertanam di klien web resmi YouTube Music (bukan kredensial pengguna).
const _webKey = 'AIzaSyC9XL3ZjWddXya6X74dJoCTL-WEYFDNX30';

class _ClientCtx {
  final String name, version, userAgent;
  final Map<String, dynamic> extra;
  const _ClientCtx(this.name, this.version, this.userAgent, [this.extra = const {}]);
  Map<String, dynamic> context() => {
        'context': {
          'client': {'clientName': name, 'clientVersion': version, 'hl': 'en', 'gl': 'US', ...extra},
          'user': {'lockedSafetyMode': false},
          'request': {'useSsl': true, 'internalExperimentFlags': [], 'consistencyTokenJars': []},
        },
      };
}

const _uaWeb = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';
final _webRemix = _ClientCtx('WEB_REMIX', '1.20251027.01.00', _uaWeb);

/// Rantai resolusi aliran (Blueprint 5.4) — urutan DIBUKTIKAN dari probe hidup (putaran v4,
/// 2026-10-23, dijalankan dari PC terhadap video uji "505"/qU9mHegkTc4):
/// ANDROID & IOS menjawab playabilityStatus OK dengan URL audio LANGSUNG (tanpa cipher) dan
/// URL-nya terbukti bisa diunduh per-range (HTTP 206, audio/mp4) — keduanya kini di depan.
/// Urutan lama menaruh klien yang kini mati/dinding-bot di depan (TV-embedded: ERROR
/// "no longer supported"; ANDROID_VR & TVHTML5: LOGIN_REQUIRED "confirm you're not a bot";
/// WEB: UNPLAYABLE) — membuang waktu & kuota pada setiap resolusi; mereka tetap dipertahankan
/// sebagai cadangan terakhir karena perilaku per-IP/per-waktu bisa berbeda.
final _streamClients = <_ClientCtx>[
  _ClientCtx('ANDROID', '20.10.38',
      'com.google.android.youtube/20.10.38 (Linux; U; Android 14; in_ID; Pixel 8) gzip',
      {'androidSdkVersion': 34, 'osName': 'Android', 'osVersion': '14'}),
  _ClientCtx('IOS', '20.10.4',
      'com.google.ios.youtube/20.10.4 (iPhone16,2; U; CPU iOS 18_3_1 like Mac OS X;)',
      {'deviceModel': 'iPhone16,2', 'osName': 'iOS', 'osVersion': '18.3.1'}),
  _ClientCtx('ANDROID_VR', '1.65.10',
      'com.google.android.apps.youtube.vr.oculus/1.65.10 (Linux; U; Android 12L; eureka-user Build/SQ3A.220605.009.A1) gzip',
      {'deviceMake': 'Oculus', 'deviceModel': 'Quest 3', 'androidSdkVersion': 32, 'osName': 'Android', 'osVersion': '12L'}),
  _ClientCtx('TVHTML5', '7.20250205.16.00',
      'Mozilla/5.0 (ChromiumStylePlatform) Cobalt/25.lts.30.1034943-gold (Starboard/15, Sony; BRAVIA 4K VH2; Android/9)'),
  _ClientCtx('WEB', '2.20250901.01.00', _uaWeb),
  _ClientCtx('TVHTML5_SIMPLY_EMBEDDED_PLAYER', '2.0',
      'Mozilla/5.0 (PlayStation; PlayStation 4/8.00) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/15.4 Safari/605.1.15'),
];

/// Tabel versi klien CADANGAN terbundel (Blueprint 5.5, Sapuan D-21):
/// bila versi utama ditolak sumber (HTTP 400 / playability ditolak karena
/// versi), resolusi menaiki tangga versi ini — maks 3 versi per klien —
/// sebelum menyerah ke klien berikutnya.
const _clientVersionFallbacks = <String, List<String>>{
  'ANDROID': ['20.10.38', '19.47.53', '19.29.37'],
  'IOS': ['20.10.4', '19.47.3', '19.29.2'],
  'WEB_REMIX': ['1.20251027.01.00', '1.20250901.01.00', '1.20250602.01.00'],
  // Hanya dipakai jalur diagnostik Ronde Klien InnerTube (klien ini belum
  // masuk rantai produksi): tanggal versi pemutar embed web.
  'WEB_EMBEDDED_PLAYER': ['1.20250821.01.00', '1.20250609.01.00', '1.20250310.01.00'],
};

/// Boleh dicoba lagi? (Blueprint 5.1 butir 3, Sapuan D-20): hanya galat
/// jaringan & 5xx — 4xx adalah jawaban pasti sumber, mencoba lagi membuang
/// kuota dan memperlambat kegagalan yang sama.
bool _retryable(Object e) {
  if (e is! DioException) return false;
  final status = e.response?.statusCode;
  if (status != null) return status >= 500;
  return e.type == DioExceptionType.connectionTimeout ||
      e.type == DioExceptionType.receiveTimeout ||
      e.type == DioExceptionType.sendTimeout ||
      e.type == DioExceptionType.connectionError;
}

/// Jalankan [op] dengan maks 2 percobaan ulang, backoff eksponensial
/// (300 ms → 600 ms) + jitter acak ≤150 ms (Blueprint 5.1, Sapuan D-20).
Future<T> _withRetry<T>(Future<T> Function() op) async {
  var attempt = 0;
  while (true) {
    try {
      return await op();
    } catch (e) {
      attempt++;
      if (attempt > 2 || !_retryable(e)) rethrow;
      final backoffMs = 300 * (1 << (attempt - 1)) + Random().nextInt(150);
      await Future<void>.delayed(Duration(milliseconds: backoffMs));
    }
  }
}

class YtMusicProvider implements MusicProvider {
  final AppDb db;
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 5),
    receiveTimeout: const Duration(seconds: 10),
  ));

  YtMusicProvider(this.db) {
    directService = DirectStreamService(
      fetchWatchContext: (videoId) => fetchWatchContext(videoId),
      resolveDirectFormats: (track, {visitorData, signatureTimestamp, playerPoToken}) =>
          resolveDirectFormats(track,
              visitorData: visitorData,
              signatureTimestamp: signatureTimestamp,
              playerPoToken: playerPoToken),
      fetchText: (url) => fetchDirectText(url),
      readEnabled: () async =>
          await db.pref<bool>(DirectStreamService.killSwitchPrefKey) ?? true,
      onEvent: (kind, detail) => Observability.instance.log(kind, detail),
    );
  }

  /// Layanan jalur DIRECT-1 (Tahap 3) — dimiliki instance ini; dipakai
  /// [resolveStream], kabel pemulihan handler, dan layar Diagnostik.
  late final DirectStreamService directService;

  /// Pipa putar melaporkan URL DIRECT trek ini ditolak edge: layanan
  /// menandai sesi basi (penolakan ke-1) atau mengecualikan trek
  /// (penolakan ke-2). Lihat [DirectStreamService.markFetchRejected].
  void noteDirectFetchRejected(TrackKey key) =>
      directService.markFetchRejected(key);

  /// Pemanasan malas sesi DIRECT sesudah putar pertama (tak memblokir).
  void prewarmDirect(Track track) {
    if (track.providerId != id) return;
    unawaited(directService.prewarm(track.playableRef));
  }

  @override
  String get id => 'ytmusic';
  @override
  String get displayName => 'YouTube Music';

  Future<Map<String, dynamic>> _post(String endpoint, _ClientCtx ctx, Map<String, dynamic> body) async {
    final res = await _withRetry(() => _dio.post(
          'https://music.youtube.com/youtubei/v1/$endpoint?key=$_webKey&prettyPrint=false',
          data: {...ctx.context(), ...body},
          options: Options(headers: {
            'User-Agent': ctx.userAgent,
            'X-YouTube-Client-Name': _clientHeaderId(ctx.name),
            'X-YouTube-Client-Version': ctx.version,
            'Origin': 'https://music.youtube.com',
            'Referer': 'https://music.youtube.com/',
            'Content-Type': 'application/json',
          }),
        ));
    final data = res.data;
    if (data is! Map) throw ProviderDegradedException('respons bukan JSON pada $endpoint');
    return data.cast<String, dynamic>();
  }

  static String _clientHeaderId(String name) => switch (name) {
        'WEB_REMIX' => '67', 'WEB' => '1', 'ANDROID' => '3', 'IOS' => '5',
        'TVHTML5' => '7', 'TVHTML5_SIMPLY_EMBEDDED_PLAYER' => '85', 'ANDROID_VR' => '28',
        'VISIONOS' => '101',
        'WEB_EMBEDDED_PLAYER' => '56',
        _ => '1',
      };

  @override
  Future<SearchResults> search(String query) async {
    final res = await _post('search', _webRemix, {'query': query});
    final parsed = parseSearchResponse(res);
    if (parsed.isEmpty && res.toString().length > 200) {
      // Respons non-kosong tetapi tidak ada yang terurai = sumber berubah (Blueprint 5.5).
      throw ProviderDegradedException('bentuk hasil pencarian berubah');
    }
    await db.cacheTracks(parsed.songs);
    return parsed;
  }

  @override
  Future<List<String>> searchSuggestions(String query) async {
    try {
      final res = await _dio.get('https://music.youtube.com/youtubei/v1/music/get_search_suggestions?key=$_webKey',
          data: {..._webRemix.context(), 'input': query},
          options: Options(headers: {'User-Agent': _uaWeb, 'Content-Type': 'application/json'}, method: 'POST'));
      // Catatan: endpoint saran memakai POST; dio.get dengan method override di atas hanya untuk kompat.
      final data = res.data;
      final out = <String>[];
      void walk(Object? n) {
        if (n is Map) {
          for (final e in n.entries) {
            if (e.key == 'searchSuggestionRenderer') {
              final t = runsText(asMap(e.value)?['suggestion']);
              if (t != null) out.add(t);
            } else { walk(e.value); }
          }
        } else if (n is List) { for (final v in n) { walk(v); } }
      }
      walk(data);
      return out;
    } catch (_) {
      return const [];
    }
  }

  Future<ContentPage> _browse(String browseId, String kind) async {
    final res = await _post('browse', _webRemix, {'browseId': browseId});
    final tracks = collectTracks(res);
    final two = collectTwoRow(res);
    String title = '';
    String? subtitle, artwork;
    // Strapline header = nama artis halaman (bukti hidup Ronde Cacat
    // Metadata: header album membawa straplineTextOne "Rachel Chinouriri"
    // dengan run ber-browseId UC…; item treknya sendiri tanpa byline).
    String? pageArtist, pageArtistId;
    void findHeader(Object? n) {
      if (n is Map) {
        for (final e in n.entries) {
          if (e.key == 'musicDetailHeaderRenderer' || e.key == 'musicResponsiveHeaderRenderer' || e.key == 'musicImmersiveHeaderRenderer') {
            final m = asMap(e.value)!;
            title = simpleText(m['title']) ?? title;
            subtitle = runsText(m['subtitle']) ?? runsText(m['secondSubtitle']) ?? subtitle;
            artwork = thumbUrl(m['thumbnail'], minWidth: 200) ?? thumbUrl(m['croppedSquareThumbnailRenderer'] ?? m, minWidth: 200) ?? artwork;
            final strap = asMap(m['straplineTextOne']);
            final strapText = runsText(strap);
            if (strapText != null && strapText.trim().isNotEmpty) {
              pageArtist = strapText.trim();
              for (final r in asList(strap?['runs'])) {
                final id = browseIdOf(r);
                if (id != null && id.startsWith('UC')) {
                  pageArtistId = id;
                  break;
                }
              }
            }
          } else { findHeader(e.value); }
        }
      } else if (n is List) { for (final v in n) { findHeader(v); } }
    }
    findHeader(res);
    if (tracks.isEmpty && two.albums.isEmpty && two.artists.isEmpty) {
      throw ProviderDegradedException('halaman $kind kosong dari sumber');
    }
    // v4.4: item trek halaman album/playlist TIDAK membawa thumbnail sendiri di
    // respons sumber (bukti probe hidup) — warisi sampul halaman (perilaku YTM),
    // supaya baris trek tidak tampil sebagai ubin inisial padahal sampul ada.
    // Ronde Cacat Metadata: ARTIS juga diwariskan (strapline header untuk
    // album; judul header — nama artis itu sendiri — untuk halaman artis),
    // karena kolom byline item album KOSONG di sumbernya. Playlist TIDAK
    // mewariskan artis: strapline-nya adalah kurator, bukan artis trek.
    var pageTracks = tracks;
    final inheritArtist = kind == 'album'
        ? pageArtist
        : (kind == 'artist' ? (pageArtist ?? title) : null);
    pageTracks = inheritPageArtist(
      pageTracks,
      artist: inheritArtist,
      artistIds: [if (pageArtistId != null) pageArtistId!],
      artworkUrl: (kind == 'album' || kind == 'playlist') ? artwork : null,
    );
    // Cacat B (Poles Beranda): item lagu halaman ARTIS tidak membawa durasi
    // dari sumbernya sama sekali — selesaikan dari playlist lagu artis yang
    // ditautkan raknya (satu panggilan telusur tambahan, hanya bila memang
    // ada durasi yang hilang). Gagal total = durasi tetap kosong (baris
    // menyembunyikan kolomnya), bukan halaman gagal.
    if (kind == 'artist' && pageTracks.any((t) => t.duration == null)) {
      final songsId = topSongsPlaylistId(res);
      if (songsId != null) {
        try {
          final songsRes = await _post('browse', _webRemix, {'browseId': songsId});
          pageTracks = fillDurations(pageTracks, collectTracks(songsRes));
        } catch (_) {/* durasi tetap kosong; halaman tetap tampil */}
      }
    }
    await db.cacheTracks(pageTracks);
    final page = ContentPage(kind: kind, id: browseId, title: title, subtitle: subtitle,
        artworkUrl: artwork, tracks: pageTracks, albums: two.albums, relatedArtists: two.artists);
    // D-10 (Blueprint 2.1/2.2): relasi halaman→trek ditulis ke album_tracks /
    // remote_playlists(+tracks) — bahan cadangan offline halaman konten.
    if (kind == 'album' || kind == 'playlist') {
      await db.cacheBrowsePage(kind, page);
    }
    return page;
  }

  /// Umpan penemuan Beranda Jelajah (F2, PRD 5.1): dua umpan browse yang
  /// INDEPENDEN — kegagalan satu tidak menyeret yang lain (UI menanganinya
  /// per sumber). Respons non-kosong tanpa satu pun rak = bentuk berubah.
  Future<List<ExploreShelf>> getHomeFeed() => _exploreFeed('FEmusic_home');
  Future<List<ExploreShelf>> getChartsFeed() => _exploreFeed('FEmusic_charts');

  Future<List<ExploreShelf>> _exploreFeed(String browseId) async {
    final res = await _post('browse', _webRemix, {'browseId': browseId});
    final shelves = parseHomeFeedShelves(res);
    if (shelves.isEmpty) {
      if (res.toString().length > 200) {
        throw ProviderDegradedException('bentuk umpan $browseId berubah');
      }
      return const [];
    }
    for (final s in shelves) {
      if (s.tracks.isNotEmpty) await db.cacheTracks(s.tracks);
    }
    return shelves;
  }

  /// Halaman Mood & Genre sumber (Ronde Koreksi Komposisi F3, papan 04):
  /// ubin-ubin kategori NYATA dari `FEmusic_moods_and_genres` — judul,
  /// warna garis, dan tujuan telusurnya semua dari sumber. Respons
  /// non-kosong tanpa satu pun ubin = bentuk berubah (degradasi jujur,
  /// pola yang sama seperti umpan Jelajah).
  Future<List<MoodGenreSection>> getMoodGenres() async {
    final res = await _post('browse', _webRemix, {'browseId': 'FEmusic_moods_and_genres'});
    final sections = parseMoodGenreSections(res);
    if (sections.isEmpty) {
      if (res.toString().length > 200) {
        throw ProviderDegradedException('bentuk halaman mood & genre berubah');
      }
      return const [];
    }
    return sections;
  }

  /// Isi satu kategori Mood & Genre: telusur titik akhir ubinnya (browseId
  /// + params dari sumber) dan kumpulkan kartu playlist/album + trek dari
  /// rak-raknya. Judul halaman = judul ubin dari sumber ([titleHint]).
  /// Halaman tanpa isi apa pun = degradasi, bukan halaman kosong palsu.
  Future<ContentPage> getMoodPage(String browseId, String? params, String titleHint) async {
    final body = <String, dynamic>{'browseId': browseId};
    if (params != null && params.isNotEmpty) body['params'] = params;
    final res = await _post('browse', _webRemix, body);
    final tracks = <Track>[];
    final cards = <Album>[];
    final seenTracks = <String>{};
    final seenCards = <String>{};
    void addFrom(List<Track> ts, List<Album> as) {
      for (final t in ts) {
        if (seenTracks.add(t.id)) tracks.add(t);
      }
      for (final a in as) {
        if (seenCards.add(a.id)) cards.add(a);
      }
    }

    for (final s in parseHomeFeedShelves(res)) {
      addFrom(s.tracks, [...s.playlists, ...s.albums]);
    }
    if (tracks.isEmpty && cards.isEmpty) {
      final two = collectTwoRow(res);
      addFrom(collectTracks(res), [...two.playlists, ...two.albums]);
    }
    if (tracks.isEmpty && cards.isEmpty) {
      throw ProviderDegradedException('halaman kategori mood kosong dari sumber');
    }
    if (tracks.isNotEmpty) await db.cacheTracks(tracks);
    return ContentPage(
      kind: 'mood',
      id: browseId,
      title: titleHint,
      tracks: tracks,
      albums: cards,
    );
  }

  @override
  Future<ContentPage> getAlbum(String albumId) => _browse(albumId, 'album');
  @override
  Future<ContentPage> getPlaylist(String playlistId) =>
      _browse(playlistId.startsWith('VL') ? playlistId : 'VL$playlistId', 'playlist');
  @override
  Future<ContentPage> getArtist(String artistId) => _browse(artistId, 'artist');

  @override
  Future<List<Track>> getRelated(Track seed) async {
    // v4.4.2: sertakan playlistId automix RDAMVM<videoId>. Bukti probe hidup:
    // `next` polos (videoId saja) hanya mengembalikan benih itu sendiri —
    // tangga 2 MATI di sebagian jaringan/wilayah; dengan RDAMVM server
    // mengembalikan panel automix penuh (30–50 item) yang memang tangga 2
    // maksudkan ("radio/related sumber"). Isinya tetap melewati gerbang
    // mutu tangga — panel sumber tidak pernah ditelan mentah.
    final res = await _post('next', _webRemix, {
      'videoId': seed.playableRef, 'isAudioOnly': true,
      'playlistId': 'RDAMVM${seed.playableRef}',
      'tunerSettingValue': 'AUTOMIX_SETTING_NORMAL',
    });
    final tracks = collectTracks(res).where((t) => t.id != seed.id).toList();
    await db.cacheTracks(tracks);
    return tracks;
  }

  /// Resolusi SATU trek menurut ID-nya dari sumber — bahan lapisan
  /// penyembuhan metadata (rekam lama yang tersimpan tanpa artis/sampul).
  /// Panel `next` untuk videoId itu memuat item treknya sendiri dengan
  /// byline + sampul penuh. Null bila sumber tidak menjawab / trek tidak
  /// ditemukan — pemanggil menampilkan rekam apa adanya. Sengaja TIDAK
  /// meng-cache panel lain: hanya trek yang diminta yang dikembalikan.
  Future<Track?> resolveTrackById(String videoId) async {
    try {
      final res = await _post('next', _webRemix, {
        'videoId': videoId,
        'isAudioOnly': true,
        'playlistId': 'RDAMVM$videoId',
        'tunerSettingValue': 'AUTOMIX_SETTING_NORMAL',
      });
      for (final t in collectTracks(res)) {
        if (t.id == videoId) return t;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<List<Track>> getSameArtist(Track seed) async {
    if (seed.artistIds.isEmpty) return const [];
    final page = await getArtist(seed.artistIds.first);
    return page.tracks.where((t) => t.id != seed.id).toList();
  }

  @override
  Future<List<Artist>> getSimilarArtists(Track seed) async {
    if (seed.artistIds.isEmpty) return const [];
    final page = await getArtist(seed.artistIds.first);
    return page.relatedArtists.where((a) => a.id != seed.artistIds.first).toList();
  }

  @override
  Future<List<Track>> getSameGenre(Track seed) async {
    // Jaring pengaman tangga 4: pencarian campuran "artis songs" TANPA parameter
    // filter. Bukti probe hidup (putaran v4.3): nilai _filterSongs yang lama
    // membuat server mengembalikan halaman berisi 20 item KATEGORI dan 0 trek —
    // tangga ini mati total; pencarian campuran yang sama mengurai 14 trek.
    // v4.4.2: artistNames item VIDEO membawa byline mentah ("Arctic Monkeys •
    // 16M views") — query harus memakai nama artisnya saja, bukan seluruh
    // byline, agar jaring pengaman benih video tidak mencari sampah.
    final artist = seed.artistNames.split('•').first.trim();
    final q = '${artist.isEmpty ? seed.artistNames : artist} songs';
    final res = await _post('search', _webRemix, {'query': q});
    final tracks = collectTracks(res).where((t) => t.id != seed.id).toList();
    await db.cacheTracks(tracks);
    return tracks;
  }

  /// Satu percobaan klien pada endpoint player — dipakai jalur normal & diagnostik.
  /// D-21: penolakan versi (HTTP 400) menaiki tabel versi cadangan klien ini
  /// (maks 3 versi) sebelum menyerah; penolakan lain langsung dilaporkan.
  /// Mengembalikan info aliran (null bila klien ini tidak menghasilkan URL audio
  /// langsung) beserta uraian hasil untuk laporan. Galat DILEMPAR ke pemanggil.
  Future<({StreamInfo? info, String detail, bool region})> _probeClient(
      _ClientCtx client, String videoId, StreamQuality quality) async {
    final versions = _clientVersionFallbacks[client.name] ?? [client.version];
    Object? lastError;
    for (final v in versions.take(3)) {
      final ctx = v == client.version
          ? client
          : _ClientCtx(client.name, v, client.userAgent, client.extra);
      try {
        return await _probeClientOnce(ctx, videoId, quality);
      } on DioException catch (e) {
        if (e.response?.statusCode == 400) {
          lastError = e;
          continue; // naik tangga versi (Blueprint 5.5)
        }
        rethrow;
      }
    }
    throw lastError ?? StreamResolutionException('semua versi klien ${client.name} ditolak');
  }

  Future<({StreamInfo? info, String detail, bool region})> _probeClientOnce(
      _ClientCtx client, String videoId, StreamQuality quality) async {
    final body = <String, dynamic>{
      'videoId': videoId,
      'playbackContext': {'contentPlaybackContext': {'vis': 0, 'splay': false, 'lactMilliseconds': '-1',
          'signatureTimestamp': await _signatureTimestamp()}},
      'racyCheckOk': true, 'contentCheckOk': true,
    };
    final Map<String, dynamic> res;
    if (client.name == 'TVHTML5_SIMPLY_EMBEDDED_PLAYER') {
      body['context'] = {...client.context()['context'] as Map, 'thirdParty': {'embedUrl': 'https://www.youtube.com/'}};
      res = await _postWithContext('player', client, body);
    } else {
      res = await _post('player', client, body);
    }
    final ps = asMap(res['playabilityStatus']);
    final status = ps?['status'] as String? ?? '(tanpa status)';
    if (status != 'OK') {
      final reason = ps?['reason'] as String? ?? simpleText(ps?['messages']) ?? '';
      // D-22: tandai penolakan wilayah agar pemanggil bisa menyatakan sebab
      // sebenarnya, bukan kegagalan generik.
      return (info: null, detail: 'playabilityStatus=$status${reason.isEmpty ? '' : ' — $reason'}',
          region: isRegionUnavailable(status, reason));
    }
    final s = pickStreamFormat(res, quality);
    if (s != null) {
      final sd = asMap(res['streamingData']);
      final total = [...asList(sd?['adaptiveFormats']), ...asList(sd?['formats'])].length;
      return (info: s, detail: 'OK — $total format, URL audio langsung terpilih (mime ${s.mimeType}, bitrate ${s.bitrate ?? '-'})', region: false);
    }
    final sd = asMap(res['streamingData']);
    final fmts = <Map<String, dynamic>>[
      ...asList(sd?['adaptiveFormats']).map((e) => asMap(e)).whereType<Map<String, dynamic>>(),
      ...asList(sd?['formats']).map((e) => asMap(e)).whereType<Map<String, dynamic>>(),
    ];
    final ciphered = fmts.where((f) => f['url'] is! String).length;
    return (info: null, detail: 'OK tetapi 0 URL audio langsung (${fmts.length} format, $ciphered tanpa URL/cipher)', region: false);
  }

  @override
  Future<StreamInfo> resolveStream(Track track, StreamQuality quality,
      {bool Function()? stillWanted}) async {
    // DIRECT-1 lebih dulu (Tahap 3): format adaptif per tingkat kualitas
    // lewat konstruksi E3. Kegagalan jalur apa pun (konteks/solver/
    // minter/403) jatuh ke rantai warisan di bawah TANPA mengubah
    // perilakunya — pengguna tidak melihat jeda maupun error tambahan.
    // DirectSuperseded dari layanan (pekerjaan dibuang dari antrean karena
    // perintah pemintanya sudah dikalahkan, Ronde 8054) DIBIARKAN naik:
    // jatuh ke rantai warisan akan membakar resolusi kedua untuk
    // pekerjaan yang memang sudah mati.
    final direct = await directService.tryResolve(track, quality,
        stillWanted: stillWanted);
    if (direct != null) {
      await db.cacheStream(track.key, direct);
      return direct;
    }
    final info = await _resolveLegacyChain(track, quality);
    directService.noteLegacyPath();
    return info;
  }

  /// Rantai resolusi warisan (pra-Tahap 3, tak berubah): cache DB yang
  /// cocok tingkat → rantai klien InnerTube → pengecualian jujur.
  Future<StreamInfo> _resolveLegacyChain(Track track, StreamQuality quality) async {
    final cached = await db.cachedStream(track.key);
    // Cache hanya berlaku bila tingkatnya cocok (streamCacheFitsQuality):
    // entri Normal tidak boleh menyabotase permintaan Rendah hemat data.
    if (cached != null && streamCacheFitsQuality(cached, quality)) return cached;
    Object? lastError;
    var regionSeen = false;
    for (final client in _streamClients) {
      try {
        final r = await _probeClient(client, track.playableRef, quality);
        if (r.info != null) { await db.cacheStream(track.key, r.info!); return r.info!; }
        if (r.region) regionSeen = true;
      } catch (e) {
        lastError = e;
        continue; // turun rantai (Blueprint 5.4)
      }
    }
    // D-22: semua klien menolak karena wilayah → nyatakan apa adanya.
    if (regionSeen) {
      throw RegionUnavailableException('tidak tersedia di wilayah ini: ${track.title}');
    }
    throw StreamResolutionException('semua klien gagal untuk ${track.title}: $lastError');
  }

  /// Jalur DEBUG Diagnostik Putar (v4.1): menjalankan rantai resolusi TANPA cache —
  /// berhenti di keberhasilan pertama persis seperti jalur normal, dan melaporkan hasil
  /// SETIAP klien yang dicoba. Tidak mengubah perilaku normal sedikit pun.
  Future<List<ClientAttempt>> debugResolveChain(Track track, StreamQuality quality) async {
    final out = <ClientAttempt>[];
    for (final client in _streamClients) {
      try {
        final r = await _probeClient(client, track.playableRef, quality);
        out.add(ClientAttempt(client: client.name, ok: r.info != null, detail: r.detail, info: r.info));
        if (r.info != null) break;
      } catch (e) {
        out.add(ClientAttempt(client: client.name, ok: false, detail: 'galat: ${describeError(e)}'));
      }
    }
    return out;
  }

  /// Konteks klien untuk probe diagnostik per klien (Ronde Klien InnerTube):
  /// IOS / TVHTML5 / ANDROID diambil dari rantai aliran produksi (konteks
  /// yang sama persis); WEB_EMBEDDED_PLAYER hanya hidup di jalur diagnostik
  /// ini selama ronde berjalan — belum masuk rantai produksi.
  _ClientCtx? _debugClientCtx(String name) {
    for (final c in _streamClients) {
      if (c.name == name) return c;
    }
    if (name == 'WEB_EMBEDDED_PLAYER') {
      return _ClientCtx('WEB_EMBEDDED_PLAYER', '1.20250821.01.00', _uaWeb);
    }
    if (name == 'WEB_REMIX') return _webRemix;
    // Keluarga SABR untuk Probe Plafon (Batch 0.5) — identitas persis
    // katalog innertubex (terekstrak dari DEX Auralys): nama konteks tetap
    // nama keluarga InnerTube-nya; kunci panggil dibedakan akhiran _SABR.
    if (name == 'VISIONOS') {
      return _ClientCtx('VISIONOS', '1.02',
          'Mozilla/5.0 (Macintosh; Intel Mac OS X 15_7_3) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15',
          {'deviceMake': 'Apple', 'deviceModel': 'RealityDevice17,1', 'osName': 'visionOS', 'osVersion': '26.5.23O471'});
    }
    if (name == 'WEB_REMIX_SABR') {
      return _ClientCtx('WEB_REMIX', '1.20260707.12.00', kDirectPathUserAgent);
    }
    // Tahap 2 (Mesin Penyeberangan 2.0): identitas WEB persis katalog
    // innertubex v0.11.2 (YouTubeClient.WEB: versi 2.20260708.00.00,
    // UA Firefox/140) — konteks resolusi untuk klien WEB_SABR.
    if (name == 'WEB_SABR') {
      return _ClientCtx('WEB', '2.20260708.00.00',
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:140.0) Gecko/20100101 Firefox/140.0');
    }
    if (name == 'IOS_SABR') {
      return _ClientCtx('IOS', '21.26.4',
          'com.google.ios.youtube/21.26.4 (iPhone16,2; U; CPU iOS 18_3_2 like Mac OS X;)',
          {'deviceModel': 'iPhone16,2', 'osName': 'iOS', 'osVersion': '18.3.2'});
    }
    if (name == 'TVHTML5_SABR') {
      return _ClientCtx('TVHTML5', '7.20260707.07.00',
          'Mozilla/5.0 (ChromiumStylePlatform) Cobalt/25.lts.30.1034943-gold (Starboard/15, Sony; BRAVIA 4K VH2; Android/9)');
    }
    return null;
  }

  /// Probe resolusi SATU klien bernama, tanpa cache, untuk Diagnostik Putar
  /// (Ronde Klien InnerTube, Fase A): status playability, daftar format
  /// audio ADAPTIF ber-URL langsung, pilihan itag per tingkat kualitas, dan
  /// fakta URL pilihan Normal (host + NAMA parameter). URL mentah hanya
  /// dipegang di memori ([ClientStreamProbe.info]) untuk probe rentang /
  /// putar harness — tidak pernah ditulis ke laporan atau log. Penolakan
  /// versi (HTTP 400) menaiki tangga versi klien, sama seperti jalur normal.
  Future<ClientStreamProbe> debugProbeNamedClient(String clientName, Track track) async {
    final base = _debugClientCtx(clientName);
    if (base == null) {
      return ClientStreamProbe(
          client: clientName, version: '-', userAgent: '',
          playability: '(klien tak dikenal)', reason: '', error: 'konteks klien tidak ada');
    }
    final versions = _clientVersionFallbacks[clientName] ?? [base.version];
    Object? lastError;
    for (final v in versions.take(3)) {
      final ctx = v == base.version
          ? base
          : _ClientCtx(base.name, v, base.userAgent, base.extra);
      try {
        return await _probeNamedClientOnce(ctx, track);
      } on DioException catch (e) {
        if (e.response?.statusCode == 400) {
          lastError = e;
          continue; // naik tangga versi, sama seperti _probeClient
        }
        return ClientStreamProbe(
            client: clientName, version: v, userAgent: ctx.userAgent,
            playability: '(galat HTTP)', reason: '', error: describeError(e));
      } catch (e) {
        return ClientStreamProbe(
            client: clientName, version: v, userAgent: ctx.userAgent,
            playability: '(galat)', reason: '', error: describeError(e));
      }
    }
    return ClientStreamProbe(
        client: clientName, version: versions.first, userAgent: base.userAgent,
        playability: '(ditolak HTTP 400 semua versi)', reason: '',
        error: lastError == null ? 'semua versi ditolak' : describeError(lastError));
  }

  /// Probe resolusi SATU klien bernama DENGAN PoToken terlampir (Diagnostik
  /// Putar — Ronde Probe PoToken, Fase B): token dikirim persis seperti
  /// klien web resmi — `serviceIntegrityDimensions.poToken` pada badan
  /// permintaan player — dan, bila sesi pencetak memberi [visitorData],
  /// konteks klien menyatakannya agar sesi resolusi sama dengan sesi
  /// cetak. Token TIDAK PERNAH dicatat; bentuk hasil sama dengan
  /// [debugProbeNamedClient] ([ClientStreamProbe], URL mentah hanya di
  /// memori). Selain dua tambahan itu, permintaannya identik dengan jalur
  /// debug yang terbukti — jalur produksi tidak berubah sama sekali.
  Future<ClientStreamProbe> debugProbeWithPoToken(String clientName, Track track,
      {String? playerPoToken, String? visitorData}) async {
    final base = _debugClientCtx(clientName);
    if (base == null) {
      return ClientStreamProbe(
          client: clientName, version: '-', userAgent: '',
          playability: '(klien tak dikenal)', reason: '', error: 'konteks klien tidak ada');
    }
    final versions = _clientVersionFallbacks[clientName] ?? [base.version];
    Object? lastError;
    for (final v in versions.take(3)) {
      final ctx = v == base.version
          ? base
          : _ClientCtx(base.name, v, base.userAgent, base.extra);
      try {
        return await _probeWithPoOnce(ctx, track,
            playerPoToken: playerPoToken, visitorData: visitorData);
      } on DioException catch (e) {
        if (e.response?.statusCode == 400) {
          lastError = e;
          continue; // naik tangga versi, sama seperti _probeClient
        }
        return ClientStreamProbe(
            client: clientName, version: v, userAgent: ctx.userAgent,
            playability: '(galat HTTP)', reason: '', error: describeError(e));
      } catch (e) {
        return ClientStreamProbe(
            client: clientName, version: v, userAgent: ctx.userAgent,
            playability: '(galat)', reason: '', error: describeError(e));
      }
    }
    return ClientStreamProbe(
        client: clientName, version: versions.first, userAgent: base.userAgent,
        playability: '(ditolak HTTP 400 semua versi)', reason: '',
        error: lastError == null ? 'semua versi ditolak' : describeError(lastError));
  }

  // ================= Diagnostik F3 Batch 0 — Tahap 1: visitorData =================
  // Bahan yang diisolasi ronde ini: visitorData dari KONTEKS TONTON subjek
  // itu sendiri (halaman watch per videoId), TANPA PoToken — berbeda dari
  // Ronde Probe PoToken (2026-11-05) yang selalu memasangkan token dengan
  // visitorData sesi minter halaman utama. Semua metode di blok ini hanya
  // dipakai layar Diagnostik Putar; jalur produksi tidak berubah.

  /// Kunci publik yang tertanam di klien web resmi www.youtube.com (kelas
  /// yang sama dengan [_webKey] untuk music.youtube.com — bukan kredensial
  /// pengguna mana pun).
  static const _wwwWebKey = 'AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8';

  /// Ambil konteks tonton anonim untuk [videoId]: visitorData dan (bila
  /// halaman memberinya) signatureTimestamp DARI halaman watch subjek itu.
  /// Nilai visitorData hanya hidup di memori pemanggil — yang boleh dicatat
  /// hanyalah [source] dan panjangnya. Sumber dicoba berurutan: halaman
  /// watch music.youtube.com → watch www.youtube.com → endpoint visitor_id.
  Future<({String? visitorData, String source, int? signatureTimestamp})>
      debugFetchWatchContext(String videoId) async {
    Future<String?> fetchHtml(String url) async {
      try {
        final res = await _dio.get<String>(url,
            options: Options(headers: {
              'User-Agent': _uaWeb,
              'Accept-Language': 'en-US,en;q=0.9',
            }, responseType: ResponseType.plain));
        return res.data;
      } catch (_) {
        return null;
      }
    }

    for (final (source, url) in [
      ('watch-music', 'https://music.youtube.com/watch?v=$videoId'),
      ('watch-www', 'https://www.youtube.com/watch?v=$videoId'),
    ]) {
      final html = await fetchHtml(url);
      if (html == null) continue;
      final m = RegExp(r'"VISITOR_DATA":"([^"]+)"').firstMatch(html) ??
          RegExp(r'"visitorData":"([^"]+)"').firstMatch(html);
      final vd = m?.group(1);
      if (vd != null && vd.isNotEmpty) {
        final stsM = RegExp(r'"signatureTimestamp":(\d+)').firstMatch(html);
        return (
          visitorData: vd,
          source: source,
          signatureTimestamp: stsM == null ? null : int.tryParse(stsM.group(1)!),
        );
      }
    }
    // Jalur API: POST visitor_id dengan konteks WEB polos (tanpa sesi).
    try {
      final res = await _dio.post(
        'https://www.youtube.com/youtubei/v1/visitor_id?key=$_wwwWebKey&prettyPrint=false',
        data: const _ClientCtx('WEB', '2.20250901.01.00', _uaWeb).context(),
        options: Options(headers: {
          'User-Agent': _uaWeb,
          'X-YouTube-Client-Name': '1',
          'X-YouTube-Client-Version': '2.20250901.01.00',
          'Content-Type': 'application/json',
        }),
      );
      final data = res.data;
      if (data is Map) {
        final vd = asMap(data['responseContext'])?['visitorData'] as String?;
        if (vd != null && vd.isNotEmpty) {
          return (visitorData: vd, source: 'visitor_id-api', signatureTimestamp: null);
        }
      }
    } catch (_) {/* semua sumber gagal — pemanggil yang menilai */}
    return (visitorData: null, source: '(semua sumber gagal)', signatureTimestamp: null);
  }

  /// Probe resolusi SATU klien bernama dengan visitorData konteks tonton
  /// (Diagnostik F3 Batch 0, Tahap 1): konteks klien menyatakan visitorData;
  /// TANPA PoToken. [visitorHeader] menambahkan header X-Goog-Visitor-Id;
  /// [webHost] memakai host www.youtube.com + kunci web www + Origin/Referer
  /// halaman watch (varian keluarga WEB murni); selain itu host
  /// music.youtube.com seperti jalur debug terbukti. [signatureTimestamp]
  /// menimpa sts bawaan dengan sts sesi tonton bila diberikan.
  Future<ClientStreamProbe> debugProbeWithVisitor(String clientName, Track track,
      {required String visitorData,
      bool visitorHeader = false,
      bool webHost = false,
      int? signatureTimestamp}) async {
    final base = _debugClientCtx(clientName);
    if (base == null) {
      return ClientStreamProbe(
          client: clientName, version: '-', userAgent: '',
          playability: '(klien tak dikenal)', reason: '', error: 'konteks klien tidak ada');
    }
    final versions = _clientVersionFallbacks[clientName] ?? [base.version];
    Object? lastError;
    for (final v in versions.take(3)) {
      final ctx = v == base.version
          ? base
          : _ClientCtx(base.name, v, base.userAgent, base.extra);
      try {
        return await _probeWithVisitorOnce(ctx, track,
            visitorData: visitorData,
            visitorHeader: visitorHeader,
            webHost: webHost,
            signatureTimestamp: signatureTimestamp);
      } on DioException catch (e) {
        if (e.response?.statusCode == 400) {
          lastError = e;
          continue; // naik tangga versi, sama seperti jalur debug lain
        }
        return ClientStreamProbe(
            client: clientName, version: v, userAgent: ctx.userAgent,
            playability: '(galat HTTP)', reason: '', error: describeError(e));
      } catch (e) {
        return ClientStreamProbe(
            client: clientName, version: v, userAgent: ctx.userAgent,
            playability: '(galat)', reason: '', error: describeError(e));
      }
    }
    return ClientStreamProbe(
        client: clientName, version: versions.first, userAgent: base.userAgent,
        playability: '(ditolak HTTP 400 semua versi)', reason: '',
        error: lastError == null ? 'semua versi ditolak' : describeError(lastError));
  }

  Future<ClientStreamProbe> _probeWithVisitorOnce(_ClientCtx client, Track track,
      {required String visitorData,
      bool visitorHeader = false,
      bool webHost = false,
      int? signatureTimestamp}) async {
    final inner = (client.context()['context'] as Map).cast<String, dynamic>();
    (inner['client'] as Map<String, dynamic>)['visitorData'] = visitorData;
    final body = <String, dynamic>{
      'videoId': track.playableRef,
      'context': inner,
      'playbackContext': {'contentPlaybackContext': {'vis': 0, 'splay': false, 'lactMilliseconds': '-1',
          'signatureTimestamp': signatureTimestamp ?? await _signatureTimestamp()}},
      'racyCheckOk': true, 'contentCheckOk': true,
    };
    final res = await _postDebugPlayer(client, body,
        videoId: track.playableRef,
        visitorHeader: visitorHeader ? visitorData : null,
        webHost: webHost);
    return _probeFromPlayerResponse(client, res);
  }

  /// Probe resolusi SATU klien bernama dengan konteks sesi
  /// TERAUTENTIKASI ala Auralys §2b (Probe Login, Batch 0.7 F3):
  /// header Cookie utuh + Authorization SAPISIDHASH + X-Goog-AuthUser
  /// (SESSION_INDEX) dikirim ke endpoint player di host music — persis
  /// cara sesi Auralys menempel ke resolusi (`playerWithSession`).
  /// Nilai cookie/token HANYA transit di memori panggilan ini; tidak
  /// pernah dicatat. [visitorData] sesi (bila terpanen) juga dinyatakan
  /// di konteks klien + header X-Goog-Visitor-Id. Tangga versi sama
  /// seperti jalur debug lain. Jalur produksi TIDAK memakai metode ini.
  Future<ClientStreamProbe> debugProbeWithAuth(String clientName, Track track,
      {required String cookieHeader,
      required String authorization,
      String? authUser,
      String? visitorData}) async {
    final base = _debugClientCtx(clientName);
    if (base == null) {
      return ClientStreamProbe(
          client: clientName, version: '-', userAgent: '',
          playability: '(klien tak dikenal)', reason: '', error: 'konteks klien tidak ada');
    }
    final versions = _clientVersionFallbacks[clientName] ?? [base.version];
    Object? lastError;
    for (final v in versions.take(3)) {
      final ctx = v == base.version
          ? base
          : _ClientCtx(base.name, v, base.userAgent, base.extra);
      try {
        return await _probeWithAuthOnce(ctx, track,
            cookieHeader: cookieHeader,
            authorization: authorization,
            authUser: authUser,
            visitorData: visitorData);
      } on DioException catch (e) {
        if (e.response?.statusCode == 400) {
          lastError = e;
          continue; // naik tangga versi, sama seperti jalur debug lain
        }
        return ClientStreamProbe(
            client: clientName, version: v, userAgent: ctx.userAgent,
            playability: '(galat HTTP)', reason: '', error: describeError(e));
      } catch (e) {
        return ClientStreamProbe(
            client: clientName, version: v, userAgent: ctx.userAgent,
            playability: '(galat)', reason: '', error: describeError(e));
      }
    }
    return ClientStreamProbe(
        client: clientName, version: versions.first, userAgent: base.userAgent,
        playability: '(ditolak HTTP 400 semua versi)', reason: '',
        error: lastError == null ? 'semua versi ditolak' : describeError(lastError));
  }

  Future<ClientStreamProbe> _probeWithAuthOnce(_ClientCtx client, Track track,
      {required String cookieHeader,
      required String authorization,
      String? authUser,
      String? visitorData}) async {
    final inner = (client.context()['context'] as Map).cast<String, dynamic>();
    if (visitorData != null) {
      (inner['client'] as Map<String, dynamic>)['visitorData'] = visitorData;
    }
    final body = <String, dynamic>{
      'videoId': track.playableRef,
      'context': inner,
      'playbackContext': {'contentPlaybackContext': {'vis': 0, 'splay': false, 'lactMilliseconds': '-1',
          'signatureTimestamp': await _signatureTimestamp()}},
      'racyCheckOk': true, 'contentCheckOk': true,
    };
    final res = await _postDebugPlayer(client, body,
        videoId: track.playableRef,
        extraHeaders: {
          'Cookie': cookieHeader,
          'Authorization': authorization,
          if (authUser != null) 'X-Goog-AuthUser': authUser,
          if (visitorData != null) 'X-Goog-Visitor-Id': visitorData,
        });
    return _probeFromPlayerResponse(client, res);
  }

  /// POST endpoint player khusus diagnostik (F3 Batch 0): host, kunci,
  /// Origin/Referer dapat dipilih per varian; header X-Goog-Visitor-Id
  /// opsional. Jalur produksi TIDAK memakai metode ini.
  Future<Map<String, dynamic>> _postDebugPlayer(_ClientCtx ctx, Map<String, dynamic> body,
      {required String videoId,
      String? visitorHeader,
      bool webHost = false,
      Map<String, String>? extraHeaders}) async {
    final res = await _withRetry(() => _dio.post(
          '${webHost ? 'https://www.youtube.com' : 'https://music.youtube.com'}'
          '/youtubei/v1/player?key=${webHost ? _wwwWebKey : _webKey}&prettyPrint=false',
          data: body,
          options: Options(headers: {
            'User-Agent': ctx.userAgent,
            'X-YouTube-Client-Name': _clientHeaderId(ctx.name),
            'X-YouTube-Client-Version': ctx.version,
            'Origin': webHost ? 'https://www.youtube.com' : 'https://music.youtube.com',
            'Referer': webHost
                ? 'https://www.youtube.com/watch?v=$videoId'
                : 'https://music.youtube.com/',
            'Content-Type': 'application/json',
            if (visitorHeader != null) 'X-Goog-Visitor-Id': visitorHeader,
            if (extraHeaders != null) ...extraHeaders,
          }),
        ));
    final data = res.data;
    if (data is! Map) throw ProviderDegradedException('respons player bukan JSON (debug)');
    return data.cast<String, dynamic>();
  }

  /// Tubuh permintaan player untuk keluarga WEB (konteks + visitorData +
  /// signatureTimestamp di playbackContext + token integritas opsional).
  /// Dipakai jalur DIRECT-1 produksi dan probe SABR diagnostik.
  Future<Map<String, dynamic>> _sabrPlayerBody(
    _ClientCtx client,
    Track track, {
    String? visitorData,
    int? signatureTimestamp,
    String? playerPoToken,
  }) async {
    final inner = (client.context()['context'] as Map).cast<String, dynamic>();
    if (visitorData != null) {
      (inner['client'] as Map<String, dynamic>)['visitorData'] = visitorData;
    }
    return <String, dynamic>{
      'videoId': track.playableRef,
      'context': inner,
      'playbackContext': {'contentPlaybackContext': {'vis': 0, 'splay': false, 'lactMilliseconds': '-1',
          'signatureTimestamp': signatureTimestamp ?? await _signatureTimestamp()}},
      'racyCheckOk': true,
      'contentCheckOk': true,
      if (playerPoToken != null)
        'serviceIntegrityDimensions': {'poToken': playerPoToken},
    };
  }

  /// Urai respons player menjadi [ClientStreamProbe] — semantik identik
  /// dengan jalur debug terbukti ([_probeNamedClientOnce]).
  ClientStreamProbe _probeFromPlayerResponse(_ClientCtx client, Map<String, dynamic> res) {
    final ps = asMap(res['playabilityStatus']);
    final status = ps?['status'] as String? ?? '(tanpa status)';
    final reason = ps?['reason'] as String? ?? simpleText(ps?['messages']) ?? '';
    if (status != 'OK') {
      return ClientStreamProbe(
          client: client.name, version: client.version, userAgent: client.userAgent,
          playability: status, reason: reason);
    }
    final sd = asMap(res['streamingData']);
    final adaptive = asList(sd?['adaptiveFormats'])
        .map((e) => asMap(e)).whereType<Map<String, dynamic>>().toList();
    final audio = adaptive.where((f) {
      final mime = (f['mimeType'] as String?) ?? '';
      return mime.startsWith('audio/') && f['url'] is String;
    }).toList();
    final totalFormats = adaptive.length + asList(sd?['formats']).length;
    final adaptiveAudioAny = adaptive
        .where((f) => ((f['mimeType'] as String?) ?? '').startsWith('audio/'))
        .length;
    final info = pickStreamFormat(res, StreamQuality.normal);
    final uri = info == null ? null : Uri.tryParse(info.url);
    return ClientStreamProbe(
      client: client.name, version: client.version, userAgent: client.userAgent,
      playability: status, reason: reason,
      audioFormats: [
        for (final f in audio)
          (itag: (f['itag'] as num?)?.toInt() ?? -1,
           mime: (f['mimeType'] as String?) ?? '',
           bitrate: (f['bitrate'] as num?)?.toInt(),
           contentLength: int.tryParse('${f['contentLength'] ?? ''}')),
      ],
      totalFormats: totalFormats,
      adaptiveTotal: adaptive.length,
      adaptiveAudioAny: adaptiveAudioAny,
      tierItags: _tierItagsOf(audio),
      info: info,
      urlHost: uri?.host,
      urlParams: uri == null ? const [] : (uri.queryParameters.keys.toList()..sort()),
    );
  }

  // ================= Diagnostik F3 Batch 0 — Tahap 2: decipher =================
  // Rute halaman watch: respons player RESMI yang tertanam di halaman
  // (ytInitialPlayerResponse) membawa format audio adaptif TERCIPHER
  // (signatureCipher). Nilai URL & cipher hanya hidup di memori; laporan
  // hanya boleh memuat playability, itag, host, NAMA parameter, panjang.

  /// Ambil teks polos (dipakai mengambil base.js player resmi; jalur
  /// DIRECT-1 produksi mengambil JS player lewat sini).
  Future<String?> fetchDirectText(String url) async {
    try {
      final res = await _dio.get<String>(url,
          options: Options(headers: {'User-Agent': _uaWeb}, responseType: ResponseType.plain));
      return res.data;
    } catch (_) {
      return null;
    }
  }

  /// Nama diagnostik lama untuk [fetchDirectText].
  Future<String?> debugFetchText(String url) => fetchDirectText(url);

  /// Ekstrak objek JSON yang dimulai di [start] (posisi '{') dengan
  /// penyeimbang kurung sadar-string. Null bila tidak seimbang.
  static String? _extractJsonAt(String src, int start) {
    var depth = 0;
    var inStr = false;
    var esc = false;
    for (var i = start; i < src.length; i++) {
      final c = src[i];
      if (inStr) {
        if (esc) {
          esc = false;
        } else if (c == '\\') {
          esc = true;
        } else if (c == '"') {
          inStr = false;
        }
        continue;
      }
      if (c == '"') {
        inStr = true;
      } else if (c == '{') {
        depth++;
      } else if (c == '}') {
        depth--;
        if (depth == 0) return src.substring(start, i + 1);
      }
    }
    return null;
  }

  /// Urai format audio adaptif (langsung & tercipher) dari respons player.
  static List<WatchFormat> _watchAudioFormats(Map<String, dynamic> res) {
    final sd = asMap(res['streamingData']);
    final audio = <WatchFormat>[];
    for (final e in asList(sd?['adaptiveFormats'])) {
      final f = asMap(e);
      if (f == null) continue;
      final mime = (f['mimeType'] as String?) ?? '';
      if (!mime.startsWith('audio/')) continue;
      final direct = f['url'] as String?;
      String? cs, sp, base;
      final cipher = (f['signatureCipher'] as String?) ?? (f['cipher'] as String?);
      if (direct == null && cipher != null) {
        final q = Uri.splitQueryString(cipher);
        cs = q['s'];
        sp = q['sp'] ?? 'signature';
        base = q['url'];
      }
      audio.add(WatchFormat(
        itag: (f['itag'] as num?)?.toInt() ?? -1,
        mime: mime,
        bitrate: (f['bitrate'] as num?)?.toInt(),
        contentLength: int.tryParse('${f['contentLength'] ?? ''}'),
        directUrl: direct,
        cipherS: cs,
        cipherSp: sp ?? 'signature',
        cipherBaseUrl: base,
      ));
    }
    return audio;
  }

  /// Resolusi player InnerTube klien [clientName] dengan visitorData pada
  /// posisi `context.visitorData` (saudara `client`) — rute X2 Tahap 2:
  /// keluarga WEB menerbitkan format audio TERCIPHER yang kemudian
  /// di-decipher harness. URL & cipher hanya di memori.
  Future<WatchPlayerProbe> debugResolveCiphered(String clientName, Track track,
      {String? visitorData, int? signatureTimestamp}) async {
    var tahap = 'ctx';
    try {
      final client = _debugClientCtx(clientName);
      if (client == null) {
        return WatchPlayerProbe(
            playability: '(klien tak dikenal)', reason: '',
            error: 'konteks klien $clientName tidak ada', visitorDataLength: 0, audio: const []);
      }
      tahap = 'konteks';
      final inner = Map<String, dynamic>.from(client.context()['context'] as Map);
      if (visitorData != null) inner['visitorData'] = visitorData;
      if (clientName == 'WEB_EMBEDDED_PLAYER' || clientName == 'TVHTML5_SIMPLY_EMBEDDED_PLAYER') {
        inner['thirdParty'] = {'embedUrl': 'https://www.youtube.com/'};
      }
      tahap = 'sts';
      final sts = signatureTimestamp ?? await _signatureTimestamp();
      tahap = 'post';
      final body = <String, dynamic>{
        'videoId': track.playableRef,
        'playbackContext': {'contentPlaybackContext': {'vis': 0, 'splay': false, 'lactMilliseconds': '-1',
            'signatureTimestamp': sts}},
        'racyCheckOk': true, 'contentCheckOk': true,
        'context': inner,
      };
      final res = await _postWithContext('player', client, body);
      tahap = 'urai';
      final ps = asMap(res['playabilityStatus']);
      return WatchPlayerProbe(
        playability: ps?['status'] as String? ?? '(tanpa status)',
        reason: ps?['reason'] as String? ?? simpleText(ps?['messages']) ?? '',
        visitorDataLength: 0,
        audio: _watchAudioFormats(res),
      );
    } catch (e, st) {
      return WatchPlayerProbe(
          playability: '(galat)', reason: '',
          error: 'tahap=$tahap: ${describeError(e)} @ ${st.toString().split('\n').take(3).join(' | ')}',
          visitorDataLength: 0, audio: const []);
    }
  }

  /// Kehadiran URL SABR (Diagnostik F3 Batch 0, Tahap 3): resolusi klien
  /// [clientName] (boleh ganti versi via [versionOverride] + UA Android
  /// sepadan) lalu laporkan playability, kunci streamingData, dan HOST
  /// serverAbrStreamingUrl bila terbit. URL penuh hanya di memori.
  Future<({String playability, List<String> sdKeys, String? abrHost, String? error})>
      debugAbrPresence(String clientName, Track track, {String? versionOverride}) async {
    var client = _debugClientCtx(clientName);
    if (client == null) {
      return (playability: '(klien tak dikenal)', sdKeys: const <String>[], abrHost: null, error: 'konteks klien tidak ada');
    }
    if (versionOverride != null) {
      final ua = clientName == 'ANDROID'
          ? 'com.google.android.youtube/$versionOverride (Linux; U; Android 14; in_ID; Pixel 8) gzip'
          : client.userAgent;
      client = _ClientCtx(clientName, versionOverride, ua, client.extra);
    }
    final body = <String, dynamic>{
      'videoId': track.playableRef,
      'playbackContext': {'contentPlaybackContext': {'vis': 0, 'splay': false, 'lactMilliseconds': '-1',
          'signatureTimestamp': await _signatureTimestamp()}},
      'racyCheckOk': true, 'contentCheckOk': true,
    };
    try {
      final Map<String, dynamic> res;
      if (clientName == 'TVHTML5_SIMPLY_EMBEDDED_PLAYER' || clientName == 'WEB_EMBEDDED_PLAYER') {
        body['context'] = {...client.context()['context'] as Map, 'thirdParty': {'embedUrl': 'https://www.youtube.com/'}};
        res = await _postWithContext('player', client, body);
      } else {
        res = await _post('player', client, body);
      }
      final ps = asMap(res['playabilityStatus']);
      final sd = asMap(res['streamingData']);
      final abr = sd?['serverAbrStreamingUrl'] as String?;
      return (
        playability: ps?['status'] as String? ?? '(tanpa status)',
        sdKeys: sd?.keys.toList() ?? const [],
        abrHost: abr == null ? null : Uri.tryParse(abr)?.host,
        error: null,
      );
    } catch (e) {
      return (playability: '(galat)', sdKeys: const <String>[], abrHost: null, error: describeError(e));
    }
  }

  /// Ambil respons player dari halaman watch [videoId] (www lebih dulu,
  /// music sebagai cadangan): playability, format audio adaptif (langsung
  /// & tercipher), jalur player JS, sts, panjang visitorData halaman.
  Future<WatchPlayerProbe> debugFetchWatchPlayer(String videoId) async {
    for (final url in [
      'https://www.youtube.com/watch?v=$videoId',
      'https://music.youtube.com/watch?v=$videoId',
    ]) {
      final html = await debugFetchText(url);
      if (html == null) continue;
      final marker = html.indexOf('ytInitialPlayerResponse');
      if (marker < 0) continue;
      final brace = html.indexOf('{', marker);
      if (brace < 0) continue;
      final jsonText = _extractJsonAt(html, brace);
      if (jsonText == null) continue;
      Object? decoded;
      try {
        decoded = jsonDecode(jsonText);
      } catch (_) {
        continue;
      }
      if (decoded is! Map) continue;
      final res = decoded.cast<String, dynamic>();
      final ps = asMap(res['playabilityStatus']);
      final status = ps?['status'] as String? ?? '(tanpa status)';
      final reason = ps?['reason'] as String? ?? simpleText(ps?['messages']) ?? '';
      final audio = _watchAudioFormats(res);
      final jsM = RegExp(r'"jsUrl":"([^"]+)"').firstMatch(html);
      final jsPath = jsM?.group(1)?.replaceAll('\\/', '/');
      final stsM = RegExp(r'"signatureTimestamp":(\d+)').firstMatch(jsonText);
      final vdM = RegExp(r'"VISITOR_DATA":"([^"]+)"').firstMatch(html) ??
          RegExp(r'"visitorData":"([^"]+)"').firstMatch(html);
      return WatchPlayerProbe(
        playability: status,
        reason: reason,
        jsPath: jsPath,
        signatureTimestamp: stsM == null ? null : int.tryParse(stsM.group(1)!),
        visitorDataLength: vdM?.group(1)?.length ?? 0,
        audio: audio,
      );
    }
    return const WatchPlayerProbe(
      playability: '(tidak ada)',
      reason: '',
      error: 'ytInitialPlayerResponse tidak ditemukan di halaman watch www maupun music',
      visitorDataLength: 0,
      audio: [],
    );
  }


  // ================= Diagnostik F3 Batch 0 — Tahap 3b: PoC SABR =================
  // Permintaan VideoPlaybackAbrRequest (protobuf tulisan tangan) ke
  // serverAbrStreamingUrl dari resolusi ANDROID, respons UMP diurai, byte
  // MEDIA untuk itag audio terpilih diakumulasi lintas putaran lanjutan.
  // URL penuh & config hanya di memori; laporan hanya angka & host.

  static void _pbVarint(List<int> out, int v) {
    var x = v;
    while (true) {
      if (x < 0x80) {
        out.add(x);
        return;
      }
      out.add((x & 0x7F) | 0x80);
      x >>= 7;
    }
  }

  static void _pbTag(List<int> out, int field, int wire) => _pbVarint(out, (field << 3) | wire);

  static void _pbFieldVarint(List<int> out, int field, int v) {
    _pbTag(out, field, 0);
    _pbVarint(out, v);
  }

  static void _pbFieldBytes(List<int> out, int field, List<int> bytes) {
    _pbTag(out, field, 2);
    _pbVarint(out, bytes.length);
    out.addAll(bytes);
  }

  /// Urai pesan protobuf jadi peta nomor field → daftar nilai (int untuk
  /// varint, Uint8List untuk length-delimited). Tahan banting: berhenti
  /// pada data tak seimbang.
  static Map<int, List<Object>> _pbParse(Uint8List b) {
    final out = <int, List<Object>>{};
    var pos = 0;
    int readVarint() {
      var result = 0;
      var shift = 0;
      while (pos < b.length && shift < 64) {
        final byte = b[pos++];
        result |= (byte & 0x7F) << shift;
        if (byte & 0x80 == 0) break;
        shift += 7;
      }
      return result;
    }

    while (pos < b.length) {
      final tag = readVarint();
      if (tag == 0) break;
      final field = tag >> 3;
      final wire = tag & 7;
      Object? value;
      if (wire == 0) {
        value = readVarint();
      } else if (wire == 2) {
        final len = readVarint();
        if (len < 0 || pos + len > b.length) break;
        value = Uint8List.sublistView(b, pos, pos + len);
        pos += len;
      } else if (wire == 1) {
        if (pos + 8 > b.length) break;
        pos += 8;
        value = 0;
      } else if (wire == 5) {
        if (pos + 4 > b.length) break;
        pos += 4;
        value = 0;
      } else {
        break;
      }
      out.putIfAbsent(field, () => []).add(value);
    }
    return out;
  }

  static int? _pbInt(Map<int, List<Object>> m, int field) {
    final v = m[field];
    if (v == null || v.isEmpty) return null;
    final x = v.first;
    return x is int ? x : null;
  }

  static Uint8List? _pbBytes(Map<int, List<Object>> m, int field) {
    final v = m[field];
    if (v == null || v.isEmpty) return null;
    final x = v.first;
    return x is Uint8List ? x : null;
  }

  /// Varint UMP (BUKAN varint protobuf): bit terdepan byte pertama
  /// menentukan lebar total (pola seperti UTF-8).
  static (int, int) _umpVarint(Uint8List b, int pos) {
    // Tata letak varint UMP terverifikasi dari UmpReader (paket googlevideo):
    // bit penanda di byte pertama menentukan lebar; bit muatan byte pertama
    // adalah bit RENDAH, byte berikutnya makin tinggi (little-endian).
    final first = b[pos];
    if (first < 0x80) return (first, 1);
    if (first < 0xC0) return ((first & 0x3F) | (b[pos + 1] << 6), 2);
    if (first < 0xE0) {
      return ((first & 0x1F) | (b[pos + 1] << 5) | (b[pos + 2] << 13), 3);
    }
    if (first < 0xF0) {
      return (
        (first & 0x0F) | (b[pos + 1] << 4) | (b[pos + 2] << 12) | (b[pos + 3] << 20),
        4
      );
    }
    return (
      b[pos + 1] | (b[pos + 2] << 8) | (b[pos + 3] << 16) | (b[pos + 4] << 24),
      5
    );
  }

  /// PoC SABR satu subjek lewat klien ANDROID. Mengembalikan angka-angka
  /// bukti saja.
  Future<SabrPocResult> debugSabrPoc(Track track, {int maxRounds = 8, Uint8List? poToken}) async {
    final client = _debugClientCtx('ANDROID')!;
    final body = <String, dynamic>{
      'videoId': track.playableRef,
      'playbackContext': {'contentPlaybackContext': {'vis': 0, 'splay': false, 'lactMilliseconds': '-1',
          'signatureTimestamp': await _signatureTimestamp()}},
      'racyCheckOk': true, 'contentCheckOk': true,
    };
    final Map<String, dynamic> res;
    try {
      res = await _post('player', client, body);
    } catch (e) {
      return SabrPocResult.failure('resolusi ANDROID galat: ${describeError(e)}');
    }
    final ps = asMap(res['playabilityStatus']);
    final status = ps?['status'] as String? ?? '(tanpa status)';
    if (status != 'OK') {
      return SabrPocResult.failure('playability $status');
    }
    final sd = asMap(res['streamingData']);
    var abrUrl = sd?['serverAbrStreamingUrl'] as String?;
    if (abrUrl == null) return SabrPocResult.failure('serverAbrStreamingUrl tidak terbit');
    final pc = asMap(res['playerConfig']);
    final mcc = asMap(pc?['mediaCommonConfig']);
    final urc = asMap(mcc?['mediaUstreamerRequestConfig']);
    final ustreamerB64 = urc?['videoPlaybackUstreamerConfig'] as String?;
    List<int>? ustreamerConfig;
    if (ustreamerB64 != null) {
      try {
        ustreamerConfig = base64.decode(ustreamerB64);
      } catch (_) {/* config tak terurai — lanjut tanpa field 5 */}
    }
    // Pilih format audio tingkat Normal + lastModified-nya.
    final audioFmts = <Map<String, dynamic>>[
      for (final e in asList(sd?['adaptiveFormats']))
        if (asMap(e) != null) asMap(e)!,
    ].where((f) => ((f['mimeType'] as String?) ?? '').startsWith('audio/')).toList();
    if (audioFmts.isEmpty) return SabrPocResult.failure('tidak ada format audio adaptif');
    audioFmts.sort((a, b) => ((a['bitrate'] as num?)?.toInt() ?? 0).compareTo((b['bitrate'] as num?)?.toInt() ?? 0));
    Map<String, dynamic>? pick;
    for (final f in audioFmts) {
      if (((f['bitrate'] as num?)?.toInt() ?? 0) <= StreamQuality.normal.maxBitrate) pick = f;
    }
    pick ??= audioFmts.first;
    final itag = (pick['itag'] as num).toInt();
    final lastModified = int.tryParse('${pick['lastModified'] ?? '0'}') ?? 0;
    final approxDurMs = int.tryParse('${pick['approxDurationMs'] ?? '0'}') ?? 0;
    final totalLen = int.tryParse('${pick['contentLength'] ?? '0'}') ?? 0;

    List<int> formatIdMsg() {
      final out = <int>[];
      _pbFieldVarint(out, 1, itag);
      _pbFieldVarint(out, 2, lastModified);
      return out;
    }

    List<int> buildRequest({
      required int playerTimeMs,
      required bool locked,
      required (int startMs, int durMs, int startSeg, int endSeg)? buffered,
      required Uint8List? playbackCookie,
      required List<(int, Uint8List)> sabrContexts,
    }) {
      final out = <int>[];
      // 1: clientAbrState {28: playerTimeMs, 40: 1 (audio saja)}
      final abrState = <int>[];
      _pbFieldVarint(abrState, 28, playerTimeMs);
      _pbFieldVarint(abrState, 40, 1);
      _pbFieldBytes(out, 1, abrState);
      // 2: initializationFormatIds (kunci format, putaran lanjutan)
      if (locked) _pbFieldBytes(out, 2, formatIdMsg());
      // 3: bufferedRange {1: formatId, 2: startTimeMs, 3: durationMs, 4/5: segmen}
      if (buffered != null) {
        final br = <int>[];
        _pbFieldBytes(br, 1, formatIdMsg());
        _pbFieldVarint(br, 2, buffered.$1);
        _pbFieldVarint(br, 3, buffered.$2);
        _pbFieldVarint(br, 4, buffered.$3);
        _pbFieldVarint(br, 5, buffered.$4);
        _pbFieldBytes(out, 3, br);
      }
      // 4: playerTimeMs (bila > 0)
      if (playerTimeMs > 0) _pbFieldVarint(out, 4, playerTimeMs);
      // 5: videoPlaybackUstreamerConfig
      if (ustreamerConfig != null) _pbFieldBytes(out, 5, ustreamerConfig);
      // 16: preferredAudioFormatId
      _pbFieldBytes(out, 16, formatIdMsg());
      // 19: streamerContext {1: clientInfo, 3: playbackCookie, 5: sabrContexts}
      final sc = <int>[];
      final ci = <int>[];
      _pbFieldBytes(ci, 12, utf8.encode('Google'));
      _pbFieldBytes(ci, 13, utf8.encode('Pixel 8'));
      _pbFieldVarint(ci, 16, 3); // ANDROID
      _pbFieldBytes(ci, 17, utf8.encode(client.version));
      _pbFieldBytes(ci, 18, utf8.encode('Android'));
      _pbFieldBytes(ci, 19, utf8.encode('14'));
      _pbFieldVarint(ci, 64, 34);
      _pbFieldBytes(sc, 1, ci);
      if (poToken != null) _pbFieldBytes(sc, 2, poToken);
      if (playbackCookie != null) _pbFieldBytes(sc, 3, playbackCookie);
      for (final (type, value) in sabrContexts) {
        final ctxMsg = <int>[];
        _pbFieldVarint(ctxMsg, 1, type);
        _pbFieldBytes(ctxMsg, 2, value);
        _pbFieldBytes(sc, 5, ctxMsg);
      }
      _pbFieldBytes(out, 19, sc);
      return out;
    }

    final dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 10)));
    var rounds = 0;
    var mediaBytesAudio = 0;
    var mediaBytesTotal = 0;
    var mediaParts = 0;
    final segments = <int>{};
    int? endSegmentNumber;
    int? headerContentLength;
    int? protection;
    var sabrError = false;
    var redirectHost = '';
    Uint8List? playbackCookie;
    final sabrContexts = <(int, Uint8List)>[];
    var playerTimeMs = 0;
    var bufferedEndMs = 0;
    var dryRounds = 0;
    final partTypes = <int, int>{};
    var framing = '';
    final roundLog = <String>[];
    final protLog = <String>[];

    while (rounds < maxRounds) {
      rounds++;
      final reqBytes = buildRequest(
        playerTimeMs: playerTimeMs,
        locked: rounds > 1,
        buffered: rounds == 1
            ? null
            : (
                0,
                bufferedEndMs,
                segments.isEmpty ? 1 : segments.reduce((a, b) => a < b ? a : b),
                segments.isEmpty ? 1 : segments.reduce((a, b) => a > b ? a : b),
              ),
        playbackCookie: playbackCookie,
        sabrContexts: sabrContexts,
      );
      final Response<List<int>> resp;
      try {
        resp = await dio.post<List<int>>(abrUrl!,
            data: Uint8List.fromList(reqBytes),
            options: Options(
              responseType: ResponseType.bytes,
              headers: {
                'User-Agent': client.userAgent,
                'Content-Type': 'application/x-protobuf',
              },
              receiveTimeout: const Duration(seconds: 60),
              validateStatus: (_) => true,
            ));
      } catch (e) {
        return SabrPocResult(
          rounds: rounds, itag: itag, mediaBytesAudio: mediaBytesAudio,
          mediaBytesTotal: mediaBytesTotal, segments: segments.length,
          endSegmentNumber: endSegmentNumber, contentLength: totalLen,
          protection: protection, sabrError: sabrError, partTypes: partTypes,
          protectionSeries: protLog.join(' '),
          detail: 'POST SABR galat putaran $rounds: ${describeError(e)}',
        );
      }
      final httpStatus = resp.statusCode ?? 0;
      final data = resp.data;
      if (httpStatus != 200 || data == null || data.isEmpty) {
        return SabrPocResult(
          rounds: rounds, itag: itag, mediaBytesAudio: mediaBytesAudio,
          mediaBytesTotal: mediaBytesTotal, segments: segments.length,
          endSegmentNumber: endSegmentNumber, contentLength: headerContentLength ?? totalLen,
          protection: protection, sabrError: sabrError, partTypes: partTypes,
          protectionSeries: protLog.join(' '),
          detail: 'POST SABR putaran $rounds: HTTP $httpStatus, ${data?.length ?? 0} byte',
        );
      }
      final bytes = data is Uint8List ? data : Uint8List.fromList(data);
      if (rounds == 1) {
        final head = bytes.take(8).map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
        framing = 'HTTP $httpStatus - ${bytes.length} byte - head=$head';
      }
      // Urai UMP.
      final headers = <int, (int itag, int startRange, int seq, bool isInit)>{};
      var pos = 0;
      var newMedia = 0;
      while (pos < bytes.length) {
        final (partType, n1) = _umpVarint(bytes, pos);
        pos += n1;
        if (pos >= bytes.length) break;
        final (partSize, n2) = _umpVarint(bytes, pos);
        pos += n2;
        if (partSize < 0 || pos + partSize > bytes.length) break;
        final payload = Uint8List.sublistView(bytes, pos, pos + partSize);
        pos += partSize;
        partTypes[partType] = (partTypes[partType] ?? 0) + 1;
        switch (partType) {
          case 20: // MEDIA_HEADER
            final m = _pbParse(payload);
            final hid = _pbInt(m, 1);
            final hItag = _pbInt(m, 3);
            if (hid != null && hItag != null) {
              headers[hid] = (
                hItag,
                _pbInt(m, 6) ?? 0,
                _pbInt(m, 9) ?? -1,
                (_pbInt(m, 8) ?? 0) != 0,
              );
              final cl = _pbInt(m, 14);
              if (cl != null && hItag == itag) headerContentLength = cl;
              final start = _pbInt(m, 11);
              final dur = _pbInt(m, 12);
              if (start != null && dur != null && hItag == itag) {
                final end = start + dur;
                if (end > bufferedEndMs) bufferedEndMs = end;
              }
            }
          case 21: // MEDIA
            if (payload.isEmpty) break;
            final (hid, hn) = _umpVarint(payload, 0);
            final h = headers[hid];
            final n = payload.length - hn;
            mediaBytesTotal += n;
            newMedia += n;
            if (h != null && h.$1 == itag) {
              mediaBytesAudio += n;
              mediaParts++;
              if (h.$3 >= 0) segments.add(h.$3);
            }
          case 42: // FORMAT_INITIALIZATION_METADATA
            final m = _pbParse(payload);
            endSegmentNumber = _pbInt(m, 4) ?? endSegmentNumber;
          case 35: // NEXT_REQUEST_POLICY
            final m = _pbParse(payload);
            playbackCookie = _pbBytes(m, 7) ?? playbackCookie;
          case 57: // SABR_CONTEXT_UPDATE {1: type, 3: value}
            final m = _pbParse(payload);
            final t = _pbInt(m, 1);
            final v = _pbBytes(m, 3);
            if (t != null && v != null) {
              sabrContexts.removeWhere((e) => e.$1 == t);
              sabrContexts.add((t, v));
            }
          case 58: // STREAM_PROTECTION_STATUS {1: status, 2: maxRetries}
            final m = _pbParse(payload);
            protection = _pbInt(m, 1) ?? protection;
            protLog.add('r$rounds:st${_pbInt(m, 1) ?? '-'}/mr${_pbInt(m, 2) ?? '-'}');
          case 43: // SABR_REDIRECT {1: url}
            final m = _pbParse(payload);
            final u = _pbBytes(m, 1);
            if (u != null) {
              abrUrl = utf8.decode(u, allowMalformed: true);
              redirectHost = Uri.tryParse(abrUrl)?.host ?? '';
            }
          case 44: // SABR_ERROR
            sabrError = true;
        }
      }
      roundLog.add('r$rounds:+$newMedia/s${segments.isEmpty ? '-' : segments.reduce((a, b) => a > b ? a : b)}/pt$playerTimeMs');
      if (sabrError) break;
      if (protection == 3) break;
      if (newMedia == 0) {
        dryRounds++;
        if (dryRounds >= 2) break;
      } else {
        dryRounds = 0;
      }
      // Maju waktu putar: ujung ter-buffer dari rentang waktu header, atau
      // taksiran dari byte (bitrate pilihan) bila rentang waktu tak terbaca.
      if (bufferedEndMs > playerTimeMs) {
        playerTimeMs = bufferedEndMs;
      } else if (mediaBytesAudio > 0 && totalLen > 0 && approxDurMs > 0) {
        playerTimeMs = (mediaBytesAudio / totalLen * approxDurMs).round();
      }
      // Target tuntas = total dari streamingData; field 14 header adalah
      // panjang PER SEGMEN (segmentLengthBytes), bukan total berkas.
      if (totalLen > 0 && mediaBytesAudio >= totalLen) break;
      if (endSegmentNumber != null &&
          segments.isNotEmpty &&
          segments.reduce((a, b) => a > b ? a : b) >= endSegmentNumber) {
        break;
      }
    }
    return SabrPocResult(
      rounds: rounds, itag: itag, mediaBytesAudio: mediaBytesAudio,
      mediaBytesTotal: mediaBytesTotal, segments: segments.length,
      endSegmentNumber: endSegmentNumber, contentLength: totalLen,
      protection: protection, sabrError: sabrError, partTypes: partTypes,
      protectionSeries: protLog.join(' '),
      detail: 'mediaParts=$mediaParts - redirectHost=$redirectHost - ustreamerConfig=${ustreamerConfig == null ? 'tidak ada' : 'ada'} - bingkai: $framing - putaran: ${roundLog.join(' ')}',
    );
  }

  Future<ClientStreamProbe> _probeWithPoOnce(_ClientCtx client, Track track,
      {String? playerPoToken, String? visitorData}) async {
    final body = <String, dynamic>{
      'videoId': track.playableRef,
      'playbackContext': {'contentPlaybackContext': {'vis': 0, 'splay': false, 'lactMilliseconds': '-1',
          'signatureTimestamp': await _signatureTimestamp()}},
      'racyCheckOk': true, 'contentCheckOk': true,
      if (playerPoToken != null)
        'serviceIntegrityDimensions': {'poToken': playerPoToken},
    };
    final Map<String, dynamic> res;
    if (visitorData == null) {
      // Identik dengan jalur debug terbukti (_post menggabungkan konteks).
      if (client.name == 'TVHTML5_SIMPLY_EMBEDDED_PLAYER' || client.name == 'WEB_EMBEDDED_PLAYER') {
        body['context'] = {...client.context()['context'] as Map, 'thirdParty': {'embedUrl': 'https://www.youtube.com/'}};
        res = await _postWithContext('player', client, body);
      } else {
        res = await _post('player', client, body);
      }
    } else {
      // Konteks harus menyatakan visitorData sesi pencetak → rakit penuh.
      final inner = (client.context()['context'] as Map).cast<String, dynamic>();
      (inner['client'] as Map<String, dynamic>)['visitorData'] = visitorData;
      if (client.name == 'TVHTML5_SIMPLY_EMBEDDED_PLAYER' || client.name == 'WEB_EMBEDDED_PLAYER') {
        inner['thirdParty'] = {'embedUrl': 'https://www.youtube.com/'};
      }
      body['context'] = inner;
      res = await _postWithContext('player', client, body);
    }
    final ps = asMap(res['playabilityStatus']);
    final status = ps?['status'] as String? ?? '(tanpa status)';
    final reason = ps?['reason'] as String? ?? simpleText(ps?['messages']) ?? '';
    if (status != 'OK') {
      return ClientStreamProbe(
          client: client.name, version: client.version, userAgent: client.userAgent,
          playability: status, reason: reason);
    }
    final sd = asMap(res['streamingData']);
    final adaptive = asList(sd?['adaptiveFormats'])
        .map((e) => asMap(e)).whereType<Map<String, dynamic>>().toList();
    final audio = adaptive.where((f) {
      final mime = (f['mimeType'] as String?) ?? '';
      return mime.startsWith('audio/') && f['url'] is String;
    }).toList();
    final totalFormats = adaptive.length + asList(sd?['formats']).length;
    final adaptiveAudioAny = adaptive
        .where((f) => ((f['mimeType'] as String?) ?? '').startsWith('audio/'))
        .length;
    final info = pickStreamFormat(res, StreamQuality.normal);
    final uri = info == null ? null : Uri.tryParse(info.url);
    return ClientStreamProbe(
      client: client.name, version: client.version, userAgent: client.userAgent,
      playability: status, reason: reason,
      audioFormats: [
        for (final f in audio)
          (itag: (f['itag'] as num?)?.toInt() ?? -1,
           mime: (f['mimeType'] as String?) ?? '',
           bitrate: (f['bitrate'] as num?)?.toInt(),
           contentLength: int.tryParse('${f['contentLength'] ?? ''}')),
      ],
      totalFormats: totalFormats,
      adaptiveTotal: adaptive.length,
      adaptiveAudioAny: adaptiveAudioAny,
      tierItags: _tierItagsOf(audio),
      info: info,
      urlHost: uri?.host,
      urlParams: uri == null ? const [] : (uri.queryParameters.keys.toList()..sort()),
    );
  }

  Future<ClientStreamProbe> _probeNamedClientOnce(_ClientCtx client, Track track) async {
    final body = <String, dynamic>{
      'videoId': track.playableRef,
      'playbackContext': {'contentPlaybackContext': {'vis': 0, 'splay': false, 'lactMilliseconds': '-1',
          'signatureTimestamp': await _signatureTimestamp()}},
      'racyCheckOk': true, 'contentCheckOk': true,
    };
    final Map<String, dynamic> res;
    if (client.name == 'TVHTML5_SIMPLY_EMBEDDED_PLAYER' || client.name == 'WEB_EMBEDDED_PLAYER') {
      body['context'] = {...client.context()['context'] as Map, 'thirdParty': {'embedUrl': 'https://www.youtube.com/'}};
      res = await _postWithContext('player', client, body);
    } else {
      res = await _post('player', client, body);
    }
    final ps = asMap(res['playabilityStatus']);
    final status = ps?['status'] as String? ?? '(tanpa status)';
    final reason = ps?['reason'] as String? ?? simpleText(ps?['messages']) ?? '';
    if (status != 'OK') {
      return ClientStreamProbe(
          client: client.name, version: client.version, userAgent: client.userAgent,
          playability: status, reason: reason);
    }
    final sd = asMap(res['streamingData']);
    final adaptive = asList(sd?['adaptiveFormats'])
        .map((e) => asMap(e)).whereType<Map<String, dynamic>>().toList();
    final audio = adaptive.where((f) {
      final mime = (f['mimeType'] as String?) ?? '';
      return mime.startsWith('audio/') && f['url'] is String;
    }).toList();
    final totalFormats = adaptive.length + asList(sd?['formats']).length;
    final adaptiveAudioAny = adaptive
        .where((f) => ((f['mimeType'] as String?) ?? '').startsWith('audio/'))
        .length;
    final info = pickStreamFormat(res, StreamQuality.normal);
    final uri = info == null ? null : Uri.tryParse(info.url);
    return ClientStreamProbe(
      client: client.name, version: client.version, userAgent: client.userAgent,
      playability: status, reason: reason,
      audioFormats: [
        for (final f in audio)
          (itag: (f['itag'] as num?)?.toInt() ?? -1,
           mime: (f['mimeType'] as String?) ?? '',
           bitrate: (f['bitrate'] as num?)?.toInt(),
           contentLength: int.tryParse('${f['contentLength'] ?? ''}')),
      ],
      totalFormats: totalFormats,
      adaptiveTotal: adaptive.length,
      adaptiveAudioAny: adaptiveAudioAny,
      tierItags: _tierItagsOf(audio),
      info: info,
      urlHost: uri?.host,
      urlParams: uri == null ? const [] : (uri.queryParameters.keys.toList()..sort()),
    );
  }

  /// Pilihan itag per tingkat kualitas dari daftar format audio adaptif —
  /// semantik yang sama dengan [pickStreamFormat] (tertinggi ≤ plafon
  /// tingkat; bila tak ada, terendah yang tersedia — D-19).
  static Map<String, int?> _tierItagsOf(List<Map<String, dynamic>> audio) {
    if (audio.isEmpty) return const {'low': null, 'normal': null, 'high': null};
    final sorted = [...audio]
      ..sort((a, b) => ((a['bitrate'] as num?) ?? 0).compareTo((b['bitrate'] as num?) ?? 0));
    int? pick(int cap) {
      Map<String, dynamic>? chosen;
      for (final f in sorted) {
        if (((f['bitrate'] as num?) ?? 0) <= cap) chosen = f;
      }
      chosen ??= sorted.first;
      return (chosen['itag'] as num?)?.toInt();
    }
    return {
      'low': pick(StreamQuality.low.maxBitrate),
      'normal': pick(StreamQuality.normal.maxBitrate),
      'high': pick(StreamQuality.high.maxBitrate),
    };
  }

  // Cache cadangan muxed khusus sesi proses (skema DB tidak diubah di v4.1).
  final Map<TrackKey, StreamInfo> _muxedCache = {};

  @override
  Future<StreamInfo?> resolveMuxedFallback(Track track) async {
    final hit = _muxedCache[track.key];
    if (hit != null && hit.expiresAt.isAfter(DateTime.now())) return hit;
    // Hanya dua klien terdepan yang terbukti hidup (probe v4/v4.1).
    for (final client in _streamClients.take(2)) {
      try {
        final body = <String, dynamic>{
          'videoId': track.playableRef,
          'playbackContext': {'contentPlaybackContext': {'vis': 0, 'splay': false, 'lactMilliseconds': '-1',
              'signatureTimestamp': await _signatureTimestamp()}},
          'racyCheckOk': true, 'contentCheckOk': true,
        };
        final res = await _post('player', client, body);
        final s = pickMuxedFallbackFormat(res);
        if (s != null) { _muxedCache[track.key] = s; return s; }
      } catch (_) {
        continue;
      }
    }
    return null;
  }

  Future<Map<String, dynamic>> _postWithContext(String endpoint, _ClientCtx ctx, Map<String, dynamic> body) async {
    final res = await _withRetry(() => _dio.post(
          'https://music.youtube.com/youtubei/v1/$endpoint?key=$_webKey&prettyPrint=false',
          data: body,
          options: Options(headers: {
            'User-Agent': ctx.userAgent,
            'X-YouTube-Client-Name': _clientHeaderId(ctx.name),
            'X-YouTube-Client-Version': ctx.version,
            'Content-Type': 'application/json',
          }),
        ));
    if (res.data is! Map) throw ProviderDegradedException('respons player bukan JSON');
    return (res.data as Map).cast<String, dynamic>();
  }

  int? _sts;
  DateTime? _stsAt;
  Future<int?> _signatureTimestamp() async {
    // Cache NEGATIF (v4): halaman utama music.youtube.com saat ini tidak lagi memuat
    // signatureTimestamp sama sekali (probe v4) — versi lama hanya mencatat _stsAt saat
    // ditemukan, sehingga null berarti halaman utama diunduh ulang sebelum SETIAP resolusi
    // trek. Kini percobaan pun dicache: hasil kosong berlaku 30 menit, hasil ada 24 jam.
    final ttl = _sts == null ? const Duration(minutes: 30) : const Duration(hours: 24);
    if (_stsAt != null && DateTime.now().difference(_stsAt!) < ttl) return _sts;
    _stsAt = DateTime.now();
    try {
      final res = await _dio.get<String>('https://music.youtube.com/',
          options: Options(headers: {'User-Agent': _uaWeb}, responseType: ResponseType.plain));
      final html = res.data ?? '';
      final m = RegExp(r'"signatureTimestamp":(\d+)').firstMatch(html);
      if (m != null) { _sts = int.tryParse(m.group(1)!); }
    } catch (_) {/* tanpa sts pun beberapa klien tetap menjawab; rantai yang menilai */}
    return _sts;
  }
}

/// Satu format audio adaptif dari respons player halaman watch
/// (Diagnostik F3 Batch 0, Tahap 2). URL & nilai cipher HANYA di memori.
class WatchFormat {
  final int itag;
  final String mime;
  final int? bitrate;
  final int? contentLength;
  final String? directUrl;
  final String? cipherS;
  final String cipherSp;
  final String? cipherBaseUrl;
  const WatchFormat({
    required this.itag,
    required this.mime,
    this.bitrate,
    this.contentLength,
    this.directUrl,
    this.cipherS,
    this.cipherSp = 'signature',
    this.cipherBaseUrl,
  });

  bool get ciphered => cipherS != null && cipherBaseUrl != null;
}

/// Hasil ambil respons player halaman watch (Diagnostik F3 Batch 0,
/// Tahap 2) — lihat [YtMusicProvider.debugFetchWatchPlayer].
class WatchPlayerProbe {
  final String playability;
  final String reason;
  final String? error;
  final String? jsPath;
  final int? signatureTimestamp;
  final int visitorDataLength;
  final List<WatchFormat> audio;
  const WatchPlayerProbe({
    required this.playability,
    required this.reason,
    this.error,
    this.jsPath,
    this.signatureTimestamp,
    required this.visitorDataLength,
    required this.audio,
  });
}

/// Hasil PoC SABR (Diagnostik F3 Batch 0, Tahap 3b) — angka bukti saja.
class SabrPocResult {
  final int rounds;
  final int itag;
  final int mediaBytesAudio;
  final int mediaBytesTotal;
  final int segments;
  final int? endSegmentNumber;
  final int contentLength;
  final int? protection;
  final bool sabrError;
  final Map<int, int> partTypes;
  final String detail;

  /// Seri anggaran proteksi per respons (Tahap 2, E6): entri
  /// `r<putaran>:st<status>/mr<maxRetries|->` untuk setiap part 58 yang
  /// tiba — field 2 (maxRetries) TIDAK dibaca ronde-rode sebelumnya.
  final String protectionSeries;
  const SabrPocResult({
    this.rounds = 0,
    this.itag = -1,
    this.mediaBytesAudio = 0,
    this.mediaBytesTotal = 0,
    this.segments = 0,
    this.endSegmentNumber,
    this.contentLength = 0,
    this.protection,
    this.sabrError = false,
    this.partTypes = const {},
    this.protectionSeries = '',
    required this.detail,
  });
  factory SabrPocResult.failure(String detail) => SabrPocResult(detail: detail);
}

// ================= Diagnostik Probe Plafon SABR (Batch 0.5 F3) =================
// Pelari sesi SABR tergeneralisasi: spesifikasi keluarga klien SABR
// (identitas terverifikasi dari katalog innertubex), resep fidelitas
// keadaan ABR meniru SabrStream referensi (paket googlevideo), dan mode
// perpanjangan sesi. Diagnostik SAJA — jalur produksi tidak disentuh.
// URL penuh, ustreamerConfig, cookie & konteks hanya di memori; hasil
// hanya angka, host, dan nama field.

/// Spesifikasi satu keluarga klien SABR untuk [SabrCeilingProbe].
class SabrClientSpec {
  /// Label laporan.
  final String label;

  /// Kunci konteks resolusi JSON (lihat _debugClientCtx).
  final String resolveAs;

  /// Nilai enum ClientInfo field 16 (clientName numerik).
  final int clientIdNum;
  final String? deviceMake, deviceModel, osName, osVersion;
  final int? androidSdk;
  const SabrClientSpec(this.label, this.resolveAs, this.clientIdNum,
      {this.deviceMake, this.deviceModel, this.osName, this.osVersion, this.androidSdk});
}

/// Peta keluarga SABR yang diuji ronde plafon. Identitas terverifikasi
/// dari DEX Auralys (konstruktor enum YouTubeClient innertubex).
const sabrClientSpecs = <String, SabrClientSpec>{
  'ANDROID': SabrClientSpec('ANDROID', 'ANDROID', 3,
      deviceMake: 'Google', deviceModel: 'Pixel 8', osName: 'Android', osVersion: '14', androidSdk: 34),
  'IOS': SabrClientSpec('IOS@21.26.4', 'IOS_SABR', 5,
      deviceMake: 'Apple', deviceModel: 'iPhone16,2', osName: 'iOS', osVersion: '18.3.2'),
  'VISIONOS': SabrClientSpec('VISIONOS', 'VISIONOS', 101,
      deviceMake: 'Apple', deviceModel: 'RealityDevice17,1', osName: 'visionOS', osVersion: '26.5.23O471'),
  'WEB_REMIX': SabrClientSpec('WEB_REMIX@1.20260707', 'WEB_REMIX_SABR', 67),
  'TVHTML5': SabrClientSpec('TVHTML5@7.20260707', 'TVHTML5_SABR', 7),
};

/// Hasil satu sesi SABR (satu trek, satu konfigurasi).
class SabrSessionResult {
  final String config;
  final int itag;
  final int rounds;
  final int mediaBytesAudio;
  final int mediaBytesTotal;
  final int segments;
  final int maxSegment;
  final int? endSegmentNumber;
  final int contentLength;
  final int approxDurMs;
  final int bufferedEndMs;

  /// Frontier efektif sesi: ujung waktu header bila terbaca, selain itu
  /// taksiran proporsi byte — posisi untuk perpanjangan sesi (T3).
  final int frontierMs;
  final int? protection;
  final bool sabrError;
  final Map<int, int> partTypes;
  final String policySummary;
  final String stopReason;
  final int elapsedMs;
  final String detail;

  /// Seri anggaran proteksi per respons (Tahap 2, E6):
  /// `r<putaran>:st<status>/mr<maxRetries|->` per part 58 — field 2
  /// (maxRetries) tidak dibaca pada ronde plafon.
  final String protectionSeries;
  const SabrSessionResult({
    required this.config,
    this.itag = 0,
    this.rounds = 0,
    this.mediaBytesAudio = 0,
    this.mediaBytesTotal = 0,
    this.segments = 0,
    this.maxSegment = 0,
    this.endSegmentNumber,
    this.contentLength = 0,
    this.approxDurMs = 0,
    this.bufferedEndMs = 0,
    this.frontierMs = 0,
    this.protection,
    this.sabrError = false,
    this.partTypes = const {},
    this.policySummary = '',
    this.stopReason = '',
    this.elapsedMs = 0,
    this.protectionSeries = '',
    required this.detail,
  });
  factory SabrSessionResult.failure(String config, String detail) =>
      SabrSessionResult(config: config, detail: detail, stopReason: 'galat');

  /// Persen kelengkapan terhadap contentLength resolusi (0 bila tak tahu).
  /// PERHATIAN: byte bisa menipu — server dapat mengirim ulang segmen yang
  /// sama; kelengkapan sejati diukur dari cakupan segmen di bawah ini.
  int get pct =>
      contentLength <= 0 ? 0 : (mediaBytesAudio * 100 ~/ contentLength);

  /// Cakupan segmen berbeda terhadap jumlah segmen total (atau frontier
  /// waktu header terhadap durasi bila jumlah segmen tak diketahui).
  int get coveragePct => endSegmentNumber != null && endSegmentNumber! > 0
      ? (segments * 100 ~/ endSegmentNumber!)
      : (approxDurMs > 0 ? bufferedEndMs * 100 ~/ approxDurMs : 0);

  /// Utuh = cakupan segmen penuh ATAU frontier waktu ≥95% durasi.
  bool get complete =>
      (endSegmentNumber != null && endSegmentNumber! > 0 && maxSegment >= endSegmentNumber!) ||
      (approxDurMs > 0 && bufferedEndMs * 100 >= approxDurMs * 95);
}

/// Pelari sesi SABR untuk probe plafon. Extension pada provider agar
/// dapat memakai pembantu privat yang sama dengan PoC Batch 0.
extension SabrCeilingProbe on YtMusicProvider {
  /// Satu sesi SABR penuh untuk [track] memakai keluarga [specKey].
  ///
  /// [faithful] false = resep PoC Batch 0 persis (playhead frontier,
  /// field 4 terisi, tanpa keadaan waktu/bandwidth, tanpa jeda backoff)
  /// sebagai kontrol. [faithful] true = resep referensi: playhead
  /// mengikuti [playheadMode] (1 = tetap 0 gaya unduh, 2 = waktu-dinding
  /// sejak sesi mulai), field 4 kosong, elapsedWallTimeMs/timeSince*
  /// nyata, bandwidthEstimate terukur, visibility 2, init format ids
  /// tiap putaran, parameter `rn` menaik, backoff NextRequestPolicy
  /// dihormati (plafon tunggu 8 dtk), konteks SABR digerbang kebijakan
  /// part 59.
  ///
  /// Perpanjangan sesi: [startAtMs] > 0 menanam playhead awal dan
  /// [preBufferedEndMs]/[preSegStart]/[preSegEnd] mendeklarasikan
  /// rentang yang "sudah ter-buffer" dari sesi sebelumnya; field 4
  /// (mediaStartTimeMs) diisi sekali pada putaran pertama sebagai
  /// deklarasi posisi mulai.
  Future<SabrSessionResult> debugSabrSession(
    Track track, {
    required String specKey,
    bool faithful = true,
    int playheadMode = 1,
    int maxRounds = 40,
    int startAtMs = 0,
    int preBufferedEndMs = 0,
    int preSegStart = 1,
    int preSegEnd = 0,
    Uint8List? poToken,
    Future<Uint8List?> Function(String url, Uint8List body)? transport,
    Map<String, String>? resolutionHeaders,
  }) async {
    final spec = sabrClientSpecs[specKey];
    if (spec == null) {
      return SabrSessionResult.failure(specKey, 'spesifikasi klien tidak dikenal');
    }
    final config =
        '${spec.label}/${faithful ? (playheadMode == 2 ? 'FIDEL-RT' : playheadMode == 3 ? 'FIDEL-EST' : 'FIDEL-0') : 'BASE'}'
        '${startAtMs > 0 ? '/LANJUT@$startAtMs' : ''}';
    final client = _debugClientCtx(spec.resolveAs);
    if (client == null) {
      return SabrSessionResult.failure(config, 'konteks resolusi ${spec.resolveAs} tidak ada');
    }
    final body = <String, dynamic>{
      'videoId': track.playableRef,
      'playbackContext': {'contentPlaybackContext': {'vis': 0, 'splay': false, 'lactMilliseconds': '-1',
          'signatureTimestamp': await _signatureTimestamp()}},
      'racyCheckOk': true, 'contentCheckOk': true,
    };
    final Map<String, dynamic> res;
    try {
      // resolutionHeaders != null (Probe Login, Batch 0.7 F3): resolusi
      // player dikirim dengan header konteks terautentikasi (cookie +
      // SAPISIDHASH ala Auralys §2b) — konteks klien digabung manual
      // karena _postDebugPlayer tidak menggabungkannya. Sesi SABR-nya
      // sendiri tetap menempel pada URL ABR bertanda tangan (cookie
      // tidak ikut ke googlevideo, persis pola Auralys). Null = perilaku
      // lama, identik.
      res = resolutionHeaders == null
          ? await _post('player', client, body)
          : await _postDebugPlayer(
              client,
              {...client.context(), ...body},
              videoId: track.playableRef,
              extraHeaders: resolutionHeaders);
    } catch (e) {
      return SabrSessionResult.failure(config, 'resolusi ${spec.label} galat: ${describeError(e)}');
    }
    final ps = asMap(res['playabilityStatus']);
    final status = ps?['status'] as String? ?? '(tanpa status)';
    if (status != 'OK') {
      return SabrSessionResult.failure(config, 'playability $status');
    }
    final sd = asMap(res['streamingData']);
    var abrUrl = sd?['serverAbrStreamingUrl'] as String?;
    if (abrUrl == null) {
      return SabrSessionResult.failure(config, 'serverAbrStreamingUrl tidak terbit');
    }
    final pc = asMap(res['playerConfig']);
    final mcc = asMap(pc?['mediaCommonConfig']);
    final urc = asMap(mcc?['mediaUstreamerRequestConfig']);
    final ustreamerB64 = urc?['videoPlaybackUstreamerConfig'] as String?;
    List<int>? ustreamerConfig;
    if (ustreamerB64 != null) {
      try {
        ustreamerConfig = base64.decode(ustreamerB64);
      } catch (_) {/* lanjut tanpa field 5 */}
    }
    final audioFmts = <Map<String, dynamic>>[
      for (final e in asList(sd?['adaptiveFormats']))
        if (asMap(e) != null) asMap(e)!,
    ].where((f) => ((f['mimeType'] as String?) ?? '').startsWith('audio/')).toList();
    if (audioFmts.isEmpty) {
      return SabrSessionResult.failure(config, 'tidak ada format audio adaptif');
    }
    audioFmts.sort((a, b) => ((a['bitrate'] as num?)?.toInt() ?? 0).compareTo((b['bitrate'] as num?)?.toInt() ?? 0));
    Map<String, dynamic>? pick;
    for (final f in audioFmts) {
      if (((f['bitrate'] as num?)?.toInt() ?? 0) <= StreamQuality.normal.maxBitrate) pick = f;
    }
    pick ??= audioFmts.first;
    final itag = (pick['itag'] as num).toInt();
    final lastModified = int.tryParse('${pick['lastModified'] ?? '0'}') ?? 0;
    final approxDurMs = int.tryParse('${pick['approxDurationMs'] ?? '0'}') ?? 0;
    final totalLen = int.tryParse('${pick['contentLength'] ?? '0'}') ?? 0;

    List<int> formatIdMsg() {
      final out = <int>[];
      YtMusicProvider._pbFieldVarint(out, 1, itag);
      YtMusicProvider._pbFieldVarint(out, 2, lastModified);
      return out;
    }

    List<int> buildRequest({
      required int playerTimeMs,
      required bool locked,
      required (int startMs, int durMs, int startSeg, int endSeg)? buffered,
      required Uint8List? playbackCookie,
      required List<(int, Uint8List)> sabrContexts,
      required int elapsedMs,
      required int bandwidthBps,
      required bool mediaStart,
    }) {
      final out = <int>[];
      // 1: clientAbrState
      final abrState = <int>[];
      if (faithful) {
        if (bandwidthBps > 0) YtMusicProvider._pbFieldVarint(abrState, 23, bandwidthBps);
        YtMusicProvider._pbFieldVarint(abrState, 28, playerTimeMs);
        YtMusicProvider._pbFieldVarint(abrState, 29, elapsedMs);
        YtMusicProvider._pbFieldVarint(abrState, 34, 2); // visibility
        YtMusicProvider._pbFieldVarint(abrState, 36, elapsedMs);
        YtMusicProvider._pbFieldVarint(abrState, 39, elapsedMs);
        YtMusicProvider._pbFieldVarint(abrState, 40, 1); // enabledTrackTypes: audio
        YtMusicProvider._pbFieldVarint(abrState, 71, 1); // enableSabrHostFallback
      } else {
        YtMusicProvider._pbFieldVarint(abrState, 28, playerTimeMs);
        YtMusicProvider._pbFieldVarint(abrState, 40, 1);
      }
      YtMusicProvider._pbFieldBytes(out, 1, abrState);
      // 2: initializationFormatIds (referensi: tiap putaran; PoC: lanjutan saja)
      if (faithful || locked) YtMusicProvider._pbFieldBytes(out, 2, formatIdMsg());
      // 3: bufferedRange {1: formatId, 2: startTimeMs, 3: durationMs, 4/5: segmen}
      if (buffered != null) {
        final br = <int>[];
        YtMusicProvider._pbFieldBytes(br, 1, formatIdMsg());
        YtMusicProvider._pbFieldVarint(br, 2, buffered.$1);
        YtMusicProvider._pbFieldVarint(br, 3, buffered.$2);
        YtMusicProvider._pbFieldVarint(br, 4, buffered.$3);
        YtMusicProvider._pbFieldVarint(br, 5, buffered.$4);
        YtMusicProvider._pbFieldBytes(out, 3, br);
      }
      // 4: mediaStartTimeMs — resep PoC mengisinya dengan playhead;
      // resep referensi mengosongkannya (kecuali deklarasi lanjut sesi).
      if (mediaStart) YtMusicProvider._pbFieldVarint(out, 4, playerTimeMs);
      // 5: videoPlaybackUstreamerConfig
      if (ustreamerConfig != null) YtMusicProvider._pbFieldBytes(out, 5, ustreamerConfig);
      // 16: selectedAudioFormatIds
      YtMusicProvider._pbFieldBytes(out, 16, formatIdMsg());
      // 19: streamerContext {1: clientInfo, 2: poToken (E4, opsional),
      // 3: playbackCookie, 5: sabrContexts}
      final sc = <int>[];
      final ci = <int>[];
      if (spec.deviceMake != null) YtMusicProvider._pbFieldBytes(ci, 12, utf8.encode(spec.deviceMake!));
      if (spec.deviceModel != null) YtMusicProvider._pbFieldBytes(ci, 13, utf8.encode(spec.deviceModel!));
      YtMusicProvider._pbFieldVarint(ci, 16, spec.clientIdNum);
      YtMusicProvider._pbFieldBytes(ci, 17, utf8.encode(client.version));
      if (spec.osName != null) YtMusicProvider._pbFieldBytes(ci, 18, utf8.encode(spec.osName!));
      if (spec.osVersion != null) YtMusicProvider._pbFieldBytes(ci, 19, utf8.encode(spec.osVersion!));
      if (spec.androidSdk != null) YtMusicProvider._pbFieldVarint(ci, 64, spec.androidSdk!);
      YtMusicProvider._pbFieldBytes(sc, 1, ci);
      if (poToken != null) YtMusicProvider._pbFieldBytes(sc, 2, poToken);
      if (playbackCookie != null) YtMusicProvider._pbFieldBytes(sc, 3, playbackCookie);
      for (final (type, value) in sabrContexts) {
        final ctxMsg = <int>[];
        YtMusicProvider._pbFieldVarint(ctxMsg, 1, type);
        YtMusicProvider._pbFieldBytes(ctxMsg, 2, value);
        YtMusicProvider._pbFieldBytes(sc, 5, ctxMsg);
      }
      YtMusicProvider._pbFieldBytes(out, 19, sc);
      return out;
    }

    final dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 10)));
    final sw = Stopwatch()..start();
    var rounds = 0;
    var mediaBytesAudio = 0;
    var mediaBytesTotal = 0;
    var mediaParts = 0;
    final segments = <int>{};
    if (preSegEnd > 0) {
      for (var s = preSegStart; s <= preSegEnd; s++) {
        segments.add(s);
      }
    }
    int? endSegmentNumber;
    int? protection;
    var sabrError = false;
    var redirectHost = '';
    Uint8List? playbackCookie;
    final sabrContexts = <(int, Uint8List)>[];
    final activeCtxTypes = <int>{};
    var bufferedEndMs = preBufferedEndMs;
    var dryRounds = 0;
    var segStallRounds = 0;
    final partTypes = <int, int>{};
    var framing = '';
    final roundLog = <String>[];
    // NextRequestPolicy terakhir (field: 1 targetAudio, 3 maxSince, 4 backoff, 5 minAudio, 7 cookie)
    int? polTargetAudio, polBackoff, polMinAudio, polMaxSince;
    var policyLog = '';
    var stopReason = 'putaran habis';
    var rn = 0;
    var totalWaitMs = 0;
    final protLog = <String>[];

    while (rounds < maxRounds) {
      rounds++;
      final elapsed = sw.elapsedMilliseconds;
      // Taksiran frontier: ujung waktu header bila terbaca; selain itu
      // proporsi byte — fallback yang sama dengan PoC Batch 0. Tanpa ini
      // playhead tertahan 0 dan server mengirim ulang segmen pertama
      // selamanya (positif palsu lari v3.9 pertama).
      final estFrontierMs = bufferedEndMs > 0
          ? bufferedEndMs
          : (totalLen > 0 && approxDurMs > 0
              ? (mediaBytesAudio / totalLen * approxDurMs).round()
              : 0);
      final int playerTimeMs;
      if (!faithful || playheadMode == 3) {
        playerTimeMs = estFrontierMs;
      } else if (playheadMode == 2) {
        // Waktu-dinding murni: playhead pemutar sungguhan maju apa pun
        // yang terjadi pada buffer (RT-2 — uji kredibilitas playhead).
        playerTimeMs = startAtMs + elapsed;
      } else {
        playerTimeMs = startAtMs;
      }
      // Deklarasi ter-buffer yang jujur: frontier header, atau cakupan
      // segmen berbeda × durasi nominal per segmen, atau warisan sesi
      // sebelumnya (mode perpanjangan) — mana yang terbesar.
      final esn = endSegmentNumber;
      final nominalBufferedMs = (esn != null && esn > 0 && approxDurMs > 0)
          ? (segments.length * approxDurMs / esn).round()
          : 0;
      var declaredBufferedMs = bufferedEndMs > nominalBufferedMs ? bufferedEndMs : nominalBufferedMs;
      if (preBufferedEndMs > declaredBufferedMs) declaredBufferedMs = preBufferedEndMs;
      final bwe = mediaBytesTotal <= 0
          ? 3000000
          : (mediaBytesTotal * 8 * 1000 ~/ (elapsed < 1 ? 1 : elapsed)).clamp(50000, 100000000).toInt();
      final sendCtx = faithful
          ? sabrContexts
              .where((e) => activeCtxTypes.isEmpty || activeCtxTypes.contains(e.$1))
              .toList()
          : sabrContexts;
      final reqBytes = buildRequest(
        playerTimeMs: playerTimeMs,
        locked: rounds > 1,
        buffered: (rounds > 1 || preBufferedEndMs > 0) && declaredBufferedMs > 0
            ? (
                0,
                declaredBufferedMs,
                segments.isEmpty ? preSegStart : segments.reduce((a, b) => a < b ? a : b),
                segments.isEmpty ? preSegEnd : segments.reduce((a, b) => a > b ? a : b),
              )
            : null,
        playbackCookie: playbackCookie,
        sabrContexts: sendCtx,
        elapsedMs: elapsed,
        bandwidthBps: bwe,
        mediaStart: faithful ? (rounds == 1 && startAtMs > 0) : playerTimeMs > 0,
      );
      var url = abrUrl!;
      if (faithful) {
        final u = Uri.parse(url);
        url = u.replace(queryParameters: {...u.queryParameters, 'rn': '$rn'}).toString();
      }
      rn++;
      final int httpStatus;
      final List<int>? data;
      if (transport != null) {
        // Transport halaman (Probe WebView E4): fetch dijalankan DARI
        // DALAM WebView watch oleh pemanggil — cookie/origin/TLS halaman
        // ikut; null berarti transport gagal (diperlakukan status 0).
        Uint8List? tb;
        try {
          tb = await transport(url, Uint8List.fromList(reqBytes));
        } catch (_) {
          tb = null;
        }
        httpStatus = tb == null ? 0 : 200;
        data = tb;
      } else {
        final Response<List<int>> resp;
        try {
          resp = await dio.post<List<int>>(url,
              data: Uint8List.fromList(reqBytes),
              options: Options(
                responseType: ResponseType.bytes,
                headers: {
                  'User-Agent': client.userAgent,
                  'Content-Type': 'application/x-protobuf',
                },
                receiveTimeout: const Duration(seconds: 60),
                validateStatus: (_) => true,
              ));
        } catch (e) {
          stopReason = 'POST galat: ${describeError(e)}';
          break;
        }
        httpStatus = resp.statusCode ?? 0;
        data = resp.data;
      }
      if (httpStatus != 200 || data == null || data.isEmpty) {
        stopReason = 'HTTP $httpStatus (${data?.length ?? 0} byte)';
        break;
      }
      final bytes = data is Uint8List ? data : Uint8List.fromList(data);
      if (rounds == 1) {
        final head = bytes.take(8).map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
        framing = 'HTTP $httpStatus - ${bytes.length} byte - head=$head';
      }
      final headers = <int, (int itag, int startRange, int seq, bool isInit)>{};
      var pos = 0;
      var newMedia = 0;
      var newSegs = 0;
      while (pos < bytes.length) {
        final (partType, n1) = YtMusicProvider._umpVarint(bytes, pos);
        pos += n1;
        if (pos >= bytes.length) break;
        final (partSize, n2) = YtMusicProvider._umpVarint(bytes, pos);
        pos += n2;
        if (partSize < 0 || pos + partSize > bytes.length) break;
        final payload = Uint8List.sublistView(bytes, pos, pos + partSize);
        pos += partSize;
        partTypes[partType] = (partTypes[partType] ?? 0) + 1;
        switch (partType) {
          case 20: // MEDIA_HEADER
            final m = YtMusicProvider._pbParse(payload);
            final hid = YtMusicProvider._pbInt(m, 1);
            final hItag = YtMusicProvider._pbInt(m, 3);
            if (hid != null && hItag != null) {
              headers[hid] = (
                hItag,
                YtMusicProvider._pbInt(m, 6) ?? 0,
                YtMusicProvider._pbInt(m, 9) ?? -1,
                (YtMusicProvider._pbInt(m, 8) ?? 0) != 0,
              );
              final start = YtMusicProvider._pbInt(m, 11);
              final dur = YtMusicProvider._pbInt(m, 12);
              if (start != null && dur != null && hItag == itag) {
                final end = start + dur;
                if (end > bufferedEndMs) bufferedEndMs = end;
              }
            }
          case 21: // MEDIA
            if (payload.isEmpty) break;
            final (hid, hn) = YtMusicProvider._umpVarint(payload, 0);
            final h = headers[hid];
            final n = payload.length - hn;
            mediaBytesTotal += n;
            newMedia += n;
            if (h != null && h.$1 == itag) {
              mediaBytesAudio += n;
              mediaParts++;
              if (h.$3 >= 0 && !segments.contains(h.$3)) {
                segments.add(h.$3);
                newSegs++;
              }
            }
          case 42: // FORMAT_INITIALIZATION_METADATA
            final m = YtMusicProvider._pbParse(payload);
            endSegmentNumber = YtMusicProvider._pbInt(m, 4) ?? endSegmentNumber;
          case 35: // NEXT_REQUEST_POLICY
            final m = YtMusicProvider._pbParse(payload);
            final tA = YtMusicProvider._pbInt(m, 1);
            final mS = YtMusicProvider._pbInt(m, 3);
            final bO = YtMusicProvider._pbInt(m, 4);
            final mA = YtMusicProvider._pbInt(m, 5);
            if (tA != null || bO != null) {
              final sig = 'tA=$tA mA=$mA bo=$bO mS=$mS';
              if (policyLog.isEmpty) policyLog = sig;
              if (tA != polTargetAudio || bO != polBackoff) {
                policyLog = '$policyLog -> $sig';
              }
              polTargetAudio = tA ?? polTargetAudio;
              polMinAudio = mA ?? polMinAudio;
              polMaxSince = mS ?? polMaxSince;
              polBackoff = bO ?? polBackoff;
            }
            playbackCookie = YtMusicProvider._pbBytes(m, 7) ?? playbackCookie;
          case 57: // SABR_CONTEXT_UPDATE {1 type, 3 value, 4 sendByDefault, 5 writePolicy}
            final m = YtMusicProvider._pbParse(payload);
            final t = YtMusicProvider._pbInt(m, 1);
            final v = YtMusicProvider._pbBytes(m, 3);
            final keepExisting = (YtMusicProvider._pbInt(m, 5) ?? 0) == 1;
            if (t != null && v != null) {
              if (!(keepExisting && sabrContexts.any((e) => e.$1 == t))) {
                sabrContexts.removeWhere((e) => e.$1 == t);
                sabrContexts.add((t, v));
              }
              if ((YtMusicProvider._pbInt(m, 4) ?? 0) != 0) activeCtxTypes.add(t);
            }
          case 59: // SABR_CONTEXT_SENDING_POLICY {1 start, 2 stop, 3 discard}
            final m = YtMusicProvider._pbParse(payload);
            List<int> idsOf(int f) {
              final out = <int>[];
              for (final v in m[f] ?? const <Object>[]) {
                if (v is int) out.add(v);
                if (v is Uint8List) {
                  var p = 0;
                  while (p < v.length) {
                    var r = 0, sh = 0;
                    while (p < v.length && sh < 64) {
                      final b = v[p++];
                      r |= (b & 0x7F) << sh;
                      if (b & 0x80 == 0) break;
                      sh += 7;
                    }
                    out.add(r);
                  }
                }
              }
              return out;
            }
            final starts = idsOf(1), stops = idsOf(2), discs = idsOf(3);
            activeCtxTypes.addAll(starts);
            activeCtxTypes.removeAll(stops);
            for (final d in discs) {
              sabrContexts.removeWhere((e) => e.$1 == d);
              activeCtxTypes.remove(d);
            }
            roundLog.add('pol59:mula$starts henti$stops buang$discs');
          case 58: // STREAM_PROTECTION_STATUS {1: status, 2: maxRetries}
            final m = YtMusicProvider._pbParse(payload);
            protection = YtMusicProvider._pbInt(m, 1) ?? protection;
            protLog.add('r$rounds:st${YtMusicProvider._pbInt(m, 1) ?? '-'}/mr${YtMusicProvider._pbInt(m, 2) ?? '-'}');
          case 43: // SABR_REDIRECT {1: url}
            final m = YtMusicProvider._pbParse(payload);
            final u = YtMusicProvider._pbBytes(m, 1);
            if (u != null) {
              abrUrl = utf8.decode(u, allowMalformed: true);
              redirectHost = Uri.tryParse(abrUrl)?.host ?? '';
            }
          case 44: // SABR_ERROR
            sabrError = true;
        }
      }
      final maxSeg = segments.isEmpty ? 0 : segments.reduce((a, b) => a > b ? a : b);
      roundLog.add('r$rounds:+$newMedia/s$maxSeg/pt$playerTimeMs/el${sw.elapsedMilliseconds}');
      if (sabrError) {
        stopReason = 'sabrError';
        break;
      }
      if (!faithful && protection == 3) {
        stopReason = 'proteksi 3 (resep PoC berhenti)';
        break;
      }
      if (endSegmentNumber != null && segments.isNotEmpty && maxSeg >= endSegmentNumber) {
        stopReason = 'tuntas-segmen';
        break;
      }
      if (approxDurMs > 0 && bufferedEndMs * 100 >= approxDurMs * 95) {
        stopReason = 'tuntas-waktu';
        break;
      }
      // Penjaga putaran duplikat: media mengalir tapi tak ada segmen BARU
      // selama 3 putaran = server mengirim ulang segmen yang sama
      // (byte-sum akan berpura-pura maju — jangan tertipu). Nonaktif di
      // mode waktu-dinding: di sana playhead-lah sinyal kemajuannya, dan
      // pengiriman ulang segmen berjalan memang perilaku server.
      if (playheadMode != 2 && newMedia > 0 && newSegs == 0) {
        segStallRounds++;
        if (segStallRounds >= 3) {
          stopReason = 'segmen berputar (duplikat)';
          break;
        }
      } else if (newSegs > 0) {
        segStallRounds = 0;
      }
      if (newMedia == 0 && newSegs == 0) {
        dryRounds++;
        if (dryRounds >= (faithful ? 3 : 2)) {
          stopReason = 'kering×$dryRounds';
          break;
        }
      } else {
        dryRounds = 0;
      }
      if (playheadMode == 2 && approxDurMs > 0 && playerTimeMs > approxDurMs + 20000) {
        stopReason = 'playhead melewati akhir lagu';
        break;
      }
      if (faithful && polBackoff != null && polBackoff > 0 && rounds < maxRounds) {
        final wait = polBackoff > 8000 ? 8000 : polBackoff;
        totalWaitMs += wait;
        await Future<void>.delayed(Duration(milliseconds: wait));
      }
    }
    if (rounds >= maxRounds && stopReason == 'putaran habis') {
      stopReason = 'putaran habis ($maxRounds)';
    }
    return SabrSessionResult(
      config: config,
      itag: itag,
      rounds: rounds,
      mediaBytesAudio: mediaBytesAudio,
      mediaBytesTotal: mediaBytesTotal,
      segments: segments.length,
      maxSegment: segments.isEmpty ? 0 : segments.reduce((a, b) => a > b ? a : b),
      endSegmentNumber: endSegmentNumber,
      contentLength: totalLen,
      approxDurMs: approxDurMs,
      bufferedEndMs: bufferedEndMs,
      frontierMs: bufferedEndMs > 0
          ? bufferedEndMs
          : (totalLen > 0 && approxDurMs > 0
              ? (mediaBytesAudio / totalLen * approxDurMs).round()
              : 0),
      protection: protection,
      sabrError: sabrError,
      partTypes: partTypes,
      policySummary: policyLog,
      stopReason: stopReason,
      elapsedMs: sw.elapsedMilliseconds,
      protectionSeries: protLog.join(' '),
      detail: 'mediaParts=$mediaParts · redirectHost=$redirectHost · '
          'ustreamerConfig=${ustreamerConfig == null ? 'tidak ada' : 'ada'} · '
          'konteks=${sabrContexts.length} (aktif ${activeCtxTypes.length}) · '
          'tungguBackoff=${totalWaitMs}ms · bingkai: $framing · putaran: ${roundLog.join(' ')}',
    );
  }
}

// ================= Diagnostik Tahap 2 — Mesin Penyeberangan 2.0 =================
// Replikasi resep innertubex v0.11.2 (Metrolist) di harness, melawan
// gerbang ronde-rode sebelumnya. Sumber konstruksi dibaca langsung dari
// clone studi-sumber/innertubex (SabrProtoCodec, SabrBootstrapFactory,
// SabrAudioStream, PlayerClientDirector, YouTubeClient) — lihat
// studi-sumber/RESEP-DAN-SELISIH.md. Diagnostik SAJA; jalur produksi
// tidak disentuh. URL bertanda tangan, token, visitorData & config
// hanya hidup di memori objek-objek ini; hasil yang boleh dicatat
// hanyalah angka, host, nama field, dan panjang.

/// Halaman watch yang diambil SEKALI untuk bootstrap Tahap 2: HTML-nya
/// memberi makan Lab PoToken (tantangan ytAtN halaman itu sendiri),
/// sedangkan field terurainya memberi makan resolusi player — keduanya
/// terikat pada pengambilan yang sama persis (resep direktur sumber).
/// Satu format dari respons player, identitas SABR lengkap.
class SabrFormatData {
  final int itag;
  final int lastModified;
  final String? xtags;
  final int contentLength;
  final int approxDurMs;
  final int bitrate;
  final String mime;
  final String? audioTrackId;
  final bool isDrc;
  final int height;
  const SabrFormatData({
    required this.itag,
    required this.lastModified,
    this.xtags,
    this.contentLength = 0,
    this.approxDurMs = 0,
    this.bitrate = 0,
    this.mime = '',
    this.audioTrackId,
    this.isDrc = false,
    this.height = 0,
  });
}

/// Bootstrap sesi SABR ala SabrBootstrapFactory (toSabrBootstrap):
/// URL ABR + ustreamerConfig + format audio terpilih + format video
/// buangan, semuanya dari SATU respons player.
class SabrBootstrapData {
  final String playability;
  final String reason;
  final String? error;
  final String? abrUrl; // memori saja
  final Uint8List? ustreamerConfig;
  final SabrFormatData? audio;
  final SabrFormatData? discard;
  final int durationMs;
  final int clientIdNum;
  final String clientVersion;
  final String userAgent;
  const SabrBootstrapData({
    this.playability = '-',
    this.reason = '',
    this.error,
    this.abrUrl,
    this.ustreamerConfig,
    this.audio,
    this.discard,
    this.durationMs = 0,
    this.clientIdNum = 0,
    this.clientVersion = '',
    this.userAgent = '',
  });
  bool get ready => error == null && abrUrl != null && audio != null && discard != null && ustreamerConfig != null;
}

/// Diagnostik SATU respons UMP di mesin WEB SABR (pola
/// SabrResponseDiagnostics sumber).
class WebSabrResponseDiag {
  final int rn;
  final int requestPlayerTimeMs;
  final int httpStatus;
  final int newSegments;
  final int cumSegments;
  final int cumMediaBytes;
  final int frontierMs;
  final int? protectionStatus;
  final int? protectionMaxRetries; // null = field 2 dihilangkan respons ini
  final int backoffMs;
  final int responseBytes;
  const WebSabrResponseDiag({
    required this.rn,
    required this.requestPlayerTimeMs,
    required this.httpStatus,
    required this.newSegments,
    required this.cumSegments,
    required this.cumMediaBytes,
    required this.frontierMs,
    required this.protectionStatus,
    required this.protectionMaxRetries,
    required this.backoffMs,
    required this.responseBytes,
  });
}

/// Hasil satu sesi WEB SABR resep sumber.
class WebSabrResult {
  final bool complete;
  final String failureKind; // '' | ATTESTATION_REQUIRED | TANPA_KEMAJUAN | PROTOKOL | SABR_ERROR | RELOAD_PLAYER | HTTP
  final String stopReason;
  final int requests;
  final int emittedBytes; // init + media, teremisikan berurutan (unik)
  final int mediaBytes; // media saja, unik (segmen teremisikan)
  final int segments;
  final int? firstSegment;
  final int? lastSegment;
  final int? endSegmentNumber;
  final int contentLength;
  final int frontierMs;
  final int durationMs;
  final Map<int, int> partTypes;
  final List<WebSabrResponseDiag> responses;
  final String validation; // rincian cek validateCompleteStream ala sumber
  final int elapsedMs;
  const WebSabrResult({
    this.complete = false,
    this.failureKind = '',
    this.stopReason = '',
    this.requests = 0,
    this.emittedBytes = 0,
    this.mediaBytes = 0,
    this.segments = 0,
    this.firstSegment,
    this.lastSegment,
    this.endSegmentNumber,
    this.contentLength = 0,
    this.frontierMs = 0,
    this.durationMs = 0,
    this.partTypes = const {},
    this.responses = const [],
    this.validation = '',
    this.elapsedMs = 0,
  });

  /// Cakupan byte unik (media teremisikan / contentLength).
  int get byteCoveragePct => contentLength <= 0 ? 0 : mediaBytes * 100 ~/ contentLength;
}

/// Pelari Tahap 2: bootstrap halaman, resolusi SABR mentah, resolusi
/// DIRECT mentah, dan mesin sesi WEB SABR setia-sumber.
/// Resolusi jalur DIRECT-1 (Tahap 3) — implementasi PRODUKSI yang
/// di-porting dari konstruksi E3 Tahap 2 (Matriks U, LULUS lagu utuh):
/// konteks halaman watch + resolusi player WEB_REMIX membawa
/// signatureTimestamp. Metode debug* Tahap 2 kini mendelegasikan ke sini.
extension DirectResolution on YtMusicProvider {
  /// SATU pengambilan halaman watch untuk [videoId] (www lebih dulu,
  /// music sebagai cadangan): visitorData tamu + signatureTimestamp
  /// (pola ekstraksi benar — lihat [parseWatchContextHtml]) + jsUrl
  /// player. HTML hanya hidup di memori hasil; kegagalan semua sumber
  /// menghasilkan WatchPageData ber-error (gugur anggun, pemanggil yang
  /// memutuskan fallback).
  Future<WatchPageData> fetchWatchContext(String videoId) async {
    Future<String?> fetchHtml(String url) async {
      try {
        final res = await _dio.get<String>(url,
            options: Options(headers: {
              'User-Agent': _uaWeb,
              'Accept-Language': 'en-US,en;q=0.9',
            }, responseType: ResponseType.plain));
        return res.data;
      } catch (_) {
        return null;
      }
    }

    for (final (source, url) in [
      ('watch-www', 'https://www.youtube.com/watch?v=$videoId'),
      ('watch-music', 'https://music.youtube.com/watch?v=$videoId'),
    ]) {
      final html = await fetchHtml(url);
      if (html == null) continue;
      final f = parseWatchContextHtml(html);
      return WatchPageData(
        html: html,
        visitorData: f.visitorData,
        signatureTimestamp: f.signatureTimestamp,
        jsUrl: f.jsUrl,
        hasEventId: f.hasEventId,
        hasYtAtN: f.hasYtAtN,
        source: source,
      );
    }
    return const WatchPageData(source: '(semua sumber gagal)', error: 'halaman watch tidak terambil');
  }

  /// Resolusi DIRECT mentah: konteks WEB_REMIX katalog, urutan direktur —
  /// tanpa token dulu; pemanggil mengulang dengan [playerPoToken]
  /// (terikat VISITOR_DATA untuk keluarga ini) bila tak ada format
  /// terpakai. Nilai URL/cipher hanya hidup di memori hasil.
  Future<DirectResolveData> resolveDirectFormats(
    Track track, {
    String? visitorData,
    int? signatureTimestamp,
    String? playerPoToken,
  }) async {
    final client = _debugClientCtx('WEB_REMIX_SABR');
    if (client == null) return const DirectResolveData(error: 'konteks WEB_REMIX_SABR tidak ada');
    final Map<String, dynamic> res;
    try {
      final body = await _sabrPlayerBody(client, track,
          visitorData: visitorData,
          signatureTimestamp: signatureTimestamp,
          playerPoToken: playerPoToken);
      res = await _postDebugPlayer(client, body, videoId: track.playableRef);
    } catch (e) {
      return DirectResolveData(error: 'resolusi WEB_REMIX galat: ${describeError(e)}');
    }
    final ps = asMap(res['playabilityStatus']);
    final status = ps?['status'] as String? ?? '(tanpa status)';
    final reason = ps?['reason'] as String? ?? simpleText(ps?['messages']) ?? '';
    if (status != 'OK') return DirectResolveData(playability: status, reason: reason);
    final sd = asMap(res['streamingData']);
    final formats = <DirectFormat>[];
    for (final e in asList(sd?['adaptiveFormats'])) {
      final f = asMap(e);
      if (f == null) continue;
      final mime = (f['mimeType'] as String?) ?? '';
      if (!mime.startsWith('audio/')) continue;
      final direct = f['url'] as String?;
      String? cs, base;
      var sp = 'signature';
      final cipher = (f['signatureCipher'] as String?) ?? (f['cipher'] as String?);
      if (direct == null && cipher != null) {
        final q = Uri.splitQueryString(cipher);
        cs = q['s'];
        sp = q['sp'] ?? 'signature';
        base = q['url'];
      }
      formats.add(DirectFormat(
        itag: looseInt(f['itag']) ?? -1,
        mime: mime,
        bitrate: looseInt(f['bitrate']),
        contentLength: int.tryParse('${f['contentLength'] ?? ''}'),
        directUrl: direct,
        cipherS: cs,
        cipherSp: sp,
        cipherBaseUrl: base,
      ));
    }
    return DirectResolveData(
      playability: status,
      reason: reason,
      formats: formats,
      expiresInSeconds: looseInt(sd?['expiresInSeconds']) ?? 21600,
    );
  }
}

extension SabrTahap2Probe on YtMusicProvider {
  /// Dekode base64url persis decodeBase64Url sumber: ganti -_ ke +/,
  /// tambah padding, dekode standar.
  static Uint8List b64UrlDecode(String value) {
    var s = value.replaceAll('-', '+').replaceAll('_', '/');
    s = s.padRight(s.length + (4 - s.length % 4) % 4, '=');
    return base64.decode(s);
  }

  /// Ambil halaman watch www SATU kali (fallback music) dan urai bahan
  /// bootstrap yang terikat padanya: visitorData, signatureTimestamp,
  /// jsUrl player, kehadiran EVENT_ID & ytAtN. HTML utuh dikembalikan
  /// di memori untuk Lab PoToken (tantangan halaman).
  /// Delegasi kompatibilitas harness Tahap 2 — implementasi produksi:
  /// [DirectResolution.fetchWatchContext].
  Future<WatchPageData> debugFetchWatchPage(String videoId) => fetchWatchContext(videoId);

  /// Tubuh permintaan player ala direktur: konteks klien + visitorData
  /// di context.client + signatureTimestamp halaman di playbackContext,
  /// dan (bila diberikan) serviceIntegrityDimensions.poToken = token
  /// player sesuai binding klien (WEB: terikat VIDEO_ID; WEB_REMIX:
  /// terikat VISITOR_DATA — pemanggil yang menyediakan token yang benar).

  SabrFormatData _fmtData(Map<String, dynamic> f) => SabrFormatData(
        itag: (f['itag'] as num?)?.toInt() ?? 0,
        lastModified: int.tryParse('${f['lastModified'] ?? '0'}') ?? 0,
        xtags: f['xtags'] as String?,
        contentLength: int.tryParse('${f['contentLength'] ?? '0'}') ?? 0,
        approxDurMs: int.tryParse('${f['approxDurationMs'] ?? '0'}') ?? 0,
        bitrate: (f['bitrate'] as num?)?.toInt() ?? 0,
        mime: (f['mimeType'] as String?) ?? '',
        audioTrackId: asMap(f['audioTrack'])?['id'] as String?,
        isDrc: f['isDrc'] == true,
        height: (f['height'] as num?)?.toInt() ?? 0,
      );

  /// Resolusi player untuk bootstrap SABR: [clientKey] 'WEB_SABR'
  /// (host www + kunci www) atau 'WEB_REMIX_SABR' (host music).
  /// Mengembalikan bootstrap lengkap atau alasan gugurnya.
  Future<SabrBootstrapData> debugResolveSabrBootstrap(
    String clientKey,
    Track track, {
    String? visitorData,
    int? signatureTimestamp,
    String? playerPoToken,
  }) async {
    final client = _debugClientCtx(clientKey);
    if (client == null) {
      return SabrBootstrapData(error: 'konteks klien $clientKey tidak ada');
    }
    final webHost = clientKey == 'WEB_SABR';
    final Map<String, dynamic> res;
    try {
      final body = await _sabrPlayerBody(client, track,
          visitorData: visitorData,
          signatureTimestamp: signatureTimestamp,
          playerPoToken: playerPoToken);
      res = await _postDebugPlayer(client, body, videoId: track.playableRef, webHost: webHost);
    } catch (e) {
      return SabrBootstrapData(
          error: 'resolusi ${client.name} galat: ${describeError(e)}',
          clientIdNum: int.tryParse(YtMusicProvider._clientHeaderId(client.name)) ?? 0,
          clientVersion: client.version,
          userAgent: client.userAgent);
    }
    final ps = asMap(res['playabilityStatus']);
    final status = ps?['status'] as String? ?? '(tanpa status)';
    final reason = ps?['reason'] as String? ?? simpleText(ps?['messages']) ?? '';
    SabrBootstrapData fail(String err) => SabrBootstrapData(
        playability: status, reason: reason, error: err,
        clientIdNum: int.tryParse(YtMusicProvider._clientHeaderId(client.name)) ?? 0,
        clientVersion: client.version, userAgent: client.userAgent);
    if (status != 'OK') return fail('playability $status');
    final sd = asMap(res['streamingData']);
    final abrUrl = sd?['serverAbrStreamingUrl'] as String?;
    if (abrUrl == null) return fail('serverAbrStreamingUrl tidak terbit');
    final urc = asMap(asMap(asMap(res['playerConfig'])?['mediaCommonConfig'])?['mediaUstreamerRequestConfig']);
    final cfgB64 = urc?['videoPlaybackUstreamerConfig'] as String?;
    if (cfgB64 == null) return fail('videoPlaybackUstreamerConfig tidak ada');
    final Uint8List ustreamerConfig;
    try {
      ustreamerConfig = b64UrlDecode(cfgB64);
    } catch (_) {
      return fail('videoPlaybackUstreamerConfig tidak terdekode');
    }
    final fmts = <Map<String, dynamic>>[
      for (final e in asList(sd?['adaptiveFormats']))
        if (asMap(e) != null) asMap(e)!,
    ];
    // Kandidat audio SABR (isSabrAudioCandidate): audio, itag>0,
    // lastModified>0. Pilihan: bitrate tertinggi <= plafon Normal,
    // selain itu terendah (konvensi harness yang sama dengan PoC).
    final audioCands = fmts
        .where((f) =>
            ((f['mimeType'] as String?) ?? '').startsWith('audio/') &&
            ((f['itag'] as num?)?.toInt() ?? 0) > 0 &&
            (int.tryParse('${f['lastModified'] ?? '0'}') ?? 0) > 0)
        .toList()
      ..sort((a, b) => ((a['bitrate'] as num?)?.toInt() ?? 0).compareTo((b['bitrate'] as num?)?.toInt() ?? 0));
    if (audioCands.isEmpty) return fail('tidak ada kandidat audio SABR (lastModified>0)');
    Map<String, dynamic>? pick;
    for (final f in audioCands) {
      if (((f['bitrate'] as num?)?.toInt() ?? 0) <= StreamQuality.normal.maxBitrate) pick = f;
    }
    pick ??= audioCands.first;
    // Video buangan (sabrDiscardVideoFormat): non-audio, height>0,
    // lastModified>0, minimum menurut (height, bitrate).
    final videoCands = fmts
        .where((f) =>
            !((f['mimeType'] as String?) ?? '').startsWith('audio/') &&
            ((f['height'] as num?)?.toInt() ?? 0) > 0 &&
            (int.tryParse('${f['lastModified'] ?? '0'}') ?? 0) > 0)
        .toList()
      ..sort((a, b) {
        final h = ((a['height'] as num?)?.toInt() ?? 0).compareTo((b['height'] as num?)?.toInt() ?? 0);
        return h != 0 ? h : ((a['bitrate'] as num?)?.toInt() ?? 0).compareTo((b['bitrate'] as num?)?.toInt() ?? 0);
      });
    if (videoCands.isEmpty) return fail('tidak ada format video buangan (height>0, lastModified>0)');
    final audio = _fmtData(pick);
    final durationMs = audio.approxDurMs > 0
        ? audio.approxDurMs
        : ((asMap(res['videoDetails'])?['lengthSeconds'] as String?) != null
            ? (int.tryParse(asMap(res['videoDetails'])!['lengthSeconds'] as String) ?? 0) * 1000
            : 0);
    if (durationMs <= 0) return fail('durasi tidak terbaca');
    return SabrBootstrapData(
      playability: status,
      reason: reason,
      abrUrl: abrUrl,
      ustreamerConfig: ustreamerConfig,
      audio: audio,
      discard: _fmtData(videoCands.first),
      durationMs: durationMs,
      clientIdNum: int.tryParse(YtMusicProvider._clientHeaderId(client.name)) ?? 0,
      clientVersion: client.version,
      userAgent: client.userAgent,
    );
  }

  /// Resolusi DIRECT mentah (E3): konteks WEB_REMIX katalog, direktur —
  /// tanpa token dulu; pemanggil mengulang dengan [playerPoToken]
  /// (terikat VISITOR_DATA untuk keluarga ini) bila perlu.
  /// Delegasi kompatibilitas harness Tahap 2 — implementasi produksi:
  /// [DirectResolution.resolveDirectFormats].
  Future<DirectResolveData> debugResolveDirectRaw(
    Track track, {
    String? visitorData,
    int? signatureTimestamp,
    String? playerPoToken,
  }) =>
      resolveDirectFormats(track,
          visitorData: visitorData,
          signatureTimestamp: signatureTimestamp,
          playerPoToken: playerPoToken);
}

/// Header MEDIA (part 20) yang terurai di mesin WEB SABR.
class _WebSabrHeader {
  final int itag;
  final int lastModified;
  final String? xtags;
  final bool isInit;
  final int sequenceNumber;
  final int startMs;
  final int durationMs;
  final int contentLength;
  final String? videoId;
  const _WebSabrHeader({
    required this.itag,
    required this.lastModified,
    this.xtags,
    required this.isInit,
    required this.sequenceNumber,
    required this.startMs,
    required this.durationMs,
    required this.contentLength,
    this.videoId,
  });
  int get endMs => startMs + durationMs;
}

/// Mesin sesi SABR keluarga WEB — port Dart setia dari
/// SabrProtoCodec.encodeRequest + SabrAudioStream (mode unduh: tanpa
/// penyedia posisi putar) innertubex v0.11.2. Perbedaan yang disengaja
/// & dicatat: (1) tubuh respons UMP dibuffer utuh oleh Dio, jadi
/// penantian penyusunan-ulang pembuka 250 ms sumber runtuh menjadi
/// "tunggu akhir respons" — setara hasil; (2) batas putaran diagnostik
/// 80 & batas waktu 900 dtk (sumber: 10.000) agar lari matriks
/// terbatas; (3) penghentian baca saat proteksi REQUIRED diterapkan
/// sebagai penghentian pemrosesan part, setara karena tubuh sudah
/// terbuffer.
extension SabrWebRunProbe on YtMusicProvider {
  static void _pbFixed32(List<int> out, int field, double v) {
    YtMusicProvider._pbTag(out, field, 5);
    final bd = ByteData(4)..setFloat32(0, v, Endian.little);
    out.addAll(bd.buffer.asUint8List());
  }

  static int _ticksToMs(int ticks, int timescale) {
    final wholeSeconds = ticks ~/ timescale;
    final wholeMs = wholeSeconds * 1000;
    final fracMs = (ticks % timescale) * 1000 ~/ timescale;
    return wholeMs + fracMs;
  }

  static List<int> _fmtIdMsg(SabrFormatData f) {
    final out = <int>[];
    YtMusicProvider._pbFieldVarint(out, 1, f.itag);
    if (f.lastModified != 0) YtMusicProvider._pbFieldVarint(out, 2, f.lastModified);
    if (f.xtags != null && f.xtags!.isNotEmpty) {
      YtMusicProvider._pbFieldBytes(out, 3, utf8.encode(f.xtags!));
    }
    return out;
  }

  static List<int> _bufferedRangeMsg(
      SabrFormatData f, int startMs, int durMs, int startSeg, int endSeg) {
    final out = <int>[];
    YtMusicProvider._pbFieldBytes(out, 1, _fmtIdMsg(f));
    if (startMs != 0) YtMusicProvider._pbFieldVarint(out, 2, startMs);
    YtMusicProvider._pbFieldVarint(out, 3, durMs);
    YtMusicProvider._pbFieldVarint(out, 4, startSeg);
    YtMusicProvider._pbFieldVarint(out, 5, endSeg);
    final tr = <int>[];
    if (startMs != 0) YtMusicProvider._pbFieldVarint(tr, 1, startMs);
    YtMusicProvider._pbFieldVarint(tr, 2, durMs);
    YtMusicProvider._pbFieldVarint(tr, 3, 1000);
    YtMusicProvider._pbFieldBytes(out, 6, tr);
    return out;
  }

  static List<int> _discardRangeMsg(SabrFormatData f) {
    const sentinel = 2147483647; // Int.MAX_VALUE
    final out = <int>[];
    YtMusicProvider._pbFieldBytes(out, 1, _fmtIdMsg(f));
    YtMusicProvider._pbFieldVarint(out, 3, sentinel);
    YtMusicProvider._pbFieldVarint(out, 4, sentinel);
    YtMusicProvider._pbFieldVarint(out, 5, sentinel);
    final tr = <int>[];
    YtMusicProvider._pbFieldVarint(tr, 2, sentinel);
    YtMusicProvider._pbFieldVarint(tr, 3, 1000);
    YtMusicProvider._pbFieldBytes(out, 6, tr);
    return out;
  }

  /// Port encodeRequest: susunan field persis SabrProtoCodec
  /// (1 state, 2 format terpilih bila initialized + format buangan
  /// selalu, 3 rentang ter-buffer + rentang buangan, 5 config,
  /// 16 audio, 17 buangan, 19 konteks streamer).
  static List<int> _encodeRequest({
    required SabrBootstrapData b,
    required int playerTimeMs,
    required bool initialized,
    required ({int startMs, int durMs, int startSeg, int endSeg})? declaredRange,
    required Uint8List? playbackCookie,
    required Map<int, Uint8List> contexts,
    required Set<int> activeTypes,
    required Uint8List? poTokenBytes,
  }) {
    final audio = b.audio!;
    final discard = b.discard!;
    final out = <int>[];
    // 1: ClientAbrState
    final state = <int>[];
    if (discard.height != 0) YtMusicProvider._pbFieldVarint(state, 21, discard.height);
    if (playerTimeMs != 0) YtMusicProvider._pbFieldVarint(state, 28, playerTimeMs);
    YtMusicProvider._pbFieldVarint(state, 34, 1);
    _pbFixed32(state, 35, 1.0);
    YtMusicProvider._pbFieldVarint(state, 40, 1); // audio
    if (audio.isDrc) YtMusicProvider._pbFieldVarint(state, 46, 1);
    if (audio.audioTrackId != null && audio.audioTrackId!.isNotEmpty) {
      YtMusicProvider._pbFieldBytes(state, 69, utf8.encode(audio.audioTrackId!));
    }
    YtMusicProvider._pbFieldBytes(out, 1, state);
    // 2: format terpilih (hanya bila initialized) + format buangan (selalu)
    if (initialized) YtMusicProvider._pbFieldBytes(out, 2, _fmtIdMsg(audio));
    YtMusicProvider._pbFieldBytes(out, 2, _fmtIdMsg(discard));
    // 3: rentang ter-buffer nyata + rentang buangan
    if (declaredRange != null) {
      YtMusicProvider._pbFieldBytes(
          out, 3, _bufferedRangeMsg(audio, declaredRange.startMs, declaredRange.durMs, declaredRange.startSeg, declaredRange.endSeg));
    }
    YtMusicProvider._pbFieldBytes(out, 3, _discardRangeMsg(discard));
    // 5: ustreamerConfig
    YtMusicProvider._pbFieldBytes(out, 5, b.ustreamerConfig!);
    // 16/17: format audio / video buangan
    YtMusicProvider._pbFieldBytes(out, 16, _fmtIdMsg(audio));
    YtMusicProvider._pbFieldBytes(out, 17, _fmtIdMsg(discard));
    // 19: streamerContext
    final sc = <int>[];
    final ci = <int>[];
    YtMusicProvider._pbFieldVarint(ci, 16, b.clientIdNum);
    YtMusicProvider._pbFieldBytes(ci, 17, utf8.encode(b.clientVersion));
    YtMusicProvider._pbFieldBytes(sc, 1, ci);
    if (poTokenBytes != null) YtMusicProvider._pbFieldBytes(sc, 2, poTokenBytes);
    if (playbackCookie != null) YtMusicProvider._pbFieldBytes(sc, 3, playbackCookie);
    for (final e in contexts.entries) {
      if (!activeTypes.contains(e.key)) continue;
      final msg = <int>[];
      YtMusicProvider._pbFieldVarint(msg, 1, e.key);
      YtMusicProvider._pbFieldBytes(msg, 2, e.value);
      YtMusicProvider._pbFieldBytes(sc, 5, msg);
    }
    final unsent = <int>[];
    for (final t in contexts.keys) {
      if (!activeTypes.contains(t)) {
        YtMusicProvider._pbVarint(unsent, t);
      }
    }
    if (unsent.isNotEmpty) YtMusicProvider._pbFieldBytes(sc, 6, unsent);
    YtMusicProvider._pbFieldBytes(out, 19, sc);
    return out;
  }

  static bool _fmtMatches(_WebSabrHeader h, SabrFormatData sel) =>
      h.itag == sel.itag &&
      (sel.lastModified == 0 || h.lastModified == sel.lastModified) &&
      (sel.xtags == null || sel.xtags!.isEmpty || h.xtags == sel.xtags);

  /// Satu sesi WEB SABR penuh. [urlOverride] dipakai pemanggil untuk
  /// URL yang sudah ditransformasi-n / ditempeli cpn; [origin] =
  /// origin keluarga (music.youtube.com / www.youtube.com) untuk
  /// header Origin+Referer ala SabrAudioStream.
  Future<WebSabrResult> debugWebSabrRun(
    SabrBootstrapData b, {
    required String videoId,
    Uint8List? poTokenBytes,
    String? urlOverride,
    String? origin,
    int maxRequests = 80,
  }) async {
    final sw = Stopwatch()..start();
    if (!b.ready) {
      return WebSabrResult(failureKind: 'PROTOKOL', stopReason: 'bootstrap tidak siap: ${b.error}', durationMs: b.durationMs, elapsedMs: 0);
    }
    final audio = b.audio!;
    var streamingUrl = urlOverride ?? b.abrUrl!;
    final dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 10)));
    var playerTimeMs = 0;
    var initialized = false;
    int? initEndSegment;
    int? initDurationMs;
    var initSegmentEmitted = false;
    Uint8List? playbackCookie;
    var backoffMs = 0;
    ({int startMs, int durMs, int startSeg, int endSeg})? declaredRange;
    _WebSabrHeader? firstBuffered;
    var requestsWithoutProgress = 0;
    var ended = false;
    int? firstSeq;
    int? lastSeq;
    var emittedBytes = 0;
    var mediaBytes = 0;
    var cumSegments = 0;
    var protectionPending = false;
    var protectionRetryCount = 0;
    int? protectionRetryLimit;
    var omittedAllowancePending = false;
    var omittedPendingCount = 0;
    final contexts = <int, Uint8List>{};
    final activeTypes = <int>{};
    final partTypes = <int, int>{};
    final responses = <WebSabrResponseDiag>[];
    var failureKind = '';
    var stopReason = 'selesai';
    var rn = 0;
    var requestCount = 0;

    int expectedDuration() { final d = initDurationMs; return (d != null && d > 0) ? d : b.durationMs; }

    // Segmen tertahan lintas respons (persis sumber: pendingMediaBySequence
    // adalah state SESI — segmen yang belum teremisikan di akhir respons
    // dibawa ke permintaan berikutnya, bukan galat).
    final pending = <int, ({_WebSabrHeader header, Uint8List data})>{};

    while (!ended &&
        failureKind.isEmpty &&
        !(initEndSegment != null && lastSeq != null && lastSeq! >= initEndSegment) &&
        playerTimeMs < expectedDuration()) {
      if (requestCount >= maxRequests) {
        failureKind = 'PROTOKOL';
        stopReason = 'batas putaran diagnostik ($maxRequests)';
        break;
      }
      if (sw.elapsedMilliseconds > 900000) {
        failureKind = 'PROTOKOL';
        stopReason = 'batas waktu diagnostik 900 dtk';
        break;
      }
      if (backoffMs > 0) {
        await Future<void>.delayed(Duration(milliseconds: backoffMs > 30000 ? 30000 : backoffMs));
      }
      final requestPlayerTimeMs = playerTimeMs;
      final reqBytes = _encodeRequest(
        b: b,
        playerTimeMs: requestPlayerTimeMs,
        initialized: initialized,
        declaredRange: declaredRange,
        playbackCookie: playbackCookie,
        contexts: contexts,
        activeTypes: activeTypes,
        poTokenBytes: poTokenBytes,
      );

      // ---- POST dengan percobaan-ulang transien ala sumber (<=2) ----
      Response<List<int>>? resp;
      var transientFailures = 0;
      while (true) {
        final u = Uri.parse(streamingUrl);
        final url = u.replace(queryParameters: {...u.queryParameters, 'rn': '$rn'}).toString();
        rn++;
        requestCount++;
        try {
          resp = await dio.post<List<int>>(url,
              data: Uint8List.fromList(reqBytes),
              options: Options(
                responseType: ResponseType.bytes,
                followRedirects: false,
                maxRedirects: 0,
                validateStatus: (_) => true,
                receiveTimeout: const Duration(seconds: 60),
                headers: {
                  'User-Agent': b.userAgent,
                  'Content-Type': 'application/x-protobuf',
                  'Accept': 'application/vnd.yt-ump',
                  'Accept-Encoding': 'identity',
                  if (origin != null) 'Origin': origin,
                  if (origin != null) 'Referer': '$origin/',
                },
              ));
        } catch (e) {
          failureKind = 'HTTP';
          stopReason = 'POST galat: ${describeError(e)}';
          resp = null;
          break;
        }
        final status = resp.statusCode ?? 0;
        const transient = {408, 425, 429, 500, 502, 503, 504};
        if (transient.contains(status) && transientFailures < 2) {
          transientFailures++;
          final ra = int.tryParse(resp.headers.value('retry-after') ?? '');
          var delayMs = ra != null ? ra * 1000 : (250 << (transientFailures - 1));
          if (delayMs < 250) delayMs = 250;
          if (delayMs > 5000) delayMs = 5000;
          await Future<void>.delayed(Duration(milliseconds: delayMs));
          continue;
        }
        break;
      }
      if (failureKind.isNotEmpty) break;
      final httpStatus = resp!.statusCode ?? 0;
      final data = resp.data;
      if (httpStatus < 200 || httpStatus >= 300 || data == null || data.isEmpty) {
        failureKind = 'HTTP';
        stopReason = httpStatus >= 300 && httpStatus < 400
            ? 'HTTP $httpStatus — redirect dilarang protokol SABR'
            : 'HTTP $httpStatus (${data?.length ?? 0} byte)';
        responses.add(WebSabrResponseDiag(
            rn: rn - 1, requestPlayerTimeMs: requestPlayerTimeMs, httpStatus: httpStatus,
            newSegments: 0, cumSegments: cumSegments, cumMediaBytes: mediaBytes,
            frontierMs: playerTimeMs, protectionStatus: null, protectionMaxRetries: null,
            backoffMs: backoffMs, responseBytes: data?.length ?? 0));
        break;
      }
      final ct = resp.headers.value('content-type') ?? '';
      if (!ct.startsWith('application/vnd.yt-ump')) {
        failureKind = 'PROTOKOL';
        stopReason = 'content-type bukan UMP: $ct';
        break;
      }

      // ---- proses part UMP respons ini ----
      final bytes = data is Uint8List ? data : Uint8List.fromList(data);
      final headers = <int, _WebSabrHeader>{};
      // Rangkaian potongan MEDIA per headerId (SabrUmpProcessor sumber:
      // part 21 menambahkan potongan; part 22 MEDIA_END memfinalkan
      // segmen dan memvalidasi panjangnya terhadap contentLength).
      final segChunks = <int, BytesBuilder>{};
      var responseInitCount = 0;
      int? respProtection;
      int? respProtectionMr;
      var respMrPresent = false;
      var terminalProtection = false;
      var newSegmentCount = 0;
      _WebSabrHeader? lastNewHeader;

      void emit(({_WebSabrHeader header, Uint8List data}) seg) {
        final h = seg.header;
        if (firstSeq == null) {
          final gap = h.startMs - requestPlayerTimeMs;
          if (gap > 1 || h.endMs <= requestPlayerTimeMs) {
            failureKind = 'PROTOKOL';
            stopReason = 'segmen pertama (seq ${h.sequenceNumber}) tidak menutupi waktu minta $requestPlayerTimeMs (start ${h.startMs})';
            return;
          }
        }
        firstSeq ??= h.sequenceNumber;
        lastSeq = h.sequenceNumber;
        if (h.endMs > playerTimeMs) playerTimeMs = h.endMs;
        emittedBytes += seg.data.length;
        mediaBytes += seg.data.length;
        cumSegments++;
        newSegmentCount++;
        firstBuffered ??= h;
        lastNewHeader = h;
      }

      void tryEmit({bool establishFromMinimum = false}) {
        if (failureKind.isNotEmpty) return;
        if (lastSeq == null) {
          int? first;
          if (pending.containsKey(0) && requestPlayerTimeMs <= 0) {
            first = 0;
          } else if (establishFromMinimum && pending.isNotEmpty) {
            first = pending.keys.reduce((a, c) => a < c ? a : c);
          }
          if (first == null) return;
          emit(pending.remove(first)!);
        }
        while (failureKind.isEmpty && lastSeq != null && pending.containsKey(lastSeq! + 1)) {
          emit(pending.remove(lastSeq! + 1)!);
        }
      }

      var pos = 0;
      while (pos < bytes.length && failureKind.isEmpty && !terminalProtection) {
        final (partType, n1) = YtMusicProvider._umpVarint(bytes, pos);
        pos += n1;
        if (pos >= bytes.length) break;
        final (partSize, n2) = YtMusicProvider._umpVarint(bytes, pos);
        pos += n2;
        if (partSize < 0 || pos + partSize > bytes.length) break;
        final payload = Uint8List.sublistView(bytes, pos, pos + partSize);
        pos += partSize;
        partTypes[partType] = (partTypes[partType] ?? 0) + 1;
        switch (partType) {
          case 20: // MEDIA_HEADER
            final m = YtMusicProvider._pbParse(payload);
            final hid = YtMusicProvider._pbInt(m, 1);
            final fItag = YtMusicProvider._pbInt(m, 3);
            if (hid != null && fItag != null) {
              if (headers.containsKey(hid)) {
                failureKind = 'PROTOKOL';
                stopReason = 'header media ganda id $hid dalam satu respons (SabrUmpProcessor)';
              }
              var startMs = YtMusicProvider._pbInt(m, 11) ?? 0;
              var durMs = YtMusicProvider._pbInt(m, 12) ?? 0;
              final trBytes = YtMusicProvider._pbBytes(m, 15);
              if (trBytes != null && (startMs == 0 || durMs == 0)) {
                final tr = YtMusicProvider._pbParse(trBytes);
                final ts = YtMusicProvider._pbInt(tr, 3);
                if (ts != null && ts > 0) {
                  if (startMs == 0) startMs = _ticksToMs(YtMusicProvider._pbInt(tr, 1) ?? 0, ts);
                  if (durMs == 0) durMs = _ticksToMs(YtMusicProvider._pbInt(tr, 2) ?? 0, ts);
                }
              }
              headers[hid] = _WebSabrHeader(
                itag: fItag,
                lastModified: YtMusicProvider._pbInt(m, 4) ?? 0,
                xtags: (YtMusicProvider._pbBytes(m, 5) != null)
                    ? utf8.decode(YtMusicProvider._pbBytes(m, 5)!, allowMalformed: true)
                    : null,
                isInit: (YtMusicProvider._pbInt(m, 8) ?? 0) != 0,
                sequenceNumber: YtMusicProvider._pbInt(m, 9) ?? -1,
                startMs: startMs,
                durationMs: durMs,
                contentLength: YtMusicProvider._pbInt(m, 14) ?? 0,
                videoId: (YtMusicProvider._pbBytes(m, 2) != null)
                    ? utf8.decode(YtMusicProvider._pbBytes(m, 2)!, allowMalformed: true)
                    : null,
              );
            }
          case 21: // MEDIA — potongan data; dirangkai per headerId
            if (payload.isEmpty) break;
            final (hid, hn) = YtMusicProvider._umpVarint(payload, 0);
            final h = headers[hid];
            if (h == null) break;
            if (_fmtMatches(h, audio) && (h.videoId == null || h.videoId == videoId)) {
              segChunks.putIfAbsent(hid, () => BytesBuilder(copy: false))
                  .add(Uint8List.sublistView(payload, hn));
            }
          case 22: // MEDIA_END — segmen utuh selesai dirangkai
            if (payload.isEmpty) break;
            final (hid, _) = YtMusicProvider._umpVarint(payload, 0);
            final h = headers[hid];
            final chunks = segChunks.remove(hid);
            if (h == null || chunks == null) break;
            final segData = chunks.takeBytes();
            if (h.contentLength > 0 && segData.length != h.contentLength) {
              failureKind = 'PROTOKOL';
              stopReason = 'segmen seq ${h.sequenceNumber} terangkai ${segData.length} byte '
                  '!= contentLength ${h.contentLength} (validasi SabrUmpProcessor)';
              break;
            }
            if (h.isInit) {
              if (_fmtMatches(h, audio) && (h.videoId == null || h.videoId == videoId)) {
                responseInitCount++;
                if (responseInitCount > 1) {
                  failureKind = 'PROTOKOL';
                  stopReason = 'segmen inisialisasi ganda dalam satu respons';
                  break;
                }
                if (!initSegmentEmitted) {
                  initSegmentEmitted = true;
                  emittedBytes += segData.length;
                  tryEmit();
                }
              }
            } else if (_fmtMatches(h, audio) && (h.videoId == null || h.videoId == videoId)) {
              final seq = h.sequenceNumber;
              final fs0 = firstSeq;
              final ls0 = lastSeq;
              final alreadyEmitted = fs0 != null && ls0 != null && seq >= fs0 && seq <= ls0;
              if (!alreadyEmitted) {
                if (pending.containsKey(seq)) {
                  failureKind = 'PROTOKOL';
                  stopReason = 'segmen duplikat pending seq $seq (protokol sumber: galat)';
                  break;
                }
                pending[seq] = (header: h, data: segData);
                if (initSegmentEmitted) tryEmit();
              }
            }
          case 42: // FORMAT_INITIALIZATION_METADATA
            final m = YtMusicProvider._pbParse(payload);
            final fBytes = YtMusicProvider._pbBytes(m, 2);
            if (fBytes != null) {
              final fm = YtMusicProvider._pbParse(fBytes);
              final probe = _WebSabrHeader(
                itag: YtMusicProvider._pbInt(fm, 1) ?? 0,
                lastModified: YtMusicProvider._pbInt(fm, 2) ?? 0,
                xtags: (YtMusicProvider._pbBytes(fm, 3) != null)
                    ? utf8.decode(YtMusicProvider._pbBytes(fm, 3)!, allowMalformed: true)
                    : null,
                isInit: false,
                sequenceNumber: -1,
                startMs: 0,
                durationMs: 0,
                contentLength: 0,
              );
              if (_fmtMatches(probe, audio)) {
                initialized = true;
                initEndSegment = YtMusicProvider._pbInt(m, 4) ?? initEndSegment;
                final units = YtMusicProvider._pbInt(m, 9);
                final scale = YtMusicProvider._pbInt(m, 10);
                if (units != null && scale != null && scale > 0) {
                  initDurationMs = _ticksToMs(units, scale);
                } else {
                  initDurationMs = YtMusicProvider._pbInt(m, 3) ?? initDurationMs;
                }
              }
            }
          case 35: // NEXT_REQUEST_POLICY {1 target, 3 maxSince, 4 backoff, 5 min, 7 cookie}
            final m = YtMusicProvider._pbParse(payload);
            backoffMs = YtMusicProvider._pbInt(m, 4) ?? backoffMs;
            playbackCookie = YtMusicProvider._pbBytes(m, 7) ?? playbackCookie;
          case 43: // SABR_REDIRECT {1: url}
            final m = YtMusicProvider._pbParse(payload);
            final u = YtMusicProvider._pbBytes(m, 1);
            if (u != null) streamingUrl = utf8.decode(u, allowMalformed: true);
          case 44: // SABR_ERROR {1: type, 2: code}
            final m = YtMusicProvider._pbParse(payload);
            final t = YtMusicProvider._pbBytes(m, 1);
            failureKind = 'SABR_ERROR';
            stopReason = 'SABR_ERROR type=${t == null ? '-' : utf8.decode(t, allowMalformed: true)} code=${YtMusicProvider._pbInt(m, 2) ?? '-'}';
          case 46: // RELOAD_PLAYER_RESPONSE
            failureKind = 'RELOAD_PLAYER';
            stopReason = 'server meminta respons player segar (RELOAD_PLAYER)';
          case 57: // SABR_CONTEXT_UPDATE {1 type, 3 value, 4 sendByDefault, 5 writePolicy}
            final m = YtMusicProvider._pbParse(payload);
            final t = YtMusicProvider._pbInt(m, 1);
            final v = YtMusicProvider._pbBytes(m, 3);
            if (t != null && v != null) {
              const keepExisting = 2;
              final wp = YtMusicProvider._pbInt(m, 5) ?? 0;
              if (wp != keepExisting || !contexts.containsKey(t)) {
                contexts[t] = v;
              }
              if ((YtMusicProvider._pbInt(m, 4) ?? 0) != 0) activeTypes.add(t);
            }
          case 58: // STREAM_PROTECTION_STATUS {1 status, 2 maxRetries}
            final m = YtMusicProvider._pbParse(payload);
            respProtection = YtMusicProvider._pbInt(m, 1) ?? respProtection;
            final mr = YtMusicProvider._pbInt(m, 2);
            if (mr != null) {
              respProtectionMr = mr;
              respMrPresent = true;
            }
            if ((respProtection ?? 0) >= 3) terminalProtection = true;
          case 59: // SABR_CONTEXT_SENDING_POLICY {1 start, 2 stop, 3 discard}
            final m = YtMusicProvider._pbParse(payload);
            List<int> idsOf(int f) {
              final out = <int>[];
              for (final v in m[f] ?? const <Object>[]) {
                if (v is int) out.add(v);
                if (v is Uint8List) {
                  var p = 0;
                  while (p < v.length) {
                    var r = 0, sh = 0;
                    while (p < v.length && sh < 64) {
                      final by = v[p++];
                      r |= (by & 0x7F) << sh;
                      if (by & 0x80 == 0) break;
                      sh += 7;
                    }
                    out.add(r);
                  }
                }
              }
              return out;
            }

            activeTypes.addAll(idsOf(1));
            activeTypes.removeAll(idsOf(2));
            for (final d in idsOf(3)) {
              contexts.remove(d);
              activeTypes.remove(d);
            }
          case 62: // END_OF_TRACK
            ended = true;
        }
      }
      if (failureKind.isEmpty && !terminalProtection) {
        // Persis sumber (emitReadyMediaSegments(establishFromMinimum:
        // true) di akhir respons): flush dari minimum; sisa pending
        // DIBAWA ke permintaan berikut — bukan galat per respons.
        tryEmit(establishFromMinimum: true);
      }

      if (failureKind.isEmpty) {
        if (newSegmentCount > 0) {
          requestsWithoutProgress = 0;
          final first = firstBuffered!;
          final last = lastNewHeader!;
          declaredRange = (
            startMs: first.startMs,
            durMs: (last.startMs + last.durationMs - first.startMs) < 0
                ? 0
                : (last.startMs + last.durationMs - first.startMs),
            startSeg: first.sequenceNumber,
            endSeg: lastSeq ?? last.sequenceNumber,
          );
        }

        // ---- akuntansi anggaran proteksi (persis SabrAudioStream) ----
        if (respProtection != null && respProtection >= 3) {
          protectionPending = true;
        } else if (respProtection == 2) {
          protectionPending = true;
          omittedAllowancePending = !respMrPresent;
          if (respMrPresent) protectionRetryLimit = respProtectionMr;
        } else if (respProtection == 1) {
          protectionPending = false;
          protectionRetryCount = 0;
          protectionRetryLimit = null;
          omittedAllowancePending = false;
        }
        if (protectionPending && !(respProtection != null && respProtection >= 3)) {
          protectionRetryCount++;
          if (omittedAllowancePending) omittedPendingCount++;
        }
        responses.add(WebSabrResponseDiag(
            rn: rn - 1, requestPlayerTimeMs: requestPlayerTimeMs, httpStatus: httpStatus,
            newSegments: newSegmentCount, cumSegments: cumSegments, cumMediaBytes: mediaBytes,
            frontierMs: playerTimeMs, protectionStatus: respProtection,
            protectionMaxRetries: respMrPresent ? respProtectionMr : null,
            backoffMs: backoffMs, responseBytes: bytes.length));
        final retriesExhausted = (protectionRetryLimit != null && protectionRetryCount > protectionRetryLimit) ||
            omittedPendingCount > 5;
        if (protectionPending &&
            ((respProtection != null && respProtection >= 3) || newSegmentCount == 0 || retriesExhausted)) {
          failureKind = 'ATTESTATION_REQUIRED';
          stopReason = 'proteksi memerlukan atestasi (status ${respProtection ?? 2}, '
              'coba=$protectionRetryCount/${protectionRetryLimit ?? 'tak-disebut'}, '
              'segmenBaru=$newSegmentCount, anggaranHabis=$retriesExhausted)';
        } else if (newSegmentCount == 0 && !ended) {
          requestsWithoutProgress++;
          if (requestsWithoutProgress >= 3) {
            failureKind = 'TANPA_KEMAJUAN';
            stopReason = 'tanpa kemajuan 3 putaran (segmen ${lastSeq ?? '-'}/${initEndSegment ?? '-'}, '
                'waktu $playerTimeMs/${expectedDuration()}ms, initialized=$initialized)';
          }
        }
      } else {
        responses.add(WebSabrResponseDiag(
            rn: rn - 1, requestPlayerTimeMs: requestPlayerTimeMs, httpStatus: httpStatus,
            newSegments: newSegmentCount, cumSegments: cumSegments, cumMediaBytes: mediaBytes,
            frontierMs: playerTimeMs, protectionStatus: respProtection,
            protectionMaxRetries: respMrPresent ? respProtectionMr : null,
            backoffMs: backoffMs, responseBytes: bytes.length));
      }
    }

    if (failureKind.isEmpty && protectionPending) {
      failureKind = 'ATTESTATION_REQUIRED';
      stopReason = 'aliran berakhir saat proteksi masih pending';
    }

    // ---- validasi tuntas ala validateCompleteStream ----
    final checks = <String>[];
    var valid = failureKind.isEmpty;
    if (!initSegmentEmitted) {
      checks.add('init=TIDAK-ADA');
      valid = false;
    } else {
      checks.add('init=ada');
    }
    if (initEndSegment != null) {
      final okSeq = lastSeq == initEndSegment;
      checks.add('seqAkhir=$lastSeq vs end=$initEndSegment ${okSeq ? 'OK' : 'SELISIH'}');
      if (!okSeq) valid = false;
    } else {
      checks.add('endSegmentNumber=tidak-diketahui');
    }
    final expDur = expectedDuration();
    final tol = expDur ~/ 100 > 2000 ? expDur ~/ 100 : 2000;
    final durDiff = (playerTimeMs - expDur).abs();
    final okDur = durDiff <= tol;
    checks.add('durasi=$playerTimeMs vs $expDur (selisih $durDiff, tol $tol) ${okDur ? 'OK' : 'SELISIH'}');
    if (!okDur) valid = false;
    if (audio.contentLength > 0) {
      final okBytes = emittedBytes == audio.contentLength;
      checks.add('byteTeremisikan=$emittedBytes vs contentLength=${audio.contentLength} ${okBytes ? 'PERSIS' : 'SELISIH'}');
      if (!okBytes) valid = false;
    }
    if (failureKind.isNotEmpty) valid = false;

    return WebSabrResult(
      complete: valid,
      failureKind: failureKind,
      stopReason: stopReason,
      requests: requestCount,
      emittedBytes: emittedBytes,
      mediaBytes: mediaBytes,
      segments: cumSegments,
      firstSegment: firstSeq,
      lastSegment: lastSeq,
      endSegmentNumber: initEndSegment,
      contentLength: audio.contentLength,
      frontierMs: playerTimeMs,
      durationMs: expDur,
      partTypes: partTypes,
      responses: responses,
      validation: checks.join(' · '),
      elapsedMs: sw.elapsedMilliseconds,
    );
  }

}
