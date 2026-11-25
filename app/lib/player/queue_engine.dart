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
  const PlayContext({
    required this.kind,
    this.id,
    required this.label,
    required this.tracks,
  });
}

/// Mesin antrean murni — implementasi aturan L-01…L-16 dari Phase 2, tanpa dependensi player.
/// Urutan efektif selalu: [sedang diputar] + Berikutnya (manual) + Lanjutan (konteks) + Putar Otomatis.
/// Antrean hanya boleh diubah lewat aktor serial di lapisan handler (L-08); kelas ini sendiri
/// adalah fungsi murni atas state agar logikanya teruji unit.
class QueueEngine {
  List<Track> manual = []; // Berikutnya
  List<Track> continuation =
      []; // Lanjutan (sisa konteks sesudah indeks berjalan)
  List<Track> autoplay = []; // Putar Otomatis
  /// Riwayat sesi: trek yang sudah dimainkan, urutan putar, tak termasuk
  /// [current]. Tanpa daftar ini gerak mundur pemutar (Sebelumnya) tak dapat
  /// diselaraskan — trek tujuan sudah terkonsumsi dari seksi antrean
  /// (temuan audit v4.4: UI desinkron dari pemutar, Sebelumnya tampak mati).
  List<Track> played = []; // Riwayat sesi
  Track? current;
  PlayContext? context;
  List<Track> seeds = []; // benih sesi (anti-drift PRD 5.4)
  RepeatMode repeat = RepeatMode.off;
  ShuffleMode shuffle = ShuffleMode.off;
  bool autoplayEnabled = true; // pengaturan global
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

  // ---------------- Siklus Acak Jujur (Ronde 8075) ----------------
  // Fondasi panel Acak gabungan: SIKLUS TANPA-ULANG. Satu siklus =
  // satu putaran penuh atas semesta antrean sesi ini (konteks + manual
  // + isi ulang yang sudah mendarat). [_cyclePlayedKeys] = kunci yang
  // SUDAH menjadi lagu berjalan sejak siklus mulai; [_cycleSeenKeys] =
  // seluruh kunci yang pernah menjadi bagian semesta siklus (diputar +
  // berjalan + mengantre). Keduanya memberi makan garis progres panel
  // ("X dari Y sudah diputar") dan penjaga tahan-ulang pada pengurutan:
  // trek yang sudah terputar di siklus berjalan ditahan di ekor seksi
  // selama masih ada yang belum terputar — pengulangan hanya boleh
  // datang sesudah siklus tuntas atau atas perintah pengguna sendiri
  // (lompat/putar-ulang manual tidak pernah diblokir di sini).
  // Siklus dimulai ulang oleh: konteks baru (playContext/playRadio),
  // bungkus Repeat-Semua, resetSessionToCurrent, dan restore snapshot.
  final Set<TrackKey> _cyclePlayedKeys = {};
  final Set<TrackKey> _cycleSeenKeys = {};

  int get cyclePlayedCount => _cyclePlayedKeys.length;
  int get cycleTotalCount => _cycleSeenKeys.length;
  bool cycleHasPlayed(TrackKey k) => _cyclePlayedKeys.contains(k);

  /// Pintu pencatatan untuk jalur yang menetapkan [current] dari luar
  /// mesin (handler: _syncEngineTo, mulai-dari-diam). Jalur internal
  /// mesin mencatat lewat [_noteCycleCurrent] yang sama.
  void noteCycleCurrent() => _noteCycleCurrent();

  void _noteCycleCurrent() {
    final c = current;
    if (c == null) return;
    _cyclePlayedKeys.add(c.key);
    _cycleSeenKeys.add(c.key);
  }

  void _noteCycleSeen(Iterable<Track> tracks) {
    for (final t in tracks) {
      _cycleSeenKeys.add(t.key);
    }
  }

  /// Mulai siklus baru: yang sudah terputar = lagu berjalan saja;
  /// semesta = [universe] (bawaan: seluruh antrean penuh saat ini).
  void _beginCycle([Iterable<Track>? universe]) {
    _cyclePlayedKeys.clear();
    _cycleSeenKeys.clear();
    _noteCycleSeen(universe ?? fullQueue);
    _noteCycleCurrent();
  }

  /// Tahan-ulang: pisahkan [ordered] menjadi yang belum terputar di
  /// siklus ini (di depan, urutan relatif dipertahankan) dan yang sudah
  /// terputar (di ekor). No-op bila salah satu sisi kosong — termasuk
  /// saat semua sudah terputar (siklus tuntas: pengulangan sah).
  List<Track> _holdCycleRepeats(List<Track> ordered) {
    if (_cyclePlayedKeys.isEmpty || ordered.length <= 1) return ordered;
    final fresh = <Track>[];
    final repeats = <Track>[];
    for (final t in ordered) {
      (_cyclePlayedKeys.contains(t.key) ? repeats : fresh).add(t);
    }
    if (repeats.isEmpty || fresh.isEmpty) return ordered;
    return [...fresh, ...repeats];
  }

  final Random _rng = Random();

