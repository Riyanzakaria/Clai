import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';

import '../app.dart';
import '../core/clai_icons.dart';
import '../core/tokens.dart';
import '../domain/models.dart';
import '../domain/transfer_data.dart';
import '../l10n/l10n.dart';
import '../services/library_transfer.dart';
import 'glass.dart';
import 'import_flow.dart';
import 'widgets.dart';

/// Layar Pindai Kode QR (Ronde 8070, mode Bagikan D2): kamera penuh,
/// bingkai bidik Volt PADAT, kontrol melayang KACA (chip kembali,
/// senter, pill "Impor dari berkas") sesuai aturan kaca hasil audit.
/// Kode yang terbaca & sah berhenti di keadaan Terbaca (kartu padat di
/// dasar layar): nama playlist + jumlah lagu → Impor / Pindai lagi.
class QrScanScreen extends ConsumerStatefulWidget {
  const QrScanScreen({super.key});

  @override
  ConsumerState<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends ConsumerState<QrScanScreen>
    with WidgetsBindingObserver {
  final MobileScannerController _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );

  /// null = izin belum diputuskan; false = ditolak (keadaan penjelasan).
  bool? _granted;
  bool _cameraError = false;
  SharedPlaylistData? _found;
  DateTime _lastRejectSnack = DateTime.fromMillisecondsSinceEpoch(0);

  // Keadaan mode ringkas (Ronde 8078): payload hanya membawa referensi
  // katalog — penerima melarutkannya lebih dulu (berprogres), lalu
  // keadaan Terbaca yang sama persis dengan mode penuh.
  bool _resolving = false;
  String? _refsName;
  int _resolveDone = 0;
  int _resolveTotal = 0;

  /// Lagu yang dilewati pada impor mode ringkas berjalan (identitas
  /// tidak terlarutkan) — ditampilkan di kartu Terbaca & snackbar.
  int _skippedCount = 0;

  /// Pelarutan selesai tetapi NOL lagu ditemukan: keadaan gagal jujur,
  /// tidak ada playlist yang ditulis.
  bool _refsNoneFound = false;

