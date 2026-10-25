import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Set ikon DS Clai (v4.4) — SATU bahasa visual menggantikan ikon Material
/// ad-hoc yang tersebar: kisi 24, coretan seragam 1.8, terminal & sambungan
/// membulat, gaya gambar-tangan khas Clai dieksekusi rapi (DS Bab 6).
/// Setiap glif = jalur coretan (stroke) dan/atau jalur isi (fill) pada kisi 24.
class ClaiIconData {
  final Path? stroke;
  final Path? fill;
  const ClaiIconData({this.stroke, this.fill});
}

/// Widget ikon DS — pengganti `Icon` untuk semua ikon aplikasi.
class ClaiIcon extends StatelessWidget {
  final ClaiIconData data;
  final double? size;
  final Color? color;
  const ClaiIcon(this.data, {super.key, this.size, this.color});

  @override
  Widget build(BuildContext context) {
    final theme = IconTheme.of(context);
    final s = size ?? theme.size ?? 24;
    final c = color ?? theme.color ?? const Color(0xFFF4F6F1);
    return SizedBox(
      width: s, height: s,
      child: CustomPaint(painter: _ClaiIconPainter(data, c)),
    );
  }
}

class _ClaiIconPainter extends CustomPainter {
  final ClaiIconData data;
  final Color color;
  const _ClaiIconPainter(this.data, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24, size.height / 24);
    final fill = data.fill;
    if (fill != null) {
      canvas.drawPath(fill, Paint()..color = color..style = PaintingStyle.fill);
    }
    final stroke = data.stroke;
    if (stroke != null) {
      canvas.drawPath(
        stroke,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }
  }

  @override
  bool shouldRepaint(_ClaiIconPainter old) => old.data != data || old.color != color;
}

// ---------- pembangun jalur ----------
Path _s(void Function(Path p) f) {
  final p = Path();
  f(p);
  return p;
}

Path _circ(double cx, double cy, double r) =>
    Path()..addOval(Rect.fromCircle(center: Offset(cx, cy), radius: r));

Path _rr(double x, double y, double w, double h, double r) =>
    Path()..addRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x, y, w, h), Radius.circular(r)));

Path _join(List<Path> parts) {
  final out = Path();
  for (final p in parts) {
    out.addPath(p, Offset.zero);
  }
  return out;
}

Path _seg(double x1, double y1, double x2, double y2) =>
    Path()..moveTo(x1, y1)..lineTo(x2, y2);