  bool get hasCurrent => current != null;
  bool get autoplayActive => autoplayEnabled && autoplaySessionOn;

  /// Daftar efektif sesudah lagu berjalan (yang benar-benar akan diputar berurutan).
  List<Track> get effectiveQueue => [...manual, ...continuation, ...autoplay];

  /// Seluruh antrean termasuk yang berjalan, untuk sumber audio gabungan.
  List<Track> get fullQueue =>
      current == null ? effectiveQueue : [current!, ...effectiveQueue];

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
    // Konteks baru = urutan alami baru: potret pra-cerdas sesi lama gugur
    // (cabang smart di bawah menanam potret milik konteks ini).
    _naturalContinuation = null;
    _naturalAutoplay = null;
    final preservedManual = List<Track>.of(manual);
    final ordered = List<Track>.of(ctx.tracks);
    final start = ordered.isEmpty ? 0 : startIndex.clamp(0, ordered.length - 1);
    // Siklus Jujur (Ronde 8075) dimulai bersama konteks: semesta =
    // trek konteks + manual yang dipertahankan; yang sudah terputar =
    // trek awal (ditandai SEBELUM pengurutan cabang di bawah, agar
    // duplikat trek awal di sisa daftar tertahan sebagai pengulangan).
    _cyclePlayedKeys.clear();
    _cycleSeenKeys.clear();
    _noteCycleSeen(ordered);
    _noteCycleSeen(preservedManual);
    if (ordered.isNotEmpty) _cyclePlayedKeys.add(ordered[start].key);
    context = ctx;
    seeds = ordered.isEmpty
        ? []
        : [...ordered.sublist(start), ...ordered.sublist(0, start)];
    if (shuffle == ShuffleMode.pure && ordered.length > 1) {
      // Fondasi Jujur (Ronde 8075): Fisher–Yates atas sisa daftar;
      // posisi lagu berjalan tetap (PRD 5.4). Potret urutan alami
      // DITANAM seperti mode cerdas — mematikan Acak kini memulihkan
      // urutan konteks persis untuk kedua mode (pure lama tidak
      // memotret sama sekali, jadi OFF-nya tidak memulihkan apa pun).
      final first = ordered[start];
      final rest = List<Track>.of(ordered)..removeAt(start);
      current = first;
      _naturalContinuation = rest.map((t) => t.key).toList();
      _naturalAutoplay = const [];
      continuation = _honestOrder(rest);
    } else if (shuffle == ShuffleMode.smart && ordered.length > 1) {
      // Smart Shuffle (F2): Lanjutan diurut cerdas (sebar artis, dorong
      // yang jarang diputar); trek berjalan tetap yang diketuk, manual
      // tak disentuh, isi tak berubah. Urutan alami (pra-cerdas) dicatat
      // agar mematikan mode mengembalikan urutan konteks persis
      // (Ronde 8066).
      final first = ordered[start];
      final rest = List<Track>.of(ordered)..removeAt(start);
      current = first;
      _naturalContinuation = rest.map((t) => t.key).toList();
      _naturalAutoplay = const [];
      continuation = _holdCycleRepeats(
        smartShuffleOrder(
          rest,
          likedKeys: _smartLiked,
          playCounts: _smartCounts,
        ),
      );
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
    _naturalContinuation = null;
    _naturalAutoplay = null;
    final preservedManual = List<Track>.of(manual);
    context = PlayContext(
      kind: 'radio',
      id: seed.id,
      label: 'Radio — ${seed.title}',
      tracks: [seed],
    );
    manual = preservedManual;
    seeds = [seed];
    current = seed;
    continuation = [];
    autoplay = [];
    played = [];
    skippedKeys.clear();
    completedKeys.clear();
    // Siklus Jujur: semesta awal = benih + manual yang dipertahankan;
    // isi ulang yang mendarat kemudian memperluas semesta (appendAutoplay).
    _beginCycle([seed, ...preservedManual]);
    sessionId++;
    version++;
  }

  /// Sesi radio dari HALAMAN Radio (F2.5): jangkar benih tetap lagu asal
  /// halaman ([seed] — anti-drift tidak berubah), tetapi trek yang diputar
  /// adalah item halaman yang diketuk pengguna ([page] pada [startIndex]).
  /// Daftar sesi = [seed, ...page]; lanjutan = item sesudah titik mulai,
  /// meniru semantik playContext (item sebelum titik mulai tidak ikut sesi
  /// ini). Antrean manual dipertahankan (D-17) dan sinyal sesi dibersihkan
  /// seperti pergantian konteks lain.
  void playRadioFromPage({
    required Track seed,
    required List<Track> page,
    required int startIndex,
  }) {
    _naturalContinuation = null;
    _naturalAutoplay = null;
    final preservedManual = List<Track>.of(manual);
    final all = [seed, ...page.where((t) => t.key != seed.key)];
    final startTrack = page.isEmpty
        ? seed
        : page[startIndex.clamp(0, page.length - 1)];
    context = PlayContext(
      kind: 'radio',
      id: seed.id,
      label: 'Radio — ${seed.title}',
      tracks: all,
    );
    manual = preservedManual;
    seeds = [seed];
    current = startTrack;
    final idx = all.indexWhere((t) => t.key == startTrack.key);
    continuation = idx >= 0 ? all.sublist(idx + 1) : [];
    autoplay = [];
    played = [];
    skippedKeys.clear();
    completedKeys.clear();
    _beginCycle([...all, ...preservedManual]);
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
    _noteCycleCurrent();
    version++;
  }

