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
import '../../game/wilds/wilds.dart' as w;
import '../shared/ambience.dart';
import '../shared/kit.dart';
import '../shared/widgets.dart';
import '../trails/trails_widgets.dart';
import '../village/story_widgets.dart';
import '../village/village_screen.dart';
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
  final _foeArt = <String, FoeArt>{};
  late final Ticker _ticker = createTicker(_tick);
  Duration _last = Duration.zero;
  double _t = 0; // seconds, for the fire, glints and effects
  final _focus = FocusNode();
  final _keys = <LogicalKeyboardKey>{};
  Offset? _stickOrigin, _stick;
  Offset? _target; // tap-to-move (world x, z)
  bool _targetRun = false;
  bool _runToggle = false;
  Size _view = Size.zero;
  double _u = 2.7; // screen px per world unit
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

  static const _floor = 'thicket';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _c = context.read<GameController>();
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
      // Sher has come along before: he waits at the trailhead now, ready to go
      final raid = _raid!;
      final sh = raid.sher;
      if (sh != null && _c.state.flags['wilds_sher_gift'] == true) {
        raid.join();
        sh
          ..x = raid.pet.x + 16
          ..z = raid.pet.z + 6
          ..face(0, -1);
        _say('Ready when you are.', 2.4);
      }
      _ticker.start();
    });
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
      seed: DateTime.now().millisecondsSinceEpoch & 0xffff,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_music != null) _c.audio.setMusic(null);
    _ticker.dispose();
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

  bool get _paused => _card != null;

  // ---- the loop
  void _tick(Duration now) {
    final dt = _last == Duration.zero ? 0.0 : math.min(0.05, (now - _last).inMicroseconds / 1e6);
    _last = now;
    _t += dt;
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
    var run = _runToggle || k(LogicalKeyboardKey.shiftLeft, LogicalKeyboardKey.shiftRight);
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

  /// The guardian's health bar is up (on a phone it takes the top row; the party and the map step down).
  bool get _bossBar {
    final r = _raid;
    return r != null && r.boss != null && !r.boss!.calm && (r.bossState == BossState.intro || r.bossState == BossState.fight);
  }

  void _toggleRun() => setState(() => _runToggle = !_runToggle);

  void _sfx(String name, double vol, {double gap = 0.06}) {
    final last = _sfxAt[name] ?? -9;
    if (_t - last < gap) return;
    _sfxAt[name] = _t;
    _c.audio.play(name, volume: vol);
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
          _sfx('enc_awaken', 0.8);
          a.buzz(Haptic.rumble);
          _showBanner('The Briarback wakes!', 2.4);
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
          _music = null;
          a.setMusic(null);
          _sfx('level_up', 0.8);
          a.buzz(Haptic.win);
          Future.delayed(const Duration(milliseconds: 2200), () {
            if (mounted && _card == null) setState(() => _card = 'victory');
          });
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
      if (r.party) {
        const lines = ['Lead the way!', 'I\'ve got your back.', 'Smell that? Rain later.', 'Stay close to the path.', 'The stream\'s cold. Bridge is drier.'];
        _say(lines[_line++ % lines.length], 2.6);
      } else {
        _card = 'sher';
        _target = null;
      }
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
    final parts = ['+$coins EvoCoins', for (final e in items.entries) '+${e.value} ${catalog[e.key]?.name ?? e.key}'];
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
        'village',
        child: Scaffold(
          backgroundColor: const Color(0xFF2E4A24),
          body: LayoutBuilder(builder: (ctx, b) {
            _view = Size(b.maxWidth, b.maxHeight);
            _u = (b.maxWidth / 145).clamp(2.4, 3.6);
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
                // the header over a soft shade
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  child: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x80141A10), Color(0x00141A10)]),
                    ),
                    child: SafeArea(
                      bottom: false,
                      child: PlaceHeader(
                        title: m == null ? 'Lumen Wilds' : '${m.name} · ${m.floor}',
                        short: m?.floor ?? 'Wilds',
                        backLabel: 'Leave',
                        onBack: _askLeave,
                      ),
                    ),
                  ),
                ),
                if (m != null && _raid != null) ...[
                  Positioned(left: 10, top: mq.padding.top + 62 + (narrow && _bossBar ? 46 : 0), child: _PartyPanel(state: this)),
                  Positioned(
                    right: 10,
                    top: mq.padding.top + 62 + (narrow && _bossBar ? 46 : 0),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      _MiniMap(state: this, onTap: () => setState(() => _card = 'map')),
                      const SizedBox(height: 6),
                      _SatchelPill(state: this),
                    ]),
                  ),
                  Positioned(
                    left: narrow ? 10 : 170,
                    right: narrow ? 10 : 120,
                    top: mq.padding.top + (narrow ? (_bossBar ? 60 : 172) : 62),
                    child: IgnorePointer(child: Center(child: _TopCenter(state: this))),
                  ),
                  if (card == null)
                    Positioned(
                      right: 10 + mq.padding.right,
                      bottom: 12 + mq.padding.bottom,
                      child: _CombatPad(state: this),
                    ),
                  if (_hintT > 0 && card == null && _hint == null)
                    _bottomHint(mq, _hintT > 1, 'Drag to walk · push far to run · tap a spot'),
                  if (_hint != null && card == null) _bottomHint(mq, _hintT2 > 0.6, _hint!),
                  if (_banner != null && card == null)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: mq.padding.bottom + (narrow ? 250 : 120),
                      child: IgnorePointer(child: Center(child: _Banner(text: _banner!))),
                    ),
                ],
                if (card != null && m != null && _raid != null) _cardFor(card, m),
              ]),
            );
          }),
        ),
      ),
    );
  }

  Widget _bottomHint(MediaQueryData mq, bool on, String text) => Positioned(
        left: 12,
        right: 216,
        bottom: 16 + mq.padding.bottom,
        child: IgnorePointer(
          child: Align(
            alignment: Alignment.bottomLeft,
            child: AnimatedOpacity(
              opacity: on ? 1 : 0,
              duration: const Duration(milliseconds: 600),
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 7),
                decoration: BoxDecoration(color: const Color(0xD92A1D10), borderRadius: BorderRadius.circular(14)),
                child: Text(text, style: EvochiText.tag.copyWith(color: const Color(0xFFFFF3DC))),
              ),
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
  /// keeps your Evochi's Raid HP full, B takes a fifth of the guardian's health.
  void _debugKey(LogicalKeyboardKey k) {
    final r = _raid, m = _map;
    if (r == null || m == null) return;
    (double, double)? to;
    final zs = m.zones;
    if (k == LogicalKeyboardKey.digit1 && zs.isNotEmpty) to = (zs[0].$3 + 10, zs[0].$4 + 60);
    if (k == LogicalKeyboardKey.digit2 && zs.length > 1) to = (zs[1].$3 + 10, zs[1].$4 + 60);
    if (k == LogicalKeyboardKey.digit3 && zs.length > 2) to = (zs[2].$3 + 10, zs[2].$4 + 60);
    if (k == LogicalKeyboardKey.digit4) to = (-10, -300);
    if (k == LogicalKeyboardKey.digit5) to = (-14, -370);
    if (k == LogicalKeyboardKey.keyB) r.debugHurtBoss(0.2);
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
        body = _Offer(
          onJoin: () {
            c.audio.play('reward_chime', volume: 0.6);
            r.join();
            final res = c.run((s, n) => w.wildsSherGift(s, n), quiet: true);
            final gift = res.events.any((e) => e.type == 'wilds_gift');
            setState(() {
              _card = null;
              _say(gift ? 'Lead the way! Here, berries for the road. Eat one when you\'re hurt.' : 'Lead the way!', gift ? 4.2 : 2.4);
            });
          },
          onLater: close,
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
                  ? 'Something old and tangled guards this gate.'
                  : (locked ? 'The light holds steady now. Your Evochi is Lv. $lvl; it needs Lv. ${s.need}.' : 'The light flickers. Not yet, but soon.'))
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
    final lostI = [for (final e in r.items.entries) if ((e.value / 2).ceil() > 0) '${(e.value / 2).ceil()} ${catalog[e.key]?.name ?? e.key}'];
    if (lostC == 0 && lostI.isEmpty) return null;
    return 'Dropped on the way: ${[if (lostC > 0) '$lostC EvoCoins', ...lostI].join(', ')} (half the satchel).';
  }

  String _satchelText(int coins, Map<String, int> items) =>
      [if (coins > 0) '$coins EvoCoins', for (final e in items.entries) '${e.value} ${catalog[e.key]?.name ?? e.key}'].join(', ');
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
    for (final t in m.tiles) {
      if (t.rect.overlaps(vis)) canvas.drawImage(t.img, t.rect.topLeft, pq);
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
      if (const {'pulse', 'spores', 'sweep', 'dust'}.contains(b.kind)) _burst(canvas, b);
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
      final k = s._u / a.scale;
      final rect = Rect.fromLTWH(g.dx - a.ax * k, g.dy - a.ay * k, a.img.width * k, a.img.height * k);
      if (!rect.overlaps(view)) continue;
      final tall = p.kind.startsWith('oak') || p.kind.startsWith('pine') || p.kind.startsWith('birch') || p.kind == 'gate' || p.kind == 'tent' || p.kind.startsWith('pillar');
      final see = tall && hidden.any((h) => p.z > h.$1 && rect.deflate(rect.width * 0.12).overlaps(h.$2));
      items.add((p.z, () => _prop(canvas, p.flip, a, g, k, see ? _see : pq)));
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
    // above everything: sparks, motes, stars, numbers
    for (final b in r.bursts) {
      if (!const {'pulse', 'spores', 'sweep', 'dust'}.contains(b.kind)) _burst(canvas, b);
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

  static final _see = Paint()
    ..filterQuality = FilterQuality.medium
    ..color = const Color.fromRGBO(0, 0, 0, 0.42);

  double get _up => s._cosP * s._u; // screen px per world unit of height

  void _prop(Canvas canvas, bool flip, PropArt a, Offset g, double k, Paint pq) {
    canvas.save();
    canvas.translate(g.dx, g.dy);
    if (flip) canvas.scale(-1, 1);
    canvas.scale(k);
    canvas.drawImage(a.img, Offset(-a.ax, -a.ay), pq);
    canvas.restore();
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
    if (a.flash > 0) p.colorFilter = ColorFilter.mode(Color.fromRGBO(255, 255, 255, (a.flash / 0.14).clamp(0.0, 1.0) * 0.75), BlendMode.srcATop);
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
      canvas.rotate(gait.roll[col] * math.pi / 180 * math.cos(face));
      final sit = w.pose == 'sit';
      canvas.scale(w.sx, w.sy * gait.squash[col] * (sit ? 0.82 : 1));
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
      canvas.scale(f.sx, f.sy * squash);
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
        canvas.drawPath(_poly(rect(mk.len)), edge);
        // chevrons along it, pointing the way it will come
        final ch = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..strokeCap = StrokeCap.round
          ..color = const Color(0xCCFFE2D6);
        for (var d = 16.0; d < mk.len - 6; d += 22) {
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
        Widget row(Widget face, String name, double hp, double maxHp, {double? stamina, bool lead = false, List<String> tags = const []}) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                face,
                const SizedBox(width: 6),
                Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(name, style: EvochiText.tag.copyWith(color: const Color(0xFFFFF3DC), fontSize: lead ? 13 : 12)),
                    const SizedBox(width: 6),
                    Text('${hp.ceil()}', style: EvochiText.tag.copyWith(color: const Color(0xFFB8E68C), fontSize: 11)),
                    for (final t in tags) ...[
                      const SizedBox(width: 4),
                      _Tag(t),
                    ],
                  ]),
                  const SizedBox(height: 3),
                  _Bar(width: lead ? 96 : 72, frac: maxHp <= 0 ? 0 : hp / maxHp, color: hp / maxHp < 0.3 ? const Color(0xFFE5675B) : const Color(0xFF6CC24A)),
                  if (stamina != null) ...[
                    const SizedBox(height: 2),
                    _Bar(width: lead ? 96 : 72, frac: stamina / 100, color: const Color(0xFF4FA3E0), height: 5),
                  ],
                ]),
              ]),
            );
        return Semantics(
          label: 'Party: ${pet?.name ?? 'your Evochi'} ${r.pet.hp.ceil()} of ${r.pet.maxHp.round()} Raid HP${sher != null ? ', Sher ${sher.hp.ceil()} HP' : ''}',
          child: ExcludeSemantics(
            child: Container(
              padding: const EdgeInsets.fromLTRB(6, 6, 10, 0),
              decoration: BoxDecoration(color: const Color(0xB32A1D10), borderRadius: BorderRadius.circular(14)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                if (pet != null)
                  row(EncFace.pet(pet, size: 38), pet.name, r.pet.hp, r.pet.maxHp, stamina: r.stamina, lead: true, tags: [if (r.pet.slowT > 0) 'Spored']),
                if (sher != null) row(const SherFace(size: 32), 'Sher', sher.hp, sher.maxHp, tags: [if (r.sherWinded > 0) 'Winded']),
              ]),
            ),
          ),
        );
      },
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(5, 1, 5, 1),
        decoration: BoxDecoration(color: text == 'Spored' ? const Color(0xFF7A5BB0) : const Color(0xFF8A6A4A), borderRadius: BorderRadius.circular(6)),
        child: Text(text, style: EvochiText.tag.copyWith(color: Colors.white, fontSize: 10)),
      );
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
        decoration: BoxDecoration(color: const Color(0xFF1A120A), borderRadius: BorderRadius.circular(height)),
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: frac.clamp(0.0, 1.0),
          heightFactor: 1,
          child: DecoratedBox(decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(height))),
        ),
      );
}

