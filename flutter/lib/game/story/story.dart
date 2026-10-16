// Village Tales, Chapter 1 rules (Quest Bible v1.0 §9). Mirrors web/src/game/story.js.
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
  const LockReason({required this.level, required this.needLevel, required this.needQuest, required this.text});
  final int level;
  final bool needLevel;
  final String? needQuest;
  final String text;
}

/// Why a quest can't be accepted yet, or null.
LockReason? lockReason(GameState s, String qid) {
  final q = storyQuests[qid]!;
  final missing = q.dependsOn.where((id) => s.story.questStates[id]?.phase != 'completed').toList();
  final lv = accountLevel(s);
  if (missing.isEmpty && lv >= q.level) return null;
  final parts = <String>[
    if (lv < q.level) 'reach level ${q.level}',
    if (missing.isNotEmpty) 'finish "${storyQuests[missing.first]!.title}"',
  ];
  return LockReason(level: q.level, needLevel: lv < q.level, needQuest: missing.isEmpty ? null : missing.first, text: 'Unlocks when you ${parts.join(' and ')}');
}

/// Steps a quest asks for, frozen at acceptance (min(nominal, personal goal)).
int resolvedSteps(GameState s, String qid, int now) {
  final st = s.story.questStates[qid];
  if (st != null) return st.resolvedSteps;
  final goal = g.goalFor(s, dayKey(now, _zone(s)));
  return math.min(storyQuests[qid]!.walk.nominal, goal);
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
  for (final qid in questOrder) {
    final q = storyQuests[qid]!;
    final st = story.questStates[qid];
    if (st == null || st.phase != q.walk.phase) continue;
    freshDays(s, st.acceptedAt, zone).forEach((k, d) {
      st.dayProgress[k] = math.max(st.dayProgress[k] ?? 0, d.steps);
    });
    if (q.walk.type == 'incremental') {
      final total = st.dayProgress.values.fold(0, (a, b) => a + b);
      st.freshTotal = math.max(st.freshTotal, total);
      if (st.freshTotal >= st.resolvedSteps) {
        _addPouch(s, q.walk.grant, events, qid);
        st.phase = q.walk.ready;
        st.readyAt = now;
        events.add(g.GameEvent('story_ready', {'questId': qid, 'npc': nextStep(s, qid).npc}));
      }
    } else {
      final set = story.qualifiedDayKeys.putIfAbsent(qid, () => <String>[]);
      final keys = st.dayProgress.keys.toList()..sort();
      for (final k in keys) {
        if (set.length >= q.walk.days) break;
        if (st.dayProgress[k]! >= st.resolvedSteps && !set.contains(k)) {
          set.add(k);
          _addPouch(s, q.walk.perDay, events, qid);
          events.add(g.GameEvent('story_day', {'questId': qid, 'day': k, 'count': set.length, 'of': q.walk.days}));
        }
      }
      if (set.length >= q.walk.days) {
        st.phase = q.walk.ready;
        st.readyAt = now;
        events.add(g.GameEvent('story_ready', {'questId': qid, 'npc': nextStep(s, qid).npc}));
      }
    }
  }
  return events;
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
    phase: q.walk.phase,
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

/// Give quest items to a villager (or the Waystone). Transactional and idempotent.
g.ActionResult storyHandIn(GameState state, String qid, String turnInId, int now) {
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
    events.add(g.GameEvent('story_ready', {'questId': qid, 'npc': nextStep(s, qid).npc}));
  }
  return _ok(s, events);
}

/// Pay out a quest's rewards exactly once (inventory items, EvoCoins, titles). Mutates [s].
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

/// Re-evaluate walking progress without new samples (app open, entering the Village).
g.ActionResult storyTick(GameState state, int now) {
  final s = state.copy();
  final events = applyStoryProgress(s, now);
  return _ok(events.isEmpty ? state : s, events);
}

// --------------------------------------------------------------------- views ----
class NextStep {
  const NextStep(this.kind, {this.npc, this.place, this.turnIn, this.label});
  final String kind; // locked | talk | walk | handin | done
  final String? npc;
  final String? place;
  final String? turnIn;
  final String? label;
}

String placeOf(String npc) => npc == 'waystone' ? 'waystone' : npcs[npc]!.location;

