import 'package:clai/domain/models.dart';
import 'package:clai/providers/spotify/spotify_web.dart';
import 'package:clai/providers/ytmusic/innertube.dart';
import 'package:clai/services/lyrics_service.dart';
import 'package:clai/services/track_matcher.dart';
import 'package:clai/services/update_service.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _twoRow(String id, String title, String sub) => {
      'musicTwoRowItemRenderer': {
        'title': {'runs': [{'text': title}]},
        'subtitle': {'runs': [{'text': sub}]},
        'thumbnailRenderer': {
          'musicThumbnailRenderer': {
            'thumbnail': {'thumbnails': [
              {'url': 'https://img/w60', 'width': 60},
              {'url': 'https://img/w540', 'width': 540},
            ]},
          },
        },
        'navigationEndpoint': {'browseEndpoint': {'browseId': id}},
      },
    };

void main() {
  group('F2 Pembaruan — umpan rilis', () {
    final sample = <String, dynamic>{
      'tag_name': 'v1.0.0+4',
      'draft': false,
      'body': 'Catatan rilis',
      'assets': [
        {'name': 'app-arm64-v8a-release.apk', 'browser_download_url': 'https://x/arm64.apk', 'size': 100},
        {'name': 'app-x86_64-release.apk', 'browser_download_url': 'https://x/x64.apk', 'size': 120},
      ],
    };
    test('parse tag + aset', () {
      final r = parseGithubReleaseJson(sample)!;
      expect(r.versionName, '1.0.0');
      expect(r.build, 4);
      expect(r.assets.length, 2);
    });
    test('draf ditolak', () {
      expect(parseGithubReleaseJson({...sample, 'draft': true}), isNull);
    });
    test('perbandingan versi', () {
      final r4 = parseGithubReleaseJson(sample)!;
      expect(isNewerRelease(r4, currentName: '1.0.0', currentBuild: 3), isTrue);
      expect(isNewerRelease(r4, currentName: '1.0.0', currentBuild: 4), isFalse);
      expect(isNewerRelease(r4, currentName: '1.0.0', currentBuild: 5), isFalse);
      final noBuild = parseGithubReleaseJson({'tag_name': 'v1.1.0', 'assets': const []})!;
      expect(isNewerRelease(noBuild, currentName: '1.0.0', currentBuild: 0), isTrue);
      expect(isNewerRelease(noBuild, currentName: '1.2.0', currentBuild: 0), isFalse);
    });
    test('pilih aset per ABI', () {
      final r = parseGithubReleaseJson(sample)!;
      expect(pickReleaseAsset(r, ['arm64-v8a', 'armeabi-v7a'])!.name, 'app-arm64-v8a-release.apk');
      expect(pickReleaseAsset(r, ['x86_64'])!.name, 'app-x86_64-release.apk');
      expect(pickReleaseAsset(r, ['armeabi-v7a'])!.name, 'app-arm64-v8a-release.apk'); // jatuh ke APK pertama
      final noApk = parseGithubReleaseJson({'tag_name': 'v2.0.0+9', 'assets': [
        {'name': 'notes.txt', 'browser_download_url': 'https://x/n', 'size': 1}
      ]})!;
      expect(pickReleaseAsset(noApk, ['arm64-v8a']), isNull);
    });
  });

  group('F2 Jelajah — pengurai rak umpan', () {
    test('rak carousel + shelf terurai berurutan dengan judul', () {
      final json = <String, dynamic>{
        'contents': {
          'sectionListRenderer': {
            'contents': [
              {'musicCarouselShelfRenderer': {
                'header': {'musicCarouselShelfBasicHeaderRenderer': {'title': {'runs': [{'text': 'New releases'}]}}},
                'contents': [
                  _twoRow('MPREb_album1', 'Album Baru', 'Artis A'),
                  _twoRow('VLPLplaylist1', 'Playlist Publik', 'Spotify'),
                ],
              }},
              {'musicShelfRenderer': {
                'header': {'musicShelfBasicHeaderRenderer': {'title': {'simpleText': 'Charts'}}},
                'contents': [_twoRow('UCartist1', 'Artis Top', '')],
              }},
              // Rak kosong harus dibuang.
              {'musicCarouselShelfRenderer': {
                'header': {'musicCarouselShelfBasicHeaderRenderer': {'title': {'runs': [{'text': 'Kosong'}]}}},
                'contents': const [],
              }},
            ],
          },
        },
      };
      final shelves = parseHomeFeedShelves(json);
      expect(shelves.length, 2);
      expect(shelves[0].title, 'New releases');
      expect(exploreTitleId(shelves[0].title), 'Rilis Baru');
      expect(shelves[0].albums.single.title, 'Album Baru');
      expect(shelves[0].playlists.single.id, 'VLPLplaylist1');
      expect(shelves[1].artists.single.id, 'UCartist1');
      expect(exploreTitleId('Judul Aneh Sumber'), 'Judul Aneh Sumber');
    });
    test('JSON tanpa rak → kosong (bukan crash)', () {
      expect(parseHomeFeedShelves({'contents': {}}), isEmpty);
      expect(parseHomeFeedShelves({}), isEmpty);
    });
  });

  group('F2 Lirik — pengurai LRC', () {
    test('multi cap waktu + pecahan + offset', () {
      final lines = parseLrc('[offset:+100]\n[00:10.00][00:20.50]Halo dunia\n[00:30.25]Baris kedua\nteks tanpa waktu');
      expect(lines, isNotNull);
      expect(lines!.length, 3);
      expect(lines[0].at, const Duration(milliseconds: 9900));
      expect(lines[0].text, 'Halo dunia');
      expect(lines[1].at, const Duration(milliseconds: 20400));
      expect(lines[2].at, const Duration(milliseconds: 30150));
    });
    test('teks polos bukan LRC', () {
      expect(parseLrc('hanya lirik polos\ntanpa cap waktu'), isNull);
      expect(parseLrc('[00:01.00]satu-satunya baris'), isNull);
    });
    test('nama artis utama & judul bersih', () {
      expect(primaryArtistName('Arctic Monkeys • 16M views'), 'Arctic Monkeys');
      expect(primaryArtistName('A, B'), 'A');
      expect(cleanedSongTitle('Lagu (Official Music Video) [HD]'), 'Lagu');
    });
  });

  group('F2 Spotify — TOTP & tautan', () {
    test('vektor RFC 6238 (SHA1, 6 digit)', () {
      // Rahasia uji klasik RFC: "12345678901234567890" (ASCII).
      expect(spotifyTotp(59, secret: '12345678901234567890'), '287082');
      expect(spotifyTotp(1111111109, secret: '12345678901234567890'), '081804');
    });
    test('kenali tautan playlist', () {
      expect(spotifyPlaylistIdFromText('https://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M?si=abc'), '37i9dQZF1DXcBWIGoYBM5M');
      expect(spotifyPlaylistIdFromText('https://open.spotify.com/intl-id/playlist/3ktAYNcRHpazJ9qecm3ptn'), '3ktAYNcRHpazJ9qecm3ptn');
      expect(spotifyPlaylistIdFromText('spotify:playlist:37i9dQZF1DXcBWIGoYBM5M'), '37i9dQZF1DXcBWIGoYBM5M');
      expect(spotifyPlaylistIdFromText('https://open.spotify.com/track/4uLU6hMCjMI75M1A2tKUQC'), isNull);
      expect(spotifyLinkOf('https://open.spotify.com/track/4uLU6hMCjMI75M1A2tKUQC')!.kind, 'track');
      expect(spotifyLinkOf('505 arctic monkeys'), isNull);
    });
  });

  group('F2 Spotify — pengurai fetchPlaylist (fixture terbukti riset)', () {
    Map<String, dynamic> page() => {
          'data': {
            'playlistV2': {
              '__typename': 'Playlist',
              'uri': 'spotify:playlist:37i9dQZF1DXcBWIGoYBM5M',
              'name': "Today's Top Hits",
              'description': 'The hottest 50.',
              'ownerV2': {'data': {'name': 'Spotify', 'uri': 'spotify:user:spotify'}},
              'images': {'items': [
                {'sources': [
                  {'width': 640, 'height': 640, 'url': 'https://i.scdn.co/pl640'},
                ]},
              ]},
              'content': {
                'totalCount': 2,
                'items': [
                  {'itemV2': {'__typename': 'TrackResponseWrapper', 'data': {
                    '__typename': 'Track',
                    'uri': 'spotify:track:2sFepQNyl1WjpROruP8bJ0',
                    'name': 'Housewife',
                    'artists': {'items': [
                      {'uri': 'spotify:artist:45dkTj5sMRSjrmBSBeiHym', 'profile': {'name': 'Tate McRae'}},
                    ]},
                    'albumOfTrack': {
                      'uri': 'spotify:album:6JvmSyocXef7RZDZFaymNl', 'name': 'Housewife',
                      'coverArt': {'sources': [
                        {'width': 64, 'url': 'https://i.scdn.co/a64'},
                        {'width': 300, 'url': 'https://i.scdn.co/a300'},
                        {'width': 640, 'url': 'https://i.scdn.co/a640'},
                      ]},
                    },
                    'trackDuration': {'totalMilliseconds': 208810},
                    'playability': {'playable': true, 'reason': 'PLAYABLE'},
                    'contentRating': {'label': 'NONE'},
                  }}},
                  {'itemV2': {'__typename': 'EpisodeResponseWrapper', 'data': {
                    '__typename': 'Episode', 'uri': 'spotify:episode:xyz', 'name': 'Ep 1',
                  }}},
                ],
              },
            },
          },
        };
    test('petakan header + trek; episode dihitung non-trek', () {
      final d = parseFetchPlaylistPage(page());
      expect(d.name, "Today's Top Hits");
      expect(d.ownerName, 'Spotify');
      expect(d.totalCount, 2);
      expect(d.tracks.length, 1);
      expect(d.nonTrackItems, 1);
      final t = d.tracks.single;
      expect(t.key.providerId, 'spotify');
      expect(t.id, '2sFepQNyl1WjpROruP8bJ0');
      expect(t.artistNames, 'Tate McRae');
      expect(t.albumTitle, 'Housewife');
      expect(t.artworkUrl, 'https://i.scdn.co/a640');
      expect(t.duration, const Duration(milliseconds: 208810));
    });
    test('NotFound → pengecualian berpesan lokal jujur', () {
      final nf = {'data': {'playlistV2': {'__typename': 'NotFound', 'message': 'Object not found'}}};
      expect(() => parseFetchPlaylistPage(nf), throwsA(isA<SpotifyProviderException>()));
    });
    test('bentuk rusak → pengecualian', () {
      expect(() => parseFetchPlaylistPage({'data': {}}), throwsA(isA<SpotifyProviderException>()));
    });
  });

  group('F2 Pencocok trek', () {
    Track cand(String title, String artist, int durMs) => Track(
        key: TrackKey('ytmusic', 'v_$title'), title: title, artistNames: artist,
        duration: Duration(milliseconds: durMs), playableRef: 'v_$title');
    test('normalisasi membuang embel-embel', () {
      expect(normalizeMatchText('Housewife (Official Video)'), 'housewife');
      expect(normalizeMatchText('Song feat. Someone'), 'song');
    });
    test('skor: identik tinggi, beda artis turun, lagu lain rendah', () {
      final same = matchScore(srcTitle: '505', srcArtist: 'Arctic Monkeys',
          srcDuration: const Duration(seconds: 193), candidate: cand('505', 'Arctic Monkeys', 193000));
      expect(same, greaterThan(0.9));
      final wrong = matchScore(srcTitle: '505', srcArtist: 'Arctic Monkeys',
          srcDuration: const Duration(seconds: 193), candidate: cand('R U Mine?', 'Arctic Monkeys', 193000));
      expect(wrong, lessThan(kMatchThreshold));
    });
  });
}
