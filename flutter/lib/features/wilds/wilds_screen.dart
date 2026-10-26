// The Lumen Wilds: a floor you explore and fight on with your Evochi (F1, the Sunlit Thicket). Scene
// first: the map fills the screen, the five tabs are gone, and the HUD is what the Guild Raids design
// asks for: your party with Raid HP and Stamina (top left), the minimap (top right, tap for the floor),
// the objective, a satchel of what you have found and not yet brought home, and the action pad (bottom
// right): Pounce (tap again for a three-hit combo), Glow Bolt, Lumen Pulse, a dodge roll, a healing item
// from your Bag.
//
// Moving: drag anywhere (a joystick appears under your finger; push it far to run), tap a spot to walk
// there, or WASD / the arrow keys and Shift to run. Keys: J Pounce, K Bolt, L Pulse, Space dodge, Q heal,
// E talk / look, Esc pause. Tap a foe to keep your attacks on it.
//
// The fight is wilds_combat.dart (a Raid): this screen feeds it input, draws it (telegraphs on the
// ground, foes, shots, numbers), plays its sounds, and talks to the save: healing items leave the Bag as
// they are eaten, the satchel is banked once when you leave (the exit, a retreat, or the guardian
// calmed), the guardian's first clear is rewarded once and remembered. A knockout is an evacuation:
// Sher carries your Evochi back to the trailhead, half the satchel is lost, and its Vitality is never
// touched.

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../controllers/game_controller.dart';
import '../../core/models/catalog.dart';
import '../../core/services/haptics.dart';
import '../../game/economy/economy.dart' as econ;
import '../../game/engine.dart' as ge;
import '../../game/trails/trails.dart' as trails;
import '../../game/wilds/charms.dart' as charms;
import '../../game/wilds/story_floors.dart' as sf;
import '../../game/wilds/wilds.dart' as w;
import '../shared/action_button.dart';
import '../shared/ambience.dart';
import '../shared/kit.dart';
import '../shared/live_scene.dart' show SceneFx;
import '../shared/widgets.dart';
import '../trails/trails_widgets.dart';
import '../../game/hatch/hatch.dart' as hatch;
import '../../game/mining/mining.dart' as mine;
import '../village/mining.dart' show MiningArt, OreKindArt, oreTier, oreName, paintOre, contactBits, nuggets, stepBits, MineBit, OreNode, SatchelChip;
import '../village/story_widgets.dart';
import 'boss_intro.dart';
import 'deep_floor.dart';
import 'wilds_art.dart';
import 'wilds_combat.dart';

/// What you carry from one Deep Wilds floor down to the next: Raid HP, the satchel, and the creatures
/// calmed on the way (not yet counted toward the worn charm).
class DeepCarry {
  const DeepCarry(this.hp, this.coins, this.items, {this.calmed = 0});
  final double hp;
  final int coins;
  final Map<String, int> items;
  final int calmed;
}

/// What the Short recorder can reach on the Wilds screen that is up.
abstract class WildsDirectorHandle {
  Raid? get raid;
  WildsMap? get map;

  /// A playtesting shortcut (debug builds), as if the key were pressed.
  void key(LogicalKeyboardKey k);

  /// A line across the screen, as the game shows them.
  void banner(String text, [double secs]);

  /// How the screen is doing (the recorder's log).
  String get debugLine;
}

class WildsScreen extends StatefulWidget {
  const WildsScreen({super.key, this.mapId = 'thicket', this.depth, this.seed, this.carry, this.surge = false, this.story, this.forceStory = false, this.mine = false});
  final String mapId;

  /// A gallery of Flint's mine (deep_floor.dart, mine: true): ore to Pounce, no fights set up.
  final bool mine;

  /// A Deep Wilds floor (F2 and down), made fresh from [seed]; null for a hand-made map.
  final int? depth;
  final int? seed;
  final DeepCarry? carry;

  /// A Hollow Surge floor (rolled on the way down: game/wilds/wilds.dart wildsDescend).
  final bool surge;

  /// Recording a Short (flutter/tool/shorts): something else plays your Evochi. Called every frame before
  /// the fight steps, with the input it may set (steer, attack, bolt, pulse, dodge) and the screen's clock.
  static void Function(Raid r, RaidInput input, double t)? director;

  /// Recording a Short: the screen that is up (its fight, its map, its debug shortcuts).
  static WildsDirectorHandle? current;

  /// Recording a Short without a GPU: the living-scene shader is left off (it costs seconds a frame in
  /// software).
  static bool plainArt = false;

  /// Recording a Short: the camera's width as a share of the game's (below 1: closer in on the action).
  static double recordZoom = 1.0;

  /// While recording: leave out the "clearing is calm" banner (it sits over the action).
  static bool recordQuiet = false;

  /// A story floor: the Trail Guild job whose place this floor is (game/wilds/story_floors.dart).
  final String? story;

  /// Playtesting (debug builds): the story floor even though its job is not open.
  final bool forceStory;
  @override
  State<WildsScreen> createState() => _WildsScreenState();
}

class _WildsScreenState extends State<WildsScreen> with SingleTickerProviderStateMixin, WidgetsBindingObserver implements WildsDirectorHandle {
  @override
  Raid? get raid => _raid;
  @override
  WildsMap? get map => _map;
  @override
  void key(LogicalKeyboardKey k) {
    if (kDebugMode) _debugKey(k);
  }

  @override
  void banner(String text, [double secs = 2.6]) => _showBanner(text, secs);

  @override
  String get debugLine => 't=${_t.toStringAsFixed(2)} ticking=${_tk?.isActive} paused=$_paused card=$_card cine=$_cine sent=$_sentCine '
      'view=$_view pet=(${_raid?.pet.x.toStringAsFixed(1)}, ${_raid?.pet.z.toStringAsFixed(1)})';

  WildsMap? _map;
  Raid? _raid;
  WalkerArt? _petArt, _sherArt;
  // the guardian's entrance (loaded in the background; without it the fight starts as before)
  BossIntroArt? _introArt;
  CineEvochiArt? _cineEvochi;
  IntroCut? _cine; // playing now
  BossIntroArt? _sentArt; // the Forgotten Sentinel's entrance (its story floor only)
  IntroCut? _sentCine;
  final _foeArt = <String, FoeArt>{};
  // made when the floor has loaded (a screen left before then has none to stop)
  Ticker? _tk;
  Ticker get _ticker => _tk ??= createTicker(_tick);
  Duration _last = Duration.zero;
  double _t = 0; // seconds, for the fire, glints and effects
  final _focus = FocusNode();
  final _keys = <LogicalKeyboardKey>{};
  Offset? _stickOrigin, _stick;
  Offset? _target; // tap-to-move (world x, z)
  bool _targetRun = false;
  Size _view = Size.zero;
  double _u = 2.7; // screen px per world unit
  /// How much of the floor the screen shows across (world units): 180 exploring, wider in a fight so you
  /// and whatever is after you fit, widest for the guardian. It eases between them.
  double _zoomW = 180;
  /// The gate's seal is down (this floor's guardian is calmed), and how far its retraction has run (0..1).
  bool _sealOpen = false;
  double _sealT = 1;
  Offset _cam = Offset.zero; // top-left of the view, in screen px of the scaled ground
  String? _card; // a spot id, 'sher', 'map', 'retreat', 'knocked', 'victory', 'pause', 'spar'
  MapSpot? _near;
  bool _nearFriend = false; // close enough to Petalune to hum or offer a treat
  bool _nearSher = false, _nearBoss = false;
  String? _bubble;
  double _bubbleT = 0;
  int _line = 0;
  double _hintT = 7;
  String? _hint;
  double _hintT2 = 0;
  final _repaint = ValueNotifier<int>(0);
  final _purseKey = GlobalKey(); // the trip's purse in the HUD: where the coins fly to
  // the mines: the ore art, what this trip has mined (the satchel chip), the chips and nuggets in the air
  MiningArt? _miningArt;
  final _satchel = <String, int>{};
  final _satchelKey = GlobalKey();
  double _satchelBumpAt = -9;
  final _mineBits = <(OreRock, List<MineBit>)>[];
  final _nuggetsIn = <MineBit>{}; // nuggets that have reached the satchel chip
  static const _oreHits = {'copper': 3, 'iron': 4, 'lumen': 4, 'obsidian': 5};
  static const _wildsPerUnit = 11.7; // the mining art's world units (the village's), in the Wilds' units
  final _flyers = <_CoinFlyer>[]; // coins on their way up to it (screen space)
  double _purseBumpAt = -9;
  final _input = RaidInput();
  final _held = <String, double>{}; // a pad button held down -> time to its next repeat
  double _itemCd = 0;
  final _sfxAt = <String, double>{};
  String? _music;
  double _combatT = 0;
  bool _combatTipShown = false;
  String? _banner;
  double _bannerT = 0;
  bool _clearFirst = true;
  final String _runId = 'r${DateTime.now().millisecondsSinceEpoch}';
  int _banks = 0;
  int _calmBanked = 0; // calms already counted toward the worn charm
  double _shakeX = 0, _shakeY = 0;
  double _flashT = 0; // a Sunflare's flash over everything
  final _rng = math.Random();
  bool _snap = true; // the camera jumps (the start, after an evacuation)
  late final GameController _c;
  ui.FragmentProgram? _fxProgram; // the living-scene shader: leaves sway, grass shimmers, water ripples
  final _fx = <Object, ui.FragmentShader>{}; // one per tile / prop drawn (each draw keeps its uniforms)

  static const _floor = 'thicket';


  ui.FragmentShader? _fxFor(Object key) {
    final p = _fxProgram;
    if (p == null || WildsScreen.plainArt) return null;
    return _fx[key] ??= p.fragmentShader();
  }

  @override
  void initState() {
    super.initState();
    WildsScreen.current = this;
    WidgetsBinding.instance.addObserver(this);
    _c = context.read<GameController>();
    SceneFx.program().then((p) {
      if (mounted) _fxProgram = p;
    });
    final c = _c;
    final pet = c.state.pet;
    final key = 's0${(pet?.stage ?? 1).clamp(1, 3)}';
    final palette = pet?.paletteId ?? 'amber';
    final wearing = pet?.equipped.values.toList() ?? const <String>[];
    final depth = widget.depth;
    // a story floor only while its job is open (a stale link to it is an ordinary floor)
    final story = widget.story != null && (sf.storyFloorOpen(c.state, widget.story!) || (kDebugMode && widget.forceStory)) ? sf.storyFloors[widget.story!] : null;
    _story = story;
    final seed = widget.seed ?? DateTime.now().millisecondsSinceEpoch & 0x7fffffff;
    final friendly = story?.beat == 'trust' || sf.petaluneWithYou(c.state);
    final extra = [if (friendly) 'petalune', if (story?.beat == 'sprout') 'hollow_sprout', if (story?.beat == 'sentinel') 'sentinel'];
    Future.wait([
      depth == null
          ? WildsMap.load(widget.mapId)
          : makeFloor(depth, seed, story: story?.beat, place: story?.place, quest: story?.quest, mine: widget.mine, nest: _wantNest(c.state, depth, seed)),
      WalkerArt.load(key, palette, wearing: wearing),
      WalkerArt.load('sher', 'sher'),
      FoeArt.load('thornling'),
      FoeArt.load('sporecap'),
      FoeArt.load('briarback'),
      for (final k in extra) FoeArt.load(k),
      if (widget.mine) MiningArt.load(const ['copper', 'iron', 'lumen', 'obsidian']),
    ]).then((r) {
      if (!mounted) return;
      final m = r[0] as WildsMap;
      _petArt = r[1] as WalkerArt;
      _sherArt = r[2] as WalkerArt;
      _foeArt['thornling'] = r[3] as FoeArt;
      _foeArt['sporecap'] = r[4] as FoeArt;
      _foeArt['briarback'] = r[5] as FoeArt;
      for (var i = 0; i < extra.length; i++) {
        _foeArt[extra[i]] = r[6 + i] as FoeArt;
      }
      if (widget.mine) _miningArt = r[6 + extra.length] as MiningArt;
      setState(() {
        _map = m;
        _raid = _newRaid(m);
      });
      // Sher keeps the camp by the fire: he gives berries and a tip, and the trail is yours to walk
      _ticker.start();
      _loadIntro(m, pet?.stage ?? 1, palette, wearing);
    });
  }

  /// The entrances this map can play (the Briarback's in the Thicket, the Sentinel's at its gate), and
  /// your Evochi's heroic cut-out for them. Nothing for a floor without a guardian.
  Future<void> _loadIntro(WildsMap m, int stage, String palette, List<String> wearing) async {
    try {
      final sentinel = m.story?.beat == 'sentinel';
      if (m.boss == null && !sentinel) return;
      if (m.boss != null) _introArt = await BossIntroArt.load('briarback');
      if (sentinel) _sentArt = await BossIntroArt.load('sentinel', warm: const [0, 1, 2, 3, 4, 26, 27, 28]);
      _cineEvochi = await CineEvochiArt.load(stage, palette, wearing);
    } catch (e, st) {
      debugPrint('boss intro art: $e\n$st');
    }
  }

  /// The guardian's Raid HP for a party of one (the plan: Sher stays at the camp, the fight eases a little).
  static const _soloBoss = 0.85;

  /// An armed Hollow Ward is spent on this run: a three-hit shield.
  int _takeWard(GameController c) {
    final res = c.run((s, n) => econ.wildsTakeWard(s), quiet: true);
    final up = res.events.where((e) => e.type == 'ward_up').firstOrNull;
    if (up == null) return 0;
    c.toast('Hollow Ward up: the first three hits are turned away', icon: 'item:hollow_ward');
    return up.data['hits'] as int;
  }

  Raid _newRaid(WildsMap m) {
    final c = context.read<GameController>();
    final level = c.view.pet?.level.level ?? 1;
    final (sx, sz, sdir) = m.start;
    final pet = Actor(id: 'pet', kind: 'pet', team: Team.party, x: sx, z: sz, radius: _petArt!.radius, health: 120.0 + 10 * (level - 1))
      ..dir = sdir;
    final s = m.sher;
    final sher = s == null ? null : Actor(id: 'sher', kind: 'sher', team: Team.party, x: s.$1, z: s.$2, radius: 7, health: 150);
    final b = m.boss;
    final cleared = m.depth == null && w.floorCleared(c.state, _floor);
    _clearFirst = !cleared;
    _sealOpen = cleared || m.mine;
    _sealT = 1;
    final ar = b == null ? null : (b['arena'] as Map).cast<String, dynamic>();
    List<(double, double)> pts(Object? l) => [for (final p in (l as List? ?? const [])) (((p as List)[0] as num).toDouble(), (p[1] as num).toDouble())];
    final fire = m.fx.where((f) => f.$3 == 'fire').toList();
    final deep = m.depth == null ? null : floorFight(m.depth!, m.mods, surge: widget.surge);
    final raid = Raid(
      ground: RaidGround(wet: m.blocked, blocks: m.blocks, bounds: m.bounds),
      pet: pet,
      sher: sher,
      sherRoute: [for (final p in s?.$3 ?? const <Offset>[]) (p.dx, p.dy)],
      sherFire: fire.isEmpty ? null : (fire.first.$1, fire.first.$2),
      zones: [for (final z in m.zones) ZoneDef(z.$1, z.$2, z.$3, z.$4, z.$5)],
      spawns: [for (final f in m.foes) FoeSpawn(f.$1, f.$2, f.$3, f.$4, f.$5)],
      bossDef: b == null || ar == null
          ? null
          : BossDef(
              x: (b['x'] as num).toDouble(),
              z: (b['z'] as num).toDouble(),
              ax: (ar['x'] as num).toDouble(),
              az: (ar['z'] as num).toDouble(),
              ar: (ar['r'] as num).toDouble(),
              wall: pts(b['wall']),
              summon: pts(b['summon']),
            ),
      bossCleared: cleared,
      level: level,
      stage: c.state.pet?.stage ?? 1,
      charm: charms.wornCharm(c.state),
      palette: c.state.pet?.paletteId ?? 'amber',
      charmRank: math.max(1, charms.charmRank(c.state, charms.wornCharm(c.state) ?? '')),
      seed: DateTime.now().millisecondsSinceEpoch & 0xffff,
      // the economy: rare finds from calmed creatures, and an armed Hollow Ward
      lootRoll: (r) => econ.rollDrops('wilds_foe', r),
      lootLabel: (id, n) => id == econ.glimmer ? '+$n Glimmer!' : '+$n ${_lootName(id)}!',
      ward: _takeWard(c),
      bossScale: _soloBoss,
      // the Deep Wilds: the creatures grow tougher and hit harder the further down you go, and a floor's
      // twists and a Surge change them again
      foeHp: deep?.hp ?? 1.0,
      foeHarm: deep?.harm ?? 1.0,
      coinMul: deep?.coins ?? 1.0,
      surge: m.depth != null && widget.surge,
      storyBeat: m.story?.beat,
      storyX: m.story?.x ?? 0,
      storyZ: m.story?.z ?? 0,
      companion: m.story?.beat != 'trust' && sf.petaluneWithYou(c.state),
      // the mines: the ore in the floor, and what your gear can break
      ores: [for (final (id, kind, x, z) in m.ores) OreRock(id, kind, x, z, hits: _oreHits[kind] ?? 3, tier: oreTier[kind] ?? 1)],
      miningPower: mine.miningPowerOf(c.state),
      oreTier: mine.oreTierOf(c.state),
    );
    final carry = widget.carry;
    if (carry != null) {
      raid.pet.hp = carry.hp.clamp(1.0, raid.pet.maxHp);
      raid.coins = carry.coins;
      raid.items.addAll(carry.items);
      _calmBanked = -carry.calmed; // the floors above's calms still count toward the charm
    }
    if (m.depth != null) _arrive(m);
    return raid;
  }

  @override
  void dispose() {
    if (identical(WildsScreen.current, this)) WildsScreen.current = null;
    WidgetsBinding.instance.removeObserver(this);
    if (_music != null) _c.audio.setMusic(null);
    _tk?.dispose();
    _introArt?.dispose();
    _sentArt?.dispose();
    for (final sh in _fx.values) {
      sh.dispose();
    }
    _focus.dispose();
    _repaint.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // away from the app: the fight waits (a focused pause card)
    if ((state == AppLifecycleState.paused || state == AppLifecycleState.hidden) && _card == null && _raid != null) {
      setState(() => _card = 'pause');
    }
  }

  // ---- mapping: world (x, z) -> ground image px -> screen
  Offset _toGround(double x, double z) {
    final m = _map!;
    return m.origin + Offset(x * m.scale, z * m.sinP * m.scale);
  }

  double get _gk => _u / _map!.scale; // screen px per ground px
  double get _cosP => math.cos(_map!.pitch * math.pi / 180);

  Offset _toScreen(double x, double z) => _toGround(x, z) * _gk - _cam + Offset(_shakeX, _shakeY);

  Offset _toWorld(Offset screen) {
    final m = _map!;
    final p = (screen + _cam - Offset(_shakeX, _shakeY)) / _gk - m.origin;
    return Offset(p.dx / m.scale, p.dy / (m.sinP * m.scale));
  }

  bool get _paused => _card != null || _cine != null || _sentCine != null;

  // ---- the loop
  void _tick(Duration now) {
    final dt = _last == Duration.zero ? 0.0 : math.min(0.05, (now - _last).inMicroseconds / 1e6);
    _last = now;
    _t += dt;
    if (_sealOpen && _sealT < 1) _sealT = math.min(1.0, _sealT + dt / 1.8);
    if (_flashT > 0) _flashT = math.max(0, _flashT - dt);
    final m = _map, r = _raid;
    if (m == null || r == null || _view == Size.zero) return;
    stepBits([for (final (_, bits) in _mineBits) ...bits].toList(), _t, dt, (x, z) => 0);
    _mineBits.removeWhere((e) {
      final gone = e.$2.every((b) => _t - b.born > b.life + 1.2 && (b.kind != 'nugget' || _t >= b.flyAt + 0.7));
      if (gone) _nuggetsIn.removeAll(e.$2);
      return gone;
    });
    if (m.depth != null && !_sealOpen && r.calmed >= r.foeTotal && (r.foeTotal > 0 || m.story != null) && (m.story == null || r.storyDone)) {
      // the floor is calm: the way down opens
      _sealOpen = true;
      _sealT = 0;
      if (r.surge) {
        _surgeBreak();
      } else {
        _showBanner('The way down opens!', 2.6);
      }
      _sfx('level_up', 0.6);
    }
    final pet = r.pet;
    // input: keys, then the joystick, then a tap target
    var vx = 0.0, vz = 0.0;
    bool k(LogicalKeyboardKey a, LogicalKeyboardKey b) => _keys.contains(a) || _keys.contains(b);
    if (k(LogicalKeyboardKey.arrowLeft, LogicalKeyboardKey.keyA)) vx -= 1;
    if (k(LogicalKeyboardKey.arrowRight, LogicalKeyboardKey.keyD)) vx += 1;
    if (k(LogicalKeyboardKey.arrowUp, LogicalKeyboardKey.keyW)) vz -= 1;
    if (k(LogicalKeyboardKey.arrowDown, LogicalKeyboardKey.keyS)) vz += 1;
    var speed = 1.0;
    var run = k(LogicalKeyboardKey.shiftLeft, LogicalKeyboardKey.shiftRight);
    if (vx != 0 || vz != 0) {
      _target = null;
    } else if (_stickOrigin != null && _stick != null) {
      final d = _stick! - _stickOrigin!;
      if (d.distance > 8) {
        vx = d.dx;
        vz = d.dy / m.sinP; // the screen's up is foreshortened north
        speed = (d.distance / 40).clamp(0.4, 1.0);
        if (d.distance > 52) run = true; // pushed to the rim
      }
    } else if (_target != null) {
      vx = _target!.dx - pet.x;
      vz = _target!.dy - pet.z;
      run = run || _targetRun;
      if (math.sqrt(vx * vx + vz * vz) < 3) {
        _target = null;
        vx = vz = 0;
      }
    }
    // a held Pounce keeps swinging (the combo), J held too
    if (_keys.contains(LogicalKeyboardKey.keyJ)) _held.putIfAbsent('attack', () => 0.25);
    for (final e in _held.entries.toList()) {
      final left = e.value - dt;
      if (left <= 0) {
        _input.attack = true;
        _held[e.key] = 0.26;
      } else {
        _held[e.key] = left;
      }
    }
    if (!_keys.contains(LogicalKeyboardKey.keyJ) && _held.containsKey('attack') && !_padHeld) _held.remove('attack');
    _input
      ..mx = vx
      ..mz = vz
      ..speed = speed
      ..run = run;
    // the walk cycles' strides come from the art
    pet.cycle = _petArt!.gait(pet.running && pet.moving).cycle;
    final sher = r.sher;
    if (sher != null) sher.cycle = _sherArt!.gait(sher.running && sher.moving).cycle;
    _itemCd = math.max(0, _itemCd - dt);
    _brewCd = math.max(0, _brewCd - dt);
    if (_god) r.pet.hp = r.pet.maxHp;
    final dir = WildsScreen.director;
    if (dir != null && !_paused) dir(r, _input, _t);
    if (!_paused) r.tick(dt, _input);
    _events(r);
    // the music: the guardian's theme while it fights, the wild theme in a skirmish
    final boss = r.bossState == BossState.intro || r.bossState == BossState.fight;
    _combatT = r.inCombat ? 4 : math.max(0, _combatT - dt);
    final want = boss ? 'enc_boss_loop' : (_combatT > 0 ? 'enc_wild_loop' : null);
    if (want != _music && r.phase == RaidPhase.explore) {
      _music = want;
      _c.audio.setMusic(want, fade: 1.2);
    }
    if (_bubble != null) {
      _bubbleT -= dt;
      if (_bubbleT <= 0) _bubble = null;
    }
    if (_bannerT > 0) {
      _bannerT -= dt;
      if (_bannerT <= 0) setState(() => _banner = null);
    }
    if (_hintT2 > 0) {
      _hintT2 -= dt;
      if (_hintT2 <= 0) setState(() => _hint = null);
    }
    // what's near enough to interact with
    MapSpot? near;
    var best = double.infinity;
    for (final s in m.spots) {
      final d = pet.distTo(s.x, s.z);
      if (d < s.r + pet.radius && d < best) {
        best = d;
        near = s;
      }
    }
    final pl = r.petalune;
    final nearFriend = pl != null && r.storyBeat == 'trust' && !r.storyDone && pet.dist(pl) < 58;
    if (nearFriend != _nearFriend) setState(() => _nearFriend = nearFriend);
    final nearSher = sher != null && pet.dist(sher) < 52 && (!r.inCombat || !r.party);
    final b = r.boss;
    final nearBoss = b != null && r.bossState == BossState.calm && pet.dist(b) < 80;
    if (near?.id != _near?.id || nearSher != _nearSher || nearBoss != _nearBoss) {
      setState(() {
        _near = near;
        _nearSher = nearSher;
        _nearBoss = nearBoss;
      });
    }
    if (_hintT > 0) {
      final before = _hintT;
      _hintT -= dt;
      if ((before > 1) != (_hintT > 1) || _hintT <= 0) setState(() {});
    }
    // the camera follows your Evochi, kept inside the ground (in the guardian's fight it leans toward the
    // guardian, so both stay in view); it shakes on big hits
    var fx = pet.x, fz = pet.z;
    final bb = r.boss;
    final bossFight = bb != null && (r.bossState == BossState.intro || r.bossState == BossState.fight);
    // the Forgotten Sentinel: the camera turns to it as it wakes, then keeps it in view
    final sent = r.sentinel;
    final sentFight = sent != null && !sent.calm && sent.st != FoeState.dormant;
    // room to move: the view widens to fit the fight
    var wantW = 180.0;
    if (bossFight) {
      wantW = 265; // the arena is wide: room to see the guardian's sweeps and charges coming
    } else if (sentFight) {
      wantW = 250; // room to see its beam sweep and its runes coming
    } else if (r.inCombat) {
      var spread = 0.0;
      for (final f in r.hostile) {
        final d = f.dist(pet);
        if (d < 170) spread = math.max(spread, d);
      }
      wantW = (spread * 2 + 90).clamp(180.0, 230.0);
    }
    if (WildsScreen.director != null) wantW *= WildsScreen.recordZoom;
    _zoomW += (wantW - _zoomW) * math.min(1.0, dt * 1.6);
    if (_view.width > 0) {
      _u = math.max((_view.width / _zoomW).clamp(1.7, 3.6), _view.width / (m.groundW / m.scale));
    }
    if (bossFight) {
      fx += (bb.x - pet.x) * 0.35;
      fz += (bb.z - pet.z) * 0.35;
    } else if (sentFight) {
      final lean = sent.st == FoeState.roar ? 0.7 : 0.35;
      fx += (sent.x - pet.x) * lean;
      fz += (sent.z - pet.z) * lean;
    }
    final p = _toGround(fx, fz) * _gk;
    final gw = m.groundW * _gk, gh = m.groundH * _gk;
    // the arena sits near the floor's north edge: the camera may look a little past it (into the dark of
    // the wood) so the fight isn't pushed up under the HUD
    final over = bossFight ? 190.0 : 70.0;
    final want2 = Offset((p.dx - _view.width / 2).clamp(0.0, math.max(0.0, gw - _view.width)),
        (p.dy - _view.height * (bossFight ? 0.6 : 0.58)).clamp(-over, math.max(0.0, gh - _view.height)));
    _cam = _snap ? want2 : Offset.lerp(_cam, want2, math.min(1.0, dt * 6))!;
    _snap = false;
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final sh = reduce ? 0.0 : r.shake;
    _shakeX = (_rng.nextDouble() - 0.5) * 12 * sh;
    _shakeY = (_rng.nextDouble() - 0.5) * 9 * sh;
    // coins arriving at the purse: it bumps, a tick sounds
    for (final f in _flyers.toList()) {
      if (_t - f.t0 >= _CoinFlyer.flight) {
        _flyers.remove(f);
        _purseBumpAt = _t;
        _sfx('coin', 0.22, gap: 0.04);
      }
    }
    _repaint.value++;
  }

