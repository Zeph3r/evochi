// Village Tales rules (Quest Bible v1.0 §9): Chapter 1, the Home Tales, the side stories and the Lumen
// Trails encounter quests (whose hand-in is the encounter itself, played in lib/game/trails).
// Mirrors web/src/game/story.js.
//
// Story progression belongs to the player account, not to a pet: it lives in `state.story`, survives
// memorials, new pets, colourway changes and evolution, and its rewards go into the shared inventory.
//
//  - only steps taken AFTER a quest is accepted count; the target is resolved once at acceptance
//    (min(nominal, personal goal)) and frozen, so changing the goal later cannot move it
//  - multi-day quests count distinct local calendar days (account time zone); one material per day
//  - progress is computed from the de-duplicated sample list, so re-delivered or replayed samples
//    never add progress, and every grant / hand-in / payout is idempotent
//  - quest materials live in their own pouch (never the catalog, the Market, chests or trading);
//    story cosmetics are ordinary inventory items with acquisition 'story', no shop and no price
//  - no timers, no streaks: rest days and paused syncs never fail a quest

import 'dart:math' as math;

import '../../core/models/catalog.dart';
import '../../core/models/game_state.dart';
import '../../core/utils/day_keys.dart';
import '../engine.dart' as g;
import '../home/home.dart' as hm;
import '../xp/step_aggregation.dart';
import '../xp/xp.dart';
import 'story_data.dart';

export 'dialogue.dart';
export 'story_data.dart';

g.ActionResult _ok(GameState s, [List<g.GameEvent> events = const []]) => g.ActionResult(s, events: events);
g.ActionResult _fail(GameState s, String error, [Map<String, Object?> info = const {}]) => g.ActionResult(s, error: error, info: info);

String _zone(GameState s) => s.player?.timezone ?? s.tzHint;

int pouchQty(GameState s, String id) => s.story.questPouch[id] ?? 0;

/// Highest level this account has reached with any Evochi (story gates never go backwards).
int accountLevel(GameState s) {
  var lv = math.max(1, s.story.peakLevel);
  final p = s.pet;
  if (p != null) lv = math.max(lv, levelInfo(p.xpAwarded.values.fold(0, (a, b) => a + b)).level);
  for (final pp in s.pastPets) {
    lv = math.max(lv, pp.peakLevel);
  }
  return lv;
}

int _phaseIndex(StoryQuest q, String phase) => q.phases.indexOf(phase);

/// The quest's phase, including the derived 'locked' / 'available' states before acceptance.
String questPhase(GameState s, String qid) {
  final st = s.story.questStates[qid];
  if (st != null) return st.phase;
  return lockReason(s, qid) != null ? 'locked' : 'available';
}

class LockReason {
  const LockReason({
    required this.level,
    required this.needLevel,
    required this.needQuest,
    required this.text,
    this.needSkills = const {},
    this.needStage,
    this.needDiscoveries = 0,
  });
  final int level;
  final bool needLevel;
  final String? needQuest;
  final String text;
  final Map<String, int> needSkills; // skill -> level still needed (Home Tales)
  final int? needStage; // the Evochi stage still needed (side stories)
  final int needDiscoveries; // Trail Guild discoveries still needed (Lumen Trails)
}

/// Why a quest can't be accepted yet, or null.
LockReason? lockReason(GameState s, String qid) {
  final q = storyQuests[qid]!;
  final missing = q.dependsOn.where((id) => s.story.questStates[id]?.phase != 'completed').toList();
  final lv = accountLevel(s);
  final skills = {for (final e in q.skills.entries) if (hm.skillLevel(s.home.skills[e.key] ?? 0).level < e.value) e.key: e.value};
  final stage = q.stage > 0 && (s.pet?.stage ?? 0) < q.stage;
  final disc = q.discoveries > 0 ? math.max(0, q.discoveries - s.trails.stat('discoveries')) : 0;
  if (missing.isEmpty && lv >= q.level && skills.isEmpty && !stage && disc == 0) return null;
  final parts = <String>[
    if (lv < q.level) 'reach level ${q.level}',
    if (missing.isNotEmpty) 'finish "${storyQuests[missing.first]!.title}"',
    for (final e in skills.entries) 'reach ${hm.skillDefs[e.key]!.name} Lv ${e.value}',
    if (disc > 0) 'complete $disc more Trail Guild discover${disc == 1 ? 'y' : 'ies'}',
    if (stage) 'your Evochi grows into a Juvenile',
  ];
  return LockReason(
    level: q.level,
    needLevel: lv < q.level,
    needQuest: missing.isEmpty ? null : missing.first,
    needSkills: skills,
    needStage: stage ? q.stage : null,
    needDiscoveries: disc,
    text: 'Unlocks when ${parts.first.startsWith('your') ? '' : 'you '}${parts.join(' and ')}',
  );
}

