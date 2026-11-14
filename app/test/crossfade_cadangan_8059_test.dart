import 'dart:io';

import 'package:clai/domain/models.dart';
import 'package:clai/player/load_ladder.dart';
import 'package:clai/player/resolving_audio_source.dart';
import 'package:clai/providers/ytmusic/direct_types.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';

/// Ronde 8059 — cadangan tangga untuk Crossfade (keputusan pemilik
/// 2026-11-13 11:27; perubahan semantik ADR-002).
///
/// Akar terbukti 2026-11-11: saat resolusi DIRECT segar BERHASIL tetapi
/// ambil byte pemain ditolak 403 (badai jendela), mode Crossfade senyap
/// total — _xfPlayCurrent/_xfPreload memasang sumber dari SATU anak
/// tangga tanpa cadangan tingkat pemain, sedang Gapless bertahan lewat
/// tangga + proxy + muxed-nya.
///
/// Perbaikan yang dikunci di sini:
/// (1) galat sumber tingkat pemain pada trek masuk Crossfade → tangga
///     dinaiki (komposisi childFor ketat + run yang sama persis dengan
///     yang dipakai _xfPlayCurrent/_xfPreload) dan trek tetap bunyi
///     dari anak cadangan;
/// (2) niat yang tergantikan di tengah panjat → kelas BATAL
///     (DirectSuperseded / cek kehendak) menghentikan panjat seketika:
///     tidak ada anak lain yang dicoba, trek lama tidak terpasang;
/// (3) jalur sehat tidak berubah: satu percobaan di anak adaptif,
///     resolver muxed tidak tersentuh.
///
/// Handler konkret tidak bisa dibangun di unit test (konstruktornya
/// menyentuh kanal platform — kendala yang sama dicatat suite 8054/
/// 8055/8057), jadi paruh perilaku diuji pada JAHITAN tangga yang
/// dipakai handler, dan paruh kabel diverifikasi pada sumber handler
/// dengan pola sapuan yang sama seperti putar_pulih_8057_test.
class _Abort implements Exception {
  const _Abort();
}

