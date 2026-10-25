import 'dart:async';
import '../l10n/l10n.dart';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../data/app_db.dart';
import '../domain/models.dart';
import '../player/load_ladder.dart';
import '../providers/music_provider.dart';

/// Status unduhan. Serialisasi DB memakai kosakata Blueprint 2.x
/// (Sapuan D-14): queued | running | paused | done | error | corrupt.
enum DownloadStatus { queued, downloading, paused, done, failed, corrupt }

String downloadStatusToDb(DownloadStatus s) => switch (s) {
      DownloadStatus.queued => 'queued',
      DownloadStatus.downloading => 'running',
      DownloadStatus.paused => 'paused',
      DownloadStatus.done => 'done',
      DownloadStatus.failed => 'error',
      DownloadStatus.corrupt => 'corrupt',
    };

DownloadStatus downloadStatusFromDb(String s, {required bool fileExists}) =>
    switch (s) {
      'done' => fileExists ? DownloadStatus.done : DownloadStatus.failed,
      'paused' => DownloadStatus.paused,
      'corrupt' => DownloadStatus.corrupt,
      // Proses mati di tengah jalan: 'running'/'queued' persisten BUKAN
      // sedang berjalan — ia jeda yang bisa dilanjutkan dari berkas sebagian.
      'running' || 'downloading' || 'queued' => DownloadStatus.paused,
      _ => DownloadStatus.failed,
    };

/// Satu baris unduhan: status + progres + berkas lokal (bila selesai).
class DownloadItemState {
  final Track track;
  final DownloadStatus status;
  final int? bytesTotal;
  final int bytesDone;
  final String? localPath;
  final String quality;
  final String? error;
  const DownloadItemState({
    required this.track,
    required this.status,
    this.bytesTotal,
    this.bytesDone = 0,
    this.localPath,
    required this.quality,
    this.error,
  });

  DownloadItemState copyWith({
    DownloadStatus? status,
    int? bytesTotal,
    int? bytesDone,
    String? localPath,
    String? error,
  }) =>
      DownloadItemState(
        track: track,
        status: status ?? this.status,
        bytesTotal: bytesTotal ?? this.bytesTotal,
        bytesDone: bytesDone ?? this.bytesDone,
        localPath: localPath ?? this.localPath,
        quality: quality,
        error: error ?? this.error,
      );
}

/// Ekstensi berkas dari MIME aliran (dipakai pemutar untuk mengenali wadah).
String extensionForMime(String mime) {
  final m = mime.toLowerCase();
  if (m.contains('webm')) return 'webm';
  if (m.contains('mp4')) return 'm4a';
  if (m.contains('mpeg') || m.contains('mp3')) return 'mp3';
  if (m.contains('ogg') || m.contains('opus')) return 'opus';
  return 'm4a'; // cadangan: wadah MP4 adalah yang paling umum dari rantai ini
}

/// Nama berkas aman dari kunci trek (tanpa karakter jalur).
String downloadFileName(TrackKey k, String ext) {
  final safeId = k.id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
  return '${k.providerId}_$safeId.$ext';
}

