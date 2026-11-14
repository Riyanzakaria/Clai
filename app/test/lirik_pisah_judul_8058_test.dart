import 'package:clai/data/app_db.dart';
import 'package:clai/domain/models.dart';
import 'package:clai/services/lyrics_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Ronde 8058 — perbaikan lirik pola "Artis - Judul".
/// Kasus terbukti (perangkat pemilik, 13 Nov): trek unggahan video
/// "COLORCODE - Sway (Official Lyrics Video)" dengan artis terbaca
/// nama kanal "Eclipse Time Records" tidak pernah ditemukan LRCLIB,
/// padahal liriknya ada sebagai (Sway, COLORCODE, 248 dtk).
const _lrcSway =
    '[00:06.63]♪\n[00:28.74]It\'s been over a year since we\'ve been apart\n[00:33.54]But somehow nothing\'s changed';

Track _track(String title, String artist, {int durSec = 248}) => Track(
      key: TrackKey('ytmusic', 'uji8058-$title-$artist'),
      title: title,
      artistNames: artist,
      duration: Duration(seconds: durSec),
      playableRef: 'uji8058',
    );

/// LRCLIB tiruan: hanya mengenal pasangan persis (Sway, COLORCODE) pada
/// /api/get; /api/search menjawab per pasangan kueri yang dikonfigurasi.
/// Mencatat semua pasangan (track_name, artist_name) yang diminta agar
/// urutan percobaan bisa diasersi.
class _FakeLrclib extends Interceptor {
  final List<(String, String)> getCalls = [];
  final List<(String, String)> searchCalls = [];

  /// Bila true, /api/get selalu 404 — memaksa jalur pencarian.
  bool getAlways404 = false;

  /// Kandidat yang dikembalikan /api/search per pasangan kueri.
  final Map<String, List<Map<String, dynamic>>> searchResults = {};

