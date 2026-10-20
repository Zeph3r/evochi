// GameController: owns the GameState, runs engine actions, persists, syncs steps and
// fans out engine events to the UI (toasts, sounds, pet reactions).

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_timezone/flutter_timezone.dart';

import '../app/constants.dart';
import '../core/models/catalog.dart';
import '../core/models/game_state.dart';
import '../core/services/analytics.dart';
import '../core/services/audio_service.dart';
import '../core/services/haptics.dart';
import '../core/utils/day_keys.dart';
import '../data/health_adapters/demo_step_source.dart';
import '../data/health_adapters/health_step_source.dart';
import '../data/health_adapters/step_source.dart';
import '../data/repositories/game_repository.dart';
import '../game/engine.dart' as g;
import '../game/home/home.dart' as h;
import '../game/story/story.dart' as story;
import '../game/trails/trails.dart' as tr;

class Toast {
  const Toast(this.message, {this.icon, this.kind = 'ok'});
  final String message;
  final String? icon;
  final String kind; // ok | warn | err
}

class GameController extends ChangeNotifier {
  GameController({required this.repo, StepSource? health, DemoStepSource? demo})
      : demo = demo ?? DemoStepSource(),
        _health = health;

  final GameRepository repo;
  final DemoStepSource demo;
  StepSource? _health;
  final AudioService audio = AudioService();
  final Analytics analytics = Analytics();

  late GameState state;
  bool ready = false;
  bool syncing = false;
  final _events = StreamController<g.GameEvent>.broadcast();
  final _toasts = StreamController<Toast>.broadcast();
  Stream<g.GameEvent> get events => _events.stream;
  Stream<Toast> get toasts => _toasts.stream;

  g.GameView? _view;
  story.StoryStatus? _story;
  h.HomeStatus? _home;
  tr.TrailsStatus? _trails;
  int _viewAt = 0;

  /// Cross-route navigation requests (pushed Village screens can't reach the tab shell directly).
  final tabRequest = ValueNotifier<String?>(null);
  String journeyTab = 'daily'; // daily | weekly | story | skills
  bool storyDoneOpen = false; // Journey > Story: the completed stories unfolded
  String? bagCategoryRequest; // e.g. 'pouch'
  String? bagItemRequest; // the item to pick there (the Market's "View in Bag")

  /// Profile > Developer tools: the step simulator, the Garden's time skip and the playtest shortcuts.
  bool get devTools => state.player?.settings.devTools ?? false;

  int get now => DateTime.now().millisecondsSinceEpoch + state.clockOffset;

  StepSource get health => _health ??= HealthStepSource();

  g.GameView get view {
    final n = now;
    if (_view == null || (n - _viewAt).abs() > 15000) {
      _view = g.derive(state, n);
      _story = null;
      _home = null;
      _trails = null;
      _viewAt = n;
    }
    return _view!;
  }

  /// Village Tales: quest views, flags and the Quest Pouch (cached with [view]).
  story.StoryStatus get storyView {
    view;
    return _story ??= story.storyStatus(state, _viewAt);
  }

  /// Hand-ins waiting plus quest offers not opened yet (badges on Visit Village and Journey > Story).
  int get storyAttention => story.storyAttention(state, storyView);

  /// Home Tales: garden beds, skills and rooms (cached with [view]; beds grow on real time, so screens
  /// that show growth call [h.plotView] with [now] directly).
  h.HomeStatus get homeView {
    view;
    return _home ??= h.homeStatus(state, _viewAt);
  }

  /// Lumen Trails: today's discoveries, guild rank, companions and the live encounter (cached with
  /// [view]; screens that show walking progress read [tr.discoveryView] with [now] directly).
  tr.TrailsStatus get trailsView {
    view;
    return _trails ??= tr.trailsStatus(state, _viewAt);
  }

  /// Something new at home (badge on Explore Home): a ripe bed, the starter gift, the Cottage ready,
  /// or a discovery to inspect on the Home Map, in the Garden or at the Cottage.
  bool get homeAttention {
    final hv = h.homeStatus(state, now);
    final clue = trailsView.ready.any((d) => const {'homemap', 'garden', 'cottage'}.contains(d.place));
    return hv.ripe > 0 || !hv.starterSeeds || storyView.cottageReady || clue;
  }

