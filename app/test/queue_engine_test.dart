import 'package:clai/domain/models.dart';
import 'package:clai/player/queue_engine.dart';
import 'package:flutter_test/flutter_test.dart';

Track t(String id, {String artist = 'Artis A'}) => Track(
      key: TrackKey('ytmusic', id), title: 'Lagu $id', artistNames: artist,
      duration: const Duration(minutes: 3), playableRef: id);

void main() {
  group('QueueEngine — aturan Phase 2', () {
    test('L-03: antrean manual bertahan saat konteks berganti', () {
      final e = QueueEngine();
      e.playContext(PlayContext(kind: 'album', label: 'A', tracks: [t('1'), t('2'), t('3')]), 0);
      e.enqueueLater(t('m1'));
      e.playContext(PlayContext(kind: 'album', label: 'B', tracks: [t('9'), t('8')]), 0);
      expect(e.current!.id, '9');
      expect(e.manual.map((x) => x.id), ['m1']);
      expect(e.continuation.map((x) => x.id), ['8']);
    });

    test('L-04: Putar Berikutnya di kepala manual, Tambah ke Antrian di ekor', () {
      final e = QueueEngine();
      e.playContext(PlayContext(kind: 'search', label: 'S', tracks: [t('1')]), 0);
      e.enqueueLater(t('a'));
      e.enqueueNext(t('b'));
      expect(e.manual.map((x) => x.id), ['b', 'a']);
      expect(e.effectiveQueue.first.id, 'b');
    });

    test('L-09: prioritas manual > lanjutan; Repeat-Satu mengulang saat selesai', () {
      final e = QueueEngine();
      e.playContext(PlayContext(kind: 'album', label: 'A', tracks: [t('1'), t('2')]), 0);
      e.enqueueNext(t('m'));
      final n1 = e.advance(byCompletion: true);
      expect(n1!.id, 'm');
      e.repeat = RepeatMode.one;
      final n2 = e.advance(byCompletion: true);
      expect(n2!.id, 'm'); // repeat-satu: tetap
      final n3 = e.advance(byCompletion: false); // skip manual menembus repeat-satu
      expect(n3!.id, '2');
    });

    test('Repeat-Semua mengulang konteks > 1 lagu dari awal', () {
      final e = QueueEngine();
      e.playContext(PlayContext(kind: 'album', label: 'A', tracks: [t('1'), t('2')]), 0);
      e.repeat = RepeatMode.all;
      e.advance(byCompletion: true);
      final looped = e.advance(byCompletion: true);
      expect(looped!.id, '1');
      expect(e.continuation.map((x) => x.id), ['2']);
    });

    test('Konteks satu lagu + Repeat-Semua = jatuh ke Putar Otomatis (advance null)', () {
      final e = QueueEngine();
      e.playContext(PlayContext(kind: 'search', label: 'S', tracks: [t('1')]), 0);
      e.repeat = RepeatMode.all;
      expect(e.advance(byCompletion: true), isNull);
      expect(e.needsAutoplayRefill, isTrue);
    });

    test('needsAutoplayRefill menyala saat sisa < 5 dan mati saat autoplay dimatikan', () {
      final e = QueueEngine();
      e.playContext(PlayContext(kind: 'search', label: 'S', tracks: [t('1'), t('2')]), 0);
      expect(e.needsAutoplayRefill, isTrue);
      e.autoplaySessionOn = false;
      expect(e.needsAutoplayRefill, isFalse);
    });

    test('jumpTo memangkas seksi dengan benar', () {
      final e = QueueEngine();
      e.playContext(PlayContext(kind: 'album', label: 'A', tracks: [t('1'), t('2'), t('3'), t('4')]), 0);
      final target = e.jumpTo(const TrackKey('ytmusic', '3'));
      expect(target!.id, '3');
      expect(e.continuation.map((x) => x.id), ['4']);
    });

    test('snapshot & restore membulatkan antrean', () {
      final e = QueueEngine();
      final all = [t('1'), t('2'), t('3'), t('m')];
      e.playContext(PlayContext(kind: 'album', label: 'A', tracks: all.sublist(0, 3)), 0);
      e.enqueueLater(all[3]);
      final snap = e.snapshot(positionMs: 42000);
      final e2 = QueueEngine();
      e2.restore(snap, {for (final x in all) x.key: x});
      expect(e2.current!.id, '1');
      expect(e2.manual.map((x) => x.id), ['m']);
      expect(e2.continuation.map((x) => x.id), ['2', '3']);
    });

    test('shuffle murni: posisi lagu berjalan tetap, urutan lain berubah dari aslinya', () {
      final e = QueueEngine()..shuffle = ShuffleMode.pure;
      final tracks = [for (var i = 0; i < 12; i++) t('$i')];
      e.playContext(PlayContext(kind: 'album', label: 'A', tracks: tracks), 4);
      expect(e.current!.id, '4');
      expect(e.continuation.length, 11);
      expect(e.continuation.map((x) => x.id).toSet().length, 11);
    });

    test('riwayat sesi & restorePlayed (audit v4.4): gerak mundur memulihkan urutan', () {
      final e = QueueEngine();
      final tracks = [t('1'), t('2'), t('3'), t('4')];
      e.playContext(PlayContext(kind: 'album', label: 'A', tracks: tracks), 0);
      expect(e.played, isEmpty);
      // Simulasi handler: current lama masuk riwayat saat maju (perilaku
      // _syncEngineTo) — di sini ditiru manual karena mesinnya murni.
      void advanceTo(String id) {
        final old = e.current!;
        e.played.add(old);
        e.continuation.removeWhere((x) => x.id == id);
        e.current = tracks.firstWhere((x) => x.id == id);
      }

      advanceTo('2');
      advanceTo('3');
      expect(e.played.map((x) => x.id), ['1', '2']);
      expect(e.current!.id, '3');
      // Mundur satu langkah: 3 kembali ke kepala Lanjutan, 2 berjalan lagi.
      e.restorePlayed(e.playedIndexOf(t('2').key));
      expect(e.current!.id, '2');
      expect(e.played.map((x) => x.id), ['1']);
      expect(e.continuation.map((x) => x.id), ['3', '4']);
      // Mundur ke awal: seluruh urutan pulih.
      e.restorePlayed(e.playedIndexOf(t('1').key));
      expect(e.current!.id, '1');
      expect(e.played, isEmpty);
      expect(e.continuation.map((x) => x.id), ['2', '3', '4']);
      // Konteks baru membersihkan riwayat.
      e.played.add(t('9'));
      e.playContext(PlayContext(kind: 'album', label: 'B', tracks: tracks), 2);
      expect(e.played, isEmpty);
      // Snapshot membawa riwayat; restore membacanya kembali.
      final e2 = QueueEngine();
      e2.playContext(PlayContext(kind: 'album', label: 'A', tracks: tracks), 0);
      e2.played.add(t('1'));
      final snap = e2.snapshot(positionMs: 0);
      expect((snap['played'] as List).length, 1);
      final e3 = QueueEngine();
      e3.restore(snap, {for (final x in tracks) x.key: x});
      expect(e3.played.map((x) => x.id), ['1']);
    });

    test('noteDuration (v4.3): durasi pemutar tercatat ke trek berjalan & seksi', () {
      Track noDur(String id) => Track(key: TrackKey('ytmusic', id), title: 'Lagu $id',
          artistNames: 'Artis A', playableRef: id);
      final e = QueueEngine();
      e.playContext(PlayContext(kind: 'search', label: 'S', tracks: [noDur('1'), noDur('2')]), 0);
      e.enqueueLater(noDur('3'));
      const d = Duration(minutes: 4, seconds: 31);
      expect(e.noteDuration(const TrackKey('ytmusic', '1'), d), isTrue);
      expect(e.current!.duration, d);
      expect(e.context!.tracks.first.duration, d, reason: 'trek konteks ikut diperbarui');
      // Trek lain tidak tersentuh; id tak dikenal = tidak ada perubahan.
      expect(e.continuation.single.duration, isNull);
      expect(e.noteDuration(const TrackKey('ytmusic', 'zzz'), d), isFalse);
      // Nilai yang sama persis tidak dihitung perubahan dua kali.
      expect(e.noteDuration(const TrackKey('ytmusic', '1'), d), isFalse);
    });
  });

  group('QueueEngine — v4.4.2 (benih isi ulang, pemicu akhir, sesi)', () {
    test('refillSeeds: jangkar benih pertama di depan, trek selesai sesi ikut, maks 3', () {
      final e = QueueEngine();
      e.playContext(PlayContext(kind: 'album', label: 'A', tracks: [t('s1'), t('s2'), t('s3'), t('s4')]), 0);
      // Dua trek selesai sesi ini (riwayat played, urutan putar s2 lalu s3).
      e.played = [t('s2'), t('s3')];
      final seeds = e.refillSeeds();
      expect(seeds.map((x) => x.id), ['s1', 's3', 's2'],
          reason: 'jangkar asli dulu, lalu yang selesai terbaru, lalu yang lebih lama');
    });

    test('refillSeeds radio: benih tunggal tetap tunggal walau ada riwayat', () {
      final e = QueueEngine();
      e.playRadio(t('only'));
      e.played = [t('old')];
      expect(e.refillSeeds().map((x) => x.id), ['only', 'old']);
    });

    test('starvedAtEnd: trek tunggal + Putar Otomatis aktif = kelaparan; mati/ada antrean = tidak', () {
      final e = QueueEngine();
      e.playRadio(t('one'));
      expect(e.starvedAtEnd, isTrue, reason: 'kondisi persis laporan pemilik cacat-2');
      e.autoplaySessionOn = false;
      expect(e.starvedAtEnd, isFalse, reason: 'sakelar mati = memang harus berhenti');
      e.autoplaySessionOn = true;
      e.enqueueLater(t('next'));
      expect(e.starvedAtEnd, isFalse, reason: 'ada antrean efektif = jendela bisa lanjut sendiri');
    });

    test('sessionId naik pada konteks manual baru (penanda batch basi)', () {
      final e = QueueEngine();
      final s0 = e.sessionId;
      e.playContext(PlayContext(kind: 'album', label: 'A', tracks: [t('1')]), 0);
      expect(e.sessionId, s0 + 1);
      e.playRadio(t('2'));
      expect(e.sessionId, s0 + 2);
    });
  });

  group('QueueEngine — v4.4.3 (jangkar trek dipilih & bersihkan = sesi baru)', () {
    test('playContext indeks > 0: benih pertama = trek yang diketuk, bukan kepala daftar', () {
      final e = QueueEngine();
      final tracks = [t('A'), t('B'), t('C'), t('D')];
      // Pola rak Terakhir Diputar: daftar [A, B, C, D], pengguna mengetuk B.
      e.playContext(PlayContext(kind: 'search', label: 'Terakhir Diputar', tracks: tracks), 1);
      expect(e.current!.id, 'B');
      expect(e.seeds.first.id, 'B', reason: 'jangkar label & isi ulang mengikuti ketukan');
      expect(e.seeds.map((x) => x.id).toSet(), {'A', 'B', 'C', 'D'},
          reason: 'seluruh konteks tetap menjadi benih pendamping, tepat sekali');
      expect(e.refillSeeds().first.id, 'B');
    });

    test('playContext indeks 0: urutan benih tidak berubah dari rancangan lama', () {
      final e = QueueEngine();
      e.playContext(PlayContext(kind: 'album', label: 'A', tracks: [t('1'), t('2'), t('3')]), 0);
      expect(e.seeds.map((x) => x.id), ['1', '2', '3']);
    });

    test('resetSessionToCurrent: benih hanya trek berjalan, sinyal & antrean bersih, sesi naik', () {
      final e = QueueEngine();
      final a = t('A'), b = t('B'), c = t('C');
      e.playContext(PlayContext(kind: 'search', label: 'Sesi lama', tracks: [a, b, c]), 0);
      e.jumpTo(b.key); // trek berjalan B, jangkar masih A — keadaan persis laporan pemilik
      expect(e.seeds.first.id, 'A');
      e.enqueueLater(t('M'));
      e.appendAutoplay([t('X'), t('Y')]);
      e.noteSkipped(c);
      e.noteCompleted(a);
      e.played.add(a);
      final sid = e.sessionId;
      e.resetSessionToCurrent();
      expect(e.current!.id, 'B');
      expect(e.seeds.map((x) => x.id), ['B'], reason: 'benih sesi baru hanya trek berjalan');
      expect(e.refillSeeds().map((x) => x.id), ['B'],
          reason: 'riwayat lama tidak boleh menyusup kembali sebagai benih isi ulang');
      expect(e.manual, isEmpty);
      expect(e.continuation, isEmpty);
      expect(e.autoplay, isEmpty);
      expect(e.played, isEmpty);
      expect(e.skippedKeys, isEmpty, reason: 'sinyal negatif sesi lama ikut direset');
      expect(e.completedKeys, isEmpty);
      expect(e.sessionId, sid + 1, reason: 'batch basi sesi lama harus tertolak penjaga handler');
      expect(e.context!.tracks.map((x) => x.id), ['B']);
      // Potret sesi baru membulat: restore menjaga jangkar B.
      final snap = e.snapshot(positionMs: 0);
      final e2 = QueueEngine();
      e2.restore(snap, {for (final x in [a, b, c]) x.key: x});
      expect(e2.current!.id, 'B');
      expect(e2.seeds.map((x) => x.id), ['B']);
    });

    test('resetSessionToCurrent tanpa trek berjalan: benih kosong bersih, tidak melempar', () {
      final e = QueueEngine();
      final sid = e.sessionId;
      e.resetSessionToCurrent();
      expect(e.seeds, isEmpty);
      expect(e.current, isNull);
      expect(e.context, isNull);
      expect(e.sessionId, sid + 1);
    });

    test('menghapus SATU trek tidak mereset sesi: jangkar, sinyal, sessionId utuh', () {
      final e = QueueEngine();
      final a = t('A'), b = t('B');
      e.playContext(PlayContext(kind: 'search', label: 'S', tracks: [a, b]), 0);
      e.appendAutoplay([t('X')]);
      e.noteSkipped(b);
      final sid = e.sessionId;
      final removed = e.removeAt(e.autoplay, 0);
      expect(removed!.id, 'X');
      expect(e.seeds.map((x) => x.id), ['A', 'B']);
      expect(e.skippedKeys, isNotEmpty);
      expect(e.sessionId, sid);
    });
  });
}
