/// Pelacak sesi audio untuk higiene efek (Ronde Kresek, 2026-11-04) — logika
/// murni, teruji unit.
///
/// Cacat yang dijaga: instance Equalizer Android dibuat per audio-session-id
/// (Kotlin `eqFor`, getOrPut) dan TIDAK PERNAH di-release — setiap pergantian
/// session-id meninggalkan satu instance efek yatim yang menempel ke sesi
/// mati, dan Visualizer sesi lama juga tidak dihentikan. Di emulator
/// session-id terbukti stabil lintas ≥12 ganti lagu (id hanya berputar saat
/// pemain/AudioSink dibuat ulang penuh: stop, galat fatal, dispose), jadi
/// kebocorannya per-pembuatan-ulang-pemain — tetapi di perangkat nyata laju
/// putarannya belum terputuskan, dan satu-satunya perilaku yang benar adalah
/// MELEPAS efek sesi lama setiap kali sesi berganti.
///
/// Tracker ini memutuskan, untuk setiap peristiwa "sesi muncul" dari satu
/// pemain: sesi mana yang harus DITERAPI efek (selalu yang baru), sesi lama
/// mana yang harus DILEPAS (hanya bila benar-benar berganti), dan apakah
/// peristiwa ini kemunculan pertama pemain itu / pengulangan id yang sama /
/// pergantian — agar handler bisa mencatat bukti pembeda ke Log insiden.
class SessionFxDecision {
  /// Sesi yang harus diterapkan EQ + (bila normalisasi nyala) Visualizer.
  final int applyTo;

  /// Sesi lama yang harus dilepas (EQ release + Visualizer stop); null bila
  /// tidak ada pergantian nyata.
  final int? releasePrevious;

  /// Kemunculan pertama pemain ini sejak proses mulai.
  final bool isFirst;

  const SessionFxDecision({
    required this.applyTo,
    required this.releasePrevious,
    required this.isFirst,
  });

  /// Pergantian sesi nyata (ada sesi sebelumnya dan id-nya berbeda).
  bool get isChange => releasePrevious != null;
}

class SessionFxTracker {
  final Map<int, int> _byPlayer = {};

  /// Beri makan peristiwa sesi-muncul untuk [player] (0 = pemain utama,
  /// 1 = pemain silang crossfade). Id yang sama berulang BUKAN pergantian:
  /// tidak ada yang dilepas (menerapkan ulang efek ke sesi yang sama aman
  /// dan idempoten).
  SessionFxDecision onAppear(int player, int sessionId) {
    final prev = _byPlayer[player];
    if (prev == null) {
      _byPlayer[player] = sessionId;
      return SessionFxDecision(
        applyTo: sessionId,
        releasePrevious: null,
        isFirst: true,
      );
    }
    if (prev == sessionId) {
      return SessionFxDecision(
        applyTo: sessionId,
        releasePrevious: null,
        isFirst: false,
      );
    }
    _byPlayer[player] = sessionId;
    return SessionFxDecision(
      applyTo: sessionId,
      releasePrevious: prev,
      isFirst: false,
    );
  }

  /// Sesi terakhir yang diketahui per pemain (untuk rilis massal saat
  /// handler berhenti / pemain dibuang).
  List<int> get knownSessionIds => _byPlayer.values.toList(growable: false);

  /// Lupakan satu pemain (pemain dibuang permanen); sesi terakhirnya tetap
  /// harus dilepas pemanggil lewat keputusan terakhirnya sendiri.
  void forget(int player) => _byPlayer.remove(player);

  /// Reset total (handler berhenti): pemanggil melepas [knownSessionIds]
  /// sebelum memanggil ini.
  void clear() => _byPlayer.clear();
}