/// The objective, or (while it fights) the guardian's health with its phase notches.
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
          return Container(
            padding: const EdgeInsets.fromLTRB(10, 5, 12, 6),
            decoration: BoxDecoration(color: const Color(0xB32A1D10), borderRadius: BorderRadius.circular(12)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const SparkIcon(size: 16),
              const SizedBox(width: 6),
              Flexible(child: Text(text, style: EvochiText.tag.copyWith(color: const Color(0xFFFFF3DC), fontSize: 12), overflow: TextOverflow.ellipsis)),
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
      child: Container(
        constraints: const BoxConstraints(maxWidth: 360),
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
        decoration: BoxDecoration(color: const Color(0xCC1E1424), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFF3B2923), width: 2)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            Text('Briarback', style: EvochiText.tag.copyWith(color: const Color(0xFFFFF3DC), fontSize: 13)),
            const SizedBox(width: 6),
            Text(boss.stage >= 3 ? 'Enraged' : 'Guardian of the Thicket', style: EvochiText.tag.copyWith(color: const Color(0xFFD9C2FF), fontSize: 11)),
          ]),
          const SizedBox(height: 4),
          LayoutBuilder(builder: (context, cons) {
            final w = math.min(cons.maxWidth, 300.0);
            return SizedBox(
              width: w,
              height: 10,
              child: Stack(children: [
                _Bar(width: w, height: 10, frac: f, color: col),
                for (final n in const [0.6, 0.3])
                  Positioned(left: w * n - 1, top: 0, bottom: 0, child: Container(width: 2, color: const Color(0xFFFFF3DC))),
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

/// What you have found and not yet brought home.
class _SatchelPill extends StatelessWidget {
  const _SatchelPill({required this.state});
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
              padding: const EdgeInsets.fromLTRB(6, 3, 9, 4),
              decoration: BoxDecoration(color: const Color(0xB32A1D10), borderRadius: BorderRadius.circular(12)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const VoxelIcon('coin', size: 18),
                const SizedBox(width: 3),
                Text('${r.coins}', style: EvochiText.tag.copyWith(color: const Color(0xFFFFE08A), fontSize: 12)),
                if (n > 0) ...[
                  const SizedBox(width: 6),
                  const ItemImage('lumen_shard', size: 18),
                  Text('$n', style: EvochiText.tag.copyWith(color: const Color(0xFFC9F5EA), fontSize: 12)),
                ],
              ]),
            ),
          );
        },
      );
}

