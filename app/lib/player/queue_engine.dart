import 'dart:math';
import '../domain/models.dart';
import '../l10n/l10n.dart';
import 'smart_shuffle.dart';

enum RepeatMode { off, all, one }
enum ShuffleMode { off, pure, smart }

/// Konteks putar: daftar asal (album/playlist/cari/radio) + indeks awal (snapshot L-15).
class PlayContext {
  final String kind; // album|playlist|search|radio|local|liked|userPlaylist
  final String? id;
  final String label;
  final List<Track> tracks;
  const PlayContext({required this.kind, this.id, required this.label, required this.tracks});
}

/// Mesin antrean murni — implementasi aturan L-01…L-16 dari Phase 2, tanpa dependensi player.
/// Urutan efektif selalu: [sedang diputar] + Berikutnya (manual) + Lanjutan (konteks) + Putar Otomatis.
/// Antrean hanya boleh diubah lewat aktor serial di lapisan handler (L-08); kelas ini sendiri
/// adalah fungsi murni atas state agar logikanya teruji unit.
class QueueEngine {
  List<Track> manual = [];       // Berikutnya
  List<Track> continuation = []; // Lanjutan (sisa konteks sesudah indeks berjalan)
  List<Track> autoplay = [];     // Putar Otomatis
  /// Riwayat sesi: trek yang sudah dimainkan, urutan putar, tak termasuk
  /// [current]. Tanpa daftar ini gerak mundur pemutar (Sebelumnya) tak dapat
  /// diselaraskan — trek tujuan sudah terkonsumsi dari seksi antrean
  /// (temuan audit v4.4: UI desinkron dari pemutar, Sebelumnya tampak mati).
  List<Track> played = [];       // Riwayat sesi
  Track? current;
  PlayContext? context;
  List<Track> seeds = [];        // benih sesi (anti-drift PRD 5.4)
  RepeatMode repeat = RepeatMode.off;
  ShuffleMode shuffle = ShuffleMode.off;
  bool autoplayEnabled = true;   // pengaturan global
  bool autoplaySessionOn = true; // sakelar sesi di layar Antrian
  int version = 0;

  /// Penanda sesi putar (v4.4.2): naik setiap konteks manual baru dimulai
  /// (playContext/playRadio/restore). Handler menggunakannya untuk membuang
  /// batch isi ulang yang dihitung untuk sesi LAMA — batch basi tidak boleh
  /// mendarat di sesi baru (pencemaran antar-sesi).
  int sessionId = 0;

  /// Status isi ulang Putar Otomatis (v4.3) — ditulis handler, dibaca layar Antrian.
  /// Tanpa status ini, jeda jaringan saat sambungan disiapkan tampak seperti
  /// "daftar radio tidak ada di mana pun" (laporan perangkat v4.2).
  bool autoplayPreparing = false;
  bool autoplayRefillFailed = false;

  /// Sinyal sesi (L-06/L-07): kunci trek yang di-skip < 30 dtk (negatif) & selesai ≥80% (positif).
  final Set<TrackKey> skippedKeys = {};
  final Set<TrackKey> completedKeys = {};

  final Random _rng = Random();

  bool get hasCurrent => current != null;
  bool get autoplayActive => autoplayEnabled && autoplaySessionOn;

  /// Daftar efektif sesudah lagu berjalan (yang benar-benar akan diputar berurutan).
  List<Track> get effectiveQueue => [...manual, ...continuation, ...autoplay];

  /// Seluruh antrean termasuk yang berjalan, untuk sumber audio gabungan.
  List<Track> get fullQueue => current == null ? effectiveQueue : [current!, ...effectiveQueue];

  /// Indeks [track] di dalam fullQueue bila pengguna mengetuknya dari seksi antrean.
  int fullIndexOf(TrackKey k) => fullQueue.indexWhere((t) => t.key == k);

  // ---------------- perintah ----------------

