// The Shorts the recorder makes (record_test.dart): each one is a few clips of the real game, played by
// the autopilot and steered by beats (a debug shortcut, a nudge to the fight, a caption), then the end
// card. Times are seconds into the clip; captions placed by a beat appear at the moment it fires.
//
// The Wilds series (action): sentinel, briarback, deep, signatures.

import 'dart:async';
import 'dart:math' as math;

import 'package:evochi/core/models/game_state.dart';
import 'package:evochi/core/utils/day_keys.dart';
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
  Pilot get autopilot;
  GameState get state;
  int get clip;
  Future<void> step();
  Future<void> waitLoaded();
  Future<void> key(LogicalKeyboardKey k);

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
  final _rng = math.Random(3);
  double _last = 0, _dodgeCd = 0;

  void reset(PilotStart? s) {
    on = s?.on ?? true;
    signature = s?.signature ?? true;
    bolts = s?.bolts ?? true;
    dodges = s?.dodges ?? true;
    prefer = s?.prefer;
    walkTo = null;
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
