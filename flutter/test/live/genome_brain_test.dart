// The personality genome (continuous genes from an egg's seed, inheritance) and the live brain (needs tuned by
// the genes, utility scores times the genes, behaviour that emerges from combinations).
import 'dart:math' as math;

import 'package:evochi/game/personality/brain.dart';
import 'package:evochi/game/personality/genome.dart';
import 'package:flutter_test/flutter_test.dart';

Genome _g(Map<String, double> genes, [int seed = 1]) => Genome(seed, {for (final n in geneNames) n: 0.5, ...genes});

/// runs [b] for [secs], returning the actions it started, in order
List<String> _run(Brain b, double secs) {
  final seen = <String>[];
  for (var t = 0.0; t < secs; t += 0.05) {
    final before = b.act;
    b.update(0.05);
    if (!identical(before, b.act)) seen.add(b.act.name);
  }
  return seen;
}

void main() {
  group('genome', () {
    test('a seed always makes the same genes', () {
      expect(Genome.fromSeed(123).genes, Genome.fromSeed(123).genes);
      expect(Genome.fromSeed(123).genes, isNot(Genome.fromSeed(124).genes));
    });

    test('most genes land near the middle; the ends are reachable but rare', () {
      final sums = {for (final n in geneNames) n: 0.0};
      var ends = 0, all = 0;
      for (var s = 0; s < 3000; s++) {
        final g = Genome.fromSeed(s * 7919 + 1);
        for (final n in geneNames) {
          sums[n] = sums[n]! + g[n];
          all++;
          if (g[n] > 0.85 || g[n] < 0.15) ends++;
          expect(g[n], inInclusiveRange(0.02, 0.98));
        }
      }
      for (final n in geneNames) {
        expect(sums[n]! / 3000, closeTo(0.5, 0.04), reason: n);
      }
      expect(ends / all, inExclusiveRange(0.005, 0.15));
    });

    test('a child is its parents\' mix, now and then nudged, and knows them', () {
      final a = Genome.fromSeed(11), b = Genome.fromSeed(22);
      final c = Genome.child(a, b, 5);
      expect(c.parents, [a.seed, b.seed]);
      expect(c.generation, 1);
      for (final n in geneNames) {
        final lo = math.min(a[n], b[n]) - 0.13, hi = math.max(a[n], b[n]) + 0.13;
        expect(c[n], inInclusiveRange(lo, hi), reason: n);
      }
      expect(Genome.child(a, b, 5).genes, c.genes); // the same pairing and nonce, the same child
      expect(Genome.fromJson(c.toJson()).genes, c.genes);
    });

    test('it is named for what stands out', () {
      expect(_g({'curiosity': 0.95, 'courage': 0.1}).describe(), 'Timid Explorer');
      expect(_g({'energy': 0.05, 'sociability': 0.9}).describe(), 'Friendly Napper');
    });
  });

  group('needs', () {
    test('its genes set when it acts on a need: a greedy one eats at 70% full, a dainty one waits', () {
      expect(NeedTuning(_g({'appetite': 0.95})).threshold['fullness'], greaterThan(0.7));
      expect(NeedTuning(_g({'appetite': 0.0})).threshold['fullness'], closeTo(0.2, 1e-9));
      expect(NeedTuning(_g({'appetite': 0.95})).drain['fullness'], greaterThan(NeedTuning(_g({'appetite': 0.0})).drain['fullness']!));
    });

    test('hungry with food down, it goes and eats it', () {
      final b = Brain(_g({'appetite': 0.8}), rng: math.Random(1));
      b.needs.fullness = 0.2;
      b.drop('food', 20, 4);
      expect(b.act.name, 'eat');
      _run(b, 12);
      expect(b.find('food'), isNull);
      expect(b.needs.fullness, greaterThan(0.5));
    });

    test('worn out, it naps until it is rested', () {
      final b = Brain(_g({'energy': 0.2}), rng: math.Random(2));
      b.needs.rest = 0.05;
      final seen = _run(b, 6);
      expect(seen, contains('nap'));
    });
  });

  group('utility', () {
    test('a friendly one greets a visitor (x2); a timid loner hides (x2)', () {
      final friend = Brain(_g({'sociability': 0.95, 'courage': 0.6}), rng: math.Random(3))..drop('visitor', 30, 0);
      final shy = Brain(_g({'sociability': 0.05, 'courage': 0.05}), rng: math.Random(3))..drop('visitor', 30, 0);
      double score(Brain b, String a) => b.scores.firstWhere((s) => s.name == a).total;
      expect(score(friend, 'greet'), greaterThan(2 * score(friend, 'hide')));
      expect(score(shy, 'hide'), greaterThan(2 * score(shy, 'greet')));
    });

    test('a curious feisty brave one would pounce on something new; a curious timid one would sneak up', () {
      final feisty = Brain(_g({'curiosity': 0.9, 'courage': 0.85, 'feistiness': 0.9}), rng: math.Random(4))..drop('object', 25, 5);
      final timid = Brain(_g({'curiosity': 0.95, 'courage': 0.05, 'feistiness': 0.1}), rng: math.Random(4))..drop('object', 25, 5);
      double score(Brain b, String a) => b.scores.where((s) => s.name == a).fold(0.0, (x, s) => s.total);
      expect(score(feisty, 'pounce'), greaterThan(score(feisty, 'inspect')));
      expect(score(feisty, 'sneak'), 0);
      expect(score(timid, 'sneak'), greaterThan(score(timid, 'inspect')));
      expect(score(timid, 'pounce'), lessThan(score(timid, 'sneak') / 4));
    });

    test('emergent: the curious timid one creeps up, bolts when it gets close, and gets used to it', () {
      final b = Brain(_g({'curiosity': 0.95, 'courage': 0.05, 'feistiness': 0.1, 'energy': 0.6}), rng: math.Random(5));
      final seen = <String>[];
      for (var k = 0; k < 3; k++) {
        b.drop('object', k.isEven ? 26 : -26, 3);
        seen.add(b.act.name); // what it chose the moment the thing landed
        seen.addAll(_run(b, 25));
      }
      final i = seen.indexOf('sneak');
      expect(i, greaterThanOrEqualTo(0), reason: '$seen');
      expect(seen.sublist(i), contains('flee'), reason: '$seen');
    });

    test('its quirks follow its genes', () {
      final lively = Quirks(_g({'energy': 0.95, 'expressiveness': 0.9}));
      final sleepy = Quirks(_g({'energy': 0.05, 'expressiveness': 0.1}));
      expect(lively.tempo, greaterThan(sleepy.tempo));
      expect(lively.hop, greaterThan(sleepy.hop));
      expect(sleepy.sway, greaterThan(lively.sway));
      expect(Quirks(_g({'courage': 0.95})).posture, greaterThan(Quirks(_g({'courage': 0.05})).posture));
    });
  });
}
