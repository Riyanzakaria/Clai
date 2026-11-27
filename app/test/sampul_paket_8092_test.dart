import 'dart:async';
import 'dart:io';

import 'package:clai/core/artwork.dart';
import 'package:clai/core/clai_icons.dart';
import 'package:clai/services/observability.dart';
import 'package:clai/ui/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ronde 8092 paket SAMPUL (S1–S4):
/// 1. Registri murni — gerbang log markFailed, evictOne, evictAllFailed.
/// 2. CoverArt — placeholder error (cloudOff) BERBEDA dari placeholder
///    memuat (inisial); kegagalan dicatat sekali ke Log insiden (S3).
/// 3. Ketuk placeholder error → percobaan baru benar-benar terbit (S2/S1).
/// 4. FallbackArtworkImage — evict mereset kait cadangan (S4).
///
/// Jaringan dimock lewat [debugNetworkImageHttpClientProvider] (pola
/// yang sama dengan sampul_cadangan_8057_test): 404 = gagal, dan URL
/// "pending" tidak pernah dijawab (Completer yang tidak selesai)
/// supaya keadaan SEDANG MEMUAT bisa diamati secara deterministik —
/// tanpa itu, keadaan memuat vs error tidak bisa dibedakan waktunya.
class _MockHeaders extends Fake implements HttpHeaders {
  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) {}
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}
  @override
  void forEach(void Function(String name, List<String> values) action) {}
}

class _MockResponse extends Fake implements HttpClientResponse {
  _MockResponse({required this.statusCode});

  @override
  final int statusCode;
  final List<int> bytes = const <int>[];

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
  final FutureOr<_MockResponse> Function(Uri url) _handler;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async =>
      _MockRequest(await _handler(url));
}