  bool get _hasResult => _found != null || _resolving || _refsNoneFound;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _askPermission();
  }

  Future<void> _askPermission() async {
    final status = await Permission.camera.request();
    if (!mounted) return;
    // MobileScanner mulai sendiri (autoStart) begitu widget-nya terbangun
    // sesudah izin diberikan — start manual di sini akan ganda.
    setState(() => _granted = status.isGranted);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_granted != true || _hasResult) return;
    switch (state) {
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
        _controller.stop();
      case AppLifecycleState.resumed:
        _controller.start();
      default:
        break;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_hasResult) return;
    if (!_routeCapture(capture)) _rejectSnack();
  }

  /// Rutekan satu tangkapan barcode — dari kamera langsung ATAU dari
  /// gambar yang diunggah (Ronde 8071) — ke keadaan yang sama persis:
  /// sah → kartu Terbaca; format lebih baru → lembar Impor Gagal.
  /// Mengembalikan true bila tangkapan menghasilkan keadaan akhir;
  /// false bila isinya ditolak sebagai bukan-bagikan (pemanggil yang
  /// memutuskan bentuk pemberitahuannya).
  bool _routeCapture(BarcodeCapture capture) {
    if (_hasResult) return true;
    final cameraLive = _granted == true && !_cameraError;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null || raw.isEmpty) continue;
      final result = decodeQrPayload(raw);
      switch (result) {
        case ParsedSharedPlaylist(:final data):
          if (cameraLive) _controller.stop();
          setState(() => _found = data);
          return true;
        case ParsedSharedRefs(:final name, :final refs):
          // Mode ringkas: larutkan referensi ke trek katalog lebih
          // dulu (kartu progres), baru keadaan Terbaca.
          if (cameraLive) _controller.stop();
          _beginResolve(name, refs);
          return true;
        case ParsedLibrary():
          // QR berisi ekspor penuh, bukan bagikan playlist — pintu yang
          // benar untuk berkas itu adalah Impor dari berkas.
          return false;
        case TransferParseFailure(
            kind: TransferFailureKind.newerVersion
          ):
          if (cameraLive) _controller.stop();
          showImportFailureSheet(context, result);
          if (cameraLive) _controller.start();
          return true;
        case TransferParseFailure():
          return false;
      }
    }
    return false;
  }

  /// Larutkan referensi payload ringkas menjadi playlist utuh.
  /// Berjalan TANPA menulis apa pun ke basis data — penulisan hanya
  /// terjadi lewat impor atomik dari keadaan Terbaca, jadi kegagalan
  /// di tengah (jaringan mati, aplikasi ditutup) tidak pernah
  /// meninggalkan playlist setengah jadi.
  Future<void> _beginResolve(String name, List<TrackKey> refs) async {
    setState(() {
      _resolving = true;
      _refsName = name;
      _resolveDone = 0;
      _resolveTotal = refs.length;
      _skippedCount = 0;
      _refsNoneFound = false;
    });
    final resolution = await resolveSharedRefs(
      name: name,
      refs: refs,
      lookup: _lookupTrack,
      onProgress: (done, total) {
        if (mounted) setState(() => _resolveDone = done);
      },
    );
    if (!mounted) return;
    setState(() {
      _resolving = false;
      if (resolution.resolvedCount == 0) {
        _refsNoneFound = true;
      } else {
        _found = resolution.data;
        _skippedCount = resolution.unresolvedCount;
      }
    });
  }

  /// Pelarutan SATU identitas katalog (Ronde 8078): cache katalog
  /// lokal lebih dulu (cepat, bisa luring), lalu sumber katalog untuk
  /// provider yang bisa dilarutkan per id — hasilnya ikut di-cache.
  /// Provider tanpa pelarut per-id tidak terlarutkan (dihitung sebagai
  /// dilewati, dilaporkan jujur).
  Future<Track?> _lookupTrack(TrackKey key) async {
    final db = ref.read(appDbProvider);
    final cached = await db.trackByKey(key);
    if (cached != null) return cached;
    if (key.providerId != 'ytmusic') return null;
    final t = await ref.read(ytMusicProvider).resolveTrackById(key.id);
    if (t != null) await db.cacheTracks([t]);
    return t;
  }

  bool _pickingImage = false;

  /// "Pilih gambar QR" (Ronde 8071): terima playlist dari GAMBAR kode
  /// QR — tangkapan layar yang dikirim lewat chat adalah cara QR
  /// benar-benar berpindah antar pengguna. Deteksi gambar-diam ML Kit
  /// lewat `analyzeImage` (API mobile_scanner 7.5.0, Android
  /// didukung); hasilnya masuk perutean yang sama persis dengan
  /// tangkapan kamera. Gambar tanpa QR / bukan Clai / tak terbaca =
  /// pemberitahuan jujur, tanpa crash.
  Future<void> _pickQrImage() async {
    if (_pickingImage || _hasResult) return;
    _pickingImage = true;
    try {
      // Pola file_picker yang sama seperti impor berkas (disemat
      // 10.3.x, API FilePicker.platform).
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: false,
      );
      if (picked == null || picked.files.isEmpty) return;
      final path = picked.files.single.path;
      if (path == null) {
        if (mounted) _snack(context.l10n.scanImageUnreadable);
        return;
      }
      BarcodeCapture? capture;
      try {
        capture = await _controller.analyzeImage(
          path,
          formats: const [BarcodeFormat.qrCode],
        );
      } catch (_) {
        if (mounted) _snack(context.l10n.scanImageUnreadable);
        return;
      }
      if (!mounted) return;
      final hasRaw = capture != null &&
          capture.barcodes.any((b) => (b.rawValue ?? '').isNotEmpty);
      if (!hasRaw) {
        _snack(context.l10n.scanImageNoQr);
        return;
      }
      if (!_routeCapture(capture) && mounted) {
        _snack(context.l10n.scanNotClai);
      }
    } finally {
      _pickingImage = false;
    }
  }

  // Semua snackbar layar ini WAJIB melayang di atas chrome cangkang
  // (pola baku aplikasi `claiSnackAboveChrome`): SnackBar polos menempel
  // dasar layar dan tertutup mini player + nav — pesan jujur yang tak
  // terlihat sama saja tak ada (temuan audit hidup ronde 8071).
  void _snack(String text) {
    ScaffoldMessenger.of(context)
        .showSnackBar(claiSnackAboveChrome(context, text));
  }

  /// Snackbar "bukan bagikan Clai" berjeda — kamera melihat kode yang
  /// sama berkali-kali; pengguna cukup diberi tahu sekali per 3 detik.
  void _rejectSnack() {
    final now = DateTime.now();
    if (now.difference(_lastRejectSnack) > const Duration(seconds: 3)) {
      _lastRejectSnack = now;
      ScaffoldMessenger.of(context).showSnackBar(
        claiSnackAboveChrome(context, context.l10n.scanNotClai),
      );
    }
  }

  Future<void> _importFound() async {
    final data = _found;
    if (data == null) return;
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final skipped = _skippedCount;
    final name = await ref.read(appDbProvider).importSharedPlaylist(data);
    await ref.read(libraryProvider).load();
    if (!mounted) return;
    messenger.showSnackBar(
      claiSnackAboveChrome(
        context,
        skipped > 0
            ? context.l10n.scanImportedSkips(name, skipped)
            : context.l10n.scanImported(name),
      ),
    );
    nav.pop();
  }

  void _scanAgain() {
    setState(() {
      _found = null;
      _skippedCount = 0;
      _refsNoneFound = false;
      _refsName = null;
      _resolveDone = 0;
      _resolveTotal = 0;
    });
    _controller.start();
  }

  /// Pill KACA berisi ikon + label (chrome melayang layar Pindai:
  /// "Impor dari berkas" dan "Pilih gambar QR").
  Widget _glassPill({
    required ClaiIconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GlassSurface(
      radius: 999,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            ClaiIcon(icon, size: 19, color: ClaiColors.ink),
            const SizedBox(width: 8),
            Text(label,
                style: const TextStyle(
                    color: ClaiColors.ink,
                    fontSize: 14,
                    fontWeight: FontWeight.w500)),
          ]),
        ),
      ),
    );
  }

  Widget _glassCircleButton({
    required ClaiIconData icon,
    required VoidCallback onTap,
    bool active = false,
  }) {
    return GlassSurface(
      radius: 999,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 44,
          height: 44,
          child: Center(
            child: ClaiIcon(
              icon,
              size: 22,
              color: active ? ClaiColors.signal : ClaiColors.ink,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        // --- permukaan kamera / keadaan pengganti ---
        if (_granted == true && !_cameraError)
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && !_cameraError) {
                  setState(() => _cameraError = true);
                }
              });
              return const SizedBox.shrink();
            },
          )
        else if (_granted == false || _cameraError)
          _ScannerSubstitute(
            title: _cameraError ? s.scanUnavailable : s.scanPermDenied,
            sub: _cameraError ? null : s.scanPermDeniedSub,
            showSettings: !_cameraError,
            onPickImage: _pickQrImage,
          )
        else
          const Center(child: CircularProgressIndicator()),

        if (_granted == true && !_cameraError)
          const Positioned.fill(child: _ViewfinderOverlay()),

        // --- chrome melayang (KACA) ---
        Positioned(
          top: MediaQuery.paddingOf(context).top + 10,
          left: 14,
          child: _glassCircleButton(
            icon: ClaiIcons.chevronLeft,
            onTap: () => Navigator.of(context).maybePop(),
          ),
        ),
        if (_granted == true && !_cameraError)
          Positioned(
            top: MediaQuery.paddingOf(context).top + 10,
            right: 14,
            child: ValueListenableBuilder<MobileScannerState>(
              valueListenable: _controller,
              builder: (context, state, _) => _glassCircleButton(
                icon: ClaiIcons.flash,
                active: state.torchState == TorchState.on,
                onTap: () => _controller.toggleTorch(),
              ),
            ),
          ),

        // --- petunjuk + pintu berkas (atau kartu Terbaca) ---
        // Jarak dasar WAJIB bottomChromeClearance: layar ini hidup di
        // dalam cangkang, mini player + nav melayang di atas dasar
        // layar — tanpa clearance, pill & kartu Terbaca tertutup
        // chrome (terbukti audit emulator ronde 8071).
        if (!_hasResult)
          Positioned(
            left: 20,
            right: 20,
            bottom: bottomChromeClearance(context) + 22,
            child: Column(children: [
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 10,
                runSpacing: 10,
                children: [
                  _glassPill(
                    icon: ClaiIcons.folder,
                    label: s.scanImportFile,
                    onTap: () => runImportFromFile(context, ref),
                  ),
                  _glassPill(
                    icon: ClaiIcons.image,
                    label: s.scanPickImage,
                    onTap: _pickQrImage,
                  ),
                ],
              ),
            ]),
          )
        else
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _resolving
                ? _ResolvingCard(
                    name: _refsName ?? '',
                    done: _resolveDone,
                    total: _resolveTotal,
                  )
                : _refsNoneFound
                    ? _NoneFoundCard(
                        name: _refsName ?? '',
                        onAgain: _scanAgain,
                      )
                    : _FoundCard(
                        data: _found!,
                        skippedCount: _skippedCount,
                        onImport: _importFound,
                        onAgain: _scanAgain,
                      ),
          ),
      ]),
    );
  }
}

