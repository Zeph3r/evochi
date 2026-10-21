// Combat in the Lumen Wilds: a small real-time simulation the Wilds screen ticks and draws. Pure Dart (no
// widgets), so it is tested on its own (test/wilds_combat_test.dart).
//
// Your Evochi leads. It has Raid HP and Stamina (kept here, apart from its Vitality: a knockout is an
// evacuation, never harm to the pet), a three-hit Pounce, a homing Glow Bolt, a Lumen Pulse round itself,
// a dodge roll with invulnerable frames, and healing items from the Bag (the screen spends them).
//
// Sher, an NPC ally, fights beside it: he flanks whatever is after your Evochi, steps out of telegraphed
// attacks, tosses a tonic when it is low, calls the guardian's moves, and when he is winded he sits a few
// seconds out and gets back up.
//
// The foes are creatures the Hollow has tangled. Defeated, the Hollow lifts and they trot off calm.
//   Thornling  noticed you (sight cone, a running Evochi is heard, a hurt one calls its pack): it circles
//              and waits its turn (at most two take a swing at the same target at once), then tucks into a
//              thorn ball and rolls along a line it shows you, tracking you until the last moment. A roll
//              into a tree or a rock knocks it silly: free hits. Too close to roll, it nips. Hurt, it backs
//              off once. Pulled far from its clearing, it gives up and goes home, healing.
//   Sporecap   keeps its distance and hops away when you close in (it picks the open way out, not a tree),
//              lobs spores where you will be (your heading, a little short of a perfect lead), and the
//              landing leaves a cloud that slows you (Spored). Cornered, it puffs.
//   Briarback  the guardian at the gate. It turns slowly (get round its flank), and chooses what to do by
//              range, cooldowns, what it just did, and how you have been playing (stay far: more charges
//              and roots; hug its flank: thorn rings). Antler sweep (a cone), charge (a line: bait it into
//              a pillar and it crashes, dazed), roots under you and where you are heading. Below 60% it
//              roars, calls two Thornlings and adds the ring; below 30% it is enraged: quicker, chains its
//              charges, more roots. Heavy hits wear its poise down to a stagger.

import 'dart:math' as math;
import 'dart:ui' show Rect;

enum Team { party, foe }

/// What the map gives the fight: where water is, the round footprints of trees, rocks and the like,
/// the bounds.
class RaidGround {
  RaidGround({required this.wet, required this.blocks, required this.bounds});
  final bool Function(double x, double z) wet;
  final List<(double, double, double)> blocks;
  final Rect bounds;
}

int dirOf(double vx, double vz) {
  final a = math.atan2(vx, vz) * 180 / math.pi; // 0 = toward you (S), 90 = right (E)
  return (((a / 45).round()) % 8 + 8) % 8;
}

double _len(double x, double z) => math.sqrt(x * x + z * z);

/// Anyone on the field: your Evochi, Sher, a foe.
class Actor {
  Actor({required this.id, required this.kind, required this.team, required this.x, required this.z, required this.radius, required double health})
      : hp = health,
        maxHp = health;
  final String id, kind;
  final Team team;
  double x, z;
  final double radius;
  double hp, maxHp;
  double fx = 0, fz = 1; // facing, a unit vector
  int dir = 0; // the sprite row: S, SE, E, NE, N, NW, W, SW
  double phase = 0, cycle = 10; // through the walk cycle; world units per cycle
  bool moving = false, running = false;
  // how it is drawn
  String? pose; // an act pose (null: walking or idle)
  String gait = 'walk';
  bool calm = false; // the Hollow has lifted
  double alpha = 1, spin = 0, sx = 1, sy = 1, lift = 0, glow = 0;
  // state
  double flash = 0, iframes = 0, stun = 0, slowT = 0, mercy = 0;
  double kx = 0, kz = 0; // knockback (units per second)
  double vx = 0, vz = 0; // velocity last tick (for leading shots)
  late double px = x, pz = z; // where it was last tick
  bool ghost = false; // passes through the others (dodging, calm, winded)
  bool get alive => hp > 0;
  bool get solid => alive && !ghost;
  double get hpFrac => maxHp <= 0 ? 0 : (hp / maxHp).clamp(0.0, 1.0);

  void face(double vx, double vz) {
    final l = _len(vx, vz);
    if (l < 1e-6) return;
    fx = vx / l;
    fz = vz / l;
    dir = dirOf(fx, fz);
  }

  double dist(Actor o) => _len(x - o.x, z - o.z);
  double distTo(double px, double pz) => _len(x - px, z - pz);
}

enum FoeState { idle, alert, engage, windup, strike, recover, stagger, flee, home, calm, dormant, roar }

class Foe extends Actor {
  Foe({required super.id, required super.kind, required super.x, required super.z, required super.radius, required super.health, required this.zone})
      : super(team: Team.foe) {
    homeX = x;
    homeZ = z;
  }
  final String zone;
  late double homeX, homeZ;
  FoeState st = FoeState.idle;
  double t = 0; // time in the state
  Actor? target;
  final threat = <Actor, double>{};
  double cd = 0.8; // the main attack's cooldown
  double cd2 = 0; // a second one (a puff)
  double strafe = 1, strafeT = 2;
  double wanderT = 0;
  double? wx, wz;
  String move = '';
  double ax = 0, az = 1; // the attack's direction (locked late in the wind-up)
  double aimX = 0, aimZ = 0; // a lob's landing spot
  double travelled = 0, travelMax = 0;
  final hit = <Actor>{};
  bool fled = false, summoned = false;
  double poise = 40, maxPoise = 40;
  double alertDelay = 0;
  double windup = 0.5, active = 0.2, recover = 0.5;
  Mark? mark;
  double leaveT = 0; // calm: trotting off

  bool get fighting => alive && (st == FoeState.engage || st == FoeState.windup || st == FoeState.strike || st == FoeState.recover || st == FoeState.alert || st == FoeState.flee);
}

/// The guardian: phases, its own cooldowns, and a read on how you play.
class Boss extends Foe {
  Boss({required super.id, required super.x, required super.z, required this.ax0, required this.az0, required this.ar})
      : super(kind: 'briarback', radius: 17, health: 1200, zone: 'arena') {
    st = FoeState.dormant;
    poise = maxPoise = 260;
  }
  final double ax0, az0, ar; // the arena
  int stage = 1;
  String last = '';
  final cds = <String, double>{'sweep': 0, 'charge': 2.5, 'roots': 4, 'ring': 6};
  double kite = 0, hug = 0, behindT = 0;
  int chain = 0;
  double think = 0;
  bool feinted = false; // held this attack a beat, waiting out an early dodge
  bool summoned60 = false, summoned30 = false;
  double get turnRate => stage >= 3 ? 3.0 : 2.2;
  double get quick => stage >= 3 ? 0.78 : (stage == 2 ? 0.9 : 1.0);
}

enum MarkShape { circle, ring, cone, line }

/// A telegraph on the ground: where something is about to land. `t / dur` fills it.
class Mark {
  Mark(this.shape, this.x, this.z, this.dur, {this.r = 0, this.dx = 0, this.dz = 1, this.len = 0, this.width = 0, this.half = 0, this.owner});
  final MarkShape shape;
  double x, z, r, dx, dz, len, width, half;
  double t = 0;
  double dur;
  final Actor? owner;
  bool done = false;
  double get p => dur <= 0 ? 1 : (t / dur).clamp(0.0, 1.0);

  /// Is (px, pz) with a body of radius rad inside?
  bool covers(double px, double pz, double rad) {
    final ox = px - x, oz = pz - z;
    switch (shape) {
      case MarkShape.circle:
        return _len(ox, oz) < r + rad * 0.6;
      case MarkShape.ring:
        return _len(ox, oz) < r + rad;
      case MarkShape.cone:
        final d = _len(ox, oz);
        if (d > r + rad) return false;
        if (d < rad + 4) return true;
        return (ox * dx + oz * dz) / d > math.cos(half) - rad / math.max(d, 1);
      case MarkShape.line:
        final along = ox * dx + oz * dz;
        if (along < -rad || along > len + rad) return false;
        return (ox * dz - oz * dx).abs() < width / 2 + rad * 0.7;
    }
  }
}

enum ShotKind { bolt, spore, vial }

class Shot {
  Shot(this.kind, this.team, this.x, this.z, {this.vx = 0, this.vz = 0, this.life = 1, this.owner, this.target});
  final ShotKind kind;
  final Team team;
  double x, z, vx, vz;
  double t = 0, life;
  final Actor? owner;
  Actor? target;
  // a lob: from (x0, z0) to (x1, z1) over `life` seconds, arcing `h` units high
  double x0 = 0, z0 = 0, x1 = 0, z1 = 0, h = 0;
  bool lob = false, done = false;
  Mark? mark;
  double get height => lob ? h * 4 * (t / life) * (1 - t / life) : 6;
}

/// A spore cloud (slows you while you stand in it).
class Hazard {
  Hazard(this.x, this.z, this.r, this.life);
  final double x, z, r;
  double t = 0;
  final double life;
}

/// The guardian's ring of thorns, rolling outward.
class Wave {
  Wave(this.x, this.z, this.maxR);
  final double x, z, maxR;
  double r = 14;
  final hit = <Actor>{};
}

class Pickup {
  Pickup(this.kind, this.x, this.z, this.amount);
  final String kind; // mote (heals)
  final double x, z;
  final int amount;
  double t = 0;
}

/// A number or a word floating up from someone.
class Floater {
  Floater(this.text, this.x, this.z, this.kind, {this.ttl = 0.9});
  final String text;
  final double x, z;
  final String kind; // dmg, crit, hurt, heal, info, loot
  double t = 0;
  final double ttl;
}

/// A little effect: sparks, dust, light motes, a pulse, roots bursting up, a slash.
class Burst {
  Burst(this.kind, this.x, this.z, this.ttl, {this.dx = 0, this.dz = 1, this.size = 1});
  final String kind;
  final double x, z, ttl, dx, dz, size;
  double t = 0;
}

class RaidEvent {
  const RaidEvent(this.type, {this.text, this.value = 0, this.x = 0, this.z = 0});
  final String type;
  final String? text;
  final double value, x, z;
}

class RaidInput {
  double mx = 0, mz = 0; // where you are steering (any length; 0 = standing)
  double speed = 1; // 0..1 (a half-pushed stick)
  bool run = false;
  bool attack = false, bolt = false, pulse = false, dodge = false;
  Foe? lock; // tapped
}

enum PetAct { none, swing, bolt, pulse, dodge, hurt, heal }

enum RaidPhase { explore, knocked }

enum BossState { absent, dormant, intro, fight, calm }

/// One spawn from the map.
class FoeSpawn {
  const FoeSpawn(this.id, this.kind, this.zone, this.x, this.z);
  final String id, kind, zone;
  final double x, z;
}

class ZoneDef {
  const ZoneDef(this.id, this.name, this.x, this.z, this.r);
  final String id, name;
  final double x, z, r;
}

class BossDef {
  const BossDef({required this.x, required this.z, required this.ax, required this.az, required this.ar, required this.wall, required this.summon});
  final double x, z, ax, az, ar;
  final List<(double, double)> wall, summon;
}

// ------------------------------------------------------------------ numbers
const _petWalk = 26.0, _petRun = 52.0;
const _stamMax = 100.0, _stamRegen = 34.0, _stamDelay = 0.55;
const _swingCost = [5.0, 5.0, 8.0], _swingDmg = [9.0, 10.0, 16.0], _swingPoise = [8.0, 8.0, 24.0], _swingKnock = [40.0, 40.0, 120.0];
const _swingLunge = [9.0, 9.0, 16.0], _swingRecover = [0.17, 0.17, 0.32];
const _boltCost = 18.0, _boltCd = 1.0, _boltDmg = 13.0;
const _pulseCost = 34.0, _pulseCd = 7.0, _pulseDmg = 18.0, _pulseR = 36.0;
const _dodgeCost = 20.0, _dodgeTime = 0.3, _dodgeDist = 46.0;
const _sherHp = 150.0;

class Raid {
  Raid({
    required this.ground,
    required this.pet,
    this.sher,
    this.sherRoute = const [],
    this.sherFire,
    this.zones = const [],
    List<FoeSpawn> spawns = const [],
    this.bossDef,
    this.bossCleared = false,
    this.level = 1,
    int seed = 7,
    this.lootRoll,
    this.lootLabel,
    this.ward = 0,
    double bossScale = 1.0,
  })  : rng = math.Random(seed),
        lootRng = math.Random(seed * 31 + 7) {
    startX = pet.x;
    startZ = pet.z;
    atk = 1 + 0.06 * (level - 1);
    for (final s in spawns) {
      foes.add(_spawn(s.id, s.kind, s.zone, s.x, s.z));
    }
    foeTotal = foes.length;
    final b = bossDef;
    if (b != null) {
      boss = Boss(id: 'briarback', x: b.x, z: b.z, ax0: b.ax, az0: b.az, ar: b.ar)..face(0, 1);
      // a lighter guardian for a party of one (Sher keeps the camp now)
      boss!
        ..maxHp *= bossScale
        ..hp = boss!.maxHp;
      bossState = bossCleared ? BossState.calm : BossState.dormant;
      if (bossCleared) {
        boss!
          ..calm = true
          ..st = FoeState.calm
          ..ghost = false;
      } else {
        boss!.pose = 'lower1';
      }
    }
    _rebuildBlocks();
  }