void main() {
  final requested = <String>[];
  final registry = FailedArtworkRegistry.instance;

  void installMock(FutureOr<_MockResponse> Function(String url) respond) {
    debugNetworkImageHttpClientProvider = () => _MockClient((url) {
          requested.add(url.toString());
          return respond(url.toString());
        });
  }

  void releaseMock() {
    debugNetworkImageHttpClientProvider = null;
  }

  Widget wrap(Widget child, {double dpr = 1}) => MaterialApp(
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
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 25));
      await tester
          .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
    }
  }

  Finder cloudOff() => find.byWidgetPredicate(
      (w) => w is ClaiIcon && w.data == ClaiIcons.cloudOff);

  setUp(() {
    requested.clear();
    registry.resetForTesting();
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  });

  tearDown(() {
    debugNetworkImageHttpClientProvider = null;
    registry.resetForTesting();
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  });

  testWidgets('1. registri: gerbang log, evictOne, evictAllFailed',
      (tester) async {
    const a = 'https://reg.invalid/a.jpg';
    const b = 'https://reg.invalid/b.jpg';
    const c = 'https://reg.invalid/c.jpg';

    expect(registry.markFailed(a), isTrue,
        reason: 'kegagalan pertama = satu-satunya yang boleh masuk log');
    expect(registry.markFailed(a), isFalse,
        reason: 'kegagalan kedua URL sama dalam satu sesi ditahan gerbang');
    expect(registry.isFailed(a), isTrue);

    registry.evictOne(a);
    expect(registry.isFailed(a), isFalse,
        reason: 'evictOne menghapus dari daftar gagal');
    expect(registry.markFailed(a), isFalse,
        reason: 'evict TIDAK menghapus catatan log: gagal lagi sesudah '
            'evict tetap tidak dicatat dua kali sesi ini');

    registry.markFailed(b);
    registry.markFailed(c);
    expect(registry.failedUrls, containsAll(<String>[a, b, c]));
    registry.evictAllFailed();
    expect(registry.failedUrls, isEmpty,
        reason: 'evictAllFailed mengosongkan daftar gagal');
  });

  testWidgets(
      '2. CoverArt: placeholder error BERBEDA dari placeholder memuat + log S3',
      (tester) async {
    // (a) Placeholder MEMUAT adalah inisial di surface2 — ditunjukkan
    // oleh CoverArt tanpa URL (widget placeholder yang sama persis
    // dengan yang dipakai loadingBuilder).
    await tester.pumpWidget(wrap(const CoverArt(url: null, size: 48, label: 'Lagu')));
    await tester.pump();
    expect(find.text('L'), findsOneWidget,
        reason: 'placeholder memuat = inisial label');
    expect(cloudOff(), findsNothing,
        reason: 'ikon error tidak boleh tampil pada placeholder memuat');

    // (b) Keadaan SEDANG memuat sungguhan: permintaan tidak pernah
    // dijawab → ikon error tetap tidak tampil.
    debugNetworkImageHttpClientProvider = () => _PendingClient(requested);
    await tester.pumpWidget(wrap(const CoverArt(
      url: 'https://pending.invalid/cover.jpg',
      size: 48,
      label: 'Lagu',
    )));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 25));
    }
    expect(cloudOff(), findsNothing,
        reason: 'selama muatan belum selesai: bukan keadaan error');
    releaseMock();

    // (c) Kegagalan nyata (404): placeholder error cloudOff tampil,
    // inisial memuat hilang, dan tepat SATU entri log S3 tercatat
    // (host + ember + konteks, tanpa URL penuh).
    installMock((_) => _MockResponse(statusCode: 404));
    const failUrl = 'https://fail.invalid/cover.jpg';
    final logBefore = Observability.instance.entries
        .where((e) => e.kind == 'sampul-gagal')
        .length;
    await tester.pumpWidget(wrap(const CoverArt(
      url: failUrl,
      size: 48,
      label: 'Lagu',
    )));
    await settle(tester);
    releaseMock();
    expect(cloudOff(), findsOneWidget,
        reason: 'keadaan error menampilkan ikon awan-silang');
    expect(find.text('L'), findsNothing,
        reason: 'placeholder memuat (inisial) tidak tampil saat error');
    expect(registry.isFailed(failUrl), isTrue,
        reason: 'URL final tercatat gagal di registri');
    final logs = Observability.instance.entries
        .where((e) => e.kind == 'sampul-gagal')
        .toList();
    expect(logs.length, logBefore + 1,
        reason: 'tepat satu entri sampul-gagal untuk kegagalan ini');
    expect(logs.last.detail, contains('host=fail.invalid'));
    expect(logs.last.detail, contains('ember=200'));
    expect(logs.last.detail, isNot(contains('cover.jpg')),
        reason: 'log tidak membawa URL penuh');
  });

  testWidgets('3. ketuk placeholder error → percobaan baru terbit',
      (tester) async {
    const url = 'https://retry.invalid/cover.jpg';
    var attempts = 0;
    installMock((u) {
      attempts++;
      // Percobaan pertama gagal; percobaan sesudah ketuk dibiarkan
      // menggantung (tidak dijawab) supaya keadaan akhirnya bisa
      // diperiksa tanpa kegagalan kedua menimpa hasil ketuk.
      if (attempts == 1) return _MockResponse(statusCode: 404);
      return Completer<_MockResponse>().future;
    });
    // installMock di atas mengembalikan Future dari Completer untuk
    // percobaan >1 — _MockClient menanganinya via FutureOr.
    await tester.pumpWidget(wrap(const CoverArt(
      url: url,
      size: 48,
      label: 'Lagu',
    )));
    await settle(tester);
    expect(cloudOff(), findsOneWidget);
    expect(registry.isFailed(url), isTrue);
    expect(attempts, 1);

    await tester.tap(find.byType(CoverArt));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 25));
    releaseMock();
    expect(attempts, 2,
        reason: 'ketuk coba-lagi menerbitkan permintaan HTTP baru');
    expect(registry.isFailed(url), isFalse,
        reason: 'evict lewat ketuk menghapus URL dari daftar gagal');
    expect(cloudOff(), findsNothing,
        reason: 'keadaan error ter-reset; ubin kembali memuat');
  });

  testWidgets(
      '4. FallbackArtworkImage: evictOne(primer) mereset kait cadangan',
      (tester) async {
    installMock((_) => _MockResponse(statusCode: 404));
    const primary = 'https://fb.invalid/p.jpg';
    const fallback = 'https://fb.invalid/f.jpg';
    await tester.pumpWidget(wrap(const FallbackArtworkImage(
      primaryUrl: primary,
      fallbackUrl: fallback,
      width: 100,
      height: 100,
      cacheWidth: 100,
      placeholder: Text('PH'),
      errorPlaceholder: Text('ERR'),
    )));
    await settle(tester);
    expect(find.text('ERR'), findsOneWidget,
        reason: 'primer + cadangan gagal → placeholder error akhir');
    expect(registry.isFailed(primary), isTrue,
        reason: 'kegagalan akhir tercatat atas URL primer (S4/S3)');
    final primaryBefore = requested.where((u) => u == primary).length;
    final fallbackBefore = requested.where((u) => u == fallback).length;
    expect(primaryBefore, 1);
    expect(fallbackBefore, 1);

    registry.evictOne(primary);
    await settle(tester);
    releaseMock();
    expect(requested.where((u) => u == primary).length, primaryBefore + 1,
        reason: 'sesudah evict, PRIMER dicoba lagi dari keadaan bersih '
            '(kait cadangan ter-reset, bukan menetap di cadangan)');
    expect(requested.where((u) => u == fallback).length, fallbackBefore + 1,
        reason: 'primer gagal lagi → satu pertukaran cadangan seperti biasa');
    expect(find.text('ERR'), findsOneWidget,
        reason: 'keduanya gagal lagi → kembali ke placeholder error akhir');
  });
}

/// Klien yang permintaannya TIDAK PERNAH selesai — untuk mengamati
/// keadaan sedang-memuat secara deterministik.
class _PendingClient extends Fake implements HttpClient {
  _PendingClient(this.requested);
  final List<String> requested;

  @override
  Future<HttpClientRequest> getUrl(Uri url) {
    requested.add(url.toString());
    return Completer<HttpClientRequest>().future;
  }
}
