// The Lumen Wilds' art, loaded for a map: the walkers (tools/art/walk.py: per gait a sheet of 8 directions
// x idle + 8 frames, with the waddle, footfall squash and body lift per frame, and the wearables per
// direction) and a map (tools/art/wilds_maps.py: the ground in tiles, the props, the walk grid, the
// spots, Sher's camp, the minimap).
//
// World units: x right, z toward you (down the screen). The map camera maps world (x, 0, z) to image
// pixels origin + (x, z * sin(pitch)) * scale, for the ground and props (their own scale) and the walkers
// (all drawn as if 6 px per unit, so the bigger stages read a little bigger, not three times).

import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/services.dart';

const wildsBase = 'assets/art/wilds/';

/// The pixels per unit every walker sheet is drawn at (see walk.py STAGE_SCALE).
const walkerDrawScale = 6.0;

Future<ui.Image> _img(String path) async {
  final data = await rootBundle.load(path);
  final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
  return (await codec.getNextFrame()).image;
}

Future<Map<String, dynamic>> _json(String f) async => (jsonDecode(await rootBundle.loadString(wildsBase + f)) as Map).cast<String, dynamic>();

List<double> _nums(Object? l) => [for (final v in (l as List? ?? const [])) (v as num).toDouble()];

class WildsGait {
  WildsGait(this.img, this.roll, this.squash, this.lift, this.cycle);
  final ui.Image img;
  final List<double> roll, squash, lift;
  final double cycle; // world units per walk cycle, as drawn
}

class WalkerArt {
  WalkerArt({required this.fw, required this.fh, required this.gx, required this.gy, required this.radius, required this.gaits, required this.wear});
  final double fw, fh, gx, gy, radius;
  final Map<String, WildsGait> gaits; // walk, run
  final Map<String, ui.Image> wear; // item id -> one row, a direction per frame

  WildsGait gait(bool running) => (running ? gaits['run'] : null) ?? gaits['walk']!;

  static Future<WalkerArt> load(String key, String variant, {Iterable<String> wearing = const []}) async {
    final walk = await _json('wilds_walk.json');
    final w = ((walk['walkers'] as Map)[key] as Map).cast<String, dynamic>();
    final sheetScale = (w['scale'] as num? ?? walkerDrawScale).toDouble();
    final gaits = <String, WildsGait>{};
    for (final e in (w['gaits'] as Map).entries) {
      final g = (e.value as Map).cast<String, dynamic>();
      final sheets = (g['sheets'] as Map).cast<String, dynamic>();
      if (sheets.isEmpty) continue;
      final file = (sheets[variant] ?? sheets['amber'] ?? sheets.values.first) as String;
      gaits[e.key as String] = WildsGait(
        await _img(wildsBase + file),
        _nums(g['roll']),
        _nums(g['squash']),
        _nums(g['lift']),
        // the stride is in the walker's own units; drawn at walkerDrawScale it covers less ground
        (g['cycle'] as num? ?? 10).toDouble() * sheetScale / walkerDrawScale,
      );
    }
    final wear = <String, ui.Image>{};
    final wm = (w['wear'] as Map?)?.cast<String, dynamic>() ?? const {};
    for (final id in wearing) {
      final m = wm[id] as Map?;
      if (m != null) wear[id] = await _img(wildsBase + (m['file'] as String));
    }
    final g = w['ground'] as List;
    return WalkerArt(
      fw: (w['frameW'] as num).toDouble(),
      fh: (w['frameH'] as num).toDouble(),
      gx: (g[0] as num).toDouble(),
      gy: (g[1] as num).toDouble(),
      radius: (w['radius'] as num? ?? 9).toDouble(),
      gaits: gaits,
      wear: wear,
    );
  }
}

class PropArt {
  PropArt(this.img, this.ax, this.ay, this.scale);
  final ui.Image img;
  final double ax, ay, scale;
}

class MapProp {
  const MapProp(this.kind, this.x, this.z, this.flip);
  final String kind;
  final double x, z;
  final bool flip;
}

class MapSpot {
  MapSpot(Map<String, dynamic> j)
      : id = j['id'] as String,
        kind = j['kind'] as String,
        x = (j['x'] as num).toDouble(),
        z = (j['z'] as num).toDouble(),
        r = (j['r'] as num).toDouble(),
        label = j['label'] as String? ?? 'Look',
        title = j['title'] as String? ?? '',
        text = j['text'] as String? ?? '',
        need = (j['need'] as num?)?.toInt();
  final String id, kind, label, title, text;
  final double x, z, r;
  final int? need; // level needed (a gate)
}

class GroundTile {
  GroundTile(this.img, this.rect);
  final ui.Image img;
  final Rect rect; // in ground pixels
}