  static Map<String, dynamic> swayRecord() => {
        'trackName': 'Sway',
        'artistName': 'COLORCODE',
        'duration': 248.0,
        'instrumental': false,
        'syncedLyrics': _lrcSway,
        'plainLyrics': 'It\'s been over a year since we\'ve been apart',
      };

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final q = options.queryParameters;
    final pair = ('${q['track_name']}', '${q['artist_name']}');
    if (options.path.endsWith('/api/get')) {
      getCalls.add(pair);
      if (!getAlways404 && pair == ('Sway', 'COLORCODE')) {
        handler.resolve(Response(
            requestOptions: options, statusCode: 200, data: swayRecord()));
      } else {
        handler.resolve(Response(
            requestOptions: options,
            statusCode: 404,
            data: <String, dynamic>{}));
      }
      return;
    }
    if (options.path.endsWith('/api/search')) {
      searchCalls.add(pair);
      final rows = searchResults['${pair.$1}|${pair.$2}'] ?? const [];
      handler.resolve(Response(
          requestOptions: options,
          statusCode: 200,
          data: [for (final r in rows) Map<String, dynamic>.from(r)]));
      return;
    }
    handler.next(options);
  }
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('splitArtistTitle (Ronde 8058)', () {
    test('kasus normal unggahan video', () {
      expect(splitArtistTitle('COLORCODE - Sway (Official Lyrics Video)'),
          ('COLORCODE', 'Sway (Official Lyrics Video)'));
    });

    test('tanpa pola → null', () {
      expect(splitArtistTitle('Sway'), isNull);
      expect(splitArtistTitle('Sway -COLORCODE'), isNull);
      expect(splitArtistTitle(''), isNull);
    });

    test('" - " ganda: pisah di yang PERTAMA', () {
      expect(splitArtistTitle('A - B - C'), ('A', 'B - C'));
    });

    test('sisi kosong → null', () {
      expect(splitArtistTitle(' - Sway'), isNull);
      expect(splitArtistTitle('COLORCODE - '), isNull);
      expect(splitArtistTitle('COLORCODE -'), isNull);
    });

    test('spasi berlebih dirapikan', () {
      expect(splitArtistTitle('COLORCODE  -  Sway'), ('COLORCODE', 'Sway'));
    });
  });

  group('pickSearchCandidate (Ronde 8058)', () {
    final sway = _FakeLrclib.swayRecord();

    test('kandidat cocok dengan varian judul PISAH, bukan judul mentah', () {
      // Inti pelonggaran: dulu kandidat 'Sway' ditolak karena judul
      // mentah trek adalah 'COLORCODE - Sway (Official Lyrics Video)'.
      final got = pickSearchCandidate(
        [sway],
        {'COLORCODE - Sway (Official Lyrics Video)', 'COLORCODE - Sway', 'Sway'},
        const Duration(seconds: 248),
      );
      expect(got, isNotNull);
      expect(got!.$2, _lrcSway);
    });

    test('kandidat berjudul asing tetap ditolak', () {
      final got = pickSearchCandidate(
        [
          {...sway, 'trackName': 'Lagu Lain Sama Sekali'}
        ],
        {'Sway'},
        const Duration(seconds: 248),
      );
      expect(got, isNull);
    });

    test('durasi terdekat menang; tersinkron diutamakan pada skor setara', () {
      final jauhPolos = {
        ...sway,
        'duration': 300.0,
        'syncedLyrics': null,
        'plainLyrics': 'polos jauh',
      };
      final dekatPolos = {
        ...sway,
        'duration': 249.0,
        'syncedLyrics': null,
        'plainLyrics': 'polos dekat',
      };
      final got = pickSearchCandidate(
          [jauhPolos, dekatPolos], {'Sway'}, const Duration(seconds: 248));
      expect(got!.$3, 'polos dekat');
      // Skor setara (durasi sama): yang tersinkron menang.
      final sinkron = {...sway, 'duration': 249.0};
      final got2 = pickSearchCandidate(
          [dekatPolos, sinkron], {'Sway'}, const Duration(seconds: 248));
      expect(got2!.$2, _lrcSway);
    });

    test('kandidat tanpa teks apa pun dilewati', () {
      final got = pickSearchCandidate(
        [
          {...sway, 'syncedLyrics': null, 'plainLyrics': null}
        ],
        {'Sway'},
        const Duration(seconds: 248),
      );
      expect(got, isNull);
    });
  });

  group('LyricsService — perilaku fetch (Dio tiruan)', () {
    late AppDb db;
    setUp(() async {
      db = AppDb();
      await db.openAt(':memory:');
    });
    tearDown(() async => db.close());

    test('kasus Sway: ditemukan lewat pisah "Artis - Judul"', () async {
      final fake = _FakeLrclib();
      final svc = LyricsService(db, dio: Dio()..interceptors.add(fake));
      final data = await svc.getLyrics(
          _track('COLORCODE - Sway (Official Lyrics Video)',
              'Eclipse Time Records'));
      expect(data, isNotNull);
      expect(data!.found, isTrue);
      expect(data.synced, isTrue);
      expect(data.lines!.first.text, '♪');
      // Dua percobaan lama tetap didahulukan persis seperti sebelumnya.
      expect(fake.getCalls.first,
          ('COLORCODE - Sway (Official Lyrics Video)', 'Eclipse Time Records'));
      expect(fake.getCalls[1], ('COLORCODE - Sway', 'Eclipse Time Records'));
      // Dan pasangan tertanam yang benar benar-benar dicoba.
      expect(fake.getCalls, contains(('Sway', 'COLORCODE')));
    });

    test('trek normal tanpa pola: urutan lama utuh, tanpa panggilan pisah',
        () async {
      final fake = _FakeLrclib();
      final svc = LyricsService(db, dio: Dio()..interceptors.add(fake));
      final data = await svc.getLyrics(_track('Sway', 'COLORCODE'));
      expect(data!.found, isTrue);
      // Percobaan pertama langsung kena — tidak ada panggilan lain.
      expect(fake.getCalls, [('Sway', 'COLORCODE')]);
      expect(fake.searchCalls, isEmpty);
    });

    test('jalur pencarian: kandidat varian pisah diterima saat get gagal',
        () async {
      final fake = _FakeLrclib()..getAlways404 = true;
      fake.searchResults['Sway|COLORCODE'] = [_FakeLrclib.swayRecord()];
      final svc = LyricsService(db, dio: Dio()..interceptors.add(fake));
      final data = await svc.getLyrics(
          _track('COLORCODE - Sway (Official Lyrics Video)',
              'Eclipse Time Records'));
      expect(data, isNotNull);
      expect(data!.found, isTrue);
      expect(fake.searchCalls, contains(('Sway', 'COLORCODE')));
    });

    test('sungguh tidak ada: null (dan tercache negatif seperti biasa)',
        () async {
      final fake = _FakeLrclib();
      final svc = LyricsService(db, dio: Dio()..interceptors.add(fake));
      final t = _track('Lagu Fiktif - Tiada', 'Kanal Antah');
      expect(await svc.getLyrics(t), isNull);
      final callsBefore = fake.getCalls.length;
      // Panggilan kedua berhenti di cache negatif — perilaku lama.
      expect(await svc.getLyrics(t), isNull);
      expect(fake.getCalls.length, callsBefore);
    });
  });
}
