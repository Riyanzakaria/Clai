import '../domain/models.dart';

/// Sumber kandidat Tangga Kemiripan — diimplementasikan provider; diuji dengan tiruan.
abstract class SimilaritySource {
  Future<List<Track>> sameArtist(Track seed);
  Future<List<Track>> related(Track seed);
  Future<List<Artist>> similarArtists(Track seed);
  Future<List<Track>> artistTopTracks(String artistId);
  Future<List<Track>> sameGenre(Track seed);
}

/// Gerbang mutu kandidat Putar Otomatis (cacat perangkat v4.4.2-1).
///
/// Bukti perangkat pemilik: umpan "related" sumber berisi video numerologi,
/// mixtape DJ berdurasi panjang, dan item non-musik lain yang lolos TANPA
/// saringan apa pun — tangga lama hanya menyaring duplikat & sinyal negatif.
/// Gerbang ini menolak kandidat yang JELAS bukan lagu tetangga wajar:
/// penanda non-musik pada judul/byline, durasi ekstrem di luar kewajaran
/// lagu (kecuali artis sama dengan benih — rekaman live artis benih sah),
/// dan klip sangat pendek. Kandidat yang lolos tidak diutak-atik urutannya
/// di sini; kedekatan diatur tangga. Bila kolam lolos saring kecil, batch
/// menjadi LEBIH PENDEK — jumlah jujur lebih baik daripada diisi sampah.
class AutoplayGate {
  AutoplayGate._();

  /// Penanda non-musik yang cukup khas untuk pencocokan substring.
  static const _nonMusicSubstrings = <String>[
    'numerolog',
    'ceramah',
    'khutbah',
    'khotbah',
    'kajian',
    'tausiyah',
    'pengajian',
    'murottal',
    'podcast',
    'talkshow',
    'talk show',
    'stand up comedy',
    'press conference',
    'konferensi pers',
    'breaking news',
    'live streaming',
    'siraman rohani',
  ];

  /// Penanda pendek yang harus berdiri sebagai kata utuh agar lagu sah
  /// seperti "Good News" tidak ikut tersaring.
  static final _nonMusicWords = <RegExp>[
    RegExp(r'\bberita\b'),
    RegExp(r'\bnews\b'),
    RegExp(r'\bsermon\b'),
  ];

  static const maxSongDuration = Duration(minutes: 25);
  static const minSongDuration = Duration(seconds: 30);