/// Steps a quest asks for, frozen at acceptance (min(nominal, personal goal)); 0 without a walk.
int resolvedSteps(GameState s, String qid, int now) {
  final st = s.story.questStates[qid];
  if (st != null) return st.resolvedSteps;
  final walk = storyQuests[qid]!.walk;
  if (walk == null) return 0;
  final goal = g.goalFor(s, dayKey(now, _zone(s)));
  return math.min(walk.nominal, goal);
}

/// Steps from samples that happened at or after [since]. Verified samples that straddle it are
/// clipped proportionally; compacted day records are ignored (progress for those days was frozen
/// while they were still fresh).
Map<String, DayTotal> freshDays(GameState s, int since, String zone) {
  final clipped = <StepSample>[];
  for (final x in s.steps.samples) {
    if (x.source == 'compacted' || x.source == 'compacted-manual') continue;
    if (x.manual) {
      if (!StoryConfig.countManualSteps) continue;
      if (x.end >= since) clipped.add(x);
      continue;
    }
    if (x.start >= since) {
      clipped.add(x);
    } else if (x.end > since) {
      clipped.add(StepSample(id: x.id, source: x.source, start: since, end: x.end, count: (x.count * (x.end - since) / (x.end - x.start)).round()));
    }
  }
  return aggregateDays(clipped, zone);
}

void _addPouch(GameState s, Map<String, int> grant, List<g.GameEvent> events, String qid) {
  grant.forEach((id, n) {
    s.story.questPouch[id] = (s.story.questPouch[id] ?? 0) + n;
    events.add(g.GameEvent('story_item', {'questId': qid, 'itemId': id, 'qty': n, 'name': questMaterials[id]!.name}));
  });
}

/// Advance walking objectives from the step samples. Mutates [s] (a working copy) and returns
/// events. Called from syncSteps after samples are merged, and after accepting a quest.
List<g.GameEvent> applyStoryProgress(GameState s, int now) {
  final events = <g.GameEvent>[];
  if (s.player == null) return events;
  final story = s.story;
  story.peakLevel = math.max(story.peakLevel, accountLevel(s));
  final zone = _zone(s);
  for (final qid in allQuests) {
    final q = storyQuests[qid]!;
    final walk = q.walk;
    final st = story.questStates[qid];
    if (walk == null || st == null || st.phase != walk.phase) continue;
    freshDays(s, st.acceptedAt, zone).forEach((k, d) {
      st.dayProgress[k] = math.max(st.dayProgress[k] ?? 0, d.steps);
    });
    if (walk.type == 'incremental') {
      final total = st.dayProgress.values.fold(0, (a, b) => a + b);
      st.freshTotal = math.max(st.freshTotal, total);
      if (st.freshTotal >= st.resolvedSteps) {
        _addPouch(s, walk.grant, events, qid);
        st.phase = walk.ready;
        st.readyAt = now;
        events.add(_readyEvent(s, qid));
      }
    } else {
      final set = story.qualifiedDayKeys.putIfAbsent(qid, () => <String>[]);
      final keys = st.dayProgress.keys.toList()..sort();
      for (final k in keys) {
        if (set.length >= walk.days) break;
        if (st.dayProgress[k]! >= st.resolvedSteps && !set.contains(k)) {
          set.add(k);
          _addPouch(s, walk.perDay, events, qid);
          events.add(g.GameEvent('story_day', {'questId': qid, 'day': k, 'count': set.length, 'of': walk.days}));
        }
      }
      if (set.length >= walk.days) {
        st.phase = walk.ready;
        st.readyAt = now;
        events.add(_readyEvent(s, qid));
      }
    }
  }
  return events;
}