/// Keadaan tanpa kamera: izin ditolak atau kamera tak tersedia —
/// penjelasan jujur + jalan keluar (pengaturan / impor berkas).
class _ScannerSubstitute extends ConsumerWidget {
  final String title;
  final String? sub;
  final bool showSettings;
  final VoidCallback? onPickImage;
  const _ScannerSubstitute({
    required this.title,
    required this.sub,
    required this.showSettings,
    this.onPickImage,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.l10n;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          rowLeadIcon(ClaiIcons.capture, size: 56, iconSize: 26),
          const SizedBox(height: 18),
          Text(title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: ClaiColors.ink,
                  fontSize: 16,
                  fontWeight: FontWeight.w600)),
          if (sub != null) ...[
            const SizedBox(height: 8),
            Text(sub!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: ClaiColors.inkSecondary, fontSize: 13, height: 1.5)),
          ],
          const SizedBox(height: 20),
          if (showSettings)
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: ClaiColors.signal,
                foregroundColor: ClaiColors.onSignal,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(ClaiRadius.pill)),
              ),
              onPressed: () => openAppSettings(),
              child: Text(s.scanOpenSettings,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
          TextButton(
            onPressed: () => runImportFromFile(context, ref),
            child: Text(s.scanImportFile,
                style: const TextStyle(color: ClaiColors.signal)),
          ),
          if (onPickImage != null)
            TextButton(
              onPressed: onPickImage,
              child: Text(s.scanPickImage,
                  style: const TextStyle(color: ClaiColors.signal)),
            ),
        ]),
      ),
    );
  }
}