  static String normText(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();

  /// Kunci artis untuk pagar & perbandingan: peka huruf/spasi dinormalkan —
  /// "Hendraa RMX V2" / "HENDRAA RMX V2" / "Hendraa Rmx V2" adalah artis
  /// yang sama (bukti antrean perangkat: pagar lama lolos karena pencocokan
  /// string persis; lima trek Hendraa berurutan lolos sebagai "artis beda").
  static String artistKey(String artistNames) => normText(artistNames);

  /// Artis utama (segmen pertama sebelum & / , / feat.) ternormalisasi.
  static String primaryArtistKey(String artistNames) {
    var s = normText(artistNames);
    for (final sep in [' & ', ', ', ' feat. ', ' feat ', ' ft. ', ' x ']) {
      final i = s.indexOf(sep);
      if (i > 0) {
        s = s.substring(0, i);
        break;
      }
    }
    return s.trim();
  }

  /// Kunci judul untuk deduplikasi versi: sufiks kurung di ujung dibuang
  /// ("Judul (Remastered)" ≡ "Judul").
  static String titleKey(String title) => normText(
    title,
  ).replaceAll(RegExp(r'\s*[\(\[][^\)\]]*[\)\]]\s*$'), '').trim();

  static bool isNonMusic(Track t) {
    final hay = '${normText(t.title)} ${normText(t.artistNames)}';
    for (final m in _nonMusicSubstrings) {
      if (hay.contains(m)) return true;
    }
    for (final w in _nonMusicWords) {
      if (w.hasMatch(hay)) return true;
    }
    return false;
  }

  /// Apakah [t] lolos gerbang sebagai sambungan untuk benih-benih sesi ini.
  static bool passes(Track t, {required Set<String> seedPrimaryKeys}) {
    if (isNonMusic(t)) return false;
    final d = t.duration;
    if (d != null) {
      if (d < minSongDuration) return false;
      // Durasi ekstrem (mixtape / live-set / kompilasi video) hanya sah dari
      // artis utama yang sama dengan salah satu benih sesi.
      if (d > maxSongDuration &&
          !seedPrimaryKeys.contains(primaryArtistKey(t.artistNames))) {
        return false;
      }
    }
    return true;
  }

  /// Versi lain dari lagu benih itu sendiri (judul + artis utama sama) —
  /// bukan sambungan, melainkan pengulangan terselubung.
  static bool isSeedVersion(Track t, List<Track> seeds) {
    final tk = titleKey(t.title);
    final pk = primaryArtistKey(t.artistNames);
    for (final s in seeds) {
      if (titleKey(s.title) == tk && primaryArtistKey(s.artistNames) == pk) {
        return true;
      }
    }
    return false;
  }

  /// Kunci deduplikasi antar-versi di dalam batch.
  static String versionKey(Track t) =>
      '${titleKey(t.title)}|${primaryArtistKey(t.artistNames)}';
}

/// Batch radio SATU benih untuk halaman Radio (F2.5): keluaran mentah
/// tangga-2 provider (RDAMVM) disaring Gerbang Kualitas dengan aturan yang
/// sama seperti penambahan batch tangga — benih sendiri & versi lain dari
/// lagu benih dibuang, duplikat kunci/versi dibuang, non-musik & durasi
/// ekstrem tersaring. Urutan sumber dipertahankan (kedekatan versi radio
/// adalah milik sumber; halaman menampilkannya apa adanya). Murni & diuji.
List<Track> gateRadioBatch(Track seed, List<Track> raw) {
  final seedPrimaryKeys = {AutoplayGate.primaryArtistKey(seed.artistNames)};
  final seen = <TrackKey>{seed.key};
  final seenVersions = <String>{};
  final out = <Track>[];
  for (final t in raw) {
    if (!seen.add(t.key)) continue;
    if (!AutoplayGate.passes(t, seedPrimaryKeys: seedPrimaryKeys)) continue;
    if (AutoplayGate.isSeedVersion(t, [seed])) continue;
    if (!seenVersions.add(AutoplayGate.versionKey(t))) continue;
    out.add(t);
  }
  return out;
}

/// Tangga Kemiripan (PRD 5.4) — murni & teruji:
/// 1 artis sama → 2 related sumber → 3 artis serupa → 4 genre/niche; 5 penguat personal (naik peringkat).
/// Anti-drift: kandidat selalu dihitung dari BENIH SESI, tidak pernah dari sambungan sebelumnya.
/// Saring: gerbang mutu (AutoplayGate), yang sudah di antrean, sinyal negatif sesi (L-06), duplikat
/// (termasuk antar-versi). Pagar: maks 2 lagu artis sama berurutan — kunci artis TERNORMALISASI.
class SimilarityLadder {
  final SimilaritySource source;
  final Set<TrackKey> likedKeys;
  final Map<TrackKey, int> playCounts;

  /// Batas waktu per panggilan sumber (v4.4.2): panggilan yang menggantung
  /// tidak boleh menyandera isi ulang selamanya — tangga itu gugur, tangga
  /// lain tetap berjalan. Tanpa batas ini satu panggilan macet memblokir
  /// semua pemicu isi ulang berikutnya (gerbang _refilling di handler).
  final Duration sourceTimeout;

  SimilarityLadder(
    this.source, {
    this.likedKeys = const {},
    this.playCounts = const {},
    this.sourceTimeout = const Duration(seconds: 15),
  });

  Future<List<T>> _guard<T>(Future<List<T>> f) =>
      f.timeout(sourceTimeout, onTimeout: () => <T>[]);