/// "Something is ready": who to see next, and whether it's a hand-in or a gathering step.
g.GameEvent _readyEvent(GameState s, String qid) {
  final n = nextStep(s, qid);
  return g.GameEvent('story_ready', {'questId': qid, 'npc': n.npc, 'kind': n.kind});
}

// ------------------------------------------------------------------- actions ----
g.ActionResult acceptStoryQuest(GameState state, String qid, int now) {
  final q = storyQuests[qid];
  if (q == null) return _fail(state, 'unknown_quest');
  if (state.player == null) return _fail(state, 'no_player');
  if (state.story.questStates[qid] != null) return _ok(state, [g.GameEvent('story_already', {'questId': qid})]); // idempotent
  final lock = lockReason(state, qid);
  if (lock != null) return _fail(state, 'story_locked', {'message': lock.text});
  final s = state.copy();
  s.story.questStates[qid] = QuestState(
    phase: q.walk?.phase ?? q.acceptPhase!,
    acceptedAt: now,
    acceptedDay: dayKey(now, _zone(s)),
    resolvedSteps: resolvedSteps(s, qid, now),
  );
  s.story.activeQuestId = qid;
  s.story.offersSeen[qid] = true;
  return _ok(s, [
    g.GameEvent('story_accepted', {'questId': qid, 'title': q.title}),
    ...applyStoryProgress(s, now),
  ]);
}

bool _hasItems(GameState s, Map<String, int> consume) => consume.entries.every((e) => pouchQty(s, e.key) >= e.value);

/// One inventory item a hand-in asks for (a harvest, homemade food), and how many are in the Bag.
class ItemNeed {
  const ItemNeed(this.id, this.need, this.have);
  final String id;
  final int need;
  final int have; // capped at [need]
  bool get ok => have >= need;
}

/// Inventory items a hand-in asks for (harvests, homemade food), and what's still missing.
/// [spent] counts items already given at the place (offered during its encounter): they did the job.
List<ItemNeed> itemNeeds(GameState s, TurnIn? t, [Map<String, int> spent = const {}]) => [
      for (final e in (t?.consumeItems ?? const <String, int>{}).entries)
        ItemNeed(e.key, e.value, math.min(g.ownedQty(s, e.key) + (spent[e.key] ?? 0), e.value)),
    ];

bool _stageOk(GameState s, TurnIn? t) => t == null || t.requireStage <= 0 || (s.pet?.stage ?? 0) >= t.requireStage;

/// Give quest items to a villager (or the Waystone, or your Cottage). Transactional and idempotent.
g.ActionResult storyHandIn(GameState state, String qid, String turnInId, int now, {Map<String, int> spent = const {}}) {
  final q = storyQuests[qid];
  final t = q?.turnIns.where((x) => x.id == turnInId).firstOrNull;
  if (q == null || t == null) return _fail(state, 'unknown_turnin');
  final st = state.story.questStates[qid];
  if (st == null) return _fail(state, 'story_not_accepted');
  if (_phaseIndex(q, st.phase) > _phaseIndex(q, t.from)) {
    return _ok(state, [g.GameEvent('story_already', {'questId': qid, 'turnIn': turnInId})]);
  }
  if (st.phase != t.from) return _fail(state, 'story_not_ready');
  if (!_hasItems(state, t.consume)) return _fail(state, 'story_missing_items');
  final short = itemNeeds(state, t, spent).where((x) => !x.ok).toList();
  if (short.isNotEmpty) return _fail(state, 'story_missing_items', {'missing': short});
  if (!_stageOk(state, t)) return _fail(state, 'story_needs_stage', {'stage': t.requireStage});
  final s = state.copy();
  final story = s.story;
  final events = <g.GameEvent>[];
  t.consume.forEach((id, n) {
    final left = (story.questPouch[id] ?? 0) - n;
    if (left <= 0) {
      story.questPouch.remove(id);
    } else {
      story.questPouch[id] = left;
    }
  });
  t.consumeItems.forEach((id, n) {
    // from the Bag first (as always); only a shortfall is covered by what was already offered at the place
    final take = math.min(n, g.ownedQty(s, id));
    if (take > 0) s.inventory[id]!.quantity -= take;
  });
  events.add(g.GameEvent('story_handin', {'questId': qid, 'turnIn': turnInId, 'npc': t.npc, 'consumed': t.consume}));
  _addPouch(s, t.grant, events, qid);
  for (final f in t.flags) {
    story.flags[f] = true;
  }
  final qs = story.questStates[qid]!;
  qs.phase = t.to;
  if (t.to == 'completed') {
    qs.completedAt = now;
    final rewards = grantStoryRewardOnce(s, qid, now);
    if (story.activeQuestId == qid) story.activeQuestId = null;
    events.add(g.GameEvent('story_completed', {'questId': qid, 'title': q.title, 'rewards': rewards}));
  } else {
    events.add(_readyEvent(s, qid));
  }
  return _ok(s, events);
}