  /// Memulai konteks baru (L-15): membuang antrean lama, menanam benih sesi.
  /// L-03: antrean manual TIDAK ikut dibuang — ia milik pengguna, bukan konteks.
  ///
  /// v4.4.3 (cacat jangkar Terakhir Diputar): benih sesi DIPUTAR mengitari
  /// indeks awal — trek yang benar-benar dipilih pengguna menjadi benih
  /// PERTAMA (jangkar label & isi ulang), sisa konteks mengikutinya sebagai
  /// benih pendamping. Versi lama menanam benih persis urutan daftar, sehingga
  /// mengetuk trek ke-2/ke-3 di rak Beranda (Terakhir Diputar/Putar Lagi)
  /// berjangkar ke trek pertama daftar itu — lagu sesi sebelumnya — walau
  /// konteksnya sendiri sudah berganti dengan benar.
  void playContext(PlayContext ctx, int startIndex) {
    final preservedManual = List<Track>.of(manual);
    final ordered = List<Track>.of(ctx.tracks);
    final start = ordered.isEmpty ? 0 : startIndex.clamp(0, ordered.length - 1);
    context = ctx;
    seeds = ordered.isEmpty
        ? []
        : [...ordered.sublist(start), ...ordered.sublist(0, start)];
    if (shuffle == ShuffleMode.pure && ordered.length > 1) {
      final first = ordered[start];
      final rest = List<Track>.of(ordered)..removeAt(start);
      rest.shuffle(_rng); // Fisher–Yates via Random; posisi lagu berjalan tetap (PRD 5.4)
      current = first;
      continuation = rest;
    } else if (shuffle == ShuffleMode.smart && ordered.length > 1) {
      // Smart Shuffle (F2): Lanjutan diurut cerdas (sebar artis, dorong favorit);
      // trek berjalan tetap yang diketuk, manual tak disentuh, isi tak berubah.
      final first = ordered[start];
      final rest = List<Track>.of(ordered)..removeAt(start);
      current = first;
      continuation = smartShuffleOrder(rest, likedKeys: _smartLiked, playCounts: _smartCounts);
    } else {
      // Konteks kosong (album/playlist tanpa trek yang bisa dimuat) TIDAK
      // boleh melempar — mesin mendarat di keadaan kosong yang jujur
      // (ditemukan Sapuan D-02 lewat uji cakupan: RangeError di baris ini).
      current = ordered.isEmpty ? null : ordered[start];
      continuation = ordered.isEmpty ? [] : ordered.sublist(start + 1);
    }
    manual = preservedManual;
    autoplay = [];
    played = [];
    // D-16 (Sapuan): sinyal sesi L-06/L-07 adalah milik SESI ini — konteks
    // baru = sesi baru. Sebelumnya skippedKeys/completedKeys bocor lintas
    // konteks (hanya resetSessionToCurrent yang membersihkannya), sehingga
    // selera sesi lama mencemari tangga kemiripan sesi berikutnya.
    skippedKeys.clear();
    completedKeys.clear();
    sessionId++;
    version++;
  }

  /// Radio dari satu lagu: konteks satu benih, sisanya diserahkan ke Putar Otomatis.
  /// D-17 (Sapuan): antrean manual DIPERTAHANKAN (L-03 berlaku untuk semua
  /// pergantian konteks, termasuk radio) — sebelumnya playRadio membuangnya
  /// senyap dengan `manual = []`.
  void playRadio(Track seed) {
    final preservedManual = List<Track>.of(manual);
    context = PlayContext(kind: 'radio', id: seed.id, label: 'Radio — ${seed.title}', tracks: [seed]);
    manual = preservedManual;
    seeds = [seed];
    current = seed;
    continuation = [];
    autoplay = [];
    played = [];
    skippedKeys.clear();
    completedKeys.clear();
    sessionId++;
    version++;
  }

  /// Indeks [k] di riwayat sesi (kejadian terakhir bila trek berulang).
  int playedIndexOf(TrackKey k) => played.lastIndexWhere((t) => t.key == k);

