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
///  - trek yang disukai mendapat dorongan ke depan,
///  - di antara yang setara, trek yang PALING JARANG DIPUTAR didahulukan
///    (Ronde 8075: redaksi terkunci Acak Cerdas di BEDAH-F3 keputusan 1 —
///    "sebar artis & prioritaskan yang jarang diputar". Dorongan lama
///    "sering diputar +1" DICABUT: ia bertabrakan langsung dengan
///    prioritas jarang-diputar dan membuat lagu yang sama menang terus),
///  - urutan akhir deterministik untuk [seed] yang sama (dapat diuji & diulang).
///
/// Dipakai untuk seksi Lanjutan & Putar Otomatis (Ronde 8066: cakupan
/// diperluas dari Lanjutan saja — antrean berbentuk Putar Otomatis kini
/// ikut terurut cerdas). Antrean manual adalah milik pengguna (L-03)
/// dan tidak pernah diacak ulang oleh mode ini.
List<Track> smartShuffleOrder(
  List<Track> input, {
  Set<TrackKey> likedKeys = const {},
  Map<TrackKey, int> playCounts = const {},
  int? seed,
}) {
  if (input.length <= 1) return List<Track>.of(input);
  final rng = seed == null ? Random() : Random(seed);

  int boost(Track t) => likedKeys.contains(t.key) ? 2 : 0;
  int plays(Track t) => playCounts[t.key] ?? 0;

  // Urutan prioritas di dalam grup & antar-kepala-grup: dorongan suka
  // dulu, lalu jumlah putar MENAIK (paling jarang paling depan).
  int byPriority(Track a, Track b) {
    final byBoost = boost(b).compareTo(boost(a));
    if (byBoost != 0) return byBoost;
    return plays(a).compareTo(plays(b));
  }

  // Konstruksi grup (masalah rearrange-string): kelompokkan per artis utama,
  // lalu selalu ambil dari grup terbesar yang BUKAN artis pilihan terakhir
  // (seri: kepala berprioritas tertinggi dulu). Ini MENJAMIN tanpa dempetan bila
  // memungkinkan secara matematis (grup terbesar ≤ (n+1)/2); bila kolam
  // memaksa (satu artis mendominasi), dempetan hanya muncul di titik yang
  // tak terhindarkan — dan tidak ada trek yang dibuang.
  final shuffled = List<Track>.of(input)..shuffle(rng);
  final groups = <String, List<Track>>{};
  for (final t in shuffled) {
    groups.putIfAbsent(AutoplayGate.primaryArtistKey(t.artistNames), () => []).add(t);
  }
  for (final g in groups.values) {
    g.sort(byPriority);
  }
  final out = <Track>[];
  String? lastArtist;
  while (out.length < input.length) {
    String? pickGroup;
    var pickSize = -1;
    Track? pickHead;
    for (final e in groups.entries) {
      if (e.value.isEmpty) continue;
      if (e.key == lastArtist && groups.values.any((g) => g.isNotEmpty && g != e.value)) {
        continue; // ada alternatif: jangan dempetkan
      }
      final head = e.value.first;
      if (e.value.length > pickSize ||
          (e.value.length == pickSize &&
              pickHead != null &&
              byPriority(head, pickHead) < 0)) {
        pickGroup = e.key;
        pickSize = e.value.length;
        pickHead = head;
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