  final RaidGround ground;
  final Actor pet;
  Actor? sher;
  final List<(double, double)> sherRoute;
  final (double, double)? sherFire;
  final List<ZoneDef> zones;
  final BossDef? bossDef;
  final bool bossCleared;
  final int level;
  final math.Random rng;
  /// Rare finds a calmed foe can leave (the economy's drop table); its own random, so the fight's dice
  /// never change when the loot does.
  final Map<String, int> Function(math.Random r)? lootRoll;
  final String Function(String id, int n)? lootLabel;
  final math.Random lootRng;
  /// A Hollow Ward: hits the shield still turns away.
  int ward;
  late double atk;
  late double startX, startZ;

  final foes = <Foe>[];
  Boss? boss;
  BossState bossState = BossState.absent;
  bool wallUp = false;
  double wallRise = 0; // 0..1, for drawing

  final marks = <Mark>[];
  final shots = <Shot>[];
  final hazards = <Hazard>[];
  final waves = <Wave>[];
  final pickups = <Pickup>[];
  final floaters = <Floater>[];
  final bursts = <Burst>[];
  final events = <RaidEvent>[];

  RaidPhase phase = RaidPhase.explore;
  double time = 0, hitstop = 0, shake = 0;
  bool party = false;

  // your Evochi
  double stamina = _stamMax, _stamWait = 0;
  PetAct act = PetAct.none;
  double actT = 0;
  int combo = 0;
  double comboUntil = 0;
  final _hitThisSwing = <Actor>{};
  double boltCd = 0, pulseCd = 0;
  double _dodgeX = 0, _dodgeZ = 1;
  double _lungeK = 1;
  double _dodgeAt = -99;
  bool _dodgeRewarded = false;
  String? _buffer;
  double _bufferT = 0;
  double _tiredT = 0;
  double _healLeft = 0;
  Foe? lock;
  final trail = <(double, double, double)>[]; // (x, z, t): where your Evochi has been (dodge afterimages)

  // Sher
  final crumbs = <(double, double)>[];
  int _leg = 0;
  double _pause = 2.0;
  double sherAtkCd = 0, sherVialCd = 4, sherHealCd = 10, sherWinded = 0, _sayCd = 0;
  int _sherSwing = 0;
  double _sherSwingT = 0;
  Foe? sherTarget;
  final _said = <String>{};

  // the run so far
  int coins = 0;
  final items = <String, int>{};
  int calmed = 0;
  final cleared = <String>{};

  List<(double, double, double)> _blocks = const [];

  Iterable<Foe> get allFoes sync* {
    yield* foes;
    final b = boss;
    if (b != null) yield b;
  }

  Iterable<Foe> get hostile => allFoes.where((f) => f.alive && !f.calm && f.st != FoeState.dormant);
  int foeTotal = 0; // the creatures the floor began with (calmed ones trot off and leave the list)
  bool get inCombat => hostile.any((f) => f.fighting && f.target != null);
  bool get wallActive => wallUp;

  Foe _spawn(String id, String kind, String zone, double x, double z) {
    final f = Foe(id: id, kind: kind, x: x, z: z, radius: kind == 'sporecap' ? 8 : 8, health: kind == 'sporecap' ? 46 : 58, zone: zone);
    f
      ..cycle = kind == 'sporecap' ? 10 : 7.2
      ..poise = kind == 'sporecap' ? 20 : 30
      ..maxPoise = kind == 'sporecap' ? 20 : 30
      ..cd = 0.6 + rng.nextDouble()
      ..strafe = rng.nextBool() ? 1 : -1;
    f.face(rng.nextDouble() - 0.5, 1);
    return f;
  }

  void _rebuildBlocks() {
    final b = bossDef;
    _blocks = [
      ...ground.blocks,
      if (wallUp && b != null) for (final (x, z) in b.wall) (x, z, 10.0),
    ];
  }

  void _emit(String type, {String? text, double value = 0, double x = 0, double z = 0}) =>
      events.add(RaidEvent(type, text: text, value: value, x: x, z: z));

  void _float(String text, double x, double z, String kind, {double ttl = 0.9}) => floaters.add(Floater(text, x, z, kind, ttl: ttl));

  void say(String text, {String? once, double gap = 3.5}) {
    if (sher == null || !party) return;
    if (once != null) {
      if (_said.contains(once)) return;
      _said.add(once);
    } else if (_sayCd > 0) {
      return;
    }
    _sayCd = gap;
    _emit('say', text: text);
  }

  // ================================================================== the loop
  void tick(double dt, RaidInput inp) {
    for (final f in floaters) {
      f.t += dt;
    }
    floaters.removeWhere((f) => f.t >= f.ttl);
    for (final b in bursts) {
      b.t += dt;
    }
    bursts.removeWhere((b) => b.t >= b.ttl);
    shake = math.max(0, shake - dt * 3);
    wallRise = (wallRise + (wallUp ? dt * 2.2 : -dt * 1.2)).clamp(0.0, 1.0);
    if (phase != RaidPhase.explore) return;
    if (hitstop > 0) {
      hitstop -= dt;
      return;
    }
    time += dt;
    _sayCd -= dt;
    _tickPet(dt, inp);
    final s = sher;
    if (s != null) _tickSher(s, dt);
    for (final f in foes.toList()) {
      _tickFoe(f, dt);
    }
    final b = boss;
    if (b != null) _tickBoss(b, dt);
    _tickShots(dt);
    _tickHazards(dt);
    _tickWaves(dt);
    _tickRoots(dt);
    _tickPickups(dt);
    _physics(dt);
    // a breather between fights: Raid HP comes back slowly when nothing is after you, Sher's faster
    if (!inCombat) {
      if (pet.alive) pet.hp = math.min(pet.maxHp, pet.hp + 1.5 * dt);
      final sh = sher;
      if (sh != null && party && sherWinded <= 0) sh.hp = math.min(sh.maxHp, sh.hp + 4 * dt);
    }
    marks.removeWhere((m) => m.done);
    foes.removeWhere((f) => f.calm && f.alpha <= 0);
    trail.removeWhere((t) => time - t.$3 > 0.35);
  }

  // ================================================================== moving
  bool _blockedAt(double x, double z, double r, {bool water = true}) {
    for (final (ox, oz, br) in _blocks) {
      final dx = x - ox, dz = z - oz;
      if (dx.abs() > br + r || dz.abs() > br + r) continue;
      if (dx * dx + dz * dz < (br + r) * (br + r)) return true;
    }
    if (water && _wet(x, z, r)) return true;
    final b = ground.bounds;
    return x < b.left || x > b.right || z < b.top || z > b.bottom;
  }

  bool _wet(double x, double z, double r) =>
      ground.wet(x, z) || ground.wet(x + r * 0.6, z) || ground.wet(x - r * 0.6, z) || ground.wet(x, z + r * 0.5) || ground.wet(x, z - r * 0.5);

  /// How far along (dx, dz) a body of radius r gets from (x, z) before something stops it (max len), and
  /// whether it was a block (a tree, a rock) rather than open ground running out.
  (double, bool) _clear(double x, double z, double dx, double dz, double r, double len) {
    for (var s = 4.0; s <= len; s += 4) {
      if (_blockedAt(x + dx * s, z + dz * s, r)) return (math.max(0.0, s - 4), true);
    }
    return (len, false);
  }

  /// Puts w at (nx, nz), sliding round blocks, the others, water and the bounds. True if a block or the
  /// water stopped it.
  bool _place(Actor w, double nx, double nz) {
    var hit = false;
    final r = w.radius;
    // the others first (the lighter gives way to whoever it bumps), then the trunks and rocks last, so
    // being shoved by the guardian never pushes anyone through a wall of them
    if (!w.ghost) {
      for (final o in _bodies) {
        if (o == w || !o.solid) continue;
        final dx = nx - o.x, dz = nz - o.z, rr = o.radius + r;
        if (dx.abs() > rr || dz.abs() > rr) continue;
        final d = _len(dx, dz);
        if (d < rr && d > 1e-6) {
          nx = o.x + dx / d * rr;
          nz = o.z + dz / d * rr;
        }
      }
    }
    // two passes: pushed out of one trunk into the next, it is pushed out again
    for (var pass = 0; pass < 2; pass++) {
      for (final (ox, oz, br) in _blocks) {
        final dx = nx - ox, dz = nz - oz;
        if (dx.abs() > br + r || dz.abs() > br + r) continue;
        final d = _len(dx, dz);
        if (d < br + r && d > 1e-6) {
          nx = ox + dx / d * (br + r);
          nz = oz + dz / d * (br + r);
          hit = true;
        }
      }
    }
    // still wedged between them: stay put (unless it was already stuck in one)
    if (hit && _blockedAt(nx, nz, r * 0.9, water: false) && !_blockedAt(w.x, w.z, r * 0.9, water: false)) {
      nx = w.x;
      nz = w.z;
    }
    // and never a big jump through anything: a move longer than its own size is checked along the way
    final jump = _len(nx - w.x, nz - w.z);
    if (jump > r && !w.ghost) {
      final (free, _) = _clear(w.x, w.z, (nx - w.x) / jump, (nz - w.z) / jump, r * 0.9, jump);
      if (free < jump - 4) {
        nx = w.x + (nx - w.x) / jump * free;
        nz = w.z + (nz - w.z) / jump * free;
        hit = true;
      }
    }
    if (_wet(nx, nz, r)) {
      hit = true;
      if (!_wet(nx, w.z, r)) {
        nz = w.z;
      } else if (!_wet(w.x, nz, r)) {
        nx = w.x;
      } else {
        nx = w.x;
        nz = w.z;
      }
    }
    final b = ground.bounds;
    if (nx < b.left || nx > b.right || nz < b.top || nz > b.bottom) hit = true;
    w.x = nx.clamp(b.left, b.right);
    w.z = nz.clamp(b.top, b.bottom);
    return hit;
  }

  Iterable<Actor> get _bodies sync* {
    yield pet;
    final s = sher;
    if (s != null) yield s;
    yield* allFoes;
  }

  /// Walk w along (vx, vz) at speed; returns true if something stopped it.
  bool _move(Actor w, double vx, double vz, double speed, double dt, {bool faceIt = true}) {
    final len = _len(vx, vz);
    if (len < 1e-6 || speed <= 0) {
      w.moving = false;
      return false;
    }
    vx /= len;
    vz /= len;
    if (faceIt) w.face(vx, vz);
    final ox = w.x, oz = w.z;
    final hit = _place(w, w.x + vx * speed * dt, w.z + vz * speed * dt);
    final moved = _len(w.x - ox, w.z - oz);
    w.moving = moved > speed * dt * 0.2;
    if (w.moving) w.phase = (w.phase + moved / w.cycle) % 1.0;
    return hit;
  }

  /// Steer round trees and rocks: if the way ahead is blocked, try angles either side.
  (double, double) _steer(Actor w, double vx, double vz, {double look = 22}) {
    final l = _len(vx, vz);
    if (l < 1e-6) return (0, 0);
    vx /= l;
    vz /= l;
    if (!_blockedAt(w.x + vx * look, w.z + vz * look, w.radius * 0.8)) return (vx, vz);
    for (final a in const [0.5, -0.5, 1.0, -1.0, 1.5, -1.5, 2.1, -2.1]) {
      final c = math.cos(a), s = math.sin(a);
      final nx = vx * c - vz * s, nz = vx * s + vz * c;
      if (!_blockedAt(w.x + nx * look, w.z + nz * look, w.radius * 0.8)) return (nx, nz);
    }
    return (vx, vz);
  }

  /// Keep apart from the other foes (so a pack spreads round you instead of stacking).
  (double, double) _separate(Foe f, double vx, double vz, double want) {
    var sx = 0.0, sz = 0.0;
    for (final o in hostile) {
      if (o == f) continue;
      final dx = f.x - o.x, dz = f.z - o.z;
      final d = _len(dx, dz);
      final keep = want + o.radius;
      if (d < keep && d > 1e-6) {
        sx += dx / d * (keep - d) / keep;
        sz += dz / d * (keep - d) / keep;
      }
    }
    return (vx + sx * 1.6, vz + sz * 1.6);
  }