/// Unduhan lagu untuk putar offline (F2 Batch 2; disapukan D-14 pra-1.0.0).
///
/// Antrean FIFO dengan maks 2 unduhan paralel; jeda per item & global
/// MEMELIHARA berkas sebagian dan unduhan dilanjutkan dari byte terakhir
/// (HTTP Range) — menutup keterbatasan tercatat T-04. Kuota penyimpanan
/// dapat diatur (0 = tanpa batas; pilihan UI 2/4/8 GB) dan pemakaian
/// terlihat. Sesudah selesai, checksum SHA-256 berkas dihitung & disimpan;
/// verifikasi ulang berjalan saat daftar dimuat — ketakcocokan menandai
/// item `corrupt` dan UI menawarkan unduh ulang. Ruang habis dilaporkan
/// sebagai pesan tersendiri, bukan "gagal" generik.
class DownloadService extends ChangeNotifier {
  final AppDb db;
  final MusicProvider provider;
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(minutes: 10),
  ));
  final Map<TrackKey, DownloadItemState> _items = {};
  final Map<TrackKey, CancelToken> _tokens = {};
  final List<TrackKey> _queue = [];
  final Set<TrackKey> _active = {};
  final Set<TrackKey> _pausing = {};
  DateTime _lastNotify = DateTime.fromMillisecondsSinceEpoch(0);

  static const maxParallel = 2;

  DownloadService(this.db, this.provider);

  List<DownloadItemState> get items {
    final list = _items.values.toList();
    list.sort((a, b) {
      int rank(DownloadItemState s) => switch (s.status) {
            DownloadStatus.downloading => 0,
            DownloadStatus.queued => 1,
            DownloadStatus.paused => 2,
            DownloadStatus.corrupt => 3,
            DownloadStatus.failed => 4,
            DownloadStatus.done => 5,
          };
      return rank(a).compareTo(rank(b));
    });
    return list;
  }

  DownloadItemState? itemFor(TrackKey k) => _items[k];

  bool isDownloaded(TrackKey k) =>
      _items[k]?.status == DownloadStatus.done && _items[k]?.localPath != null;

  /// Peta kunci → path untuk handler (sumber berkas lokal di LoadLadder).
  Map<TrackKey, String> get downloadedPaths {
    final out = <TrackKey, String>{};
    for (final e in _items.entries) {
      if (e.value.status == DownloadStatus.done && e.value.localPath != null) {
        out[e.key] = e.value.localPath!;
      }
    }
    return out;
  }

  /// Trek terunduh sebagai objek Track (bahan isi ulang offline).
  Future<List<Track>> downloadedTracks() async {
    final keys = downloadedPaths.keys.toList();
    return db.tracksByKeys(keys);
  }

  /// Total byte yang dipakai unduhan (selesai + sebagian).
  int get usedBytes => _items.values.fold(0, (a, s) => a + s.bytesDone);

  /// Kuota unduhan dalam byte (0 = tanpa batas) dari pref pengguna.
  Future<int> quotaBytes() async => await db.pref<int>('downloads.quotaBytes') ?? 0;

  Future<Directory> _dir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(base.path, 'downloads'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Muat status dari DB; berkas yang hilang dari disk ditandai gagal jujur
  /// (bukan dilaporkan selesai). Unduhan yang terputus proses mati menjadi
  /// `paused` (bisa dilanjutkan), bukan gagal.
  Future<void> load() async {
    final rows = await db.downloadItems();
    final keys = <TrackKey>[];
    for (final r in rows) {
      keys.add(TrackKey(r['provider_id'] as String, r['provider_track_id'] as String));
    }
    final tracks = await db.tracksByKeys(keys);
    final byKey = {for (final t in tracks) t.key: t};
    _items.clear();
    for (final r in rows) {
      final k = TrackKey(r['provider_id'] as String, r['provider_track_id'] as String);
      final t = byKey[k];
      if (t == null) continue; // metadata hilang: baris yatim dilewati
      final path = r['local_path'] as String?;
      final exists = path != null && await File(path).exists();
      final status = downloadStatusFromDb(r['status'] as String, fileExists: exists);
      _items[k] = DownloadItemState(
        track: t,
        status: status,
        bytesTotal: r['bytes_total'] as int?,
        bytesDone: (r['bytes_done'] as int?) ?? 0,
        localPath: path,
        quality: (r['quality'] as String?) ?? 'normal',
        error: status == DownloadStatus.failed && r['status'] == 'done'
            ? l10n.dlErrFileMissing
            : null,
      );
      if (status == DownloadStatus.failed && r['status'] == 'done' && !exists) {
        await db.saveDownloadItem(k,
            status: 'error', bytesDone: 0, quality: _items[k]!.quality);
      }
    }
    notifyListeners();
    // D-14: verifikasi checksum item selesai di latar (korup → ditandai).
    unawaited(verifyDownloads());
  }

  /// Verifikasi ulang checksum semua item `done`: berkas yang berubah di
  /// disk (korup) ditandai corrupt agar pengguna tahu & bisa unduh ulang —
  /// sebelumnya checksum dihitung & disimpan tetapi tidak pernah diverifikasi.
  Future<void> verifyDownloads() async {
    final rows = await db.downloadItems();
    for (final r in rows) {
      final k = TrackKey(r['provider_id'] as String, r['provider_track_id'] as String);
      final item = _items[k];
      if (item == null || item.status != DownloadStatus.done) continue;
      final stored = r['checksum'] as String?;
      final path = item.localPath;
      if (stored == null || path == null) continue;
      try {
        final actual = await _sha256(File(path));
        if (actual != stored) {
          _set(k, item.copyWith(status: DownloadStatus.corrupt, error: l10n.dlErrCorrupt));
          await db.saveDownloadItem(k,
              status: 'corrupt', bytesTotal: item.bytesTotal,
              bytesDone: item.bytesDone, localPath: path, checksum: stored,
              quality: item.quality);
        }
      } catch (_) {/* berkas tak terbaca ditangani jalur load berikutnya */}
    }
  }

  void _notifyThrottled() {
    final now = DateTime.now();
    if (now.difference(_lastNotify) < const Duration(milliseconds: 250)) return;
    _lastNotify = now;
    notifyListeners();
  }

  void _set(TrackKey k, DownloadItemState s) {
    _items[k] = s;
    notifyListeners();
  }

  /// Antrekan unduhan (atau lanjutkan yang terjeda). FIFO, maks
  /// [maxParallel] berjalan bersamaan.
  Future<void> download(Track track, StreamQuality quality) async {
    final k = track.key;
    if (isDownloaded(k)) return;
    if (_active.contains(k) || _queue.contains(k)) return;
    await db.cacheTracks([track]);
    final cur = _items[k];
    _set(k, DownloadItemState(
      track: track,
      status: DownloadStatus.queued,
      bytesTotal: cur?.bytesTotal,
      bytesDone: cur?.bytesDone ?? 0,
      localPath: cur?.localPath,
      quality: quality.name,
    ));
    await db.saveDownloadItem(k,
        status: 'queued', bytesTotal: cur?.bytesTotal,
        bytesDone: cur?.bytesDone ?? 0, localPath: cur?.localPath, quality: quality.name);
    _queue.add(k);
    _pump();
  }

  void _pump() {
    while (_active.length < maxParallel && _queue.isNotEmpty) {
      final k = _queue.removeAt(0);
      final item = _items[k];
      if (item == null || item.status != DownloadStatus.queued) continue;
      _active.add(k);
      unawaited(_run(k));
    }
  }

  /// Jeda satu item: unduhan berjalan dihentikan di byte saat ini (berkas
  /// sebagian DIPELIHARA); item antrean dicabut dari antrean.
  Future<void> pauseDownload(TrackKey k) async {
    final item = _items[k];
    if (item == null) return;
    if (item.status == DownloadStatus.queued) {
      _queue.remove(k);
      _set(k, item.copyWith(status: DownloadStatus.paused));
      await db.saveDownloadItem(k, status: 'paused',
          bytesTotal: item.bytesTotal, bytesDone: item.bytesDone,
          localPath: item.localPath, quality: item.quality);
    } else if (item.status == DownloadStatus.downloading) {
      _pausing.add(k);
      _tokens[k]?.cancel();
    }
  }

  /// Jeda SEMUA unduhan (berjalan + antrean).
  Future<void> pauseAll() async {
    for (final k in _items.keys.toList()) {
      final s = _items[k]?.status;
      if (s == DownloadStatus.downloading || s == DownloadStatus.queued) {
        await pauseDownload(k);
      }
    }
  }

  /// Lanjutkan semua item terjeda.
  Future<void> resumeAll() async {
    for (final e in _items.entries.toList()) {
      if (e.value.status == DownloadStatus.paused) {
        await download(e.value.track,
            StreamQuality.values.asNameMap()[e.value.quality] ?? StreamQuality.normal);
      }
    }
  }

  Future<void> _run(TrackKey k) async {
    final token = CancelToken();
    _tokens[k] = token;
    final item0 = _items[k]!;
    final quality =
        StreamQuality.values.asNameMap()[item0.quality] ?? StreamQuality.normal;
    try {
      // Kuota (D-14): item yang akan mulai diperiksa terhadap kuota —
      // penuh berarti pesan tersendiri, bukan kegagalan generik.
      final quota = await quotaBytes();
      if (quota > 0 && usedBytes - item0.bytesDone >= quota) {
        throw _QuotaFull();
      }
      final dir = await _dir();
      final candidates = <StreamInfo?>[];
      Object? lastError;
      try {
        candidates.add(await provider.resolveStream(item0.track, quality));
      } catch (e) {
        lastError = e;
      }
      try {
        candidates.add(await provider.resolveMuxedFallback(item0.track));
      } catch (_) {}
      String? donePath;
      int doneSize = 0;
      for (final info in candidates) {
        if (info == null) continue;
        final path = p.join(
            dir.path, downloadFileName(k, extensionForMime(info.mimeType)));
        final resumeFrom = await _partialSize(path, _items[k]?.bytesDone ?? 0);
        _set(k, _items[k]!.copyWith(
            status: DownloadStatus.downloading, bytesDone: resumeFrom, localPath: path));
        await db.saveDownloadItem(k, status: 'running',
            bytesDone: resumeFrom, localPath: path, quality: quality.name);
        try {
          doneSize = await _fetchToFile(info.url, path,
              resumeFrom: resumeFrom, token: token, key: k);
          donePath = path;
          break;
        } on DioException catch (e) {
          if (CancelToken.isCancel(e)) rethrow;
          lastError = e;
          // Range ditolak sumber (403/416): berkas sebagian tak berguna di
          // kandidat ini — buang, kandidat berikut mulai dari nol.
          if (resumeFrom > 0) {
            try { await File(path).delete(); } catch (_) {}
            _items[k] = _items[k]!.copyWith(bytesDone: 0);
          }
        }
      }
      if (donePath == null) {
        throw lastError ?? StateError('tidak ada sumber unduhan');
      }
      final file = File(donePath);
      final size = doneSize;
      final expected = _items[k]?.bytesTotal;
      if (expected != null && expected > 0 && size != expected) {
        // Ukuran akhir tak cocok dengan yang dijanjikan sumber: korup.
        _set(k, _items[k]!.copyWith(
            status: DownloadStatus.corrupt, bytesDone: size, error: l10n.dlErrCorrupt));
        await db.saveDownloadItem(k, status: 'corrupt', bytesTotal: expected,
            bytesDone: size, localPath: donePath, quality: quality.name);
        return;
      }
      final checksum = await _sha256(file);
      await db.saveDownloadItem(k,
          status: 'done', bytesTotal: size, bytesDone: size,
          localPath: donePath, checksum: checksum, quality: quality.name);
      _set(k, _items[k]!.copyWith(
          status: DownloadStatus.done, bytesTotal: size, bytesDone: size, localPath: donePath));
    } on _QuotaFull {
      await db.saveDownloadItem(k, status: 'error',
          bytesDone: _items[k]?.bytesDone ?? 0, quality: quality.name);
      _set(k, _items[k]!.copyWith(status: DownloadStatus.failed, error: l10n.dlErrQuotaFull));
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) {
        if (_pausing.contains(k)) {
          // Jeda: pelihara berkas sebagian + posisi byte-nya.
          final cur = _items[k]!;
          await db.saveDownloadItem(k, status: 'paused', bytesTotal: cur.bytesTotal,
              bytesDone: cur.bytesDone, localPath: cur.localPath, quality: quality.name);
          _set(k, cur.copyWith(status: DownloadStatus.paused));
        } else {
          // Batal penuh: berkas sebagian dibuang, baris dihapus.
          await deleteDownload(k, keepRow: false);
        }
        return;
      }
      await _failWith(k, quality, _shortError(e));
    } on FileSystemException catch (e) {
      final noSpace = e.osError?.errorCode == 28 ||
          e.message.toLowerCase().contains('no space');
      await _failWith(k, quality, noSpace ? l10n.dlErrStorageFull : e.message);
    } catch (e) {
      await _failWith(k, quality, e.toString());
    } finally {
      _tokens.remove(k);
      _pausing.remove(k);
      _active.remove(k);
      _pump();
    }
  }

  Future<void> _failWith(TrackKey k, StreamQuality quality, String message) async {
    await db.saveDownloadItem(k, status: 'error',
        bytesDone: _items[k]?.bytesDone ?? 0, quality: quality.name);
    final cur = _items[k];
    if (cur != null) _set(k, cur.copyWith(status: DownloadStatus.failed, error: message));
  }

  /// Ukuran berkas sebagian yang konsisten dengan catatan (untuk lanjut
  /// Range). 0 bila tidak ada/tidak konsisten — mulai dari nol lebih aman
  /// daripada menempel pada berkas yang tidak dikenal.
  Future<int> _partialSize(String path, int recordedBytes) async {
    if (recordedBytes <= 0) return 0;
    try {
      final f = File(path);
      if (await f.exists() && await f.length() == recordedBytes) return recordedBytes;
    } catch (_) {}
    return 0;
  }

  /// Unduh [url] ke [path] lewat aliran; lanjut dari [resumeFrom] bila >0
  /// (Range). Mengembalikan ukuran akhir berkas. Kemajuan ditulis ke state.
  Future<int> _fetchToFile(String url, String path,
      {required int resumeFrom, required CancelToken token, required TrackKey key}) async {
    final resp = await _dio.get<ResponseBody>(
      url,
      cancelToken: token,
      options: Options(
        responseType: ResponseType.stream,
        headers: {
          ...LoadLadder.streamHeaders,
          if (resumeFrom > 0) 'Range': 'bytes=$resumeFrom-',
        },
      ),
    );
    final status = resp.statusCode ?? 0;
    // Server mengabaikan Range (200): mulai dari nol, tulis ulang.
    final append = resumeFrom > 0 && status == 206;
    final startAt = append ? resumeFrom : 0;
    final contentLength = resp.headers.value('content-length');
    final total = contentLength == null
        ? null
        : (int.tryParse(contentLength) ?? 0) + startAt;
    final file = File(path);
    final raf = await file.open(mode: append ? FileMode.append : FileMode.write);
    var done = startAt;
    try {
      await for (final chunk in resp.data!.stream) {
        await raf.writeFrom(chunk);
        done += chunk.length;
        final cur = _items[key];
        if (cur != null) {
          _items[key] = cur.copyWith(bytesDone: done, bytesTotal: total ?? cur.bytesTotal);
          _notifyThrottled();
        }
      }
    } finally {
      await raf.close();
    }
    return done;
  }

  Future<String> _sha256(File file) async {
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString();
  }

  String _shortError(DioException e) => switch (e.type) {
        DioExceptionType.connectionTimeout || DioExceptionType.receiveTimeout => l10n.dlErrTimeout,
        DioExceptionType.connectionError => l10n.dlErrNoConnection,
        DioExceptionType.badResponse => l10n.dlErrSourceRefused(e.response?.statusCode ?? 0),
        _ => l10n.dlFailed,
      };

  /// Batalkan unduhan berjalan (berkas sebagian dibuang).
  Future<void> cancelDownload(TrackKey k) async {
    if (_items[k]?.status == DownloadStatus.queued) {
      _queue.remove(k);
      await deleteDownload(k, keepRow: false);
      return;
    }
    _tokens[k]?.cancel();
  }

  /// Hapus unduhan (berkas + baris DB).
  Future<void> deleteDownload(TrackKey k, {bool keepRow = false}) async {
    final cur = _items[k];
    final path = cur?.localPath;
    if (path != null) {
      try {
        await File(path).delete();
      } catch (_) {/* berkas sudah hilang: tetap lanjut */}
    }
    if (!keepRow) {
      await db.deleteDownloadItem(k);
      _items.remove(k);
    }
    notifyListeners();
  }
}

class _QuotaFull implements Exception {}

void unawaited(Future<void> f) {
  f.then((_) {}, onError: (_) {});
}