  /// A Pounce landed on ore: the sound and feel, the chips and dust, and at the break the nuggets that
  /// pop out and fly to the satchel chip, the ore itself banked at once (game/mining: once per break).
  void _oreHit(RaidEvent e) {
    final r = _raid, art = _miningArt;
    if (r == null || art == null) return;
    final o = r.ores.where((o) => (o.x - e.x).abs() < 0.01 && (o.z - e.z).abs() < 0.01).firstOrNull;
    if (o == null) return;
    final c = context.read<GameController>();
    final broke = e.type == 'ore_break';
    _sfx('mine_${o.kind}_${broke ? 'break' : e.type == 'ore_chip' ? 'chip' : 'crack'}', broke ? 0.8 : 0.6);
    c.audio.buzz(broke ? Haptic.thump : Haptic.hit, strength: broke ? 0.8 : 0.45);
    c.run((st, now) => mine.markFirstTrip(st, now), quiet: true);
    final toward = Offset(r.pet.x - o.x, r.pet.z - o.z);
    final tw = toward.distance > 0 ? toward / toward.distance : const Offset(0, 1);
    final node = OreNode(o.kind, 0, 0)..state = o.state;
    final rm = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final bits = contactBits(node, _t, tw, broke: broke, reduced: rm);
    if (broke) {
      final n = o.kind == 'copper' ? 3 : 2;
      bits.addAll(nuggets(node, _t, tw, n));
      final res = c.run((st, now) => mine.breakOre(st, o.kind, n, 'mine:${_map?.floor}:${o.id}:${DateTime.now().millisecondsSinceEpoch}', now), quiet: true);
      if (res.events.any((ev) => ev.type == 'ore_first')) {
        final name = oreName[o.kind] ?? o.kind;
        Future.delayed(const Duration(milliseconds: 900), () => c.toast('Your first $name! It is in your Bag, ready for Bram.', icon: 'gem'));
      }
      _satchel[o.kind] = (_satchel[o.kind] ?? 0) + n;
    }
    _mineBits.add((o, bits));
  }

  /// The satchel chip's middle, in the map's own coordinates (where the nuggets fly to).
  Offset? _satchelPoint() {
    final sb = _satchelKey.currentContext?.findRenderObject() as RenderBox?;
    final mb = context.findRenderObject() as RenderBox?;
    if (sb == null || mb == null || !sb.attached || !mb.attached) return null;
    return mb.globalToLocal(sb.localToGlobal(sb.size.center(Offset.zero)));
  }

  /// The purse's middle, in the map's own coordinates (where the coins fly to).
  Offset? _pursePoint() {
    final pb = _purseKey.currentContext?.findRenderObject() as RenderBox?;
    final mb = context.findRenderObject() as RenderBox?;
    if (pb == null || mb == null || !pb.attached || !mb.attached) return null;
    return mb.globalToLocal(pb.localToGlobal(pb.size.center(Offset.zero)));
  }

  /// What the purse shows: the trip's coins less the ones still on their way to it.
  int get _shownCoins {
    final r = _raid;
    if (r == null) return 0;
    var pending = 0;
    for (final p in r.pickups) {
      if (p.kind == 'coin' && p.t < 20) pending += p.amount;
    }
    for (final f in _flyers) {
      pending += f.amount;
    }
    return math.max(0, r.coins - pending);
  }

  bool _padHeld = false;
  String? _objText; // the objective line, and when it last changed (it shows, then fades)
  double _objAt = 0;

  void _sfx(String name, double vol, {double gap = 0.06}) {
    final last = _sfxAt[name] ?? -9;
    if (_t - last < gap) return;
    _sfxAt[name] = _t;
    _c.audio.play(name, volume: vol);
  }

  /// The entrance's sounds and rumbles.
  void _introCue(String cue) {
    final a = _c.audio;
    switch (cue) {
      case 'open':
        _sfx('enc_awaken', 0.8);
      case 'roar':
        _sfx('wild_roar', 0.95, gap: 0.3);
        a.buzz(Haptic.rumble);
      case 'blast':
        _sfx('enc_whoosh', 0.8);
        _sfx('enc_rumble', 0.6);
        a.buzz(Haptic.rumble, strength: 0.8);
      case 'dig':
        _sfx('wild_dodge', 0.5);
        a.buzz(Haptic.hit);
      case 'slam':
        _sfx('wild_crash', 0.95);
        _sfx('enc_rumble', 0.7);
        a.buzz(Haptic.thump);
      case 'whoosh':
        _sfx('enc_whoosh', 0.5);
      case 'ready':
        _sfx('enc_surge', 0.6);
        a.buzz(Haptic.perfect);
    }
  }

  /// The Sentinel's entrance's sounds and rumbles.
  void _sentCue(String cue) {
    final a = _c.audio;
    switch (cue) {
      case 'open':
        _sfx('enc_rumble', 0.4);
      case 'ignite':
        _sfx('enc_awaken', 0.85);
        a.buzz(Haptic.hit);
      case 'rise':
        _sfx('enc_rumble', 0.75);
        a.buzz(Haptic.rumble, strength: 0.6);
      case 'roar':
        _sfx('wild_roar', 0.85, gap: 0.3);
        _sfx('enc_rumble', 0.8);
        a.buzz(Haptic.rumble);
      case 'charge':
        _sfx('enc_glow', 0.8);
      case 'beam':
        _sfx('enc_surge', 0.9);
        a.buzz(Haptic.rumble, strength: 0.8);
      case 'leap':
        _sfx('wild_dodge', 0.7);
      case 'blast':
        _sfx('wild_crash', 0.9);
        a.buzz(Haptic.thump);
      case 'land':
        _sfx('wild_hit', 0.4);
        a.buzz(Haptic.hit);
      case 'title':
        _sfx('wild_crash', 0.95);
        _sfx('enc_rumble', 0.7);
        a.buzz(Haptic.thump);
    }
  }

  void _say(String text, [double secs = 2.8]) {
    _bubble = text;
    _bubbleT = secs;
  }

  /// A line across the screen for [secs]. A [hold] one (a Surge breaking) is not talked over by the small
  /// news that comes right after it (a clearing calm in the same moment).
  void _showBanner(String text, [double secs = 2.6, bool hold = false]) {
    if (!hold && _t < _bannerHold) return;
    if (hold) _bannerHold = _t + secs - 0.6;
    setState(() => _banner = text);
    _bannerT = secs;
  }

  double _bannerHold = -1;

  void _events(Raid r) {
    if (r.events.isEmpty) return;
    final c = context.read<GameController>();
    final a = c.audio;
    for (final e in r.events) {
      switch (e.type) {
        case 'swing':
          _sfx('wild_swing', e.value >= 2 ? 0.5 : 0.35);
        case 'hit':
          _sfx('wild_hit', 0.6, gap: 0.07);
          a.buzz(Haptic.hit, strength: 0.5);
        case 'hurt':
          _sfx('wild_hurt', 0.6, gap: 0.1);
          a.buzz(Haptic.hurt);
        case 'dodge':
          _sfx('wild_dodge', 0.45, gap: 0.1);
        case 'dodged':
          a.buzz(Haptic.tick);
        case 'tired':
          a.buzz(Haptic.error, strength: 0.4);
        case 'bolt':
          _sfx('wild_bolt', 0.4, gap: 0.1);
        case 'pulse':
          _sfx('enc_surge', 0.5);
          a.buzz(Haptic.surge, strength: 0.6);
        case 'alert':
          _sfx('pet_chirp', 0.22, gap: 0.6);
          if (!_combatTipShown) {
            _combatTipShown = true;
            setState(() => _hint = defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS
                ? 'Pounce, Bolt and Pulse on the right. Roll through attacks with Dodge.'
                : 'J Pounce (again for a combo) · K Bolt · L Pulse · Space dodge · Q heal');
            _hintT2 = 6;
          }
        case 'roll':
          _sfx('wild_roll', 0.45, gap: 0.2);
        case 'bonk':
          _sfx('wild_crash', 0.45);
          a.buzz(Haptic.thump, strength: 0.5);
        case 'spore_lob':
        case 'puff':
        case 'spore_land':
          _sfx('wild_spore', 0.4, gap: 0.15);
        case 'calm':
          _sfx('wild_calm', 0.55, gap: 0.3);
          a.buzz(Haptic.win, strength: 0.6);
        case 'zone':
          _sfx('reward_chime', 0.6);
          if (!(WildsScreen.director != null && WildsScreen.recordQuiet)) _showBanner('${e.text ?? 'The clearing'} is calm');
        case 'say':
          if (e.text != null) _say(e.text!);
        case 'pickup':
          _sfx('coin', 0.3, gap: 0.15);
        case 'sher_heal':
          _sfx('enc_soothe', 0.45);
        case 'boss_intro':
          // the entrance: in full the first time, a short slam and title after (a still card with
          // reduced motion); the old banner if its art has not loaded
          final seen = c.state.trails.seen['briarback_intro'] == true;
          final reduce = MediaQuery.of(context).disableAnimations;
          if (_introArt != null) {
            r.shake = 0;
            setState(() => _cine = reduce ? IntroCut.still : (seen ? IntroCut.short : IntroCut.full));
            if (!seen) c.run((s, n) => trails.markTrailSeen(s, 'briarback_intro'), quiet: true);
          } else {
            _sfx('enc_awaken', 0.8);
            a.buzz(Haptic.rumble);
            _showBanner('The Briarback wakes!', 2.4);
          }
        case 'roar':
          _sfx('wild_roar', 0.75, gap: 0.5);
          a.buzz(Haptic.rumble, strength: 0.7);
        case 'boss_phase':
          setState(() {});
        case 'sweep':
          _sfx('enc_whoosh', 0.6);
        case 'charge':
          _sfx('enc_rumble', 0.5);
        case 'crash':
          _sfx('wild_crash', 0.85);
          a.buzz(Haptic.thump);
        case 'paw':
          _sfx('enc_rumble', 0.35, gap: 0.15);
          a.buzz(Haptic.hit);
        case 'hoof':
          _sfx('enc_rumble', 0.22, gap: 0.12);
        case 'story_done':
          _storyDone();
        case 'sentinel_wake':
          // its entrance: in full the first time, the looming shot and the title after (a still card with
          // reduced motion); without its art, it simply wakes in the fight
          if (_sentArt != null) {
            final seen = c.state.trails.seen['sentinel_intro'] == true;
            final reduce = MediaQuery.of(context).disableAnimations;
            r.shake = 0;
            setState(() => _sentCine = reduce ? IntroCut.still : (seen ? IntroCut.short : IntroCut.full));
            if (!seen) c.run((s, n) => trails.markTrailSeen(s, 'sentinel_intro'), quiet: true);
          } else {
            _sfx('enc_awaken', 0.8);
            a.buzz(Haptic.rumble);
            _showBanner('Something huge stirs against the gate...', 2.0);
          }
        case 'sentinel_rise':
          _sfx('wild_crash', 0.8);
          _sfx('enc_rumble', 0.7);
          a.buzz(Haptic.thump);
          _showBanner('The Forgotten Sentinel wakes!', 2.4);
        case 'slam':
          _sfx('wild_crash', 0.7);
          a.buzz(Haptic.thump, strength: 0.8);
        case 'beam':
          _sfx('enc_surge', 0.7);
        case 'runes':
          _sfx('enc_rumble', 0.45, gap: 0.2);
        case 'shield_up':
          _sfx('enc_awaken', 0.6);
          _showBanner(
              e.value <= 1
                  ? 'It kneels behind a Hollow shield! Calm what it called, or break the shield with Lumen (a Lantern Tonic).'
                  : 'The shield again! Calm them, or light your Evochi with Lumen.',
              4.0);
        case 'shielded':
          _sfx('enc_glow', 0.35, gap: 0.25);
        case 'shield_hit':
          _sfx('wild_hit', 0.5, gap: 0.08);
        case 'shield_break':
          _sfx('wild_crash', 0.8);
          a.buzz(Haptic.thump);
          _showBanner('The shield shatters! It staggers: now!', 2.2);
        case 'hum':
          _sfx('enc_soothe', 0.6);
        case 'treat':
          _sfx('reward_chime', 0.5);
          a.buzz(Haptic.reward, strength: 0.5);
        case 'startle':
          _sfx('pet_chirp', 0.5, gap: 0.4);
          if (!_startleTold) {
            _startleTold = true;
            _showBanner('Petalune startles! Walk gently near it, and keep your attacks away.', 3.0);
          }
        case 'hush':
          _sfx('enc_soothe', 0.55);
          _showBanner('Petalune hums: Petal Hush!', 1.4);
        case 'lash':
          _sfx('enc_whoosh', 0.6, gap: 0.15);
          a.buzz(Haptic.hit, strength: 0.5);
        case 'thorns':
          _sfx('wild_crash', 0.45, gap: 0.15);
          a.buzz(Haptic.thump, strength: 0.5);
        case 'sig_ready':
          _sfx('reward_chime', 0.6);
          a.buzz(Haptic.reward);
          _showBanner('${r.sigName} is ready!', 1.6);
        case 'signature':
          _sfx(switch (e.text) { 'ocean' => 'enc_whoosh', 'coral' => 'enc_soothe', 'amber' => 'enc_surge', _ => 'wild_crash' }, 0.9);
          _sfx('enc_rumble', 0.6);
          a.buzz(Haptic.thump);
          if (e.text == 'amber' || e.text == null) _flashT = 0.35;
        case 'zap':
          _sfx('enc_surge', 0.35, gap: 0.12);
        case 'leap':
          _sfx('wild_crash', 0.5, gap: 0.1);
          a.buzz(Haptic.thump);
        case 'dazzled':
          _sfx('play_boing', 0.45, gap: 0.2);
          a.buzz(Haptic.hit);
        case 'close_call':
          _sfx('enc_soothe', 0.6);
          a.buzz(Haptic.perfect);
        case 'pillar_crack':
          _sfx('wild_crash', 0.5, gap: 0.1);
        case 'pillar_break':
          _sfx('wild_crash', 1.0, gap: 0.1);
          _sfx('enc_rumble', 0.8);
          a.buzz(Haptic.thump);
        case 'stomp':
          _sfx('enc_rumble', 0.6, gap: 0.2);
          a.buzz(Haptic.rumble, strength: 0.5);
        case 'roots':
          _sfx('wild_crash', 0.3, gap: 0.12);
        case 'stagger':
          _sfx('play_boing', 0.4, gap: 0.3);
        case 'sher_swipe':
          _sfx('wild_swing', 0.3, gap: 0.12);
        case 'victory':
          // the guardian calmed: the gate's seal draws back into its gems
          _sealOpen = true;
          _sealT = 0;
          _music = null;
          a.setMusic(null);
          _sfx('level_up', 0.8);
          a.buzz(Haptic.win);
          Future.delayed(const Duration(milliseconds: 2200), () {
            if (mounted && _card == null) setState(() => _card = 'victory');
          });
        case 'launch':
          _sfx('wild_crash', 0.35, gap: 0.1);
          a.buzz(Haptic.hit);
        case 'counter':
          _sfx('wild_crash', 0.5);
          a.buzz(Haptic.thump);
        case 'perfect_dodge':
          _sfx('enc_soothe', 0.6);
          a.buzz(Haptic.perfect);
        case 'loot_in':
          _sfx('coin', 0.18, gap: 0.05);
        case 'coin_bounce':
          _sfx('coin', 0.08, gap: 0.08);
        case 'coin_fly':
          _flyers.add(_CoinFlyer(_toScreen(e.x, e.z) - Offset(0, 6 * _cosP * _u), e.value.round(), _t));
        case 'signature_wind':
          _sfx('enc_soothe', 0.7);
          a.buzz(Haptic.rumble, strength: 0.4);
        case 'ore_hard':
          _sfx('mine_clink', 0.6);
          a.buzz(Haptic.error, strength: 0.4);
          _showBanner('Needs better gear: ${oreName[e.text] ?? e.text} is too hard', 1.8);
        case 'ore_chip' || 'ore_crack' || 'ore_break':
          _oreHit(e);
        case 'buff':
          _sfx('reward_chime', 0.5);
          a.buzz(Haptic.reward);
        case 'rare_drop':
          _sfx('reward_chime', 0.7);
          a.buzz(Haptic.reward);
        case 'warded':
          _sfx('enc_soothe', 0.5, gap: 0.2);
        case 'second_wind':
          a.buzz(Haptic.win);
        case 'knockout':
          _music = null;
          a.setMusic(null);
          a.buzz(Haptic.error);
          setState(() {
            _card = 'knocked';
            _target = null;
            _held.clear();
          });
      }
    }
    r.events.clear();
  }

  // ---- taps and actions
  void _tap(Offset pos) {
    final m = _map, r = _raid;
    if (m == null || r == null || _card != null) return;
    final sher = r.sher;
    if (sher != null && (!r.inCombat || !r.party)) {
      final s = _toScreen(sher.x, sher.z);
      final k = _u / walkerDrawScale;
      final a = _sherArt!;
      final rect = Rect.fromLTWH(s.dx - a.gx * k * 0.6, s.dy - a.gy * k * 0.9, a.fw * k * 0.6, a.gy * k * 0.95);
      if (rect.contains(pos)) {
        _talkToSher();
        return;
      }
    }
    // a foe under the finger: keep the attacks on it
    Foe? hit;
    var bd = 40.0;
    for (final f in r.hostile) {
      final a = _foeArt[f.kind];
      if (a == null) continue;
      final g = _toScreen(f.x, f.z) - Offset(0, a.top * _u / a.scale * 0.45);
      final d = (g - pos).distance;
      if (d < bd + f.radius * _u * 0.5) {
        bd = d;
        hit = f;
      }
    }
    if (hit != null) {
      _input.lock = hit;
      if (hit.dist(r.pet) > 60) {
        _target = Offset(hit.x, hit.z);
        _targetRun = true;
      }
      context.read<GameController>().audio.buzz(Haptic.tick);
      return;
    }
    final wpt = _toWorld(pos);
    _target = wpt;
    _targetRun = (wpt - Offset(r.pet.x, r.pet.z)).distance > 140;
  }

  void _talkToSher() {
    final r = _raid;
    if (r == null) return;
    context.read<GameController>().audio.play('pet_chirp', volume: 0.5);
    setState(() {
      _card = 'sher';
      _target = null;
    });
  }

  void _interact() {
    if (_card != null) return;
    if (_nearFriend) {
      context.read<GameController>().audio.play('ui_tap', volume: 0.4);
      setState(() {
        _card = 'petalune';
        _target = null;
      });
      return;
    }
    // a spot you are standing at comes first (the calm guardian likes to wander by the gate)
    if (_nearBoss && _near == null) {
      setState(() => _card = 'spar');
      return;
    }
    if (_nearSher && !(_raid?.party ?? false)) {
      _talkToSher();
      return;
    }
    final s = _near;
    if (s == null) {
      if (_nearSher) _talkToSher();
      return;
    }
    context.read<GameController>().audio.play('ui_tap', volume: 0.4);
    setState(() {
      _card = s.id;
      _target = null;
    });
  }

  void _press(String what) {
    if (_card != null || _raid == null) return;
    switch (what) {
      case 'attack':
        _input.attack = true;
      case 'bolt':
        _input.bolt = true;
      case 'pulse':
        _input.pulse = true;
      case 'dodge':
        _input.dodge = true;
      case 'item':
        _eat();
    }
  }

  void _eat() {
    final r = _raid;
    if (r == null || _itemCd > 0 || r.phase != RaidPhase.explore) return;
    final c = context.read<GameController>();
    final id = w.nextHealItem(c.state);
    if (id == null) {
      _showBanner('No healing items in your Bag', 1.8);
      c.audio.buzz(Haptic.error, strength: 0.4);
      return;
    }
    if (r.pet.hp >= r.pet.maxHp) {
      _showBanner('Raid HP is full', 1.4);
      return;
    }
    final res = c.run((s, n) => w.wildsUseHeal(s, id, n), quiet: true);
    if (res.ok) {
      r.useHeal(w.wildsHealAmount(id));
      _itemCd = 2.5;
      _sfx('enc_soothe', 0.45);
    }
  }

  // ---- brews: drunk in a fight for a buff
  bool _brewPick = false;
  double _brewCd = 0;

  void _brewTap(List<String> brews) {
    final c = context.read<GameController>();
    if (brews.isEmpty) {
      _showBanner('No brews: the Apothecary makes them', 2.2);
      c.audio.buzz(Haptic.error, strength: 0.4);
      return;
    }
    if (brews.length == 1) {
      _drink(brews.first);
    } else {
      setState(() => _brewPick = !_brewPick);
    }
  }

  void _drink(String id) {
    final r = _raid;
    setState(() => _brewPick = false);
    if (r == null || _brewCd > 0 || r.phase != RaidPhase.explore) return;
    final c = context.read<GameController>();
    final res = c.run((s, n) => w.wildsDrink(s, id, n), quiet: true);
    final ev = res.events.where((e) => e.type == 'wilds_drink').firstOrNull;
    if (ev == null) return;
    final buff = ev.data['buff'] as String;
    if (_story != null) _storySpent[id] = (_storySpent[id] ?? 0) + 1;
    final before = r.coating;
    r.applyBuff(buff);
    // one coating at a time: the new one washes the last off
    if (coatings.contains(buff) && before != null && before != buff) {
      _showBanner('${buffDefs[buff]?.name} coating: ${buffDefs[before]?.name} washed off', 2.0);
    }
    _brewCd = 1.5;
    c.analytics.track('wilds_brew', {'item': id});
  }

  /// The satchel into the save (once per bank: a retry adds nothing).
  bool _bank() {
    final r = _raid;
    final calmed = r == null ? 0 : r.calmed - _calmBanked;
    if (r == null || (r.coins <= 0 && r.items.isEmpty && calmed <= 0)) return false;
    final c = context.read<GameController>();
    final coins = r.coins;
    final items = Map<String, int>.of(r.items);
    final res = c.run((s, n) => w.wildsBank(s, '$_runId-$_banks', coins, items, n, calmed: calmed), quiet: true);
    if (!res.ok) return false;
    r.coins = 0;
    r.items.clear();
    _calmBanked = r.calmed;
    if (coins <= 0 && items.isEmpty) {
      _banks++;
      return true;
    }
    _banks++;
    final parts = ['+$coins EvoCoins', for (final e in items.entries) '+${e.value} ${_lootName(e.key)}'];
    c.toast('Satchel brought home: ${parts.join(', ')}', icon: 'coin');
    c.audio.play('coin', volume: 0.6);
    return true;
  }

  void _leave() {
    _bank();
    // a direct pop: the PopScope above only catches the back gesture (and asks first)
    Navigator.of(context).pop();
  }

  // ---- the Deep Wilds
  final _used = <String>{}; // spots spent on this floor: chests opened, shrines prayed at, camps rested at

  /// Down the steps to the next floor: a fresh floor, the run (Raid HP, satchel) carried along.
  void _descend(int depth) {
    final r = _raid;
    if (r == null) return;
    final c = context.read<GameController>();
    final seed = DateTime.now().microsecondsSinceEpoch & 0x7fffffff;
    final res = c.run((s, n) => w.wildsDescend(s, depth, seed, n), quiet: true);
    final surge = res.events.any((e) => e.type == 'hollow_surge');
    c.audio.play('enc_whoosh', volume: 0.6);
    c.analytics.track('wilds_descend', {'floor': depth, 'surge': surge});
    final carry = DeepCarry(r.pet.hp, r.coins, Map.of(r.items), calmed: r.calmed - _calmBanked);
    // a Trail Guild job's place waiting at this depth: the floor is the story's (and no Surge on it)
    final story = sf.storyFloorAt(c.state, depth);
    Navigator.of(context).pushReplacement(PageRouteBuilder<void>(
      transitionDuration: const Duration(milliseconds: 700),
      pageBuilder: (_, __, ___) => WildsScreen(depth: depth, seed: seed, carry: carry, surge: surge && story == null && !widget.mine, story: widget.mine ? null : story?.quest, mine: widget.mine),
      transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
    ));
  }

  // ---- story floors
  sf.StoryFloor? _story;
  final _storySpent = <String, int>{}; // the job's hand-in items used up on the floor (a brew drunk)
  bool _storyHandedIn = false, _startleTold = false;

  /// The beat is done: the job hands in (once), a moment to take it in, then the quest's reward.
  void _storyDone() {
    final st = _story;
    if (st == null || _storyHandedIn) return;
    _storyHandedIn = true;
    final c = context.read<GameController>();
    final res = c.run((s, n) => sf.wildsStoryDone(s, st.quest, n, spent: _storySpent));
    _sfx('level_up', 0.8);
    c.audio.buzz(Haptic.win);
    c.analytics.track('wilds_story_done', {'quest': st.quest});
    _showBanner(
        switch (st.beat) { 'trust' => 'Petalune trusts you!', 'sentinel' => 'The Forgotten Sentinel is restored!', _ => 'The Hollow Sprout is restored!' },
        3.0,
        true);
    if (!res.ok) return;
    Future.delayed(const Duration(milliseconds: 2400), () async {
      if (!mounted) return;
      setState(() => _card = 'story');
      await showStoryReward(context, st.quest, backToVillage: false);
      if (mounted) setState(() => _card = null);
    });
  }

  /// Hum to Petalune (from its card).
  void _hum() {
    setState(() => _card = null);
    if (!(_raid?.hum() ?? false)) _showBanner('Give it a moment', 1.2);
  }

  /// Offer Petalune a treat from the Bag.
  void _offer(String id) {
    final r = _raid;
    if (r == null) return;
    final c = context.read<GameController>();
    final res = c.run((s, n) => sf.wildsOffer(s, id, n));
    setState(() => _card = null);
    final ev = res.events.where((e) => e.type == 'wilds_treat').firstOrNull;
    if (ev == null) return;
    r.treat(ev.data['trust'] as int);
    c.analytics.track('wilds_treat', {'item': id});
  }

  /// A new floor: its name and twists on a banner; a Surge announces itself.
  void _arrive(WildsMap m) {
    final names = [for (final id in m.mods) floorModDefs[id]!.$1];
    Future.delayed(const Duration(milliseconds: 600), () {
      if (!mounted) return;
      final st = _story;
      if (st != null) {
        _showBanner(st.line, 4.4, true);
      } else if (widget.surge) {
        _showBanner('A Hollow Surge! This floor churns with the Hollow. Calm it to break the Surge.', 4.2, true);
        _sfx('enc_rumble', 0.7);
        context.read<GameController>().analytics.track('wilds_surge', {'floor': m.depth});
      } else if (names.isNotEmpty) {
        _showBanner('${m.floor}: ${names.join(' · ')}', 3.2);
      }
    });
  }