  void _physics(double dt) {
    for (final a in _bodies) {
      a.flash = math.max(0, a.flash - dt);
      a.iframes = math.max(0, a.iframes - dt);
      a.mercy = math.max(0, a.mercy - dt);
      a.stun = math.max(0, a.stun - dt);
      a.slowT = math.max(0, a.slowT - dt);
      if (a.kx != 0 || a.kz != 0) {
        _place(a, a.x + a.kx * dt, a.z + a.kz * dt);
        final k = math.exp(-9 * dt);
        a.kx *= k;
        a.kz *= k;
        if (_len(a.kx, a.kz) < 3) a.kx = a.kz = 0;
      }
      if (dt > 0) {
        a.vx = (a.x - a.px) / dt;
        a.vz = (a.z - a.pz) / dt;
      }
      a.px = a.x;
      a.pz = a.z;
    }
  }

  // ================================================================== your Evochi
  void press(String what) {
    _buffer = what;
    _bufferT = 0.32;
  }

  bool get busy => act != PetAct.none && act != PetAct.heal;

  /// Spend Stamina. A dodge, a bolt or a pulse also holds its recovery a breath; pounces don't (you can
  /// keep a combo going and still have the legs to roll out of trouble).
  void _spend(double s, {bool hold = true}) {
    stamina = math.max(0, stamina - s);
    if (hold) _stamWait = _stamDelay;
  }

  bool _afford(double s) {
    if (stamina >= s) return true;
    if (_tiredT <= 0) {
      _float('Out of breath', pet.x, pet.z, 'info');
      _emit('tired');
      _tiredT = 1.2;
    }
    return false;
  }

  Foe? _softTarget(double range, double mx, double mz) {
    Foe? best;
    var bs = double.infinity;
    final l = _len(mx, mz);
    final hx = l > 1e-6 ? mx / l : pet.fx, hz = l > 1e-6 ? mz / l : pet.fz;
    for (final f in hostile) {
      final d = pet.dist(f);
      if (d > range + f.radius) continue;
      final dot = ((f.x - pet.x) * hx + (f.z - pet.z) * hz) / math.max(d, 1e-6);
      final s = d - 30 * dot - (f == lock ? 40 : 0);
      if (s < bs) {
        bs = s;
        best = f;
      }
    }
    return best;
  }

  void _tickPet(double dt, RaidInput inp) {
    final p = pet;
    if (inp.attack) press('attack');
    if (inp.bolt) press('bolt');
    if (inp.pulse) press('pulse');
    if (inp.dodge) press('dodge');
    inp.attack = inp.bolt = inp.pulse = inp.dodge = false;
    if (inp.lock != null) {
      lock = inp.lock;
      inp.lock = null;
    }
    if (lock != null && (!lock!.alive || lock!.calm)) lock = null;
    _bufferT -= dt;
    if (_bufferT <= 0) _buffer = null;
    _tiredT -= dt;
    boltCd = math.max(0, boltCd - dt);
    pulseCd = math.max(0, pulseCd - dt);
    // stamina: back after a short breath, slower in spores, none while running
    _stamWait -= dt;
    if (_stamWait <= 0 && !(p.running && p.moving)) {
      stamina = math.min(_stamMax, stamina + _stamRegen * (p.slowT > 0 ? 0.5 : 1) * dt);
    }
    // a heal over a moment
    if (_healLeft > 0) {
      final h = math.min(_healLeft, dt * 40);
      _healLeft -= h;
      p.hp = math.min(p.maxHp, p.hp + h);
    }
    p.sx = p.sy = 1;
    p.lift = 0;
    p.spin = 0;
    p.ghost = false;
    p.glow = math.max(0, p.glow - dt * 2);
    actT += dt;
    // start what was pressed, if it can be
    final want = _buffer;
    if (want != null && p.stun <= 0) {
      final canCancel = act == PetAct.none || act == PetAct.heal || (act == PetAct.swing && actT > 0.16) || (act == PetAct.bolt && actT > 0.14);
      if (want == 'dodge' && act != PetAct.dodge && act != PetAct.hurt && (canCancel || act == PetAct.pulse && actT > 0.3)) {
        if (_afford(_dodgeCost)) {
          _spend(_dodgeCost);
          final l = _len(inp.mx, inp.mz);
          _dodgeX = l > 1e-6 ? inp.mx / l : -p.fx;
          _dodgeZ = l > 1e-6 ? inp.mz / l : -p.fz;
          p.face(l > 1e-6 ? _dodgeX : p.fx, l > 1e-6 ? _dodgeZ : p.fz);
          act = PetAct.dodge;
          actT = 0;
          _dodgeAt = time;
          p.iframes = _dodgeTime + 0.05;
          _dodgeRewarded = false;
          _emit('dodge');
        }
        _buffer = null;
      } else if (want == 'attack' && (canCancel && (act != PetAct.swing || actT > _swingRecoverEnd - 0.12))) {
        final next = (act == PetAct.swing || time < comboUntil) ? (combo + 1) % 3 : 0;
        if (_afford(_swingCost[next])) {
          _spend(_swingCost[next], hold: false);
          combo = next;
          act = PetAct.swing;
          actT = 0;
          _hitThisSwing.clear();
          final t = _softTarget(48, inp.mx, inp.mz);
          if (t != null) p.face(t.x - p.x, t.z - p.z);
          _lungeK = t != null ? 1.0 : 0.3; // with nothing to pounce on, only a hop in place
          _emit('swing', value: combo.toDouble());
        }
        _buffer = null;
      } else if (want == 'bolt' && canCancel && boltCd <= 0) {
        if (_afford(_boltCost)) {
          _spend(_boltCost);
          act = PetAct.bolt;
          actT = 0;
          boltCd = _boltCd;
          final t = _softTarget(170, inp.mx, inp.mz);
          if (t != null) p.face(t.x - p.x, t.z - p.z);
        }
        _buffer = null;
      } else if (want == 'pulse' && canCancel && pulseCd <= 0) {
        if (_afford(_pulseCost)) {
          _spend(_pulseCost);
          act = PetAct.pulse;
          actT = 0;
          pulseCd = _pulseCd;
          _emit('pulse_charge');
        }
        _buffer = null;
      }
    }
    var mx = inp.mx, mz = inp.mz;
    switch (act) {
      case PetAct.swing:
        final c = combo;
        // a quick crouch, the lunge (the pounce hops), then a breath
        if (actT < 0.07) {
          p.sy = 0.86;
          p.sx = 1.08;
        } else if (actT < 0.2) {
          final lunge = _swingLunge[c] / 0.13 * _lungeK;
          _move(p, p.fx, p.fz, lunge * (p.slowT > 0 ? 0.7 : 1), dt, faceIt: false);
          p.sy = 1.12;
          p.sx = 0.92;
          if (c == 2) p.lift = math.sin((actT - 0.07) / 0.13 * math.pi) * 9;
          _swingHits(c);
        }
        if (actT > 0.2 + _swingRecover[c]) {
          act = PetAct.none;
          comboUntil = time + 0.45;
        }
        mx = mz = 0;
      case PetAct.bolt:
        p.sy = 0.92;
        p.glow = 1;
        if (actT >= 0.1 && actT - dt < 0.1) {
          final t = _softTarget(170, p.fx, p.fz);
          final sh = Shot(ShotKind.bolt, Team.party, p.x + p.fx * 10, p.z + p.fz * 10, vx: p.fx * 165, vz: p.fz * 165, life: 1.2, owner: p, target: t);
          shots.add(sh);
          _emit('bolt');
        }
        if (actT > 0.24) act = PetAct.none;
        mx = mz = 0;
      case PetAct.pulse:
        p.glow = math.min(1, actT / 0.28);
        p.sy = 1 - 0.1 * math.min(1, actT / 0.28);
        if (actT >= 0.28 && actT - dt < 0.28) _pulse();
        if (actT > 0.56) act = PetAct.none;
        mx = mz = 0;
      case PetAct.dodge:
        p.ghost = true;
        final k = actT / _dodgeTime;
        p.spin = k * math.pi * 2;
        p.sy = 0.85;
        _move(p, _dodgeX, _dodgeZ, _dodgeDist / _dodgeTime * (1.25 - 0.5 * k), dt, faceIt: false);
        p.running = true;
        if (trail.isEmpty || time - trail.last.$3 > 0.045) trail.add((p.x, p.z, time));
        if (actT > _dodgeTime) {
          act = PetAct.none;
          p.running = false;
        }
        mx = mz = 0;
      case PetAct.hurt:
        if (actT > 0.28) act = PetAct.none;
        mx = mz = 0;
      case PetAct.heal:
        if (actT > 0.5) act = PetAct.none;
      case PetAct.none:
        break;
    }
    if (act == PetAct.none || act == PetAct.heal) {
      final run = inp.run;
      var sp = (run ? _petRun : _petWalk) * inp.speed;
      if (p.slowT > 0) sp *= 0.6;
      if (act == PetAct.heal) sp *= 0.5;
      p.running = run;
      final l = _len(mx, mz);
      if (l > 1e-6) {
        _move(p, mx, mz, sp, dt);
      } else {
        p.moving = false;
      }
    } else if (act != PetAct.dodge) {
      p.running = false;
      if (act != PetAct.swing) p.moving = false;
    }
    // crumbs for Sher
    if (crumbs.isEmpty || _len(p.x - crumbs.last.$1, p.z - crumbs.last.$2) > 3) {
      crumbs.add((p.x, p.z));
      if (crumbs.length > 80) crumbs.removeAt(0);
    }
  }

  double get _swingRecoverEnd => 0.2 + _swingRecover[combo];

  void _swingHits(int c) {
    final p = pet;
    final hx = p.x + p.fx * 9, hz = p.z + p.fz * 9;
    for (final f in hostile.toList()) {
      if (_hitThisSwing.contains(f)) continue;
      if (_len(f.x - hx, f.z - hz) > f.radius + 12) continue;
      _hitThisSwing.add(f);
      final d = math.max(_len(f.x - p.x, f.z - p.z), 1e-6);
      _hurt(f, _swingDmg[c] * atk, from: p, kx: (f.x - p.x) / d * _swingKnock[c], kz: (f.z - p.z) / d * _swingKnock[c], poise: _swingPoise[c]);
      if (c == 2) hitstop = 0.05;
    }
  }

  void _pulse() {
    final p = pet;
    bursts.add(Burst('pulse', p.x, p.z, 0.45, size: _pulseR));
    _emit('pulse');
    shake = math.max(shake, 0.25);
    p.slowT = 0;
    hazards.removeWhere((h) => _len(h.x - p.x, h.z - p.z) < _pulseR + h.r * 0.5);
    for (final f in hostile.toList()) {
      final d = p.dist(f);
      if (d > _pulseR + f.radius) continue;
      final k = d > 1e-6 ? 1 / d : 0.0;
      _hurt(f, _pulseDmg * atk, from: p, kx: (f.x - p.x) * k * 150, kz: (f.z - p.z) * k * 150, poise: 34);
    }
  }

  /// A healing item from the Bag (the screen has already spent it): heals over a moment.
  void useHeal(int amount) {
    _healLeft += amount;
    if (!busy) {
      act = PetAct.heal;
      actT = 0;
    }
    _float('+$amount', pet.x, pet.z, 'heal');
    bursts.add(Burst('heal', pet.x, pet.z, 0.7));
  }

