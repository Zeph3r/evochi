// The Shorts the recorder makes (record_test.dart): each one is a few clips of the real game, played by
// the autopilot and steered by beats (a debug shortcut, a nudge to the fight, a caption), then the end
// card. Times are seconds into the clip; captions placed by a beat appear at the moment it fires.
//
// The Wilds series (action): sentinel, briarback, deep, signatures.

import 'dart:async';
import 'dart:math' as math;

import 'package:evochi/controllers/game_controller.dart';
import 'package:evochi/core/models/game_state.dart';
import 'package:evochi/core/utils/day_keys.dart';
import 'package:evochi/features/home/nook_sheet.dart';
import 'package:evochi/features/shared/kit.dart';
import 'package:evochi/features/village/village_walk.dart';
import 'package:evochi/game/hatch/hatch.dart' as hatch;
import 'package:evochi/features/wilds/wilds_combat.dart';
import 'package:evochi/features/wilds/wilds_screen.dart';
import 'package:evochi/game/engine.dart' as g;
import 'package:evochi/game/story/story.dart' as q;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ------------------------------------------------------------------------------------- the pieces
/// What a beat can reach while recording (a take of the camera).
abstract class Take {
  int get frame;
  double get t; // the video's clock
  WildsDirectorHandle? get screen;
  Raid? get raid;
  VillageWalkScreenState? get walk; // a walkable map, when one is up
  Pilot get autopilot;
  GameState get state;
  GameController get ctl;
  int get clip;
  Future<void> step();
  Future<void> waitLoaded();
  Future<void> key(LogicalKeyboardKey k);
  Future<void> tapText(String text); // a button by its words

  /// A moment a beat noted (the video's clock), for a clip to end after.
  double? mark;

  /// A caption from now, for [secs].
  void say(List<(String, Color)> spans, {double secs = 2.0, double size = 26, double y = 190});
}

class Beat {
  const Beat(this.at, this.run, {this.when});
  final double at; // seconds into the clip (the earliest it may fire)
  final FutureOr<void> Function(Take s) run;

  /// It waits for this too (checked every frame from [at]).
  final bool Function(Take s)? when;
}

class PilotStart {
  const PilotStart({this.on = true, this.signature = true, this.bolts = true, this.dodges = true, this.prefer});
  final bool on, signature, bolts, dodges;
  final Set<String>? prefer;
}

class Clip {
  const Clip({
    required this.state,
    required this.open,
    required this.secs,
    this.setup,
    this.preroll = 0.8,
    this.beats = const [],
    this.pilot,
    this.until,
    this.zoom = 0.8,
    this.quiet = false,
    this.loaded,
    this.exits = true,
  });
  final GameState Function() state;
  final Widget Function() open;

  /// The longest it runs (seconds); it ends sooner once [until] holds.
  final double secs;
  final bool Function(Take s)? until;
  final FutureOr<void> Function(Take s)? setup; // before the camera rolls
  final double preroll; // game time run before the camera rolls (not captured)
  final List<Beat> beats;
  final PilotStart? pilot;

  /// The camera's reach (under 1: closer than the game's own).
  final double zoom;

  /// No "clearing is calm" banner over the action.
  final bool quiet;

  /// When this clip's screen counts as up (null: a Wilds floor's fight, a walkable map's tiles).
  final bool Function()? loaded;

  /// On a walkable map, whether walking into a way out leads through it (false: it only stops you).
  final bool exits;
}

class Cap {
  Cap(this.t0, this.t1, this.spans, {this.size = 26, this.y = 190});
  final double t0;
  double t1; // a newer caption cuts it short
  final List<(String, Color)> spans;
  final double size, y; // logical px (the video is 3x)
}

class Short {
  const Short({
    required this.id,
    required this.clips,
    required this.endTitle,
    this.caps = const [],
    this.stamp,
    this.cta = 'Join the beta waitlist',
    this.endSecs = 2.7,
    this.music,
  });
  final String id;
  final List<Clip> clips;
  final List<Cap> caps; // at fixed times of the video (beats add more as they fire)
  final String? stamp;
  final List<(String, Color?)> endTitle;
  final String cta;
  final double endSecs;
  final String? music; // the bed under the whole video (an ambient loop's name); null: the game's own calls
}

// colours of the captions
const white = Color(0xFFFFF9F0);
const gold = Color(0xFFFFE5A2);
const blue = Color(0xFFBFE4FA);
const pink = Color(0xFFFFC4D6);
const mint = Color(0xFFC9F0E8);
const lilac = Color(0xFFD9C2FF);

/// The autopilot: closes in on the nearest creature still fighting and keeps up a combo, rolls out of
/// anything about to land on it, fires a Bolt at range, a Pulse when crowded, and its signature move
/// when it is ready.
class Pilot {
  bool on = true;
  bool signature = true;
  bool bolts = true;
  bool dodges = true;

  /// Only these kinds are chased (null: any); e.g. the Sentinel, not what it called.
  Set<String>? prefer;

  /// Steer here instead of fighting (a walk-in), until reached.
  Offset? walkTo;
  bool walkRun = false;

