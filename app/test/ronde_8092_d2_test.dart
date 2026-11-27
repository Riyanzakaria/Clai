import 'dart:io';

import 'package:clai/player/audio_handler.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ronde 8092 D2 — R7 (berhenti-otomatis dibersihkan & terlihat) +
/// R8 (niat & sebab-jeda tercatat), dari BEDAH-D2 di
/// builds/bukti-ronde-8092. Kontrak dikunci pada KABEL SUMBER, gaya
/// ronde_8092_d1_test: handler konkret tidak bisa dibangun di unit
/// test (kanal platform), jadi pola strukturalnya yang diverifikasi;
/// keputusan penjaga verifikasi diuji sebagai logika murni
/// (advanceVerifyBlockedByPause + PauseCause diekspor handler).
void main() {
  final src = File('lib/player/audio_handler.dart').readAsStringSync();

  String bodyBetween(String startMarker, String endMarker) {
    final start = src.indexOf(startMarker);
    if (start < 0) throw StateError('$startMarker tidak ditemukan');
    final end = src.indexOf(endMarker, start);
    if (end <= start) {
      throw StateError('$endMarker tidak ditemukan sesudah $startMarker');
    }
    return src.substring(start, end);
  }

  int count(String haystack, String needle) =>
      haystack.split(needle).length - 1;

  final recovery = bodyBetween(
    'Future<void> _recoverFromPlayerError(Object e) async',
    'Future<void> onTaskRemoved',
  );

  group('R7a/R7b — berhenti-otomatis tercatat & menutup episode', () {
    test('entri log berhenti-otomatis di KEDUA cabang (xf + gapless)',
        () {
      expect(count(recovery, "'berhenti-otomatis'"), 2,
          reason: 'satu entri per situs tembak (crossfade & gapless)');
      expect(count(recovery, 'jalur=crossfade'), 1);
      expect(count(recovery, 'jalur=gapless'), 1);
    });

    test('detail log memuat nilai penghitung + kunci trek', () {
      expect(
        count(recovery, 'gagalBeruntun=\$_consecutiveFailures'),
        2,
        reason: 'nilai penghitung SAAT menembak terbaca dari log',
      );
      expect(count(recovery, 'kunci=\${cur.key}'), 2);
      expect(count(recovery, 'trek="\${cur.title}"'), 2);
    });

    test('penghitung direset SESUDAH menembak di situs yang sama', () {
      // Di tiap cabang: urutan log → stop → reset, di dalam blok >= 3.
      for (final jalur in ['crossfade', 'gapless']) {
        final at = recovery.indexOf('jalur=$jalur');
        expect(at, greaterThan(-1));
        final end = at + 700 > recovery.length ? recovery.length : at + 700;
        final seg = recovery.substring(at, end);
        expect(seg, contains('_consecutiveFailures = 0;'),
            reason: 'reset penutup episode sesudah tembakan $jalur');
        expect(
          seg.indexOf('.stop();'),
          lessThan(seg.indexOf('_consecutiveFailures = 0;')),
          reason: 'reset terjadi SESUDAH bentuk terminal stop ($jalur)',
        );
      }
      // Total reset di badan pemulihan: hanya dua penutup episode ini
      // (reset lain hidup di titik komit/pintu putar, bukan di sini).
      expect(count(recovery, '_consecutiveFailures = 0;'), 2);
    });
  });

  group('R7c — bentuk terminal berhenti bersih, bukan pause telanjang',
      () {
    test('kedua situs memakai stop() pemain, bukan pause()', () {
      expect(recovery, contains('await _activePlayer.stop();'),
          reason: 'cabang crossfade: stop pemain aktif');
      expect(recovery, contains('await _player.stop();'),
          reason: 'cabang gapless: stop pemain gapless');
      expect(count(recovery, '.pause();'), 0,
          reason:
              'tidak ada lagi pause telanjang di badan pemulihan — '
              'parkir loading+pause tak boleh terbentuk dari jalur ini');
    });

    test('notis berhenti-otomatis tetap dikirim di kedua cabang', () {
      expect(count(recovery, 'notices.add(l10n.noticeAutoStop);'), 2);
    });
  });

  group('R7d — reset terpusat di titik komit penggantian sumber', () {
    test('penolong terpusat: reset HANYA bila kunci terkomit berganti',
        () {
      final helper = bodyBetween(
        'void _resetFailuresOnCommittedKey(String key)',
        '/// Tangga strategi muat',
      );
      expect(helper, contains('if (_lastCommittedSourceKey != key)'));
      expect(helper, contains('_consecutiveFailures = 0;'));
      expect(helper, contains('_lastCommittedSourceKey = key;'));
    });

    test('titik komit _buildSource memanggil penolong untuk kunci '
        'jendela pertama', () {
      final build = bodyBetween(
        'Future<void> _buildSource({',
        'Future<void> _maybeExtendWindow',
      );
      expect(
        build,
        contains('_resetFailuresOnCommittedKey(window.first.key.toString());'),
      );
      // Komit = SESUDAH setAudioSource berhasil, bukan sebelumnya.
      expect(
        build.indexOf('_resetFailuresOnCommittedKey('),
        greaterThan(build.indexOf('await _player.setAudioSource(')),
      );
    });

    test('titik komit crossfade (_xfPlayCurrent) memanggil penolong',
        () {
      final xf = bodyBetween(
        'Future<void> _xfPlayCurrent(',
        'void _xfTick()',
      );
      expect(
        xf,
        contains('_resetFailuresOnCommittedKey(t.key.toString());'),
      );
      expect(
        xf.indexOf('_resetFailuresOnCommittedKey('),
        greaterThan(xf.indexOf('await _activePlayer.setAudioSource(')),
        reason: 'reset hanya sesudah sumber benar-benar terpasang',
      );
    });

    test('jatuh-balik trek yang SAMA tidak me-reset: situs pemulihan '
        'tidak memuat reset di luar cabang berhenti-otomatis', () {
      // Badan pemulihan hanya me-reset di dua penutup episode (R7a);
      // bangun-ulang berjangkar (coba-ulang tangga / maju tangga)
      // tidak menyentuh penghitung selain ++.
      expect(count(recovery, '_consecutiveFailures++;'), 2);
      expect(count(recovery, '_resetFailuresOnCommittedKey('), 0,
          reason:
              'reset komit hidup di _buildSource/_xfPlayCurrent dan '
              'di sana bergating kunci-berganti');
    });
  });

  group('R8a/R8b — niat & sebab-jeda tercatat di pintunya', () {
    test('bidang + penolong niat-putar ada', () {
      expect(src, contains('PauseCause _lastPauseCause = PauseCause.none;'));
      expect(src, contains('void _notePlayIntent()'));
      final helper = bodyBetween(
        'void _notePlayIntent()',
        'void _resetFailuresOnCommittedKey',
      );
      expect(helper, contains('_lastPauseCause = PauseCause.none;'));
      expect(helper, contains('_consecutiveFailures = 0;'),
          reason: 'perintah eksplisit memulai episode baru (R8b)');
    });

    test('pintu putar eksplisit menyetel niat: play(), playTracks, '
        'jumpTo', () {
      final play = bodyBetween(
        'Future<void> play() async',
        'Future<void> _pauseFromSystem() async',
      );
      expect(play, contains('_notePlayIntent();'),
          reason: 'play() publik mencatat niat sesudah penjaga sesi kosong');
      expect(
        play.indexOf('_notePlayIntent();'),
        greaterThan(play.indexOf('engine.current == null')),
      );
      final playTracks = bodyBetween(
        'Future<void> playTracks(',
        'Future<void> startRadio(',
      );
      expect(playTracks, contains('_notePlayIntent();'));
      final jump = bodyBetween(
        'Future<void> jumpTo(TrackKey k',
        'Future<void> setAutoplaySession',
      );
      expect(jump, contains('_notePlayIntent();'));
      expect(
        jump.indexOf('_notePlayIntent();'),
        greaterThan(jump.indexOf('if (target == null) return;')),
        reason: 'jumpTo yang GAGAL (target null) tidak me-reset episode',
      );
    });

    test('pintu jeda menyetel sebabnya masing-masing', () {
      final pause = bodyBetween(
        'Future<void> pause() async',
        'Future<void> fadeOutAndPause() async',
      );
      expect(pause, contains('_lastPauseCause = PauseCause.user;'));
      final sys = bodyBetween(
        'Future<void> _pauseFromSystem() async',
        'Future<void> pause() async',
      );
      expect(sys, contains('_lastPauseCause = PauseCause.system;'));
      expect(count(recovery, '_lastPauseCause = PauseCause.autoStop;'), 2,
          reason: 'kedua cabang berhenti-otomatis menandai sebabnya');
    });

    test('enum memuat semua sebab yang disyaratkan', () {
      expect(
        PauseCause.values.map((c) => c.name),
        containsAll(['none', 'user', 'system', 'autoStop', 'recovery']),
      );
    });
  });

  group('R8c — _verifyAdvance membaca sebab-jeda (logika murni)', () {
    test('jeda pengguna/sistem saat tak berbunyi & tak completed: '
        'TERHALANG (perilaku lama utuh)', () {
      for (final cause in [PauseCause.user, PauseCause.system, PauseCause.recovery, PauseCause.none]) {
        expect(
          advanceVerifyBlockedByPause(
            playing: false,
            completed: false,
            cause: cause,
          ),
          isTrue,
          reason: 'sebab $cause bukan autoStop → jangan dioverride',
        );
      }
    });

    test('sesudah berhenti-otomatis: TIDAK terhalang — verifikasi '
        'berjalan sebagaimana niat-putar', () {
      expect(
        advanceVerifyBlockedByPause(
          playing: false,
          completed: false,
          cause: PauseCause.autoStop,
        ),
        isFalse,
      );
    });

    test('sedang berbunyi atau completed: tidak pernah terhalang', () {
      for (final cause in PauseCause.values) {
        expect(
          advanceVerifyBlockedByPause(
            playing: true,
            completed: false,
            cause: cause,
          ),
          isFalse,
        );
        expect(
          advanceVerifyBlockedByPause(
            playing: false,
            completed: true,
            cause: cause,
          ),
          isFalse,
        );
      }
    });

    test('kabel sumber: timer verifikasi memakai penolong + sebab '
        'tercatat, bukan tebakan playing mentah', () {
      final arm = bodyBetween(
        'void _armAdvanceVerifyTimer(',
        'Future<void> retryAutoplayRefill',
      );
      expect(arm, contains('advanceVerifyBlockedByPause('));
      expect(arm, contains('cause: _lastPauseCause,'));
    });
  });
}
