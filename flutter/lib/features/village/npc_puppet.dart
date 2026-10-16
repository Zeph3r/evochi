// A layered villager: floor shadow, body, head (per expression) with a blink overlay, and the arm
// with their prop, animated by the idle / talk / listen loops from the art manifest. Mirrors
// web/src/ui/puppet.js: idle keeps one shared clock (so a rebuild never restarts it), talk and
// listen start fresh when they begin (that start is the reaction).
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../../core/services/asset_manifest.dart';

final _epoch = DateTime.now();

class NpcPuppet extends StatefulWidget {
  const NpcPuppet({
    super.key,
    required this.art,
    required this.width,
    required this.height,
    this.expression = 'neutral',
    this.state = 'idle',
    this.classic = false,
    this.animate = true,
  });
  final NpcPuppetArt art;
  final double width;
  final double height;
  final String expression;
  final String state; // idle | talk | listen
  final bool classic;
  final bool animate;
  @override
  State<NpcPuppet> createState() => _NpcPuppetState();
}

class _NpcPuppetState extends State<NpcPuppet> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker((_) => setState(() {}));
  DateTime _stateStart = DateTime.now();
  bool _blink = false;
  Timer? _blinkTimer;
  final _rng = math.Random();

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(NpcPuppet old) {
    super.didUpdateWidget(old);
    if (old.state != widget.state) _stateStart = DateTime.now();
    if (old.animate != widget.animate) _sync();
  }

  void _sync() {
    if (widget.animate) {
      if (!_ticker.isActive) _ticker.start();
      _scheduleBlink(first: true);
    } else {
      _ticker.stop();
      _blinkTimer?.cancel();
    }
  }

  void _scheduleBlink({bool first = false}) {
    _blinkTimer?.cancel();
    _blinkTimer = Timer(Duration(milliseconds: (first ? 900 : 2400) + _rng.nextInt(3000)), () {
      if (!mounted) return;
      setState(() => _blink = true);
      _blinkTimer = Timer(const Duration(milliseconds: 150), () {
        if (!mounted) return;
        setState(() => _blink = false);
        _scheduleBlink();
      });
    });
  }

  @override
  void dispose() {
    _blinkTimer?.cancel();
    _ticker.dispose();
    super.dispose();
  }

  /// Sample a keyframe track at loop phase t (0..1), easing in and out between keys.
  static List<double> _sample(List<List<double>> keys, double t) {
    if (keys.isEmpty) return const [];
    if (t <= keys.first[0]) return keys.first.sublist(1);
    for (var i = 0; i < keys.length - 1; i++) {
      final a = keys[i];
      final b = keys[i + 1];
      if (t <= b[0]) {
        final span = math.max(1e-6, b[0] - a[0]);
        var u = ((t - a[0]) / span).clamp(0.0, 1.0).toDouble();
        u = u * u * (3 - 2 * u);
        return [for (var k = 1; k < a.length; k++) a[k] + (b[k] - a[k]) * u];
      }
    }
    return keys.last.sublist(1);
  }

  @override
  Widget build(BuildContext context) {
    final art = widget.art;
    final s = widget.width / art.w;
    final anim = widget.animate ? art.anim(widget.state) : null;
    var phase = 0.0;
    if (anim != null) {
      final ms = widget.state == 'idle' ? DateTime.now().difference(_epoch).inMilliseconds : DateTime.now().difference(_stateStart).inMilliseconds;
      phase = (ms % anim.dur) / anim.dur;
    }
    final tracks = anim?.tracks ?? const <String, List<List<double>>>{};
    Widget place(String file, Rect box) => Positioned(
          left: box.left * s,
          top: box.top * s,
          width: box.width * s,
          height: box.height * s,
          child: Image.asset(file, fit: BoxFit.fill, excludeFromSemantics: true, gaplessPlayback: true, filterQuality: FilterQuality.medium),
        );
    Widget? shadow;
    final parts = <Widget>[];
    for (final l in art.layers) {
      if (l.part == 'shadow') {
        shadow = place(l.file(), l.box);
        continue;
      }
      final kids = <Widget>[place(l.file(classic: widget.classic, expr: widget.expression), l.box)];
      final b = l.blink(classic: widget.classic);
      if (b != null && widget.expression != 'happy') {
        kids.add(Positioned(
          left: b.$2.left * s,
          top: b.$2.top * s,
          width: b.$2.width * s,
          height: b.$2.height * s,
          child: Opacity(opacity: _blink ? 1 : 0, child: Image.asset(b.$1, fit: BoxFit.fill, excludeFromSemantics: true, gaplessPlayback: true)),
        ));
      }
      Widget layer = Stack(clipBehavior: Clip.none, children: kids);
      final k = tracks[l.part];
      if (k != null && l.pivot != null) {
        final v = _sample(k, phase); // rot, dx, dy
        layer = Transform(
          origin: Offset(l.pivot!.dx * s, l.pivot!.dy * s),
          transform: Matrix4.identity()
            ..translate(v[1] * widget.width, v[2] * widget.height)
            ..rotateZ(v[0] * math.pi / 180),
          child: layer,
        );
      }
      parts.add(Positioned.fill(child: layer));
    }
    Widget body = Stack(clipBehavior: Clip.none, children: parts);
    final all = tracks['all'];
    if (all != null) {
      final v = _sample(all, phase); // squash, dy
      body = Transform(
        origin: Offset(art.ground.dx * s, art.ground.dy * s),
        transform: Matrix4.identity()
          ..translate(0.0, v[1] * widget.height)
          ..scale(2 - v[0], v[0]),
        child: body,
      );
    }
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: Stack(clipBehavior: Clip.none, children: [if (shadow != null) shadow, Positioned.fill(child: body)]),
    );
  }
}
