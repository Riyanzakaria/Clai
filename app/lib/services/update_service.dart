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

/// Ekstrak blok pengguna dari badan rilis (Ronde 8069): poin-poin di bawah
/// judul `## Yang baru` SAJA — aturan terkunci pemilik 2026-11-21, aplikasi
/// tidak pernah menampilkan lapis teknis catatan rilis. Pengumpulan
/// berhenti di pemisah `---`, di blok `<details>`, atau di judul `## `
/// berikutnya, mana pun yang lebih dulu. Badan tanpa blok itu (rilis
/// warisan pra-format-dua-lapis) atau blok tanpa satu pun poin → daftar
/// kosong, dan pemanggil menyembunyikan semua pintu masuk "Yang baru".
/// Murni: tanpa keadaan, tanpa I/O.
List<String> userFacingNotes(String body) {
  final out = <String>[];
  var inBlock = false;
  for (final raw in body.split('\n')) {
    final line = raw.trim(); // trim sekaligus membuang \r sisa CRLF
    if (!inBlock) {
      if (line.toLowerCase() == '## yang baru') inBlock = true;
      continue;
    }
    if (line == '---' || line.startsWith('<details') || line.startsWith('## ')) {
      break;
    }
    if (line.startsWith('- ')) {
      final item = line.substring(2).trim();
      if (item.isNotEmpty) out.add(item);
    }
  }
  return out;
}

/// Tingkat pengumuman sesudah pasang (Ronde 8079, spec
/// `desain-f3/pisah-pengaturan/BANNER-UPDATE.md`): rilis FITUR (major/
/// minor berubah) → overlay B1 sekali per versi; rilis tambalan (patch/
/// bangun saja) → spanduk konfirmasi B2 sekali; sama/turun → tidak ada.
enum AnnouncementTier { none, feature, patch }

