// The live brain: what your Evochi does from moment to moment, worked out from who it is (its genome) and how
// it is (its needs) and what is around it (food, something new, a visitor, your touch). Three systems, all
// driven by the genes:
//
//  * Needs that drain and the point at which it acts on them: fullness, rest, fun and company drain at rates its
//    genes set, and each has a threshold its genes set too (a greedy one goes looking for food at 70% full, a
//    dainty one waits until 25%; a sleepy one naps sooner).
//  * Utility AI: every action is scored from its needs and what is around it, then multiplied by its genes (a
//    timid one's flee x2, a friendly one's greet x2); it picks among the best by weighted chance and keeps at
//    what it started unless something clearly better comes up. Actions play out in steps, so combinations
//    emerge: a curious timid one creeps up on something new and bolts when it gets close (less each time, until
//    it is used to it); a curious feisty one stalks it and pounces.
//  * Quirks (quirks()): how it moves, from its genes: its pace, how high it hops, how often it glances round,
//    its posture, its blink, its idle habit. The animator (features/live) reads them.
//
// The world is the floor it stands on, in the model's units (the Eggling is about 30 tall), x across and z
// toward you. Nothing here draws or saves: it is the same on every platform, and testable on its own.

import 'dart:math' as math;

import 'genome.dart';

/// how it is: each 0..1, 1 full
class Needs {
  double fullness = 0.75, rest = 0.85, fun = 0.6, company = 0.65;

  Map<String, double> get all => {'fullness': fullness, 'rest': rest, 'fun': fun, 'company': company};

  void set(String k, double v) {
    v = v.clamp(0.0, 1.0);
    switch (k) {
      case 'fullness':
        fullness = v;
      case 'rest':
        rest = v;
      case 'fun':
        fun = v;
      case 'company':
        company = v;
    }
  }
}

/// how its genes tune its needs: how fast each drains (per second of play) and when it acts on it
class NeedTuning {
  NeedTuning(Genome g)
      : drain = {
          'fullness': 0.0042 * (0.55 + 0.9 * g['appetite']),
          'rest': 0.0026 * (0.6 + 0.8 * g['energy']),
          'fun': 0.0055 * (0.45 + 0.6 * g['curiosity'] + 0.4 * g['energy']),
          'company': 0.0035 * (0.35 + 1.2 * g['sociability']),
        },
        threshold = {
          'fullness': 0.2 + 0.55 * g['appetite'], // goes looking for food below this
          'rest': 0.15 + 0.3 * (1 - g['energy']), // naps below this
          'fun': 0.25 + 0.3 * g['curiosity'], // bored below this
          'company': 0.2 + 0.4 * g['sociability'], // lonely below this
        };
  final Map<String, double> drain;
  final Map<String, double> threshold;
}

/// how it moves, from its genes (the animator reads these)
class Quirks {
  Quirks(Genome g)
      : tempo = 0.75 + 0.55 * g['energy'],
        hop = (0.1 + 0.16 * g['energy']) * (0.7 + 0.6 * g['expressiveness']),
        glance = 0.04 + 0.22 * g['curiosity'],
        posture = -3 + 7 * g['courage'],
        crouch = 1 - 0.07 * (1 - g['courage']),
        sway = 1.0 + 3.0 * (1 - g['energy']),
        blink = 2.4 + 3.0 * (1 - g['expressiveness']),
        bounce = 0.006 + 0.02 * g['energy'],
        idle = _idleOf(g);

  /// its pace (1 average)
  final double tempo;

  /// how high it hops, of its height
  final double hop;

  /// glances round per second when idle
  final double glance;

  /// how it holds itself: degrees forward (bold) or back (timid)
  final double posture;

  /// how low it carries itself (timid ones a touch lower)
  final double crouch;

  /// how far it sways at rest (degrees): the sleepy ones more
  final double sway;

  /// seconds between blinks
  final double blink;

