// Personality acting (tools/art/acting.py): a habit performed by the posed body, the face baked in, streamed frame
// by frame from an animated WebP so only the frame on screen is ever decoded, each worn piece posed alongside.
// Which habit plays is the behaviour director's choice (game/personality); this only shows it.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/widgets.dart';

import '../../core/services/asset_manifest.dart';
import '../../game/personality/catalog.dart';
import '../../game/personality/director.dart';
import '../../game/personality/personality.dart';

const actingBase = '${artBase}acting/';

/// One clip as exported: its frames, its box in the stage's full cell (each clip is cropped to what it covers),
/// how high the body is each frame (voxels: the shadow), the body per palette and each worn piece.
class ActingClipDef {
  ActingClipDef(this.id, this.n, this.end, this.box, this.lift, this.body, this.wear);
  final String id;
  final int n;
  final double end;
  final Rect box;
  final List<double> lift;
  final Map<String, String> body, wear;
}

/// A stage's clips: their rate, px per voxel (the hero sprite's), where the body stands in the full cell.
class ActingStage {
  ActingStage(this.fps, this.scale, this.ground, this.clips);
  final double fps, scale;
  final Offset ground;
  final Map<String, ActingClipDef> clips;

  static Future<Map<String, dynamic>?>? _index;
  static final Map<int, ActingStage?> _stages = {};

  /// The clips drawn for [stage], or null when it has none yet (it acts with the scene's simple motions).
  static Future<ActingStage?> load(int stage) async {
    if (_stages.containsKey(stage)) return _stages[stage];
    _index ??= () async {
      try {
        return (jsonDecode(await rootBundle.loadString('${actingBase}acting.json')) as Map).cast<String, dynamic>();
      } catch (_) {
        return null;
      }
    }();
    final j = await _index;
    final st = (j?['s0${stage.clamp(1, 3)}'] as Map?)?.cast<String, dynamic>();
    if (st == null) return _stages[stage] = null;
    double d(Object? v) => (v as num).toDouble();
    final g = st['ground'] as List;
    final clips = <String, ActingClipDef>{};
    ((st['clips'] as Map?) ?? const {}).forEach((k, v) {
      final c = (v as Map).cast<String, dynamic>();
      final b = c['box'] as List;
      clips[k as String] = ActingClipDef(
        k,
        (c['n'] as num).toInt(),
        d(c['end']),
        Rect.fromLTWH(d(b[0]), d(b[1]), d(b[2]), d(b[3])),
        [for (final x in c['lift'] as List) d(x)],
        ((c['body'] as Map?) ?? const {}).cast<String, String>(),
        ((c['wear'] as Map?) ?? const {}).cast<String, String>(),
      );
    });
    return _stages[stage] = ActingStage(d(st['fps']), d(st['scale']), Offset(d(g[0]), d(g[1])), clips);
  }

  /// tests: forget what was loaded
  @visibleForTesting
  static void reset() {
    _index = null;
    _stages.clear();
  }
}

class _Layer {
  _Layer(this.codec);
  final ui.Codec codec;
  ui.Image? image;
  int at = -1;
  bool _busy = false, _gone = false;

  void want(int i, int n, VoidCallback onFrame) {
    if (_busy || _gone || at >= i || at >= n - 1) return;
    _busy = true;
    codec.getNextFrame().then((f) {
      _busy = false;
      if (_gone) {
        f.image.dispose();
        return;
      }
      image?.dispose();
      image = f.image;
      at++;
      onFrame();
      if (at < i) want(i, n, onFrame);
    }, onError: (Object _) {
      _busy = false;
    });
  }

  void dispose() {
    _gone = true;
    image?.dispose();
    image = null;
    codec.dispose();
  }
}

/// One clip being played: the body and the worn pieces, streamed in step.
class ActingPlayer {
  ActingPlayer._(this.stage, this.def, this._layers);
  final ActingStage stage;
  final ActingClipDef def;
  final List<_Layer> _layers;
  int _frame = 0;

  static final Map<String, Future<Uint8List>> _bytes = {};
  static Future<Uint8List> _load(String file) =>
      _bytes.putIfAbsent(file, () async => (await rootBundle.load(actingBase + file)).buffer.asUint8List());

