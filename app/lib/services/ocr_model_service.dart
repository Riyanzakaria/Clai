import 'dart:convert';
import '../l10n/l10n.dart';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../data/app_db.dart';
import 'observability.dart';
import 'update_service.dart';

/// Manifest model OCR yang diterbitkan sebagai aset GitHub Releases
/// (berkas `clai-ocr-model.json` menempel pada rilis, di samping APK).
/// Berkas modelnya sendiri (traineddata Tesseract) adalah aset terpisah —
/// APK TIDAK membawanya (keputusan riyan 24 Okt 2026, "cara ketiga").
class OcrModelManifest {
  final String lang; // kode bahasa Tesseract, mis. 'eng'
  final String file; // nama aset model di rilis, mis. 'eng.traineddata'
  final int size; // byte persis yang diharapkan
  final String sha256; // hex huruf kecil
  final String version; // label manusiawi, mis. 'tessdata_fast 4.1.0 (eng)'
  const OcrModelManifest(
      {required this.lang,
      required this.file,
      required this.size,
      required this.sha256,
      required this.version});
}

/// Urai manifest model OCR. Null bila bentuknya tidak dikenal — pemanggil
/// menyatakannya sebagai galat umpan, bukan mengarang nilai.
OcrModelManifest? parseOcrModelManifest(Map<String, dynamic> json) {
  final lang = json['lang'] as String?;
  final file = json['file'] as String?;
  final size = (json['size'] as num?)?.toInt();
  final sha = (json['sha256'] as String?)?.toLowerCase();
  if (lang == null || lang.isEmpty || file == null || file.isEmpty) return null;
  if (size == null || size <= 0) return null;
  if (sha == null || !RegExp(r'^[0-9a-f]{64}$').hasMatch(sha)) return null;
  return OcrModelManifest(
      lang: lang,
      file: file,
      size: size,
      sha256: sha,
      version: (json['version'] as String?) ?? file);
}

/// SHA-256 sebuah berkas, dibaca mengalir (berkas model ±4 MB; cara ini
/// tetap hemat memori untuk aset yang lebih besar kelak).
Future<String> sha256OfFile(File f) async {
  final digest = await f.openRead().transform(sha256).single;
  return digest.toString();
}

enum OcrModelStatus {
  unknown,
  notDownloaded,
  downloading,
  verifying,
  ready,

  /// Keadaan NETRAL pra-rilis (laporan perangkat pemilik atas 2006): umpan
  /// menjawab 404 (repo belum punya Release apa pun) atau rilis terbaru
  /// tidak membawa aset model. Ini BUKAN kegagalan — tidak ada yang rusak,
  /// unduhan hanya belum dibuka. Ditampilkan tenang tanpa warna galat.
  unavailable,
  error,
}

/// Klasifikasi jawaban umpan rilis (murni, diuji unit):
/// 200 = rilis terbaca; 404 = belum ada rilis yang diterbitkan (keadaan
/// normal pra-rilis); selainnya (5xx/4xx lain/transport) = kegagalan nyata.
enum FeedAvailability { available, notPublished, failed }

FeedAvailability classifyFeedStatus(int? statusCode) => switch (statusCode) {
      200 => FeedAvailability.available,
      404 => FeedAvailability.notPublished,
      _ => FeedAvailability.failed,
    };

/// Model OCR unduh-di-dalam-aplikasi untuk Tangkap-dari-gambar
/// (F2 Batch 2.1, cara ketiga). Alur: tawarkan → unduh sekali dari aset
/// GitHub Releases dengan progres → verifikasi checksum → tukar atomik
/// (.part → berkas final) → tersimpan di penyimpanan privat aplikasi →
/// bekerja offline penuh. Pengaturan menampilkan status + ukuran + hapus.
///
/// Umpan yang dipakai SAMA dengan pembaruan dalam aplikasi (pref
/// `update.feedUrl` boleh menimpanya — dipakai umpan simulasi saat uji).
class OcrModelController extends ChangeNotifier {
  final AppDb db;
  final Dio _dio;
  final Future<Directory> Function() _supportDir;
  final String? _feedOverride;

  OcrModelController(this.db,
      {Dio? dio,
      Future<Directory> Function()? supportDir,
      String? feedUrlOverride})
      : _dio = dio ??
            Dio(BaseOptions(
                connectTimeout: const Duration(seconds: 8),
                receiveTimeout: const Duration(seconds: 60))),
        _supportDir = supportDir ?? getApplicationSupportDirectory,
        _feedOverride = feedUrlOverride;

