import 'package:clai/core/clai_icons.dart';
import 'package:clai/domain/models.dart';
import 'package:clai/ui/queue_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Uji widget cacat v4-3 pada widget ASLI yang dipakai layar Antrian
/// (QueueSectionList): geser pada badan baris harus menggulir daftar luar,
/// seret hanya boleh mulai dari pegangan ≡.
Track mkTrack(int i) => Track(
      key: TrackKey('ytmusic', 'vid$i'),
      title: 'Trek $i',
      artistNames: 'Artis $i',
      playableRef: 'vid$i',
    );

Widget harness({
  required List<Track> items,
  required void Function(int from, int to) onReorder,
}) {
  return MaterialApp(
    home: Scaffold(
      body: ListView(children: [
        QueueSectionList(
          section: 'manual',
          items: items,
          itemIndices: [for (var i = 0; i < items.length; i++) i],
          rowBuilder: (ctx, t, engineIndex, handle) => SizedBox(
            height: 56,
            child: Row(children: [Expanded(child: Text(t.title)), handle]),
          ),
          onReorder: onReorder,
          onDismissed: (_, __) {},
        ),
        const SizedBox(height: 400),
      ]),
    ),
  );
}

void main() {
  testWidgets('geser vertikal pada badan baris menggulir daftar; urutan tidak berubah',
      (tester) async {
    final items = [for (var i = 0; i < 12; i++) mkTrack(i)];
    var reorderCalls = 0;
    await tester.pumpWidget(harness(items: items, onReorder: (o, n) => reorderCalls++));
    final before = tester.getTopLeft(find.text('Trek 8')).dy;
    await tester.drag(find.text('Trek 2'), const Offset(0, -240));
    await tester.pumpAndSettle();
    expect(reorderCalls, 0, reason: 'badan baris tidak boleh memulai seret-urut');
    final after = tester.getTopLeft(find.text('Trek 8')).dy;
    expect(after, lessThan(before - 100),
        reason: 'daftar luar benar-benar bergeser ke atas');
    expect(items.map((t) => t.title).toList(),
        [for (var i = 0; i < 12; i++) 'Trek $i'], reason: 'urutan utuh');
  });

  testWidgets('seret dari pegangan ≡ mengubah urutan', (tester) async {
    final items = [for (var i = 0; i < 10; i++) mkTrack(i)];
    int? from, to;
    await tester.pumpWidget(harness(items: items, onReorder: (o, n) {
      from = o;
      to = n;
    }));
    // v4.4: pegangan kini glif DS (ClaiIcon dragHandle), bukan Icons.drag_handle.
    await tester.drag(
        find.byWidgetPredicate((w) => w is ClaiIcon && w.data == ClaiIcons.dragHandle).first,
        const Offset(0, 130));
    await tester.pumpAndSettle();
    expect(from, 0);
    expect(to, isNotNull);
    expect(to!, greaterThan(0), reason: 'trek pertama berpindah ke bawah');
  });
}