  /// how much it bobs as it walks, of its height
  final double bounce;

  /// its habit while it waits: tap (taps a foot), sway, glance, wiggle, bob
  final String idle;

  static String _idleOf(Genome g) {
    final c = <String, double>{
      'tap': g['energy'] * (1 - g['courage'] * 0.3),
      'sway': 1 - g['energy'],
      'glance': g['curiosity'] * 0.9,
      'wiggle': g['expressiveness'] * 0.95,
      'bob': 0.45,
    };
    return c.entries.reduce((a, b) => b.value > a.value ? b : a).key;
  }
}

/// something on the floor
class Thing {
  Thing(this.kind, this.x, this.z, {this.novelty = 1.0});

  /// food | object | visitor
  final String kind;
  double x, z;

  /// how new it still is to it (an object, a visitor), 0..1
  double novelty;
  double age = 0;
}

/// what it is doing: an action and where it has got to in it
class Act {
  Act(this.name, {this.why = '', this.thing});
  final String name;
  final String why;
  final Thing? thing;

  /// its steps: go (moving to its target), do (doing it there), done
  String step = 'go';
  double t = 0, stepT = 0;
  double? tx, tz;

  /// walk | sneak | run | none
  String gait = 'walk';
  String expr = 'default';
  int count = 0;
}

/// one action's score, for the lab
class Score {
  Score(this.name, this.base, this.gene, this.total);
  final String name;
  final double base, gene, total;
}

class Brain {
  Brain(this.genome, {math.Random? rng, this.size = 30, this.halfW = 40, this.halfD = 18})
      : rng = rng ?? math.Random(genome.seed),
        tuning = NeedTuning(genome),
        quirks = Quirks(genome);

  final Genome genome;
  final math.Random rng;
  final NeedTuning tuning;
  final Quirks quirks;

  /// its height, and the floor's half width and half depth (model units)
  final double size, halfW, halfD;

  final needs = Needs();
  final things = <Thing>[];

  // where it is and which way it faces (radians: 0 toward you, + toward +x)
  double x = 0, z = 0, heading = 0;
  double speed = 0;

  Act act = Act('idle');
  List<Score> scores = const [];
  final _cooldown = <String, double>{};
  double clock = 0;

  /// you touched it
  bool _petted = false;

  double g(String gene) => genome[gene];

  // ---- the world
  void drop(String kind, double x, double z) {
    things.removeWhere((t) => t.kind == kind);
    things.add(Thing(kind, x.clamp(-halfW, halfW), z.clamp(-halfD, halfD)));
    if (act.name != 'nap') _decide(force: true);
  }

  void pet() {
    _petted = true;
    _decide(force: true);
  }

  Thing? find(String kind) {
    for (final t in things) {
      if (t.kind == kind) return t;
    }
    return null;
  }

  double dist(Thing t) => math.sqrt((t.x - x) * (t.x - x) + (t.z - z) * (t.z - z));

