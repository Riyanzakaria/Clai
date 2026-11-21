import 'dart:math' as math;

import '../domain/models.dart';
import 'track_matcher.dart';

/// Pengurai perintah suara berbasis aturan (F2 Batch 2, PRD 5.14 B) — tanpa
/// LLM, murni & teruji. Bahasa Indonesia & Inggris, pola terbatas.
/// Ketidakpastian TIDAK ditebak: skor dekat → tanya; keyakinan rendah →
/// minta ulangi (di layanan); tidak ditemukan → dikatakan apa adanya.
enum VoiceAction { play, addNext, addQueue, skip, pause, resume, unknown }

/// Kata pengisi ujung-depan kueri: "putar LAGU sway" — kata "lagu" di sini
/// kata benda umum, bukan bagian judul (Ronde 8065).
const _kVoiceFillerHeads = {'lagu', 'berjudul'};

/// Kata pengisi ujung-belakang kueri: "... dong", "... aja", "... nya".
const _kVoiceFillerTails = {'dong', 'aja', 'saja', 'nya', 'yang'};

/// Bersihkan kueri hasil urai dari kata pengisi (murni, Ronde 8065):
/// "lagu sway" → "sway", "sway dong" → "sway", "sway nya" → "sway".
/// Pengisi hanya dibuang di UJUNG (depan/belakang) dan tidak pernah sampai
/// menghabiskan kueri yang masih menyisakan kata lain — kecuali kueri yang
/// seluruhnya kata pengisi ("lagu") yang memang bukan judul → ''.
String cleanVoiceQuery(String raw) {
  final words = raw
      .toLowerCase()
      .trim()
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .toList();
  while (words.length > 1 && _kVoiceFillerHeads.contains(words.first)) {
    words.removeAt(0);
  }
  while (words.length > 1 && _kVoiceFillerTails.contains(words.last)) {
    words.removeLast();
  }
  if (words.length == 1 && _kVoiceFillerHeads.contains(words.single)) {
    return '';
  }
  return words.join(' ');
}

({VoiceAction action, String query}) parseVoiceCommand(String raw) {
  var t = raw.toLowerCase().trim();
  t = t.replaceAll(RegExp(r'[.?!]+$'), '').trim();
  if (t.isEmpty) return (action: VoiceAction.unknown, query: '');

  // Aksi tanpa argumen (cocokkan persis dulu — "putar lagi" = lanjut, bukan putar X).
  switch (t) {
    case 'lewati':
    case 'lewat':
    case 'selanjutnya':
    case 'lagu berikutnya':
    case 'skip':
    case 'next':
      return (action: VoiceAction.skip, query: '');
    case 'jeda':
    case 'berhenti sebentar':
    case 'pause':
      return (action: VoiceAction.pause, query: '');
    case 'lanjut':
    case 'lanjutkan':
    case 'putar lagi':
    case 'resume':
    case 'continue':
      return (action: VoiceAction.resume, query: '');
  }

  String rest(String prefix) => t.substring(prefix.length).trim();
  // Semua kueri berkata-kerja melewati cleanVoiceQuery (Ronde 8065):
  // kata pengisi ujung dibuang di satu titik ini, bukan per cabang.
  if (t.startsWith('putar ')) {
    return (action: VoiceAction.play, query: cleanVoiceQuery(rest('putar ')));
  }
  if (t.startsWith('putarin ')) {
    return (
      action: VoiceAction.play,
      query: cleanVoiceQuery(rest('putarin '))
    );
  }
  if (t.startsWith('putarkan ')) {
    return (
      action: VoiceAction.play,
      query: cleanVoiceQuery(rest('putarkan '))
    );
  }
  if (t.startsWith('mainkan ')) {
    return (
      action: VoiceAction.play,
      query: cleanVoiceQuery(rest('mainkan '))
    );
  }
  if (t.startsWith('play ')) {
    return (action: VoiceAction.play, query: cleanVoiceQuery(rest('play ')));
  }
  if (t.startsWith('ganti ke ')) {
    return (
      action: VoiceAction.play,
      query: cleanVoiceQuery(rest('ganti ke '))
    );
  }
  if (t.startsWith('pindah ke ')) {
    return (
      action: VoiceAction.play,
      query: cleanVoiceQuery(rest('pindah ke '))
    );
  }
  if (t.startsWith('tambah ')) {
    var q = rest('tambah ');
    if (q.endsWith(' setelah ini')) {
      return (
        action: VoiceAction.addNext,
        query: cleanVoiceQuery(
            q.substring(0, q.length - ' setelah ini'.length).trim())
      );
    }
    if (q.endsWith(' ke antrean') || q.endsWith(' ke antrian')) {
      final cut = q.endsWith(' ke antrean') ? ' ke antrean' : ' ke antrian';
      return (
        action: VoiceAction.addQueue,
        query: cleanVoiceQuery(q.substring(0, q.length - cut.length).trim())
      );
    }
    return (action: VoiceAction.addQueue, query: cleanVoiceQuery(q));
  }
  if (t.startsWith('add ')) {
    var q = rest('add ');
    if (q.endsWith(' after this')) {
      return (
        action: VoiceAction.addNext,
        query: cleanVoiceQuery(
            q.substring(0, q.length - ' after this'.length).trim())
      );
    }
    if (q.endsWith(' to queue')) {
      return (
        action: VoiceAction.addQueue,
        query:
            cleanVoiceQuery(q.substring(0, q.length - ' to queue'.length).trim())
      );
    }
    return (action: VoiceAction.addQueue, query: cleanVoiceQuery(q));
  }
  if (t.startsWith('queue ')) {
    return (
      action: VoiceAction.addQueue,
      query: cleanVoiceQuery(rest('queue '))
    );
  }
  return (action: VoiceAction.unknown, query: '');
}

