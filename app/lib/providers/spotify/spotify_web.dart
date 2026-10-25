import 'dart:convert';
import '../../l10n/l10n.dart';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../../domain/models.dart';

/// Lapisan web Spotify — CLEAN-ROOM (F2, PETA-JALAN butir 1).
///
/// Ditulis dari fakta protokol publik yang diverifikasi empiris dari PC
/// pemilik pada 2026-10-24 (laporan: builds/bukti-emulator-f2b1/riset-spotify.md).
/// TIDAK ada kode dari proyek lain yang disalin — termasuk spotube-plugin-
/// spotify (AGPL) yang hanya dijadikan pembanding arah model pada evaluasi.
///
/// Model terpilih: token web ANONIM (tanpa akun, tanpa kunci pengembang
/// pengguna) → GraphQL internal web (persisted query `fetchPlaylist`).
/// Konstanta di bawah ini FAKTA PROTOKOL yang beredar publik & terbukti
/// hidup; Spotify bisa merotasinya — kegagalannya harus terdegradasi anggun
/// di pemanggil (pesan jujur + Log insiden), bukan crash.
const kSpotifyTotpSecret = '376136387538459893883312310911992847112448894410210511297108';
const kSpotifyTotpVersion = 61;
const kSpotifyFetchPlaylistHash = '91d4c2bc3e0cd1bc672281c4f1f59f43ff55ba726ca04a45810d99bd091f3f0e';

/// TOTP web player Spotify (RFC 6238): HMAC-SHA1, kunci = byte ASCII string
/// rahasia, counter = floor(serverTime/30) big-endian 64-bit, 6 digit.
String spotifyTotp(int serverTimeSeconds, {String secret = kSpotifyTotpSecret}) {
  final counter = serverTimeSeconds ~/ 30;
  final msg = ByteData(8)..setUint64(0, counter, Endian.big);
  final digest = Hmac(sha1, utf8.encode(secret)).convert(msg.buffer.asUint8List());
  final b = digest.bytes;
  final offset = b[b.length - 1] & 0x0f;
  final code = ((b[offset] & 0x7f) << 24) |
      ((b[offset + 1] & 0xff) << 16) |
      ((b[offset + 2] & 0xff) << 8) |
      (b[offset + 3] & 0xff);
  return (code % 1000000).toString().padLeft(6, '0');
}

/// Kenali tautan Spotify di teks bebas (bidang Cari / tempel).
/// Mengembalikan (kind, playlistId?) — kind: playlist|track|album|artist|
/// episode|show|other. Hanya playlist yang didukung Batch 1.
({String kind, String? playlistId})? spotifyLinkOf(String text) {
  final t = text.trim();
  final uriM = RegExp(r'^spotify:(playlist|track|album|artist|episode|show):([A-Za-z0-9]+)$').firstMatch(t);
  if (uriM != null) {
    final kind = uriM.group(1)!;
    return (kind: kind, playlistId: kind == 'playlist' ? uriM.group(2) : null);
  }
  if (!t.contains('spotify')) return null;
  final m = RegExp(r'open\.spotify\.com/(?:intl-[a-zA-Z-]+/)?(playlist|track|album|artist|episode|show)/([A-Za-z0-9]+)').firstMatch(t);
  if (m != null) {
    final kind = m.group(1)!;
    return (kind: kind, playlistId: kind == 'playlist' ? m.group(2) : null);
  }
  if (t.contains('open.spotify.com') || t.startsWith('spotify:')) return (kind: 'other', playlistId: null);
  return null;
}

String? spotifyPlaylistIdFromText(String text) => spotifyLinkOf(text)?.playlistId;

/// Kegagalan provider Spotify yang DAPAT dijelaskan ke pengguna (token ditolak,
/// hash dirotasi, playlist tidak publik, bentuk berubah). Dibedakan dari
/// kegagalan jaringan mentah agar UI jujur soal sebabnya.
class SpotifyProviderException implements Exception {
  final String message;
  SpotifyProviderException(this.message);
  @override
  String toString() => 'SpotifyProvider: $message';
}

/// Satu halaman/hasil playlist publik Spotify yang ternormalisasi.
class SpotifyPlaylistData {
  final String id;
  final String name;
  final String description;
  final String ownerName;
  final String? imageUrl;
  final int totalCount;
  final List<Track> tracks; // providerId 'spotify' — metadata saja, BUKAN sumber audio
  final int nonTrackItems; // item non-trek (episode dsb.) yang dilewati
  final bool truncated;
  const SpotifyPlaylistData({required this.id, required this.name, required this.description,
      required this.ownerName, this.imageUrl, required this.totalCount, required this.tracks,
      this.nonTrackItems = 0, this.truncated = false});
}

