import '../domain/models.dart';

/// Edit bedah pada ekor sumber gabungan yang hidup (temuan vonis 2008 #3).
///
/// Sebelum perbaikan ini, setiap mutasi antrean (hapus, urungkan, geser,
/// bersihkan, sakelar Putar Otomatis, saring offline, sisip Berikutnya)
/// membangun ulang SELURUH ConcatenatingAudioSource lewat setAudioSource —
/// trek yang sedang berbunyi ikut disiapkan ulang dan terdengar sebagai
/// jeda. Rencana di berkas ini menghitung edit minimal atas anak-anak
/// sumber SESUDAH indeks trek berjalan, sehingga trek berjalan tidak
/// pernah disentuh: yang berubah hanya antrean di depannya.
sealed class TailEdit {
  const TailEdit();
}

/// Cabut anak ekor pada [tailIndex] (0 = anak pertama sesudah trek
/// berjalan), dalam koordinat ekor TERPASANG saat ini.
class TailRemove extends TailEdit {
  final int tailIndex;
  const TailRemove(this.tailIndex);

  @override
  bool operator ==(Object other) =>
      other is TailRemove && other.tailIndex == tailIndex;

  @override
  int get hashCode => tailIndex.hashCode;

  @override
  String toString() => 'TailRemove($tailIndex)';
}

/// Sisipkan [track] pada [tailIndex], dalam koordinat ekor TUJUAN
/// (sesudah seluruh penghapusan diterapkan).
class TailInsert extends TailEdit {
  final int tailIndex;
  final Track track;
  const TailInsert(this.tailIndex, this.track);

  @override
  bool operator ==(Object other) =>
      other is TailInsert &&
      other.tailIndex == tailIndex &&
      other.track.key == track.key;

  @override
  int get hashCode => Object.hash(tailIndex, track.key);

  @override
  String toString() => 'TailInsert($tailIndex, ${track.key})';
}

/// Rencana edit minimal yang mengubah ekor terpasang [loadedTail] menjadi
/// [desiredTail] (keduanya urutan trek sesudah trek berjalan).
///
/// Berbasis LCS (longest common subsequence) atas kunci trek: anak yang
/// urutannya sudah benar TIDAK disentuh sama sekali — anak sumbernya yang
/// sudah teresolusi (dan mungkin sudah ter-buffer untuk transisi gapless)
/// dipertahankan persis. Yang dicabut hanya yang hilang/pindah keluar,
/// yang disisipkan hanya yang baru/pindah masuk.
///
/// Kontrak eksekusi: terapkan semua [TailRemove] dalam urutan indeks
/// MENURUN (agar indeks di bawahnya tidak bergeser), lalu semua
/// [TailInsert] dalam urutan indeks MENAIK pada koordinat tujuan.
List<TailEdit> planTailEdits(List<Track> loadedTail, List<Track> desiredTail) {
  final n = loadedTail.length;
  final m = desiredTail.length;
  if (n == 0 && m == 0) return const [];
  // Tabel LCS arah suffix: dp[i][j] = panjang LCS loadedTail[i:] vs desiredTail[j:].
  final dp = List.generate(n + 1, (_) => List<int>.filled(m + 1, 0));
  for (var i = n - 1; i >= 0; i--) {
    for (var j = m - 1; j >= 0; j--) {
      dp[i][j] = loadedTail[i].key == desiredTail[j].key
          ? dp[i + 1][j + 1] + 1
          : (dp[i + 1][j] >= dp[i][j + 1] ? dp[i + 1][j] : dp[i][j + 1]);
    }
  }
  final keptLoaded = <int>{};
  final keptDesired = <int>{};
  var i = 0;
  var j = 0;
  while (i < n && j < m) {
    if (loadedTail[i].key == desiredTail[j].key) {
      keptLoaded.add(i);
      keptDesired.add(j);
      i++;
      j++;
    } else if (dp[i + 1][j] >= dp[i][j + 1]) {
      i++;
    } else {
      j++;
    }
  }
  return [
    for (var a = 0; a < n; a++)
      if (!keptLoaded.contains(a)) TailRemove(a),
    for (var b = 0; b < m; b++)
      if (!keptDesired.contains(b)) TailInsert(b, desiredTail[b]),
  ];
}
