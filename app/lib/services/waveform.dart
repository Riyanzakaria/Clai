import 'dart:convert';
import 'dart:math' as math;

/// Waveform UKUR (ronde Player B, keputusan pemilik 2026-11-09 22:22):
/// bentuk gelombang seek Player dibangun dari energi NYATA lagu —
/// sampel RMS Visualizer yang sama dengan mesin normalisasi/napas,
/// diakumulasi per ember posisi saat lagu diputar. Bukan gambar
/// bawaan, bukan karangan: ember yang belum pernah terukur tampil
/// sebagai garis datar minimal (keadaan "belum terukur" yang terbaca
/// jujur), dan terisi progresif pada putaran pertama; putaran ulang
/// membacanya dari basis data, utuh.
///
/// Berkas ini MURNI (tanpa Flutter/DB) agar seluruh pemetaan teruji
/// unit: indeks ember, akumulasi dB, normalisasi persentil tampil,
/// predikat gerbang, dan serialisasi.
///
/// **Ronde Perbaikan Waveform 8050 (2026-11-10, perintah pemilik
/// 20:24–20:26 — "batangnya ga bervariasi", "lebih sensitif",
/// "solve dengan best practice, gaada error lagi di tempat yang
/// sama"):** akar kelas kegagalannya adalah NILAI TERSIMPAN YANG
/// SUDAH DIPETAKAN. Format v2 menyimpan energi 0..1 hasil pemetaan
/// jendela tetap (−60..−2 dB): pita RMS Visualizer HP pemilik yang
/// terbukti hanya −16..−3 dB menjenuhkan semua ember ke 0,76–0,98 —
/// kejenuhan itu MENEMPEL PERMANEN di basis data dan normalisasi
/// puncak menampilkannya sebagai batang seragam penuh, di build apa
/// pun, selamanya. Perbaikan strukturalnya:
///
/// 1. **Simpan BESARAN MENTAH**: ember menyimpan RATA-RATA rmsDb
///    (domain dBFS) per ember + jumlah sampel — tidak ada jendela,
///    tidak ada pemetaan, tidak ada kejenuhan yang bisa menempel.
///    Pita perangkat selebar atau sesempit apa pun tersimpan apa
///    adanya.
/// 2. **Pemetaan pindah ke WAKTU TAMPIL dan bersifat RELATIF**:
///    tinggi batang dihitung dari distribusi dB trek itu sendiri
///    (persentil p10 → lantai, p95 → penuh; lihat [displayHeights]).
///    Tampilan tidak lagi bergantung pada dB absolut — kelas
///    kegagalan "pita perangkat berbeda dari asumsi jendela" tutup.
/// 3. **Serialisasi v3** (dB + hitungan). Data v2/v1 decode → null:
///    nilai jenuh era jendela tetap tidak bisa dipercaya lagi —
///    trek diperlakukan BELUM TERUKUR dan diukur ulang saat diputar
///    (gerbang terbuka untuknya; lihat predikat di bawah). Baris
///    rusak juga null. Tidak ada jalur di mana data lama/rusak
///    tampil sebagai bagan kosong yang mati: yang tampil adalah
///    garis datar jujur yang tumbuh lagi saat lagu diputar.

/// Jumlah ember tetap per trek (putusan ronde: pita 48–64).
const int kWaveformBucketCount = 56;

/// Lantai rentang dinamis tampil (dB): distribusi yang lebih sempit
/// dari ini TIDAK direntangkan paksa ke penuh — dua momen yang hanya
/// berbeda 0,5 dB memang terdengar sama keras, dan menampilkannya
/// sebagai kontras 0-vs-1 adalah dinamika karangan. Rentang efektif
/// minimal [kWaveformMinDisplaySpanDb] menjaga batang data nyaris
/// seragam tetap di sekitar tinggi menengah yang seragam (jujur),
/// sementara dinamika nyata ≥ rentang ini memakai skala penuh.
const double kWaveformMinDisplaySpanDb = 3.0;

