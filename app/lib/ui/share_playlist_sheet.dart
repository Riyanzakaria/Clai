import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../app.dart';
import '../core/clai_icons.dart';
import '../core/tokens.dart';
import '../domain/transfer_data.dart';
import '../l10n/l10n.dart';
import '../services/library_transfer.dart';
import 'widgets.dart';

/// Mode Bagikan D2 (Ronde 8070 — Berbagi Tanpa Server terlipat ke D2):
/// satu playlist menjadi kode QR (payload ringkas terkompresi; ambang
/// [kQrMaxPayloadChars]) dan/atau berkas bagikan berisi lengkap.
/// Lembar PADAT (surface-1) sesuai aturan kaca; kartu QR terang demi
/// keterpindaian.

/// Pilih playlist pengguna lalu buka lembar Bagikan-nya (pintu hub
/// Kepemilikan).
Future<void> openSharePlaylistPicker(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet<void>(
    context: claiRootContext(context),
    isScrollControlled: true,
    backgroundColor: ClaiColors.surface1,
    shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(ClaiRadius.sheet))),
    builder: (_) => _SharePickerSheet(ref: ref),
  );
}

class _SharePickerSheet extends ConsumerWidget {
  final WidgetRef ref;
  const _SharePickerSheet({required this.ref});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.l10n;
    final db = ref.read(appDbProvider);
    return ClaiSheetScaffold(children: [
      const Padding(
        padding: EdgeInsets.only(top: 14),
        child: SheetHandle(),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(s.sharePickPlaylist, style: displayStyle(20)),
        ),
      ),
      FutureBuilder<List<Map<String, Object?>>>(
        future: db.playlists(),
        builder: (context, snap) {
          final rows = (snap.data ?? const [])
              .where((r) => (r['is_system'] as int? ?? 0) == 0)
              .toList();
          if (snap.connectionState == ConnectionState.waiting) {
            return const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          if (rows.isEmpty) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
              child: Text(s.shareNoPlaylists,
                  style: const TextStyle(
                      color: ClaiColors.inkSecondary, fontSize: 14)),
            );
          }
          return Column(children: [
            // Ronde 8084: baris pemilih terkunci 60/pitch 68 + hairline
            // antar baris; rowLeadIcon slot 40 glyph 24; judul 15/600,
            // sub hitungan 13 satu baris.
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) ...[
                const Padding(
                  padding: EdgeInsets.only(left: 76),
                  child: Divider(height: 1, color: ClaiColors.divider),
                ),
                const SizedBox(height: 7),
              ],
              FutureBuilder<int>(
                future: db.playlistCount(rows[i]['id'] as String),
                builder: (context, c) => ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 20),
                  minTileHeight: 60,
                  titleTextStyle: const TextStyle(
                      color: ClaiColors.ink,
                      fontSize: 15,
                      fontWeight: FontWeight.w600),
                  subtitleTextStyle: const TextStyle(
                      color: ClaiColors.inkSecondary, fontSize: 13),
                  leading:
                      rowLeadIcon(ClaiIcons.musicNote, size: 40, iconSize: 24),
                  title: Text(rows[i]['name'] as String,
                      style: const TextStyle(
                          color: ClaiColors.ink,
                          fontSize: 15,
                          fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  subtitle: Text(s.songCount(c.data ?? 0),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: ClaiColors.inkSecondary, fontSize: 13)),
                  trailing: ClaiIcon(ClaiIcons.chevronRight,
                      color: ClaiColors.inkFaint),
                  onTap: () async {
                    final data = await ref
                        .read(libraryTransferProvider)
                        .playlistData(rows[i]['id'] as String);
                    if (!context.mounted || data == null) return;
                    Navigator.of(context).pop();
                    openSharePlaylistSheet(context, data);
                  },
                ),
              ),
            ],
            const SizedBox(height: 12),
          ]);
        },
      ),
    ]);
  }
}