class WildsMap {
  WildsMap._(this.j);
  final Map<String, dynamic> j;
  late final List<GroundTile> tiles;
  late final Map<String, PropArt> propArt;
  late final List<MapProp> props;
  late final List<(double, double, double)> blocks;
  late final List<MapSpot> spots;
  late final ui.Image minimap;
  late final Uint8List _grid;

  String get name => j['name'] as String;
  String get floor => j['floor'] as String? ?? '';
  String get objective => j['objective'] as String? ?? '';
  double get pitch => (j['pitch'] as num).toDouble();
  double get sinP => math.sin(pitch * math.pi / 180);
  double get scale => (_ground['scale'] as num? ?? j['scale'] as num).toDouble();
  Map<String, dynamic> get _ground => (j['ground'] as Map).cast<String, dynamic>();
  double get groundW => (_ground['w'] as num).toDouble();
  double get groundH => (_ground['h'] as num).toDouble();
  Offset get origin => Offset(((_ground['origin'] as List)[0] as num).toDouble(), ((_ground['origin'] as List)[1] as num).toDouble());
  Rect get bounds {
    final b = _nums(j['bounds']);
    return Rect.fromLTRB(b[0], b[1], b[2], b[3]);
  }

  /// Where you arrive: (x, z) and the direction index you face.
  (double, double, int) get start {
    final s = (j['start'] as Map).cast<String, dynamic>();
    const dirs = ['S', 'SE', 'E', 'NE', 'N', 'NW', 'W', 'SW'];
    return ((s['x'] as num).toDouble(), (s['z'] as num).toDouble(), math.max(0, dirs.indexOf(s['dir'] as String? ?? 'N')));
  }

  List<(double, double, String)> get fx => [
        for (final f in (j['fx'] as List? ?? const []))
          (((f as Map)['x'] as num).toDouble(), (f['z'] as num).toDouble(), f['kind'] as String),
      ];

  (double, double, List<Offset>)? get sher {
    final s = (j['sher'] as Map?)?.cast<String, dynamic>();
    if (s == null) return null;
    return (
      (s['x'] as num).toDouble(),
      (s['z'] as num).toDouble(),
      [for (final p in s['route'] as List) Offset(((p as List)[0] as num).toDouble(), (p[1] as num).toDouble())],
    );
  }

  /// The world rectangle the minimap covers (the slab).
  Rect get miniWorld {
    final g = (j['grid'] as Map).cast<String, dynamic>();
    final x0 = (g['x0'] as num).toDouble(), z0 = (g['z0'] as num).toDouble();
    final c = (g['cell'] as num).toDouble();
    return Rect.fromLTWH(x0, z0, (g['cols'] as num) * c, (g['rows'] as num) * c);
  }

  /// Water and the like: true where nobody can stand.
  bool blocked(double x, double z) {
    final g = (j['grid'] as Map).cast<String, dynamic>();
    final c = (g['cell'] as num).toDouble();
    final cols = (g['cols'] as num).toInt(), rows = (g['rows'] as num).toInt();
    final i = ((x - (g['x0'] as num)) / c).floor(), k = ((z - (g['z0'] as num)) / c).floor();
    if (i < 0 || k < 0 || i >= cols || k >= rows) return true;
    final bit = k * cols + i;
    return (_grid[bit >> 3] >> (7 - (bit & 7))) & 1 == 1;
  }

  static Future<WildsMap> load(String id) async {
    final m = WildsMap._(await _json('wilds_map_$id.json'));
    final g = m._ground;
    m.tiles = [
      for (final t in g['tiles'] as List)
        GroundTile(await _img(wildsBase + ((t as Map)['image'] as String)),
            Rect.fromLTWH((t['x'] as num).toDouble(), (t['y'] as num).toDouble(), (t['w'] as num).toDouble(), (t['h'] as num).toDouble())),
    ];
    final images = (m.j['images'] as Map).cast<String, dynamic>();
    m.propArt = {};
    for (final e in images.entries) {
      final p = (e.value as Map).cast<String, dynamic>();
      final a = p['anchor'] as List;
      m.propArt[e.key] = PropArt(await _img(wildsBase + (p['image'] as String)), (a[0] as num).toDouble(), (a[1] as num).toDouble(),
          (p['scale'] as num? ?? m.scale).toDouble());
    }
    m.props = [
      for (final p in m.j['props'] as List)
        MapProp((p as Map)['kind'] as String, (p['x'] as num).toDouble(), (p['z'] as num).toDouble(), p['flip'] == true),
    ];
    m.blocks = [
      for (final b in m.j['blocks'] as List) (((b as List)[0] as num).toDouble(), (b[1] as num).toDouble(), (b[2] as num).toDouble()),
    ];
    m.spots = [for (final s in m.j['spots'] as List) MapSpot((s as Map).cast<String, dynamic>())];
    m.minimap = await _img(wildsBase + ((m.j['minimap'] as Map)['image'] as String));
    m._grid = base64Decode(((m.j['grid'] as Map)['blocked'] as String));
    return m;
  }
}