/// Ambang rentang dinamis (dB) untuk menyebut data PENUH "bervariasi"
/// di predikat gerbang: di bawah ini, data penuh dianggap belum bisa
/// dipercaya (kemungkinan jenuh/tercemar hening) dan diukur ulang —
/// kecuali sampelnya sudah sangat banyak (lihat
/// [waveformWantsVisualizer]).
const double kWaveformVarianceFloorDb = 0.5;

/// Data waveform satu trek: [buckets] selalu sepanjang
/// [kWaveformBucketCount]; null = belum terukur, nilai lain =
/// RATA-RATA rmsDb (dBFS, domain log) sampel terukur di ember itu;
/// [counts] = jumlah sampel yang membentuk rata-rata tiap ember
/// (0 = belum terukur). Rata-rata berjalan di domain dB — momen
/// sesaat tidak memaku ember dan putaran ulang MENYEMPURNAKAN
/// pengukuran.
class WaveformData {
  final List<double?> buckets;
  final List<int> counts;

  WaveformData(List<double?> buckets, [List<int>? counts])
      : buckets = List.unmodifiable(buckets.length == kWaveformBucketCount
            ? buckets
            : List<double?>.generate(
                kWaveformBucketCount,
                (i) => i < buckets.length ? buckets[i] : null,
              )),
        counts = List.unmodifiable(List<int>.generate(
          kWaveformBucketCount,
          (i) {
            if (counts != null && i < counts.length) return counts[i];
            // Konstruksi dari ember saja: satu sampel per ember
            // terukur (data lama & data rakitan uji).
            return (i < buckets.length && buckets[i] != null) ? 1 : 0;
          },
        ));

  static final WaveformData empty =
      WaveformData(List<double?>.filled(kWaveformBucketCount, null));

  int get measuredCount => buckets.where((b) => b != null).length;

  bool get isEmpty => measuredCount == 0;

  bool get isFull => measuredCount == kWaveformBucketCount;

  /// Total sampel yang membentuk seluruh data (bobot bukti ukur).
  int get totalSamples => counts.fold(0, (a, b) => a + b);

  /// Jumlah sampel yang membentuk rata-rata ember [index].
  int sampleCountAt(int index) =>
      (index < 0 || index >= kWaveformBucketCount) ? 0 : counts[index];

  /// Persentil [p] (0..100) atas nilai dB ember-ember TERUKUR
  /// (interpolasi linear antar peringkat terurut); null bila belum
  /// ada ember terukur. Murni & deterministik — dasar normalisasi
  /// tampil relatif dan predikat varians gerbang.
  double? percentileDb(double p) {
    final vals = <double>[for (final b in buckets) if (b != null) b]..sort();
    if (vals.isEmpty) return null;
    if (vals.length == 1) return vals.first;
    final rank = (p.clamp(0.0, 100.0) / 100.0) * (vals.length - 1);
    final lo = rank.floor();
    final hi = math.min(lo + 1, vals.length - 1);
    final frac = rank - lo;
    return vals[lo] + (vals[hi] - vals[lo]) * frac;
  }

  /// Rentang dinamis terukur (p95 − p10, dB); 0 bila kurang dari dua
  /// ember terukur. Inilah "variasi" yang dibaca predikat gerbang —
  /// di domain dB mentah, bukan di energi terpeta.
  double get dynamicRangeDb {
    if (measuredCount < 2) return 0;
    final lo = percentileDb(10)!;
    final hi = percentileDb(95)!;
    return hi - lo;
  }