  /// An ore node to work: steer to it, then strike until it bursts, a strike every [mineEvery] seconds
  /// (0: as fast as the swing allows).
  OreRock? mineAt;
  double mineEvery = 0, _struck = -9;
  final _rng = math.Random(3);
  double _last = 0, _dodgeCd = 0, _stuck = 0, _lx = 0, _lz = 0;

  void reset(PilotStart? s) {
    on = s?.on ?? true;
    signature = s?.signature ?? true;
    bolts = s?.bolts ?? true;
    dodges = s?.dodges ?? true;
    prefer = s?.prefer;
    walkTo = null;
    mineAt = null;
    mineEvery = 0;
    _struck = -9;
    _last = 0;
    _dodgeCd = 0;
  }

  void call(Raid r, RaidInput i, double t) {
    final dt = (t - _last).clamp(0.0, 0.1);
    _last = t;
    _dodgeCd -= dt;
    final p = r.pet;
    final w = walkTo;
    if (w != null) {
      final dx = w.dx - p.x, dz = w.dy - p.z;
      if (dx * dx + dz * dz < 36) {
        walkTo = null;
      } else {
        i
          ..mx = dx
          ..mz = dz
          ..run = walkRun;
        return;
      }
    }
    final o = mineAt;
    if (o != null) {
      if (o.broken) {
        mineAt = null;
        _stuck = 0;
      } else {
        final dx = o.x - p.x, dz = o.z - p.z;
        final d = math.sqrt(dx * dx + dz * dz);
        // the swing reaches 9 ahead and takes a node within 22 of that: strike from 30 out, or as soon
        // as the rock's own footprint stops the walk (the node sits in blocked cells)
        final moved = (p.x - _lx).abs() + (p.z - _lz).abs();
        _lx = p.x;
        _lz = p.z;
        _stuck = moved < 0.2 ? _stuck + dt : 0;
        if (d > 30 && _stuck < 0.4) {
          i
            ..mx = dx
            ..mz = dz
            ..run = d > 70;
        } else {
          final go = t - _struck >= mineEvery;
          if (go) _struck = t;
          i
            ..mx = dx
            ..mz = dz
            ..speed = 0.08
            ..attack = go;
        }
        return;
      }
    }
    if (!on) return;
    // something about to land on it: roll out of it (sideways out of a line or a sweep)
    if (dodges && _dodgeCd <= 0) {
      for (final m in r.marks) {
        if (m.done || m.p < 0.5 || !m.covers(p.x, p.z, p.radius + 3)) continue;
        var ax = p.x - m.x, az = p.z - m.z;
        if (m.shape == MarkShape.line || m.shape == MarkShape.cone) {
          ax = -m.dz;
          az = m.dx;
          if ((p.x - m.x) * ax + (p.z - m.z) * az < 0) {
            ax = -ax;
            az = -az;
          }
        }
        if (ax.abs() + az.abs() < 1e-3) ax = 1;
        i
          ..mx = ax
          ..mz = az
          ..run = true
          ..dodge = true;
        _dodgeCd = 0.55;
        return;
      }
    }
    final foes = [
      for (final f in r.hostile)
        if (prefer == null || prefer!.contains(f.kind)) f
    ];
    if (foes.isEmpty) return;
    foes.sort((a, b) => p.dist(a).compareTo(p.dist(b)));
    final f = foes.first;
    final d = p.dist(f);
    final reach = p.radius + f.radius + 9;
    if (signature && r.sigReady && d < 95) r.press('signature');
    if (bolts && d > 55 && d < 170 && _rng.nextDouble() < 0.05) i.bolt = true;
    if (r.hostile.where((o) => p.dist(o) < 48).length >= 2 && _rng.nextDouble() < 0.04) i.pulse = true;
    if (d > reach) {
      i
        ..mx = f.x - p.x
        ..mz = f.z - p.z
        ..run = d > 80;
    } else {
      i
        ..mx = f.x - p.x
        ..mz = f.z - p.z
        ..speed = 0.12
        ..attack = true;
    }
  }
}

// ------------------------------------------------------------------------------------- the save
final _t0 = DateTime.utc(2026, 10, 21, 18).millisecondsSinceEpoch;

/// A fresh save with Mochi, an Elder of [palette], some berries and the brews the Shorts use. With
/// [sentinelJob], the Trail Guild's Sentinel job is ready to hand in at its gate.
GameState mochi(String palette, {int stage = 3, bool sentinelJob = false}) {
  var s = GameState.fresh(_t0, 'America/New_York');
  s = g.startGuest(s, _t0, 'America/New_York').state;
  s = g.setConnection(s, 'demo', _t0).state;
  s = g.createPet(s, name: 'Mochi', paletteId: palette, requestId: 'req-shorts', now: _t0).state;
  s = s.copy();
  s.pet!
    ..stage = stage
    ..xpAwarded['shorts'] = 4000;
  for (final (id, n) in const [('berry_snack', 6), ('lantern_tonic', 2), ('golden_bun', 2)]) {
    g.grantItem(s, id, n, 'shorts', _t0);
  }
  if (sentinelJob) {
    final day = dayKey(_t0, 'America/New_York');
    for (final dep in const ['vq01', 'vq02', 'vq03', 'hq01', 'eq01', 'eq02']) {
      s.story.questStates[dep] = QuestState.fromJson({'phase': 'completed', 'acceptedAt': _t0 - 2 * hourMs, 'acceptedDay': day, 'resolvedSteps': 1000, 'completedAt': _t0 - hourMs});
    }
    s.story.questStates['eq03'] = QuestState.fromJson({'phase': 'gate_ready', 'acceptedAt': _t0 - hourMs, 'acceptedDay': day, 'resolvedSteps': 3000});
    s.story.questPouch['q_old_trail_map'] = 1;
    assert(q.nextStep(s, 'eq03').kind == 'encounter');
  }
  return s;
}

