import 'package:clai/core/clai_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// v4.4 butir 3a — set ikon DS: setiap glif punya jalur yang sah, berada di
/// dalam kisi 24 (toleransi ujung coretan), dan ClaiIcon me-render tanpa error.
void main() {
  final glyphs = <String, ClaiIconData>{
    'home': ClaiIcons.home, 'homeFill': ClaiIcons.homeFill,
    'search': ClaiIcons.search, 'library': ClaiIcons.library, 'libraryFill': ClaiIcons.libraryFill,
    'play': ClaiIcons.play, 'pause': ClaiIcons.pause, 'next': ClaiIcons.next, 'prev': ClaiIcons.prev,
    'shuffle': ClaiIcons.shuffle, 'repeat': ClaiIcons.repeat, 'repeatOne': ClaiIcons.repeatOne,
    'heart': ClaiIcons.heart, 'heartFill': ClaiIcons.heartFill,
    'queue': ClaiIcons.queue, 'lyrics': ClaiIcons.lyrics, 'moon': ClaiIcons.moon,
    'download': ClaiIcons.download, 'add': ClaiIcons.add, 'moreVert': ClaiIcons.moreVert,
    'share': ClaiIcons.share, 'radio': ClaiIcons.radio, 'check': ClaiIcons.check,
    'checkCircle': ClaiIcons.checkCircle, 'warning': ClaiIcons.warning, 'info': ClaiIcons.info,
    'settings': ClaiIcons.settings, 'chevronDown': ClaiIcons.chevronDown,
    'chevronRight': ClaiIcons.chevronRight, 'close': ClaiIcons.close, 'infinity': ClaiIcons.infinity,
    'album': ClaiIcons.album, 'person': ClaiIcons.person, 'playlistAdd': ClaiIcons.playlistAdd,
    'dragHandle': ClaiIcons.dragHandle, 'trash': ClaiIcons.trash, 'folder': ClaiIcons.folder,
    'folderOff': ClaiIcons.folderOff, 'history': ClaiIcons.history, 'sort': ClaiIcons.sort,
    'clearAll': ClaiIcons.clearAll, 'shield': ClaiIcons.shield, 'phone': ClaiIcons.phone,
    'battery': ClaiIcons.battery, 'batteryAlert': ClaiIcons.batteryAlert, 'copy': ClaiIcons.copy,
    'external': ClaiIcons.external, 'cloudOff': ClaiIcons.cloudOff, 'musicNote': ClaiIcons.musicNote,
    'musicOff': ClaiIcons.musicOff, 'searchOff': ClaiIcons.searchOff, 'playCircle': ClaiIcons.playCircle,
  };

  test('semua glif katalog memiliki jalur & berada dalam kisi 24', () {
    expect(glyphs.length, greaterThanOrEqualTo(50));
    for (final e in glyphs.entries) {
      final paths = [e.value.stroke, e.value.fill].whereType<Path>();
      expect(paths, isNotEmpty, reason: '${e.key} tanpa jalur');
      for (final p in paths) {
        final b = p.getBounds();
        expect(b.left, greaterThanOrEqualTo(-0.7), reason: '${e.key} keluar kisi kiri: $b');
        expect(b.top, greaterThanOrEqualTo(-0.7), reason: '${e.key} keluar kisi atas: $b');
        expect(b.right, lessThanOrEqualTo(24.7), reason: '${e.key} keluar kisi kanan: $b');
        expect(b.bottom, lessThanOrEqualTo(24.7), reason: '${e.key} keluar kisi bawah: $b');
        expect(b.width, greaterThan(0), reason: '${e.key} jalur kosong');
        expect(b.height, greaterThan(0), reason: '${e.key} jalur kosong');
      }
    }
  });

  testWidgets('ClaiIcon me-render semua glif dalam grid tanpa exception', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: GridView.count(
          crossAxisCount: 6,
          children: [
            for (final g in glyphs.values)
              Center(child: ClaiIcon(g, size: 32, color: const Color(0xFFF4F6F1))),
          ],
        ),
      ),
    ));
    expect(tester.takeException(), isNull);
  });
}