  // ================================================================== damage
  /// Hurts a; returns whether it landed.
  bool _hurt(Actor a, double dmg, {Actor? from, double kx = 0, double kz = 0, double poise = 0, double stun = 0, String cause = ''}) {
    if (!a.alive || a.calm) return false;
    if (a is Foe && (a.st == FoeState.roar || a.st == FoeState.dormant)) {
      _float('Shrugged off', a.x, a.z, 'info', ttl: 0.6);
      return false;
    }
    if (a.iframes > 0 || a.mercy > 0) {
      if (a == pet && act == PetAct.dodge && !_dodgeRewarded) {
        _dodgeRewarded = true;
        stamina = math.min(_stamMax, stamina + 12);
        _float('Dodged!', a.x, a.z, 'info', ttl: 0.7);
        _emit('dodged');
      }
      return false;
    }
    if (a == sher && sherWinded > 0) return false;
    if (a == pet && ward > 0) {
      // the Hollow Ward turns the blow away
      ward--;
      a.mercy = 0.5;
      _float(ward > 0 ? 'Warded! ($ward left)' : 'Ward spent!', a.x, a.z, 'info', ttl: 0.9);
      _emit('warded', value: ward.toDouble());
      return false;
    }
    var crit = false;
    if (a is Foe) {
      // from behind, or while it is dazed: it hurts more
      if (from != null) {
        final d = math.max(a.dist(from), 1e-6);
        final behind = ((a.x - from.x) * a.fx + (a.z - from.z) * a.fz) / d;
        if (behind > 0.45 && a is Boss) crit = true;
      }
      if (a.st == FoeState.stagger) crit = true;
      if (crit) dmg *= 1.4;
      dmg *= 0.92 + rng.nextDouble() * 0.16;
    }
    final n = math.max(1, dmg.round());
    a.hp -= n;
    a.flash = 0.14;
    a.kx += kx;
    a.kz += kz;
    final fx = (a.x + (from?.x ?? a.x)) / 2, fz = (a.z + (from?.z ?? a.z)) / 2;
    bursts.add(Burst('spark', fx, fz, 0.25));
    if (a.team == Team.party) {
      _float('-$n', a.x, a.z, 'hurt');
      if (a == pet) {
        a.mercy = 0.6;
        shake = math.max(shake, 0.35);
        if (stun > 0 || n >= 10) {
          act = PetAct.hurt;
          actT = 0;
          a.stun = math.max(a.stun, stun);
        }
        _emit('hurt', value: n.toDouble(), text: cause);
        if (a.hp <= 0) {
          a.hp = 0;
          _knockout();
        }
      } else {
        a.mercy = 0.3;
        if (a.hp <= 0) {
          a.hp = 0;
          sherWinded = 9;
          a.ghost = true;
          say("I'm winded... keep going, I'll catch up!", gap: 6);
        }
      }
      return true;
    }
    final f = a as Foe;
    _float('$n', f.x, f.z, crit ? 'crit' : 'dmg');
    _emit('hit', value: n.toDouble(), x: f.x, z: f.z);
    if (from != null) {
      f.threat[from] = (f.threat[from] ?? 0) + n;
      if (f.st == FoeState.idle || f.st == FoeState.home) {
        f.target = from;
        _alert(f, from, instant: true);
      }
    }
    f.poise -= poise;
    if (f.poise <= 0 && f.st != FoeState.strike) {
      f.poise = f.maxPoise;
      _stagger(f, f is Boss ? 1.9 : 0.9);
    } else if (f is! Boss && (f.st == FoeState.engage || f.st == FoeState.idle) && poise >= 8) {
      f.pose = 'hurt';
      f.t = 0;
      f.stun = 0.22;
    }
    if (f.hp <= 0) {
      f.hp = 0;
      _calm(f);
    } else if (f is Boss) {
      _bossHealthCheck(f);
    }
    return true;
  }

  void _stagger(Foe f, double secs) {
    _endMark(f);
    f.st = FoeState.stagger;
    f.t = 0;
    f.stun = secs;
    f.pose = f is Boss ? 'stagger' : 'hurt';
    f.spin = 0;
    f.ghost = false;
    _float('Staggered!', f.x, f.z, 'info', ttl: 0.8);
    _emit('stagger', x: f.x, z: f.z);
  }

  void _endMark(Foe f) {
    f.mark?.done = true;
    f.mark = null;
  }

  void _knockout() {
    phase = RaidPhase.knocked;
    act = PetAct.none;
    _emit('knockout');
  }

  /// A Heartbloom after a knockout: back up where you fell, with 60% Raid HP and a moment's grace.
  void secondWind() {
    if (phase != RaidPhase.knocked) return;
    phase = RaidPhase.explore;
    pet
      ..hp = pet.maxHp * 0.6
      ..mercy = 2.0;
    act = PetAct.none;
    bursts.add(Burst('motes', pet.x, pet.z, 1.4, size: 2));
    _float('Second wind!', pet.x, pet.z, 'info', ttl: 1.2);
    _emit('second_wind');
  }

  /// After a knockout: back at the trailhead. Half the unbanked satchel is lost; the guardian (if it was
  /// fighting) and any foe still after you go back to their places, healed.
  ({int coinsLost, Map<String, int> itemsLost}) evacuate() {
    final lostC = (coins / 2).ceil();
    coins -= lostC;
    final lostI = <String, int>{};
    for (final e in items.entries.toList()) {
      final l = (e.value / 2).ceil();
      if (l > 0) lostI[e.key] = l;
      items[e.key] = e.value - l;
    }
    items.removeWhere((k, v) => v <= 0);
    pet
      ..hp = pet.maxHp
      ..x = startX
      ..z = startZ
      ..kx = 0
      ..kz = 0
      ..face(0, -1);
    stamina = _stamMax;
    _healLeft = 0;
    act = PetAct.none;
    crumbs.clear();
    final s = sher;
    if (s != null && party) {
      s
        ..hp = s.maxHp
        ..x = startX + 14
        ..z = startZ + 10
        ..ghost = false;
      sherWinded = 0;
    }
    marks.clear();
    shots.clear();
    hazards.clear();
    waves.clear();
    for (final f in foes.toList()) {
      if (f.summoned && !f.calm) {
        foes.remove(f);
        continue;
      }
      if (!f.calm) _goHome(f, heal: true);
    }
    final b = boss;
    if (b != null && bossState != BossState.calm) {
      b
        ..hp = b.maxHp
        ..x = bossDef!.x
        ..z = bossDef!.z
        ..stage = 1
        ..st = FoeState.dormant
        ..pose = 'lower1'
        ..target = null
        ..summoned30 = false
        ..summoned60 = false
        ..chain = 0
        ..face(0, 1);
      b.threat.clear();
      bossState = BossState.dormant;
      wallUp = false;
      _rebuildBlocks();
    }
    phase = RaidPhase.explore;
    return (coinsLost: lostC, itemsLost: lostI);
  }

  // ================================================================== Sher
  void join() {
    party = true;
    final s = sher;
    if (s != null) {
      s.maxHp = _sherHp;
      s.hp = _sherHp;
    }
  }

  void _tickSher(Actor s, double dt) {
    final p = pet;
    s.sx = s.sy = 1;
    s.lift = 0;
    sherAtkCd -= dt;
    sherVialCd -= dt;
    sherHealCd -= dt;
    final gap = s.dist(p);
    if (!party) {
      _sherIdle(s, p, gap, dt);
      return;
    }
    if (sherWinded > 0) {
      sherWinded -= dt;
      s.moving = false;
      s.pose = 'sit';
      s.ghost = true;
      if (sherWinded <= 0) {
        s.hp = s.maxHp * 0.5;
        s.ghost = false;
        s.pose = null;
        say("I'm okay! Back in it.", gap: 4);
      }
      return;
    }
    s.pose = null;
    // out of anything about to land
    for (final m in marks) {
      if (m.owner == s || m.done) continue;
      if (m.covers(s.x, s.z, s.radius) && m.p > 0.25) {
        var ex = s.x - m.x, ez = s.z - m.z;
        if (m.shape == MarkShape.line) {
          final side = (s.x - m.x) * m.dz - (s.z - m.z) * m.dx;
          ex = m.dz * (side >= 0 ? 1 : -1);
          ez = -m.dx * (side >= 0 ? 1 : -1);
        }
        final (vx, vz) = _steer(s, ex, ez);
        s.running = true;
        _move(s, vx, vz, _petRun * 1.05, dt);
        return;
      }
    }
    for (final w in waves) {
      final d = s.distTo(w.x, w.z);
      if (d > w.r - 4 && d - w.r < 30) {
        // the ring is coming: step in behind it
        s.running = true;
        _move(s, w.x - s.x, w.z - s.z, _petRun, dt);
        return;
      }
    }
    // a tonic when your Evochi is low
    if (p.hpFrac < 0.4 && sherHealCd <= 0 && phase == RaidPhase.explore) {
      if (gap < 80) {
        sherHealCd = 32;
        final amt = (p.maxHp * 0.3).round();
        p.hp = math.min(p.maxHp, p.hp + amt);
        _float('+$amt', p.x, p.z, 'heal');
        bursts.add(Burst('heal', p.x, p.z, 0.7));
        bursts.add(Burst('toss', s.x, s.z, 0.5, dx: p.x - s.x, dz: p.z - s.z));
        _emit('sher_heal');
        say(['Catch! Drink up.', 'Here, take this!', "Don't fall on me now. Here!"][rng.nextInt(3)], gap: 3);
        return;
      }
      s.running = true;
      _move(s, p.x - s.x, p.z - s.z, _petRun * 1.1, dt);
      return;
    }
    // a fight on: pick what is after your Evochi (or nearest it), go to its flank, swipe
    final t = _sherPick(s);
    sherTarget = t;
    if (t != null) {
      final d = s.dist(t);
      // a vial at whatever keeps away (Sporecaps), now and then
      if (sherVialCd <= 0 && d > 40 && d < 150 && (t.kind == 'sporecap' || t is Boss)) {
        sherVialCd = 6.5 + rng.nextDouble() * 2;
        final fl = d / 140;
        final sh = Shot(ShotKind.vial, Team.party, s.x, s.z, life: fl.clamp(0.35, 1.0), owner: s, target: t)
          ..lob = true
          ..x0 = s.x
          ..z0 = s.z
          ..x1 = t.x + t.vx * fl * 0.6
          ..z1 = t.z + t.vz * fl * 0.6
          ..h = 26;
        shots.add(sh);
        s.face(t.x - s.x, t.z - s.z);
        _emit('vial');
        return;
      }
      // the flank: beside the target, across from your Evochi
      var ox = t.x - p.x, oz = t.z - p.z;
      final ol = math.max(_len(ox, oz), 1e-6);
      ox /= ol;
      oz /= ol;
      final side = ((s.x - t.x) * -oz + (s.z - t.z) * ox) >= 0 ? 1.0 : -1.0;
      final reach = t.radius + s.radius + 5;
      final gx = t.x + (ox * 0.5 + -oz * side * 0.85) * reach, gz = t.z + (oz * 0.5 + ox * side * 0.85) * reach;
      final gd = s.distTo(gx, gz);
      if (_sherSwingT > 0) {
        _sherSwingT -= dt;
        s.face(t.x - s.x, t.z - s.z);
        s.moving = false;
        return;
      }
      if (d < reach + 6 && sherAtkCd <= 0 && t.st != FoeState.strike) {
        _sherSwing = (_sherSwing + 1) % 2;
        sherAtkCd = _sherSwing == 1 ? 0.35 : 1.25;
        _sherSwingT = 0.22;
        s.face(t.x - s.x, t.z - s.z);
        s.sx = 1.1;
        bursts.add(Burst('slash', (s.x + t.x) / 2, (s.z + t.z) / 2, 0.22, dx: t.x - s.x, dz: t.z - s.z));
        final k = 1 / math.max(d, 1e-6);
        _hurt(t, 8 + rng.nextDouble() * 3, from: s, kx: (t.x - s.x) * k * 40, kz: (t.z - s.z) * k * 40, poise: 6);
        _emit('sher_swipe');
        return;
      }
      if (gd > 3) {
        final (vx, vz) = _steer(s, gx - s.x, gz - s.z);
        s.running = gd > 40;
        _move(s, vx, vz, gd > 40 ? _petRun : _petWalk * 1.2, dt);
        if (gd < 20) s.face(t.x - s.x, t.z - s.z);
      } else {
        s.moving = false;
        s.face(t.x - s.x, t.z - s.z);
      }
      return;
    }
    _sherFollow(s, p, gap, dt);
  }

  Foe? _sherPick(Actor s) {
    Foe? best;
    var bs = double.infinity;
    for (final f in hostile) {
      if (!f.fighting) continue;
      final dp = f.dist(pet);
      if (dp > 150) continue;
      var sc = dp + s.dist(f) * 0.4;
      if (f.target == pet) sc -= 40;
      if (f.st == FoeState.windup || f.st == FoeState.recover) sc -= 15;
      if (f == sherTarget) sc -= 20; // stick with it
      if (f is Boss) sc -= 25;
      if (sc < bs) {
        bs = sc;
        best = f;
      }
    }
    return best;
  }

  void _sherFollow(Actor s, Actor p, double gap, double dt) {
    if (gap > 40) {
      // a spot about 34 units back along your path, a step to its side
      var tx = p.x, tz = p.z;
      var acc = 0.0;
      var sx = 0.0, sz = 0.0;
      for (var i = crumbs.length - 1; i >= 0; i--) {
        final ddx = crumbs[i].$1 - tx, ddz = crumbs[i].$2 - tz;
        final d = _len(ddx, ddz);
        acc += d;
        if (d > 0) {
          sx = -ddz / d;
          sz = ddx / d;
        }
        tx = crumbs[i].$1;
        tz = crumbs[i].$2;
        if (acc >= 34) break;
      }
      tx += sx * 12;
      tz += sz * 12;
      s.running = gap > 70;
      _move(s, tx - s.x, tz - s.z, gap > 70 ? _petRun * 1.1 : _petWalk, dt);
    } else {
      s.moving = false;
      if (p.moving) s.face(p.fx, p.fz);
    }
  }