  // ---- scoring: a base from its needs and what is around it, times its genes
  Map<String, (double, double)> _scores() {
    final n = needs, th = tuning.threshold;
    final food = find('food'), obj = find('object'), vis = find('visitor');
    final s = <String, (double, double)>{};
    void put(String a, double base, double gene) {
      if (base > 0) s[a] = (base, gene);
    }

    final content = ((n.fullness + n.rest + n.fun + n.company) / 4).clamp(0.0, 1.0);
    put('idle', 0.2, 0.7 + 0.6 * (1 - g('energy')));
    put('look_around', 0.16, 0.4 + 1.2 * g('curiosity'));
    put('wander', 0.12 + 0.35 * (1 - n.fun), 0.4 + 1.2 * g('energy'));
    final bored = n.fun < th['fun']! ? (th['fun']! - n.fun) / th['fun']! : 0.0;
    put('bounce', 0.08 + 0.7 * bored, 0.3 + 1.2 * g('energy'));
    put('show_off', 0.1 * content, 0.2 + 1.6 * g('expressiveness'));
    if (n.rest < th['rest']!) {
      put('nap', 0.9 + 2 * (th['rest']! - n.rest), 1.0 + 0.5 * (1 - g('energy')));
    } else if (n.rest < th['rest']! + 0.15) {
      put('nap', 0.12, 1 - g('energy'));
    }
    final hungry = n.fullness < th['fullness']!;
    if (food != null) {
      put('eat', hungry ? 0.9 + 1.5 * (th['fullness']! - n.fullness) : 0.1, 0.6 + 0.8 * g('appetite'));
    } else if (hungry && n.fullness < th['fullness']! * 0.85) {
      put('beg', 0.35, 0.4 + 0.6 * g('appetite') + 0.4 * g('sociability'));
    }
    if (obj != null && obj.novelty > 0.02) {
      final nov = obj.novelty;
      put('inspect', nov * 0.9, g('curiosity') * (0.3 + 1.0 * g('courage')));
      if (g('courage') < 0.55) put('sneak', nov * 1.0, g('curiosity') * (1.25 - g('courage')));
      put('pounce', nov * 0.8, (0.3 + 0.7 * g('curiosity')) * g('feistiness') * (0.3 + g('courage')) * 1.6);
      final near = (1 - (dist(obj) / (size * 1.6))).clamp(0.0, 1.0);
      put('flee', nov * near * 0.7, (1 - g('courage')) * (g('courage') < 0.3 ? 2.0 : 1.0));
    }
    if (vis != null) {
      final near = (1 - (dist(vis) / (size * 2.2))).clamp(0.0, 1.0);
      put('greet', 0.5 + 0.3 * vis.novelty, (0.3 + 0.9 * g('sociability')) * (g('sociability') > 0.6 ? 2.0 : 1.0) * (0.5 + 0.5 * g('courage')));
      put('hide', 0.3 + 0.5 * near, (1 - g('sociability')) * (1 - g('courage')) * (g('courage') < 0.3 ? 2.0 : 1.0));
      if (g('feistiness') > 0.55) put('pounce', 0.35 * vis.novelty, g('feistiness') * g('courage'));
    }
    if (n.company < th['company']!) {
      put('seek_attention', 0.4 + 1.5 * (th['company']! - n.company), 0.4 + 1.0 * g('sociability'));
    }
    if (_petted) put('enjoy_pet', 3.0, 0.6 + 0.8 * g('sociability'));
    return s;
  }

  void _decide({bool force = false}) {
    final raw = _scores();
    final list = <Score>[];
    raw.forEach((a, v) {
      var total = v.$1 * v.$2;
      if ((_cooldown[a] ?? -1) > clock) total *= 0.15;
      if (a == act.name && act.step != 'done') total *= 1.35; // it keeps at what it started
      list.add(Score(a, v.$1, v.$2, total));
    });
    list.sort((p, q) => q.total.compareTo(p.total));
    scores = list;
    if (!force && act.step != 'done') return;
    // the best few by weighted chance (sharpened: mostly the best, now and then the next)
    final top = list.take(4).where((s) => s.total > 0).toList();
    if (top.isEmpty) return _start('idle', 'nothing to do');
    if (act.step != 'done' && top.first.name == act.name) return;
    final w = [for (final s in top) math.pow(s.total, 3).toDouble()];
    var r = rng.nextDouble() * w.fold(0.0, (a, b) => a + b);
    var pick = top.first;
    for (var i = 0; i < top.length; i++) {
      r -= w[i];
      if (r <= 0) {
        pick = top[i];
        break;
      }
    }
    _start(pick.name, 'scored ${pick.total.toStringAsFixed(2)} (needs ${pick.base.toStringAsFixed(2)} x genes ${pick.gene.toStringAsFixed(2)})');
  }

