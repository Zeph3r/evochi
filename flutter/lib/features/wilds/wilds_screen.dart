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
import '../../game/wilds/wilds.dart' as w;
import '../shared/ambience.dart';
import '../shared/kit.dart';
import '../shared/live_scene.dart' show SceneFx;
import '../shared/widgets.dart';
import '../trails/trails_widgets.dart';
import '../village/story_widgets.dart';
import 'boss_intro.dart';
import 'wilds_art.dart';
import 'wilds_combat.dart';

class WildsScreen extends StatefulWidget {
  const WildsScreen({super.key, this.mapId = 'thicket'});
  final String mapId;
  @override
  State<WildsScreen> createState() => _WildsScreenState();
}

class _WildsScreenState extends State<WildsScreen> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  WildsMap? _map;
  Raid? _raid;
  WalkerArt? _petArt, _sherArt;
  // the guardian's entrance (loaded in the background; without it the fight starts as before)
  BossIntroArt? _introArt;
  CineEvochiArt? _cineEvochi;
  IntroCut? _cine; // playing now
  final _foeArt = <String, FoeArt>{};
  late final Ticker _ticker = createTicker(_tick);
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
  bool _nearSher = false, _nearBoss = false;
  String? _bubble;
  double _bubbleT = 0;
  int _line = 0;
  double _hintT = 7;
  String? _hint;
  double _hintT2 = 0;
  final _repaint = ValueNotifier<int>(0);
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
  double _shakeX = 0, _shakeY = 0;
  final _rng = math.Random();
  bool _snap = true; // the camera jumps (the start, after an evacuation)
  late final GameController _c;
  ui.FragmentProgram? _fxProgram; // the living-scene shader: leaves sway, grass shimmers, water ripples
  final _fx = <Object, ui.FragmentShader>{}; // one per tile / prop drawn (each draw keeps its uniforms)

  static const _floor = 'thicket';


  ui.FragmentShader? _fxFor(Object key) {
    final p = _fxProgram;
    if (p == null) return null;
    return _fx[key] ??= p.fragmentShader();
  }

  @override
  void initState() {
    super.initState();
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
    Future.wait([
      WildsMap.load(widget.mapId),
      WalkerArt.load(key, palette, wearing: wearing),
      WalkerArt.load('sher', 'sher'),
      FoeArt.load('thornling'),
      FoeArt.load('sporecap'),
      FoeArt.load('briarback'),
    ]).then((r) {
      if (!mounted) return;
      final m = r[0] as WildsMap;
      _petArt = r[1] as WalkerArt;
      _sherArt = r[2] as WalkerArt;
      _foeArt['thornling'] = r[3] as FoeArt;
      _foeArt['sporecap'] = r[4] as FoeArt;
      _foeArt['briarback'] = r[5] as FoeArt;
      setState(() {
        _map = m;
        _raid = _newRaid(m);
      });
      // Sher keeps the camp by the fire: he gives berries and a tip, and the trail is yours to walk
      _ticker.start();
      _loadIntro(pet?.stage ?? 1, palette, wearing);
    });
  }

  Future<void> _loadIntro(int stage, String palette, List<String> wearing) async {
    try {
      _introArt = await BossIntroArt.load('briarback');
      _cineEvochi = await CineEvochiArt.load(stage, palette, wearing);
    } catch (e) {
      debugPrint('boss intro art: $e');
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
    final cleared = w.floorCleared(c.state, _floor);
    _clearFirst = !cleared;
    _sealOpen = cleared;
    _sealT = 1;
    final ar = b == null ? null : (b['arena'] as Map).cast<String, dynamic>();
    List<(double, double)> pts(Object? l) => [for (final p in (l as List? ?? const [])) (((p as List)[0] as num).toDouble(), (p[1] as num).toDouble())];
    final fire = m.fx.where((f) => f.$3 == 'fire').toList();
    return Raid(
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
      seed: DateTime.now().millisecondsSinceEpoch & 0xffff,
      // the economy: rare finds from calmed creatures, and an armed Hollow Ward
      lootRoll: (r) => econ.rollDrops('wilds_foe', r),
      lootLabel: (id, n) => id == econ.glimmer ? '+$n Glimmer!' : '+$n ${_lootName(id)}!',
      ward: _takeWard(c),
      bossScale: _soloBoss,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_music != null) _c.audio.setMusic(null);
    _ticker.dispose();
    _introArt?.dispose();
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

  bool get _paused => _card != null || _cine != null;

  // ---- the loop
  void _tick(Duration now) {
    final dt = _last == Duration.zero ? 0.0 : math.min(0.05, (now - _last).inMicroseconds / 1e6);
    _last = now;
    _t += dt;
    if (_sealOpen && _sealT < 1) _sealT = math.min(1.0, _sealT + dt / 1.8);
    final m = _map, r = _raid;
    if (m == null || r == null || _view == Size.zero) return;
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
    // room to move: the view widens to fit the fight
    var wantW = 180.0;
    if (bossFight) {
      wantW = 265; // the arena is wide: room to see the guardian's sweeps and charges coming
    } else if (r.inCombat) {
      var spread = 0.0;
      for (final f in r.hostile) {
        final d = f.dist(pet);
        if (d < 170) spread = math.max(spread, d);
      }
      wantW = (spread * 2 + 90).clamp(180.0, 230.0);
    }
    _zoomW += (wantW - _zoomW) * math.min(1.0, dt * 1.6);
    if (_view.width > 0) {
      _u = math.max((_view.width / _zoomW).clamp(1.7, 3.6), _view.width / (m.groundW / m.scale));
    }
    if (bossFight) {
      fx += (bb.x - pet.x) * 0.35;
      fz += (bb.z - pet.z) * 0.35;
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
    _repaint.value++;
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

  void _say(String text, [double secs = 2.8]) {
    _bubble = text;
    _bubbleT = secs;
  }

  void _showBanner(String text, [double secs = 2.6]) {
    setState(() => _banner = text);
    _bannerT = secs;
  }

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
          _showBanner('${e.text ?? 'The clearing'} is calm');
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
    if (_nearBoss) {
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
    if (r == null || (r.coins <= 0 && r.items.isEmpty)) return false;
    final c = context.read<GameController>();
    final coins = r.coins;
    final items = Map<String, int>.of(r.items);
    final res = c.run((s, n) => w.wildsBank(s, '$_runId-$_banks', coins, items, n), quiet: true);
    if (!res.ok) return false;
    r.coins = 0;
    r.items.clear();
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
                      right: 10 + mq.padding.right + 182,
                      bottom: 12 + mq.padding.bottom + 96,
                      child: _BrewShelf(brews: w.ownedBrews(context.read<GameController>().state), onPick: _drink),
                    ),
                  if (_hintT > 0 && card == null && _hint == null)
                    _bottomHint(mq, _hintT > 1, 'Drag to walk · push far to run'),
                  if (_hint != null && card == null) _bottomHint(mq, _hintT2 > 0.6, _hint!),
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
        if (k == LogicalKeyboardKey.space) _press('dodge');
        if (k == LogicalKeyboardKey.keyQ) _press('item');
      }
    }
    if (e is KeyUpEvent) _keys.remove(k);
    return KeyEventResult.handled;
  }

  /// Playtesting shortcuts (debug builds only): 1-3 the clearings, 4 the arena's edge, 5 the arena, G
  /// keeps your Evochi's Raid HP full, B takes a fifth of the guardian's health, I replays its entrance.
  void _debugKey(LogicalKeyboardKey k) {
    final r = _raid, m = _map;
    if (r == null || m == null) return;
    (double, double)? to;
    final zs = m.zones;
    if (k == LogicalKeyboardKey.digit1 && zs.isNotEmpty) to = (zs[0].$3 + 10, zs[0].$4 + 60);
    if (k == LogicalKeyboardKey.digit2 && zs.length > 1) to = (zs[1].$3 + 10, zs[1].$4 + 60);
    if (k == LogicalKeyboardKey.digit3 && zs.length > 2) to = (zs[2].$3 + 10, zs[2].$4 + 60);
    // 4: at the arena's way in; 5: a few steps inside, where the guardian wakes
    final ar = (m.boss?['arena'] as Map?)?.cast<String, dynamic>();
    if (ar != null) {
      final ax = (ar['x'] as num).toDouble(), az = (ar['z'] as num).toDouble(), rr = (ar['r'] as num).toDouble();
      if (k == LogicalKeyboardKey.digit4) to = (ax - 12, az + rr + 16);
      if (k == LogicalKeyboardKey.digit5) to = (ax - 6, az + rr * 0.45);
    }
    if (k == LogicalKeyboardKey.keyB) r.debugHurtBoss(0.2);
    // I: play the guardian's entrance again (the full cut)
    if (k == LogicalKeyboardKey.keyI && _introArt != null) setState(() => _cine = IntroCut.full);
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
    final Widget body;
    switch (card) {
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
        canvas.drawImage(t.img, t.rect.topLeft, pq);
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
      if (const {'pulse', 'spores', 'sweep', 'dust', 'scar'}.contains(b.kind)) _burst(canvas, b);
    }
    // the target ring
    final lock = r.lock;
    if (lock != null && lock.alive && !lock.calm) _ring(canvas, lock, const Color(0xFFFFD25A));
    // soft shadows under everyone (the props' shadows are in the ground)
    final shadow = Paint()
      ..color = const Color(0x40000000)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    final actors = <Actor>[pet, if (sher != null) sher, ...r.allFoes];
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
    }
    for (final sh in r.shots) {
      items.add((sh.z + 1, () => _shot(canvas, sh)));
    }
    items.sort((a, b) => a.$1.compareTo(b.$1));
    for (final it in items) {
      it.$2();
    }
    // the wood's own life: leaves coming down, fireflies in the shade; the edges sink into shadow
    if (!rm) _ambient(canvas, size);
    _vignette(canvas, size);
    // above everything: sparks, motes, stars, numbers
    for (final b in r.bursts) {
      if (!const {'pulse', 'spores', 'sweep', 'dust', 'scar'}.contains(b.kind)) _burst(canvas, b);
    }
    // a glint where something waits to be found
    for (final sp in m.spots) {
      if (sp.kind != 'glint') continue;
      _glint(canvas, s._toScreen(sp.x, sp.z) - Offset(0, 10 * s._u / 2.7));
    }
    for (final f in r.allFoes) {
      _foeBar(canvas, f);
    }
    for (final f in r.floaters) {
      _floater(canvas, f);
    }
    // Sher's bubble
    final b = s._bubble;
    if (b != null && sher != null) _bubble(canvas, sher, b);
  }

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
    canvas.save();
    canvas.translate(g.dx, g.dy - w.lift * _up);
    if (!rm) {
      final face = w.dir * math.pi / 4;
      canvas.rotate(gait.roll[col] * math.pi / 180 * math.cos(face) + w.tilt);
      final sit = w.pose == 'sit';
      final pop = Curves.easeOut.transform(w.pop.clamp(0.0, 1.0));
      canvas.scale(w.sx * (1 + 0.1 * pop), w.sy * gait.squash[col] * (sit ? 0.82 : 1) * (1 - 0.12 * pop));
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
    final k = s._u / a.scale;
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
    if (f.st == FoeState.stagger && f is Boss) _stars(canvas, g - Offset(0, a.top * k * 0.95), 2, 1);
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
        _glow(canvas, g, 12 * s._u / 2.7, const Color(0x999FF0DA));
        canvas.drawCircle(g, 4 * s._u / 2.7, Paint()..color = const Color(0xFFE8FFF8));
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
          final String text;
          if (r.calmed < r.foeTotal) {
            text = 'Calm the Hollow creatures  ${r.calmed}/${r.foeTotal}';
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
              Text(state._map!.name.toUpperCase(), style: _hudText(10, const Color(0xCCFFE7B8)).copyWith(letterSpacing: 1.6)),
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
class _CombatPad extends StatelessWidget {
  const _CombatPad({required this.state});
  final _WildsScreenState state;
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
          opacity: calm ? 0.72 : 1,
          duration: const Duration(milliseconds: 400),
          child: SizedBox(
            width: 178,
            height: 170,
            child: Stack(clipBehavior: Clip.none, children: [
              Positioned(
                right: 0,
                bottom: 0,
                child: _PadButton(
                  label: 'Pounce',
                  icon: 'paw',
                  size: 78,
                  tone: const Color(0xFFF4B84E),
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
              Positioned(
                right: 84,
                bottom: 2,
                child: _PadButton(label: 'Dodge', icon: 'swirl', size: 54, tone: const Color(0xFFB8E68C), dim: st < 20, onDown: () => s._press('dodge')),
              ),
              Positioned(
                right: 70,
                bottom: 62,
                child: _PadButton(
                  label: 'Glow Bolt',
                  icon: 'energy',
                  size: 50,
                  tone: const Color(0xFF9FF0DA),
                  cooldown: r.boltCd / 1.0,
                  dim: st < 18,
                  onDown: () => s._press('bolt'),
                ),
              ),
              Positioned(
                right: 10,
                bottom: 86,
                child: _PadButton(
                  label: 'Lumen Pulse',
                  icon: 'sun',
                  size: 50,
                  tone: const Color(0xFFC9F5EA),
                  cooldown: r.pulseCd / 7.0,
                  dim: st < 34,
                  onDown: () => s._press('pulse'),
                ),
              ),
              Positioned(
                right: 128,
                bottom: 60,
                child: _PadButton(
                  label: heals > 0 ? 'Eat a berry, $heals left' : 'No berries',
                  icon: 'potion',
                  image: healId,
                  badge: heals > 0 ? '$heals' : null,
                  size: 42,
                  tone: const Color(0xFFFFF0DE),
                  cooldown: s._itemCd / 2.5,
                  dim: heals == 0,
                  onDown: () => s._press('item'),
                ),
              ),
              // the brews: a flask; with more than one kind, it opens a little shelf of them
              Positioned(
                right: 134,
                bottom: 112,
                child: _PadButton(
                  label: brews.isEmpty ? 'No brews' : 'Drink a brew',
                  icon: 'potion',
                  image: brews.isEmpty ? null : brews.first,
                  badge: brews.length > 1 ? '${brews.length}' : null,
                  size: 40,
                  tone: const Color(0xFFBFF6FF),
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

/// The brews on a little shelf (when there is more than one kind to choose from).
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

class _PadButton extends StatelessWidget {
  const _PadButton({required this.label, required this.icon, required this.size, required this.tone, required this.onDown, this.onUp, this.cooldown = 0, this.dim = false, this.image, this.badge});
  final String label, icon;
  final double size, cooldown;
  final Color tone; // the rim
  final VoidCallback onDown;
  final VoidCallback? onUp;
  final bool dim;
  final String? image, badge;
  @override
  Widget build(BuildContext context) {
    final ready = cooldown <= 0.001;
    return Semantics(
      button: true,
      label: label,
      child: Listener(
        onPointerDown: (_) => onDown(),
        onPointerUp: (_) => onUp?.call(),
        onPointerCancel: (_) => onUp?.call(),
        child: ExcludeSemantics(
          child: Opacity(
            opacity: dim ? 0.45 : 1,
            child: SizedBox(
              width: size,
              height: size,
              child: Stack(clipBehavior: Clip.none, children: [
                Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const RadialGradient(center: Alignment(0, -0.3), colors: [Color(0x66243020), Color(0x8C0B120A)]),
                    border: Border.all(color: tone.withAlpha(200), width: 2),
                  ),
                  alignment: Alignment.center,
                  child: image != null ? ItemImage(image!, size: size * 0.62) : VoxelIcon(icon, size: size * 0.6),
                ),
                if (!ready) Positioned.fill(child: CustomPaint(painter: _CooldownPainter(cooldown.clamp(0.0, 1.0)))),
                if (badge != null)
                  Positioned(
                    right: -3,
                    bottom: -3,
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(5, 0, 5, 1),
                      decoration: BoxDecoration(color: const Color(0xE62A1D10), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0x59FFF6E4))),
                      child: Text(badge!, style: EvochiText.tag.copyWith(color: const Color(0xFFFFF6E4), fontSize: 10.5, height: 1.25)),
                    ),
                  ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _CooldownPainter extends CustomPainter {
  _CooldownPainter(this.left);
  final double left; // 1 = just used, 0 = ready
  @override
  void paint(Canvas canvas, Size size) {
    final r = Offset.zero & size;
    canvas.drawArc(r.deflate(2), -math.pi / 2, 2 * math.pi * left, true, Paint()..color = const Color(0x990B120A));
  }

  @override
  bool shouldRepaint(covariant _CooldownPainter old) => old.left != left;
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
          final talk = (s._nearSher && (near == null || !r.party)) || s._nearBoss;
          // (positioned even when empty: a bare box in the Stack would size it to nothing)
          if (!talk && near == null) return const Positioned(left: 0, top: 0, child: SizedBox.shrink());
          final String label;
          final Offset at;
          if (s._nearBoss) {
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
    final objective = r.calmed >= r.foeTotal && r.bossState == BossState.calm
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
