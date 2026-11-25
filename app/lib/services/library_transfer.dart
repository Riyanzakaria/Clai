import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../data/app_db.dart';
import '../domain/models.dart';
import '../domain/transfer_data.dart';
import 'sys_channel.dart';

/// Mesin transfer kepemilikan (Ronde 8070, Workstream D2 — F-12):
/// ekspor/impor JSON berversi, ekspor M3U per playlist, dan codec QR
/// untuk mode Bagikan. Semua penguraian bersifat DEFENSIF dan selesai
/// sepenuhnya sebelum satu baris pun ditulis ke basis data — penerapan
/// atomik di [AppDb.applyLibraryImport] hanya menerima data yang sudah
/// tervalidasi utuh di sini.

/// Nilai field `format` berkas ekspor penuh.
const kExportFormat = 'clai-export';

/// Nilai field `format` berkas bagikan satu playlist.
const kPlaylistFormat = 'clai-playlist';

/// Versi skema transfer yang didukung bangun ini. Berkas dengan versi
/// format LEBIH BARU ditolak dengan penjelasan versi (F-12) — tidak ada
/// impor paksa.
const kTransferFormatVersion = 1;

/// Batas ukuran berkas impor yang diterima (20 MB) — ekspor riwayat
/// besar pun jauh di bawah ini; di atasnya berkas dianggap tidak wajar.
const kMaxImportBytes = 20 * 1024 * 1024;

/// Ambang muat payload QR, dalam karakter base64url. Kapasitas byte QR
/// koreksi-error M: versi 26 ≈ 1.057 byte, versi 30 ≈ 1.517 byte —
/// payload ≤ 1.000 karakter tetap di wilayah yang andal dipindai kamera
/// HP dari layar lain. Di atas ambang ini lembar Bagikan hanya
/// menawarkan berkas (isi lengkap, tanpa batas ukuran playlist).
/// Diukur pada data uji ronde: ±55–75 karakter per trek sesudah
/// kompresi zlib, jadi QR menampung kira-kira 13–18 trek tipikal.
const kQrMaxPayloadChars = 1000;

/// Versi payload QR mode PENUH (metadata per trek lengkap) — format
/// yang dihasilkan semua build ≤8077. Tidak berubah selamanya:
/// payload lama harus tetap terbaca (kompatibilitas mundur).
const kQrFullVersion = 1;

/// Versi payload QR mode RINGKAS (Ronde 8078): hanya nama playlist +
/// identitas katalog per trek `[provider, id]`; penerima membangun
/// ulang metadata tiap trek dari katalog sebelum impor. Build lama
/// (≤8077) yang memindai payload ini menolaknya lewat gerbang versi
/// sebagai "format lebih baru" (F-12) — jujur, bukan "korup".
const kQrRefsVersion = 2;

/// Versi payload QR tertinggi yang didukung bangun ini.
const kQrMaxSupportedVersion = kQrRefsVersion;

/// Provider trek lokal: berkas di perangkat pengguna sendiri, tidak
/// punya identitas katalog — tidak bisa ikut payload ringkas dan
/// tidak bisa dilarutkan penerima.
const kLocalProviderId = 'local';

// Batas kewajaran struktural berkas impor (anti berkas absurd/korup).
const _maxPlaylists = 2000;
const _maxTracksPerPlaylist = 20000;
const _maxLiked = 50000;
const _maxHistory = 500000;
const _maxSavedItems = 10000;

/// Jenis kegagalan penguraian berkas transfer.
enum TransferFailureKind {
  /// Teks bukan JSON sama sekali.
  notJson,

  /// JSON valid tetapi bukan berkas Clai (format tak dikenal).
  unrecognized,

  /// Berkas dari versi format yang lebih baru daripada yang didukung
  /// aplikasi ini (F-12: ditolak dengan penjelasan versi).
  newerVersion,

  /// Berkas Clai tetapi strukturnya rusak/tidak lengkap.
  corrupt,

  /// Berkas melebihi batas ukuran impor (dihasilkan gerbang pemilih
  /// berkas, bukan pengurai).
  tooLarge,
}

