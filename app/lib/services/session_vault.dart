import 'package:flutter/foundation.dart';

import '../data/app_db.dart';
import '../player/queue_engine.dart';

/// Metadata tampilan satu sesi Brankas (snapshot penuh dimuat terpisah
/// lewat [SessionVaultService.snapshotOf] — daftar & rak tidak membayar
/// biaya dekode snapshot).
class VaultSessionInfo {
  final String id;
  final String name;
  final DateTime savedAt;
  final int trackCount;
  final String? currentTitle;
  final String? currentArtist;
  final String? currentArtwork;
  final String? contextLabel;
  final int positionMs;

  const VaultSessionInfo({
    required this.id,
    required this.name,
    required this.savedAt,
    required this.trackCount,
    this.currentTitle,
    this.currentArtist,
    this.currentArtwork,
    this.contextLabel,
    this.positionMs = 0,
  });

  factory VaultSessionInfo.fromRow(Map<String, Object?> r) =>
      VaultSessionInfo(
        id: r['id'] as String,
        name: r['name'] as String,
        savedAt:
            DateTime.fromMillisecondsSinceEpoch((r['saved_at'] as num).toInt()),
        trackCount: (r['track_count'] as num?)?.toInt() ?? 0,
        currentTitle: r['current_title'] as String?,
        currentArtist: r['current_artist'] as String?,
        currentArtwork: r['current_artwork'] as String?,
        contextLabel: r['context_label'] as String?,
        positionMs: (r['position_ms'] as num?)?.toInt() ?? 0,
      );
}

/// Nama bawaan sesi: `<Hari> <bagian hari>, <d> <Bln>` — pola rujukan
/// desain Brankas Sesi ("Jumat malam, 21 Nov"). MURNI (diuji unit):
/// nama hari/bulan adalah data kalender per locale dinyatakan sebagai
/// tabel, tanpa dependensi intl (pola `homeDateKicker` Beranda).
String defaultSessionName(DateTime now, String languageCode) {
  const idDays = [
    'Senin',
    'Selasa',
    'Rabu',
    'Kamis',
    'Jumat',
    'Sabtu',
    'Minggu',
  ];
  const enDays = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  const idMonths = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'Mei',
    'Jun',
    'Jul',
    'Agu',
    'Sep',
    'Okt',
    'Nov',
    'Des',
  ];
  const enMonths = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final id = languageCode == 'id';
  final day = (id ? idDays : enDays)[now.weekday - 1];
  final mon = (id ? idMonths : enMonths)[now.month - 1];
  final h = now.hour;
  final part = id
      ? (h >= 5 && h < 11
          ? 'pagi'
          : h < 15
              ? 'siang'
              : h < 19
                  ? 'sore'
                  : 'malam')
      : (h >= 5 && h < 12
          ? 'morning'
          : h < 17
              ? 'afternoon'
              : h < 20
                  ? 'evening'
                  : 'night');
  return id
      ? '$day $part, ${now.day} $mon'
      : '$day $part, $mon ${now.day}';
}

/// Label tanggal simpan untuk meta daftar/detail: id "21 Nov 2026",
/// en "Nov 21, 2026". MURNI.
String vaultDateLabel(DateTime d, String languageCode) {
  const idMonths = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'Mei',
    'Jun',
    'Jul',
    'Agu',
    'Sep',
    'Okt',
    'Nov',
    'Des',
  ];
  const enMonths = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final id = languageCode == 'id';
  final mon = (id ? idMonths : enMonths)[d.month - 1];
  return id ? '${d.day} $mon ${d.year}' : '$mon ${d.day}, ${d.year}';
}

/// Jam simpan "19:42" (24 jam, tanpa intl). MURNI.
String vaultTimeLabel(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

/// Brankas Sesi (Ronde 8072, Workstream D): arsip permanen sesi putar.
///
/// Simpan menangkap snapshot antrean PENUH dari mesin (bentuk yang sama
/// persis dengan simpanan Lanjut Besok D-15) lewat satu INSERT atomik;
/// pulih diserahkan ke jahitan handler yang sudah terbukti
/// (`restoreSleepSession`) oleh lapisan UI — layanan ini murni data.
class SessionVaultService extends ChangeNotifier {
  final AppDb db;
  SessionVaultService(this.db);

  List<VaultSessionInfo> _sessions = [];
  bool loaded = false;

  List<VaultSessionInfo> get sessions => _sessions;
  bool get isEmpty => _sessions.isEmpty;

  Future<void> load() async {
    final rows = await db.vaultSessions();
    _sessions = rows.map(VaultSessionInfo.fromRow).toList();
    loaded = true;
    notifyListeners();
  }

  /// Simpan antrean [engine] saat ini sebagai sesi bernama. Null bila
  /// tidak ada lagu berjalan (tidak ada sesi untuk disimpan — pemanggil
  /// menonaktifkan titik masuknya pada keadaan itu).
  Future<String?> saveCurrent({
    required QueueEngine engine,
    required Duration position,
    required String name,
  }) async {
    if (engine.current == null) return null;
    final snap = engine.snapshot(positionMs: position.inMilliseconds);
    final id = await db.saveVaultSession(
      name: name,
      snapshot: snap,
      currentTrack: engine.current,
    );
    await load();
    return id;
  }

  Future<Map<String, Object?>?> snapshotOf(String id) =>
      db.vaultSnapshot(id);

  Future<void> delete(String id) async {
    await db.deleteVaultSession(id);
    await load();
  }
}
