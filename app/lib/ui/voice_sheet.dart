import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/l10n.dart';
import 'package:permission_handler/permission_handler.dart';

import '../app.dart';
import '../core/clai_icons.dart';
import '../core/tokens.dart';
import '../services/voice_service.dart';
import 'widgets.dart';

Future<void> openVoiceSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: claiRootContext(context),
    isScrollControlled: true,
    backgroundColor: ClaiColors.surface1,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => const FractionallySizedBox(
        heightFactor: 0.72, child: VoiceSheet()),
  );
}

/// Lembar Antrean Suara (F2 Batch 2): tombol mikrofon (pengenal Android),
/// transkrip, status, daftar pilihan bila ambigu, dan kolom ketik simulasi —
/// kolom ini JUGA jalur bukti emulator (tanpa mikrofon, pipeline sama).
class VoiceSheet extends ConsumerStatefulWidget {
  const VoiceSheet({super.key});
  @override
  ConsumerState<VoiceSheet> createState() => _VoiceSheetState();
}

class _VoiceSheetState extends ConsumerState<VoiceSheet> {
  final _typed = TextEditingController();

  @override
  void dispose() {
    _typed.dispose();
    super.dispose();
  }

  Future<void> _mic() async {
    final granted = await Permission.microphone.isGranted ||
        await Permission.microphone.request().isGranted;
    if (!granted) {
      await ref
          .read(voiceServiceProvider)
          .speak(context.l10n.voiceMicDenied);
      return;
    }
    await ref.read(voiceServiceProvider).startListening();
  }

  @override
  Widget build(BuildContext context) {
    final voice = ref.watch(voiceServiceProvider);
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 14, 20, 28 + bottomInset),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Center(child: SheetHandle()),
        const SizedBox(height: 18),
        Row(children: [
          Expanded(
              child: Text(context.l10n.voiceTitle, style: displayStyle(20))),
          IconButton(
              icon: ClaiIcon(ClaiIcons.close, color: ClaiColors.inkSecondary),
              onPressed: () async {
                await voice.stopListening();
                if (context.mounted) Navigator.of(context).pop();
              }),
        ]),
        const SizedBox(height: 4),
        Text(context.l10n.voiceExamples,
            style: const TextStyle(
                color: ClaiColors.inkSecondary, fontSize: 13)),
        const SizedBox(height: 18),
        Center(
          child: _MicHero(
            listening: voice.state == VoiceState.listening,
            onTap: _mic,
          ),
        ),
        const SizedBox(height: 12),
        Center(
            child: Text(
                switch (voice.state) {
                  VoiceState.listening => context.l10n.voiceListening,
                  VoiceState.thinking => context.l10n.voiceSearching,
                  VoiceState.awaitingChoice => context.l10n.voiceWhichOne,
                  VoiceState.idle => context.l10n.voiceHintIdle,
                },
                style:
                    const TextStyle(color: ClaiColors.inkSecondary, fontSize: 13))),
        if (voice.lastTranscript.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text('“${voice.lastTranscript}”',
              style: const TextStyle(
                  color: ClaiColors.ink,
                  fontSize: 15,
                  fontStyle: FontStyle.italic)),
        ],
        if (voice.lastMessage.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(voice.lastMessage,
              style: const TextStyle(color: ClaiColors.inkSecondary, height: 1.45)),
        ],
        if (voice.state == VoiceState.awaitingChoice)
          for (var i = 0; i < voice.candidates.length; i++) ...[
            if (i > 0)
              const Divider(
                  color: ClaiColors.divider,
                  height: 1,
                  thickness: 1,
                  indent: 48),
            InkWell(
              onTap: () => voice.handleText(i == 0 ? 'first' : 'second'),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(children: [
                  SizedBox(
                    width: 36,
                    child: Text('${i + 1}',
                        style: displayStyle(17)
                            .copyWith(color: ClaiColors.signal)),
                  ),
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(voice.candidates[i].title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: ClaiColors.ink,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500)),
                          if (brandSafeSubtitle(
                                  voice.candidates[i].artistNames) !=
                              null)
                            Text(
                                brandSafeSubtitle(
                                    voice.candidates[i].artistNames)!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    color: ClaiColors.inkSecondary,
                                    fontSize: 13)),
                        ]),
                  ),
                ]),
              ),
            ),
          ],
        const Spacer(),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _typed,
              style: const TextStyle(color: ClaiColors.ink),
              decoration: claiFieldDecoration(
                hintText: context.l10n.voiceInputHint,
              ).copyWith(fillColor: ClaiColors.surface2),
              onSubmitted: (v) {
                if (v.trim().isEmpty) return;
                voice.handleText(v.trim());
                _typed.clear();
              },
            ),
          ),
          const SizedBox(width: 10),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: ClaiColors.signal,
                foregroundColor: ClaiColors.onSignal,
                shape: const StadiumBorder()),
            onPressed: () {
              final v = _typed.text.trim();
              if (v.isEmpty) return;
              voice.handleText(v);
              _typed.clear();
            },
            child: Text(context.l10n.voiceSend),
          ),
        ]),
      ]),
    );
  }
}

