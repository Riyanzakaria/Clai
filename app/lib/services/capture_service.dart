import 'package:dio/dio.dart';
import '../l10n/l10n.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../data/app_db.dart';
import '../domain/models.dart';
import '../providers/music_provider.dart';
import '../providers/spotify/spotify_provider.dart';
import 'ocr_model_service.dart';
import 'observability.dart';
import 'track_matcher.dart';
import 'voice_commands.dart';

/// Ditandai saat Tangkap-gambar diminta tetapi model OCR belum terpasang —
/// UI menampilkannya sebagai tawaran unduh, bukan kegagalan.
class OcrModelMissing implements Exception {
  const OcrModelMissing();
  @override
  String toString() => l10n.capSvcModelMissing;
}

/// Satu baris hasil tangkapan: ditemukan (dengan trek audio Clai) atau tidak
/// (dengan alasan) — kegagalan dilaporkan per item, tidak diam-diam.
class CaptureItem {
  final String label;
  final Track? track;
  final String? error;
  const CaptureItem({required this.label, this.track, this.error});
}

/// Tangkap dari Mana Saja (F2 Batch 2, PRD 5.14 C): teks/tautan/gambar yang
/// dibagikan dari aplikasi mana pun → lagu Clai.
/// - Playlist Spotify → metadata Spotify, tiap lagu dicocokkan ke audio YTM.
/// - Playlist YouTube → langsung trek YTM (sudah sumber audio).
/// - Tautan watch / tautan umum → judul via oEmbed/<title> → pencarian YTM.
/// - Teks bebas → kata kunci pencarian YTM.
/// - Gambar → OCR Tesseract (Kotlin) → tiap baris jadi kata kunci pencarian.
///   Model OCR TIDAK terbundel: diunduh sekali di dalam aplikasi
///   (OcrModelController, cara ketiga) lalu bekerja offline.
/// Pencocokan memakai skor suara yang sama (ambang 0.35) agar "cocok" berarti
/// benar-benar lagu itu, bukan hasil pertama yang asal bunyi.
class CaptureService extends ChangeNotifier {
  final AppDb db;
  final MusicProvider ytm;
  final SpotifyMetadataProvider spotify;
  final TrackMatcher matcher;
  final Dio _dio;

  /// Pengendali model OCR (opsional agar tes lama tetap berdiri sendiri);
  /// di aplikasi nyata selalu disambungkan dari app.dart.
  OcrModelController? ocrModels;

  static const _shareCh = MethodChannel('clai/share');

  String inputSummary = '';
  List<CaptureItem> items = [];
  bool working = false;
  String? error;

  CaptureService(this.db, this.ytm, this.spotify, this.matcher, {Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
                connectTimeout: const Duration(seconds: 8),
                receiveTimeout: const Duration(seconds: 15)));

  List<Track> get foundTracks =>
      items.where((i) => i.track != null).map((i) => i.track!).toList();

  static final _urlRe = RegExp(r'https?://[^\s]+');

  /// Klasifikasi tautan (murni, diuji unit).
  static ({String kind, String id})? classifyUrl(String url) {
    final spotifyPl =
        RegExp(r'open\.spotify\.com/playlist/([A-Za-z0-9]+)').firstMatch(url);
    if (spotifyPl != null) {
      return (kind: 'spotify-playlist', id: spotifyPl.group(1)!);
    }
    final spotifyTr =
        RegExp(r'open\.spotify\.com/track/([A-Za-z0-9]+)').firstMatch(url);
    if (spotifyTr != null) return (kind: 'spotify-track', id: spotifyTr.group(1)!);
    final ytPl = RegExp(r'[?&]list=([A-Za-z0-9_-]+)').firstMatch(url);
    if (url.contains('youtube.com') || url.contains('youtu.be')) {
      if (ytPl != null) return (kind: 'youtube-playlist', id: ytPl.group(1)!);
      final watch = RegExp(r'[?&]v=([A-Za-z0-9_-]+)').firstMatch(url) ??
          RegExp(r'youtu\.be/([A-Za-z0-9_-]+)').firstMatch(url);
      if (watch != null) return (kind: 'youtube-watch', id: watch.group(1)!);
    }
    if (ytPl != null) return (kind: 'youtube-playlist', id: ytPl.group(1)!);
    return null;
  }

  Future<String?> ocrImage(String uri) async {
    final models = ocrModels;
    if (models == null) return null;
    if (models.status != OcrModelStatus.ready || models.dataPath == null) {
      throw const OcrModelMissing();
    }
    try {
      return await _shareCh.invokeMethod<String>('ocrImage',
          {'uri': uri, 'dataPath': models.dataPath, 'lang': models.lang});
    } on PlatformException catch (e) {
      if (e.code == 'model-belum-ada') throw const OcrModelMissing();
      // Kegagalan OCR (izin URI tertolak scoped storage, gambar rusak,
      // mesin gagal) dicatat jujur ke log insiden: layar menampilkan
      // "tidak ada teks terbaca", tetapi sebabnya bisa ditelusur.
      Observability.instance.log('ocr-gagal', '${e.code}: ${e.message}');
      return null;
    } catch (_) {
      return null;
    }
  }

  void _push(CaptureItem item) {
    items = [...items, item];
    notifyListeners();
  }