/// Katalog glif Clai. Nama mengikuti peran, bukan bentuk Material-nya.
class ClaiIcons {
  // --- navigasi ---
  static final home = ClaiIconData(stroke: _join([
    _s((p) => p..moveTo(3.6, 11.2)..lineTo(12, 3.9)..lineTo(20.4, 11.2)),
    _s((p) => p..moveTo(5.6, 9.4)..lineTo(5.6, 20.2)..lineTo(10.1, 20.2)..lineTo(10.1, 14.9)..lineTo(13.9, 14.9)..lineTo(13.9, 20.2)..lineTo(18.4, 20.2)..lineTo(18.4, 9.4)),
  ]));
  static final homeFill = ClaiIconData(fill: _s((p) => p
    ..moveTo(12, 3.1)..lineTo(22.1, 11.6)..lineTo(19.6, 11.6)..lineTo(19.6, 20.7)
    ..lineTo(14.3, 20.7)..lineTo(14.3, 15.1)..lineTo(9.7, 15.1)..lineTo(9.7, 20.7)
    ..lineTo(4.4, 20.7)..lineTo(4.4, 11.6)..lineTo(1.9, 11.6)..close()));
  static final search = ClaiIconData(stroke: _join([
    _circ(11, 11, 6.7),
    _seg(16, 16, 20.7, 20.7),
  ]));
  // F2 Antrean Suara: mikrofon — kapsul + busur + tiang.
  static final mic = ClaiIconData(stroke: _join([
    _s((p) => p
      ..moveTo(9, 3.5)
      ..lineTo(9, 11.5)
      ..cubicTo(9, 13.5, 10.3, 14.8, 12, 14.8)
      ..cubicTo(13.7, 14.8, 15, 13.5, 15, 11.5)
      ..lineTo(15, 3.5)
      ..cubicTo(15, 1.5, 9, 1.5, 9, 3.5)
      ..close()),
    _s((p) => p..moveTo(5.5, 11)..cubicTo(5.5, 15.5, 8.3, 18.2, 12, 18.2)..cubicTo(15.7, 18.2, 18.5, 15.5, 18.5, 11)),
    _seg(12, 18.2, 12, 21),
    _seg(9, 21, 15, 21),
  ]));
  static final library = ClaiIconData(stroke: _join([
    _seg(6, 4.4, 6, 19.6),
    _seg(10.1, 4.4, 10.1, 19.6),
    _s((p) => p..moveTo(13.9, 5.1)..lineTo(18.7, 3.9)..lineTo(21.1, 18.7)..lineTo(16.3, 19.9)..close()),
  ]));
  static final libraryFill = ClaiIconData(fill: _join([
    _rr(3.9, 3.6, 2.9, 16.8, 0.8),
    _rr(8.6, 3.6, 2.9, 16.8, 0.8),
    _s((p) => p..moveTo(13.6, 4.7)..lineTo(18.9, 3.4)..lineTo(21.3, 18.4)..lineTo(16, 19.7)..close()),
  ]));

  // --- transport ---
  static final play = ClaiIconData(fill: _s((p) => p
    ..moveTo(8.4, 5.4)..cubicTo(8.4, 4.6, 9.2, 4.1, 9.9, 4.5)
    ..lineTo(18.9, 11)..cubicTo(19.5, 11.4, 19.5, 12.6, 18.9, 13)
    ..lineTo(9.9, 19.5)..cubicTo(9.2, 19.9, 8.4, 19.4, 8.4, 18.6)..close()));
  static final pause = ClaiIconData(fill: _join([
    _rr(6.8, 5, 3.6, 14, 1.8),
    _rr(13.6, 5, 3.6, 14, 1.8),
  ]));
  static final next = ClaiIconData(fill: _join([
    _s((p) => p..moveTo(6.3, 6.1)..lineTo(14.9, 12)..lineTo(6.3, 17.9)..close()),
    _rr(16.1, 6, 2.7, 12, 1.35),
  ]));
  static final prev = ClaiIconData(fill: _join([
    _s((p) => p..moveTo(17.7, 6.1)..lineTo(9.1, 12)..lineTo(17.7, 17.9)..close()),
    _rr(5.2, 6, 2.7, 12, 1.35),
  ]));
  static final shuffle = ClaiIconData(stroke: _join([
    _s((p) => p..moveTo(3.5, 6.8)..lineTo(7, 6.8)..cubicTo(10.6, 6.8, 11.9, 10.4, 14.1, 13.1)..cubicTo(15.4, 14.7, 16.8, 16.2, 20.5, 17.2)),
    _s((p) => p..moveTo(17.3, 13.9)..lineTo(20.6, 17.2)..lineTo(17.3, 20.5)),
    _s((p) => p..moveTo(3.5, 17.2)..lineTo(7, 17.2)..cubicTo(10.2, 17.2, 11.6, 14.6, 13.2, 12.2)),
    _s((p) => p..moveTo(14.4, 10.2)..cubicTo(15.8, 8.3, 17.2, 6.8, 20.5, 6.8)),
    _s((p) => p..moveTo(17.3, 3.5)..lineTo(20.6, 6.8)..lineTo(17.3, 10.1)),
  ]));
  static final repeat = ClaiIconData(stroke: _join([
    _s((p) => p..moveTo(6, 8)..lineTo(16.5, 8)..arcToPoint(const Offset(20, 11.5), radius: const Radius.circular(3.5))..lineTo(20, 13.5)),
    _s((p) => p..moveTo(16.9, 4.9)..lineTo(20.3, 8.3)..lineTo(16.9, 11.7)),
    _s((p) => p..moveTo(18, 16)..lineTo(7.5, 16)..arcToPoint(const Offset(4, 12.5), radius: const Radius.circular(3.5))..lineTo(4, 10.5)),
    _s((p) => p..moveTo(7.1, 19.1)..lineTo(3.7, 15.7)..lineTo(7.1, 12.3)),
  ]));
  static final repeatOne = ClaiIconData(stroke: _join([
    repeat.stroke!,
    _seg(12.2, 15.2, 12.2, 10),
    _s((p) => p..moveTo(10.5, 11.4)..lineTo(12.2, 10)),
  ]));

