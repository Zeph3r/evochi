// A live voxel model (tools/art/live_export.py): the Eggling's faces at rest, posed and drawn every frame
// instead of played from pre-rendered clips. Pure Dart: each face is moved with its part (the body, or one of
// the four feet), lit as the clips' renderer lights it (its smoothed normal, its occlusion, the same light),
// sorted far to near and drawn as coloured triangles, with a dark outline round the whole. Its face and markings
// are the decals the clips project onto it, carried with the body.
//
// A pose (LivePose) is the rig the acting clips are keyed in (tools/art/acting.py): squash (height, volume
// kept), lean (degrees, a shear: the feet stay down), puff, roll / yaw / pitch (degrees), root (where it stands,
// world units) and each foot's offset. Poses blend channel by channel, so one movement eases into the next.

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/widgets.dart';

/// the rig's channels: squash lean puff roll yaw pitch, root x y z, then per foot (dy dz dx): its left front,
/// right front, left back, right back (acting.py's FN FF BN BF)
class LivePose {
  LivePose([List<double>? v]) : v = Float64List.fromList(v ?? rest);
  final Float64List v;

  static const channels = 21;
  static final rest = [1.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, ...List.filled(12, 0.0)];
  static const names = ['squash', 'lean', 'puff', 'roll', 'yaw', 'pitch', 'rx', 'ry', 'rz'];

  double get squash => v[0];
  double get lean => v[1];
  double get puff => v[2];
  double get roll => v[3];
  double get yaw => v[4];
  double get pitch => v[5];

  /// foot [k] (0 left front, 1 right front, 2 left back, 3 right back): (dy, dz, dx)
  (double, double, double) foot(int k) => (v[9 + 3 * k], v[10 + 3 * k], v[11 + 3 * k]);

  LivePose copy() => LivePose(v);

  static LivePose lerp(LivePose a, LivePose b, double t) =>
      LivePose([for (var i = 0; i < channels; i++) a.v[i] + (b.v[i] - a.v[i]) * t]);
}

// the six faces of a voxel: its normal and four corners (from its low corner), as voxel.py's FACES
const _faceN = [
  [1, 0, 0], [-1, 0, 0], [0, 1, 0], [0, -1, 0], [0, 0, 1], [0, 0, -1],
];
const _faceC = [
  [[1, 0, 0], [1, 1, 0], [1, 1, 1], [1, 0, 1]],
  [[0, 0, 0], [0, 0, 1], [0, 1, 1], [0, 1, 0]],
  [[0, 1, 0], [0, 1, 1], [1, 1, 1], [1, 1, 0]],
  [[0, 0, 0], [1, 0, 0], [1, 0, 1], [0, 0, 1]],
  [[0, 0, 1], [1, 0, 1], [1, 1, 1], [0, 1, 1]],
  [[0, 0, 0], [0, 1, 0], [1, 1, 0], [1, 0, 0]],
];

// a part's pose foot index: body none; foot_ln (left front) 0, foot_lf (left back) 2, foot_rn (right front) 1,
// foot_rf (right back) 3; and which side it is on (a foot's dx is mirrored by its side)
const _partFoot = [-1, 0, 2, 1, 3];
const _partSide = [0.0, -1.0, -1.0, 1.0, 1.0];

class LiveModel {
  LiveModel._(this.meta, this.n, this.corners, this.dir, this.part, this.mat, this.ao, this.normals, this._decals);

  final Map<String, dynamic> meta;
  final int n;
  final Float32List corners; // n x 4 x 3, world units at rest
  final Uint8List dir, part, mat, ao;
  final Float32List normals; // n x 3, smoothed
  final Map<String, Map<String, LiveDecals>> _decals; // palette -> set -> quads

  List<String> get palettes => (meta['palettes'] as Map).keys.cast<String>().toList();
  List<String> get expressions => [for (final s in meta['decalSets'] as List) if (s['name'] != 'pattern') s['name'] as String];
  double get top => (meta['top'] as num).toDouble();

  static final _cache = <String, Future<LiveModel>>{};

  /// the model in [dir] (assets/live/<name>), loaded once
  static Future<LiveModel> load(String dir) => _cache[dir] ??= _load(dir);