// ------------------------------------------------------------------------------------- helpers
Future<void> _god(Take s) => s.key(LogicalKeyboardKey.keyG);
Foe? _sentinel(Take s) => s.raid?.sentinel;

/// Your Evochi set down on open ground about [dist] from (x, z), south of it first (so what it faces is
/// up the screen), clear of the trees' trunks.
void placeNear(Take s, double x, double z, {double dist = 40}) {
  final r = s.raid!, m = s.screen!.map!;
  final rad = r.pet.radius;
  bool free(double px, double pz) {
    for (final (dx, dz) in const [(0.0, 0.0), (7.0, 0.0), (-7.0, 0.0), (0.0, 6.0), (0.0, -6.0)]) {
      if (m.blocked(px + dx, pz + dz)) return false;
    }
    for (final (bx, bz, br) in r.ground.blocks) {
      final dx = bx - px, dz = bz - pz;
      if (dx * dx + dz * dz < (br + rad + 5) * (br + rad + 5)) return false;
    }
    return true;
  }

  for (var d = dist; d < dist + 140; d += 6) {
    for (final a in const [0.0, -0.45, 0.45, -0.9, 0.9, -1.4, 1.4, 3.14]) {
      final ang = math.pi / 2 + a;
      final px = x + math.cos(ang) * d, pz = z + math.sin(ang) * d;
      if (free(px, pz)) {
        r.pet
          ..x = px
          ..z = pz
          ..face(x - px, z - pz);
        return;
      }
    }
  }
}

/// Into the first clearing of the floor that is up, a little south of its middle.
void toFirstClearing(Take s, {double dist = 34}) {
  final zs = s.screen!.map!.zones;
  if (zs.isEmpty) return;
  placeNear(s, zs.first.$3, zs.first.$4, dist: dist);
}

// ------------------------------------------------------------------------------------- the Shorts
final allShorts = <Short>[sentinel, briarback, deep, signatures];

/// The week of Oct 27 (the formula: hook on frame one, the turn at 5-7 s, the payoff at 10-12, a loopable end).
final weekShorts = <Short>[mineShort, coinsShort, eggShort, groveShort, tidalShort, laneShort, shaftShort, stagesShort];

/// Two seconds of a floor, to time the recorder (never part of 'all').
final bench = Short(
  id: 'bench',
  endTitle: const [('Bench', null)],
  endSecs: 0.4,
  clips: [
    Clip(
      state: () => mochi('coral'),
      open: () => const WildsScreen(depth: 5, seed: 777, story: 'eq03', forceStory: true),
      secs: 1.0,
      preroll: 0.5,
      setup: (s) => toFirstClearing(s),
      beats: [Beat(0, (s) => s.autopilot.walkTo = Offset(s.raid!.pet.x, s.raid!.pet.z - 60))],
    ),
  ],
);

/// 1. The Forgotten Sentinel: a walk up to the old gate; it wakes (its cinematic); the fight, its
/// shield broken with a Lantern Tonic; restored, it bows.
final sentinel = Short(
  id: 'sentinel',
  stamp: 'THE WILDS · 01',
  music: 'enc_boss_loop',
  endTitle: const [('Your steps.\n', null), ('Your adventure.', Color(0xFF6E4FA3))],
  clips: [
    Clip(
      state: () => mochi('ocean', sentinelJob: true),
      open: () => const WildsScreen(depth: 5, seed: 777, story: 'eq03', forceStory: true),
      secs: 30,
      preroll: 1.2,
      pilot: const PilotStart(prefer: {'sentinel'}),
      setup: (s) async {
        await _god(s);
        final r = s.raid!..holdSentinel = true;
        // at the arena's south edge, it asleep until the walk-in (the camera settles in the preroll)
        placeNear(s, r.storyX, r.storyZ, dist: 98);
        s.autopilot.on = false;
      },
      beats: [
        Beat(0.05, (s) {
          final r = s.raid!;
          s.autopilot.walkTo = Offset(r.storyX, r.storyZ + 50);
          s.say(const [('I walked ', white), ('3,000 steps', gold), ('\nto find this...', white)], secs: 1.9, size: 27);
        }),
        Beat(1.4, (s) => s.raid!.holdSentinel = false),
        // the fight, once its entrance has played
        Beat(2.0, (s) {
          s.autopilot.on = true;
          s.say(const [('Roll through ', white), ('everything', gold)], secs: 1.8);
        }, when: (s) => _sentinel(s)?.st == FoeState.engage),
        // its shield: the next hit brings it up
        Beat(6.5, (s) {
          final st = _sentinel(s)!;
          st.hp = math.min(st.hp, st.maxHp * 0.665);
        }, when: (s) => (_sentinel(s)?.st ?? FoeState.dormant) != FoeState.dormant && _sentinel(s)?.st != FoeState.roar),
        Beat(6.6, (s) => s.say(const [('It hides behind a\n', white), ('Hollow shield', lilac)], secs: 1.8), when: (s) => s.raid!.sentinelShield > 0),
        Beat(8.2, (s) {
          final r = s.raid!;
          r.applyBuff('lantern', secs: 30);
          r.sentinelShield = math.min(r.sentinelShield, r.sentinelShieldMax * 0.22);
          s.screen?.banner('Lantern Tonic: Lumen pours off Mochi!', 1.8);
          s.say(const [('Lantern Tonic:', gold), ('\nLIGHT IT UP', white)], secs: 1.7, size: 28);
        }, when: (s) => s.raid!.sentinelShield > 0),
        // shattered: the finish (no second shield)
        Beat(9.0, (s) {
          s.raid!.sentinelShields = 2;
          final st = _sentinel(s)!;
          st.hp = math.min(st.hp, st.maxHp * 0.04);
        }, when: (s) => s.raid!.sentinelShields > 0 && s.raid!.sentinelShield <= 0),
        Beat(9.2, (s) {
          s.mark = s.t;
          s.say(const [('It ', white), ('remembered', mint), ('\nwho it was.', white)], secs: 2.4, size: 27);
        }, when: (s) => s.raid!.storyDone),
      ],
      // the bow, then out before the quest card comes up
      until: (s) => s.mark != null && s.t - s.mark! > 2.25,
    ),
  ],
);