  /// Gerak mundur: jadikan trek riwayat ke-[playedIndex] sebagai current.
  /// Trek yang dimainkan sesudahnya + current lama kembali ke kepala Lanjutan
  /// dalam urutan putar semula, sehingga Maju mengulang langkah yang sama.
  /// (Trek manual yang sudah terlanjur dimainkan pulang sebagai Lanjutan —
  /// perbedaan seksi kosmetik, urutan putar yang dijaga.)
  void restorePlayed(int playedIndex) {
    if (playedIndex < 0 || playedIndex >= played.length) return;
    final target = played[playedIndex];
    final after = played.sublist(playedIndex + 1);
    played = played.sublist(0, playedIndex);
    continuation = [...after, if (current != null) current!, ...continuation];
    current = target;
    version++;
  }

  /// L-04: Putar Berikutnya menyisip di kepala Berikutnya; Tambah ke Antrian di ekornya.
  void enqueueNext(Track t) { manual.insert(0, t); version++; }
  void enqueueLater(Track t) { manual.add(t); version++; }

  Track? removeAt(List<Track> section, int index) {
    if (index < 0 || index >= section.length) return null;
    final t = section.removeAt(index);
    version++;
    return t;
  }

  void moveIn(List<Track> section, int from, int to) {
    if (from == to || from < 0 || from >= section.length || to < 0 || to >= section.length) return;
    final t = section.removeAt(from);
    section.insert(to, t);
    version++;
  }

  /// Sinyal selera untuk Smart Shuffle (diisi handler dari DB saat mode aktif):
  /// kunci disukai & hitungan putar. Dipakai playContext mode smart & applySmartShuffle.
  Set<TrackKey> _smartLiked = {};
  Map<TrackKey, int> _smartCounts = {};

  void setSmartSignals({Set<TrackKey>? likedKeys, Map<TrackKey, int>? playCounts}) {
    if (likedKeys != null) _smartLiked = likedKeys;
    if (playCounts != null) _smartCounts = playCounts;
  }

  /// Mengurut ulang Lanjutan yang sedang berjalan secara cerdas (sakelar Smart
  /// Shuffle dinyalakan di tengah sesi). Manual tidak disentuh; isi tidak berubah.
  void applySmartShuffle() {
    if (continuation.length <= 1) return;
    continuation = smartShuffleOrder(continuation, likedKeys: _smartLiked, playCounts: _smartCounts);
    version++;
  }

  void clearManual() { manual = []; version++; }

  /// Langkah maju khusus jalur crossfade (F2, ADR-002): mengambil trek
  /// berikutnya dari antrean efektif (manual → lanjutan → autoplay) dengan
  /// semantik yang sama seperti pemindahan alami di handler gapless — trek
  /// lama masuk riwayat sesi, trek baru menjadi current. Repeat-Semua atas
  /// konteks banyak trek mengulang dari awal; Repeat-Satu ditangani pemutar
  /// (loop), bukan di sini — kecuali [manualSkip] (tombol Next eksplisit
  /// selalu pindah, seperti jalur gapless). Null = tidak ada berikutnya.
  Track? takeNextForCrossfade({bool manualSkip = false}) {
    if (current == null) return null;
    if (repeat == RepeatMode.one && !manualSkip) return current;
    final upcoming = effectiveQueue;
    if (upcoming.isNotEmpty) {
      final old = current!;
      final next = _takeNext();
      played.add(old);
      current = next;
      version++;
      return next;
    }
    if (repeat == RepeatMode.all && context != null && context!.tracks.length > 1) {
      final old = current!;
      played.add(old);
      current = context!.tracks.first;
      continuation = context!.tracks.sublist(1);
      version++;
      return current;
    }
    return null;
  }

  /// Mode offline (F2): sisakan hanya trek yang bisa diputar tanpa jaringan
  /// (kunci [playable]) di manual/lanjutan/autoplay. Lagu yang sedang berjalan
  /// TIDAK disentuh — mode ini menyaring antrean, bukan memotong lagu yang
  /// sedang berbunyi. Mengembalikan jumlah trek yang disaring keluar.
  int retainOffline(Set<TrackKey> playable) {
    var removed = 0;
    int keep(List<Track> s) {
      final before = s.length;
      s.retainWhere((t) => playable.contains(t.key));
      return before - s.length;
    }
    removed += keep(manual);
    removed += keep(continuation);
    removed += keep(autoplay);
    if (removed > 0) version++;
    return removed;
  }
  void clearAutoplay() { autoplay = []; version++; }
  void clearAllUpcoming() { manual = []; continuation = []; autoplay = []; version++; }