/// The action pad: Pounce (big), Dodge, Glow Bolt and Lumen Pulse (cooldown rings), a healing item, Run;
/// and the context button (Talk, Look, Leave) above it when something is near.
class _CombatPad extends StatelessWidget {
  const _CombatPad({required this.state});
  final _WildsScreenState state;
  @override
  Widget build(BuildContext context) {
    final c = context.watch<GameController>();
    final healId = w.nextHealItem(c.state);
    final heals = w.healItemCount(c.state);
    final s = state;
    final r = s._raid!;
    final near = s._near;
    final talk = (s._nearSher && (near == null || !r.party)) || s._nearBoss;
    final ctx = talk || near != null;
    return ValueListenableBuilder<int>(
      valueListenable: s._repaint,
      builder: (context, _, child) {
        final st = r.stamina;
        return SizedBox(
          width: 204,
          height: ctx ? 246 : 176,
          child: Stack(clipBehavior: Clip.none, children: [
            if (ctx)
              Positioned(
                right: 2,
                top: 0,
                child: _ActionButton(
                  label: s._nearBoss ? 'Spar' : (talk ? (r.party ? 'Chat' : 'Talk') : near!.label),
                  icon: talk ? Icons.chat_bubble_rounded : Icons.touch_app_rounded,
                  big: true,
                  onTap: s._interact,
                ),
              ),
            Positioned(
              right: 0,
              bottom: 0,
              child: _PadButton(
                label: 'Pounce',
                icon: Icons.pets_rounded,
                size: 80,
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
              right: 86,
              bottom: 0,
              child: _PadButton(label: 'Dodge', icon: Icons.rotate_left_rounded, size: 56, tone: const Color(0xFFB8E68C), dim: st < 20, onDown: () => s._press('dodge')),
            ),
            Positioned(
              right: 74,
              bottom: 64,
              child: _PadButton(
                label: 'Bolt',
                icon: Icons.blur_on_rounded,
                size: 54,
                tone: const Color(0xFF9FF0DA),
                cooldown: r.boltCd / 1.0,
                dim: st < 18,
                onDown: () => s._press('bolt'),
              ),
            ),
            Positioned(
              right: 8,
              bottom: 88,
              child: _PadButton(
                label: 'Pulse',
                icon: Icons.flare_rounded,
                size: 54,
                tone: const Color(0xFFC9F5EA),
                cooldown: r.pulseCd / 7.0,
                dim: st < 34,
                onDown: () => s._press('pulse'),
              ),
            ),
            Positioned(
              right: 150,
              bottom: 2,
              child: _PadButton(
                label: heals > 0 ? '$heals' : 'Heal',
                image: healId,
                icon: Icons.local_dining_rounded,
                size: 48,
                tone: const Color(0xFFFFF0DE),
                cooldown: s._itemCd / 2.5,
                dim: heals == 0,
                onDown: () => s._press('item'),
              ),
            ),
            Positioned(
              right: 140,
              bottom: 58,
              child: _PadButton(
                label: 'Run',
                icon: Icons.directions_run_rounded,
                size: 42,
                tone: s._runToggle ? const Color(0xFF6CC24A) : const Color(0xFFE6D3AE),
                onDown: s._toggleRun,
              ),
            ),
          ]),
        );
      },
    );
  }
}

class _PadButton extends StatelessWidget {
  const _PadButton({required this.label, required this.icon, required this.size, required this.tone, required this.onDown, this.onUp, this.cooldown = 0, this.dim = false, this.image});
  final String label;
  final IconData icon;
  final double size, cooldown;
  final Color tone;
  final VoidCallback onDown;
  final VoidCallback? onUp;
  final bool dim;
  final String? image;
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
            opacity: dim ? 0.55 : 1,
            child: SizedBox(
              width: size,
              height: size,
              child: Stack(children: [
                Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(center: const Alignment(-0.2, -0.35), colors: [Color.lerp(tone, Colors.white, 0.55)!, tone]),
                    border: Border.all(color: const Color(0xFF3B2923), width: 2.5),
                    boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 6, offset: Offset(0, 3))],
                  ),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    if (image != null) ItemImage(image!, size: size * 0.46) else Icon(icon, size: size * 0.36, color: EvochiColor.ink),
                    Text(label, style: EvochiText.tag.copyWith(color: EvochiColor.ink, fontSize: size > 70 ? 13 : 10.5, height: 1.05)),
                  ]),
                ),
                if (!ready) Positioned.fill(child: CustomPaint(painter: _CooldownPainter(cooldown.clamp(0.0, 1.0)))),
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
    canvas.drawArc(r.deflate(2), -math.pi / 2, 2 * math.pi * left, true, Paint()..color = const Color(0x8C1A120A));
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