/// Pay out a quest's rewards exactly once (inventory items, EvoCoins, gifts, titles). Mutates [s].
/// Returns null when they were already paid.
StoryRewards? grantStoryRewardOnce(GameState s, String qid, int now) {
  final story = s.story;
  if (story.claimedRewards.contains(qid)) return null;
  final r = storyQuests[qid]!.rewards;
  for (final id in r.items) {
    final it = catalog[id];
    if (it == null || !it.isStory) throw StateError('story reward must be a story item: $id');
    if (g.ownedQty(s, id) <= 0) g.grantItem(s, id, 1, 'story:$qid', now, 'story:$qid');
  }
  if (r.coins > 0) g.addTxn(s, WalletTxn(id: 'story:$qid', amount: r.coins, cause: 'story:$qid', at: now));
  r.gifts.forEach((id, n) => g.grantItem(s, id, n, 'story:$qid', now, 'story:$qid:gift'));
  for (final t in r.titles) {
    if (!story.titleUnlocks.contains(t)) story.titleUnlocks.add(t);
  }
  story.claimedRewards.add(qid);
  return r;
}

g.ActionResult _patch(GameState state, void Function(StoryState st) fn) {
  final s = state.copy();
  fn(s.story);
  return _ok(s);
}

g.ActionResult markNpcMet(GameState state, String npcId) => state.story.npcsMet[npcId] == true ? _ok(state) : _patch(state, (st) => st.npcsMet[npcId] = true);

g.ActionResult markOfferSeen(GameState state, String qid) => state.story.offersSeen[qid] == true ? _ok(state) : _patch(state, (st) => st.offersSeen[qid] = true);

g.ActionResult markCompletionSeen(GameState state, String qid) {
  final st = state.story.questStates[qid];
  if (st == null || st.seenCompletion) return _ok(state);
  return _patch(state, (x) => x.questStates[qid]!.seenCompletion = true);
}

g.ActionResult setTracked(GameState state, String qid, bool on) {
  if (state.story.questStates[qid] == null) return _fail(state, 'story_not_accepted');
  return _patch(state, (x) => x.questStates[qid]!.tracked = on);
}

/// Playtest only: finish Chapter 1's first quest (with its reward) and reach account level 2, so the
/// Home Tales open. Returns the state unchanged (no events) when that's already true.
g.ActionResult playtestHomeTalesReady(GameState state, int now) {
  final s = state.copy();
  final st = s.story;
  var changed = false;
  if (st.questStates['vq01']?.phase != 'completed') {
    st.questStates['vq01'] = QuestState(
      phase: 'completed',
      acceptedAt: now - hourMs,
      acceptedDay: dayKey(now - hourMs, _zone(s)),
      resolvedSteps: 2000,
      completedAt: now,
      seenCompletion: true,
      tracked: false,
    );
    st.questPouch.remove('q_dawn_dew_vial');
    st.questPouch.remove('q_lumenbud_sprig');
    st.flags['lamp_lit'] = true;
    grantStoryRewardOnce(s, 'vq01', now);
    if (st.activeQuestId == 'vq01') st.activeQuestId = null;
    changed = true;
  }
  if (accountLevel(s) < 2) {
    st.peakLevel = 2;
    changed = true;
  }
  return changed ? _ok(s, [const g.GameEvent('playtest_home_tales')]) : _ok(state);
}

