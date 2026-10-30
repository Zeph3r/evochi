part of 'boss_intro.dart';

/// Your Evochi's leap clear of the Forgotten Sentinel's beam (tools/art/cine_jump.py, cine_jump_export.py): 30 fps
/// of a posed, articulated leap from the entrance's camera, in its colour and with whatever it wears, and where the
/// body is over the ground each frame. Positions are the cells' pixels measured from where it stood at the start;
/// a cell is drawn at  from + (root[i] - ground) * k.
class JumpArt {
  JumpArt._(this.sheet, this.wear, this.cell, this.cols, this.fps, this.n, this.ground, this.root, this.shadow, this.feet,
      this.strike, this.beamDir, this.aim, this.beamOn, this.hit, this.beamOff, this.lift, this.land, this.end);
  final ui.Image sheet;
  final List<ui.Image> wear;
  final Size cell;
  final int cols, fps, n;
  final Offset ground;
  final List<Offset> root;

  /// per frame: the shadow's centre on the ground, and how high the lowest foot is over it (world units)
  final List<(Offset, double)> shadow;
  final List<List<FootContact>> feet;
  final Offset strike, beamDir;
  final double aim, beamOn, hit, beamOff, lift, land, end;

  static Future<JumpArt?> load(int stage, String palette, [Iterable<String> worn = const []]) async {
    try {
      final j = (jsonDecode(await rootBundle.loadString('${wildsBase}wilds_jump.json')) as Map).cast<String, dynamic>();
      final st = (j['s0${stage.clamp(1, 3)}'] as Map?)?.cast<String, dynamic>();
      if (st == null) return null;
      final sheets = (st['sheets'] as Map).cast<String, dynamic>();
      final wm = ((st['wear'] as Map?) ?? const {}).cast<String, dynamic>();
      if (worn.any((k) => wm[k] == null)) return null; // a piece without its frames: the older dodge
      final b = (j['beam'] as Map).cast<String, dynamic>();
      double d(Map m, String k) => (m[k] as num).toDouble();
      return JumpArt._(
        await _img(wildsBase + ((sheets[palette] ?? sheets['amber']) as String)),
        [for (final k in worn) await _img(wildsBase + (wm[k] as String))],
        Size(d(st, 'w'), d(st, 'h')),
        (j['cols'] as num).toInt(),
        (j['fps'] as num).toInt(),
        (st['n'] as num).toInt(),
        _pt(st['ground']),
        [for (final p in st['root'] as List) _pt(p)],
        [for (final p in st['shadow'] as List) (_pt(p), ((p as List)[2] as num).toDouble())],
        [
          for (final f in st['feet'] as List)
            [for (final c in f as List) FootContact(_pt(c), ((c as List)[2] as num).toDouble(), (c[3] as num).toDouble(), (c[4] as num).toDouble())]
        ],
        _pt(st['strike']),
        _pt(st['beamDir']),
        d(b, 'aim'),
        d(b, 'on'),
        d(b, 'hit'),
        d(b, 'off'),
        d(j, 'off'),
        d(j, 'land'),
        d(st, 'end'),
      );
    } catch (_) {
      return null;
    }
  }

  int frameAt(double u) => (u * fps).floor().clamp(0, n - 1);

  /// where the cell's ground point is, on screen, for frame [i]
  Offset at(int i, Offset from, double k) => from + root[i] * k;

  /// the frame, with what it wears, its ground point at [from] moved by the leap; [k]: screen px per cell px
  void draw(Canvas canvas, int i, Offset from, double k, Paint paint) {
    final o = from + (root[i] - ground) * k;
    final src = Rect.fromLTWH((i % cols) * cell.width, (i ~/ cols) * cell.height, cell.width, cell.height);
    final dst = Rect.fromLTWH(o.dx, o.dy, cell.width * k, cell.height * k);
    canvas.drawImageRect(sheet, src, dst, paint);
    for (final w in wear) {
      canvas.drawImageRect(w, src, dst, paint);
    }
  }
}