  Future<void> captureText(String input) async {
    items = [];
    error = null;
    working = true;
    inputSummary = input.length > 80 ? '${input.substring(0, 80)}…' : input;
    notifyListeners();
    try {
      final urls = _urlRe
          .allMatches(input)
          .map((m) => m.group(0)!)
          .map((u) => u.replaceAll(RegExp(r'[),.]+$'), ''))
          .toList();
      if (urls.isEmpty) {
        await _searchItem(input.trim(), label: input.trim());
      } else {
        for (final url in urls) {
          await _captureUrl(url);
        }
        // Sisa teks non-tautan diperlakukan sebagai kata kunci tambahan.
        final rest = input.replaceAll(_urlRe, ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
        if (rest.isNotEmpty) await _searchItem(rest, label: rest);
      }
    } catch (e) {
      error = e.toString();
    } finally {
      working = false;
      notifyListeners();
    }
  }

  Future<void> captureImage(String uri) async {
    items = [];
    error = null;
    working = true;
    inputSummary = l10n.capImageList;
    notifyListeners();
    try {
      final text = await ocrImage(uri);
      if (text == null || text.trim().isEmpty) {
        error = l10n.capSvcNoText;
      } else {
        final lines = text
            .split('\n')
            .map((l) => l.trim())
            .where((l) => l.length >= 3)
            .take(30)
            .toList();
        if (lines.isEmpty) {
          error = l10n.capSvcNoLines;
        } else {
          for (final line in lines) {
            await _searchItem(line, label: line);
          }
        }
      }
    } on OcrModelMissing {
      error = l10n.capSvcModelMissingLong;
    } catch (e) {
      error = e.toString();
    } finally {
      working = false;
      notifyListeners();
    }
  }

  Future<void> _captureUrl(String url) async {
    final c = classifyUrl(url);
    if (c == null) {
      // Tautan umum: judul halaman → pencarian.
      final title = await _pageTitle(url);
      if (title == null) {
        _push(CaptureItem(label: url, error: l10n.capSvcTitleUnreadable));
      } else {
        await _searchItem(title, label: l10n.capSvcFromLink(title));
      }
      return;
    }
    switch (c.kind) {
      case 'spotify-playlist':
        try {
          final pl = await spotify.getPlaylist(c.id);
          inputSummary = l10n.capSvcSpotifySummary(pl.name);
          notifyListeners();
          for (final src in pl.tracks) {
            final label = '${src.title} — ${src.artistNames}';
            try {
              final matched = await matcher.match(src);
              _push(matched == null
                  ? CaptureItem(label: label, error: l10n.capSvcNoAudioMatch)
                  : CaptureItem(label: label, track: matched));
            } catch (_) {
              _push(CaptureItem(label: label, error: l10n.capSvcMatchFailed));
            }
          }
        } catch (_) {
          _push(CaptureItem(label: url, error: l10n.capSvcPlaylistNotFound));
        }
        break;
      case 'spotify-track':
        final meta = await _spotifyOembed(url);
        if (meta == null) {
          _push(CaptureItem(label: url, error: l10n.capSvcMetaUnreadable));
        } else {
          await _searchItem(meta, label: meta);
        }
        break;
      case 'youtube-playlist':
        try {
          final page = await ytm.getPlaylist(c.id);
          inputSummary = l10n.capSvcYtSummary(page.title);
          notifyListeners();
          for (final t in page.tracks) {
            _push(CaptureItem(label: '${t.title} — ${t.artistNames}', track: t));
          }
        } catch (_) {
          _push(CaptureItem(label: url, error: l10n.capSvcPlaylistLoadFail));
        }
        break;
      case 'youtube-watch':
        final meta = await _youtubeOembed(url);
        if (meta == null) {
          _push(CaptureItem(label: url, error: l10n.capSvcVideoMetaUnreadable));
        } else {
          await _searchItem(meta, label: meta);
        }
        break;
    }
  }

  Future<void> _searchItem(String query, {required String label}) async {
    try {
      final results = await ytm.search(query);
      if (results.songs.isEmpty) {
        _push(CaptureItem(label: label, error: l10n.capSvcNotFound));
        return;
      }
      final likedKeys = await db.likedKeys();
      final counts = await db.playCounts();
      final scored = results.songs
          .map((t) => (
                track: t,
                score: voiceScore(query, t,
                    liked: likedKeys.contains(t.key), plays: counts[t.key] ?? 0)
              ))
          .toList()
        ..sort((a, b) => b.score.compareTo(a.score));
      final top = scored.first;
      if (top.score < kVoiceAcceptThreshold) {
        _push(CaptureItem(label: label, error: l10n.capSvcNoGoodMatch));
      } else {
        _push(CaptureItem(label: label, track: top.track));
      }
    } catch (_) {
      _push(CaptureItem(label: label, error: l10n.capSvcSearchFailed));
    }
  }

  Future<String?> _pageTitle(String url) async {
    try {
      final res = await _dio.get<String>(url,
          options: Options(responseType: ResponseType.plain,
              validateStatus: (s) => s != null && s < 400));
      final html = res.data ?? '';
      final m = RegExp(r'<title[^>]*>([^<]+)</title>', caseSensitive: false)
          .firstMatch(html);
      final title = m?.group(1)?.trim();
      if (title == null || title.isEmpty) return null;
      return title;
    } catch (_) {
      return null;
    }
  }

  Future<String?> _spotifyOembed(String url) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
          'https://open.spotify.com/oembed',
          queryParameters: {'url': url});
      final title = res.data?['title'] as String?;
      final author = res.data?['author_name'] as String?;
      if (title == null) return null;
      return author == null ? title : '$title $author';
    } catch (_) {
      return null;
    }
  }

  Future<String?> _youtubeOembed(String url) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
          'https://www.youtube.com/oembed',
          queryParameters: {'url': url, 'format': 'json'});
      final title = res.data?['title'] as String?;
      final author = res.data?['author_name'] as String?;
      if (title == null) return null;
      return author == null ? title : '$title $author';
    } catch (_) {
      return null;
    }
  }
}
