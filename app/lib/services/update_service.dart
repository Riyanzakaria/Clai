import 'dart:io';
import '../l10n/l10n.dart';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../data/app_db.dart';
import 'observability.dart';
import 'sys_channel.dart';

/// Satu rilis dari umpan GitHub Releases (bentuk JSON resmi GitHub — umpan
/// simulasi lokal untuk pengujian meniru bentuk yang sama persis).
class ReleaseInfo {
  final String tag; // mis. 'v1.0.0+4'
  final String versionName; // '1.0.0'
  final int build; // 4 (dari sufiks '+4' tag; 0 bila tag tanpa nomor bangun)
  final String notes;
  final List<({String name, String url, int size})> assets;
  const ReleaseInfo({required this.tag, required this.versionName, required this.build,
      required this.notes, required this.assets});
}

/// Urai JSON /releases/latest GitHub. Mengembalikan null bila bentuknya tidak
/// dikenal (umpan berubah) — pemanggil menyatakannya sebagai "tidak ada rilis
/// yang bisa dibaca", bukan error jaringan.
ReleaseInfo? parseGithubReleaseJson(Map<String, dynamic> json) {
  final tag = json['tag_name'] as String?;
  if (tag == null || tag.isEmpty || json['draft'] == true) return null;
  final clean = tag.startsWith('v') ? tag.substring(1) : tag;
  var name = clean;
  var build = 0;
  final plus = clean.lastIndexOf('+');
  if (plus > 0) {
    build = int.tryParse(clean.substring(plus + 1)) ?? 0;
    name = clean.substring(0, plus);
  }
  final assets = <({String name, String url, int size})>[];
  final rawAssets = json['assets'];
  if (rawAssets is List) {
    for (final a in rawAssets) {
      if (a is Map) {
        final n = a['name'] as String?;
        final u = a['browser_download_url'] as String?;
        if (n != null && u != null) {
          assets.add((name: n, url: u, size: (a['size'] as num?)?.toInt() ?? 0));
        }
      }
    }
  }
  return ReleaseInfo(tag: tag, versionName: name, build: build,
      notes: (json['body'] as String?) ?? '', assets: assets);
}

