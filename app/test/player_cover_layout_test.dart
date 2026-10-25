import 'package:clai/ui/player_sheet.dart';
import 'package:flutter_test/flutter_test.dart';

/// v4.4 butir 1 — sampul Player elastis. Kontrak desain:
/// (a) layar mainstream: kolom total TIDAK melebihi ruang (definisi luapan 23px
///     di perangkat pemilik) dan sampul sebesar mungkin;
/// (b) layar ekstrem: sampul berhenti di lantai 120 dan widget menggulir —
///     luapan RenderFlex tetap mustahil karena kolom berada dalam gulir.
void main() {
  group('layar mainstream — muat penuh tanpa luapan', () {
    final heights = [700.0, 760.0, 833.0, 880.0];
    final scales = [1.0, 1.15, 1.3];
    for (final h in heights) {
      for (final ts in scales) {
        for (final ap in [true, false]) {
          test('h=$h ts=$ts autoplay=$ap', () {
            final l = playerCoverLayout(maxWidth: 371, maxHeight: h, textScale: ts, autoplay: ap);
            expect(l.cover, greaterThanOrEqualTo(120));
            expect(l.cover, lessThanOrEqualTo(371));
            expect(l.contentHeight, lessThanOrEqualTo(h + 0.001),
                reason: 'kolom ${l.contentHeight.toStringAsFixed(1)}dp > ruang ${h}dp');
            expect(l.contentHeight + l.spacer, lessThanOrEqualTo(h + 0.001));
          });
        }
      }
    }
  });

  group('layar pendek — lantai sampul + gulir, bukan luapan', () {
    final heights = [520.0, 600.0, 640.0];
    final scales = [1.0, 1.3];
    for (final h in heights) {
      for (final ts in scales) {
        test('h=$h ts=$ts autoplay=true', () {
          final l = playerCoverLayout(maxWidth: 371, maxHeight: h, textScale: ts, autoplay: true);
          expect(l.cover, greaterThanOrEqualTo(120), reason: 'sampul tidak boleh hilang');
          expect(l.spacer, 0, reason: 'tidak ada spacer paksa pada mode gulir');
          expect(l.contentHeight <= h + 0.001 || l.cover == 120, isTrue,
              reason: 'melebihi ruang hanya boleh saat sampul di lantai (gulir mengambil alih)');
        });
      }
    }
  });

  test('layar tinggi: sampul selebar konten penuh (PRD 5.5 utuh)', () {
    // Sapuan D-25: judul Player kini display 28 sesuai DS 6.9 (dulu 26) —
    // blok judul lebih tinggi ±4,7 dp sehingga pada h=833 sampul menyerahkan
    // ruang itu; selebar konten penuh tercapai lagi pada layar lebih tinggi.
    final tall = playerCoverLayout(maxWidth: 371, maxHeight: 900, textScale: 1.0, autoplay: true);
    expect(tall.cover, 371);
    expect(tall.contentHeight + tall.spacer, closeTo(900, 0.001));
    final l = playerCoverLayout(maxWidth: 371, maxHeight: 833, textScale: 1.0, autoplay: true);
    expect(l.cover, greaterThanOrEqualTo(360));
    expect(l.contentHeight + l.spacer, closeTo(833, 0.001));
  });

  test('kasus pemilik (ruang sempit + banner): sampul menyusut, bukan luapan', () {
    final l = playerCoverLayout(maxWidth: 371, maxHeight: 700, textScale: 1.1, autoplay: true);
    expect(l.cover, lessThan(371));
    expect(l.cover, greaterThanOrEqualTo(120));
    expect(l.contentHeight, lessThanOrEqualTo(700.001));
  });

  test('ruang ekstrem: sampul berhenti di lantai 120', () {
    final l = playerCoverLayout(maxWidth: 371, maxHeight: 470, textScale: 1.3, autoplay: true);
    expect(l.cover, 120);
    expect(l.spacer, 0);
  });

  test('tanpa banner Putar Otomatis: sampul lebih besar', () {
    final withAp = playerCoverLayout(maxWidth: 371, maxHeight: 720, textScale: 1.0, autoplay: true);
    final noAp = playerCoverLayout(maxWidth: 371, maxHeight: 720, textScale: 1.0, autoplay: false);
    expect(noAp.cover, greaterThan(withAp.cover));
  });
}
