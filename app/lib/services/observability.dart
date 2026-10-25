/// Observabilitas lokal (PRD Bab 9 F1): log insiden di perangkat saja — tanpa telemetri, tanpa jaringan.
///
/// Sapuan D-04: log kini PERSISTEN. Sebelumnya entri hanya hidup di memori
/// (batas 200) — insiden yang membunuh proses adalah justru yang hilang,
/// dan angka crash-free Bab 3 tidak bisa diukur sama sekali. Kini setiap
/// entri juga ditulis ke tabel `incident_log` (lewat sink yang dipasang
/// bootstrap), entri lama dimuat kembali saat aplikasi mulai, dan retensi
/// dibatasi 500 entri tersimpan. Menulis log tidak boleh pernah gagal
/// melempar — semua jalur persisten dibungkus tangkapan senyap.
class Observability {
  Observability._();
  static final instance = Observability._();
  final List<({DateTime at, String kind, String detail})> entries = [];

  /// Sink persisten dipasang bootstrap sesudah basis data terbuka.
  Future<void> Function(String kind, String detail, int atMs)? _sink;

  /// Entri yang dicatat sebelum sink terpasang (fase awal mulai dingin)
  /// disimpan di sini lalu disiram ke basis data oleh [attachPersistence].
  final List<({int atMs, String kind, String detail})> _pending = [];

  void log(String kind, String detail) {
    final now = DateTime.now();
    entries.add((at: now, kind: kind, detail: detail));
    if (entries.length > 200) entries.removeRange(0, entries.length - 200);
    final sink = _sink;
    if (sink != null) {
      sink(kind, detail, now.millisecondsSinceEpoch)
          .then((_) {}, onError: (_) {/* log tidak boleh menjatuhkan aplikasi */});
    } else {
      _pending.add((atMs: now.millisecondsSinceEpoch, kind: kind, detail: detail));
      if (_pending.length > 200) _pending.removeRange(0, _pending.length - 200);
    }
  }

  /// Pasang sink persisten + muat entri tersimpan ke daftar memori agar
  /// layar Log menampilkan riwayat lintas proses, bukan hanya sesi ini.
  Future<void> attachPersistence({
    required Future<void> Function(String kind, String detail, int atMs) sink,
    required Future<List<({int at, String kind, String detail})>> Function() load,
  }) async {
    _sink = sink;
    try {
      final stored = await load();
      final merged = <({DateTime at, String kind, String detail})>[
        for (final e in stored) (at: DateTime.fromMillisecondsSinceEpoch(e.at), kind: e.kind, detail: e.detail),
        ...entries,
      ]..sort((a, b) => a.at.compareTo(b.at));
      entries
        ..clear()
        ..addAll(merged.length > 200 ? merged.sublist(merged.length - 200) : merged);
    } catch (_) {/* riwayat gagal dimuat: log sesi ini tetap jalan */}
    final pending = List.of(_pending);
    _pending.clear();
    for (final p in pending) {
      try {
        await sink(p.kind, p.detail, p.atMs);
      } catch (_) {/* entri awal yang gagal ditulis tidak menghalangi mulai */}
    }
  }
}
