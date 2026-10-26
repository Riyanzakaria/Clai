import 'package:clai/domain/models.dart';
import 'package:clai/l10n/app_localizations.dart';
import 'package:clai/l10n/app_localizations_en.dart';
import 'package:clai/l10n/app_localizations_id.dart';
import 'package:clai/player/queue_engine.dart';
import 'package:clai/player/similarity.dart';
import 'package:clai/services/sleep_service.dart';
import 'package:clai/ui/mini_player.dart';
import 'package:clai/ui/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Track t(String id, String artist,
        {String provider = 'ytmusic',
        Duration? duration = const Duration(minutes: 3, seconds: 20)}) =>
    Track(
        key: TrackKey(provider, id),
        title: 'Lagu $id',
        artistNames: artist,
        duration: duration,
        playableRef: provider == 'local' ? '/data/$id.mp3' : id);

void main() {
  group('gateRadioBatch (halaman Radio F2.5)', () {
    final seed = t('seed1', 'Sombr');

    test('benih sendiri & versi lain lagu benih dibuang', () {
      final raw = [
        t('seed1', 'Sombr'), // benih itu sendiri
        t('lain', 'Sombr'), // versi lain? judul beda → lolos
        Track(
            key: const TrackKey('ytmusic', 'seed1remaster'),
            title: 'Lagu seed1 (Remastered)',
            artistNames: 'Sombr',
            duration: const Duration(minutes: 3),
            playableRef: 'seed1remaster'),
      ];
      final out = gateRadioBatch(seed, raw);
      expect(out.map((e) => e.id), ['lain']);
    });

    test('non-musik & durasi ekstrem tersaring gerbang', () {
      final raw = [
        t('ok', 'Artis Lain'),
        Track(
            key: const TrackKey('ytmusic', 'pod'),
            title: 'Podcast santai',
            artistNames: 'Pod',
            duration: const Duration(minutes: 40),
            playableRef: 'pod'),
        Track(
            key: const TrackKey('ytmusic', 'mix'),
            title: 'DJ Mix 2026',
            artistNames: 'DJ',
            duration: const Duration(minutes: 58),
            playableRef: 'mix'),
        Track(
            key: const TrackKey('ytmusic', 'clip'),
            title: 'Klip pendek',
            artistNames: 'Klip',
            duration: const Duration(seconds: 12),
            playableRef: 'clip'),
      ];
      final out = gateRadioBatch(seed, raw);
      expect(out.map((e) => e.id), ['ok']);
    });

    test('duplikat kunci & versi dibuang, urutan sumber dipertahankan', () {
      final raw = [t('b', 'B'), t('a', 'A'), t('b', 'B')];
      final out = gateRadioBatch(seed, raw);
      expect(out.map((e) => e.id), ['b', 'a']);
    });
  });

  group('playRadioFromPage (mesin antrean)', () {
    test('jangkar benih tetap; item diketuk jadi current; lanjutan sesudahnya',
        () {
      final e = QueueEngine();
      final seed = t('s', 'Benih');
      final page = [t('p1', 'A'), t('p2', 'B'), t('p3', 'C')];
      e.playRadioFromPage(seed: seed, page: page, startIndex: 1);
      expect(e.seeds.map((x) => x.id), ['s']);
      expect(e.context?.kind, 'radio');
      expect(e.current?.id, 'p2');
      expect(e.continuation.map((x) => x.id), ['p3']);
      expect(e.fullQueue.first.id, 'p2');
    });

    test('antrean manual dipertahankan (D-17)', () {
      final e = QueueEngine();
      e.playContext(
          PlayContext(kind: 'search', label: 'x', tracks: [t('a', 'A')]), 0);
      e.enqueueLater(t('m', 'M'));
      e.playRadioFromPage(seed: t('s', 'S'), page: [t('p', 'P')], startIndex: 0);
      expect(e.manual.map((x) => x.id), ['m']);
    });
  });

  group('teks berbagi (Pamer tingkat 1)', () {
    final AppLocalizations id10n = AppLocalizationsId();
    final AppLocalizations en10n = AppLocalizationsEn();

    test('trek katalog: 3 baris persis (judul — artis, tautan, kredit)', () {
      final s = claiTrackShareText(t('abc123', 'Sombr'), id10n);
      final lines = s.split('\n');
      expect(lines.length, 3);
      expect(lines[0], 'Lagu abc123 — Sombr');
      expect(lines[1], 'https://music.youtube.com/watch?v=abc123');
      expect(lines[2], contains('Clai'));
      expect(lines[2], contains(kClaiEvergreenApkUrl));
      expect(kClaiEvergreenApkUrl,
          'https://github.com/Riyanzakaria/Clai/releases/latest/download/clai.apk');
    });

    test('trek lokal: tanpa tautan katalog (tidak mengarang)', () {
      final s = claiTrackShareText(t('f1', 'Lokal', provider: 'local'), id10n);
      expect(s.contains('music.youtube.com'), isFalse);
      expect(s.split('\n').length, 2);
      expect(s, contains(kClaiEvergreenApkUrl));
    });

    test('kredit Inggris memakai teks Inggris', () {
      final s = claiTrackShareText(t('abc123', 'Sombr'), en10n);
      expect(s, contains('Shared via Clai'));
    });

    test('berbagi halaman: judul — subjudul + kredit, tanpa tautan tonton',
        () {
      final s = claiPageShareText('Album X', 'Artis Y', id10n);
      expect(s.split('\n').first, 'Album X — Artis Y');
      expect(s, contains(kClaiEvergreenApkUrl));
      expect(s.contains('watch?v='), isFalse);
    });
  });

  group('jendela peredupan tidur', () {
    test('timer panjang dibatasi 30 detik', () {
      expect(sleepFadeWindowFor(const Duration(minutes: 60)),
          const Duration(seconds: 30));
      expect(sleepFadeWindowFor(const Duration(minutes: 15)),
          const Duration(seconds: 30));
    });
    test('timer pendek proporsional (seperempat masa)', () {
      expect(sleepFadeWindowFor(const Duration(seconds: 60)),
          const Duration(seconds: 15));
      expect(sleepFadeWindowFor(const Duration(seconds: 20)),
          const Duration(seconds: 5));
      expect(sleepFadeWindowFor(const Duration(seconds: 8)),
          const Duration(seconds: 2));
    });
    test('nol/negatif = tanpa jendela', () {
      expect(sleepFadeWindowFor(Duration.zero), Duration.zero);
    });
  });

  group('keputusan geser mini player', () {
    const w = 400.0; // ambang 35% = 140
    test('geser melewati 35% = ganti lagu', () {
      expect(miniSwipeDecision(offsetX: -140, width: w), MiniSwipeAction.next);
      expect(
          miniSwipeDecision(offsetX: -260, width: w), MiniSwipeAction.next);
      expect(miniSwipeDecision(offsetX: 140, width: w),
          MiniSwipeAction.previous);
    });
    test('lepas di bawah ambang (pelan) = tidak ada aksi (berpegas kembali)',
        () {
      expect(miniSwipeDecision(offsetX: -100, width: w, velocityX: -80),
          MiniSwipeAction.none);
      expect(miniSwipeDecision(offsetX: 60, width: w), MiniSwipeAction.none);
      expect(miniSwipeDecision(offsetX: 0, width: w), MiniSwipeAction.none);
    });
    test('fling cepat warisan tetap diakui di bawah ambang jarak', () {
      expect(miniSwipeDecision(offsetX: -60, width: w, velocityX: -900),
          MiniSwipeAction.next);
      expect(miniSwipeDecision(offsetX: 60, width: w, velocityX: 900),
          MiniSwipeAction.previous);
      // fling berlawanan arah dengan geseran tidak diakui
      expect(miniSwipeDecision(offsetX: -60, width: w, velocityX: 900),
          MiniSwipeAction.none);
    });
    test('lebar tak sah = none', () {
      expect(miniSwipeDecision(offsetX: -500, width: 0), MiniSwipeAction.none);
    });
  });
}
