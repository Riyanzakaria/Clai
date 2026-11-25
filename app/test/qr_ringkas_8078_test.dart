// Ronde 8078 — Mode QR Ringkas (payload QR hibrida, F-15/F-16).
//
// Kontrak yang diuji:
// (1) Kompatibilitas mundur BYTE: payload v1 hasil encoder build
//     ≤8077 (emas yang ditangkap sebelum codec diubah) terurai persis
//     sama, dan encoder mode penuh hari ini menghasilkan byte yang
//     sama untuk data yang sama.
// (2) Codec ringkas v2: nama + [provider, id] per trek round-trip
//     menjadi ParsedSharedRefs dengan urutan persis; v3 ditolak
//     sebagai format lebih baru (F-12).
// (3) Perencana mode: penuh bila muat → ringkas bila penuh tak muat
//     tetapi ringkas muat → berkas saja bila keduanya tak muat. Trek
//     lokal terkecuali dari ringkas dan terhitung; playlist semua-
//     lokal yang besar tidak menghasilkan QR kosong.
// (4) Pelarutan: urutan dipertahankan, yang gagal dihitung (termasuk
//     lookup yang melempar), progres dilaporkan, duplikat dipertahankan.
// (5) Impor hasil pelarutan lewat jalur atomik yang sama: playlist
//     tercipta dengan isi/urutan persis; impor kedua → " (2)".
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:clai/data/app_db.dart';
import 'package:clai/domain/models.dart';
import 'package:clai/domain/transfer_data.dart';
import 'package:clai/services/library_transfer.dart';

/// Payload v1 yang dihasilkan encoder build 8077 untuk playlist
/// "Emas Uji" (2 trek, satu ref == id, satu ref berbeda) — ditangkap
/// di bukti-ronde-8078/payload-emas-v1.txt SEBELUM codec 8078 ditulis.
const kGoldenV1 =
    'eJxNzsEKgkAUBdBfedz1C7Ta6M4ohIhAIcpEYtRnTOkY6igS_XubFv3A4bwxwncZBj52jerp9NBgDPDTFPPQ2F4XYJTRtJ688_1SRGAcZZSOwtYYRaEehZLW0ukFRqyLJwX9UMsMXrorx3EYyPjfUnnhLleX5HpbgLG3pa1pK-auDMVS0Ua6XEoFRtAN-hcytq4ZnVQHpY3neciyzxe9JTmJ';

SharedPlaylistData get _goldenData => SharedPlaylistData(
      formatVersion: kTransferFormatVersion,
      name: 'Emas Uji',
      tracks: const [
        TransferTrack(
          providerId: 'ytmusic',
          trackId: 'dQw4w9WgXcQ',
          title: 'Never Gonna Give You Up',
          artistNames: 'Rick Astley',
          durationMs: 213000,
          playableRef: 'dQw4w9WgXcQ',
        ),
        TransferTrack(
          providerId: 'ytmusic',
          trackId: 'abc123XYZ_-',
          title: 'Judul Dengan Ref Berbeda',
          artistNames: 'Artis Uji',
          durationMs: null,
          playableRef: 'refLain999',
        ),
      ],
    );

/// Trek bergaya nyata: id 11 karakter berentropi + judul/artis dari
/// kombinasi kata — TIDAK repetitif, agar angka kompresi zlib jujur
/// (data sintetis repetitif terkompresi jauh lebih kecil dari nyata).
TransferTrack _realish(int i, {String provider = 'ytmusic'}) {
  final rnd = Random(7919 + i * 131);
  const alpha =
      'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_';
  final id = provider == 'local'
      ? '/storage/emulated/0/Music/lagu-$i.mp3'
      : String.fromCharCodes([
          for (var k = 0; k < 11; k++)
            alpha.codeUnitAt(rnd.nextInt(alpha.length)),
        ]);
  const words = [
    'Senja', 'Kota', 'Angin', 'Laut', 'Bintang', 'Rindu', 'Jalan',
    'Pulang', 'Cahaya', 'Embun', 'Gelombang', 'Senandung', 'Langit',
    'Hujan', 'Daun', 'Api', 'Malam', 'Pagi', 'Bukit', 'Sungai',
  ];
  String pick() => words[rnd.nextInt(words.length)];
  return TransferTrack(
    providerId: provider,
    trackId: id,
    title: '${pick()} ${pick()} ${pick()}',
    artistNames: '${pick()} ${pick()}',
    durationMs: 150000 + rnd.nextInt(180000),
    playableRef: id,
  );
}

SharedPlaylistData _bigPlaylist(int n,
        {int locals = 0, String name = 'play'}) =>
    SharedPlaylistData(
      formatVersion: kTransferFormatVersion,
      name: name,
      tracks: [
        for (var i = 0; i < n; i++) _realish(i),
        for (var i = 0; i < locals; i++) _realish(10000 + i, provider: 'local'),
      ],
    );

