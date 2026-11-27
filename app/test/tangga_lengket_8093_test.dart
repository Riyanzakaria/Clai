import 'package:clai/domain/models.dart';
import 'package:clai/player/load_ladder.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ronde 8093 — tangga pemenang lengket (dossier REPRO 23 Nov 2026 §4):
/// sesudah SATU kegagalan anak adaptif, pemenang lengket pindah ke muxed
/// dan TIDAK pernah kembali — jalan pulih lama (`onRecovered` service)
/// mensyaratkan direct-ok untuk trek korban persis, yang mustahil terjadi
/// selama tak ada pemuatan melewati anak adaptif. Tes ini mengunci
/// perbaikan masa-percobaan (probe): tangga HARUS mencoba anak adaptif
/// lagi di dalam sesi yang sama, dengan backoff hitungan kemenangan,
/// tanpa menghajar sumber yang sungguh mati.
void main() {
  StreamInfo info(String url) => StreamInfo(
      url: url,
      mimeType: 'audio/webm',
      expiresAt: DateTime.now().add(const Duration(hours: 1)));

  LoadLadder ladder() => LoadLadder(
        resolveAdaptive: (t, {stillWanted}) async => info('https://contoh/adaptif'),
        resolveMuxed: (t) async => info('https://contoh/muxed'),
        tagFor: (t) => 'tag-${t.id}',
        isLocal: (t) => false,
      );

  test(
      'REPRO kebuntuan: sesudah demosi ke muxed, anak adaptif dicoba lagi '
      'dalam sesi yang sama dan tangga pulih penuh', () async {
    final l = ladder();
    var adaptiveDown = true;
    final attempted = <int>[];
    Future<int> load() => l.run(attempt: (rung) async {
          attempted.add(rung);
          if (rung == LoadLadder.rungAdaptiveUri && adaptiveDown) {
            throw StateError('403 jendela');
          }
        });

    // Pemuatan pertama: adaptif gugur (403), muxed menang → demosi.
    expect(await load(), LoadLadder.rungMuxedUri);
    expect(l.stickyRung, LoadLadder.rungMuxedUri);

    // Sumber adaptif sebenarnya sudah sehat lagi (sesi disegarkan dsb).
    adaptiveDown = false;
    attempted.clear();

    // 30 pemuatan berikutnya: tanpa masa percobaan, anak adaptif TIDAK
    // PERNAH dicoba lagi dan lengket tetap di muxed selamanya (kebuntuan
    // dossier). Dengan perbaikan: anak adaptif dicoba lagi dan menang.
    for (var i = 0; i < 30; i++) {
      await load();
    }
    expect(attempted, contains(LoadLadder.rungAdaptiveUri),
        reason: 'anak adaptif tidak pernah dicoba lagi sesudah demosi — '
            'kebuntuan tangga lengket masih hidup');
    expect(l.stickyRung, LoadLadder.rungAdaptiveUri,
        reason: 'tangga tidak pulih ke adaptif di dalam sesi yang sama');
  });

  test(
      'anti-thrash: adaptif sungguh mati → percobaan ulang terbatas '
      '(jadwal backoff), pemuatan tetap sehat via muxed', () async {
    final l = ladder();
    var adaptiveAttempts = 0;
    Future<int> load() => l.run(attempt: (rung) async {
          if (rung == LoadLadder.rungAdaptiveUri) {
            adaptiveAttempts++;
            throw StateError('403 jendela');
          }
        });

    // 100 pemuatan: yang pertama mendemosi (1 percobaan adaptif), lalu
    // masa percobaan pada kemenangan ke-5, 10, 20, 40 (backoff ganda,
    // batas 40) → total percobaan adaptif sesudah demosi ≤ 4.
    for (var i = 0; i < 100; i++) {
      expect(await load(), LoadLadder.rungMuxedUri);
    }
    expect(l.stickyRung, LoadLadder.rungMuxedUri);
    expect(adaptiveAttempts, 5,
        reason: 'percobaan adaptif harus tepat 1 (demosi) + 4 (masa '
            'percobaan terjadwal 5/10/20/40) dalam 100 pemuatan; dapat '
            '$adaptiveAttempts');
  });

  test(
      'bentuk urutan masa percobaan: adaptif sekali di depan, lalu '
      'rotasi pemenang seperti tangga biasa', () async {
    final l = ladder();
    var adaptiveDown = true;
    final attempted = <int>[];
    Future<int> load() => l.run(attempt: (rung) async {
          attempted.add(rung);
          if (rung == LoadLadder.rungAdaptiveUri && adaptiveDown) {
            throw StateError('403 jendela');
          }
        });

    await load(); // demosi ke muxed
    expect(l.stickyRung, LoadLadder.rungMuxedUri);
    // 5 kemenangan di muxed memenuhi ambang awal → run berikutnya percobaan.
    for (var i = 0; i < 5; i++) {
      await load();
    }
    attempted.clear();
    // Percobaan: adaptif gugur lagi → jatuh ke pemenang (muxed) pada run
    // yang sama; adaptif dicoba tepat SATU kali, di depan.
    expect(await load(), LoadLadder.rungMuxedUri);
    expect(attempted, [LoadLadder.rungAdaptiveUri, LoadLadder.rungMuxedUri]);
    expect(l.stickyRung, LoadLadder.rungMuxedUri);
  });

  test(
      'pemulihan mereset backoff: demosi kedua mendapat ambang awal lagi, '
      'bukan ambang ganda warisan', () async {
    final l = ladder();
    var adaptiveDown = true;
    var adaptiveAttempts = 0;
    Future<int> load() => l.run(attempt: (rung) async {
          if (rung == LoadLadder.rungAdaptiveUri) {
            adaptiveAttempts++;
            if (adaptiveDown) throw StateError('403 jendela');
          }
        });

    await load(); // demosi (percobaan adaptif #1)
    // Biarkan DUA masa percobaan gagal (ambang 5 lalu 10) agar backoff
    // terbukti sudah berganda sebelum pemulihan.
    for (var i = 0; i < 5; i++) {
      await load();
    }
    await load(); // percobaan #2 gugur → ambang jadi 10
    for (var i = 0; i < 10; i++) {
      await load();
    }
    await load(); // percobaan #3 gugur → ambang jadi 20
    expect(adaptiveAttempts, 3);

    // Adaptif pulih: masa percobaan berikutnya (sesudah 20 kemenangan)
    // berhasil → tangga kembali ke adaptif.
    adaptiveDown = false;
    for (var i = 0; i < 20; i++) {
      await load();
    }
    await load(); // percobaan #4 menang
    expect(l.stickyRung, LoadLadder.rungAdaptiveUri);
    expect(adaptiveAttempts, 4);

    // Demosi KEDUA: masa percobaan harus datang sesudah ambang AWAL (5
    // kemenangan), bukan 40 (ganda warisan bila backoff tidak direset).
    adaptiveDown = true;
    await load(); // demosi kedua (percobaan adaptif #5)
    expect(l.stickyRung, LoadLadder.rungMuxedUri);
    adaptiveDown = false;
    final before = adaptiveAttempts;
    for (var i = 0; i < 5; i++) {
      await load();
    }
    await load(); // run ke-6 sesudah demosi = masa percobaan bila ambang 5
    expect(adaptiveAttempts, before + 1,
        reason: 'masa percobaan demosi kedua tidak datang pada ambang '
            'awal — backoff warisan tidak direset oleh pemulihan');
    expect(l.stickyRung, LoadLadder.rungAdaptiveUri);
  });
}