/// Klasifikasi perubahan versi terpasang (murni). [fromBuild]/
/// [toBuild] dalam domain bangun dasar (versionCode % 1000, domain
/// yang sama dengan pemecah seri [isNewerRelease]).
AnnouncementTier classifyVersionChange({
  required String fromName,
  required int fromBuild,
  required String toName,
  required int toBuild,
}) {
  if (compareVersionNames(toName, fromName) < 0) {
    return AnnouncementTier.none; // turun versi: diam, basis digeser
  }
  List<int> parts(String v) => v
      .split('.')
      .map((s) => int.tryParse(s.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0)
      .toList();
  final pf = parts(fromName), pt = parts(toName);
  int at(List<int> p, int i) => i < p.length ? p[i] : 0;
  if (at(pt, 0) != at(pf, 0) || at(pt, 1) != at(pf, 1)) {
    return AnnouncementTier.feature;
  }
  if (toName == fromName && toBuild <= fromBuild) {
    return AnnouncementTier.none; // identik / bangun mundur
  }
  return AnnouncementTier.patch;
}

/// Permukaan unggulan yang dikenal pengumuman B1 (CTA deep-link).
enum AnnounceSurface { vault, share, taste, shuffle }

/// Pemetaan kata kunci → permukaan untuk item "Yang baru" (terpelihara
/// di sini, dijaga tes pengumuman_8079): urutan pemeriksaan adalah
/// urutan kekhususan — brankas paling khas, acak paling umum.
AnnounceSurface? announceSurfaceFor(String item) {
  final t = item.toLowerCase();
  if (t.contains('brankas')) return AnnounceSurface.vault;
  if (t.contains('bagikan') || t.contains('berbagi') || t.contains('qr')) {
    return AnnounceSurface.share;
  }
  if (t.contains('samaran') || t.contains('selera')) {
    return AnnounceSurface.taste;
  }
  if (t.contains('acak') || t.contains('shuffle')) {
    return AnnounceSurface.shuffle;
  }
  return null;
}

/// Pecah item "Yang baru" menjadi judul + subjudul untuk baris sorotan
/// B1 (murni): item rilis nyata adalah kalimat utuh, jadi pemisahan
/// hanya terjadi pada pola "Kepala: isi" dengan kepala pendek
/// (≤ 28 karakter); selain itu seluruh item adalah judulnya.
({String title, String? subtitle}) splitAnnounceItem(String item) {
  final idx = item.indexOf(': ');
  if (idx > 0 && idx <= 28) {
    final head = item.substring(0, idx).trim();
    final rest = item.substring(idx + 2).trim();
    if (head.isNotEmpty && rest.isNotEmpty) {
      return (title: head, subtitle: rest);
    }
  }
  return (title: item, subtitle: null);
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

/// Rilis dianggap BARU bila NAMA versinya lebih tinggi — nama adalah kunci
/// utama. Nomor bangun hanya memecah seri bila nama sama DAN tag rilis memang
/// membawa nomor bangun ('+N').
///
/// Mengapa bukan sebaliknya (Ronde 8054): semua tag rilis terbit TIDAK membawa
/// sufiks bangun (v1.0.0, v1.1.0, v2.0.0 → build selalu 0), sedangkan nomor
/// bangun pemasangan selalu > 0 (versionCode % 1000: 1.1.0 → 18). Aturan lama
/// ("salah satu sisi positif → bandingkan bangun saja") dengan itu selalu
/// memutuskan 0 > 18 = false: pembaruan dalam aplikasi tidak pernah menyala
/// untuk rilis terbit mana pun.
///
/// Pemecah seri pada nama yang sama juga harus SATU DOMAIN (Ronde 8056):
/// [ReleaseInfo.build] menyimpan sufiks tag apa adanya (tag `v2.0.1+8055`
/// → 8055), sedangkan `currentBuild` pemanggil sudah berupa bangun dasar
/// (versionCode % 1000 → 55). Membandingkan keduanya mentah berarti
/// 8055 > 55 selalu benar pada nama yang sama: rilis yang sedang terpasang
/// ditawarkan ulang selamanya dan status "sudah terbaru" tidak pernah
/// tercapai (terbukti E2E 12 Nov 2026, tahap 7). Maka sufiks tag
/// dinormalisasi ke domain yang sama di titik banding ini; ReleaseInfo
/// sendiri tetap jujur menyimpan nilai tag utuh.
bool isNewerRelease(ReleaseInfo r, {required String currentName, required int currentBuild}) {
  final byName = compareVersionNames(r.versionName, currentName);
  if (byName != 0) return byName > 0;
  final tagBuild = r.build % 1000;
  return tagBuild > 0 && tagBuild > currentBuild;
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

/// Nama berkas unduhan lokal untuk satu rilis — DIKAITKAN ke identitas
/// rilis (Ronde 8065). Akar cacat yang terbukti di HP riyan 14 Nov 2026:
/// nama lama selalu nama aset ('clai.apk') untuk SEMUA rilis, dan
/// pakai-ulang hanya mencocokkan UKURAN berkas; aset 2.0.1 dan 2.0.2
/// kebetulan sama-sama 30.884.225 byte, sehingga APK 2.0.1 sisa unduhan
/// lama dinyatakan "sudah terunduh" untuk 2.0.2 lalu ditolak Android
/// sebagai penurunan versi (INSTALL_FAILED_VERSION_DOWNGRADE).
/// Kini: nomor bangun dari tag bila ada ('clai-8065.apk'), selain itu tag
/// yang disanitasi.
String updateFileNameForRelease(ReleaseInfo r) {
  if (r.build > 0) return 'clai-${r.build}.apk';
  final safe = r.tag.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '-');
  return 'clai-$safe.apk';
}

/// Pola nama berkas unduhan Clai di folder sementara: nama terikat rilis
/// (`clai-<build>.apk` / `clai-<tag>.apk`) DAN nama warisan pra-8065
/// ('clai.apk' polos). Berkas lain di folder itu bukan urusan fungsi ini.
bool isUpdateFileName(String name) =>
    name == 'clai.apk' ||
    (name.startsWith('clai-') && name.toLowerCase().endsWith('.apk'));

/// Keputusan pakai-ulang berkas unduhan (murni): hanya bila berkasnya ada
/// dan UKURANNYA persis sama dengan aset yang ditawarkan. Nama berkasnya
/// sudah terikat rilis oleh pemanggil, jadi kecocokan ukuran di sini
/// hanya mungkin untuk berkas rilis yang sama.
bool shouldReuseUpdateFile(
        {required bool exists,
        required int fileLength,
        required int assetSize}) =>
    exists && assetSize > 0 && fileLength == assetSize;

/// Hapus berkas unduhan MILIK RILIS LAIN di [dir] (semua nama berpola
/// [isUpdateFileName] selain [keepName]) — tidak boleh ada sisa lintas
/// versi di folder sementara. Mengembalikan nama berkas yang terhapus.
/// Folder yang belum ada / tak terbaca → daftar kosong, tanpa galat.
Future<List<String>> pruneStaleUpdateFiles(
    Directory dir, String keepName) async {
  final deleted = <String>[];
  try {
    if (!await dir.exists()) return deleted;
    await for (final e in dir.list()) {
      if (e is! File) continue;
      final segments = e.uri.pathSegments;
      final name = segments.isEmpty ? '' : segments.last;
      if (name != keepName && isUpdateFileName(name)) {
        try {
          await e.delete();
          deleted.add(name);
        } catch (_) {
          // Berkas terkunci dsb.: lewati — unduhan rilis ini tidak
          // bergantung padanya (namanya berbeda).
        }
      }
    }
  } catch (_) {
    // Folder tak bisa didaftar: perlakukan sebagai tak ada yang dibersihkan.
  }
  return deleted;
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

  // ---------------- Pengumuman sesudah pasang (Ronde 8079, B1/B2) ----
  //
  // Mesin tampil-sekali per versi: pref `announce.seen*` adalah basis
  // versi terakhir yang SUDAH diumumkan (atau dibasiskan diam-diam).
  // Basis TIDAK dimajukan sebelum pengguna benar-benar menutup
  // pengumuman — aplikasi mati dengan overlay belum terjawab berarti
  // pengumuman tampil lagi pada buka dingin berikutnya (keputusan
  // spec: belum pernah ditutup ≠ sudah diumumkan).
  // Sumber catatan: simpanan `announce.pending*` (ditulis saat unduhan
  // rilis ini siap pasang — jalur pembaruan dalam aplikasi) atau
  // `announce.currentNotes*` (check() yang mendapati rilis terbaru di
  // umpan ADALAH versi terpasang — jalur sideload/Drive).
  AnnouncementTier announceTier = AnnouncementTier.none;
  String announceVersionName = '';
  List<String> announceNotes = const [];
  bool get hasAnnouncement => announceTier != AnnouncementTier.none;

  Future<void> _markAnnounceSeen(String name, int build) async {
    await db.setPref('announce.seenVersionName', name);
    await db.setPref('announce.seenBuild', build);
  }

  void _armAnnouncement(
      AnnouncementTier tier, String versionName, List<String> notes) {
    announceTier = tier;
    announceVersionName = versionName;
    announceNotes = notes;
    notifyListeners();
  }

  /// Catatan "Yang baru" untuk versi TERPASANG: cache currentNotes
  /// dulu; bila belum ada, satu putaran check() (yang mengisi cache itu
  /// saat rilis umpan == versi terpasang). Null = sumber tidak ketemu.
  Future<List<String>?> _notesForInstalledVersion(
      String name, int build) async {
    Future<List<String>?> fromCache() async {
      final cn = await db.pref<String>('announce.currentNotesVersion');
      if (cn != name) return null;
      final body = await db.pref<String>('announce.currentNotesBody');
      return body == null ? null : userFacingNotes(body);
    }

    final cached = await fromCache();
    if (cached != null) return cached;
    if (autoCheck) {
      await check(manual: false);
      return fromCache();
    }
    return null;
  }

  /// Nilai keadaan pengumuman untuk versi yang SEDANG terpasang.
  /// Dipanggil sekali saat mulai (sesudah loadPrefs), sebelum
  /// maybeAutoCheck. Tidak pernah melempar: mesin pengumuman tidak
  /// boleh menggagalkan penyalaan aplikasi.
  Future<void> evaluateAnnouncement() async {
    try {
      final v = await SysChannel.appVersion();
      if (v == null) return;
      final curName = v.name;
      final curBuild = SysChannel.baseBuildOf(v.code);
      final seenName = await db.pref<String>('announce.seenVersionName');
      if (seenName == null) {
        // Belum ada basis: instalasi segar ATAU debut mesin ini pada
        // pemasangan lama (8079 pertama kali berjalan). Bedakan dari
        // sinyal data lama: pernah memeriksa pembaruan atau pernah
        // memutar lagu.
        final lastCheck = await db.pref<int>('update.lastCheckMs') ?? 0;
        final everPlayed =
            await db.pref<bool>('playback.everPlayed') ?? false;
        if (lastCheck == 0 && !everPlayed) {
          await _markAnnounceSeen(curName, curBuild); // segar: diam
          return;
        }
        // Debut pada basis lama: umumkan sebagai rilis fitur HANYA
        // bila catatan versi terpasang bisa bersumber dari umpan.
        final notes = await _notesForInstalledVersion(curName, curBuild);
        if (notes != null && notes.isNotEmpty) {
          _armAnnouncement(AnnouncementTier.feature, curName, notes);
        } else {
          await _markAnnounceSeen(curName, curBuild);
        }
        return;
      }
      final seenBuild = await db.pref<int>('announce.seenBuild') ?? 0;
      if (seenName == curName && seenBuild == curBuild) return;
      final tier = classifyVersionChange(
          fromName: seenName,
          fromBuild: seenBuild,
          toName: curName,
          toBuild: curBuild);
      if (tier == AnnouncementTier.none) {
        await _markAnnounceSeen(curName, curBuild);
        return;
      }
      // Utamakan simpanan unduhan rilis ini; selain itu umpan.
      List<String>? notes;
      final pName = await db.pref<String>('announce.pendingVersionName');
      final pBuild = await db.pref<int>('announce.pendingBuild') ?? -1;
      if (pName == curName && pBuild % 1000 == curBuild) {
        final body = await db.pref<String>('announce.pendingNotes');
        if (body != null) notes = userFacingNotes(body);
      }
      notes ??= await _notesForInstalledVersion(curName, curBuild);
      if (tier == AnnouncementTier.feature) {
        if (notes != null && notes.isNotEmpty) {
          _armAnnouncement(tier, curName, notes);
        } else {
          // Rilis fitur tanpa blok "Yang baru": tidak ada yang jujur
          // untuk diumumkan — basis dimajukan diam-diam.
          await _markAnnounceSeen(curName, curBuild);
        }
      } else {
        // Tambalan: B2 tampil juga tanpa catatan ("Lihat" disembun-
        // yikan UI bila kosong).
        _armAnnouncement(tier, curName, notes ?? const []);
      }
    } catch (_) {
      // Diam: pengumuman adalah lapisan pemberitahuan, bukan gerbang.
    }
  }

  /// Pengguna menutup pengumuman (B1 lewat CTA/"Nanti saja", B2 lewat
  /// ✕/"Lihat"): basis dimajukan ke versi terpasang, keadaan dibersih-
  /// kan — tidak tampil lagi untuk versi ini, selamanya.
  Future<void> dismissAnnouncement() async {
    final v = await SysChannel.appVersion();
    if (v != null) {
      await _markAnnounceSeen(v.name, SysChannel.baseBuildOf(v.code));
    }
    announceTier = AnnouncementTier.none;
    announceVersionName = '';
    announceNotes = const [];
    notifyListeners();
  }

  /// Simpan catatan rilis yang baru diunduh sebagai pengumuman
  /// tertunda: sesudah pemasangan sistem selesai dan aplikasi menyala
  /// pada versi itu, evaluateAnnouncement menemukannya di sini.
  Future<void> _stashPendingAnnouncement(ReleaseInfo r) async {
    await db.setPref('announce.pendingVersionName', r.versionName);
    await db.setPref('announce.pendingBuild', r.build);
    await db.setPref('announce.pendingNotes', r.notes);
  }

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
        } else {
          // Ronde 8065: begitu identitas rilis terbaru diketahui, sisa
          // unduhan rilis LAIN di folder sementara dibersihkan — juga
          // pada hasil "sudah terbaru", agar berkas basi tidak menunggu
          // sebagai jebakan untuk pemeriksaan berikutnya.
          await _pruneFor(parsed);
          if (isNewerRelease(parsed, currentName: v.name, currentBuild: SysChannel.baseBuildOf(v.code))) {
            status = UpdateStatus.available;
            release = parsed;
            message = l10n.updAvailableMsg(parsed.versionName);
            notifyListeners();
            if (autoDownload) await download(auto: true);
          } else {
            status = UpdateStatus.upToDate;
            release = null;
            message = l10n.updUpToDate;
            // Ronde 8079: rilis terbaru di umpan ADALAH versi yang
            // terpasang → catatannya disimpan sebagai catatan versi
            // terpasang (sumber lembar "Yang baru" sesudah pasang dan
            // spanduk B2 pada jalur pasang sideload/Drive, yang tidak
            // melewati unduhan dalam aplikasi).
            if (parsed.versionName == v.name) {
              await db.setPref(
                  'announce.currentNotesVersion', parsed.versionName);
              await db.setPref('announce.currentNotesBody', parsed.notes);
            }
          }
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

  /// Bersihkan sisa unduhan rilis lain untuk rilis [r] (Ronde 8065).
  /// Gagal-aman penuh: folder sementara yang tak terjangkau tidak boleh
  /// menggagalkan pemeriksaan/unduhan itu sendiri.
  Future<void> _pruneFor(ReleaseInfo r) async {
    try {
      final dir =
          Directory('${(await getTemporaryDirectory()).path}/clai-updates');
      await pruneStaleUpdateFiles(dir, updateFileNameForRelease(r));
    } catch (_) {}
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
      // Ronde 8065: nama berkas terikat rilis ini, dan sisa rilis lain
      // dibersihkan SEBELUM keputusan pakai-ulang — berkas build lain
      // tidak akan pernah terbaca sebagai unduhan rilis ini lagi.
      final fileName = updateFileNameForRelease(r);
      await pruneStaleUpdateFiles(dir, fileName);
      final file = File('${dir.path}/$fileName');
      final exists = await file.exists();
      if (shouldReuseUpdateFile(
          exists: exists,
          fileLength: exists ? await file.length() : -1,
          assetSize: asset.size)) {
        downloadedPath = file.path;
        status = UpdateStatus.readyToInstall;
        message = l10n.updAlreadyDownloaded;
        await _stashPendingAnnouncement(r);
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
      await _stashPendingAnnouncement(r);
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
