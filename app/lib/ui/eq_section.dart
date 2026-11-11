import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../app.dart';
import '../core/clai_icons.dart';
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
  /// false = tata letak formulir di panel Pengaturan (terbangun);
  /// true = panggung layar penuh papan EQ Gelombang 2 (slider
  /// vertikal) untuk EqScreen. Mesin keadaan yang sama persis.
  final bool stage;
  const EqSection({super.key, this.stage = false});
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

  Future<void> _setEnabled(bool v) async {
    setState(() => _enabled = v);
    await _save();
    await _applyCurrent();
    if (!v) {
      // Ronde Kresek: EQ dimatikan = instance Equalizer DILEPAS,
      // bukan hanya di-disable (lihat catatan di sakelar formulir).
      final handler = ref.read(audioHandlerProvider);
      for (final id in handler.audioSessionIds) {
        if (id != null) await _fx.eqRelease(id);
      }
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
  bool _touchedCustom = false;

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
      _touchedCustom = false;
    });
    await _save();
    await ref.read(appDbProvider).setPref('audiofx.namedPreset', name);
    await _applyCurrent();
  }

  String _freqLabel(int hz) =>
      hz >= 1000 ? '${(hz / 1000).toStringAsFixed(1)} kHz' : '$hz Hz';

  @override
  Widget build(BuildContext context) {
    if (widget.stage) return _buildStage(context);
    return _buildForm(context);
  }

  Widget _buildForm(BuildContext context) {
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
        secondary: tonalIconBox(ClaiIcons.musicNote, size: 40, iconSize: 20),
        title: Text(s.eqTitle, style: const TextStyle(color: ClaiColors.ink)),
        subtitle: Text(s.eqSubtitle,
            style: const TextStyle(color: ClaiColors.inkSecondary)),
        value: _enabled,
        onChanged: _setEnabled,
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
        DropdownTile<int>(
          title: s.eqPreset,
          leading: tonalIconBox(ClaiIcons.sort, size: 40, iconSize: 20),
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
                  _touchedCustom = true;
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
  // ---------------------------------------------------------- panggung
  /// Tata letak layar penuh (EqScreen): kepala judul + sakelar induk,
  /// keterangan sesi, baris preset bernama + kata keadaan Kustom,
  /// panggung slider vertikal, panel preset perangkat, catatan kaki.
  /// Semua nilai dari EqInfo perangkat — jumlah pita & frekuensi
  /// tengah TIDAK dikunci ke contoh papan.
  Widget _buildStage(BuildContext context) {
    final s = context.l10n;
    final comma = Localizations.localeOf(context).languageCode == 'id';
    if (_supported == null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
        child: Text(s.eqChecking,
            style: const TextStyle(color: ClaiColors.inkSecondary)),
      );
    }
    if (_supported == false) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
        child: Text(s.eqUnavailable,
            style: const TextStyle(color: ClaiColors.inkSecondary, height: 1.45)),
      );
    }
    final info = _info;
    final customVisible = _touchedCustom ||
        (_namedPreset == null && _preset == -1 && _bands.any((b) => b != 0));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 12, 0),
          child: Row(children: [
            Expanded(child: Text(s.eqTitle, style: displayStyle(20))),
            Switch(value: _enabled, onChanged: _setEnabled),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 2, 20, 0),
          child: Text(s.eqSubtitle,
              style: const TextStyle(
                  color: ClaiColors.inkSecondary, fontSize: 13, height: 1.45)),
        ),
        if (info == null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: ClaiColors.surface1,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(s.eqWaitingSession,
                  style: const TextStyle(
                      color: ClaiColors.inkSecondary, height: 1.5)),
            ),
          )
        else ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
            child: Wrap(spacing: 8, runSpacing: 8, children: [
              for (final e in {
                'flat': s.eqPresetFlat,
                'bass': s.eqPresetBass,
                'vocal': s.eqPresetVocal,
                'acoustic': s.eqPresetAcoustic,
              }.entries)
                ChoiceChip(
                  label: Text(e.value),
                  selected: _namedPreset == e.key,
                  onSelected:
                      _enabled ? (_) => _applyNamedPreset(e.key, info) : null,
                  selectedColor: ClaiColors.accent,
                  labelStyle: TextStyle(
                      color: _namedPreset == e.key
                          ? ClaiColors.onAccent
                          : ClaiColors.ink,
                      fontSize: 13,
                      fontWeight: FontWeight.w500),
                  backgroundColor: ClaiColors.surface2,
                  side: BorderSide.none,
                ),
              if (customVisible)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  decoration: BoxDecoration(
                    border: Border.all(color: ClaiColors.accent, width: 1),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(s.eqCustom,
                      style: const TextStyle(
                          color: ClaiColors.accent,
                          fontSize: 13,
                          fontWeight: FontWeight.w500)),
                ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
            child: Container(
              padding: const EdgeInsets.fromLTRB(8, 20, 8, 16),
              decoration: BoxDecoration(
                color: ClaiColors.surface1,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Opacity(
                opacity: _enabled ? 1 : 0.45,
                child: _BandStage(
                  info: info,
                  bands: _bands,
                  enabled: _enabled,
                  commaDecimal: comma,
                  onDrag: (i, v) {
                    setState(() {
                      if (_bands.length <= i) {
                        _bands = List<int>.from(info.bandLevels);
                      }
                      _bands[i] = v;
                      _preset = -1;
                      _namedPreset = null;
                      _touchedCustom = true;
                    });
                  },
                  onDragEnd: () async {
                    await _save();
                    await _applyCurrent();
                  },
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
            child: Container(
              decoration: BoxDecoration(
                color: ClaiColors.surface1,
                borderRadius: BorderRadius.circular(20),
              ),
              clipBehavior: Clip.antiAlias,
              child: DropdownTile<int>(
                title: s.eqPreset,
                leading: tonalIconBox(ClaiIcons.sort, size: 40, iconSize: 20),
                value: _preset >= 0 && _preset < info.presets.length
                    ? _preset
                    : -1,
                items: [
                  DropdownMenuItem(value: -1, child: Text(s.eqCustom)),
                  for (var i = 0; i < info.presets.length; i++)
                    DropdownMenuItem(value: i, child: Text(info.presets[i])),
                ],
                onChanged: !_enabled
                    ? null
                    : (v) async {
                        if (v == null) return;
                        setState(() {
                          _preset = v;
                          _touchedCustom = false;
                        });
                        await _save();
                        await _applyCurrent();
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
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
            child: Text(s.eqWaitingSession,
                style: const TextStyle(
                    color: ClaiColors.inkFaint, fontSize: 12, height: 1.5)),
          ),
        ],
      ],
    );
  }
}


/// Panggung pita vertikal: kolom sama lebar per pita perangkat —
/// label dB tabular di atas (positif Volt), rel vertikal 220 dp dengan
/// isian Volt dari garis nol kontinu ke ibu jari, label frekuensi di
/// bawah. Nilai dibaca/ditulis dalam milibel persis seperti slider
/// formulir (langkah 100 mB), simpan+terapkan di akhir seretan.
class _BandStage extends StatelessWidget {
  final EqInfo info;
  final List<int> bands;
  final bool enabled;
  final bool commaDecimal;
  final void Function(int index, int valueMb) onDrag;
  final VoidCallback onDragEnd;
  const _BandStage({
    required this.info,
    required this.bands,
    required this.enabled,
    required this.commaDecimal,
    required this.onDrag,
    required this.onDragEnd,
  });

  static const double _trackH = 220;
  static const double _labelH = 20;

  String _dbLabel(int mb) {
    var t = (mb / 100).toStringAsFixed(1);
    if (commaDecimal) t = t.replaceAll('.', ',');
    return mb > 0 ? '+$t' : t;
  }

  String _freqLabel(int hz) {
    if (hz < 1000) return '$hz Hz';
    var t = (hz / 1000).toStringAsFixed(1);
    if (commaDecimal) t = t.replaceAll('.', ',');
    return '$t kHz';
  }

  @override
  Widget build(BuildContext context) {
    final range = (info.maxLevel - info.minLevel).toDouble();
    final zeroFrac =
        range <= 0 ? 0.5 : (info.maxLevel - 0) / range; // dari atas
    return Column(children: [
      SizedBox(
        height: _labelH + _trackH + 8 + 16,
        child: Stack(children: [
          // Garis nol kontinu melintasi semua kolom (±8 dp melewati
          // ujung rel pertama & terakhir lewat padding panel).
          Positioned(
            left: 0,
            right: 0,
            top: _labelH + zeroFrac * _trackH,
            child: Container(
                height: 1, color: Colors.white.withValues(alpha: 0.16)),
          ),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (var i = 0; i < info.bandCount; i++)
              Expanded(
                child: Column(children: [
                  SizedBox(
                    height: _labelH,
                    child: Text(
                      _dbLabel(bands.length > i ? bands[i] : 0),
                      style: TextStyle(
                        fontSize: 13,
                        fontFeatures: const [FontFeature.tabularFigures()],
                        color: enabled && (bands.length > i ? bands[i] : 0) > 0
                            ? ClaiColors.accent
                            : ClaiColors.inkSecondary,
                      ),
                    ),
                  ),
                  _VerticalBandTrack(
                    valueMb: bands.length > i ? bands[i] : 0,
                    minMb: info.minLevel,
                    maxMb: info.maxLevel,
                    height: _trackH,
                    enabled: enabled,
                    onDrag: enabled ? (v) => onDrag(i, v) : null,
                    onDragEnd: enabled ? onDragEnd : null,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _freqLabel(
                        info.centerFreqHz.length > i ? info.centerFreqHz[i] : 0),
                    style: const TextStyle(
                        fontSize: 11, color: ClaiColors.inkFaint),
                  ),
                ]),
              ),
          ]),
        ]),
      ),
    ]);
  }
}

class _VerticalBandTrack extends StatelessWidget {
  final int valueMb;
  final int minMb;
  final int maxMb;
  final double height;
  final bool enabled;
  final ValueChanged<int>? onDrag;
  final VoidCallback? onDragEnd;
  const _VerticalBandTrack({
    required this.valueMb,
    required this.minMb,
    required this.maxMb,
    required this.height,
    required this.enabled,
    required this.onDrag,
    required this.onDragEnd,
  });

  int _valueFromDy(double dy) {
    final range = (maxMb - minMb).toDouble();
    if (range <= 0) return valueMb;
    final frac = (dy / height).clamp(0.0, 1.0);
    final raw = maxMb - frac * range;
    final snapped = (raw / 100).round() * 100;
    return snapped.clamp(minMb, maxMb);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragStart:
          onDrag == null ? null : (d) => onDrag!(_valueFromDy(d.localPosition.dy)),
      onVerticalDragUpdate:
          onDrag == null ? null : (d) => onDrag!(_valueFromDy(d.localPosition.dy)),
      onVerticalDragEnd: onDragEnd == null ? null : (_) => onDragEnd!(),
      child: CustomPaint(
        size: Size(40, height),
        painter: _BandTrackPainter(
          valueMb: valueMb,
          minMb: minMb,
          maxMb: maxMb,
          enabled: enabled,
        ),
      ),
    );
  }
}

class _BandTrackPainter extends CustomPainter {
  final int valueMb;
  final int minMb;
  final int maxMb;
  final bool enabled;
  const _BandTrackPainter({
    required this.valueMb,
    required this.minMb,
    required this.maxMb,
    required this.enabled,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final range = (maxMb - minMb).toDouble();
    final zeroY = range <= 0 ? size.height / 2 : (maxMb / range) * size.height;
    final thumbY =
        range <= 0 ? zeroY : ((maxMb - valueMb) / range) * size.height;
    final cx = size.width / 2;
    final trackPaint = Paint()..color = ClaiColors.surface3;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(cx - 2, 0, 4, size.height), const Radius.circular(2)),
      trackPaint,
    );
    // Keadaan mati: isian + ibu jari ABU (spek papan), bukan Volt
    // yang sekadar diredupkan panel.
    final signalColor =
        enabled ? ClaiColors.accent : ClaiColors.inkSecondary;
    final fillPaint = Paint()..color = signalColor;
    final top = thumbY < zeroY ? thumbY : zeroY;
    final bottom = thumbY > zeroY ? thumbY : zeroY;
    if (bottom - top > 0.5) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(cx - 2, top, 4, bottom - top),
            const Radius.circular(2)),
        fillPaint,
      );
    }
    canvas.drawCircle(Offset(cx, thumbY), 13, Paint()..color = signalColor);
    canvas.drawCircle(Offset(cx, thumbY), 3,
        Paint()..color = enabled ? ClaiColors.onAccent : ClaiColors.base);
  }

  @override
  bool shouldRepaint(_BandTrackPainter old) =>
      old.valueMb != valueMb ||
      old.minMb != minMb ||
      old.maxMb != maxMb ||
      old.enabled != enabled;
}

