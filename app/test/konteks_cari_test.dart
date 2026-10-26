// Regresi keputusan pemilik 2026-10-26 (Ronde Konteks Pencarian, build 2018):
// mengetuk lagu di HASIL PENCARIAN menjadikan HANYA lagu itu konteks putar
// (daftar hasil = daftar temu, bukan kurasi); kelanjutan adalah pekerjaan
// Putar Otomatis. Kasus kontrol: ketuk di playlist tetap konteks daftar penuh.
//
// Catatan cakupan: SearchScreen utuh tidak dipompa (handler konkret menyentuh
// kanal platform — kendala yang sama dicatat radio_header_a5_test). Yang
// diuji: fungsi pembentuk konteks yang dipakai layar Cari sungguhan
// (searchTapTracks) + mesin antrean sungguhan dengan konteks persis seperti
// yang dibangun handler dari ketukan itu.
import 'package:clai/domain/models.dart';
import 'package:clai/player/queue_engine.dart';
import 'package:clai/ui/search_screen.dart';
import 'package:flutter_test/flutter_test.dart';

Track t(String id) => Track(
      key: TrackKey('ytmusic', id),
      title: 'Lagu $id',
      artistNames: 'Artis A',
      duration: const Duration(minutes: 3),
      playableRef: id,
    );

void main() {
  final hasilCari = [t('c1'), t('c2'), t('c3'), t('c4'), t('c5')];

  group('konteks pencarian satu lagu (keputusan 2026-10-26)', () {
    test('searchTapTracks mengembalikan tepat lagu yang diketuk', () {
      final out = searchTapTracks(hasilCari[2]);
      expect(out.length, 1);
      expect(out.single.key, hasilCari[2].key);
    });

    test('ketuk hasil cari ke-3: antrean non-otomatis = 1 lagu itu saja', () {
      // Persis yang dibangun handler dari ketukan baris ke-3 di layar Cari:
      // playTracks(searchTapTracks(t), 0, kind: 'search', label: 'Hasil cari')
      // → engine.playContext di dalamnya.
      final e = QueueEngine();
      e.playContext(
        PlayContext(
          kind: 'search',
          label: 'Hasil cari',
          tracks: searchTapTracks(hasilCari[2]),
        ),
        0,
      );
      expect(e.current?.key, hasilCari[2].key);
      // Lagu hasil lain TIDAK masuk: bukan di Lanjutan, bukan di Berikutnya,
      // bukan sebagai benih pendamping.
      expect(e.continuation, isEmpty);
      expect(e.manual, isEmpty);
      expect(e.fullQueue.map((x) => x.key), [hasilCari[2].key]);
      expect(e.seeds.map((x) => x.key), [hasilCari[2].key]);
      // Label & jenis konteks tetap jujur.
      expect(e.context?.kind, 'search');
      expect(e.context?.label, 'Hasil cari');
      // Putar Otomatis belum terisi di tingkat mesin (isi ulang adalah
      // pekerjaan handler) dan gerbangnya aktif secara bawaan.
      expect(e.autoplay, isEmpty);
      expect(e.autoplayActive, isTrue);
    });

    test('ketuk hasil cari pertama pun tetap satu lagu (bukan daftar)', () {
      final e = QueueEngine();
      e.playContext(
        PlayContext(
          kind: 'search',
          label: 'Hasil cari',
          tracks: searchTapTracks(hasilCari[0]),
        ),
        0,
      );
      expect(e.fullQueue.map((x) => x.key), [hasilCari[0].key]);
      expect(e.continuation, isEmpty);
    });
  });

  group('kontrol: konteks daftar penuh tidak berubah', () {
    test('ketuk lagu ke-3 di playlist: sisa playlist tetap menjadi Lanjutan',
        () {
      final playlist = [t('p1'), t('p2'), t('p3'), t('p4'), t('p5')];
      final e = QueueEngine();
      e.playContext(
        PlayContext(kind: 'playlist', label: 'Playlist Uji', tracks: playlist),
        2,
      );
      expect(e.current?.key, playlist[2].key);
      expect(
        e.continuation.map((x) => x.key),
        [playlist[3].key, playlist[4].key],
      );
      expect(
        e.fullQueue.map((x) => x.key),
        [playlist[2].key, playlist[3].key, playlist[4].key],
      );
    });
  });
}