  /// Bersihkan-semua-antrean = AKHIRI SESI (v4.4.3, keputusan pemilik):
  /// pengguna yang membuang seluruh antrean bermaksud mulai bersih, jadi
  /// jangkar lama tidak boleh menghantui sesi berikutnya. Benih sesi menjadi
  /// HANYA trek yang sedang berjalan; konteks menyusut menjadi konteks sesi
  /// trek-tunggal itu; riwayat & sinyal sesi (skip negatif, selesai positif)
  /// direset; [sessionId] naik agar batch isi ulang sesi lama yang masih
  /// terbang tertolak oleh penjaga handler. Menghapus SATU trek (removeAt)
  /// TIDAK memanggil ini — sesi berjalan terus.
  void resetSessionToCurrent() {
    final cur = current;
    manual = [];
    continuation = [];
    autoplay = [];
    seeds = cur == null ? [] : [cur];
    context = cur == null
        ? null
        : PlayContext(kind: 'session', id: cur.id, label: cur.title, tracks: [cur]);
    played = [];
    skippedKeys.clear();
    completedKeys.clear();
    autoplayPreparing = false;
    autoplayRefillFailed = false;
    sessionId++;
    version++;
  }

  /// Mengganti bagian Putar Otomatis (isi ulang L-05): 3 trek terdekat TIDAK pernah diganti.
  void appendAutoplay(List<Track> batch) {
    autoplay.addAll(batch);
    version++;
  }

  /// Catat durasi yang ditemukan PEMUTAR untuk trek [k] (v4.3): ganti objek trek
  /// di semua tempat ia hidup (berjalan, seksi-seksi, trek konteks) dengan salinan
  /// berdurasi. Mengembalikan true bila ada yang berubah.
  ///
  /// Akar cacat "durasi total hilang & tidak bisa seek": banyak trek sumber
  /// (item Song dari pencarian, item panel) tidak membawa durasi metadata,
  /// padahal ExoPlayer mengetahuinya dari wadah aliran sesudah memuat. UI hanya
  /// membaca durasi trek — tanpa pencatatan ini, total tampil "–" dan seekbar
  /// nonaktif walau lagunya terputar normal.
  bool noteDuration(TrackKey k, Duration d) {
    var changed = false;
    Track fix(Track t) {
      if (t.key == k && t.duration != d) { changed = true; return t.copyWith(duration: d); }
      return t;
    }
    if (current != null) current = fix(current!);
    manual = [for (final t in manual) fix(t)];
    continuation = [for (final t in continuation) fix(t)];
    autoplay = [for (final t in autoplay) fix(t)];
    final ctx = context;
    if (ctx != null) {
      for (var i = 0; i < ctx.tracks.length; i++) { ctx.tracks[i] = fix(ctx.tracks[i]); }
    }
    seeds = [for (final t in seeds) fix(t)];
    if (changed) version++;
    return changed;
  }

  /// F2: tempel sampul hasil pengayaan ke semua kemunculan trek (cermin noteDuration).
  bool noteArtwork(TrackKey k, String url) {
    var changed = false;
    Track fix(Track t) {
      if (t.key == k && t.artworkUrl == null) { changed = true; return t.copyWith(artworkUrl: url); }
      return t;
    }
    if (current != null) current = fix(current!);
    manual = [for (final t in manual) fix(t)];
    continuation = [for (final t in continuation) fix(t)];
    autoplay = [for (final t in autoplay) fix(t)];
    final ctx = context;
    if (ctx != null) {
      for (var i = 0; i < ctx.tracks.length; i++) { ctx.tracks[i] = fix(ctx.tracks[i]); }
    }
    seeds = [for (final t in seeds) fix(t)];
    played = [for (final t in played) fix(t)];
    if (changed) version++;
    return changed;
  }

  void setAutoplayBatch(List<Track> batch) {
    autoplay = List<Track>.of(batch);
    version++;
  }

