import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app.dart';
import '../core/artwork.dart';
import '../core/clai_icons.dart';
import '../core/tokens.dart';
import '../data/app_db.dart';
import '../domain/models.dart';
import '../domain/taste_mirror.dart';
import '../l10n/l10n.dart';
import '../services/ambient_theme.dart';
import '../services/cover_accent_service.dart';
import '../services/session_vault.dart' show vaultDateLabel;
import '../services/taste_service.dart';
import 'ownership_sheets.dart' show openExportSheet;
import 'samaran_gate.dart';
import 'widgets.dart';

/// Seksi datar Ronde 8083 (pola "Pengaturan — Kulit Baru", PETA-KULIT):
/// label seksi sentence-case 13/600 inkSecondary langsung di latar
/// halaman, baris-baris telanjang di bawahnya, hairline antar grup —
/// TANPA panel/kartu tonal bertumpuk dan TANPA kicker kapital
/// (pengganti lokal settingsSection khusus layar-layar berkas ini;
/// berkas settings_screen.dart bukan milik paket ini).
Widget _flatSection(String title, List<Widget> rows) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 2),
        child: Text(
          title,
          style: const TextStyle(
            color: ClaiColors.inkSecondary,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      ...rows,
      const Padding(
        padding: EdgeInsets.only(top: 10),
        child: Divider(
          height: 1,
          indent: 20,
          endIndent: 20,
          color: ClaiColors.divider,
        ),
      ),
    ],
  );
}

/// Sisipkan hairline antar baris terkunci (Ronde 8084, kontrak panel:
/// baris 60 + hairline inset sejajar teks 76 + napas 7 = pitch 68).
List<Widget> _hairlineRows(List<Widget> rows) {
  final out = <Widget>[];
  for (var i = 0; i < rows.length; i++) {
    if (i > 0) {
      out.add(
        const Padding(
          padding: EdgeInsets.only(left: 76),
          child: Divider(height: 1, color: ClaiColors.divider),
        ),
      );
      out.add(const SizedBox(height: 7));
    }
    out.add(rows[i]);
  }
  return out;
}

/// Ruang Kendali Selera (Ronde 8074, KOMPOSISI-F3 Paket Pertama butir 7
/// + BEDAH-F3 keputusan 3): layar "Kelola selera kamu" — Cermin Selera
/// (murni playback_events), slider bobot terkini/seumur, Mode Samaran,
/// Keluarkan dari Rekomendasi (retroaktif, dengan Urungkan), dan Reset
/// Selera berjaring pengaman ekspor D2. Semua permukaan PADAT (aturan
/// kaca: kaca hanya chrome melayang); sinyal fungsional memakai `signal`
/// (pagar Sinyal Putih DS v5.0) — Volt hanya pada rel saklar menyala
/// lewat tema global.
class TasteControlScreen extends ConsumerStatefulWidget {
  const TasteControlScreen({super.key});

  @override
  ConsumerState<TasteControlScreen> createState() => _TasteControlScreenState();
}

