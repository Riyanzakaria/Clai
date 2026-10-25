import 'package:clai/providers/ytmusic/innertube.dart';
import 'package:flutter_test/flutter_test.dart';

/// Fixture terpotong & teranonimkan dari bentuk respons WEB_REMIX (Blueprint 5.6).
Map<String, dynamic> songItem() => {
      'musicResponsiveListItemRenderer': {
        'flexColumns': [
          {'musicResponsiveListItemFlexColumnRenderer': {'text': {'runs': [{'text': 'Lagu Uji'}]}}},
          {'musicResponsiveListItemFlexColumnRenderer': {'text': {'runs': [
            {'text': 'Artis Uji', 'navigationEndpoint': {'browseEndpoint': {'browseId': 'UC1234567890abcdef'}}},
          ]}}},
          {'musicResponsiveListItemFlexColumnRenderer': {'text': {'runs': [
            {'text': 'Album Uji', 'navigationEndpoint': {'browseEndpoint': {'browseId': 'MPREb_albumuji'}}},
          ]}}},
        ],
        'fixedColumns': [
          {'musicResponsiveListItemFixedColumnRenderer': {'text': {'runs': [{'text': '3:45'}]}}},
        ],
        'thumbnail': {'musicThumbnailRenderer': {'thumbnail': {'thumbnails': [
          {'url': 'https://example.invalid/w60.jpg', 'width': 60},
          {'url': 'https://example.invalid/w226.jpg', 'width': 226},
        ]}}},
        'overlay': {'musicItemThumbnailOverlayRenderer': {'content': {'musicPlayButtonRenderer': {
          'playNavigationEndpoint': {'watchEndpoint': {'videoId': 'dQw4w9WgXcQ'}},
        }}}},
      },
    };

void main() {
  test('parseDurationText menangani m:ss dan h:mm:ss', () {
    expect(parseDurationText('3:45')!.inSeconds, 225);
    expect(parseDurationText('1:02:03')!.inSeconds, 3723);
    expect(parseDurationText('bukan angka'), isNull);
  });

  test('collectTracks mengurai item lagu dari pohon bersarang', () {
    final tree = {'contents': {'shelves': [songItem(), songItem()]}};
    final tracks = collectTracks(tree);
    // Item yang sama dua kali harus ter-dedupe oleh kunci videoId dari overlay.
    expect(tracks.length, 1);
    final t = tracks.first;
    expect(t.title, 'Lagu Uji');
    expect(t.artistNames, 'Artis Uji');
    expect(t.artistIds, contains('UC1234567890abcdef'));
    expect(t.albumId, 'MPREb_albumuji');
    expect(t.duration!.inSeconds, 225);
  });

  test('pohon kosong menghasilkan daftar kosong, bukan crash', () {
    expect(collectTracks({'a': 1}), isEmpty);
    expect(collectTracks(null), isEmpty);
  });

  // v4.3: bentuk item panel dari endpoint `next` (radio/automix) — fixture
  // dipadatkan dari probe hidup (kunci-kunci asli playlistPanelVideoRenderer).
  Map<String, dynamic> panelItem() => {
        'playlistPanelVideoRenderer': {
          'title': {'runs': [{'text': 'Lagu Panel'}]},
          'longBylineText': {'runs': [
            {'text': 'Artis Panel', 'navigationEndpoint': {'browseEndpoint': {'browseId': 'UCpanel123456789'}}},
          ]},
          'shortBylineText': {'runs': [{'text': 'Artis Panel'}]},
          'lengthText': {'runs': [{'text': '4:14'}]},
          'thumbnail': {'thumbnails': [
            {'url': 'https://example.invalid/panel.jpg', 'width': 120},
          ]},
          'videoId': 'panelVideo01',
          'navigationEndpoint': {'watchEndpoint': {'videoId': 'panelVideo01'}},
        },
      };

  test('collectTracks mengurai playlistPanelVideoRenderer (sumber radio)', () {
    final tree = {'contents': {'playlistPanelRenderer': {'contents': [panelItem(), panelItem()]}}};
    final tracks = collectTracks(tree);
    expect(tracks.length, 1, reason: 'item sama ter-dedupe per videoId');
    final t = tracks.single;
    expect(t.title, 'Lagu Panel');
    expect(t.artistNames, 'Artis Panel');
    expect(t.artistIds, contains('UCpanel123456789'));
    expect(t.duration!.inSeconds, 254);
    expect(t.playableRef, 'panelVideo01');
  });

  test('parsePanelTrackItem menolak item tanpa videoId/judul', () {
    expect(parsePanelTrackItem({'title': {'runs': [{'text': 'X'}]}}), isNull);
    expect(parsePanelTrackItem({'videoId': 'abc'}), isNull);
    expect(parsePanelTrackItem(null), isNull);
  });
}