  static const manifestAssetName = 'clai-ocr-model.json';
  static const _defaultFeed =
      'https://api.github.com/repos/Riyanzakaria/clai/releases/latest';
  static const _envFeed = String.fromEnvironment('UPDATE_FEED_URL');

  OcrModelStatus status = OcrModelStatus.unknown;
  String message = '';
  double progress = 0;
  String? modelVersion;
  int installedSize = 0;
  String _modelLang = 'eng';
  bool _busy = false;

  /// Direktori datapath Tesseract: berisi `tessdata/<lang>.traineddata`.
  Directory? _baseDir;

  Future<Directory> baseDir() async =>
      _baseDir ??= Directory('${(await _supportDir()).path}/ocr-model');

  /// Jalur datapath untuk kanal OCR Kotlin; null sebelum [refresh] berjalan.
  String? get dataPath => _baseDir?.path;
  String get lang => _modelLang;

  File _finalFile(Directory base, String lang) =>
      File('${base.path}/tessdata/$lang.traineddata');
  File _partFile(Directory base, String lang) =>
      File('${base.path}/tessdata/$lang.traineddata.part');
  File _metaFile(Directory base) => File('${base.path}/meta.json');

  Future<String> _feedUrl() async {
    if (_feedOverride != null && _feedOverride.isNotEmpty) return _feedOverride;
    final override = await db.pref<String>('update.feedUrl');
    if (override != null && override.isNotEmpty) return override;
    if (_envFeed.isNotEmpty) return _envFeed;
    return _defaultFeed;
  }

  /// Segarkan status dari disk (murah; dipanggil saat aplikasi mulai dan
  /// saat lembar Tangkap/Pengaturan dibuka). Sisa berkas .part dari unduhan
  /// yang terputus dibersihkan — keadaan selalu bersih.
  Future<void> refresh() async {
    final base = await baseDir();
    try {
      final part = _partFile(base, _modelLang);
      if (await part.exists()) await part.delete();
    } catch (_) {}
    try {
      final metaFile = _metaFile(base);
      if (await metaFile.exists()) {
        final meta =
            jsonDecode(await metaFile.readAsString()) as Map<String, dynamic>;
        _modelLang = (meta['lang'] as String?) ?? 'eng';
        final f = _finalFile(base, _modelLang);
        final expected = (meta['size'] as num?)?.toInt() ?? -1;
        if (await f.exists() && await f.length() == expected) {
          status = OcrModelStatus.ready;
          modelVersion = meta['version'] as String?;
          installedSize = expected;
          message = l10n.ocrMsgInstalled;
          notifyListeners();
          return;
        }
        // Meta ada tapi berkas hilang/rusak sebagian → buang, nyatakan jujur.
        await _wipe(base);
      }
    } catch (_) {
      // Meta tak terbaca: perlakukan sebagai belum terpasang.
      try { await _wipe(base); } catch (_) {}
    }
    status = OcrModelStatus.notDownloaded;
    modelVersion = null;
    installedSize = 0;
    message = l10n.ocrMsgNotDownloaded;
    notifyListeners();
  }

  Future<void> _wipe(Directory base) async {
    if (await base.exists()) await base.delete(recursive: true);
  }

  Future<void> deleteModel() async {
    if (_busy) return;
    final base = await baseDir();
    await _wipe(base);
    status = OcrModelStatus.notDownloaded;
    modelVersion = null;
    installedSize = 0;
    progress = 0;
    message = l10n.ocrMsgDeleted;
    notifyListeners();
  }

