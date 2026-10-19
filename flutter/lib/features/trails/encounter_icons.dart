// Lumen Trails: the encounter's small icons (status chips, announcements, the log card, the floating
// numbers, the intro card's goal, the result's subtitle, the speech bubble), drawn from the same 24x24
// SVG path data as `SI` in web/src/screens/encounter.js, through a tiny path-data parser.

import 'package:flutter/material.dart';

/// One shape of an icon: SVG path data (or a circle), its fill and its stroke.
class _Shape {
  const _Shape(String this.d, {this.color, this.stroke, this.width = 0, this.cap = StrokeCap.butt, this.join = StrokeJoin.miter})
      : cx = 0,
        cy = 0,
        r = 0;
  const _Shape.circle(this.cx, this.cy, this.r, {this.color, this.stroke, this.width = 0})
      : d = null,
        cap = StrokeCap.butt,
        join = StrokeJoin.miter;
  final String? d; // null: a circle
  final double cx, cy, r;
  final Color? color; // the fill
  final Color? stroke;
  final double width;
  final StrokeCap cap;
  final StrokeJoin join;
}

const _star = 'M12 2.5l2.3 7.2 7.2 2.3-7.2 2.3L12 21.5l-2.3-7.2L2.5 12l7.2-2.3z';
const _heart = 'M12 20.5s-7.5-4.6-9.4-9.3C1.2 7.7 3.4 4.1 7 4.1c2.1 0 3.6 1.2 5 3 1.4-1.8 2.9-3 5-3 3.6 0 5.8 3.6 4.4 7.1-1.9 4.7-9.4 9.3-9.4 9.3z';