void main() {
  const track = Track(
      key: TrackKey('ytmusic', 'x'),
      title: 'Uji',
      artistNames: 'A',
      playableRef: 'x');
  StreamInfo info(String url) => StreamInfo(
      url: url,
      mimeType: 'audio/webm',
      expiresAt: DateTime.now().add(const Duration(hours: 1)));

  LoadLadder ladder({
    Future<StreamInfo> Function(Track, {bool Function()? stillWanted})?
        adaptive,
    Future<StreamInfo?> Function(Track)? muxed,
  }) =>
      LoadLadder(
        resolveAdaptive: adaptive ??
            (t, {stillWanted}) async => info('https://contoh/adaptif'),
        resolveMuxed: muxed ?? (t) async => info('https://contoh/muxed'),
        tagFor: (t) => 'tag-${t.id}',
        isLocal: (t) => false,
      );

  group('komposisi panjat crossfade (childFor ketat + run)', () {
    test(
        '(1) sumber langsung ditolak pemain (403) → cadangan muxed terpasang, trek bunyi',
        () async {
      final l = ladder();
      final installed = <AudioSource>[];
      // Pemain tiruan: menolak byte anak adaptif di tingkat pemain
      // (resolusi sukses, ambil byte 403 — pola badai 2026-11-11),
      // menerima anak lain.
      Future<void> install(AudioSource child) async {
        if (child is UriAudioSource &&
            child.uri.toString() == 'https://contoh/adaptif') {
          throw StateError('PlayerException (403) source error');
        }
        installed.add(child);
      }

      final winner = await l.run(
        attempt: (rung) async {
          final child = await l.childFor(track, rung, strict: true);
          await install(child);
        },
        isAbortError: (e) => e is _Abort || e is DirectSuperseded,
      );
      expect(winner, LoadLadder.rungMuxedUri);
      expect(installed, hasLength(1));
      expect((installed.single as UriAudioSource).uri.toString(),
          'https://contoh/muxed');
      expect(l.stickyRung, LoadLadder.rungMuxedUri,
          reason: 'pemenang cadangan menjadi lengket, seperti gapless');
    });

    test('(1b) adaptif + muxed gugur di pemain → anak proxy menyelamatkan',
        () async {
      final l = ladder(muxed: (t) async => null); // muxed tak tersedia
      final installed = <AudioSource>[];
      Future<void> install(AudioSource child) async {
        if (child is UriAudioSource) {
          throw StateError('PlayerException (403) source error');
        }
        installed.add(child);
      }

      final winner = await l.run(
        attempt: (rung) async {
          final child = await l.childFor(track, rung, strict: true);
          await install(child);
        },
        isAbortError: (e) => e is _Abort || e is DirectSuperseded,
      );
      expect(winner, LoadLadder.rungProxy);
      expect(installed.single, isA<ResolvingAudioSource>());
    });

    test(
        '(2) niat tergantikan sebelum resolusi jalan → DirectSuperseded menghentikan panjat',
        () async {
      var wanted = false;
      var muxedCalls = 0;
      final l = ladder(
        // Resolver DIRECT nyata membuang pekerjaan yang sudah
        // dikalahkan dari antrean resolusi (Ronde 8054).
        adaptive: (t, {stillWanted}) async {
          if (stillWanted != null && !stillWanted()) {
            throw const DirectSuperseded();
          }
          return info('https://contoh/adaptif');
        },
        muxed: (t) async {
          muxedCalls++;
          return info('https://contoh/muxed');
        },
      );
      var rungFailedCalls = 0;
      await expectLater(
        l.run(
          attempt: (rung) async {
            await l.childFor(track, rung,
                strict: true, stillWanted: () => wanted);
          },
          isAbortError: (e) => e is _Abort || e is DirectSuperseded,
          onRungFailed: (rung, e, st) => rungFailedCalls++,
        ),
        throwsA(isA<DirectSuperseded>()),
      );
      expect(muxedCalls, 0, reason: 'anak berikutnya tidak boleh dicoba');
      expect(rungFailedCalls, 0,
          reason: 'kelas BATAL bukan kegagalan anak tangga');
      expect(l.stickyRung, LoadLadder.rungAdaptiveUri);
    });

    test(
        '(2b) niat tergantikan DI TENGAH panjat (sesudah anak pertama gugur) → panjat berhenti, tak ada yang terpasang',
        () async {
      var wanted = true;
      final tried = <int>[];
      final l = ladder();
      await expectLater(
        l.run(
          attempt: (rung) async {
            tried.add(rung);
            await l.childFor(track, rung, strict: true);
            // Pemasangan anak pertama ditolak pemain DAN pada saat yang
            // sama niat pengguna sudah berpindah (ketukan lebih baru).
            if (rung == LoadLadder.rungAdaptiveUri) {
              wanted = false;
              throw StateError('PlayerException (403) source error');
            }
            if (!wanted) throw const _Abort(); // titik komit _xfPlayCurrent
            // (trek lama tidak boleh terpasang)
          },
          isAbortError: (e) => e is _Abort || e is DirectSuperseded,
        ),
        throwsA(isA<_Abort>()),
      );
      expect(tried, [LoadLadder.rungAdaptiveUri, LoadLadder.rungMuxedUri],
          reason: 'panjat berhenti tepat di titik komit anak kedua');
    });

    test('(3) jalur sehat: satu percobaan, muxed tak tersentuh, lengket diam',
        () async {
      var muxedCalls = 0;
      final l = ladder(muxed: (t) async {
        muxedCalls++;
        return info('https://contoh/muxed');
      });
      final tried = <int>[];
      final installed = <AudioSource>[];
      final winner = await l.run(
        attempt: (rung) async {
          tried.add(rung);
          final child = await l.childFor(track, rung, strict: true);
          installed.add(child);
        },
        isAbortError: (e) => e is _Abort || e is DirectSuperseded,
      );
      expect(winner, LoadLadder.rungAdaptiveUri);
      expect(tried, [LoadLadder.rungAdaptiveUri]);
      expect(muxedCalls, 0);
      expect((installed.single as UriAudioSource).uri.toString(),
          'https://contoh/adaptif');
      expect(l.stickyRung, LoadLadder.rungAdaptiveUri);
    });
  });

  group('kabel sumber handler (sapuan)', () {
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

    test('_xfPlayCurrent menaiki tangga dengan penjaga generasi penuh', () {
      final body = bodyBetween(
          'Future<void> _xfPlayCurrent(', '/// Satu detak monitor');
      expect(body, contains('_ladder.run('));
      expect(body,
          contains('isAbortError: (e) => e is _Superseded || e is DirectSuperseded'));
      expect(body, contains("'crossfade-tangga-gagal'"));
      expect(body, contains('on DirectSuperseded'));
      expect(body, contains('on _Superseded'));
      // Penjaga pasca-pasang 8054 tetap utuh sesudah panjat.
      expect(body,
          contains('if (superseded()) return; // ketukan lebih baru tiba saat memasang'));
      expect(body, contains('await _activePlayer.play();'));
    });

    test('_xfPreload menaiki tangga & menandai degradasi dari anak pemenang',
        () {
      final body =
          bodyBetween('Future<void> _xfPreload(', 'void _xfStartRamp()');
      expect(body, contains('_ladder.run('));
      expect(body, contains('_xfPreloadDegraded = wonRung != firstRung'));
      expect(body, contains("'crossfade-preload-degradasi'"));
      expect(body, contains('on _Superseded'),
          reason: 'kepala basi di tengah panjat bukan kegagalan preload');
    });

    test('ramp tidak pernah dimulai untuk preload terdegradasi', () {
      final tick = bodyBetween('void _xfTick() {', 'Future<void> _xfPreload(');
      expect(tick, contains('if (remaining.inMilliseconds <= rampMs && !_xfPreloadDegraded)'));
      final ramp =
          bodyBetween('void _xfStartRamp() {', 'Future<void> _xfFinishRamp()');
      expect(ramp, contains('_xfPreloadDegraded'));
    });

    test('_onPlayerError: galat bukan-sumber tidak memicu pemulihan', () {
      final body = bodyBetween(
          'Future<void> _onPlayerError(', 'Future<void> onTaskRemoved');
      final idxInterruption = body.indexOf('if (isInterruptionError(e)) return;');
      final idxXf = body.indexOf('if (_xfMode) {');
      expect(idxInterruption, greaterThanOrEqualTo(0));
      expect(idxXf, greaterThan(idxInterruption),
          reason: 'saringan interupsi mendahului semua cabang pemulihan');
      // Coba-ulang crossfade tetap lewat _xfPlayCurrent (yang kini
      // menaiki tangga di dalamnya).
      expect(body, contains('await _xfPlayCurrent(cur);'));
    });
  });
}
