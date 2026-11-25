import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:clai/app.dart';
import 'package:clai/data/app_db.dart';
import 'package:clai/domain/models.dart';
import 'package:clai/l10n/app_localizations.dart';
import 'package:clai/ui/taste_control_screen.dart';
import 'package:clai/ui/widgets.dart';

/// Ronde 8089 — kontrak yang dijaga:
/// (A) font tampilan Inter Tight (dirinci di font_tampilan_8089_test);
/// (C) pola kepala baku layar dorong: AppBarTheme centerTitle + judul
///     font tampilan, helper claiPushedAppBar membawa ClaiBackButton;
/// (D) wajah baris utilitas: gaya judul panel & pintu hub memakai font
///     tampilan [kRowTitleSize] (17 pada 8089; sempat 14 di Ronde 8090,
///     dipulihkan ke 17 oleh Ronde 8091 — vonis perangkat pemilik
///     25 Nov 2026 19:14), pintu laci tepat 68 (pitch disiplin DS §14.6);
/// (B) sumber sampul Cermin Panggung: sampul per artis = artwork trek
///     paling sering diputar milik artis itu (memberi jalan ke trek
///     berikutnya ber-artwork; tanpa artwork → null → ubin motif), dan
///     hero Selera merender numeral '01' TANPA progress bar per artis.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('Bagian C — kepala baku', () {
    // testWidgets: buildClaiTheme memakai GoogleFonts (preseden
    // kedip_beranda_8085_test.dart).
    testWidgets('tema: AppBar judul tengah + font tampilan 700',
        (tester) async {
      final theme = buildClaiTheme();
      expect(theme.appBarTheme.centerTitle, isTrue);
      expect(theme.appBarTheme.titleTextStyle?.fontFamily, 'Inter Tight');
      expect(theme.appBarTheme.titleTextStyle?.fontWeight, FontWeight.w700);
    });

    testWidgets('claiPushedAppBar: judul tengah, chevron Clai, 1 baris',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('id'),
          home: Builder(
            builder: (context) => Scaffold(
              appBar: claiPushedAppBar(context, 'Selera kamu'),
              body: const SizedBox(),
            ),
          ),
        ),
      );
      final bar = tester.widget<AppBar>(find.byType(AppBar));
      expect(bar.centerTitle, isTrue);
      expect(bar.backgroundColor, Colors.transparent);
      expect(find.byType(ClaiBackButton), findsOneWidget);
      final title = tester.widget<Text>(find.text('Selera kamu'));
      expect(title.maxLines, 1);
      expect(title.overflow, TextOverflow.ellipsis);
      // Judul benar-benar di tengah layar (800 dp permukaan uji).
      expect(tester.getCenter(find.text('Selera kamu')).dx,
          closeTo(400, 1.5));
    });
  });

  group('Bagian D — wajah baris utilitas (sumber)', () {
    String src(String p) => File(p).readAsStringSync();

    // Ukuran judul baris utilitas hidup di konstanta bersama
    // kRowTitleSize lewat gaya bersama rowTitleStyle (ronde 8090
    // memusatkan; ronde 8091 memulihkan angkanya ke 17).
    test('panel Pengaturan: judul font tampilan kRowTitleSize/700', () {
      final s = src('lib/ui/settings_screen.dart');
      expect(s, contains('fontFamily: kDisplayFontFamily'));
      expect(s, contains('fontSize: kRowTitleSize'));
      expect(s, contains('rowTitleStyle()'),
          reason: 'pintu hub memakai gaya judul baris bersama');
    });

    test('laci Menu: pintu tepat 68 + judul font tampilan', () {
      final s = src('lib/ui/menu_drawer.dart');
      expect(s, contains('height: 68'));
      expect(s, contains('rowTitleStyle()'));
    });

    test('8091: kRowTitleSize = 17 (pulihan kontrak 8089), Inter Tight 700',
        () {
      expect(kRowTitleSize, 17);
      final st = rowTitleStyle();
      expect(st.fontSize, 17);
      expect(st.fontWeight, FontWeight.w700);
      expect(st.fontFamily, 'Inter Tight');
    });

    test('8090: affordance kembali = chevronLeft murni', () {
      final icons = src('lib/core/clai_icons.dart');
      expect(icons, contains('chevronLeft'));
      final w = src('lib/ui/widgets.dart');
      expect(w, contains('ClaiIcons.chevronLeft'),
          reason: 'ClaiBackButton + GlassBackChip memakai chevronLeft');
      expect(w, isNot(contains('ClaiIcons.arrowBack')),
          reason: 'tidak ada lagi affordance kembali berbatang panah');
      expect(src('lib/ui/qr_scan_screen.dart'),
          contains('ClaiIcons.chevronLeft'));
    });

    test('Selera: tanpa progress bar per artis; ada widget sampul motif',
        () {
      final s = src('lib/ui/taste_control_screen.dart');
      expect(s, isNot(contains('LinearProgressIndicator')),
          reason: 'progress bar per artis pensiun di Cermin Panggung');
      expect(s, contains('_ArtistCover'));
      expect(s, contains('topArtistCovers'));
    });
  });

  group('Bagian B — sumber sampul per artis', () {
    late Directory dir;
    late AppDb db;
    late Database raw;

    Track mk(String id, String artist, String? art) => Track(
          key: TrackKey('ytmusic', id),
          title: 'Lagu $id',
          artistNames: artist,
          playableRef: id,
          duration: const Duration(minutes: 3),
          artworkUrl: art,
        );

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('sampul8089');
      db = AppDb();
      raw = await db.openAt('${dir.path}/t.db');
      // Artis X: trek x1 (5 putar, TANPA artwork) di atas x2 (3 putar,
      // ber-artwork) → sampul harus jatuh ke x2. Artis Y: y1 (2 putar,
      // ber-artwork). Artis Z: z1 (1 putar, tanpa artwork) → null.
      await db.cacheTracks([
        mk('x1', 'Artis X', null),
        mk('x2', 'Artis X', 'https://img/x2.jpg'),
        mk('y1', 'Artis Y', 'https://img/y1.jpg'),
        mk('z1', 'Artis Z', null),
      ]);
      Future<void> seed(String id, int n) async {
        for (var i = 0; i < n; i++) {
          await raw.insert('playback_events', {
            'provider_id': 'ytmusic',
            'provider_track_id': id,
            'started_at': 1000000 + i * 1000,
            'listened_ms': 90000,
            'completed': 1,
          });
        }
      }

      await seed('x1', 5);
      await seed('x2', 3);
      await seed('y1', 2);
      await seed('z1', 1);
    });

    tearDown(() async {
      await db.close();
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    test('pemenang ber-artwork per artis; tanpa artwork → null', () async {
      final covers = await db.topTrackArtworkByArtist();
      expect(covers['Artis X'], 'https://img/x2.jpg',
          reason: 'x1 terbanyak tapi tanpa artwork → x2 yang dipakai');
      expect(covers['Artis Y'], 'https://img/y1.jpg');
      expect(covers['Artis Z'], isNull);
    });
  });

  group('Bagian B — hero Selera (widget)', () {
    late Directory dir;
    late AppDb db;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('selera8089');
      db = AppDb();
      await db.openAt('${dir.path}/t.db');
    });

    tearDown(() async {
      await db.close();
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    testWidgets('hero merender 01 + nama artis, tanpa progress bar',
        (tester) async {
      await tester.runAsync(() async {
        final x = Track(
          key: const TrackKey('ytmusic', 'hx'),
          title: 'Lagu HX',
          artistNames: 'Artis Hero',
          playableRef: 'hx',
          duration: const Duration(minutes: 3),
        );
        await db.cacheTracks([x]);
        for (var i = 0; i < 4; i++) {
          await db.logPlayback(x,
              listenedMs: 90000, completed: true, contextKind: 'search');
        }
        await tester.pumpWidget(
          ProviderScope(
            overrides: [appDbProvider.overrideWithValue(db)],
            child: const MaterialApp(
              localizationsDelegates:
                  AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              locale: Locale('id'),
              home: TasteControlScreen(),
            ),
          ),
        );
        for (var i = 0; i < 150; i++) {
          await tester.pump(const Duration(milliseconds: 100));
          if (find.text('01').evaluate().isNotEmpty) break;
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
        expect(find.text('01'), findsOneWidget,
            reason: 'numeral editorial hero peringkat 1');
        expect(find.text('Artis Hero'), findsWidgets);
        expect(find.byType(LinearProgressIndicator), findsNothing,
            reason: 'progress bar per artis sudah pensiun');
        // Beri rantai tag genre malas waktu menetap sebelum tearDown.
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 100));
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
      });
    });
  });
}
