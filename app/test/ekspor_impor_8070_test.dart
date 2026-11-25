// Ronde 8070 — D2 Ekspor/Impor + Bagikan (F-12 USER-FLOW-DAN-LOGIKA).
//
// Kontrak yang diuji:
// (1) Ekspor = SATU JSON berversi: playlist, suka, riwayat OPSIONAL,
//     item tersimpan. Round-trip susun→urai mempertahankan isi.
// (2) Impor: validasi PENUH sebelum terapkan; berkas korup/asing/versi
//     lebih baru ditolak dengan jenis kegagalan yang tepat (F-12:
//     versi lebih baru = penjelasan versi, tanpa impor paksa).
// (3) Gabungkan: dedupe per kunci trek di playlist, suka gabungan,
//     riwayat dedupe tupel — menerapkan dua kali tidak menggandakan.
// (4) Ganti semua: data lama hilang, isi berkas masuk; berkas TANPA
//     riwayat tidak menyentuh riwayat yang ada.
// (5) Bagikan: payload QR ringkas (zlib+base64url) round-trip; ambang
//     ukuran memutuskan QR vs berkas; playlist diterima menjadi
//     playlist BARU (tabrakan nama → akhiran " (2)").
// (6) M3U: kepala + EXTINF + ref per trek.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:clai/app.dart';
import 'package:clai/data/app_db.dart';
import 'package:clai/domain/models.dart';
import 'package:clai/domain/transfer_data.dart';
import 'package:clai/l10n/app_localizations.dart';
import 'package:clai/services/library_transfer.dart';
import 'package:clai/ui/import_flow.dart';
import 'package:clai/ui/ownership_sheets.dart';
import 'package:clai/ui/settings_screen.dart';
import 'package:clai/ui/share_playlist_sheet.dart';

Track _t(String id, {String title = 'Lagu', String artist = 'Artis'}) => Track(
  key: TrackKey('ytmusic', id),
  title: '$title $id',
  artistNames: artist,
  duration: const Duration(seconds: 200),
  playableRef: id,
);

TransferTrack _tt(String id) => TransferTrack.fromTrack(_t(id));

