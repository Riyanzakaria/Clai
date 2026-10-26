import 'dart:async';

import '../data/app_db.dart';
import '../domain/models.dart';
import '../providers/ytmusic/innertube.dart' show artistNameFromByline;

/// Lapisan penyembuhan metadata (Ronde Cacat Metadata, 25 Okt 2026).
///
/// Sebagian rekam trek di basis data lokal tersimpan dengan artis kosong
/// dan/atau tanpa sampul — lahir dari bentuk sumber yang memang tidak
/// membawa kolom itu (item album tanpa byline, dsb.) pada build lama.
/// Perbaikan di sumber menghentikan rekam BARU; lapisan ini menyembuhkan
/// rekam yang SUDAH terlanjur kosong di perangkat pengguna (termasuk HP
/// pemilik) tanpa hapus data: saat trek seperti itu ditampilkan/diputar,
/// ia diselesaikan SATU KALI dari provider (resolve by ID), lalu baris
/// lokalnya diperbarui.
///
/// Aturan main yang dijaga:
/// - Kegagalan (offline / tidak ditemukan) = tampil apa adanya, tanpa
///   error, tanpa pengecualian yang lolos ke pemanggil.
/// - Percobaan ditandai (pref `heal.attempt.…`) dan tidak diulang selama
///   [_retryGap] — tidak ada pengulangan agresif di setiap buka layar.
/// - Percobaan serentak untuk trek yang sama digabung (satu panggilan).
class TrackMetadataHealer {
  final AppDb db;
  final Future<Track?> Function(String videoId) _resolveById;

  TrackMetadataHealer(this.db,
      {required Future<Track?> Function(String videoId) resolveById})
      : _resolveById = resolveById;

  final Map<String, Future<Track?>> _inFlight = {};

  static const _retryGap = Duration(days: 7);
  static const _categoryWords = {'Song', 'Video', 'Episode'};

  /// Nama artis dianggap rusak bila kosong, hanya kata kategori sumber
  /// (cacat parser lama yang menyimpan "Song" sebagai nama artis), atau
  /// masih byline mentah yang kini direduksi parser ("Artis • Album • 2025",
  /// "Artis • 552K views • 8.1K likes") — nilai yang akan berubah oleh
  /// reduksi itu berarti rekam lama belum bersih.
  static bool artistBroken(String artistNames) {
    final a = artistNames.trim();
    if (a.isEmpty || _categoryWords.contains(a)) return true;
    return artistNameFromByline(a) != a;
  }

  /// Hanya trek provider katalog yang bisa diselesaikan by ID; trek lokal
  /// dan impor tidak disentuh lapisan ini.
  static bool needsHeal(Track t) =>
      t.providerId == 'ytmusic' &&
      (artistBroken(t.artistNames) || t.artworkUrl == null);

  /// Kembalikan salinan yang sudah disembuhkan, atau null bila tidak perlu /
  /// tidak bisa disembuhkan sekarang. Tidak pernah melempar.
  Future<Track?> healIfNeeded(Track t) {
    if (!needsHeal(t)) return Future<Track?>.value(null);
    final k = '${t.providerId}/${t.id}';
    // PERANGKAP yang pernah menggantung uji & akan menggantung aplikasi:
    // callback whenComplete TIDAK boleh mengembalikan hasil Map.remove —
    // nilai yang tersimpan di peta adalah future whenComplete ini sendiri,
    // dan whenComplete menunggu future yang dikembalikan callback-nya
    // (= menunggu dirinya sendiri = buntu total). Badan berkurung wajib.
    return _inFlight.putIfAbsent(
        k,
        () => _heal(t).whenComplete(() {
              _inFlight.remove(k);
            }));
  }

  Future<Track?> _heal(Track t) async {
    try {
      final prefKey = 'heal.attempt.${t.providerId}.${t.id}';
      final last = await db.pref<int>(prefKey) ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - last < _retryGap.inMilliseconds) return null;
      await db.setPref(prefKey, now);
      final resolved = await _resolveById(t.id);
      if (resolved == null) return null;
      var healed = t;
      var changed = false;
      if (artistBroken(t.artistNames) &&
          resolved.artistNames.trim().isNotEmpty &&
          !artistBroken(resolved.artistNames)) {
        healed = healed.copyWith(
          artistNames: resolved.artistNames,
          artistIds:
              resolved.artistIds.isNotEmpty ? resolved.artistIds : null,
        );
        changed = true;
      }
      if (healed.artworkUrl == null && resolved.artworkUrl != null) {
        healed = healed.copyWith(artworkUrl: resolved.artworkUrl);
        changed = true;
      }
      if (!changed) return null;
      await db.cacheTracks([healed]);
      return healed;
    } catch (_) {
      // Penyembuhan tidak pernah menjatuhkan tampilan/pemutaran.
      return null;
    }
  }
}
