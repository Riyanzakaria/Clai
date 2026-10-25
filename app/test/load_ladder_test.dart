import 'package:clai/domain/models.dart';
import 'package:clai/player/load_ladder.dart';
import 'package:clai/player/resolving_audio_source.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';

/// Tangga strategi muat (v4.2): urutan maju saat gagal, kelengketan pemenang,
/// kegagalan total setelah ketiga anak — dengan percobaan & resolusi palsu.
void main() {
  const track = Track(
      key: TrackKey('ytmusic', 'x'), title: 'Uji', artistNames: 'A', playableRef: 'x');
  StreamInfo info(String url) => StreamInfo(
      url: url, mimeType: 'audio/webm', expiresAt: DateTime.now().add(const Duration(hours: 1)));

  LoadLadder ladder({
    Future<StreamInfo> Function(Track)? adaptive,
    Future<StreamInfo?> Function(Track)? muxed,
    bool Function(Track)? isLocal,
  }) =>
      LoadLadder(
        resolveAdaptive: adaptive ?? (t) async => info('https://contoh/adaptif'),
        resolveMuxed: muxed ?? (t) async => info('https://contoh/muxed'),
        tagFor: (t) => 'tag-${t.id}',
        isLocal: isLocal ?? ((t) => false),
      );

  group('run: urutan & kelengketan', () {
    test('semua anak gagal → percobaan [0,1,2] lalu melempar galat terakhir', () async {
      final l = ladder();
      final tried = <int>[];
      final failed = <int>[];
      await expectLater(
        l.run(
          attempt: (rung) async {
            tried.add(rung);
            throw StateError('gagal-$rung');
          },
          onRungFailed: (rung, e, st) => failed.add(rung),
        ),
        throwsA(predicate((e) => e.toString().contains('gagal-2'))),
      );
      expect(tried, [0, 1, 2]);
      expect(failed, [0, 1, 2]);
      expect(l.stickyRung, 0); // tak ada pemenang: lengket tidak bergerak
    });

    test('berhasil di anak 1 → pemenang lengket; pemuatan berikut mulai dari 1', () async {
      final l = ladder();
      final tried1 = <int>[];
      final winner = await l.run(attempt: (rung) async {
        tried1.add(rung);
        if (rung == 0) throw StateError('anak 0 gugur');
      });
      expect(winner, 1);
      expect(tried1, [0, 1]);
      expect(l.stickyRung, 1);

      final tried2 = <int>[];
      final winner2 = await l.run(attempt: (rung) async {
        tried2.add(rung);
      });
      expect(winner2, 1);
      expect(tried2, [1]); // langsung dari pemenang, anak 0 tidak dicoba ulang
    });

    test('pemenang 2 lalu semua gagal → rotasi [2,0,1] (ketiga anak tetap dicoba)', () async {
      final l = ladder();
      await l.run(attempt: (rung) async {
        if (rung != 2) throw StateError('belum');
      });
      expect(l.stickyRung, 2);
      final tried = <int>[];
      await expectLater(
        l.run(attempt: (rung) async {
          tried.add(rung);
          throw StateError('semua gugur');
        }),
        throwsStateError,
      );
      expect(tried, [2, 0, 1]);
    });

    test('advance memutar pemenang satu anak', () {
      final l = ladder();
      expect(l.advance(), 1);
      expect(l.advance(), 2);
      expect(l.advance(), 0);
      expect(l.orderForAttempt(), [0, 1, 2]);
    });
  });

  group('childFor', () {
    test('anak 0: URI adaptif dengan header pasangan (UA + Referer)', () async {
      final src = await ladder().childFor(track, LoadLadder.rungAdaptiveUri, strict: true);
      expect(src, isA<UriAudioSource>());
      final uri = src as UriAudioSource;
      expect(uri.uri.toString(), 'https://contoh/adaptif');
      expect(uri.headers?['User-Agent'], ResolvingAudioSource.playerUserAgent);
      expect(uri.headers?['Referer'], 'https://music.youtube.com/');
    });

    test('anak 0 ketat: kegagalan resolusi DILEMPAR (tangga harus tahu)', () async {
      final l = ladder(adaptive: (t) async => throw StateError('resolusi mati'));
      await expectLater(l.childFor(track, 0, strict: true), throwsStateError);
    });

    test('anak 0 longgar: kegagalan resolusi menurun ke proxy untuk trek itu', () async {
      final l = ladder(adaptive: (t) async => throw StateError('resolusi mati'));
      final src = await l.childFor(track, 0);
      expect(src, isA<ResolvingAudioSource>());
    });

    test('anak 1: URI muxed dengan header yang sama', () async {
      final src = await ladder().childFor(track, LoadLadder.rungMuxedUri, strict: true);
      final uri = src as UriAudioSource;
      expect(uri.uri.toString(), 'https://contoh/muxed');
      expect(uri.headers?['User-Agent'], ResolvingAudioSource.playerUserAgent);
    });

    test('anak 1 ketat tanpa muxed → StateError; longgar → proxy', () async {
      final l = ladder(muxed: (t) async => null);
      await expectLater(l.childFor(track, 1, strict: true), throwsStateError);
      expect(await l.childFor(track, 1), isA<ResolvingAudioSource>());
    });

    test('anak 2: selalu proxy', () async {
      expect(await ladder().childFor(track, LoadLadder.rungProxy), isA<ResolvingAudioSource>());
    });

    test('trek lokal melewati tangga di semua anak', () async {
      const local = Track(
          key: TrackKey('local', '7'),
          title: 'Lokal',
          artistNames: 'B',
          playableRef: 'content://media/external/audio/media/7');
      final l = ladder(isLocal: (t) => t.providerId == 'local');
      for (final rung in [0, 1, 2]) {
        final src = await l.childFor(local, rung, strict: true);
        expect(src, isA<UriAudioSource>());
        expect((src as UriAudioSource).uri.scheme, 'content');
      }
    });
  });
}