/// Hasil penguraian teks transfer: persis satu dari tiga bentuk ini.
sealed class TransferParseResult {
  const TransferParseResult();
}

/// Berkas ekspor penuh yang valid.
class ParsedLibrary extends TransferParseResult {
  final LibraryTransferData data;
  const ParsedLibrary(this.data);
}

/// Berkas/payload bagikan satu playlist yang valid.
class ParsedSharedPlaylist extends TransferParseResult {
  final SharedPlaylistData data;
  const ParsedSharedPlaylist(this.data);
}

/// Payload QR mode ringkas yang sah (Ronde 8078): nama + identitas
/// katalog per trek. Metadata SENGAJA belum ada di sini — penerima
/// melarutkan tiap identitas menjadi trek katalog (lihat
/// [resolveSharedRefs]) sebelum apa pun ditulis ke basis data.
class ParsedSharedRefs extends TransferParseResult {
  final String name;
  final List<TrackKey> refs;
  const ParsedSharedRefs({required this.name, required this.refs});
}

/// Penguraian gagal — [kind] menentukan teks penjelasan di lembar
/// Impor Gagal; tidak ada data yang diterapkan dalam keadaan ini.
class TransferParseFailure extends TransferParseResult {
  final TransferFailureKind kind;

  /// Versi format yang ditemukan (untuk [TransferFailureKind.newerVersion]).
  final int? foundVersion;

  /// Rincian teknis singkat (jalur field) untuk kegagalan korup.
  final String? detail;
  const TransferParseFailure(this.kind, {this.foundVersion, this.detail});
}

// ---------------------------------------------------------------------------
// Penyusunan JSON ekspor
// ---------------------------------------------------------------------------

Map<String, Object?> _trackJson(TransferTrack t) => t.toJson();

Map<String, Object?> exportToJson(LibraryTransferData d) => {
      'format': kExportFormat,
      'formatVersion': d.formatVersion,
      if (d.appVersion != null) 'appVersion': d.appVersion,
      if (d.exportedAt != null) 'exportedAt': d.exportedAt,
      'playlists': [
        for (final p in d.playlists)
          {
            'name': p.name,
            if (p.description != null) 'description': p.description,
            if (p.createdAt != null) 'createdAt': p.createdAt,
            'tracks': [for (final t in p.tracks) _trackJson(t)],
          },
      ],
      'liked': [
        for (final l in d.liked)
          {'track': _trackJson(l.track), 'likedAt': l.likedAt},
      ],
      if (d.history != null)
        'history': [
          for (final e in d.history!)
            {
              'track': _trackJson(e.track),
              'startedAt': e.startedAt,
              'listenedMs': e.listenedMs,
              'completed': e.completed,
              if (e.contextKind != null) 'contextKind': e.contextKind,
              if (e.contextId != null) 'contextId': e.contextId,
            },
        ],
      'savedItems': [
        for (final s in d.savedItems)
          {
            'kind': s.kind,
            'providerId': s.providerId,
            'itemId': s.itemId,
            'title': s.title,
            if (s.subtitle != null) 'subtitle': s.subtitle,
            if (s.artworkUrl != null) 'artworkUrl': s.artworkUrl,
            'savedAt': s.savedAt,
          },
      ],
    };

/// JSON berkas bagikan satu playlist (isi LENGKAP — pasangan berkas
/// dari payload QR yang ringkas).
Map<String, Object?> sharedPlaylistToJson(SharedPlaylistData d) => {
      'format': kPlaylistFormat,
      'formatVersion': d.formatVersion,
      'name': d.name,
      'tracks': [for (final t in d.tracks) _trackJson(t)],
    };

// ---------------------------------------------------------------------------
// Penguraian defensif
// ---------------------------------------------------------------------------

/// Urai byte berkas transfer: gerbang ukuran dulu, lalu dekode UTF-8
/// toleran (byte rusak → JSON tidak valid → kegagalan notJson).
TransferParseResult parseTransferBytes(List<int> bytes) {
  if (bytes.length > kMaxImportBytes) {
    return const TransferParseFailure(TransferFailureKind.tooLarge);
  }
  return parseTransferText(utf8.decode(bytes, allowMalformed: true));
}