  void _sherIdle(Actor s, Actor p, double gap, double dt) {
    if (gap < 64) {
      s.moving = false;
      s.face(p.x - s.x, p.z - s.z);
      return;
    }
    if (_pause > 0) {
      _pause -= dt;
      s.moving = false;
      return;
    }
    if (sherRoute.isEmpty) return;
    final t = sherRoute[_leg % sherRoute.length];
    final dx = t.$1 - s.x, dz = t.$2 - s.z;
    if (_len(dx, dz) < 2) {
      _leg++;
      _pause = 2.5 + (_leg % 3) * 1.5;
      final f = sherFire;
      if (f != null) s.face(f.$1 - s.x, f.$2 - s.z);
    } else {
      s.running = false;
      _move(s, dx, dz, 15, dt);
    }
  }

  // ================================================================== foes
  Actor? _bestTarget(Foe f) {
    // mostly your Evochi; Sher if he has been doing the hurting (a margin, so it doesn't flicker)
    final cands = <Actor>[pet, if (sher != null && party && sherWinded <= 0) sher!];
    Actor? best;
    var bs = -double.infinity;
    for (final c in cands) {
      final d = f.dist(c);
      var sc = (f.threat[c] ?? 0) * (c == pet ? 1.3 : 1.0) - d * 0.35;
      if (c == f.target) sc += 12;
      if (sc > bs) {
        bs = sc;
        best = c;
      }
    }
    return best;
  }

  bool _sees(Foe f, Actor a, double range) {
    final d = f.dist(a);
    if (d > range) return false;
    if (d < range * 0.45) return true;
    final dot = ((a.x - f.x) * f.fx + (a.z - f.z) * f.fz) / math.max(d, 1e-6);
    if (dot > -0.2) return true;
    return a == pet && pet.running && pet.moving && d < range * 0.7; // heard
  }

  void _alert(Foe f, Actor who, {bool instant = false}) {
    if (f.st != FoeState.idle && f.st != FoeState.home) return;
    f.target = who;
    f.threat[who] = (f.threat[who] ?? 0) + 5;
    f.st = FoeState.alert;
    f.t = 0;
    f.alertDelay = instant ? 0.15 : 0.45;
    f.face(who.x - f.x, who.z - f.z);
    f.moving = false;
    _float('!', f.x, f.z, 'alert', ttl: 0.7);
    _emit('alert', x: f.x, z: f.z);
    // the pack hears it
    for (final o in foes) {
      if (o == f || o.zone != f.zone || o.st != FoeState.idle || !o.alive || o.calm) continue;
      if (o.dist(f) < 130) {
        o.target = who;
        o.st = FoeState.alert;
        o.t = 0;
        o.alertDelay = 0.3 + rng.nextDouble() * 0.35;
        o.face(who.x - o.x, who.z - o.z);
        _float('!', o.x, o.z, 'alert', ttl: 0.7);
      }
    }
  }

  void _goHome(Foe f, {bool heal = false}) {
    _endMark(f);
    f
      ..st = FoeState.home
      ..t = 0
      ..target = null
      ..pose = null
      ..spin = 0
      ..ghost = false;
    f.threat.clear();
    if (heal) {
      f
        ..hp = f.maxHp
        ..x = f.homeX
        ..z = f.homeZ
        ..st = FoeState.idle;
    }
  }

  /// When a foe last began an attack on each of you: the next waits a beat, so a pack's swings come one
  /// after another, never all at once.
  final _lastSwing = <Actor, double>{};

  bool _beat(Actor target, double gap) => time - (_lastSwing[target] ?? -99) > gap;

  int _tokens(Actor target, {required bool ranged}) {
    var n = 0;
    for (final f in hostile) {
      if (f.target != target) continue;
      final isRanged = f.kind == 'sporecap';
      if (isRanged != ranged) continue;
      if (f.st == FoeState.windup || f.st == FoeState.strike) n++;
    }
    if (ranged) n += shots.where((s) => s.team == Team.foe && s.target == target && !s.done).length;
    return n;
  }

  void _tickFoe(Foe f, double dt) {
    f.t += dt;
    if (f.calm) {
      _tickCalm(f, dt);
      return;
    }
    if (!f.alive) return;
    f.cd -= dt;
    f.cd2 -= dt;
    f.sx = f.sy = 1;
    f.lift = 0;
    if (f.st != FoeState.strike) f.spin = 0;
    // threat fades
    for (final k in f.threat.keys.toList()) {
      f.threat[k] = f.threat[k]! * math.exp(-dt * 0.15);
    }
    if (f.stun > 0 && f.st != FoeState.stagger) {
      f.moving = false;
      return;
    }
    if (f.st == FoeState.stagger) {
      f.moving = false;
      if (f.stun <= 0) {
        f.st = FoeState.engage;
        f.pose = null;
        f.t = 0;
        f.cd = math.max(f.cd, 0.4);
      }
      return;
    }
    if (f.pose == 'hurt' && f.st == FoeState.engage && f.t > 0.22) f.pose = null;
    switch (f.st) {
      case FoeState.idle:
        _wander(f, dt);
        for (final a in [pet, if (sher != null && party && sherWinded <= 0) sher!]) {
          final b = boss;
          if (wallUp && b != null && !f.summoned && a.distTo(b.ax0, b.az0) < b.ar) continue;
          if (_sees(f, a, f.kind == 'sporecap' ? 100 : 78)) {
            _alert(f, a);
            break;
          }
        }
      case FoeState.alert:
        f.moving = false;
        final t = f.target;
        if (t != null) f.face(t.x - f.x, t.z - f.z);
        f.sy = 1 + 0.08 * math.sin(f.t * 30) * (f.t < 0.3 ? 1 : 0);
        if (f.t > f.alertDelay) {
          f.st = FoeState.engage;
          f.t = 0;
        }
      case FoeState.home:
        final d = f.distTo(f.homeX, f.homeZ);
        f.hp = math.min(f.maxHp, f.hp + f.maxHp * 0.3 * dt);
        if (d < 6) {
          f.moving = false;
          if (f.hp >= f.maxHp) {
            f.st = FoeState.idle;
            f.t = 0;
            f.fled = false;
          }
        } else {
          final (vx, vz) = _steer(f, f.homeX - f.x, f.homeZ - f.z);
          _move(f, vx, vz, 30, dt);
        }
      case FoeState.engage:
      case FoeState.flee:
        _engage(f, dt);
      case FoeState.windup:
      case FoeState.strike:
      case FoeState.recover:
        if (f.kind == 'thornling') {
          _thornAttack(f, dt);
        } else {
          _sporeAttack(f, dt);
        }
      default:
        break;
    }
  }

  void _wander(Foe f, double dt) {
    f.wanderT -= dt;
    if (f.wx == null || f.wanderT <= 0) {
      if (f.wx != null && f.wanderT > -1.5) {
        f.moving = false; // a pause between strolls
        return;
      }
      final a = rng.nextDouble() * math.pi * 2;
      final r = 6 + rng.nextDouble() * 18;
      f.wx = f.homeX + math.cos(a) * r;
      f.wz = f.homeZ + math.sin(a) * r;
      f.wanderT = 3 + rng.nextDouble() * 3;
    }
    final dx = f.wx! - f.x, dz = f.wz! - f.z;
    if (_len(dx, dz) < 2) {
      f.moving = false;
      f.wanderT = math.min(f.wanderT, 0);
      return;
    }
    final (vx, vz) = _steer(f, dx, dz);
    _move(f, vx, vz, f.kind == 'sporecap' ? 9 : 11, dt);
  }

  void _engage(Foe f, double dt) {
    var t = f.target;
    // who to go after (re-picked now and then)
    if (t == null || !t.alive || (t == sher && sherWinded > 0) || f.t % 1.0 < dt) {
      t = f.target = _bestTarget(f);
    }
    if (t == null) {
      _goHome(f);
      return;
    }
    // too far from home: give up, go back and heal; and nobody outside the guardian's brambles keeps at
    // you while they are closed
    final b = boss;
    final walled = wallUp && b != null && !f.summoned && t.distTo(b.ax0, b.az0) < b.ar;
    if (f.distTo(f.homeX, f.homeZ) > 190 || (t.dist(f) > 240) || walled) {
      _goHome(f);
      return;
    }
    final d = f.dist(t);
    if (f.kind == 'thornling') {
      _thornEngage(f, t, d, dt);
    } else {
      _sporeEngage(f, t, d, dt);
    }
  }

  // ---- Thornling
  void _thornEngage(Foe f, Actor t, double d, double dt) {
    // hurt: back off once, then come again
    if (f.st == FoeState.flee) {
      if (f.t > 1.5) {
        f.st = FoeState.engage;
        f.t = 0;
      } else {
        final (vx, vz) = _steer(f, f.x - t.x, f.z - t.z);
        f.running = true;
        _move(f, vx, vz, 34, dt);
        return;
      }
    }
    if (!f.fled && f.hpFrac < 0.3 && rng.nextDouble() < 0.5) {
      f.fled = true;
      f.st = FoeState.flee;
      f.t = 0;
      return;
    }
    f.fled = f.fled || f.hpFrac < 0.3;
    final tokens = _tokens(t, ranged: false);
    final cap = t == pet ? 2 : 1;
    final busy = t == pet && (act == PetAct.swing || act == PetAct.heal || act == PetAct.bolt);
    if (f.cd <= 0 && tokens < cap && _beat(t, 0.75)) {
      if (d < f.radius + t.radius + 7) {
        _startAttack(f, 'nip', 0.34, 0.12, 0.42);
        return;
      }
      if (d < 68 && d > 18) {
        // roll only along a line that is clear (no tree in the way)
        final dx = (t.x - f.x) / d, dz = (t.z - f.z) / d;
        final (free, _) = _clear(f.x, f.z, dx, dz, f.radius * 0.9, d);
        if (free >= d - t.radius - 4) {
          _startAttack(f, 'roll', busy ? 0.48 : 0.62, 0.5, 0.65);
          return;
        }
      }
    }
    // circle at a respectful distance, waiting its turn; flip the way round now and then
    f.strafeT -= dt;
    if (f.strafeT <= 0) {
      f.strafe = -f.strafe;
      f.strafeT = 1.6 + rng.nextDouble() * 2.4;
    }
    final want = f.cd <= 0.3 && tokens < cap ? 34.0 : 46.0;
    final rx = (f.x - t.x) / math.max(d, 1e-6), rz = (f.z - t.z) / math.max(d, 1e-6);
    var vx = -rz * f.strafe * 0.8 + rx * (want - d) / 12;
    var vz = rx * f.strafe * 0.8 + rz * (want - d) / 12;
    (vx, vz) = _separate(f, vx, vz, 24);
    (vx, vz) = _steer(f, vx, vz, look: 14);
    f.running = (d - want).abs() > 30;
    _move(f, vx, vz, f.running ? 40 : 24, dt, faceIt: false);
    f.face(t.x - f.x, t.z - f.z);
  }

  void _startAttack(Foe f, String move, double windup, double active, double recover) {
    final t = f.target!;
    f
      ..move = move
      ..st = FoeState.windup
      ..t = 0
      ..windup = windup
      ..active = active
      ..recover = recover
      ..travelled = 0
      ..moving = false;
    f.hit.clear();
    final d = math.max(f.dist(t), 1e-6);
    f.ax = (t.x - f.x) / d;
    f.az = (t.z - f.z) / d;
    f.face(f.ax, f.az);
    _endMark(f);
    _lastSwing[t] = time;
    switch (move) {
      case 'roll':
        f.travelMax = 74;
        f.mark = Mark(MarkShape.line, f.x, f.z, windup, dx: f.ax, dz: f.az, len: 74, width: 18, owner: f);
      case 'nip':
        f.mark = Mark(MarkShape.circle, f.x + f.ax * 12, f.z + f.az * 12, windup, r: 10, owner: f);
      case 'lob':
        break;
      case 'puff':
        f.mark = Mark(MarkShape.circle, f.x, f.z, windup, r: 30, owner: f);
    }
    if (f.mark != null) marks.add(f.mark!);
  }