  void _start(String name, String why) {
    final thing = switch (name) {
      'eat' => find('food'),
      'inspect' || 'sneak' || 'flee' => find('object'),
      'greet' || 'hide' => find('visitor'),
      'pounce' => find('object') ?? find('visitor'),
      _ => null,
    };
    final a = Act(name, why: why, thing: thing);
    switch (name) {
      case 'wander':
        a.tx = (rng.nextDouble() * 2 - 1) * halfW * 0.8;
        a.tz = (rng.nextDouble() * 2 - 1) * halfD * 0.8;
      case 'eat':
        a.gait = g('appetite') > 0.65 ? 'run' : 'walk';
        a.expr = 'happy';
      case 'inspect':
        a.expr = 'curious';
      case 'sneak':
        a.gait = 'sneak';
        a.expr = 'curious';
      case 'pounce':
        a.gait = 'sneak';
        a.expr = 'determined';
      case 'flee':
        _away(a, thing);
        a.gait = 'run';
        a.expr = 'surprised';
      case 'greet':
        a.expr = 'happy';
      case 'hide':
        _away(a, thing);
        a.gait = g('courage') < 0.35 ? 'run' : 'walk';
        a.expr = 'sad';
      case 'seek_attention':
        a.tx = x * 0.3;
        a.tz = halfD * 0.85;
        a.expr = 'happy';
      case 'beg':
        a.step = 'do';
        a.expr = 'curious';
      case 'nap':
        a.step = 'do';
        a.expr = 'sleepy';
      case 'enjoy_pet':
        _petted = false;
        a.step = 'do';
        a.expr = 'happy';
      default:
        a.step = 'do';
        a.expr = name == 'show_off' || name == 'bounce' ? 'excited' : (name == 'look_around' ? 'curious' : 'default');
    }
    if (name == 'enjoy_pet') _petted = false;
    act = a;
  }

  void _away(Act a, Thing? from) {
    final fx = from?.x ?? x, fz = from?.z ?? z;
    var dx = x - fx, dz = z - fz;
    final l = math.sqrt(dx * dx + dz * dz);
    if (l < 1e-3) {
      dx = rng.nextBool() ? 1 : -1;
      dz = 0;
    } else {
      dx /= l;
      dz /= l;
    }
    a.tx = (x + dx * size * 1.4).clamp(-halfW, halfW);
    a.tz = (z + dz * size * 0.8).clamp(-halfD, halfD);
  }

  /// its walking speed for a gait (model units a second)
  double pace(String gait) => switch (gait) {
        'sneak' => size * 0.22,
        'run' => size * (0.9 + 0.5 * g('energy')),
        _ => size * (0.35 + 0.4 * g('energy')),
      };

  // ---- time passing
  void update(double dt) {
    clock += dt;
    act.t += dt;
    act.stepT += dt;
    // needs drain
    tuning.drain.forEach((k, r) => needs.set(k, needs.all[k]! - r * dt));
    for (final t in things) {
      t.age += dt;
      if (t.kind == 'object') t.novelty = (t.novelty - 0.004 * dt).clamp(0.0, 1.0);
    }
    // a visitor wanders by, then leaves
    final vis = find('visitor');
    if (vis != null) {
      vis.x += math.sin(vis.age * 0.7) * dt * 4;
      if (vis.age > 22) things.remove(vis);
    }
    _run(dt);
    // a few times a second it looks again: something better may have come up
    if (act.step == 'done') {
      _decide(force: true);
    } else if ((clock * 4).floor() != ((clock - dt) * 4).floor()) {
      _decide();
      final best = scores.isEmpty ? null : scores.first;
      // only an urgent one cuts in (fright, a big need), never into a nap unless it is woken
      if (best != null && best.name != act.name && act.name != 'nap' && best.total > 1.5 &&
          (scores.length < 2 || best.total > 1.8 * (scores.firstWhere((s) => s.name == act.name, orElse: () => Score(act.name, 0, 0, 0.3)).total))) {
        _start(best.name, 'cut in: ${best.total.toStringAsFixed(2)}');
      }
    }
  }

