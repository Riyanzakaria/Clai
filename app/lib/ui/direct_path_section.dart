/// Bagian DIRECT-1 di Diagnostik Putar (Tahap 3): kesehatan jalur
/// resolver produksi dari DATA (statistik [DirectPathStats] + log insiden
/// `direct-*`), sakelar kill-switch, penyegar sesi, mode sabotase untuk
/// pementasan bukti penolakan 403, dan perbandingan byte DIRECT vs
/// muxed untuk trek terakhir. Permukaan internal — teks sengaja tidak
/// lewat ARB, sama seperti baris laporan harness diagnostik lain.
///
/// Aturan merek tetap berlaku: bagian ini BUKAN permukaan pengguna akhir;
/// jalur DIRECT sendiri tak terlihat di UI produksi.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app.dart';
import '../core/tokens.dart';
import '../domain/models.dart';
import '../player/load_ladder.dart';
import '../services/direct_stream_service.dart';
import 'widgets.dart';

class DirectPathSection extends ConsumerStatefulWidget {
  const DirectPathSection({super.key});

  @override
  ConsumerState<DirectPathSection> createState() => _DirectPathSectionState();
}

class _DirectPathSectionState extends ConsumerState<DirectPathSection> {
  Timer? _ticker;
  bool? _enabled;
  String? _byteCompare;
  bool _comparing = false;

  DirectStreamService get _service => ref.read(ytMusicProvider).directService;