const _icons = <String, List<_Shape>>{
  'leaf': [
    _Shape('M4.5 19.5c-.6-7.2 4.4-13.6 15.4-14.4.6 9.6-5.4 15.6-13 14.6', color: Color(0xFF7CC456), stroke: Color(0xFF3F8A35), width: 1.6, join: StrokeJoin.round),
    _Shape('M5 19.5c3.4-4.6 6.6-7.6 11-10', stroke: Color(0xFF2F6B2A), width: 1.5, cap: StrokeCap.round),
  ],
  'spark': [_Shape(_star, color: Color(0xFFFFD25A), stroke: Color(0xFFD8962A), width: 1.3, join: StrokeJoin.round)],
  'hollow': [
    _Shape(_star, color: Color(0xFFB48CFF), stroke: Color(0xFF6B3FB8), width: 1.3, join: StrokeJoin.round),
    _Shape.circle(18.5, 5.5, 1.8, color: Color(0xFFD9C2FF)),
  ],
  'sun': [
    _Shape('M12 2.5v2.6M12 18.9v2.6M2.5 12h2.6M18.9 12h2.6M5.3 5.3l1.8 1.8M16.9 16.9l1.8 1.8M5.3 18.7l1.8-1.8M16.9 7.1l1.8-1.8', stroke: Color(0xFFE5A12F), width: 2, cap: StrokeCap.round),
    _Shape.circle(12, 12, 5, color: Color(0xFFFFD25A), stroke: Color(0xFFE5A12F), width: 1.6),
  ],
  'bolt': [_Shape('M13.5 2.5L5 13.5h6l-1.5 8 8.5-11h-6z', color: Color(0xFFFFD25A), stroke: Color(0xFFC98A20), width: 1.5, join: StrokeJoin.round)],
  'trust': [_Shape(_heart, color: Color(0xFFF58CA6), stroke: Color(0xFFC8577A), width: 1.4)],
  'soothed': [_Shape(_heart, color: Color(0xFF7FD9C9), stroke: Color(0xFF3E9F8F), width: 1.4)],
  'bloom': [
    _Shape.circle(12, 6.5, 3.6, color: Color(0xFFF7A6BE), stroke: Color(0xFFD86E92), width: 1.2),
    _Shape.circle(17.3, 10.4, 3.6, color: Color(0xFFF7A6BE), stroke: Color(0xFFD86E92), width: 1.2),
    _Shape.circle(15.3, 16.6, 3.6, color: Color(0xFFF7A6BE), stroke: Color(0xFFD86E92), width: 1.2),
    _Shape.circle(8.7, 16.6, 3.6, color: Color(0xFFF7A6BE), stroke: Color(0xFFD86E92), width: 1.2),
    _Shape.circle(6.7, 10.4, 3.6, color: Color(0xFFF7A6BE), stroke: Color(0xFFD86E92), width: 1.2),
    _Shape.circle(12, 12, 2.8, color: Color(0xFFFFD25A)),
  ],
  'charged': [_Shape('M12 2.8l2.8 5.8 6.3.9-4.6 4.4 1.1 6.3L12 17.2 6.4 20.2l1.1-6.3L2.9 9.5l6.3-.9z', color: Color(0xFFFFD25A), stroke: Color(0xFFD8962A), width: 1.4, join: StrokeJoin.round)],
  'unsteady': [
    _Shape('M12 12.2c0-1.3 1.6-1.8 2.4-.8 1.2 1.6-.3 3.9-2.4 3.9-2.8 0-4.4-3.1-3.1-5.6 1.7-3.1 6.1-3.4 8.2-.8 2.6 3.2.6 8.2-3.6 8.9-4.6.8-8.5-3.2-7.7-7.8',
        stroke: Color(0xFF9B5FE0), width: 2.2, cap: StrokeCap.round),
  ],
  'flicker': [_Shape('M13 2.5L7 13h4.5L10 21.5 17 10.5h-4.5z', color: Color(0xFFC9A2FF), stroke: Color(0xFF7A4CC8), width: 1.4, join: StrokeJoin.round)],
  'waking': [
    _Shape('M2.5 12s3.6-6 9.5-6 9.5 6 9.5 6-3.6 6-9.5 6-9.5-6-9.5-6z', color: Color(0xFFEADCFF), stroke: Color(0xFF7A4CC8), width: 1.6),
    _Shape.circle(12, 12, 3.2, color: Color(0xFF9B5FE0)),
  ],
  'wary': [_Shape('M12 2.8l7.5 3v5.6c0 4.8-3.2 8.3-7.5 9.8-4.3-1.5-7.5-5-7.5-9.8V5.8z', color: Color(0xFF8EC2F0), stroke: Color(0xFF3F7FC0), width: 1.5, join: StrokeJoin.round)],
  'tired': [
    _Shape('M12 3.5v12M6.5 10.5L12 16l5.5-5.5', stroke: Color(0xFFE2574C), width: 2.6, cap: StrokeCap.round, join: StrokeJoin.round),
    _Shape('M5 20h14', stroke: Color(0xFFE2574C), width: 2.2, cap: StrokeCap.round),
  ],
  'target': [
    _Shape.circle(12, 12, 9, color: Color(0xFFFFFFFF), stroke: Color(0xFFE2574C), width: 2),
    _Shape.circle(12, 12, 5.5, color: Color(0xFFFBD3CF), stroke: Color(0xFFE2574C), width: 2),
    _Shape.circle(12, 12, 2, color: Color(0xFFE2574C)),
  ],
};

/// The icons by name: leaf, spark, hollow (and hollowed), sun, bolt, trust, soothed, bloom, charged,
/// unsteady, flicker, waking, wary, tired, target. Unknown names draw the spark.
bool hasEncIcon(String name) => _icons.containsKey(name == 'hollowed' ? 'hollow' : name);

/// One of the encounter's small icons, [size] square.
class EncIcon extends StatelessWidget {
  const EncIcon(this.name, {super.key, this.size = 24});
  final String name;
  final double size;
  @override
  Widget build(BuildContext context) => SizedBox(width: size, height: size, child: CustomPaint(painter: _EncIconPainter(name == 'hollowed' ? 'hollow' : name)));
}

class _EncIconPainter extends CustomPainter {
  _EncIconPainter(this.name);
  final String name;

  static final Map<String, List<Path?>> _paths = {};

