import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import '../domain/models.dart';

/// Provider File Lokal (F-11 Phase 2): berkas perangkat adalah warga kelas satu antrean & playlist.
/// Berkas dipindai lewat MethodChannel ke MediaStore sistem (android/.../MainActivity.kt) —
/// plugin on_audio_query dibuang karena tidak memiliki namespace AGP & tidak terawat.
/// Label format tampil dari MIME MediaStore (murni, diuji): hanya
/// keluarga yang benar-benar dikenali yang dilabeli; selainnya null
/// (UI tidak menebak format dari nama berkas).
String? localFormatLabel(String? mime) {
  switch (mime?.toLowerCase().trim()) {
    case 'audio/mpeg':
      return 'MP3';
    case 'audio/flac':
    case 'audio/x-flac':
      return 'FLAC';
    case 'audio/mp4':
    case 'audio/x-m4a':
    case 'audio/m4a':
      return 'M4A';
    case 'audio/aac':
      return 'AAC';
    case 'audio/ogg':
      return 'OGG';
    case 'audio/opus':
      return 'OPUS';
    case 'audio/x-wav':
    case 'audio/wav':
    case 'audio/vnd.wave':
      return 'WAV';
    case 'audio/x-ms-wma':
      return 'WMA';
    default:
      return null;
  }
}

class LocalFilesService {
  static const _channel = MethodChannel('clai/local_audio');
  static const providerId = 'local';

  /// Label format per id MediaStore dari pindai terakhir (untuk chip
  /// baris & pita statistik Berkas Lokal) — Track sendiri tidak diubah.
  final Map<String, String> _formatById = {};

  String? formatOf(Track track) => _formatById[track.id];

  /// Himpunan label format yang ditemukan pindai terakhir, terurut.
  List<String> get scannedFormats {
    final set = _formatById.values.toSet().toList()..sort();
    return set;
  }

  Future<bool> ensurePermission() async {
    final status = await Permission.audio.status;
    if (status.isGranted) return true;
    return (await Permission.audio.request()).isGranted;
  }

  Future<List<Track>> scan() async {
    final rows = await _channel.invokeListMethod<Map>('querySongs') ?? const [];
    _formatById.clear();
    final tracks = <Track>[];
    for (final r in rows) {
      final m = r.cast<String, Object?>();
      final durationMs = (m['duration'] as num?)?.toInt() ?? 0;
      final uri = m['uri'] as String?;
      // D-28 (Sapuan): berkas <30 detik TIDAK lagi dibuang senyap dari hasil
      // pindai. Saringan itu milik gerbang Putar Otomatis (lagu sangat pendek
      // bukan sambungan yang baik), tetapi perpustakaan pengguna adalah warga
      // kelas satu (F-11) — jingle, memo suara, dan lagu pendek miliknya
      // harus tampil persis seperti yang ada di perangkatnya.
      if (uri == null) continue;
      final fmt = localFormatLabel(m['mime'] as String?);
      if (fmt != null) _formatById[m['id'] as String] = fmt;
      final artist = m['artist'] as String?;
      tracks.add(Track(
        key: TrackKey(providerId, m['id'] as String),
        title: (m['title'] as String?) ?? 'Tanpa judul',
        artistNames: (artist == null || artist == '<unknown>') ? 'Artis tidak dikenal' : artist,
        albumTitle: m['album'] as String?,
        duration: Duration(milliseconds: durationMs),
        playableRef: uri,
      ));
    }
    return tracks;
  }
}