/// 2. The Briarback: in through its brambles; its entrance; the fight, a perfect dodge, its signature
/// move; calmed.
final briarback = Short(
  id: 'briarback',
  stamp: 'THE WILDS · 02',
  music: 'enc_boss_loop',
  endTitle: const [('Every step\n', null), ('levels you up.', Color(0xFFC8832C))],
  clips: [
    Clip(
      state: () => mochi('amber'),
      open: () => const WildsScreen(),
      secs: 30,
      preroll: 1.2,
      setup: (s) async {
        await _god(s);
        await s.key(LogicalKeyboardKey.digit4); // the arena's edge
        s.autopilot.on = false;
      },
      beats: [
        Beat(0.05, (s) {
          final b = s.raid!.boss!;
          s.autopilot.walkTo = Offset(b.x, b.z + 60);
          s.say(const [('A ', white), ('step counter', gold), ('\nwith ', white), ('BOSS FIGHTS?', pink)], secs: 2.4, size: 28);
        }),
        Beat(1.0, (s) {
          s.autopilot
            ..on = true
            ..walkTo = null;
        }, when: (s) => s.raid!.bossState == BossState.fight),
        Beat(4.5, (s) {
          s.raid!.sig = 100;
          s.say(const [('Elder move:', white), ('\nSUNFLARE', gold)], secs: 1.8, size: 28);
        }, when: (s) => s.raid!.bossState == BossState.fight),
        Beat(7.5, (s) async {
          for (var i = 0; i < 4; i++) {
            await s.key(LogicalKeyboardKey.keyB);
          }
        }, when: (s) => s.raid!.bossState == BossState.fight),
        Beat(8.0, (s) {
          s.mark = s.t;
          s.say(const [('Calmed,', white), ('\nnot beaten.', mint)], secs: 2.4);
        }, when: (s) => s.raid!.bossState == BossState.calm),
      ],
      until: (s) => s.mark != null && s.t - s.mark! > 2.4,
    ),
  ],
);

/// 3. The Deep Wilds: a clearing calmed, the way down opens, down a floor, and a Hollow Surge.
final deep = Short(
  id: 'deep',
  stamp: 'THE WILDS · 03',
  music: 'enc_wild_loop',
  endTitle: const [('Walk more.\n', null), ('Go deeper.', Color(0xFF477B3A))],
  clips: [
    Clip(
      state: () => mochi('coral'),
      open: () => const WildsScreen(depth: 2, seed: 5),
      secs: 15.5,
      preroll: 1.0,
      setup: (s) async {
        await _god(s);
        toFirstClearing(s);
      },
      beats: [
        Beat(0.1, (s) => s.say(const [('Every floor is\n', white), ('made fresh', mint)], secs: 2.2, size: 28)),
        Beat(3.2, (s) => s.key(LogicalKeyboardKey.keyC)),
        Beat(3.5, (s) => s.say(const [('Calm it, and the\n', white), ('way down opens', gold)], secs: 1.8)),
        Beat(5.0, (s) async {
          await s.key(LogicalKeyboardKey.keyN);
          toFirstClearing(s);
        }),
        Beat(5.2, (s) => s.say(const [('F2... F3... F4...', white)], secs: 2.2, size: 30)),
        Beat(6.3, (s) async {
          await s.key(LogicalKeyboardKey.keyN);
          toFirstClearing(s);
        }),
        Beat(7.4, (s) async {
          await s.key(LogicalKeyboardKey.keyH);
          toFirstClearing(s);
        }),
        Beat(7.6, (s) => s.say(const [('...until the Hollow\n', white), ('SURGES', lilac)], secs: 2.2, size: 30)),
        Beat(11.6, (s) => s.key(LogicalKeyboardKey.keyC)),
        Beat(11.9, (s) => s.say(const [('Bigger fights.\n', white), ('Bigger loot.', gold)], secs: 2.4, size: 28)),
      ],
    ),
  ],
);