/// Urai teks berkas transfer (ekspor penuh ATAU bagikan playlist).
/// Tidak pernah melempar — semua kegagalan menjadi [TransferParseFailure].
TransferParseResult parseTransferText(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) {
    return const TransferParseFailure(TransferFailureKind.notJson);
  }
  Object? root;
  try {
    root = jsonDecode(trimmed);
  } catch (_) {
    return const TransferParseFailure(TransferFailureKind.notJson);
  }
  if (root is! Map<String, dynamic>) {
    return const TransferParseFailure(TransferFailureKind.unrecognized);
  }
  final format = root['format'];
  if (format != kExportFormat && format != kPlaylistFormat) {
    return const TransferParseFailure(TransferFailureKind.unrecognized);
  }
  final versionRaw = root['formatVersion'];
  if (versionRaw is! num) {
    return const TransferParseFailure(TransferFailureKind.corrupt,
        detail: 'formatVersion hilang/bukan angka');
  }
  final version = versionRaw.toInt();
  if (version > kTransferFormatVersion) {
    return TransferParseFailure(TransferFailureKind.newerVersion,
        foundVersion: version);
  }
  if (version < 1) {
    return const TransferParseFailure(TransferFailureKind.corrupt,
        detail: 'formatVersion < 1');
  }
  try {
    if (format == kPlaylistFormat) {
      return ParsedSharedPlaylist(_parseSharedPlaylist(root, version));
    }
    return ParsedLibrary(_parseLibrary(root, version));
  } on FormatException catch (e) {
    return TransferParseFailure(TransferFailureKind.corrupt,
        detail: e.message);
  }
}

Map<String, dynamic> _asMap(Object? v, String path) {
  if (v is! Map<String, dynamic>) {
    throw FormatException('$path: harus objek');
  }
  return v;
}

List<dynamic> _asList(Object? v, String path, int max) {
  if (v == null) return const [];
  if (v is! List) throw FormatException('$path: harus daftar');
  if (v.length > max) {
    throw FormatException('$path: melebihi batas $max entri');
  }
  return v;
}

List<TransferTrack> _parseTracks(Object? v, String path) {
  final list = _asList(v, path, _maxTracksPerPlaylist);
  return [
    for (var i = 0; i < list.length; i++)
      TransferTrack.fromJson(_asMap(list[i], '$path[$i]'), '$path[$i]'),
  ];
}

SharedPlaylistData _parseSharedPlaylist(
    Map<String, dynamic> root, int version) {
  final name = root['name'];
  if (name is! String || name.isEmpty || name.length > 500) {
    throw const FormatException('name: wajib string 1–500 karakter');
  }
  return SharedPlaylistData(
    formatVersion: version,
    name: name,
    tracks: _parseTracks(root['tracks'], 'tracks'),
  );
}

