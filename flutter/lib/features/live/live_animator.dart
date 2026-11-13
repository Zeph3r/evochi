// The live Eggling's body language: every frame, a pose (live_model.dart's rig) from what the brain is doing
// (game/personality/brain.dart) and how its genes say it moves (Quirks): its pace, how high it hops, how often
// it glances round, how it holds itself, its idle habit, its blink. One action eases into the next (a short
// crossfade from wherever the body was), so nothing restarts or jumps.

import 'dart:math' as math;

import '../../game/personality/brain.dart';
import 'live_model.dart';

class LiveAnimator {
  LiveAnimator(this.brain);
  Brain brain;

  LivePose pose = LivePose();
  String expression = 'default';
  double t = 0;

  Act? _last;
  LivePose? _from;
  double _since = 9;
  double _walk = 0;
  double _nextBlink = 1.5, _blinkUntil = -1;
  double _glance = 0, _glanceTo = 0, _nextGlance = 2, _glanceHold = 0;
  final _rng = math.Random(7);

  static const _fade = 0.28;

  void update(double dt) {
    t += dt;
    final a = brain.act;
    if (!identical(a, _last)) {
      _from = pose.copy();
      _since = 0;
      _last = a;
    }
    _since += dt;
    final target = _poseFor(a, dt);
    final k = (_since / _fade).clamp(0.0, 1.0);
    pose = (_from == null || k >= 1) ? target : LivePose.lerp(_from!, target, k * k * (3 - 2 * k));
    expression = _expression(a);
  }

  String _expression(Act a) {
    var e = a.expr;
    if (a.name == 'sneak' && a.step == 'go') e = 'curious';
    if (a.name == 'pounce' && a.step == 'do') e = 'happy';
    // a blink now and then, its genes setting how often
    if (t > _nextBlink) {
      _blinkUntil = t + 0.13;
      _nextBlink = t + brain.quirks.blink * (0.55 + 0.9 * _rng.nextDouble());
    }
    const blinks = {'default', 'happy', 'curious', 'determined'};
    if (t < _blinkUntil && blinks.contains(e)) return 'blink';
    return e;
  }

  double _sm(double x) {
    final c = x.clamp(0.0, 1.0);
    return c * c * (3 - 2 * c);
  }