  // --- aksi & status ---
  static Path get _heartPath => _s((p) => p
    ..moveTo(12, 20.2)
    ..cubicTo(5.8, 15.9, 3.4, 12.7, 3.4, 9.4)
    ..cubicTo(3.4, 6.7, 5.4, 4.9, 7.8, 4.9)
    ..cubicTo(9.5, 4.9, 11.1, 6, 12, 7.5)
    ..cubicTo(12.9, 6, 14.5, 4.9, 16.2, 4.9)
    ..cubicTo(18.6, 4.9, 20.6, 6.7, 20.6, 9.4)
    ..cubicTo(20.6, 12.7, 18.2, 15.9, 12, 20.2)..close());
  static final heart = ClaiIconData(stroke: _heartPath);
  static final heartFill = ClaiIconData(fill: _heartPath);
  static final queue = ClaiIconData(stroke: _join([
    _seg(4, 6.5, 14.5, 6.5),
    _seg(4, 11.5, 14.5, 11.5),
    _seg(4, 16.5, 9.5, 16.5),
    _circ(16.7, 17.5, 2.5),
    _seg(19.2, 17.5, 19.2, 7.9),
    _s((p) => p..moveTo(19.2, 7.9)..lineTo(15.3, 9.5)),
  ]));
  static final lyrics = ClaiIconData(stroke: _join([
    _rr(4.6, 4.6, 14.8, 14.8, 3),
    _seg(8.2, 9.6, 15.8, 9.6),
    _seg(8.2, 13.2, 13.4, 13.2),
  ]));
  static final moon = ClaiIconData(stroke: _s((p) => p
    ..moveTo(20.3, 15.1)
    ..cubicTo(16.5, 19.8, 10.5, 21, 6.8, 17.8)
    ..cubicTo(3.1, 14.6, 3, 8.6, 6.2, 5.6)
    ..cubicTo(7.3, 4.5, 8.1, 4, 8.9, 3.7)
    ..cubicTo(12.6, 5.8, 17.4, 10.4, 20.3, 15.1)..close()));
  static final download = ClaiIconData(stroke: _join([
    _seg(12, 3.8, 12, 13.4),
    _s((p) => p..moveTo(7.2, 10.2)..lineTo(12, 15)..lineTo(16.8, 10.2)),
    _seg(4.6, 19.6, 19.4, 19.6),
    _seg(4.6, 19.6, 4.6, 16.9),
    _seg(19.4, 19.6, 19.4, 16.9),
  ]));
  static final add = ClaiIconData(stroke: _join([_seg(12, 5, 12, 19), _seg(5, 12, 19, 12)]));
  static final moreVert = ClaiIconData(fill: _join([
    _circ(12, 5.2, 1.7), _circ(12, 12, 1.7), _circ(12, 18.8, 1.7),
  ]));
  static final share = ClaiIconData(stroke: _join([
    _circ(6, 12, 2.7), _circ(17.5, 5.8, 2.7), _circ(17.5, 18.2, 2.7),
    _seg(8.4, 10.8, 15.1, 7),
    _seg(8.4, 13.2, 15.1, 17),
  ]));
  static final radio = ClaiIconData(
    fill: _circ(12, 12, 1.8),
    stroke: _join([
      _s((p) => p..moveTo(9.3, 9.3)..arcToPoint(const Offset(9.3, 14.7), radius: const Radius.circular(3.9), clockwise: false)),
      _s((p) => p..moveTo(14.7, 9.3)..arcToPoint(const Offset(14.7, 14.7), radius: const Radius.circular(3.9))),
      _s((p) => p..moveTo(6.5, 6.5)..arcToPoint(const Offset(6.5, 17.5), radius: const Radius.circular(7.8), clockwise: false)),
      _s((p) => p..moveTo(17.5, 6.5)..arcToPoint(const Offset(17.5, 17.5), radius: const Radius.circular(7.8))),
    ]),
  );
  // F2: segarkan (cek pembaruan) — dua busur berlawanan + dua mata panah.
  static final refresh = ClaiIconData(stroke: _join([
    _s((p) => p..arcTo(const Rect.fromLTWH(3.6, 3.6, 16.8, 16.8), -0.32, 2.45, true)),
    _s((p) => p..arcTo(const Rect.fromLTWH(3.6, 3.6, 16.8, 16.8), 2.82, 2.45, true)),
    _s((p) => p..moveTo(15.9, 2.6)..lineTo(20.9, 3.9)..lineTo(19.7, 8.9)),
    _s((p) => p..moveTo(8.1, 21.4)..lineTo(3.1, 20.1)..lineTo(4.3, 15.1)),
  ]));
  // F2: tautan (tempel tautan Spotify) — dua kait rantai + batang penghubung.
  static final link = ClaiIconData(stroke: _join([
    _s((p) => p
      ..moveTo(14.4, 6.9)..lineTo(17.4, 6.9)
      ..arcTo(const Rect.fromLTWH(12.4, 6.9, 10.0, 10.2), -math.pi / 2, math.pi, false)
      ..lineTo(14.4, 17.1)),
    _s((p) => p
      ..moveTo(9.6, 17.1)..lineTo(6.6, 17.1)
      ..arcTo(const Rect.fromLTWH(1.6, 6.9, 10.0, 10.2), math.pi / 2, math.pi, false)
      ..lineTo(9.6, 6.9)),
    _seg(8.8, 12, 15.2, 12),
  ]));
  // F2: Wi-Fi terputus (keadaan lirik gagal jaringan) — busur sinyal + titik + coretan.
  static final wifiOff = ClaiIconData(
    fill: _circ(12, 17.8, 1.3),
    stroke: _join([
      _s((p) => p..moveTo(5.2, 10.2)..arcToPoint(const Offset(18.8, 10.2), radius: const Radius.circular(9.8))),
      _s((p) => p..moveTo(7.9, 13.6)..arcToPoint(const Offset(16.1, 13.6), radius: const Radius.circular(6.0))),
      _seg(4, 4, 20, 20),
    ]),
  );
  static final check = ClaiIconData(stroke: _s((p) => p..moveTo(4.8, 12.6)..lineTo(9.8, 17.6)..lineTo(19.2, 6.8)));
  static final checkCircle = ClaiIconData(stroke: _join([
    _circ(12, 12, 8.6),
    _s((p) => p..moveTo(8.4, 12.4)..lineTo(11.2, 15.2)..lineTo(15.8, 9.4)),
  ]));
  static final warning = ClaiIconData(
    fill: _circ(12, 16.9, 1),
    stroke: _join([
      _s((p) => p..moveTo(12, 4.4)..lineTo(21, 19.3)..lineTo(3, 19.3)..close()),
      _seg(12, 9.8, 12, 13.9),
    ]),
  );
  static final info = ClaiIconData(
    fill: _circ(12, 8.1, 1),
    stroke: _join([_circ(12, 12, 8.8), _seg(12, 11.2, 12, 15.6)]),
  );
  // Gerigi betulan (siluet 8 gigi hasil hitung + hub) — versi lama (lingkaran +
  // garis-garis lepas) terbaca sebagai MATAHARI di tangkapan emulator v4.4.
  static final settings = ClaiIconData(stroke: _join([_cog(), _circ(12, 12, 3)]));
  static Path _cog() {
    final p = Path();
    const c = 12.0, rOut = 9.7, rRoot = 7.5;
    Offset pt(double r, double deg) {
      final a = deg * math.pi / 180;
      return Offset(c + r * math.cos(a), c + r * math.sin(a));
    }
    for (var i = 0; i < 8; i++) {
      final a = i * 45.0;
      final pts = [pt(rRoot, a - 22.5), pt(rOut, a - 8), pt(rOut, a + 8), pt(rRoot, a + 22.5)];
      for (final q in pts) {
        if (i == 0 && q == pts.first) { p.moveTo(q.dx, q.dy); } else { p.lineTo(q.dx, q.dy); }
      }
    }
    p.close();
    return p;
  }
  static final chevronDown = ClaiIconData(stroke: _s((p) => p..moveTo(5.5, 9.3)..lineTo(12, 15.8)..lineTo(18.5, 9.3)));
  static final chevronRight = ClaiIconData(stroke: _s((p) => p..moveTo(9.3, 5.5)..lineTo(15.8, 12)..lineTo(9.3, 18.5)));
  static final close = ClaiIconData(stroke: _join([_seg(6, 6, 18, 18), _seg(18, 6, 6, 18)]));
  static final infinity = ClaiIconData(stroke: _s((p) => p
    ..moveTo(12, 12)
    ..cubicTo(13.6, 9.2, 15.6, 7.4, 17.4, 7.4)
    ..cubicTo(19.6, 7.4, 21, 9.2, 21, 12)
    ..cubicTo(21, 14.8, 19.6, 16.6, 17.4, 16.6)
    ..cubicTo(15.6, 16.6, 13.6, 14.8, 12, 12)
    ..cubicTo(10.4, 9.2, 8.4, 7.4, 6.6, 7.4)
    ..cubicTo(4.4, 7.4, 3, 9.2, 3, 12)
    ..cubicTo(3, 14.8, 4.4, 16.6, 6.6, 16.6)
    ..cubicTo(8.4, 16.6, 10.4, 14.8, 12, 12)..close()));

