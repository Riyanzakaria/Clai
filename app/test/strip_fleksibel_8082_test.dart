// Ronde 8082 (DS v5.3 §13.1, koreksi vonis HP pemilik 23 Nov 01:51
// atas aturan global 8080/8081): strip inset atas FLEKSIBEL mengikuti
// permukaan atas halaman yang dibuka. Tes ini mengunci matriks
// keputusan murni claiStripFollowsAmbient + perilaku pengamat rute
// AboveRootRouteObserver yang menggerakkannya.
//
// Bukti bangku yang mendasari matriks (build 8081, dua sampul kontras,
// baris pertama halaman di bawah inset, y=75–130):
//   Beranda  (35,38,30) → (43,38,36)   ambient (dosis pahlawan)
//   Cari     (20,21,21) → (23,21,23)   ambient (dosis tugas 40%)
//   Koleksi  (20,21,21) → (23,21,23)   ambient (dosis tugas 40%)
// Ketiga tab berganti mengikuti sampul → akar tab = mode ambient.
import 'package:clai/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

bool _strip({
  int tab = 0,
  bool shell = false,
  bool root = false,
  bool player = false,
}) =>
    claiStripFollowsAmbient(
      tab: tab,
      shellRoutePushed: shell,
      rootRouteCovered: root,
      playerSheetOpen: player,
    );

MaterialPageRoute<void> _route() =>
    MaterialPageRoute<void>(builder: (_) => const SizedBox());

void main() {
  group('claiStripFollowsAmbient — matriks DS v5.3 §13.1', () {
    test('akar tab: ketiga tab ambient (terbukti bangku 8082)', () {
      for (final tab in [0, 1, 2]) {
        expect(_strip(tab: tab), isTrue, reason: 'tab $tab');
      }
    });

    test('rute terdorong cangkang (Pengaturan/Selera/sub-halaman) = dasar',
        () {
      for (final tab in [0, 1, 2]) {
        expect(_strip(tab: tab, shell: true), isFalse, reason: 'tab $tab');
      }
    });

    test('lembar/dialog di navigator akar = dasar', () {
      expect(_strip(root: true), isFalse);
      expect(_strip(tab: 2, root: true), isFalse);
    });

    test('Player terbuka = ambient, menang atas penutup akar lain', () {
      expect(_strip(player: true), isTrue);
      expect(_strip(player: true, root: true), isTrue);
      expect(_strip(player: true, shell: true), isTrue);
    });

    test('tab di luar jangkauan = dasar (bawaan aman)', () {
      expect(_strip(tab: -1), isFalse);
      expect(_strip(tab: 3), isFalse);
    });
  });

  group('AboveRootRouteObserver', () {
    test('rute pertama tidak menutup; dorong di atasnya menutup; pop '
        'membuka lagi', () {
      final covered = ValueNotifier<bool>(false);
      final obs = AboveRootRouteObserver(covered);
      final root = _route();
      final pushed = _route();
      obs.didPush(root, null);
      expect(covered.value, isFalse);
      obs.didPush(pushed, root);
      expect(covered.value, isTrue);
      obs.didPop(pushed, root);
      expect(covered.value, isFalse);
    });

    test('dua rute menumpuk: satu pop belum membuka', () {
      final covered = ValueNotifier<bool>(false);
      final obs = AboveRootRouteObserver(covered);
      final root = _route();
      final a = _route();
      final b = _route();
      obs.didPush(root, null);
      obs.didPush(a, root);
      obs.didPush(b, a);
      obs.didPop(b, a);
      expect(covered.value, isTrue);
      obs.didRemove(a, root);
      expect(covered.value, isFalse);
    });

    test('replace rute penutup mempertahankan keadaan tertutup', () {
      final covered = ValueNotifier<bool>(false);
      final obs = AboveRootRouteObserver(covered);
      final root = _route();
      final a = _route();
      final b = _route();
      obs.didPush(root, null);
      obs.didPush(a, root);
      obs.didReplace(newRoute: b, oldRoute: a);
      expect(covered.value, isTrue);
      obs.didPop(b, root);
      expect(covered.value, isFalse);
    });
  });
}
