import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:clai/ui/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ronde 8057 FIX B — sampul Player: varian besar gagal muat menukar
/// SEKALI ke varian 544 (guc) / hqdefault (ytimg); kedua-duanya gagal
/// → placeholder. Jaringan dimock lewat
/// [debugNetworkImageHttpClientProvider] (jalur resmi NetworkImage di
/// mode debug/uji): URL primer dibalas 404, URL cadangan dibalas PNG
/// 1x1 yang sah, dan daftar URL yang benar-benar diminta dicatat agar
/// urutan primer → cadangan bisa dipastikan, bukan sekadar ditebak
/// dari tampilan akhir.
final _pngBytes = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+ip1sAAAAASUVORK5CYII=');

class _MockHeaders extends Fake implements HttpHeaders {
  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) {}
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}
  @override
  void forEach(void Function(String name, List<String> values) action) {}
}

class _MockResponse extends Fake implements HttpClientResponse {
  _MockResponse({required this.statusCode, this.bytes = const <int>[]});

  @override
  final int statusCode;
  final List<int> bytes;

  @override
  int get contentLength => bytes.length;

  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;

  @override
  StreamSubscription<List<int>> listen(void Function(List<int> event)? onData,
      {Function? onError, void Function()? onDone, bool? cancelOnError}) {
    return Stream<List<int>>.fromIterable(<List<int>>[bytes]).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  Future<E> drain<E>([E? futureError]) async {
    await Stream<List<int>>.fromIterable(<List<int>>[bytes]).drain<void>();
    return futureError as E;
  }
}

class _MockRequest extends Fake implements HttpClientRequest {
  _MockRequest(this._response);
  final _MockResponse _response;

  @override
  HttpHeaders get headers => _MockHeaders();

