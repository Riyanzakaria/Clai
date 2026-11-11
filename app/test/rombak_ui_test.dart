// Kampanye Rombak UI Total (perintah pemilik 2026-11-09 23:51) —
// Batch 1: (a) geometri daerah lukis chrome transparan: sisi mini
// player HARUS bebas lukisan (konten bergulir menembus), daerah di
// balik kartu & di bawah kartu TETAP terlukis (fade anti-hantu zona
// nav dipertahankan); (b) Beranda gabungan: jendela minggu Senin,
// baris tanggal, dan kejujuran rak "Paling sering minggu ini"
// (hitungan mentah playback_events DALAM jendela; minggu kosong =
// kosong).
import 'dart:io';

import 'package:clai/app.dart';
import 'package:clai/data/app_db.dart';
import 'package:clai/domain/models.dart';
import 'package:clai/services/waveform.dart';
import 'package:clai/ui/home_screen.dart';
import 'package:clai/ui/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Track _t(String id) => Track(
  key: TrackKey('ytmusic', id),
  title: 'Lagu $id',
  artistNames: 'Artis',
  duration: const Duration(minutes: 2),
  playableRef: id,
);

/// Tanam satu peristiwa putar pada waktu pilihan (baris mentah —
/// `logPlayback` selalu memakai waktu sekarang).
/// DB uji terisolasi per tes: berkas temp sendiri (membuka
/// ':memory:' dua kali dalam satu proses ffi berbagi basis data
/// yang sama, jadi peristiwa antar-tes bisa bocor).
Future<AppDb> _freshDb() async {
  final db = AppDb();
  final dir = await Directory.systemTemp.createTemp('rombak_ui');
  await db.openAt('${dir.path}/test.db');
  return db;
}

/// Tanam satu peristiwa putar pada waktu pilihan (baris mentah —
/// `logPlayback` selalu memakai waktu sekarang).
Future<void> _seedPlay(AppDb db, String id, DateTime at) async {
  final t = _t(id);
  await db.cacheTracks([t]);
  final d = await db.db;
  await d.insert('playback_events', {
    'provider_id': t.providerId,
    'provider_track_id': t.id,
    'started_at': at.millisecondsSinceEpoch,
    'listened_ms': 60000,
    'completed': 0,
  });
}