  /// The floor calmed on a Surge: the Hollow breaks, and a Lumen cache spills into the satchel.
  void _surgeBreak() {
    final r = _raid, m = _map;
    if (r == null || m == null) return;
    final depth = m.depth ?? 1;
    final rng = math.Random(widget.seed ?? depth);
    final coins = 60 + depth * 12 + rng.nextInt(20);
    final shards = 3 + depth ~/ 3;
    r.coins += coins;
    r.items['lumen_shard'] = (r.items['lumen_shard'] ?? 0) + shards;
    final found = <String>['$coins EvoCoins', '$shards Lumen Shards'];
    // two rolls at the guardian's rare finds (charms among them)
    for (var i = 0; i < 2; i++) {
      econ.rollDrops('wilds_boss', rng).forEach((id, n) {
        r.items[id] = (r.items[id] ?? 0) + n;
        found.add('$n ${_lootName(id)}');
      });
    }
    _flashT = 0.35;
    _showBanner('The Surge breaks! ${found.join(', ')}', 4.4, true);
    _sfx('reward_chime', 0.8);
  }

  /// A shrine's two blessings (decided by where it stands, so it offers the same two every time you look).
  (String, String) _blessingsFor(MapSpot s) {
    const all = ['regen', 'swift', 'moonlit', 'lantern', 'thornskin'];
    final i = (s.x.abs() * 7 + s.z.abs() * 13).round() % all.length;
    return (all[i], all[(i + 2) % all.length]);
  }

  void _bless(MapSpot s, String buff) {
    _used.add(s.id);
    _raid?.applyBuff(buff, secs: 120);
    _sfx('reward_chime', 0.6);
  }

  void _rest(MapSpot s) {
    final r = _raid;
    if (r == null) return;
    _used.add(s.id);
    r.pet.hp = r.pet.maxHp;
    _showBanner('Rested: Raid HP full', 2.0);
    _sfx('enc_soothe', 0.6);
  }

  /// Whether this floor has a nest hollow: always while you have never found an egg (from the first Deep
  /// floor, or the mine's third gallery), then on about a third of floors, by the seed.
  bool _wantNest(GameState st, int depth, int seed) {
    if (widget.mine && depth < 3) return false;
    if (st.hatch.eggs.isEmpty) return true;
    return (seed * 7 + depth * 13) % 10 < 3;
  }

  /// Which egg a floor's hollow holds, and the key that makes this hollow pay once.
  String _nestEgg() => (_map?.mine ?? false) ? 'stone_egg' : ((_map?.depth ?? 1) >= 5 ? 'stone_egg' : 'forest_egg');
  String _nestKey(MapSpot s) => '${_map?.id ?? 'deep'}:${_map?.depth ?? 0}:${widget.seed ?? 0}:${s.id}';

  void _takeEgg(MapSpot s) {
    final c = context.read<GameController>();
    final m = _map;
    if (m == null) return;
    final where = m.mine ? 'Found in the mine, gallery ${m.depth ?? 1}' : 'Found in the Deep Wilds, ${m.floor}';
    final r = c.run((st, n) => hatch.findEgg(st, _nestEgg(), where, _nestKey(s), n), quiet: true);
    if (!r.ok) {
      _showBanner('You have found an egg already today.', 2.2);
      return;
    }
    _used.add(s.id);
    final first = r.events.any((e) => e.type == 'egg_found' && e.data['first'] == true);
    final name = hatch.eggTemplates[_nestEgg()]?.name ?? 'An egg';
    _showBanner('$name! It is in your egg collection.', 3.0);
    _sfx('reward_chime', 0.7);
    c.audio.buzz(Haptic.reward);
    c.analytics.track('egg_obtained', {'source': m.mine ? 'mine' : 'deep', 'egg_family': _nestEgg()});
    if (first) {
      Future.delayed(const Duration(milliseconds: 2600), () {
        if (mounted) c.toast('Bring it home: the Hatching Nook is the little room by your cottage.', icon: 'star');
      });
    }
  }

  /// An old chest: coins and a find, more of both further down.
  void _openChest(MapSpot s) {
    final r = _raid;
    final m = _map;
    if (r == null || m == null) return;
    _used.add(s.id);
    final depth = m.depth ?? 1;
    final rng = math.Random(s.x.round() * 31 + s.z.round() + depth);
    final coins = 18 + depth * 8 + rng.nextInt(10);
    r.coins += coins;
    final found = <String>['$coins EvoCoins'];
    final shards = 1 + depth ~/ 3;
    r.items['lumen_shard'] = (r.items['lumen_shard'] ?? 0) + shards;
    found.add('$shards Lumen Shard${shards > 1 ? 's' : ''}');
    econ.rollDrops('wilds_foe', rng).forEach((id, n) {
      r.items[id] = (r.items[id] ?? 0) + n;
      found.add('$n ${_lootName(id)}');
    });
    _showBanner('Found: ${found.join(', ')}', 3.2);
    _sfx('reward_chime', 0.7);
    // the lid stays open
    _image('assets/art/economy/chest_wood_open.webp').then((img) {
      final a = m.propArt['chest'];
      if (a != null && mounted) setState(() => m.propArt['chest'] = PropArt(img, img.width / 2, img.height * 0.92, a.scale));
    });
  }

  Future<ui.Image> _image(String path) async {
    final data = await rootBundle.load(path);
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    return (await codec.getNextFrame()).image;
  }

  void _askLeave() {
    final r = _raid;
    if (r == null || (r.coins <= 0 && r.items.isEmpty && !r.inCombat && r.bossState != BossState.fight)) {
      _leave();
      return;
    }
    setState(() => _card = 'retreat');
  }

  @override
  Widget build(BuildContext context) {
    final m = _map;
    final rm = MediaQuery.of(context).disableAnimations;
    final mq = MediaQuery.of(context);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_card == null) {
          _askLeave();
        } else if (_card != 'knocked' && _card != 'victory') {
          setState(() => _card = null);
        }
      },
      child: Ambience(
        'forest',
        child: Scaffold(
          backgroundColor: const Color(0xFF2E4A24),
          body: LayoutBuilder(builder: (ctx, b) {
            _view = Size(b.maxWidth, b.maxHeight);
            _u = (b.maxWidth / _zoomW).clamp(1.7, 3.6);
            if (m != null) _u = math.max(_u, b.maxWidth / (m.groundW / m.scale));
            final card = _card;
            final narrow = b.maxWidth < 560;
            return Focus(
              focusNode: _focus,
              autofocus: true,
              onKeyEvent: (_, e) => _key(e),
              child: Stack(children: [
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapUp: (d) => _tap(d.localPosition),
                    onPanStart: (d) => setState(() {
                      _target = null;
                      _stickOrigin = d.localPosition;
                      _stick = d.localPosition;
                    }),
                    onPanUpdate: (d) => setState(() => _stick = d.localPosition),
                    onPanEnd: (_) => setState(() => _stickOrigin = _stick = null),
                    onPanCancel: () => setState(() => _stickOrigin = _stick = null),
                    child: m == null || _raid == null
                        ? const Center(child: CircularProgressIndicator())
                        : CustomPaint(painter: _MapPainter(this, rm, repaint: _repaint)),
                  ),
                ),
                if (_stickOrigin != null && _stick != null) _Stick(origin: _stickOrigin!, knob: _stick!),
                // a Sunflare's flash
                Positioned.fill(
                  child: IgnorePointer(
                    child: ValueListenableBuilder<int>(
                      valueListenable: _repaint,
                      builder: (_, __, ___) => _flashT <= 0 || rm
                          ? const SizedBox.shrink()
                          : ColoredBox(color: Color.fromRGBO(255, 246, 214, (_flashT / 0.35) * 0.75)),
                    ),
                  ),
                ),
                // a Surge: the Hollow's violet hangs at the edges of the floor until it breaks
                if (widget.surge && m != null && m.depth != null)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: ValueListenableBuilder<int>(
                        valueListenable: _repaint,
                        builder: (_, __, ___) {
                          final on = _sealOpen ? (1 - _sealT).clamp(0.0, 1.0) : 1.0;
                          if (on <= 0) return const SizedBox.shrink();
                          final pulse = rm ? 0.0 : 0.06 * math.sin(_t * 1.7);
                          return DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: RadialGradient(radius: 1.05, colors: [
                                const Color(0x00000000),
                                Color.fromRGBO(70, 24, 120, (0.30 + pulse) * on),
                                Color.fromRGBO(40, 10, 70, (0.55 + pulse) * on),
                              ], stops: const [0.45, 0.82, 1.0]),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                // a soft shade at the top so the HUD reads
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  height: mq.padding.top + 96,
                  child: const IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x660B120A), Color(0x000B120A)]),
                      ),
                    ),
                  ),
                ),
                if (m != null && _raid != null) ...[
                  _NearLabel(state: this),
                  // top left: back, then the party
                  Positioned(
                    left: 8 + mq.padding.left,
                    top: mq.padding.top + 8,
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Semantics(
                        button: true,
                        label: 'Leave the Wilds',
                        child: GestureDetector(
                          onTap: _askLeave,
                          child: Container(
                            width: 38,
                            height: 38,
                            decoration: _glass(0.45),
                            child: const Icon(Icons.arrow_back_rounded, size: 20, color: Color(0xFFFFF6E4)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _PartyPanel(state: this),
                    ]),
                  ),
                  Positioned(
                    right: 10 + mq.padding.right,
                    top: mq.padding.top + 8,
                    child: _MiniMap(state: this, onTap: () => setState(() => _card = 'map')),
                  ),
                  Positioned(
                    right: 10 + mq.padding.right,
                    top: mq.padding.top + 8 + 78 + 6,
                    child: _Purse(state: this),
                  ),
                  if (_miningArt != null)
                    Positioned(
                      right: 10 + mq.padding.right,
                      top: mq.padding.top + 8 + 78 + 6 + 32 + 6,
                      child: ValueListenableBuilder<int>(
                        valueListenable: _repaint,
                        builder: (_, __, ___) => _satchel.values.any((v) => v > 0)
                            ? SatchelChip(counts: _satchel, bumpAt: _satchelBumpAt, now: _t, art: _miningArt!, anchor: _satchelKey)
                            : SizedBox(key: _satchelKey, width: 40, height: 40),
                      ),
                    ),
                  Positioned(
                    left: narrow ? 12 : 200,
                    right: narrow ? 12 : 110,
                    top: mq.padding.top + (narrow ? 92 : 14),
                    child: IgnorePointer(child: Center(child: _TopCenter(state: this))),
                  ),
                  if (card == null)
                    Positioned(
                      right: 10 + mq.padding.right,
                      bottom: 12 + mq.padding.bottom,
                      child: _CombatPad(state: this),
                    ),
                  // the brew shelf, beside the pad's flask
                  if (card == null && _brewPick && w.ownedBrews(context.read<GameController>().state).length > 1)
                    Positioned(
                      right: 10 + mq.padding.right + 236 - 4,
                      bottom: 12 + mq.padding.bottom + 92,
                      child: _BrewShelf(brews: w.ownedBrews(context.read<GameController>().state), onPick: _drink),
                    ),
                  if (_hintT > 0 && card == null && _hint == null && WildsScreen.director == null)
                    _bottomHint(mq, _hintT > 1, 'Drag to walk · push far to run'),
                  if (_hint != null && card == null && WildsScreen.director == null) _bottomHint(mq, _hintT2 > 0.6, _hint!),
                  if (_banner != null && card == null)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: mq.padding.bottom + (narrow ? 230 : 120),
                      child: IgnorePointer(child: Center(child: _Banner(text: _banner!))),
                    ),
                ],
                if (card != null && m != null && _raid != null) _cardFor(card, m),
                if (_cine != null && _introArt != null)
                  Positioned.fill(
                    child: BossIntro(
                      art: _introArt!,
                      evochi: _cineEvochi,
                      cut: _cine!,
                      name: 'Briarback',
                      title: 'Guardian of the Thicket',
                      petName: _c.state.pet?.name ?? 'Your Evochi',
                      tint: cineTint(_c.state.pet?.paletteId ?? 'amber'),
                      onCue: _introCue,
                      onDone: () {
                        setState(() => _cine = null);
                        _raid?.skipIntro();
                        // let the pictures go, but keep a rematch's opening ready
                        _introArt?.want(const [22, 23, 24]);
                      },
                    ),
                  ),
                Positioned.fill(
                  child: IgnorePointer(
                    child: ValueListenableBuilder<int>(
                      valueListenable: _repaint,
                      builder: (_, __, ___) => CustomPaint(painter: _FlyerPainter(this)),
                    ),
                  ),
                ),
                if (_sentCine != null && _sentArt != null)
                  Positioned.fill(
                    child: SentinelIntro(
                      art: _sentArt!,
                      evochi: _cineEvochi,
                      cut: _sentCine!,
                      petName: _c.state.pet?.name ?? 'Your Evochi',
                      tint: cineTint(_c.state.pet?.paletteId ?? 'amber'),
                      onCue: _sentCue,
                      onDone: () {
                        setState(() => _sentCine = null);
                        _raid?.sentinelAwake();
                        _sentArt?.want(const [26, 27, 28]);
                      },
                    ),
                  ),
              ]),
            );
          }),
        ),
      ),
    );
  }

  Widget _bottomHint(MediaQueryData mq, bool on, String text) => Positioned(
        left: 16,
        right: 200,
        bottom: 20 + mq.padding.bottom,
        child: IgnorePointer(
          child: Align(
            alignment: Alignment.bottomLeft,
            child: AnimatedOpacity(
              opacity: on ? 1 : 0,
              duration: const Duration(milliseconds: 600),
              child: Text(text, style: _hudText(12.5)),
            ),
          ),
        ),
      );

  KeyEventResult _key(KeyEvent e) {
    final k = e.logicalKey;
    if (e is KeyDownEvent) {
      _keys.add(k);
      if (k == LogicalKeyboardKey.keyE || k == LogicalKeyboardKey.enter) _interact();
      if (k == LogicalKeyboardKey.escape) {
        setState(() => _card = _card == null ? 'pause' : (_card == 'knocked' || _card == 'victory' ? _card : null));
      }
      if (_card == null && kDebugMode) _debugKey(k);
      if (_card == null) {
        if (k == LogicalKeyboardKey.keyJ) _press('attack');
        if (k == LogicalKeyboardKey.keyK) _press('bolt');
        if (k == LogicalKeyboardKey.keyL) _press('pulse');
        if (k == LogicalKeyboardKey.keyU) _press('signature');
        if (k == LogicalKeyboardKey.space) _press('dodge');
        if (k == LogicalKeyboardKey.keyQ) _press('item');
      }
    }
    if (e is KeyUpEvent) _keys.remove(k);
    return KeyEventResult.handled;
  }

  /// Playtesting shortcuts (debug builds only): 1-3 the clearings, 4 the arena's edge, 5 the arena, G
  /// keeps your Evochi's Raid HP full, B takes a fifth of the guardian's health, I replays its entrance, N
  /// goes down to the next Deep Wilds floor, H opens a Surge floor, C calms every creature on the floor, P and O
  /// open the Mossy Ruins' story floors (Petalune, the Hollow Sprout) and Y the Sentinel's Gate, 9 goes to a
  /// story floor's beat.
  void _debugKey(LogicalKeyboardKey k) {
    final r = _raid, m = _map;
    if (r == null || m == null) return;
    (double, double)? to;
    final zs = m.zones;
    if (k == LogicalKeyboardKey.digit1 && zs.isNotEmpty) to = (zs[0].$3 + 10, zs[0].$4 + 60);
    if (k == LogicalKeyboardKey.digit2 && zs.length > 1) to = (zs[1].$3 + 10, zs[1].$4 + 60);
    if (k == LogicalKeyboardKey.digit3 && zs.length > 2) to = (zs[2].$3 + 10, zs[2].$4 + 60);
    // 9: a story floor's beat (a few steps south of it)
    final st = m.story;
    if (k == LogicalKeyboardKey.digit9 && st != null) to = (st.x, st.z + 62);
    // 4: at the arena's way in; 5: a few steps inside, where the guardian wakes
    final ar = (m.boss?['arena'] as Map?)?.cast<String, dynamic>();
    if (ar != null) {
      final ax = (ar['x'] as num).toDouble(), az = (ar['z'] as num).toDouble(), rr = (ar['r'] as num).toDouble();
      if (k == LogicalKeyboardKey.digit4) to = (ax - 12, az + rr + 16);
      if (k == LogicalKeyboardKey.digit5) to = (ax - 6, az + rr * 0.45);
    }
    if (k == LogicalKeyboardKey.keyB) r.debugHurtBoss(0.2);
    // N: straight down to the next Deep Wilds floor
    if (k == LogicalKeyboardKey.keyN) _descend((m.depth ?? 1) + 1);
    if (k == LogicalKeyboardKey.keyH) {
      // a Surge floor at least F5 deep, to look at
      final depth = math.max(5, m.depth ?? 5);
      Navigator.of(context).pushReplacement(MaterialPageRoute<void>(builder: (_) => WildsScreen(depth: depth, seed: 4242 + depth, surge: true)));
    }
    // calm every creature on the floor (to try the way down, and a Surge's break)
    if (k == LogicalKeyboardKey.keyC) r.calmAllForTesting();
    // the story floors, whatever the jobs say: P Petalune, O the Hollow Sprout, Y the Sentinel's Gate
    if (k == LogicalKeyboardKey.keyP || k == LogicalKeyboardKey.keyO || k == LogicalKeyboardKey.keyY) {
      final q = k == LogicalKeyboardKey.keyP ? 'eq01' : (k == LogicalKeyboardKey.keyO ? 'eq02' : 'eq03');
      final f = sf.storyFloors[q]!;
      Navigator.of(context).pushReplacement(MaterialPageRoute<void>(builder: (_) => WildsScreen(depth: f.depth, seed: 777, story: q, forceStory: true)));
    }
    // I: play the guardian's entrance again (the full cut)
    if (k == LogicalKeyboardKey.keyI && _introArt != null) setState(() => _cine = IntroCut.full);
    if (k == LogicalKeyboardKey.keyI && _sentArt != null) setState(() => _sentCine = IntroCut.full);
    // the gate's seal: up again (R), or drawn back as if the guardian had just been calmed (T)
    if (k == LogicalKeyboardKey.keyR) setState(() => _sealOpen = false);
    if (k == LogicalKeyboardKey.keyT) {
      setState(() {
        _sealOpen = true;
        _sealT = 0;
      });
    }
    if (k == LogicalKeyboardKey.keyG) {
      _god = !_god;
      _showBanner(_god ? 'Debug: Raid HP stays full' : 'Debug: off', 1.2);
    }
    if (to == null) return;
    r.pet
      ..x = to.$1
      ..z = to.$2;
    final s = r.sher;
    if (s != null && r.party) {
      s
        ..x = to.$1 + 12
        ..z = to.$2 + 10;
    }
    r.crumbs.clear();
    _snap = true;
  }

  bool _god = false;

  Widget _cardFor(String card, WildsMap m) {
    final mq = MediaQuery.of(context);
    final r = _raid!;
    final c = context.read<GameController>();
    void close() => setState(() => _card = null);
    if (card == 'map') {
      return Positioned.fill(child: _FullMap(state: this, onClose: close));
    }
    // the quest's reward is up (a dialog over the floor): the fight waits behind it
    if (card == 'story') return const Positioned(left: 0, top: 0, child: SizedBox.shrink());
    final Widget body;
    switch (card) {
      case 'petalune':
        final treats = sf.treatsFor(c.state);
        body = _PetaluneCard(
          trust: r.trust,
          humReady: r.humReady,
          treats: [for (final id in treats.take(3)) (id: id, name: catalog[id]?.name ?? id, have: ge.ownedQty(c.state, id), trust: sf.treatTrust(id))],
          onHum: _hum,
          onOffer: _offer,
          onClose: close,
        );
      case 'sher':
        // Sher keeps the camp: berries for the road (once) and a tip each time you stop by
        final gifted = c.state.flags['wilds_sher_gift'] == true;
        final tip = _sherTips[_line % _sherTips.length];
        body = _Offer(
          gifted: gifted,
          tip: tip,
          onThanks: () {
            _line++;
            if (!gifted) {
              c.audio.play('reward_chime', volume: 0.6);
              c.run((s, n) => w.wildsSherGift(s, n), quiet: true);
              c.toast('Sher gave you 3 Berry Snacks', icon: 'item:berry_snack');
            }
            setState(() => _card = null);
          },
        );
      case 'retreat':
        body = _InfoCard(
          title: 'Retreat to the village?',
          text: r.coins > 0 || r.items.isNotEmpty
              ? 'Your satchel comes home with you: ${_satchelText(r.coins, r.items)}.'
              : 'Nothing in the satchel yet. The creatures here will be waiting next time.',
          note: r.bossState == BossState.fight ? 'The Briarback will be back at full strength.' : null,
          primary: 'Retreat',
          primaryTone: ButtonTone.gold,
          secondary: 'Stay',
          onPrimary: _leave,
          onSecondary: close,
        );
      case 'pause':
        body = _InfoCard(
          title: 'Paused',
          text: 'The Thicket waits for you.',
          primary: 'Resume',
          secondary: 'Leave',
          onPrimary: close,
          onSecondary: () => setState(() => _card = 'retreat'),
        );
      case 'knocked':
        final pet = c.state.pet;
        body = _InfoCard(
          title: '${pet?.name ?? 'Your Evochi'} was knocked out',
          text: r.party
              ? 'Sher carried ${pet?.name ?? 'your Evochi'} back to the trailhead. Raid HP is back to full; its Vitality is untouched.'
              : '${pet?.name ?? 'Your Evochi'} scrambled back to the trailhead. Raid HP is back to full; its Vitality is untouched.',
          note: _lostText(r),
          // a Heartbloom: get back up where you fell, satchel and all
          secondary: ge.ownedQty(c.state, 'heartbloom') > 0 ? 'Heartbloom (${ge.ownedQty(c.state, 'heartbloom')})' : null,
          onSecondary: () {
            if (!c.run((s, n) => econ.wildsSecondWind(s, n)).ok) return;
            r.secondWind();
            c.audio.play('level_up', volume: 0.7);
            setState(() => _card = null);
          },
          primary: 'Back on my feet',
          primaryTone: ButtonTone.green,
          onPrimary: () {
            r.evacuate();
            setState(() {
              _card = null;
              _snap = true;
            });
            if (r.party) _say('Easy now. We\'ll get it next time.', 3);
          },
        );
      case 'victory':
        final reward = w.clearReward(_clearFirst);
        body = _VictoryCard(
          first: _clearFirst,
          coins: reward.coins,
          items: reward.items,
          satchelCoins: r.coins,
          satchelItems: Map.of(r.items),
          onCollect: () {
            final res = c.run((s, n) => w.wildsClear(s, _floor, n), quiet: true);
            final got = res.events.any((e) => e.type == 'wilds_cleared');
            _bank();
            if (got) {
              c.audio.play('reward_chime', volume: 0.7);
              c.toast(_clearFirst ? 'The Sunlit Thicket is calm! +${reward.coins} EvoCoins + Briar Heartwood' : 'A good spar! +${reward.coins} EvoCoins + Briar Heartwood',
                  icon: 'item:briar_heartwood');
              // the guardian's rare roll and the first-clear Glimmer (the economy)
              final ev = res.events.firstWhere((e) => e.type == 'wilds_cleared');
              final extra = [
                for (final x in (ev.data['rewards'] as List).cast<Map<String, Object?>>())
                  if (x['kind'] == 'glimmer') '+${x['amount']} Glimmer' else if (x['kind'] == 'item' && econ.activeRares.contains(x['itemId'])) '+1 ${_lootName(x['itemId'] as String)}',
              ];
              if (extra.isNotEmpty) c.toast('The guardian left a gift: ${extra.join(', ')}', icon: 'glimmer');
            } else if (!_clearFirst) {
              c.toast('Sparring rewards come once a day', icon: 'coin', kind: 'warn');
            }
            setState(() {
              _clearFirst = false;
              _card = null;
            });
            if (r.party) _say('The gate\'s light is steadier already. Fernwood next, when you\'re ready.', 4);
          },
        );
      case 'spar':
        body = _InfoCard(
          title: 'The Briarback',
          text: 'Its antlers are in bloom now, the Hollow long gone. It lowers its head and paws the moss: a friendly challenge.',
          note: 'Sparring rewards: once a day.',
          primary: 'Spar',
          primaryTone: ButtonTone.green,
          secondary: 'Not now',
          onPrimary: () {
            r.rematch();
            setState(() => _card = null);
          },
          onSecondary: close,
        );
      default:
        final s = m.spots.firstWhere((x) => x.id == card);
        final lvl = c.view.pet?.level.level ?? 1;
        final locked = s.need != null && lvl < s.need!;
        final calm = r.bossState == BossState.calm;
        final deep = m.depth;
        final used = _used.contains(s.id);
        if (s.kind == 'gate' && (deep != null || (calm && !locked))) {
          // the way down: the Thicket's gate once its guardian is calm, a deep floor's once the floor is
          final open = deep == null || _sealOpen;
          final next = (deep ?? 1) + 1;
          body = _SpotCard(
            spot: s,
            note: open
                ? 'Steps lead down into F$next. Your satchel and your Raid HP come with you.'
                : 'The seal holds while the Hollow stirs on this floor: ${r.foeTotal - r.calmed} still to calm.',
            primary: open ? 'Descend' : 'OK',
            secondary: open ? 'Not yet' : null,
            onPrimary: open ? () => _descend(next) : close,
            onSecondary: close,
          );
          break;
        }
        if (s.kind == 'nest') {
          // a nest hollow: an egg left behind (the Hatching Nook's; one a day, this hollow once)
          final taken = used || c.state.hatch.eggs.any((e) => e.id == 'egg:${_nestKey(s)}');
          final full = !taken && hatch.findEgg(c.state, _nestEgg(), '', _nestKey(s), c.now).error == 'found_today';
          body = _SpotCard(
            spot: s,
            note: taken
                ? 'The hollow is empty now; the egg is yours.'
                : full
                    ? 'You have found an egg already today. Leave this one be; it will keep.'
                    : 'Warm, under the down. Take it home to the Hatching Nook and your walking will hatch it.',
            primary: taken || full ? 'OK' : 'Take the egg',
            secondary: taken || full ? null : 'Leave it',
            onPrimary: () {
              if (!taken && !full) _takeEgg(s);
              close();
            },
            onSecondary: close,
          );
          break;
        }
        if (s.kind == 'chest' || s.kind == 'shrine' || s.kind == 'camp') {
          final blessings = _blessingsFor(s);
          body = _SpotCard(
            spot: s,
            note: used
                ? 'Nothing more here.'
                : switch (s.kind) {
                    'shrine' => 'Choose a blessing: it lasts two minutes.',
                    'camp' => r.pet.hp >= r.pet.maxHp ? 'Your Evochi is fresh already.' : null,
                    _ => null,
                  },
            primary: used ? 'OK' : switch (s.kind) { 'chest' => 'Open', 'shrine' => buffDefs[blessings.$1]!.name, _ => 'Rest' },
            secondary: used ? null : (s.kind == 'shrine' ? buffDefs[blessings.$2]!.name : 'Leave it'),
            onPrimary: () {
              if (!used) {
                switch (s.kind) {
                  case 'chest':
                    _openChest(s);
                  case 'shrine':
                    _bless(s, blessings.$1);
                  default:
                    _rest(s);
                }
              }
              close();
            },
            onSecondary: () {
              if (!used && s.kind == 'shrine') _bless(s, blessings.$2);
              close();
            },
          );
          break;
        }
        body = _SpotCard(
          spot: s,
          note: s.kind == 'gate'
              ? (!calm
                  ? 'Something old and tangled guards this gate. While it does, the seal holds.'
                  : (locked
                      ? 'The seal is down. The path beyond is steep: your Evochi is Lv. $lvl and needs Lv. ${s.need}.'
                      : 'The seal is down. Fernwood Trail is still overgrown past the doorway. Soon.'))
              : (s.kind == 'exit' && (r.coins > 0 || r.items.isNotEmpty) ? 'Your satchel comes home: ${_satchelText(r.coins, r.items)}.' : null),
          primary: s.kind == 'exit' ? 'Leave' : 'OK',
          secondary: s.kind == 'exit' ? 'Stay' : null,
          onPrimary: () {
            if (s.kind == 'exit') {
              _leave();
            } else {
              close();
            }
          },
          onSecondary: close,
        );
    }
    final dim = card == 'knocked' || card == 'victory' || card == 'pause' || card == 'retreat';
    return Positioned.fill(
      child: Container(
        color: dim ? const Color(0x99141A10) : Colors.transparent,
        alignment: Alignment.bottomCenter,
        padding: EdgeInsets.fromLTRB(12, 12, 12, 12 + mq.padding.bottom),
        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 480), child: body),
      ),
    );
  }

  String? _lostText(Raid r) {
    final lostC = (r.coins / 2).ceil();
    final lostI = [for (final e in r.items.entries) if ((e.value / 2).ceil() > 0) '${(e.value / 2).ceil()} ${_lootName(e.key)}'];
    if (lostC == 0 && lostI.isEmpty) return null;
    return 'Dropped on the way: ${[if (lostC > 0) '$lostC EvoCoins', ...lostI].join(', ')} (half the satchel).';
  }

  String _satchelText(int coins, Map<String, int> items) =>
      [if (coins > 0) '$coins EvoCoins', for (final e in items.entries) '${e.value} ${_lootName(e.key)}'].join(', ');
}