  /// L-04: Putar Berikutnya menyisip di kepala Berikutnya; Tambah ke Antrian di ekornya.
  void enqueueNext(Track t) {
    manual.insert(0, t);
    _noteCycleSeen([t]);
    version++;
  }

  void enqueueLater(Track t) {
    manual.add(t);
    _noteCycleSeen([t]);
    version++;
  }

  Track? removeAt(List<Track> section, int index) {
    if (index < 0 || index >= section.length) return null;
    final t = section.removeAt(index);
    version++;
    return t;
  }

  /// Daftar seksi berdasarkan nama handler ('manual' | 'continuation' |
  /// 'autoplay'); null untuk nama tak dikenal.
  List<Track>? sectionByName(String section) => switch (section) {
        'manual' => manual,
        'continuation' => continuation,
        'autoplay' => autoplay,
        _ => null,
      };

  /// Cabut SEMUA item berkunci [keys] dari [section] (Ronde Tambahan 2015,
  /// hapus massal mode pilih-banyak). Mengembalikan trek yang tercabut
  /// dalam urutan asalnya; urutan penyintas dipertahankan persis. Trek
  /// berjalan tidak pernah ada di seksi-seksi ini, jadi tak tersentuh.
  List<Track> removeAllKeys(List<Track> section, Set<TrackKey> keys) {
    if (keys.isEmpty) return const [];
    final removed = <Track>[];
    section.removeWhere((t) {
      if (keys.contains(t.key)) {
        removed.add(t);
        return true;
      }
      return false;
    });
    if (removed.isNotEmpty) version++;
    return removed;
  }

  /// Cabut satu item dari seksi bernama untuk DIPINDAHKAN (Ronde Tambahan
  /// 2015, menu konteks item antrean: "Putar Berikutnya"/"Tambah ke
  /// Antrian" atas item yang sudah di antrean = pindah, bukan salin).
  /// [index] adalah petunjuk dari tampilan; bila item di sana tidak lagi
  /// berkunci [key] (antrean bergeser selama lembar terbuka), cari kunci
  /// itu di seluruh seksi. Null bila seksi tak dikenal / kunci tak ada.
  /// Berbeda dari jalur hapus: TANPA sinyal negatif sesi untuk Putar
  /// Otomatis — memindahkan bukanlah menolak.
  Track? extractQueued(String section, int index, TrackKey key) {
    final list = sectionByName(section);
    if (list == null) return null;
    var at = index;
    if (at < 0 || at >= list.length || list[at].key != key) {
      at = list.indexWhere((t) => t.key == key);
    }
    if (at < 0) return null;
    final t = list.removeAt(at);
    version++;
    return t;
  }

  /// Tambah banyak di ekor Berikutnya sekaligus (Ronde Tambahan 2015,
  /// "Tambah ke antrean" halaman Radio atas seluruh daftar bangkitan).
  void enqueueAllLater(List<Track> tracks) {
    if (tracks.isEmpty) return;
    manual.addAll(tracks);
    _noteCycleSeen(tracks);
    version++;
  }

  void moveIn(List<Track> section, int from, int to) {
    if (from == to ||
        from < 0 ||
        from >= section.length ||
        to < 0 ||
        to >= section.length) {
      return;
    }
    final t = section.removeAt(from);
    section.insert(to, t);
    version++;
  }

  /// Sinyal selera untuk Smart Shuffle (diisi handler dari DB saat mode aktif):
  /// kunci disukai & hitungan putar. Dipakai playContext mode smart & applySmartShuffle.
  Set<TrackKey> _smartLiked = {};
  Map<TrackKey, int> _smartCounts = {};

  void setSmartSignals({
    Set<TrackKey>? likedKeys,
    Map<TrackKey, int>? playCounts,
  }) {
    if (likedKeys != null) _smartLiked = likedKeys;
    if (playCounts != null) _smartCounts = playCounts;
  }

  /// Potret urutan ALAMI (pra-cerdas) Lanjutan & Putar Otomatis sesi ini,
  /// diambil saat urutan cerdas pertama kali diterapkan (Ronde 8066).
  /// Mematikan Smart Shuffle mengembalikan urutan ini untuk trek yang
  /// masih ada; trek yang tiba sesudah potret diambil (isi ulang) tidak
  /// dikenal potret dan mempertahankan urutan relatifnya di ekor seksi.
  /// Null = tidak ada urutan cerdas yang sedang berlaku.
  List<TrackKey>? _naturalContinuation;
  List<TrackKey>? _naturalAutoplay;

  void _snapshotNaturalOrderIfNeeded() {
    _naturalContinuation ??= continuation.map((t) => t.key).toList();
    _naturalAutoplay ??= autoplay.map((t) => t.key).toList();
  }

