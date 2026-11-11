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
            style: const TextStyle(color: ClaiColors.inkSecondary, height: 1.45)),
        const SizedBox(height: 18),
        Center(
          child: GestureDetector(
            onTap: _mic,
            child: Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                  color: voice.state == VoiceState.listening
                      ? ClaiColors.accent
                      : ClaiColors.surface2,
                  shape: BoxShape.circle),
              child: ClaiIcon(ClaiIcons.mic,
                  color: voice.state == VoiceState.listening
                      ? ClaiColors.onAccent
                      : ClaiColors.ink,
                  size: 44),
            ),
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
                  fontSize: 16,
                  fontStyle: FontStyle.italic)),
        ],
        if (voice.lastMessage.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(voice.lastMessage,
              style: const TextStyle(color: ClaiColors.inkSecondary, height: 1.45)),
        ],
        if (voice.state == VoiceState.awaitingChoice)
          for (var i = 0; i < voice.candidates.length; i++)
            EntityRow(
              leading: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: ClaiColors.surface2,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text('${i + 1}',
                      style: const TextStyle(
                          color: ClaiColors.accent,
                          fontSize: 16,
                          fontWeight: FontWeight.w700)),
                ),
              ),
              title: voice.candidates[i].title,
              subtitle: brandSafeSubtitle(voice.candidates[i].artistNames),
              onTap: () => voice.handleText(i == 0 ? 'first' : 'second'),
            ),
        const Spacer(),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _typed,
              style: const TextStyle(color: ClaiColors.ink),
              decoration: claiFieldDecoration(
                hintText: context.l10n.voiceInputHint,
              ),
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
                backgroundColor: ClaiColors.accent,
                foregroundColor: ClaiColors.onAccent),
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