  /// Opens [clip] for [palette] wearing [worn]; null when it can't be shown as worn (a piece without its frames)
  /// or the files aren't there: the caller plays the simple motion instead.
  static Future<ActingPlayer?> open(ActingStage st, String clip, String palette, Iterable<String> worn) async {
    final def = st.clips[clip];
    if (def == null) return null;
    final body = def.body[palette] ?? def.body['amber'];
    if (body == null || worn.any((k) => def.wear[k] == null)) return null;
    try {
      final files = [body, for (final k in worn) def.wear[k]!];
      final layers = <_Layer>[];
      for (final f in files) {
        layers.add(_Layer(await ui.instantiateImageCodec(await _load(f))));
      }
      return ActingPlayer._(st, def, layers);
    } catch (_) {
      return null;
    }
  }

  double get duration => def.n / stage.fps;

  /// the frame for [t] s into the clip (frames only go forward)
  int frameAt(double t) => (t * stage.fps).floor().clamp(0, def.n - 1);

  /// asks for the frame for [t]; [onFrame] when a new one is decoded
  void advance(double t, VoidCallback onFrame) {
    _frame = frameAt(t);
    for (final l in _layers) {
      l.want(_frame, def.n, onFrame);
    }
  }

  /// the first frame is in: it can take over from the still sprite
  bool get ready => _layers.every((l) => l.image != null);

  /// how high the body is now (voxels)
  double get lift => def.lift[_frame.clamp(0, def.lift.length - 1)];

  /// Draws the current frame with the body's ground point at [ground], [s]: screen px per clip px.
  void draw(Canvas canvas, Offset ground, double s, Paint paint) {
    final dst = Rect.fromLTWH(ground.dx + (def.box.left - stage.ground.dx) * s, ground.dy + (def.box.top - stage.ground.dy) * s,
        def.box.width * s, def.box.height * s);
    for (final l in _layers) {
      final im = l.image;
      if (im == null) continue;
      canvas.drawImageRect(im, Rect.fromLTWH(0, 0, im.width.toDouble(), im.height.toDouble()), dst, paint);
    }
  }

  void dispose() {
    for (final l in _layers) {
      l.dispose();
    }
  }
}

// ------------------------------------------------------------------------------------ the directors
final _clock = Stopwatch()..start();

/// One clock for every scene, so a habit's cooldown carries from screen to screen.
double personalityNow() => _clock.elapsedMicroseconds / 1e6;

final _directors = <String, BehaviorDirector>{};

/// The director for this personality, kept while the app runs (its cooldowns and what it did lately).
BehaviorDirector directorFor(Personality p) =>
    _directors.putIfAbsent('${p.seed}:${p.profile}:${p.signature}', () => BehaviorDirector(p));

/// The scene's one-shot reaction kinds, as the personality's contexts (others are the scene's own).
const reactionContexts = {'pet': 'pet', 'play': 'play', 'snack': 'feed', 'reward': 'reward', 'inspect': 'return', 'hatch': 'hatch'};

// ------------------------------------------------------------------------------------ a sprite that acts
/// The hero sprite that performs once when it appears: the hatch reveal plays its signature. Draws the still
/// sprite, then the director's choice for [context] (its clip, or the still sprite with its face).
class ActingSprite extends StatefulWidget {
  const ActingSprite({
    super.key,
    required this.stage,
    required this.palette,
    required this.personality,
    this.context = 'hatch',
    this.behavior,
    this.replay = 0,
    this.height = 130,
    this.delay = const Duration(milliseconds: 350),
    this.director,
    this.onChoice,
    this.semanticLabel,
  });
  final int stage;
  final String palette;
  final Personality personality;
  final String context;

  /// plays this instead of asking the director (the developer preview)
  final BehaviorDef? behavior;

  /// change it to perform again
  final int replay;
  final double height;
  final Duration delay;

  /// the director to ask (default: its live one)
  final BehaviorDirector? director;
  final ValueChanged<Choice>? onChoice;
  final String? semanticLabel;

  @override
  State<ActingSprite> createState() => _ActingSpriteState();
}