  /// Mengurut ulang antrean efektif yang akan datang secara cerdas
  /// (sakelar Smart Shuffle dinyalakan di tengah sesi): Lanjutan DAN
  /// Putar Otomatis, masing-masing di dalam seksinya. Manual tidak
  /// disentuh (L-03, milik pengguna); isi tiap seksi tidak berubah —
  /// hanya urutan. (Ronde 8066: cakupan lama hanya-Lanjutan membuat
  /// sakelar no-op total pada antrean berbentuk Putar Otomatis — konteks
  /// satu trek + isi ulang — karena Lanjutan-nya kosong.)
  void applySmartShuffle() {
    _snapshotNaturalOrderIfNeeded();
    var changed = false;
    if (continuation.length > 1) {
      continuation = _holdCycleRepeats(
        smartShuffleOrder(
          continuation,
          likedKeys: _smartLiked,
          playCounts: _smartCounts,
        ),
      );
      changed = true;
    }
    if (autoplay.length > 1) {
      autoplay = _holdCycleRepeats(
        smartShuffleOrder(
          autoplay,
          likedKeys: _smartLiked,
          playCounts: _smartCounts,
        ),
      );
      changed = true;
    }
    if (changed) version++;
  }

  /// Urutan fondasi Jujur atas satu daftar: Fisher–Yates murni +
  /// tahan-ulang siklus. Inilah satu-satunya perbedaan Jujur dari acak
  /// biasa: urutannya permutasi acak, TETAPI trek yang sudah terputar
  /// di siklus berjalan tidak pernah dijadwalkan ulang selama masih
  /// ada yang belum terputar.
  List<Track> _honestOrder(List<Track> input, {int? seed}) {
    final out = List<Track>.of(input);
    if (out.length > 1) out.shuffle(seed == null ? _rng : Random(seed));
    return _holdCycleRepeats(out);
  }

  /// Terapkan fondasi Jujur ke antrean efektif yang akan datang
  /// (sakelar Acak dinyalakan di tengah sesi, atau turun dari Cerdas):
  /// Lanjutan DAN Putar Otomatis diacak Fisher–Yates di dalam seksinya
  /// masing-masing. Potret urutan alami ditanam lebih dulu (bila belum
  /// ada) agar OFF memulihkan urutan pra-acak persis — jaminan yang
  /// sama seperti mode cerdas (Ronde 8075; pure lama tidak punya ini).
  /// Manual tidak disentuh (L-03); lagu berjalan tidak berganti.
  void applyHonestShuffle({int? seed}) {
    _snapshotNaturalOrderIfNeeded();
    var changed = false;
    if (continuation.length > 1) {
      continuation = _honestOrder(continuation, seed: seed);
      changed = true;
    }
    if (autoplay.length > 1) {
      autoplay = _honestOrder(autoplay, seed: seed);
      changed = true;
    }
    if (changed) version++;
  }

  /// Acak-ulang sekali ketuk (panel Acak, Ronde 8075): urutkan ulang
  /// SISA antrean menurut mode yang sedang aktif (Cerdas → cerdas,
  /// Jujur → Fisher–Yates baru) tanpa mengganti lagu berjalan dan
  /// tanpa membuang potret urutan alami — OFF sesudah acak-ulang tetap
  /// memulihkan urutan asli sesi. No-op saat acak mati.
  void reshuffleUpcoming({int? seed}) {
    if (shuffle == ShuffleMode.smart) {
      applySmartShuffle();
    } else if (shuffle == ShuffleMode.pure) {
      applyHonestShuffle(seed: seed);
    }
  }

  /// Urutkan cerdas HANYA ekor Putar Otomatis mulai indeks [fromIndex]
  /// (batch isi ulang yang baru mendarat saat mode cerdas menyala, Ronde
  /// 8066): trek yang sudah antre tidak digeser sama sekali, batch baru
  /// tiba sudah tersebar. Dipanggil handler sesudah appendAutoplay.
  void smartOrderAutoplayTail(int fromIndex) {
    final from = fromIndex.clamp(0, autoplay.length);
    if (autoplay.length - from <= 1) return;
    autoplay = [
      ...autoplay.sublist(0, from),
      ..._holdCycleRepeats(
        smartShuffleOrder(
          autoplay.sublist(from),
          likedKeys: _smartLiked,
          playCounts: _smartCounts,
        ),
      ),
    ];
    version++;
  }

  /// Ekor isi ulang diurutkan fondasi Jujur (mode pure menyala, Ronde
  /// 8075): batch yang baru mendarat diacak Fisher–Yates di ekornya
  /// saja + tahan-ulang siklus — pasangan [smartOrderAutoplayTail]
  /// untuk mode cerdas. Trek yang sudah antre tidak digeser.
  void honestOrderAutoplayTail(int fromIndex) {
    final from = fromIndex.clamp(0, autoplay.length);
    if (autoplay.length - from <= 1) return;
    autoplay = [
      ...autoplay.sublist(0, from),
      ..._honestOrder(autoplay.sublist(from)),
    ];
    version++;
  }

