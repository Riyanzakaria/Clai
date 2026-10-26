import 'dart:async';
import 'l10n/l10n.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/clai_icons.dart';
import 'core/tokens.dart';
import 'data/app_db.dart';
import 'domain/models.dart';
import 'player/audio_handler.dart';
import 'player/queue_engine.dart' show ShuffleMode;
import 'providers/provider_similarity.dart';
import 'providers/ytmusic/ytmusic_provider.dart';
import 'services/audio_fx_service.dart';
import 'services/enrichment_service.dart';
import 'services/gate_metrics.dart';
import 'services/listenbrainz_service.dart';
import 'services/loudness_estimator.dart';
import 'services/observability.dart';
import 'services/track_metadata_healer.dart';

/// Cap waktu niat mulai proses (B-01: metrik mulai dingin Bab 3). main()
/// menyentuhnya pertama kali agar inisialisasi malasnya terjadi sedini
/// mungkin; bootstrap mengukur sampai langkah-langkahnya tuntas.
final appStartStamp = DateTime.now();

/// Versi aplikasi (samakan dengan `version` di pubspec.yaml) — untuk laporan kesalahan.
const kAppVersion = '1.0.0+7';

/// Batas cache gambar terukur (Blueprint 8.1, Sapuan D-27): 150 MB.
/// Sebelumnya cache gambar Flutter berjalan dengan bawaan tak terukur.
const kImageCacheMaxBytes = 150 * 1024 * 1024;

void configureImageCache() {
  PaintingBinding.instance.imageCache.maximumSizeBytes = kImageCacheMaxBytes;
}

/// Satu langkah inisialisasi bernama. [run] boleh melempar; runner membungkusnya
/// menjadi [BootstrapFailure] beserta nama langkahnya.
class BootstrapStep {
  const BootstrapStep(this.label, this.run);
  final String label;
  final Future<void> Function() run;
}

/// Kegagalan satu langkah bootstrap — ditampilkan apa adanya ke pengguna
/// (tidak ada lagi kegagalan berupa layar hitam).
class BootstrapFailure implements Exception {
  const BootstrapFailure(this.stepLabel, this.error, this.stackTrace);
  final String stepLabel;
  final Object error;
  final StackTrace stackTrace;
  @override
  String toString() => 'Langkah "$stepLabel" gagal: $error';
}

/// Menjalankan langkah-langkah bootstrap BERURUTAN, satu per satu, masing-masing
/// dengan batas waktu. Kemajuan dilaporkan lewat [onStep] agar splash bisa
/// menampilkan langkah yang sedang berjalan.
class BootstrapRunner {
  const BootstrapRunner({this.stepTimeout = const Duration(seconds: 10)});
  final Duration stepTimeout;

  Future<void> run(
    List<BootstrapStep> steps, {
    void Function(String label)? onStep,
  }) async {
    for (final step in steps) {
      onStep?.call(step.label);
      try {
        await step.run().timeout(stepTimeout);
      } catch (e, st) {
        throw BootstrapFailure(step.label, e, st);
      }
    }
  }
}

/// Layanan hasil bootstrap — dipasang sebagai override Riverpod untuk ClaiApp.
class AppServices {
  const AppServices({
    required this.db,
    required this.provider,
    required this.handler,
  });
  final AppDb db;
  final YtMusicProvider provider;
  final ClaiAudioHandler handler;
}

/// Laporan teks yang bisa disalin pengguna dari layar kesalahan.
String buildStartupReport(BootstrapFailure failure) {
  final stackLines = failure.stackTrace
      .toString()
      .split('\n')
      .take(12)
      .join('\n');
  return [
    'Clai — laporan gagal mulai',
    'Waktu: ${DateTime.now().toIso8601String()}',
    'Versi aplikasi: $kAppVersion',
    'Platform: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
    'Langkah yang gagal: ${failure.stepLabel}',
    'Error: ${failure.error}',
    'Stack (ringkas):',
    stackLines,
  ].join('\n');
}