  /// Perpindahan saat lagu selesai/lewati. Mengembalikan trek yang harus diputar berikutnya
  /// (null = berhenti; handler lalu meminta isi ulang otomatis dulu lewat [needsAutoplay]).
  /// Menghormati prioritas L-09: Repeat-Satu > manual > konteks/Repeat-Semua > Putar Otomatis.
  Track? advance({required bool byCompletion}) {
    if (current == null) return null;
    if (byCompletion && repeat == RepeatMode.one) return current; // putar ulang yang sama
    final upcoming = effectiveQueue;
    if (upcoming.isNotEmpty) {
      final next = _takeNext();
      current = next;
      version++;
      return next;
    }
    // Antrean efektif kosong:
    if (repeat == RepeatMode.all && context != null) {
      final ctxTracks = context!.tracks;
      if (ctxTracks.length > 1) {
        // Repeat-Semua mengulang konteks dari awal (L-09).
        final first = ctxTracks.first;
        current = first;
        continuation = ctxTracks.sublist(1);
        version++;
        return first;
      }
      // Konteks satu lagu + Repeat-Semua = Putar Otomatis (PRD 5.4).
      return null;
    }
    return null;
  }

  /// Lompat manual ke trek tertentu dalam antrean efektif (ketuk di layar Antrian).
  Track? jumpTo(TrackKey k) {
    // Cari di manual dulu, lalu continuation, lalu autoplay; yang mendahului dibuang (perilaku standar).
    bool cut(List<Track> s) {
      final i = s.indexWhere((t) => t.key == k);
      if (i < 0) return false;
      current = s[i];
      // item sebelum target di seksi yang sama dibuang; seksi sesudahnya: sisanya menjadi lanjutan alami.
      if (identical(s, manual)) {
        continuation = [...s.sublist(i + 1), ...continuation];
        manual = [];
      } else if (identical(s, continuation)) {
        continuation = s.sublist(i + 1);
      } else {
        autoplay = s.sublist(i + 1);
      }
      version++;
      return true;
    }
    if (cut(manual) || cut(continuation) || cut(autoplay)) return current;
    return null;
  }

  Track _takeNext() {
    if (manual.isNotEmpty) return manual.removeAt(0);
    if (continuation.isNotEmpty) return continuation.removeAt(0);
    return autoplay.removeAt(0);
  }

  /// Apakah isi ulang Putar Otomatis harus diminta sekarang (sisa efektif < 5, PRD 5.4).
  bool get needsAutoplayRefill => autoplayActive && current != null && effectiveQueue.length < 5 &&
      !(repeat == RepeatMode.all && (context?.tracks.length ?? 0) > 1);

  /// Kondisi pemicu akhir trek alami (cacat v4.4.2-2): trek berjalan adalah
  /// satu-satunya isi jendela dan tidak ada sambungan apa pun di antrean
  /// efektif, padahal Putar Otomatis aktif. Pada keadaan ini akhir trek alami
  /// WAJIB memicu isi ulang + lanjut otomatis — tanpa keadaan ini pemutar
  /// berhenti di trek pertama dan hanya Next manual / siklus sakelar yang
  /// bisa menghidupkannya (laporan pemilik).
  bool get starvedAtEnd => autoplayActive && current != null && effectiveQueue.isEmpty;

  /// Benih untuk isi ulang (PRD 5.4): jangkar anti-drift adalah benih sesi
  /// ASLI — trek awal yang dipilih pengguna selalu di depan (playContext
  /// memutar daftar benih mengitari indeks awal, v4.4.3). Trek yang pengguna biarkan
  /// SELESAI sesi ini (riwayat [played], terbaru dulu) ikut menjadi benih
  /// (sinyal positif ringan), lalu sisa benih konteks. Sambungan otomatis
  /// TIDAK pernah menjadi benih (tidak ada rantai drift). Maks 3 (anggaran
  /// tangga). Jangkar diatur ulang hanya oleh konteks manual baru
  /// (playContext/playRadio menanam ulang [seeds]).
  List<Track> refillSeeds() {
    if (seeds.isEmpty) return current == null ? const [] : [current!];
    final out = <Track>[seeds.first];
    void push(Track t) {
      if (out.length >= 3) return;
      if (!out.any((s) => s.key == t.key)) out.add(t);
    }
    for (final t in played.reversed) { push(t); }
    for (final s in seeds.skip(1)) { push(s); }
    return out;
  }