  /// Kembalikan Lanjutan & Putar Otomatis ke urutan alami pra-cerdas
  /// (sakelar Smart Shuffle dimatikan, Ronde 8066). Trek yang sudah
  /// terkonsumsi/tercabut hilang dari potret begitu saja; trek yang tiba
  /// sesudah potret (isi ulang) mempertahankan urutan relatifnya di ekor
  /// seksinya. Manual tidak pernah ikut — ia tidak pernah diacak cerdas.
  /// No-op bila tidak ada potret (mode cerdas tidak sedang berlaku).
  void restoreSmartShuffleOrder() {
    final natC = _naturalContinuation;
    final natA = _naturalAutoplay;
    if (natC == null && natA == null) return;
    List<Track> restore(List<Track> section, List<TrackKey>? natural) {
      if (natural == null || section.length <= 1) return section;
      final rank = <TrackKey, int>{
        for (var i = 0; i < natural.length; i++) natural[i]: i,
      };
      final known = section.where((t) => rank.containsKey(t.key)).toList()
        ..sort((a, b) => rank[a.key]!.compareTo(rank[b.key]!));
      final unknown = section.where((t) => !rank.containsKey(t.key)).toList();
      return [...known, ...unknown];
    }

    final c = restore(continuation, natC);
    final a = restore(autoplay, natA);
    if (!identical(c, continuation) || !identical(a, autoplay)) {
      continuation = c;
      autoplay = a;
      version++;
    }
    _naturalContinuation = null;
    _naturalAutoplay = null;
  }