  Future<List<Track>> buildBatch({
    required List<Track> seeds,
    required Set<TrackKey> alreadyQueued,
    required Set<TrackKey> sessionNegative,
    String? lastArtistNames,
    int target = 15,
  }) async {
    if (seeds.isEmpty) return const [];
    final excluded = {...alreadyQueued, ...sessionNegative};
    final byLadder = <int, List<Track>>{1: [], 2: [], 3: [], 4: []};
    final seen = <TrackKey>{};
    final seenVersions = <String>{};
    final seedPrimaryKeys = {
      for (final s in seeds) AutoplayGate.primaryArtistKey(s.artistNames),
    };

    void add(int ladder, Iterable<Track> tracks) {
      for (final t in tracks) {
        if (excluded.contains(t.key)) continue;
        if (!seen.add(t.key)) continue;
        if (!AutoplayGate.passes(t, seedPrimaryKeys: seedPrimaryKeys)) continue;
        if (AutoplayGate.isSeedVersion(t, seeds)) continue;
        if (!seenVersions.add(AutoplayGate.versionKey(t))) continue;
        byLadder[ladder]!.add(t);
      }
    }

    // Setiap tangga dicoba dari semua benih (dibatasi 3 benih teratas agar jaringan hemat),
    // kegagalan satu tangga tidak menjatuhkan tangga lain. Panggilan antar-benih
    // kini PARALEL per tangga (v4.4.2): versi sekuensial membuat isi ulang
    // pertama tiba dalam hitungan menit di jaringan lambat — jendela trek
    // tunggal bisa habis sebelum sambungan pertama mendarat (cacat-2).
    // Urutan hasil dipertahankan (Future.wait menjaga urutan benih).
    final seedSlice = seeds.take(3).toList();
    final sameArtistResults = await Future.wait([
      for (final seed in seedSlice)
        () async {
          try {
            return await _guard(source.sameArtist(seed));
          } catch (_) {
            return const <Track>[];
          }
        }(),
    ]);
    for (final r in sameArtistResults) {
      add(1, r);
    }
    final relatedResults = await Future.wait([
      for (final seed in seedSlice)
        () async {
          try {
            return await _guard(source.related(seed));
          } catch (_) {
            return const <Track>[];
          }
        }(),
    ]);
    for (final r in relatedResults) {
      add(2, r);
    }
    final similarResults = await Future.wait([
      for (final seed in seedSlice)
        () async {
          try {
            final artists = await _guard(source.similarArtists(seed));
            final tops = await Future.wait([
              for (final a in artists.take(4))
                () async {
                  try {
                    return await _guard(source.artistTopTracks(a.id));
                  } catch (_) {
                    return const <Track>[];
                  }
                }(),
            ]);
            return [for (final t in tops) ...t];
          } catch (_) {
            return const <Track>[];
          }
        }(),
    ]);
    for (final r in similarResults) {
      add(3, r);
    }
    if (byLadder.values.every((l) => l.length < 4)) {
      final genreResults = await Future.wait([
        for (final seed in seedSlice)
          () async {
            try {
              return await _guard(source.sameGenre(seed));
            } catch (_) {
              return const <Track>[];
            }
          }(),
      ]);
      for (final r in genreResults) {
        add(4, r);
      }
    }

    // Gabung berurutan tangga 1→4; di dalam tangga, yang liked/sering diputar naik (tangga 5 = penguat),
    // lalu kandidat TERSTRUKTUR (punya album/artis terdaftar) sebelum item panel
    // telanjang — kedekatan katalog mengalahkan umpan video mentah (v4.4.2).
    int boost(Track t) =>
        (likedKeys.contains(t.key) ? 2 : 0) +
        ((playCounts[t.key] ?? 0) > 2 ? 1 : 0);
    int structured(Track t) =>
        (t.albumId != null || t.artistIds.isNotEmpty) ? 1 : 0;
    final merged = <Track>[];
    for (var ladder = 1; ladder <= 4; ladder++) {
      final list = byLadder[ladder]!;
      list.sort((a, b) {
        final byBoost = boost(b).compareTo(boost(a));
        if (byBoost != 0) return byBoost;
        return structured(b).compareTo(structured(a));
      });
      merged.addAll(list);
    }

    // Penempatan rakus dengan pagar artis: ambil kandidat teratas yang tidak
    // membuat 3 lagu artis sama (kunci ternormalisasi) berurutan — termasuk
    // menjembatani lagu terakhir antrean. Kandidat yang hanya bisa melanggar
    // pagar DIBUANG (batch lebih pendek & jujur), bukan ditumpuk di ekor
    // seperti lolos-tunda versi lama yang justru menciptakan run di ujung.
    final out = <Track>[];
    final pool = List<Track>.of(merged);
    String? runKey = lastArtistNames == null
        ? null
        : AutoplayGate.artistKey(lastArtistNames);
    var runCount = lastArtistNames == null ? 0 : 1;
    while (out.length < target && pool.isNotEmpty) {
      var pick = -1;
      for (var i = 0; i < pool.length; i++) {
        final k = AutoplayGate.artistKey(pool[i].artistNames);
        if (k == runKey && runCount >= 2) continue;
        pick = i;
        break;
      }
      if (pick < 0) break;
      final t = pool.removeAt(pick);
      final k = AutoplayGate.artistKey(t.artistNames);
      if (k == runKey) {
        runCount++;
      } else {
        runKey = k;
        runCount = 1;
      }
      out.add(t);
    }
    return out;
  }
}

/// Hasil pembangunan batch isi ulang (temuan vonis 2008 #4).
class RefillBatch {
  final List<Track> batch;

