import '../domain/models.dart';
import 'track_matcher.dart';

/// Pengurai perintah suara berbasis aturan (F2 Batch 2, PRD 5.14 B) — tanpa
/// LLM, murni & teruji. Bahasa Indonesia & Inggris, pola terbatas.
/// Ketidakpastian TIDAK ditebak: skor dekat → tanya; keyakinan rendah →
/// minta ulangi (di layanan); tidak ditemukan → dikatakan apa adanya.
enum VoiceAction { play, addNext, addQueue, skip, pause, resume, unknown }

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
  if (t.startsWith('putar ')) {
    return (action: VoiceAction.play, query: rest('putar '));
  }
  if (t.startsWith('mainkan ')) {
    return (action: VoiceAction.play, query: rest('mainkan '));
  }
  if (t.startsWith('play ')) {
    return (action: VoiceAction.play, query: rest('play '));
  }
  if (t.startsWith('tambah ')) {
    var q = rest('tambah ');
    if (q.endsWith(' setelah ini')) {
      return (
        action: VoiceAction.addNext,
        query: q.substring(0, q.length - ' setelah ini'.length).trim()
      );
    }
    if (q.endsWith(' ke antrean') || q.endsWith(' ke antrian')) {
      final cut = q.endsWith(' ke antrean') ? ' ke antrean' : ' ke antrian';
      return (
        action: VoiceAction.addQueue,
        query: q.substring(0, q.length - cut.length).trim()
      );
    }
    return (action: VoiceAction.addQueue, query: q);
  }
  if (t.startsWith('add ')) {
    var q = rest('add ');
    if (q.endsWith(' after this')) {
      return (
        action: VoiceAction.addNext,
        query: q.substring(0, q.length - ' after this'.length).trim()
      );
    }
    if (q.endsWith(' to queue')) {
      return (
        action: VoiceAction.addQueue,
        query: q.substring(0, q.length - ' to queue'.length).trim()
      );
    }
    return (action: VoiceAction.addQueue, query: q);
  }
  if (t.startsWith('queue ')) {
    return (action: VoiceAction.addQueue, query: rest('queue '));
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
double voiceScore(String query, Track candidate,
    {bool liked = false, int plays = 0}) {
  final title = titleSimilarity(query, candidate.title);
  final artist = artistSimilarity(query, candidate.artistNames);
  var score = 0.7 * title + 0.3 * artist;
  if (liked) score += 0.05;
  if (plays > 0) score += 0.05;
  return score.clamp(0.0, 1.0);
}

/// Ambang: di bawah ini = tidak ditemukan; selisih 2 teratas di bawah ini = tanya.
const kVoiceAcceptThreshold = 0.35;
const kVoiceAmbiguityGap = 0.08;
