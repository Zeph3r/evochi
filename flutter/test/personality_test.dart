import 'dart:convert';
import 'dart:math' as math;

import 'package:evochi/core/models/game_state.dart';
import 'package:evochi/game/personality/catalog.dart';
import 'package:evochi/game/personality/director.dart';
import 'package:evochi/game/personality/personality.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _petJson({Map<String, dynamic>? personality}) => {
      'id': 'pet_abc123',
      'requestId': 'r1',
      'name': 'Mochi',
      'paletteId': 'coral',
      'stage': 2,
      'createdAt': 1,
      'createdDay': '2026-10-01',
      if (personality != null) 'personality': personality,
    };

void main() {
  group('making a personality', () {
    test('a seed always makes the same companion', () {
      for (var seed = 0; seed < 200; seed++) {
        expect(jsonEncode(generatePersonality(seed).toJson()), jsonEncode(generatePersonality(seed).toJson()));
      }
    });

    test('every profile turns up, and every choice is in the catalog and its profile', () {
      final seen = <String>{};
      for (var seed = 0; seed < 300; seed++) {
        final p = generatePersonality(seed);
        seen.add(p.profile);
        final prof = profiles[p.profile]!;
        expect(p.signature, prof.signature);
        expect(p.habits.length, 2);
        for (final h in [...p.habits, ...p.idle, ...p.combat.values, p.signature]) {
          expect(behaviors.containsKey(h), isTrue, reason: '$h in the catalog');
        }
        for (final h in p.habits) {
          expect(prof.habitPool, contains(h));
        }
        expect(p.combat.keys.toSet(), {'stance', 'anticipation', 'recovery', 'calmedReaction'});
        for (final t in traitNames) {
          final (lo, hi) = prof.traits[t]!;
          expect(p.traits[t]!, inInclusiveRange(lo - 0.01, hi + 0.01));
        }
        expect(prof.interests, contains(p.interest));
        for (final v in p.style.values) {
          expect(v, inInclusiveRange(0.85, 1.25));
        }
      }
      expect(seen, {'cautious', 'lively', 'calm'});
    });
  });

  group('keeping it', () {
    test('saved with the pet, and loaded back the same', () {
      final p = Pet.fromJson(_petJson(personality: generatePersonality(42).toJson()));
      final again = Pet.fromJson(jsonDecode(jsonEncode(p.toJson())) as Map<String, dynamic>);
      expect(jsonEncode(again.personality.toJson()), jsonEncode(p.personality.toJson()));
    });

    test('an Evochi from before personalities gets one, once, the same every load', () {
      final a = Pet.fromJson(_petJson());
      final b = Pet.fromJson(_petJson());
      expect(a.personality.origin, 'migration');
      expect(jsonEncode(a.personality.toJson()), jsonEncode(b.personality.toJson()));
      // and once saved, it is what was saved, whatever the generator would make now
      final saved = a.toJson();
      (saved['personality'] as Map)['traits'] = {'energy': 0.11, 'curiosity': 0.22, 'boldness': 0.33, 'sociability': 0.44, 'expressiveness': 0.55};
      final c = Pet.fromJson(jsonDecode(jsonEncode(saved)) as Map<String, dynamic>);
      expect(c.personality.trait('energy'), 0.11);
      expect(c.personality.signature, a.personality.signature);
    });

    test('evolving keeps who it is', () {
      final p = Pet.fromJson(_petJson(personality: generatePersonality(7).toJson()));
      final before = jsonEncode(p.personality.toJson());
      p.stage = 3;
      expect(jsonEncode(Pet.fromJson(p.toJson()).personality.toJson()), before);
    });
  });

  group('the director', () {
    Personality of(String profile) {
      for (var s = 0; s < 500; s++) {
        final p = generatePersonality(s);
        if (p.profile == profile) return p;
      }
      throw StateError(profile);
    }

    test('always has something to do, and keeps to the repertoire', () {
      for (final prof in profiles.keys) {
        final d = BehaviorDirector(of(prof), rng: math.Random(1));
        for (var i = 0; i < 200; i++) {
          final c = d.choose('idle', i * 3.0);
          final b = c.behavior;
          expect(b.contexts, contains('idle'));
          final p = d.p;
          expect(b.kind == 'neutral' || b.id == p.signature || p.habits.contains(b.id) || p.idle.contains(b.id), isTrue, reason: '${b.id} for $prof');
        }
      }
    });

    test('cooldowns hold: nothing repeats before its time', () {
      final d = BehaviorDirector(of('lively'), rng: math.Random(3));
      final at = <String, double>{};
      for (var i = 0; i < 300; i++) {
        final now = i * 2.0;
        final b = d.choose('idle', now).behavior;
        if (b.cooldown > 0 && at.containsKey(b.id)) {
          expect(now - at[b.id]!, greaterThanOrEqualTo(b.cooldown), reason: b.id);
        }
        at[b.id] = now;
      }
    });

    test('the signature is what shows when it matters: hatching, food arriving', () {
      for (final prof in profiles.keys) {
        var sig = 0;
        for (var seed = 0; seed < 100; seed++) {
          final d = BehaviorDirector(of(prof), rng: math.Random(seed));
          if (d.choose('hatch', 0).behavior.id == d.p.signature) sig++;
        }
        expect(sig, greaterThan(70), reason: '$prof hatching');
      }
    });

    test('profiles are told apart by what they do', () {
      Map<String, int> tally(String prof) {
        final t = <String, int>{};
        final d = BehaviorDirector(of(prof), rng: math.Random(9));
        for (var i = 0; i < 400; i++) {
          final id = d.choose('idle', i * 30.0).behavior.id;
          t[id] = (t[id] ?? 0) + 1;
        }
        return t;
      }

      final lively = tally('lively'), calm = tally('calm'), cautious = tally('cautious');
      expect((lively['happy_wiggle'] ?? 0) + (lively['bounce_in_place'] ?? 0), greaterThan(80));
      expect((calm['gentle_sway'] ?? 0) + (calm['slow_blink'] ?? 0), greaterThan(80));
      expect((cautious['careful_peek'] ?? 0) + (cautious['look_around'] ?? 0), greaterThan(80));
      expect(lively['gentle_sway'] ?? 0, 0);
      expect(calm['bounce_in_place'] ?? 0, 0);
    });

    test('tired, the energetic habits fade', () {
      int hops(Mood m) {
        var n = 0;
        for (var seed = 0; seed < 300; seed++) {
          final d = BehaviorDirector(of('lively'), rng: math.Random(seed));
          final id = d.choose('idle', 100, mood: m).behavior.id;
          if (id == 'bounce_in_place' || id == 'happy_wiggle') n++;
        }
        return n;
      }

      expect(hops(const Mood(tired: 0.95)), lessThan(hops(const Mood(tired: 0.0))));
    });

    test('the encounter reads its saved repertoire', () {
      for (final prof in profiles.keys) {
        final d = BehaviorDirector(of(prof));
        for (final phase in ['stance', 'anticipation', 'recovery', 'calmedReaction']) {
          expect(d.combat(phase).id, profiles[prof]!.combat[phase]);
        }
      }
    });
  });
}
