import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/app_db.dart';
import 'ambient_theme.dart';

/// Keadaan tema suasana yang diamati UI (immutable).
class AmbientState {
  final bool enabled;
  final AmbientStrength strength;
  final bool breathing;
  final bool reduceEffects;
  final AmbientPalette palette;

  /// Faktor modulasi alfa napas (1,0 = netral; pita 0,7–1,3).
  final double breathFactor;

  const AmbientState({
    required this.enabled,
    required this.strength,
    required this.breathing,
    required this.reduceEffects,
    required this.palette,
    required this.breathFactor,
  });

  static const initial = AmbientState(
    enabled: true,
    strength: AmbientStrength.hidup,
    breathing: true,
    reduceEffects: false,
    palette: AmbientPalette.inactive,
    breathFactor: 1.0,
  );

  AmbientState copyWith({
    bool? enabled,
    AmbientStrength? strength,
    bool? breathing,
    bool? reduceEffects,
    AmbientPalette? palette,
    double? breathFactor,
  }) =>
      AmbientState(
        enabled: enabled ?? this.enabled,
        strength: strength ?? this.strength,
        breathing: breathing ?? this.breathing,
        reduceEffects: reduceEffects ?? this.reduceEffects,
        palette: palette ?? this.palette,
        breathFactor: breathFactor ?? this.breathFactor,
      );

  @override
  bool operator ==(Object other) =>
      other is AmbientState &&
      other.enabled == enabled &&
      other.strength == strength &&
      other.breathing == breathing &&
      other.reduceEffects == reduceEffects &&
      other.palette == palette &&
      other.breathFactor == breathFactor;

  @override
  int get hashCode => Object.hash(
      enabled, strength, breathing, reduceEffects, palette, breathFactor);
}

/// Kontroler "Sampul Hidup" (DS v4.0 §5): pemilik tunggal keadaan tema
/// suasana. Pengaturan hidup sebagai pref DB (`ui.themeDynamic`,
/// `ui.ambientStrength`, `ui.ambientBreathing`, `ui.reduceEffects`) —
/// pola yang sama dengan sakelar lama `ui.dynamicAccent`.
///
/// Sumber tinta masuk lewat [setSource] (kunci trek + warna tanda
/// tangan sampulnya); [TintSettler] menahan ganti-cepat (anti-kedip),
/// detak 300 md memasang yang tertunda. Napas (U1) diberi makan RMS
/// Visualizer lewat [feedRms] oleh cangkang aplikasi.
class AmbientController extends StateNotifier<AmbientState> {
  final AppDb db;
  final TintSettler _settler = TintSettler();
  final BreathEnvelope _breath = BreathEnvelope();
  final Map<String, Color?> _sourceColors = {};
  Timer? _timer;
  DateTime? _lastFeedAt;
  bool _playing = false;

  // Instrumentasi napas (Ronde Player B): penghitung yang bisa dibaca
  // Layar Diagnostik agar rantai RMS→amplop→faktor bisa DIBUKTIKAN,
  // bukan ditebak — pelajaran rekaman datar ronde 8038, di mana tak
  // ada yang bisa membedakan "sampel tak sampai" dari "sampel hening".
  int rmsSeen = 0;
  int rmsFed = 0;
  double? rmsMinDb;
  double? rmsMaxDb;

  /// Level amplop & faktor saat ini (untuk Diagnostik).
  double get breathLevel => _breath.level;
  double get breathFactorNow => _breath.factor;

  AmbientController(this.db) : super(AmbientState.initial) {
    _loadPrefs();
    _timer = Timer.periodic(const Duration(milliseconds: 300), (_) => _tick());
  }

  Future<void> _loadPrefs() async {
    final enabled = await db.pref<bool>('ui.themeDynamic') ?? true;
    final strengthName = await db.pref<String>('ui.ambientStrength');
    final breathing = await db.pref<bool>('ui.ambientBreathing') ?? true;
    final reduce = await db.pref<bool>('ui.reduceEffects') ?? false;
    if (!mounted) return;
    state = state.copyWith(
      enabled: enabled,
      strength:
          strengthName == 'tenang' ? AmbientStrength.tenang : AmbientStrength.hidup,
      breathing: breathing,
      reduceEffects: reduce,
    );
    _rebuildPalette();
  }

  void _tick() {
    final committed = _settler.tick(DateTime.now());
    if (committed != null) _rebuildPalette();
    // Napas meluruh saat tidak ada umpan segar (jeda / Visualizer mati).
    if (!_playing || !state.breathing || !state.enabled || state.reduceEffects) {
      _breath.decay(const Duration(milliseconds: 300));
      _publishBreath();
    }
  }

  void _rebuildPalette() {
    final key = _settler.committedKey;
    final source = key == null ? null : _sourceColors[key];
    state = state.copyWith(
      palette: buildAmbientPalette(
        source: source,
        enabled: state.enabled,
        strength: state.strength,
      ),
    );
  }

  /// Trek aktif berubah: daftarkan warna tanda tangan sampulnya (null =
  /// tanpa sampul → palet tidak aktif sampai ada sumber berwarna).
  void setSource(String key, Color? sourceColor) {
    _sourceColors[key] = sourceColor;
    final commitNow = _settler.onSource(key, DateTime.now());
    if (commitNow != null) _rebuildPalette();
  }

  /// Umpan RMS dari Visualizer (dipanggil cangkang; murah & aman sering).
  void feedRms(double rmsDb, {required bool playing}) {
    _playing = playing;
    rmsSeen++;
    if (rmsMinDb == null || rmsDb < rmsMinDb!) rmsMinDb = rmsDb;
    if (rmsMaxDb == null || rmsDb > rmsMaxDb!) rmsMaxDb = rmsDb;
    if (!state.enabled || !state.breathing || state.reduceEffects || !playing) {
      return;
    }
    final now = DateTime.now();
    final rawDt = _lastFeedAt == null
        ? const Duration(milliseconds: 100)
        : now.difference(_lastFeedAt!);
    _lastFeedAt = now;
    // Jeda panjang (buffering dsb.) TIDAK membuang sampel lagi: dt
    // dijepit oleh breathFeedDt dan laju amplop sendiri yang menjaga
    // permukaan tak melompat (lihat komentar di ambient_theme.dart —
    // penjaga buang lama adalah akar rekaman datar ronde 8038).
    _breath.feed(rmsDb, breathFeedDt(rawDt));
    rmsFed++;
    _publishBreath();
  }

  void _publishBreath() {
    final s = _breath.factor;
    if ((s - state.breathFactor).abs() > 0.004) {
      state = state.copyWith(breathFactor: s);
    }
  }

  Future<void> setEnabled(bool v) async {
    state = state.copyWith(enabled: v);
    if (!v) _settler.reset();
    _rebuildPalette();
    await db.setPref('ui.themeDynamic', v);
  }

  Future<void> setStrength(AmbientStrength s) async {
    state = state.copyWith(strength: s);
    _rebuildPalette();
    await db.setPref('ui.ambientStrength', s.name);
  }

  Future<void> setBreathing(bool v) async {
    state = state.copyWith(breathing: v);
    await db.setPref('ui.ambientBreathing', v);
  }

  Future<void> setReduceEffects(bool v) async {
    state = state.copyWith(reduceEffects: v);
    await db.setPref('ui.reduceEffects', v);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