  void _thornAttack(Foe f, double dt) {
    final t = f.target;
    if (f.st == FoeState.windup) {
      final k = f.t / f.windup;
      if (f.move == 'roll') {
        f.pose = k < 0.5 ? 'crouch' : 'tuck';
        f.sx = 1 + 0.04 * math.sin(f.t * 40);
        // track (with a little lead) until the last 40%
        if (t != null && k < 0.6) {
          final lx = t.x + t.vx * 0.22, lz = t.z + t.vz * 0.22;
          final d = math.max(_len(lx - f.x, lz - f.z), 1e-6);
          f.ax = (lx - f.x) / d;
          f.az = (lz - f.z) / d;
          f.face(f.ax, f.az);
        }
        final (free, _) = _clear(f.x, f.z, f.ax, f.az, f.radius * 0.9, 74);
        f.mark
          ?..x = f.x
          ..z = f.z
          ..dx = f.ax
          ..dz = f.az
          ..len = math.max(free + 6, 20);
      } else {
        f.pose = 'crouch';
        if (t != null) f.face(t.x - f.x, t.z - f.z);
        f.mark
          ?..x = f.x + f.fx * 12
          ..z = f.z + f.fz * 12;
      }
      if (f.mark != null) f.mark!.t = f.t;
      if (f.t >= f.windup) {
        _endMark(f);
        f.st = FoeState.strike;
        f.t = 0;
        if (f.move == 'roll') _emit('roll', x: f.x, z: f.z);
      }
      return;
    }
    if (f.st == FoeState.strike) {
      if (f.move == 'roll') {
        f.pose = 'ball';
        f.spin += dt * 18;
        const sp = 165.0;
        final ox = f.x, oz = f.z;
        f.ghost = true; // rolls through, hitting whoever it meets
        final hitBlock = _place(f, f.x + f.ax * sp * dt, f.z + f.az * sp * dt);
        f.ghost = false;
        f.travelled += _len(f.x - ox, f.z - oz);
        f.dir = dirOf(f.ax, f.az);
        for (final a in [pet, if (sher != null && party) sher!]) {
          if (f.hit.contains(a) || !a.alive) continue;
          if (f.dist(a) < f.radius + a.radius - 1) {
            f.hit.add(a);
            final landed = _hurt(a, 9, from: f, kx: f.ax * 130 + (a.x - f.x) * 2, kz: f.az * 130 + (a.z - f.z) * 2, stun: 0.25, cause: f.summoned ? 'summon' : 'roll');
            if (landed) {
              // it bounces off
              f.st = FoeState.recover;
              f.t = 0;
              f.kx = -f.ax * 60;
              f.kz = -f.az * 60;
              return;
            }
          }
        }
        if (hitBlock && f.travelled < f.travelMax - 2) {
          // into a tree: knocked silly
          _stagger(f, 1.6);
          f.pose = 'hurt';
          f.kx = -f.ax * 50;
          f.kz = -f.az * 50;
          shake = math.max(shake, 0.2);
          bursts.add(Burst('stars', f.x, f.z, 1.6));
          _emit('bonk', x: f.x, z: f.z);
          say('Ha! Right into the tree. Get it!', once: 'bonk');
          return;
        }
        if (f.travelled >= f.travelMax || f.t > 0.8) {
          f.st = FoeState.recover;
          f.t = 0;
        }
      } else {
        f.pose = 'nip';
        if (f.t < 0.08) _move(f, f.ax, f.az, 70, dt, faceIt: false);
        if (t != null && !f.hit.contains(t) && f.dist(t) < f.radius + t.radius + 8) {
          f.hit.add(t);
          _hurt(t, 5, from: f, kx: f.ax * 70, kz: f.az * 70, cause: f.summoned ? 'summon' : 'nip');
        }
        if (f.t > f.active) {
          f.st = FoeState.recover;
          f.t = 0;
        }
      }
      return;
    }
    // recover: open to hits
    f.pose = f.move == 'roll' ? (f.t < f.recover * 0.5 ? 'tuck' : null) : null;
    f.moving = false;
    if (f.t >= f.recover) {
      f.st = FoeState.engage;
      f.t = 0;
      f.pose = null;
      f.cd = f.move == 'nip' ? 1.4 + rng.nextDouble() * 0.7 : 2.2 + rng.nextDouble() * 1.2;
      if (f.hpFrac < 0.3) f.cd *= 0.8;
    }
  }

  // ---- Sporecap
  void _sporeEngage(Foe f, Actor t, double d, double dt) {
    final hop = math.sin(f.phase * math.pi).abs() * 1.7 + 0.15; // it moves while airborne
    // cornered and close: puff
    if (d < f.radius + t.radius + 16 && f.cd2 <= 0) {
      _startAttack(f, 'puff', 0.55, 0.15, 0.55);
      return;
    }
    if (f.st == FoeState.flee && f.t > 2.0) {
      f.st = FoeState.engage;
      f.t = 0;
    }
    if (!f.fled && f.hpFrac < 0.35) {
      f.fled = true;
      f.st = FoeState.flee;
      f.t = 0;
    }
    final tokens = _tokens(t, ranged: true);
    if (f.st != FoeState.flee && f.cd <= 0 && d < 150 && d > 34 && tokens < 2) {
      _startAttack(f, 'lob', 0.75, 0.1, 0.45);
      return;
    }
    // keep its distance: too close, hop the open way out; too far, come nearer; else drift sideways
    double vx, vz, sp;
    if (d < 62 || f.st == FoeState.flee) {
      (vx, vz) = _escape(f, t);
      sp = 21;
    } else if (d > 112) {
      (vx, vz) = _steer(f, t.x - f.x, t.z - f.z);
      sp = 18;
    } else {
      f.strafeT -= dt;
      if (f.strafeT <= 0) {
        f.strafe = -f.strafe;
        f.strafeT = 2 + rng.nextDouble() * 2.5;
      }
      final rx = (f.x - t.x) / d, rz = (f.z - t.z) / d;
      (vx, vz) = _steer(f, -rz * f.strafe, rx * f.strafe, look: 14);
      sp = 10;
    }
    (vx, vz) = _separate(f, vx, vz, 26);
    // it hops to its own rhythm (and moves while it is in the air)
    final ph = f.phase;
    _move(f, vx, vz, sp * hop, dt, faceIt: false);
    f.phase = (ph + dt * 1.7) % 1.0;
    f.moving = true;
    f.face(t.x - f.x, t.z - f.z);
  }

  /// The best way out: of 12 headings, the one that gains the most distance, isn't into a tree or the
  /// water, stays near home, and doesn't flip from the last one.
  (double, double) _escape(Foe f, Actor t) {
    var best = (f.x - t.x, f.z - t.z);
    var bs = -double.infinity;
    for (var i = 0; i < 12; i++) {
      final a = i * math.pi / 6;
      final vx = math.cos(a), vz = math.sin(a);
      final px = f.x + vx * 24, pz = f.z + vz * 24;
      var s = _len(px - t.x, pz - t.z);
      final (free, _) = _clear(f.x, f.z, vx, vz, f.radius, 26);
      if (free < 18) s -= 200;
      final home = _len(px - f.homeX, pz - f.homeZ);
      if (home > 70) s -= (home - 70) * 1.2;
      s += (vx * f.vx + vz * f.vz) * 0.25;
      for (final o in hostile) {
        if (o != f && _len(px - o.x, pz - o.z) < 20) s -= 15;
      }
      if (s > bs) {
        bs = s;
        best = (vx, vz);
      }
    }
    return best;
  }

  void _sporeAttack(Foe f, double dt) {
    final t = f.target;
    if (f.st == FoeState.windup) {
      final k = f.t / f.windup;
      f.pose = k < 0.5 ? 'swell1' : 'swell2';
      f.glow = k;
      if (t != null) f.face(t.x - f.x, t.z - f.z);
      if (f.mark != null) f.mark!.t = f.t;
      if (f.t >= f.windup) {
        _endMark(f);
        f.st = FoeState.strike;
        f.t = 0;
        if (f.move == 'lob' && t != null) {
          final d = f.dist(t);
          final flight = (0.55 + d / 260).clamp(0.6, 1.1);
          // lead where it is heading (a bit short of perfect, so turning dodges it)
          var lx = t.x + t.vx * flight * 0.75, lz = t.z + t.vz * flight * 0.75;
          final off = _len(lx - t.x, lz - t.z);
          if (off > 46) {
            lx = t.x + (lx - t.x) / off * 46;
            lz = t.z + (lz - t.z) / off * 46;
          }
          final sh = Shot(ShotKind.spore, Team.foe, f.x, f.z, life: flight, owner: f, target: t)
            ..lob = true
            ..x0 = f.x
            ..z0 = f.z
            ..x1 = lx
            ..z1 = lz
            ..h = 30;
          sh.mark = Mark(MarkShape.circle, lx, lz, flight, r: 16, owner: f);
          marks.add(sh.mark!);
          shots.add(sh);
          _emit('spore_lob', x: f.x, z: f.z);
        } else if (f.move == 'puff') {
          bursts.add(Burst('spores', f.x, f.z, 0.8, size: 30));
          _emit('puff', x: f.x, z: f.z);
          for (final a in [pet, if (sher != null && party) sher!]) {
            final d = f.dist(a);
            if (d < 30 + a.radius * 0.6) {
              final k = 1 / math.max(d, 1e-6);
              if (_hurt(a, 7, from: f, kx: (a.x - f.x) * k * 110, kz: (a.z - f.z) * k * 110, cause: 'puff')) {
                a.slowT = math.max(a.slowT, 2.5);
              }
            }
          }
          hazards.add(Hazard(f.x, f.z, 22, 2.2));
        }
      }
      return;
    }
    if (f.st == FoeState.strike) {
      f.pose = 'puff';
      f.glow = 0;
      if (f.t > f.active) {
        f.st = FoeState.recover;
        f.t = 0;
      }
      return;
    }
    f.pose = null;
    if (f.t >= f.recover) {
      f.st = FoeState.engage;
      f.t = 0;
      if (f.move == 'puff') {
        f.cd2 = 4.0;
        f.cd = math.max(f.cd, 0.8);
      } else {
        f.cd = 2.3 + rng.nextDouble() * 0.9;
      }
    }
  }

  // ---- defeated: the Hollow lifts
  void _calm(Foe f) {
    _endMark(f);
    f
      ..calm = true
      ..st = FoeState.calm
      ..t = 0
      ..pose = null
      ..spin = 0
      ..ghost = true
      ..glow = 0
      ..kx = 0
      ..kz = 0
      ..moving = false;
    bursts.add(Burst('motes', f.x, f.z, 1.2, size: f is Boss ? 3 : 1));
    if (lock == f) lock = null;
    if (f is Boss) {
      _victory(f);
      return;
    }
    _emit('calm', x: f.x, z: f.z);
    calmed += f.summoned ? 0 : 1;
    // what it leaves: coins into the satchel, sometimes a shard, a mote of light that heals
    final c = (f.kind == 'sporecap' ? 3 : 2) + rng.nextInt(3);
    coins += c;
    _float('+$c coins', f.x, f.z, 'loot', ttl: 1.2);
    if (!f.summoned && rng.nextDouble() < 0.18) {
      items['lumen_shard'] = (items['lumen_shard'] ?? 0) + 1;
      _float('+1 Lumen Shard', f.x, f.z - 6, 'loot', ttl: 1.4);
    }
    final roll = lootRoll;
    if (!f.summoned && roll != null) {
      var dz = 13.0;
      roll(lootRng).forEach((id, n) {
        items[id] = (items[id] ?? 0) + n;
        _float(lootLabel?.call(id, n) ?? '+$n $id', f.x, f.z - dz, 'loot', ttl: 2.0);
        _emit('rare_drop', text: id, x: f.x, z: f.z);
        dz += 7;
      });
    }
    if (rng.nextDouble() < (pet.hpFrac < 0.5 ? 0.7 : 0.35)) pickups.add(Pickup('mote', f.x + 4, f.z + 3, 14));
    // a cleared clearing
    final z = f.zone;
    if (f.summoned) return;
    if (!cleared.contains(z) && foes.where((o) => o.zone == z && !o.summoned).every((o) => o.calm)) {
      cleared.add(z);
      var name = 'The clearing';
      for (final zz in zones) {
        if (zz.id == z) name = zz.name;
      }
      _emit('zone', text: name);
      say(['$name is calm. Nice work!', 'That\'s the lot. Breathe.', 'Calm again. Onward.'][rng.nextInt(3)], gap: 2);
    }
  }

  void _tickCalm(Foe f, double dt) {
    f.sx = f.sy = 1;
    if (f is Boss) {
      f.moving = false;
      f.pose = null;
      if (bossState == BossState.calm && f.t > 0.5) {
        // it lingers by the gate, at peace; turns to you when you come near
        if (pet.dist(f) < 90) f.face(pet.x - f.x, pet.z - f.z);
      }
      return;
    }
    if (f.t < 0.9) {
      f.moving = false;
      f.lift = math.sin(f.t / 0.9 * math.pi) * 4; // a happy hop
      return;
    }
    // trots off toward the nearer edge of the wood, fading
    final edge = f.x < 0 ? ground.bounds.left - 30 : ground.bounds.right + 30;
    f.ghost = true;
    f.running = false;
    f.face(edge - f.x, 0.3);
    f.x += f.fx * 24 * dt;
    f.z += f.fz * 24 * dt;
    f.moving = true;
    f.phase = (f.phase + 24 * dt / f.cycle) % 1.0;
    f.alpha = math.max(0, 1 - (f.t - 1.6) / 1.4);
  }

