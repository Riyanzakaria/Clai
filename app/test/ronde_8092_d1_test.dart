import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Ronde 8092 D1 — perbaikan stall lengket sesudah pemulihan galat
/// (BEDAH-D1 di builds/bukti-ronde-8092). Kontrak R1–R6 dikunci pada
/// KABEL SUMBER, gaya putar_pulih_8057_test/ronde_8092_lompat_test:
/// handler konkret tidak bisa dibangun di unit test (kanal platform),
/// jadi pola strukturalnya yang diverifikasi di sini; logika murni
/// watchdog/verifikasi diuji di ronde_8092_lompat_test.
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

  group('R1 — pemulihan terserial (penjaga reentri)', () {
    final pintu = bodyBetween(
      'Future<void> _onPlayerError(Object e) async',
      'Future<void> _recoverFromPlayerError(Object e) async',
    );

    test('penjaga ada di pintu _onPlayerError', () {
      expect(src, contains('bool _recovering = false;'));
      expect(src, contains('bool _recoveryPending = false;'));
      expect(pintu, contains('if (_recovering) {'));
      expect(pintu, contains('_recoveryPending = true;'));
      expect(pintu, contains('return;'),
          reason: 'panggilan konkuren tidak berjalan bersamaan');
    });

    test('tertunda dijalankan SATU kali sesudah yang berjalan selesai',
        () {
      expect(pintu, contains('finally'));
      expect(pintu, contains('if (_recoveryPending) {'));
      expect(pintu, contains('_recoveryPending = false;'));
      expect(pintu, contains('await _recoverFromPlayerError(e);'));
      // Panggilan susulan lewat pintu yang sama (bukan badan langsung).
      expect(count(pintu, '_onPlayerError('), 2,
          reason: 'deklarasi pintu + satu panggilan susulan tertunda');
    });

    test('berlaku untuk gapless DAN crossfade (badan bersama)', () {
      final badan = bodyBetween(
        'Future<void> _recoverFromPlayerError(Object e) async',
        'Future<void> onTaskRemoved',
      );
      expect(badan, contains('player-error-xf'),
          reason: 'cabang crossfade ada di dalam badan terserial');
      expect(badan, contains("'player-error'"),
          reason: 'cabang gapless ada di dalam badan yang sama');
    });

    test('berhenti-otomatis TIDAK tertelan penjaga: ia membersihkan '
        'tertunda sebelum jeda', () {
      final badan = bodyBetween(
        'Future<void> _recoverFromPlayerError(Object e) async',
        'Future<void> onTaskRemoved',
      );
      expect(count(badan, '_recoveryPending = false;'), 2,
          reason: 'kedua cabang berhenti-otomatis (xf + gapless)');
      expect(count(badan, '_consecutiveFailures >= 3'), 2);
    });
  });

  group('R2 — jangan berjangkar di trek beracun', () {
    final badan = bodyBetween(
      'Future<void> _recoverFromPlayerError(Object e) async',
      'Future<void> onTaskRemoved',
    );

    test('penanda jangkar gugur total ada dan dibaca sebelum bangun',
        () {
      expect(src, contains('_anchorBuildFailedKeys'));
      expect(badan, contains('final anchorPoisoned'));
      expect(badan, contains('_anchorBuildFailedKeys.contains(attemptKey)'));
      expect(badan, contains('!anchorPoisoned'),
          reason: 'kedua cabang bangun dilewati bila jangkar beracun');
      expect(count(badan, '!anchorPoisoned'), 2,
          reason: 'cabang coba-ulang + cabang maju-tangga');
    });

    test('gugur total di tangga menandai jangkar; berhasil membersihkan',
        () {
      expect(count(badan, '_anchorBuildFailedKeys.add(attemptKey);'), 2,
          reason: 'kedua tangkap galat bangun menandai');
      expect(count(badan, '_anchorBuildFailedKeys.remove(attemptKey);'), 2,
          reason: 'kedua bangun berhasil membersihkan penanda');
    });

    test('batas maks satu bangun-jangkar per episode: jangkar beracun '
        'jatuh ke jalur lewati biasa', () {
      // Sesudah kedua cabang bangun (yang berpenjaga anchorPoisoned),
      // aliran mencapai penghitung gagal beruntun + skipToNext yang
      // sama seperti jalur lewati biasa.
      final lewatiAt = badan.indexOf('await skipToNext();');
      expect(lewatiAt, greaterThan(badan.indexOf('!anchorPoisoned')));
      expect(badan, contains('noticeSkippedUnplayable'));
      expect(badan, contains('_consecutiveFailures++;'));
    });

    test('penanda dibersihkan saat trek benar-benar berganti', () {
      expect(
        src,
        contains('_anchorBuildFailedKeys.remove(t.key.toString());'),
      );
    });
  });

  group('R3 — putus warisan posisi di _rebuildTail', () {
    final def = bodyBetween(
      'Future<bool> _rebuildTail({',
      'Future<void> _syncTailAfterMutation',
    );

    test('penyalinan posisi bersyarat keadaan pemain', () {
      expect(def, contains('ProcessingState.idle'));
      expect(def, contains('ProcessingState.loading'));
      expect(def, contains('_lastPosition = Duration.zero;'),
          reason: 'idle/loading → posisi sumber baru nol');
      expect(def, contains('_lastPosition = pos;'),
          reason: 'pemutaran nyata → posisi disalin seperti semula');
      // Syaratnya mendahului panggilan _buildSource di badan ini.
      expect(
        def.indexOf('ProcessingState.loading'),
        lessThan(def.indexOf('await _buildSource(')),
      );
    });

    test('jalur pulih sesi tidak disentuh: _pendingRestoreSeek utuh '
        'di _buildSource', () {
      final build = bodyBetween(
        'Future<void> _buildSource({',
        'Future<void> _maybeExtendWindow',
      );
      expect(
        build,
        contains('initialPosition: _pendingRestoreSeek ?? _lastPosition'),
        reason: 'restore sesi memakai jalurnya sendiri (D-06)',
      );
    });
  });

  group('R4 — komit generasi atomik di _buildSource', () {
    final build = bodyBetween(
      'Future<void> _buildSource({',
      'Future<void> _maybeExtendWindow',
    );

    test('cek generasi terakhir menempel tepat sebelum setAudioSource '
        'tanpa await di antaranya', () {
      final commitAt = build.lastIndexOf('if (gen != null && gen != _playGen)');
      // Kemunculan terakhir sebelum setAudioSource adalah titik komit
      // (pasca-pasang ada sesudahnya) — cari blok komit dari log-nya.
      final logAt = build.indexOf('pembangunan gugur di titik komit');
      final setAt = build.indexOf('await _player.setAudioSource(');
      expect(logAt, greaterThan(-1));
      expect(logAt, lessThan(setAt));
      final between = build.substring(logAt, setAt);
      expect(between, contains('throw const _Superseded();'));
      // Tidak ada await antara lemparan komit dan pemanggilan pasang,
      // selain penugasan sinkron _source/_sourceTracks.
      final throwAt = build.indexOf('throw const _Superseded();', logAt);
      final seg = build.substring(throwAt, setAt);
      expect(seg.contains('await '), isFalse,
          reason: 'segmen komit→pasang: $seg');
      expect(commitAt, greaterThan(build.indexOf('_sourceTracks = window;')),
          reason: 'cek komit sesudah penugasan sumber, menempel pasang');
    });

    test('jaring kedua pasca-pasang tetap ada', () {
      final setAt = build.indexOf('await _player.setAudioSource(');
      expect(
        build.indexOf('if (gen != null && gen != _playGen)', setAt),
        greaterThan(setAt),
        reason: 'penjaga pasca-pasang dipertahankan',
      );
    });
  });

  group('R5 — cabang escalated memanggil jalur maju-paksa', () {
    test('handler membedakan fire dan escalated dari watchdog', () {
      expect(src, contains('LoadingStage.fire'));
      expect(src, contains('LoadingStage.escalated'));
      expect(src, contains("'loading-abadi'"));
      expect(src, contains("'loading-abadi-eskalasi'"));
    });

    test('escalated → _forceAdvanceAfterLoadingEscalation → skipToNext',
        () {
      final force = bodyBetween(
        'Future<void> _forceAdvanceAfterLoadingEscalation() async',
        'Future<void> _onPlayerError(Object e) async',
      );
      expect(force, contains('await skipToNext();'),
          reason: 'mesin lewati yang ada — ujung antrean/repeat sama');
      expect(force, contains('_loadingWatchdog.reset();'));
      expect(force, contains('_urlAttempts.remove(k);'),
          reason: 'penghitung episode trek lama direset');
      expect(force, contains('_ladderAdvances.remove(k);'));
      // Escalated TIDAK menyerahkan pasien ke _onPlayerError lagi.
      final tickAt = src.indexOf('LoadingStage.escalated');
      final seg = src.substring(tickAt, tickAt + 900);
      expect(seg, contains('_forceAdvanceAfterLoadingEscalation()'));
      expect(seg, isNot(contains('_onPlayerError')));
    });
  });

  group('R6 — verifikasi lompat memeriksa kemajuan muat', () {
    final arm = bodyBetween(
      'void _armAdvanceVerifyTimer(',
      'Future<void> retryAutoplayRefill',
    );

    test('posisi saat lompatan tercatat di target verifikasi', () {
      expect(src, contains('positionMs: _activePlayer.position.inMilliseconds'));
      expect(src, contains('positionAtJumpMs'));
    });

    test('kunci berpindah tanpa kemajuan muat → persenjatai ulang '
        'SATU kali, bukan langsung terverifikasi', () {
      expect(arm, contains('loadProgressStalled('));
      expect(arm, contains('tanpa-kemajuan-muat'));
      expect(arm, contains('AdvanceVerifyTarget.loadRecheckDelay'));
      expect(arm, contains('loadRecheck: true'));
      expect(arm, contains('_verifyTarget.loadRearmed = true;'));
    });

    test('pemeriksaan kedua tetap macet → eskalasi jumpTo seperti '
        'aksi eskalasi sekarang', () {
      expect(arm, contains("Observability.instance.log("));
      expect(arm, contains("'eskalasi-lompat'"));
      expect(
        count(arm, 'await jumpTo(toKey, preserveSleepTimer: true);'),
        2,
        reason: 'eskalasi muat (R6) + eskalasi kunci-belum-berpindah lama',
      );
    });

    test('kunci belum berpindah → perilaku lama utuh', () {
      expect(arm, contains('trek tak berpindah 1,5 dtk sesudah upaya maju'));
      expect(arm, contains('advanceVerified('));
    });
  });
}
