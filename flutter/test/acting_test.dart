import 'dart:convert';
import 'dart:io';

import 'package:evochi/game/personality/catalog.dart';
import 'package:evochi/game/personality/director.dart';
import 'package:evochi/game/personality/personality.dart';
import 'package:flutter_test/flutter_test.dart';

// The acting clips as shipped (tools/art/acting.py): every clip the catalog's habits name for the Eggling is
// drawn, in every colour and with every worn piece, and the director only reaches for what is there.
void main() {
  final j = jsonDecode(File('assets/art/acting/acting.json').readAsStringSync()) as Map<String, dynamic>;
  final s01 = (j['s01'] as Map).cast<String, dynamic>();
  final clips = (s01['clips'] as Map).cast<String, dynamic>();

  test('every habit the Eggling can show is drawn, whole', () {
    final wanted = {
      for (final b in behaviors.values)
        if (b.clip != null && b.kind != 'combat') b.clip!,
    };
    expect(clips.keys.toSet().containsAll(wanted), isTrue, reason: 'missing ${wanted.difference(clips.keys.toSet())}');
    final pals = (clips['double_hop'] as Map)['body'] as Map;
    for (final e in clips.entries) {
      final c = (e.value as Map).cast<String, dynamic>();
      expect((c['lift'] as List).length, c['n'], reason: e.key);
      expect((c['body'] as Map).keys.toSet(), pals.keys.toSet(), reason: '${e.key}: every colour');
      expect((c['wear'] as Map).keys, isNotEmpty, reason: '${e.key}: the worn pieces');
      for (final f in [...(c['body'] as Map).values, ...(c['wear'] as Map).values]) {
        expect(File('assets/art/acting/$f').existsSync(), isTrue, reason: f as String);
      }
      final box = (c['box'] as List).cast<num>();
      expect(box[2] > 0 && box[3] > 0, isTrue);
    }
  });

  test('the signatures play at hatching from what is drawn', () {
    for (final prof in profiles.keys) {
      final p = generatePersonality(3, profile: prof);
      final d = BehaviorDirector(p);
      final b = d.choose('hatch', 0, clips: clips.keys.toSet()).behavior;
      expect(b.clip == null || clips.containsKey(b.clip), isTrue);
    }
  });
}
