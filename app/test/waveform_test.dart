import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:clai/data/app_db.dart';
import 'package:clai/domain/models.dart';
import 'package:clai/services/waveform.dart';
import 'package:clai/services/waveform_recorder.dart';

/// Waveform UKUR (Ronde Player B): pemetaan ember, pengisian
/// progresif, persistensi (serialisasi + DB lewat perekam), dan
/// keadaan render kosong/sebagian/penuh. Data waveform adalah energi
/// NYATA hasil ukur — tes ini menjaga kejujurannya: ember tak terukur
/// tetap null.
///
/// Sisipan G-2 (2026-11-10): akumulasi gabung-maks diganti RATA-RATA
/// berjalan dan format naik ke v2.
///
/// **Ronde Perbaikan Waveform 8050 (2026-11-10):** akar kelas
/// kegagalan "hanya nyala ketika build baru" + "batang selalu sama
/// ukurannya" adalah NILAI TERSIMPAN YANG SUDAH DIPETAKAN — format
/// v2 menyimpan energi hasil jendela tetap (−60..−2 dB) yang
/// menjenuhkan pita perangkat sempit (−16..−3 dB) secara PERMANEN di
/// basis data. Format v3 menyimpan dB MENTAH + jumlah sampel;
/// pemetaan pindah ke waktu tampil sebagai normalisasi PERSENTIL
/// relatif per trek (p10→lantai, p95→penuh, rentang jujur minimal
/// 3 dB); data v2/v1 decode → null (ukur ulang). Kelompok tes di
/// bawah mengunci kelas kegagalan itu satu per satu.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('waveformBucketIndex — pemetaan posisi → ember', () {
    test('tepi & tengah pada 56 ember', () {
      const dur = Duration(minutes: 4); // 240 dtk → ember ±4,28 dtk
      expect(waveformBucketIndex(Duration.zero, dur), 0);
      expect(waveformBucketIndex(const Duration(seconds: 120), dur), 28);
      expect(waveformBucketIndex(const Duration(seconds: 239), dur), 55);
      // Posisi tepat di ujung dijepit ke ember terakhir, bukan meluap.
      expect(waveformBucketIndex(dur, dur), 55);
      expect(waveformBucketIndex(const Duration(minutes: 9), dur), 55);
    });

    test('durasi tak sah → -1 (tidak mengarang ember)', () {
      expect(waveformBucketIndex(Duration.zero, Duration.zero), -1);
      expect(
          waveformBucketIndex(const Duration(seconds: 3),
              const Duration(seconds: -1)),
          -1);
    });
  });

  group('WaveformData.withSample — akumulasi dB MENTAH', () {
    test('kosong: semua null, hitungan 0', () {
      final d = WaveformData.empty;
      expect(d.isEmpty, isTrue);
      expect(d.isFull, isFalse);
      expect(d.measuredCount, 0);
      expect(d.buckets.length, kWaveformBucketCount);
    });

    test('sampel pertama tersimpan sebagai dB apa adanya (BUKAN energi '
        'terpeta — regresi kelas kejenuhan v2)', () {
      final d = WaveformData.empty.withSample(10, -20);
      expect(d.buckets[10], closeTo(-20, 1e-9),
          reason: 'nilai tersimpan hidup di domain dBFS; tidak ada '
              'jendela yang bisa menjenuhkannya di basis data');
      expect(d.sampleCountAt(10), 1);
      expect(d.measuredCount, 1);
    });

    test('rata-rata berjalan di domain dB; putaran ulang menyempurnakan',
        () {
      var d = WaveformData.empty.withSample(10, -20);
      d = d.withSample(10, -26);
      expect(d.buckets[10], closeTo(-23, 1e-9));
      expect(d.sampleCountAt(10), 2);
      d = d.withSample(10, -17);
      expect(d.buckets[10], closeTo((-23 * 2 + -17) / 3, 1e-9));
      expect(d.sampleCountAt(10), 3);
    });

    test('satu hentakan keras tidak memaku ember', () {
      var d = WaveformData.empty.withSample(5, -30);
      d = d.withSample(5, -6);
      d = d.withSample(5, -30);
      d = d.withSample(5, -30);
      expect(d.buckets[5], closeTo((-30 + -6 + -30 + -30) / 4, 1e-9));
    });

    test('konvergen = objek yang sama (hemat tulis DB & notifikasi)', () {
      final d = WaveformData.empty.withSample(3, -20);
      expect(identical(d.withSample(3, -20), d), isTrue,
          reason: 'sampel sama dengan rata-rata tidak menggerakkan apa pun');
      // Rata-rata berbobot besar: satu sampel menyimpang sedikit pun
      // bergerak < 0,05 dB → tetap no-op.
      final heavy = WaveformData(
        List<double?>.filled(kWaveformBucketCount, -20.0),
        List<int>.filled(kWaveformBucketCount, 100),
      );
      expect(identical(heavy.withSample(0, -16), heavy), isTrue);
    });

    test('sampel dijepit ke domain Visualizer (−96..0) & indeks liar '
        'ditolak', () {
      expect(WaveformData.empty.withSample(0, 5).buckets[0], 0);
      expect(WaveformData.empty.withSample(0, -120).buckets[0], -96);
      final d = WaveformData.empty.withSample(1, -20);
      expect(identical(d.withSample(-1, -10), d), isTrue);
      expect(identical(d.withSample(kWaveformBucketCount, -10), d), isTrue);
    });

    test('penuh: 56 ember terisi → isFull', () {
      var d = WaveformData.empty;
      for (var i = 0; i < kWaveformBucketCount; i++) {
        d = d.withSample(i, -20);
      }
      expect(d.isFull, isTrue);
      expect(d.measuredCount, kWaveformBucketCount);
    });

    test('mergedWith menggabung rata-rata BERBOBOT jumlah sampel (dB)',
        () {
      final a =
          WaveformData.empty.withSample(1, -30).withSample(2, -12);
      final b =
          WaveformData.empty.withSample(2, -24).withSample(3, -18);
      final m = a.mergedWith(b);
      expect(m.buckets[1], closeTo(-30, 1e-9), reason: 'hanya di a');
      expect(m.buckets[2], closeTo(-18, 1e-9),
          reason: '(−12×1 + −24×1) / 2 — bobot sampel, bukan maks');
      expect(m.sampleCountAt(2), 2);
      expect(m.buckets[3], closeTo(-18, 1e-9), reason: 'hanya di b');
      expect(m.measuredCount, 3);
      // Menggabung dua himpunan ukur (muatan DB + umpan langsung)
      // menjumlahkan bukti sampelnya: nilai ember yang sama
      // dipertahankan, hitungannya bertambah — bukan no-op.
      final self = a.mergedWith(a);
      expect(self.buckets[1], closeTo(-30, 1e-9));
      expect(self.sampleCountAt(1), 2);
    });
  });

  group('persentil & rentang dinamis (domain dB mentah)', () {
    test('kosong & tunggal', () {
      expect(WaveformData.empty.percentileDb(50), isNull);
      expect(WaveformData.empty.dynamicRangeDb, 0);
      final one = WaveformData.empty.withSample(7, -15);
      expect(one.percentileDb(10), closeTo(-15, 1e-9));
      expect(one.percentileDb(95), closeTo(-15, 1e-9));
      expect(one.dynamicRangeDb, 0);
    });

    test('interpolasi linear antar peringkat terurut', () {
      var d = WaveformData.empty;
      for (final v in [-40.0, -30.0, -20.0, -10.0]) {
        d = d.withSample(d.measuredCount, v);
      }
      // 4 nilai terurut: p10 peringkat 0,3 → −40 + 0,3×10 = −37;
      // p95 peringkat 2,85 → −20 + 0,85×10 = −11,5.
      expect(d.percentileDb(10), closeTo(-37, 1e-9));
      expect(d.percentileDb(95), closeTo(-11.5, 1e-9));
      expect(d.dynamicRangeDb, closeTo(25.5, 1e-9));
    });
  });

  group('displayHeights — normalisasi PERSENTIL waktu tampil (8050)', () {
    test('pita perangkat sempit (−16..−3 dB) tampil BERVARIASI nyata '
        '(regresi vonis pemilik: batang selalu sama ukuran)', () {
      var d = WaveformData.empty;
      for (var i = 0; i < kWaveformBucketCount; i++) {
        d = d.withSample(i, -16 + 13 * i / (kWaveformBucketCount - 1));
      }
      final h = d.displayHeights();
      expect(h.every((e) => e != null), isTrue);
      final vals = h.cast<double>();
      expect(vals.reduce((a, b) => a < b ? a : b), closeTo(0.10, 0.02),
          reason: 'ember terpelan menempel lantai tampil terukur');
      expect(vals.reduce((a, b) => a > b ? a : b), closeTo(1.0, 0.02),
          reason: 'ember di atas p95 tampil penuh');
      expect(vals.toSet().length, greaterThanOrEqualTo(20),
          reason: 'dinamika di dalam pita sempit terbaca sebagai '
              'banyak tinggi berbeda, bukan satu tinggi seragam');
    });

    test('data nyaris seragam TIDAK diledakkan (rentang jujur ≥3 dB)',
        () {
      // Semua ember dalam ±0,4 dB di sekitar −10: secara dengar memang
      // seragam — tampil harus mengumpul di tengah, bukan 0-vs-1.
      var d = WaveformData.empty;
      for (var i = 0; i < kWaveformBucketCount; i++) {
        d = d.withSample(i, i.isEven ? -10.4 : -9.6);
      }
      final h = d.displayHeights().cast<double>();
      for (final v in h) {
        expect(v, inInclusiveRange(0.30, 0.75));
      }
      final spread =
          h.reduce((a, b) => a > b ? a : b) - h.reduce((a, b) => a < b ? a : b);
      expect(spread, lessThan(0.45));
    });

    test('p95 (bukan maksimum) jadi jangkar: satu hentakan liar tidak '
        'meratakan lagu', () {
      var d = WaveformData(
          List<double?>.filled(kWaveformBucketCount, -30.0));
      d = d.withSample(20, -3); // ember 20: rata-rata (−30 + −3)/2
      final h = d.displayHeights();
      expect(h[20], closeTo(1.0, 0.02));
      expect(h[0], closeTo(0.55, 0.02),
          reason: 'massa pelan tampil menengah oleh pelebaran rentang '
              'jujur — tidak runtuh ke lantai gara-gara satu hentakan');
    });

    test('ember terukur selalu terbedakan dari tik belum-terukur', () {
      final d = WaveformData.empty.withSample(0, -50);
      final h = d.displayHeights();
      expect(h[0], isNotNull);
      expect(h[0]!, greaterThanOrEqualTo(0.10),
          reason: 'lantai tampil terukur 0,10');
      expect(h[1], isNull, reason: 'belum terukur tetap null (jujur)');
      expect(WaveformData.empty.displayHeights().every((e) => e == null),
          isTrue);
    });
  });

  group('serialisasi v3 — dB mentah + jumlah sampel', () {
    test('pulang-pergi: nilai (dibulatkan 0,1 dB) & hitungan awet', () {
      var d = WaveformData.empty.withSample(0, -20).withSample(55, -6);
      d = d.withSample(0, -22); // ember 0: rata-rata −21, 2 sampel
      expect(d.encode().startsWith('{"v":3'), isTrue,
          reason: 'muatan membawa penanda format v3');
      final back = WaveformData.decode(d.encode());
      expect(back, isNotNull);
      expect(back!.buckets[0], closeTo(-21, 0.001));
      expect(back.sampleCountAt(0), 2,
          reason: 'jumlah sampel ikut tersimpan (rata-rata bisa lanjut)');
      expect(back.buckets[55], closeTo(-6, 0.001));
      expect(back.measuredCount, 2);
    });

    test('MIGRASI 8050: data v2 (energi jenuh jendela tetap) dibuang — '
        'ukur ulang', () {
      // Baris DB era v2: 56 ember energi ±0,95 (jenuh oleh pita
      // perangkat sempit) — tidak bisa dipulihkan ke dB mentah.
      final b = List<double>.filled(kWaveformBucketCount, 0.95);
      final n = List<int>.filled(kWaveformBucketCount, 4);
      expect(WaveformData.decode('{"v":2,"b":$b,"n":$n}'), isNull,
          reason: 'kejenuhan era jendela tetap tidak dipercaya lagi; '
              'trek diperlakukan belum terukur');
    });

    test('MIGRASI: data v1 (larik polos) dibuang — ukur ulang', () {
      expect(WaveformData.decode('[0.95, 0.95, null, 1.0]'), isNull);
      expect(WaveformData.decode('[0.5, null]'), isNull);
    });

    test('data rusak → null (tidak pernah tampil sebagai data)', () {
      expect(WaveformData.decode(null), isNull);
      expect(WaveformData.decode(''), isNull);
      expect(WaveformData.decode('bukan json'), isNull);
      expect(WaveformData.decode('{"a":1}'), isNull,
          reason: 'objek tanpa penanda v3 tidak dipercaya');
      // Entri bukan angka di dalam v3 terbaca sebagai ember kosong,
      // bukan crash.
      final d = WaveformData.decode('{"v":3,"b":["x",-20],"n":[1,1]}');
      expect(d, isNotNull);
      expect(d!.buckets[0], isNull);
      expect(d.buckets[1], closeTo(-20, 1e-9));
    });
  });

  group('waveformWantsVisualizer — gerbang yang tidak membungkam '
      'pengukuran ulang (8050)', () {
    test('belum lengkap = butuh', () {
      expect(waveformWantsVisualizer(WaveformData.empty), isTrue);
      final partial = WaveformData.empty.withSample(0, -20);
      expect(waveformWantsVisualizer(partial), isTrue);
    });

    test('penuh + bervariasi = selesai (Visualizer tidak dibakar)', () {
      var d = WaveformData.empty;
      for (var i = 0; i < kWaveformBucketCount; i++) {
        d = d.withSample(i, -20 + (i % 7));
      }
      expect(d.isFull, isTrue);
      expect(d.dynamicRangeDb, greaterThanOrEqualTo(kWaveformVarianceFloorDb));
      expect(waveformWantsVisualizer(d), isFalse);
    });

    test('penuh tetapi DATAR dengan sampel sedikit = TETAP butuh '
        '(regresi akar "mati sendiri": penanda penuh era jenuh tidak '
        'boleh mematikan gerbang selamanya)', () {
      final flat = WaveformData(
        List<double?>.filled(kWaveformBucketCount, -10.0),
        List<int>.filled(kWaveformBucketCount, 1),
      );
      expect(flat.isFull, isTrue);
      expect(flat.dynamicRangeDb, 0);
      expect(waveformWantsVisualizer(flat), isTrue,
          reason: '56 ember identik dari 1 sampel per ember adalah '
              'tanda data jenuh/tercemar, bukan lagu selesai diukur');
    });

    test('penuh datar dengan bukti sampel berlimpah = lagu memang '
        'seragam → diterima, gerbang padam (kejujuran dua arah)', () {
      final flatProven = WaveformData(
        List<double?>.filled(kWaveformBucketCount, -10.0),
        List<int>.filled(kWaveformBucketCount, 3),
      );
      expect(flatProven.totalSamples, 3 * kWaveformBucketCount);
      expect(waveformWantsVisualizer(flatProven), isFalse);
    });
  });

  group('WaveformRecorder — umpan, cache, persistensi', () {
    const key = TrackKey('ytmusic', 'trek-uji');

    test('feed hanya saat playing & menyimpan dB MENTAH per ember', () async {
      final db = _FakeWaveDb();
      final r = WaveformRecorder(db);
      r.feed(
          key: key,
          position: const Duration(seconds: 30),
          duration: const Duration(minutes: 4),
          rmsDb: -20,
          playing: false);
      expect(r.dataFor(key).isEmpty, isTrue,
          reason: 'jeda: tidak ada pengukuran');
      r.feed(
          key: key,
          position: const Duration(seconds: 30),
          duration: const Duration(minutes: 4),
          rmsDb: -20,
          playing: true);
      final d = r.dataFor(key);
      expect(d.measuredCount, 1);
      expect(
          d.buckets[waveformBucketIndex(
              const Duration(seconds: 30), const Duration(minutes: 4))],
          closeTo(-20, 1e-9),
          reason: 'yang tersimpan adalah rmsDb mentah — pemetaan '
              'terjadi nanti di waktu tampil (persentil)');
      // Persistensi terpanggil dengan data yang sama.
      await Future<void>.delayed(Duration.zero);
      expect(db.saved[key], isNotNull);
      expect(db.saved[key]!.measuredCount, 1);
    });

    test('penghitung diagnosis: sebab buang tercatat apa adanya', () {
      final db = _FakeWaveDb();
      final r = WaveformRecorder(db);
      // Tidak playing → buang jeda, tanpa tulis.
      r.feed(
          key: key,
          position: const Duration(seconds: 10),
          duration: const Duration(minutes: 4),
          rmsDb: -20,
          playing: false);
      // Durasi nol → buang durasi0 (indeks tak terhitung).
      r.feed(
          key: key,
          position: const Duration(seconds: 10),
          duration: Duration.zero,
          rmsDb: -20,
          playing: true);
      // Sampel sah → satu tulis diterima.
      r.feed(
          key: key,
          position: const Duration(seconds: 10),
          duration: const Duration(minutes: 4),
          rmsDb: -20,
          playing: true);
      expect(r.feedCalls, 3);
      expect(r.dropNotPlaying, 1);
      expect(r.dropNoDuration, 1);
      expect(r.dropBadIndex, 0);
      expect(r.acceptedWrites, 1);
      expect(r.lastFeedKey, key);
      expect(r.lastDurMs, 240000);
      // Asal sesi & keselarasan kunci dari noteRmsEvent.
      r.noteRmsEvent(
          fromActiveSession: true,
          hasCurrent: true,
          feedKey: key,
          soundingKey: key);
      r.noteRmsEvent(
          fromActiveSession: false,
          hasCurrent: true,
          feedKey: key,
          soundingKey: const TrackKey('ytmusic', 'trek-lain'));
      r.noteRmsEvent(
          fromActiveSession: false, hasCurrent: false, feedKey: null, soundingKey: null);
      expect(r.rmsEvents, 3);
      expect(r.rmsFromActiveSession, 1);
      expect(r.rmsFromOtherSession, 2);
      expect(r.rmsKeyMismatch, 1);
      expect(r.rmsNoCurrent, 1);
    });

    test('dataFor memuat dari DB secara malas lalu menyatu', () async {
      final db = _FakeWaveDb();
      db.stored[key] = WaveformData.empty.withSample(3, -14);
      final r = WaveformRecorder(db);
      expect(r.dataFor(key).isEmpty, isTrue,
          reason: 'muat asinkron: panggilan pertama masih kosong');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(r.dataFor(key).buckets[3], closeTo(-14, 1e-9));
    });
  });

  group('AppDb waveform (skema v5) — jalur upgrade adversarial', () {
    test('saveWaveform/waveformFor pulang-pergi v3 di DB memori', () async {
      final db = AppDb();
      await db.openAt(':memory:');
      const k = TrackKey('ytmusic', 'wf1');
      expect(await db.waveformFor(k), isNull);
      final d = WaveformData.empty.withSample(7, -18).withSample(8, -9);
      await db.saveWaveform(k, d);
      final back = await db.waveformFor(k);
      expect(back, isNotNull);
      expect(back!.buckets[7], closeTo(-18, 0.001));
      expect(back.buckets[8], closeTo(-9, 0.001));
      expect(back.measuredCount, 2);
      await db.close();
    });

    test('baris v1 di DB terbaca null (jalur ukur-ulang)', () async {
      final db = AppDb();
      await db.openAt(':memory:');
      const k = TrackKey('ytmusic', 'wf-v1');
      final d = await db.db;
      await d.insert('track_waveforms', {
        'provider_id': k.providerId,
        'provider_track_id': k.id,
        'buckets': '[0.95, 0.95, 0.95]',
        'updated_at': 0,
      });
      expect(await db.waveformFor(k), isNull,
          reason: 'data jenuh format lama tidak dipercaya; trek akan '
              'diukur ulang saat diputar');
      await db.close();
    });

    test('ADVERSARIAL 8050: DB disemai baris v2 JENUH (keadaan HP '
        'pemilik sesudah build lama) → terbaca null → putaran baru '
        'menulis v3 dan waveform pulih', () async {
      final db = AppDb();
      await db.openAt(':memory:');
      const k = TrackKey('ytmusic', 'wf-jenuh');
      final d = await db.db;
      // Semai persis muatan era v2: energi terjenuh jendela tetap.
      final b = List<double>.filled(kWaveformBucketCount, 0.95);
      final n = List<int>.filled(kWaveformBucketCount, 4);
      await d.insert('track_waveforms', {
        'provider_id': k.providerId,
        'provider_track_id': k.id,
        'buckets': '{"v":2,"b":$b,"n":$n}',
        'updated_at': 0,
      });
      expect(await db.waveformFor(k), isNull,
          reason: 'baris jenuh warisan build lama ditolak di jalur '
              'baca yang sama dengan produksi — bukan dipercaya');
      // Pemulihan: pengukuran baru (dB mentah) menimpa baris lama.
      var fresh = WaveformData.empty;
      for (var i = 0; i < kWaveformBucketCount; i++) {
        fresh = fresh.withSample(i, -16 + 13 * i / (kWaveformBucketCount - 1));
      }
      await db.saveWaveform(k, fresh);
      final back = await db.waveformFor(k);
      expect(back, isNotNull);
      expect(back!.isFull, isTrue);
      // Rentang dinamis adalah p95 − p10 (bukan maks − min): untuk
      // sebaran linear −16..−3 nilainya ±11,05 dB.
      expect(back.dynamicRangeDb, closeTo(11.05, 0.2));
      final heights = back.displayHeights().cast<double>();
      expect(
          heights.reduce((a, c) => a > c ? a : c) -
              heights.reduce((a, c) => a < c ? a : c),
          greaterThan(0.8),
          reason: 'sesudah upgrade, batang tampil bervariasi penuh '
              'dari data yang sama sekali baru');
      await db.close();
    });
  });
}

/// AppDb palsu tanpa IO untuk perekam: hanya dua metode waveform.
class _FakeWaveDb extends AppDb {
  final Map<TrackKey, WaveformData> stored = {};
  final Map<TrackKey, WaveformData> saved = {};

  @override
  Future<WaveformData?> waveformFor(TrackKey k) async => stored[k];

  @override
  Future<void> saveWaveform(TrackKey k, WaveformData data) async {
    saved[k] = data;
    stored[k] = data;
  }
}