/// Akar aplikasi. Dipasang oleh main() TANPA menunggu apa pun: frame pertama
/// (splash bermerek) selalu tergambar lebih dulu, inisialisasi berat berjalan
/// sesudahnya per langkah dengan batas waktu & permukaan kesalahan yang jujur.
///
/// Ini membalik urutan lama (runApp paling akhir sesudah AudioService.init +
/// baca preferensi) yang membuat satu macet di awal = layar hitam + ANR.
class ClaiBootstrapApp extends StatefulWidget {
  const ClaiBootstrapApp({super.key});
  @override
  State<ClaiBootstrapApp> createState() => _ClaiBootstrapAppState();
}

class _ClaiBootstrapAppState extends State<ClaiBootstrapApp> {
  static const _runner = BootstrapRunner();

  String? _stepLabel;
  BootstrapFailure? _failure;
  AppServices? _services;
  bool _running = false;

  @override
  void initState() {
    super.initState();
    // Mulai SETELAH frame pertama benar-benar tergambar.
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    if (_running) return;
    _running = true;
    setState(() {
      _failure = null;
      _services = null;
      _stepLabel = 'Memulai…';
    });

    AppDb? db;
    YtMusicProvider? provider;
    ClaiAudioHandler? handler;

    final steps = <BootstrapStep>[
      BootstrapStep(l10n.startupDb, () async {
        db = AppDb();
        await db!
            .db; // hangatkan buka DB di sini, bukan tersebar di layar pertama
        // D-04: log insiden kini persisten — pasang sink basis data dan muat
        // riwayatnya; entri yang tercatat sebelum langkah ini (mulai dingin)
        // ikut disiram dari penampung sementara.
        await Observability.instance.attachPersistence(
          sink: (kind, detail, atMs) =>
              db!.insertIncident(kind, detail, at: atMs),
          load: () => db!.incidents(limit: 200),
        );
        if (db!.migrationRecovered) {
          Observability.instance.log(
            'migrasi-dipulihkan',
            'basis data dibuka dari cadangan pra-migrasi (${db!.lastMigrationError ?? ''})',
          );
        }
      }),
      BootstrapStep(l10n.startupSource, () async {
        provider = YtMusicProvider(db!);
      }),
      BootstrapStep(l10n.startupPlayer, () async {
        handler = await AudioService.init(
          builder: () => ClaiAudioHandler(
            db: db!,
            provider: provider!,
            similaritySource: ProviderSimilaritySource(provider!),
          ),
          config: AudioServiceConfig(
            androidNotificationChannelId: 'com.riyanzakaria.clai.audio',
            androidNotificationChannelName: 'Clai — Pemutaran',
            // ADR-001: layanan tetap foreground saat jeda — memulai lagi tidak perlu startForeground dari latar.
            // androidNotificationOngoing SENGAJA tidak dipasang: audio_service melarangnya bersama
            // androidStopForegroundOnPause: false (assertion di AudioServiceConfig) — dan tak perlu,
            // karena layanan yang selalu foreground membuat notifikasinya memang selalu ongoing.
            androidStopForegroundOnPause: false,
            androidNotificationIcon: 'mipmap/ic_launcher',
          ),
        );
      }),
      BootstrapStep(l10n.startupPrefs, () async {
        final autoplay = await db!.pref<bool>('playback.autoplay');
        if (autoplay != null) handler!.engine.autoplayEnabled = autoplay;
        final quality = await db!.pref<String>('playback.quality');
        if (quality != null) {
          handler!.quality =
              StreamQuality.values.asNameMap()[quality] ?? StreamQuality.normal;
        }
        final smart = await db!.pref<bool>('playback.smartShuffle');
        if (smart == true) {
          handler!.engine.shuffle = ShuffleMode.smart;
          handler!.engine.setSmartSignals(
            likedKeys: await db!.likedKeys(),
            playCounts: await db!.playCounts(),
          );
          // Butir D: nilai engine yang ditetapkan langsung di sini wajib
          // diterbitkan ke playbackState, sama seperti jalur lain.
          handler!.syncShuffleState();
        }
        final transition = await db!.pref<String>('playback.transition');
        if (transition == 'crossfade') {
          handler!.transitionMode = 'crossfade';
        } else if (transition == 'gapless') {
          handler!.transitionMode = 'gapless';
        }
        final xfSecs = await db!.pref<double>('playback.crossfadeSecs');
        if (xfSecs != null) handler!.crossfadeSecs = xfSecs.clamp(1, 12);
        final norm = await db!.pref<bool>('playback.normalization');
        if (norm != null) handler!.normalizationOn = norm;
        // Sapuan: D-03 mode hemat data + D-33 perilaku fokus audio.
        final saver = await db!.pref<bool>('playback.dataSaver');
        if (saver != null) handler!.dataSaverOn = saver;
        final focus = await db!.pref<String>('playback.focusBehavior');
        if (focus != null) handler!.duckLowersVolume = focus != 'pause';
        final autoR = await db!.pref<bool>('playback.autoResume');
        if (autoR != null) handler!.autoResume = autoR;
      }),
      BootstrapStep(l10n.startupServices, () async {
        // Kait F2 Batch 1: scrobble ListenBrainz (token pengguna, default mati)
        // & pengayaan sampul MusicBrainz/CAA. Semua gagal-aman di sisi layanan;
        // pemutar tidak pernah menunggu mereka.
        final lb = ListenBrainzService(db!);
        final enrich = EnrichmentService(db!);
        handler!.trackStartedListeners.add((t) => unawaited(lb.playingNow(t)));
        handler!.onListenFinished = (t, listenedMs, _) {
          if (listenedMs >= 30000) {
            unawaited(
              lb.scrobble(
                t,
                startedAt: DateTime.now().subtract(
                  Duration(milliseconds: listenedMs),
                ),
              ),
            );
          }
        };
        handler!.artworkEnricher = (t) => enrich.coverFor(t);
        // Lapisan penyembuhan metadata (Ronde Cacat Metadata): trek yang
        // mulai diputar dengan artis kosong / tanpa sampul diselesaikan
        // sekali dari provider (resolve by ID); hasilnya ditempel handler
        // ke antrean + DB. Gagal = putar jalan terus dengan rekam apa
        // adanya; tidak pernah menunggu pemutaran.
        final healer =
            TrackMetadataHealer(db!, resolveById: provider!.resolveTrackById);
        handler!.trackStartedListeners.add((t) {
          if (TrackMetadataHealer.needsHeal(t)) {
            unawaited(healer.healIfNeeded(t).then((h) {
              if (h != null) unawaited(handler!.refreshTrackMetadata(h));
            }));
          }
        });
        // Lanjut Besok (F2 Batch 2): estimator RMS mulai mendengarkan
        // peristiwa Visualizer; sampel hanya diakumulasi saat sakelar
        // normalisasi nyala (cek di dalam estimator).
        final estimator = LoudnessEstimator(db!, handler!, AudioFxService());
        estimator.start();
        // D-11: lintasan retensi Blueprint 2.4, dijeda maks sekali per 24
        // jam — katalog LRU 90 hari, riwayat sesuai setelan pengguna
        // (bawaan 365 hari), cache aliran kedaluwarsa + batas 200 baris.
        final lastRun = await db!.pref<int>('retention.lastRun') ?? 0;
        if (DateTime.now().millisecondsSinceEpoch - lastRun > 86400000) {
          final days = await db!.pref<int>('data.historyDays') ?? 365;
          await db!.pruneRetention(historyDays: days);
          await db!.pruneIncidents();
          await db!.setPref(
            'retention.lastRun',
            DateTime.now().millisecondsSinceEpoch,
          );
        }
      }),
    ];

    try {
      await _runner.run(
        steps,
        onStep: (label) {
          if (mounted) setState(() => _stepLabel = label);
        },
      );
      // B-01: mulai dingin terukur dari cap waktu main() ke bootstrap tuntas.
      GateMetrics.instance.coldStartMs = DateTime.now()
          .difference(appStartStamp)
          .inMilliseconds;
      Observability.instance.log(
        'startup',
        'bootstrap selesai; mulai dingin ${GateMetrics.instance.coldStartMs} ms',
      );
      if (mounted) {
        setState(
          () => _services = AppServices(
            db: db!,
            provider: provider!,
            handler: handler!,
          ),
        );
      }
    } on BootstrapFailure catch (f) {
      Observability.instance.log('startup-gagal', f.toString());
      if (mounted) setState(() => _failure = f);
    } finally {
      _running = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final services = _services;
    final failure = _failure;
    return MaterialApp(
      title: 'Clai',
      debugShowCheckedModeBanner: false,
      theme: buildClaiTheme(),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: services != null
          ? ProviderScope(
              overrides: [
                appDbProvider.overrideWithValue(services.db),
                ytMusicProvider.overrideWithValue(services.provider),
                audioHandlerProvider.overrideWithValue(services.handler),
              ],
              child: const ClaiApp(),
            )
          : failure != null
          ? StartupErrorScreen(
              failure: failure,
              report: buildStartupReport(failure),
              onRetry: _start,
            )
          : SplashScreen(stepLabel: _stepLabel ?? l10n.startupStarting),
    );
  }
}

/// Layar pembuka bermerek: logo + nama + langkah yang sedang berjalan.
/// Sengaja tanpa dependensi async (font/teks polos) agar selalu bisa tergambar.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key, required this.stepLabel});
  final String stepLabel;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ClaiColors.base,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(
                'assets/logo/clai-mark-512.png',
                width: 96,
                height: 96,
                errorBuilder: (_, __, ___) => ClaiIcon(
                  ClaiIcons.musicNote,
                  size: 96,
                  color: ClaiColors.accent,
                ),
              ),
              const SizedBox(height: ClaiSpace.lg),
              const Text(
                'Clai',
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                  color: ClaiColors.ink,
                ),
              ),
              const SizedBox(height: ClaiSpace.huge),
              const SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  color: ClaiColors.accent,
                ),
              ),
              const SizedBox(height: ClaiSpace.md),
              Text(
                stepLabel,
                style: const TextStyle(
                  fontSize: 13,
                  color: ClaiColors.inkSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Layar kesalahan mulai yang jujur: langkah yang gagal + error + jalan keluar.
class StartupErrorScreen extends StatelessWidget {
  const StartupErrorScreen({
    super.key,
    required this.failure,
    required this.report,
    required this.onRetry,
  });
  final BootstrapFailure failure;
  final String report;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ClaiColors.base,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(ClaiSpace.xxl),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ClaiIcon(ClaiIcons.warning, size: 52, color: ClaiColors.error),
              const SizedBox(height: ClaiSpace.lg),
              Text(
                context.l10n.startupFailedTitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: ClaiColors.ink,
                ),
              ),
              const SizedBox(height: ClaiSpace.md),
              Text(
                context.l10n.startupFailedStep(failure.stepLabel),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, color: ClaiColors.ink),
              ),
              const SizedBox(height: ClaiSpace.sm),
              SelectableText(
                '${failure.error}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  color: ClaiColors.inkSecondary,
                ),
              ),
              const SizedBox(height: ClaiSpace.xxl),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: ClaiColors.accent,
                  foregroundColor: ClaiColors.onAccent,
                ),
                onPressed: onRetry,
                child: Text(context.l10n.startupRetry),
              ),
              const SizedBox(height: ClaiSpace.sm),
              OutlinedButton(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: report));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(context.l10n.startupReportCopied)),
                    );
                  }
                },
                child: Text(context.l10n.diagCopy),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