/// The context button (Talk, Look, Leave, Spar).
class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.label, required this.icon, required this.onTap, this.big = false});
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool big;
  @override
  Widget build(BuildContext context) {
    final d = big ? 70.0 : 58.0;
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        child: ExcludeSemantics(
          child: Container(
            width: d,
            height: d,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const RadialGradient(center: Alignment(-0.2, -0.35), colors: [Color(0xFFFFF0B0), EvochiColor.primary]),
              border: Border.all(color: const Color(0xFF3B2923), width: 2.5),
              boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 6, offset: Offset(0, 3))],
            ),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(icon, size: big ? 24 : 22, color: EvochiColor.ink),
              Text(label, style: EvochiText.tag.copyWith(color: EvochiColor.ink, fontSize: big ? 12 : 11, height: 1.1)),
            ]),
          ),
        ),
      ),
    );
  }
}

/// The minimap: the floor around you, top-down, north up; the gate, the camp, Sher, the foes and the
/// guardian marked. Tap for the whole floor.
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
            child: Container(
              width: 92,
              height: 92,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF3B2923), width: 2.5),
                boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 6, offset: Offset(0, 2))],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(11),
                child: CustomPaint(painter: _MiniPainter(state, span: 220, repaint: state._repaint)),
              ),
            ),
          ),
        ),
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
          for (final e in items.entries) chip(ItemImage(e.key, size: 26), '${catalog[e.key]?.name ?? e.key} x${e.value}'),
        ]),
        if (satchelCoins > 0 || satchelItems.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('Your satchel comes home too: ${[if (satchelCoins > 0) '$satchelCoins EvoCoins', for (final e in satchelItems.entries) '${e.value} ${catalog[e.key]?.name ?? e.key}'].join(', ')}.',
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
class _Offer extends StatelessWidget {
  const _Offer({required this.onJoin, required this.onLater});
  final VoidCallback onJoin, onLater;
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
                const Text('A scout who knows the Wilds', style: EvochiText.caption),
              ]),
            ),
          ]),
          const SizedBox(height: 8),
          Text('Heading deeper? Something Hollow has the wood on edge, and the old guardian at the gate isn\'t itself. Two are safer than one. Mind if I join your party?',
              style: EvochiText.bodyText.copyWith(height: 1.35)),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: EvochiButton(label: 'Not now', tone: ButtonTone.cream, onPressed: onLater)),
            const SizedBox(width: 8),
            Expanded(child: EvochiButton(label: 'Join my party', tone: ButtonTone.green, onPressed: onJoin)),
          ]),
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
