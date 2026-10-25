/// Pembersihan teks TAMPIL untuk baris lagu & kartu Beranda (Ronde Poles
/// Beranda, butir 3 — keputusan riyan 24 Okt 2026).
///
/// Trek dari sumber video membawa judul unggahan mentah — awalan kurung
/// nama pengunggah seperti "[AIJING 아이찡] A2O LITE - NEON …" — dan byline
/// berisi metadata unggahan ("sarivkzx • 4K views", "3d ago • MBC Radio").
/// Ditampilkan apa adanya, Beranda terbaca sebagai daftar unggahan, bukan
/// daftar lagu. Fungsi di sini membersihkan LAPISAN TAMPIL saja: data asli
/// tidak pernah diubah (pencarian, pencocokan trek, radio, dan riwayat
/// tetap memakai teks sumber yang utuh).
library;

/// Judul tampil bersih: buang awalan kelompok kurung siku `[...]` /
/// kurung siku penuh U+3010/U+3011 (boleh berurutan) dari AWAL judul — pola khas
/// nama kanal/pengunggah pada judul unggahan. Kurung biasa TIDAK disentuh:
/// judul sah bisa diawali kurung biasa ("(Don't Fear) The Reaper").
/// Bila sesudah dibuang tidak tersisa apa-apa, judul asli dikembalikan —
/// baris tidak pernah tampil tanpa judul.
String cleanDisplayTitle(String raw) {
var t = raw.trim();
while (true) {
String? closer;
if (t.startsWith('[')) closer = ']';
if (t.startsWith('\u3010')) closer = '\u3011';
if (closer == null) break;
final end = t.indexOf(closer);
if (end < 0) break;
final rest = t.substring(end + 1).trim();
if (rest.isEmpty) break; // jangan sampai judul hilang sama sekali
t = rest;
}
return t.replaceAll(RegExp(r'\s+'), ' ');
}

final _viewsRe = RegExp(
r'^[\d]+([.,]\d+)?\s*(k|m|b|rb|jt)?\s+(views?|plays?|x\s+ditonton)$',
caseSensitive: false);
final _agoEnRe = RegExp(
r'^(\d+\s*(second|minute|hour|day|week|month|year)s?\s+ago|\d+\s*[smhdwy]\s+ago)$',
caseSensitive: false);
final _agoIdRe =
RegExp(r'^\d+\s+(detik|menit|jam|hari|minggu|bulan|tahun)\s+yang\s+lalu$',
caseSensitive: false);
final _streamedRe =
RegExp(r'^(streamed|premiered)\b.*\bago$', caseSensitive: false);

/// Satu segmen byline adalah metadata unggahan (bukan nama artis/album):
/// jumlah tontonan ("4K views", "16M views", "1,2 rb x ditonton") atau
/// umur unggahan ("3d ago", "2 weeks ago", "Streamed 5 days ago").
bool isUploadMetaSegment(String seg) {
final s = seg.trim();
if (s.isEmpty) return true;
return _viewsRe.hasMatch(s) ||
_agoEnRe.hasMatch(s) ||
_agoIdRe.hasMatch(s) ||
_streamedRe.hasMatch(s);
}

/// Artis tampil bersih: byline dipecah per " • ", segmen metadata unggahan
/// dibuang, sisanya digabung kembali. Segmen sah (artis • album • tahun)
/// tidak disentuh. Bila semua segmen adalah metadata, hasilnya string
/// kosong — pemanggil menyembunyikan baris artis sama sekali daripada
/// menampilkan metadata unggahan sebagai "artis".
String cleanDisplayArtist(String raw) {
final segs = raw
.split('•')
.map((s) => s.trim())
.where((s) => s.isNotEmpty)
.where((s) =>!isUploadMetaSegment(s))
.toList();
return segs.join(' • ');
}