  @override
  void initState() {
    super.initState();
    _loadSwitch();
    _ticker = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _loadSwitch() async {
    final v = await ref
        .read(ytMusicProvider)
        .db
        .pref<bool>(DirectStreamService.killSwitchPrefKey);
    if (mounted) setState(() => _enabled = v ?? true);
  }

  Future<void> _setSwitch(bool v) async {
    setState(() => _enabled = v);
    await ref
        .read(ytMusicProvider)
        .db
        .setPref(DirectStreamService.killSwitchPrefKey, v);
  }

  /// Banding byte: total berkas muxed (itag 18) trek DIRECT terakhir,
  /// dibaca dari Content-Range satu permintaan 1 byte — dibandingkan
  /// dengan contentLength format adaptif yang tercatat di statistik.
  Future<void> _compareBytes() async {
    final stats = _service.stats;
    final trackId = stats.lastTrackId;
    final directBytes = stats.lastContentLength;
    if (trackId == null || directBytes == null || directBytes <= 0) {
      setState(() => _byteCompare = 'Belum ada resolusi DIRECT sesi ini.');
      return;
    }
    setState(() {
      _comparing = true;
      _byteCompare = null;
    });
    try {
      final provider = ref.read(ytMusicProvider);
      final track = Track(
        key: TrackKey('ytmusic', trackId),
        title: stats.lastTitle ?? trackId,
        artistNames: '',
        playableRef: trackId,
      );
      final muxed = await provider.resolveMuxedFallback(track);
      if (muxed == null) {
        setState(() => _byteCompare = 'Muxed tidak tersedia untuk trek ini.');
        return;
      }
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
      try {
        final req = await client.getUrl(Uri.parse(muxed.url));
        req.headers.set(HttpHeaders.userAgentHeader, muxed.userAgent ?? LoadLadder.streamHeaders['User-Agent']!);
        req.headers.set(HttpHeaders.rangeHeader, 'bytes=0-0');
        final res = await req.close().timeout(const Duration(seconds: 20));
        final cr = res.headers.value(HttpHeaders.contentRangeHeader);
        await res.drain<void>();
        final m = cr == null ? null : RegExp(r'/(\d+)$').firstMatch(cr);
        final muxedBytes = m == null ? null : int.tryParse(m.group(1)!);
        if (muxedBytes == null) {
          setState(() => _byteCompare = 'Total muxed tak terbaca (status ${res.statusCode}).');
          return;
        }
        final hemat = (1 - directBytes / muxedBytes) * 100;
        setState(() => _byteCompare =
            'DIRECT itag ${stats.lastItag ?? '-'}: ${_fmtBytes(directBytes)} · '
            'muxed itag 18: ${_fmtBytes(muxedBytes)} · hemat ${hemat.toStringAsFixed(1)}%');
      } finally {
        client.close(force: true);
      }
    } catch (e) {
      setState(() => _byteCompare = 'Banding byte galat: $e');
    } finally {
      if (mounted) setState(() => _comparing = false);
    }
  }

  static String _fmtBytes(int b) {
    if (b >= 1048576) return '${(b / 1048576).toStringAsFixed(2)} MB ($b)';
    if (b >= 1024) return '${(b / 1024).toStringAsFixed(1)} KB ($b)';
    return '$b byte';
  }

  @override
  Widget build(BuildContext context) {
    final stats = _service.stats;
    final sabotage = _service.sabotage;
    const labelStyle = TextStyle(color: ClaiColors.ink, fontWeight: FontWeight.w600, fontSize: 13);
    const valueStyle = TextStyle(color: ClaiColors.inkSecondary, fontSize: 12, height: 1.45);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: Container(
        padding: const EdgeInsets.all(14),
        // 8045: bingkai seksi selaras kartu Diagnostik (surface-1,
        // radius 16); isi & kepadatan datanya tidak berubah.
        decoration: BoxDecoration(
            color: ClaiColors.surface1, borderRadius: BorderRadius.circular(16)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('DIRECT-1 · jalur resolusi produksi (Tahap 3)', style: labelStyle),
          const SizedBox(height: 6),
          Text(
            'Sukses ${stats.okCount} · jatuh ke warisan ${stats.fallbackCount}'
            '${stats.fallbackByCause.isEmpty ? '' : ' (${stats.fallbackByCause.entries.map((e) => '${e.key}×${e.value}').join(', ')})'}'
            ' · gagal beruntun ${stats.consecutiveFailures}'
            '${stats.inCooldown ? ' · DEMOSI sampai ${stats.cooldownUntil}' : ''}',
            style: valueStyle,
          ),
          Text(
            'Terakhir: jalur ${stats.lastPath ?? '-'}'
            '${stats.lastItag != null ? ' · itag ${stats.lastItag}' : ''}'
            '${stats.lastBitrate != null ? ' · ${(stats.lastBitrate! / 1000).round()} kbps' : ''}'
            '${stats.lastCause != null ? ' · sebab ${stats.lastCause}' : ''}'
            '${stats.lastTitle != null ? ' · "${stats.lastTitle}"' : ''}',
            style: valueStyle,
          ),
          if (stats.lastError != null)
            Text('Galat terakhir: ${stats.lastError}', style: valueStyle),
          // Audit 8047 (§6.14): dense dibuang, ukuran teks ke kelas
          // skala type (judul 15/badan, subjudul 13/keterangan).
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Jalur DIRECT aktif (kill-switch)',
                style: TextStyle(color: ClaiColors.ink, fontSize: 15)),
            subtitle: const Text(
                'Mati = semua resolusi lewat rantai warisan (itag 18) seperti sebelum Tahap 3.',
                style: TextStyle(color: ClaiColors.inkSecondary, fontSize: 13)),
            value: _enabled ?? true,
            onChanged: _enabled == null ? null : _setSwitch,
          ),
          Row(children: [
            const Text('Sabotase sig: ', style: valueStyle),
            // Audit 8047: dropdown mentah -> BoundedDropdown baku §6.14.
            BoundedDropdown<DirectSabotage>(
              value: sabotage,
              items: const [
                DropdownMenuItem(value: DirectSabotage.off, child: Text('mati')),
                DropdownMenuItem(value: DirectSabotage.once, child: Text('sekali')),
                DropdownMenuItem(value: DirectSabotage.always, child: Text('selalu')),
              ],
              onChanged: (v) {
                if (v != null) setState(() => _service.sabotage = v);
              },
            ),
            const Spacer(),
            TextButton(
              onPressed: () {
                _service.invalidateSession();
                setState(() {});
              },
              child: const Text('Segarkan sesi minter'),
            ),
          ]),
          Row(children: [
            TextButton(
              onPressed: _comparing ? null : _compareBytes,
              child: Text(_comparing ? 'Membandingkan…' : 'Bandingkan byte trek terakhir'),
            ),
          ]),
          if (_byteCompare != null) Text(_byteCompare!, style: valueStyle),
        ]),
      ),
    );
  }
}
