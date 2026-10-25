import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../core/artwork.dart';
import '../data/app_db.dart';
import 'cover_accent.dart';

/// Aksen cover dinamis (F2 Batch 2): warna tanda tangan sampul →
/// desaturasi 20% → latar tonal. Hasil tercache di enrichment_cache
/// (kind 'cover-accent-v2', kunci = URL sampul) agar unduhan & dekode
/// hanya sekali per sampul.
///
/// F2 Batch 2.1: kind cache NAIK versi (nilai lama dari rumus kusam tidak
/// boleh bertahan di perangkat), ekstraksi memakai warna tanda tangan
/// tertimbang saturasi (bukan rata-rata global), dan campuran tonal
/// diperkuat 0,28 → 0,50 — rumus lama menghasilkan bingkai nyaris hitam
/// yang tak terlihat di layar HP walau "terbukti" di tangkapan emulator.
class CoverAccentService {
  final AppDb db;
  final Dio _dio;
  CoverAccentService(this.db, {Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
                connectTimeout: const Duration(seconds: 6),
                receiveTimeout: const Duration(seconds: 12)));

  /// Warna tonal (siap pakai sebagai latar di belakang sampul) atau null.
  Future<Color?> tonalForUrl(String? url) async {
    if (url == null) return null;
    final sized = artworkUrlForSize(url, 200) ?? url;
    final cached = await db.enrichment('cover-accent-v2', sized);
    if (cached.exists && cached.value != null) {
      final rgb = rgbFromHex(cached.value!);
      if (rgb != null) return Color.fromARGB(255, rgb.r, rgb.g, rgb.b);
    }
    try {
      final res = await _dio.get<List<int>>(sized,
          options: Options(responseType: ResponseType.bytes,
              validateStatus: (s) => s != null && s < 500,
              receiveTimeout: const Duration(seconds: 10)));
      if (res.statusCode != 200 || res.data == null || res.data!.isEmpty) {
        return null;
      }
      final codec = await ui.instantiateImageCodec(Uint8List.fromList(res.data!));
      final frame = await codec.getNextFrame();
      final img = frame.image;
      final bytes = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
      img.dispose();
      if (bytes == null) return null;
      final px = bytes.buffer.asUint8List();
      // Warna tanda tangan dulu; sampul praktis tak berwarna jatuh ke
      // rata-rata global (perilaku lama) agar tetap ada nuansa.
      final sig = dominantSaturatedRgb(px) ?? averageRgb(px);
      final desat = desaturateRgb(sig, 0.20);
      final tonal = tonalRgb(desat, (r: 0x0A, g: 0x0A, b: 0x0E), 0.50);
      final hex = rgbToHex(tonal);
      await db.saveEnrichment('cover-accent-v2', sized, hex);
      return Color.fromARGB(255, tonal.r, tonal.g, tonal.b);
    } catch (_) {
      return null;
    }
  }
}