/// Re-evaluate walking progress without new samples (app open, entering the Village).
g.ActionResult storyTick(GameState state, int now) {
  final s = state.copy();
  final events = applyStoryProgress(s, now);
  return _ok(events.isEmpty ? state : s, events);
}

// --------------------------------------------------------------------- views ----
class NextStep {
  const NextStep(this.kind, {this.npc, this.place, this.turnIn, this.label, this.needs = const [], this.stage = 0, this.encounter});
  final String kind; // locked | talk | walk | gather | grow | encounter | handin | done
  final String? npc;
  final String? place; // a place id, 'waystone', 'cottage', 'ruins' or 'gate'
  final String? turnIn;
  final String? label;
  final List<ItemNeed> needs; // gather / handin: the inventory items the hand-in takes
  final int stage; // grow: the Evochi stage the hand-in needs
  final String? encounter; // encounter (and gather before one): the creature at the place
}

/// Trail places: hand-ins that happen at the Mossy Ruins or the Old Gate (encounters).
const trailPlaceIds = {'ruins', 'gate'};

/// Where a villager (or the Waystone, your Cottage, the ruins or the gate) is found.
String placeOf(String npc) => npc == 'waystone' || npc == 'cottage' || trailPlaceIds.contains(npc) ? npc : npcs[npc]!.location;

/// Where to go next for a quest.
NextStep nextStep(GameState s, String qid) {
  final q = storyQuests[qid]!;
  final phase = questPhase(s, qid);
  if (phase == 'completed') return const NextStep('done');
  if (phase == 'locked') return NextStep('locked', npc: q.giver, place: placeOf(q.giver));
  if (phase == 'available') return NextStep('talk', npc: q.giver, place: placeOf(q.giver));
  if (q.walk != null && phase == q.walk!.phase) return const NextStep('walk');
  final t = q.turnIns.where((x) => x.from == phase).firstOrNull;
  if (t == null) return const NextStep('done');
  final place = placeOf(t.npc);
  final needs = itemNeeds(s, t);
  if (needs.any((x) => !x.ok)) return NextStep('gather', npc: t.npc, place: place, turnIn: t.id, label: t.label, needs: needs, encounter: t.encounter);
  if (!_stageOk(s, t)) return NextStep('grow', npc: t.npc, place: place, turnIn: t.id, label: t.label, stage: t.requireStage);
  if (t.encounter != null) return NextStep('encounter', npc: t.npc, place: place, turnIn: t.id, label: t.label, needs: needs, encounter: t.encounter);
  return NextStep('handin', npc: t.npc, place: place, turnIn: t.id, label: t.label, needs: needs);
}

String fill(String text, Map<String, String> vars) => text.replaceAllMapped(RegExp(r'\{(\w+)\}'), (m) => vars[m[1]] ?? m[0]!);

String fmtN(int n) {
  final str = n.abs().toString();
  final b = StringBuffer(n < 0 ? '-' : '');
  for (var i = 0; i < str.length; i++) {
    if (i > 0 && (str.length - i) % 3 == 0) b.write(',');
    b.write(str[i]);
  }
  return b.toString();
}

class WalkView {
  const WalkView({required this.type, required this.target, required this.days, this.progress = 0, this.pct = 0, this.qualified = 0, this.todaySteps = 0, this.todayDone = false});
  final String type; // incremental | days | none (a quest without a walk; the web build's `walk: null`)
  final int target;
  final int days;
  final int progress; // incremental
  final double pct;
  final int qualified; // days
  final int todaySteps;
  final bool todayDone;
}

class ObjectiveView {
  const ObjectiveView(this.id, this.text, this.done, {this.item, this.need = 0, this.have = 0, this.ready = false, this.optional = false});
  final String id;
  final String text;
  final bool done;
  final bool optional; // never blocks the quest
  final String? item; // counted objectives: the inventory item ("Grow and harvest 3 Sunberries")
  final int need;
  final int have; // capped at [need]
  final bool ready; // done, or enough in the Bag
}

