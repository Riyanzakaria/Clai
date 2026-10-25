/// Pemilih sampul sadar ukuran tampil (v4.4, keluhan pemilik: "cover blur semua").
///
/// Akar: pengurai menyimpan SATU varian thumbnail dari sumber — yang kecil,
/// cukup untuk baris daftar 48dp — lalu Player merentangkannya selebar layar.
/// Sumber (YouTube Music) sebenarnya melayani banyak ukuran; URL-nya sendiri
/// membawa parameter ukuran yang bisa ditulis ulang:
/// - googleusercontent: `...=w60-h60-l90-rj` → ganti pasangan w/h, flag lain utuh.
/// - i.ytimg.com: segmen kualitas (`default|mqdefault|hqdefault|sddefault|maxresdefault`).
/// URL lokal (content://, file://, jalur MediaStore) dan host lain tidak disentuh.
library;

/// Tangga ukuran unduh (px) — permukaan tampil dibulatkan NAIK ke anak tangga
/// terdekat supaya dua permukaan berukuran mirip berbagi satu unduhan/cache.
const artworkBuckets = [200, 544, 1080];

/// Anak tangga unduh untuk sampul selebar [displaySizeDp] pada kerapatan [dpr].
int artworkBucketFor(double displaySizeDp, double dpr) {
  final need = (displaySizeDp * dpr).ceil();
  for (final b in artworkBuckets) {
    if (need <= b) return b;
  }
  return artworkBuckets.last;
}

final _gucSizeRe = RegExp(r'=w(\d+)(?:-h(\d+))?((?:-[a-zA-Z0-9]+)*)$');
final _ytimgRe = RegExp(r'((?:i\.ytimg\.com|img\.youtube\.com)/vi/[^/]+/)([a-z]+)(\.jpg)');

const _ytimgRank = {'default': 0, 'mqdefault': 1, 'hqdefault': 2, 'sddefault': 3, 'maxresdefault': 4};

int _ytimgRankForTarget(int targetPx) {
  if (targetPx >= 1000) return 4; // maxresdefault 1280
  if (targetPx >= 600) return 3; // sddefault 640
  if (targetPx >= 320) return 2; // hqdefault 480
  if (targetPx >= 160) return 1; // mqdefault 320
  return 0;
}

/// URL sampul untuk permukaan yang butuh gambar ±[targetPx] piksel.
/// Mengembalikan URL asal bila tidak ada skema ukuran yang dikenal.
String? artworkUrlForSize(String? url, int targetPx) {
  if (url == null || url.isEmpty) return url;
  if (!url.startsWith('http')) return url; // lokal/MediaStore: jangan diubah

  // Pisahkan query agar regex ukuran berlabuh di akhir jalur.
  final q = url.indexOf('?');
  final head = q == -1 ? url : url.substring(0, q);
  final tail = q == -1 ? '' : url.substring(q);

  if (head.contains('googleusercontent.com')) {
    final sized = head.replaceFirstMapped(
      _gucSizeRe,
      (m) => '=w$targetPx-h$targetPx${m.group(3) ?? ''}',
    );
    return '$sized$tail';
  }

  final yt = _ytimgRe.firstMatch(head);
  if (yt != null) {
    final current = _ytimgRank[yt.group(2)] ?? 0;
    final want = _ytimgRankForTarget(targetPx);
    if (want <= current) return url; // jangan turunkan varian yang sudah lebih besar
    final name = _ytimgRank.entries.firstWhere((e) => e.value == want).key;
    return '${head.replaceRange(yt.start, yt.end, '${yt.group(1)}$name${yt.group(3)}')}$tail';
  }

  return url;
}
