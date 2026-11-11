// Ronde Koreksi Komposisi F3 — tes fungsi murni baru:
// pengurai Mood & Genre (pipa Jelajah Cari), pemilih kartu Charts,
// gradasi ubin mood, label terakhir-diputar & format ukuran Koleksi.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:clai/core/tokens.dart';
import 'package:clai/domain/models.dart';
import 'package:clai/l10n/app_localizations.dart';
import 'package:clai/providers/ytmusic/innertube.dart';
import 'package:clai/ui/collection_screen.dart';
import 'package:clai/ui/search_screen.dart';
import 'package:clai/ui/widgets.dart';

Album _album(String id, String title) =>
    Album(providerId: 'ytmusic', id: id, title: title, artistNames: 'X');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  chartFallbackTitleSizeTests();

  group('parseMoodGenreSections', () {
    final fixture = {
      'contents': {
        'singleColumnBrowseResultsRenderer': {
          'tabs': [
            {
              'tabRenderer': {
                'content': {
                  'sectionListRenderer': {
                    'contents': [
                      {
                        'gridRenderer': {
                          'header': {
                            'gridHeaderRenderer': {
                              'title': {
                                'runs': [
                                  {'text': 'Moods'}
                                ]
                              }
                            }
                          },
                          'items': [
                            {
                              'musicNavigationButtonRenderer': {
                                'buttonText': {
                                  'runs': [
                                    {'text': 'Galau'}
                                  ]
                                },
                                'solid': {'leftStripeColor': 4294901760},
                                'clickCommand': {
                                  'browseEndpoint': {
                                    'browseId': 'UCMOOD1',
                                    'params': 'params-galau'
                                  }
                                }
                              }
                            },
                            {
                              'musicNavigationButtonRenderer': {
                                'buttonText': {'simpleText': 'Santai'},
                                'solid': {'leftStripeColor': 0},
                                'clickCommand': {
                                  'browseEndpoint': {'browseId': 'UCMOOD2'}
                                }
                              }
                            },
                            {
                              // Tanpa endpoint → harus dibuang, bukan
                              // jadi ubin mati.
                              'musicNavigationButtonRenderer': {
                                'buttonText': {
                                  'runs': [
                                    {'text': 'Rusak'}
                                  ]
                                },
                                'clickCommand': {}
                              }
                            },
                          ]
                        }
                      },
                    ]
                  }
                }
              }
            }
          ]
        }
      }
    };

    test('mengurai seksi + item; item tanpa endpoint dibuang', () {
      final sections = parseMoodGenreSections(fixture);
      expect(sections, hasLength(1));
      expect(sections.single.title, 'Moods');
      expect(sections.single.items, hasLength(2));
      final galau = sections.single.items.first;
      expect(galau.title, 'Galau');
      expect(galau.stripeColor, 4294901760);
      expect(galau.browseId, 'UCMOOD1');
      expect(galau.params, 'params-galau');
      final santai = sections.single.items.last;
      expect(santai.title, 'Santai');
      expect(santai.params, isNull);
    });

    test('respons kosong/tidak dikenal → daftar kosong, bukan crash', () {
      expect(parseMoodGenreSections(const {}), isEmpty);
      expect(
          parseMoodGenreSections(const {
            'contents': {'takDikenal': true}
          }),
          isEmpty);
    });
  });

  group('chartCardsOf', () {
    test('playlist didahulukan, album menyusul, dedupe per id', () {
      final shelves = [
        ExploreShelf(
          title: 'Charts',
          albums: [_album('OLAK1', 'Album A')],
          playlists: [_album('VLPL1', 'Top 50')],
        ),
        ExploreShelf(
          title: 'Trending',
          playlists: [_album('VLPL1', 'Top 50'), _album('VLPL2', 'Viral')],
        ),
      ];
      final cards = chartCardsOf(shelves);
      expect(cards.map((c) => c.item.id), ['VLPL1', 'VLPL2', 'OLAK1']);
      expect(cards.first.shelfTitle, 'Charts');
      expect(cards.last.shelfTitle, 'Charts');
    });

    test('rak hanya berisi trek → tanpa kartu (fallback baris trek)', () {
      expect(chartCardsOf([const ExploreShelf(title: 'Top Songs')]), isEmpty);
      expect(chartCardsOf(const []), isEmpty);
    });
  });

  group('moodTileGradient', () {
    test('garis 0 → pasangan tonal DS', () {
      final (a, b) = moodTileGradient(0);
      expect(a, ClaiColors.surface3);
      expect(b, ClaiColors.surface1);
    });

    test('warna nyata → ujung terang & gelap berbeda, alpha penuh', () {
      final (a, b) = moodTileGradient(0xFF7C4DFF);
      expect(a, isNot(b));
      expect(a.a, 1.0);
      expect(b.a, 1.0);
    });
  });

  group('penyaring merek byline (aturan sumber tak dinamai)', () {
    test('nama kanal platform disaring; nama nyata lolos', () {
      expect(brandSafeByline('YouTube Charts'), '');
      expect(brandSafeByline('Dimas Aditya'), 'Dimas Aditya');
      expect(brandSafeSubtitle('YouTube Charts • 2026'), '2026');
      expect(brandSafeSubtitle('YouTube Charts'), isNull);
      expect(brandSafeSubtitle('Dewa 19 • 2007'), 'Dewa 19 • 2007');
      expect(brandSafeSubtitle(null), isNull);
    });
  });

  group('lastPlayedLabel & formatStorageSize', () {
    late AppLocalizations l;
    setUpAll(() async {
      l = await AppLocalizations.delegate.load(const Locale('id'));
    });

    final now = DateTime(2026, 11, 10, 15, 30);
    int ms(DateTime d) => d.millisecondsSinceEpoch;

    test('hari kalender yang sama → hari ini', () {
      expect(
          lastPlayedLabel(l, ms(DateTime(2026, 11, 10, 0, 5)), now),
          contains('hari ini'));
    });

    test('kemarin kalender (lintas tengah malam) → kemarin', () {
      expect(
          lastPlayedLabel(l, ms(DateTime(2026, 11, 9, 23, 55)), now),
          contains('kemarin'));
    });

    test('3 hari → "3 hari lalu"; 14 hari → "2 minggu lalu"', () {
      expect(lastPlayedLabel(l, ms(DateTime(2026, 11, 7, 12)), now),
          contains('3 hari'));
      expect(lastPlayedLabel(l, ms(DateTime(2026, 10, 27, 12)), now),
          contains('2 minggu'));
    });

    test('60 hari → bulan; 400 hari → tahun', () {
      expect(lastPlayedLabel(l, ms(DateTime(2026, 9, 11, 12)), now),
          contains('bulan'));
      expect(lastPlayedLabel(l, ms(DateTime(2025, 10, 6, 12)), now),
          contains('tahun'));
    });

    test('ukuran: MB bulat; ≥1024 MB → GB satu desimal koma (id)', () {
      expect(formatStorageSize(0, commaDecimal: true), '0 MB');
      expect(formatStorageSize(300 * 1024 * 1024, commaDecimal: true),
          '300 MB');
      expect(formatStorageSize(1536 * 1024 * 1024, commaDecimal: true),
          '1,5 GB');
      expect(formatStorageSize(1536 * 1024 * 1024, commaDecimal: false),
          '1.5 GB');
    });
  });
}

void chartFallbackTitleSizeTests() {
  group('chartFallbackTitleSize (8045, cadangan tipografi Charts)', () {
    test('judul pendek tetap ukuran penuh papan (27)', () {
      expect(chartFallbackTitleSize('DAILY TOP'), 27);
      expect(chartFallbackTitleSize('HITS'), 27);
    });
    test('kata terpanjang menentukan: INDONESIA mengecil agar tak patah', () {
      final s = chartFallbackTitleSize('TRENDING 20 INDONESIA');
      expect(s, lessThan(27));
      expect(s, greaterThanOrEqualTo(17));
      // Kata terpanjang muat di lebar teks kartu (136 dp @ 0,68×ukuran
      // — faktor Clash Display 600 terkalibrasi ulang, ronde 8049).
      expect(s * 0.68 * 'INDONESIA'.length, lessThanOrEqualTo(136.5));
    });
    test('kata ekstrem tetap di atas lantai keterbacaan 17', () {
      expect(chartFallbackTitleSize('SUPERCALIFRAGILISTIC'), 17);
    });
  });
}