  /// Unduh + verifikasi + pasang model. Kegagalan apa pun berakhir di
  /// status error dengan pesan jujur dan TANPA berkas setengah yang dimuat.
  Future<void> download() async {
    if (_busy || status == OcrModelStatus.ready) return;
    _busy = true;
    status = OcrModelStatus.downloading;
    progress = 0;
    message = l10n.ocrMsgContacting;
    notifyListeners();
    final base = await baseDir();
    File? part;
    try {
      final feedUrl = await _feedUrl();
      final rel = await _dio.get<Map<String, dynamic>>(feedUrl,
          options: Options(headers: {
            'Accept': 'application/vnd.github+json',
            'User-Agent': 'Clai'
          }, validateStatus: (s) => s != null && s < 500));
      // Klasifikasi keadaan umpan (Sapuan, butir pra-rilis): 404 = belum ada
      // rilis — keadaan NETRAL, bukan galat; 5xx/4xx lain = galat jujur.
      final availability = classifyFeedStatus(rel.statusCode);
      if (availability == FeedAvailability.notPublished) {
        status = OcrModelStatus.unavailable;
        message = l10n.ocrMsgNotPublished;
        return;
      }
      if (availability == FeedAvailability.failed || rel.data == null) {
        throw StateError(l10n.ocrErrFeed(rel.statusCode ?? 0));
      }
      final release = parseGithubReleaseJson(rel.data!);
      if (release == null) throw StateError(l10n.updBadShape);
      ({String name, String url, int size})? manifestAsset;
      for (final a in release.assets) {
        if (a.name == manifestAssetName) manifestAsset = a;
      }
      if (manifestAsset == null) {
        // Rilis ada tetapi belum membawa model: tetap netral pra-rilis.
        status = OcrModelStatus.unavailable;
        message = l10n.ocrMsgNoModelInRelease;
        return;
      }
      final man = await _dio.get<Map<String, dynamic>>(manifestAsset.url,
          options: Options(headers: {'User-Agent': 'Clai'}));
      if (man.data == null) throw StateError(l10n.ocrErrManifestEmpty);
      final manifest = parseOcrModelManifest(man.data!);
      if (manifest == null) throw StateError(l10n.ocrErrManifestUnknown);
      ({String name, String url, int size})? modelAsset;
      for (final a in release.assets) {
        if (a.name == manifest.file) modelAsset = a;
      }
      if (modelAsset == null) {
        // Manifest menjanjikan berkas yang tidak menempel di rilis:
        // dari sisi pengguna sama netralnya — model belum tersedia.
        status = OcrModelStatus.unavailable;
        message = l10n.ocrMsgNoModelInRelease;
        Observability.instance
            .log('ocr-model-aset-hilang', 'manifest menyebut ${manifest.file}, aset tidak ada di rilis');
        return;
      }
      _modelLang = manifest.lang;
      final tessDir = Directory('${base.path}/tessdata');
      await tessDir.create(recursive: true);
      part = _partFile(base, manifest.lang);
      if (await part.exists()) await part.delete();
      message = l10n.ocrMsgDownloading(manifest.version);
      notifyListeners();
      await _dio.download(modelAsset.url, part.path,
          onReceiveProgress: (done, total) {
        final t = total > 0 ? total : manifest.size;
        if (t > 0) {
          progress = (done / t).clamp(0, 1);
          notifyListeners();
        }
      });
      status = OcrModelStatus.verifying;
      message = l10n.ocrModelVerifying;
      notifyListeners();
      final partSize = await part.length();
      final digest = await sha256OfFile(part);
      if (partSize != manifest.size || digest != manifest.sha256) {
        await part.delete();
        part = null;
        status = OcrModelStatus.error;
        message = l10n.ocrMsgChecksumFail;
        Observability.instance.log('ocr-model-checksum-gagal',
            'size $partSize/${manifest.size} sha $digest/${manifest.sha256}');
        return;
      }
      // Tukar atomik: berkas .part yang sudah terverifikasi menjadi final.
      final fin = _finalFile(base, manifest.lang);
      if (await fin.exists()) await fin.delete();
      await part.rename(fin.path);
      part = null;
      await _metaFile(base).writeAsString(jsonEncode({
        'lang': manifest.lang,
        'file': manifest.file,
        'size': manifest.size,
        'sha256': manifest.sha256,
        'version': manifest.version,
        'downloadedAtMs': DateTime.now().millisecondsSinceEpoch,
      }));
      status = OcrModelStatus.ready;
      modelVersion = manifest.version;
      installedSize = manifest.size;
      progress = 1;
      message = l10n.ocrMsgInstalledReady;
    } catch (e) {
      try {
        if (part != null && await part.exists()) await part.delete();
      } catch (_) {}
      status = OcrModelStatus.error;
      message = e is StateError
          ? e.message
          : l10n.ocrMsgDownloadFailed;
      if (e is! StateError) {
        Observability.instance.log('ocr-model-unduh-gagal', e.toString());
      }
    } finally {
      _busy = false;
      notifyListeners();
    }
  }
}