LibraryTransferData _parseLibrary(Map<String, dynamic> root, int version) {
  final playlists = <TransferPlaylist>[];
  final plList = _asList(root['playlists'], 'playlists', _maxPlaylists);
  for (var i = 0; i < plList.length; i++) {
    final p = _asMap(plList[i], 'playlists[$i]');
    final name = p['name'];
    if (name is! String || name.isEmpty || name.length > 500) {
      throw FormatException('playlists[$i].name: wajib string 1–500');
    }
    final desc = p['description'];
    if (desc != null && desc is! String) {
      throw FormatException('playlists[$i].description: harus string');
    }
    final created = p['createdAt'];
    if (created != null && created is! num) {
      throw FormatException('playlists[$i].createdAt: harus angka');
    }
    playlists.add(TransferPlaylist(
      name: name,
      description: desc,
      createdAt: created?.toInt(),
      tracks: _parseTracks(p['tracks'], 'playlists[$i].tracks'),
    ));
  }

  final liked = <TransferLike>[];
  final likeList = _asList(root['liked'], 'liked', _maxLiked);
  for (var i = 0; i < likeList.length; i++) {
    final l = _asMap(likeList[i], 'liked[$i]');
    final at = l['likedAt'];
    if (at is! num) {
      throw FormatException('liked[$i].likedAt: harus angka');
    }
    liked.add(TransferLike(
      track: TransferTrack.fromJson(
          _asMap(l['track'], 'liked[$i].track'), 'liked[$i].track'),
      likedAt: at.toInt(),
    ));
  }

  List<TransferEvent>? history;
  if (root.containsKey('history')) {
    history = <TransferEvent>[];
    final hList = _asList(root['history'], 'history', _maxHistory);
    for (var i = 0; i < hList.length; i++) {
      final e = _asMap(hList[i], 'history[$i]');
      final started = e['startedAt'];
      final listened = e['listenedMs'];
      final completed = e['completed'];
      if (started is! num || listened is! num || completed is! bool) {
        throw FormatException(
            'history[$i]: startedAt/listenedMs angka, completed boolean');
      }
      final ck = e['contextKind'];
      final ci = e['contextId'];
      if ((ck != null && ck is! String) || (ci != null && ci is! String)) {
        throw FormatException('history[$i].context*: harus string');
      }
      history.add(TransferEvent(
        track: TransferTrack.fromJson(
            _asMap(e['track'], 'history[$i].track'), 'history[$i].track'),
        startedAt: started.toInt(),
        listenedMs: listened.toInt(),
        completed: completed,
        contextKind: ck,
        contextId: ci,
      ));
    }
  }

  final saved = <TransferSavedItem>[];
  final sList = _asList(root['savedItems'], 'savedItems', _maxSavedItems);
  for (var i = 0; i < sList.length; i++) {
    final s = _asMap(sList[i], 'savedItems[$i]');
    String reqS(String k) {
      final v = s[k];
      if (v is! String || v.isEmpty) {
        throw FormatException('savedItems[$i].$k: wajib string');
      }
      return v;
    }

    final at = s['savedAt'];
    if (at is! num) {
      throw FormatException('savedItems[$i].savedAt: harus angka');
    }
    final sub = s['subtitle'];
    final art = s['artworkUrl'];
    if ((sub != null && sub is! String) || (art != null && art is! String)) {
      throw FormatException('savedItems[$i]: subtitle/artworkUrl string');
    }
    saved.add(TransferSavedItem(
      kind: reqS('kind'),
      providerId: reqS('providerId'),
      itemId: reqS('itemId'),
      title: reqS('title'),
      subtitle: sub,
      artworkUrl: art,
      savedAt: at.toInt(),
    ));
  }

  final appVersion = root['appVersion'];
  final exportedAt = root['exportedAt'];
  return LibraryTransferData(
    formatVersion: version,
    appVersion: appVersion is String ? appVersion : null,
    exportedAt: exportedAt is num ? exportedAt.toInt() : null,
    playlists: playlists,
    liked: liked,
    history: history,
    savedItems: saved,
  );
}

// ---------------------------------------------------------------------------
// Codec QR (mode Bagikan)
// ---------------------------------------------------------------------------

/// Susun payload QR ringkas untuk satu playlist: JSON posisi
/// `[provider, id, judul, artis, durasiMs, ref]` per trek (ref kosong =
/// sama dengan id — keadaan mayoritas trek katalog), lalu zlib →
/// base64url tanpa padding. Bidang sampul/album/eksplisit SENGAJA tidak
/// ikut kendaraan QR (ukuran); berkas bagikan memuat isi lengkap.
String encodeQrPayload(SharedPlaylistData d) {
  final compact = {
    'v': d.formatVersion,
    'n': d.name,
    't': [
      for (final t in d.tracks)
        [
          t.providerId,
          t.trackId,
          t.title,
          t.artistNames,
          t.durationMs,
          t.playableRef == t.trackId ? '' : t.playableRef,
        ],
    ],
  };
  final bytes = ZLibCodec().encode(utf8.encode(jsonEncode(compact)));
  return base64Url.encode(bytes).replaceAll('=', '');
}

/// Apakah [payload] masih dalam ambang andal-pindai (lihat
/// [kQrMaxPayloadChars]).
bool qrPayloadFits(String payload) => payload.length <= kQrMaxPayloadChars;

