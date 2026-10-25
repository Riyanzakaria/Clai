import 'dart:math';
import 'package:dio/dio.dart';
import '../../core/error_describe.dart';
import '../../data/app_db.dart';
import '../../domain/models.dart';
import '../music_provider.dart';
import 'innertube.dart';

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

  YtMusicProvider(this.db);

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
    void findHeader(Object? n) {
      if (n is Map) {
        for (final e in n.entries) {
          if (e.key == 'musicDetailHeaderRenderer' || e.key == 'musicResponsiveHeaderRenderer' || e.key == 'musicImmersiveHeaderRenderer') {
            final m = asMap(e.value)!;
            title = simpleText(m['title']) ?? title;
            subtitle = runsText(m['subtitle']) ?? runsText(m['secondSubtitle']) ?? subtitle;
            artwork = thumbUrl(m['thumbnail'], minWidth: 200) ?? thumbUrl(m['croppedSquareThumbnailRenderer'] ?? m, minWidth: 200) ?? artwork;
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
    var pageTracks = tracks;
    if ((kind == 'album' || kind == 'playlist') && artwork != null) {
      pageTracks = [for (final t in tracks) t.artworkUrl == null ? t.copyWith(artworkUrl: artwork) : t];
    }
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
  Future<StreamInfo> resolveStream(Track track, StreamQuality quality) async {
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