  /// The Trail Guild has something for you (the dot on its Village row): a discovery to inspect, an
  /// encounter ready, or today's board not started yet.
  bool get guildAttention {
    final t = trailsView;
    return t.ready.isNotEmpty || storyView.encounters.isNotEmpty || (t.foundToday == 0 && t.walking.isEmpty);
  }

  /// Switch the main tab from anywhere (closes pushed screens first; see MainShell).
  void goTab(String tab, {String? journey, String? bag, String? bagItem}) {
    if (journey != null) journeyTab = journey;
    if (bag != null) bagCategoryRequest = bag;
    if (bagItem != null) bagItemRequest = bagItem;
    tabRequest.value = null;
    tabRequest.value = tab;
    notifyListeners();
  }

  Future<void> init() async {
    ensureTimeZones();
    String zone;
    try {
      zone = await FlutterTimezone.getLocalTimezone();
    } catch (_) {
      zone = 'UTC';
    }
    state = await repo.load() ?? GameState.fresh(DateTime.now().millisecondsSinceEpoch, zone);
    state.tzHint = zone;
    _applySettings();
    // what the phone's vibration motor can do (patterns, strengths), for the haptics
    unawaited(audio.hx.init());
    ready = true;
    // story walks re-check progress on open (e.g. a quest whose target was met by the last sync)
    if (state.player != null) run((s, n) => story.storyTick(s, n), quiet: true);
    notifyListeners();
    if (state.pet != null && state.steps.connection != 'none') unawaited(sync());
  }

  void _applySettings() {
    final st = state.player?.settings;
    audio.configure(sound: st?.sound ?? true, music: st?.music ?? true, haptics: st?.haptics ?? true);
    analytics.consent = st?.analytics ?? false;
  }

  void _commit(GameState s) {
    s.savedAtMs = DateTime.now().millisecondsSinceEpoch;
    state = s;
    _view = null;
    _story = null;
    _home = null;
    _trails = null;
    repo.save(s);
    _applySettings();
    notifyListeners();
  }

  /// Runs an engine action. On success commits and broadcasts; on failure shows a friendly toast.
  g.ActionResult run(g.ActionResult Function(GameState s, int now) action, {bool quiet = false}) {
    final res = action(state, now);
    if (res.ok) {
      if (!identical(res.state, state)) _commit(res.state);
      for (final e in res.events) {
        _events.add(e);
        _handle(e);
      }
    } else if (!quiet) {
      _errorToast(res);
    }
    return res;
  }

  void toast(String message, {String? icon, String kind = 'ok'}) => _toasts.add(Toast(message, icon: icon, kind: kind));

