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

  /// Ronde 8065: penanda sesi dengar. [_finalHandled] — satu transkrip
  /// final sudah diproses pada sesi ini; error pengenal SUSULAN tidak
  /// boleh menimpa hasilnya. [_disconnectRetried] — dengar-ulang otomatis
  /// untuk layanan terputus (kode 11) hanya boleh terjadi SATU kali.
  bool _finalHandled = false;
  bool _disconnectRetried = false;
  String _listenLang = 'id';

  VoiceService(this.db, this.provider);

  /// Pengenal suara Android (id-ID bawaan; 'en' bila diminta). Gagal-aman:
  /// perangkat tanpa pengenal → pesan jujur, kolom ketik tetap bisa dipakai.
  Future<void> startListening({String lang = 'id'}) async {
    _listenLang = lang;
    _finalHandled = false;
    _disconnectRetried = false;
    await _beginListening();
  }

  Future<void> _beginListening() async {
    try {
      final ok =
          await _ch.invokeMethod<bool>('startListening', {'lang': _listenLang});
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
      // Ronde 8065 (bukti HP riyan 14 Nov 18:40): pengenal sempat
      // menyerahkan transkrip final yang bagus, LALU layanannya terputus
      // (kode 11) — error susulan itu tidak boleh membuang perintah yang
      // sudah diterima. Final yang sudah diproses menang atas error.
      if (_finalHandled) return;
      // Kode 11 = layanan pengenal terputus (ERROR_SERVER_DISCONNECTED)
      // TANPA transkrip final: coba dengar ulang otomatis SATU kali
      // sebelum gagal jujur seperti sedia kala.
      if (voiceErrorCode(error) == 11 && !_disconnectRetried) {
        _disconnectRetried = true;
        _beginListening().then((_) {}, onError: (_) {});
        return;
      }
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
      _finalHandled = true;
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
  ///
  /// Ronde 8065 — veto keyakinan DICABUT (bukti HP riyan 14 Nov 18:39:
  /// transkrip "putar lagu sway" terbaca benar tetapi dibuang mentah-
  /// mentah karena angka keyakinan pengenal < 0.5). Kini teks selalu
  /// diurai dulu: jawaban pilihan & aksi tanpa argumen jalan tanpa
  /// memandang keyakinan; putar/tambah diputuskan skor pencocokan —
  /// keyakinan rendah hanya mengubah BUNYI kegagalan menjadi ajakan
  /// mengulangi (lihat voiceFailureWording).
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
    final lowConfidence = confidence != null && confidence < 0.5;
    final parsed = parseVoiceCommand(text);
    switch (parsed.action) {
      case VoiceAction.unknown:
        await speak(l10n.vcUnknown);
        break;
      case VoiceAction.skip:
        _lowConfidenceCount = 0;
        await handler.skipToNext();
        await speak(l10n.vcSkipped);
        await handler.playEarcon();
        break;
      case VoiceAction.pause:
        _lowConfidenceCount = 0;
        await handler.pauseNow();
        await speak(l10n.vcPaused);
        break;
      case VoiceAction.resume:
        _lowConfidenceCount = 0;
        await handler.playNow();
        await speak(l10n.vcResumed);
        break;
      case VoiceAction.play:
      case VoiceAction.addNext:
      case VoiceAction.addQueue:
        await _resolveAndApply(parsed.query, parsed.action,
            lowConfidence: lowConfidence);
        break;
    }
  }

  /// Kegagalan resolusi kueri: bunyinya dipilih kebijakan murni
  /// [voiceFailureWording] — spesifik (tidak ditemukan/tak cocok/gagal
  /// cari), ajakan mengulangi (keyakinan rendah + cocok pun gagal), atau
  /// menyerah sopan sesudah ajakan berturut habis (PRD 5.14B).
  Future<void> _failResolution(String specificMessage,
      {required bool lowConfidence}) async {
    state = VoiceState.idle;
    switch (voiceFailureWording(
        lowConfidence: lowConfidence, failedAttempts: _lowConfidenceCount)) {
      case VoiceFailureWording.askRepeat:
        _lowConfidenceCount++;
        await speak(l10n.vcUnclear);
      case VoiceFailureWording.giveUp:
        _lowConfidenceCount = 0;
        await speak(l10n.vcStopped);
      case VoiceFailureWording.specific:
        _lowConfidenceCount = 0;
        await speak(specificMessage);
    }
    notifyListeners();
  }

  Future<void> _resolveAndApply(String query, VoiceAction action,
      {required bool lowConfidence}) async {
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
        await _failResolution(l10n.vcNotFound(query),
            lowConfidence: lowConfidence);
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
      switch (decideVoiceResolution([for (final s in scored) s.score])) {
        case VoiceResolveDecision.fail:
          await _failResolution(l10n.vcNoMatch(query),
              lowConfidence: lowConfidence);
          return;
        case VoiceResolveDecision.askChoice:
          // Dua teratas berskor dekat → tanya, jangan tebak.
          candidates = [scored[0].track, scored[1].track];
          pendingAction = action;
          state = VoiceState.awaitingChoice;
          _lowConfidenceCount = 0;
          notifyListeners();
          await speak(l10n.vcWhich(scored[0].track.artistNames, scored[1].track.artistNames, scored[0].track.title, scored[1].track.title));
          return;
        case VoiceResolveDecision.apply:
          _lowConfidenceCount = 0;
          state = VoiceState.idle;
          notifyListeners();
          await _apply(scored.first.track, action);
          return;
      }
    } catch (_) {
      await _failResolution(l10n.vcSearchFailed,
          lowConfidence: lowConfidence);
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