  static Future<LiveModel> _load(String base) async {
    final meta = jsonDecode(await rootBundle.loadString('$base/model.json')) as Map<String, dynamic>;
    final fb = (await rootBundle.load('$base/faces.bin')).buffer.asUint8List();
    final n = meta['faces'] as int;
    final res = (meta['res'] as num).toDouble();
    final lo = [for (final x in meta['lo'] as List) (x as num).toDouble()];
    final corners = Float32List(n * 12);
    final dir = Uint8List(n), part = Uint8List(n), mat = Uint8List(n), ao = Uint8List(n);
    final normals = Float32List(n * 3);
    final bd = ByteData.sublistView(fb);
    for (var f = 0; f < n; f++) {
      final o = f * 10;
      final i = fb[o], j = fb[o + 1], k = fb[o + 2], d = fb[o + 3];
      dir[f] = d;
      mat[f] = fb[o + 4];
      part[f] = fb[o + 5];
      ao[f] = fb[o + 6];
      for (var a = 0; a < 3; a++) {
        normals[f * 3 + a] = bd.getInt8(o + 7 + a) / 127.0;
      }
      for (var c = 0; c < 4; c++) {
        final cc = _faceC[d][c];
        corners[f * 12 + c * 3] = (i + lo[0] + cc[0]) / res;
        corners[f * 12 + c * 3 + 1] = (j + lo[1] + cc[1]) / res;
        corners[f * 12 + c * 3 + 2] = (k + lo[2] + cc[2]) / res;
      }
    }
    final sets = meta['decalSets'] as List;
    final decals = <String, Map<String, LiveDecals>>{};
    for (final p in (meta['palettes'] as Map).keys.cast<String>()) {
      final b = (await rootBundle.load('$base/decals_$p.bin')).buffer.asUint8List();
      final out = <String, LiveDecals>{};
      var off = 0;
      for (final s in sets) {
        final cnt = s['count'] as int;
        out[s['name'] as String] = LiveDecals.parse(b, off, cnt);
        off += cnt * 32;
      }
      decals[p] = out;
    }
    return LiveModel._(meta, n, corners, dir, part, mat, ao, normals, decals);
  }

  LiveDecals? decals(String palette, String set) => _decals[palette]?[set];
}

/// quads lying on the body (its markings, its face in one expression)
class LiveDecals {
  LiveDecals(this.n, this.pts, this.rgb, this.lit, this.normal);
  final int n;
  final Float32List pts; // n x 4 x 3
  final Uint8List rgb; // n x 3
  final Float32List lit; // n
  final Float32List normal; // n x 3

  static LiveDecals parse(Uint8List b, int off, int n) {
    final bd = ByteData.sublistView(b);
    final pts = Float32List(n * 12), lit = Float32List(n), normal = Float32List(n * 3);
    final rgb = Uint8List(n * 3);
    for (var q = 0; q < n; q++) {
      final o = off + q * 32;
      for (var a = 0; a < 12; a++) {
        pts[q * 12 + a] = bd.getInt16(o + a * 2, Endian.little) / 64.0;
      }
      rgb[q * 3] = b[o + 24];
      rgb[q * 3 + 1] = b[o + 25];
      rgb[q * 3 + 2] = b[o + 26];
      lit[q] = b[o + 27] / 255.0;
      for (var a = 0; a < 3; a++) {
        normal[q * 3 + a] = bd.getInt8(o + 28 + a) / 127.0;
      }
    }
    return LiveDecals(n, pts, rgb, lit, normal);
  }
}

/// a 3x3 matrix (row major) and a translation
class _Affine {
  _Affine(this.m, this.t);
  final List<double> m; // 9
  final List<double> t; // 3
}

List<double> _mul(List<double> a, List<double> b) => [
      for (var r = 0; r < 3; r++)
        for (var c = 0; c < 3; c++) a[r * 3] * b[c] + a[r * 3 + 1] * b[3 + c] + a[r * 3 + 2] * b[6 + c]
    ];

List<double> _inverseT(List<double> m) {
  // (m^-1)^T: the cofactor matrix over the determinant
  final a = m[0], b = m[1], c = m[2], d = m[3], e = m[4], f = m[5], g = m[6], h = m[7], i = m[8];
  final A = e * i - f * h, B = -(d * i - f * g), C = d * h - e * g;
  final D = -(b * i - c * h), E = a * i - c * g, F = -(a * h - b * g);
  final G = b * f - c * e, H = -(a * f - c * d), I = a * e - b * d;
  final det = a * A + b * B + c * C;
  final k = det.abs() < 1e-12 ? 0.0 : 1 / det;
  return [A * k, B * k, C * k, D * k, E * k, F * k, G * k, H * k, I * k];
}