  void _errorToast(g.ActionResult r) {
    final m = <String, Toast>{
      'insufficient': Toast('Not enough EvoCoins - ${r.info['short']} more needed', icon: 'coin', kind: 'warn'),
      'owned': const Toast('You already own this', icon: 'bag', kind: 'warn'),
      'not_eligible': const Toast('Not ready yet - keep walking!', icon: 'steps', kind: 'warn'),
      'pet_dead': const Toast('Your Evochi is resting in the memorial', icon: 'heart_empty', kind: 'warn'),
      'full': const Toast('Vitality is already full', icon: 'heart'),
      'cooldown': const Toast('Recovery items need a short rest between uses', icon: 'potion', kind: 'warn'),
      'no_anchor': const Toast('That decoration does not fit this spot', icon: 'decorations', kind: 'warn'),
      'all_placed': const Toast('All of those are already placed', icon: 'decorations', kind: 'warn'),
      'incompatible': const Toast("This accessory doesn't fit your Evochi's current form", icon: 'wearables', kind: 'warn'),
      'invalid_name': Toast((r.info['message'] as String?) ?? 'Check the name', icon: 'paw', kind: 'warn'),
      'need_herbs': Toast('You need ${r.info['need']} Healing Herbs', icon: 'care', kind: 'warn'),
      'walk_needed': const Toast("Reach today's step goal to rekindle", icon: 'steps', kind: 'warn'),
      'not_for_sale': const Toast('Story rewards are earned, never sold', icon: 'star', kind: 'warn'),
      'story_locked': Toast((r.info['message'] as String?) ?? 'Not unlocked yet', icon: 'lock', kind: 'warn'),
      'story_not_ready': const Toast('Not ready yet - keep going!', icon: 'journey', kind: 'warn'),
      'story_missing_items': Toast(_missingText(r.info['missing']) ?? 'Something is missing from your Quest Pouch', icon: 'journey', kind: 'warn'),
      'story_needs_stage': const Toast('Your Evochi needs to grow into a Juvenile first', icon: 'evolve', kind: 'warn'),
      'not_owned': const Toast('You do not own this yet', icon: 'bag', kind: 'warn'),
      'plot_locked': Toast('This bed opens at Farming Lv ${r.info['need'] ?? 4}', icon: 'lock', kind: 'warn'),
      'plot_busy': const Toast('Something is already growing here', icon: 'skill_farming', kind: 'warn'),
      'crop_locked': Toast('Reach Farming Lv ${r.info['need'] ?? 2} to grow this', icon: 'lock', kind: 'warn'),
      'no_seed': const Toast('No seeds left - get more in the Market', icon: 'shop', kind: 'warn'),
      'not_ripe': const Toast('Not ripe yet - a walk will speed it up', icon: 'steps', kind: 'warn'),
      'tonic_used': const Toast('This bed already had a Sprout Tonic', icon: 'potion', kind: 'warn'),
      'already_ripe': const Toast('Already ripe - harvest it!', icon: 'skill_farming'),
      'station_locked': const Toast('That room is not open yet', icon: 'lock', kind: 'warn'),
      'recipe_locked': r.info['flag'] == 'sprout_restored'
          ? const Toast('Restore the Hollow Sprout (Tangled Lumen) to learn this recipe', icon: 'lock', kind: 'warn')
          : Toast('Reach ${h.skillDefs[r.info['skill']]?.name ?? 'your skill'} Lv ${r.info['need'] ?? 2} to learn this recipe', icon: 'lock', kind: 'warn'),
      'missing_ingredients': const Toast('Some ingredients are missing', icon: 'skill_farming', kind: 'warn'),
      'use_in_garden': const Toast('Use this on a garden bed', icon: 'skill_farming', kind: 'warn'),
      'discovery_not_ready': Toast('Walk ${fmtSteps(r.info['need'])} more steps first', icon: 'steps', kind: 'warn'),
      'not_posted': const Toast("That discovery is not on today's board", icon: 'discover', kind: 'warn'),
      'no_energy': Toast('Not enough Energy (${r.info['need'] ?? 0} needed). Soothe to rest, or use an item', icon: 'energy', kind: 'warn'),
      'encounter_busy': const Toast('Finish or retreat from the current encounter first', icon: 'encounter', kind: 'warn'),
      'encounter_over': const Toast('This encounter is over', icon: 'encounter'),
      'companion_used': const Toast('Petalune already helped this time', icon: 'creature_petalune', kind: 'warn'),
      'no_companion': const Toast('No companion can help here', icon: 'encounter', kind: 'warn'),
    };
    _toasts.add(m[r.error] ?? const Toast('Something went wrong - please try again', icon: 'warning', kind: 'err'));
    audio.play('error_bonk', volume: 0.5);
  }

  /// "1,250" for a step count carried in an error's info (0 when missing).
  static String fmtSteps(Object? n) => story.fmtN(n is num ? n.round() : 0);

  /// "You still need 2 more Sunberries" for a refused hand-in (null when nothing is listed).
  static String? _missingText(Object? missing) {
    if (missing is! List || missing.isEmpty) return null;
    final parts = [for (final x in missing.whereType<story.ItemNeed>()) '${x.need - x.have} more ${h.itemLabel(x.id, x.need - x.have)}'];
    return parts.isEmpty ? null : 'You still need ${parts.join(' and ')}';
  }