  @override
  void paint(Canvas canvas, Size size) {
    final shapes = _icons[name] ?? _icons['spark']!;
    final paths = _paths.putIfAbsent(name, () => [for (final s in shapes) s.d == null ? null : svgPath(s.d!)]);
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    for (var i = 0; i < shapes.length; i++) {
      final s = shapes[i];
      final path = paths[i];
      void draw(Paint paint) {
        if (path == null) {
          canvas.drawCircle(Offset(s.cx, s.cy), s.r, paint);
        } else {
          canvas.drawPath(path, paint);
        }
      }

      if (s.color != null) draw(Paint()..color = s.color!);
      if (s.stroke != null && s.width > 0) {
        draw(Paint()
          ..color = s.stroke!
          ..style = PaintingStyle.stroke
          ..strokeWidth = s.width
          ..strokeCap = s.cap
          ..strokeJoin = s.join);
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_EncIconPainter old) => old.name != name;
}

// ------------------------------------------------------------------ SVG path data ----
final _tok = RegExp(r'[MmLlHhVvCcSsQqTtZz]|[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?');
final _isCmd = RegExp(r'^[A-Za-z]$');

/// Parses SVG path data (M L H V C S Q T Z, absolute and relative, with implicit repeats) into a Path.
Path svgPath(String d) {
  final toks = [for (final m in _tok.allMatches(d)) m.group(0)!];
  final p = Path();
  var i = 0;
  String? cmd;
  var x = 0.0, y = 0.0, sx = 0.0, sy = 0.0;
  // the last control point, for the smooth curves (S/s after C/c/S/s, T/t after Q/q/T/t)
  double? cx, cy;
  var lastCubic = false, lastQuad = false;
  double n() => double.parse(toks[i++]);
  while (i < toks.length) {
    if (_isCmd.hasMatch(toks[i])) {
      cmd = toks[i++];
    } else if (cmd == null) {
      i++;
      continue;
    }
    final rel = cmd == cmd.toLowerCase();
    final ox = rel ? x : 0.0;
    final oy = rel ? y : 0.0;
    var cubic = false, quad = false;
    switch (cmd.toUpperCase()) {
      case 'M':
        x = ox + n();
        y = oy + n();
        p.moveTo(x, y);
        sx = x;
        sy = y;
        // further pairs are line-tos
        cmd = rel ? 'l' : 'L';
      case 'L':
        x = ox + n();
        y = oy + n();
        p.lineTo(x, y);
      case 'H':
        x = ox + n();
        p.lineTo(x, y);
      case 'V':
        y = oy + n();
        p.lineTo(x, y);
      case 'C':
        final x1 = ox + n(), y1 = oy + n(), x2 = ox + n(), y2 = oy + n();
        x = ox + n();
        y = oy + n();
        p.cubicTo(x1, y1, x2, y2, x, y);
        cx = x2;
        cy = y2;
        cubic = true;
      case 'S':
        // the first control point mirrors the last curve's second one through the current point
        final x1 = lastCubic && cx != null ? 2 * x - cx : x;
        final y1 = lastCubic && cy != null ? 2 * y - cy : y;
        final x2 = ox + n(), y2 = oy + n();
        x = ox + n();
        y = oy + n();
        p.cubicTo(x1, y1, x2, y2, x, y);
        cx = x2;
        cy = y2;
        cubic = true;
      case 'Q':
        final x1 = ox + n(), y1 = oy + n();
        x = ox + n();
        y = oy + n();
        p.quadraticBezierTo(x1, y1, x, y);
        cx = x1;
        cy = y1;
        quad = true;
      case 'T':
        final x1 = lastQuad && cx != null ? 2 * x - cx : x;
        final y1 = lastQuad && cy != null ? 2 * y - cy : y;
        x = ox + n();
        y = oy + n();
        p.quadraticBezierTo(x1, y1, x, y);
        cx = x1;
        cy = y1;
        quad = true;
      case 'Z':
        p.close();
        x = sx;
        y = sy;
        cmd = null;
      default:
        i++;
    }
    lastCubic = cubic;
    lastQuad = quad;
  }
  return p;
}