/// Susun payload QR mode RINGKAS (Ronde 8078): amplop yang sama
/// (JSON → zlib → base64url) tetapi isinya hanya nama + identitas
/// katalog per trek `[provider, id]` — tanpa judul/artis/durasi.
/// ±13–20 karakter per trek sesudah kompresi, jadi satu QR menampung
/// kira-kira 50–80 trek; penerima membangun ulang metadatanya dari
/// katalog (lihat [resolveSharedRefs]).
String encodeQrRefsPayload(String name, List<TrackKey> refs) {
  final compact = {
    'v': kQrRefsVersion,
    'n': name,
    't': [
      for (final r in refs) [r.providerId, r.id],
    ],
  };
  final bytes = ZLibCodec().encode(utf8.encode(jsonEncode(compact)));
  return base64Url.encode(bytes).replaceAll('=', '');
}

/// Rencana kendaraan QR untuk satu playlist (keputusan mode MURNI —
/// lembar Bagikan hanya menampilkannya).
sealed class QrSharePlan {
  const QrSharePlan();
}

/// Mode penuh muat: QR membawa metadata lengkap, persis perilaku
/// build ≤8077.
class QrShareFull extends QrSharePlan {
  final String payload;
  const QrShareFull(this.payload);
}

/// Mode penuh tidak muat tetapi mode ringkas muat: QR membawa
/// referensi katalog untuk [trackCount] trek; [localExcluded] trek
/// lokal tidak ikut (dinyatakan jujur di lembar pengirim).
class QrShareRefs extends QrSharePlan {
  final String payload;
  final int trackCount;
  final int localExcluded;
  const QrShareRefs(this.payload,
      {required this.trackCount, required this.localExcluded});
}

/// Bahkan mode ringkas tidak muat (atau tidak ada satu pun trek
/// katalog): hanya berkas yang ditawarkan, seperti perilaku lama.
class QrShareTooBig extends QrSharePlan {
  final int localExcluded;
  const QrShareTooBig({required this.localExcluded});
}

/// Tentukan mode Bagikan-QR untuk [d]: penuh bila muat; bila tidak,
/// ringkas atas trek berkatalog saja bila itu muat; selain itu
/// terlalu besar. Trek lokal tidak pernah membatalkan mode penuh —
/// mereka hanya terkecuali dari mode ringkas.
QrSharePlan planQrShare(SharedPlaylistData d) {
  final full = encodeQrPayload(d);
  if (qrPayloadFits(full)) return QrShareFull(full);
  final refs = [
    for (final t in d.tracks)
      if (t.providerId != kLocalProviderId) t.key,
  ];
  final localExcluded = d.tracks.length - refs.length;
  if (refs.isEmpty) return QrShareTooBig(localExcluded: localExcluded);
  final compact = encodeQrRefsPayload(d.name, refs);
  if (!qrPayloadFits(compact)) {
    return QrShareTooBig(localExcluded: localExcluded);
  }
  return QrShareRefs(compact,
      trackCount: refs.length, localExcluded: localExcluded);
}

/// Hasil pelarutan payload ringkas: playlist berisi trek yang
/// berhasil dibangun ulang (URUTAN payload dipertahankan) + hitungan
/// identitas yang tidak terlarutkan (dilewati, dilaporkan jujur —
/// mereka tidak bisa dinamai karena judulnya memang tidak dibawa).
class RefsResolution {
  final SharedPlaylistData data;
  final int unresolvedCount;
  const RefsResolution({required this.data, required this.unresolvedCount});

  int get resolvedCount => data.tracks.length;
}