  void clearManual() {
    manual = [];
    version++;
  }

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
      _noteCycleCurrent();
      version++;
      return next;
    }
    if (repeat == RepeatMode.all &&
        context != null &&
        context!.tracks.length > 1) {
      final old = current!;
      played.add(old);
      return _wrapCycle();
    }
    return null;
  }

  /// Bungkus Repeat-Semua = SIKLUS BARU (Ronde 8075). Acak mati:
  /// perilaku warisan persis (konteks dari awal, urutan alami). Acak
  /// menyala: urutan siklus baru DITANAM menurut mode aktif atas
  /// seluruh trek konteks — versi lama membungkus ke urutan alami
  /// konteks, yang berarti pengulangan terjadwal sekaligus acak yang
  /// bocor di setiap bungkus. Potret alami ditanam ulang ke urutan
  /// konteks siklus baru agar OFF memulihkan urutan siklus itu, dan
  /// pencatatan siklus dimulai dari kepala siklus baru. Mengembalikan
  /// trek kepala siklus baru; pemanggil bertanggung jawab atas
  /// riwayat sesi (played) seperti sebelumnya.
  Track _wrapCycle() {
    final ctxTracks = context!.tracks;
    if (shuffle == ShuffleMode.off) {
      current = ctxTracks.first;
      continuation = ctxTracks.sublist(1);
      _beginCycle(ctxTracks);
    } else {
      final ordered = shuffle == ShuffleMode.smart
          ? smartShuffleOrder(
              List<Track>.of(ctxTracks),
              likedKeys: _smartLiked,
              playCounts: _smartCounts,
            )
          : _honestOrder(ctxTracks);
      // Batas siklus tidak boleh berbunyi sebagai pengulangan: lagu
      // yang BARU selesai (current saat ini) tidak boleh menjadi
      // kepala siklus baru bila ada kunci lain — tukar dengan kunci
      // berbeda pertama.
      final finishedKey = current?.key;
      if (finishedKey != null && ordered.length > 1 &&
          ordered.first.key == finishedKey) {
        final swapAt = ordered.indexWhere((t) => t.key != finishedKey);
        if (swapAt > 0) {
          final tmp = ordered[0];
          ordered[0] = ordered[swapAt];
          ordered[swapAt] = tmp;
        }
      }
      current = ordered.first;
      final natural = List<Track>.of(ctxTracks);
      final at = natural.indexWhere((t) => t.key == current!.key);
      if (at >= 0) natural.removeAt(at);
      _naturalContinuation = natural.map((t) => t.key).toList();
      _naturalAutoplay = const [];
      _cyclePlayedKeys.clear();
      _cycleSeenKeys.clear();
      _noteCycleSeen(ctxTracks);
      _noteCycleCurrent();
      continuation = _holdCycleRepeats(ordered.sublist(1));
    }
    version++;
    return current!;
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

  void clearAutoplay() {
    autoplay = [];
    version++;
  }

  void clearAllUpcoming() {
    manual = [];
    continuation = [];
    autoplay = [];
    version++;
  }

  /// Bersihkan-semua-antrean = AKHIRI SESI (v4.4.3, keputusan pemilik):
  /// pengguna yang membuang seluruh antrean bermaksud mulai bersih, jadi
  /// jangkar lama tidak boleh menghantui sesi berikutnya. Benih sesi menjadi
  /// HANYA trek yang sedang berjalan; konteks menyusut menjadi konteks sesi
  /// trek-tunggal itu; riwayat & sinyal sesi (skip negatif, selesai positif)
  /// direset; [sessionId] naik agar batch isi ulang sesi lama yang masih
  /// terbang tertolak oleh penjaga handler. Menghapus SATU trek (removeAt)
  /// TIDAK memanggil ini — sesi berjalan terus.
  void resetSessionToCurrent() {
    _naturalContinuation = null;
    _naturalAutoplay = null;
    final cur = current;
    manual = [];
    continuation = [];
    autoplay = [];
    seeds = cur == null ? [] : [cur];
    context = cur == null
        ? null
        : PlayContext(
            kind: 'session',
            id: cur.id,
            label: cur.title,
            tracks: [cur],
          );
    played = [];
    skippedKeys.clear();
    completedKeys.clear();
    autoplayPreparing = false;
    autoplayRefillFailed = false;
    // Siklus Jujur ikut mulai bersih: semesta = trek berjalan saja.
    _beginCycle();
    sessionId++;
    version++;
  }

  /// Mengganti bagian Putar Otomatis (isi ulang L-05): 3 trek terdekat TIDAK pernah diganti.
  void appendAutoplay(List<Track> batch) {
    autoplay.addAll(batch);
    // Isi ulang memperluas semesta siklus Jujur (Ronde 8075).
    _noteCycleSeen(batch);
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
      if (t.key == k && t.duration != d) {
        changed = true;
        return t.copyWith(duration: d);
      }
      return t;
    }

    if (current != null) current = fix(current!);
    manual = [for (final t in manual) fix(t)];
    continuation = [for (final t in continuation) fix(t)];
    autoplay = [for (final t in autoplay) fix(t)];
    final ctx = context;
    if (ctx != null) {
      for (var i = 0; i < ctx.tracks.length; i++) {
        ctx.tracks[i] = fix(ctx.tracks[i]);
      }
    }
    seeds = [for (final t in seeds) fix(t)];
    if (changed) version++;
    return changed;
  }

  /// F2: tempel sampul hasil pengayaan ke semua kemunculan trek (cermin noteDuration).
  bool noteArtwork(TrackKey k, String url) {
    var changed = false;
    Track fix(Track t) {
      if (t.key == k && t.artworkUrl == null) {
        changed = true;
        return t.copyWith(artworkUrl: url);
      }
      return t;
    }

    if (current != null) current = fix(current!);
    manual = [for (final t in manual) fix(t)];
    continuation = [for (final t in continuation) fix(t)];
    autoplay = [for (final t in autoplay) fix(t)];
    final ctx = context;
    if (ctx != null) {
      for (var i = 0; i < ctx.tracks.length; i++) {
        ctx.tracks[i] = fix(ctx.tracks[i]);
      }
    }
    seeds = [for (final t in seeds) fix(t)];
    played = [for (final t in played) fix(t)];
    if (changed) version++;
    return changed;
  }

  /// Ganti objek trek di semua daftar dengan salinan hasil penyembuhan
  /// metadata (artis/sampul yang tadinya kosong kini terisi). Mengembalikan
  /// true bila ada yang berubah. Antrean & posisi tidak disentuh — hanya
  /// objek trek berkunci sama yang ditukar.
  bool noteMetadata(Track healed) {
    var changed = false;
    Track fix(Track t) {
      if (t.key == healed.key &&
          (t.artistNames != healed.artistNames ||
              t.artworkUrl != healed.artworkUrl)) {
        changed = true;
        return healed;
      }
      return t;
    }

    if (current != null) current = fix(current!);
    manual = [for (final t in manual) fix(t)];
    continuation = [for (final t in continuation) fix(t)];
    autoplay = [for (final t in autoplay) fix(t)];
    final ctx = context;
    if (ctx != null) {
      for (var i = 0; i < ctx.tracks.length; i++) {
        ctx.tracks[i] = fix(ctx.tracks[i]);
      }
    }
    seeds = [for (final t in seeds) fix(t)];
    played = [for (final t in played) fix(t)];
    if (changed) version++;
    return changed;
  }

  void setAutoplayBatch(List<Track> batch) {
    autoplay = List<Track>.of(batch);
    _noteCycleSeen(batch);
    version++;
  }

  /// Perpindahan saat lagu selesai/lewati. Mengembalikan trek yang harus diputar berikutnya
  /// (null = berhenti; handler lalu meminta isi ulang otomatis dulu lewat [needsAutoplay]).
  /// Menghormati prioritas L-09: Repeat-Satu > manual > konteks/Repeat-Semua > Putar Otomatis.
  Track? advance({required bool byCompletion}) {
    if (current == null) return null;
    if (byCompletion && repeat == RepeatMode.one) {
      return current; // putar ulang yang sama
    }
    final upcoming = effectiveQueue;
    if (upcoming.isNotEmpty) {
      final next = _takeNext();
      current = next;
      _noteCycleCurrent();
      version++;
      return next;
    }
    // Antrean efektif kosong:
    if (repeat == RepeatMode.all && context != null) {
      final ctxTracks = context!.tracks;
      if (ctxTracks.length > 1) {
        // Repeat-Semua mengulang konteks = siklus baru (L-09, Ronde 8075).
        return _wrapCycle();
      }
      // Konteks satu lagu + Repeat-Semua = Putar Otomatis (PRD 5.4).
      return null;
    }
    return null;
  }

  /// Lompat manual ke trek tertentu dalam antrean efektif (ketuk di layar Antrian).
  Track? jumpTo(TrackKey k) {
    // Trek yang sedang berjalan saat lompatan terjadi SUDAH terputar sesi
    // ini: catat ke riwayat sebelum current diganti. Tanpa ini trek itu
    // hilang dari [played] (jalur maju alami & crossfade mencatatnya lewat
    // played.add(old)) sehingga isi-ulang Putar Otomatis boleh menawarkannya
    // lagi di sesi yang sama — cacat vonis perangkat T3 lengan E, terbukti
    // di emulator 2026-11-09 ("back to friends" kembali di batch isi-ulang
    // #2; log: riwayat dikecualikan 2, seharusnya 3).
    final outgoing = current;
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

    if (cut(manual) || cut(continuation) || cut(autoplay)) {
      if (outgoing != null &&
          outgoing.key != k &&
          (played.isEmpty || played.last.key != outgoing.key)) {
        played.add(outgoing);
      }
      _noteCycleCurrent();
      return current;
    }
    return null;
  }

  Track _takeNext() {
    if (manual.isNotEmpty) return manual.removeAt(0);
    if (continuation.isNotEmpty) return continuation.removeAt(0);
    return autoplay.removeAt(0);
  }

  /// Apakah isi ulang Putar Otomatis harus diminta sekarang (sisa efektif < 5, PRD 5.4).
  bool get needsAutoplayRefill =>
      autoplayActive &&
      current != null &&
      effectiveQueue.length < 5 &&
      !(repeat == RepeatMode.all && (context?.tracks.length ?? 0) > 1);

  /// Kondisi pemicu akhir trek alami (cacat v4.4.2-2): trek berjalan adalah
  /// satu-satunya isi jendela dan tidak ada sambungan apa pun di antrean
  /// efektif, padahal Putar Otomatis aktif. Pada keadaan ini akhir trek alami
  /// WAJIB memicu isi ulang + lanjut otomatis — tanpa keadaan ini pemutar
  /// berhenti di trek pertama dan hanya Next manual / siklus sakelar yang
  /// bisa menghidupkannya (laporan pemilik).
  bool get starvedAtEnd =>
      autoplayActive && current != null && effectiveQueue.isEmpty;

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

    for (final t in played.reversed) {
      push(t);
    }
    for (final s in seeds.skip(1)) {
      push(s);
    }
    return out;
  }

  /// Lagu selesai ≥80% (L-07 positif) / di-skip (negatif).
  void noteCompleted(Track t) => completedKeys.add(t.key);
  void noteSkipped(Track t) => skippedKeys.add(t.key);

  /// Serialisasi snapshot (L-16) — trek direferensikan kuncinya, direstorasi lewat katalog lokal.
  Map<String, Object?> snapshot({required int positionMs}) => {
    'contextKind': context?.kind,
    'contextId': context?.id,
    'contextLabel': context?.label,
    'seeds': seeds.map((t) => {'p': t.providerId, 'i': t.id}).toList(),
    'manual': manual.map((t) => {'p': t.providerId, 'i': t.id}).toList(),
    'continuation': continuation
        .map((t) => {'p': t.providerId, 'i': t.id})
        .toList(),
    'autoplay': autoplay.map((t) => {'p': t.providerId, 'i': t.id}).toList(),
    'played': played.map((t) => {'p': t.providerId, 'i': t.id}).toList(),
    // Ronde 8067: potret urutan alami IKUT diserialkan — tanpanya
    // restore() terpaksa mengosongkan potret, dan OFF sesudah start
    // dingin menjadi no-op permanen (vonis HP 20 Nov atas 8066).
    if (_naturalContinuation != null)
      'naturalContinuation': _naturalContinuation!
          .map((k) => {'p': k.providerId, 'i': k.id})
          .toList(),
    if (_naturalAutoplay != null)
      'naturalAutoplay': _naturalAutoplay!
          .map((k) => {'p': k.providerId, 'i': k.id})
          .toList(),
    // Ronde 8075: kunci yang sudah terputar di siklus Jujur berjalan —
    // tanpanya start dingin menghitung ulang siklus dari nol dan panel
    // boleh menjadwalkan ulang lagu yang baru saja diputar sesi ini.
    'cyclePlayed': _cyclePlayedKeys
        .map((k) => {'p': k.providerId, 'i': k.id})
        .toList(),
    'currentRef': current == null
        ? null
        : '${current!.providerId}|${current!.id}',
    'positionMs': positionMs,
    'shuffle': switch (shuffle) {
      ShuffleMode.pure => 'pure',
      ShuffleMode.smart => 'smart',
      ShuffleMode.off => 'off',
    },
    'repeat': repeat.name,
    'autoplayEnabled': autoplayEnabled,
    'signals': {
      'skipped': skippedKeys
          .map((k) => {'p': k.providerId, 'i': k.id})
          .toList(),
      'completed': completedKeys
          .map((k) => {'p': k.providerId, 'i': k.id})
          .toList(),
    },
  };

  static List<TrackKey> _keysOf(Object? raw) {
    if (raw is! List) return const [];
    // Defensif penuh (Ronde Bug Notifikasi): entri Map yang tak punya
    // 'p'/'i' String ikut DILEWATI — cast telanjang di sini adalah pelempar
    // TypeError yang membunuh restorasi snapshot beracun di setiap boot.
    return raw
        .map(
          (e) => (e is Map && e['p'] is String && e['i'] is String)
              ? TrackKey(e['p'] as String, e['i'] as String)
              : null,
        )
        .whereType<TrackKey>()
        .toList();
  }

  void restore(Map<String, Object?> snap, Map<TrackKey, Track> byKey) {
    // Siklus Jujur dibangun ulang di ekor restore (Ronde 8075);
    // kosongkan dulu agar cabang penerapan cerdas warisan di bawah
    // tidak membaca sisa siklus sesi sebelumnya.
    _cyclePlayedKeys.clear();
    _cycleSeenKeys.clear();
    Track? find(TrackKey k) => byKey[k];
    seeds = _keysOf(snap['seeds']).map(find).whereType<Track>().toList();
    manual = _keysOf(snap['manual']).map(find).whereType<Track>().toList();
    continuation = _keysOf(
      snap['continuation'],
    ).map(find).whereType<Track>().toList();
    autoplay = _keysOf(snap['autoplay']).map(find).whereType<Track>().toList();
    played = _keysOf(snap['played']).map(find).whereType<Track>().toList();
    final cur = snap['currentRef'] as String?;
    if (cur != null) {
      final parts = cur.split('|');
      if (parts.length >= 2) {
        current = byKey[TrackKey(parts[0], parts.sublist(1).join('|'))];
      }
    }
    context = seeds.isEmpty
        ? null
        : PlayContext(
            kind: (snap['contextKind'] as String?) ?? 'restored',
            id: snap['contextId'] as String?,
            label: (snap['contextLabel'] as String?) ?? l10n.ctxPreviousSession,
            tracks: seeds,
          );
    shuffle = switch (snap['shuffle']) {
      'pure' => ShuffleMode.pure,
      'smart' => ShuffleMode.smart,
      _ => ShuffleMode.off,
    };
    // Ronde 8067: potret urutan alami pra-cerdas. Snapshot 8067+
    // membawanya terserialkan → pulihkan apa adanya (urutan tersimpan
    // SUDAH urutan cerdas yang berlaku; jangan diterapkan ulang).
    // Snapshot warisan (8064/8066) tidak membawanya: bila mode pulih
    // adalah cerdas, tanam urutan pulih sebagai alas alami sesi ini
    // lalu terapkan urutan cerdas di atasnya — sakelar harus BEKERJA
    // dari keadaan terbawa ini: ON mengurut dari alas yang diketahui,
    // OFF kembali ke alas itu. (8066 mengosongkan potret di sini:
    // OFF sesudah pulih no-op senyap, dan ketukan ON berikutnya
    // menanam urutan cerdas sebagai "alami" — sakelar mati selama
    // sisa sesi; vonis HP 20 Nov 2026.)
    final natCRaw = snap['naturalContinuation'];
    final natARaw = snap['naturalAutoplay'];
    if (natCRaw is List && natARaw is List) {
      _naturalContinuation = _keysOf(natCRaw);
      _naturalAutoplay = _keysOf(natARaw);
    } else if (shuffle == ShuffleMode.smart) {
      _naturalContinuation = continuation.map((t) => t.key).toList();
      _naturalAutoplay = autoplay.map((t) => t.key).toList();
      applySmartShuffle();
    } else {
      _naturalContinuation = null;
      _naturalAutoplay = null;
    }
    repeat = RepeatMode.values.asNameMap()[snap['repeat']] ?? RepeatMode.off;
    autoplayEnabled = snap['autoplayEnabled'] != false;
    // Siklus Jujur (Ronde 8075): pulihkan himpunan terputar dari
    // snapshot; snapshot warisan (tanpa kolom ini) dibangun ulang dari
    // riwayat sesi + lagu berjalan — pendekatan terbaik yang tersedia
    // untuk sesi yang ditinggalkan build lama. Semesta dibangun ulang
    // dari seluruh isi snapshot.
    final cycleRaw = _keysOf(snap['cyclePlayed']);
    _cyclePlayedKeys
      ..clear()
      ..addAll(
        cycleRaw.isNotEmpty
            ? cycleRaw
            : [
                for (final t in played) t.key,
                if (current != null) current!.key,
              ],
      );
    _cycleSeenKeys
      ..clear()
      ..addAll(_cyclePlayedKeys)
      ..addAll(seeds.map((t) => t.key))
      ..addAll(manual.map((t) => t.key))
      ..addAll(continuation.map((t) => t.key))
      ..addAll(autoplay.map((t) => t.key))
      ..addAll(played.map((t) => t.key));
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