/// Everything the Journey card, quest details and the Village need about one quest.
class StoryQuestView {
  StoryQuestView({
    required this.id,
    required this.quest,
    required this.phase,
    required this.accepted,
    required this.lock,
    required this.resolved,
    required this.walk,
    required this.objectives,
    required this.current,
    required this.next,
    required this.tracked,
    required this.paused,
    required this.seenCompletion,
    required this.completedAt,
  });
  final String id;
  final StoryQuest quest;
  final String phase;
  final bool accepted;
  final LockReason? lock;
  final int resolved;
  final WalkView walk;
  final List<ObjectiveView> objectives;
  final String? current;
  final NextStep next;
  final bool tracked;
  final bool paused; // walking, but no step source connected: waiting, never failing
  final bool seenCompletion;
  final int? completedAt;

  int get n => quest.n;
  String get title => quest.title;
  int get level => quest.level;
  String get summary => quest.summary;
  String get giver => quest.giver;
  StoryRewards get rewards => quest.rewards;
  String get line => quest.line; // chapter | home | side | trail
  bool get hasWalk => quest.walk != null;
  List<String> get dependsOn => quest.dependsOn;
  bool get completed => phase == 'completed';
}

StoryQuestView questView(GameState s, String qid, int now) {
  final q = storyQuests[qid]!;
  final st = s.story.questStates[qid];
  final phase = questPhase(s, qid);
  final lock = phase == 'locked' ? lockReason(s, qid) : null;
  final resolved = resolvedSteps(s, qid, now);
  final today = dayKey(now, _zone(s));
  final qualified = s.story.qualifiedDayKeys[qid] ?? const <String>[];
  final qw = q.walk;
  var walk = qw == null ? const WalkView(type: 'none', target: 0, days: 0) : WalkView(type: qw.type, target: resolved, days: qw.days);
  if (st != null && qw != null) {
    if (qw.type == 'incremental') {
      final total = _phaseIndex(q, phase) > _phaseIndex(q, qw.phase) ? resolved : math.min(resolved, st.freshTotal);
      walk = WalkView(type: qw.type, target: resolved, days: qw.days, progress: total, pct: resolved > 0 ? total / resolved : 1.0);
    } else {
      walk = WalkView(
        type: qw.type,
        target: resolved,
        days: qw.days,
        qualified: qualified.length,
        todaySteps: math.min(resolved, st.dayProgress[today] ?? 0),
        todayDone: qualified.contains(today),
        pct: qualified.length / qw.days,
      );
    }
  }
  final pi = _phaseIndex(q, phase);
  final objectives = <ObjectiveView>[];
  for (final o in q.objectives) {
    final done = pi >= _phaseIndex(q, o.doneAt);
    final text = fill(o.text, {'resolved_steps': fmtN(resolved)});
    final c = o.count;
    if (c == null) {
      objectives.add(ObjectiveView(o.id, text, done, optional: o.optional));
    } else {
      final have = math.min(c.n, g.ownedQty(s, c.itemId));
      objectives.add(ObjectiveView(o.id, text, done, item: c.itemId, need: c.n, have: done ? c.n : have, ready: done || have >= c.n, optional: o.optional));
    }
  }
  return StoryQuestView(
    id: qid,
    quest: q,
    phase: phase,
    accepted: st != null,
    lock: lock,
    resolved: resolved,
    walk: walk,
    objectives: objectives,
    current: objectives.where((o) => !o.done && !o.optional && !(o.ready && o.item != null)).firstOrNull?.id ?? objectives.where((o) => !o.done && !o.optional).firstOrNull?.id,
    next: nextStep(s, qid),
    tracked: st?.tracked ?? false,
    paused: st != null && qw != null && phase == qw.phase && s.steps.connection == 'none',
    seenCompletion: st?.seenCompletion ?? false,
    completedAt: st?.completedAt,
  );
}