// ====================================================================== the map
class _MapPainter extends CustomPainter {
  _MapPainter(this.s, this.rm, {required Listenable repaint}) : super(repaint: repaint);
  final _WildsScreenState s;
  final bool rm;

  @override
  void paint(Canvas canvas, Size size) {
    final m = s._map, r = s._raid;
    if (m == null || r == null) return;
    final pet = r.pet;
    final sher = r.sher;
    final gk = s._gk;
    final pq = Paint()..filterQuality = FilterQuality.medium;
    final view = Offset.zero & size;
    // the ground, in tiles (only those on screen)
    canvas.save();
    canvas.translate(-s._cam.dx + s._shakeX, -s._cam.dy + s._shakeY);
    canvas.scale(gk);
    final vis = Rect.fromLTWH((s._cam.dx - s._shakeX) / gk, (s._cam.dy - s._shakeY) / gk, size.width / gk, size.height / gk).inflate(8);
    final ft = s._t % 600.0;
    for (var i = 0; i < m.tiles.length; i++) {
      final t = m.tiles[i];
      if (!t.rect.overlaps(vis)) continue;
      final sh = rm || t.mask == null ? null : s._fxFor(t);
      if (sh == null) {
        canvas.drawImageRect(t.img, Rect.fromLTWH(0, 0, t.img.width.toDouble(), t.img.height.toDouble()), t.rect, pq);
        continue;
      }
      sh
        ..setFloat(0, t.rect.left)
        ..setFloat(1, t.rect.top)
        ..setFloat(2, t.rect.width)
        ..setFloat(3, t.rect.height)
        ..setFloat(4, t.img.width.toDouble())
        ..setFloat(5, t.img.height.toDouble())
        ..setFloat(6, ft)
        ..setFloat(7, 1)
        ..setFloat(8, t.rect.left)
        ..setFloat(9, t.rect.top)
        ..setImageSampler(0, t.img)
        ..setImageSampler(1, t.mask!);
      canvas.drawRect(t.rect, Paint()..shader = sh);
    }
    // the canopy's shade on a made floor (the Thicket's is in its render)
    if (m.shade.isNotEmpty) {
      final sp = Paint();
      for (final (x, z, r) in m.shade) {
        final c = s._toGround(x, z);
        if (!vis.inflate(r * m.scale).contains(c)) continue;
        final rx = r * m.scale, rz = rx * m.sinP;
        sp.shader = ui.Gradient.radial(c, rx, const [Color(0x55081008), Color(0x00081008)]);
        canvas.drawOval(Rect.fromCenter(center: c, width: rx * 2, height: rz * 2.4), sp);
      }
    }
    canvas.restore();
    // past the floor's north edge: the deep wood, the seam softened
    final seam = -s._cam.dy + s._shakeY;
    if (seam > 0) {
      canvas.drawRect(Rect.fromLTWH(0, 0, size.width, seam), Paint()..color = const Color(0xFF1F3318));
      canvas.drawRect(
          Rect.fromLTWH(0, seam - 30, size.width, 90),
          Paint()
            ..shader = ui.Gradient.linear(Offset(0, seam - 30), Offset(0, seam + 60), const [Color(0xFF1F3318), Color(0x001F3318)]));
    }
    // on the ground: spore clouds, the guardian's rings, telegraphs, effects that lie flat
    for (final h in r.hazards) {
      _cloud(canvas, h);
    }
    for (final mk in r.marks) {
      if (!mk.done) _mark(canvas, mk);
    }
    for (final wv in r.waves) {
      _wave(canvas, wv);
    }
    for (final b in r.bursts) {
      if (const {'pulse', 'spores', 'sweep', 'dust', 'scar', 'reef', 'snare'}.contains(b.kind)) _burst(canvas, b);
    }
    // the target ring
    final lock = r.lock;
    if (lock != null && lock.alive && !lock.calm) _ring(canvas, lock, const Color(0xFFFFD25A));
    // soft shadows under everyone (the props' shadows are in the ground)
    final shadow = Paint()
      ..color = const Color(0x40000000)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    final actors = <Actor>[pet, if (sher != null) sher, ...r.friends, ...r.allFoes];
    for (final a in actors) {
      if (a.alpha <= 0.02) continue;
      final g = s._toScreen(a.x, a.z);
      if (!view.inflate(80).contains(g)) continue;
      shadow.color = Color.fromRGBO(0, 0, 0, 0.25 * a.alpha);
      canvas.drawOval(Rect.fromCenter(center: g, width: a.radius * 2.4 * s._u, height: a.radius * 1.1 * s._u), shadow);
    }
    for (final sh in r.shots) {
      if (sh.lob) {
        final g = s._toScreen(sh.x, sh.z);
        canvas.drawOval(Rect.fromCenter(center: g, width: 7 * s._u, height: 3 * s._u), shadow..color = const Color(0x33000000));
      }
    }
    // a counter is ready (after a perfect dodge): a gold ring under your Evochi
    if (r.counterT > 0) {
      final t = rm ? 0.5 : (math.sin(s._t * 14) + 1) / 2;
      canvas.drawOval(
          _ellipse(pet.x, pet.z, 15 + 2 * t),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3
            ..color = Color.fromRGBO(255, 205, 90, 0.55 + 0.4 * t));
    }
    for (final p in r.pickups) {
      _pickup(canvas, p);
    }
    // everything standing, back to front; a tall prop in front of someone turns see-through
    final wk = s._u / walkerDrawScale;
    final hidden = [
      for (final a in [pet, if (sher != null) sher])
        (a.z, Rect.fromCenter(center: s._toScreen(a.x, a.z) - Offset(0, s._petArt!.gy * wk * 0.45), width: s._petArt!.fw * wk * 0.5, height: s._petArt!.gy * wk * 0.8)),
      if (r.boss != null && r.bossState != BossState.absent)
        (r.boss!.z, Rect.fromCenter(center: s._toScreen(r.boss!.x, r.boss!.z) - Offset(0, 22 * s._u), width: 40 * s._u, height: 44 * s._u)),
    ];
    final items = <(double, void Function())>[];
    for (final p in m.props) {
      final a = m.propArt[p.kind];
      if (a == null) continue;
      final g = s._toScreen(p.x, p.z);
      final k = s._u / a.scale * p.s;
      final rect = Rect.fromLTWH(g.dx - a.ax * k, g.dy - a.ay * k, a.img.width * k, a.img.height * k);
      if (!rect.overlaps(view)) continue;
      final tall = p.kind.startsWith('oak') || p.kind.startsWith('pine') || p.kind.startsWith('birch') || p.kind == 'gate' || p.kind == 'tent' || p.kind.startsWith('pillar');
      final see = tall && hidden.any((h) => p.z > h.$1 && rect.deflate(rect.width * 0.12).overlaps(h.$2));
      final sh = rm || a.mask == null ? null : s._fxFor(p);
      final stone = p.kind.startsWith('pillar') || p.kind == 'boulder';
      final dmg = stone ? r.crackAt(p.x, p.z) : 0;
      if (dmg < 0) {
        items.add((p.z, () => _rubble(canvas, g, k * a.img.width * 0.5, p.x)));
        continue;
      }
      items.add((p.z, () => _prop(canvas, p.flip, a, g, k, see ? _see : pq, sh, s._toGround(p.x, p.z))));
      if (dmg > 0) items.add((p.z + 0.05, () => _cracks(canvas, rect, dmg, p.x)));
      if (p.kind == 'gate') items.add((p.z + 0.5, () => _seal(canvas)));
    }
    // the brambles that close the arena
    final bramble = m.propArt['bramble'];
    final def = r.bossDef;
    if (bramble != null && def != null && r.wallRise > 0) {
      for (var i = 0; i < def.wall.length; i++) {
        final (x, z) = def.wall[i];
        final g = s._toScreen(x, z);
        final k = s._u / bramble.scale;
        final rise = (r.wallRise * 1.3 - i * 0.07).clamp(0.0, 1.0);
        final flip = i.isOdd;
        items.add((z, () => _rising(canvas, bramble, g, k, rise, flip)));
      }
    }
    for (final a in actors) {
      if (a.alpha <= 0.02) continue;
      final g = s._toScreen(a.x, a.z);
      if (!view.inflate(160).contains(g)) continue;
      if (a is Foe) {
        final art = s._foeArt[a.kind];
        if (art != null) items.add((a.z, () => _foe(canvas, a, art, g)));
        // the charge's afterimages: the guardian a breath behind itself, fading violet
        if (a is Boss && art != null && r.bossTrail.isNotEmpty && !rm) {
          for (final (x, z, t0) in r.bossTrail) {
            final age = ((r.time - t0) / 0.32).clamp(0.0, 1.0);
            if (age >= 1) continue;
            items.add((z - 0.1, () {
              final keep = (a.alpha, a.flash);
              a.alpha = 0.32 * (1 - age);
              a.flash = 0.1;
              _foe(canvas, a, art, s._toScreen(x, z));
              a.alpha = keep.$1;
              a.flash = keep.$2;
            }));
          }
        }
      } else {
        items.add((a.z, () => _walker(canvas, a, a == pet ? s._petArt! : s._sherArt!, g, a == pet)));
      }
    }
    for (final (x, z, kind) in m.fx) {
      if (kind == 'fire') items.add((z + 0.5, () => _fire(canvas, s._toScreen(x, z))));
      if (kind == 'lamp') items.add((z + 0.5, () => _lamp(canvas, s._toScreen(x, z))));
    }
    final mart = s._miningArt;
    if (mart != null) {
      for (final o in r.ores) {
        final a = mart.ores[o.kind];
        if (a == null) continue;
        items.add((o.z, () => _ore(canvas, o, a)));
      }
    }
    for (final sh in r.shots) {
      items.add((sh.z + 1, () => _shot(canvas, sh)));
    }
    items.sort((a, b) => a.$1.compareTo(b.$1));
    for (final it in items) {
      it.$2();
    }
    _sentinelBeam(canvas, r);
    // the wood's own life: leaves coming down, fireflies in the shade; the edges sink into shadow
    if (!rm && !m.mine) _ambient(canvas, size);
    _vignette(canvas, size);
    if (m.mine) _caveDark(canvas, size, m, r);
    if (s._miningArt != null) _mineBitsPaint(canvas);
    // above everything: sparks, motes, stars, numbers
    for (final b in r.bursts) {
      if (!const {'pulse', 'spores', 'sweep', 'dust', 'scar', 'reef', 'snare'}.contains(b.kind)) _burst(canvas, b);
    }
    // a glint where something waits to be found
    for (final sp in m.spots) {
      if (sp.kind != 'glint' && !(sp.kind == 'nest' && !s._used.contains(sp.id))) continue;
      _glint(canvas, s._toScreen(sp.x, sp.z) - Offset(0, 10 * s._u / 2.7));
    }
    for (final f in r.allFoes) {
      _foeBar(canvas, f);
    }
    _trustBar(canvas, r);
    for (final f in r.floaters) {
      _floater(canvas, f);
    }
    // Sher's bubble
    final b = s._bubble;
    if (b != null && sher != null) _bubble(canvas, sher, b);
    // a flash over everything: a heavy hit (white), a signature move (its colour)
    if (r.flashT > 0 && !rm) {
      final a = (r.flashT / 0.22).clamp(0.0, 1.0);
      canvas.drawRect(view, Paint()..color = _tint(r.flashKind).withAlpha((a * (r.flashKind == 'white' ? 90 : 120)).round()));
    }
  }

  /// The colour of an effect tagged with a palette (a signature move), or a plain white or mint.
  static Color _tint(String tag) => switch (tag) {
        'ocean' => const Color(0xFF7FD2FF),
        'amber' => const Color(0xFFFFD66A),
        'amethyst' => const Color(0xFFD9A6FF),
        'forest' => const Color(0xFFA6E58A),
        'coral' => const Color(0xFFFFA3B0),
        'obsidian' => const Color(0xFFB9B4D6),
        'mint' => const Color(0xFF9FF0DA),
        _ => const Color(0xFFFFF6E4),
      };

  static double _h(int a, int b, int c) {
    var x = (a * 73856093) ^ (b * 19349663) ^ (c * 83492791);
    x = (x ^ (x >> 13)) * 1274126177;
    x = x ^ (x >> 16);
    return (x & 0xFFFFFF) / 0x1000000;
  }