  LivePose _poseFor(Act a, double dt) {
    final b = brain, q = b.quirks, s = b.size;
    final p = LivePose();
    final v = p.v;
    final tempo = q.tempo;
    final u = a.stepT;
    // at rest: breathing, its posture
    v[0] = q.crouch * (1 + 0.012 * math.sin(t * 2 * math.pi / (3.2 / tempo)));
    v[1] = q.posture;
    var yaw = b.heading * 180 / math.pi;
    // glances round (the curious ones more), held a moment, eased
    final idleish = a.name == 'idle' || a.name == 'wander' || (a.name == 'look_around');
    if (idleish && t > _nextGlance && _glanceHold <= 0) {
      _glanceTo = (_rng.nextBool() ? 1 : -1) * (18 + 22 * _rng.nextDouble());
      _glanceHold = 0.5 + 0.8 * _rng.nextDouble();
      _nextGlance = t + 1 / q.glance * (0.5 + _rng.nextDouble());
    }
    if (_glanceHold > 0) {
      _glanceHold -= dt;
      if (_glanceHold <= 0) _glanceTo = 0;
    }
    _glance += (_glanceTo - _glance) * (1 - math.exp(-dt * 7));
    // walking: diagonal pairs of feet stepping, a bob, leaning into it
    if (b.speed > 0.1) {
      final gait = a.gait == 'run' || a.gait == 'sneak' ? a.gait : 'walk';
      _walk += dt * b.speed / (s * (gait == 'sneak' ? 0.12 : 0.3)) * math.pi;
      final lift = gait == 'sneak' ? 0.5 : (gait == 'run' ? 2.0 : 1.2);
      final stride = gait == 'sneak' ? 0.8 : (gait == 'run' ? 3.0 : 1.9);
      for (var k = 0; k < 4; k++) {
        final ph = (k == 0 || k == 3) ? _walk : _walk + math.pi;
        v[9 + 3 * k] = lift * math.max(0.0, math.sin(ph));
        v[10 + 3 * k] = stride * math.cos(ph);
      }
      v[7] = s * q.bounce * (gait == 'sneak' ? 0.15 : (gait == 'run' ? 1.6 : 1.0)) * math.sin(_walk).abs();
      v[1] += gait == 'run' ? 9 : (gait == 'sneak' ? 5 : 3);
      if (gait == 'sneak') v[0] *= 0.86;
      if (gait == 'run') v[0] *= 1 + 0.05 * math.cos(2 * _walk);
    } else {
      switch (a.name) {
        case 'idle':
          _idle(v, q.idle, q);
        case 'look_around':
          final lp = u / 2.4;
          final look = lp < 0.4 ? _sm(lp / 0.25) * 35 : (lp < 0.8 ? 35 - 70 * _sm((lp - 0.4) / 0.25) : -35 + 35 * _sm((lp - 0.8) / 0.2));
          yaw += look;
          v[5] = 5;
        case 'inspect':
        case 'sneak':
          if (a.step == 'do') {
            v[1] += 10;
            v[5] = -9 + 3 * math.sin(t * 9);
            v[0] *= 0.95;
          }
        case 'eat':
          if (a.step == 'do') {
            v[1] += 12;
            v[5] = -14 + 4 * math.sin(t * 10);
            v[0] *= 0.96 + 0.03 * math.sin(t * 10);
          }
        case 'pounce':
          if (a.step == 'ready') {
            v[0] = 0.8;
            v[1] += 8;
            v[3] = 4 * math.sin(t * 22);
          } else if (a.step == 'leap') {
            final w = (u / 0.55).clamp(0.0, 1.0);
            v[7] = s * q.hop * 1.7 * math.sin(math.pi * w);
            v[0] = w < 0.15 ? 0.85 : (w > 0.85 ? 0.88 : 1.14);
            v[1] += 12;
            for (var k = 0; k < 4; k++) {
              v[9 + 3 * k] = 1.6 * math.sin(math.pi * w);
            }
          } else if (a.step == 'do') {
            final w = (u / 0.35).clamp(0.0, 1.0);
            v[0] = 0.84 + 0.16 * _sm(w);
            v[3] = 6 * math.sin(t * 16) * (1 - _sm(u / 1.2));
          }
        case 'flee':
        case 'hide':
          if (a.step == 'do') {
            final deep = a.name == 'hide' ? 0.8 : 0.85;
            v[0] = deep;
            v[1] = -6;
            v[3] = 1.6 * math.sin(t * 40) * (1 - b.g('courage'));
          }
        case 'greet':
        case 'bounce':
        case 'beg':
        case 'seek_attention':
          final rate = a.name == 'beg' ? 2.4 : 1.8 * tempo;
          final h = a.name == 'beg' ? 0.04 : (a.name == 'greet' ? q.hop : q.hop * 0.9);
          final ph = (t * math.pi * rate) % math.pi;
          final air = math.sin(ph);
          v[7] = s * h * air;
          v[0] = air < 0.18 ? 0.86 + 0.8 * air : 1.0 + 0.1 * air;
          for (var k = 0; k < 4; k++) {
            v[9 + 3 * k] = 0.9 * air;
          }
          if (a.name == 'greet' || a.name == 'seek_attention') v[3] = 4 * math.sin(t * 8);
          if (a.name == 'beg' || a.name == 'seek_attention') v[5] = 10;
        case 'show_off':
          _signature(v, u, q, s, (dy) => yaw += dy);
        case 'nap':
          final settle = _sm(u / 1.2);
          v[0] = 1 - 0.14 * settle + 0.02 * math.sin(t * 2 * math.pi / 4.2) * settle;
          v[1] = q.posture * (1 - settle) + 4 * settle;
          v[5] = -6 * settle;
        case 'enjoy_pet':
          v[3] = 6 * math.sin(t * 2 * math.pi * 1.6);
          v[0] = 0.96 + 0.03 * math.sin(t * 2 * math.pi * 3.2);
          v[5] = 6;
        default:
          break;
      }
    }
    v[4] = yaw + _glance;
    return p;
  }

  void _idle(List<double> v, String habit, Quirks q) {
    switch (habit) {
      case 'tap': // a front foot tapping, in bursts
        final burst = (t % 3.2) < 1.0;
        if (burst) v[12] = 0.8 * math.max(0.0, math.sin(t * 6 * q.tempo * math.pi));
      case 'sway':
        v[3] = q.sway * math.sin(t * 2 * math.pi / (3.6 / q.tempo));
      case 'wiggle':
        if ((t % 4.5) < 0.7) v[3] = 5 * math.sin(t * 2 * math.pi * 3);
      case 'bob':
        v[0] *= 1 + 0.025 * math.sin(t * 2 * math.pi / (1.6 / q.tempo));
      default: // glance: the glances above
        break;
    }
  }

  /// its showing-off move, from its genes: the lively a double hop, the bubbly a spin, the rest a proud chin lift
  void _signature(List<double> v, double u, Quirks q, double s, void Function(double) turn) {
    final g = brain.genome;
    if (g['energy'] > 0.6) {
      final w = u * q.tempo;
      final first = w < 0.7, k = first ? w / 0.7 : (w - 0.7) / 0.8;
      final h = (first ? 1.0 : 1.4) * q.hop * s;
      final air = math.sin(math.pi * k.clamp(0.0, 1.0));
      v[7] = h * air;
      v[0] = air < 0.15 ? 0.85 : 1.12;
      for (var j = 0; j < 4; j++) {
        v[9 + 3 * j] = 1.2 * air;
      }
    } else if (g['expressiveness'] > 0.6) {
      turn(360 * _sm(u / 1.1));
      v[7] = s * 0.05 * math.sin(math.pi * (u / 1.1).clamp(0.0, 1.0));
      v[3] = 5 * math.sin(u * 14);
    } else {
      final w = _sm(u / 0.5) * (1 - _sm((u - 1.1) / 0.4));
      v[5] = 14 * w;
      v[1] = v[1] - 6 * w;
      v[0] *= 1 + 0.05 * w;
    }
  }
}