/// Kartu keadaan Membangun Ulang (Ronde 8078) — payload ringkas
/// terbaca; referensinya sedang dilarutkan ke katalog. PADAT
/// surface-1 seperti kartu Terbaca; tanpa tombol (belum ada yang
/// bisa dikonfirmasi) selain meninggalkan layar.
class _ResolvingCard extends StatelessWidget {
  final String name;
  final int done;
  final int total;
  const _ResolvingCard({
    required this.name,
    required this.done,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    return Container(
      decoration: const BoxDecoration(
        color: ClaiColors.surface1,
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(ClaiRadius.sheet)),
      ),
      padding: EdgeInsets.fromLTRB(
          20, 18, 20, bottomChromeClearance(context) + 20),
      child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(name,
                    style: displayStyle(18),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
            ]),
            const SizedBox(height: 6),
            Text(s.scanResolving(done, total),
                style: const TextStyle(
                    color: ClaiColors.inkSecondary, fontSize: 13)),
          ]),
    );
  }
}

/// Kartu gagal jujur mode ringkas (Ronde 8078): pelarutan selesai
/// tetapi nol lagu ditemukan di katalog — TIDAK ada playlist yang
/// ditulis. Pengguna bisa memindai ulang atau kembali.
class _NoneFoundCard extends StatelessWidget {
  final String name;
  final VoidCallback onAgain;
  const _NoneFoundCard({required this.name, required this.onAgain});

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    return Container(
      decoration: const BoxDecoration(
        color: ClaiColors.surface1,
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(ClaiRadius.sheet)),
      ),
      padding: EdgeInsets.fromLTRB(
          20, 18, 20, bottomChromeClearance(context) + 20),
      child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              ClaiIcon(ClaiIcons.warning,
                  size: 22, color: ClaiColors.inkSecondary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(name,
                    style: displayStyle(18),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
            ]),
            const SizedBox(height: 6),
            Text(s.scanRefsNoneFound,
                style: const TextStyle(
                    color: ClaiColors.inkSecondary,
                    fontSize: 13,
                    height: 1.5)),
            const SizedBox(height: 18),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: ClaiColors.signal,
                foregroundColor: ClaiColors.onSignal,
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(ClaiRadius.pill)),
              ),
              onPressed: onAgain,
              child: Text(s.scanAgain,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
          ]),
    );
  }
}