  /// Catat satu sampel [rmsDb] ke ember [index] sebagai RATA-RATA
  /// berjalan di domain dB: ember kosong mulai dari sampel ini;
  /// ember terukur bergerak menuju sampel baru sebesar 1/(n+1).
  /// Mengembalikan `this` bila rata-rata bergerak kurang dari
  /// 0,05 dB (pemanggil memakai identitas ini untuk melewati tulis
  /// DB & pemberitahuan UI — tulis tetap hemat).
  WaveformData withSample(int index, double rmsDb) {
    if (index < 0 || index >= kWaveformBucketCount) return this;
    final v = rmsDb.clamp(-96.0, 0.0);
    final cur = buckets[index];
    if (cur == null) {
      final next = List<double?>.of(buckets);
      next[index] = v;
      final nextCounts = List<int>.of(counts);
      nextCounts[index] = 1;
      return WaveformData(next, nextCounts);
    }
    final n = counts[index];
    final newAvg = (cur * n + v) / (n + 1);
    if ((newAvg - cur).abs() < 0.05) return this;
    final next = List<double?>.of(buckets);
    next[index] = newAvg;
    final nextCounts = List<int>.of(counts);
    nextCounts[index] = n + 1;
    return WaveformData(next, nextCounts);
  }

  /// Gabung dua data ember-per-ember sebagai rata-rata BERBOBOT
  /// jumlah sampel — dipakai saat muatan DB tiba sesudah umpan
  /// langsung lebih dulu mengisi (kedua sisi adalah pengukuran nyata
  /// dari trek yang sama; yang lebih banyak sampelnya berbobot lebih
  /// besar).
  WaveformData mergedWith(WaveformData other) {
    var changed = false;
    final next = List<double?>.filled(kWaveformBucketCount, null);
    final nextCounts = List<int>.filled(kWaveformBucketCount, 0);
    for (var i = 0; i < kWaveformBucketCount; i++) {
      final a = buckets[i];
      final b = other.buckets[i];
      if (a == null && b == null) continue;
      if (a == null) {
        next[i] = b;
        nextCounts[i] = other.counts[i];
        changed = true;
      } else if (b == null) {
        next[i] = a;
        nextCounts[i] = counts[i];
      } else {
        final na = counts[i];
        final nb = other.counts[i];
        next[i] = (a * na + b * nb) / (na + nb);
        nextCounts[i] = na + nb;
        if (next[i] != a || nextCounts[i] != na) changed = true;
      }
    }
    return changed ? WaveformData(next, nextCounts) : this;
  }

  /// Tinggi batang tampil 0..1 per ember (null tetap null = belum
  /// terukur). **Normalisasi PERSENTIL per trek** (Ronde 8050,
  /// menggantikan normalisasi puncak era v2): p10 distribusi dB trek
  /// → lantai, p95 → penuh; nilai di antaranya linear dalam dB.
  /// Karena relatif terhadap distribusi lagu itu sendiri, dinamika
  /// di dalam pita perangkat sesempit apa pun (−16..−3 dB di HP
  /// pemilik) tampil berbeda nyata antarbatang — tanpa satu pun
  /// asumsi dB absolut.
  ///
  /// Kejujuran dijaga dua sisi: (a) rentang efektif tidak pernah
  /// lebih sempit dari [kWaveformMinDisplaySpanDb] — selisih
  /// sub-3 dB tidak diledakkan menjadi kontras penuh; data nyaris
  /// seragam tampil nyaris seragam di sekitar tinggi menengah.
  /// (b) Ember terukur diberi lantai tampil 0,10 agar selalu
  /// terbedakan dari tik datar "belum terukur", dan p95 (bukan
  /// maksimum) menjadi jangkar penuh agar satu hentakan liar tidak
  /// meratakan seluruh lagu.
  List<double?> displayHeights() {
    if (isEmpty) return buckets;
    var lo = percentileDb(10)!;
    var hi = percentileDb(95)!;
    if (hi - lo < kWaveformMinDisplaySpanDb) {
      final mid = (lo + hi) / 2;
      lo = mid - kWaveformMinDisplaySpanDb / 2;
      hi = mid + kWaveformMinDisplaySpanDb / 2;
    }
    final span = hi - lo;
    return buckets.map((b) {
      if (b == null) return null;
      final t = ((b - lo) / span).clamp(0.0, 1.0);
      return 0.10 + 0.90 * t;
    }).toList();
  }