  void _handle(g.GameEvent e) {
    final name = state.pet?.name ?? 'your Evochi';
    switch (e.type) {
      case 'xp':
        toast('+${e.data['amount']} XP for $name', icon: 'xp');
      case 'equipped':
        audio.buzz(Haptic.equip);
      case 'level_up':
        toast('Level ${e.data['level']}! $name is growing', icon: 'star');
        audio.play('level_up');
      case 'goal_met':
        toast('Daily goal reached! Bond +1', icon: 'heart');
        audio.buzz(Haptic.win);
      case 'evolution_ready':
        toast('Something is stirring... evolution is ready!', icon: 'evolve');
        analytics.track('evolution_unlocked', {'stage': e.data['stage']});
      case 'quest_ready':
        toast('Quest ready to claim: ${e.data['title']}', icon: 'chest');
      case 'claimed':
        final rewards = (e.data['rewards'] as List).cast<Map<String, Object?>>();
        final coins = rewards.where((r) => r['kind'] == 'coins').fold<int>(0, (a, r) => a + (r['amount'] as int));
        final items = rewards.where((r) => r['kind'] == 'item').map((r) => item(r['itemId'] as String).name).toList();
        toast('+$coins EvoCoins${items.isEmpty ? '' : ' + ${items.join(', ')}'}', icon: 'coin');
        audio.play('coin');
      case 'purchased':
        audio.play('purchase');
      case 'bond':
        toast('Bond +${e.data['amount']}', icon: 'heart');
      case 'recovered':
        toast('Your Evochi is feeling better!', icon: 'heart');
      case 'story_item':
        final id = e.data['itemId'] as String;
        final m = story.questMaterials[id]!;
        final have = state.story.questPouch[id] ?? 1;
        toast(
          id == 'q_dawn_dew_vial'
              ? 'Morning light collected! ${m.name} added to your Quest Pouch.'
              : (m.max > 1 ? '${m.name} $have/${m.max} added to your Quest Pouch' : '${m.name} added to your Quest Pouch'),
          icon: 'item:$id',
        );
        audio.play('reward_chime', volume: 0.7);
      case 'story_ready':
        final npc = e.data['npc'] as String?;
        if (npc == 'cottage') {
          toast('Bram has the roof up! Restore your Cottage on the Home Map', icon: 'home_map');
        } else if (e.data['kind'] == 'gather') {
          final title = story.storyQuests[e.data['questId']]?.title ?? 'Your quest';
          toast('$title: now gather what ${story.npcs[npc]?.name ?? 'they'} asked for', icon: 'skill_farming');
        } else if (npc == 'waystone') {
          toast('The Waystone is ready to wake', icon: 'star');
        } else if (npc != null && story.npcs.containsKey(npc)) {
          toast('${story.npcs[npc]!.name} is ready for you in Sunlit Village', icon: 'pin');
        }
      case 'harvested':
        audio.buzz(Haptic.harvest);
        final items = (e.data['items'] as Map).cast<String, int>();
        toast(items.entries.map((x) => '+${x.value} ${h.itemLabel(x.key, x.value)}').join(', '), icon: items.isEmpty ? 'skill_farming' : 'item:${items.keys.first}');
      case 'planted':
        final crop = h.cropDefs[e.data['crop']]!;
        toast('${crop.name} planted', icon: 'item:${crop.seed}');
      case 'watered':
        toast('Watered! +15% growth', icon: 'skill_farming');
      case 'tonic_used':
        toast('Sprout Tonic! +50% growth', icon: 'item:sprout_tonic');
      case 'skill_up':
        audio.play('level_up'); // the Skill-up card itself is shown by SkillUpListener
      case 'discovery_ready':
        toast('Discovery ready: inspect ${tr.trailPlaceNames[e.data['place']] ?? 'its place'}', icon: 'discover');
        audio.play('reward_chime', volume: 0.6);
      case 'discovery_begun':
        toast('Discovery begun: ${e.data['title']}. Your next steps count', icon: 'discover');
      case 'guild_rank':
        toast('Trail Guild rank up: ${e.data['name']}!', icon: 'trail_badge');
        audio.play('level_up');
      case 'companion_joined':
        final id = e.data['creature'] as String?;
        toast('${tr.creatureDefs[id]?.name ?? 'A new friend'} joined you as a companion!', icon: id == null ? 'encounter' : 'creature_$id');
      case 'encounter_retreat':
        toast('You slipped away. Items used are back in your Bag', icon: 'bag');
      case 'story_completed':
        analytics.track('story_quest_completed', {'quest': e.data['questId']});
      case 'sync_failed':
        toast('Sync failed - your last saved progress is safe', icon: 'warning', kind: 'err');
      default:
        break;
    }
  }

