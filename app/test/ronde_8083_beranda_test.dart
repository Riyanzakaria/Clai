// Ronde 8083 — Paket Beranda (Susunan Baru).
//
// Kontrak yang diuji:
// (a) Urutan _buildModern: Brankas Sesi (SessionShelf) TEPAT SESUDAH
//     blok kartu Lanjutkan dan SEBELUM Cepat Putar (Cacat A); pita
//     fitur artis tepat sesudah _topWeekSection.
// (b) Jalur Beranda di ketiga berkas paket ini TANPA border/garis tepi
//     elemen: tidak ada Border.all / Border(...) / warna putih tepi.
// (c) Baris Terakhir Diputar (RecentWaveRow): tanpa data waveform
//     tersimpan → painter gelombang TIDAK digambar; dengan data
//     terukur → WaveformStrip tampil.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:clai/domain/models.dart';
import 'package:clai/services/waveform.dart';
import 'package:clai/ui/home_screen.dart';
import 'package:clai/ui/widgets.dart';

String _src(String path) => File(path).readAsStringSync();

/// Potongan sumber _buildModern saja (dari tanda tangan metode sampai
/// metode berikutnya, _greetingHeader).
String _modernSource() {
  final src = _src('lib/ui/home_screen.dart');
  final start = src.indexOf('Widget _buildModern(BuildContext context)');
  expect(start, greaterThanOrEqualTo(0), reason: '_buildModern hilang');
  final end = src.indexOf('Widget _greetingHeader', start);
  expect(end, greaterThan(start), reason: '_greetingHeader hilang');
  return src.substring(start, end);
}

Track _t(String id) => Track(
  key: TrackKey('ytmusic', id),
  title: 'Lagu $id',
  artistNames: 'Artis $id',
  duration: const Duration(minutes: 3),
  playableRef: id,
);

void main() {
  group('Ronde 8083 — urutan _buildModern (uji sumber terarah)', () {
    test('SessionShelf sesudah kartu Lanjutkan, sebelum Cepat Putar', () {
      final modern = _modernSource();
      final continueIdx = modern.indexOf(
        'return _continueCard(context, item);',
      );
      final shelfIdx = modern.indexOf('const SessionShelf()');
      final quickIdx = modern.indexOf('_quickPlaySection(context)');
      expect(continueIdx, greaterThanOrEqualTo(0));
      expect(
        shelfIdx,
        greaterThan(continueIdx),
        reason: 'Brankas harus SESUDAH blok kartu Lanjutkan',
      );
      expect(
        quickIdx,
        greaterThan(shelfIdx),
        reason: 'Brankas harus SEBELUM Cepat Putar',
      );
      // Brankas hanya muncul sekali di modern (tidak lagi di atas hero).
      expect('const SessionShelf()'.allMatches(modern).length, 1);
    });

    test('pita artis sesudah _topWeekSection; daftar sidik & rel besar '
        'menggantikan dua CoverRail lama', () {
      final modern = _modernSource();
      final topWeekIdx = modern.indexOf('_topWeekSection(context)');
      final artistIdx = modern.indexOf('const PersonalArtistRail()');
      expect(topWeekIdx, greaterThanOrEqualTo(0));
      expect(
        artistIdx,
        greaterThan(topWeekIdx),
        reason: 'PersonalArtistRail naik tepat sesudah Paling Sering',
      );
      expect(
        modern.contains('_recentWaveList(context)'),
        isTrue,
        reason: 'Terakhir Diputar harus daftar baris sidik gelombang',
      );
      expect(
        modern.contains('_playAgainRail(context)'),
        isTrue,
        reason: 'Putar Lagi harus rel sampul besar lokal',
      );
      expect(
        modern.contains('_collectionMosaicStrip(context)'),
        isTrue,
        reason: 'Koleksi Kamu harus strip ubin mosaik',
      );
      expect(
        modern.contains('CoverRail('),
        isFalse,
        reason: 'tidak ada lagi CoverRail generik di _buildModern',
      );
    });
  });

  group('Ronde 8083 — Beranda tanpa border putih/garis tepi', () {
    for (final path in [
      'lib/ui/home_screen.dart',
      'lib/ui/personal_shelves_section.dart',
      'lib/ui/jelajah_section.dart',
    ]) {
      test('$path: tanpa Border.all / Border sisi / Colors.white', () {
        final src = _src(path);
        expect(src.contains('Border.all('), isFalse);
        expect(src.contains('Border.fromBorderSide'), isFalse);
        expect(src.contains('Colors.white'), isFalse);
        // "Border(" polos (bukan BorderRadius) = garis tepi elemen.
        expect(RegExp(r'Border\(').hasMatch(src), isFalse);
        expect(src.contains('side: BorderSide'), isFalse);
      });
    }

    test('tidak ada kicker lokal DimKicker di berkas paket Beranda', () {
      for (final path in [
        'lib/ui/home_screen.dart',
        'lib/ui/personal_shelves_section.dart',
        'lib/ui/jelajah_section.dart',
      ]) {
        expect(_src(path).contains('DimKicker'), isFalse, reason: path);
      }
    });
  });

  group('Ronde 8083 — RecentWaveRow sidik gelombang jujur', () {
    Widget tree(WaveformData? data) => MaterialApp(
      home: Scaffold(
        body: RecentWaveRow(track: _t('r1'), waveform: data, onTap: () {}),
      ),
    );

    testWidgets('tanpa data waveform → painter gelombang TIDAK digambar', (
      tester,
    ) async {
      await tester.pumpWidget(tree(null));
      await tester.pump();
      expect(
        find.byType(WaveformStrip),
        findsNothing,
        reason:
            'painter gelombang (WaveformStrip) tidak boleh '
            'digambar untuk trek tanpa data waveform tersimpan',
      );
      // Barisnya sendiri tetap tampil utuh.
      expect(find.text('Lagu r1'), findsOneWidget);
      expect(find.text('Artis r1'), findsOneWidget);
    });

    testWidgets('data kosong (0 terukur) → tetap tanpa sidik', (tester) async {
      await tester.pumpWidget(tree(WaveformData.empty));
      await tester.pump();
      expect(find.byType(WaveformStrip), findsNothing);
    });

    testWidgets('data terukur tersimpan → WaveformStrip tampil', (
      tester,
    ) async {
      final measured = WaveformData(
        List<double?>.filled(kWaveformBucketCount, -18.0),
      );
      expect(measured.measuredCount, kWaveformBucketCount);
      await tester.pumpWidget(tree(measured));
      await tester.pump();
      expect(find.byType(WaveformStrip), findsOneWidget);
    });

    test('gerbang hasWaveform murni', () {
      final empty = RecentWaveRow(
        track: _t('r2'),
        waveform: WaveformData.empty,
        onTap: () {},
      );
      expect(empty.hasWaveform, isFalse);
      final measured = RecentWaveRow(
        track: _t('r2'),
        waveform: WaveformData(
          List<double?>.filled(kWaveformBucketCount, -20.0),
        ),
        onTap: () {},
      );
      expect(measured.hasWaveform, isTrue);
    });
  });
}
