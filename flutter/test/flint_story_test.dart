// Flint is a story NPC (npc_flint at the Crossing): his conversation is built by the story system like the
// villagers', so a quest can be given to him later. These keep his talk whole.

import 'package:evochi/core/models/game_state.dart';
import 'package:evochi/core/utils/day_keys.dart';
import 'package:evochi/game/engine.dart' as g;
import 'package:evochi/game/story/story.dart' as q;
import 'package:flutter_test/flutter_test.dart';

const tzName = 'America/New_York';
final t0 = DateTime.utc(2026, 10, 5, 14).millisecondsSinceEpoch;

GameState freshPet() {
  var s = GameState.fresh(t0, tzName);
  s = g.startGuest(s, t0, tzName).state;
  s = g.setConnection(s, 'demo', t0).state;
  return g.createPet(s, name: 'Ember', paletteId: 'amber', requestId: 'req-1', now: t0).state;
}

void main() {
  setUpAll(ensureTimeZones);

  test('Flint is registered: an NPC at the Crossing, a place that names him', () {
    expect(q.npcs['npc_flint']?.location, 'crossing');
    expect(q.places['crossing']?.npcs, contains('npc_flint'));
  });

  test('his conversation: hello the first time, his choices after; every line exists and every way on leads somewhere', () {
    var s = freshPet();
    final first = q.npcConversation(s, 'npc_flint', t0);
    expect(first.start, 'FL_HELLO');
    s = q.markNpcMet(s, 'npc_flint').state;
    final again = q.npcConversation(s, 'npc_flint', t0);
    expect(again.start, 'FL_HUB');
    for (final conv in [first, again]) {
      for (final n in conv.nodes.values) {
        expect(q.lines[n.id]?.speaker, 'npc_flint', reason: n.id);
        expect(n.choices, isNotEmpty, reason: n.id);
        for (final ch in n.choices) {
          if (ch.next != null) expect(conv.nodes.containsKey(ch.next), isTrue, reason: '${n.id} -> ${ch.next}');
          expect(ch.next != null || ch.goto != null || ch.leave || ch.act != null || ch.reward != null, isTrue, reason: '${n.id}: ${ch.label}');
        }
      }
    }
    final gotos = again.nodes.values.expand((n) => n.choices).map((c) => c.goto).whereType<String>().toSet();
    expect(gotos, containsAll(['flint:gear', 'flint:enter']));
  });
}