  // --------------------------------------------------------------- steps ----
  StepSource? get activeSource => switch (state.steps.connection) {
        'health' => health,
        'demo' => demo,
        _ => null,
      };

  /// Pulls observations since the last sync (with a 2-day overlap for late data) and merges them.
  Future<void> sync() async {
    final src = activeSource;
    if (src == null || syncing) return;
    syncing = true;
    notifyListeners();
    final to = now;
    final createdAt = state.pet?.createdAt ?? to;
    final from = [state.steps.lastSync ?? createdAt, createdAt].reduce((a, b) => a < b ? a : b) - 2 * dayMs;
    try {
      final samples = await src.readSamples(from < to - 30 * dayMs ? to - 30 * dayMs : from, to);
      run((s, n) => g.syncSteps(s, samples, n, source: src.id));
      analytics.track('step_sync_result', {'ok': true, 'bucket': samples.length > 50 ? 'large' : 'small'});
    } catch (_) {
      run((s, n) => g.syncSteps(s, const [], n, success: false));
      analytics.track('step_sync_result', {'ok': false});
    } finally {
      syncing = false;
      notifyListeners();
    }
  }

  Future<StepPermission> connectHealth() async {
    final p = await health.requestPermission();
    if (p == StepPermission.granted) {
      run((s, n) => g.setConnection(s, 'health', n));
      unawaited(sync());
    }
    return p;
  }

  Future<void> simulateWalk(int steps) async {
    // real step data keeps its own timestamps; see _demoNotBefore for the simulated walk
    demo.walk(steps, now, notBefore: _demoNotBefore(state));
    await sync();
  }

  /// A simulated walk "just happened": it never reaches back before a story quest was accepted,
  /// before the latest planting, or before a discovery was begun today, so a demo walk right after
  /// any of them always counts in full.
  static int _demoNotBefore(GameState s) {
    final active = s.story.activeQuestId;
    final since = active == null ? 0 : (s.story.questStates[active]?.acceptedAt ?? 0);
    final planted = s.home.plots.values.fold<int>(0, (a, p) => p != null && p.plantedAt > a ? p.plantedAt : a);
    final today = dayKey(DateTime.now().millisecondsSinceEpoch + s.clockOffset, g.zoneOf(s));
    var begun = 0;
    final day = s.trails.days[today];
    if (day != null) {
      for (final x in day.states.values) {
        if (x.foundAt == null && x.acceptedAt > begun) begun = x.acceptedAt;
      }
    }
    return [since, planted, begun].reduce((a, b) => a > b ? a : b);
  }

  void addManualSteps(int steps) {
    run((s, n) => g.syncSteps(s, manualEntry(steps, n), n, source: 'manual'));
  }

  // ------------------------------------------------------------ playtest ----
  /// Walk [ratio] x goal on each of [days] days, advancing the preview clock a day at a time.
  void advanceDays(int days, double ratio) {
    var s = state;
    for (var i = 0; i < days; i++) {
      final n = DateTime.now().millisecondsSinceEpoch + s.clockOffset;
      if (ratio > 0) {
        final goal = g.goalFor(s, dayKey(n, g.zoneOf(s)));
        final samples = demo.walk((goal * ratio).round(), n, watch: false, notBefore: _demoNotBefore(s));
        demo.readSamples(0, n + 1);
        s = g.syncSteps(s, samples, n, source: 'demo').state;
      }
      s = s.copy()..clockOffset += dayMs;
      s = g.syncSteps(s, const [], DateTime.now().millisecondsSinceEpoch + s.clockOffset, source: 'demo').state;
    }
    _commit(s);
  }

