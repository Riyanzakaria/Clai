import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import '../domain/models.dart';

/// Provider File Lokal (F-11 Phase 2): berkas perangkat adalah warga kelas satu antrean & playlist.
/// Berkas dipindai lewat MethodChannel ke MediaStore sistem (android/.../MainActivity.kt) —
/// plugin on_audio_query dibuang karena tidak memiliki namespace AGP & tidak terawat.
class LocalFilesService {
  static const _channel = MethodChannel('clai/local_audio');
  static const providerId = 'local';

  Future<bool> ensurePermission() async {
    final status = await Permission.audio.status;
    if (status.isGranted) return true;
    return (await Permission.audio.request()).isGranted;
  }

  Future<List<Track>> scan() async {
    final rows = await _channel.invokeListMethod<Map>('querySongs') ?? const [];
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