  /// Lagu selesai ≥80% (L-07 positif) / di-skip (negatif).
  void noteCompleted(Track t) => completedKeys.add(t.key);
  void noteSkipped(Track t) => skippedKeys.add(t.key);

  /// Serialisasi snapshot (L-16) — trek direferensikan kuncinya, direstorasi lewat katalog lokal.
  Map<String, Object?> snapshot({required int positionMs}) => {
        'contextKind': context?.kind, 'contextId': context?.id, 'contextLabel': context?.label,
        'seeds': seeds.map((t) => {'p': t.providerId, 'i': t.id}).toList(),
        'manual': manual.map((t) => {'p': t.providerId, 'i': t.id}).toList(),
        'continuation': continuation.map((t) => {'p': t.providerId, 'i': t.id}).toList(),
        'autoplay': autoplay.map((t) => {'p': t.providerId, 'i': t.id}).toList(),
        'played': played.map((t) => {'p': t.providerId, 'i': t.id}).toList(),
        'currentRef': current == null ? null : '${current!.providerId}|${current!.id}',
        'positionMs': positionMs,
        'shuffle': switch (shuffle) { ShuffleMode.pure => 'pure', ShuffleMode.smart => 'smart', ShuffleMode.off => 'off' },
        'repeat': repeat.name,
        'autoplayEnabled': autoplayEnabled,
        'signals': {
          'skipped': skippedKeys.map((k) => {'p': k.providerId, 'i': k.id}).toList(),
          'completed': completedKeys.map((k) => {'p': k.providerId, 'i': k.id}).toList(),
        },
      };

  static List<TrackKey> _keysOf(Object? raw) {
    if (raw is! List) return const [];
    return raw.map((e) => e is Map ? TrackKey(e['p'] as String, e['i'] as String) : null).whereType<TrackKey>().toList();
  }

  void restore(Map<String, Object?> snap, Map<TrackKey, Track> byKey) {
    Track? find(TrackKey k) => byKey[k];
    seeds = _keysOf(snap['seeds']).map(find).whereType<Track>().toList();
    manual = _keysOf(snap['manual']).map(find).whereType<Track>().toList();
    continuation = _keysOf(snap['continuation']).map(find).whereType<Track>().toList();
    autoplay = _keysOf(snap['autoplay']).map(find).whereType<Track>().toList();
    played = _keysOf(snap['played']).map(find).whereType<Track>().toList();
    final cur = snap['currentRef'] as String?;
    if (cur != null) {
      final parts = cur.split('|');
      if (parts.length >= 2) current = byKey[TrackKey(parts[0], parts.sublist(1).join('|'))];
    }
    context = seeds.isEmpty ? null : PlayContext(
        kind: (snap['contextKind'] as String?) ?? 'restored', id: snap['contextId'] as String?,
        label: (snap['contextLabel'] as String?) ?? l10n.ctxPreviousSession, tracks: seeds);
    shuffle = switch (snap['shuffle']) { 'pure' => ShuffleMode.pure, 'smart' => ShuffleMode.smart, _ => ShuffleMode.off };
    repeat = RepeatMode.values.asNameMap()[snap['repeat']] ?? RepeatMode.off;
    autoplayEnabled = snap['autoplayEnabled'] != false;
    sessionId++;
    final sig = snap['signals'];
    // D-16: pulihkan sinyal MILIK snapshot ini saja — bersihkan dulu agar
    // restore di atas mesin yang sudah hidup tidak mencampur dua sesi.
    skippedKeys.clear();
    completedKeys.clear();
    if (sig is Map) {
      skippedKeys.addAll(_keysOf(sig['skipped']));
      completedKeys.addAll(_keysOf(sig['completed']));
    }
    version++;
  }
}