  bool _goTo(double tx, double tz, double dt, String gait, {double stop = 2}) {
    final dx = tx - x, dz = tz - z;
    final l = math.sqrt(dx * dx + dz * dz);
    if (l <= stop) {
      speed = 0;
      return true;
    }
    final want = math.atan2(dx, dz);
    var turn = want - heading;
    while (turn > math.pi) {
      turn -= 2 * math.pi;
    }
    while (turn < -math.pi) {
      turn += 2 * math.pi;
    }
    heading += turn.clamp(-dt * 6, dt * 6);
    final v = pace(gait) * quirks.tempo.clamp(0.8, 1.3);
    speed = v;
    final step = math.min(l - stop, v * dt) * math.cos(turn.abs().clamp(0, math.pi / 2));
    x = (x + dx / l * step).clamp(-halfW, halfW);
    z = (z + dz / l * step).clamp(-halfD, halfD);
    return false;
  }

  void _face(double tx, double tz, double dt) {
    final want = math.atan2(tx - x, tz - z);
    var turn = want - heading;
    while (turn > math.pi) {
      turn -= 2 * math.pi;
    }
    while (turn < -math.pi) {
      turn += 2 * math.pi;
    }
    heading += turn.clamp(-dt * 4, dt * 4);
  }

  void _next(Act a, String step) {
    a.step = step;
    a.stepT = 0;
  }