/// Banding versi semantik sederhana 'a.b.c' (bagian non-angka diabaikan).
int compareVersionNames(String a, String b) {
  List<int> parts(String v) => v.split('.').map((s) => int.tryParse(s.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0).toList();
  final pa = parts(a), pb = parts(b);
  for (var i = 0; i < 3; i++) {
    final x = i < pa.length ? pa[i] : 0;
    final y = i < pb.length ? pb[i] : 0;
    if (x != y) return x.compareTo(y);
  }
  return 0;
}

/// Rilis dianggap BARU bila nomor bangunnya lebih tinggi; bila tag tanpa nomor
/// bangun (build 0 di kedua sisi), bandingkan nama versi.
bool isNewerRelease(ReleaseInfo r, {required String currentName, required int currentBuild}) {
  if (r.build > 0 || currentBuild > 0) return r.build > currentBuild;
  return compareVersionNames(r.versionName, currentName) > 0;
}

/// Pilih aset APK yang cocok dengan ABI perangkat (nama berkas split Flutter
/// memuat ABI-nya, mis. 'app-arm64-v8a-release.apk'). Jatuh ke APK pertama.
({String name, String url, int size})? pickReleaseAsset(ReleaseInfo r, List<String> abis) {
  final apks = r.assets.where((a) => a.name.toLowerCase().endsWith('.apk')).toList();
  if (apks.isEmpty) return null;
  for (final abi in abis) {
    for (final a in apks) {
      if (a.name.contains(abi)) return a;
    }
  }
  return apks.first;
}

enum UpdateStatus { unknown, checking, noReleases, upToDate, available, downloading, readyToInstall, installing, error }

/// Pembaruan Dalam Aplikasi (PETA-JALAN butir 6): cek GitHub Releases (tarik,
/// ±1×/hari, bisa dimatikan, tanpa data pengguna — hanya GET publik), unduh di
/// dalam aplikasi dengan progres, pasang lewat PackageInstaller sistem.
///
/// Batas platform dinyatakan apa adanya: pemasangan menampilkan konfirmasi
/// sistem Android; Clai tidak pernah memasang diam-diam.
class UpdateController extends ChangeNotifier {
  final AppDb db;
  final Dio _dio;
  UpdateController(this.db, {Dio? dio}) : _dio = dio ?? Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 8), receiveTimeout: const Duration(seconds: 30)));

  static const _defaultFeed = 'https://api.github.com/repos/Riyanzakaria/clai/releases/latest';
  static const _envFeed = String.fromEnvironment('UPDATE_FEED_URL');
  static const _throttle = Duration(hours: 20);

  UpdateStatus status = UpdateStatus.unknown;
  String message = '';
  ReleaseInfo? release;
  double progress = 0;
  String? downloadedPath;
  String currentLabel = '';

  bool autoCheck = true;
  bool autoDownload = false;
  bool wifiOnly = true;
  bool _busy = false;

  Future<void> loadPrefs() async {
    autoCheck = await db.pref<bool>('update.autoCheck') ?? true;
    autoDownload = await db.pref<bool>('update.autoDownload') ?? false;
    wifiOnly = await db.pref<bool>('update.wifiOnly') ?? true;
    final v = await SysChannel.appVersion();
    if (v != null) currentLabel = '${v.name} (bangun ${SysChannel.baseBuildOf(v.code)})';
    notifyListeners();
  }

  Future<void> setAutoCheck(bool v) async { autoCheck = v; await db.setPref('update.autoCheck', v); notifyListeners(); }
  Future<void> setAutoDownload(bool v) async { autoDownload = v; await db.setPref('update.autoDownload', v); notifyListeners(); }
  Future<void> setWifiOnly(bool v) async { wifiOnly = v; await db.setPref('update.wifiOnly', v); notifyListeners(); }

  Future<String> _feedUrl() async {
    final override = await db.pref<String>('update.feedUrl');
    if (override != null && override.isNotEmpty) return override;
    if (_envFeed.isNotEmpty) return _envFeed;
    return _defaultFeed;
  }

  /// Pemeriksaan otomatis (dipanggil saat aplikasi mulai): menghormati saklar
  /// & jeda ±1 hari. Kegagalan diam (offline dsb.) — pemeriksaan manual yang
  /// melaporkan hasilnya ke pengguna.
  Future<void> maybeAutoCheck() async {
    if (!autoCheck || _busy) return;
    final last = await db.pref<int>('update.lastCheckMs') ?? 0;
    if (DateTime.now().millisecondsSinceEpoch - last < _throttle.inMilliseconds) return;
    await check(manual: false);
  }

  Future<void> check({required bool manual}) async {
    if (_busy) return;
    _busy = true;
    status = UpdateStatus.checking;
    message = '';
    notifyListeners();
    try {
      final v = await SysChannel.appVersion();
      final url = await _feedUrl();
      final res = await _dio.get<Map<String, dynamic>>(url,
          options: Options(headers: {'Accept': 'application/vnd.github+json', 'User-Agent': 'Clai'},
              validateStatus: (s) => s != null && s < 500));
      await db.setPref('update.lastCheckMs', DateTime.now().millisecondsSinceEpoch);
      if (res.statusCode == 404) {
        // Keadaan NYATA saat ini: repo belum punya Release (menanti izin pemilik).
        status = UpdateStatus.noReleases;
        release = null;
        message = l10n.updNoReleases;
      } else if (res.statusCode == 200 && res.data != null) {
        final parsed = parseGithubReleaseJson(res.data!);
        if (parsed == null) {
          status = UpdateStatus.error;
          message = l10n.updBadShape;
        } else if (v == null) {
          status = UpdateStatus.error;
          message = l10n.updVersionUnreadable;
        } else if (isNewerRelease(parsed, currentName: v.name, currentBuild: SysChannel.baseBuildOf(v.code))) {
          status = UpdateStatus.available;
          release = parsed;
          message = l10n.updAvailableMsg(parsed.versionName);
          notifyListeners();
          if (autoDownload) await download(auto: true);
        } else {
          status = UpdateStatus.upToDate;
          release = null;
          message = l10n.updUpToDate;
        }
      } else {
        status = UpdateStatus.error;
        message = l10n.updCheckFailedHttp(res.statusCode ?? 0);
      }
    } catch (e) {
      status = UpdateStatus.error;
      message = l10n.updCheckFailed;
      if (manual) Observability.instance.log('update-cek-gagal', e.toString());
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> download({bool auto = false}) async {
    final r = release;
    if (r == null || status == UpdateStatus.downloading) return;
    final abis = await SysChannel.deviceAbis();
    final asset = pickReleaseAsset(r, abis);
    if (asset == null) {
      status = UpdateStatus.error;
      message = l10n.updNoApk(r.tag);
      notifyListeners();
      return;
    }
    if (auto && wifiOnly) {
      final net = await SysChannel.networkType();
      if (net != 'wifi' && net != 'ethernet') {
        // Unduhan otomatis ditunda sampai Wi-Fi — dinyatakan, bukan diam-diam.
        message = l10n.updWaitingWifi;
        notifyListeners();
        return;
      }
    }
    status = UpdateStatus.downloading;
    progress = 0;
    notifyListeners();
    try {
      final dir = Directory('${(await getTemporaryDirectory()).path}/clai-updates');
      await dir.create(recursive: true);
      final file = File('${dir.path}/${asset.name}');
      if (await file.exists() && asset.size > 0 && await file.length() == asset.size) {
        downloadedPath = file.path;
        status = UpdateStatus.readyToInstall;
        message = l10n.updAlreadyDownloaded;
        notifyListeners();
        return;
      }
      await _dio.download(asset.url, file.path, onReceiveProgress: (done, total) {
        final t = total > 0 ? total : asset.size;
        if (t > 0) { progress = (done / t).clamp(0, 1); notifyListeners(); }
      });
      downloadedPath = file.path;
      status = UpdateStatus.readyToInstall;
      message = l10n.updDownloadDone;
    } catch (e) {
      status = UpdateStatus.error;
      message = l10n.updDownloadFailed;
      Observability.instance.log('update-unduh-gagal', e.toString());
    }
    notifyListeners();
  }

  Future<void> install() async {
    final path = downloadedPath;
    if (path == null) return;
    status = UpdateStatus.installing;
    notifyListeners();
    try {
      await SysChannel.installApk(path);
      // Sistem menampilkan konfirmasi/pemasangan; sesudahnya status dibiarkan
      // "siap" — versi baru akan terbaca saat aplikasi dibuka lagi.
      status = UpdateStatus.readyToInstall;
      message = l10n.updFollowSystem;
    } catch (e) {
      // Berkas unduhan tetap utuh & valid — kegagalan ada di sisi izin/
      // sistem, jadi kembali ke "siap pasang" agar ubin Pasang tetap ada
      // dan pengguna bisa mencoba lagi (sesuai bunyi pesannya).
      status = UpdateStatus.readyToInstall;
      message = e.toString().contains('izin')
          ? l10n.updInstallPermMsg
          : l10n.updInstallFailed;
      Observability.instance.log('update-pasang-gagal', e.toString());
    }
    notifyListeners();
  }
}