/// 4. Every Elder's signature move, one after another: in close, into a fight, then the move.
Clip _sigClip(String palette, String colour, Color col, {bool first = false}) => Clip(
      state: () => mochi(palette),
      open: () => const WildsScreen(depth: 2, seed: 9),
      secs: first ? 3.0 : 2.3,
      preroll: 1.3,
      zoom: 0.62,
      quiet: true,
      pilot: const PilotStart(signature: false, bolts: false),
      setup: (s) async {
        await _god(s);
        toFirstClearing(s, dist: 26);
      },
      beats: [
        if (first) Beat(0.05, (s) => s.say(const [('Every Elder has a\n', white), ('signature move', gold)], secs: 1.3, size: 27, y: 165)),
        Beat(first ? 1.15 : 0.45, (s) {
          s.raid!
            ..sig = 100
            ..press('signature');
          s.say([('$colour\n', col), (Raid.sigNames[palette]!.toUpperCase(), white)], secs: 1.7, size: 30, y: 165);
          // up top (lower down, the long names ran into the action buttons); gone by the clip's end, so
          // a name never sits over the next Evochi
        }),
      ],
    );

final signatures = Short(
  id: 'signatures',
  stamp: 'THE WILDS · 04',
  music: 'enc_wild_loop',
  endTitle: const [('Which one\n', null), ('is yours?', Color(0xFF6E4FA3))],
  clips: [
    _sigClip('ocean', 'Ocean', blue, first: true),
    _sigClip('amber', 'Amber', gold),
    _sigClip('amethyst', 'Amethyst', lilac),
    _sigClip('forest', 'Forest', mint),
    _sigClip('coral', 'Coral', pink),
    _sigClip('obsidian', 'Obsidian', const Color(0xFFCFD8EE)),
  ],
);

// ------------------------------------------------------------------------------- the week of Oct 27
// Saves for the week: an egg in a cradle, a hatched companion resting at home.

/// Mochi with [template] egg in the first cradle, [progress] steps along.
GameState withEgg(String palette, String template, {int progress = 0, bool ready = false}) {
  var s = mochi(palette);
  s = s.copy();
  g.addTxn(s, WalletTxn(id: 'shorts:glimmer', amount: 1000, cause: 'shorts', at: _t0, currency: 'glimmer'));
  final r = template == 'forest_egg' || template == 'stone_egg'
      ? hatch.findEgg(s, template, 'Found in the Deep Wilds', 'shorts:$template', _t0)
      : hatch.buyEgg(s, template, 'shorts:$template', _t0);
  assert(r.error == null, r.error);
  s = hatch.assignEgg(r.state, r.state.hatch.eggs.single.id, _t0).state.copy();
  final e = s.hatch.eggs.single;
  e.progress = progress;
  if (ready) {
    e.progress = hatch.eggTemplates[template]!.need;
    e.state = 'ready';
  }
  return s;
}

/// Mochi, with a hatchling called [name] (from a forest egg) resting at home.
GameState withCompanion(String palette, String name) {
  var s = withEgg(palette, 'forest_egg', ready: true);
  final r = hatch.hatchEgg(s, s.hatch.eggs.single.id, name: name, requestId: 'shorts:hatch', now: _t0);
  assert(r.error == null, r.error);
  s = r.state;
  return s;
}

/// A screen for the Nook: the sheet as a window over the home's green.
Widget nookStage() => const Scaffold(
      backgroundColor: Color(0xFF86B566),
      body: SafeArea(
        child: Align(
          alignment: Alignment.bottomCenter,
          child: FramedWindow(
            padding: EdgeInsets.fromLTRB(10, 8, 10, 14),
            shadow: BoxShadow(color: Color(0x4D000000), blurRadius: 18, offset: Offset(0, -6)),
            child: SingleChildScrollView(child: NookSheet(scale: 1.55)),
          ),
        ),
      ),
    );

/// Where the Nook Shorts' captions sit: over the egg's card, clear of the egg.
const _nookY = 276.0; // between the cradle and the egg's card: clear of the egg and of the card's small print

/// Set your Evochi down just south of the nearest [kind] node (on a cut: a new floor coming up) and
/// have it work the node: the pilot steers straight, and a gallery's rock is in the way of straight.
OreRock? toOre(Take s, String kind, {bool work = true}) {
  final o = _ore(s, kind) ?? _ore(s, '');
  if (o == null) return null;
  placeNear(s, o.x, o.z, dist: 24);
  if (work) s.autopilot.mineAt = o;
  return o;
}

/// Move an egg along (the recorder's hand): [progress] steps, and ready if it is there.
void eggTo(Take s, int progress) {
  s.ctl.run((st, n) {
    final t = st.copy();
    final e = t.hatch.eggs.single;
    e.progress = progress;
    final need = hatch.eggTemplates[e.templateId]!.need;
    if (progress >= need) e.state = 'ready';
    return g.ActionResult(t);
  }, quiet: true);
}