  // ================================================================== shots, clouds, rings, pickups
  void _tickShots(double dt) {
    for (final s in shots) {
      s.t += dt;
      if (s.lob) {
        final k = (s.t / s.life).clamp(0.0, 1.0);
        s.x = s.x0 + (s.x1 - s.x0) * k;
        s.z = s.z0 + (s.z1 - s.z0) * k;
        s.mark?.t = s.t;
        if (s.t >= s.life) {
          s.done = true;
          s.mark?.done = true;
          if (s.kind == ShotKind.spore) {
            bursts.add(Burst('spores', s.x, s.z, 0.7, size: 16));
            hazards.add(Hazard(s.x, s.z, 18, 3.0));
            _emit('spore_land', x: s.x, z: s.z);
            for (final a in [pet, if (sher != null && party) sher!]) {
              if (_len(a.x - s.x, a.z - s.z) < 16 + a.radius * 0.6) {
                if (_hurt(a, 8, from: s.owner, cause: 'spore')) a.slowT = math.max(a.slowT, 2.5);
              }
            }
          } else if (s.kind == ShotKind.vial) {
            bursts.add(Burst('flash', s.x, s.z, 0.5, size: 18));
            _emit('vial_land', x: s.x, z: s.z);
            for (final f in hostile.toList()) {
              if (_len(f.x - s.x, f.z - s.z) < 18 + f.radius) {
                _hurt(f, 10, from: s.owner, poise: 12);
                if (f is! Boss) f.stun = math.max(f.stun, 0.8);
              }
            }
          }
        }
        continue;
      }
      // a glow bolt: homes a little
      final t = s.target;
      if (t != null && t.alive && !t.calm) {
        final dx = t.x - s.x, dz = t.z - s.z;
        final d = math.max(_len(dx, dz), 1e-6);
        final sp = _len(s.vx, s.vz);
        final turn = math.min(1.0, 4.0 * dt);
        var nvx = s.vx / sp * (1 - turn) + dx / d * turn, nvz = s.vz / sp * (1 - turn) + dz / d * turn;
        final nl = _len(nvx, nvz);
        nvx /= nl;
        nvz /= nl;
        s.vx = nvx * sp;
        s.vz = nvz * sp;
      }
      s.x += s.vx * dt;
      s.z += s.vz * dt;
      if (s.t > s.life || _blockedAt(s.x, s.z, 1, water: false)) {
        s.done = true;
        bursts.add(Burst('spark', s.x, s.z, 0.25));
        continue;
      }
      for (final f in hostile.toList()) {
        if (_len(f.x - s.x, f.z - s.z) < f.radius + 4) {
          final sp = math.max(_len(s.vx, s.vz), 1e-6);
          _hurt(f, _boltDmg * atk, from: pet, kx: s.vx / sp * 50, kz: s.vz / sp * 50, poise: 10);
          s.done = true;
          bursts.add(Burst('glow', s.x, s.z, 0.35));
          break;
        }
      }
    }
    shots.removeWhere((s) => s.done);
  }

  void _tickHazards(double dt) {
    for (final h in hazards) {
      h.t += dt;
      for (final a in [pet, if (sher != null && party) sher!]) {
        if (_len(a.x - h.x, a.z - h.z) < h.r + a.radius * 0.4) a.slowT = math.max(a.slowT, 0.6);
      }
    }
    hazards.removeWhere((h) => h.t >= h.life);
  }

  void _tickWaves(double dt) {
    for (final w in waves) {
      w.r += 105 * dt;
      for (final a in [pet, if (sher != null && party) sher!]) {
        if (w.hit.contains(a)) continue;
        final d = _len(a.x - w.x, a.z - w.z);
        if ((d - w.r).abs() < 6 + a.radius * 0.6) {
          w.hit.add(a);
          final k = 1 / math.max(d, 1e-6);
          _hurt(a, 12, from: boss, kx: (a.x - w.x) * k * 120, kz: (a.z - w.z) * k * 120, stun: 0.2, cause: 'ring');
        }
      }
    }
    waves.removeWhere((w) => w.r > w.maxR);
  }

  void _tickPickups(double dt) {
    for (final p in pickups) {
      p.t += dt;
      if (_len(pet.x - p.x, pet.z - p.z) < 14 + pet.radius) {
        p.t = 999;
        final before = pet.hp;
        pet.hp = math.min(pet.maxHp, pet.hp + p.amount);
        final got = (pet.hp - before).round();
        if (got > 0) _float('+$got', pet.x, pet.z, 'heal');
        bursts.add(Burst('heal', pet.x, pet.z, 0.6));
        _emit('pickup');
      }
    }
    pickups.removeWhere((p) => p.t > 20);
  }

  // ================================================================== the guardian
  void _tickBoss(Boss b, double dt) {
    b.t += dt;
    b.sx = b.sy = 1;
    b.lift = 0;
    if (b.calm) {
      _tickCalm(b, dt);
      return;
    }
    switch (bossState) {
      case BossState.dormant:
        // it stands with its head low, roots round its legs, until you step into the arena
        b.pose = 'lower1';
        b.moving = false;
        if (pet.distTo(b.ax0, b.az0) < b.ar - 6 && pet.z < b.az0 + b.ar * 0.55) {
          bossState = BossState.intro;
          b.st = FoeState.roar;
          b.t = 0;
          b.target = pet;
          b.face(pet.x - b.x, pet.z - b.z);
          wallUp = true;
          _rebuildBlocks();
          // Sher hops the brambles if he was still outside; nobody is left standing in the wall
          final s = sher;
          if (s != null && party && s.distTo(b.ax0, b.az0) > b.ar - 12) {
            s
              ..x = pet.x + 14
              ..z = pet.z + 8;
            bursts.add(Burst('dust', s.x, s.z, 0.6));
          }
          for (final a in [pet, if (s != null) s]) {
            _place(a, a.x, a.z);
          }
          _emit('boss_intro');
          shake = 0.6;
        }
        return;
      case BossState.intro:
        b.pose = b.t < 0.5 ? 'lower2' : 'roar';
        b.moving = false;
        if (b.t > 0.5 && b.t - dt <= 0.5) {
          _emit('roar');
          shake = 0.8;
        }
        if (b.t > 2.2) {
          bossState = BossState.fight;
          b.st = FoeState.engage;
          b.t = 0;
          b.think = 0.6;
          say('Its charge! Get a pillar between you and it.', once: 'boss_hint');
        }
        return;
      case BossState.fight:
        break;
      default:
        return;
    }
    for (final k in b.cds.keys.toList()) {
      b.cds[k] = b.cds[k]! - dt;
    }
    for (final k in b.threat.keys.toList()) {
      b.threat[k] = b.threat[k]! * math.exp(-dt * 0.12);
    }
    final t = b.target = (b.target == null || b.t % 1.5 < dt) ? _bestTarget(b) : b.target;
    if (t == null) return;
    final d = b.dist(t);
    // how you've been playing
    final behind = ((t.x - b.x) * b.fx + (t.z - b.z) * b.fz) / math.max(d, 1e-6) < -0.2;
    b.kite += ((d > 70 ? 1.0 : 0.0) - b.kite) * math.min(1, dt * 0.25);
    b.hug += ((d < 45 && behind ? 1.0 : 0.0) - b.hug) * math.min(1, dt * 0.35);
    b.behindT = behind && d < 60 ? b.behindT + dt : 0;
    switch (b.st) {
      case FoeState.stagger:
        b.moving = false;
        b.pose = 'stagger';
        if (b.stun <= 0) {
          b.st = FoeState.engage;
          b.t = 0;
          b.think = 0.3;
          b.pose = null;
        }
      case FoeState.roar:
        b.moving = false;
        b.pose = 'roar';
        if (b.t > 0.35 && b.t - dt <= 0.35) {
          _emit('roar');
          shake = 0.7;
          // a shove round it
          for (final a in [pet, if (sher != null && party) sher!]) {
            final dd = b.dist(a);
            if (dd < 46) {
              final k = 1 / math.max(dd, 1e-6);
              a.kx += (a.x - b.x) * k * 160;
              a.kz += (a.z - b.z) * k * 160;
            }
          }
          _summon(b);
        }
        if (b.t > 1.5) {
          b.st = FoeState.engage;
          b.t = 0;
          b.think = 0.4;
        }
      case FoeState.engage:
        _bossEngage(b, t, d, dt);
      case FoeState.windup:
      case FoeState.strike:
      case FoeState.recover:
        _bossAttack(b, t, dt);
      default:
        b.st = FoeState.engage;
    }
  }

  void _turnToward(Boss b, double tx, double tz, double dt) {
    final want = math.atan2(tx - b.x, tz - b.z);
    final have = math.atan2(b.fx, b.fz);
    var diff = want - have;
    while (diff > math.pi) {
      diff -= 2 * math.pi;
    }
    while (diff < -math.pi) {
      diff += 2 * math.pi;
    }
    final step = diff.clamp(-b.turnRate * dt, b.turnRate * dt);
    final a = have + step;
    b.face(math.sin(a), math.cos(a));
  }

  void _bossEngage(Boss b, Actor t, double d, double dt) {
    b.pose = null;
    b.gait = 'walk';
    b.think -= dt;
    final facing = ((t.x - b.x) * b.fx + (t.z - b.z) * b.fz) / math.max(d, 1e-6);
    if (b.think <= 0) {
      final pick = _bossChoose(b, t, d, facing);
      if (pick != null) {
        _bossStart(b, pick, t);
        return;
      }
    }
    // keep a comfortable range, turning slowly (its flank is the place to be)
    _turnToward(b, t.x, t.z, dt);
    final sp = 20.0 * (b.stage >= 3 ? 1.3 : 1);
    if (d > 52) {
      final (vx, vz) = _steer(b, b.fx, b.fz, look: 26);
      _move(b, vx, vz, sp, dt, faceIt: false);
    } else if (d < 26) {
      _move(b, -b.fx, -b.fz, sp * 0.6, dt, faceIt: false);
    } else {
      b.moving = false;
    }
  }

  /// Utility: each move's score from range, facing, cooldown, repetition and how you play; a weighted
  /// pick among the good ones.
  String? _bossChoose(Boss b, Actor t, double d, double facing) {
    final sc = <String, double>{};
    if (b.cds['sweep']! <= 0 && d < 50 + t.radius && facing > 0.35) sc['sweep'] = 1.3;
    if (b.cds['charge']! <= 0 && d > 55) {
      final (free, _) = _clear(b.x, b.z, (t.x - b.x) / d, (t.z - b.z) / d, b.radius * 0.8, d);
      sc['charge'] = (0.6 + b.kite * 0.9) * (free > d * 0.5 ? 1.0 : 0.4);
    }
    if (b.cds['roots']! <= 0 && d > 30) sc['roots'] = 0.55 + b.kite * 0.5;
    if (b.stage >= 2 && b.cds['ring']! <= 0) sc['ring'] = (d < 60 ? 0.9 : 0.25) + b.hug * 1.2 + (b.behindT > 1.2 ? 1.0 : 0);
    if (sc.isEmpty) {
      b.think = 0.2;
      return null;
    }
    if (sc.containsKey(b.last)) sc[b.last] = sc[b.last]! * 0.35;
    final total = sc.values.fold(0.0, (a, v) => a + v * v);
    var r = rng.nextDouble() * total;
    for (final e in sc.entries) {
      r -= e.value * e.value;
      if (r <= 0) return e.key;
    }
    return sc.keys.first;
  }

  void _bossStart(Boss b, String move, Actor t) {
    b
      ..move = move
      ..last = move
      ..st = FoeState.windup
      ..t = 0
      ..travelled = 0
      ..feinted = false
      ..moving = false;
    b.hit.clear();
    _endMark(b);
    final d = math.max(b.dist(t), 1e-6);
    switch (move) {
      case 'sweep':
        b.windup = 0.8 * b.quick;
        b.active = 0.28;
        b.recover = 0.7 * b.quick;
        b.cds['sweep'] = 1.6;
        b.mark = Mark(MarkShape.cone, b.x, b.z, b.windup, r: 54, dx: b.fx, dz: b.fz, half: 66 * math.pi / 180, owner: b);
        _emit('boss_windup', text: 'sweep');
      case 'charge':
        b.windup = (b.chain > 0 ? 0.62 : 1.05) * b.quick;
        b.active = 2.0;
        b.recover = 0.8 * b.quick;
        b.cds['charge'] = (b.stage >= 3 ? 3.6 : 5.5);
        b.ax = (t.x - b.x) / d;
        b.az = (t.z - b.z) / d;
        b.face(b.ax, b.az);
        b.mark = Mark(MarkShape.line, b.x, b.z, b.windup, dx: b.ax, dz: b.az, len: 200, width: 36, owner: b);
        _emit('boss_windup', text: 'charge');
        if (b.chain == 0) say(b.stage >= 3 ? 'It\'s not stopping! Keep rolling!' : 'Charge! Sidestep it, into a pillar!', gap: 5);
      case 'roots':
        b.windup = 0.85 * b.quick;
        b.active = 1.0;
        b.recover = 0.6 * b.quick;
        b.cds['roots'] = 6.0;
        _emit('boss_windup', text: 'roots');
        say('Roots! Keep moving!', gap: 5);
      case 'ring':
        b.windup = 0.95 * b.quick;
        b.active = 0.2;
        b.recover = 0.7 * b.quick;
        b.cds['ring'] = 7.5;
        b.mark = Mark(MarkShape.ring, b.x, b.z, b.windup, r: 26, owner: b);
        _emit('boss_windup', text: 'ring');
        say('Thorn ring! Roll through it!', once: 'ring_hint');
    }
    if (b.mark != null) marks.add(b.mark!);
  }