  /// Fireflies and falling leaves, in the world (they stay put as the camera moves). Each is a pure
  /// function of its cell and the time: nothing to keep between frames.
  void _ambient(Canvas canvas, Size size) {
    final t = s._t;
    final a = s._toWorld(const Offset(-40, -80)), b = s._toWorld(Offset(size.width + 40, size.height + 40));
    final up = _up;
    // fireflies: a few per cell, drifting, blinking slowly
    const fc = 60.0;
    final glow = Paint()..blendMode = BlendMode.plus;
    for (var cx = (a.dx / fc).floor(); cx <= (b.dx / fc).floor(); cx++) {
      for (var cz = (a.dy / fc).floor(); cz <= (b.dy / fc).floor(); cz++) {
        for (var i = 0; i < 2; i++) {
          if (_h(cx, cz, i * 7 + 1) > 0.7) continue;
          final ph = _h(cx, cz, i * 7 + 2) * 6.283, ph2 = _h(cx, cz, i * 7 + 3) * 6.283;
          final x = (cx + _h(cx, cz, i * 7 + 4)) * fc + math.sin(t * 0.31 + ph) * 14 + math.sin(t * 0.83 + ph2) * 5;
          final z = (cz + _h(cx, cz, i * 7 + 5)) * fc + math.cos(t * 0.27 + ph2) * 12 + math.sin(t * 0.67 + ph) * 4;
          final y = 7 + _h(cx, cz, i * 7 + 6) * 12 + math.sin(t * 1.1 + ph) * 3;
          // on for a while, then dark: a slow pulse with a sharp-ish top
          final on = math.pow(math.max(0.0, math.sin(t * (0.55 + 0.3 * _h(cx, cz, i)) + ph * 3)), 3).toDouble();
          if (on < 0.03) continue;
          final g = s._toScreen(x, z) - Offset(0, y * up);
          final r = 2.4 * s._u;
          glow.shader = ui.Gradient.radial(g, r * 2.6, [
            Color.fromRGBO(255, 250, 170, 0.95 * on),
            Color.fromRGBO(214, 240, 110, 0.35 * on),
            const Color(0x00C8F060),
          ], const [0.0, 0.25, 1.0]);
          canvas.drawCircle(g, r * 2.6, glow);
        }
      }
    }
    // leaves: one in some cells, coming down from the canopy in a lazy zigzag, then gone
    const lc = 110.0;
    final leaf = Paint();
    const cols = [Color(0xFF6E9440), Color(0xFF8AA348), Color(0xFFB0893A), Color(0xFF9C6A30), Color(0xFF557A34)];
    for (var cx = (a.dx / lc).floor(); cx <= (b.dx / lc).floor(); cx++) {
      for (var cz = (a.dy / lc).floor(); cz <= (b.dy / lc).floor(); cz++) {
        if (_h(cx, cz, 91) > 0.55) continue;
        const life = 7.0;
        final off = _h(cx, cz, 92) * life;
        final cyc = ((t + off) / life).floor();
        final f = ((t + off) / life) - cyc; // 0..1 through this fall
        final x0 = (cx + _h(cx, cz, cyc * 3 + 1)) * lc, z0 = (cz + _h(cx, cz, cyc * 3 + 2)) * lc;
        final y = 42 * (1 - f);
        final x = x0 + math.sin(f * 9 + cx) * 7 + f * 18; // the wind carries it east a little
        final g = s._toScreen(x, z0) - Offset(0, y * up);
        final fade = f < 0.08 ? f / 0.08 : (f > 0.9 ? (1 - f) / 0.1 : 1.0);
        leaf.color = cols[(cyc + cx * 3 + cz).abs() % cols.length].withAlpha((230 * fade).round());
        canvas.save();
        canvas.translate(g.dx, g.dy);
        canvas.rotate(math.sin(f * 9 + cz) * 1.1);
        canvas.scale(1, 0.55 + 0.45 * math.cos(f * 13 + cx).abs()); // turning over as it falls
        canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: 2.6 * s._u, height: 1.5 * s._u), leaf);
        canvas.restore();
      }
    }
  }

  /// The gate's seal: beams of Lumen light between the gem sockets on the pillars, crackling, until the
  /// floor's guardian is calmed; then they draw back into the gems for good (a short retraction the first
  /// time it happens here).
  void _seal(Canvas canvas) {
    final seal = s._map?.gateSeal;
    if (seal == null) return;
    final (gx, gz, emit, beams) = seal;
    final open = s._sealOpen;
    final k = open ? (1 - s._sealT).clamp(0.0, 1.0) : 1.0; // how much of each beam is still out
    final t = s._t;
    // the seal's light spills into the doorway and onto the steps
    if (k > 0) {
      final c = s._toScreen(gx, gz) - Offset(0, beams[beams.length ~/ 2] * _up);
      final hum = rm ? 1.0 : 0.85 + 0.15 * math.sin(t * 3.1);
      _glow(canvas, c, emit * 2.1 * s._u * k, Color.fromRGBO(120, 230, 255, 0.22 * hum * k));
      canvas.drawOval(_ellipse(gx, gz + 6, emit * 1.3 * k), Paint()..color = Color.fromRGBO(140, 235, 255, 0.12 * hum * k));
    }
    for (var i = 0; i < beams.length; i++) {
      final h = beams[i];
      final l = s._toScreen(gx - emit + 2, gz) - Offset(0, h * _up);
      final r = s._toScreen(gx + emit - 2, gz) - Offset(0, h * _up);
      // the emitters glow either way (dimmer once the seal is down)
      for (final e in [l, r]) {
        _glow(canvas, e, (open && k <= 0 ? 6 : 10) * s._u / 2.7, Color.fromRGBO(160, 250, 255, open && k <= 0 ? 0.35 : 0.85));
        canvas.drawCircle(e, 2.2 * s._u / 2.7, Paint()..color = const Color(0xFFEFFFFF));
      }
      if (k <= 0) continue;
      // the beam: whole while the seal holds; drawing back, each half retreats into its own gem
      final mid = Offset.lerp(l, r, 0.5)!;
      final halves = k >= 1 ? [(l, r)] : [(l, Offset.lerp(l, mid, k)!), (r, Offset.lerp(r, mid, k)!)];
      final flick = rm ? 1.0 : 0.82 + 0.18 * math.sin(t * 31 + i * 2.1) * math.sin(t * 7.3 + i);
      final glowP = Paint()
        ..color = Color.fromRGBO(120, 235, 255, 0.5 * flick)
        ..strokeWidth = 11 * s._u / 2.7
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
      final core = Paint()
        ..color = Color.fromRGBO(235, 255, 255, 0.95 * flick)
        ..strokeWidth = 2.6 * s._u / 2.7
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;
      for (final (p0, p1) in halves) {
        // a wavering beam: a few segments, nudged by a shimmer
        final path = Path()..moveTo(p0.dx, p0.dy);
        const segs = 8;
        for (var j = 1; j <= segs; j++) {
          final pt = Offset.lerp(p0, p1, j / segs)!;
          final w = (j == segs || rm) ? 0.0 : math.sin(t * 23 + j * 1.7 + i * 3) * 1.2 * s._u / 2.7;
          path.lineTo(pt.dx, pt.dy + w);
        }
        canvas.drawPath(path, glowP);
        canvas.drawPath(path, core);
      }
      final a = l, b = r;
      // sparks crawling along it (while it holds)
      if (!rm && k >= 1) {
        for (var j = 0; j < 3; j++) {
          final f = ((t * (0.6 + j * 0.23) + i * 0.37 + j * 0.31) % 1.0);
          final pt = Offset.lerp(a, b, f)!;
          canvas.drawCircle(pt, 1.6 * s._u / 2.7, Paint()..color = const Color(0xFFFFFFFF));
        }
      }
    }
  }

  void _vignette(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    // a perfect dodge: the world slows and cools for a moment
    final sm = s._raid?.slowmo ?? 0;
    if (sm > 0 && !rm) {
      canvas.drawRect(
          Offset.zero & size,
          Paint()
            ..shader = ui.Gradient.radial(c, size.longestSide * 0.7, [const Color(0x00000000), Color.fromRGBO(120, 200, 255, 0.22 * math.min(1.0, sm / 0.2))], const [0.45, 1.0]));
    }
    canvas.drawRect(
        Offset.zero & size,
        Paint()
          ..shader = ui.Gradient.radial(c, size.longestSide * 0.62, const [Color(0x00000000), Color(0x00000000), Color(0x5A0A1408)],
              const [0.0, 0.55, 1.0]));
  }

  static final _see = Paint()
    ..filterQuality = FilterQuality.medium
    ..color = const Color.fromRGBO(0, 0, 0, 0.42);

  /// An ore node (the mines): the mining art's sprite in its crack state, shoved by a hit, glowing as
  /// your Evochi comes near (lumen), a soft shade under it.
  void _ore(Canvas canvas, OreRock o, OreKindArt a) {
    final sp = a.states[o.state];
    final k = a.unit * _WildsScreenState._wildsPerUnit * s._u; // screen px per sprite px
    final g = s._toScreen(o.x, o.z);
    var dst = Rect.fromLTWH(g.dx - sp.ground.dx * k, g.dy - sp.ground.dy * k, sp.img.width * k, sp.img.height * k);
    final h = s._t - o.hitAt;
    if (h >= 0 && h < 0.24 && !rm) dst = dst.shift(Offset(o.hitDir * 3.2 * math.sin(h / 0.24 * math.pi * 3) * (1 - h / 0.24), 0));
    canvas.drawOval(Rect.fromCenter(center: g, width: dst.width * 0.8, height: dst.width * 0.26), Paint()..color = const Color(0x3A16241F));
    final d = math.sqrt(math.pow(s._raid!.pet.x - o.x, 2) + math.pow(s._raid!.pet.z - o.z, 2)) / _WildsScreenState._wildsPerUnit;
    paintOre(canvas, sp.img, dst, o.kind, o.state, s._t, (1 - (d - 2.6) / 3.5).clamp(0.0, 1.0), rm, o.x * 0.37 + o.z * 0.11);
  }

  /// The chips, dust and nuggets of a strike (kept in the mining art's own units round the node), the
  /// nuggets flying off to the satchel chip when their time comes.
  void _mineBitsPaint(Canvas canvas) {
    final art = s._miningArt!;
    const K = _WildsScreenState._wildsPerUnit;
    final now = s._t;
    final to = s._satchelPoint();
    final upk = s._u * K; // screen px per mining unit
    for (final (o, bits) in s._mineBits) {
      for (final b in bits) {
        final age = now - b.born;
        final p = s._toScreen(o.x + b.x * K, o.z + b.z * K) - Offset(0, b.y * K * _up);
        switch (b.kind) {
          case 'dust':
            final a = (1 - age / b.life).clamp(0.0, 1.0);
            canvas.drawCircle(p, upk * b.size * (0.5 + age / b.life), Paint()
              ..color = b.color.withAlpha(((0.45 * a) * 255).round())
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
          case 'spark':
            final a = (1 - age / b.life).clamp(0.0, 1.0);
            canvas.drawCircle(p, upk * b.size * (1 + a), Paint()..color = b.color.withAlpha((a * 255).round()));
          case 'chip':
            final a = (1 - (age - b.life) / 0.6).clamp(0.0, 1.0);
            if (a <= 0) continue;
            final sz = upk * b.size;
            canvas.save();
            canvas.translate(p.dx, p.dy);
            canvas.rotate(age * 9 + b.size * 40);
            canvas.drawRect(Rect.fromCenter(center: Offset.zero, width: sz, height: sz), Paint()..color = b.color.withAlpha((a * 255).round()));
            canvas.drawRect(Rect.fromCenter(center: Offset.zero, width: sz, height: sz), Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1
              ..color = const Color(0xFF3B2923).withAlpha(((0.7 * a) * 255).round()));
            canvas.restore();
          case 'nugget':
            final n = art.ores[b.ore]?.nugget;
            if (n == null) continue;
            final unit = art.ores[b.ore]!.nuggetUnit;
            var at = p;
            var kk = upk * unit;
            if (now >= b.flyAt && to != null) {
              b.from ??= p;
              final e = ((now - b.flyAt) / 0.5).clamp(0.0, 1.0);
              final f = Curves.easeIn.transform(e);
              at = Offset.lerp(b.from, to, f)! - Offset(0, 60 * math.sin(e * math.pi));
              kk *= 1 - 0.45 * f;
              if (e >= 1) {
                if (s._nuggetsIn.add(b)) {
                  s._satchelBumpAt = now;
                  s._sfx('mine_collect', 0.5);
                }
                continue;
              }
            }
            canvas.drawImageRect(n.img, Rect.fromLTWH(0, 0, n.img.width.toDouble(), n.img.height.toDouble()),
                Rect.fromLTWH(at.dx - n.ground.dx * kk, at.dy - n.ground.dy * kk, n.img.width * kk, n.img.height * kk), Paint()..filterQuality = FilterQuality.medium);
        }
      }
    }
  }

  /// A miner's lantern hung on a post: a warm glow that breathes, the galleries' light.
  void _lamp(Canvas canvas, Offset g) {
    final k = s._u / 2.7;
    final t = s._t;
    final flick = rm ? 0.5 : (math.sin(t * 9 + g.dx) + math.sin(t * 5.3 + 1) + 2) / 4;
    canvas.drawRect(Rect.fromCenter(center: g - Offset(0, 14 * k), width: 2.6 * k, height: 28 * k), Paint()..color = const Color(0xFF4A2E1A));
    canvas.drawRect(Rect.fromLTWH(g.dx - 1.3 * k, g.dy - 28 * k, 9 * k, 2.2 * k), Paint()..color = const Color(0xFF4A2E1A));
    final lc = g + Offset(7 * k, -22 * k);
    canvas.drawCircle(lc, (14 + 4 * flick) * k, Paint()
      ..color = Color.fromRGBO(255, 179, 71, 0.22 + 0.08 * flick)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 12 * k));
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: lc, width: 5 * k, height: 6.5 * k), Radius.circular(1.2 * k)), Paint()..color = const Color(0xFF2E2A2A));
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: lc, width: 3.4 * k, height: 4.6 * k), Radius.circular(0.8 * k)),
        Paint()..color = Color.lerp(const Color(0xFFFFC561), const Color(0xFFFFE6A8), flick)!);
  }

  /// The cave's dark: the galleries lit only round their lamps, your Evochi's own light and the ore's
  /// glow; the rock beyond sinks into black.
  void _caveDark(Canvas canvas, Size size, WildsMap m, Raid r) {
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    c.drawRect(Offset.zero & size, Paint()..color = const Color(0xB40A0810));
    final clear = Paint()..blendMode = BlendMode.dstOut;
    void light(Offset at, double rad, double a) {
      c.drawCircle(at, rad, clear..shader = ui.Gradient.radial(at, rad, [Color.fromRGBO(0, 0, 0, a), const Color(0x00000000)], const [0.25, 1.0]));
    }
    final u = s._u / 2.7;
    light(s._toScreen(r.pet.x, r.pet.z) - Offset(0, 14 * u), 150 * u, 1.0);
    final sh = r.sher;
    if (sh != null) light(s._toScreen(sh.x, sh.z) - Offset(0, 14 * u), 90 * u, 0.8);
    for (final (x, z, kind) in m.fx) {
      if (kind == 'lamp' || kind == 'fire') light(s._toScreen(x, z) - Offset(0, 20 * u), 130 * u, 0.95);
    }
    for (final o in r.ores) {
      if (o.kind == 'lumen' && !o.broken) light(s._toScreen(o.x, o.z) - Offset(0, 10 * u), 70 * u, 0.7);
    }
    canvas.drawPicture(rec.endRecording());
  }

  double get _up => s._cosP * s._u; // screen px per world unit of height

  void _prop(Canvas canvas, bool flip, PropArt a, Offset g, double k, Paint pq, [ui.FragmentShader? sh, Offset at = Offset.zero]) {
    canvas.save();
    canvas.translate(g.dx, g.dy);
    if (flip) canvas.scale(-1, 1);
    canvas.scale(k);
    if (sh == null) {
      canvas.drawImage(a.img, Offset(-a.ax, -a.ay), pq);
    } else {
      final w = a.img.width.toDouble(), h = a.img.height.toDouble();
      sh
        ..setFloat(0, -a.ax)
        ..setFloat(1, -a.ay)
        ..setFloat(2, w)
        ..setFloat(3, h)
        ..setFloat(4, w)
        ..setFloat(5, h)
        ..setFloat(6, s._t % 600.0)
        ..setFloat(7, 1)
        ..setFloat(8, at.dx - a.ax)
        ..setFloat(9, at.dy - a.ay)
        ..setImageSampler(0, a.img)
        ..setImageSampler(1, a.mask!);
      canvas.drawRect(Rect.fromLTWH(-a.ax, -a.ay, w, h), Paint()
        ..shader = sh
        ..color = pq.color);
    }
    canvas.restore();
  }

  /// Cracks across a pillar or boulder the guardian has run into (more of them after each crash).
  void _cracks(Canvas canvas, Rect r, int n, double seed) {
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = const Color(0xDD2A2024);
    final hi = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = const Color(0x66FFF4E0);
    for (var c = 0; c < n * 2; c++) {
      var x = r.left + r.width * (0.3 + 0.4 * ((seed * 7.3 + c * 3.1) % 1.0));
      var y = r.top + r.height * (0.25 + 0.15 * c);
      final path = Path()..moveTo(x, y);
      for (var i = 0; i < 4; i++) {
        x += r.width * (((seed + c * 5 + i * 3) % 2 == 0) ? 0.08 : -0.07);
        y += r.height * 0.09;
        path.lineTo(x, y);
      }
      canvas.drawPath(path, p);
      canvas.drawPath(path.shift(const Offset(1.2, 0.6)), hi);
    }
  }

  /// What is left of a pillar or boulder the guardian brought down: a heap of mossy stones.
  void _rubble(Canvas canvas, Offset g, double w, double seed) {
    canvas.drawOval(Rect.fromCenter(center: g, width: w * 1.6, height: w * 0.55), Paint()..color = const Color(0x40000000));
    final cols = [const Color(0xFF8E897F), const Color(0xFF827D73), const Color(0xFF9A958A), const Color(0xFF5E8C40)];
    for (var i = 0; i < 9; i++) {
      final a = i * 2.39996 + seed;
      final d = w * 0.5 * ((i * 0.37 + seed * 0.13) % 1.0);
      final c = g + Offset(math.cos(a) * d, math.sin(a) * d * 0.4 - w * 0.08);
      final sz = w * (0.16 + 0.12 * ((i * 0.61) % 1.0));
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: c, width: sz, height: sz * 0.7), Radius.circular(sz * 0.2)),
          Paint()..color = cols[i % cols.length]);
      canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromCenter(center: c, width: sz, height: sz * 0.7), Radius.circular(sz * 0.2)),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2
            ..color = const Color(0xAA3B2923));
    }
  }

  void _rising(Canvas canvas, PropArt a, Offset g, double k, double rise, bool flip) {
    if (rise <= 0) return;
    canvas.save();
    canvas.translate(g.dx, g.dy);
    if (flip) canvas.scale(-1, 1);
    canvas.scale(k, k * (0.15 + 0.85 * Curves.easeOutBack.transform(rise)));
    canvas.drawImage(a.img, Offset(-a.ax, -a.ay), Paint()..filterQuality = FilterQuality.medium);
    canvas.restore();
  }

  Paint _spritePaint(Actor a) {
    final p = Paint()
      ..filterQuality = FilterQuality.medium
      ..color = Color.fromRGBO(0, 0, 0, a.alpha.clamp(0.0, 1.0));
    if (a.flash > 0) {
      p.colorFilter = ColorFilter.mode(Color.fromRGBO(255, 255, 255, (a.flash / 0.14).clamp(0.0, 1.0) * 0.75), BlendMode.srcATop);
    } else if (a is Foe && a.chillT > 0) {
      // frosted over by a Frost coating
      p.colorFilter = ColorFilter.mode(Color.fromRGBO(170, 220, 255, 0.22 + 0.1 * (a.chillT / 3).clamp(0.0, 1.0)), BlendMode.srcATop);
    }
    return p;
  }

  void _glow(Canvas canvas, Offset c, double r, Color col) {
    canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = ui.Gradient.radial(c, r, [col, col.withAlpha(0)]));
  }

  void _walker(Canvas canvas, Actor w, WalkerArt art, Offset g, bool isPet) {
    final r = s._raid!;
    final gait = art.gait(w.running && w.moving);
    final col = w.moving ? 1 + (w.phase * 8).floor() % 8 : 0;
    final k = s._u / walkerDrawScale;
    // afterimages of a dodge roll
    if (isPet) {
      for (final (x, z, t) in r.trail) {
        final age = (r.time - t) / 0.35;
        final gg = s._toScreen(x, z);
        final p = Paint()
          ..filterQuality = FilterQuality.low
          ..color = Color.fromRGBO(0, 0, 0, (1 - age).clamp(0.0, 1.0) * 0.35)
          ..colorFilter = const ColorFilter.mode(Color(0xAA9FF0DA), BlendMode.srcATop);
        canvas.drawImageRect(gait.img, Rect.fromLTWH(col * art.fw, w.dir * art.fh, art.fw, art.fh),
            Rect.fromLTWH(gg.dx - art.gx * k, gg.dy - art.gy * k, art.fw * k, art.fh * k), p);
      }
      if (w.glow > 0) _glow(canvas, g - Offset(0, art.gy * k * 0.4), 26 * s._u / 2.7, Color.fromRGBO(159, 240, 218, 0.55 * w.glow));
      if (w.slowT > 0) _glow(canvas, g - Offset(0, art.gy * k * 0.3), 20 * s._u / 2.7, const Color(0x55A27BD6));
    }
    final pose = gaitPose(w.phase, w.moving && w.alive, run: w.running ? 1 : 0, reduced: rm);
    canvas.save();
    canvas.translate(g.dx, g.dy - w.lift * _up - pose.bob * art.fh * k);
    if (!rm) {
      final face = w.dir * math.pi / 4;
      canvas.rotate((gait.roll[col] + pose.roll) * math.pi / 180 * math.cos(face) + w.tilt);
      final sit = w.pose == 'sit';
      final pop = Curves.easeOut.transform(w.pop.clamp(0.0, 1.0));
      canvas.scale(w.sx * pose.sx * (1 + 0.1 * pop), w.sy * pose.sy * gait.squash[col] * (sit ? 0.82 : 1) * (1 - 0.12 * pop));
    }
    final dst = Rect.fromLTWH(-art.gx * k, -art.gy * k, art.fw * k, art.fh * k);
    final paint = _spritePaint(w);
    canvas.drawImageRect(gait.img, Rect.fromLTWH(col * art.fw, w.dir * art.fh, art.fw, art.fh), dst, paint);
    // what it wears rides the body's bob
    if (isPet) {
      final lift = col < gait.lift.length ? gait.lift[col] : 0.0;
      for (final img in art.wear.values) {
        canvas.drawImageRect(img, Rect.fromLTWH(w.dir * art.fw, 0, art.fw, art.fh), dst.shift(Offset(0, -lift * k)), paint);
      }
    }
    canvas.restore();
    if (w.pose == 'sit') _stars(canvas, g - Offset(0, art.gy * k * 0.95), 1, 0.7);
  }

  void _foe(Canvas canvas, Foe f, FoeArt a, Offset g) {
    final k = s._u / a.scale * f.size;
    if (f.elite && !f.calm) {
      _glow(canvas, g - Offset(0, a.top * k * 0.35), a.top * k * 0.7, Color.fromRGBO(150, 90, 230, 0.32 + 0.1 * math.sin(s._t * 4)));
    } else if (!f.calm && (s._raid?.surge ?? false)) {
      // a Surge: every creature churns with the Hollow
      _glow(canvas, g - Offset(0, a.top * k * 0.3), a.top * k * 0.55, Color.fromRGBO(130, 60, 210, 0.22 + 0.08 * math.sin(s._t * 3 + f.x)));
    }
    final pose = f.pose;
    final pi = pose == null ? null : a.poses[pose];
    final ui.Image img;
    final Rect src;
    var roll = 0.0, squash = 1.0;
    if (pi != null) {
      img = a.act;
      src = Rect.fromLTWH(pi * a.fw, f.dir * a.fh, a.fw, a.fh);
    } else {
      final gait = a.gaits[f.gait] ?? a.gaits['walk']!;
      img = gait.sheets[f.calm ? 'calm' : 'hollow'] ?? gait.sheets.values.first;
      final col = f.moving ? 1 + (f.phase * 8).floor() % 8 : 0;
      src = Rect.fromLTWH(col * a.fw, f.dir * a.fh, a.fw, a.fh);
      roll = gait.roll[col];
      squash = gait.squash[col];
    }
    // a wind-up gathers a violet glow; the enraged guardian burns with it
    final glow = math.max(f.glow, f is Boss && f.stage >= 3 && !f.calm ? 0.5 + 0.2 * math.sin(s._t * 6) : 0.0);
    if (glow > 0 && !f.calm) _glow(canvas, g - Offset(0, a.top * k * 0.45), a.top * k * 0.6, Color.fromRGBO(170, 120, 230, 0.45 * glow));
    if (f.st == FoeState.windup && !f.calm && f is! Boss) _glow(canvas, g - Offset(0, a.top * k * 0.4), a.top * k * 0.55, const Color(0x55FF6B5E));
    canvas.save();
    canvas.translate(g.dx, g.dy - f.lift * _up);
    if (!rm) {
      canvas.rotate(roll * math.pi / 180 * math.cos(f.dir * math.pi / 4));
      final pop = Curves.easeOut.transform(f.pop.clamp(0.0, 1.0)) * (f is Boss ? 0.4 : 1.0);
      canvas.scale(f.sx * (1 + 0.12 * pop), f.sy * squash * (1 - 0.16 * pop));
    }
    if (pose == 'ball' && f.spin != 0 && !rm) {
      final c = 7.0 * _up;
      canvas.translate(0, -c);
      canvas.rotate(f.spin * (f.ax >= 0 ? 1 : -1));
      canvas.translate(0, c);
    }
    canvas.drawImageRect(img, src, Rect.fromLTWH(-a.gx * k, -a.gy * k, a.fw * k, a.fh * k), _spritePaint(f));
    canvas.restore();
    if (f.st == FoeState.stagger && (f is Boss || f.kind == 'sentinel')) _stars(canvas, g - Offset(0, a.top * k * 0.95), 2, 1);
    if (f.kind == 'sentinel' && !f.calm) _sentinelShield(canvas, f, a, g, k);
  }

  /// The Sentinel's Hollow shield: a violet dome over it, cracking as Lumen wears it down.
  void _sentinelShield(Canvas canvas, Foe f, FoeArt a, Offset g, double k) {
    final r = s._raid!;
    if (r.sentinelShield <= 0) return;
    final left = (r.sentinelShield / r.sentinelShieldMax).clamp(0.0, 1.0);
    final h = a.top * k * 1.05, w = f.radius * 2.6 * s._u;
    final pulse = rm ? 0.0 : 0.05 * math.sin(s._t * 3);
    final dome = Rect.fromLTRB(g.dx - w / 2, g.dy - h, g.dx + w / 2, g.dy + w * 0.18);
    canvas.drawOval(dome, Paint()..color = Color.fromRGBO(150, 100, 230, 0.16 + pulse + 0.1 * left));
    canvas.drawOval(
        dome,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2
          ..color = Color.fromRGBO(220, 200, 255, 0.55 + 0.3 * left));
    // cracks as it weakens
    final cracks = ((1 - left) * 7).floor();
    final cp = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = const Color(0xDDFFF6FF);
    for (var i = 0; i < cracks; i++) {
      final a0 = -math.pi * (0.15 + 0.7 * ((i * 0.618) % 1.0));
      final start = dome.center + Offset(math.cos(a0) * w / 2 * 0.95, math.sin(a0) * dome.height / 2 * 0.95);
      final path = Path()..moveTo(start.dx, start.dy);
      var p = start;
      for (var j = 0; j < 3; j++) {
        p = p + Offset((((i + j) * 0.37) % 1.0 - 0.5) * 10, 7 + j * 2.0);
        path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(path, cp);
    }
  }

  /// The Sentinel's eyes' beam: from its eyes down to the ground, sweeping.
  void _sentinelBeam(Canvas canvas, Raid r) {
    final b = r.beam;
    final f = r.sentinel;
    if (b == null || f == null) return;
    final a = s._foeArt['sentinel'];
    final eyeH = a == null ? 40.0 : a.top * s._u / a.scale * f.size * 0.78;
    final from = s._toScreen(f.x, f.z) - Offset(0, eyeH);
    final to = s._toScreen(b.x + b.dx * b.len, b.z + b.dz * b.len);
    final ground = s._toScreen(b.x + b.dx * 20, b.z + b.dz * 20);
    final flick = rm ? 1.0 : 0.85 + 0.15 * math.sin(s._t * 40);
    // the burn along the ground
    canvas.drawLine(ground, to, Paint()
      ..strokeWidth = 7 * s._u / 2.7
      ..strokeCap = StrokeCap.round
      ..color = Color.fromRGBO(120, 70, 200, 0.35 * flick));
    for (final (wd, col) in [
      (16.0, Color.fromRGBO(150, 90, 240, 0.28 * flick)),
      (8.0, Color.fromRGBO(200, 160, 255, 0.6 * flick)),
      (3.0, const Color.fromRGBO(255, 245, 255, 0.95)),
    ]) {
      canvas.drawLine(from, to, Paint()
        ..strokeWidth = wd * s._u / 2.7
        ..strokeCap = StrokeCap.round
        ..color = col);
    }
    _glow(canvas, to, 16 * s._u / 2.7, Color.fromRGBO(210, 170, 255, 0.6 * flick));
    _glow(canvas, from, 10 * s._u / 2.7, const Color(0xCCF1E6FF));
  }

  void _heart(Canvas canvas, Offset c, double r, Color col) {
    final p = Path()
      ..moveTo(c.dx, c.dy + r * 0.9)
      ..cubicTo(c.dx - r * 1.6, c.dy - r * 0.2, c.dx - r * 0.7, c.dy - r * 1.3, c.dx, c.dy - r * 0.45)
      ..cubicTo(c.dx + r * 0.7, c.dy - r * 1.3, c.dx + r * 1.6, c.dy - r * 0.2, c.dx, c.dy + r * 0.9)
      ..close();
    canvas.drawPath(p, Paint()..color = col);
  }

  /// Petalune's trust, a little pink bar over it while you earn it.
  void _trustBar(Canvas canvas, Raid r) {
    final f = r.petalune;
    if (f == null || r.storyBeat != 'trust' || r.storyDone || r.pet.dist(f) > 160) return;
    final a = s._foeArt['petalune'];
    if (a == null) return;
    final g = s._toScreen(f.x, f.z) - Offset(0, a.top * s._u / a.scale + 10);
    const w = 40.0, h = 6.0;
    final rect = Rect.fromCenter(center: g, width: w, height: h);
    canvas.drawRRect(RRect.fromRectAndRadius(rect.inflate(1.5), const Radius.circular(4)), Paint()..color = const Color(0xCC3B2923));
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(rect.left, rect.top, w * r.trust / 100, h), const Radius.circular(3)),
        Paint()..color = const Color(0xFFF5A3B5));
    _heart(canvas, Offset(rect.left - 7, rect.center.dy), 4, const Color(0xFFE0849A));
  }

  void _foeBar(Canvas canvas, Foe f) {
    if (f is Boss || f.calm || !f.alive || f.hp >= f.maxHp || f.alpha < 0.5) return;
    final a = s._foeArt[f.kind];
    if (a == null) return;
    final g = s._toScreen(f.x, f.z) - Offset(0, a.top * s._u / a.scale + 8);
    const w = 34.0, h = 5.0;
    final rect = Rect.fromCenter(center: g, width: w, height: h);
    canvas.drawRRect(RRect.fromRectAndRadius(rect.inflate(1.5), const Radius.circular(4)), Paint()..color = const Color(0xCC1A120A));
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(rect.left, rect.top, w * f.hpFrac, h), const Radius.circular(3)),
        Paint()..color = const Color(0xFFE5675B));
  }

  void _ring(Canvas canvas, Actor a, Color col) {
    final g = s._toScreen(a.x, a.z);
    final pulse = rm ? 0.0 : math.sin(s._t * 6) * 0.06;
    final rect = Rect.fromCenter(center: g, width: a.radius * 2.9 * s._u * (1 + pulse), height: a.radius * 1.35 * s._u * (1 + pulse));
    canvas.drawOval(
        rect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..color = col.withAlpha(200));
  }

  // ---- telegraphs: where something is about to land. Red-orange, the fill grows to the moment it hits.
  static const _danger = Color(0xFFFF5A4E);

  Path _poly(List<(double, double)> pts) {
    final p = Path();
    for (var i = 0; i < pts.length; i++) {
      final o = s._toScreen(pts[i].$1, pts[i].$2);
      if (i == 0) {
        p.moveTo(o.dx, o.dy);
      } else {
        p.lineTo(o.dx, o.dy);
      }
    }
    return p..close();
  }

  Rect _ellipse(double x, double z, double r) {
    final c = s._toScreen(x, z);
    return Rect.fromCenter(center: c, width: r * 2 * s._u, height: r * 2 * s._u * s._map!.sinP);
  }

  void _mark(Canvas canvas, Mark mk) {
    final p = mk.p;
    final fill = Paint()..color = _danger.withAlpha((40 + 50 * p).round());
    final grow = Paint()..color = _danger.withAlpha((70 + 80 * p).round());
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = _danger.withAlpha((150 + 100 * p).round());
    switch (mk.shape) {
      case MarkShape.circle:
        canvas.drawOval(_ellipse(mk.x, mk.z, mk.r), fill);
        canvas.drawOval(_ellipse(mk.x, mk.z, mk.r * p), grow);
        canvas.drawOval(_ellipse(mk.x, mk.z, mk.r), edge);
      case MarkShape.ring:
        // the ring about to roll out: a glowing band round the guardian
        final outer = _ellipse(mk.x, mk.z, mk.r + 8 * p);
        canvas.drawOval(outer, edge..strokeWidth = 3 + 4 * p);
        canvas.drawOval(_ellipse(mk.x, mk.z, mk.r * 0.7), fill);
      case MarkShape.line:
        final nx = -mk.dz, nz = mk.dx;
        List<(double, double)> rect(double len) => [
              (mk.x + nx * mk.width / 2, mk.z + nz * mk.width / 2),
              (mk.x + nx * mk.width / 2 + mk.dx * len, mk.z + nz * mk.width / 2 + mk.dz * len),
              (mk.x - nx * mk.width / 2 + mk.dx * len, mk.z - nz * mk.width / 2 + mk.dz * len),
              (mk.x - nx * mk.width / 2, mk.z - nz * mk.width / 2),
            ];
        canvas.drawPath(_poly(rect(mk.len)), fill);
        canvas.drawPath(_poly(rect(mk.len * p)), grow);
        // about to go: the edge flashes white
        if (p > 0.72) edge.color = Color.lerp(edge.color, const Color(0xFFFFFFFF), 0.5 + 0.5 * math.sin(s._t * 30))!;
        canvas.drawPath(_poly(rect(mk.len)), edge..strokeWidth = p > 0.72 ? 3.5 : 2);
        // chevrons along it, pointing the way it will come
        final ch = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..strokeCap = StrokeCap.round
          ..color = const Color(0xCCFFE2D6);
        for (var d = 16.0 + (rm ? 0 : (s._t * 70) % 22); d < mk.len - 6; d += 22) {
          final cx = mk.x + mk.dx * d, cz = mk.z + mk.dz * d;
          final a = s._toScreen(cx - mk.dx * 5 + nx * 5, cz - mk.dz * 5 + nz * 5);
          final b = s._toScreen(cx, cz);
          final c = s._toScreen(cx - mk.dx * 5 - nx * 5, cz - mk.dz * 5 - nz * 5);
          canvas.drawPath(Path()..moveTo(a.dx, a.dy)..lineTo(b.dx, b.dy)..lineTo(c.dx, c.dy), ch);
        }
      case MarkShape.cone:
        List<(double, double)> cone(double rad) {
          final pts = <(double, double)>[(mk.x, mk.z)];
          final a0 = math.atan2(mk.dx, mk.dz);
          for (var i = 0; i <= 14; i++) {
            final a = a0 - mk.half + 2 * mk.half * i / 14;
            pts.add((mk.x + math.sin(a) * rad, mk.z + math.cos(a) * rad));
          }
          return pts;
        }
        canvas.drawPath(_poly(cone(mk.r)), fill);
        canvas.drawPath(_poly(cone(mk.r * p)), grow);
        canvas.drawPath(_poly(cone(mk.r)), edge);
    }
  }

  void _cloud(Canvas canvas, Hazard h) {
    final fade = (math.min(h.t / 0.3, 1.0) * math.min((h.life - h.t) / 0.6, 1.0)).clamp(0.0, 1.0);
    for (var i = 0; i < 5; i++) {
      final a = i * 1.26 + s._t * 0.4;
      final rr = h.r * (0.55 + 0.12 * math.sin(s._t * 1.7 + i));
      final cx = h.x + math.cos(a) * h.r * 0.35, cz = h.z + math.sin(a) * h.r * 0.35;
      canvas.drawOval(_ellipse(cx, cz, rr), Paint()..color = Color.fromRGBO(162, 123, 214, 0.22 * fade));
    }
    canvas.drawOval(_ellipse(h.x, h.z, h.r),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = Color.fromRGBO(217, 194, 255, 0.5 * fade));
  }

  void _wave(Canvas canvas, Wave wv) {
    final band = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8 * s._u / 2.7
      ..color = const Color(0x99A27BD6);
    canvas.drawOval(_ellipse(wv.x, wv.z, wv.r), band);
    final n = (wv.r / 3).clamp(12, 60).round();
    final thorn = Paint()..color = const Color(0xFF3E2B46);
    for (var i = 0; i < n; i++) {
      final a = i * 2 * math.pi / n;
      final b = s._toScreen(wv.x + math.sin(a) * wv.r, wv.z + math.cos(a) * wv.r);
      final hgt = (7 + (i % 3) * 2) * _up;
      canvas.drawPath(Path()..moveTo(b.dx - 3, b.dy)..lineTo(b.dx, b.dy - hgt)..lineTo(b.dx + 3, b.dy)..close(), thorn);
    }
  }

  void _pickup(Canvas canvas, Pickup p) {
    if (p.kind == 'coin') {
      // a coin: out of the calmed creature, spinning, bouncing, resting a beat before it flies up
      final u = s._u / 2.7;
      final base = s._toScreen(p.x, p.z);
      final spin = math.cos(p.t * 14 + p.x);
      final rest = p.t > 0.75;
      final g = base - Offset(0, (p.y + (rest ? 3 + 2 * math.sin(s._t * 6 + p.z) : 0)) * _up);
      canvas.drawOval(Rect.fromCenter(center: base, width: 9 * u, height: 4 * u), Paint()..color = const Color(0x3A16241F));
      final r = 5.2 * u;
      final rr = Rect.fromCenter(center: g, width: r * 2 * (0.25 + 0.75 * spin.abs()), height: r * 2);
      canvas.drawOval(rr, Paint()..color = const Color(0xFFB8781E));
      canvas.drawOval(rr.deflate(1.2), Paint()..color = spin > 0 ? const Color(0xFFFFD35A) : const Color(0xFFE9B23C));
      canvas.drawOval(rr.deflate(r * 0.42), Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = const Color(0x99B8781E));
      if (rest) _glow(canvas, g, 10 * u, const Color(0x55FFE07A));
      return;
    }
    if (p.kind == 'loot') {
      // a glint of loot arcing out, then streaking to your Evochi
      final up = p.t < 0.35 ? 4 + 26 * math.sin(p.t / 0.35 * math.pi) * 0.6 : 8.0;
      final g = s._toScreen(p.x, p.z) - Offset(0, up * _up);
      _glow(canvas, g, 9 * s._u / 2.7, const Color(0x99FFE07A));
      _star(canvas, g, 4.5 * s._u / 2.7, const Color(0xFFFFF6D0));
      return;
    }
    final g = s._toScreen(p.x, p.z) - Offset(0, (6 + math.sin(s._t * 3 + p.x) * 2) * _up);
    final fade = p.t > 17 ? (20 - p.t) / 3 : 1.0;
    if (p.kind == 'bloom') {
      // the Starseed Charm's bloom of light: petals opening round a star
      final u = s._u / 2.7, open = Curves.easeOutBack.transform((p.t / 0.6).clamp(0.0, 1.0));
      final base = s._toScreen(p.x, p.z);
      _glow(canvas, base - Offset(0, 4 * _up), 18 * u, Color.fromRGBO(255, 236, 170, 0.55 * fade));
      for (var i = 0; i < 5; i++) {
        final a = i * math.pi * 2 / 5 + s._t * 0.6;
        canvas.drawOval(Rect.fromCenter(center: base - Offset(0, 3 * _up) + Offset(math.cos(a) * 5 * u, math.sin(a) * 2.6 * u) * open, width: 6 * u * open, height: 3.6 * u * open),
            Paint()..color = Color.fromRGBO(255, 214, 236, fade));
      }
      _star(canvas, base - Offset(0, 4 * _up), 3.6 * u * open, Color.fromRGBO(255, 250, 220, fade));
      return;
    }
    _glow(canvas, g, 12 * s._u / 2.7, Color.fromRGBO(255, 240, 160, 0.6 * fade));
    canvas.drawCircle(g, 3.5 * s._u / 2.7, Paint()..color = Color.fromRGBO(255, 253, 230, fade));
  }

  void _shot(Canvas canvas, Shot sh) {
    final g = s._toScreen(sh.x, sh.z) - Offset(0, sh.height * _up);
    switch (sh.kind) {
      case ShotKind.bolt:
        final sp = math.max(1e-6, math.sqrt(sh.vx * sh.vx + sh.vz * sh.vz));
        for (var i = 3; i >= 1; i--) {
          final t = s._toScreen(sh.x - sh.vx / sp * i * 5, sh.z - sh.vz / sp * i * 5) - Offset(0, sh.height * _up);
          canvas.drawCircle(t, (4 - i) * 1.3 * s._u / 2.7, Paint()..color = Color.fromRGBO(159, 240, 218, 0.25 * (4 - i) / 3));
        }
        final hue = sh.prism
            ? HSVColor.fromAHSV(1, (s._t * 240 + sh.x * 3) % 360, 0.55, 1).toColor()
            : (sh.shard ? const Color(0xFFC6A2FF) : const Color(0xFF9FF0DA));
        _glow(canvas, g, 12 * s._u / 2.7, hue.withAlpha(153));
        canvas.drawCircle(g, (sh.prism ? 3 : 4) * s._u / 2.7, Paint()..color = const Color(0xFFE8FFF8));
      case ShotKind.spore:
        _glow(canvas, g, 10 * s._u / 2.7, const Color(0x88A27BD6));
        canvas.drawCircle(g, 5 * s._u / 2.7, Paint()..color = const Color(0xFF6B4C95));
        canvas.drawCircle(g + const Offset(-1.5, -1.5), 1.6 * s._u / 2.7, Paint()..color = const Color(0xFFD9C2FF));
      case ShotKind.vial:
        canvas.save();
        canvas.translate(g.dx, g.dy);
        canvas.rotate(sh.t * 12);
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset.zero, width: 5 * s._u / 2.7, height: 8 * s._u / 2.7), const Radius.circular(2)),
            Paint()..color = const Color(0xFFF4B84E));
        canvas.restore();
    }
  }

  void _stars(Canvas canvas, Offset c, double size, double alpha) {
    for (var i = 0; i < 3; i++) {
      final a = s._t * 4 + i * 2.1;
      final p = c + Offset(math.cos(a) * 10 * size, math.sin(a) * 3.5 * size);
      _star(canvas, p, 3.5 * size, Color.fromRGBO(255, 225, 110, alpha));
    }
  }

  void _star(Canvas canvas, Offset c, double r, Color col) {
    final path = Path();
    for (var i = 0; i < 8; i++) {
      final a = i * math.pi / 4 - math.pi / 2;
      final rr = i.isEven ? r : r * 0.4;
      final o = c + Offset(math.cos(a) * rr, math.sin(a) * rr);
      if (i == 0) {
        path.moveTo(o.dx, o.dy);
      } else {
        path.lineTo(o.dx, o.dy);
      }
    }
    canvas.drawPath(path..close(), Paint()..color = col);
  }

  void _burst(Canvas canvas, Burst b) {
    final k = (b.t / b.ttl).clamp(0.0, 1.0);
    final g = s._toScreen(b.x, b.z);
    final u = s._u / 2.7;
    switch (b.kind) {
      case 'swipe':
        // the Pounce's arc of light: bigger as your Evochi grows, tinted by its coating
        final col = switch (b.tag) {
          'ember' => const Color(0xFFFFA24A),
          'frost' => const Color(0xFFBFE9FF),
          'static' => const Color(0xFFFFE86A),
          'sap' => const Color(0xFFB8EE7A),
          'dazzle' => const Color(0xFFFFF0A8),
          'hush' => const Color(0xFF9FB8FF),
          _ => const Color(0xFFFFF6E4),
        };
        final a0 = math.atan2(b.dz * s._map!.sinP, b.dx);
        final w = 34 * u * b.size, h = 24 * u * b.size;
        final c = g - Offset(0, 9 * _up);
        final rect = Rect.fromCenter(center: c, width: w, height: h);
        final sweep = 1.0 + 0.9 * k;
        canvas.drawArc(rect, a0 - 0.9, sweep, false,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = (5 + 3 * b.size) * (1 - k)
              ..strokeCap = StrokeCap.round
              ..color = col.withAlpha(((1 - k) * 230).round()));
        if (b.tag.isNotEmpty) _glow(canvas, c, 18 * u * b.size, col.withAlpha(((1 - k) * 110).round()));
      case 'quake':
        // the Leap lands: a ring of force across the ground and a puff of grit
        canvas.drawOval(
            _ellipse(b.x, b.z, b.size * Curves.easeOutCubic.transform(k)),
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 6 * (1 - k) + 1
              ..color = Color.fromRGBO(255, 244, 214, 0.85 * (1 - k)));
        canvas.drawOval(_ellipse(b.x, b.z, b.size * 0.6 * k), Paint()..color = Color.fromRGBO(200, 180, 140, 0.25 * (1 - k)));
      case 'frost':
        // a Frost coating takes hold: ice shards burst out and glitter
        final p = Paint()
          ..strokeWidth = 2.4
          ..strokeCap = StrokeCap.round
          ..color = Color.fromRGBO(200, 236, 255, 1 - k);
        final c = g - Offset(0, 10 * _up * b.size);
        for (var i = 0; i < 8; i++) {
          final a = i * math.pi / 4 + 0.3;
          final d0 = 3 + 6 * k, d1 = 8 + 18 * k;
          canvas.drawLine(c + Offset(math.cos(a) * d0, math.sin(a) * d0 * 0.7) * u * b.size,
              c + Offset(math.cos(a) * d1, math.sin(a) * d1 * 0.7) * u * b.size, p);
        }
        _glow(canvas, c, 18 * u * b.size, Color.fromRGBO(170, 220, 255, 0.5 * (1 - k)));
      case 'sap':
        // green motes drawn from the hit back into your Evochi
        final pc = Paint()..color = Color.fromRGBO(170, 230, 110, 0.9 * (1 - k * k));
        for (var i = 0; i < 4; i++) {
          final kk = (k * 1.3 - i * 0.1).clamp(0.0, 1.0);
          final at = s._toScreen(b.x + b.dx * kk, b.z + b.dz * kk) - Offset(math.sin(i * 2.1 + k * 6) * 6 * u, (12 + 10 * math.sin(kk * math.pi)) * _up);
          canvas.drawCircle(at, 2.6 * u, pc);
        }
      case 'zap':
        // Static: a jagged spark leaps to the next foe
        final from = g - Offset(0, 10 * _up), to = s._toScreen(b.x + b.dx, b.z + b.dz) - Offset(0, 10 * _up);
        final path = Path()..moveTo(from.dx, from.dy);
        for (var i = 1; i < 6; i++) {
          final t = i / 6;
          final mid = Offset.lerp(from, to, t)!;
          path.lineTo(mid.dx + ((i + (s._t * 30).floor()) % 2 == 0 ? 6 : -6) * u, mid.dy + (i.isEven ? -4 : 4) * u);
        }
        path.lineTo(to.dx, to.dy);
        canvas.drawPath(
            path,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 3
              ..strokeJoin = StrokeJoin.round
              ..color = Color.fromRGBO(255, 236, 110, 1 - k));
        _glow(canvas, to, 16 * u, Color.fromRGBO(255, 236, 110, 0.6 * (1 - k)));
      case 'tide':
        // Tidal Surge: a wall of water rolling out ahead, foam on its crest
        final along = b.size * Curves.easeOutCubic.transform(k);
        final nx = -b.dz, nz = b.dx;
        final fade = 1 - k * k;
        for (var i = 0; i < 3; i++) {
          final d = along - i * 14;
          if (d < 0) continue;
          final cx = b.x + b.dx * d, cz = b.z + b.dz * d;
          final a = s._toScreen(cx + nx * 34, cz + nz * 34), c = s._toScreen(cx - nx * 34, cz - nz * 34);
          canvas.drawLine(
              a - Offset(0, (10 - i * 3) * _up),
              c - Offset(0, (10 - i * 3) * _up),
              Paint()
                ..strokeWidth = (14 - i * 4) * u
                ..strokeCap = StrokeCap.round
                ..color = Color.fromRGBO(i == 0 ? 220 : 90, i == 0 ? 245 : 170, 255, (i == 0 ? 0.9 : 0.6) * fade));
        }
      case 'crystal':
        // Crystal Shards: a ring of violet light as they leave
        canvas.drawOval(
            _ellipse(b.x, b.z, b.size * (0.4 + k)),
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 5 * (1 - k)
              ..color = Color.fromRGBO(200, 160, 255, 0.9 * (1 - k)));
        _glow(canvas, g - Offset(0, 8 * _up), 30 * u, Color.fromRGBO(190, 150, 255, 0.6 * (1 - k)));
      case 'lash':
        // the Hollow Sprout's vine: it whips out along the telegraph and snaps back
        final out = k < 0.35 ? k / 0.35 : 1 - (k - 0.35) / 0.65;
        final path = Path();
        final px = -b.dz, pz = b.dx;
        for (var i = 0; i <= 16; i++) {
          final f = i / 16 * out;
          final wv = math.sin(f * 9 + k * 14) * 5 * (1 - f * 0.5);
          final p = s._toScreen(b.x + b.dx * b.size * f + px * wv, b.z + b.dz * b.size * f + pz * wv) - Offset(0, 6 * _up);
          if (i == 0) {
            path.moveTo(p.dx, p.dy);
          } else {
            path.lineTo(p.dx, p.dy);
          }
        }
        canvas.drawPath(
            path,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 7 * u
              ..strokeCap = StrokeCap.round
              ..color = const Color(0xFF43306B));
        canvas.drawPath(
            path,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2.5 * u
              ..strokeCap = StrokeCap.round
              ..color = const Color(0xFFD9C2FF).withAlpha(((1 - k) * 230).round()));
      case 'notes':
        // a hum: little notes drifting up from your Evochi
        for (var i = 0; i < 4; i++) {
          final kk = ((k * 1.3) - i * 0.12).clamp(0.0, 1.0);
          if (kk <= 0) continue;
          final p = g - Offset(-10 * u + i * 7 * u + math.sin(kk * 6 + i) * 5 * u, (22 + 40 * kk) * _up);
          final a = ((1 - kk) * 255).round();
          final tp = TextPainter(
              text: TextSpan(text: i.isEven ? '♪' : '♫', style: TextStyle(fontSize: 15 * u, color: Color.fromARGB(a, 255, 240, 200), fontWeight: FontWeight.w700)),
              textDirection: TextDirection.ltr)
            ..layout();
          tp.paint(canvas, p - Offset(tp.width / 2, tp.height / 2));
        }
      case 'hearts':
        // a treat, or trust won: hearts float up
        for (var i = 0; i < 3 + (b.size * 2).round(); i++) {
          final kk = ((k * 1.2) - i * 0.08).clamp(0.0, 1.0);
          if (kk <= 0) continue;
          final p = g - Offset(math.sin(i * 2.1) * 14 * u + math.sin(kk * 5 + i) * 4 * u, (18 + 46 * kk) * _up);
          _heart(canvas, p, (5 + i % 3) * u, Color.fromRGBO(245, 130, 160, 1 - kk));
        }
      case 'hush':
        // Petal Hush: a soft pink ring rolls out over the fight
        canvas.drawOval(
            _ellipse(b.x, b.z, b.size * Curves.easeOut.transform(k)),
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 4 * (1 - k) + 1
              ..color = Color.fromRGBO(250, 190, 210, 0.8 * (1 - k)));
        for (var i = 0; i < 10; i++) {
          final a = i * 0.628 + k * 1.5;
          final rr = b.size * Curves.easeOut.transform(k) * 0.9;
          _heart(canvas, s._toScreen(b.x + math.cos(a) * rr, b.z + math.sin(a) * rr) - Offset(0, 6 * _up), 3.5 * u, Color.fromRGBO(255, 210, 225, 1 - k));
        }
      case 'snare' when b.tag == 'rune':
        // the Sentinel's runes: a ring of old light bursts up out of the ground
        final rise = k < 0.12 ? k / 0.12 : (k > 0.7 ? (1 - k) / 0.3 : 1.0);
        final e = _ellipse(b.x, b.z, b.size);
        canvas.drawOval(e, Paint()..color = Color.fromRGBO(150, 100, 230, 0.35 * rise));
        canvas.drawOval(
            e,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2.5
              ..color = Color.fromRGBO(230, 210, 255, 0.9 * rise));
        canvas.drawOval(
            e.deflate(e.width * 0.18),
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.5
              ..color = Color.fromRGBO(200, 170, 250, 0.7 * rise));
        // shafts of light up out of it
        for (var i = 0; i < 7; i++) {
          final a = i * math.pi * 2 / 7 + b.x * 0.1;
          final base = s._toScreen(b.x + math.cos(a) * b.size * 0.7, b.z + math.sin(a) * b.size * 0.7);
          final h = (24 + 10 * ((i * 0.37) % 1.0)) * _up * rise;
          canvas.drawLine(base, base - Offset(0, h), Paint()
            ..strokeWidth = 3 * u
            ..strokeCap = StrokeCap.round
            ..color = Color.fromRGBO(210, 180, 255, 0.55 * rise));
        }
      case 'snare':
        // Thorn Snare: thorns burst up in a ring and hold, then sink (violet: the Hollow Sprout's)
        final rise = k < 0.15 ? k / 0.15 : (k > 0.8 ? (1 - k) / 0.2 : 1.0);
        final hollow = b.tag == 'hollow';
        canvas.drawOval(_ellipse(b.x, b.z, b.size), Paint()..color = hollow ? Color.fromRGBO(70, 40, 110, 0.3 * rise) : Color.fromRGBO(60, 90, 40, 0.25 * rise));
        final tp = Paint()..color = hollow ? Color.fromRGBO(67, 48, 107, rise) : Color.fromRGBO(70, 110, 46, rise);
        final hi = Paint()..color = hollow ? Color.fromRGBO(200, 170, 240, rise) : Color.fromRGBO(140, 190, 90, rise);
        for (var i = 0; i < 26; i++) {
          final a = i * 2.39996;
          final rr = b.size * (0.25 + 0.75 * ((i * 0.37) % 1.0));
          final base = s._toScreen(b.x + math.cos(a) * rr, b.z + math.sin(a) * rr);
          final h = (10 + 8 * ((i * 0.61) % 1.0)) * _up * rise;
          final w2 = 3 * u;
          canvas.drawPath(Path()..moveTo(base.dx - w2, base.dy)..lineTo(base.dx + w2, base.dy)..lineTo(base.dx + 1, base.dy - h)..close(), tp);
          canvas.drawLine(base, base - Offset(-1, h * 0.8), hi..strokeWidth = 1);
        }
      case 'reef':
        // Reef Bloom: coral and soft light underfoot that heals
        final rise = k < 0.1 ? k / 0.1 : (k > 0.85 ? (1 - k) / 0.15 : 1.0);
        canvas.drawOval(_ellipse(b.x, b.z, b.size), Paint()..color = Color.fromRGBO(255, 150, 140, 0.18 * rise));
        canvas.drawOval(
            _ellipse(b.x, b.z, b.size),
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2.5
              ..color = Color.fromRGBO(255, 190, 170, 0.7 * rise));
        for (var i = 0; i < 9; i++) {
          final a = i * 2.39996 + 0.5;
          final rr = b.size * (0.3 + 0.6 * ((i * 0.53) % 1.0));
          final base = s._toScreen(b.x + math.cos(a) * rr, b.z + math.sin(a) * rr);
          final sway = math.sin(s._t * 2 + i) * 2 * u;
          final cp = Paint()
            ..strokeWidth = 3 * u
            ..strokeCap = StrokeCap.round
            ..color = (i.isEven ? const Color(0xFFFF8A80) : const Color(0xFFFFB3A0)).withAlpha((rise * 255).round());
          canvas.drawLine(base, base + Offset(sway - 3 * u, -9 * _up * rise), cp);
          canvas.drawLine(base, base + Offset(sway + 3 * u, -7 * _up * rise), cp);
        }
        for (var i = 0; i < 6; i++) {
          final ph = (s._t * 0.5 + i / 6) % 1.0;
          final a = i * 1.7;
          final at = s._toScreen(b.x + math.cos(a) * b.size * 0.5, b.z + math.sin(a) * b.size * 0.5) - Offset(0, ph * 26 * _up);
          canvas.drawCircle(at, 2.2 * u, Paint()..color = Color.fromRGBO(255, 230, 220, (1 - ph) * 0.8 * rise));
        }
      case 'sunflare':
        // Sunflare: a burst of light rays from your Evochi
        final c = g - Offset(0, 10 * _up);
        final rays = Paint()
          ..strokeWidth = 4 * u * (1 - k)
          ..strokeCap = StrokeCap.round
          ..color = Color.fromRGBO(255, 230, 140, 0.9 * (1 - k));
        for (var i = 0; i < 16; i++) {
          final a = i * math.pi / 8 + k;
          final r0 = 12 * u + b.size * 0.3 * k * u, r1 = r0 + (30 + 40 * k) * u;
          canvas.drawLine(c + Offset(math.cos(a), math.sin(a) * 0.6) * r0, c + Offset(math.cos(a), math.sin(a) * 0.6) * r1, rays);
        }
        _glow(canvas, c, (30 + 90 * k) * u, Color.fromRGBO(255, 236, 160, 0.7 * (1 - k)));
      case 'scar':
        // moss torn up behind the charge: a dark furrow that fades
        final a = s._toScreen(b.x - b.dx * 7, b.z - b.dz * 7), c = s._toScreen(b.x + b.dx * 7, b.z + b.dz * 7);
        final fade = (1 - k) * (k < 0.05 ? k / 0.05 : 1.0);
        for (final side in const [-1.0, 1.0]) {
          final o = Offset(-b.dz, b.dx * s._map!.sinP) * 6 * side * u;
          canvas.drawLine(
              a + o,
              c + o,
              Paint()
                ..strokeWidth = 4 * u
                ..strokeCap = StrokeCap.round
                ..color = Color.fromRGBO(70, 50, 34, 0.55 * fade));
        }
      case 'debris':
      case 'rubble':
        // chunks of stone thrown off the pillar, falling back
        final n = b.kind == 'rubble' ? 14 : 8;
        final pc = Paint();
        for (var i = 0; i < n; i++) {
          final a = (i / n) * math.pi * 2 + b.x;
          final out = Offset(math.cos(a) + b.dx * 0.8, math.sin(a) * 0.5 + b.dz * 0.4);
          final dist = (18 + 26 * ((i * 0.37) % 1.0)) * b.size * Curves.easeOutCubic.transform(k);
          final up = 40 * b.size * math.sin(k * math.pi) * (0.6 + ((i * 0.53) % 0.6));
          final c = g + out * dist * u - Offset(0, up * u);
          pc.color = (i.isEven ? const Color(0xFF8E897F) : const Color(0xFF6E695F)).withAlpha(((1 - k * k) * 255).round());
          canvas.save();
          canvas.translate(c.dx, c.dy);
          canvas.rotate(k * 8 + i);
          canvas.drawRect(Rect.fromCenter(center: Offset.zero, width: 6 * u * b.size, height: 4 * u * b.size), pc);
          canvas.restore();
        }
        if (b.kind == 'rubble') _glow(canvas, g - Offset(0, 10 * _up), 40 * u * b.size, Color.fromRGBO(220, 210, 190, 0.5 * (1 - k)));
      case 'spark':
        final p = Paint()
          ..strokeWidth = 2.2
          ..strokeCap = StrokeCap.round
          ..color = Color.fromRGBO(255, 244, 200, 1 - k);
        final c = g - Offset(0, 8 * _up);
        for (var i = 0; i < 6; i++) {
          final a = i * math.pi / 3 + b.x;
          final d0 = 4 + 10 * k, d1 = 8 + 16 * k;
          canvas.drawLine(c + Offset(math.cos(a) * d0, math.sin(a) * d0) * u, c + Offset(math.cos(a) * d1, math.sin(a) * d1) * u, p);
        }
      case 'glow':
        _glow(canvas, g - Offset(0, 6 * _up), (8 + 18 * k) * u, Color.fromRGBO(159, 240, 218, 0.7 * (1 - k)));
      case 'flash':
        _glow(canvas, g - Offset(0, 4 * _up), (10 + b.size * k) * u * 1.4, Color.fromRGBO(255, 236, 170, 0.8 * (1 - k)));
      case 'pulse':
        final rr = b.size * Curves.easeOut.transform(k);
        canvas.drawOval(_ellipse(b.x, b.z, rr), Paint()..color = Color.fromRGBO(159, 240, 218, 0.28 * (1 - k)));
        canvas.drawOval(
            _ellipse(b.x, b.z, rr),
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 4
              ..color = Color.fromRGBO(220, 255, 245, 0.9 * (1 - k)));
      case 'spores':
        for (var i = 0; i < 6; i++) {
          final a = i * 1.05 + b.x;
          final rr = b.size * (0.3 + 0.7 * k);
          canvas.drawOval(_ellipse(b.x + math.cos(a) * rr * 0.5, b.z + math.sin(a) * rr * 0.5, rr * 0.45),
              Paint()..color = Color.fromRGBO(162, 123, 214, 0.4 * (1 - k)));
        }
      case 'sweep':
        final a0 = math.atan2(b.dx, b.dz);
        final pts = <(double, double)>[(b.x, b.z)];
        for (var i = 0; i <= 12; i++) {
          final a = a0 - 1.15 + 2.3 * i / 12;
          pts.add((b.x + math.sin(a) * b.size, b.z + math.cos(a) * b.size));
        }
        canvas.drawPath(_poly(pts), Paint()..color = Color.fromRGBO(255, 235, 220, 0.45 * (1 - k)));
      case 'dust':
        for (var i = 0; i < 5; i++) {
          final a = i * 1.3 + b.z;
          final rr = (6 + 14 * k) * b.size;
          canvas.drawOval(_ellipse(b.x + math.cos(a) * rr * 0.6, b.z + math.sin(a) * rr * 0.6, rr * 0.35),
              Paint()..color = Color.fromRGBO(186, 160, 120, 0.45 * (1 - k)));
        }
      case 'heal':
        final p = Paint()..color = Color.fromRGBO(140, 230, 120, 1 - k);
        for (var i = 0; i < 5; i++) {
          final c = g + Offset(math.sin(i * 2.3) * 12 * u, -(10 + 26 * k + i * 4) * _up);
          canvas.drawRect(Rect.fromCenter(center: c, width: 2.4 * u, height: 7 * u), p);
          canvas.drawRect(Rect.fromCenter(center: c, width: 7 * u, height: 2.4 * u), p);
        }
      case 'motes':
        for (var i = 0; i < 14 * b.size; i++) {
          final a = i * 2.39;
          final rr = (6 + 18 * k) * u * b.size;
          final c = g + Offset(math.cos(a) * rr, -(6 + 30 * k * (0.6 + (i % 4) * 0.2)) * _up * b.size + math.sin(a) * rr * 0.4);
          final col = Color.lerp(const Color(0xFFC8B1E4), const Color(0xFFFFE9A6), k)!;
          canvas.drawCircle(c, (2.2 - k) * u * 1.2, Paint()..color = col.withAlpha(((1 - k) * 255).round()));
        }
      case 'purify':
        for (var i = 0; i < 3; i++) {
          final kk = ((k * 1.4) - i * 0.18).clamp(0.0, 1.0);
          canvas.drawOval(
              _ellipse(b.x, b.z, 20 + 90 * kk),
              Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = 6 * (1 - kk)
                ..color = Color.fromRGBO(255, 245, 200, 0.8 * (1 - kk)));
        }
        _glow(canvas, g - Offset(0, 30 * _up), (40 + 60 * k) * u, Color.fromRGBO(255, 248, 220, 0.75 * (1 - k)));
      case 'roots':
        final up = k < 0.25 ? k / 0.25 : (1 - (k - 0.25) / 0.75);
        final p = Paint()..color = const Color(0xFF4A3550);
        for (var i = 0; i < 6; i++) {
          final a = i * 1.05 + b.x;
          final c = s._toScreen(b.x + math.cos(a) * b.size * 0.55, b.z + math.sin(a) * b.size * 0.55);
          final h = (10 + (i % 3) * 4) * _up * up;
          canvas.drawPath(Path()..moveTo(c.dx - 3.5 * u, c.dy)..lineTo(c.dx + math.cos(a) * 3, c.dy - h)..lineTo(c.dx + 3.5 * u, c.dy)..close(), p);
        }
      case 'stars':
        // the dazed stars ride on the foe's own drawing (see _foe); a small burst marks the moment
        if (k < 0.2) _star(canvas, g - Offset(0, 14 * _up * b.size), 8 * u * (1 - k * 4), const Color(0xFFFFE16E));
      case 'impact':
        {
          // where a blow lands: a white flash, a ring, and spikes thrown out the way it hit
          final col = _tint(b.tag);
          final c = g - Offset(0, 9 * _up * b.size);
          final a0 = math.atan2(b.dz * 0.6, b.dx);
          final grow = Curves.easeOut.transform(k);
          _glow(canvas, c, (8 + 14 * grow) * u * b.size, col.withAlpha(((1 - k) * 200).round()));
          canvas.drawCircle(c, (4 + 20 * grow) * u * b.size, Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3.5 * (1 - k)
            ..color = col.withAlpha(((1 - k) * 230).round()));
          final sp = Paint()
            ..strokeCap = StrokeCap.round
            ..strokeWidth = 3 * (1 - k) * b.size
            ..color = Colors.white.withAlpha(((1 - k) * 240).round());
          for (var i = 0; i < 6; i++) {
            final a = a0 + (i - 2.5) * 0.46 + 0.2 * math.sin(i * 2.3 + b.x);
            final ln = (9 + 22 * grow + (i % 2) * 6) * u * b.size;
            final from = c + Offset(math.cos(a), math.sin(a)) * (4 + 10 * grow) * u * b.size;
            canvas.drawLine(from, from + Offset(math.cos(a), math.sin(a)) * ln, sp);
          }
        }
      case 'lines':
        {
          // speed lines flung out from your Evochi: a signature move, a pulse
          final col = _tint(b.tag);
          final c = g - Offset(0, 12 * _up);
          final sp = Paint()
            ..strokeCap = StrokeCap.round
            ..color = col.withAlpha(((1 - k) * 200).round());
          for (var i = 0; i < 18; i++) {
            final a = i * math.pi * 2 / 18 + 0.17 * math.sin(i * 3.1 + b.x);
            final r0 = (b.size * 0.25 + b.size * 0.6 * k) * u, r1 = r0 + (b.size * 0.25 + 10) * u * (1 - 0.5 * k);
            sp.strokeWidth = (2.6 - 1.8 * k) * (i % 3 == 0 ? 1.6 : 1);
            canvas.drawLine(c + Offset(math.cos(a) * r0, math.sin(a) * r0 * 0.6), c + Offset(math.cos(a) * r1, math.sin(a) * r1 * 0.6), sp);
          }
        }
      case 'gather':
        {
          // light drawn in from all round into your Evochi as a signature move winds up
          final col = _tint(b.tag);
          final c = g - Offset(0, 14 * _up);
          for (var i = 0; i < 12; i++) {
            final a = i * math.pi * 2 / 12 + k * 1.4 + b.x;
            final r0 = (60 - 52 * k) * u * b.size;
            final at = c + Offset(math.cos(a) * r0, math.sin(a) * r0 * 0.6);
            canvas.drawCircle(at, (1.5 + 2.5 * k) * u, Paint()..color = col.withAlpha(((0.4 + 0.6 * k) * 230).round()));
          }
          canvas.drawOval(Rect.fromCenter(center: c, width: (70 - 60 * k) * 2 * u * b.size, height: (70 - 60 * k) * 1.2 * u * b.size), Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5 + 3 * k
            ..color = col.withAlpha(((0.3 + 0.7 * k) * 200).round()));
          _glow(canvas, c, (6 + 26 * k) * u, col.withAlpha((k * 200).round()));
        }
      case 'slash':
        final a0 = math.atan2(b.dz, b.dx);
        canvas.drawArc(Rect.fromCenter(center: g - Offset(0, 8 * _up), width: 30 * u, height: 18 * u), a0 - 1.0 + 1.4 * k, 1.2, false,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 3
              ..strokeCap = StrokeCap.round
              ..color = Color.fromRGBO(255, 240, 220, 1 - k));
      case 'launch':
        // the third Pounce: a ring of dust and a white flash where it lands
        canvas.drawOval(
            _ellipse(b.x, b.z, (10 + 26 * Curves.easeOut.transform(k)) * b.size),
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 5 * (1 - k)
              ..color = Color.fromRGBO(255, 248, 225, 0.85 * (1 - k)));
        _glow(canvas, g - Offset(0, 8 * _up), (10 + 20 * k) * u * b.size, Color.fromRGBO(255, 250, 230, 0.7 * (1 - k)));
      case 'ember':
        final p = Paint()..color = Color.lerp(const Color(0xFFFFD25E), const Color(0xFFE2522F), k)!.withAlpha(((1 - k) * 230).round());
        for (var i = 0; i < 3; i++) {
          final c = g + Offset(math.sin(i * 2.1 + b.x) * 5 * u, -(8 + 22 * k + i * 4) * _up);
          canvas.drawCircle(c, (2.6 - 1.6 * k) * u, p);
        }
      case 'buff':
        // a brew takes hold: a rising ring of light round your Evochi
        for (var i = 0; i < 2; i++) {
          final kk = (k - i * 0.25).clamp(0.0, 1.0);
          canvas.drawOval(
              _ellipse(b.x, b.z, 14 + 10 * kk),
              Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = 3 * (1 - kk)
                ..color = Color.fromRGBO(200, 245, 255, 0.9 * (1 - kk)));
        }
        _glow(canvas, g - Offset(0, (10 + 30 * k) * _up), 14 * u, Color.fromRGBO(220, 250, 255, 0.6 * (1 - k)));
      case 'toss':
        final tx = b.x + b.dx * k, tz = b.z + b.dz * k;
        final c = s._toScreen(tx, tz) - Offset(0, (12 + 30 * 4 * k * (1 - k)) * _up);
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: c, width: 5 * u, height: 8 * u), const Radius.circular(2)),
            Paint()..color = const Color(0xFF8FE3D0));
    }
  }

  void _glint(Canvas canvas, Offset g) {
    final t = rm ? 0.5 : (math.sin(s._t * 3) + 1) / 2;
    final p = Paint()
      ..color = Color.lerp(const Color(0x66FFF3B0), const Color(0xEEFFF3B0), t)!
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    canvas.drawCircle(g, 5 + 3 * t, p);
    _star(canvas, g, 7 + 4 * t, const Color(0xFFFFFDF0));
  }

  void _floater(Canvas canvas, Floater f) {
    final k = f.t / f.ttl;
    final big = f.kind == 'crit' || f.kind == 'alert';
    final col = switch (f.kind) {
      'crit' => const Color(0xFFFFB13B),
      'hurt' => const Color(0xFFFF6B5E),
      'heal' => const Color(0xFF8CE678),
      'loot' => const Color(0xFFFFE08A),
      'alert' => const Color(0xFFFFE16E),
      'info' => const Color(0xFFFFF3DC),
      _ => Colors.white,
    };
    final size = (big ? 22.0 : (f.kind == 'info' || f.kind == 'loot' ? 13.0 : 17.0)) * (k < 0.15 ? 0.7 + 2 * k : 1.0);
    final style = EvochiText.number.copyWith(fontSize: size, height: 1.0);
    final tp = TextPainter(
      text: TextSpan(
          text: f.text,
          style: style.copyWith(
              foreground: Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = 3.5
                ..color = Color.fromRGBO(43, 28, 18, 1 - k * k))),
      textDirection: TextDirection.ltr,
    )..layout();
    final tf = TextPainter(text: TextSpan(text: f.text, style: style.copyWith(color: col.withAlpha(((1 - k * k) * 255).round()))), textDirection: TextDirection.ltr)
      ..layout();
    final g = s._toScreen(f.x, f.z) - Offset(tp.width / 2 + (f.kind == 'hurt' ? -10 : 0), (f.kind == 'alert' ? 44 : 30) * s._u / 2.7 + 28 * k + tp.height);
    tp.paint(canvas, g);
    tf.paint(canvas, g);
  }

  void _bubble(Canvas canvas, Actor sher, String b) {
    final g = s._toScreen(sher.x, sher.z);
    final tp = TextPainter(
      text: TextSpan(text: b, style: EvochiText.tag.copyWith(color: EvochiColor.ink, fontSize: 13)),
      textDirection: TextDirection.ltr,
      maxLines: 3,
    )..layout(maxWidth: 190);
    final top = g.dy - s._sherArt!.gy * s._u / walkerDrawScale - tp.height - 16;
    final hi = math.max(tp.width / 2 + 16, s._view.width - tp.width / 2 - 16);
    final cx = g.dx.clamp(tp.width / 2 + 16, hi).toDouble();
    final r = RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(cx, top + tp.height / 2), width: tp.width + 20, height: tp.height + 14),
        const Radius.circular(12));
    canvas.drawRRect(r.shift(const Offset(0, 2)), Paint()..color = const Color(0x55000000));
    canvas.drawRRect(r, Paint()..color = const Color(0xFFFFF7E8));
    canvas.drawRRect(
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = const Color(0xFF3B2923));
    tp.paint(canvas, Offset(cx - tp.width / 2, top));
  }

  void _fire(Canvas canvas, Offset g) {
    final t = s._t;
    final k = s._u / 2.7;
    final flick = rm ? 0.5 : (math.sin(t * 13) + math.sin(t * 7.3 + 1) + 2) / 4;
    canvas.drawCircle(
        g - Offset(0, 4 * k),
        (16 + 4 * flick) * k,
        Paint()
          ..color = const Color(0x55FFB347)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 10 * k));
    for (var i = 0; i < 3; i++) {
      final h = (12 + 6 * flick - i * 3.5) * k;
      final w = (7 - i * 1.8) * k;
      final c = [const Color(0xFFE9592C), const Color(0xFFFF9A3A), const Color(0xFFFFE08A)][i];
      final sway = rm ? 0.0 : math.sin(t * 9 + i) * 1.2 * k;
      canvas.drawPath(
          Path()
            ..moveTo(g.dx - w, g.dy - 2 * k)
            ..quadraticBezierTo(g.dx - w * 0.6, g.dy - h * 0.6, g.dx + sway, g.dy - h - 2 * k)
            ..quadraticBezierTo(g.dx + w * 0.6, g.dy - h * 0.6, g.dx + w, g.dy - 2 * k)
            ..close(),
          Paint()..color = c);
    }
    if (!rm) {
      for (var i = 0; i < 5; i++) {
        final ph = (t * 0.7 + i / 5) % 1.0;
        final x = g.dx + math.sin(i * 2.1 + t * 2) * 6 * k;
        final y = g.dy - (14 + ph * 34) * k;
        canvas.drawCircle(Offset(x, y), 1.4 * k, Paint()..color = Color.fromRGBO(255, 214, 120, 1 - ph));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _MapPainter old) => true;
}