OreRock? _ore(Take s, String kind) {
  final r = s.raid;
  if (r == null) return null;
  final p = r.pet;
  double d2(OreRock o) => (o.x - p.x) * (o.x - p.x) + (o.z - p.z) * (o.z - p.z);
  final list = r.ores.where((o) => !o.broken && (kind.isEmpty || o.kind == kind)).toList()..sort((a, b) => d2(a).compareTo(d2(b)));
  return list.firstOrNull;
}

/// Mon · A step counter where you MINE?? The Old Trail up into the portal; the first copper node;
/// the break; the nuggets into the satchel.
final mineShort = Short(
  id: 'mine',
  stamp: 'THE MINE · 01',
  music: 'enc_wild_loop',
  endTitle: const [('Walk there.\n', null), ('Dig it up.', Color(0xFF8D5D3B))],
  clips: [
    Clip(
      state: () => mochi('amber'),
      open: () => const VillageWalkScreen(map: 'trail', arrive: 'village'),
      secs: 17,
      preroll: 1.0,
      pilot: const PilotStart(on: false),
      setup: (s) async {
        final w = s.walk!;
        w.me
          ..x = 103.0
          ..z = -9.5
          ..dir = 2;
      },
      beats: [
        Beat(0.05, (s) {
          s.say(const [('A step counter\n', white), ('where you ', white), ('MINE??', gold)], secs: 2.2, size: 28);
          s.walk?.walkTo(116.5, -14.6);
        }),
        // in the mine (the cut is the walk through the portal): set down by the first copper, a beat to
        // look at it, then a strike every 1.5 s so it breaks at the payoff
        Beat(2.0, (s) => toOre(s, 'copper', work: false), when: (s) => s.raid != null),
        Beat(4.4, (s) {
          s.autopilot
            ..mineEvery = 1.5
            ..mineAt = _ore(s, 'copper');
          s.say(const [("That's copper.", white)], secs: 1.8);
        }, when: (s) => s.raid != null),
        Beat(6.0, (s) {
          s.say(const [('He walked here.\n', white), ('1,800 steps.', gold)], secs: 2.6, size: 27);
        }, when: (s) => (s.raid?.ores.any((o) => o.broken) ?? false)),
        Beat(11.5, (s) {
          s.mark = s.t;
          s.say(const [('Deeper tomorrow.', white)], secs: 2.2);
        }, when: (s) => s.raid != null),
      ],
      until: (s) => s.mark != null && s.t - s.mark! > 2.4,
    ),
  ],
);

/// Tue · In my game enemies don't drop loot. They drop COINS that fly to you.
final coinsShort = Short(
  id: 'coins',
  stamp: 'THE WILDS · 05',
  music: 'enc_wild_loop',
  endTitle: const [('Calm it.\n', null), ('Keep the coins.', Color(0xFFC8832C))],
  clips: [
    Clip(
      state: () => mochi('amber'),
      open: () => const WildsScreen(depth: 2, seed: 9),
      secs: 15,
      preroll: 1.2,
      zoom: 0.64,
      quiet: true,
      pilot: const PilotStart(on: false, signature: false, bolts: false),
      setup: (s) async {
        await _god(s);
        toFirstClearing(s, dist: 34);
      },
      beats: [
        Beat(0.05, (s) => s.say(const [("In my game enemies\n", white), ("don't drop loot.", white)], secs: 2.3, size: 27)),
        Beat(1.2, (s) {
          s.autopilot.on = true;
          // the nearest one goes down in a few hits (the take is about what it drops)
          final r = s.raid!;
          final f = (r.hostile.toList()..sort((a, b) => r.pet.dist(a).compareTo(r.pet.dist(b)))).firstOrNull;
          if (f != null) f.hp = math.min(f.hp, f.maxHp * 0.3);
        }),
        Beat(2.6, (s) => s.say(const [('They drop ', white), ('COINS', gold)], secs: 1.6, size: 32), when: (s) => (s.raid?.calmed ?? 0) > 0),
        Beat(2.7, (s) => s.mark = s.t, when: (s) => (s.raid?.calmed ?? 0) > 0),
        Beat(3.0, (s) => s.say(const [('...that fly to you', white)], secs: 1.8, size: 27), when: (s) => s.mark != null && s.t - s.mark! > 1.4),
        Beat(9.0, (s) => s.say(const [('Coins buy his looks.\n', white), ('Never his steps.', mint)], secs: 2.4, size: 26)),
        Beat(12.3, (s) => s.say(const [('Again.', white)], secs: 1.8, size: 30)),
      ],
    ),
  ],
);