/// Where to go next for a quest.
NextStep nextStep(GameState s, String qid) {
  final q = storyQuests[qid]!;
  final phase = questPhase(s, qid);
  if (phase == 'completed') return const NextStep('done');
  if (phase == 'locked') return NextStep('locked', npc: q.giver, place: placeOf(q.giver));
  if (phase == 'available') return NextStep('talk', npc: q.giver, place: placeOf(q.giver));
  if (phase == q.walk.phase) return const NextStep('walk');
  final t = q.turnIns.where((x) => x.from == phase).firstOrNull;
  if (t == null) return const NextStep('done');
  return NextStep('handin', npc: t.npc, place: placeOf(t.npc), turnIn: t.id, label: t.label);
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
  final String type;
  final int target;
  final int days;
  final int progress; // incremental
  final double pct;
  final int qualified; // days
  final int todaySteps;
  final bool todayDone;
}

class ObjectiveView {
  const ObjectiveView(this.id, this.text, this.done);
  final String id;
  final String text;
  final bool done;
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
  var walk = WalkView(type: q.walk.type, target: resolved, days: q.walk.days);
  if (st != null) {
    if (q.walk.type == 'incremental') {
      final total = _phaseIndex(q, phase) > _phaseIndex(q, q.walk.phase) ? resolved : math.min(resolved, st.freshTotal);
      walk = WalkView(type: q.walk.type, target: resolved, days: q.walk.days, progress: total, pct: total / resolved);
    } else {
      walk = WalkView(
        type: q.walk.type,
        target: resolved,
        days: q.walk.days,
        qualified: qualified.length,
        todaySteps: math.min(resolved, st.dayProgress[today] ?? 0),
        todayDone: qualified.contains(today),
        pct: qualified.length / q.walk.days,
      );
    }
  }
  final pi = _phaseIndex(q, phase);
  final objectives = [
    for (final o in q.objectives) ObjectiveView(o.id, fill(o.text, {'resolved_steps': fmtN(resolved)}), pi >= _phaseIndex(q, o.doneAt)),
  ];
  return StoryQuestView(
    id: qid,
    quest: q,
    phase: phase,
    accepted: st != null,
    lock: lock,
    resolved: resolved,
    walk: walk,
    objectives: objectives,
    current: objectives.where((o) => !o.done).firstOrNull?.id,
    next: nextStep(s, qid),
    tracked: st?.tracked ?? false,
    paused: st != null && phase == q.walk.phase && s.steps.connection == 'none',
    seenCompletion: st?.seenCompletion ?? false,
    completedAt: st?.completedAt,
  );
}

class StoryStatus {
  StoryStatus({
    required this.quests,
    required this.flags,
    required this.pouch,
    required this.titles,
    required this.level,
  });
  final List<StoryQuestView> quests;
  final Map<String, bool> flags;
  final Map<String, int> pouch;
  final List<String> titles;
  final int level;

  List<StoryQuestView> get turnIns => quests.where((v) => v.next.kind == 'handin').toList();
  StoryQuestView? get active => quests.where((v) => v.accepted && !v.completed).firstOrNull;
  StoryQuestView? get nextUp =>
      active ?? quests.where((v) => v.phase == 'available').firstOrNull ?? quests.where((v) => v.phase == 'locked').firstOrNull;
  bool get chapterDone => quests.every((v) => v.completed);
  StoryQuestView quest(String id) => quests.firstWhere((v) => v.id == id);
  bool flag(String f) => flags[f] ?? false;
}

/// Summary for badges and the Village: quest views, flags, pouch, what needs attention.
StoryStatus storyStatus(GameState s, int now) => StoryStatus(
      quests: [for (final id in questOrder) questView(s, id, now)],
      flags: {...defaultStoryFlags, ...s.story.flags},
      pouch: Map.of(s.story.questPouch),
      titles: List.of(s.story.titleUnlocks),
      level: accountLevel(s),
    );

/// New offers the player hasn't opened yet.
List<StoryQuestView> unseenOffers(GameState s, StoryStatus st) => st.quests.where((v) => v.phase == 'available' && s.story.offersSeen[v.id] != true).toList();

/// Something in the Village is waiting for the player (badge on Visit Village / Story tab).
int storyAttention(GameState s, StoryStatus st) => st.turnIns.length + unseenOffers(s, st).length;

/// Which villagers have something for the player right now (map markers): 'handin' | 'quest'.
Map<String, String> npcMarkers(GameState s) {
  final out = <String, String>{};
  for (final qid in questOrder) {
    final n = nextStep(s, qid);
    if (n.kind == 'handin') {
      out[n.npc!] = 'handin';
    } else if (n.kind == 'talk' && !out.containsKey(n.npc)) {
      out[n.npc!] = 'quest';
    }
  }
  return out;
}
