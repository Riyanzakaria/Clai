import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app.dart';
import '../core/tokens.dart';
import '../services/audio_fx_service.dart';
import '../l10n/l10n.dart';
import '../services/observability.dart';
import 'widgets.dart';

/// Seksi EQ di Pengaturan (F2 Batch 2): Equalizer Android per sesi pemain
/// Clai. Perangkat tanpa efek → teks jujur, bukan sakelar pajangan.
/// Setelan tersimpan di pref dan diterapkan otomatis saat sesi audio baru
/// muncul (handler._applyEqToSession) — mengubah di sini juga menerapkannya
/// langsung ke sesi yang sedang berjalan bila ada.
class EqSection extends ConsumerStatefulWidget {
  const EqSection({super.key});
  @override
  ConsumerState<EqSection> createState() => _EqSectionState();
}

class _EqSectionState extends ConsumerState<EqSection> {
  final _fx = AudioFxService();
  bool? _supported;
  EqInfo? _info;
  bool _enabled = false;
  int _preset = -1;
  List<int> _bands = const [];
  StreamSubscription<int>? _sessionSub;
  bool _diagnosed = false;

  @override
  void initState() {
    super.initState();
    _load();
    // Sesi pertama muncul SELAGI Pengaturan terbuka (pengguna memutar lagu
    // dari mini player lalu kembali) → nilai ulang, jangan biarkan tampilan
    // "menunggu sesi" basi.
    _sessionSub =
        ref.read(audioHandlerProvider).audioSessionAppearances.listen((_) {
      if (mounted && _info == null && _supported != false) _load();
    });
  }

  @override
  void dispose() {
    _sessionSub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final db = ref.read(appDbProvider);
    final handler = ref.read(audioHandlerProvider);
    // F2 Batch 2.1 — keputusan ketersediaan dari PERCOBAAN NYATA pada sesi
    // pemain yang hidup (bukan probe sesi 0 seperti build 2005 yang keliru
    // menyatakan "tidak tersedia" di HP riyan):
    // - belum ada sesi → BUKAN "tidak tersedia"; keadaan menunggu sesi.
    // - ada sesi & eqInfo berhasil → tersedia.
    // - ada sesi & semua percobaan gagal → tidak tersedia + diagnosis
    //   terstruktur dicatat ke Log insiden.
    final liveIds =
        handler.audioSessionIds.whereType<int>().toList(growable: false);
    EqInfo? info;
    for (final id in liveIds) {
      info = await _fx.eqInfo(id);
      if (info != null) break;
    }
    var supported = true;
    if (liveIds.isNotEmpty && info == null) {
      supported = false;
      if (!_diagnosed) {
        _diagnosed = true;
        final diag = await _fx.eqDiagnose(liveIds.first);
        Observability.instance
            .log('eq-tak-tersedia', 'sesi ${liveIds.first}: $diag');
      }
    }
    final enabled = await db.pref<bool>('audiofx.enabled') ?? false;
    final preset = await db.pref<int>('audiofx.preset') ?? -1;
    _namedPreset = await db.pref<String>('audiofx.namedPreset');
    final bandsRaw = await db.pref<List>('audiofx.bands');
    final bands = bandsRaw == null
        ? <int>[]
        : bandsRaw.map((e) => (e as num).toInt()).toList();
    if (mounted) {
      setState(() {
        _supported = supported;
        _info = info;
        _enabled = enabled;
        _preset = preset;
        _bands = bands.isNotEmpty
            ? bands
            : (info?.bandLevels ?? const <int>[]);
      });
    }
  }

  Future<void> _applyCurrent() async {
    final handler = ref.read(audioHandlerProvider);
    for (final id in handler.audioSessionIds) {
      if (id != null) {
        await _fx.eqApply(
            sessionId: id,
            enabled: _enabled,
            preset: _preset,
            bandLevels: _bands);
      }
    }
  }

  Future<void> _save() async {
    final db = ref.read(appDbProvider);
    await db.setPref('audiofx.enabled', _enabled);
    await db.setPref('audiofx.preset', _preset);
    await db.setPref('audiofx.bands', _bands);
  }

  String? _namedPreset;

  /// Pola preset bernama PRD 5.4 (Sapuan D-29) dalam dB pada 5 titik jangkar
  /// (rendah → tinggi); dipetakan ke jumlah pita perangkat lewat interpolasi
  /// posisi — preset perangkat OEM tetap tersedia di dropdown di bawahnya.
  static const _namedPatterns = <String, List<double>>{
    'flat': [0, 0, 0, 0, 0],
    'bass': [6, 4, 2, 0, 0],
    'vocal': [-2, 0, 3, 4, 2],
    'acoustic': [3, 1, 0, 2, 3],
  };

  List<int> _patternBands(String name, EqInfo info) {
    final pattern = _namedPatterns[name]!;
    final n = info.bandCount;
    return List.generate(n, (i) {
      final frac = n <= 1 ? 0.0 : i / (n - 1);
      final pos = frac * (pattern.length - 1);
      final lo = pos.floor(), hi = pos.ceil();
      final v = lo == hi
          ? pattern[lo]
          : pattern[lo] + (pattern[hi] - pattern[lo]) * (pos - lo);
      return (v * 100).round().clamp(info.minLevel, info.maxLevel);
    });
  }