Map<String, dynamic>? _asMap(Object? v) => v is Map ? v.cast<String, dynamic>() : null;
List<dynamic> _asList(Object? v) => v is List ? v : const [];

String _lastSegment(String? uri) => (uri ?? '').split(':').last;

String? _widestSource(Object? sourcesNode, {int maxWidth = 640}) {
  String? best;
  String? firstUrl;
  var bestW = -1;
  for (final s in _asList(sourcesNode)) {
    final m = _asMap(s);
    if (m == null) continue;
    final url = m['url'] as String?;
    if (url == null) continue;
    firstUrl ??= url;
    final w = (m['width'] as num?)?.toInt() ?? 0;
    if (w <= maxWidth && w > bestW) { best = url; bestW = w; }
  }
  return best ?? firstUrl;
}

/// Urai satu respons fetchPlaylist (murni — diuji dengan fixture terbukti).
/// Melempar SpotifyProviderException berisi pesan sumber bila playlistV2
/// bukan "Playlist" (NotFound/GenericError dikirim Spotify sebagai HTTP 200!).
SpotifyPlaylistData parseFetchPlaylistPage(Map<String, dynamic> json) {
  final pv2 = _asMap(_asMap(json['data'])?['playlistV2']);
  if (pv2 == null) {
    throw SpotifyProviderException(l10n.spErrShapeV2);
  }
  final typename = pv2['__typename'] as String?;
  if (typename != 'Playlist') {
    final msg = pv2['message'] as String?;
    // NotFound = tidak ada ATAU tidak publik bagi akses anonim (Spotify
    // tidak membedakannya) — tampilkan pesan lokal yang jujur; pesan mentah
    // sumber tetap tercatat lewat log insiden di pemanggil.
    if (typename == 'NotFound') {
      throw SpotifyProviderException(
          'Playlist tidak ditemukan atau tidak publik. Akses tanpa akun hanya bisa membaca playlist publik.');
    }
    throw SpotifyProviderException(
        msg ?? 'Playlist tidak ditemukan atau tidak publik untuk akses anonim.');
  }
  final content = _asMap(pv2['content']);
  final owner = _asMap(_asMap(pv2['ownerV2'])?['data']);
  final images = _asList(_asMap(pv2['images'])?['items']);
  final tracks = <Track>[];
  var nonTrack = 0;
  for (final itemNode in _asList(content?['items'])) {
    final item = _asMap(itemNode);
    final data = _asMap(_asMap(item?['itemV2'])?['data']);
    if (data == null) { nonTrack++; continue; }
    if (data['__typename'] != 'Track') { nonTrack++; continue; }
    final uri = data['uri'] as String? ?? '';
    final id = _lastSegment(uri);
    if (id.isEmpty) { nonTrack++; continue; }
    final artists = <String>[];
    final artistIds = <String>[];
    for (final a in _asList(_asMap(data['artists'])?['items'])) {
      final am = _asMap(a);
      final name = _asMap(am?['profile'])?['name'] as String?;
      if (name != null && name.isNotEmpty) artists.add(name);
      final au = am?['uri'] as String?;
      if (au != null) artistIds.add(_lastSegment(au));
    }
    final album = _asMap(data['albumOfTrack']);
    final durMs = (_asMap(data['trackDuration'])?['totalMilliseconds'] as num?)?.toInt();
    tracks.add(Track(
      key: TrackKey('spotify', id),
      title: (data['name'] as String?) ?? '',
      artistNames: artists.join(', '),
      albumId: album == null ? null : _lastSegment(album['uri'] as String?),
      albumTitle: album?['name'] as String?,
      artistIds: artistIds,
      duration: durMs == null ? null : Duration(milliseconds: durMs),
      artworkUrl: _widestSource(_asMap(album?['coverArt'])?['sources']),
      isExplicit: _asMap(data['contentRating'])?['label'] == 'EXPLICIT',
      playableRef: id,
    ));
  }
  return SpotifyPlaylistData(
    id: _lastSegment(pv2['uri'] as String?),
    name: (pv2['name'] as String?) ?? '',
    description: (pv2['description'] as String?) ?? '',
    ownerName: (owner?['name'] as String?) ?? '',
    imageUrl: images.isEmpty ? null : _widestSource(_asMap(images.first)?['sources']),
    totalCount: (content?['totalCount'] as num?)?.toInt() ?? tracks.length,
    tracks: tracks,
    nonTrackItems: nonTrack,
  );
}