  // --- koleksi & konten ---
  static final album = ClaiIconData(stroke: _join([_circ(12, 12, 8.8), _circ(12, 12, 2.7)]));
  static final person = ClaiIconData(stroke: _join([
    _circ(12, 8, 3.5),
    _s((p) => p..moveTo(5.2, 19.6)..cubicTo(6, 15.8, 8.8, 14, 12, 14)..cubicTo(15.2, 14, 18, 15.8, 18.8, 19.6)),
  ]));
  static final playlistAdd = ClaiIconData(stroke: _join([
    _seg(4, 6.5, 15, 6.5),
    _seg(4, 11.5, 15, 11.5),
    _seg(4, 16.5, 10, 16.5),
    _seg(17.5, 14.3, 17.5, 20.7),
    _seg(14.3, 17.5, 20.7, 17.5),
  ]));
  static final dragHandle = ClaiIconData(fill: _join([
    _circ(9, 6.5, 1.35), _circ(15, 6.5, 1.35),
    _circ(9, 12, 1.35), _circ(15, 12, 1.35),
    _circ(9, 17.5, 1.35), _circ(15, 17.5, 1.35),
  ]));
  static final trash = ClaiIconData(stroke: _join([
    _seg(4.5, 6.5, 19.5, 6.5),
    _s((p) => p..moveTo(9.5, 6.5)..lineTo(9.5, 4.6)..lineTo(14.5, 4.6)..lineTo(14.5, 6.5)),
    _s((p) => p..moveTo(6.5, 6.5)..lineTo(7.4, 19.2)..lineTo(16.6, 19.2)..lineTo(17.5, 6.5)),
    _seg(10.2, 10.5, 10.2, 16.4),
    _seg(13.8, 10.5, 13.8, 16.4),
  ]));
  static final folder = ClaiIconData(stroke: _s((p) => p
    ..moveTo(3.8, 6.8)..lineTo(3.8, 17.4)
    ..arcToPoint(const Offset(5.6, 19.2), radius: const Radius.circular(1.8))
    ..lineTo(18.4, 19.2)
    ..arcToPoint(const Offset(20.2, 17.4), radius: const Radius.circular(1.8))
    ..lineTo(20.2, 9.4)
    ..arcToPoint(const Offset(18.4, 7.6), radius: const Radius.circular(1.8))
    ..lineTo(11, 7.6)..lineTo(9, 5)..lineTo(5.6, 5)
    ..arcToPoint(const Offset(3.8, 6.8), radius: const Radius.circular(1.8))..close()));
  static final folderOff = ClaiIconData(stroke: _join([folder.stroke!, _seg(4.5, 4.5, 19.5, 19.5)]));
  static final history = ClaiIconData(stroke: _join([
    _s((p) => p..moveTo(4.6, 4.6)..lineTo(4.6, 9.4)..lineTo(9.4, 9.4)),
    _s((p) => p..moveTo(5.1, 9.7)..cubicTo(5.6, 6.9, 8.2, 4.9, 12, 4.4)..cubicTo(16.2, 4.4, 19.6, 7.8, 19.6, 12)..cubicTo(19.6, 16.2, 16.2, 19.6, 12, 19.6)..cubicTo(9.6, 19.6, 7.6, 19, 6.4, 17.7)),
    _seg(12, 8.2, 12, 12.2),
    _seg(12, 12.2, 15.1, 14),
  ]));
  static final sort = ClaiIconData(stroke: _join([
    _seg(7.5, 5, 7.5, 16.6),
    _s((p) => p..moveTo(4.8, 13.9)..lineTo(7.5, 16.9)..lineTo(10.2, 13.9)),
    _seg(16.5, 19, 16.5, 7.4),
    _s((p) => p..moveTo(13.8, 10.1)..lineTo(16.5, 7.1)..lineTo(19.2, 10.1)),
  ]));
  static final clearAll = ClaiIconData(stroke: _join([
    _seg(4, 6.5, 17, 6.5),
    _seg(4, 12, 14, 12),
    _seg(4, 17.5, 11, 17.5),
    _seg(16.6, 15.4, 20.4, 19.6),
    _seg(20.4, 15.4, 16.6, 19.6),
  ]));