/// Larutkan identitas katalog payload ringkas menjadi trek utuh lewat
/// [lookup] (cache katalog lokal → provider; disediakan pemanggil).
/// Tidak pernah melempar: kegagalan per identitas (terhapus, privat,
/// terblokir wilayah, jaringan mati) menjadi hitungan tak-terlarut.
/// Konkurensi dibatasi agar katalog tidak dibanjiri; progres
/// dilaporkan lewat [onProgress] (selesai, total).
Future<RefsResolution> resolveSharedRefs({
  required String name,
  required List<TrackKey> refs,
  required Future<Track?> Function(TrackKey key) lookup,
  void Function(int done, int total)? onProgress,
  int concurrency = 6,
}) async {
  final found = List<Track?>.filled(refs.length, null);
  var next = 0;
  var done = 0;
  Future<void> worker() async {
    while (true) {
      final i = next++;
      if (i >= refs.length) return;
      Track? t;
      try {
        t = await lookup(refs[i]);
      } catch (_) {
        t = null;
      }
      found[i] = t;
      done++;
      onProgress?.call(done, refs.length);
    }
  }

  final workers =
      concurrency < 1 ? 1 : (concurrency > refs.length && refs.isNotEmpty ? refs.length : concurrency);
  await Future.wait([for (var w = 0; w < workers; w++) worker()]);
  final tracks = <TransferTrack>[];
  var unresolved = 0;
  for (final t in found) {
    if (t == null) {
      unresolved++;
    } else {
      tracks.add(TransferTrack.fromTrack(t));
    }
  }
  return RefsResolution(
    data: SharedPlaylistData(
      formatVersion: kTransferFormatVersion,
      name: name,
      tracks: tracks,
    ),
    unresolvedCount: unresolved,
  );
}

/// Urai payload QR (atau, demi ketahanan, JSON bagikan polos yang
/// diawali `{`). Hasilnya keluarga yang sama dengan [parseTransferText].
TransferParseResult decodeQrPayload(String raw) {
  final text = raw.trim();
  if (text.startsWith('{')) return parseTransferText(text);
  Object? root;
  try {
    var b64 = text.replaceAll(RegExp(r'\s'), '');
    while (b64.length % 4 != 0) {
      b64 += '=';
    }
    final decoded = ZLibCodec().decode(base64Url.decode(b64));
    root = jsonDecode(utf8.decode(decoded));
  } catch (_) {
    return const TransferParseFailure(TransferFailureKind.unrecognized);
  }
  if (root is! Map<String, dynamic>) {
    return const TransferParseFailure(TransferFailureKind.unrecognized);
  }
  final v = root['v'];
  if (v is! num) {
    return const TransferParseFailure(TransferFailureKind.corrupt,
        detail: 'payload QR: v hilang');
  }
  if (v.toInt() > kQrMaxSupportedVersion) {
    return TransferParseFailure(TransferFailureKind.newerVersion,
        foundVersion: v.toInt());
  }
  try {
    final name = root['n'];
    if (name is! String || name.isEmpty || name.length > 500) {
      throw const FormatException('payload QR: n tidak sah');
    }
    final list = root['t'];
    if (list is! List || list.length > _maxTracksPerPlaylist) {
      throw const FormatException('payload QR: t tidak sah');
    }
    if (v.toInt() == kQrRefsVersion) {
      // Mode ringkas (Ronde 8078): entri hanya [provider, id].
      final refs = <TrackKey>[];
      for (var i = 0; i < list.length; i++) {
        final e = list[i];
        if (e is! List || e.length < 2) {
          throw FormatException('payload QR: ref[$i] tidak sah');
        }
        final provider = e[0], id = e[1];
        if (provider is! String ||
            id is! String ||
            provider.isEmpty ||
            id.isEmpty) {
          throw FormatException('payload QR: ref[$i] tipe salah');
        }
        refs.add(TrackKey(provider, id));
      }
      return ParsedSharedRefs(name: name, refs: refs);
    }
    if (v.toInt() != kQrFullVersion) {
      throw const FormatException('payload QR: v tidak dikenal');
    }
    final tracks = <TransferTrack>[];
    for (var i = 0; i < list.length; i++) {
      final e = list[i];
      if (e is! List || e.length < 5) {
        throw FormatException('payload QR: trek[$i] tidak sah');
      }
      final provider = e[0], id = e[1], title = e[2], artist = e[3];
      final dur = e[4];
      final ref = e.length > 5 ? e[5] : null;
      if (provider is! String ||
          id is! String ||
          title is! String ||
          artist is! String ||
          (dur != null && dur is! num) ||
          (ref != null && ref is! String)) {
        throw FormatException('payload QR: trek[$i] tipe salah');
      }
      if (provider.isEmpty || id.isEmpty || title.isEmpty) {
        throw FormatException('payload QR: trek[$i] kosong');
      }
      tracks.add(TransferTrack(
        providerId: provider,
        trackId: id,
        title: title,
        artistNames: artist,
        durationMs: dur?.toInt(),
        playableRef: (ref == null || ref.isEmpty) ? id : ref,
      ));
    }
    return ParsedSharedPlaylist(SharedPlaylistData(
      formatVersion: v.toInt(),
      name: name,
      tracks: tracks,
    ));
  } on FormatException catch (e) {
    return TransferParseFailure(TransferFailureKind.corrupt,
        detail: e.message);
  }
}