// ====================================================================== the HUD
/// The party: your Evochi first (it leads), then Sher. Raid HP (green) and Stamina (blue); statuses.
/// Text over the world: light, with a soft dark halo so it reads on grass and shade alike.
const _hudShadow = [Shadow(color: Color(0xCC0B120A), blurRadius: 6), Shadow(color: Color(0x990B120A), blurRadius: 2, offset: Offset(0, 1))];
TextStyle _hudText(double size, [Color color = const Color(0xFFFFF6E4)]) =>
    EvochiText.tag.copyWith(color: color, fontSize: size, shadows: _hudShadow, height: 1.15);

/// A round, see-through button for the HUD (the back arrow, the minimap's frame).
BoxDecoration _glass(double alpha) => BoxDecoration(
      shape: BoxShape.circle,
      color: Color.fromRGBO(12, 20, 10, alpha),
      border: Border.all(color: const Color(0x59FFF6E4), width: 1.5),
    );

/// The party: round portraits, Raid HP as a ring round each (stamina an inner arc on your Evochi's).
class _PartyPanel extends StatelessWidget {
  const _PartyPanel({required this.state});
  final _WildsScreenState state;
  @override
  Widget build(BuildContext context) {
    final c = context.watch<GameController>();
    final pet = c.state.pet;
    return ValueListenableBuilder<int>(
      valueListenable: state._repaint,
      builder: (context, _, child) {
        final r = state._raid!;
        final sher = r.party ? r.sher : null;
        return Semantics(
          label: 'Party: ${pet?.name ?? 'your Evochi'} ${r.pet.hp.ceil()} of ${r.pet.maxHp.round()} Raid HP, stamina ${r.stamina.round()}'
              '${sher != null ? ', Sher ${sher.hp.ceil()} HP' : ''}',
          child: ExcludeSemantics(
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              if (pet != null)
                _Portrait(
                  size: 52,
                  hp: r.pet.maxHp <= 0 ? 0 : r.pet.hp / r.pet.maxHp,
                  stamina: r.stamina / 100,
                  tag: r.pet.slowT > 0 ? 'Spored' : null,
                  child: EncFace.pet(pet, size: 42),
                ),
              if (sher != null) ...[
                const SizedBox(width: 4),
                _Portrait(
                  size: 40,
                  hp: sher.maxHp <= 0 ? 0 : sher.hp / sher.maxHp,
                  tag: r.sherWinded > 0 ? 'Winded' : null,
                  child: const SherFace(size: 31),
                ),
              ],
              // the charm it wears, with its rank
              if (r.charm != null) ...[
                const SizedBox(width: 6),
                Tooltip(
                  message: '${item(r.charm!).name} (Rank ${charms.rankLabel(r.charmRank)}): ${charms.charmDefs[r.charm]?.short ?? ''}',
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0x55000000), border: Border.all(color: const Color(0xFFE9C46A), width: 1.5)),
                    alignment: Alignment.center,
                    child: Stack(clipBehavior: Clip.none, alignment: Alignment.center, children: [
                      ItemImage(r.charm!, size: 21),
                      Positioned(
                        right: -6,
                        bottom: -5,
                        child: Text(charms.rankLabel(r.charmRank),
                            style: EvochiText.tiny.copyWith(color: const Color(0xFFFFE9A8), fontSize: 9, fontWeight: FontWeight.w900, shadows: const [Shadow(blurRadius: 3)])),
                      ),
                    ]),
                  ),
                ),
              ],
              // the brews at work: each one's bottle with its time running down round it
              if (r.buffs.isNotEmpty) ...[
                const SizedBox(width: 6),
                Wrap(spacing: 3, runSpacing: 3, children: [
                  for (final e in r.buffs.entries) _BuffChip(id: e.key, left: e.value),
                ]),
              ],
            ]),
          ),
        );
      },
    );
  }
}