/// Kartu keadaan Terbaca — PADAT surface-1 (aturan kaca: lembar/kartu
/// hasil tidak ikut kaca), menempel di dasar layar kamera.
class _FoundCard extends StatelessWidget {
  final SharedPlaylistData data;

  /// Lagu yang dilewati pada pelarutan mode ringkas (0 = mode penuh
  /// atau semua terlarut) — dinyatakan di kartu sebelum impor.
  final int skippedCount;
  final VoidCallback onImport;
  final VoidCallback onAgain;
  const _FoundCard({
    required this.data,
    this.skippedCount = 0,
    required this.onImport,
    required this.onAgain,
  });

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    return Container(
      decoration: const BoxDecoration(
        color: ClaiColors.surface1,
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(ClaiRadius.sheet)),
      ),
      padding: EdgeInsets.fromLTRB(
          20, 18, 20, bottomChromeClearance(context) + 20),
      child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              ClaiIcon(ClaiIcons.checkCircle,
                  size: 22, color: ClaiColors.signal),
              const SizedBox(width: 10),
              Expanded(
                child: Text(data.name,
                    style: displayStyle(18),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
            ]),
            const SizedBox(height: 6),
            Text(s.scanFoundSub(data.tracks.length),
                style: const TextStyle(
                    color: ClaiColors.inkSecondary, fontSize: 13)),
            if (skippedCount > 0) ...[
              const SizedBox(height: 4),
              Text(s.scanSkippedCount(skippedCount),
                  style: const TextStyle(
                      color: ClaiColors.inkSecondary, fontSize: 13)),
            ],
            const SizedBox(height: 18),
            Row(children: [
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: ClaiColors.signal,
                    foregroundColor: ClaiColors.onSignal,
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(ClaiRadius.pill)),
                  ),
                  onPressed: onImport,
                  child: Text(s.scanImportAction,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: onAgain,
                child: Text(s.scanAgain,
                    style: const TextStyle(color: ClaiColors.inkSecondary)),
              ),
            ]),
          ]),
    );
  }
}

/// Lapisan bidik: penggelapan di luar kotak bidik + empat siku Volt
/// PADAT (bukan kaca — penanda bidik harus terbaca di segala kamera).
class _ViewfinderOverlay extends StatelessWidget {
  const _ViewfinderOverlay();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(painter: _ViewfinderPainter(), size: Size.infinite),
    );
  }
}

class _ViewfinderPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final boxSize = size.width * 0.68;
    final box = Rect.fromCenter(
      center: Offset(size.width / 2, size.height * 0.42),
      width: boxSize,
      height: boxSize,
    );
    final rrect = RRect.fromRectAndRadius(box, const Radius.circular(24));
    final shade = Path()
      ..addRect(Offset.zero & size)
      ..addRRect(rrect);
    shade.fillType = PathFillType.evenOdd;
    canvas.drawPath(shade, Paint()..color = Colors.black.withValues(alpha: 0.45));

    final corner = Paint()
      ..color = ClaiColors.signal
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;
    const len = 30.0;
    final l = box.left, t = box.top, r = box.right, b = box.bottom;
    canvas.drawPath(
        Path()
          ..moveTo(l, t + len)
          ..lineTo(l, t)
          ..lineTo(l + len, t),
        corner);
    canvas.drawPath(
        Path()
          ..moveTo(r - len, t)
          ..lineTo(r, t)
          ..lineTo(r, t + len),
        corner);
    canvas.drawPath(
        Path()
          ..moveTo(l, b - len)
          ..lineTo(l, b)
          ..lineTo(l + len, b),
        corner);
    canvas.drawPath(
        Path()
          ..moveTo(r - len, b)
          ..lineTo(r, b)
          ..lineTo(r, b - len),
        corner);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