/// draws a LiveModel in a pose
class LiveRenderer {
  LiveRenderer(this.model);
  final LiveModel model;

  // scratch, reused frame to frame
  late final Float32List _pos = Float32List(model.n * 12);
  final _order = <int>[];
  final _depth = <double>[];

  /// the rotation (R = Ry(yaw) Rx(pitch) Rz(roll), as characters.head_rotation)
  static List<double> rotation(double pitchDeg, double yawDeg, double rollDeg) {
    final p = pitchDeg * math.pi / 180, y = yawDeg * math.pi / 180, r = rollDeg * math.pi / 180;
    final rx = <double>[1, 0, 0, 0, math.cos(p), math.sin(p), 0, -math.sin(p), math.cos(p)];
    final ry = <double>[math.cos(y), 0, math.sin(y), 0, 1, 0, -math.sin(y), 0, math.cos(y)];
    final rz = <double>[math.cos(r), math.sin(r), 0, -math.sin(r), math.cos(r), 0, 0, 0, 1];
    return _mul(_mul(ry, rx), rz);
  }

  /// each part's placement for [pose]: p' = R (A (p + off - Ps) + Ps - Pt) + Pt + root
  List<_Affine> _parts(LivePose pose) {
    final ps = [for (final x in model.meta['squashPivot'] as List) (x as num).toDouble()];
    final pt = [for (final x in model.meta['turnPivot'] as List) (x as num).toDouble()];
    final sq = pose.squash.clamp(0.4, 2.0), pf = pose.puff;
    final tl = math.tan(pose.lean * math.pi / 180);
    final s = <double>[pf / math.sqrt(sq), 0, 0, 0, pf * sq, 0, 0, 0, pf / math.sqrt(sq)];
    final sh = <double>[1, 0, 0, 0, 1, 0, 0, tl, 1];
    final a = _mul(sh, s);
    final r = rotation(pose.pitch, pose.yaw, pose.roll);
    final ra = _mul(r, a);
    final out = <_Affine>[];
    for (var k = 0; k < 5; k++) {
      var off = <double>[0, 0, 0];
      if (_partFoot[k] >= 0) {
        final (dy, dz, dx) = pose.foot(_partFoot[k]);
        off = [_partSide[k] * dx, dy, dz];
      }
      // t = R (A (off - Ps) + Ps - Pt) + Pt + root
      final u = [for (var i = 0; i < 3; i++) off[i] - ps[i]];
      final au = [for (var i = 0; i < 3; i++) a[i * 3] * u[0] + a[i * 3 + 1] * u[1] + a[i * 3 + 2] * u[2] + ps[i] - pt[i]];
      final t = [for (var i = 0; i < 3; i++) r[i * 3] * au[0] + r[i * 3 + 1] * au[1] + r[i * 3 + 2] * au[2] + pt[i] + pose.v[6 + i]];
      out.add(_Affine(ra, t));
    }
    return out;
  }

