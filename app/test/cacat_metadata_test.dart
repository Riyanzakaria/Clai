import 'package:clai/data/app_db.dart';
import 'package:clai/domain/models.dart';
import 'package:clai/providers/ytmusic/innertube.dart';
import 'package:clai/services/ocr_model_service.dart';
import 'package:clai/services/track_metadata_healer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Ronde Cacat Metadata (build 2014): trek tampil tanpa artis & tanpa
/// sampul. Akar terbukti hidup 25 Okt 2026 — item daftar trek halaman ALBUM
/// tidak membawa byline sama sekali di sumbernya (kolom fleksibel ke-2
/// kosong, tanpa thumbnail); artis hanya ada di strapline header. Ditambah
/// dua cacat byline saudara: kata kategori "Song" tersimpan sebagai nama
/// artis, dan byline panel penuh "Artis • Album • Tahun" disimpan utuh.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('artistNameFromByline', () {
    test('byline panel penuh → segmen pertama saja', () {
      expect(artistNameFromByline('sombr • I Barely Know Her • 2025'), 'sombr');
      expect(artistNameFromByline('The 1975 • Being Funny In A Foreign Language • 2022'),
          'The 1975');
    });
    test('kata kategori saja → kosong jujur, bukan nama artis', () {
      expect(artistNameFromByline('Song'), '');
      expect(artistNameFromByline('Video'), '');
      expect(artistNameFromByline(''), '');
    });
    test('nama artis biasa tidak diubah', () {
      expect(artistNameFromByline('sombr'), 'sombr');
      expect(artistNameFromByline('Netto Brito & Luan Pereira'),
          'Netto Brito & Luan Pereira');
      // Dua segmen tanpa tahun/statistik di ekor: bukan pola album → biarkan.
      expect(artistNameFromByline('A • B'), 'A • B');
    });
    test('ekor statistik video dibuang', () {
      expect(
          artistNameFromByline('Rachel Chinouriri • 552K views • 8.1K likes'),
          'Rachel Chinouriri');
      expect(artistNameFromByline('Arctic Monkeys • 16M views'),
          'Arctic Monkeys');
      expect(artistNameFromByline('alive band official • 10M views • 20K likes'),
          'alive band official');
      expect(artistNameFromByline('sombr • 3.8M plays'), 'sombr');
    });
  });

  group('parseTrackItem bentuk album (bukti hidup MPREb_UAlc3D9cy2s)', () {
    // Disederhanakan dari respons browse asli: flexColumns[1].text = {}
    // (byline kosong), TANPA kunci thumbnail, durasi di fixedColumns.
    final albumItem = <String, dynamic>{
      'videoId': 'RUdeXgc4vL0',
      'flexColumns': [
        {
          'musicResponsiveListItemFlexColumnRenderer': {
            'text': {
              'runs': [
                {'text': 'All I Ever Asked (with sombr) (feat. sombr)'}
              ]
            }
          }
        },
        {
          'musicResponsiveListItemFlexColumnRenderer': {'text': {}}
        },
        {
          'musicResponsiveListItemFlexColumnRenderer': {
            'text': {
              'runs': [
                {'text': '3.8M plays'}
              ]
            }
          }
        },
      ],
      'fixedColumns': [
        {
          'musicResponsiveListItemFixedColumnRenderer': {
            'text': {
              'runs': [
                {'text': '3:38'}
              ]
            }
          }
        }
      ],
    };

    test('artis kosong & sampul null dari sumber — bentuk inilah cacatnya',
        () {
      final t = parseTrackItem(albumItem);
      expect(t, isNotNull);
      expect(t!.artistNames, '');
      expect(t.artworkUrl, isNull);
      expect(t.duration, const Duration(minutes: 3, seconds: 38));
    });

    test('inheritPageArtist mengisi dari konteks header', () {
      final t = parseTrackItem(albumItem)!;
      final filled = inheritPageArtist([t],
          artist: 'Rachel Chinouriri',
          artistIds: const ['UCiZ0AtOgemlCINGbnUK54kw'],
          artworkUrl: 'https://yt3.googleusercontent.com/cover=w544');
      expect(filled.single.artistNames, 'Rachel Chinouriri');
      expect(filled.single.artistIds, ['UCiZ0AtOgemlCINGbnUK54kw']);
      expect(filled.single.artworkUrl, contains('w544'));
    });

    test('inheritPageArtist tidak menimpa metadata per-trek yang ada', () {
      final good = Track(
          key: const TrackKey('ytmusic', 'x1'),
          title: 'X',
          artistNames: 'Artis Asli',
          artworkUrl: 'https://img/track',
          playableRef: 'x1');
      final out = inheritPageArtist([good],
          artist: 'Artis Halaman', artworkUrl: 'https://img/page');
      expect(out.single.artistNames, 'Artis Asli');
      expect(out.single.artworkUrl, 'https://img/track');
    });
  });

  test('parseTrackItem byline kategori saja tidak lagi bocor jadi artis',
      () {
    final item = <String, dynamic>{
      'videoId': 'c-8abSPAPOU',
      'flexColumns': [
        {
          'musicResponsiveListItemFlexColumnRenderer': {
            'text': {
              'runs': [
                {'text': 'back to friends'}
              ]
            }
          }
        },
        {
          'musicResponsiveListItemFlexColumnRenderer': {
            'text': {
              'runs': [
                {'text': 'Song'}
              ]
            }
          }
        },
      ],
      'fixedColumns': [
        {
          'musicResponsiveListItemFixedColumnRenderer': {
            'text': {
              'runs': [
                {'text': '3:20'}
              ]
            }
          }
        }
      ],
    };
    final t = parseTrackItem(item);
    expect(t, isNotNull);
    expect(t!.artistNames, '', reason: 'dulu tersimpan harfiah sebagai "Song"');
  });

  test('parsePanelTrackItem mereduksi byline penuh ke nama artis', () {
    final panel = <String, dynamic>{
      'videoId': 'abc123',
      'title': {
        'runs': [
          {'text': 'back to friends'}
        ]
      },
      'longBylineText': {
        'runs': [
          {'text': 'sombr • I Barely Know Her • 2025'}
        ]
      },
      'lengthText': {
        'runs': [
          {'text': '3:20'}
        ]
      },
      'thumbnail': {
        'thumbnails': [
          {'url': 'https://i.ytimg.com/vi/abc123/default.jpg', 'width': 120}
        ]
      },
    };
    final t = parsePanelTrackItem(panel);
    expect(t, isNotNull);
    expect(t!.artistNames, 'sombr');
    expect(t.artworkUrl, isNotNull);
  });

  group('cacheTracks penjaga metadata', () {
    test('tulis-ulang stub tidak menghapus artis/sampul yang dikenal',
        () async {
      final db = AppDb();
      await db.openAt(':memory:');
      const key = TrackKey('ytmusic', 'g1');
      final good = Track(
          key: key,
          title: 'Lagu',
          artistNames: 'Artis',
          artworkUrl: 'https://img/good',
          duration: const Duration(minutes: 3),
          playableRef: 'g1');
      await db.cacheTracks([good]);
      final stub = Track(
          key: key, title: 'Lagu', artistNames: '', playableRef: 'g1');
      await db.cacheTracks([stub]);
      final row = await db.trackByKey(key);
      expect(row!.artistNames, 'Artis');
      expect(row.artworkUrl, 'https://img/good');
      expect(row.duration, const Duration(minutes: 3));
      // Nilai tak-kosong yang masuk tetap menang (pembaruan sah).
      final newer = Track(
          key: key,
          title: 'Lagu',
          artistNames: 'Artis Baru',
          artworkUrl: 'https://img/new',
          playableRef: 'g1');
      await db.cacheTracks([newer]);
      final row2 = await db.trackByKey(key);
      expect(row2!.artistNames, 'Artis Baru');
      expect(row2.artworkUrl, 'https://img/new');
    });
  });

  group('TrackMetadataHealer', () {
    Track broken() => Track(
        key: const TrackKey('ytmusic', 'h1'),
        title: 'Why',
        artistNames: '',
        playableRef: 'h1');

    test('resolve by ID menyembuhkan baris lokal sekali', () async {
      final db = AppDb();
      await db.openAt(':memory:');
      await db.cacheTracks([broken()]);
      var calls = 0;
      final healer = TrackMetadataHealer(db, resolveById: (id) async {
        calls++;
        return Track(
            key: TrackKey('ytmusic', id),
            title: 'Why',
            artistNames: 'sombr',
            artworkUrl: 'https://img/why',
            playableRef: id);
      });
      final healed = await healer.healIfNeeded(broken());
      expect(healed, isNotNull);
      expect(healed!.artistNames, 'sombr');
      expect(healed.artworkUrl, 'https://img/why');
      final row = await db.trackByKey(const TrackKey('ytmusic', 'h1'));
      expect(row!.artistNames, 'sombr');
      expect(row.artworkUrl, 'https://img/why');
      // Trek yang sudah sembuh tidak memanggil resolver lagi.
      final again = await healer.healIfNeeded(row);
      expect(again, isNull);
      expect(calls, 1);
    });

    test('kegagalan resolve ditandai — tidak diulang agresif', () async {
      final db = AppDb();
      await db.openAt(':memory:');
      var calls = 0;
      final healer = TrackMetadataHealer(db, resolveById: (id) async {
        calls++;
        return null;
      });
      // ID khusus tes ini: basis data ':memory:' ffi dipakai bersama antar
      // tes dalam satu berkas, tanda percobaan tes lain tidak boleh bocor.
      final t9 = Track(
          key: const TrackKey('ytmusic', 'h9'),
          title: 'Why',
          artistNames: '',
          playableRef: 'h9');
      expect(await healer.healIfNeeded(t9), isNull);
      expect(await healer.healIfNeeded(t9), isNull);
      expect(calls, 1,
          reason: 'percobaan gagal menandai pref; panggilan kedua ditahan');
      // Baris lokal tidak berubah dan tidak ada error yang lolos.
      expect(await db.trackByKey(const TrackKey('ytmusic', 'h9')), isNull);
    });

    test('artis byline mengembang (pola rak pemilik) ikut disembuhkan',
        () async {
      final db = AppDb();
      await db.openAt(':memory:');
      final bloated = Track(
          key: const TrackKey('ytmusic', 'h7'),
          title: 'Why',
          artistNames: 'sombr • I Barely Know Her • 2025',
          artworkUrl: 'https://img/why',
          playableRef: 'h7');
      expect(TrackMetadataHealer.needsHeal(bloated), isTrue,
          reason: 'judul rak pemilik lahir dari nilai seperti ini');
      final healer = TrackMetadataHealer(db, resolveById: (id) async => Track(
          key: TrackKey('ytmusic', id),
          title: 'Why',
          artistNames: 'sombr',
          artworkUrl: 'https://img/why',
          playableRef: id));
      final healed = await healer.healIfNeeded(bloated);
      expect(healed!.artistNames, 'sombr');
    });

    test('artis kata kategori ("Song") ikut disembuhkan; trek lokal tidak',
        () async {
      final db = AppDb();
      await db.openAt(':memory:');
      final songWart = Track(
          key: const TrackKey('ytmusic', 'h2'),
          title: 'back to friends',
          artistNames: 'Song',
          artworkUrl: 'https://img/btf',
          playableRef: 'h2');
      expect(TrackMetadataHealer.needsHeal(songWart), isTrue);
      final healer = TrackMetadataHealer(db, resolveById: (id) async => Track(
          key: TrackKey('ytmusic', id),
          title: 'back to friends',
          artistNames: 'sombr',
          artworkUrl: 'https://img/btf',
          playableRef: id));
      final healed = await healer.healIfNeeded(songWart);
      expect(healed!.artistNames, 'sombr');
      final local = Track(
          key: const TrackKey('local', 'l1'),
          title: 'Berkas',
          artistNames: '',
          playableRef: '/music/x.mp3');
      expect(TrackMetadataHealer.needsHeal(local), isFalse);
    });
  });

  group('parseOcrModelManifestBody (kebal content-type)', () {
    const body =
        '{"lang":"eng","file":"eng.traineddata","size":4113088,'
        '"sha256":"7d4322bd2a7749724879683fc3912cb542f19906c83bcc1a52132556427170b2",'
        '"version":"tessdata_fast 4.1.0 (eng)"}';
    test('badan String JSON utuh terurai (bentuk insiden octet-stream)', () {
      final m = parseOcrModelManifestBody(body);
      expect(m, isNotNull);
      expect(m!.file, 'eng.traineddata');
      expect(m.size, 4113088);
    });
    test('badan kosong / sampah / bukan objek → null', () {
      expect(parseOcrModelManifestBody(null), isNull);
      expect(parseOcrModelManifestBody(''), isNull);
      expect(parseOcrModelManifestBody('bukan json'), isNull);
      expect(parseOcrModelManifestBody('[1,2]'), isNull);
      expect(parseOcrModelManifestBody('{"lang":"eng"}'), isNull);
    });
  });
}