  /// Serialisasi untuk DB — **format v3**: objek JSON
  /// `{"v":3,"b":[rata-rata dB|null],"n":[jumlah sampel]}` (dB
  /// dibulatkan 1 desimal — presisi jauh di bawah ambang dengar dan
  /// ambang no-op rata-rata).
  String encode() => jsonEncode({
        'v': 3,
        'b': buckets
            .map((b) => b == null ? null : (b * 10).round() / 10)
            .toList(),
        'n': counts,
      });

  /// Baca kembali. Hanya format v3 yang dipercaya: **format v2
  /// (energi terpeta jendela tetap, era G-2) dan v1 (larik polos)
  /// mengembalikan null dengan sengaja** — nilai-nilai itu membawa
  /// kejenuhan jendela lama yang tidak bisa dipulihkan ke dB mentah,
  /// jadi trek diperlakukan belum terukur dan diukur ulang pada
  /// putaran berikutnya (Ronde 8050; pola yang sama seperti v1→v2
  /// dulu). Data rusak juga null. Tidak ada keadaan di mana baris
  /// lama/rusak tampil sebagai data: ia selalu berarti "ukur lagi".
  static WaveformData? decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final v = jsonDecode(raw);
      if (v is! Map || v['v'] != 3) return null;
      final b = v['b'];
      if (b is! List) return null;
      final n = v['n'];
      return WaveformData(
        b.map((e) => e is num ? e.toDouble().clamp(-96.0, 0.0) : null).toList(),
        n is List
            ? n.map((e) => e is num ? e.toInt() : 0).toList()
            : null,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  bool operator ==(Object other) {
    if (other is! WaveformData) return false;
    for (var i = 0; i < kWaveformBucketCount; i++) {
      if (buckets[i] != other.buckets[i]) return false;
      if (counts[i] != other.counts[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(Object.hashAll(buckets), Object.hashAll(counts));
}

/// Predikat gerbang Visualizer untuk konsumen waveform (Sisipan
/// G-1 + penguatan Ronde 8050): perekaman masih membutuhkan aliran
/// RMS selama data trek yang sedang diputar belum LENGKAP **dan
/// TERPERCAYA**:
///
/// - Belum penuh → butuh (pengukuran berjalan).
/// - Penuh + bervariasi (rentang ≥ [kWaveformVarianceFloorDb]) →
///   tidak butuh; data selesai, Visualizer tidak dibakar.
/// - Penuh tetapi NYARIS TANPA VARIASI → **tetap butuh**: sebaris
///   ember penuh bernilai (nyaris) sama persis adalah tanda data
///   jenuh/tercemar (kejenuhan jendela lama, atau ember terisi
///   peristiwa sesi diam saat crossfade), BUKAN tanda lagu selesai
///   diukur — gerbang tidak boleh membungkam pengukuran ulang
///   selamanya hanya karena penanda penuh tercapai. Pengecualian
///   kejujuran: bila total sampel sudah ≥ 3× jumlah ember dan
///   rentangnya tetap nol, lagunya memang seragam (drone/ambient
///   datar) — data diterima, gerbang padam.
/// - Data lama/rusak tidak pernah sampai ke predikat ini sebagai
///   "penuh": decode menolaknya menjadi null → dataFor kosong →
///   belum penuh → butuh. Murni.
bool waveformWantsVisualizer(WaveformData data) {
  if (!data.isFull) return true;
  if (data.dynamicRangeDb >= kWaveformVarianceFloorDb) return false;
  return data.totalSamples < 3 * kWaveformBucketCount;
}

/// Indeks ember untuk [position] dalam [duration]; -1 bila tak sah
/// (durasi belum diketahui / posisi di luar rentang).
int waveformBucketIndex(Duration position, Duration duration,
    [int count = kWaveformBucketCount]) {
  final total = duration.inMilliseconds;
  if (total <= 0 || count <= 0) return -1;
  final pos = position.inMilliseconds.clamp(0, total - 1);
  return (pos * count) ~/ total;
}