  /// paints the model standing at [anchor] (where its spot lands on screen), [scale] px a unit
  void paint(Canvas canvas, Offset anchor, double scale, LivePose pose,
      {String palette = 'amber', String expression = 'default', double camYaw = 18, double camPitch = 13, double outlinePx = 2.6}) {
    final meta = model.meta;
    final pal = (meta['palettes'] as Map)[palette] as Map? ?? (meta['palettes'] as Map).values.first as Map;
    final mats = [for (final c in pal['mats'] as List) [for (final x in c as List) (x as num).toDouble()]];
    final outline = [for (final x in pal['outline'] as List) (x as num).toInt()];
    final li = meta['light'] as Map;
    final key = [for (final x in li['key'] as List) (x as num).toDouble()];
    final kl = math.sqrt(key[0] * key[0] + key[1] * key[1] + key[2] * key[2]);
    final L = [key[0] / kl, key[1] / kl, key[2] / kl];
    final keyCol = [for (final x in li['keyCol'] as List) (x as num).toDouble()];
    final fillCol = [for (final x in li['fillCol'] as List) (x as num).toDouble()];
    final amb = (li['ambient'] as num).toDouble(), keyAmt = (li['keyAmt'] as num).toDouble();
    // the camera (orthographic): toward it d, across r, up u
    final cy = camYaw * math.pi / 180, cp = camPitch * math.pi / 180;
    final d = [math.sin(cy) * math.cos(cp), math.sin(cp), math.cos(cy) * math.cos(cp)];
    final rr = [math.cos(cy), 0.0, -math.sin(cy)];
    final uu = [d[1] * rr[2] - d[2] * rr[1], d[2] * rr[0] - d[0] * rr[2], d[0] * rr[1] - d[1] * rr[0]];
    final parts = _parts(pose);
    final nmat = _inverseT(parts[0].m); // normals: (R A)^-T, the same for every part
    // which way each face direction points once posed, and whether it can be seen
    final dirN = [
      for (final fn in _faceN)
        () {
          final x = nmat[0] * fn[0] + nmat[1] * fn[1] + nmat[2] * fn[2];
          final y = nmat[3] * fn[0] + nmat[4] * fn[1] + nmat[5] * fn[2];
          final z = nmat[6] * fn[0] + nmat[7] * fn[1] + nmat[8] * fn[2];
          return x * d[0] + y * d[1] + z * d[2] > 1e-6;
        }()
    ];
    final m = model;
    _order.clear();
    _depth.clear();
    final cols = <int>[];
    final shown = <int>[];
    for (var f = 0; f < m.n; f++) {
      if (!dirN[m.dir[f]]) continue;
      final P = parts[m.part[f]];
      final a = P.m, t = P.t;
      var cx = 0.0, cyy = 0.0, cz = 0.0;
      for (var c = 0; c < 4; c++) {
        final o = f * 12 + c * 3;
        final x = m.corners[o], y = m.corners[o + 1], z = m.corners[o + 2];
        final X = a[0] * x + a[1] * y + a[2] * z + t[0];
        final Y = a[3] * x + a[4] * y + a[5] * z + t[1];
        final Z = a[6] * x + a[7] * y + a[8] * z + t[2];
        _pos[o] = X;
        _pos[o + 1] = Y;
        _pos[o + 2] = Z;
        cx += X;
        cyy += Y;
        cz += Z;
      }
      // its light: the smoothed normal, turned with it
      final sx = m.normals[f * 3], sy = m.normals[f * 3 + 1], sz = m.normals[f * 3 + 2];
      var nx = nmat[0] * sx + nmat[1] * sy + nmat[2] * sz;
      var ny = nmat[3] * sx + nmat[4] * sy + nmat[5] * sz;
      var nz = nmat[6] * sx + nmat[7] * sy + nmat[8] * sz;
      final nl = math.sqrt(nx * nx + ny * ny + nz * nz) + 1e-9;
      nx /= nl;
      ny /= nl;
      nz /= nl;
      final diff = math.max(0.0, nx * L[0] + ny * L[1] + nz * L[2]);
      final hemi = 0.5 + 0.5 * ny;
      final occ = m.ao[f] / 200.0;
      final alb = mats[m.mat[f]];
      int ch(int i) => (alb[i] * (amb * (0.82 + 0.18 * hemi) * fillCol[i] + keyAmt * diff * keyCol[i]) * occ).round().clamp(0, 255);
      cols.add(0xFF000000 | (ch(0) << 16) | (ch(1) << 8) | ch(2));
      shown.add(f);
      _depth.add(-((cx / 4) * d[0] + (cyy / 4) * d[1] + (cz / 4) * d[2]));
    }
    // its markings and face, carried with the body, a little toward you so they lie over it
    final decalPos = <double>[];
    final decalCol = <int>[];
    final decalDepth = <double>[];
    for (final set in ['pattern', expression]) {
      final dc = m.decals(palette, set) ?? m.decals(palette, 'default');
      if (dc == null) continue;
      final P = parts[0];
      final a = P.m, t = P.t;
      for (var q = 0; q < dc.n; q++) {
        final sx = dc.normal[q * 3], sy = dc.normal[q * 3 + 1], sz = dc.normal[q * 3 + 2];
        var nx = nmat[0] * sx + nmat[1] * sy + nmat[2] * sz;
        var ny = nmat[3] * sx + nmat[4] * sy + nmat[5] * sz;
        var nz = nmat[6] * sx + nmat[7] * sy + nmat[8] * sz;
        final nl = math.sqrt(nx * nx + ny * ny + nz * nz) + 1e-9;
        nx /= nl;
        ny /= nl;
        nz /= nl;
        if (nx * d[0] + ny * d[1] + nz * d[2] < 0.08) continue;
        var cx = 0.0, cyy = 0.0, cz = 0.0;
        for (var c = 0; c < 4; c++) {
          final o = q * 12 + c * 3;
          final x = dc.pts[o], y = dc.pts[o + 1], z = dc.pts[o + 2];
          final X = a[0] * x + a[1] * y + a[2] * z + t[0];
          final Y = a[3] * x + a[4] * y + a[5] * z + t[1];
          final Z = a[6] * x + a[7] * y + a[8] * z + t[2];
          decalPos..add(X)..add(Y)..add(Z);
          cx += X;
          cyy += Y;
          cz += Z;
        }
        final lit = dc.lit[q];
        final diff = math.max(0.0, nx * L[0] + ny * L[1] + nz * L[2]);
        final hemi = 0.5 + 0.5 * ny;
        int ch(int i) {
          final base = dc.rgb[q * 3 + i].toDouble();
          final shaded = (base * (amb * (0.82 + 0.18 * hemi) * fillCol[i] + keyAmt * diff * keyCol[i])).clamp(0.0, 255.0);
          return (base * (1 - lit) + shaded * lit).round().clamp(0, 255);
        }
        decalCol.add(0xFF000000 | (ch(0) << 16) | (ch(1) << 8) | ch(2));
        decalDepth.add(-((cx / 4) * d[0] + (cyy / 4) * d[1] + (cz / 4) * d[2]) - 0.3);
      }
    }
    // far to near
    final nb = shown.length, nd = decalCol.length;
    final idx = List<int>.generate(nb + nd, (i) => i);
    double depthOf(int i) => i < nb ? _depth[i] : decalDepth[i - nb];
    idx.sort((p, q) => depthOf(q).compareTo(depthOf(p)));
    final pos = Float32List((nb + nd) * 12);
    final col = Int32List((nb + nd) * 6);
    var w = 0;
    void quad(double x0, double y0, double x1, double y1, double x2, double y2, double x3, double y3, int c) {
      final o = w * 12;
      pos[o] = x0;
      pos[o + 1] = y0;
      pos[o + 2] = x1;
      pos[o + 3] = y1;
      pos[o + 4] = x2;
      pos[o + 5] = y2;
      pos[o + 6] = x0;
      pos[o + 7] = y0;
      pos[o + 8] = x2;
      pos[o + 9] = y2;
      pos[o + 10] = x3;
      pos[o + 11] = y3;
      for (var k = 0; k < 6; k++) {
        col[w * 6 + k] = c;
      }
      w++;
    }

    (double, double) proj(double x, double y, double z) =>
        (anchor.dx + (x * rr[0] + y * rr[1] + z * rr[2]) * scale, anchor.dy - (x * uu[0] + y * uu[1] + z * uu[2]) * scale);
    for (final i in idx) {
      if (i < nb) {
        final f = shown[i];
        final o = f * 12;
        final (x0, y0) = proj(_pos[o], _pos[o + 1], _pos[o + 2]);
        final (x1, y1) = proj(_pos[o + 3], _pos[o + 4], _pos[o + 5]);
        final (x2, y2) = proj(_pos[o + 6], _pos[o + 7], _pos[o + 8]);
        final (x3, y3) = proj(_pos[o + 9], _pos[o + 10], _pos[o + 11]);
        quad(x0, y0, x1, y1, x2, y2, x3, y3, cols[i]);
      } else {
        final q = i - nb;
        final o = q * 12;
        final (x0, y0) = proj(decalPos[o], decalPos[o + 1], decalPos[o + 2]);
        final (x1, y1) = proj(decalPos[o + 3], decalPos[o + 4], decalPos[o + 5]);
        final (x2, y2) = proj(decalPos[o + 6], decalPos[o + 7], decalPos[o + 8]);
        final (x3, y3) = proj(decalPos[o + 9], decalPos[o + 10], decalPos[o + 11]);
        quad(x0, y0, x1, y1, x2, y2, x3, y3, decalCol[q]);
      }
    }
    final verts = ui.Vertices.raw(ui.VertexMode.triangles, pos, colors: col);
    // the outline: the whole drawn dark and grown, under it
    if (outlinePx > 0) {
      final oc = Color.fromARGB(255, outline[0], outline[1], outline[2]);
      canvas.saveLayer(null, Paint()
        ..imageFilter = ui.ImageFilter.dilate(radiusX: outlinePx, radiusY: outlinePx)
        ..colorFilter = ColorFilter.mode(oc, BlendMode.srcIn));
      canvas.drawVertices(verts, BlendMode.dst, Paint());
      canvas.restore();
    }
    canvas.drawVertices(verts, BlendMode.dst, Paint());
  }
}