  void _bossAttack(Boss b, Actor t, double dt) {
    final k = b.windup <= 0 ? 1.0 : b.t / b.windup;
    if (b.st == FoeState.windup) {
      // it reads an early dodge: from the second phase it may hold the sweep or the charge a beat, so a
      // roll made too soon is spent before the hit comes (the telegraph slows to show it is waiting)
      if (!b.feinted && b.stage >= 2 && (b.move == 'sweep' || b.move == 'charge') && k > 0.45 && k < 0.92) {
        final early = _dodgeAt > time - b.t && time - _dodgeAt < 0.4 && t == pet;
        if (early && rng.nextDouble() < (b.stage >= 3 ? 0.55 : 0.4)) {
          b.feinted = true;
          b.windup += 0.45;
          b.mark?.dur += 0.45;
          say('Wait for it...', once: 'feint');
        }
      }
      b.mark?.t = b.t;
      switch (b.move) {
        case 'sweep':
          b.pose = 'lower1';
          if (k < 0.5 || (b.feinted && b.windup - b.t > 0.2)) _turnToward(b, t.x, t.z, dt);
          b.mark
            ?..x = b.x
            ..z = b.z
            ..dx = b.fx
            ..dz = b.fz;
        case 'charge':
          b.pose = k < 0.45 ? 'lower1' : 'lower2';
          b.sx = 1 + 0.03 * math.sin(b.t * 35);
          if (k < 0.65 || (b.feinted && b.windup - b.t > 0.2)) {
            final lx = t.x + t.vx * 0.15, lz = t.z + t.vz * 0.15;
            final dd = math.max(_len(lx - b.x, lz - b.z), 1e-6);
            b.ax = (lx - b.x) / dd;
            b.az = (lz - b.z) / dd;
            b.face(b.ax, b.az);
          }
          // it runs on past you, then pulls up; it only crashes if something stands in that run
          final (free, _) = _clear(b.x, b.z, b.ax, b.az, b.radius * 0.8, 260);
          final reach = math.min(_len(t.x - b.x, t.z - b.z) + 55, 175.0);
          b.travelMax = math.min(free + 4, reach);
          b.mark
            ?..x = b.x
            ..z = b.z
            ..dx = b.ax
            ..dz = b.az
            ..len = math.max(b.travelMax + b.radius, 30);
        case 'roots':
          b.pose = k < 0.55 ? 'rear1' : 'rear2';
        case 'ring':
          b.pose = k < 0.5 ? 'rear1' : 'rear2';
          b.mark
            ?..x = b.x
            ..z = b.z;
      }
      if (b.t >= b.windup) {
        _endMark(b);
        b.st = FoeState.strike;
        b.t = 0;
        _bossStrike(b, t);
      }
      return;
    }
    if (b.st == FoeState.strike) {
      switch (b.move) {
        case 'sweep':
          b.pose = b.t < b.active * 0.5 ? 'sweep_l' : 'sweep_r';
          if (b.t >= b.active) _bossRecover(b);
        case 'charge':
          b.pose = null;
          b.gait = 'charge';
          final sp = 190.0 * (b.stage >= 3 ? 1.1 : 1);
          final ox = b.x, oz = b.z;
          b.ghost = true;
          final hitBlock = _place(b, b.x + b.ax * sp * dt, b.z + b.az * sp * dt);
          b.ghost = false;
          final moved = _len(b.x - ox, b.z - oz);
          b.travelled += moved;
          b.moving = true;
          b.running = true;
          b.phase = (b.phase + moved / 30) % 1.0;
          b.dir = dirOf(b.ax, b.az);
          for (final a in [pet, if (sher != null && party) sher!]) {
            if (b.hit.contains(a) || !a.alive) continue;
            if (b.dist(a) < b.radius + a.radius) {
              b.hit.add(a);
              // thrown aside, away from its line
              final side = (a.x - b.x) * b.az - (a.z - b.z) * b.ax >= 0 ? 1.0 : -1.0;
              _hurt(a, 22, from: b, kx: (b.az * side * 1.0 + b.ax * 0.5) * 230, kz: (-b.ax * side * 1.0 + b.az * 0.5) * 230, stun: 0.4, cause: 'charge');
            }
          }
          if (hitBlock && b.travelled > 12) {
            // it crashed: dazed, open
            b.running = false;
            b.gait = 'walk';
            _stagger(b, 2.6);
            b.kx = -b.ax * 40;
            b.kz = -b.az * 40;
            b.chain = 0;
            shake = 0.9;
            hitstop = 0.08;
            bursts.add(Burst('stars', b.x, b.z, 2.6, size: 2));
            bursts.add(Burst('dust', b.x + b.ax * b.radius, b.z + b.az * b.radius, 0.8, size: 2));
            _emit('crash', x: b.x, z: b.z);
            say('It crashed! Hit it now!', gap: 3);
            return;
          }
          if (b.travelled >= b.travelMax || moved < sp * dt * 0.3 || b.t > 2.2) {
            b.running = false;
            b.gait = 'walk';
            if (b.stage >= 3 && b.chain < 1) {
              b.chain++;
              _bossStart(b, 'charge', t);
              return;
            }
            b.chain = 0;
            _bossRecover(b);
          }
        case 'roots':
          b.pose = 'stomp';
          if (b.t >= 0.3) _bossRecover(b);
        case 'ring':
          b.pose = 'stomp';
          if (b.t >= b.active) _bossRecover(b);
      }
      return;
    }
    // recover: its head comes up slowly (a window to hit it)
    b.pose = b.move == 'charge' ? 'lower1' : null;
    b.moving = false;
    if (b.t >= b.recover) {
      b.st = FoeState.engage;
      b.t = 0;
      b.pose = null;
      b.think = (0.35 + rng.nextDouble() * 0.45) * b.quick;
    }
  }

  void _bossRecover(Boss b) {
    b.st = FoeState.recover;
    b.t = 0;
  }

  void _bossStrike(Boss b, Actor t) {
    switch (b.move) {
      case 'sweep':
        _emit('sweep', x: b.x, z: b.z);
        bursts.add(Burst('sweep', b.x, b.z, 0.3, dx: b.fx, dz: b.fz, size: 54));
        final cone = Mark(MarkShape.cone, b.x, b.z, 0, r: 54, dx: b.fx, dz: b.fz, half: 66 * math.pi / 180);
        for (final a in [pet, if (sher != null && party) sher!]) {
          if (cone.covers(a.x, a.z, a.radius)) {
            final d = math.max(b.dist(a), 1e-6);
            _hurt(a, 18, from: b, kx: (a.x - b.x) / d * 170, kz: (a.z - b.z) / d * 170, stun: 0.3, cause: 'sweep');
          }
        }
      case 'charge':
        _emit('charge', x: b.x, z: b.z);
      case 'roots':
        _emit('stomp', x: b.x, z: b.z);
        shake = math.max(shake, 0.5);
        final spots = <(double, double)>[];
        for (final a in [pet, if (sher != null && party && sherWinded <= 0) sher!]) {
          spots.add((a.x, a.z));
        }
        // where your Evochi is heading, and a few round it
        spots.add((pet.x + pet.vx * 0.8, pet.z + pet.vz * 0.8));
        final extra = b.stage >= 3 ? 4 : 2;
        for (var i = 0; i < extra; i++) {
          final a = rng.nextDouble() * math.pi * 2, r = 22 + rng.nextDouble() * 26;
          spots.add((pet.x + math.cos(a) * r, pet.z + math.sin(a) * r));
        }
        for (final (x, z) in spots) {
          if (_len(x - b.ax0, z - b.az0) > b.ar) continue;
          final m = Mark(MarkShape.circle, x, z, 0.95, r: 15, owner: b);
          marks.add(m);
          _roots.add(m);
        }
      case 'ring':
        _emit('stomp', x: b.x, z: b.z);
        shake = math.max(shake, 0.5);
        waves.add(Wave(b.x, b.z, 150));
    }
  }

  final _roots = <Mark>[];

  /// Roots burst up where their marks fill.
  void _tickRoots(double dt) {
    for (final m in _roots) {
      m.t += dt;
      if (m.t >= m.dur && !m.done) {
        m.done = true;
        bursts.add(Burst('roots', m.x, m.z, 0.7, size: m.r));
        _emit('roots', x: m.x, z: m.z);
        for (final a in [pet, if (sher != null && party) sher!]) {
          if (_len(a.x - m.x, a.z - m.z) < m.r + a.radius * 0.5) {
            _hurt(a, 14, from: boss, stun: 0.45, cause: 'roots');
          }
        }
      }
    }
    _roots.removeWhere((m) => m.done);
  }

  void _bossHealthCheck(Boss b) {
    final f = b.hpFrac;
    if (b.stage == 1 && f <= 0.6) {
      b.stage = 2;
      _bossRoar(b);
      say('It\'s calling for help! Watch your back.', gap: 2);
    } else if (b.stage == 2 && f <= 0.3) {
      b.stage = 3;
      _bossRoar(b);
      say('It\'s furious now. Stay light on your feet!', gap: 2);
    }
  }

  void _bossRoar(Boss b) {
    _endMark(b);
    b.running = false;
    b.gait = 'walk';
    b.chain = 0;
    b.st = FoeState.roar;
    b.t = 0;
    b.glow = b.stage >= 3 ? 1 : 0.5;
    _emit('boss_phase', value: b.stage.toDouble());
  }

  void _summon(Boss b) {
    final def = bossDef;
    if (def == null) return;
    final want = (b.stage == 2 && !b.summoned60) || (b.stage == 3 && !b.summoned30);
    if (!want) return;
    if (b.stage == 2) b.summoned60 = true;
    if (b.stage == 3) b.summoned30 = true;
    // two Thornlings out of the brambles, from the spots farthest from your Evochi
    final spots = [...def.summon]..sort((a, c) => _len(c.$1 - pet.x, c.$2 - pet.z).compareTo(_len(a.$1 - pet.x, a.$2 - pet.z)));
    for (var i = 0; i < 2 && i < spots.length; i++) {
      final (x, z) = spots[i];
      final f = _spawn('summon_${b.stage}_$i', 'thornling', 'arena', x, z)
        ..summoned = true
        ..maxHp = 40
        ..hp = 40
        ..cd = 1.2 + i * 0.8;
      f.homeX = b.ax0;
      f.homeZ = b.az0;
      foes.add(f);
      bursts.add(Burst('dust', x, z, 0.8));
      f.target = pet;
      f.st = FoeState.alert;
      f.alertDelay = 0.5 + i * 0.3;
      f.face(pet.x - x, pet.z - z);
    }
  }

  void _victory(Boss b) {
    bossState = BossState.calm;
    b.st = FoeState.calm;
    b.calm = true;
    b.ghost = false;
    b.glow = 0;
    b.running = false;
    b.gait = 'walk';
    marks.clear();
    _roots.clear();
    waves.clear();
    shots.removeWhere((s) => s.team == Team.foe);
    for (final f in foes.toList()) {
      if (f.summoned && !f.calm) {
        f.hp = 0;
        _calm(f);
      }
    }
    wallUp = false;
    _rebuildBlocks();
    shake = 1.0;
    hitstop = 0.18;
    bursts.add(Burst('purify', b.x, b.z, 2.2, size: 3));
    _emit('victory');
    say('You did it! Look... the Hollow\'s gone out of it.', gap: 1);
  }

  /// Playtesting (debug builds): take a share of the guardian's health, as a hit would.
  void debugHurtBoss(double frac) {
    final b = boss;
    if (b == null || b.calm || bossState != BossState.fight) return;
    b.hp = math.max(1, b.hp - b.maxHp * frac);
    _bossHealthCheck(b);
  }

  /// The guardian again, after it has been calmed: it stands ready to spar.
  void rematch() {
    final b = boss;
    if (b == null) return;
    b
      ..calm = false
      ..hp = b.maxHp
      ..stage = 1
      ..st = FoeState.dormant
      ..pose = 'lower1'
      ..alpha = 1
      ..summoned30 = false
      ..summoned60 = false
      ..ghost = false;
    b.threat.clear();
    bossState = BossState.dormant;
  }
}