  void fastTrackEvolution() {
    var guard = 0;
    while (!(g.derive(state, now).pet?.evolution.eligible ?? true) && guard++ < 400) {
      advanceDays(1, 1.5);
    }
  }

  /// Move the preview clock forward without any steps (crops grow, cooldowns tick).
  void skipTime(int ms) {
    var s = state.copy()..clockOffset += ms;
    s = g.syncSteps(s, const [], DateTime.now().millisecondsSinceEpoch + s.clockOffset, source: 'demo').state;
    _commit(s);
  }

  /// Finish Chapter 1's first quest (with its reward) and reach level 2. False if already there.
  bool homeTalesReady() => run((s, n) => story.playtestHomeTalesReady(s, n)).events.isNotEmpty;

  /// A handful of every seed and harvest, into Bag > Pantry.
  void grantPantry() {
    const add = {
      'seed_sunberry': 3,
      'seed_meadow_carrot': 3,
      'seed_golden_wheat': 3,
      'seed_glowleaf': 2,
      'seed_moonshroom': 2,
      'sunberry': 6,
      'meadow_carrot': 4,
      'golden_wheat': 4,
      'glowleaf': 4,
      'moonshroom': 4,
    };
    final s = state.copy();
    add.forEach((id, n) => g.grantItem(s, id, n, 'playtest', now));
    _commit(s);
  }

  /// Every Cozy Skill up one level (maxed skills stay put).
  void skillsUp() {
    final s = state.copy();
    for (final k in h.skillOrder) {
      final xp = s.home.skills[k] ?? 0;
      final v = h.skillLevel(xp);
      if (!v.maxed) s.home.skills[k] = xp + v.need - v.into;
    }
    _commit(s);
  }

  /// Lumen Trails: Chapter 1's first quest done, level 3 and two discoveries found, so Pip has a
  /// Guild job. Returns how many discoveries it found (0: the Trails were already open).
  int trailsReady() {
    final r = run((s, n) => tr.playtestTrailsReady(s, n));
    return r.events.isEmpty ? 0 : ((r.events.first.data['found'] as int?) ?? 0);
  }

  /// Begin, walk and inspect up to [max] of today's discoveries. Returns how many were found.
  int finishDiscoveries(int max) {
    final (s, n) = tr.playtestFinishDiscoveries(state, now, max);
    if (n > 0) _commit(s);
    return n;
  }

  /// +3 Lumen Shards and a Lantern Tonic.
  void grantTrailItems() {
    final s = state.copy();
    g.grantItem(s, 'lumen_shard', 3, 'playtest', now);
    g.grantItem(s, 'lantern_tonic', 1, 'playtest', now);
    _commit(s);
  }

  void grantHerbs(int n) {
    final s = state.copy();
    final cur = s.inventory.putIfAbsent('healing_herb', () => Ownership());
    cur.quantity += n;
    cur.acquisitions.add(Acquisition(at: now, source: 'playtest', qty: n));
    _commit(s);
  }

  // ------------------------------------------------------------- settings ----
  void updateSettings(void Function(Settings s) change) {
    final s = state.copy();
    change(s.player!.settings);
    _commit(s);
  }

  void mutate(void Function(GameState s) change) {
    final s = state.copy();
    change(s);
    _commit(s);
  }

  Future<void> deleteAllData() async {
    await repo.wipe(state);
    state = GameState.fresh(DateTime.now().millisecondsSinceEpoch, state.tzHint);
    _view = null;
    notifyListeners();
  }

  Future<void> flush() => repo.flush(state);

  int get balance => view.balance;
  CatalogItem catalogItem(String id) => item(id);
  GameConfig get config => GameConfig.current;

  @override
  void dispose() {
    tabRequest.dispose();
    _events.close();
    _toasts.close();
    super.dispose();
  }
}