  @override
  Future<HttpClientResponse> close() async => _response;
}

class _MockClient extends Fake implements HttpClient {
  _MockClient(this._handler);
  final _MockResponse Function(Uri url) _handler;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async =>
      _MockRequest(_handler(url));
}

void main() {
  final requested = <String>[];

  void installMock(_MockResponse Function(String url) respond) {
    debugNetworkImageHttpClientProvider = () => _MockClient((url) {
          requested.add(url.toString());
          return respond(url.toString());
        });
  }

  Widget wrap(Widget child, {double dpr = 3}) => MaterialApp(
        home: Scaffold(
          body: Center(
            child: Builder(
              builder: (ctx) => MediaQuery(
                data: MediaQuery.of(ctx).copyWith(devicePixelRatio: dpr),
                child: child,
              ),
            ),
          ),
        ),
      );

  Future<void> settle(WidgetTester tester) async {
    // Selang-seling pump (zona async-palsu) dan runAsync: decode codec
    // gambar adalah kerja async NYATA mesin, yang hanya maju di runAsync.
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 25));
      await tester
          .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
    }
  }

  /// Provider debug lukis WAJIB dikembalikan di DALAM badan uji:
  /// pengikat memeriksa invarian variabel debug sebelum tearDown paket
  /// test berjalan, jadi menyetelnya di tearDown sudah terlambat.
  void releaseMock() {
    debugNetworkImageHttpClientProvider = null;
  }

  setUp(() {
    requested.clear();
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  });

  tearDown(() {
    debugNetworkImageHttpClientProvider = null;
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  });

  testWidgets(
      'CoverArt besar (guc): primer w1080 404 → cadangan w544 tampil',
      (tester) async {
    installMock((url) => url.contains('w1080')
        ? _MockResponse(statusCode: 404)
        : url.contains('w544')
            ? _MockResponse(statusCode: 200, bytes: _pngBytes)
            : _MockResponse(statusCode: 404));
    await tester.pumpWidget(wrap(const CoverArt(
      url: 'https://lh3.googleusercontent.com/coverA=w544-h544-l90-rj',
      size: 200,
      label: 'Alpha',
    )));
    await settle(tester);
    releaseMock();
    expect(
      requested,
      containsAllInOrder([
        'https://lh3.googleusercontent.com/coverA=w1080-h1080-l90-rj',
        'https://lh3.googleusercontent.com/coverA=w544-h544-l90-rj',
      ]),
      reason: 'urutan muat harus primer 1080 dulu, lalu tepat satu cadangan 544',
    );
    expect(find.byType(RawImage), findsOneWidget,
        reason: 'gambar cadangan harus benar-benar ter-decode & tampil');
    expect(find.text('A'), findsNothing,
        reason: 'placeholder inisial tidak boleh tampil sesudah cadangan berhasil');
  });

  testWidgets(
      'CoverArt besar (ytimg): maxresdefault 404 → hqdefault tampil',
      (tester) async {
    installMock((url) => url.contains('maxresdefault')
        ? _MockResponse(statusCode: 404)
        : url.contains('hqdefault')
            ? _MockResponse(statusCode: 200, bytes: _pngBytes)
            : _MockResponse(statusCode: 404));
    await tester.pumpWidget(wrap(const CoverArt(
      url: 'https://i.ytimg.com/vi/VIDB/hqdefault.jpg',
      size: 200,
      label: 'Beta',
    )));
    await settle(tester);
    releaseMock();
    expect(
      requested,
      containsAllInOrder([
        'https://i.ytimg.com/vi/VIDB/maxresdefault.jpg',
        'https://i.ytimg.com/vi/VIDB/hqdefault.jpg',
      ]),
    );
    expect(find.byType(RawImage), findsOneWidget);
    expect(find.text('B'), findsNothing);
  });

  testWidgets('primer DAN cadangan gagal → placeholder, tanpa putaran ulang',
      (tester) async {
    installMock((_) => _MockResponse(statusCode: 404));
    await tester.pumpWidget(wrap(const CoverArt(
      url: 'https://lh3.googleusercontent.com/coverC=w544-h544-l90-rj',
      size: 200,
      label: 'Gamma',
    )));
    await settle(tester);
    releaseMock();
    expect(find.byType(RawImage), findsNothing);
    expect(find.text('G'), findsOneWidget,
        reason: 'placeholder inisial adalah keadaan akhir bila keduanya gagal');
    expect(
      requested.where((u) => u.contains('coverC')).length,
      lessThanOrEqualTo(2),
      reason: 'maksimum dua percobaan: primer + satu cadangan, tidak ada loop',
    );
  });

  testWidgets('CoverArt kecil (ember ≤ 544): TIDAK ada cadangan',
      (tester) async {
    installMock((_) => _MockResponse(statusCode: 404));
    await tester.pumpWidget(wrap(
      const CoverArt(
        url: 'https://lh3.googleusercontent.com/coverD=w544-h544-l90-rj',
        size: 48,
        label: 'Delta',
      ),
      dpr: 1,
    ));
    await settle(tester);
    releaseMock();
    expect(find.text('D'), findsOneWidget);
    expect(requested, ['https://lh3.googleusercontent.com/coverD=w200-h200-l90-rj'],
        reason: 'permukaan kecil tetap perilaku lama: satu muat w200, placeholder pada error');
  });

  testWidgets(
      'FallbackArtworkImage: ganti primaryUrl mereset keadaan cadangan',
      (tester) async {
    installMock((url) {
      if (url.endsWith('/p1.jpg') || url.endsWith('/f2.jpg')) {
        return _MockResponse(statusCode: 404);
      }
      return _MockResponse(statusCode: 200, bytes: _pngBytes);
    });
    Widget tree(String primary, String fallback) => wrap(FallbackArtworkImage(
          primaryUrl: primary,
          fallbackUrl: fallback,
          width: 100,
          height: 100,
          cacheWidth: 100,
          placeholder: const Text('PH'),
        ));
    await tester.pumpWidget(tree(
        'https://example.invalid/p1.jpg', 'https://example.invalid/f1.jpg'));
    await settle(tester);
    expect(find.byType(RawImage), findsOneWidget,
        reason: 'p1 gagal, f1 (cadangan) tampil');
    expect(requested,
        containsAllInOrder(['https://example.invalid/p1.jpg', 'https://example.invalid/f1.jpg']));

    requested.clear();
    // Primary baru yang SEHAT: bila keadaan cadangan lama bocor, widget
    // akan langsung meminta f2 (yang 404) dan berakhir di placeholder.
    await tester.pumpWidget(tree(
        'https://example.invalid/p2.jpg', 'https://example.invalid/f2.jpg'));
    await settle(tester);
    releaseMock();
    expect(requested, contains('https://example.invalid/p2.jpg'),
        reason: 'primary baru harus diminta dari keadaan bersih');
    expect(requested, isNot(contains('https://example.invalid/f2.jpg')));
    expect(find.byType(RawImage), findsOneWidget);
    expect(find.text('PH'), findsNothing);
  });
}
