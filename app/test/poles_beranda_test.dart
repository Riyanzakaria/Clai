import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:clai/core/display_text.dart';
import 'package:clai/domain/models.dart';
import 'package:clai/providers/ytmusic/innertube.dart';
import 'package:clai/ui/cover_accent_glow.dart';
import 'package:clai/ui/home_screen.dart';
import 'package:clai/ui/widgets.dart';

/// Ronde Poles Beranda (keputusan riyan 24 Okt 2026) — uji per butir.
void main() {
group('butir 3 — cleanDisplayTitle', () {
test('awalan kurung siku pengunggah dibuang', () {
expect(cleanDisplayTitle('[AIJING 아이찡] A2O LITE - NEON (아이찡)'),
startsWith('A2O LITE - NEON'));
});
test('kurung siku penuh dibuang', () {
expect(cleanDisplayTitle('\u3010공식\u3011NewJeans - Hype Boy'), 'NewJeans - Hype Boy');
});
test('awalan kurung berurutan dibuang semua', () {
expect(cleanDisplayTitle('[LIVE][HD] Lagu Bagus'), 'Lagu Bagus');
});
test('judul bersih tidak berubah', () {
expect(cleanDisplayTitle('Do I Wanna Know?'), 'Do I Wanna Know?');
});
test('kurung biasa di awal judul sah TIDAK disentuh', () {
expect(cleanDisplayTitle("(Don't Fear) The Reaper"),
"(Don't Fear) The Reaper");
});
test('kurung di tengah judul tidak disentuh', () {
expect(cleanDisplayTitle('Lagu [Versi Akustik] Lama'),
'Lagu [Versi Akustik] Lama');
});
test('judul yang seluruhnya kurung tidak menjadi kosong', () {
expect(cleanDisplayTitle('[Hanya Ini]'), '[Hanya Ini]');
});
test('kurung tak tertutup dibiarkan', () {
expect(cleanDisplayTitle('[Rusak Tanpa Tutup'), '[Rusak Tanpa Tutup');
});
});

group('butir 3 — cleanDisplayArtist', () {
test('segmen views dibuang, kanal tetap', () {
expect(cleanDisplayArtist('sarivkzx • 4K views'), 'sarivkzx');
// Format "plays" tangga lagu YTM (temuan emulator: Pilihan Cepat
// menampilkan "Bruno Mars • 433M plays" mentah sebelum pola ini).
expect(cleanDisplayArtist('Bruno Mars • 433M plays'), 'Bruno Mars');
expect(cleanDisplayArtist('Lewis Capaldi • 1.2B plays'), 'Lewis Capaldi');
});
test('segmen ago di depan dibuang, kanal tetap', () {
expect(cleanDisplayArtist('3d ago • MBC Radio'), 'MBC Radio');
});
test('byline artis • album • tahun sah tidak berubah', () {
expect(cleanDisplayArtist('Rihanna • Unapologetic • 2012'),
'Rihanna • Unapologetic • 2012');
});
test('semua segmen metadata → kosong (baris artis disembunyikan)', () {
expect(cleanDisplayArtist('16M views • 2 weeks ago'), '');
});
test('bentuk umur lain: minggu bahasa Inggris & streamed', () {
expect(isUploadMetaSegment('2 weeks ago'), isTrue);
expect(isUploadMetaSegment('Streamed 5 days ago'), isTrue);
expect(isUploadMetaSegment('3 hari yang lalu'), isTrue);
expect(isUploadMetaSegment('1,2 rb x ditonton'), isTrue);
expect(isUploadMetaSegment('Arctic Monkeys'), isFalse);
});
});

group('butir 2 — bgReminderVisible', () {
test('belum pernah memutar → tidak tampil', () {
expect(
bgReminderVisible(
everPlayed: false,
dismissed: false,
notifGranted: false,
batteryGranted: false),
isFalse);
});
test('sudah ditolak (Nanti saja) → tidak tampil lagi', () {
expect(
bgReminderVisible(
everPlayed: true,
dismissed: true,
notifGranted: false,
batteryGranted: false),
isFalse);
});
test('pernah memutar + izin belum lengkap → tampil', () {
expect(
bgReminderVisible(
everPlayed: true,
dismissed: false,
notifGranted: true,
batteryGranted: false),
isTrue);
});
test('izin lengkap → tidak tampil (kondisi berubah)', () {
expect(
bgReminderVisible(
everPlayed: true,
dismissed: false,
notifGranted: true,
batteryGranted: true),
isFalse);
});
});

group('butir 5 — tonalIsNeutral', () {
test('abu monokrom terdeteksi netral', () {
expect(tonalIsNeutral(const Color(0xFF2A2A2E)), isTrue);
expect(tonalIsNeutral(const Color(0xFF101014)), isTrue);
});
test('tona berona (hijau NEON / merah muda) tidak netral', () {
expect(tonalIsNeutral(const Color(0xFF3E5A1E)), isFalse);
expect(tonalIsNeutral(const Color(0xFF6E2A3C)), isFalse);
});
});

group('cacat B — durasi halaman artis (fixture payload asli)', () {
final artistJson = jsonDecode(
File('test/fixtures/browse_artist_topsongs.json').readAsStringSync());
final songsJson = jsonDecode(File(
'test/fixtures/browse_artist_songs_playlist.json')
.readAsStringSync());

test('item artis memang TIDAK membawa durasi dari sumber', () {
final tracks = collectTracks(artistJson);
expect(tracks, isNotEmpty);
expect(tracks.every((t) => t.duration == null), isTrue,
reason: 'akar cacat: kolom artis berisi jumlah putar, bukan durasi');
});

test('tautan playlist lagu teratas ditemukan dari judul rak', () {
expect(topSongsPlaylistId(artistJson),
'VLOLAK5uy_kwQGu4I_SWeaJUKQePnuMZW9YyZsrus58');
});

test('fillDurations mengisi durasi dari item playlist (3:57 dst.)', () {
final tracks = collectTracks(artistJson);
final source = collectTracks(songsJson);
expect(source.any((t) => t.duration != null), isTrue);
final filled = fillDurations(tracks, source);
expect(filled.every((t) => t.duration != null), isTrue);
expect(filled.first.duration, const Duration(minutes: 3, seconds: 57));
});
});

group('butir E — Buka Artis untuk trek tanpa ID', () {
Track mk({List<String> ids = const [], String names = ''}) => Track(
key: const TrackKey('ytmusic', 'vidx'),
title: 'Lagu',
artistNames: names,
artistIds: ids,
playableRef: 'vidx');

test('tampil bila ada ID, tampil bila hanya nama, hilang bila keduanya kosong', () {
expect(canOpenArtist(mk(ids: ['UC1'], names: 'Siapa')), isTrue);
expect(canOpenArtist(mk(names: 'Raissa Anggiani')), isTrue);
expect(canOpenArtist(mk(names: '   ')), isFalse);
expect(canOpenArtist(mk()), isFalse);
});

test('nama utama dipotong dari byline & kolaborasi', () {
expect(primaryArtistName('Arash Buana & Raissa Anggiani'), 'Arash Buana');
expect(primaryArtistName('Raissa Anggiani • Album • 2022'), 'Raissa Anggiani');
expect(primaryArtistName('A feat. B'), 'A');
// Label kategori byline YTM bukan nama artis (kasus emulator 2007:
// trek hasil cari ber-byline literal "Song" — Buka Artis tak boleh
// menyelesaikan ke artis acak untuk nama ini).
expect(primaryArtistName('Song'), '');
expect(primaryArtistName('Video'), '');
expect(canOpenArtist(mk(names: 'Song')), isFalse);
});

test('pickArtistForName: persis didahulukan, lalu pertama, kosong → null', () {
const a = Artist(providerId: 'ytmusic', id: 'UCa', name: 'Raissa Anggiani');
const b = Artist(providerId: 'ytmusic', id: 'UCb', name: 'Raissa Anggiani Karaoke');
expect(pickArtistForName([b, a], 'raissa anggiani')?.id, 'UCa');
expect(pickArtistForName([b], 'Tidak Ada')?.id, 'UCb');
expect(pickArtistForName(const [], 'X'), isNull);
});
});

group('cacat C — BoundedDropdown tidak meremas judul baris', () {
testWidgets('judul tetap lebar wajar di layar sempit dengan item nilai panjang', (tester) async {
tester.view.physicalSize = const Size(320, 640);
tester.view.devicePixelRatio = 1.0;
addTearDown(tester.view.reset);
await tester.pumpWidget(const MaterialApp(home: Scaffold(body: ListTile(
title: Text('Streaming quality'),
subtitle: Text('High · best available'),
trailing: BoundedDropdown<String>(
value: 'high',
items: [
DropdownMenuItem(value: 'high', child: Text('High · highest available · Opus ±256 kbps')),
DropdownMenuItem(value: 'low', child: Text('Low · data saver · up to 70 kbps')),
],
onChanged: null,
),
))));
final titleSize = tester.getSize(find.text('Streaming quality'));
expect(titleSize.width, greaterThan(80),
reason: 'judul tidak boleh kolaps ke ±1 huruf (cacat C)');
expect(tester.takeException(), isNull);
});
});
}
