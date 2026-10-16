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
import '../core/utils/day_keys.dart';
import '../data/health_adapters/demo_step_source.dart';
import '../data/health_adapters/health_step_source.dart';
import '../data/health_adapters/step_source.dart';
import '../data/repositories/game_repository.dart';
import '../game/engine.dart' as g;
import '../game/story/story.dart' as story;

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
  int _viewAt = 0;

  /// Cross-route navigation requests (pushed Village screens can't reach the tab shell directly).
  final tabRequest = ValueNotifier<String?>(null);
  String journeyTab = 'daily'; // daily | weekly | story
  String? bagCategoryRequest; // e.g. 'pouch'

  int get now => DateTime.now().millisecondsSinceEpoch + state.clockOffset;

  StepSource get health => _health ??= HealthStepSource();

  g.GameView get view {
    final n = now;
    if (_view == null || (n - _viewAt).abs() > 15000) {
      _view = g.derive(state, n);
      _story = null;
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

  /// Switch the main tab from anywhere (closes pushed screens first; see MainShell).
  void goTab(String tab, {String? journey, String? bag}) {
    if (journey != null) journeyTab = journey;
    if (bag != null) bagCategoryRequest = bag;
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
      'story_missing_items': const Toast('Something is missing from your Quest Pouch', icon: 'journey', kind: 'warn'),
    };
    _toasts.add(m[r.error] ?? const Toast('Something went wrong - please try again', icon: 'warning', kind: 'err'));
    audio.play('error_bonk', volume: 0.5);
  }

  void _handle(g.GameEvent e) {
    final name = state.pet?.name ?? 'your Evochi';
    switch (e.type) {
      case 'xp':
        toast('+${e.data['amount']} XP for $name', icon: 'xp');
      case 'level_up':
        toast('Level ${e.data['level']}! $name is growing', icon: 'star');
        audio.play('level_up');
      case 'goal_met':
        toast('Daily goal reached! Bond +1', icon: 'heart');
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
        if (npc == 'waystone') {
          toast('The Waystone is ready to wake', icon: 'star');
        } else if (npc != null) {
          toast('${story.npcs[npc]!.name} is ready for you in Sunlit Village', icon: 'pin');
        }
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
    // the simulated walk "just happened"; it never reaches back before a story quest was accepted,
    // so a demo walk right after accepting counts in full (real step data keeps its own timestamps)
    final active = state.story.activeQuestId;
    final since = active == null ? 0 : (state.story.questStates[active]?.acceptedAt ?? 0);
    demo.walk(steps, now, notBefore: since);
    await sync();
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
        final active = s.story.activeQuestId;
        final since = active == null ? 0 : (s.story.questStates[active]?.acceptedAt ?? 0);
        final samples = demo.walk((goal * ratio).round(), n, watch: false, notBefore: since);
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