/// A brew at work: its bottle in a ring that empties as the buff runs out.
class _BuffChip extends StatelessWidget {
  const _BuffChip({required this.id, required this.left});
  final String id;
  final double left;
  @override
  Widget build(BuildContext context) {
    final def = buffDefs[id];
    final brew = w.wildsBrews.entries.where((e) => e.value == id).map((e) => e.key).firstOrNull;
    final f = def == null ? 0.0 : (left / def.secs).clamp(0.0, 1.0);
    return Tooltip(
      message: def == null ? id : '${def.name}: ${def.text}',
      child: SizedBox(
        width: 26,
        height: 26,
        child: Stack(alignment: Alignment.center, children: [
          CircularProgressIndicator(value: f, strokeWidth: 2.5, backgroundColor: const Color(0x55000000), valueColor: const AlwaysStoppedAnimation(Color(0xFFBFF6FF))),
          if (brew != null) ItemImage(brew, size: 20),
        ]),
      ),
    );
  }
}

class _Portrait extends StatelessWidget {
  const _Portrait({required this.size, required this.hp, required this.child, this.stamina, this.tag});
  final double size, hp;
  final double? stamina;
  final String? tag;
  final Widget child;
  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size + (tag != null ? 12 : 0),
        child: Stack(clipBehavior: Clip.none, alignment: Alignment.topCenter, children: [
          SizedBox(width: size, height: size, child: CustomPaint(painter: _RingPainter(hp, stamina))),
          Positioned(top: (size - (size - 10)) / 2, child: SizedBox(width: size - 10, height: size - 10, child: Center(child: child))),
          if (tag != null)
            Positioned(
              top: size - 6,
              child: Container(
                padding: const EdgeInsets.fromLTRB(5, 0, 5, 1),
                decoration: BoxDecoration(color: tag == 'Spored' ? const Color(0xE67A5BB0) : const Color(0xE68A6A4A), borderRadius: BorderRadius.circular(6)),
                child: Text(tag!, style: EvochiText.tag.copyWith(color: Colors.white, fontSize: 9.5, height: 1.3)),
              ),
            ),
        ]),
      );
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.hp, this.stamina);
  final double hp;
  final double? stamina;
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2 - 2.5;
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.5
      ..color = const Color(0x8C0B120A);
    canvas.drawCircle(c, r, track);
    final f = hp.clamp(0.0, 1.0);
    final col = f < 0.3 ? const Color(0xFFF0685A) : (f < 0.6 ? const Color(0xFFE8C04E) : const Color(0xFF7DD456));
    canvas.drawArc(
        Rect.fromCircle(center: c, radius: r),
        -math.pi / 2,
        2 * math.pi * f,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4.5
          ..strokeCap = StrokeCap.round
          ..color = col);
    final st = stamina;
    if (st != null) {
      // stamina: a thin arc along the bottom, inside the ring
      final rr = r - 4.5;
      final s = st.clamp(0.0, 1.0);
      final arc = Rect.fromCircle(center: c, radius: rr);
      canvas.drawArc(arc, math.pi * 0.2, math.pi * 0.6, false, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = const Color(0x990B120A));
      canvas.drawArc(arc, math.pi * 0.8, -math.pi * 0.6 * s, false, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..color = s < 0.2 ? const Color(0xFF8FA6B8) : const Color(0xFF5CB8F0));
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.hp != hp || old.stamina != stamina;
}

class _Bar extends StatelessWidget {
  const _Bar({required this.width, required this.color, this.frac = 1, this.height = 7});
  final double width, height, frac;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
        width: width,
        height: height,
        padding: const EdgeInsets.all(1),
        decoration: BoxDecoration(color: const Color(0xB31A120A), borderRadius: BorderRadius.circular(height)),
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: frac.clamp(0.0, 1.0),
          heightFactor: 1,
          child: DecoratedBox(decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(height))),
        ),
      );
}

/// The objective as a line of text that shows when it changes (and on arrival), then fades; while
/// the guardian fights, its health.
class _TopCenter extends StatelessWidget {
  const _TopCenter({required this.state});
  final _WildsScreenState state;
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
        valueListenable: state._repaint,
        builder: (context, _, child) {
          final r = state._raid!;
          final b = r.boss;
          if (b != null && (r.bossState == BossState.intro || r.bossState == BossState.fight) && !b.calm) {
            return _BossBar(boss: b);
          }
          final sent = r.sentinel;
          if (sent != null && !sent.calm && sent.st != FoeState.dormant) {
            return _SentinelBar(sentinel: sent, shield: r.sentinelShield / r.sentinelShieldMax);
          }
          final String text;
          final deep = state._map!.depth != null;
          if (r.storyBeat == 'trust' && !r.storyDone) {
            text = r.pet.dist(r.petalune ?? r.pet) < 160 ? 'Earn Petalune\'s trust  ${r.trust.round()}%' : 'Find what waits in the ruins';
          } else if (r.storyBeat == 'sprout' && !r.storyDone) {
            text = 'Restore the Hollow Sprout';
          } else if (r.calmed < r.foeTotal) {
            text = 'Calm the Hollow creatures  ${r.calmed}/${r.foeTotal}';
          } else if (deep) {
            text = 'The way down is open';
          } else if (r.bossState != BossState.calm) {
            text = 'Face the guardian at the old gate';
          } else {
            text = 'The Thicket is calm';
          }
          if (text != state._objText) {
            state._objText = text;
            state._objAt = state._t;
          }
          final on = state._t - state._objAt < 5.5 || state._combatT > 0;
          return AnimatedOpacity(
            opacity: on ? 1 : 0,
            duration: const Duration(milliseconds: 900),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(state._map!.depth == null ? state._map!.name.toUpperCase() : '${state._map!.name.toUpperCase()} · ${state._map!.floor}',
                  style: _hudText(10, const Color(0xCCFFE7B8)).copyWith(letterSpacing: 1.6)),
              if (deep && (r.surge || state._map!.mods.isNotEmpty))
                Text(
                    [if (r.surge) 'HOLLOW SURGE', for (final id in state._map!.mods) floorModDefs[id]!.$1.toUpperCase()].join(' · '),
                    style: _hudText(9, r.surge ? const Color(0xFFD9B8FF) : const Color(0xAAE8F0C8)).copyWith(letterSpacing: 1.2)),
              const SizedBox(height: 1),
              Text(text, textAlign: TextAlign.center, style: _hudText(14)),
            ]),
          );
        },
      );
}

class _BossBar extends StatelessWidget {
  const _BossBar({required this.boss});
  final Boss boss;
  @override
  Widget build(BuildContext context) {
    final f = boss.hpFrac;
    final col = boss.stage >= 3 ? const Color(0xFFE0526B) : (boss.stage == 2 ? const Color(0xFFB878E8) : const Color(0xFF9B7BD6));
    return Semantics(
      label: 'Briarback, ${(f * 100).round()} percent',
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            Text('Briarback', style: _hudText(14)),
            const SizedBox(width: 6),
            Text(boss.stage >= 3 ? 'Enraged' : 'Guardian of the Thicket', style: _hudText(11, const Color(0xFFD9C2FF))),
          ]),
          const SizedBox(height: 4),
          LayoutBuilder(builder: (context, cons) {
            final w = math.min(cons.maxWidth, 280.0);
            return SizedBox(
              width: w,
              height: 9,
              child: Stack(children: [
                _Bar(width: w, height: 9, frac: f, color: col),
                for (final n in const [0.6, 0.3])
                  Positioned(left: w * n - 1, top: 1, bottom: 1, child: Container(width: 2, color: const Color(0xCCFFF3DC))),
              ]),
            );
          }),
        ]),
      ),
    );
  }
}

class _SentinelBar extends StatelessWidget {
  const _SentinelBar({required this.sentinel, required this.shield});
  final Foe sentinel;
  final double shield; // 0..1 while its Hollow shield is up
  @override
  Widget build(BuildContext context) {
    final f = sentinel.hpFrac;
    return Semantics(
      label: 'The Forgotten Sentinel, ${(f * 100).round()} percent${shield > 0 ? ', shielded' : ''}',
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            Text('The Forgotten Sentinel', style: _hudText(14)),
            const SizedBox(width: 6),
            Text(shield > 0 ? 'Shielded' : (f < 0.5 ? 'Waking fury' : 'Guardian of the Gate'), style: _hudText(11, const Color(0xFFD9C2FF))),
          ]),
          const SizedBox(height: 4),
          LayoutBuilder(builder: (context, cons) {
            final w = math.min(cons.maxWidth, 280.0);
            return SizedBox(
              width: w,
              height: shield > 0 ? 14 : 9,
              child: Stack(children: [
                _Bar(width: w, height: 9, frac: f, color: f < 0.5 ? const Color(0xFFE0526B) : const Color(0xFF9B7BD6)),
                for (final n in const [0.66, 0.33])
                  Positioned(left: w * n - 1, top: 1, height: 7, child: Container(width: 2, color: const Color(0xCCFFF3DC))),
                if (shield > 0)
                  Positioned(left: 0, top: 10, child: _Bar(width: w, height: 4, frac: shield, color: const Color(0xFFC8B1E4))),
              ]),
            );
          }),
        ]),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 9),
        decoration: Kit.parchment(radius: 14),
        child: Text(text, style: EvochiText.cardTitle.copyWith(fontSize: 15)),
      );
}

/// The action pad, icons only on see-through discs: Pounce (big; hold to keep at it), Dodge, Glow Bolt
/// and Lumen Pulse (their cooldowns sweep round), a berry. Running is the stick pushed to its rim.
/// The combat pad, bottom right: a big Pounce with the stamina ringed round it, the moves on a quarter
/// circle round it (Dodge, Bolt, Pulse), an Elder's signature move above them with its charge ring, and
/// the things to eat and drink in a column to the left. Every button is named under it.
class _CombatPad extends StatelessWidget {
  const _CombatPad({required this.state});
  final _WildsScreenState state;

  static const _w = 236.0, _h = 246.0;
  static const _pounce = Offset(186, 192), _dodge = Offset(88, 192), _bolt = Offset(114, 122), _pulse = Offset(186, 94), _sig = Offset(124, 38);
  static const _berry = Offset(28, 192), _brew = Offset(28, 130);

  Widget _at(Offset c, double size, Widget child, {double ring = 0}) =>
      Positioned(left: c.dx - size / 2 - ring, top: c.dy - size / 2 - ring, child: child);

  @override
  Widget build(BuildContext context) {
    final c = context.watch<GameController>();
    final healId = w.nextHealItem(c.state);
    final heals = w.healItemCount(c.state);
    final brews = w.ownedBrews(c.state);
    final s = state;
    final r = s._raid!;
    return ValueListenableBuilder<int>(
      valueListenable: s._repaint,
      builder: (context, _, child) {
        final st = r.stamina;
        // the pad is quieter out of a fight
        final calm = s._combatT <= 0;
        return AnimatedOpacity(
          opacity: calm ? 0.78 : 1,
          duration: const Duration(milliseconds: 400),
          child: SizedBox(
            width: _w,
            height: _h,
            child: Stack(clipBehavior: Clip.none, children: [
              // stamina: a green ring round the Pounce
              _at(_pounce, 86 + 14, CustomPaint(size: const Size(100, 100), painter: _StaminaRing(st / 100.0))),
              _at(
                _pounce,
                86,
                ActionButton(
                  label: 'Pounce',
                  hint: 'Tap to strike, hold to keep striking',
                  icon: 'paw',
                  size: 86,
                  palette: KitButtonPalette.gold,
                  dim: st < 5,
                  onDown: () {
                    s._padHeld = true;
                    s._press('attack');
                    s._held['attack'] = 0.3;
                  },
                  onUp: () {
                    s._padHeld = false;
                    s._held.remove('attack');
                  },
                ),
              ),
              _at(_dodge, 56, ActionButton(label: 'Dodge', icon: 'swirl', size: 56, palette: KitButtonPalette.green, dim: st < 20, onDown: () => s._press('dodge'))),
              _at(
                _bolt,
                56,
                ActionButton(
                  label: 'Bolt',
                  semantic: 'Glow Bolt',
                  icon: 'energy',
                  size: 56,
                  palette: _mint,
                  cooldown: r.boltCd / 1.0,
                  dim: st < 18,
                  onDown: () => s._press('bolt'),
                ),
              ),
              _at(
                _pulse,
                56,
                ActionButton(
                  label: 'Pulse',
                  semantic: 'Lumen Pulse',
                  icon: 'sun',
                  size: 56,
                  palette: _mint,
                  cooldown: r.pulseCd / 7.0,
                  dim: st < 34,
                  onDown: () => s._press('pulse'),
                ),
              ),
              // an Elder's signature move: fills from perfect dodges, counters and close calls
              if (r.stage >= 3)
                _at(
                  _sig,
                  64,
                  ActionButton(
                    label: r.sigName,
                    semantic: r.sigReady ? '${r.sigName}: ready' : '${r.sigName}: ${r.sig.round()} percent charged',
                    icon: 'star',
                    size: 64,
                    palette: r.sigReady ? KitButtonPalette.gold : KitButtonPalette.plum,
                    charge: r.sig / 100,
                    ready: r.sigReady,
                    dim: !r.sigReady,
                    badge: r.sigReady ? '!' : null,
                    onDown: () => s._press('signature'),
                  ),
                  ring: 6,
                ),
              _at(
                _berry,
                46,
                ActionButton(
                  label: heals > 0 ? 'Eat' : 'No food',
                  semantic: heals > 0 ? 'Eat a berry, $heals left' : 'No berries',
                  icon: 'potion',
                  image: healId,
                  badge: heals > 0 ? '$heals' : null,
                  size: 46,
                  palette: KitButtonPalette.cream,
                  cooldown: s._itemCd / 2.5,
                  dim: heals == 0,
                  onDown: () => s._press('item'),
                ),
              ),
              // the brews: a flask; with more than one kind, it opens a little shelf of them
              _at(
                _brew,
                46,
                ActionButton(
                  label: brews.isEmpty ? 'No brew' : 'Drink',
                  semantic: brews.isEmpty ? 'No brews' : 'Drink a brew',
                  icon: 'potion',
                  image: brews.isEmpty ? null : brews.first,
                  badge: brews.length > 1 ? '${brews.length}' : null,
                  size: 46,
                  palette: KitButtonPalette.cream,
                  cooldown: s._brewCd / 1.5,
                  dim: brews.isEmpty,
                  onDown: () => s._brewTap(brews),
                ),
              ),
            ]),
          ),
        );
      },
    );
  }
}

