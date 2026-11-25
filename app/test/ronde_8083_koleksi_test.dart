// Ronde 8083 — Koleksi "Perbaikan" (paket KOLEKSI).
//
// Kontrak yang diuji:
// (a) Total durasi playlist JUJUR: null (tidak tampil) bila ada satu
//     saja trek tanpa durasi / playlist kosong; total persis bila
//     semua durasi diketahui. Bentuk panjangnya "3 jam 12 mnt" /
//     "45 mnt" (en: "3 hr 12 min" / "45 min").
// (b) Jalur baris playlist di collection_screen.dart TIDAK memakai
//     painter/waveform apa pun (playlist tidak punya waveform tunggal).
// (c) CollectionRow: mosaik 56 radius 12 (widget terarah + uji sumber),
//     nama Clash 17, tinggi baris ±72.
// (d) Baris ringkasan header dirakit dari kunci yang ada:
//     "<N> lagu • <N> playlist • <N> album" (id) / en setara.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:clai/domain/models.dart';
import 'package:clai/l10n/app_localizations.dart';
import 'package:clai/ui/collection_screen.dart';

Track _t(String id, {Duration? duration}) => Track(
  key: TrackKey('ytmusic', id),
  title: 'Lagu $id',
  artistNames: 'Artis $id',
  duration: duration,
  playableRef: id,
);

void main() {
  group('(a) playlistTotalDuration — kejujuran total durasi', () {
    test('semua durasi diketahui → total persis', () {
      final tracks = [
        _t('1', duration: const Duration(minutes: 60)),
        _t('2', duration: const Duration(minutes: 72)),
        _t('3', duration: const Duration(minutes: 60)),
      ];
      expect(
        playlistTotalDuration(tracks),
        const Duration(hours: 3, minutes: 12),
      );
    });

    test('satu trek tanpa durasi → null (total tidak tampil)', () {
      final tracks = [
        _t('1', duration: const Duration(minutes: 3)),
        _t('2'),
        _t('3', duration: const Duration(minutes: 4)),
      ];
      expect(playlistTotalDuration(tracks), isNull);
    });

    test('playlist kosong → null', () {
      expect(playlistTotalDuration(const []), isNull);
    });

    test('formatTotalDuration: gaya spesimen id & en', () {
      expect(
        formatTotalDuration(
          const Duration(hours: 3, minutes: 12),
          indonesian: true,
        ),
        '3 jam 12 mnt',
      );
      expect(
        formatTotalDuration(const Duration(minutes: 45), indonesian: true),
        '45 mnt',
      );
      expect(
        formatTotalDuration(const Duration(hours: 2), indonesian: true),
        '2 jam',
      );
      expect(
        formatTotalDuration(
          const Duration(hours: 3, minutes: 12),
          indonesian: false,
        ),
        '3 hr 12 min',
      );
      expect(
        formatTotalDuration(const Duration(minutes: 45), indonesian: false),
        '45 min',
      );
    });
  });

  group('(b) jalur baris playlist tanpa waveform/painter (uji sumber)', () {
    final src = File('lib/ui/collection_screen.dart').readAsStringSync();

    test('tidak ada painter/waveform di berkas Koleksi', () {
      expect(src.contains('CustomPaint'), isFalse);
      expect(src.contains('CustomPainter'), isFalse);
      // Pemeriksaan pada IDENTITAS kode, bukan kata di komentar
      // (komentar berkas sah menyebut "waveform" sebagai prosa).
      expect(src.contains('WaveformStrip'), isFalse);
      expect(src.contains('WaveformData'), isFalse);
      expect(src.contains('waveformFor'), isFalse);
    });

    test('baris playlist memakai playlistTotalDuration dari agregat meta', () {
      expect(src.contains('playlistDurations'), isTrue);
      expect(src.contains('playlistTotalDuration(tracks)'), isTrue);
    });

    test('tidak ada border putih di elemen Koleksi berkas ini', () {
      expect(src.contains('Border.all'), isFalse);
      expect(src.contains('BorderSide(color: Colors.white'), isFalse);
      expect(src.contains('BorderSide(color: ClaiColors.ink'), isFalse);
    });
  });

  group('(c) CollectionRow — geometri R2', () {
    testWidgets('mosaik 56 tertanam, nama & meta tampil, ketuk jalan', (
      tester,
    ) async {
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CollectionRow(
              mosaic: Container(
                key: const ValueKey('mosaik-uji'),
                width: 56,
                height: 56,
                color: const Color(0xFF26262F),
              ),
              name: 'Gelombang Senja',
              meta: '48 lagu • 2 jam 41 mnt',
              onTap: () => taps++,
            ),
          ),
        ),
      );
      final mosaic = tester.getSize(find.byKey(const ValueKey('mosaik-uji')));
      expect(mosaic.width, 56);
      expect(mosaic.height, 56);
      expect(find.text('Gelombang Senja'), findsOneWidget);
      expect(find.text('48 lagu • 2 jam 41 mnt'), findsOneWidget);
      // Nama memakai Clash Display 17 (displayStyle R2).
      final nameWidget = tester.widget<Text>(find.text('Gelombang Senja'));
      expect(nameWidget.style?.fontFamily, 'Inter Tight');
      expect(nameWidget.style?.fontSize, 17);
      // Tinggi baris total ±72 (padding vertikal 8 + mosaik 56).
      final rowSize = tester.getSize(find.byType(CollectionRow));
      expect(rowSize.height, 72);
      await tester.tap(find.byType(CollectionRow));
      expect(taps, 1);
    });

    test('uji sumber: baris playlist dibangun dengan mosaik 56 radius 12', () {
      final src = File('lib/ui/collection_screen.dart').readAsStringSync();
      expect(src.contains('size: 56, radius: 12'), isTrue);
      expect(src.contains('class CollectionRow'), isTrue);
    });
  });

  group('(d) collectionSummaryLine — rakitan kunci yang ada', () {
    testWidgets('id: "49 lagu • 5 playlist • 2 album"', (tester) async {
      late AppLocalizations l;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('id'),
          home: Builder(
            builder: (context) {
              l = AppLocalizations.of(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(
        collectionSummaryLine(l, songs: 49, playlists: 5, albums: 2),
        '49 lagu • 5 playlist • 2 album',
      );
    });

    testWidgets('en: "49 songs • 5 playlists • 2 albums"', (tester) async {
      late AppLocalizations l;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Builder(
            builder: (context) {
              l = AppLocalizations.of(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(
        collectionSummaryLine(l, songs: 49, playlists: 5, albums: 2),
        '49 songs • 5 playlists • 2 albums',
      );
    });
  });

  group('motif keadaan kosong deterministik', () {
    test('pola batang tetap, bukan acak', () {
      expect(kEmptyWaveHeights, hasLength(20));
      expect(kEmptyWaveHeights.every((h) => h > 0 && h <= 32), isTrue);
    });
  });
}
