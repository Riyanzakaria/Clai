import 'dart:async';
import '../l10n/l10n.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../data/app_db.dart';
import '../domain/models.dart';
import '../player/audio_handler.dart';
import '../providers/music_provider.dart';
import 'voice_commands.dart';

enum VoiceState { idle, listening, thinking, awaitingChoice }

/// Antrean Suara (F2 Batch 2, PRD 5.14 B): teks hasil pengenal suara (atau
/// ketikan simulasi di emulator) → perintah aturan → pencarian → skor →
/// antrean manual, dengan konfirmasi suara yang MENYEBUT JUDULNYA.
/// Tidak ada lagu yang masuk antrean tanpa konfirmasi itu.
class VoiceService extends ChangeNotifier {
  final AppDb db;
  final MusicProvider provider;

  /// Dipasang app.dart initState (handler hidup sesudah bootstrap).
  late ClaiAudioHandler handler;

  static const _ch = MethodChannel('clai/voice');
  static const _events = EventChannel('clai/voice_events');
  static const _tts = MethodChannel('clai/tts');

  VoiceState state = VoiceState.idle;
  String lastTranscript = '';
  String lastMessage = '';
  List<Track> candidates = [];
  VoiceAction? pendingAction;
  StreamSubscription? _eventSub;
  int _lowConfidenceCount = 0;

  VoiceService(this.db, this.provider);

  /// Pengenal suara Android (id-ID bawaan; 'en' bila diminta). Gagal-aman:
  /// perangkat tanpa pengenal → pesan jujur, kolom ketik tetap bisa dipakai.
  Future<void> startListening({String lang = 'id'}) async {
    try {
      final ok = await _ch.invokeMethod<bool>('startListening', {'lang': lang});
      if (ok != true) {
        lastMessage =
            'Pengenal suara tidak tersedia di perangkat ini — ketik perintah di bawah.';
        state = VoiceState.idle;
        notifyListeners();
        return;
      }
      state = VoiceState.listening;
      notifyListeners();
      await _eventSub?.cancel();
      _eventSub = _events.receiveBroadcastStream().listen(_onVoiceEvent,
          onError: (_) {
        lastMessage = l10n.vcDisconnected;
        state = VoiceState.idle;
        notifyListeners();
      });
    } catch (_) {
      lastMessage =
          'Pengenal suara tidak tersedia di perangkat ini — ketik perintah di bawah.';
      state = VoiceState.idle;
      notifyListeners();
    }
  }

  Future<void> stopListening() async {
    try {
      await _ch.invokeMethod<void>('stopListening');
    } catch (_) {}
    await _eventSub?.cancel();
    _eventSub = null;
    if (state == VoiceState.listening) {
      state = VoiceState.idle;
      notifyListeners();
    }
  }

  void _onVoiceEvent(Object? event) {
    if (event is! Map) return;
    final error = event['error'] as String?;
    if (error != null) {
      lastMessage = l10n.vcFailed(error);
      state = VoiceState.idle;
      notifyListeners();
      return;
    }
    final text = event['text'] as String?;
    if (text == null || text.isEmpty) return;
    final isFinal = event['isFinal'] as bool? ?? false;
    lastTranscript = text;
    notifyListeners();
    if (isFinal) {
      final conf = (event['confidence'] as num?)?.toDouble();
      handleText(text, confidence: conf).then((_) {}, onError: (_) {});
    }
  }

  Future<void> speak(String text) async {
    lastMessage = text;
    notifyListeners();
    try {
      await _tts.invokeMethod<void>('speak', {'text': text});
    } catch (_) {/* TTS gagal: pesan tetap tampil di layar */}
  }

