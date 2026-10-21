// Charms: something your Evochi wears in the Wilds that changes its attacks. One at a time.
//
// A charm grows as you use it: it reaches rank II after 25 creatures calmed while it is worn, rank III
// after 75. Charms drop in the Wilds (rarely from creatures, more often from a guardian), the Starlight
// Caravan sells one or two each week for Glimmer (rank I: play is what raises it), and the Prism and
// Starseed charms are only ever set from a Prism Scale or a Starseed. A charm you already own that drops
// again turns into progress toward its next rank.
//
// What each charm does in a fight lives with the fight (features/wilds/wilds_combat.dart); this file is the
// save side: owning, wearing, ranks and setting the two special ones.

import '../../core/models/catalog.dart';
import '../../core/models/game_state.dart';
import '../engine.dart';

class CharmDef {
  const CharmDef(this.id, this.short, this.ranks, {this.forge = const {}, this.sold = true});
  final String id;
  final String short; // what it does, in a few words
  final List<String> ranks; // what each rank (I, II, III) gives
  final Map<String, int> forge; // what sets it (Prism, Starseed); empty for the others
  final bool sold; // the Caravan may stock it

  String get name => catalog[id]?.name ?? id;
}

const charmDefs = <String, CharmDef>{
  'emberfang_charm': CharmDef('emberfang_charm', 'Hits can set foes alight', ['A 25% chance', 'A 35% chance', 'A 45% chance']),
  'frostbell_charm': CharmDef('frostbell_charm', 'Hits can chill foes', ['A 25% chance', 'A 35% chance', 'A 45% chance']),
  'static_acorn': CharmDef('static_acorn', 'Every few hits spark to another foe', ['Every 6th hit', 'Every 5th hit', 'Every 4th hit']),
  'sap_locket': CharmDef('sap_locket', 'Hits heal you a little', ['+1 Raid HP a hit', '+1.5 Raid HP a hit', '+2 Raid HP a hit']),
  'dazzle_pebble': CharmDef('dazzle_pebble', 'Hits build dizziness until a foe reels', ['Slowly', 'Steadily', 'Quickly']),
  'prism_charm': CharmDef('prism_charm', 'Your Bolt splits into three', ['Side bolts at 40%', 'Side bolts at 55%', 'Side bolts at 70%'],
      forge: {'prism_scale': 1, 'lumen_shard': 2}, sold: false),
  'starseed_charm': CharmDef('starseed_charm', 'Calmed creatures leave a healing bloom', ['Heals 12', 'Heals 18', 'Heals 24'],
      forge: {'starseed': 1, 'glowleaf': 1}, sold: false),
};

/// Creatures calmed (while worn) to reach rank II and rank III.
const charmRankAt = [25, 75];

/// A charm already owned that comes again: this much progress instead.
const charmDupeXp = 15;

bool ownsCharm(GameState s, String id) => ownedQty(s, id) > 0;

List<String> ownedCharms(GameState s) => [for (final id in charmDefs.keys) if (ownsCharm(s, id)) id];

int charmXp(GameState s, String id) => s.economy.charmXp[id] ?? 0;

/// 1, 2 or 3 (0 if not owned).
int charmRank(GameState s, String id) {
  if (!ownsCharm(s, id)) return 0;
  final xp = charmXp(s, id);
  return 1 + charmRankAt.where((n) => xp >= n).length;
}

/// The charm worn in the Wilds, if it is still owned.
String? wornCharm(GameState s) {
  final id = s.economy.charm;
  return id.isNotEmpty && ownsCharm(s, id) ? id : null;
}

String rankLabel(int r) => const ['', 'I', 'II', 'III'][r.clamp(0, 3)];

/// Progress to the next rank: (calmed so far, needed), or null at rank III.
(int, int)? charmNext(GameState s, String id) {
  final xp = charmXp(s, id);
  for (final n in charmRankAt) {
    if (xp < n) return (xp, n);
  }
  return null;
}

/// Wear a charm in the Wilds ('' takes it off).
ActionResult wearCharm(GameState state, String id) {
  if (id.isNotEmpty && !ownsCharm(state, id)) return ActionResult(state, error: 'not_owned');
  if (state.economy.charm == id) return ActionResult(state);
  final s = state.copy();
  s.economy.charm = id;
  return ActionResult(s, events: [GameEvent('charm_worn', {'id': id})]);
}

/// Set the Prism or Starseed charm from its rare find.
ActionResult setCharm(GameState state, String id, int now) {
  final d = charmDefs[id];
  if (d == null || d.forge.isEmpty) return ActionResult(state, error: 'not_a_charm');
  if (ownsCharm(state, id)) return ActionResult(state, error: 'owned');
  for (final e in d.forge.entries) {
    if (ownedQty(state, e.key) < e.value) return ActionResult(state, error: 'charm_needs', info: {'id': id});
  }
  final s = state.copy();
  for (final e in d.forge.entries) {
    s.inventory[e.key]!.quantity -= e.value;
  }
  grantItem(s, id, 1, 'charm_set', now, 'charm_set:$id');
  if (s.economy.charm.isEmpty) s.economy.charm = id;
  return ActionResult(s, events: [GameEvent('charm_set', {'id': id})]);
}

/// After a run (mutates [s]): the worn charm grows by the creatures calmed; charms that dropped but are
/// already owned become progress instead. Returns the events (a rank reached, a duplicate turned in).
List<GameEvent> charmsAfterRun(GameState s, int calmed, Map<String, int> found) {
  final events = <GameEvent>[];
  void grow(String id, int by) {
    final before = charmRank(s, id);
    s.economy.charmXp[id] = charmXp(s, id) + by;
    final after = charmRank(s, id);
    if (after > before) events.add(GameEvent('charm_rank', {'id': id, 'rank': after}));
  }

  for (final e in found.entries) {
    if (charmDefs.containsKey(e.key) && ownsCharm(s, e.key)) {
      grow(e.key, charmDupeXp * e.value);
      events.add(GameEvent('charm_dupe', {'id': e.key, 'xp': charmDupeXp * e.value}));
    }
  }
  final worn = wornCharm(s);
  if (worn != null && calmed > 0) grow(worn, calmed);
  return events;
}