class _ActingSpriteState extends State<ActingSprite> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  ui.Image? _atlas;
  ActingPlayer? _player;
  Duration _t = Duration.zero, _start = Duration.zero;
  String _expr = 'happy';
  final _repaint = ValueNotifier(0);
  Timer? _wait;
  int _req = 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick); // made here: made lazily, a first use in dispose would look up a dead tree
    _loadAtlas();
    _wait = Timer(widget.delay, _go);
  }

  @override
  void didUpdateWidget(ActingSprite old) {
    super.didUpdateWidget(old);
    if (old.palette != widget.palette || old.stage != widget.stage) _loadAtlas();
    if (old.replay != widget.replay || old.stage != widget.stage || old.palette != widget.palette) {
      _wait?.cancel();
      _go();
    }
  }

  void _loadAtlas() {
    final e = AssetManifest.instance!.char(widget.stage);
    AtlasCache.load(artBase + e.atlasFile(widget.palette)).then((i) {
      if (mounted) setState(() => _atlas = i);
    });
  }

  Future<void> _go() async {
    if (!mounted) return;
    final req = ++_req;
    _stop();
    final reduce = WidgetsBinding.instance.platformDispatcher.accessibilityFeatures.disableAnimations;
    var b = widget.behavior;
    if (b == null) {
      final c = (widget.director ?? directorFor(widget.personality)).choose(widget.context, personalityNow());
      widget.onChoice?.call(c);
      b = c.behavior;
    }
    final act = b;
    setState(() => _expr = act.exprEnd ?? act.expr);
    final clip = act.clip;
    final st = reduce || clip == null ? null : await ActingStage.load(widget.stage);
    final pl = st == null || clip == null ? null : await ActingPlayer.open(st, clip, widget.palette, const []);
    if (!mounted || req != _req) {
      pl?.dispose();
      return;
    }
    if (pl != null) {
      _player = pl;
      _start = _t;
      pl.advance(0, () => _repaint.value++);
      if (!_ticker.isActive) _ticker.start();
    }
  }

  void _stop() {
    _player?.dispose();
    _player = null;
    if (_ticker.isActive) _ticker.stop();
    _t = Duration.zero;
    _repaint.value++;
  }

  void _tick(Duration t) {
    _t = t;
    final pl = _player;
    if (pl == null) return;
    final u = (t - _start).inMicroseconds / 1e6;
    if (u > pl.duration + 0.05) return _stop();
    if (pl.ready) {
      pl.advance(u, () => _repaint.value++);
    } else {
      _start = t; // it starts when its first frame is in
    }
  }

  @override
  void dispose() {
    _wait?.cancel();
    _ticker.dispose();
    _player?.dispose();
    _repaint.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final e = AssetManifest.instance!.char(widget.stage);
    final s = widget.height / e.h;
    return Semantics(
      image: widget.semanticLabel != null,
      label: widget.semanticLabel,
      child: SizedBox(
        width: e.w * s,
        height: widget.height,
        child: CustomPaint(painter: _ActingSpritePainter(this, s)),
      ),
    );
  }
}

class _ActingSpritePainter extends CustomPainter {
  _ActingSpritePainter(this.st, this.s) : super(repaint: st._repaint);
  final _ActingSpriteState st;
  final double s;

  @override
  void paint(Canvas canvas, Size size) {
    final e = AssetManifest.instance!.char(st.widget.stage);
    final ground = e.anchor('ground') * s;
    final paint = Paint()..filterQuality = FilterQuality.medium;
    final pl = st._player;
    if (pl != null && pl.ready) {
      pl.draw(canvas, ground, s * e.scale / pl.stage.scale, paint);
      return;
    }
    final a = st._atlas;
    if (a == null) return;
    final src = e.frame(st.widget.palette, st._expr);
    canvas.drawImageRect(a, src, Rect.fromLTWH(0, 0, src.width * s, src.height * s), paint);
  }

  @override
  bool shouldRepaint(_ActingSpritePainter old) => true;
}

/// For the developer preview: what a behaviour looks like without its clip (its face, its simple motion).
String describeBehavior(BehaviorDef b) => '${b.kind} · ${b.clip ?? 'no clip'} · ${b.motion} · ${b.expr}${b.exprEnd != null ? ' → ${b.exprEnd}' : ''}';
