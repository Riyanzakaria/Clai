import 'package:clai/core/artwork.dart';
import 'package:clai/providers/ytmusic/innertube.dart';
import 'package:flutter_test/flutter_test.dart';

/// v4.4 butir 4 — sampul tajam sadar ukuran tampil.
void main() {
  group('artworkUrlForSize — googleusercontent', () {
    const base = 'https://lh3.googleusercontent.com/abc123=w60-h60-l90-rj';
    test('permintaan besar menulis ulang w/h, flag lain utuh', () {
      expect(artworkUrlForSize(base, 1080),
          'https://lh3.googleusercontent.com/abc123=w1080-h1080-l90-rj');
    });
    test('permintaan daftar menulis ulang ke 200', () {
      expect(artworkUrlForSize(base, 200),
          'https://lh3.googleusercontent.com/abc123=w200-h200-l90-rj');
    });
    test('URL tersimpan lama (=w226) bisa dinaikkan', () {
      expect(
          artworkUrlForSize('https://lh3.googleusercontent.com/x=w226-h226-l90-rj', 1080),
          'https://lh3.googleusercontent.com/x=w1080-h1080-l90-rj');
    });
    test('suffix tanpa -h tetap ditulis ulang berpasangan', () {
      expect(artworkUrlForSize('https://lh3.googleusercontent.com/x=w544-l90-rj', 200),
          'https://lh3.googleusercontent.com/x=w200-h200-l90-rj');
    });
    test('URL tanpa suffix ukuran tidak diubah', () {
      const u = 'https://lh3.googleusercontent.com/plainimage';
      expect(artworkUrlForSize(u, 1080), u);
    });
  });

  group('artworkUrlForSize — i.ytimg', () {
    const def = 'https://i.ytimg.com/vi/VID123/default.jpg';
    test('target besar → maxresdefault', () {
      expect(artworkUrlForSize(def, 1080), 'https://i.ytimg.com/vi/VID123/maxresdefault.jpg');
    });
    test('target sedang → hqdefault', () {
      expect(artworkUrlForSize(def, 544), 'https://i.ytimg.com/vi/VID123/hqdefault.jpg');
    });
    test('target kecil → mqdefault', () {
      expect(artworkUrlForSize(def, 200), 'https://i.ytimg.com/vi/VID123/mqdefault.jpg');
    });
    test('tidak pernah menurunkan varian yang sudah besar', () {
      const max = 'https://i.ytimg.com/vi/VID123/maxresdefault.jpg';
      expect(artworkUrlForSize(max, 200), max);
    });
  });

  group('artworkUrlForSize — yang tidak disentuh', () {
    test('null & kosong lolos apa adanya', () {
      expect(artworkUrlForSize(null, 1080), isNull);
      expect(artworkUrlForSize('', 1080), '');
    });
    test('jalur lokal/MediaStore tidak diubah', () {
      const c = 'content://media/external/audio/albumart/42';
      expect(artworkUrlForSize(c, 1080), c);
      const f = 'file:///storage/emulated/0/Music/cover.jpg';
      expect(artworkUrlForSize(f, 1080), f);
    });
    test('host http lain tidak diubah', () {
      const u = 'https://example.invalid/cover.jpg';
      expect(artworkUrlForSize(u, 1080), u);
    });
  });

  group('artworkBucketFor', () {
    test('baris daftar 48dp tetap di tangga kecil', () {
      expect(artworkBucketFor(48, 2.625), 200);
      expect(artworkBucketFor(48, 3.0), 200);
    });
    test('kartu 84dp naik ke 544', () {
      expect(artworkBucketFor(84, 3.0), 544);
    });
    test('sampul Player selebar konten naik ke 1080', () {
      expect(artworkBucketFor(371, 2.625), 1080);
      expect(artworkBucketFor(320, 2.0), 1080);
    });
  });

  group('thumbUrl — varian terbesar dari larik sumber', () {
    Map<String, dynamic> node(List<Map<String, Object>> thumbs) => {
          'musicThumbnailRenderer': {'thumbnail': {'thumbnails': thumbs}}
        };
    test('larik multi-ukuran: yang terbesar menang (bukan terkecil >= ambang)', () {
      final url = thumbUrl(node([
        {'url': 'https://lh3.googleusercontent.com/a=w60-h60-l90-rj', 'width': 60},
        {'url': 'https://lh3.googleusercontent.com/a=w544-h544-l90-rj', 'width': 544},
        {'url': 'https://lh3.googleusercontent.com/a=w226-h226-l90-rj', 'width': 226},
      ]));
      expect(url, 'https://lh3.googleusercontent.com/a=w544-h544-l90-rj');
    });
    test('larik satu ukuran tetap terambil', () {
      final url = thumbUrl(node([
        {'url': 'https://i.ytimg.com/vi/x/hqdefault.jpg', 'width': 480},
      ]));
      expect(url, 'https://i.ytimg.com/vi/x/hqdefault.jpg');
    });
    test('node kosong → null', () {
      expect(thumbUrl(null), isNull);
      expect(thumbUrl({'lain': 1}), isNull);
    });
    test('REGRESI cacat diskografi: pembungkus thumbnailRenderer (halaman artis)', () {
      // Bentuk persis dari probe hidup halaman artis (2026-10-23): item dua-baris
      // diskografi membawa {thumbnailRenderer: {musicThumbnailRenderer: ...}}.
      final node = {
        'thumbnailRenderer': {
          'musicThumbnailRenderer': {
            'thumbnail': {
              'thumbnails': [
                {'url': 'https://yt3.googleusercontent.com/x=w226-h226-l90-rj', 'width': 226},
                {'url': 'https://yt3.googleusercontent.com/x=w544-h544-l90-rj', 'width': 544},
              ]
            }
          }
        }
      };
      expect(thumbUrl(node), 'https://yt3.googleusercontent.com/x=w544-h544-l90-rj');
    });
    test('collectTwoRow membaca sampul diskografi bentuk halaman artis', () {
      final tree = {
        'musicTwoRowItemRenderer': {
          'title': {'runs': [{'text': 'Malibu Nights'}]},
          'subtitle': {'runs': [{'text': 'Album • 2018'}]},
          'navigationEndpoint': {'browseEndpoint': {'browseId': 'MPREb_test123'}},
          'thumbnailRenderer': {
            'musicThumbnailRenderer': {
              'thumbnail': {
                'thumbnails': [
                  {'url': 'https://yt3.googleusercontent.com/a=w226-h226-l90-rj', 'width': 226},
                  {'url': 'https://yt3.googleusercontent.com/a=w544-h544-l90-rj', 'width': 544},
                ]
              }
            }
          },
        }
      };
      final r = collectTwoRow(tree);
      expect(r.albums, hasLength(1));
      expect(r.albums.single.artworkUrl, 'https://yt3.googleusercontent.com/a=w544-h544-l90-rj');
    });
  });
}
