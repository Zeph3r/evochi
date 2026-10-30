// The behaviour director: at an idle opportunity or an event (food arriving, being petted, hatching), it picks
// how your Evochi reacts. It filters what can't play (wrong context, cooling down, not drawn for this stage,
// needing a target that isn't there), scores the rest, damps what it did recently, and picks by weighted chance;
// then it starts the cooldowns. The neutral idle is always a candidate, so the choice is never empty.
//
//   weight = base x trait affinity x interest affinity x mood x context x repetition
//
// Every factor is bounded and never negative. Randomness only chooses within the repertoire; the saved identity
// never changes.

import 'dart:math' as math;

import 'catalog.dart';
import 'personality.dart';

/// How it feels right now (apart from who it is): each 0..1.
class Mood {
  const Mood({this.content = 0.6, this.excited = 0.3, this.hungry = 0.2, this.tired = 0.2});
  final double content, excited, hungry, tired;
}

/// One candidate's score, for the developer preview.
class Scored {
  Scored(this.id, this.weight, this.factors, [this.excluded]);
  final String id;
  final double weight;
  final Map<String, double> factors;
  final String? excluded;
}

class Choice {
  Choice(this.behavior, this.candidates, this.context);
  final BehaviorDef behavior;
  final List<Scored> candidates;
  final String context;
}

class BehaviorDirector {
  BehaviorDirector(this.p, {math.Random? rng}) : _rng = rng ?? math.Random();
  final Personality p;
  final math.Random _rng;

  /// behaviour id -> the time (s) it may play again
  final cooldownUntil = <String, double>{};

  /// what it did lately, newest last
  final recent = <String>[];

  /// signatures share one cooldown on top of their own (they stay special)
  double signatureUntil = 0;
  Choice? last;

  bool _inRepertoire(BehaviorDef b, String context) {
    if (b.kind == 'neutral') return true;
    if (b.id == p.signature) return true;
    if (p.habits.contains(b.id)) return true;
    if (context == 'idle' && p.idle.contains(b.id)) return true;
    return false;
  }

  /// the trait factor: (value)^pull for a positive pull, (1 - value)^-pull for a negative one; 0.05..1
  double traitAffinity(BehaviorDef b) {
    var f = 1.0;
    b.affinity.forEach((t, pull) {
      final v = p.trait(t).clamp(0.0, 1.0);
      f *= pull >= 0 ? math.pow(v, pull) : math.pow(1 - v, -pull);
    });
    return f.clamp(0.05, 1.0);
  }

  double _mood(BehaviorDef b, Mood m) {
    var f = 1.0;
    final energetic = (b.affinity['energy'] ?? 0) > 0;
    if (energetic) f *= 1.0 - 0.6 * m.tired;
    if ((b.affinity['energy'] ?? 0) < 0) f *= 0.8 + 0.4 * m.tired;
    if (b.kind == 'signature') f *= 0.7 + 0.6 * m.excited;
    if (m.content < 0.3) f *= b.kind == 'neutral' ? 1.5 : 0.7; // low spirits: quieter
    return f.clamp(0.1, 2.0);
  }

  double _context(BehaviorDef b, String context) {
    // the moments that matter call for the signature; idle time mostly for the small habits
    if (b.kind == 'signature') return const {'hatch': 6.0, 'feed': 2.5, 'wilds_open': 3.0, 'wilds_calmed': 2.0}[context] ?? 0.35;
    if (b.kind == 'habit') return context == 'idle' ? 0.8 : 1.4;
    return 1.0;
  }

  double _repeat(BehaviorDef b) {
    final i = recent.lastIndexOf(b.id);
    if (i < 0) return 1.0;
    final ago = recent.length - 1 - i; // 0: the last thing it did
    return (0.25 + 0.25 * ago).clamp(0.25, 1.0);
  }

  /// what it does now, in [context] at time [now] (s); [stage]'s clips decide what can be drawn (a behaviour with
  /// a clip not drawn for it still plays its simple motion); [targets]: what is in the scene to look at
  Choice choose(String context, double now, {Mood mood = const Mood(), Set<String> clips = const {}, Set<String> targets = const {}}) {
    final scored = <Scored>[];
    for (final b in behaviors.values) {
      String? out;
      if (!b.contexts.contains(context)) {
        out = 'context';
      } else if (!_inRepertoire(b, context)) {
        out = 'repertoire';
      } else if ((cooldownUntil[b.id] ?? -1) > now) {
        out = 'cooldown';
      } else if (b.kind == 'signature' && signatureUntil > now && context == 'idle') {
        out = 'signature rest';
      } else if (b.interest != null && b.id == 'inspect_leaf' && !targets.contains(b.interest)) {
        out = 'no target';
      }
      if (out != null) {
        scored.add(Scored(b.id, 0, const {}, out));
        continue;
      }
      final f = {
        'base': b.base,
        'trait': traitAffinity(b),
        'interest': b.interest == null ? 1.0 : (b.interest == p.interest ? 1.6 : 0.8),
        'mood': _mood(b, mood),
        'context': _context(b, context),
        'repeat': _repeat(b),
        'drawn': b.clip == null || clips.isEmpty || clips.contains(b.clip) ? 1.0 : 0.6,
      };
      final w = f.values.fold(1.0, (a, x) => a * x);
      scored.add(Scored(b.id, w.isFinite && w > 0 ? w : 0, f));
    }
    final live = scored.where((s) => s.excluded == null && s.weight > 0).toList();
    BehaviorDef pick;
    if (live.isEmpty) {
      pick = behaviors[neutralIdle]!;
    } else {
      final total = live.fold(0.0, (a, s) => a + s.weight);
      var x = _rng.nextDouble() * total;
      var id = live.last.id;
      for (final s in live) {
        x -= s.weight;
        if (x <= 0) {
          id = s.id;
          break;
        }
      }
      pick = behaviors[id]!;
    }
    // its cooldowns; a signature also rests every signature for a while
    cooldownUntil[pick.id] = now + pick.cooldown;
    if (pick.kind == 'signature') signatureUntil = now + 45;
    recent.add(pick.id);
    if (recent.length > 6) recent.removeAt(0);
    return last = Choice(pick, scored, context);
  }

  /// the encounter's presentation for a phase (stance, anticipation, recovery, calmedReaction): the saved
  /// combat repertoire, or the neutral one
  BehaviorDef combat(String phase) => behaviors[p.combat[phase]] ?? behaviors[neutralIdle]!;
}