// ---------------------------------------------------------------------------
// M3U
// ---------------------------------------------------------------------------

/// Susun berkas M3U satu playlist: `#EXTINF` (artis — judul, durasi
/// detik; -1 bila tak diketahui) + baris ref putar per trek.
String buildM3u(List<TransferTrack> tracks) {
  String clean(String s) => s.replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
  final b = StringBuffer('#EXTM3U\n');
  for (final t in tracks) {
    final secs =
        t.durationMs == null ? -1 : (t.durationMs! / 1000).round();
    b.writeln('#EXTINF:$secs,${clean(t.artistNames)} - ${clean(t.title)}');
    b.writeln(t.playableRef);
  }
  return b.toString();
}

// ---------------------------------------------------------------------------
// Layanan (pengumpul data + penulis berkas)
// ---------------------------------------------------------------------------

/// Nama berkas ekspor untuk tanggal [t]: `clai-ekspor-YYYYMMDD.json`.
String exportFileName(DateTime t) {
  String two(int n) => n.toString().padLeft(2, '0');
  return 'clai-ekspor-${t.year}${two(t.month)}${two(t.day)}.json';
}

/// Nama berkas bagikan/M3U yang aman untuk satu playlist.
String playlistFileSlug(String name) {
  final slug = name
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  return slug.isEmpty ? 'playlist' : slug;
}

class LibraryTransferService {
  final AppDb db;
  const LibraryTransferService(this.db);

  /// Kumpulkan seluruh isi ekspor dari basis data. [includeHistory]
  /// adalah pilihan pengguna di lembar Ekspor (F-12: riwayat opsional).
  Future<LibraryTransferData> gatherExport({
    required bool includeHistory,
  }) async {
    final v = await SysChannel.appVersion();
    return LibraryTransferData(
      formatVersion: kTransferFormatVersion,
      appVersion: v?.name,
      exportedAt: DateTime.now().millisecondsSinceEpoch,
      playlists: await db.exportPlaylistsData(),
      liked: await db.exportLikedData(),
      history: includeHistory ? await db.exportHistoryData() : null,
      savedItems: await db.exportSavedItemsData(),
    );
  }

  /// Data transfer satu playlist pengguna menurut id-nya (untuk
  /// Bagikan & M3U); null bila playlist tidak ada.
  Future<TransferPlaylist?> playlistData(String playlistId) async {
    final rows = await db.playlists();
    Map<String, Object?>? row;
    for (final r in rows) {
      if (r['id'] == playlistId) row = r;
    }
    if (row == null) return null;
    final tracks = await db.playlistTracks(playlistId);
    return TransferPlaylist(
      name: row['name'] as String,
      description: row['description'] as String?,
      createdAt: row['created_at'] as int?,
      tracks: [for (final t in tracks) TransferTrack.fromTrack(t)],
    );
  }

  /// Tulis [content] ke berkas temporer yang bisa dibagikan lewat
  /// share sheet sistem; mengembalikan berkasnya.
  Future<File> writeShareFile(String fileName, String content) async {
    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}/$fileName');
    await f.writeAsString(content);
    return f;
  }

  /// Varian biner dari [writeShareFile] (Ronde 8071: gambar kartu QR).
  Future<File> writeShareBytes(String fileName, List<int> bytes) async {
    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}/$fileName');
    await f.writeAsBytes(bytes, flush: true);
    return f;
  }
}