/// Ubin sakelar Normalisasi — dipakai halaman Audio DAN layar EQ
/// (satu kendali, satu pref, dua permukaan; logika izin mikrofon
/// untuk pengukuran Visualizer sama persis seperti terbangun).
class NormalizationTile extends ConsumerStatefulWidget {
  const NormalizationTile({super.key});
  @override
  ConsumerState<NormalizationTile> createState() => _NormalizationTileState();
}

class _NormalizationTileState extends ConsumerState<NormalizationTile> {
  bool _norm = false;

  @override
  void initState() {
    super.initState();
    ref.read(appDbProvider).pref<bool>('playback.normalization').then((n) {
      if (mounted && n != null) setState(() => _norm = n);
    });
  }

  @override
  Widget build(BuildContext context) {
    final handler = ref.read(audioHandlerProvider);
    return SwitchListTile(
      secondary: tonalIconBox(ClaiIcons.gauge, size: 40, iconSize: 20),
      title: Text(context.l10n.setNormalization,
          style: const TextStyle(color: ClaiColors.ink)),
      subtitle: Text(context.l10n.setNormalizationSub,
          style: const TextStyle(color: ClaiColors.inkSecondary)),
      value: _norm,
      onChanged: (v) async {
        setState(() => _norm = v);
        if (v) {
          // Pengukuran memakai Visualizer Android, yang MEWAJIBKAN izin
          // mikrofon walau tidak merekam apa pun (F2 Batch 2.1).
          final st = await Permission.microphone.request();
          if (!st.isGranted && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(context.l10n.normMicSnack)));
          }
        }
        await handler.setNormalization(v);
      },
    );
  }
}