class _BrewShelf extends StatelessWidget {
  const _BrewShelf({required this.brews, required this.onPick});
  final List<String> brews;
  final ValueChanged<String> onPick;
  @override
  Widget build(BuildContext context) {
    final c = context.watch<GameController>();
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(color: const Color(0xCC1B2A1A), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0x99BFF6FF), width: 1.5)),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final id in brews)
          Semantics(
            button: true,
            label: '${catalog[id]?.name ?? id}, ${buffDefs[w.wildsBrews[id]]?.text ?? ''}',
            excludeSemantics: true,
            child: GestureDetector(
              onTap: () => onPick(id),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  ItemImage(id, size: 30),
                  const SizedBox(width: 6),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    Text('${buffDefs[w.wildsBrews[id]]?.name ?? ''}${coatings.contains(w.wildsBrews[id]) ? ' coating' : ''} ×${ge.ownedQty(c.state, id)}',
                        style: EvochiText.tag.copyWith(color: const Color(0xFFFFF6E4), fontSize: 12)),
                    Text(catalog[id]?.name ?? id, style: EvochiText.tiny.copyWith(color: const Color(0xCCFFF6E4), fontSize: 10.5)),
                  ]),
                ]),
              ),
            ),
          ),
      ]),
    );
  }
}

/// Lumen: a mint button for the light moves.
const _mint = KitButtonPalette(
  colors: [Color(0xFFE6FBF5), Color(0xFFBFF0E2), Color(0xFF9FE3D0)],
  stops: [0, 0.5, 1],
  border: Color(0xFF2E6E62),
  edge: Color(0xFF235449),
  shade: Color(0x66318A78),
  drop: Color(0x40204A40),
  pressed: [Color(0xFFCFF2E8), Color(0xFF8FD3BF)],
  pressShade: Color(0x59204A40),
  textShadow: Color(0x66FFFFFF),
);

/// Stamina as a ring round the Pounce: green, draining clockwise, amber when it is nearly spent.
class _StaminaRing extends CustomPainter {
  _StaminaRing(this.frac);
  final double frac;
  @override
  void paint(Canvas canvas, Size size) {
    final r = (Offset.zero & size).deflate(2);
    canvas.drawOval(r, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..color = const Color(0x992A1D10));
    if (frac <= 0) return;
    canvas.drawArc(r, -math.pi / 2, 2 * math.pi * frac.clamp(0.0, 1.0), false, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round
      ..color = frac < 0.25 ? const Color(0xFFF2B35A) : const Color(0xFFA9E07A));
  }

  @override
  bool shouldRepaint(_StaminaRing old) => old.frac != frac;
}

/// Sher's face in a round frame, from his villager sprite (centred a little up and left of the face
/// point: his head turns to the right, and his ears stay in frame).
class SherFace extends StatelessWidget {
  const SherFace({super.key, this.size = 40});
  final double size;
  @override
  Widget build(BuildContext context) {
    final sz = villageArt.npcSize('sher');
    final f = villageArt.npcFace('sher');
    final k = size * 1.08 / sz.width;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFFFFF0DE), border: Border.all(color: const Color(0xFFEE9C47), width: 2)),
      child: ClipOval(
        child: Stack(clipBehavior: Clip.hardEdge, children: [
          Positioned(
            left: size / 2 - (f.dx - 0.06 * sz.width) * k,
            top: size * 0.5 - (f.dy - 0.06 * sz.height) * k,
            width: sz.width * k,
            height: sz.height * k,
            child: Image.asset(villageArt.npc('sher'), fit: BoxFit.fill, filterQuality: FilterQuality.medium, excludeFromSemantics: true),
          ),
        ]),
      ),
    );
  }
}

/// What you can do with what's near (Talk, Look, Read, Spar...): a small label over it, tap to do it.
class _NearLabel extends StatelessWidget {
  const _NearLabel({required this.state});
  final _WildsScreenState state;
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
        valueListenable: state._repaint,
        builder: (context, _, child) {
          final s = state;
          final r = s._raid!;
          final near = s._near;
          final talk = (s._nearSher && (near == null || !r.party)) || s._nearBoss || s._nearFriend;
          // (positioned even when empty: a bare box in the Stack would size it to nothing)
          if (!talk && near == null) return const Positioned(left: 0, top: 0, child: SizedBox.shrink());
          final String label;
          final Offset at;
          final pl = r.petalune;
          if (s._nearFriend && pl != null) {
            label = 'Petalune';
            at = s._toScreen(pl.x, pl.z) - Offset(0, 40 * s._u / 2.7);
          } else if (s._nearBoss) {
            label = 'Spar';
            at = s._toScreen(r.boss!.x, r.boss!.z) - Offset(0, 48 * s._u / 2.7);
          } else if (talk) {
            label = r.party ? 'Chat' : 'Talk';
            at = s._toScreen(r.sher!.x, r.sher!.z) - Offset(0, 62 * s._u / 2.7);
          } else {
            label = near!.label;
            at = s._toScreen(near.x, near.z) - Offset(0, 30 * s._u / 2.7);
          }
          return Positioned(
            left: at.dx - 60,
            top: at.dy - 30,
            width: 120,
            height: 34,
            child: Center(
              child: Semantics(
                button: true,
                label: label,
                child: GestureDetector(
                  onTap: s._interact,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(9, 4, 11, 5),
                    decoration: BoxDecoration(
                      color: const Color(0xD9FFF3DC),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFF3B2923), width: 1.5),
                      boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 5, offset: Offset(0, 2))],
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(talk ? Icons.chat_bubble_rounded : Icons.touch_app_rounded, size: 14, color: EvochiColor.ink),
                      const SizedBox(width: 4),
                      Text(label, style: EvochiText.tag.copyWith(color: EvochiColor.ink, fontSize: 12.5, height: 1.1)),
                      if (!kIsWeb && defaultTargetPlatform != TargetPlatform.android && defaultTargetPlatform != TargetPlatform.iOS) ...[
                        const SizedBox(width: 5),
                        Text('E', style: EvochiText.tag.copyWith(color: const Color(0xFF8F6A42), fontSize: 10.5)),
                      ],
                    ]),
                  ),
                ),
              ),
            ),
          );
        },
      );
}

/// The minimap: a round window on the floor around you, north up; the gate, the camp, Sher, the foes
/// and the guardian marked; what's in the satchel as a badge. Tap for the whole floor.
/// The trip's purse: the coins calmed creatures have left, in a dark-wood pill under the minimap. It
/// bumps as each coin flies in.
class _Purse extends StatelessWidget {
  const _Purse({required this.state});
  final _WildsScreenState state;
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
        valueListenable: state._repaint,
        builder: (_, __, ___) {
          final n = state._shownCoins;
          final b = ((state._t - state._purseBumpAt) / 0.28).clamp(0.0, 1.0);
          final scale = 1 + 0.16 * math.sin(b * math.pi);
          return Semantics(
            label: '$n coins this trip',
            child: Transform.scale(
              scale: scale,
              alignment: Alignment.centerRight,
              child: Container(
                key: state._purseKey,
                height: 32,
                padding: const EdgeInsets.fromLTRB(6, 0, 10, 0),
                decoration: Kit.coinPill(),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const VoxelIcon('coin', size: 22),
                  const SizedBox(width: 5),
                  Text(fmt(n),
                      textScaler: TextScaler.noScaling,
                      style: EvochiText.number.copyWith(color: Colors.white, fontSize: 14, height: 1.1, shadows: kitWoodTextShadow)),
                ]),
              ),
            ),
          );
        },
      );
}

/// A coin flying up from the ground to the purse.
class _CoinFlyer {
  _CoinFlyer(this.from, this.amount, this.t0);
  final Offset from;
  final int amount;
  final double t0;
  static const flight = 0.5;
}

class _FlyerPainter extends CustomPainter {
  _FlyerPainter(this.s);
  final _WildsScreenState s;
  @override
  void paint(Canvas canvas, Size size) {
    if (s._flyers.isEmpty) return;
    final to = s._pursePoint() ?? Offset(size.width - 40, 60);
    final u = s._u / 2.7;
    for (final f in s._flyers) {
      final e = ((s._t - f.t0) / _CoinFlyer.flight).clamp(0.0, 1.0);
      final k = Curves.easeInQuad.transform(e);
      final at = Offset.lerp(f.from, to, k)! - Offset(0, 46 * math.sin(e * math.pi));
      final r = (5.2 - 1.6 * e) * u;
      final spin = math.cos(s._t * 18 + f.from.dx);
      // a short trail behind it
      canvas.drawLine(at, Offset.lerp(f.from, to, (k - 0.08).clamp(0.0, 1.0))! - Offset(0, 46 * math.sin((e - 0.08).clamp(0.0, 1.0) * math.pi)),
          Paint()
            ..strokeWidth = r * 0.9
            ..strokeCap = StrokeCap.round
            ..color = const Color(0x66FFD35A));
      final rr = Rect.fromCenter(center: at, width: r * 2 * (0.3 + 0.7 * spin.abs()), height: r * 2);
      canvas.drawOval(rr, Paint()..color = const Color(0xFFB8781E));
      canvas.drawOval(rr.deflate(1.1), Paint()..color = spin > 0 ? const Color(0xFFFFD35A) : const Color(0xFFE9B23C));
    }
  }

  @override
  bool shouldRepaint(_FlyerPainter old) => true;
}

class _MiniMap extends StatelessWidget {
  const _MiniMap({required this.state, required this.onTap});
  final _WildsScreenState state;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: 'Map of the floor',
        child: GestureDetector(
          onTap: onTap,
          child: ExcludeSemantics(
            child: SizedBox(
              width: 78,
              height: 78,
              child: Stack(clipBehavior: Clip.none, children: [
                Container(
                  width: 78,
                  height: 78,
                  decoration: _glass(0.3).copyWith(boxShadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 6, offset: Offset(0, 2))]),
                  padding: const EdgeInsets.all(2),
                  child: ClipOval(child: Opacity(opacity: 0.9, child: CustomPaint(painter: _MiniPainter(state, span: 200, repaint: state._repaint)))),
                ),
                Positioned(left: -6, bottom: -4, child: _Satchel(state: state)),
              ]),
            ),
          ),
        ),
      );
}

/// What you have found and not yet brought home: a badge on the minimap.
class _Satchel extends StatelessWidget {
  const _Satchel({required this.state});
  final _WildsScreenState state;
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
        valueListenable: state._repaint,
        builder: (context, _, child) {
          final r = state._raid!;
          final n = r.items.values.fold(0, (a, v) => a + v);
          if (r.coins <= 0 && n == 0) return const SizedBox.shrink();
          return Semantics(
            label: 'Satchel: ${r.coins} coins${n > 0 ? ' and $n items' : ''}, not yet brought home',
            child: Container(
              padding: const EdgeInsets.fromLTRB(3, 1, 7, 2),
              decoration: BoxDecoration(color: const Color(0xE62A1D10), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0x59FFF6E4))),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const VoxelIcon('coin', size: 15),
                const SizedBox(width: 2),
                Text('${r.coins}', style: EvochiText.tag.copyWith(color: const Color(0xFFFFE08A), fontSize: 11)),
                if (n > 0) ...[
                  const SizedBox(width: 4),
                  const ItemImage('lumen_shard', size: 15),
                  Text('$n', style: EvochiText.tag.copyWith(color: const Color(0xFFC9F5EA), fontSize: 11)),
                ],
              ]),
            ),
          );
        },
      );
}

class _MiniPainter extends CustomPainter {
  _MiniPainter(this.s, {required this.span, required Listenable repaint, this.whole = false}) : super(repaint: repaint);
  final _WildsScreenState s;
  final double span; // world units across
  final bool whole;

  @override
  void paint(Canvas canvas, Size size) {
    final m = s._map, r = s._raid;
    if (m == null || r == null) return;
    final pet = r.pet;
    final wr = m.miniWorld;
    final img = m.minimap;
    final double k;
    final Offset c0;
    if (whole) {
      k = math.min(size.width / wr.width, size.height / wr.height);
      c0 = Offset((size.width - wr.width * k) / 2 - wr.left * k, (size.height - wr.height * k) / 2 - wr.top * k);
    } else {
      k = size.width / span;
      c0 = Offset(size.width / 2 - pet.x * k, size.height / 2 - pet.z * k);
    }
    Offset at(double x, double z) => Offset(x * k, z * k) + c0;
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF2E4A24));
    final src = Offset.zero & Size(img.width.toDouble(), img.height.toDouble());
    final dst = Rect.fromPoints(at(wr.left, wr.top), at(wr.right, wr.bottom));
    canvas.drawImageRect(img, src, dst, Paint()..filterQuality = FilterQuality.low);
    final dot = Paint();
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = const Color(0xFF3B2923);
    for (final sp in m.spots) {
      final p = at(sp.x, sp.z);
      if (sp.kind == 'gate') {
        dot.color = const Color(0xFF8FE3D0);
        canvas.drawCircle(p, whole ? 7 : 5, dot);
        canvas.drawCircle(p, whole ? 7 : 5, edge);
      } else if (sp.kind == 'exit') {
        dot.color = const Color(0xFFFFF3DC);
        canvas.drawCircle(p, whole ? 5 : 4, dot);
      } else if (sp.kind == 'glint' && whole) {
        dot.color = const Color(0xFFFFE08A);
        canvas.drawCircle(p, 4, dot);
      }
    }
    for (final (x, z, kind) in m.fx) {
      if (kind == 'fire') {
        dot.color = const Color(0xFFFF9A3A);
        canvas.drawCircle(at(x, z), whole ? 5 : 4, dot);
      }
    }
    // Petalune (pink)
    for (final f in r.friends) {
      dot.color = const Color(0xFFF5A3B5);
      canvas.drawCircle(at(f.x, f.z), whole ? 5 : 4, dot);
    }
    // the foes still tangled, the guardian
    for (final f in r.allFoes) {
      if (f.calm || !f.alive) continue;
      if (f is Boss) {
        dot.color = const Color(0xFFB878E8);
        canvas.drawCircle(at(f.x, f.z), whole ? 8 : 6, dot);
        canvas.drawCircle(at(f.x, f.z), whole ? 8 : 6, edge);
      } else {
        dot.color = const Color(0xFFE5675B);
        canvas.drawCircle(at(f.x, f.z), whole ? 4 : 3, dot);
      }
    }
    final sher = r.sher;
    if (sher != null) {
      dot.color = const Color(0xFFEE9C47);
      canvas.drawCircle(at(sher.x, sher.z), whole ? 5 : 4, dot);
    }
    // you: a pointer in the way you face
    final p = at(pet.x, pet.z);
    final a = pet.dir * math.pi / 4; // 0 = facing south (down)
    final dir = Offset(math.sin(a), math.cos(a));
    final side = Offset(-dir.dy, dir.dx);
    final rr = whole ? 8.0 : 6.0;
    final path = Path()
      ..moveTo(p.dx + dir.dx * rr, p.dy + dir.dy * rr)
      ..lineTo(p.dx - dir.dx * rr * 0.6 + side.dx * rr * 0.7, p.dy - dir.dy * rr * 0.6 + side.dy * rr * 0.7)
      ..lineTo(p.dx - dir.dx * rr * 0.6 - side.dx * rr * 0.7, p.dy - dir.dy * rr * 0.6 - side.dy * rr * 0.7)
      ..close();
    canvas.drawPath(path, Paint()..color = Colors.white);
    canvas.drawPath(path, edge);
  }

  @override
  bool shouldRepaint(covariant _MiniPainter old) => true;
}

/// The whole floor, top-down, with the objective: a focused view (not over other cards).
class _FullMap extends StatelessWidget {
  const _FullMap({required this.state, required this.onClose});
  final _WildsScreenState state;
  final VoidCallback onClose;
  @override
  Widget build(BuildContext context) {
    final m = state._map!;
    final r = state._raid!;
    final mq = MediaQuery.of(context);
    final objective = r.storyBeat != null && !r.storyDone
        ? (r.storyBeat == 'trust'
            ? 'Petalune waits in the Mossy Ruins, north. Stay near and gentle, hum, offer a treat: earn its trust.'
            : 'The Hollow Sprout lashes out in the Mossy Ruins, north. Calm its Hollow to restore it.')
        : m.depth != null
        ? (r.calmed >= r.foeTotal
            ? 'The floor is calm: the old doorway down is open.'
            : 'Calm the Hollow creatures (${r.calmed}/${r.foeTotal}), then take the old doorway down.')
        : r.calmed >= r.foeTotal && r.bossState == BossState.calm
        ? 'The Thicket is calm. The old gate north leads to Fernwood Trail.'
        : 'Calm the Hollow creatures (${r.calmed}/${r.foeTotal})${r.bossState == BossState.calm ? '. The guardian is calm.' : ' and the guardian at the old gate.'}';
    return Container(
      color: const Color(0xCC141A10),
      padding: EdgeInsets.fromLTRB(16, mq.padding.top + 12, 16, mq.padding.bottom + 16),
      child: Column(children: [
        Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          decoration: Kit.parchment(radius: 14),
          child: Row(children: [
            const SparkIcon(size: 26),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${m.name} · ${m.floor}', style: EvochiText.cardTitle),
                Text(objective, style: EvochiText.caption),
              ]),
            ),
          ]),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF3B2923), width: 3),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(13),
              child: CustomPaint(painter: _MiniPainter(state, span: 0, whole: true, repaint: state._repaint), child: const SizedBox.expand()),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: Wrap(spacing: 10, runSpacing: 4, children: [
              _legend(const Color(0xFF8FE3D0), 'Gate'),
              _legend(const Color(0xFFFF9A3A), 'Camp'),
              _legend(const Color(0xFFEE9C47), 'Sher'),
              _legend(const Color(0xFFE5675B), 'Hollow creatures'),
              _legend(const Color(0xFFB878E8), 'Guardian'),
              _legend(const Color(0xFFFFE08A), 'Glint'),
            ]),
          ),
          EvochiButton(label: 'Close', tone: ButtonTone.cream, small: true, expand: false, onPressed: onClose),
        ]),
      ]),
    );
  }

  Widget _legend(Color c, String t) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: c, shape: BoxShape.circle, border: Border.all(color: const Color(0xFF3B2923)))),
        const SizedBox(width: 4),
        Text(t, style: EvochiText.tag.copyWith(color: const Color(0xFFFFF3DC), fontSize: 12)),
      ]);
}

/// Something you found or reached: a focused card with what it says and what you can do.
/// Near Petalune: how far its trust has come, a hum, and a treat from the Bag (the ones it loves warm it
/// half again as much).
class _PetaluneCard extends StatelessWidget {
  const _PetaluneCard({required this.trust, required this.humReady, required this.treats, required this.onHum, required this.onOffer, required this.onClose});
  final double trust;
  final bool humReady;
  final List<({String id, String name, int have, int trust})> treats;
  final VoidCallback onHum, onClose;
  final void Function(String id) onOffer;
  @override
  Widget build(BuildContext context) {
    final mood = trust < 30 ? 'It watches you, ready to bolt.' : (trust < Raid.trustDrift ? 'It has stopped backing away. It is curious.' : 'It edges closer. Almost there.');
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: Kit.parchment(radius: 16),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Petalune', style: EvochiText.cardTitle.copyWith(fontSize: 18)),
        const SizedBox(height: 4),
        Text('$mood Stay near and gentle; a hum or a treat helps it trust you.', style: EvochiText.bodyText.copyWith(height: 1.35)),
        const SizedBox(height: 8),
        Row(children: [
          const Icon(Icons.favorite_rounded, size: 16, color: Color(0xFFE0849A)),
          const SizedBox(width: 6),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: trust / 100,
                minHeight: 10,
                backgroundColor: const Color(0x333B2923),
                valueColor: const AlwaysStoppedAnimation(Color(0xFFF5A3B5)),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text('${trust.round()}%', style: EvochiText.tag.copyWith(color: EvochiColor.ink)),
        ]),
        const SizedBox(height: 10),
        EvochiButton(label: humReady ? 'Hum a soft tune' : 'Humming...', tone: ButtonTone.green, onPressed: humReady ? onHum : null),
        for (final t in treats) ...[
          const SizedBox(height: 6),
          EvochiButton(label: 'Offer ${t.name} (${t.have})${t.trust > 20 ? ' · loves it' : ''}', tone: ButtonTone.cream, onPressed: () => onOffer(t.id)),
        ],
        if (treats.isEmpty) ...[
          const SizedBox(height: 6),
          Text('No food in your Bag to offer. It loves Sunberry Tarts.', style: EvochiText.caption.copyWith(color: EvochiColor.textSecondary), textAlign: TextAlign.center),
        ],
        const SizedBox(height: 6),
        TextButton(onPressed: onClose, child: const Text('Let it be')),
      ]),
    );
  }
}

class _SpotCard extends StatelessWidget {
  const _SpotCard({required this.spot, required this.primary, required this.onPrimary, this.secondary, this.onSecondary, this.note});
  final MapSpot spot;
  final String primary;
  final String? secondary, note;
  final VoidCallback onPrimary;
  final VoidCallback? onSecondary;
  @override
  Widget build(BuildContext context) => _InfoCard(
        title: spot.title,
        text: spot.text,
        note: note,
        primary: primary,
        primaryTone: spot.kind == 'exit' ? ButtonTone.gold : ButtonTone.green,
        secondary: secondary,
        onPrimary: onPrimary,
        onSecondary: onSecondary,
      );
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.title, required this.text, required this.primary, required this.onPrimary, this.secondary, this.onSecondary, this.note, this.primaryTone = ButtonTone.green});
  final String title, text, primary;
  final String? secondary, note;
  final VoidCallback onPrimary;
  final VoidCallback? onSecondary;
  final ButtonTone primaryTone;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: Kit.parchment(radius: 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(title, style: EvochiText.cardTitle.copyWith(fontSize: 18)),
          const SizedBox(height: 6),
          Text(text, style: EvochiText.bodyText.copyWith(height: 1.35)),
          if (note != null) ...[
            const SizedBox(height: 6),
            Text(note!, style: EvochiText.caption.copyWith(color: EvochiColor.textSecondary)),
          ],
          const SizedBox(height: 10),
          Row(children: [
            if (secondary != null) ...[
              Expanded(child: EvochiButton(label: secondary!, tone: ButtonTone.cream, onPressed: onSecondary)),
              const SizedBox(width: 8),
            ],
            Expanded(child: EvochiButton(label: primary, tone: primaryTone, onPressed: onPrimary)),
          ]),
        ]),
      );
}

/// The guardian calmed: what it leaves (once, the first time; a spar's smaller reward after), and the
/// satchel coming home with it.
class _VictoryCard extends StatelessWidget {
  const _VictoryCard({required this.first, required this.coins, required this.items, required this.satchelCoins, required this.satchelItems, required this.onCollect});
  final bool first;
  final int coins, satchelCoins;
  final Map<String, int> items, satchelItems;
  final VoidCallback onCollect;
  @override
  Widget build(BuildContext context) {
    Widget chip(Widget icon, String text) => Container(
          padding: const EdgeInsets.fromLTRB(6, 4, 10, 4),
          decoration: BoxDecoration(color: const Color(0x33FFFFFF), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0x553B2923))),
          child: Row(mainAxisSize: MainAxisSize.min, children: [icon, const SizedBox(width: 4), Text(text, style: EvochiText.tag.copyWith(color: EvochiColor.ink))]),
        );
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: Kit.parchment(radius: 16),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(first ? 'The Briarback is calm' : 'A good spar', style: EvochiText.cardTitle.copyWith(fontSize: 19)),
        const SizedBox(height: 6),
        Text(
            first
                ? 'The Hollow has gone out of the old guardian. Its antlers are budding, and it stands aside from the gate. It left you a piece of its heartwood.'
                : 'The Briarback shakes out its antlers, pleased. It left you a little more heartwood.',
            style: EvochiText.bodyText.copyWith(height: 1.35)),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 6, children: [
          chip(const VoxelIcon('coin', size: 22), '+$coins'),
          for (final e in items.entries) chip(ItemImage(e.key, size: 26), '${_lootName(e.key)} x${e.value}'),
        ]),
        if (satchelCoins > 0 || satchelItems.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('Your satchel comes home too: ${[if (satchelCoins > 0) '$satchelCoins EvoCoins', for (final e in satchelItems.entries) '${e.value} ${_lootName(e.key)}'].join(', ')}.',
              style: EvochiText.caption.copyWith(color: EvochiColor.textSecondary)),
        ],
        if (!first) ...[
          const SizedBox(height: 4),
          Text('Sparring rewards come once a day.', style: EvochiText.caption.copyWith(color: EvochiColor.textSecondary)),
        ],
        const SizedBox(height: 10),
        EvochiButton(label: 'Collect', tone: ButtonTone.gold, onPressed: onCollect),
      ]),
    );
  }
}

/// Meeting Sher: his offer to come along.
const _sherTips = [
  'The Briarback charges in a straight line. Dodge through it, then strike its flank while it shakes off the crash.',
  'Sporecaps lob their spores where you are standing. Keep moving and they land behind you.',
  'Thornlings roll at you. Sidestep, and pounce while they uncurl.',
  'Hurt? Eat a berry from the leaf button. Your Vitality stays untouched in here.',
  'Calmed creatures sometimes leave rare finds. Bring your satchel home before you push your luck.',
];

class _Offer extends StatelessWidget {
  const _Offer({required this.gifted, required this.tip, required this.onThanks});
  final bool gifted;
  final String tip;
  final VoidCallback onThanks;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: Kit.parchment(radius: 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            const SherFace(size: 56),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Sher', style: EvochiText.cardTitle.copyWith(fontSize: 18)),
                const Text('A scout who keeps the camp', style: EvochiText.caption),
              ]),
            ),
          ]),
          const SizedBox(height: 8),
          Text(
            gifted
                ? 'Back already? The fire\'s still going. $tip'
                : 'Heading deeper? Something Hollow has the wood on edge. I\'ll keep the fire lit here for when you come back. Take these berries for the road, and a word of advice: $tip',
            style: EvochiText.bodyText.copyWith(height: 1.35),
          ),
          const SizedBox(height: 10),
          EvochiButton(label: gifted ? 'Thanks, Sher' : 'Thanks, Sher (3 Berry Snacks)', tone: ButtonTone.green, onPressed: onThanks),
        ]),
      );
}

/// The joystick under your finger while you drag (the rim: running).
class _Stick extends StatelessWidget {
  const _Stick({required this.origin, required this.knob});
  final Offset origin, knob;
  @override
  Widget build(BuildContext context) {
    var d = knob - origin;
    final far = d.distance > 52;
    if (d.distance > 56) d = d / d.distance * 56;
    return Positioned(
      left: origin.dx - 64,
      top: origin.dy - 64,
      child: IgnorePointer(
        child: SizedBox(
          width: 128,
          height: 128,
          child: Stack(children: [
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0x33FFFFFF),
                border: Border.all(color: far ? const Color(0xFFB8E68C) : const Color(0x99FFF3DC), width: far ? 3 : 2),
              ),
            ),
            Positioned(
              left: 64 + d.dx - 22,
              top: 64 + d.dy - 22,
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xE6FFF3DC),
                  border: Border.all(color: far ? const Color(0xFF6CC24A) : EvochiColor.primary, width: 2.5),
                  boxShadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 6, offset: Offset(0, 2))],
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// A satchel entry's name: an item, or Glimmer (a rare foe drop).
String _lootName(String id) => id == econ.glimmer ? 'Glimmer' : (catalog[id]?.name ?? id);