  void _run(double dt) {
    final a = act, th = a.thing;
    speed = 0;
    switch (a.name) {
      case 'wander':
      case 'seek_attention':
        if (a.step == 'go' && _goTo(a.tx!, a.tz!, dt, a.gait, stop: 1.5)) _next(a, 'do');
        if (a.step == 'do') {
          if (a.name == 'seek_attention') {
            _face(x, halfD * 3, dt);
            needs.set('company', needs.company + 0.05 * dt);
          }
          if (a.stepT > (a.name == 'seek_attention' ? 3.0 : 0.6)) _next(a, 'done');
        }
      case 'eat':
        if (th == null || !things.contains(th)) return _next(a, 'done');
        if (a.step == 'go' && _goTo(th.x, th.z, dt, a.gait, stop: size * 0.55)) _next(a, 'do');
        if (a.step == 'do') {
          _face(th.x, th.z, dt);
          needs.set('fullness', needs.fullness + 0.16 * dt);
          if (a.stepT > 3.5 || needs.fullness > 0.98) {
            things.remove(th);
            _cooldown['eat'] = clock + 5;
            _next(a, 'done');
          }
        }
      case 'inspect':
        if (th == null || !things.contains(th)) return _next(a, 'done');
        if (a.step == 'go' && _goTo(th.x, th.z, dt, a.gait, stop: size * 0.6)) _next(a, 'do');
        if (a.step == 'do') {
          _face(th.x, th.z, dt);
          th.novelty = (th.novelty - 0.18 * dt).clamp(0.0, 1.0);
          needs.set('fun', needs.fun + 0.06 * dt);
          if (a.stepT > 2.8) _next(a, 'done');
        }
      case 'sneak':
        if (th == null || !things.contains(th)) return _next(a, 'done');
        if (a.step == 'go') {
          if (_goTo(th.x, th.z, dt, 'sneak', stop: size * 0.75)) {
            // close now: a timid one's nerve goes (less each time, as it gets used to it)
            final nerve = (1 - g('courage')) * (0.35 + 0.65 * th.novelty);
            th.novelty = (th.novelty - 0.2).clamp(0.0, 1.0);
            if (rng.nextDouble() < nerve) {
              _start('flee', 'startled: it got close (nerve ${nerve.toStringAsFixed(2)})');
              act.count = 1;
              return;
            }
            a.expr = 'curious';
            _next(a, 'do');
          }
        } else if (a.step == 'do') {
          _face(th.x, th.z, dt);
          th.novelty = (th.novelty - 0.15 * dt).clamp(0.0, 1.0);
          needs.set('fun', needs.fun + 0.05 * dt);
          if (a.stepT > 2.4) _next(a, 'done');
        }
      case 'pounce':
        if (th == null || !things.contains(th)) return _next(a, 'done');
        if (a.step == 'go') {
          if (_goTo(th.x, th.z, dt, 'sneak', stop: size * 1.2)) _next(a, 'ready');
        } else if (a.step == 'ready') {
          _face(th.x, th.z, dt);
          if (a.stepT > 0.7 / quirks.tempo) {
            a.tx = th.x;
            a.tz = th.z;
            a.expr = 'excited';
            _next(a, 'leap');
          }
        } else if (a.step == 'leap') {
          _goTo(a.tx!, a.tz!, dt, 'run', stop: size * 0.4);
          speed = 0;
          if (a.stepT > 0.55) {
            th.novelty = (th.novelty - 0.35).clamp(0.0, 1.0);
            needs.set('fun', needs.fun + 0.3);
            _next(a, 'do');
          }
        } else if (a.step == 'do') {
          if (a.stepT > 1.2) _next(a, 'done');
        }
      case 'flee':
      case 'hide':
        if (a.step == 'go' && _goTo(a.tx!, a.tz!, dt, a.gait, stop: 1.5)) _next(a, 'do');
        if (a.step == 'do') {
          if (th != null) _face(th.x, th.z, dt);
          needs.set('fun', needs.fun - 0.02 * dt);
          final hold = a.name == 'hide' ? 5.0 : 1.8 + 1.5 * (1 - g('courage'));
          if (a.stepT > hold || (a.name == 'hide' && (th == null || !things.contains(th)))) {
            if (a.name == 'flee') _cooldown['sneak'] = clock + 3;
            _next(a, 'done');
          }
        }
      case 'greet':
        if (th == null || !things.contains(th)) return _next(a, 'done');
        if (a.step == 'go' && _goTo(th.x, th.z, dt, a.gait, stop: size * 0.9)) _next(a, 'do');
        if (a.step == 'do') {
          _face(th.x, th.z, dt);
          needs.set('company', needs.company + 0.12 * dt);
          th.novelty = (th.novelty - 0.2 * dt).clamp(0.0, 1.0);
          if (a.stepT > 2.6) {
            _cooldown['greet'] = clock + 8;
            _next(a, 'done');
          }
        }
      case 'nap':
        needs.set('rest', needs.rest + 0.05 * dt);
        if (needs.rest > 0.97 || _petted) {
          _next(a, 'done');
          _cooldown['nap'] = clock + 20;
        }
      case 'enjoy_pet':
        _face(x, halfD * 3, dt);
        needs.set('company', needs.company + 0.15 * dt);
        if (a.stepT > 1.8) _next(a, 'done');
      case 'beg':
        _face(x, halfD * 3, dt);
        if (a.stepT > 2.6) {
          _cooldown['beg'] = clock + 6;
          _next(a, 'done');
        }
      case 'bounce':
      case 'show_off':
        needs.set('fun', needs.fun + (a.name == 'bounce' ? 0.1 : 0.04) * dt);
        if (a.stepT > (a.name == 'bounce' ? 2.2 : 1.6) / quirks.tempo) {
          _cooldown[a.name] = clock + (a.name == 'bounce' ? 4 : 12);
          _next(a, 'done');
        }
      case 'look_around':
        if (a.stepT > 2.4) {
          _cooldown['look_around'] = clock + 3;
          _next(a, 'done');
        }
      default: // idle
        if (a.stepT > 2.5 + 2 * (1 - g('energy'))) _next(a, 'done');
    }
  }
}
