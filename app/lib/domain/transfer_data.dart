import 'models.dart';

/// Tipe data transfer kepemilikan (Ronde 8070, Workstream D2 — F-12
/// USER-FLOW-DAN-LOGIKA): bentuk typed dari berkas ekspor Clai dan dari
/// payload bagikan-playlist. Murni data — penguraian/penyusunan JSON dan
/// codec QR hidup di `services/library_transfer.dart`; penerapan ke basis
/// data hidup di `data/app_db.dart`. Berkas ini tidak mengimpor keduanya
/// agar tidak ada siklus impor.

/// Satu trek dalam berkas transfer: metadata lengkap agar penerima bisa
/// merekonstruksi baris katalog tanpa jaringan (id + ref resolusi ikut).
class TransferTrack {
  final String providerId;
  final String trackId;
  final String title;
  final String artistNames;
  final String? albumId;
  final int? durationMs;
  final String? artworkUrl;
  final bool isExplicit;
  final String playableRef;

  const TransferTrack({
    required this.providerId,
    required this.trackId,
    required this.title,
    required this.artistNames,
    this.albumId,
    this.durationMs,
    this.artworkUrl,
    this.isExplicit = false,
    required this.playableRef,
  });

  TrackKey get key => TrackKey(providerId, trackId);

  factory TransferTrack.fromTrack(Track t) => TransferTrack(
        providerId: t.providerId,
        trackId: t.id,
        title: t.title,
        artistNames: t.artistNames,
        albumId: t.albumId,
        durationMs: t.duration?.inMilliseconds,
        artworkUrl: t.artworkUrl,
        isExplicit: t.isExplicit,
        playableRef: t.playableRef,
      );

  Track toTrack() => Track(
        key: key,
        title: title,
        artistNames: artistNames,
        albumId: albumId,
        duration:
            durationMs == null ? null : Duration(milliseconds: durationMs!),
        artworkUrl: artworkUrl,
        isExplicit: isExplicit,
        playableRef: playableRef,
      );

  Map<String, Object?> toJson() => {
        'providerId': providerId,
        'trackId': trackId,
        'title': title,
        'artistNames': artistNames,
        if (albumId != null) 'albumId': albumId,
        if (durationMs != null) 'durationMs': durationMs,
        if (artworkUrl != null) 'artworkUrl': artworkUrl,
        if (isExplicit) 'isExplicit': true,
        'playableRef': playableRef,
      };

  /// Penguraian defensif: field wajib harus string tak-kosong; field
  /// opsional yang hadir harus bertipe benar. Pelanggaran apa pun →
  /// [FormatException] (pemanggil memetakannya ke kegagalan "korup"
  /// SEBELUM satu baris pun ditulis — F-12: atomik).
  factory TransferTrack.fromJson(Map<String, dynamic> j, String path) {
    String req(String k) {
      final v = j[k];
      if (v is! String || v.isEmpty) {
        throw FormatException('$path.$k: wajib string tak-kosong');
      }
      return v;
    }

    String? optStr(String k) {
      final v = j[k];
      if (v == null) return null;
      if (v is! String) throw FormatException('$path.$k: harus string');
      return v;
    }

    int? optInt(String k) {
      final v = j[k];
      if (v == null) return null;
      if (v is! num) throw FormatException('$path.$k: harus angka');
      return v.toInt();
    }

    final explicit = j['isExplicit'];
    if (explicit != null && explicit is! bool) {
      throw FormatException('$path.isExplicit: harus boolean');
    }
    return TransferTrack(
      providerId: req('providerId'),
      trackId: req('trackId'),
      title: req('title'),
      artistNames: req('artistNames'),
      albumId: optStr('albumId'),
      durationMs: optInt('durationMs'),
      artworkUrl: optStr('artworkUrl'),
      isExplicit: explicit ?? false,
      playableRef: req('playableRef'),
    );
  }
}

/// Satu playlist pengguna dalam berkas transfer (entri berurutan).
class TransferPlaylist {
  final String name;
  final String? description;
  final int? createdAt;
  final List<TransferTrack> tracks;
  const TransferPlaylist({
    required this.name,
    this.description,
    this.createdAt,
    required this.tracks,
  });
}

/// Satu lagu disukai beserta waktu sukanya.
class TransferLike {
  final TransferTrack track;
  final int likedAt;
  const TransferLike({required this.track, required this.likedAt});
}

/// Satu peristiwa putar mentah (riwayat).
class TransferEvent {
  final TransferTrack track;
  final int startedAt;
  final int listenedMs;
  final bool completed;
  final String? contextKind;
  final String? contextId;
  const TransferEvent({
    required this.track,
    required this.startedAt,
    required this.listenedMs,
    required this.completed,
    this.contextKind,
    this.contextId,
  });
}

/// Satu item tersimpan (album/artis) dari tab Koleksi.
class TransferSavedItem {
  final String kind;
  final String providerId;
  final String itemId;
  final String title;
  final String? subtitle;
  final String? artworkUrl;
  final int savedAt;
  const TransferSavedItem({
    required this.kind,
    required this.providerId,
    required this.itemId,
    required this.title,
    this.subtitle,
    this.artworkUrl,
    required this.savedAt,
  });
}

/// Isi penuh berkas ekspor `clai-export` yang sudah terurai & tervalidasi.
/// [history] null = berkas tidak memuat riwayat (pilihan pengguna saat
/// ekspor, F-12 "riwayat opsional") — impor TIDAK menyentuh riwayat
/// dalam keadaan itu, termasuk pada mode ganti.
class LibraryTransferData {
  final int formatVersion;
  final String? appVersion;
  final int? exportedAt;
  final List<TransferPlaylist> playlists;
  final List<TransferLike> liked;
  final List<TransferEvent>? history;
  final List<TransferSavedItem> savedItems;
  const LibraryTransferData({
    required this.formatVersion,
    this.appVersion,
    this.exportedAt,
    required this.playlists,
    required this.liked,
    required this.history,
    required this.savedItems,
  });

  int get historyCount => history?.length ?? 0;
}

/// Isi berkas/payload bagikan satu playlist (`clai-playlist`).
class SharedPlaylistData {
  final int formatVersion;
  final String name;
  final List<TransferTrack> tracks;
  const SharedPlaylistData({
    required this.formatVersion,
    required this.name,
    required this.tracks,
  });
}

/// Proyeksi mode Gabungkan terhadap basis data saat ini — bahan
/// ringkasan Pratinjau Impor (F-12: ringkasan tambah/gabung/ganti
/// tampil SEBELUM diterapkan).
class ImportProjection {
  /// Playlist berkas yang namanya belum ada → dibuat baru.
  final int newPlaylists;

  /// Playlist berkas yang namanya sudah ada → digabungkan ke yang ada.
  final int mergedPlaylists;

  /// Entri trek yang benar-benar akan ditambahkan lintas semua playlist
  /// (sesudah dedupe per kunci trek di dalam playlist tujuan).
  final int playlistTracksAdded;

  /// Lagu suka berkas yang belum disukai di perangkat.
  final int likedAdded;

  /// Peristiwa riwayat berkas yang belum tercatat (dedupe tupel persis).
  final int historyAdded;

  const ImportProjection({
    required this.newPlaylists,
    required this.mergedPlaylists,
    required this.playlistTracksAdded,
    required this.likedAdded,
    required this.historyAdded,
  });
}