Track _catalogTrack(TrackKey k) => Track(
      key: k,
      title: 'Terlarut ${k.id}',
      artistNames: 'Katalog',
      duration: const Duration(minutes: 3),
      playableRef: k.id,
    );

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('kompatibilitas mundur v1 (emas 8077)', () {
    test('payload emas terurai persis seperti sebelum 8078', () {
      final r = decodeQrPayload(kGoldenV1);
      expect(r, isA<ParsedSharedPlaylist>());
      final d = (r as ParsedSharedPlaylist).data;
      expect(d.name, 'Emas Uji');
      expect(d.tracks, hasLength(2));
      expect(d.tracks[0].trackId, 'dQw4w9WgXcQ');
      expect(d.tracks[0].title, 'Never Gonna Give You Up');
      expect(d.tracks[0].playableRef, 'dQw4w9WgXcQ');
      expect(d.tracks[1].trackId, 'abc123XYZ_-');
      expect(d.tracks[1].playableRef, 'refLain999');
      expect(d.tracks[1].durationMs, isNull);
    });

    test('encoder mode penuh hari ini byte-identik dengan emas', () {
      expect(encodeQrPayload(_goldenData), kGoldenV1);
    });
  });

  group('codec ringkas v2', () {
    test('round-trip: nama + refs persis, urutan dipertahankan', () {
      final refs = [
        const TrackKey('ytmusic', 'aaaaaaaaaa1'),
        const TrackKey('ytmusic', 'bbbbbbbbbb2'),
        const TrackKey('ytmusic', 'aaaaaaaaaa1'),
      ];
      final payload = encodeQrRefsPayload('Campuran', refs);
      final r = decodeQrPayload(payload);
      expect(r, isA<ParsedSharedRefs>());
      final parsed = r as ParsedSharedRefs;
      expect(parsed.name, 'Campuran');
      expect(parsed.refs, refs);
    });

    test('payload v3 ditolak sebagai format lebih baru', () {
      final raw = jsonEncode({
        'v': 3,
        'n': 'Masa Depan',
        't': [
          ['ytmusic', 'aaaaaaaaaa1']
        ],
      });
      final payload = base64Url
          .encode(ZLibCodec().encode(utf8.encode(raw)))
          .replaceAll('=', '');
      final r = decodeQrPayload(payload);
      expect(r, isA<TransferParseFailure>());
      final f = r as TransferParseFailure;
      expect(f.kind, TransferFailureKind.newerVersion);
      expect(f.foundVersion, 3);
    });

    test('payload ringkas rusak → korup, bukan crash', () {
      final raw = jsonEncode({
        'v': 2,
        'n': 'Rusak',
        't': [
          ['ytmusic']
        ],
      });
      final payload = base64Url
          .encode(ZLibCodec().encode(utf8.encode(raw)))
          .replaceAll('=', '');
      final r = decodeQrPayload(payload);
      expect(r, isA<TransferParseFailure>());
      expect((r as TransferParseFailure).kind, TransferFailureKind.corrupt);
    });
  });

  group('perencana mode planQrShare', () {
    test('playlist kecil → mode penuh, payload sama seperti 8077', () {
      final plan = planQrShare(_goldenData);
      expect(plan, isA<QrShareFull>());
      expect((plan as QrShareFull).payload, kGoldenV1);
    });

    test('49 trek: penuh TIDAK muat, ringkas muat (kasus "play" riyan)',
        () {
      final data = _bigPlaylist(49);
      final full = encodeQrPayload(data);
      expect(full.length, greaterThan(kQrMaxPayloadChars),
          reason: 'penuh=${full.length} karakter');
      final plan = planQrShare(data);
      expect(plan, isA<QrShareRefs>());
      final refs = plan as QrShareRefs;
      expect(refs.trackCount, 49);
      expect(refs.localExcluded, 0);
      expect(refs.payload.length, lessThanOrEqualTo(kQrMaxPayloadChars),
          reason: 'ringkas=${refs.payload.length} karakter');
      // ignore: avoid_print
      print('UKURAN 49 trek: penuh=${full.length} ringkas=${refs.payload.length}');
      final back = decodeQrPayload(refs.payload);
      expect(back, isA<ParsedSharedRefs>());
      expect((back as ParsedSharedRefs).refs,
          [for (final t in data.tracks) t.key]);
    });

    test('besar + lokal: lokal terkecuali dari ringkas & terhitung', () {
      final data = _bigPlaylist(49, locals: 3);
      final plan = planQrShare(data);
      expect(plan, isA<QrShareRefs>());
      final refs = plan as QrShareRefs;
      expect(refs.trackCount, 49);
      expect(refs.localExcluded, 3);
      final back = decodeQrPayload(refs.payload) as ParsedSharedRefs;
      expect(back.refs.every((k) => k.providerId != 'local'), isTrue);
    });

    test('semua lokal & besar → terlalu besar (tidak ada QR kosong)', () {
      final data = _bigPlaylist(0, locals: 60);
      final plan = planQrShare(data);
      expect(plan, isA<QrShareTooBig>());
      expect((plan as QrShareTooBig).localExcluded, 60);
    });

    test('200 trek: ringkas pun tidak muat → berkas saja', () {
      final plan = planQrShare(_bigPlaylist(200));
      expect(plan, isA<QrShareTooBig>());
    });

    test('kecil dengan trek lokal → tetap mode penuh (perilaku lama)',
        () {
      final data = SharedPlaylistData(
        formatVersion: kTransferFormatVersion,
        name: 'Kecil Campuran',
        tracks: [_realish(1), _realish(2, provider: 'local')],
      );
      final plan = planQrShare(data);
      expect(plan, isA<QrShareFull>());
      final back = decodeQrPayload((plan as QrShareFull).payload);
      expect(back, isA<ParsedSharedPlaylist>());
      expect((back as ParsedSharedPlaylist).data.tracks, hasLength(2));
    });
  });

  group('pelarutan resolveSharedRefs', () {
    final a = const TrackKey('ytmusic', 'aaaaaaaaaa1');
    final b = const TrackKey('ytmusic', 'bbbbbbbbbb2');
    final bogus = const TrackKey('ytmusic', 'zzzzzzzzzz9');

    Future<Track?> lookup(TrackKey k) async =>
        (k == a || k == b) ? _catalogTrack(k) : null;

    test('campuran asli + bogus: urutan utuh, gagal terhitung persis',
        () async {
      final res = await resolveSharedRefs(
        name: 'Campur',
        refs: [a, bogus, b, bogus],
        lookup: lookup,
      );
      expect(res.resolvedCount, 2);
      expect(res.unresolvedCount, 2);
      expect(res.data.tracks.map((t) => t.trackId),
          ['aaaaaaaaaa1', 'bbbbbbbbbb2']);
      expect(res.data.name, 'Campur');
    });

    test('semua bogus → nol terlarut (keadaan gagal jujur pemanggil)',
        () async {
      final res = await resolveSharedRefs(
        name: 'Hantu',
        refs: [bogus, bogus],
        lookup: lookup,
      );
      expect(res.resolvedCount, 0);
      expect(res.unresolvedCount, 2);
      expect(res.data.tracks, isEmpty);
    });

    test('lookup melempar → dihitung gagal, resolver tidak melempar',
        () async {
      final res = await resolveSharedRefs(
        name: 'Jaringan Mati',
        refs: [a, b],
        lookup: (k) async => throw StateError('offline'),
      );
      expect(res.resolvedCount, 0);
      expect(res.unresolvedCount, 2);
    });

    test('progres dilaporkan sampai (total, total); duplikat utuh',
        () async {
      final seen = <int>[];
      final res = await resolveSharedRefs(
        name: 'Ganda',
        refs: [a, a, b],
        lookup: lookup,
        onProgress: (done, total) => seen.add(done),
      );
      expect(res.resolvedCount, 3);
      expect(seen.last, 3);
      expect(seen, [1, 2, 3]);
    });
  });

  group('impor hasil pelarutan (jalur atomik yang sama)', () {
    late Directory dir;
    var seq = 0;

    Future<AppDb> freshDb() async {
      final db = AppDb();
      await db.openAt('${dir.path}/r${seq++}.db');
      return db;
    }

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('clai_8078');
    });

    tearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    test('playlist terlarut tercipta persis; impor ulang → " (2)"',
        () async {
      final db = await freshDb();
      final a = const TrackKey('ytmusic', 'aaaaaaaaaa1');
      final b = const TrackKey('ytmusic', 'bbbbbbbbbb2');
      final res = await resolveSharedRefs(
        name: 'play',
        refs: [b, a],
        lookup: (k) async => _catalogTrack(k),
      );
      final name1 = await db.importSharedPlaylist(res.data);
      expect(name1, 'play');
      final rows = await db.playlists();
      final row = rows.singleWhere((r) => r['name'] == 'play');
      final tracks = await db.playlistTracks(row['id'] as String);
      expect(tracks.map((t) => t.id), ['bbbbbbbbbb2', 'aaaaaaaaaa1']);
      expect(tracks.first.title, 'Terlarut bbbbbbbbbb2');

      final name2 = await db.importSharedPlaylist(res.data);
      expect(name2, 'play (2)');
      await db.close();
    });
  });
}