class StoryStatus {
  StoryStatus({
    required this.quests,
    required this.home,
    required this.side,
    required this.trail,
    required this.flags,
    required this.pouch,
    required this.titles,
    required this.level,
    required this.activeQuestId,
    required this.offers,
  });
  final List<StoryQuestView> quests; // Chapter 1
  final List<StoryQuestView> home; // Home Tales
  final List<StoryQuestView> side; // side stories (optional)
  final List<StoryQuestView> trail; // Lumen Trails (encounter quests)
  final Map<String, bool> flags;
  final Map<String, int> pouch;
  final List<String> titles;
  final int level;
  final String? activeQuestId;
  final List<StoryQuestView> offers; // available quests the player hasn't opened yet

  List<StoryQuestView> get all => [...quests, ...home, ...side, ...trail];

  /// Hand-ins waiting in the Village (the Cottage hand-in happens on the Home Map, so it isn't one).
  List<StoryQuestView> get turnIns => all.where((v) => v.next.kind == 'handin' && v.next.npc != 'cottage').toList();

  /// Encounters ready to play (the quest's walk and gathering are done).
  List<StoryQuestView> get encounters => all.where((v) => v.next.kind == 'encounter').toList();
  List<StoryQuestView> get actives => all.where((v) => v.accepted && !v.completed).toList();
  StoryQuestView? get active => actives.where((v) => v.id == activeQuestId).firstOrNull ?? actives.firstOrNull;
  List<StoryQuestView> get unseenDone => all.where((v) => v.completed && !v.seenCompletion).toList();
  int get attention => turnIns.length + offers.length;

  /// The quest the Village strip shows: the chapter first, then the Home Tales once it's done.
  StoryQuestView? get nextUp {
    final chapterActive = quests.where((v) => v.accepted && !v.completed).firstOrNull;
    if (chapterActive != null) return chapterActive;
    final avail = quests.where((v) => v.phase == 'available').firstOrNull;
    if (avail != null) return avail;
    if (chapterDone) {
      final h = home.where((v) => v.accepted && !v.completed).firstOrNull ?? home.where((v) => v.phase == 'available').firstOrNull;
      if (h != null) return h;
    }
    return quests.where((v) => v.phase == 'locked').firstOrNull;
  }

  bool get chapterDone => quests.every((v) => v.completed);
  bool get cottageReady => quest('hq01').phase == 'restoration_ready';
  StoryQuestView quest(String id) => all.firstWhere((v) => v.id == id);
  bool flag(String f) => flags[f] ?? false;
}

/// Summary for badges and the Village: quest views, flags, pouch, what needs attention.
StoryStatus storyStatus(GameState s, int now) {
  final quests = [for (final id in questOrder) questView(s, id, now)];
  final homeQuests = [for (final id in homeOrder) questView(s, id, now)];
  final side = [for (final id in sideOrder) questView(s, id, now)];
  final trail = [for (final id in trailOrder) questView(s, id, now)];
  return StoryStatus(
    quests: quests,
    home: homeQuests,
    side: side,
    trail: trail,
    flags: {...defaultStoryFlags, ...s.story.flags},
    pouch: Map.of(s.story.questPouch),
    titles: List.of(s.story.titleUnlocks),
    level: accountLevel(s),
    activeQuestId: s.story.activeQuestId,
    offers: [...quests, ...homeQuests, ...side, ...trail].where((v) => v.phase == 'available' && s.story.offersSeen[v.id] != true).toList(),
  );
}

/// New offers the player hasn't opened yet.
List<StoryQuestView> unseenOffers(GameState s, StoryStatus st) => st.all.where((v) => v.phase == 'available' && s.story.offersSeen[v.id] != true).toList();

/// Something in the Village is waiting for the player (badge on Visit Village / Story tab).
int storyAttention(GameState s, StoryStatus st) => st.turnIns.length + unseenOffers(s, st).length;

/// Which villagers have something for the player right now (map markers): 'handin' | 'quest'.
Map<String, String> npcMarkers(GameState s) {
  final out = <String, String>{};
  for (final qid in allQuests) {
    final n = nextStep(s, qid);
    if (n.kind == 'handin') {
      out[n.npc!] = 'handin';
    } else if (n.kind == 'talk' && !out.containsKey(n.npc)) {
      out[n.npc!] = 'quest';
    }
  }
  return out;
}