/// Pahlawan mikrofon (Ronde 8086): cakram datar signal 88 dengan glif mic
/// onSignal, dikelilingi cincin 28 batang radial bermotif gelombang Clai.
/// Cakram signal di SEMUA keadaan; keadaan mendengarkan dibaca dari cincin —
/// batang menyala signal dan berdenyut halus, dan animasinya berhenti total
/// di luar keadaan dengar (keputusan terkunci koordinator, PROGRES 8086).
/// Seluruh pahlawan adalah satu target ketuk [_mic] yang sama seperti dulu.
class _MicHero extends StatefulWidget {
  final bool listening;
  final VoidCallback onTap;
  const _MicHero({required this.listening, required this.onTap});

  @override
  State<_MicHero> createState() => _MicHeroState();
}

class _MicHeroState extends State<_MicHero>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1200));

  @override
  void initState() {
    super.initState();
    if (widget.listening) _pulse.repeat();
  }

  @override
  void didUpdateWidget(covariant _MicHero oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.listening && !_pulse.isAnimating) {
      _pulse.repeat();
    } else if (!widget.listening && _pulse.isAnimating) {
      _pulse.stop();
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: SizedBox(
        width: 136,
        height: 136,
        child: Stack(alignment: Alignment.center, children: [
          AnimatedBuilder(
            animation: _pulse,
            builder: (context, _) => CustomPaint(
              size: const Size(136, 136),
              painter: _MicRingPainter(
                  listening: widget.listening, phase: _pulse.value),
            ),
          ),
          Container(
            width: 88,
            height: 88,
            decoration: const BoxDecoration(
                color: ClaiColors.signal, shape: BoxShape.circle),
            child: ClaiIcon(ClaiIcons.mic,
                color: ClaiColors.onSignal, size: 40),
          ),
        ]),
      ),
    );
  }
}

/// Pelukis cincin batang radial pahlawan mikrofon: 28 batang, lebar 3,
/// ujung membulat, panjang DETERMINISTIK dari pola tetap di bawah —
/// bukan acak (sejalan DS §14.5, motif gelombang deterministik). Saat
/// mendengarkan, panjang tiap batang dimodulasi fase denyutnya sendiri.
class _MicRingPainter extends CustomPainter {
  final bool listening;
  final double phase;
  const _MicRingPainter({required this.listening, required this.phase});

  /// Pola panjang batang (dp) — tetap, tertulis di kode.
  static const List<double> _lengths = [
    9, 13, 17, 11, 15, 18, 12, 16, 10, 14, //
    17, 11, 15, 9, 13, 18, 12, 16, 10, 14, //
    17, 11, 15, 9, 13, 16, 12, 18,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    const innerRadius = 48.0; // cakram 88 (jari-jari 44) + napas 4
    final paint = Paint()
      ..color = listening
          ? ClaiColors.signal
          : ClaiColors.inkFaint.withValues(alpha: 0.55)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < _lengths.length; i++) {
      final angle = (2 * math.pi * i / _lengths.length) - math.pi / 2;
      var len = _lengths[i];
      if (listening) {
        len *= 0.8 + 0.2 * math.sin(2 * math.pi * phase + i * 0.7);
      }
      final dir = Offset(math.cos(angle), math.sin(angle));
      canvas.drawLine(center + dir * innerRadius,
          center + dir * (innerRadius + len), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _MicRingPainter oldDelegate) =>
      oldDelegate.listening != listening || oldDelegate.phase != phase;
}