LibraryTransferData _sampleData({bool withHistory = true}) =>
    LibraryTransferData(
      formatVersion: kTransferFormatVersion,
      appVersion: '2.1.0',
      exportedAt: 1700000000000,
      playlists: [
        TransferPlaylist(name: 'Senja', tracks: [_tt('a'), _tt('b')]),
        TransferPlaylist(name: 'Pagi', tracks: [_tt('c')]),
      ],
      liked: [TransferLike(track: _tt('a'), likedAt: 111)],
      history: withHistory
          ? [
              TransferEvent(
                track: _tt('a'),
                startedAt: 1000,
                listenedMs: 5000,
                completed: false,
              ),
              TransferEvent(
                track: _tt('b'),
                startedAt: 2000,
                listenedMs: 200000,
                completed: true,
              ),
            ]
          : null,
      savedItems: const [
        TransferSavedItem(
          kind: 'album',
          providerId: 'ytmusic',
          itemId: 'alb1',
          title: 'Album Satu',
          savedAt: 42,
        ),
      ],
    );

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('codec JSON ekspor (F-12 butir 1)', () {
    test('round-trip susun → urai mempertahankan isi penuh', () {
      final text = jsonEncode(exportToJson(_sampleData()));
      final r = parseTransferText(text);
      expect(r, isA<ParsedLibrary>());
      final d = (r as ParsedLibrary).data;
      expect(d.formatVersion, kTransferFormatVersion);
      expect(d.appVersion, '2.1.0');
      expect(d.playlists.map((p) => p.name), ['Senja', 'Pagi']);
      expect(d.playlists.first.tracks.map((t) => t.trackId), ['a', 'b']);
      expect(d.playlists.first.tracks.first.durationMs, 200000);
      expect(d.liked.single.track.trackId, 'a');
      expect(d.liked.single.likedAt, 111);
      expect(d.history, hasLength(2));
      expect(d.history!.last.completed, isTrue);
      expect(d.savedItems.single.itemId, 'alb1');
    });

    test('riwayat opsional: tanpa kunci history → history null', () {
      final text = jsonEncode(exportToJson(_sampleData(withHistory: false)));
      final d = (parseTransferText(text) as ParsedLibrary).data;
      expect(d.history, isNull);
    });

    test('bukan JSON → notJson; JSON asing → unrecognized', () {
      expect(
        (parseTransferText('halo dunia') as TransferParseFailure).kind,
        TransferFailureKind.notJson,
      );
      expect(
        (parseTransferText('') as TransferParseFailure).kind,
        TransferFailureKind.notJson,
      );
      expect(
        (parseTransferText('{"format":"punya-aplikasi-lain"}')
                as TransferParseFailure)
            .kind,
        TransferFailureKind.unrecognized,
      );
      expect(
        (parseTransferText('[1,2,3]') as TransferParseFailure).kind,
        TransferFailureKind.unrecognized,
      );
    });

    test('versi format lebih baru → newerVersion + nomor versinya', () {
      final text = jsonEncode({
        'format': kExportFormat,
        'formatVersion': 99,
        'playlists': [],
        'liked': [],
      });
      final f = parseTransferText(text) as TransferParseFailure;
      expect(f.kind, TransferFailureKind.newerVersion);
      expect(f.foundVersion, 99);
    });

    test('struktur rusak → corrupt (judul trek hilang, likedAt hilang)', () {
      final noTitle = jsonEncode({
        'format': kExportFormat,
        'formatVersion': 1,
        'playlists': [
          {
            'name': 'X',
            'tracks': [
              {
                'providerId': 'ytmusic',
                'trackId': 'a',
                'artistNames': 'A',
                'playableRef': 'a',
              },
            ],
          },
        ],
        'liked': [],
      });
      expect(
        (parseTransferText(noTitle) as TransferParseFailure).kind,
        TransferFailureKind.corrupt,
      );

      final noLikedAt = jsonEncode({
        'format': kExportFormat,
        'formatVersion': 1,
        'playlists': [],
        'liked': [
          {'track': _tt('a').toJson()},
        ],
      });
      expect(
        (parseTransferText(noLikedAt) as TransferParseFailure).kind,
        TransferFailureKind.corrupt,
      );
    });

    test('byte: gerbang ukuran → tooLarge; byte sah terurai', () {
      final big = Uint8List(kMaxImportBytes + 1);
      expect(
        (parseTransferBytes(big) as TransferParseFailure).kind,
        TransferFailureKind.tooLarge,
      );
      final ok = utf8.encode(jsonEncode(exportToJson(_sampleData())));
      expect(parseTransferBytes(ok), isA<ParsedLibrary>());
    });
  });

  group('codec QR bagikan', () {
    test('round-trip payload kecil: nama, trek, ref==id dibangun ulang', () {
      final shared = SharedPlaylistData(
        formatVersion: kTransferFormatVersion,
        name: 'Senja di Kota',
        tracks: [_tt('a'), _tt('b')],
      );
      final payload = encodeQrPayload(shared);
      expect(
        qrPayloadFits(payload),
        isTrue,
        reason: 'payload 2 trek harus jauh di bawah ambang',
      );
      final r = decodeQrPayload(payload);
      expect(r, isA<ParsedSharedPlaylist>());
      final d = (r as ParsedSharedPlaylist).data;
      expect(d.name, 'Senja di Kota');
      expect(d.tracks.map((t) => t.trackId), ['a', 'b']);
      expect(d.tracks.first.playableRef, 'a');
      expect(d.tracks.first.durationMs, 200000);
    });

    test('ref berbeda dari id dipertahankan', () {
      final shared = SharedPlaylistData(
        formatVersion: kTransferFormatVersion,
        name: 'Lokal',
        tracks: const [
          TransferTrack(
            providerId: 'local',
            trackId: 'f1',
            title: 'Berkas Lokal',
            artistNames: 'Artis',
            playableRef: '/musik/f1.mp3',
          ),
        ],
      );
      final d =
          (decodeQrPayload(encodeQrPayload(shared)) as ParsedSharedPlaylist)
              .data;
      expect(d.tracks.single.playableRef, '/musik/f1.mp3');
    });

    test('playlist besar: payload melewati ambang → hanya berkas', () {
      // Judul/artis dibuat berentropi realistis (pola berulang akan
      // terkompresi zlib jauh di bawah ukuran dunia nyata).
      var seed = 12345;
      String word(int len) {
        const chars = 'abcdefghijklmnopqrstuvwxyz';
        var s = '';
        for (var i = 0; i < len; i++) {
          seed = (seed * 1103515245 + 12345) & 0x7fffffff;
          s += chars[seed % 26];
        }
        return s;
      }

      final shared = SharedPlaylistData(
        formatVersion: kTransferFormatVersion,
        name: 'Raksasa',
        tracks: [
          for (var i = 0; i < 40; i++)
            TransferTrack(
              providerId: 'ytmusic',
              trackId: word(11),
              title: '${word(9)} ${word(7)} ${word(12)}',
              artistNames: '${word(8)} ${word(6)}',
              durationMs: 200000,
              playableRef: word(11),
            ),
        ],
      );
      final payload = encodeQrPayload(shared);
      expect(payload.length, greaterThan(kQrMaxPayloadChars));
      expect(qrPayloadFits(payload), isFalse);
      // Codec-nya sendiri tetap utuh walau tidak ditawarkan sebagai QR.
      expect(decodeQrPayload(payload), isA<ParsedSharedPlaylist>());
    });

    test('kode asing → unrecognized; payload versi baru → newerVersion', () {
      expect(
        (decodeQrPayload('https://contoh.invalid/apa') as TransferParseFailure)
            .kind,
        TransferFailureKind.unrecognized,
      );
      final future = encodeQrPayload(
        const SharedPlaylistData(
          formatVersion: 99,
          name: 'Masa Depan',
          tracks: [],
        ),
      );
      final f = decodeQrPayload(future) as TransferParseFailure;
      expect(f.kind, TransferFailureKind.newerVersion);
      expect(f.foundVersion, 99);
    });
  });

  group('M3U', () {
    test('kepala, EXTINF berdurasi, ref; durasi tak diketahui → -1', () {
      final m3u = buildM3u([
        _tt('a'),
        const TransferTrack(
          providerId: 'ytmusic',
          trackId: 'z',
          title: 'Tanpa Durasi',
          artistNames: 'Artis',
          playableRef: 'z',
        ),
      ]);
      final lines = m3u.trim().split('\n');
      expect(lines[0], '#EXTM3U');
      expect(lines[1], '#EXTINF:200,Artis - Lagu a');
      expect(lines[2], 'a');
      expect(lines[3], '#EXTINF:-1,Artis - Tanpa Durasi');
      expect(lines[4], 'z');
    });
  });

  group('basis data: ekspor, gabung, ganti, bagikan', () {
    late Directory dir;
    var seq = 0;

    Future<AppDb> freshDb() async {
      final db = AppDb();
      await db.openAt('${dir.path}/t${seq++}.db');
      return db;
    }

    Future<void> seed(AppDb db) async {
      await db.createPlaylist('p1', 'Senja');
      await db.addToPlaylist('p1', _t('a'));
      await db.addToPlaylist('p1', _t('b'));
      await db.createPlaylist('p2', 'Pagi');
      await db.addToPlaylist('p2', _t('c'));
      await db.setLiked(_t('a'), true);
      await db.logPlayback(_t('a'), listenedMs: 5000, completed: false);
      await db.logPlayback(_t('b'), listenedMs: 200000, completed: true);
    }

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('clai_8070');
    });

    tearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    test('ekspor dari DB nyata membawa playlist, suka, riwayat', () async {
      final db = await freshDb();
      await seed(db);
      final pls = await db.exportPlaylistsData();
      expect(pls.map((p) => p.name), ['Senja', 'Pagi']);
      expect(pls.first.tracks.map((t) => t.trackId), ['a', 'b']);
      final liked = await db.exportLikedData();
      expect(liked.single.track.trackId, 'a');
      final hist = await db.exportHistoryData();
      expect(hist, hasLength(2));
      expect(hist.last.completed, isTrue);
      final counts = await db.libraryCounts();
      expect(counts.playlists, 2);
      expect(counts.liked, 1);
      expect(counts.history, 2);
      await db.close();
    });

    test(
      'round-trip penuh: seed → ekspor → urai → terapkan ke DB kosong',
      () async {
        final a = await freshDb();
        await seed(a);
        final data = LibraryTransferData(
          formatVersion: kTransferFormatVersion,
          playlists: await a.exportPlaylistsData(),
          liked: await a.exportLikedData(),
          history: await a.exportHistoryData(),
          savedItems: await a.exportSavedItemsData(),
        );
        final parsed = parseTransferText(jsonEncode(exportToJson(data)));
        expect(parsed, isA<ParsedLibrary>());

        final b = await freshDb();
        await b.applyLibraryImport(
          (parsed as ParsedLibrary).data,
          replace: false,
        );
        final pls = await b.playlists();
        expect(pls.map((r) => r['name']), containsAll(['Senja', 'Pagi']));
        final senja =
            pls.firstWhere((r) => r['name'] == 'Senja')['id'] as String;
        expect((await b.playlistTracks(senja)).map((t) => t.id), ['a', 'b']);
        expect((await b.likedTracks()).map((t) => t.id), ['a']);
        expect((await b.exportHistoryData()), hasLength(2));
        await a.close();
        await b.close();
      },
    );

    test('gabung dua kali: tidak ada penggandaan apa pun', () async {
      final db = await freshDb();
      final data = _sampleData();
      await db.applyLibraryImport(data, replace: false);
      await db.applyLibraryImport(data, replace: false);
      final counts = await db.libraryCounts();
      expect(counts.playlists, 2);
      expect(counts.liked, 1);
      expect(counts.history, 2);
      final pls = await db.playlists();
      final senja = pls.firstWhere((r) => r['name'] == 'Senja')['id'] as String;
      expect(await db.playlistCount(senja), 2);
      await db.close();
    });

    test(
      'gabung ke playlist se-nama: entri menjadi gabungan berurutan',
      () async {
        final db = await freshDb();
        await db.createPlaylist('px', 'Senja');
        await db.addToPlaylist('px', _t('x'));
        await db.addToPlaylist('px', _t('a'));
        await db.applyLibraryImport(_sampleData(), replace: false);
        final tracks = await db.playlistTracks('px');
        // 'a' sudah ada (tidak digandakan), 'b' menyusul di ekor.
        expect(tracks.map((t) => t.id), ['x', 'a', 'b']);
        await db.close();
      },
    );

    test('proyeksi gabung menghitung tambah/gabung dengan benar', () async {
      final db = await freshDb();
      await db.createPlaylist('px', 'Senja');
      await db.addToPlaylist('px', _t('a'));
      await db.setLiked(_t('a'), true);
      final p = await db.projectLibraryImport(_sampleData());
      expect(p.mergedPlaylists, 1); // Senja
      expect(p.newPlaylists, 1); // Pagi
      expect(p.playlistTracksAdded, 2); // b (Senja) + c (Pagi)
      expect(p.likedAdded, 0); // a sudah disukai
      expect(p.historyAdded, 2);
      await db.close();
    });

    test('ganti semua: data lama hilang, isi berkas masuk', () async {
      final db = await freshDb();
      await db.createPlaylist('lama', 'Playlist Lama');
      await db.addToPlaylist('lama', _t('z'));
      await db.setLiked(_t('z'), true);
      await db.logPlayback(_t('z'), listenedMs: 1000, completed: false);
      await db.applyLibraryImport(_sampleData(), replace: true);
      final counts = await db.libraryCounts();
      expect(counts.playlists, 2);
      expect(counts.liked, 1);
      expect(counts.history, 2);
      expect(
        (await db.playlists()).map((r) => r['name']),
        isNot(contains('Playlist Lama')),
      );
      expect(await db.isLiked(const TrackKey('ytmusic', 'z')), isFalse);
      await db.close();
    });

    test('ganti dengan berkas TANPA riwayat: riwayat lama bertahan', () async {
      final db = await freshDb();
      await db.logPlayback(_t('z'), listenedMs: 1000, completed: false);
      await db.applyLibraryImport(
        _sampleData(withHistory: false),
        replace: true,
      );
      final counts = await db.libraryCounts();
      expect(counts.history, 1);
      expect(counts.playlists, 2);
      await db.close();
    });

    test(
      'berkas korup di playlist kedua: urai gagal → DB tak berubah',
      () async {
        final db = await freshDb();
        await db.createPlaylist('aman', 'Aman');
        final text = jsonEncode({
          'format': kExportFormat,
          'formatVersion': 1,
          'playlists': [
            {
              'name': 'Baik',
              'tracks': [_tt('a').toJson()],
            },
            {
              'name': 'Rusak',
              'tracks': [
                {'providerId': 'ytmusic'},
              ],
            },
          ],
          'liked': [],
        });
        expect(parseTransferText(text), isA<TransferParseFailure>());
        final counts = await db.libraryCounts();
        expect(counts.playlists, 1);
        expect((await db.playlists()).single['name'], 'Aman');
        await db.close();
      },
    );

    test('bagikan diterima: playlist baru; impor lagi → akhiran (2)', () async {
      final db = await freshDb();
      final shared = SharedPlaylistData(
        formatVersion: kTransferFormatVersion,
        name: 'Senja di Kota',
        tracks: [_tt('a'), _tt('b'), _tt('a')],
      );
      final first = await db.importSharedPlaylist(shared);
      expect(first, 'Senja di Kota');
      final second = await db.importSharedPlaylist(shared);
      expect(second, 'Senja di Kota (2)');
      final pls = await db.playlists();
      expect(pls, hasLength(2));
      // Duplikat di dalam berkas bagikan didedupe: 3 entri → 2 trek.
      expect(await db.playlistCount(pls.first['id'] as String), 2);
      await db.close();
    });
  });

  group('widget: hub, lembar ekspor, pratinjau, gagal, bagikan', () {
    late Directory dir;
    late AppDb db;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('clai_8070w');
      db = AppDb();
      await db.openAt('${dir.path}/w.db');
    });

    tearDown(() async {
      await db.close();
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    Widget tree(Widget home) => ProviderScope(
      overrides: [appDbProvider.overrideWithValue(db)],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('id'),
        home: home,
      ),
    );

    // Seluruh badan tes widget berjalan di waktu NYATA (runAsync):
    // future DB sqflite-ffi yang lahir di zona jam palsu testWidgets
    // tidak pernah selesai (rantai lanjutannya terikat zona itu), jadi
    // semai, pompa, dan ketuk semua tinggal di zona nyata; penantian
    // memakai putaran jajak (pompa + jeda nyata) sampai penanda tampil.
    Future<void> untilFound(WidgetTester tester, Finder finder) async {
      for (var i = 0; i < 150; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        if (finder.evaluate().isNotEmpty) return;
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      await tester.pump();
    }

    Future<void> untilGone(WidgetTester tester, Finder finder) async {
      for (var i = 0; i < 150; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        if (finder.evaluate().isEmpty) return;
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      await tester.pump();
    }

    // Notis debug WARISAN hub (pola yang sama seperti gulir_8052):
    // baris grup hub adalah ListTile telanjang di dalam kartu
    // DecoratedBox → aseran "ink splashes may be invisible" menyala di
    // mode debug (terstrip di rilis). Serap HANYA notis itu (satuan
    // atau agregat ≤13 = jumlah baris grup hub); eksepsi lain gagal.
    void absorbHubNotices(WidgetTester tester) {
      var e = tester.takeException();
      while (e != null) {
        final s = e.toString();
        final agg = RegExp(r'Multiple exceptions \((\d+)\)').firstMatch(s);
        final ok =
            s.contains('ListTile background color or ink splashes') ||
            (agg != null && int.parse(agg.group(1)!) <= 13);
        expect(ok, isTrue, reason: 'eksepsi tak terduga di hub: $e');
        e = tester.takeException();
      }
    }

    testWidgets('halaman Kepemilikan (pintu laci sejak 8079) memuat '
        'empat pintu D2', (tester) async {
      // Hub memakai DB pref-nol (pola _NullDb gulir_8052): kartu
      // Tampilan hub memuat pref lewat AmbientController secara async —
      // dengan DB berkas asli, muatan yang tertinggal melewati
      // tearDown (DB ditutup) membuka ulang lewat path_provider dan
      // meledak sesudah tes selesai. Yang diuji di sini pintu
      // Kepemilikan, bukan kartu itu.
      // Ronde 8079 (pemeliharaan tes): pintu Kepemilikan KELUAR dari
      // hub Pengaturan — rumahnya kini pintu Laci Menu; yang diuji di
      // sini halaman tujuannya langsung (OwnershipPage), isi empat
      // pintu D2 tidak berubah.
      tester.view.physicalSize = const Size(390, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.runAsync(() async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [appDbProvider.overrideWithValue(_NullPrefDb())],
            child: MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              locale: const Locale('id'),
              home: const OwnershipPage(),
            ),
          ),
        );
        await untilFound(tester, find.text('Ekspor data'));
        absorbHubNotices(tester);
        expect(find.text('Ekspor data'), findsOneWidget);
        expect(find.text('Impor data'), findsOneWidget);
        expect(find.text('Bagikan playlist'), findsOneWidget);
        expect(find.text('Terima playlist'), findsOneWidget);
      });
    });

    testWidgets('lembar Ekspor: hitungan nyata + saklar riwayat + M3U', (
      tester,
    ) async {
      await tester.runAsync(() async {
        await db.createPlaylist('p1', 'Senja');
        await db.addToPlaylist('p1', _t('a'));
        await db.setLiked(_t('a'), true);
        await tester.pumpWidget(
          tree(
            Scaffold(
              body: Consumer(
                builder: (ctx, ref, _) => TextButton(
                  onPressed: () => openExportSheet(ctx, ref),
                  child: const Text('buka'),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.tap(find.text('buka'));
        // Penanda selesai memuat = baris hitungan (lahir dari future DB);
        // saklar riwayat tampil sejak awal dan bukan penanda yang sah.
        await untilFound(tester, find.textContaining('1 lagu disukai'));
        expect(find.text('Ekspor data'), findsOneWidget);
        expect(find.textContaining('1 playlist'), findsOneWidget);
        expect(find.text('Sertakan riwayat putar'), findsOneWidget);
        expect(find.text('Playlist sebagai M3U'), findsOneWidget);
        expect(find.text('Senja'), findsOneWidget);
      });
    });

    testWidgets('pratinjau impor: ringkasan gabung tampil; Ganti semua '
        'meminta konfirmasi kedua dan Batal tidak menerapkan apa pun', (
      tester,
    ) async {
      await tester.runAsync(() async {
        await db.createPlaylist('px', 'Senja');
        await db.addToPlaylist('px', _t('a'));
        await tester.pumpWidget(
          tree(
            Scaffold(
              body: Consumer(
                builder: (ctx, ref, _) => TextButton(
                  onPressed: () => showImportPreviewSheet(
                    ctx,
                    ref,
                    _sampleData(),
                    fileName: 'clai-ekspor-20251121.json',
                  ),
                  child: const Text('buka'),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.tap(find.text('buka'));
        // Baris ringkasan proyeksi berawalan poin "• " — cari sebagai
        // potongan teks, bukan teks persis.
        await untilFound(
          tester,
          find.textContaining('1 playlist digabungkan ke yang sudah ada'),
        );
        expect(find.text('Berkas: clai-ekspor-20251121.json'), findsOneWidget);
        expect(
          find.textContaining('1 playlist baru ditambahkan'),
          findsOneWidget,
        );
        expect(find.text('Gabungkan'), findsOneWidget);
        expect(find.text('Ganti semua'), findsOneWidget);
        // Pilih mode ganti → tombol utama berubah → ketuk → dialog.
        await tester.tap(find.text('Ganti semua'));
        await untilFound(tester, find.text('Ganti semua…'));
        await tester.tap(find.text('Ganti semua…'));
        await untilFound(tester, find.text('Ganti semua data?'));
        expect(find.text('Ganti semua data?'), findsOneWidget);
        await tester.tap(find.text('Batal'));
        await untilGone(tester, find.text('Ganti semua data?'));
        expect(find.text('Ganti semua data?'), findsNothing);
        // Batal = nol perubahan: playlist asal tetap satu-satunya.
        final counts = await db.libraryCounts();
        expect(counts.playlists, 1);
        expect(await db.playlistCount('px'), 1);
      });
    });

    testWidgets('lembar Impor Gagal: penjelasan versi untuk berkas lebih '
        'baru', (tester) async {
      await tester.runAsync(() async {
        await tester.pumpWidget(
          tree(
            Scaffold(
              body: Builder(
                builder: (ctx) => TextButton(
                  onPressed: () => showImportFailureSheet(
                    ctx,
                    const TransferParseFailure(
                      TransferFailureKind.newerVersion,
                      foundVersion: 99,
                    ),
                  ),
                  child: const Text('buka'),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.tap(find.text('buka'));
        await untilFound(tester, find.text('Berkas tidak bisa diimpor'));
        expect(find.textContaining('format 99'), findsOneWidget);
        expect(find.textContaining('Perbarui Clai'), findsOneWidget);
      });
    });

    testWidgets('lembar Bagikan: playlist kecil → QR tampil; tombol '
        'berkas ada', (tester) async {
      await tester.runAsync(() async {
        await tester.pumpWidget(
          tree(
            Scaffold(
              body: Consumer(
                builder: (ctx, ref, _) => TextButton(
                  onPressed: () => openSharePlaylistSheet(
                    ctx,
                    TransferPlaylist(
                      name: 'Senja',
                      tracks: [_tt('a'), _tt('b')],
                    ),
                  ),
                  child: const Text('buka'),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.tap(find.text('buka'));
        await untilFound(tester, find.byType(QrImageView));
        expect(find.byType(QrImageView), findsOneWidget);
        expect(find.text('Bagikan berkas'), findsOneWidget);
      });
    });

    testWidgets('lembar Bagikan: playlist besar → tanpa QR, penjelasan '
        'berkas saja', (tester) async {
      var seedN = 987654;
      String word(int len) {
        const chars = 'abcdefghijklmnopqrstuvwxyz';
        var s = '';
        for (var i = 0; i < len; i++) {
          seedN = (seedN * 1103515245 + 12345) & 0x7fffffff;
          s += chars[seedN % 26];
        }
        return s;
      }

      // Sejak ronde 8078 "terlalu besar" berarti mode ringkas pun
      // melewati ambang: 200 trek (40 trek kini masuk mode ringkas).
      final big = TransferPlaylist(
        name: 'Raksasa',
        tracks: [
          for (var i = 0; i < 200; i++)
            TransferTrack(
              providerId: 'ytmusic',
              trackId: word(11),
              title: '${word(9)} ${word(7)} ${word(12)}',
              artistNames: '${word(8)} ${word(6)}',
              durationMs: 200000,
              playableRef: word(11),
            ),
        ],
      );
      await tester.runAsync(() async {
        await tester.pumpWidget(
          tree(
            Scaffold(
              body: Consumer(
                builder: (ctx, ref, _) => TextButton(
                  onPressed: () => openSharePlaylistSheet(ctx, big),
                  child: const Text('buka'),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.tap(find.text('buka'));
        await untilFound(
          tester,
          find.textContaining('terlalu besar untuk kode QR'),
        );
        expect(find.byType(QrImageView), findsNothing);
        expect(find.text('Bagikan berkas'), findsOneWidget);
      });
    });
  });
}

/// DB pref-nol untuk tes hub (pola gulir_8052): pref selalu null tanpa
/// menyentuh disk, sehingga pemuat pref async hub tidak pernah membuka
/// basis data sungguhan.
class _NullPrefDb extends AppDb {
  @override
  Future<T?> pref<T>(String key) async => null;
}
