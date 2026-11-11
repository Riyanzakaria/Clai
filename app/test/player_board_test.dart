import 'dart:math' as math;

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:clai/app.dart';
import 'package:clai/core/clai_icons.dart';
import 'package:clai/data/app_db.dart';
import 'package:clai/domain/models.dart';
import 'package:clai/l10n/app_localizations.dart';
import 'package:clai/l10n/app_localizations_id.dart';
import 'package:clai/player/queue_engine.dart';
import 'package:clai/services/ambient_theme.dart';
import 'package:clai/services/ambient_controller.dart';
import 'package:clai/services/waveform.dart';
import 'package:clai/ui/player_sheet.dart';

/// Ronde Player B — komposisi papan B dalam bahasa kita (keputusan
/// pemilik 2026-11-09 22:22; kemudi 22:31: baris atas keping kaca
/// 8038): tata letak murni, judul menyusut (perbaikan cacat potong
/// 8038), waveform ukur yang bisa diseret, dan kehadiran semua fungsi
/// (tutup, ⋮, suka, vinil, transportasi, slot status, dok berlabel,
/// strip Putar Otomatis).
void main() {
  group('playerBoardLayout — sampul elastis terjepit lebar', () {
    test('metrik pemilik 360×752 ts 1: muat persis, sampul 260 (papan)',
        () {
      final l = playerBoardLayout(
          maxWidth: 360, maxHeight: 752, textScale: 1, autoplay: false);
      expect(l.contentHeight, closeTo(752, 0.01));
      expect(l.cover, closeTo(260, 0.01),
          reason: 'lebar 360 − margin 16 − jalur intip 68 − margin 16');
      expect(l.spacer, greaterThan(0));
    });

    test('strip Putar Otomatis ramping: sampul pulih ke batas lebar (G-3)',
        () {
      // Era kartu penuh: banner ±117 dp menekan sampul ke ±209.
      // Strip satu baris (34 dp) mengembalikan ±51 dp — sampul
      // kembali dibatasi LEBAR (260, proporsi papan B), bukan banner.
      final l = playerBoardLayout(
          maxWidth: 360, maxHeight: 752, textScale: 1, autoplay: true);
      expect(l.contentHeight, closeTo(752, 0.01));
      expect(l.cover, closeTo(260, 0.01));
      expect(l.spacer, greaterThan(0));
    });

    test('layar pendek: sampul menyentuh lantai 170, konten digulir',
        () {
      final l = playerBoardLayout(
          maxWidth: 360, maxHeight: 480, textScale: 1, autoplay: false);
      expect(l.cover, 170);
      expect(l.contentHeight, greaterThan(480));
    });

    test('layar lebar: sampul dibatasi tinggi, bukan lebar', () {
      final l = playerBoardLayout(
          maxWidth: 600, maxHeight: 752, textScale: 1, autoplay: false);
      expect(l.cover, greaterThan(260));
      expect(l.cover, lessThanOrEqualTo(470));
      expect(l.contentHeight, closeTo(752, 0.01));
    });

    test('skala teks 1,6 tetap terjepit dan tidak negatif', () {
      final l = playerBoardLayout(
          maxWidth: 360, maxHeight: 752, textScale: 1.6, autoplay: true);
      expect(l.cover, inInclusiveRange(170, 260));
      expect(l.spacer, greaterThanOrEqualTo(0));
    });
  });

  group('titleScaleForWidth — judul menyusut, dilantai 0,68', () {
    test('muat → 1; sempit → proporsional; sangat sempit → lantai', () {
      expect(titleScaleForWidth(200, 300), 1.0);
      expect(titleScaleForWidth(300, 300), 1.0);
      expect(titleScaleForWidth(400, 300), closeTo(0.75, 1e-9));
      expect(titleScaleForWidth(900, 300), closeTo(0.68, 1e-9));
      expect(titleScaleForWidth(0, 300), 1.0);
      expect(titleScaleForWidth(300, 0), 1.0);
    });
  });

  group('WaveformSeekBar — seek di atas data ukur', () {
    Widget host({
      required void Function(Duration) onSeek,
      required WaveformData data,
    }) {
      return MaterialApp(
        locale: const Locale('id'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: 360,
              child: WaveformSeekBar(
                position: const Duration(seconds: 50),
                duration: const Duration(seconds: 200),
                onSeek: onSeek,
                tone: const Color(0xFFE05252),
                data: data,
              ),
            ),
          ),
        ),
      );
    }

    WaveformData partial() {
      var d = WaveformData.empty;
      for (var i = 0; i < 14; i++) {
        d = d.withSample(i, -30.0 + (i % 5) * 3.0);
      }
      return d;
    }

    testWidgets('seret 25% → 75%: gelembung tampil, lepas = seek',
        (tester) async {
      Duration? sought;
      await tester.pumpWidget(
          host(onSeek: (d) => sought = d, data: partial()));
      final box = tester.getRect(find.byType(WaveformSeekBar));
      final y = box.top + 24;
      final gesture =
          await tester.startGesture(Offset(box.left + box.width * 0.25, y));
      await gesture.moveTo(Offset(box.left + box.width * 0.75, y));
      await tester.pump();
      expect(find.text('2:30'), findsOneWidget,
          reason: 'gelembung waktu sasaran selama menyeret');
      await gesture.up();
      await tester.pump();
      expect(sought, isNotNull);
      expect(sought!.inSeconds, closeTo(150, 1));
    });

    testWidgets('ketuk melompat; data kosong tetap bisa seek (jujur)',
        (tester) async {
      Duration? sought;
      await tester.pumpWidget(
          host(onSeek: (d) => sought = d, data: WaveformData.empty));
      expect(tester.takeException(), isNull,
          reason: 'keadaan belum terukur tetap ter-render tanpa galat');
      final box = tester.getRect(find.byType(WaveformSeekBar));
      await tester.tapAt(Offset(box.left + box.width * 0.5, box.top + 24));
      await tester.pump();
      expect(sought?.inSeconds, closeTo(100, 1));
    });
  });

  group('PlayerBoardBody — kehadiran fungsi & bentuk papan', () {
    Finder icon(ClaiIconData data) => find.byWidgetPredicate(
        (w) => w is ClaiIcon && w.data == data,
        description: 'ikon Clai');

    Future<void> pumpBody(
      WidgetTester tester, {
      required QueueEngine engine,
      bool liked = true,
      String title = 'AKU TENANG',
      WaveformData? wave,
      void Function(bool)? onPlayPause,
    }) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      final palette = buildAmbientPalette(
        source: const Color(0xFFB43A2A),
        enabled: true,
        strength: AmbientStrength.hidup,
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [appDbProvider.overrideWithValue(_InstantDb())],
          child: MaterialApp(
            locale: const Locale('id'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: PlayerBoardBody(
                item: MediaItem(
                  id: 'lagu-uji',
                  title: title,
                  artist: 'Nabih Fvnky V2',
                  duration: const Duration(minutes: 3, seconds: 47),
                ),
                engine: engine,
                contextLabel: 'Dari Album Uji',
                liked: liked,
                // 8053 B(i): papan kini menerima irisan UI; faktor
                // napas dibacanya sendiri lewat select() faktor napas
                // (keadaan awal pengontrol = 1,0, sama seperti fixture
                // lama breathFactor: 1.0).
                amb: ambientUiSlice(
                  AmbientState(
                    enabled: true,
                    strength: AmbientStrength.hidup,
                    breathing: true,
                    reduceEffects: false,
                    palette: palette,
                    breathFactor: 1.0,
                  ),
                ),
                positionStream: const Stream<Duration>.empty(),
                initialPosition: const Duration(seconds: 84),
                playbackStateStream: const Stream<PlaybackState>.empty(),
                initialPlaybackState: PlaybackState(
                    playing: false,
                    processingState: AudioProcessingState.ready),
                bitrateKbps: 144,
                waveformData: wave,
                onClose: () {},
                onMore: () {},
                onLike: () {},
                artistTappable: false,
                onArtistTap: () {},
                onPlayPause: onPlayPause ?? (_) {},
                onPrev: () {},
                onNext: () {},
                onShuffleToggle: () {},
                onRepeatCycle: () {},
                onSeek: (_) {},
                onLyrics: () {},
                onQueue: () {},
                onTimer: () {},
                onVoice: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    QueueEngine engine({bool autoplay = false}) {
      final e = QueueEngine();
      e.playContext(
        PlayContext(kind: 'album', label: 'Album Uji', tracks: [
          Track(
            key: TrackKey('ytmusic', 'lagu-uji'),
            title: 'AKU TENANG',
            artistNames: 'Nabih Fvnky V2',
            duration: const Duration(minutes: 3, seconds: 47),
            playableRef: 'lagu-uji',
          ),
        ]),
        0,
      );
      e.autoplayEnabled = autoplay;
      e.autoplaySessionOn = autoplay;
      return e;
    }

    testWidgets('semua kontrol hadir; tanpa kartu autoplay bila mati',
        (tester) async {
      final l10n = AppLocalizationsId();
      await pumpBody(tester, engine: engine());
      expect(tester.takeException(), isNull);
      // Baris atas kaca gaya 8038: tutup · pil konteks · ⋮.
      expect(icon(ClaiIcons.chevronDown), findsOneWidget);
      expect(icon(ClaiIcons.moreVert), findsOneWidget);
      expect(find.text('Dari Album Uji'), findsOneWidget,
          reason: 'pil kaca konteks');
      // Blok judul di bawah sampul + suka.
      expect(find.text('AKU TENANG'), findsWidgets);
      expect(find.text('Nabih Fvnky V2'), findsOneWidget);
      expect(icon(ClaiIcons.heartFill), findsOneWidget);
      // Vinil mengintip + waveform ukur.
      expect(find.byType(SpinningVinyl), findsOneWidget);
      expect(find.byType(WaveformSeekBar), findsOneWidget);
      // Transportasi melayang: lima kontrol.
      expect(icon(ClaiIcons.shuffle), findsOneWidget);
      expect(icon(ClaiIcons.prev), findsOneWidget);
      expect(icon(ClaiIcons.play), findsOneWidget);
      expect(icon(ClaiIcons.next), findsOneWidget);
      expect(icon(ClaiIcons.repeat), findsOneWidget);
      // Baris waktu + slot status jujur.
      expect(find.text('1:24'), findsOneWidget);
      expect(find.text('-2:23'), findsOneWidget);
      expect(find.text(l10n.playerBitrate(144)), findsOneWidget);
      // Bilah dok berlabel: empat fungsi nyata.
      expect(find.text(l10n.playerLyrics), findsOneWidget);
      expect(find.text(l10n.queueTitle), findsOneWidget);
      expect(find.text(l10n.playerTimer), findsOneWidget);
      expect(find.text(l10n.playerVoice), findsOneWidget);
      // Autoplay mati → strip tidak ada (perilaku tampil kartu lama).
      expect(find.text(l10n.playerAutoplayStrip), findsNothing);
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('strip Putar Otomatis tampil saat sesi autoplay aktif (G-3)',
        (tester) async {
      final l10n = AppLocalizationsId();
      await pumpBody(tester, engine: engine(autoplay: true), liked: false);
      expect(tester.takeException(), isNull);
      expect(find.text(l10n.playerAutoplayStrip), findsOneWidget);
      // Teks penjelasan 3 baris kartu lama TIDAK lagi di Player modern.
      expect(find.text(l10n.playerAutoplayCard), findsNothing);
      expect(icon(ClaiIcons.heart), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('ketuk tombol putar raksasa memanggil onPlayPause(false)',
        (tester) async {
      bool? played;
      await pumpBody(tester,
          engine: engine(), onPlayPause: (p) => played = p);
      await tester.tap(icon(ClaiIcons.play));
      await tester.pump();
      expect(played, isFalse);
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets(
        'judul panjang MENYUSUT & tidak meluap (cacat 8038: "Love Me Back (Fa…")',
        (tester) async {
      await pumpBody(tester,
          engine: engine(), title: 'Love Me Back (Fayah Beat)');
      expect(tester.takeException(), isNull,
          reason: 'tidak boleh ada galat luapan pada judul panjang');
      final titleWidget = tester.widget<Text>(
          find.text('Love Me Back (Fayah Beat)'));
      expect(titleWidget.style?.fontSize, isNotNull);
      expect(titleWidget.style!.fontSize!, lessThan(38),
          reason: 'judul menyusut dari display 38 agar muat');
      expect(titleWidget.maxLines, 1);
      expect(titleWidget.overflow, TextOverflow.ellipsis);
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('SpinningVinyl — putaran melandai dua arah', () {
    double angleOf(WidgetTester tester) {
      final t = tester.widget<Transform>(find.descendant(
        of: find.byType(SpinningVinyl),
        matching: find.byType(Transform),
      ));
      final m = t.transform.storage;
      return math.atan2(m[1], m[0]);
    }

    Widget host({required bool active}) {
      return MaterialApp(
        home: Scaffold(
          body: Center(
            child: SpinningVinyl(
              size: 200,
              labelColor: const Color(0xFFE05252),
              active: active,
            ),
          ),
        ),
      );
    }

    testWidgets('aktif: sudut berubah; jeda: mereda lalu BEKU',
        (tester) async {
      await tester.pumpWidget(host(active: true));
      await tester.pump(const Duration(milliseconds: 100));
      final a0 = angleOf(tester);
      await tester.pump(const Duration(milliseconds: 600));
      final a1 = angleOf(tester);
      expect(a1, isNot(closeTo(a0, 0.01)),
          reason: 'piringan harus berputar saat aktif');
      await tester.pumpWidget(host(active: false));
      await tester.pump(const Duration(seconds: 3));
      final a2 = angleOf(tester);
      await tester.pump(const Duration(seconds: 1));
      expect((angleOf(tester) - a2).abs(), lessThan(0.02),
          reason: 'reda hampir berhenti: rayapan di bawah persepsi');
      await tester.pump(const Duration(seconds: 2));
      final a3 = angleOf(tester);
      await tester.pump(const Duration(seconds: 1));
      expect(angleOf(tester), closeTo(a3, 1e-9),
          reason: 'sesudah membeku, sudut tidak bergerak lagi');
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });
}

/// AppDb tanpa IO: pref selalu null (bawaan) — pengontrol suasana di
/// AmbientWashLayer jadi diam tanpa menyentuh kanal sqflite di tes.
class _InstantDb extends AppDb {
  @override
  Future<T?> pref<T>(String key) async => null;
}