/// Wed · I walked 2,000 steps and my egg hatched. The Nook: 100 to go, the steps, the hatch.
final eggShort = Short(
  id: 'egg',
  stamp: 'THE NOOK · 01',
  music: 'mus_lullaby',
  endTitle: const [('Steps hatch\n', null), ('new friends.', Color(0xFF5E7F4A))],
  clips: [
    Clip(
      state: () => withEgg('amber', 'tide_egg', progress: 2400),
      open: nookStage,
      secs: 16,
      preroll: 0.6,
      pilot: const PilotStart(on: false),
      loaded: () => true,
      beats: [
        Beat(0.05, (s) => s.say(const [('I walked ', white), ('2,000 steps', gold), ('\nand my egg hatched', white)], secs: 2.4, size: 27, y: _nookY)),
        Beat(2.8, (s) => s.say(const [('100 to go.', white)], secs: 1.6, size: 30, y: _nookY)),
        Beat(4.6, (s) => s.say(const [('So I went outside.', white)], secs: 2.0, size: 27, y: _nookY)),
        // the bar fills, step by step
        for (var k = 1; k <= 10; k++) Beat(4.8 + k * 0.16, (s) => eggTo(s, 2400 + k * 10)),
        Beat(6.9, (s) => s.say(const [("...and it's ready.", gold)], secs: 1.4, size: 28, y: _nookY)),
        Beat(8.4, (s) => s.tapText('Hatch')),
        Beat(12.2, (s) {
          final pet = hatch.allPets(s.state).where((p) => p.name == 'Little One').firstOrNull;
          if (pet != null) s.ctl.run((st, n) => hatch.renameCompanion(st, pet.id, 'Moss'), quiet: true);
          s.say(const [('Hi, Moss.', white)], secs: 1.8, size: 32, y: 72);
        }),
        Beat(14.2, (s) => s.say(const [("He's been waiting too.", white)], secs: 1.8, size: 26, y: 72)),
      ],
    ),
  ],
);

/// Thu · I got a second pet. The first one didn't mind. He made room. The Grove at home.
final groveShort = Short(
  id: 'grove',
  stamp: 'HOME · 01',
  music: 'mus_summer_morning',
  endTitle: const [('One walks.\n', null), ('The rest wait here.', Color(0xFF5E7F4A))],
  endSecs: 2.4,
  clips: [
    Clip(
      state: () => withCompanion('amber', 'Moss'),
      open: () => const VillageWalkScreen(map: 'home', arrive: 'nest'),
      secs: 14,
      preroll: 1.0,
      pilot: const PilotStart(on: false),
      exits: false,
      setup: (s) async {
        final w = s.walk!;
        // in the Grove, across the glade from the moss bed where the hatchling rests
        w.me
          ..x = -23.0
          ..z = 28.0
          ..dir = 6;
      },
      beats: [
        Beat(0.05, (s) => s.say(const [('I got a second pet.', white)], secs: 1.6, size: 28)),
        Beat(1.4, (s) => s.walk?.walkTo(-32.6, 27.2)),
        Beat(1.8, (s) => s.say(const [("I thought he'd be jealous.", white)], secs: 2.2, size: 26)),
        Beat(5.0, (s) {
          s.walk?.me.dir = 6;
          s.say(const [('He made room.', gold)], secs: 2.4, size: 32);
        }, when: (s) => !(s.walk?.me.moving ?? true)),
        Beat(10.4, (s) => s.say(const [('You can only walk one at a time.\n', white), ('The other waits here.', mint)], secs: 3.2, size: 24)),
      ],
    ),
  ],
);

/// Fri 5 · My pet's ULTIMATE is a tidal wave. An Ocean Elder, three Thornlings, Tidal Surge.
final tidalShort = Short(
  id: 'tidal',
  stamp: 'THE WILDS · 06',
  music: 'enc_boss_loop',
  endTitle: const [('Every Elder\n', null), ('has one.', Color(0xFF3C6E9C))],
  clips: [
    Clip(
      state: () => mochi('ocean'),
      open: () => const WildsScreen(depth: 3, seed: 21),
      secs: 15,
      preroll: 1.2,
      zoom: 0.7,
      quiet: true,
      pilot: const PilotStart(signature: false, bolts: false),
      setup: (s) async {
        await _god(s);
        toFirstClearing(s, dist: 30);
      },
      beats: [
        Beat(0.05, (s) => s.say(const [("My pet's ", white), ('ULTIMATE', gold), ('\nis a tidal wave', white)], secs: 2.3, size: 28)),
        Beat(4.2, (s) {
          s.raid!.sig = 100;
          s.say(const [('wait for it', white)], secs: 1.4, size: 26);
        }),
        Beat(5.4, (s) => s.raid!.press('signature'), when: (s) => s.raid!.hostile.where((f) => s.raid!.pet.dist(f) < 110).length >= 2),
        Beat(8.6, (s) => s.say(const [('Three at once.', gold)], secs: 2.0, size: 30), when: (s) => (s.raid?.calmed ?? 0) >= 2),
        Beat(11.6, (s) => s.say(const [('Charges back up\n', white), ('as you walk.', blue)], secs: 2.6, size: 26)),
      ],
    ),
  ],
);

