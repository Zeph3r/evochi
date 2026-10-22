// Story floors: the Trail Guild's jobs, played in the Deep Wilds. While a job's hand-in is ready (its walk
// done, what it needs in the Bag), its place waits at a floor of Fernwood Trail: the Mossy Ruins at F3
// (Petalune, then the Hollow Sprout), the Sentinel's Gate at F5. Only while the job is open: once it is
// done, that floor is an ordinary one again.
//
// The beat itself lives on the Wilds screen (features/wilds): earning Petalune's trust (no fighting it),
// restoring the Hollow Sprout, the Sentinel. Only the save's side is here: which floor is a story floor,
// a treat offered to Petalune, and the job's hand-in when the beat is done (once: a retry finds the quest
// already completed and adds nothing).

import '../../core/models/catalog.dart';
import '../../core/models/game_state.dart';
import '../engine.dart';
import '../story/story.dart' as story;
import '../trails/trails.dart' as trails;
import 'wilds.dart' show wildsHealItems;

class StoryFloor {
  const StoryFloor({required this.quest, required this.place, required this.depth, required this.beat, required this.creature, required this.line});
  final String quest; // the Trail Guild job (game/story/story_data.dart)
  final String place; // shown for the floor's name
  final int depth; // the floor it waits at
  final String beat; // trust | sprout | sentinel
  final String creature; // game/trails/trails.dart creatureDefs
  final String line; // the arrival banner
}

const storyFloors = <String, StoryFloor>{
  'eq01': StoryFloor(
      quest: 'eq01',
      place: 'Mossy Ruins',
      depth: 3,
      beat: 'trust',
      creature: 'petalune',
      line: 'The Mossy Ruins. Something small and green is watching you from the stones.'),
  'eq02': StoryFloor(
      quest: 'eq02',
      place: 'Mossy Ruins',
      depth: 3,
      beat: 'sprout',
      creature: 'hollow_sprout',
      line: 'The Mossy Ruins. The Hollow has wound itself round a sprout here, and it is lashing out.'),
  'eq03': StoryFloor(
      quest: 'eq03',
      place: "Sentinel's Gate",
      depth: 5,
      beat: 'sentinel',
      creature: 'sentinel',
      line: 'The old gate past the bridge. Something huge sleeps against it, tangled in Hollow.'),
};

/// The beats the Wilds can play (all three: every Trail Guild job's place is a story floor now).
const playableBeats = {'trust', 'sprout', 'sentinel'};

/// A job's place is open: its hand-in is ready (the walk done, what it needs in the Bag).
bool storyFloorOpen(GameState s, String qid) {
  final f = storyFloors[qid];
  return f != null && playableBeats.contains(f.beat) && story.nextStep(s, qid).kind == 'encounter';
}

/// The story floor waiting at [depth], if a job's place is open there.
StoryFloor? storyFloorAt(GameState s, int depth) {
  for (final f in storyFloors.values) {
    if (f.depth == depth && storyFloorOpen(s, f.quest)) return f;
  }
  return null;
}

ActionResult _fail(GameState s, String error) => ActionResult(s, error: error);

/// How much a treat warms Petalune: any food from the Bag, half again for the ones it loves.
int treatTrust(String itemId) => (trails.creatureDefs['petalune']!.likes.contains(itemId) ? 30 : 20);

/// The foods Petalune can be offered (from the Bag), the ones it loves first.
List<String> treatsFor(GameState s) {
  final likes = trails.creatureDefs['petalune']!.likes;
  final foods = {...likes, ...wildsHealItems}.where((id) => catalog[id] != null && ownedQty(s, id) > 0).toList();
  foods.sort((a, b) => (likes.contains(a) ? 0 : 1).compareTo(likes.contains(b) ? 0 : 1));
  return foods;
}

/// A treat offered to Petalune: one leaves the Bag; the screen warms its trust by [treatTrust].
ActionResult wildsOffer(GameState state, String itemId, int now) {
  if (!treatsFor(state).contains(itemId)) return _fail(state, ownedQty(state, itemId) < 1 ? 'not_owned' : 'not_a_treat');
  final s = state.copy();
  s.inventory[itemId]!.quantity -= 1;
  return ActionResult(s, events: [GameEvent('wilds_treat', {'itemId': itemId, 'trust': treatTrust(itemId)})]);
}

/// The beat is done (Petalune trusts you; the Sprout or the Sentinel is restored): the creature is
/// remembered (a companion, or restored) and the job's hand-in runs and pays out, once. [spent] is what of
/// the hand-in's items was used up on the floor (a Lantern Tonic drunk in the fight still counts).
ActionResult wildsStoryDone(GameState state, String qid, int now, {Map<String, int> spent = const {}}) {
  final f = storyFloors[qid];
  if (f == null) return _fail(state, 'unknown_story_floor');
  final q = story.storyQuests[qid]!;
  final t = q.turnIns.firstWhere((x) => x.encounter != null);
  if (story.questPhase(state, qid) == 'completed') return ActionResult(state, events: [GameEvent('story_already', {'questId': qid})]);
  var s = state.copy();
  final tr = s.trails;
  final befriend = f.beat == 'trust';
  if (befriend) {
    tr.companions.putIfAbsent(f.creature, () => CompanionState(since: now));
    tr.stats['befriended'] = tr.stat('befriended') + 1;
  } else {
    tr.restored[f.creature] = now;
    tr.stats['restored'] = tr.stat('restored') + 1;
  }
  tr.stats['encounters'] = tr.stat('encounters') + 1;
  final r = story.storyHandIn(s, qid, t.id, now, spent: spent);
  if (!r.ok) return _fail(state, r.error!);
  s = r.state;
  return ActionResult(s, events: [
    GameEvent(befriend ? 'wilds_befriended' : 'wilds_restored', {'quest': qid, 'creature': f.creature}),
    ...r.events,
    if (befriend) GameEvent('companion_joined', {'creature': f.creature}),
  ]);
}

/// Petalune walks the Wilds with you once it trusts you (and casts Petal Hush when a fight goes on).
bool petaluneWithYou(GameState s) => s.trails.companions.containsKey('petalune');
