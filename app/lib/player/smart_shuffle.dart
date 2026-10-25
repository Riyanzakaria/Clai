import 'dart:math';

import '../domain/models.dart';
import 'similarity.dart';

/// Smart Shuffle (F2) — pengacakan CERDAS atas daftar yang SUDAH ada.
///
/// Janji produk (dijawab ke pemilik): fungsi ini TIDAK PERNAH menambah,
/// membuang, atau mengganti satu pun trek — keluarannya adalah permutasi
/// persis dari masukannya. Penyuntikan lagu baru tetap wilayah eksklusif
/// Putar Otomatis yang berlabel AUTO. Yang diatur di sini hanya URUTAN:
///  - artis utama yang sama disebar (tidak berdempetan bila memungkinkan),
///  - trek yang disukai / sering diputar mendapat dorongan ke depan,
///  - urutan akhir deterministik untuk [seed] yang sama (dapat diuji & diulang).
///
/// Dipakai untuk seksi Lanjutan saja: antrean manual adalah milik pengguna
/// (L-03) dan tidak pernah diacak ulang oleh mode ini.
List<Track> smartShuffleOrder(
  List<Track> input, {
  Set<TrackKey> likedKeys = const {},
  Map<TrackKey, int> playCounts = const {},
  int? seed,
}) {
  if (input.length <= 1) return List<Track>.of(input);
  final rng = seed == null ? Random() : Random(seed);

  int boost(Track t) =>
      (likedKeys.contains(t.key) ? 2 : 0) + ((playCounts[t.key] ?? 0) > 2 ? 1 : 0);

  // Konstruksi grup (masalah rearrange-string): kelompokkan per artis utama,
  // lalu selalu ambil dari grup terbesar yang BUKAN artis pilihan terakhir
  // (seri: dorongan tertinggi dulu). Ini MENJAMIN tanpa dempetan bila
  // memungkinkan secara matematis (grup terbesar ≤ (n+1)/2); bila kolam
  // memaksa (satu artis mendominasi), dempetan hanya muncul di titik yang
  // tak terhindarkan — dan tidak ada trek yang dibuang.
  final shuffled = List<Track>.of(input)..shuffle(rng);
  final groups = <String, List<Track>>{};
  for (final t in shuffled) {
    groups.putIfAbsent(AutoplayGate.primaryArtistKey(t.artistNames), () => []).add(t);
  }
  for (final g in groups.values) {
    g.sort((a, b) => boost(b).compareTo(boost(a)));
  }
  final out = <Track>[];
  String? lastArtist;
  while (out.length < input.length) {
    String? pickGroup;
    var pickSize = -1;
    var pickBoost = -1;
    for (final e in groups.entries) {
      if (e.value.isEmpty) continue;
      if (e.key == lastArtist && groups.values.any((g) => g.isNotEmpty && g != e.value)) {
        continue; // ada alternatif: jangan dempetkan
      }
      final headBoost = boost(e.value.first);
      if (e.value.length > pickSize ||
          (e.value.length == pickSize && headBoost > pickBoost)) {
        pickGroup = e.key;
        pickSize = e.value.length;
        pickBoost = headBoost;
      }
    }
    // pickGroup tak mungkin null selama masih ada sisa (fallback: grup terakhir).
    pickGroup ??= groups.entries.firstWhere((e) => e.value.isNotEmpty).key;
    final t = groups[pickGroup]!.removeAt(0);
    out.add(t);
    lastArtist = pickGroup;
  }
  return out;
}

/// Apakah urutan [ordered] masih memuat artis utama yang sama berdempetan
/// (dipakai uji & diagnosis; bukan syarat keras bila kolam memaksa).
bool hasAdjacentSameArtist(List<Track> ordered) {
  for (var i = 1; i < ordered.length; i++) {
    if (AutoplayGate.primaryArtistKey(ordered[i].artistNames) ==
        AutoplayGate.primaryArtistKey(ordered[i - 1].artistNames)) {
      return true;
    }
  }
  return false;
}