  // --- perangkat & sistem ---
  static final shield = ClaiIconData(stroke: _join([
    _s((p) => p..moveTo(12, 3.6)..lineTo(19, 5.8)..lineTo(19, 11)..cubicTo(19, 16, 16.2, 19.4, 12, 20.8)..cubicTo(7.8, 19.4, 5, 16, 5, 11)..lineTo(5, 5.8)..close()),
    _s((p) => p..moveTo(9, 11.6)..lineTo(11.2, 13.8)..lineTo(15.2, 9.6)),
  ]));
  static final phone = ClaiIconData(stroke: _join([
    _rr(7.6, 3.6, 8.8, 16.8, 2.2),
    _seg(10.8, 17.4, 13.2, 17.4),
  ]));
  static final battery = ClaiIconData(
    fill: _rr(5.4, 11.1, 5.6, 2.8, 0.9),
    stroke: _join([_rr(3, 8.8, 16.5, 7.4, 2), _seg(21.7, 11.2, 21.7, 13.2)]),
  );
  static final batteryAlert = ClaiIconData(
    fill: _circ(11.2, 14.9, 0.95),
    stroke: _join([_rr(3, 8.8, 16.5, 7.4, 2), _seg(21.7, 11.2, 21.7, 13.2), _seg(11.2, 10.4, 11.2, 13.2)]),
  );
  static final copy = ClaiIconData(stroke: _join([
    _rr(9, 9, 11.5, 11.5, 2.5),
    _s((p) => p..moveTo(5.5, 15)..lineTo(5, 15)..arcToPoint(const Offset(3, 13), radius: const Radius.circular(2))..lineTo(3, 5)..arcToPoint(const Offset(5, 3), radius: const Radius.circular(2))..lineTo(13, 3)..arcToPoint(const Offset(15, 5), radius: const Radius.circular(2))..lineTo(15, 5.5)),
  ]));
  static final external = ClaiIconData(stroke: _join([
    _s((p) => p..moveTo(13.5, 4.5)..lineTo(19.5, 4.5)..lineTo(19.5, 10.5)),
    _seg(19.3, 4.7, 11, 13),
    _s((p) => p..moveTo(17, 13.8)..lineTo(17, 18.5)..arcToPoint(const Offset(15.2, 20.3), radius: const Radius.circular(1.8))..lineTo(6.3, 20.3)..arcToPoint(const Offset(4.5, 18.5), radius: const Radius.circular(1.8))..lineTo(4.5, 9.7)..arcToPoint(const Offset(6.3, 7.9), radius: const Radius.circular(1.8))..lineTo(11, 7.9)),
  ]));
  static final cloudOff = ClaiIconData(stroke: _join([
    _s((p) => p..moveTo(7, 18.6)..lineTo(16.6, 18.6)..cubicTo(19.6, 18.6, 21.2, 16.4, 20.4, 13.9)..cubicTo(19.9, 12.3, 18.6, 11.3, 17, 11.1)..cubicTo(16.4, 7.6, 13.6, 5.4, 10.6, 6)..cubicTo(7.9, 6.5, 6.2, 8.6, 6.4, 11.2)..cubicTo(4.4, 12, 3.4, 14.6, 4.6, 16.6)..cubicTo(5.2, 17.8, 6, 18.4, 7, 18.6)..close()),
    _seg(4.5, 4.6, 19.5, 19.4),
  ]));
  static Path get _noteStroke => _join([
        _seg(11.2, 17.6, 11.2, 6.4),
        _s((p) => p..moveTo(11.2, 6.4)..cubicTo(13.9, 5.5, 16.4, 5.7, 18.2, 7.1)),
      ]);
  static Path get _noteFill => _join([
        Path()..addOval(const Rect.fromLTWH(5.6, 15.4, 5.6, 4.3)),
        _s((p) => p..moveTo(11.2, 6.4)..cubicTo(13.9, 5.5, 16.4, 5.7, 18.2, 7.1)..lineTo(18.2, 10.7)..cubicTo(16.4, 9.4, 13.9, 9.2, 11.2, 10.1)..close()),
      ]);
  static final musicNote = ClaiIconData(stroke: _noteStroke, fill: _noteFill);
  static final musicOff = ClaiIconData(stroke: _join([_noteStroke, _seg(4.5, 4.5, 19.5, 19.5)]), fill: _noteFill);
  static final searchOff = ClaiIconData(stroke: _join([
    _circ(10.6, 10.6, 6.2),
    _seg(15.2, 15.2, 16.4, 16.4),
    _seg(17.2, 16.6, 20.6, 20),
    _seg(20.6, 16.6, 17.2, 20),
  ]));
  static final playCircle = ClaiIconData(
    stroke: _circ(12, 12, 8.8),
    fill: _s((p) => p..moveTo(10.2, 8.7)..lineTo(15.7, 12)..lineTo(10.2, 15.3)..close()),
  );
}