/// Render kartu bagikan QR sebagai PNG (Ronde 8071): kartu putih
/// polos — wordmark "Clai." (titik Volt di akhir, DS 6.6), nama playlist, hitungan lagu,
/// kode QR besar, dan baris penutup untuk penerima. GAMBAR inilah
/// yang berjalan lewat aplikasi chat (perilaku riyan: kode QR
/// diunduh/dibagikan sebagai gambar), jadi keterpindaian adalah
/// syarat utama: seluruh kartu putih memberi zona tenang jauh di
/// atas kebutuhan 4 modul di sekeliling kode.
Future<Uint8List> renderQrShareCardPng({
  required String payload,
  required String playlistName,
  required String countText,
  required String footerText,
}) async {
  const double w = 1080;
  const double pad = 84;
  const double qrSize = 816;
  const darkInk = Color(0xFF10130A);
  const grayInk = Color(0xFF5C615A);

  final qrPainter = QrPainter(
    data: payload,
    version: QrVersions.auto,
    eyeStyle: const QrEyeStyle(
      eyeShape: QrEyeShape.square,
      color: Color(0xFF000000),
    ),
    dataModuleStyle: const QrDataModuleStyle(
      dataModuleShape: QrDataModuleShape.square,
      color: Color(0xFF000000),
    ),
  );
  final qrData = await qrPainter.toImageData(qrSize);
  if (qrData == null) {
    throw StateError('render QR gagal');
  }
  final qrCodec = await ui.instantiateImageCodec(qrData.buffer.asUint8List());
  final qrImage = (await qrCodec.getNextFrame()).image;

  TextPainter lay(String text, TextStyle style,
      {double maxWidth = w - 2 * pad, int maxLines = 1}) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      maxLines: maxLines,
      ellipsis: '…',
    );
    tp.layout(maxWidth: maxWidth);
    return tp;
  }

  TextPainter laySpan(TextSpan span,
      {double maxWidth = w - 2 * pad, int maxLines = 1}) {
    final tp = TextPainter(
      text: span,
      textDirection: TextDirection.ltr,
      maxLines: maxLines,
      ellipsis: '…',
    );
    tp.layout(maxWidth: maxWidth);
    return tp;
  }

  // Wordmark "Clai." — atom yang sama dengan ClaiWordmark (DS 6.6):
  // titiknya glif titik font tampilan berwarna Volt, di akhir kata.
  final wordmark = laySpan(
    const TextSpan(
      style: TextStyle(
        fontFamily: kDisplayFontFamily,
        fontSize: 58,
        fontWeight: FontWeight.w600,
        color: darkInk,
        height: 1.1,
      ),
      children: [
        TextSpan(text: 'Clai'),
        TextSpan(text: '.', style: TextStyle(color: ClaiColors.accent)),
      ],
    ),
  );
  final name = lay(
    playlistName,
    const TextStyle(
      fontFamily: kDisplayFontFamily,
      fontSize: 54,
      fontWeight: FontWeight.w600,
      color: darkInk,
      height: 1.18,
    ),
    maxLines: 2,
  );
  final count = lay(
    countText,
    const TextStyle(fontSize: 38, color: grayInk, height: 1.3),
  );
  final footer = lay(
    footerText,
    const TextStyle(fontSize: 36, color: grayInk, height: 1.3),
    maxWidth: w,
  );

  // Susun vertikal: wordmark → nama → hitungan → QR → penutup.
  var y = 76.0;
  final wordmarkY = y;
  y += wordmark.height + 44;
  final nameY = y;
  y += name.height + 14;
  final countY = y;
  y += count.height + 58;
  final qrY = y;
  y += qrSize + 54;
  final footerY = y;
  y += footer.height + 76;
  final h = y;

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, w, h));
  canvas.drawRect(
      Rect.fromLTWH(0, 0, w, h), Paint()..color = const Color(0xFFFFFFFF));
  // Wordmark "Clai." — titik Volt-nya sudah menyatu sebagai glif titik
  // di akhir kata (di dalam painter wordmark); tanda tangan merek kartu.
  wordmark.paint(canvas, Offset(pad, wordmarkY));
  name.paint(canvas, Offset(pad, nameY));
  count.paint(canvas, Offset(pad, countY));
  canvas.drawImage(qrImage, Offset((w - qrSize) / 2, qrY), Paint());
  footer.paint(canvas, Offset((w - footer.width) / 2, footerY));

  final picture = recorder.endRecording();
  final image = await picture.toImage(w.ceil(), h.ceil());
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  if (png == null) {
    throw StateError('render kartu QR gagal');
  }
  return png.buffer.asUint8List();
}

/// Lembar Bagikan untuk satu playlist yang datanya sudah terpegang.
///
/// Ronde 8077: lembar ini ConsumerStatefulWidget yang membaca ref
/// MILIKNYA sendiri. Versi sebelumnya memegang WidgetRef pinjaman dari
/// pemanggil — pada jalur pemilih (pemilih menutup dirinya lalu membuka
/// lembar ini) ref itu sudah mati saat lembar tampil, sehingga kedua
/// tombol Bagikan melempar "Cannot use ref after the widget was
/// disposed" pada langkah pertama dan mati tanpa respons (cacat nyata
/// dari HP riyan pada vonis staging 8076).
Future<void> openSharePlaylistSheet(
  BuildContext context,
  TransferPlaylist playlist,
) {
  final shared = SharedPlaylistData(
    formatVersion: kTransferFormatVersion,
    name: playlist.name,
    tracks: playlist.tracks,
  );
  return showModalBottomSheet<void>(
    context: claiRootContext(context),
    isScrollControlled: true,
    backgroundColor: ClaiColors.surface1,
    shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(ClaiRadius.sheet))),
    builder: (_) => _ShareSheet(shared: shared),
  );
}

class _ShareSheet extends ConsumerStatefulWidget {
  final SharedPlaylistData shared;
  const _ShareSheet({required this.shared});

