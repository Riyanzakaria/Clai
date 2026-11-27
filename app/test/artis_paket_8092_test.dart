import 'dart:io';

import 'package:clai/data/app_db.dart';
import 'package:clai/domain/models.dart';
import 'package:clai/providers/ytmusic/innertube.dart';
import 'package:clai/ui/widgets.dart' show pickArtistForName;
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Ronde 8092 — Paket Artis (A1 artistIds persisten, A2 cabut cadang
/// pickArtistForName, A3 pewarisan artis rak di parser pencarian).
/// Sumber kebenaran: builds/bukti-artis-dari-player/LAPORAN.md.

Track mk(String id,
        {String names = 'Magnolia Celebration',
        List<String> ids = const []}) =>
    Track(
      key: TrackKey('ytmusic', id),
      title: 'Lagu $id',
      artistNames: names,
      artistIds: ids,
      duration: const Duration(minutes: 3),
      playableRef: id,
    );

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('A1 — migrasi v8 → v9', () {
    test('skema naik ke v9, data v8 utuh, trek lama artistIds=[]', () async {
      final dir = await Directory.systemTemp.createTemp('clai_mig9');
      final path = '${dir.path}/v8.db';
      // Fixture skema v8 minimal: tabel tracks PERSIS definisi lama
      // (tanpa kolom artist_ids) + satu trek tersimpan.
      final v8 = await databaseFactoryFfi.openDatabase(path,
          options: OpenDatabaseOptions(
            version: 8,
            onCreate: (d, v) async {
              await d.execute('''CREATE TABLE tracks (
                provider_id TEXT NOT NULL, provider_track_id TEXT NOT NULL, title TEXT NOT NULL,
                artist_names TEXT NOT NULL, album_id TEXT, duration_ms INTEGER, artwork_url TEXT,
                is_explicit INTEGER NOT NULL DEFAULT 0, playable_ref TEXT NOT NULL, cached_at INTEGER NOT NULL,
                PRIMARY KEY (provider_id, provider_track_id))''');
            },
          ));
      await v8.insert('tracks', {
        'provider_id': 'ytmusic',
        'provider_track_id': 'lama1',
        'title': 'Magnolia',
        'artist_names': 'Magnolia Celebration',
        'album_id': null,
        'duration_ms': 256000,
        'artwork_url': null,
        'is_explicit': 0,
        'playable_ref': 'lama1',
        'cached_at': 1,
      });
      await v8.close();

      final db = AppDb();
      final d = await db.openAt(path);
      expect(await d.getVersion(), 9);
      expect(AppDb.schemaVersion, 9);
      final cols = await d.rawQuery('PRAGMA table_info(tracks)');
      expect(cols.map((c) => c['name']), contains('artist_ids'));
      final lama = await db.trackByKey(const TrackKey('ytmusic', 'lama1'));
      expect(lama, isNotNull);
      expect(lama!.title, 'Magnolia');
      expect(lama.artistNames, 'Magnolia Celebration');
      expect(lama.duration, const Duration(milliseconds: 256000));
      expect(lama.artistIds, isEmpty,
          reason: 'rekam pra-v9 tidak punya pengenal artis — dibaca []');
      await db.close();
      await dir.delete(recursive: true);
    });
  });

  group('A1 — round-trip & penjaga gabung cacheTracks', () {
    test('toDbRow → fromDbRow membawa artistIds identik', () {
      final t = mk('rt1', ids: const ['UCaaa', 'UCbbb']);
      final back = Track.fromDbRow(t.toDbRow());
      expect(back.artistIds, ['UCaaa', 'UCbbb']);
      expect(back.title, t.title);
      expect(back.artistNames, t.artistNames);
      // Baris tanpa kolom artist_ids (peta lama) dibaca sebagai [].
      final row = t.toDbRow()..remove('artist_ids');
      expect(Track.fromDbRow(row).artistIds, isEmpty);
    });

    test('cacheTracks: masuk kosong tidak menghapus, masuk terisi memperbarui',
        () async {
      final db = AppDb();
      await db.openAt(':memory:');
      await db.cacheTracks([mk('g1', ids: const ['UCsimpan'])]);
      expect((await db.trackByKey(const TrackKey('ytmusic', 'g1')))!.artistIds,
          ['UCsimpan']);

      // Trek masuk bernama lengkap tetapi artistIds kosong: id tersimpan
      // TIDAK boleh terhapus (regresi penjaga lama yang menumpang cabang
      // nama-kosong).
      await db.cacheTracks([mk('g1', ids: const [])]);
      expect((await db.trackByKey(const TrackKey('ytmusic', 'g1')))!.artistIds,
          ['UCsimpan']);

      // Trek masuk ber-id terisi memperbarui.
      await db.cacheTracks([mk('g1', ids: const ['UCbaru'])]);
      expect((await db.trackByKey(const TrackKey('ytmusic', 'g1')))!.artistIds,
          ['UCbaru']);
      await db.close();
    });
  });

  group('A2 — pickArtistForName tanpa cadang berbahaya', () {
    const asing = Artist(
        providerId: 'ytmusic', id: 'UCSeP4LSDvpnRarE15oriMoQ', name: 'Alvin Lizada');
    const benar = Artist(
        providerId: 'ytmusic',
        id: 'UCufMCbapcb69A44RTZ8RY-w',
        name: 'Magnolia Celebration');

    test('daftar tanpa kecocokan persis → null, BUKAN results.first', () {
      // Komposisi persis probe hidup LAPORAN: pencarian nama artis yang
      // hasilnya sama sekali tidak memuat artis itu.
      expect(pickArtistForName(const [asing], 'Magnolia Celebration'), isNull);
      expect(pickArtistForName(const [], 'Magnolia Celebration'), isNull);
    });

    test('kecocokan persis (variasi kapitalisasi/spasi) → artis yang benar',
        () {
      expect(pickArtistForName(const [asing, benar], 'magnolia celebration')?.id,
          'UCufMCbapcb69A44RTZ8RY-w');
      expect(pickArtistForName(const [benar], '  MAGNOLIA CELEBRATION ')?.id,
          'UCufMCbapcb69A44RTZ8RY-w');
    });
  });

  group('A3 — pewarisan artis rak di parser pencarian', () {
    // Fixture dibangun dari bentuk nyata probe-search-magnolia.json:
    // musicCardShelfRenderer berjudul artis (run bernama + browseId UC,
    // subtitle "Artist • …") yang isinya item ringkas ber-byline
    // "Song • durasi" + kolom jumlah putar, videoId di playlistItemData.
    Map<String, dynamic> flexCol(List<Map<String, dynamic>> runs) => {
          'musicResponsiveListItemFlexColumnRenderer': {
            'text': {'runs': runs}
          }
        };

    // Bentuk probe nyata: videoId dibawa playlistItemData DAN overlay
    // tombol putar (parser mengambilnya dari overlay).
    Map<String, dynamic> overlayOf(String videoId) => {
          'musicItemThumbnailOverlayRenderer': {
            'content': {
              'musicPlayButtonRenderer': {
                'playNavigationEndpoint': {
                  'watchEndpoint': {'videoId': videoId}
                }
              }
            }
          }
        };

    Map<String, dynamic> compactItem(String videoId, String title, String dur) => {
          'musicResponsiveListItemRenderer': {
            'playlistItemData': {'videoId': videoId},
            'overlay': overlayOf(videoId),
            'flexColumns': [
              flexCol([
                {'text': title}
              ]),
              flexCol([
                {'text': 'Song'},
                {'text': ' • '},
                {'text': dur}
              ]),
              flexCol([
                {'text': '14M plays'}
              ]),
            ],
          }
        };

    Map<String, dynamic> fullItem(String videoId, String title) => {
          'musicResponsiveListItemRenderer': {
            'playlistItemData': {'videoId': videoId},
            'overlay': overlayOf(videoId),
            'flexColumns': [
              flexCol([
                {'text': title}
              ]),
              flexCol([
                {
                  'text': 'Artis Lain',
                  'navigationEndpoint': {
                    'browseEndpoint': {'browseId': 'UCartislain00000000'}
                  }
                }
              ]),
              flexCol([
                {'text': '9K plays'}
              ]),
            ],
            'fixedColumns': [
              {
                'musicResponsiveListItemFixedColumnRenderer': {
                  'text': {
                    'runs': [
                      {'text': '3:00'}
                    ]
                  }
                }
              }
            ],
          }
        };

    Map<String, dynamic> searchJson() => {
          'contents': {
            'sectionListRenderer': {
              'contents': [
                {
                  'musicCardShelfRenderer': {
                    'title': {
                      'runs': [
                        {
                          'text': 'Magnolia Celebration',
                          'navigationEndpoint': {
                            'browseEndpoint': {
                              'browseId': 'UCufMCbapcb69A44RTZ8RY-w'
                            }
                          }
                        }
                      ]
                    },
                    'subtitle': {
                      'runs': [
                        {'text': 'Artist'},
                        {'text': ' • '},
                        {'text': '9.22K subscribers'}
                      ]
                    },
                    'contents': [
                      compactItem('3UdVruU2qGc', 'Magnolia', '4:16'),
                      fullItem('fullVideo01', 'Game Over'),
                    ],
                  }
                },
                {
                  // Rak campuran pencarian umum: item ringkas di luar rak
                  // artis TIDAK mewarisi apa pun.
                  'itemSectionRenderer': {
                    'contents': [
                      compactItem('luarVideo01', 'Lagu Luar', '2:30'),
                    ]
                  }
                },
                {
                  // Rak berjudul nama TANPA browseId UC: bukan konteks
                  // artis yang terbukti — tidak ada pewarisan.
                  'musicCardShelfRenderer': {
                    'title': {
                      'runs': [
                        {'text': 'Bukan Artis Terverifikasi'}
                      ]
                    },
                    'contents': [
                      compactItem('samarVideo1', 'Lagu Samar', '1:59'),
                    ],
                  }
                },
              ]
            }
          }
        };

    test('item ringkas di rak artis mewarisi; item penuh & di luar rak tidak',
        () {
      final res = parseSearchResponse(searchJson());
      final byId = {for (final t in res.songs) t.id: t};

      final ringkas = byId['3UdVruU2qGc']!;
      expect(ringkas.title, 'Magnolia');
      expect(ringkas.artistNames, 'Magnolia Celebration');
      expect(ringkas.artistIds, ['UCufMCbapcb69A44RTZ8RY-w']);
      expect(ringkas.duration, const Duration(minutes: 4, seconds: 16));

      final penuh = byId['fullVideo01']!;
      expect(penuh.artistNames, 'Artis Lain',
          reason: 'metadata per-trek yang ada tidak boleh tertimpa rak');
      expect(penuh.artistIds, ['UCartislain00000000']);

      final luar = byId['luarVideo01']!;
      expect(luar.artistNames, '');
      expect(luar.artistIds, isEmpty);

      final samar = byId['samarVideo1']!;
      expect(samar.artistNames, '');
      expect(samar.artistIds, isEmpty);
    });
  });
}