void main() {
  group(
    'chromeBackingRects — geometri daerah lukis (Koreksi Chrome 2; sejak 8046 hanya warisan)',
    () {
      // Putusan pemilik 2026-11-10 atas 8042: plat di belakang kartu
      // IKUT HILANG (melengkapi pembebasan sisi 11:18). Bingkai uji:
      // lebar 360, tinggi lukis 200, tepi bawah kartu y=64 (tema
      // hidup) → strip nav mulai y=65. Titik uji:
      //  • titik balik kartu (x=180, y=32): TIDAK terlukis lagi —
      //    kartu melayang penuh di atas konten.
      //  • titik sisi (x=6, y=32): tidak terlukis (tetap).
      //  • titik celah bawah kartu (x=180, y=64): tidak terlukis.
      //  • titik strip nav (x=180, y=100) & sisinya (x=6, y=100):
      //    terlukis (fade zona nav selebar layar).
      //  • titik inset (x=180, y=199): terlukis (terminal pekat).
      test('hanya fade zona nav yang terlukis', () {
        final rects = chromeBackingRects(
          width: 360,
          height: 200,
          cardBottomY: kMiniPlayerHeight,
        );
        bool covered(Offset p) => rects.any((r) => r.contains(p));
        expect(
          covered(const Offset(180, 32)),
          isFalse,
          reason: 'di balik kartu TIDAK boleh ada plat lagi',
        );
        expect(
          covered(const Offset(6, 32)),
          isFalse,
          reason: 'sisi kiri kartu harus transparan',
        );
        expect(
          covered(const Offset(354, 32)),
          isFalse,
          reason: 'sisi kanan kartu harus transparan',
        );
        expect(
          covered(const Offset(180, 64)),
          isFalse,
          reason: 'celah di bawah kartu ikut bebas',
        );
        expect(
          covered(const Offset(180, 100)),
          isTrue,
          reason: 'strip nav tetap terlukis (fade anti-hantu)',
        );
        expect(
          covered(const Offset(6, 100)),
          isTrue,
          reason: 'fade zona nav selebar layar',
        );
        expect(
          covered(const Offset(180, 199)),
          isTrue,
          reason: 'inset sistem: terminal pekat berlanjut',
        );
      });

      test('tema mati (tuck 16): balik kartu bebas, zona nav terlukis', () {
        final rects = chromeBackingRects(
          width: 360,
          height: 200,
          cardBottomY: kChromeScrimTuck,
        );
        bool covered(Offset p) => rects.any((r) => r.contains(p));
        expect(
          covered(const Offset(180, 8)),
          isFalse,
          reason: 'strip selipan di balik kartu ikut hilang',
        );
        expect(covered(const Offset(6, 8)), isFalse);
        expect(covered(const Offset(180, 50)), isTrue);
        expect(covered(const Offset(180, 199)), isTrue);
      });

      test('margin sisi kartu = konstanta yang dipakai daerah lukis', () {
        // Satu konstanta untuk kartu & daerah lukis: tidak boleh
        // meleset satu sama lain (koreksi geometri 2011 terulang).
        expect(kMiniPlayerSideMargin, 12);
      });
    },
  );

  group('profil fade zona nav — sejak 8046 hanya tema warisan', () {
    double alphaAt(List<Color> colors, List<double> stops, double t) {
      if (t <= stops.first) return colors.first.a;
      if (t >= stops.last) return colors.last.a;
      for (var i = 0; i < stops.length - 1; i++) {
        if (t >= stops[i] && t <= stops[i + 1]) {
          final span = stops[i + 1] - stops[i];
          final f = span == 0 ? 0.0 : (t - stops[i]) / span;
          return colors[i].a + (colors[i + 1].a - colors[i].a) * f;
        }
      }
      return colors.last.a;
    }

    test('warisan: alfa 0 sampai tepi atas strip, monoton naik di '
        'strip, 1.0 di dasar lukisan', () {
      const h = 71.0; // chromeScrimPaintHeight(0) = tuck 16 + 1 + 54
      final g = chromeNavFadeLegacyGradient(null, h, kChromeScrimTuck);
      final colors = g.colors;
      final stops = g.stops;
      expect(colors.map((c) => c.a).toList(), kChromeNavFadeAlphas);
      // Ruas lukisan di atas strip nav (0..17 dp: selipan + celah):
      // datar transparan — tak ada lukisan di pita kartu warisan.
      expect(alphaAt(colors, stops, 0), 0);
      expect(alphaAt(colors, stops, 16 / h), 0);
      expect(alphaAt(colors, stops, 17 / h), 0);
      // Di dalam strip: monoton tak-menurun, berakhir pekat.
      var prev = 0.0;
      for (var dp = 17; dp <= 71; dp += 3) {
        final a = alphaAt(colors, stops, dp / h);
        expect(
          a,
          greaterThanOrEqualTo(prev),
          reason: 'alfa turun di $dp dp — fade tak monoton',
        );
        prev = a;
      }
      expect(prev, 1.0);
      expect(alphaAt(colors, stops, 1.0), 1.0);
    });

    test('profil warisan berbagi hentian & alfa yang sama', () {
      const h = 71.0; // chromeScrimPaintHeight(0) = 16 + 1 + 54
      final g = chromeNavFadeLegacyGradient(null, h, kChromeScrimTuck);
      expect(g.stops, chromeNavFadeStops(h, kChromeScrimTuck));
      expect(g.colors.map((c) => c.a).toList(), kChromeNavFadeAlphas);
      // Terminal warisan = warna scrim lama pada alfa penuh.
      expect(g.colors.last, chromeScrimGradient(null, h).colors.last);
    });
  });

  group('weekStartMonday', () {
    test('Senin → dirinya sendiri pukul 00:00', () {
      // 2026-11-09 adalah Senin.
      final s = weekStartMonday(DateTime(2026, 11, 9, 15, 30));
      expect(s, DateTime(2026, 11, 9));
    });
    test('Rabu → Senin minggu yang sama', () {
      final s = weekStartMonday(DateTime(2026, 11, 11, 9, 0));
      expect(s, DateTime(2026, 11, 9));
    });
    test('Minggu → Senin SEBELUMNYA (minggu berjalan)', () {
      final s = weekStartMonday(DateTime(2026, 11, 8, 23, 59));
      expect(s, DateTime(2026, 11, 2));
    });
  });

  group('homeDateKicker', () {
    test('id: SENIN · 9 NOV untuk Senin 9 Nov 2026', () {
      expect(homeDateKicker(DateTime(2026, 11, 9), 'id'), 'SENIN · 9 NOV');
    });
    test('en: MON · NOV 9', () {
      expect(homeDateKicker(DateTime(2026, 11, 9), 'en'), 'MON · NOV 9');
    });
    test('id: Minggu 8 Nov 2026 → MINGGU · 8 NOV', () {
      expect(homeDateKicker(DateTime(2026, 11, 8), 'id'), 'MINGGU · 8 NOV');
    });
  });

  group('topPlayedSince — kejujuran jendela minggu', () {
    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });

    test('hanya putar DALAM jendela yang terhitung; urutan by count', () async {
      final db = await _freshDb();
      final monday = DateTime(2026, 11, 9); // Senin 00:00
      // Minggu lalu (di luar jendela): 5 putar trek 'lama'.
      for (var i = 0; i < 5; i++) {
        await _seedPlay(db, 'lama', monday.subtract(Duration(hours: 2 + i)));
      }
      // Minggu ini: 'a' 3×, 'b' 2×, 'c' 1×.
      for (var i = 0; i < 3; i++) {
        await _seedPlay(db, 'a', monday.add(Duration(hours: 1 + i)));
      }
      for (var i = 0; i < 2; i++) {
        await _seedPlay(db, 'b', monday.add(Duration(hours: 5 + i)));
      }
      await _seedPlay(db, 'c', monday.add(const Duration(hours: 9)));
      final top = await db.topPlayedSince(monday.millisecondsSinceEpoch);
      expect(top.map((e) => e.track.id), ['a', 'b', 'c']);
      expect(top.map((e) => e.count), [3, 2, 1]);
      expect(
        top.any((e) => e.track.id == 'lama'),
        isFalse,
        reason: 'putaran minggu lalu tidak boleh menyusup',
      );
    });

    test('minggu kosong = daftar kosong (keadaan kosong jujur)', () async {
      final db = await _freshDb();
      final monday = DateTime(2026, 11, 9);
      await _seedPlay(db, 'x', monday.subtract(const Duration(days: 1)));
      final top = await db.topPlayedSince(monday.millisecondsSinceEpoch);
      expect(top, isEmpty);
    });

    test('batas limit dihormati', () async {
      final db = await _freshDb();
      final monday = DateTime(2026, 11, 9);
      for (final id in ['a', 'b', 'c', 'd']) {
        await _seedPlay(db, id, monday.add(const Duration(hours: 1)));
      }
      final top = await db.topPlayedSince(
        monday.millisecondsSinceEpoch,
        limit: 3,
      );
      expect(top.length, 3);
    });
  });

  group('WaveformStrip — kejujuran visual', () {
    testWidgets('data belum terukur: strip tetap dirender (garis datar)', (
      tester,
    ) async {
      final empty = WaveformData.empty;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WaveformStrip(
              data: empty,
              fraction: 0.5,
              playedColor: Colors.green,
              unplayedColor: Colors.grey,
              flatColor: Colors.grey.shade800,
            ),
          ),
        ),
      );
      expect(find.byType(WaveformStrip), findsOneWidget);
      expect(find.byType(CustomPaint), findsWidgets);
    });

    test('displayHeights: ember tak terukur tetap null (bukan 0)', () {
      // Ronde 8050: nilai ember adalah dB MENTAH dan tinggi tampil
      // adalah normalisasi PERSENTIL (p10→lantai, p95→penuh), bukan
      // normalisasi puncak era v2. Semua ember −20 dB kecuali ember 3
      // yang menerima sampel −6 → rata-rata (−20 + −6)/2 = −13 dB.
      final d = WaveformData(
        List<double?>.filled(kWaveformBucketCount, -20.0),
      ).withSample(3, -6);
      final h = d.displayHeights();
      expect(
        h[3],
        closeTo(1.0, 0.02),
        reason: 'ember jauh di atas p95 tampil penuh (spesifikasi)',
      );
      // Massa −20 dB: p10 = p95 = −20 → rentang diperlebar jujur ke
      // 3 dB di sekitar −20 → t = 0,5 → tinggi 0,10 + 0,9×0,5 = 0,55.
      expect(h[0], closeTo(0.55, 0.02));
      final e = WaveformData([null, null]);
      final eh = e.displayHeights();
      expect(eh.length, kWaveformBucketCount);
      expect(
        eh.every((x) => x == null),
        isTrue,
        reason: 'belum terukur tetap null — tidak pernah 0 karangan',
      );
    });
  });
}
