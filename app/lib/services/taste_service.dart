import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../data/app_db.dart';
import '../domain/models.dart';
import '../domain/personal_rank.dart';
import '../domain/taste_mirror.dart';

/// Ruang Kendali Selera (Ronde 8074, Workstream D): satu pintu keadaan
/// selera pengguna — Mode Samaran, bobot rekomendasi, pengecualian, dan
/// bahan Cermin Selera. Semua keadaan persisten hidup di AppDb
/// (user_prefs + taste_exclusions); layanan ini hanya cermin hidupnya
/// untuk UI dan gerbang handler.
class TasteService extends ChangeNotifier {
  final AppDb db;
  final Dio _dio;
  TasteService(this.db, {Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 6),
              receiveTimeout: const Duration(seconds: 12),
              headers: {
                'User-Agent':
                    'Clai/1.0.0 ( https://github.com/Riyanzakaria/clai )',
                'Accept': 'application/json',
              },
            ));

  bool _loaded = false;
  bool get loaded => _loaded;

  bool _samaranOn = false;
  bool get samaranOn => _samaranOn;

  double _recentEmphasis = 1.0;
  double get recentEmphasis => _recentEmphasis;

  List<TasteExclusion> _exclusions = const [];
  List<TasteExclusion> get exclusions => _exclusions;

  Future<void> load() async {
    _samaranOn = await db.pref<bool>(AppDb.prefTasteSamaran) ?? false;
    _recentEmphasis = await db.tasteRecentEmphasis();
    _exclusions = await db.tasteExclusions();
    _loaded = true;
    notifyListeners();
  }

  Future<void> _reloadExclusions() async {
    _exclusions = await db.tasteExclusions();
    notifyListeners();
  }

  // ---------------- Mode Samaran ----------------

  Future<void> setSamaran(bool on) async {
    if (_samaranOn == on) return;
    _samaranOn = on;
    notifyListeners();
    await db.setPref(AppDb.prefTasteSamaran, on);
  }

  // ---------------- Bobot rekomendasi ----------------

  Future<void> setRecentEmphasis(double e) async {
    final v = e.clamp(0.0, 1.0).toDouble();
    if (_recentEmphasis == v) return;
    _recentEmphasis = v;
    notifyListeners();
    await db.setPref(AppDb.prefTasteRecentEmphasis, v);
  }

  // ---------------- Pengecualian ----------------

  Future<void> excludeArtist(String artistNames) async {
    final name = artistNames.trim();
    if (name.isEmpty) return;
    await db.addTasteExclusion(TasteExclusion(
      kind: 'artist',
      key: name,
      label: name,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    ));
    await _reloadExclusions();
  }

  Future<void> excludeTrack(Track t) async {
    await db.addTasteExclusion(TasteExclusion(
      kind: 'track',
      key: trackExclusionKey(t.providerId, t.id),
      label: t.title,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    ));
    await _reloadExclusions();
  }

  /// Urungkan satu pengecualian (baris dihapus; riwayat tidak pernah
  /// diubah, jadi pengaruhnya hilang seketika dan utuh).
  Future<void> undoExclusion(TasteExclusion e) async {
    await db.removeTasteExclusion(e.kind, e.key);
    await _reloadExclusions();
  }

  bool artistExcluded(String artistNames) =>
      isArtistExcluded(artistNames, _exclusions);

  bool trackExcluded(Track t) => isTrackExcluded(t, _exclusions);

  // ---------------- Reset ----------------

  /// Reset Selera penuh: data turunan selera dihapus AppDb dalam satu
  /// transaksi; keadaan hidup di sini diselaraskan sesudahnya.
  Future<void> resetTaste() async {
    await db.resetTaste();
    _recentEmphasis = 1.0;
    _exclusions = const [];
    notifyListeners();
  }

  // ---------------- Cermin Selera ----------------

  /// Bahan cermin: data pola (murni cap waktu) + artis teratas berbobot
  /// selera, TANPA yang dikeluarkan (cermin menampilkan selera yang
  /// sedang berlaku, bukan yang sudah dibuang pengguna).
  Future<({TasteMirrorData mirror, List<TasteArtistRank> topArtists})>
      mirrorData({int topLimit = 20}) async {
    final events = await db.allPlayEvents();
    final now = DateTime.now().millisecondsSinceEpoch;
    final mirror = computeTasteMirror(events: events, nowMs: now);
    final byArtist = await db.artistPlayTimestamps();
    final ranks = <TasteArtistRank>[
      for (final e in byArtist.entries)
        if (!isArtistExcluded(e.key, _exclusions))
          (
            name: e.key,
            count: e.value.length,
            score: tastePlayScore(e.value, now, _recentEmphasis),
            last: e.value.isEmpty
                ? 0
                : e.value.reduce((a, b) => a > b ? a : b),
          ),
    ];
    ranks.sort(
      (a, b) => compareHybridRank(
        scoreA: a.score,
        countA: a.count,
        lastPlayedA: a.last,
        scoreB: b.score,
        countB: b.count,
        lastPlayedB: b.last,
      ),
    );
    return (mirror: mirror, topArtists: ranks.take(topLimit).toList());
  }

  /// Sampul per artis untuk hero & peringkat Cermin Panggung
  /// (Ronde 8089) — lihat [AppDb.topTrackArtworkByArtist].
  Future<Map<String, String?>> topArtistCovers() =>
      db.topTrackArtworkByArtist();

  // ---------------- Tag genre MusicBrainz (perkiraan) ----------------

  static const _tagKind = 'mb-artist-tags';
  Future<void> _tagTail = Future<void>.value();
  DateTime _lastTagCall = DateTime.fromMillisecondsSinceEpoch(0);

  /// Tag genre artis dari MusicBrainz — PEMANIS OPSIONAL (keputusan
  /// BEDAH-F3 #3): tersimpan lokal di enrichment_cache, dilabeli
  /// perkiraan di UI. Gagal jaringan / tak ditemukan → daftar kosong
  /// (dan hasil negatif ikut tercache agar tidak menggedor server).
  /// MusicBrainz membatasi 1 permintaan/detik — panggilan diserialkan.
  Future<List<String>> genreTagsForArtist(String artistNames) {
    final run = _tagTail.then((_) => _genreTagsInner(artistNames));
    _tagTail = run.then((_) {}, onError: (_) {});
    return run;
  }

  Future<List<String>> _genreTagsInner(String artistNames) async {
    final name = primaryArtistNameOf(artistNames).trim();
    if (name.isEmpty) return const [];
    final key = name.toLowerCase();
    final cached = await db.enrichment(_tagKind, key);
    if (cached.exists) {
      if (cached.value == null) return const [];
      try {
        final v = jsonDecode(cached.value!);
        if (v is List) return [for (final t in v) t.toString()];
      } catch (_) {
        /* cache rusak: cari ulang di bawah */
      }
      return const [];
    }
    try {
      final wait =
          const Duration(seconds: 1) - DateTime.now().difference(_lastTagCall);
      if (wait > Duration.zero) await Future<void>.delayed(wait);
      _lastTagCall = DateTime.now();
      final res = await _dio.get<Map<String, dynamic>>(
        'https://musicbrainz.org/ws/2/artist/',
        queryParameters: {
          'query': 'artist:"${name.replaceAll('"', '')}"',
          'fmt': 'json',
          'limit': 1,
        },
        options: Options(validateStatus: (s) => s != null && s < 500),
      );
      final artists = res.data?['artists'];
      List<String> tags = const [];
      if (artists is List && artists.isNotEmpty) {
        final first = artists.first;
        if (first is Map && first['tags'] is List) {
          final raw = <({String name, int count})>[
            for (final t in first['tags'] as List)
              if (t is Map && t['name'] is String)
                (
                  name: t['name'] as String,
                  count: (t['count'] as num?)?.toInt() ?? 0,
                ),
          ];
          raw.sort((a, b) => b.count.compareTo(a.count));
          tags = [for (final t in raw.take(3)) t.name];
        }
      }
      await db.saveEnrichment(
          _tagKind, key, tags.isEmpty ? null : jsonEncode(tags));
      return tags;
    } catch (_) {
      // Gagal jaringan TIDAK dicache sebagai negatif — coba lagi nanti.
      return const [];
    }
  }
}

/// Satu baris peringkat artis untuk Cermin Selera.
typedef TasteArtistRank = ({
  String name,
  int count,
  double score,
  int last,
});