/// Jawaban atas pertanyaan "maksudmu A atau B?": 0/1, -1 = batal, null = bukan jawaban.
int? parseChoiceAnswer(String raw) {
  final t = raw.toLowerCase().trim();
  switch (t) {
    case 'yang pertama':
    case 'pertama':
    case 'nomor satu':
    case 'satu':
    case 'first':
    case 'number one':
    case 'one':
      return 0;
    case 'yang kedua':
    case 'kedua':
    case 'nomor dua':
    case 'dua':
    case 'second':
    case 'number two':
    case 'two':
      return 1;
    case 'batal':
    case 'cancel':
      return -1;
  }
  return null;
}

/// Skor kandidat suara (0..1): kemiripan judul dominan + artis + penguat
/// riwayat (disukai/diputar sebelumnya). Ambang terima & ambang tanya di layanan.
///
/// Ronde 8065: kemiripan memakai varian DIPERKUAT (rapat-spasi + toleransi
/// edit) dan konteks lebih berbobot — disukai +0.10, riwayat putar
/// +0.05/putar dibatasi +0.10 — agar lagu yang memang milik pengguna
/// memenangkan seri melawan judul kembar milik orang asing.
double voiceScore(String query, Track candidate,
    {bool liked = false, int plays = 0}) {
  final title = fuzzyTitleSimilarity(query, candidate.title);
  final artist = fuzzyArtistSimilarity(query, candidate.artistNames);
  var score = 0.7 * title + 0.3 * artist;
  if (liked) score += 0.10;
  if (plays > 0) score += math.min(plays * 0.05, 0.10);
  return score.clamp(0.0, 1.0);
}

/// Ambang: di bawah ini = tidak ditemukan; selisih 2 teratas di bawah ini = tanya.
const kVoiceAcceptThreshold = 0.35;
const kVoiceAmbiguityGap = 0.08;

/// Aksi yang MEMBAWA kueri (putar/tambah) — satu-satunya aksi yang nasibnya
/// diputuskan skor pencocokan. Aksi tanpa argumen (lewati/jeda/lanjut) hasil
/// urai persis: tidak ada yang bisa "salah cocok" padanya.
bool voiceActionNeedsQuery(VoiceAction a) =>
    a == VoiceAction.play ||
    a == VoiceAction.addNext ||
    a == VoiceAction.addQueue;

/// Keputusan resolusi kueri dari skor kandidat yang SUDAH terurut menurun
/// (Ronde 8065, difaktorkan dari layanan agar teruji murni):
/// kosong/di bawah ambang → fail; dua teratas berskor dekat → askChoice;
/// selain itu → apply.
enum VoiceResolveDecision { apply, askChoice, fail }

VoiceResolveDecision decideVoiceResolution(List<double> scoresDesc) {
  if (scoresDesc.isEmpty) return VoiceResolveDecision.fail;
  if (scoresDesc.first < kVoiceAcceptThreshold) {
    return VoiceResolveDecision.fail;
  }
  if (scoresDesc.length > 1 &&
      (scoresDesc[0] - scoresDesc[1]).abs() < kVoiceAmbiguityGap) {
    return VoiceResolveDecision.askChoice;
  }
  return VoiceResolveDecision.apply;
}

/// Bunyi kegagalan resolusi kueri (Ronde 8065). Kebijakan baru: keyakinan
/// pengenal BUKAN veto — perintah tetap diurai dan dicocokkan dulu.
/// Keyakinan rendah hanya mengubah BUNYI kegagalan pencocokan menjadi
/// ajakan mengulangi (pengenal mungkin memang salah dengar), dan sesudah
/// [kMaxVoiceRepeats] ajakan berturut-turut, menyerah sopan.
enum VoiceFailureWording { specific, askRepeat, giveUp }

/// Maksimum ajakan mengulangi berturut-turut sebelum menyerah (PRD 5.14B).
const kMaxVoiceRepeats = 2;

/// [failedAttempts] = jumlah kegagalan berkeyakinan-rendah berturut
/// SEBELUM kegagalan ini (0 = kegagalan pertama).
VoiceFailureWording voiceFailureWording(
    {required bool lowConfidence, required int failedAttempts}) {
  if (!lowConfidence) return VoiceFailureWording.specific;
  return failedAttempts >= kMaxVoiceRepeats
      ? VoiceFailureWording.giveUp
      : VoiceFailureWording.askRepeat;
}

/// Kode galat pengenal dari string bawaan sisi asli ("kode 11" →
/// 11 = ERROR_SERVER_DISCONNECTED Android). Null bila tak ada angka.
int? voiceErrorCode(String error) {
  final m = RegExp(r'\d+').firstMatch(error);
  return m == null ? null : int.tryParse(m.group(0)!);
}