  /// Jalur utama: satu teks perintah (dari pengenal ATAU ketikan simulasi).
  Future<void> handleText(String text, {double? confidence}) async {
    lastTranscript = text;
    // Jawaban atas pertanyaan pilihan lebih dulu.
    if (state == VoiceState.awaitingChoice) {
      final choice = parseChoiceAnswer(text);
      if (choice == null) {
        await speak(l10n.vcAnswerChoice);
        return;
      }
      if (choice == -1) {
        state = VoiceState.idle;
        candidates = [];
        pendingAction = null;
        await speak(l10n.vcCancelled);
        notifyListeners();
        return;
      }
      if (choice < candidates.length) {
        final track = candidates[choice];
        final action = pendingAction;
        state = VoiceState.idle;
        candidates = [];
        pendingAction = null;
        notifyListeners();
        await _apply(track, action ?? VoiceAction.play);
      }
      return;
    }
    // Keyakinan rendah: minta ulangi maks 2× lalu menyerah sopan.
    // D-36 (Sapuan): off-by-one — syarat lama `< 2` sesudah increment hanya
    // memberi SATU tanya-ulang nyata (hitungan 1), lalu menyerah pada
    // hitungan 2. Kini tanya-ulang terjadi pada hitungan 1 dan 2 (dua kali,
    // sesuai PRD 5.14B), menyerah pada hitungan 3.
    if (confidence != null && confidence < 0.5) {
      _lowConfidenceCount++;
      if (_lowConfidenceCount <= 2) {
        await speak(l10n.vcUnclear);
      } else {
        _lowConfidenceCount = 0;
        await speak(l10n.vcStopped);
        state = VoiceState.idle;
        notifyListeners();
      }
      return;
    }
    _lowConfidenceCount = 0;
    final parsed = parseVoiceCommand(text);
    switch (parsed.action) {
      case VoiceAction.unknown:
        await speak(l10n.vcUnknown);
        break;
      case VoiceAction.skip:
        await handler.skipToNext();
        await speak(l10n.vcSkipped);
        await handler.playEarcon();
        break;
      case VoiceAction.pause:
        await handler.pauseNow();
        await speak(l10n.vcPaused);
        break;
      case VoiceAction.resume:
        await handler.playNow();
        await speak(l10n.vcResumed);
        break;
      case VoiceAction.play:
      case VoiceAction.addNext:
      case VoiceAction.addQueue:
        await _resolveAndApply(parsed.query, parsed.action);
        break;
    }
  }

  Future<void> _resolveAndApply(String query, VoiceAction action) async {
    if (query.isEmpty) {
      await speak(l10n.vcSayTitle);
      return;
    }
    state = VoiceState.thinking;
    notifyListeners();
    try {
      final results = await provider.search(query);
      final songs = results.songs;
      if (songs.isEmpty) {
        state = VoiceState.idle;
        await speak(l10n.vcNotFound(query));
        notifyListeners();
        return;
      }
      final likedKeys = await db.likedKeys();
      final counts = await db.playCounts();
      final scored = songs
          .map((t) => (
                track: t,
                score: voiceScore(query, t,
                    liked: likedKeys.contains(t.key),
                    plays: counts[t.key] ?? 0)
              ))
          .toList()
        ..sort((a, b) => b.score.compareTo(a.score));
      final top = scored.first;
      if (top.score < kVoiceAcceptThreshold) {
        state = VoiceState.idle;
        await speak(l10n.vcNoMatch(query));
        notifyListeners();
        return;
      }
      // Dua teratas berskor dekat → tanya, jangan tebak.
      if (scored.length > 1 &&
          (top.score - scored[1].score).abs() < kVoiceAmbiguityGap) {
        candidates = [scored[0].track, scored[1].track];
        pendingAction = action;
        state = VoiceState.awaitingChoice;
        notifyListeners();
        await speak(l10n.vcWhich(scored[0].track.artistNames, scored[1].track.artistNames, scored[0].track.title, scored[1].track.title));
        return;
      }
      state = VoiceState.idle;
      notifyListeners();
      await _apply(top.track, action);
    } catch (_) {
      state = VoiceState.idle;
      await speak(l10n.vcSearchFailed);
      notifyListeners();
    }
  }

  /// Penerapan + konfirmasi yang MENYEBUT JUDUL (syarat PRD).
  Future<void> _apply(Track track, VoiceAction action) async {
    switch (action) {
      case VoiceAction.play:
        await handler.playTracks([track], 0, kind: 'search', label: l10n.vcContextLabel);
        await speak(l10n.vcPlaying(track.title, track.artistNames));
        break;
      case VoiceAction.addNext:
        await handler.enqueue(track, next: true);
        await speak(l10n.vcAddedNext(track.title, track.artistNames));
        break;
      case VoiceAction.addQueue:
        await handler.enqueue(track, next: false);
        await speak(l10n.vcAddedQueue(track.title, track.artistNames));
        break;
      default:
        break;
    }
    await handler.playEarcon();
  }
}