class _TasteControlScreenState extends ConsumerState<TasteControlScreen> {
  bool _loading = true;
  TasteMirrorData _mirror = TasteMirrorData.empty;
  List<TasteArtistRank> _topArtists = const [];
  // Ronde 8089 (Cermin Panggung): sampul per artis + warna tanda
  // tangan sampul hero untuk wash ambient kepala layar.
  Map<String, String?> _covers = const {};
  Color? _heroSource;
  final Map<String, List<String>> _tags = {};
  bool _tagsRequested = false;
  double? _emphasisDraft;
  // Tanda keadaan layanan saat cermin terakhir dimuat (lihat ref.listen
  // di build — perbandingan prev/next tidak bekerja untuk
  // ChangeNotifierProvider).
  int _seenExclusions = -1;
  double _seenEmphasis = -1;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final taste = ref.read(tasteServiceProvider);
    if (!taste.loaded) await taste.load();
    final data = await taste.mirrorData();
    if (!mounted) return;
    setState(() {
      _mirror = data.mirror;
      _topArtists = data.topArtists;
      _loading = false;
      _seenExclusions = taste.exclusions.length;
      _seenEmphasis = taste.recentEmphasis;
    });
    if (!_tagsRequested) {
      _tagsRequested = true;
      _loadTags(data.topArtists);
    }
    // Ronde 8089: sampul per artis menyusul sesudah cermin tampil
    // (hero & peringkat menggambar ubin motif sampai sampul tiba),
    // lalu warna tanda tangan sampul hero untuk wash ambient.
    // Fase pengaya ini best-effort: kegagalannya (mis. basis data
    // ditutup saat layar dibuang) tidak boleh menggagalkan layar.
    try {
      final covers = await taste.topArtistCovers();
      if (!mounted) return;
      setState(() => _covers = covers);
      if (data.topArtists.isNotEmpty) {
        final heroUrl = covers[data.topArtists.first.name];
        if (heroUrl != null && heroUrl.isNotEmpty) {
          final source = await CoverAccentService(
            ref.read(appDbProvider),
          ).sourceForUrl(heroUrl);
          if (!mounted) return;
          setState(() => _heroSource = source);
        }
      }
    } catch (_) {
      // Sampul & ambient adalah pengaya visual; cermin tetap sah.
    }
  }

  /// Tag genre = pemanis opsional: dimuat malas untuk 5 artis teratas,
  /// kegagalan jaringan berarti barisnya tidak tampil (bukan galat).
  Future<void> _loadTags(List<TasteArtistRank> artists) async {
    final taste = ref.read(tasteServiceProvider);
    for (final a in artists.take(5)) {
      final tags = await taste.genreTagsForArtist(a.name);
      if (!mounted) return;
      if (tags.isNotEmpty) {
        setState(() => _tags[a.name] = tags);
      }
    }
  }

  String _daypartLabel(AppLocalizations s, Daypart d) => switch (d) {
    Daypart.diniHari => s.tasteDaypartDiniHari,
    Daypart.pagi => s.tasteDaypartPagi,
    Daypart.siang => s.tasteDaypartSiang,
    Daypart.sore => s.tasteDaypartSore,
    Daypart.malam => s.tasteDaypartMalam,
  };

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    final taste = ref.watch(tasteServiceProvider);
    // Segarkan cermin bila pengecualian/bobot berubah dari layar lain
    // (daftar Keluarkan, lembar Reset). JANGAN bandingkan prev vs next:
    // untuk ChangeNotifierProvider keduanya objek yang SAMA (sudah
    // bermutasi), jadi perbandingan itu selalu salah — bandingkan nilai
    // layanan kini terhadap tanda yang terakhir dimuat layar ini.
    ref.listen(tasteServiceProvider, (_, next) {
      if (next.exclusions.length != _seenExclusions ||
          next.recentEmphasis != _seenEmphasis) {
        _tagsRequested = false;
        _load();
      }
    });
    final emphasis = _emphasisDraft ?? taste.recentEmphasis;
    // Ronde 8089 (Cermin Panggung): wash ambient hero dari warna
    // tanda tangan sampul artis peringkat 1, lewat mesin ambient yang
    // SUDAH ada (bukan mesin kedua). Tema Dinamis mati / tanpa sumber
    // → palet tidak aktif → tanpa lapisan wash. Irisan select() agar
    // terbitan napas tidak membangun ulang layar ini.
    final amb = ref.watch(ambientControllerProvider.select(ambientUiSlice));
    final palette = buildAmbientPalette(
      source: _heroSource,
      enabled: amb.enabled,
      strength: amb.strength,
    );
    return Scaffold(
      appBar: claiPushedAppBar(context, s.tasteTitle),
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          if (palette.active)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 480,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      palette.washColor(AmbientSurfaceKind.hero, amb.strength),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          FiniteScrollPage(
            children: [
              // Kepala melayang di atas wash ambient (extendBody): isi
              // mulai DI BAWAH bar kepala supaya judul tengah & chevron
              // tidak menimpa sampul hero (judul tak terbaca di atas
              // sampul terang) — komposisi Figma: zona kepala berwash,
              // hero sesudahnya.
              SizedBox(
                height: MediaQuery.paddingOf(context).top + kToolbarHeight,
              ),
              // ---------------- Cermin Selera (Cermin Panggung) -------
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 28),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_mirror.isEmpty)
                _noteRow(s.tasteMirrorEmpty)
              else ...[
                _hero(context),
                ..._rankRows(context),
                _patterns(context),
                _balance(context),
              ],
              const SizedBox(height: 8),
              // ---------------- Mode Samaran ----------------
              _flatSection(s.tasteSamaranTitle, [
                Material(
                  type: MaterialType.transparency,
                  child: SwitchListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                    minTileHeight: 60,
                    secondary: rowLeadIcon(
                      ClaiIcons.eyeOff,
                      size: 40,
                      iconSize: 24,
                    ),
                    title: Text(
                      s.tasteSamaranTitle,
                      style: rowTitleStyle(),
                    ),
                    // Ronde 8080 (vonis HP pemilik): tanpa subjudul penjelasan
                    // — penjelas Samaran tinggal SATU di lembar "Cara kerja"
                    // (gerbang S1, samaran_gate.dart) yang memang muncul saat
                    // menyalakan. Baris ini kini ikon + judul + saklar saja.
                    value: taste.samaranOn,
                    // Ronde 8079: menyalakan lewat gerbang penjelas S1 yang
                    // sama dengan pil Player (samaran_gate.dart).
                    onChanged: (v) => handleSamaranSwitch(context, ref, v),
                  ),
                ),
              ]),
              // ---------------- Bobot rekomendasi ----------------
              // Ronde 8089 (Bagian D): blok slider MANDIRI gaya Figma —
              // judul blok font tampilan [kRowTitleSize]/700 + bacaan nilai rata
              // kanan 13 di baris kepala yang sama, slider di bawah,
              // label ujung skala 13; hairline penutup seperti
              // _flatSection. Slider & perilakunya persis seperti
              // sebelumnya.
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              s.tasteWeightsTitle,
                              style: rowTitleStyle(),
                            ),
                            const Spacer(),
                            Text(
                              '${(emphasis * 100).round()}%',
                              style: const TextStyle(
                                color: ClaiColors.inkSecondary,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            activeTrackColor: ClaiColors.signal,
                            inactiveTrackColor: ClaiColors.surface3,
                            thumbColor: ClaiColors.signal,
                            overlayColor: ClaiColors.signal.withValues(
                              alpha: 0.12,
                            ),
                          ),
                          child: Slider(
                            value: emphasis,
                            min: 0,
                            max: 1,
                            onChanged: (v) =>
                                setState(() => _emphasisDraft = v),
                            onChangeEnd: (v) {
                              ref
                                  .read(tasteServiceProvider)
                                  .setRecentEmphasis(v);
                              setState(() => _emphasisDraft = null);
                            },
                          ),
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              s.tasteWeightLifetime,
                              style: const TextStyle(
                                color: ClaiColors.inkSecondary,
                                fontSize: 13,
                              ),
                            ),
                            Text(
                              s.tasteWeightRecent,
                              style: const TextStyle(
                                color: ClaiColors.inkSecondary,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.only(top: 10),
                    child: Divider(
                      height: 1,
                      indent: 20,
                      endIndent: 20,
                      color: ClaiColors.divider,
                    ),
                  ),
                ],
              ),
              // ---------------- Keluarkan dari Rekomendasi ----------------
              _flatSection(s.tasteExcludeTitle, [
                Material(
                  type: MaterialType.transparency,
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                    minTileHeight: 60,
                    titleTextStyle: rowTitleStyle(),
                    subtitleTextStyle: const TextStyle(
                      color: ClaiColors.inkSecondary,
                      fontSize: 13,
                    ),
                    leading: rowLeadIcon(
                      ClaiIcons.clearAll,
                      size: 40,
                      iconSize: 24,
                    ),
                    title: Text(
                      s.tasteExcludeTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: rowTitleStyle(),
                    ),
                    subtitle: Text(
                      taste.exclusions.isEmpty
                          ? s.tasteExcludeEmpty
                          : '${taste.exclusions.length}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: ClaiColors.inkSecondary,
                        fontSize: 13,
                      ),
                    ),
                    trailing: ClaiIcon(
                      ClaiIcons.chevronRight,
                      color: ClaiColors.inkFaint,
                    ),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const TasteExclusionsScreen(),
                      ),
                    ),
                  ),
                ),
              ]),
              // ---------------- Reset Selera ----------------
              _flatSection(s.tasteResetTitle, [
                Material(
                  type: MaterialType.transparency,
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                    minTileHeight: 60,
                    titleTextStyle: rowTitleStyle(),
                    leading: rowLeadIcon(
                      ClaiIcons.trash,
                      size: 40,
                      iconSize: 24,
                    ),
                    title: Text(
                      s.tasteResetTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: rowTitleStyle(),
                    ),
                    trailing: ClaiIcon(
                      ClaiIcons.chevronRight,
                      color: ClaiColors.inkFaint,
                    ),
                    onTap: () => showResetTasteSheet(context, ref),
                  ),
                ),
              ]),
              SizedBox(height: bottomChromeClearance(context)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _noteRow(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
    child: Text(
      text,
      style: const TextStyle(
        color: ClaiColors.inkSecondary,
        fontSize: 13,
        height: 1.4,
      ),
    ),
  );

  /// Hero Cermin Panggung (Ronde 8089): artis peringkat 1 — sampul
  /// persegi selebar konten radius 16, angka "01" display 56 di kiri
  /// bawah, nama display 28 + hitungan display 20, dan baris genre
  /// perkiraan (bila tagnya ada) di bawahnya.
  Widget _hero(BuildContext context) {
    final s = context.l10n;
    final a = _topArtists.first;
    final tags = _tags[a.name];
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, c) => _ArtistCover(
              url: _covers[a.name],
              size: c.maxWidth,
              radius: 16,
              hero: true,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('01', style: displayStyle(56)),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      a.name,
                      style: displayStyle(28),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      s.tastePlaysCount(a.count),
                      style: displayStyle(20),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (tags != null && tags.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                s.tasteGenreEstimate(tags.join(', ')),
                style: const TextStyle(
                  color: ClaiColors.inkFaint,
                  fontSize: 12,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
    );
  }

  /// Peringkat 02–08 Cermin Panggung (Ronde 8089): baris 64 — nomor
  /// display 20 redup selebar 44, sampul 48 radius 8, nama 15/500,
  /// hitungan 13; hairline antar baris sejajar awal nama (indent
  /// absolut 20 + 84 = 104). Tanpa progress bar, tanpa baris genre.
  List<Widget> _rankRows(BuildContext context) {
    final s = context.l10n;
    final end = math.min(8, _topArtists.length);
    final out = <Widget>[];
    for (var i = 1; i < end; i++) {
      final a = _topArtists[i];
      if (i > 1) {
        out.add(
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Divider(height: 1, indent: 84, color: ClaiColors.divider),
          ),
        );
      }
      out.add(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: SizedBox(
            height: 64,
            child: Row(
              children: [
                SizedBox(
                  width: 44,
                  child: Text(
                    '${i + 1}'.padLeft(2, '0'),
                    style: displayStyle(
                      20,
                    ).copyWith(color: ClaiColors.inkFaint),
                  ),
                ),
                _ArtistCover(url: _covers[a.name], size: 48, radius: 8),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    a.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: ClaiColors.ink,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Text(
                  s.tastePlaysCount(a.count),
                  style: const TextStyle(
                    color: ClaiColors.inkSecondary,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return out;
  }

  Widget _patterns(BuildContext context) {
    final s = context.l10n;
    final peak = _mirror.peakDaypart;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
          child: Text(s.tastePatternsTitle, style: displayStyle(17)),
        ),
        if (peak != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: Text(
              s.tastePeakDaypart(_daypartLabel(s, peak)),
              style: const TextStyle(
                color: ClaiColors.ink,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 12),
          _BarRow(values: _mirror.hourCounts, height: 44),
          const SizedBox(height: 4),
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '00',
                style: TextStyle(color: ClaiColors.inkFaint, fontSize: 11),
              ),
              Text(
                '06',
                style: TextStyle(color: ClaiColors.inkFaint, fontSize: 11),
              ),
              Text(
                '12',
                style: TextStyle(color: ClaiColors.inkFaint, fontSize: 11),
              ),
              Text(
                '18',
                style: TextStyle(color: ClaiColors.inkFaint, fontSize: 11),
              ),
              Text(
                '23',
                style: TextStyle(color: ClaiColors.inkFaint, fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _BarRow(values: _mirror.dayCounts, height: 36),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (final d in [
                s.tasteDayMon,
                s.tasteDayTue,
                s.tasteDayWed,
                s.tasteDayThu,
                s.tasteDayFri,
                s.tasteDaySat,
                s.tasteDaySun,
              ])
                Text(
                  d,
                  style: const TextStyle(
                    color: ClaiColors.inkFaint,
                    fontSize: 11,
                  ),
                ),
            ],
          ),
            ],
          ),
        ),
      ],
    );
  }

  /// Keseimbangan Cermin Panggung (Ronde 8089): judul display 17,
  /// baris stat — persen terkini display 34 + labelnya 13, di kanan
  /// persen seumur + labelnya 13 — lalu split bar 6dp (signal di atas
  /// surface3) selebar konten.
  Widget _balance(BuildContext context) {
    final s = context.l10n;
    final pct = (_mirror.recentShare * 100).round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
          child: Text(s.tasteBalanceTitle, style: displayStyle(17)),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('$pct%', style: displayStyle(34)),
              const SizedBox(width: 8),
              Text(
                s.tasteBalanceRecent,
                style: const TextStyle(
                  color: ClaiColors.inkSecondary,
                  fontSize: 13,
                ),
              ),
              const Spacer(),
              Text(
                '${100 - pct}% · ${s.tasteBalanceLifetime}',
                style: const TextStyle(
                  color: ClaiColors.inkSecondary,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 4),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: Stack(
              children: [
                Container(height: 6, color: ClaiColors.surface3),
                FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: _mirror.recentShare,
                  child: Container(height: 6, color: ClaiColors.signal),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Sampul artis Cermin Panggung (Ronde 8089): persegi [size] radius
/// [radius] memakai disiplin CoverArt (ember ukuran + cacheWidth
/// dibatasi decode). URL kosong/gagal → ubin motif gelombang merek
/// di surface2 (hero: motif diskala 2,4) — bukan ikon generik.
class _ArtistCover extends StatelessWidget {
  final String? url;
  final double size;
  final double radius;
  final bool hero;
  const _ArtistCover({
    required this.url,
    required this.size,
    required this.radius,
    this.hero = false,
  });

  @override
  Widget build(BuildContext context) {
    final motif = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: ClaiColors.surface2,
        borderRadius: BorderRadius.circular(radius),
      ),
      alignment: Alignment.center,
      // FittedBox scaleDown: motif selebar 51 tidak meluber dari ubin
      // 48 (luapan 3px tertangkap tes selera_8074) — pada ukuran
      // alaminya ia tampil persis; hanya menyusut sepersekian bila
      // ubin lebih sempit dari motif.
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: hero
            ? Transform.scale(scale: 2.4, child: const ClaiWaveMotif())
            : const ClaiWaveMotif(),
      ),
    );
    final u = url;
    if (u == null || u.isEmpty) return motif;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final bucket = artworkBucketFor(size, dpr);
    final sizedUrl = artworkUrlForSize(u, bucket) ?? u;
    final decodeWidth = sizedUrl.contains('ytimg.com')
        ? bucket
        : math.min(bucket, math.max((size * dpr).ceil(), 1));
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Image.network(
        sizedUrl,
        key: ValueKey(sizedUrl),
        width: size,
        height: size,
        fit: BoxFit.cover,
        cacheWidth: decodeWidth,
        errorBuilder: (_, __, ___) => motif,
        loadingBuilder: (c, child, prog) => prog == null ? child : motif,
      ),
    );
  }
}

/// Batang mini untuk histogram cermin: batang tertinggi memakai
/// `signal`, sisanya tonal redup — tanpa sumbu, tanpa angka karangan.
class _BarRow extends StatelessWidget {
  final List<int> values;
  final double height;
  const _BarRow({required this.values, required this.height});

  @override
  Widget build(BuildContext context) {
    if (values.isEmpty) return SizedBox(height: height);
    final maxV = values.reduce((a, b) => a > b ? a : b);
    return SizedBox(
      height: height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < values.length; i++) ...[
            if (i > 0) const SizedBox(width: 3),
            Expanded(
              child: Container(
                height: maxV == 0 ? 2 : (2 + (height - 2) * (values[i] / maxV)),
                decoration: BoxDecoration(
                  color: values[i] == maxV && maxV > 0
                      ? ClaiColors.signal
                      : ClaiColors.surface3,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Keluarkan dari Rekomendasi
// ---------------------------------------------------------------------

/// Daftar pengecualian yang berlaku (dengan Urungkan per baris) +
/// pintu mengeluarkan artis/lagu baru dari permukaan selera teratas.
/// Pengecualian berlaku RETROAKTIF karena ia saringan baca di atas
/// riwayat — mengurungkan mengembalikan keadaan persis seperti semula.
class TasteExclusionsScreen extends ConsumerStatefulWidget {
  const TasteExclusionsScreen({super.key});

  @override
  ConsumerState<TasteExclusionsScreen> createState() =>
      _TasteExclusionsScreenState();
}

class _TasteExclusionsScreenState extends ConsumerState<TasteExclusionsScreen> {
  List<TasteArtistRank> _topArtists = const [];
  List<Track> _topTracks = const [];
  bool _loading = true;
  int _seenExclusions = -1;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final taste = ref.read(tasteServiceProvider);
    if (!taste.loaded) await taste.load();
    final data = await taste.mirrorData(topLimit: 10);
    final tracks = await ref.read(appDbProvider).frequentTracks(limit: 10);
    if (!mounted) return;
    setState(() {
      _topArtists = data.topArtists;
      _topTracks = tracks;
      _loading = false;
      _seenExclusions = taste.exclusions.length;
    });
  }

  void _snackExcluded(String label, TasteExclusion e) {
    final s = context.l10n;
    ScaffoldMessenger.of(context).showSnackBar(
      claiSnackAboveChrome(
        context,
        s.tasteExcludedDone(label),
        action: SnackBarAction(
          label: s.tasteUndo,
          onPressed: () => ref.read(tasteServiceProvider).undoExclusion(e),
        ),
      ),
    );
  }

  Future<void> _excludeArtist(String name) async {
    final taste = ref.read(tasteServiceProvider);
    await taste.excludeArtist(name);
    final e = taste.exclusions.firstWhere(
      (x) => x.isArtist && x.key == name.trim(),
      orElse: () => TasteExclusion(
        kind: 'artist',
        key: name.trim(),
        label: name.trim(),
        createdAt: 0,
      ),
    );
    if (!mounted) return;
    _snackExcluded(name, e);
    _load();
  }

  Future<void> _excludeTrack(Track t) async {
    final taste = ref.read(tasteServiceProvider);
    await taste.excludeTrack(t);
    final e = taste.exclusions.firstWhere(
      (x) => !x.isArtist && x.key == trackExclusionKey(t.providerId, t.id),
      orElse: () => TasteExclusion(
        kind: 'track',
        key: trackExclusionKey(t.providerId, t.id),
        label: t.title,
        createdAt: 0,
      ),
    );
    if (!mounted) return;
    _snackExcluded(t.title, e);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    final taste = ref.watch(tasteServiceProvider);
    // Sama seperti layar Kendali: prev/next ChangeNotifierProvider
    // adalah objek yang sama — bandingkan terhadap tanda terakhir.
    ref.listen(tasteServiceProvider, (_, next) {
      if (next.exclusions.length != _seenExclusions) {
        _load();
      }
    });
    return Scaffold(
      appBar: claiPushedAppBar(context, s.tasteExcludeTitle),
      body: FiniteScrollPage(
        children: [
          _flatSection(s.tasteExcludeTitle, [
            if (taste.exclusions.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                child: Text(
                  s.tasteExcludeEmpty,
                  style: const TextStyle(
                    color: ClaiColors.inkSecondary,
                    fontSize: 13,
                  ),
                ),
              )
            else
              ..._hairlineRows([
                for (final e in taste.exclusions)
                  Material(
                    type: MaterialType.transparency,
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20,
                      ),
                      minTileHeight: 60,
                      titleTextStyle: const TextStyle(
                        color: ClaiColors.ink,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                      subtitleTextStyle: const TextStyle(
                        color: ClaiColors.inkSecondary,
                        fontSize: 13,
                      ),
                      leading: rowLeadIcon(
                        e.isArtist ? ClaiIcons.person : ClaiIcons.musicNote,
                        size: 40,
                        iconSize: 24,
                      ),
                      title: Text(
                        e.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: ClaiColors.ink,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        e.isArtist ? s.tasteKindArtist : s.tasteKindTrack,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: ClaiColors.inkSecondary,
                          fontSize: 13,
                        ),
                      ),
                      trailing: TextButton(
                        onPressed: () =>
                            ref.read(tasteServiceProvider).undoExclusion(e),
                        child: Text(
                          s.tasteUndo,
                          style: const TextStyle(color: ClaiColors.signal),
                        ),
                      ),
                    ),
                  ),
              ]),
          ]),
          if (!_loading && _topArtists.isNotEmpty)
            _flatSection(s.tastePickArtists, [
              ..._hairlineRows([
                for (final a in _topArtists)
                  Material(
                    type: MaterialType.transparency,
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20,
                      ),
                      minTileHeight: 60,
                      titleTextStyle: const TextStyle(
                        color: ClaiColors.ink,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                      subtitleTextStyle: const TextStyle(
                        color: ClaiColors.inkSecondary,
                        fontSize: 13,
                      ),
                      leading: rowLeadIcon(
                        ClaiIcons.person,
                        size: 40,
                        iconSize: 24,
                      ),
                      title: Text(
                        a.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: ClaiColors.ink,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        s.tastePlaysCount(a.count),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: ClaiColors.inkSecondary,
                          fontSize: 13,
                        ),
                      ),
                      trailing: TextButton(
                        onPressed: () => _excludeArtist(a.name),
                        child: Text(
                          s.tasteExcludeAction,
                          style: const TextStyle(color: ClaiColors.signal),
                        ),
                      ),
                    ),
                  ),
              ]),
            ]),
          if (!_loading && _topTracks.isNotEmpty)
            _flatSection(s.tastePickTracks, [
              ..._hairlineRows([
                for (final t in _topTracks)
                  Material(
                    type: MaterialType.transparency,
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20,
                      ),
                      minTileHeight: 60,
                      titleTextStyle: const TextStyle(
                        color: ClaiColors.ink,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                      subtitleTextStyle: const TextStyle(
                        color: ClaiColors.inkSecondary,
                        fontSize: 13,
                      ),
                      leading: rowLeadIcon(
                        ClaiIcons.musicNote,
                        size: 40,
                        iconSize: 24,
                      ),
                      title: Text(
                        t.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: ClaiColors.ink,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        t.artistNames,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: ClaiColors.inkSecondary,
                          fontSize: 13,
                        ),
                      ),
                      trailing: TextButton(
                        onPressed: () => _excludeTrack(t),
                        child: Text(
                          s.tasteExcludeAction,
                          style: const TextStyle(color: ClaiColors.signal),
                        ),
                      ),
                    ),
                  ),
              ]),
            ]),
          SizedBox(height: bottomChromeClearance(context)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Reset Selera
// ---------------------------------------------------------------------

/// Lembar konfirmasi Reset Selera (padat, pola lembar baku): penjelasan
/// jujur apa yang terhapus dan apa yang TIDAK, baris "Cadangan terakhir"
/// dari cap waktu ekspor D2 yang nyata (atau "belum ada" + pintu ekspor),
/// lalu tombol destruktif. Membatalkan di titik mana pun = nol perubahan.
Future<void> showResetTasteSheet(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet<void>(
    context: claiRootContext(context),
    isScrollControlled: true,
    backgroundColor: ClaiColors.surface1,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(ClaiRadius.sheet),
      ),
    ),
    builder: (_) => _ResetTasteSheet(ref: ref),
  );
}

class _ResetTasteSheet extends StatefulWidget {
  final WidgetRef ref;
  const _ResetTasteSheet({required this.ref});

  @override
  State<_ResetTasteSheet> createState() => _ResetTasteSheetState();
}

class _ResetTasteSheetState extends State<_ResetTasteSheet> {
  int? _lastExportAt;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    widget.ref.read(appDbProvider).pref<int>(AppDb.prefLastExportAt).then((v) {
      if (mounted) setState(() => _lastExportAt = v);
    });
  }

  Future<void> _confirm() async {
    if (_busy) return; // penjaga masuk-ulang: satu konfirmasi = satu reset
    // Tangkap semua yang berbasis konteks SEBELUM jeda async (pola
    // lembar Ekspor 8070) — sesudah reset, konteks lembar bisa basi.
    final rootCtx = claiRootContext(context);
    final messenger = ScaffoldMessenger.of(rootCtx);
    final snack = claiSnackAboveChrome(rootCtx, rootCtx.l10n.tasteResetDone);
    final nav = Navigator.of(context);
    setState(() => _busy = true);
    await widget.ref.read(tasteServiceProvider).resetTaste();
    if (!mounted) return;
    nav.pop();
    messenger.showSnackBar(snack);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    final lang = Localizations.localeOf(context).languageCode;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SheetHandle(),
            const SizedBox(height: 16),
            Text(
              s.tasteResetSheetTitle,
              style: const TextStyle(
                color: ClaiColors.ink,
                fontSize: 19,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              s.tasteResetSheetBody,
              style: const TextStyle(
                color: ClaiColors.inkSecondary,
                fontSize: 13,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 16),
            // Ronde 8083: baris "Cadangan terakhir" datar langsung di
            // permukaan lembar + hairline — wadah tonal bertumpuk di
            // dalam lembar pensiun (pola Kulit Baru).
            const Divider(height: 1, color: ClaiColors.divider),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                children: [
                  ClaiIcon(
                    ClaiIcons.history,
                    size: 18,
                    color: ClaiColors.inkSecondary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _lastExportAt == null
                          ? s.tasteResetNoBackup
                          : s.tasteResetBackup(
                              vaultDateLabel(
                                DateTime.fromMillisecondsSinceEpoch(
                                  _lastExportAt!,
                                ),
                                lang,
                              ),
                            ),
                      style: const TextStyle(
                        color: ClaiColors.ink,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  if (_lastExportAt == null)
                    TextButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                        openExportSheet(context, widget.ref);
                      },
                      child: Text(
                        s.tasteExportFirst,
                        style: const TextStyle(color: ClaiColors.signal),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: ClaiColors.error,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              onPressed: _busy ? null : _confirm,
              child: Text(s.tasteResetConfirm),
            ),
            const SizedBox(height: 6),
            TextButton(
              onPressed: _busy ? null : () => Navigator.of(context).pop(),
              child: Text(
                s.commonCancel,
                style: const TextStyle(color: ClaiColors.inkSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