  Future<void> _applyNamedPreset(String name, EqInfo info) async {
    setState(() {
      _namedPreset = name;
      _preset = -1; // pola Clai = pita kustom, bukan preset perangkat
      _bands = _patternBands(name, info);
    });
    await _save();
    await ref.read(appDbProvider).setPref('audiofx.namedPreset', name);
    await _applyCurrent();
  }

  String _freqLabel(int hz) =>
      hz >= 1000 ? '${(hz / 1000).toStringAsFixed(1)} kHz' : '$hz Hz';

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    if (_supported == null) {
      return ListTile(
        title: Text(s.eqTitle, style: const TextStyle(color: ClaiColors.ink)),
        subtitle: Text(s.eqChecking,
            style: const TextStyle(color: ClaiColors.inkSecondary)),
      );
    }
    if (_supported == false) {
      return ListTile(
        title: Text(s.eqTitle, style: const TextStyle(color: ClaiColors.ink)),
        subtitle: Text(s.eqUnavailable,
            style: const TextStyle(color: ClaiColors.inkSecondary)),
      );
    }
    final info = _info;
    return Column(children: [
      SwitchListTile(
        title: Text(s.eqTitle, style: const TextStyle(color: ClaiColors.ink)),
        subtitle: Text(s.eqSubtitle,
            style: const TextStyle(color: ClaiColors.inkSecondary)),
        value: _enabled,
        activeThumbColor: ClaiColors.accent,
        onChanged: (v) async {
          setState(() => _enabled = v);
          await _save();
          await _applyCurrent();
        },
      ),
      if (info == null)
        ListTile(
          subtitle: Text(s.eqWaitingSession,
              style: const TextStyle(color: ClaiColors.inkSecondary)),
        ),
      if (info != null && _enabled) ...[
        // D-29: preset bernama PRD (Datar/Bass/Vokal/Akustik) sebagai pola
        // pita milik Clai — sebelumnya hanya preset perangkat/OEM yang ada.
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(s.eqNamedPresets, style: const TextStyle(color: ClaiColors.inkSecondary, fontSize: 13)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: [
              for (final e in {
                'flat': s.eqPresetFlat,
                'bass': s.eqPresetBass,
                'vocal': s.eqPresetVocal,
                'acoustic': s.eqPresetAcoustic,
              }.entries)
                ChoiceChip(
                  label: Text(e.value),
                  selected: _namedPreset == e.key,
                  onSelected: (_) => _applyNamedPreset(e.key, info),
                  selectedColor: ClaiColors.accent,
                  labelStyle: TextStyle(
                      color: _namedPreset == e.key ? ClaiColors.onAccent : ClaiColors.ink,
                      fontSize: 13, fontWeight: FontWeight.w500),
                  backgroundColor: ClaiColors.surface2, side: BorderSide.none,
                ),
            ]),
          ]),
        ),
        ListTile(
          title: Text(s.eqPreset, style: const TextStyle(color: ClaiColors.ink)),
          trailing: BoundedDropdown<int>(
            value: _preset >= 0 && _preset < info.presets.length ? _preset : -1,
            items: [
              DropdownMenuItem(value: -1, child: Text(s.eqCustom)),
              for (var i = 0; i < info.presets.length; i++)
                DropdownMenuItem(value: i, child: Text(info.presets[i])),
            ],
            onChanged: (v) async {
              if (v == null) return;
              setState(() => _preset = v);
              await _save();
              await _applyCurrent();
              // Baca ulang level hasil preset perangkat.
              final handler = ref.read(audioHandlerProvider);
              for (final id in handler.audioSessionIds) {
                if (id != null) {
                  final fresh = await _fx.eqInfo(id);
                  if (fresh != null && mounted) {
                    setState(() => _bands = fresh.bandLevels);
                  }
                  break;
                }
              }
            },
          ),
        ),
        for (var i = 0; i < info.bandCount; i++)
          ListTile(
            title: Text(
                s.eqBandLabel(_freqLabel(info.centerFreqHz.length > i ? info.centerFreqHz[i] : 0), ((_bands.length > i ? _bands[i] : 0) / 100).toStringAsFixed(1)),
                style: const TextStyle(color: ClaiColors.ink)),
            subtitle: Slider(
              value: ((_bands.length > i ? _bands[i] : 0).toDouble())
                  .clamp(info.minLevel.toDouble(), info.maxLevel.toDouble()),
              min: info.minLevel.toDouble(),
              max: info.maxLevel.toDouble(),
              divisions: ((info.maxLevel - info.minLevel) ~/ 100).clamp(1, 100),
              activeColor: ClaiColors.accent,
              onChanged: (v) {
                setState(() {
                  if (_bands.length <= i) {
                    _bands = List<int>.from(info.bandLevels);
                  }
                  _bands[i] = v.round();
                  _preset = -1;
                  _namedPreset = null; // geser manual = kustom (tersimpan via _save)
                });
              },
              onChangeEnd: (_) async {
                await _save();
                await _applyCurrent();
              },
            ),
          ),
      ],
    ]);
  }
}