  /// true bila percobaan ketat (riwayat sesi dikecualikan) menghasilkan
  /// batch kosong dan pembangunan jatuh ke pelonggaran — pengulangan lagu
  /// yang sudah diputar sesi ini diizinkan karena kolamnya habis.
  final bool relaxed;

  const RefillBatch(this.batch, {this.relaxed = false});
}

/// Bangun batch isi ulang Putar Otomatis dengan pengecualian riwayat sesi
/// BERTINGKAT (temuan vonis 2008 #4).
///
/// Cacat awal: isi ulang hanya mengecualikan antrean berjalan + sinyal
/// skip, sehingga lagu yang SUDAH diputar di sesi yang sama ditawarkan
/// lagi — pada kolam terkait yang sempit, kebanyakan isi batch berikutnya
/// adalah pengulangan. Kini [playedKeys] (kunci riwayat sesi) ikut
/// dikecualikan pada percobaan pertama. Bila kolam benar-benar habis
/// sesudah pengecualian itu (batch kosong), pengecualian riwayat
/// dilonggarkan pada percobaan kedua — pengulangan yang jujur lebih baik
/// daripada isi ulang gagal dan antrean mati. Sinyal skip sesi TIDAK
/// pernah dilonggarkan di kedua percobaan.
Future<RefillBatch> buildRefillBatch(
  SimilarityLadder ladder, {
  required List<Track> seeds,
  required Set<TrackKey> queuedKeys,
  required Set<TrackKey> playedKeys,
  required Set<TrackKey> sessionNegative,
  String? lastArtistNames,
}) async {
  if (playedKeys.isEmpty) {
    return RefillBatch(
      await ladder.buildBatch(
        seeds: seeds,
        alreadyQueued: queuedKeys,
        sessionNegative: sessionNegative,
        lastArtistNames: lastArtistNames,
      ),
    );
  }
  final strict = await ladder.buildBatch(
    seeds: seeds,
    alreadyQueued: {...queuedKeys, ...playedKeys},
    sessionNegative: sessionNegative,
    lastArtistNames: lastArtistNames,
  );
  if (strict.isNotEmpty) return RefillBatch(strict);
  final relaxed = await ladder.buildBatch(
    seeds: seeds,
    alreadyQueued: queuedKeys,
    sessionNegative: sessionNegative,
    lastArtistNames: lastArtistNames,
  );
  return RefillBatch(relaxed, relaxed: true);
}