/// Fri 6 · Something took over the forest. I'm walking in. Down the lane to the purple arch, and in.
final laneShort = Short(
  id: 'lane',
  stamp: 'THE WILDS · 07',
  music: 'enc_wild_loop',
  endTitle: const [('The Hollow waits.\n', null), ('Walk in.', Color(0xFF6E4FA3))],
  clips: [
    Clip(
      state: () => mochi('amber'),
      open: () => const VillageWalkScreen(map: 'trail', arrive: 'village'),
      secs: 10.5,
      preroll: 1.0,
      pilot: const PilotStart(on: false),
      exits: false,
      setup: (s) async {
        final w = s.walk!;
        w.me
          ..x = 117.0
          ..z = -7.5
          ..dir = 2;
      },
      beats: [
        Beat(0.05, (s) {
          s.say(const [('Something took over\n', white), ('the forest.', lilac)], secs: 2.4, size: 28);
          s.walk?.walkTo(130.0, -12.6);
        }),
        Beat(5.0, (s) => s.say(const [("I'm walking in.", white)], secs: 1.8, size: 30)),
        Beat(7.4, (s) => s.walk?.me.dir = 0), // a look back
        Beat(8.6, (s) => s.walk?.me.dir = 4),
      ],
    ),
    Clip(
      state: () => mochi('amber'),
      open: () => const WildsScreen(depth: 1, seed: 3),
      secs: 4.6,
      preroll: 1.2,
      zoom: 0.8,
      quiet: true,
      pilot: const PilotStart(on: false),
      setup: (s) async {
        await _god(s);
        toFirstClearing(s, dist: 40);
      },
      beats: [
        Beat(0.05, (s) => s.say(const [('3,000 steps', gold), ('\ngot me here.', white)], secs: 2.6, size: 28)),
      ],
    ),
  ],
);

/// Sat 7 · 3,500 steps in, the mine opened a shaft. Gallery 1 to the way down; the iron; the bounce;
/// the break; the glow below.
final shaftShort = Short(
  id: 'shaft',
  stamp: 'THE MINE · 02',
  music: 'enc_wild_loop',
  endTitle: const [('The mine goes down\n', null), ('with your steps.', Color(0xFF8D5D3B))],
  clips: [
    Clip(
      state: () => mochi('amber'),
      open: () => const WildsScreen(depth: 1, seed: 11, mine: true),
      secs: 16,
      preroll: 1.2,
      pilot: const PilotStart(on: false),
      setup: (s) async {
        await _god(s);
        toFirstClearing(s, dist: 30);
      },
      beats: [
        Beat(0.05, (s) {
          s.say(const [('3,500 steps', gold), (' in, the mine\n', white), ('opened a shaft', white)], secs: 2.4, size: 27);
          final g = s.screen?.map?.gateSeal;
          if (g != null) s.autopilot.walkTo = Offset(g.$1, g.$2 + 26); // to the shaft's mouth
        }),
        Beat(3.6, (s) => s.key(LogicalKeyboardKey.keyN)),
        Beat(3.7, (s) {
          s.autopilot
            ..walkTo = null
            ..mineEvery = 1.0;
          toOre(s, 'iron');
        }, when: (s) => (s.screen?.map?.depth ?? 1) >= 2),
        Beat(4.4, (s) => s.say(const [('Iron. ', white), ("Copper won't cut it.", blue)], secs: 1.8, size: 26), when: (s) => (s.screen?.map?.depth ?? 1) >= 2),
        // the first swings bounce; then the pick that opens iron (the recorder's hand)
        Beat(6.2, (s) {
          s.raid!.oreTier = 2;
          s.say(const [('So: an ', white), ('Iron Pick.', gold)], secs: 1.8, size: 28);
        }),
        Beat(8.0, (s) => s.mark = s.t, when: (s) => (s.raid?.ores.any((o) => o.broken && o.kind == 'iron') ?? false) || s.t > 13),
        Beat(8.1, (s) => s.say(const [("Something's glowing\n", white), ('further down.', mint)], secs: 2.6, size: 26), when: (s) => s.mark != null && s.t - s.mark! > 1.5),
      ],
      until: (s) => s.mark != null && s.t - s.mark! > 4.2,
    ),
  ],
);

/// Sat 8 · This egg came from the woods. This came out of it. The stages, the hatch, the hatchling at home.
final stagesShort = Short(
  id: 'stages',
  stamp: 'THE NOOK · 02',
  music: 'mus_lullaby',
  endTitle: const [('Next week:\n', null), ('what it becomes.', Color(0xFF5E7F4A))],
  endSecs: 2.2,
  clips: [
    Clip(
      state: () => withEgg('amber', 'forest_egg'),
      open: nookStage,
      secs: 10.0,
      preroll: 0.6,
      pilot: const PilotStart(on: false),
      loaded: () => true,
      beats: [
        Beat(0.05, (s) => s.say(const [('This egg came\n', white), ('from the woods.', mint)], secs: 1.4, size: 27, y: _nookY)),
        Beat(1.1, (s) => eggTo(s, 600)),
        Beat(1.9, (s) => eggTo(s, 1300)),
        Beat(2.7, (s) => eggTo(s, 1800)),
        Beat(3.5, (s) {
          eggTo(s, 2000);
          s.say(const [('2,000 steps', gold)], secs: 1.6, size: 32, y: _nookY);
        }),
        Beat(5.4, (s) => s.tapText('Hatch')),
        Beat(8.3, (s) => s.say(const [('This came\n', white), ('out of it.', gold)], secs: 1.7, size: 30, y: 72)),
      ],
    ),
    Clip(
      state: () => withCompanion('amber', 'Moss'),
      open: () => const VillageWalkScreen(map: 'home', arrive: 'nest'),
      secs: 3.2,
      preroll: 1.0,
      pilot: const PilotStart(on: false),
      exits: false,
      setup: (s) async {
        final w = s.walk!;
        w.me
          ..x = -32.6
          ..z = 27.2
          ..dir = 6;
      },
      beats: [],
    ),
  ],
);