  @override
  ConsumerState<_ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends ConsumerState<_ShareSheet> {
  bool _sharingImage = false;

  SharedPlaylistData get shared => widget.shared;

  Future<void> _shareFile(BuildContext context) async {
    try {
      final svc = ref.read(libraryTransferProvider);
      final file = await svc.writeShareFile(
        'clai-playlist-${playlistFileSlug(shared.name)}.json',
        jsonEncode(sharedPlaylistToJson(shared)),
      );
      await SharePlus.instance.share(ShareParams(files: [XFile(file.path)]));
    } catch (_) {
      // Tulis/bagikan gagal: lembar tetap terbuka — pengguna bisa
      // mencoba lagi. (8077: kegagalan tidak lagi lolos sebagai
      // eksepsi async tak tertangani yang tak terlihat pengguna.)
    }
  }

  /// Bagikan GAMBAR kartu QR (Ronde 8071): render PNG lalu serahkan
  /// ke share sheet sistem — dari sana pengguna meneruskan ke chat
  /// atau menyimpan gambarnya (unduh). Penjaga masuk-ulang: ketukan
  /// ganda saat render tidak membuka dua share sheet.
  Future<void> _shareQrImage(BuildContext context, String payload,
      {required int qrTrackCount}) async {
    if (_sharingImage) return;
    final s = context.l10n;
    setState(() => _sharingImage = true);
    try {
      final png = await renderQrShareCardPng(
        payload: payload,
        playlistName: shared.name,
        countText: s.songCount(qrTrackCount),
        footerText: s.shareQrCardFooter,
      );
      final file = await ref
          .read(libraryTransferProvider)
          .writeShareBytes(
              'clai-qr-${playlistFileSlug(shared.name)}.png', png);
      await SharePlus.instance.share(ShareParams(
        files: [XFile(file.path, mimeType: 'image/png')],
      ));
    } catch (_) {
      // Render/bagikan gagal: lembar tetap terbuka, tombol pulih —
      // pengguna bisa mencoba lagi atau memakai jalur berkas.
    } finally {
      if (mounted) setState(() => _sharingImage = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    // Ronde 8078: mode kendaraan diputuskan planQrShare — penuh bila
    // muat, ringkas (referensi katalog) bila penuh tidak muat tetapi
    // ringkas muat, berkas saja bila keduanya tidak muat.
    final plan = planQrShare(shared);
    final payload = switch (plan) {
      QrShareFull(:final payload) => payload,
      QrShareRefs(:final payload) => payload,
      QrShareTooBig() => null,
    };
    final qrTrackCount = switch (plan) {
      QrShareFull() => shared.tracks.length,
      QrShareRefs(:final trackCount) => trackCount,
      QrShareTooBig() => 0,
    };
    return ClaiSheetScaffold(children: [
      const Padding(
        padding: EdgeInsets.only(top: 14),
        child: SheetHandle(),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(shared.name, style: displayStyle(20)),
            const SizedBox(height: 4),
            Text(s.songCount(shared.tracks.length),
                style: const TextStyle(
                    color: ClaiColors.inkSecondary, fontSize: 13)),
            const SizedBox(height: 20),
            if (payload != null) ...[
              Center(
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: QrImageView(
                    data: payload,
                    version: QrVersions.auto,
                    size: 216,
                    backgroundColor: Colors.white,
                    eyeStyle: const QrEyeStyle(
                      eyeShape: QrEyeShape.square,
                      color: Colors.black,
                    ),
                    dataModuleStyle: const QrDataModuleStyle(
                      dataModuleShape: QrDataModuleShape.square,
                      color: Colors.black,
                    ),
                  ),
                ),
              ),
              // Ronde 8084: shareViaQrNote + shareRefsNote DIBUANG
              // (§13.2); shareLocalExcluded TETAP sebagai baris
              // hitungan murni (golongan (a)).
              if (plan is QrShareRefs && plan.localExcluded > 0) ...[
                const SizedBox(height: 14),
                Center(
                  child: Text(s.shareLocalExcluded(plan.localExcluded),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: ClaiColors.inkSecondary,
                          fontSize: 13,
                          height: 1.45)),
                ),
              ],
            ] else ...[
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                rowLeadIcon(ClaiIcons.warning, size: 40, iconSize: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(s.shareTooBigForQr,
                      style: const TextStyle(
                          color: ClaiColors.ink, fontSize: 14, height: 1.5)),
                ),
              ]),
            ],
            if (payload != null) ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: ClaiColors.ink,
                  side: const BorderSide(color: ClaiColors.surface3),
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(ClaiRadius.pill)),
                ),
                onPressed: _sharingImage
                    ? null
                    : () => _shareQrImage(context, payload,
                        qrTrackCount: qrTrackCount),
                icon: ClaiIcon(ClaiIcons.image,
                    size: 19, color: ClaiColors.ink),
                label: Text(s.shareQrImageAction,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
            ],
            const SizedBox(height: 22),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: ClaiColors.signal,
                foregroundColor: ClaiColors.onSignal,
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(ClaiRadius.pill)),
              ),
              onPressed: () => _shareFile(context),
              child: Text(s.shareFileAction,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    ]);
  }
}
