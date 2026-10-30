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
  double tilt = 0; // a lean in radians (drawn only), toward screen-right when positive
  double size = 1; // drawn bigger (an elite)
  double pop = 0; // 1 at the instant of a hit, easing to 0: the body squashes and springs back
  // state
  double flash = 0, iframes = 0, stun = 0, slowT = 0, mercy = 0;
  double burnT = 0, _burnFx = 0; // set alight by an Ember Draught's hits
  double chillT = 0; // chilled by a Frost coating: moves and winds up slower
  double daze = 0; // built up by a Dazzle coating: at 100 it reels
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
  bool elite = false; // a Deep Wilds elite: bigger, tougher, hits harder, drops more
  int lashes = 0; // the Hollow Sprout's lashes in a row
  final extra = <Mark>[]; // more than one telegraph at once (the Hollow Sprout's thorns)
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
  int pierce = 0; // foes it can pass through (a Juvenile's bolt goes through one)
  double power = 1; // a share of a full bolt's damage (the Prism Charm's side bolts)
  bool prism = false; // drawn in rainbow
  bool shard = false; // an Elder's crystal shard
  final hits = <Actor>{};
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
  Pickup(this.kind, this.x, this.z, this.amount, {this.vx = 0, this.vz = 0, this.vy = 0});
  final String kind; // mote (heals) | bloom (the Starseed Charm's: heals) | loot (a glint of what a calmed foe left: it flies to you) | coin (bursts out, bounces, then flies up to your purse)
  double x, z;
  final int amount;
  double vx, vz;
  double vy, y = 0; // a coin's height and climb (units)
  int bounces = 0;
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
  Burst(this.kind, this.x, this.z, this.ttl, {this.dx = 0, this.dz = 1, this.size = 1, this.tag = ''});
  final String kind;
  final String tag; // e.g. the coating that tints a swipe
  final double x, z, ttl, dx, dz, size;
  double t = 0;
}

/// An ore node in the mines, struck with the Pounce (MINES_PLAN.md): it cracks whole -> chipped ->
/// cracked -> burst over its hits (times your mining power), and grows back a while after it bursts.
/// Too hard for your gear: a clink, nothing lost.
class OreRock {
  OreRock(this.id, this.kind, this.x, this.z, {required this.hits, required this.tier, this.radius = 9});
  final String id, kind;
  final double x, z, radius;
  final int hits, tier;
  double damage = 0;
  int state = 0; // 0 whole, 1 chipped, 2 cracked, 3 burst
  double hitAt = -9, hitDir = 1, brokeAt = -9, noteAt = -9;
  bool get broken => state == 3;

  bool strike(double power) {
    damage += power;
    if (damage >= hits - 1e-6) {
      state = 3;
      return true;
    }
    state = damage / hits < 0.5 ? 1 : 2;
    return false;
  }
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
const _pulseCost = 34.0, _pulseCd = 7.0, _pulseDmg = 18.0, _pulseR0 = 36.0;
const _dodgeCost = 20.0, _dodgeTime = 0.3, _dodgeDist = 46.0;

/// A potion's buff in the Wilds (an Apothecary brew drunk mid-run).
class BuffDef {
  const BuffDef(this.name, this.secs, this.text);
  final String name;
  final double secs;
  final String text;
}

const buffDefs = <String, BuffDef>{
  'regen': BuffDef('Regenerating', 20, '+3 Raid HP a second'),
  'swift': BuffDef('Swift', 30, 'Stamina comes back 60% faster; dodges cost less'),
  'moonlit': BuffDef('Moonlit', 30, 'A 1 in 4 chance to crit'),
  'lantern': BuffDef('Lantern-lit', 30, 'The Hollow hits 35% softer'),
  'ember': BuffDef('Ember', 30, 'Your hits set foes alight'),
  'thornskin': BuffDef('Thornskin', 25, 'Strikers take 40% of their blow back'),
  // coatings: something on your own attacks (one at a time)
  'frost': BuffDef('Frost', 30, 'Your hits chill: foes move and wind up slower'),
  'static': BuffDef('Static', 30, 'Every fourth hit sparks to another foe'),
  'sap': BuffDef('Sap', 30, 'Your hits heal you a little'),
  'dazzle': BuffDef('Dazzle', 30, 'Your hits build dizziness until a foe reels'),
  'hush': BuffDef('Hush', 30, 'Your hits break guard far sooner'),
};

/// Coatings sit on your Evochi's own attacks; a new one washes the last one off.
const coatings = {'ember', 'frost', 'static', 'sap', 'dazzle', 'hush'};
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
    this.stage = 1,
    this.charm,
    this.charmRank = 1,
    this.palette = 'amber',
    int seed = 7,
    this.lootRoll,
    this.lootLabel,
    this.ward = 0,
    double bossScale = 1.0,
    this.foeHp = 1.0,
    this.foeHarm = 1.0,
    this.coinMul = 1.0,
    this.surge = false,
    this.storyBeat,
    this.storyX = 0,
    this.storyZ = 0,
    this.companion = false,
    List<OreRock> ores = const [],
    this.miningPower = 1.0,
    this.oreTier = 1,
  })  : ores = List.of(ores),
        rng = math.Random(seed),
        lootRng = math.Random(seed * 31 + 7) {
    startX = pet.x;
    startZ = pet.z;
    // each evolution hits a little harder (and its moves change: see the Pounce, Bolt and Pulse)
    atk = (1 + 0.06 * (level - 1)) * (1 + 0.08 * (stage.clamp(1, 3) - 1));
    for (final s in spawns) {
      foes.add(_spawn(s.id, s.kind, s.zone, s.x, s.z));
    }
    // a story floor's creature; Petalune at your side once it trusts you
    if (storyBeat == 'trust') {
      friends.add(_friend(storyX, storyZ));
    } else if (companion) {
      friends.add(_friend(pet.x - 16, pet.z + 12)
        ..calm = true
        ..alpha = 1);
    }
    if (storyBeat == 'sprout') foes.add(_sprout(storyX, storyZ));
    if (storyBeat == 'sentinel') foes.add(_sentinel(storyX, storyZ));
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
  final int stage; // your Evochi's: 1 Eggling, 2 Juvenile, 3 Elder
  // the charm it wears (game/wilds/charms.dart) and its rank, 1-3
  final String? charm;
  final int charmRank;
  final String palette; // your Evochi's colour: an Elder's signature move is its colour's own
  /// An Elder's signature move, filled by perfect dodges, counters and close calls (0-100).
  double sig = 0;
  bool get sigReady => stage >= 3 && sig >= 100;
  double _reefT = 0, _reefX = 0, _reefZ = 0; // the Reef Bloom's healing ground
  void _sigGain(double n) {
    if (stage < 3) return;
    final was = sig;
    sig = math.min(100, sig + n);
    if (was < 100 && sig >= 100) _emit('sig_ready');
  }
  int _charmN = 0; // hits toward the Static Acorn's next spark
  double _charmSapCd = 0;
  int get _ci => (charmRank - 1).clamp(0, 2);
  /// Deeper floors: the creatures' health and the harm they do, as multiples.
  final double foeHp, foeHarm;

  /// The coins a calmed creature leaves, as a multiple (a Lumen-rich floor, a Surge).
  final double coinMul;

  /// A Hollow Surge floor: every creature churns with the Hollow (drawn so), and an elite leaves twice the
  /// rare rolls.
  final bool surge;

  // ---- story floors (game/wilds/story_floors.dart): the beat, where it plays, and Petalune
  /// trust (earn Petalune's trust: it is never fought) | sprout (restore the Hollow Sprout) | null.
  final String? storyBeat;
  final double storyX, storyZ;

  /// Round Petalune's ruins, a haven: no Hollow creature follows you in while it learns to trust you.
  static const havenR = 74.0;

  /// Petalune walks with you (befriended before): it casts Petal Hush when a fight goes on.
  final bool companion;

  /// Creatures on your side that nobody fights: Petalune (wary, then a friend).
  final friends = <Foe>[];

  /// Petalune's trust, 0 to 100. Being near and gentle grows it to 70; a hum or a treat takes it the rest.
  double trust = 0;
  static const trustDrift = 70.0;

  /// The story's beat is done: Petalune trusts you, or the Sprout or the Sentinel is restored.
  bool storyDone = false;

  // ---- the Forgotten Sentinel (the Sentinel's Gate, F5)
  /// Its Hollow shield while it kneels behind it (0: down). Only Lumen breaks it (your Evochi lit by a
  /// Lantern Tonic), or calming what it called out of the dark.
  double sentinelShield = 0, sentinelShieldMax = 1;
  int sentinelShields = 0; // raised so far (at two thirds and a third of its Hollow)
  double _shieldT = 0;

  /// Its eyes' beam while it sweeps (for drawing): from (x, z) along (dx, dz), [len] long; [k] 0..1 through
  /// the sweep.
  ({double x, double z, double dx, double dz, double len, double k})? beam;
  Foe? get sentinel => foes.where((f) => f.kind == 'sentinel').firstOrNull;
  double _humCd = 0, _startleCd = 0, _friendPoseT = 0, _hushT = 8, _wasAct = 0;
  Foe? get petalune => friends.where((f) => f.kind == 'petalune').firstOrNull;
  bool get humReady => _humCd <= 0;
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
  /// The mines: the ore in the floor, your gear's reach (the hardest ore it breaks) and power.
  final List<OreRock> ores;
  final double miningPower;
  int oreTier; // (the recorder raises it mid-floor for a Short)
  double time = 0, hitstop = 0, shake = 0;
  double flashT = 0; // a flash over the whole view (a heavy hit, a signature move), seconds left
  String flashKind = 'white'; // white, or the palette a signature move is tinted by
  double _sigWind = 0; // a signature move winding up (the world slows, then it fires)

  /// An Elder's ultimate plays its cut-in (the screen has the art, and short animations are off): the world holds
  /// from the button until the screen's release marker ([ultRelease]), then the effect resolves, once. Off: the
  /// short wind-up. The cut-in only presents: what the ultimate does is decided here.
  bool cinematic = false;

  /// > 0 while a cut-in plays: seconds since it began (the world holds)
  double ultHold = 0;

  /// Healing Mist's wave on its way: each creature it will reach, when (s after the release), and its push
  final _mistHits = <(Foe, double, double, double)>[];
  double _mistT = 0;

  /// how fast the mist's leading edge rolls out (world units a second)
  static const mistSpeed = 420.0;
  /// A perfect dodge slows the world for a moment (real seconds left) and opens a counter window.
  double slowmo = 0, counterT = 0;
  /// Potion buffs (an Apothecary brew drunk in the Wilds): id -> seconds left. See [buffDefs].
  final buffs = <String, double>{};
  bool has(String b) => (buffs[b] ?? 0) > 0;

  /// Drink a brew: its buff starts (or refreshes) at full length.
  void applyBuff(String id, {double? secs}) {
    final d = buffDefs[id];
    if (d == null) return;
    if (coatings.contains(id)) buffs.removeWhere((k, _) => k != id && coatings.contains(k));
    buffs[id] = math.max(buffs[id] ?? 0, secs ?? d.secs);
    bursts.add(Burst('buff', pet.x, pet.z, 0.8, size: 2));
    _float(d.name, pet.x, pet.z, 'info', ttl: 1.1);
    _emit('buff', text: id);
  }
  bool party = false;

  // your Evochi
  double stamina = _stamMax, _stamWait = 0;
  PetAct act = PetAct.none;
  double actT = 0;
  bool _landed = false;
  double idleT = 0, _nextFlourish = 7, _flourishT = -1, _glanceUntil = 0, _nextGlance = 3, cheerT = 0;
  int _flourishKind = 0, _flourishN = 0;
  int _stepK = 0;
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
  // the guardian's charge leaves its mark: afterimages and torn moss behind it, and a pillar it runs
  // into cracks (two crashes bring a pillar down, three a boulder: the arena changes as you fight)
  final bossTrail = <(double, double, double)>[]; // x, z, time
  final damage = <int, int>{}; // ground block -> crashes taken
  final broken = <int>{};
  double _hoofT = 0, _trailT = 0;
  int _staticN = 0; // hits toward the next Static spark
  double _sapCd = 0;
  bool _chaining = false;

  /// The Pulse reaches further as your Evochi grows.
  double get pulseR => _pulseR0 * (stage >= 3 ? 1.4 : (stage >= 2 ? 1.25 : 1.0));

  /// The coating on your Evochi's attacks right now, if any.
  String? get coating => buffs.keys.where(coatings.contains).firstOrNull;
  bool _closeCall = false;

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
    final elite = id.startsWith('elite');
    final f = Foe(
        id: id,
        kind: kind,
        x: x,
        z: z,
        radius: (kind == 'sporecap' ? 8 : 8) * (elite ? 1.3 : 1),
        health: (kind == 'sporecap' ? 46 : 58) * foeHp * (elite ? 2.8 : 1),
        zone: zone);
    f.elite = elite;
    if (elite) f.size = 1.4;
    f
      ..cycle = kind == 'sporecap' ? 10 : 7.2
      ..poise = (kind == 'sporecap' ? 20 : 30) * (elite ? 1.8 : 1)
      ..maxPoise = (kind == 'sporecap' ? 20 : 30) * (elite ? 1.8 : 1)
      ..cd = 0.6 + rng.nextDouble()
      ..strafe = rng.nextBool() ? 1 : -1;
    f.face(rng.nextDouble() - 0.5, 1);
    return f;
  }

  void _rebuildBlocks() {
    final b = bossDef;
    _blocks = [
      for (var i = 0; i < ground.blocks.length; i++)
        if (!broken.contains(i)) ground.blocks[i],
      if (wallUp && b != null) for (final (x, z) in b.wall) (x, z, 10.0),
    ];
  }

  /// For the arena's pillars and boulders: -1 if the guardian has brought it down, else the crashes it has
  /// taken (0 if none, or nothing breakable stands there).
  int crackAt(double x, double z) {
    if (damage.isEmpty && broken.isEmpty) return 0;
    var best = 12.0, at = -1;
    for (var i = 0; i < ground.blocks.length; i++) {
      final (bx, bz, _) = ground.blocks[i];
      final d = _len(bx - x, bz - z);
      if (d < best) {
        best = d;
        at = i;
      }
    }
    if (at < 0) return 0;
    if (broken.contains(at)) return -1;
    return damage[at] ?? 0;
  }

  /// The block the guardian just ran into: crack it, and bring it down after enough crashes.
  void _crashInto(Boss b) {
    final hx = b.x + b.ax * b.radius, hz = b.z + b.az * b.radius;
    var best = double.infinity, at = -1;
    for (var i = 0; i < ground.blocks.length; i++) {
      if (broken.contains(i)) continue;
      final (bx, bz, br) = ground.blocks[i];
      final d = _len(bx - hx, bz - hz) - br;
      if (d < best && _len(bx - b.ax0, bz - b.az0) < b.ar - 6) {
        best = d;
        at = i;
      }
    }
    if (at < 0 || best > 10) return;
    final (bx, bz, br) = ground.blocks[at];
    final n = (damage[at] ?? 0) + 1;
    damage[at] = n;
    bursts.add(Burst('debris', bx, bz, 0.9, dx: -b.ax, dz: -b.az, size: br > 10 ? 1.6 : 1.1));
    if (n >= (br > 10 ? 3 : 2)) {
      broken.add(at);
      _rebuildBlocks();
      bursts.add(Burst('rubble', bx, bz, 1.2, size: br > 10 ? 1.8 : 1.3));
      shake = math.max(shake, 1.1);
      _emit('pillar_break', x: bx, z: bz);
      say(br > 10 ? 'The boulder\'s gone! Find other cover!' : 'It smashed the pillar! Use another one!', gap: 2);
    } else {
      _emit('pillar_crack', x: bx, z: bz);
    }
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
    if (ultHold > 0) {
      // the cut-in has the screen; if it never hands back (no art after all), the ultimate resolves anyway
      ultHold += dt;
      if (ultHold > 3.0) ultRelease();
      return;
    }
    for (final f in floaters) {
      f.t += dt;
    }
    floaters.removeWhere((f) => f.t >= f.ttl);
    for (final b in bursts) {
      b.t += dt;
    }
    bursts.removeWhere((b) => b.t >= b.ttl);
    shake = math.max(0, shake - dt * 3);
    flashT = math.max(0, flashT - dt);
    for (final o in ores) {
      if (o.broken && time - o.brokeAt > 45) {
        o.damage = 0;
        o.state = 0;
        o.brokeAt = -9;
      }
    }
    wallRise = (wallRise + (wallUp ? dt * 2.2 : -dt * 1.2)).clamp(0.0, 1.0);
    if (phase != RaidPhase.explore) return;
    if (hitstop > 0) {
      hitstop -= dt;
      return;
    }
    if (_sigWind > 0) {
      // a signature move's wind-up runs in real time (the world is slowed round it)
      _sigWind -= dt;
      if (_sigWind <= 0) _signatureFire();
    }
    _tickMist(dt);
    if (slowmo > 0) {
      slowmo -= dt;
      dt *= 0.35;
    }
    counterT = math.max(0, counterT - dt);
    if (buffs.isNotEmpty) {
      buffs.updateAll((k, v) => v - dt);
      buffs.removeWhere((k, v) => v <= 0);
      if (has('regen') && pet.alive) pet.hp = math.min(pet.maxHp, pet.hp + 3 * dt);
    }
    _tickBurns(dt);
    _sapCd -= dt;
    _tickReef(dt);
    _charmSapCd -= dt;
    time += dt;
    _sayCd -= dt;
    _tickPet(dt, inp);
    final s = sher;
    if (s != null) _tickSher(s, dt);
    for (final f in friends) {
      _tickFriend(f, dt);
    }
    for (final f in foes.toList()) {
      _cool(f, dt);
      _tickFoe(f, f.chillT > 0 ? dt * 0.62 : dt);
    }
    final b = boss;
    if (b != null) {
      _cool(b, dt);
      _tickBoss(b, b.chillT > 0 ? dt * 0.8 : dt);
    }
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
      a.pop = math.max(0, a.pop - dt * 6);
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
      stamina = math.min(_stamMax, stamina + _stamRegen * (p.slowT > 0 ? 0.5 : 1) * (has('swift') ? 1.6 : 1) * dt);
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
    p.tilt = 0;
    p.ghost = false;
    p.glow = math.max(0, p.glow - dt * 2);
    actT += dt;
    // start what was pressed, if it can be
    final want = _buffer;
    if (want != null && p.stun <= 0) {
      final canCancel = act == PetAct.none || act == PetAct.heal || (act == PetAct.swing && actT > 0.16) || (act == PetAct.bolt && actT > 0.14);
      if (want == 'dodge' && act != PetAct.dodge && act != PetAct.hurt && (canCancel || act == PetAct.pulse && actT > 0.3)) {
        final cost = _dodgeCost * (has('swift') ? 0.7 : 1);
        if (_afford(cost)) {
          _spend(cost);
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
      } else if (want == 'signature' && canCancel) {
        if (sigReady) {
          sig = 0;
          _signature();
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
        final lean = math.sin(p.dir * math.pi / 4);
        // a crouch that coils back, the lunge (the pounce hops) with the body stretched through it and an
        // afterimage behind, then a landing squash that springs out
        if (actT < 0.07) {
          final k = actT / 0.07;
          p.sy = 1 - 0.14 * k;
          p.sx = 1 + 0.08 * k;
          p.tilt = -lean * 0.12 * k;
        } else if (actT < 0.2) {
          // a Juvenile's third Pounce is a Leap: further and higher, and it lands with a shockwave
          final leap = c == 2 && stage >= 2;
          final lunge = _swingLunge[c] * (leap ? 1.35 : 1) / 0.13 * _lungeK;
          _move(p, p.fx, p.fz, lunge * (p.slowT > 0 ? 0.7 : 1), dt, faceIt: false);
          final big = c == 2 ? 1.6 : 1.0;
          p.sy = 1 + 0.12 * big;
          p.sx = 1 - 0.08 * big;
          p.tilt = lean * 0.2 * big;
          if (c == 2) p.lift = math.sin((actT - 0.07) / 0.13 * math.pi) * (leap ? 18 : 9);
          if (actT - dt < 0.07) {
            // the swipe itself: an arc of light (bigger as it grows, tinted by its coating)
            bursts.add(Burst('swipe', p.x + p.fx * 10, p.z + p.fz * 10, 0.22,
                dx: p.fx, dz: p.fz, size: (0.8 + 0.25 * (stage - 1)) * (c == 2 ? 1.3 : 1), tag: coating ?? ''));
          }
          if (trail.isEmpty || time - trail.last.$3 > 0.03) trail.add((p.x, p.z, time));
          _swingHits(c);
          _landed = false;
        } else {
          final k = ((actT - 0.2) / 0.16).clamp(0.0, 1.0);
          final land = (1 - k) * (1 - k);
          final big = c == 2 ? 1.7 : 1.0;
          p.sy = 1 - 0.1 * big * land;
          p.sx = 1 + 0.09 * big * land;
          p.tilt = -lean * 0.06 * land * big;
          if (!_landed && _lungeK > 0.5) {
            _landed = true;
            bursts.add(Burst('dust', p.x - p.fx * 2, p.z - p.fz * 2, 0.4, size: c == 2 ? 1.4 : 0.8));
            if (c == 2 && stage >= 2) _leapLand(p);
          }
        }
        if (actT > 0.2 + _swingRecover[c]) {
          act = PetAct.none;
          comboUntil = time + 0.45;
        }
        mx = mz = 0;
      case PetAct.bolt:
        {
          // lean in, then a small kick back as it fires
          final lean = math.sin(p.dir * math.pi / 4);
          p.sy = actT < 0.1 ? 0.92 : 1.04;
          p.sx = actT < 0.1 ? 1.04 : 0.96;
          p.tilt = actT < 0.1 ? lean * 0.08 : -lean * 0.1 * (1 - ((actT - 0.1) / 0.14).clamp(0.0, 1.0));
        }
        p.glow = 1;
        if (actT >= 0.1 && actT - dt < 0.1) {
          final t = _softTarget(170, p.fx, p.fz);
          final sh = Shot(ShotKind.bolt, Team.party, p.x + p.fx * 10, p.z + p.fz * 10, vx: p.fx * 165, vz: p.fz * 165, life: 1.2, owner: p, target: t)
            ..pierce = stage >= 3 ? 2 : (stage >= 2 ? 1 : 0);
          shots.add(sh);
          if (charm == 'prism_charm') {
            // the Prism Charm: two lesser bolts fan out either side
            for (final turn in const [-0.26, 0.26]) {
              final c = math.cos(turn), sn = math.sin(turn);
              final dx = p.fx * c - p.fz * sn, dz = p.fx * sn + p.fz * c;
              shots.add(Shot(ShotKind.bolt, Team.party, p.x + dx * 10, p.z + dz * 10, vx: dx * 165, vz: dz * 165, life: 1.0, owner: p)
                ..power = const [0.4, 0.55, 0.7][_ci]
                ..prism = true);
            }
          }
          _emit('bolt');
        }
        if (actT > 0.24) act = PetAct.none;
        mx = mz = 0;
      case PetAct.pulse:
        p.glow = math.min(1, actT / 0.28);
        if (actT < 0.28) {
          p.sy = 1 - 0.1 * math.min(1, actT / 0.28);
          p.sx = 1 + 0.06 * math.min(1, actT / 0.28);
        } else {
          // released: it springs up and comes down in a wave
          final k = ((actT - 0.28) / 0.28).clamp(0.0, 1.0);
          p.lift = math.sin(k * math.pi) * 6;
          p.sy = 1 + 0.12 * math.sin(k * math.pi);
          p.sx = 1 - 0.06 * math.sin(k * math.pi);
        }
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
    _petLife(p, dt);
    // crumbs for Sher
    if (crumbs.isEmpty || _len(p.x - crumbs.last.$1, p.z - crumbs.last.$2) > 3) {
      crumbs.add((p.x, p.z));
      if (crumbs.length > 80) crumbs.removeAt(0);
    }
  }


  /// The body when nothing is being asked of it: it breathes and shifts its weight, glances at what is
  /// near, stands ready when something hostile is close, droops a little when hurt badly, and now and
  /// then stretches, shakes itself or hops. Footfalls kick up dust. All of it is drawn only: it never
  /// moves the Evochi or changes a hit.
  void _petLife(Actor p, double dt) {
    // footfalls: a puff of dust on each step while running
    if (p.moving && p.running && act == PetAct.none) {
      final k = (p.phase * 2).floor();
      if (k != _stepK) {
        _stepK = k;
        bursts.add(Burst('dust', p.x - p.fx * 3, p.z - p.fz * 3, 0.32, size: 0.5));
      }
    }
    final free = act == PetAct.none && !p.moving && p.stun <= 0 && !p.ghost;
    if (!free) {
      idleT = 0;
      _flourishT = -1;
      _nextFlourish = 7;
      return;
    }
    idleT += dt;
    final t = time;
    final lean = math.sin(p.dir * math.pi / 4);
    final low = p.hpFrac < 0.3;
    Actor? near;
    var nd = 150.0;
    for (final f in hostile) {
      if (f.calm || f.st == FoeState.dormant) continue;
      final d = p.dist(f);
      if (d < nd) {
        nd = d;
        near = f;
      }
    }
    // breathing: slower and shallower when hurt
    final br = math.sin(t * (low ? 1.5 : 2.3));
    p.sy *= 1 + (low ? 0.012 : 0.02) * br;
    p.sx *= 1 - (low ? 0.006 : 0.01) * br;
    if (near != null && nd < 110) {
      // ready: low and springy, facing it
      p.face(near.x - p.x, near.z - p.z);
      p.sy *= 0.955 + 0.012 * math.sin(t * 7);
      p.sx *= 1.03;
      p.tilt += lean * 0.05;
      return;
    }
    if (cheerT > 0) {
      cheerT -= dt;
      final k = (t * 2.2) % 1.0;
      p.lift = math.sin(k * math.pi) * 5;
      p.sy *= 1 + 0.07 * math.sin(k * math.pi);
      p.sx *= 1 - 0.04 * math.sin(k * math.pi);
      return;
    }
    // a slow shift of weight from side to side
    p.tilt += 0.03 * math.sin(t * 0.8) * (low ? 0.4 : 1);
    if (low) {
      p.sy *= 0.97;
      return;
    }
    // a glance at whatever is near: a foe, or a friend, then back
    if (t >= _glanceUntil && t >= _nextGlance && idleT > 2.2) {
      final tgt = near ?? (sher != null && p.dist(sher!) < 160 ? sher : null);
      if (tgt != null) {
        _glanceUntil = t + 1.1;
        _nextGlance = t + 3.5 + (_flourishN % 3) * 1.3;
        p.face(tgt.x - p.x, tgt.z - p.z);
      } else {
        _nextGlance = t + 2.5;
      }
    }
    // now and then a flourish
    if (_flourishT < 0 && idleT > _nextFlourish) {
      _flourishT = 0;
      _flourishKind = _flourishN++ % 3;
    }
    if (_flourishT >= 0) {
      _flourishT += dt;
      final len = _flourishKind == 1 ? 0.9 : 0.8;
      final k = (_flourishT / len).clamp(0.0, 1.0);
      final w = math.sin(k * math.pi);
      switch (_flourishKind) {
        case 0: // a stretch
          p.sy *= 1 + 0.11 * w;
          p.sx *= 1 - 0.07 * w;
        case 1: // a shake-off
          p.tilt += math.sin(k * 34) * 0.1 * (1 - k);
          p.sx *= 1 + 0.03 * w;
        default: // a hop
          p.lift = math.sin(k * math.pi) * 7;
          p.sy *= 1 + 0.08 * math.sin(k * math.pi) - 0.1 * (k < 0.15 ? 1 - k / 0.15 : 0);
      }
      if (_flourishT >= len) {
        _flourishT = -1;
        _nextFlourish = idleT + 8 + (_flourishN % 4) * 2.0;
      }
    }
  }

  double get _swingRecoverEnd => 0.2 + _swingRecover[combo];

  void _swingHits(int c) {
    final p = pet;
    final hx = p.x + p.fx * 9, hz = p.z + p.fz * 9;
    _swingOre(c, hx, hz);
    for (final f in hostile.toList()) {
      if (_hitThisSwing.contains(f)) continue;
      if (_len(f.x - hx, f.z - hz) > f.radius + 12) continue;
      _hitThisSwing.add(f);
      final d = math.max(_len(f.x - p.x, f.z - p.z), 1e-6);
      // a counter after a perfect dodge lands harder and breaks poise
      final counter = counterT > 0;
      final k = counter ? 1.6 : 1.0;
      _hurt(f, _swingDmg[c] * atk * k, from: p, kx: (f.x - p.x) / d * _swingKnock[c] * k, kz: (f.z - p.z) / d * _swingKnock[c] * k, poise: _swingPoise[c] * (counter ? 2 : 1));
      if (counter) {
        counterT = 0;
        hitstop = math.max(hitstop, 0.08);
        shake = math.max(shake, 0.5);
        _float('Counter!', f.x, f.z - 8, 'crit', ttl: 0.9);
        bursts.add(Burst('slash', f.x, f.z, 0.35, size: 2));
        _emit('counter', x: f.x, z: f.z);
        _sigGain(20);
      }
      // every hit lands with a beat of hit-stop, a shake and an impact flash that grow through the three
      hitstop = math.max(hitstop, const [0.03, 0.045, 0.09][c]);
      shake = math.max(shake, const [0.16, 0.26, 0.6][c]);
      bursts.add(Burst('impact', f.x, f.z, 0.3, dx: (f.x - p.x) / d, dz: (f.z - p.z) / d, size: const [0.8, 1.0, 1.5][c]));
      if (c == 2) {
        // the third Pounce launches small foes: a longer beat, a flash, a burst, a moment stunned
        flashT = math.max(flashT, 0.1);
        flashKind = 'white';
        bursts.add(Burst('launch', f.x, f.z, 0.4, size: f is Boss ? 2 : 1.4));
        if (f is! Boss && !f.calm) f.stun = math.max(f.stun, 0.35);
        _emit('launch', x: f.x, z: f.z);
        _sigGain(5);
      }
    }
  }

  /// A Pounce at an ore node (the mines): a strike on the nearest one in reach, once a swing.
  void _swingOre(int c, double hx, double hz) {
    final p = pet;
    OreRock? best;
    var bd = 1e9;
    for (final o in ores) {
      if (o.broken) continue;
      final d = _len(o.x - hx, o.z - hz);
      if (d < o.radius + 13 && d < bd) {
        best = o;
        bd = d;
      }
    }
    final o = best;
    if (o == null) return;
    final d = math.max(_len(o.x - p.x, o.z - p.z), 1e-6);
    final dx = (o.x - p.x) / d, dz = (o.z - p.z) / d;
    o.hitAt = time;
    o.hitDir = p.x <= o.x ? 1 : -1;
    if (o.tier > oreTier) {
      // too hard for your gear: a clink and a bounce, nothing lost
      o.noteAt = time;
      p.kx -= dx * 60;
      p.kz -= dz * 60;
      p.tilt = 0.2 * (dx.abs() > 0.2 ? dx.sign : 1);
      hitstop = math.max(hitstop, 0.03);
      bursts.add(Burst('impact', o.x, o.z, 0.2, dx: dx, dz: dz, size: 0.5));
      _emit('ore_hard', text: o.kind, x: o.x, z: o.z);
      return;
    }
    final first = o.damage == 0;
    final broke = o.strike(miningPower);
    hitstop = math.max(hitstop, broke ? 0.09 : 0.04);
    shake = math.max(shake, broke ? 0.5 : 0.2);
    bursts.add(Burst('impact', o.x, o.z, 0.28, dx: dx, dz: dz, size: broke ? 1.4 : 0.9));
    if (broke) {
      o.brokeAt = time;
      flashT = math.max(flashT, 0.07);
      flashKind = 'white';
      _emit('ore_break', text: o.kind, value: ores.indexOf(o).toDouble(), x: o.x, z: o.z);
    } else {
      _emit(first ? 'ore_chip' : 'ore_crack', text: o.kind, x: o.x, z: o.z);
    }
  }

  /// The Leap lands: a shockwave knocks back and stuns what is near (the guardian only loses poise).
  void _leapLand(Actor p) {
    final r = stage >= 3 ? 42.0 : 30.0;
    bursts.add(Burst('quake', p.x, p.z, 0.5, size: r));
    shake = math.max(shake, 0.45);
    hitstop = math.max(hitstop, 0.05);
    _emit('leap', x: p.x, z: p.z);
    for (final f in hostile.toList()) {
      final d = p.dist(f);
      if (d > r + f.radius) continue;
      final k = d > 1e-6 ? 1 / d : 0.0;
      _hurt(f, 6 * atk, from: p, kx: (f.x - p.x) * k * 110, kz: (f.z - p.z) * k * 110, poise: 16);
      if (f is! Boss && !f.calm) f.stun = math.max(f.stun, 0.6);
    }
  }

  /// Each colour's signature move (Elders only): the name it is called by.
  static const sigNames = {
    'ocean': 'Healing Mist',
    'amber': 'Sunflare',
    'amethyst': 'Crystal Shards',
    'forest': 'Thorn Snare',
    'coral': 'Reef Bloom',
    'obsidian': 'Quake',
  };

  String get sigName => sigNames[palette] ?? 'Sunflare';

  void _signature() {
    final p = pet;
    if (cinematic) {
      ultHold = 1e-6;
      p.glow = 1;
      p.iframes = math.max(p.iframes, 1.0);
      bursts.add(Burst('gather', p.x, p.z, 0.3, size: 1.6, tag: palette));
      _emit('ult_begin', text: palette, x: p.x, z: p.z);
      return;
    }
    // the wind-up: the world slows, light gathers into your Evochi, nothing can touch it
    _sigWind = 0.3;
    slowmo = math.max(slowmo, 0.42);
    p.glow = 1;
    p.iframes = math.max(p.iframes, 0.9);
    bursts.add(Burst('gather', p.x, p.z, 0.3, size: 1.6, tag: palette));
    _emit('signature_wind', text: palette, x: p.x, z: p.z);
  }

  /// The cut-in's release marker: back in the Wilds, the ultimate resolves now (once; a second call does nothing).
  void ultRelease() {
    if (ultHold <= 0) return;
    ultHold = 0;
    _signatureFire();
  }

  void _signatureFire() {
    final p = pet;
    hitstop = math.max(hitstop, 0.14);
    shake = math.max(shake, 1.0);
    flashT = math.max(flashT, 0.22);
    flashKind = palette;
    p.glow = 1;
    bursts.add(Burst('lines', p.x, p.z, 0.55, size: 190, tag: palette));
    bursts.add(Burst('impact', p.x, p.z, 0.4, size: 2.4, tag: palette));
    // its name over it, unless its cut-in has just shown it (one less line of text over the fight)
    if (!cinematic) _float(sigName, p.x, p.z - 10, 'crit', ttl: 1.3);
    _emit('signature', text: palette, x: p.x, z: p.z);
    switch (palette) {
      case 'ocean':
        // Healing Mist: a wave of mist rolls out ahead and washes the Hollow out of whatever it reaches (the
        // Tidal Surge's own reach, damage, push and stun, each landing as the leading edge arrives); it mends
        // you, and whoever is with you, and lingers a while, mending still and slowing what wades into it
        flashT = math.max(flashT, 0.34);
        bursts.add(Burst('mistburst', p.x, p.z, 0.6, size: 1));
        bursts.add(Burst('mistwave', p.x, p.z, 1.1, dx: p.fx, dz: p.fz, size: 150));
        bursts.add(Burst('mistlinger', p.x, p.z, 5, dx: p.fx, dz: p.fz, size: 150));
        _mistHits.clear();
        _mistT = 0;
        for (final f in hostile.toList()) {
          final ax = f.x - p.x, az = f.z - p.z;
          final along = ax * p.fx + az * p.fz, across = (ax * p.fz - az * p.fx).abs();
          if (along < -8 || along > 150 || across > 30 + f.radius) continue;
          _mistHits.add((f, math.max(0.0, along) / mistSpeed, p.fx, p.fz));
        }
        for (final a in [p, if (sher != null && party) sher!]) {
          final heal = math.min(a.maxHp - a.hp, a.maxHp * 0.35);
          a.hp += heal;
          if (heal >= 1) _float('+${heal.round()}', a.x, a.z, 'heal');
        }
        _reefT = 5;
        _reefX = p.x;
        _reefZ = p.z;
      case 'amethyst':
        // a ring of crystal shards that go through whatever they meet
        bursts.add(Burst('crystal', p.x, p.z, 0.5, size: 40));
        for (var i = 0; i < 12; i++) {
          final a = i * math.pi * 2 / 12;
          shots.add(Shot(ShotKind.bolt, Team.party, p.x + math.cos(a) * 8, p.z + math.sin(a) * 8, vx: math.cos(a) * 190, vz: math.sin(a) * 190, life: 0.9, owner: p)
            ..power = 1.4
            ..pierce = 3
            ..shard = true);
        }
      case 'forest':
        // thorns burst up all round and hold everything near fast
        bursts.add(Burst('snare', p.x, p.z, 2.6, size: 72));
        for (final f in hostile.toList()) {
          if (p.dist(f) > 72 + f.radius) continue;
          _hurt(f, 14 * atk, from: p, poise: 40);
          if (f is Boss) {
            _chill(f, 3.0);
          } else {
            f.stun = math.max(f.stun, 2.4);
            f.burnT = math.max(f.burnT, 2.0);
          }
        }
      case 'coral':
        // a reef blooms underfoot: it heals you (and anyone with you) and slows what wades in
        _reefT = 6;
        _reefX = p.x;
        _reefZ = p.z;
        bursts.add(Burst('reef', p.x, p.z, 6, size: 56));
        p.hp = math.min(p.maxHp, p.hp + 20);
        _float('+20', p.x, p.z, 'heal');
      case 'obsidian':
        // the ground itself heaves: the widest stun there is
        bursts.add(Burst('quake', p.x, p.z, 0.7, size: 95));
        bursts.add(Burst('rubble', p.x, p.z, 1.0, size: 1.6));
        shake = math.max(shake, 1.2);
        for (final f in hostile.toList()) {
          final d = p.dist(f);
          if (d > 95 + f.radius) continue;
          final k = d > 1e-6 ? 1 / d : 0.0;
          _hurt(f, 26 * atk, from: p, kx: (f.x - p.x) * k * 160, kz: (f.z - p.z) * k * 160, poise: 90, stun: f is Boss ? 0 : 1.3);
        }
      default:
        // amber: a flash of sunlight that dazzles everything that can see it
        bursts.add(Burst('sunflare', p.x, p.z, 0.8, size: 170));
        for (final f in hostile.toList()) {
          if (p.dist(f) > 170) continue;
          _hurt(f, 12 * atk, from: p, poise: 30);
          if (f is Boss) {
            _dazzle(f, 60);
          } else {
            f.stun = math.max(f.stun, 1.8);
          }
        }
    }
  }

  /// Healing Mist's wave reaching each creature in turn: the hit as the Tidal Surge's, the corruption stripped off,
  /// and where that clears the last of the Hollow, its purification
  void _tickMist(double dt) {
    if (_mistHits.isEmpty) return;
    _mistT += dt;
    final p = pet;
    for (final h in _mistHits.toList()) {
      final (f, at, fx, fz) = h;
      if (_mistT < at) continue;
      _mistHits.remove(h);
      if (!f.alive || f.calm) continue;
      bursts.add(Burst('strip', f.x, f.z, 0.7, dx: fx, dz: fz, size: f is Boss ? 2.2 : 1.0));
      _hurt(f, 30 * atk, from: p, kx: fx * 280, kz: fz * 280, poise: 70, stun: f is Boss ? 0 : 0.8, cause: 'mist');
      if (f.calm) bursts.add(Burst('cleanse', f.x, f.z, 1.2, size: f is Boss ? 2.2 : 1.0));
    }
  }

  void _tickReef(double dt) {
    if (_reefT <= 0) return;
    _reefT -= dt;
    for (final a in [pet, if (sher != null && party) sher!]) {
      if (_len(a.x - _reefX, a.z - _reefZ) < 56) a.hp = math.min(a.maxHp, a.hp + 9 * dt);
    }
    for (final f in hostile) {
      if (_len(f.x - _reefX, f.z - _reefZ) < 56 + f.radius) f.chillT = math.max(f.chillT, 0.3);
    }
  }

  void _pulse() {
    final p = pet;
    bursts.add(Burst('pulse', p.x, p.z, 0.45, size: pulseR));
    bursts.add(Burst('lines', p.x, p.z, 0.4, size: pulseR * 1.2, tag: 'mint'));
    _emit('pulse');
    shake = math.max(shake, 0.4);
    hitstop = math.max(hitstop, 0.05);
    flashT = math.max(flashT, 0.07);
    flashKind = 'mint';
    p.slowT = 0;
    hazards.removeWhere((h) => _len(h.x - p.x, h.z - p.z) < pulseR + h.r * 0.5);
    for (final f in hostile.toList()) {
      final d = p.dist(f);
      if (d > pulseR + f.radius) continue;
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
    // deeper floors' creatures hit harder; an elite harder still
    if (from is Foe && a.team == Team.party) dmg *= foeHarm * (from.elite ? 1.35 : 1);
    if (a is Foe && (a.st == FoeState.roar || a.st == FoeState.dormant)) {
      _float('Shrugged off', a.x, a.z, 'info', ttl: 0.6);
      return false;
    }
    if (a is Foe && a.kind == 'sentinel' && sentinelShield > 0) {
      // the Hollow shield: only Lumen gets through (a Lantern Tonic's light on your Evochi)
      bursts.add(Burst('spark', a.x, a.z - 6, 0.3, tag: 'hollow'));
      if (from == pet && has('lantern')) {
        sentinelShield -= dmg;
        _float('Lumen!', a.x, a.z, 'crit', ttl: 0.6);
        _emit('shield_hit', x: a.x, z: a.z);
        if (sentinelShield <= 0) _shieldBreak(a);
        return true;
      }
      _float('Shielded', a.x, a.z, 'info', ttl: 0.6);
      _emit('shielded', x: a.x, z: a.z);
      return false;
    }
    if (a.iframes > 0 || a.mercy > 0) {
      if (a == pet && act == PetAct.dodge && !_dodgeRewarded) {
        _dodgeRewarded = true;
        stamina = math.min(_stamMax, stamina + 12);
        // dodged right as it landed: the world slows and a counter is ready
        if (time - _dodgeAt < 0.2) {
          slowmo = 0.45;
          counterT = 1.4;
          _float('Perfect dodge!', a.x, a.z, 'crit', ttl: 0.9);
          _emit('perfect_dodge');
          _sigGain(34);
        } else {
          _float('Dodged!', a.x, a.z, 'info', ttl: 0.7);
          _emit('dodged');
        }
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
    if (a == pet && from is Foe) {
      if (has('lantern')) dmg *= 0.65; // the Lantern Tonic steadies you against the Hollow
      if (has('thornskin') && from.alive && !from.calm) {
        // Thornskin: a share of the blow goes back into whoever struck
        _hurt(from, dmg * 0.4, from: pet, poise: 4);
        bursts.add(Burst('spark', from.x, from.z, 0.3));
      }
    }
    var crit = false;
    if (a is Foe && from == pet) {
      if (has('moonlit') && rng.nextDouble() < 0.25) crit = true;
      if (has('ember')) a.burnT = 3.0;
      if (has('frost')) _chill(a, 3.0);
      if (has('hush')) poise *= 1.6;
      if (has('sap') && _sapCd <= 0 && pet.hp < pet.maxHp) {
        _sapCd = 0.2;
        _sapHeal(a, 2.5);
      }
      if (has('dazzle')) _dazzle(a, a is Boss ? 11 : 24);
      if (has('static') && !_chaining && ++_staticN >= 4) {
        _staticN = 0;
        _spark(a, dmg * 0.5);
      }
      // the charm it wears
      switch (charm) {
        case 'emberfang_charm' when !_chaining:
          if (rng.nextDouble() < const [0.25, 0.35, 0.45][_ci]) {
            if (a.burnT <= 0) bursts.add(Burst('ember', a.x, a.z, 0.5));
            a.burnT = math.max(a.burnT, 2.0);
          }
        case 'frostbell_charm' when !_chaining:
          if (rng.nextDouble() < const [0.25, 0.35, 0.45][_ci]) _chill(a, 2.0);
        case 'static_acorn' when !_chaining:
          if (++_charmN >= const [6, 5, 4][_ci]) {
            _charmN = 0;
            _spark(a, dmg * 0.45);
          }
        case 'sap_locket' when !_chaining:
          if (_charmSapCd <= 0 && pet.hp < pet.maxHp) {
            _charmSapCd = 0.25;
            _sapHeal(a, const [1.0, 1.5, 2.0][_ci]);
          }
        case 'dazzle_pebble' when !_chaining:
          _dazzle(a, (a is Boss ? 0.5 : 1.0) * const [10.0, 14.0, 18.0][_ci]);
      }
    }
    if (a is Foe) {
      // from behind, or while it is dazed: it hurts more
      if (from != null) {
        final d = math.max(a.dist(from), 1e-6);
        final behind = ((a.x - from.x) * a.fx + (a.z - from.z) * a.fz) / d;
        if (behind > 0.45 && a is Boss) crit = true;
      }
      if (a.st == FoeState.stagger) crit = true;
      if (crit) {
        dmg *= 1.4;
        hitstop = math.max(hitstop, 0.04);
      }
      dmg *= 0.92 + rng.nextDouble() * 0.16;
    }
    final n = math.max(1, dmg.round());
    a.hp -= n;
    a.flash = 0.14;
    a.pop = 1;
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
    _float('$n', f.x, f.z, crit ? 'crit' : (cause == 'mist' ? 'mist' : 'dmg'));
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
    } else if (f is! Boss && f.kind != 'sentinel' && (f.st == FoeState.engage || f.st == FoeState.idle) && poise >= 8) {
      f.pose = 'hurt';
      f.t = 0;
      f.stun = 0.22;
    }
    if (f.hp <= 0) {
      f.hp = 0;
      _calm(f);
    } else if (f is Boss) {
      _bossHealthCheck(f);
    } else if (f.kind == 'sentinel') {
      _sentinelHealthCheck(f);
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
    for (final m in f.extra) {
      m.done = true;
    }
    f.extra.clear();
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
    if (f.kind == 'sentinel') {
      _tickSentinel(f, dt);
      return;
    }
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
          if (_sees(f, a, f.kind == 'hollow_sprout' ? 125 : (f.kind == 'sporecap' ? 100 : 78))) {
            if (f.kind == 'hollow_sprout') {
              if (holdSprout) break;
              // the first time it sees you: its entrance (the screen holds the fight while it plays)
              if (!sproutWoke) _emit('sprout_wake', x: f.x, z: f.z);
              sproutWoke = true;
            }
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
        } else if (f.kind == 'hollow_sprout') {
          _sproutAttack(f, dt);
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
    // and the Mossy Ruins' old Lumen keeps the Hollow out while Petalune is learning to trust you
    final haven = storyBeat == 'trust' && !storyDone && t.distTo(storyX, storyZ) < havenR;
    if (f.distTo(f.homeX, f.homeZ) > 190 || (t.dist(f) > 240) || walled || haven) {
      _goHome(f);
      return;
    }
    final d = f.dist(t);
    if (f.kind == 'thornling') {
      _thornEngage(f, t, d, dt);
    } else if (f.kind == 'hollow_sprout') {
      _sproutEngage(f, t, d, dt);
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
    if (f.kind == 'sentinel') {
      _sentinelMarks(f, move, windup, t);
      if (f.mark != null) marks.add(f.mark!);
      return;
    }
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
      case 'burst':
        f.mark = Mark(MarkShape.circle, f.x, f.z, windup, r: 46, owner: f);
      case 'lash':
        f.mark = Mark(MarkShape.line, f.x, f.z, windup, dx: f.ax, dz: f.az, len: 104, width: 20, owner: f);
      case 'thorns':
        // where you stand and where you might step: three patches of ground the thorns come up through
        final a0 = rng.nextDouble() * math.pi * 2;
        final lx = t.x + t.vx * 0.35, lz = t.z + t.vz * 0.35;
        f.mark = Mark(MarkShape.circle, lx, lz, windup, r: 17, owner: f);
        for (final k in const [0, 1]) {
          final a = a0 + k * math.pi;
          f.extra.add(Mark(MarkShape.circle, lx + math.cos(a) * 34, lz + math.sin(a) * 34, windup, r: 17, owner: f));
        }
        marks.addAll(f.extra);
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

  // ================================================================== story floors
  Foe _friend(double x, double z) => Foe(id: 'petalune', kind: 'petalune', x: x, z: z, radius: 7, health: 100, zone: 'ruins')
    ..ghost = true
    ..cycle = 9
    ..st = FoeState.idle
    ..face(0, 1);

  /// The Hollow Sprout: a mini-boss rooted in the ruins (it never strays far from them).
  Foe _sprout(double x, double z) {
    final f = Foe(id: 'sprout', kind: 'hollow_sprout', x: x, z: z, radius: 14, health: 420 * foeHp, zone: 'ruins');
    f
      ..size = 1.7
      ..cycle = 14
      ..poise = 90
      ..maxPoise = 90
      ..cd = 1.2
      ..cd2 = 2.0
      ..face(0, 1);
    return f;
  }

  /// Hum to Petalune (the interact button, near it): warms its trust past where being gentle takes it.
  bool hum() {
    final f = petalune;
    if (f == null || storyDone || storyBeat != 'trust' || _humCd > 0 || pet.dist(f) > 64) return false;
    _humCd = 5;
    _addTrust(trust < trustDrift ? 9 : 12, f);
    f.pose = 'hum';
    _friendPoseT = 1.4;
    pet.face(f.x - pet.x, f.z - pet.z);
    bursts.add(Burst('notes', pet.x, pet.z, 1.6));
    _emit('hum', x: pet.x, z: pet.z);
    return true;
  }

  /// A treat offered to Petalune (the save took it from the Bag): [amount] of trust.
  void treat(int amount) {
    final f = petalune;
    if (f == null || storyDone) return;
    _addTrust(amount.toDouble(), f);
    f.pose = 'happy';
    _friendPoseT = 1.6;
    bursts.add(Burst('hearts', f.x, f.z, 1.4));
    _emit('treat', x: f.x, z: f.z);
  }

  void _addTrust(double n, Foe f) {
    final before = trust;
    trust = (trust + n).clamp(0.0, 100.0);
    if (trust >= 99.5) trust = 100; // what shows as 100% is 100%
    if (n > 0 && trust > before) _float('+${(trust - before).round()} trust', f.x, f.z - 14, 'heal', ttl: 1.0);
    if (trust >= 100 && !storyDone) {
      storyDone = true;
      f
        ..calm = true
        ..pose = 'nuzzle'
        ..t = 0;
      _friendPoseT = 1.8;
      slowmo = 0.6;
      bursts.add(Burst('hearts', f.x, f.z, 2.2, size: 2));
      bursts.add(Burst('motes', f.x, f.z, 1.6, size: 2));
      _emit('story_done', text: 'petalune', x: f.x, z: f.z);
    }
  }

  void _tickFriend(Foe f, double dt) {
    f.t += dt;
    _friendPoseT -= dt;
    if (_friendPoseT <= 0 && f.pose != null && f.pose != 'wary') f.pose = null;
    f.lift = 0;
    if (storyBeat == 'trust' && !storyDone) {
      _tickTrust(f, dt);
    } else {
      _friendFollow(f, dt);
      _tickHush(f, dt);
    }
  }

  /// Wary Petalune: gentle company grows its trust; a fight near it, a charge at it or a swing near it
  /// frightens it back.
  void _tickTrust(Foe f, double dt) {
    _humCd -= dt;
    _startleCd -= dt;
    final p = pet;
    final d = f.dist(p);
    final fightNear = hostile.any((o) => o.fighting && o.distTo(f.x, f.z) < 170);
    final striking = act == PetAct.swing || act == PetAct.bolt || act == PetAct.pulse;
    final struck = striking && _wasAct == 0;
    _wasAct = striking ? 1 : 0;
    if ((struck && d < 90) || (p.running && p.moving && d < 54)) {
      if (_startleCd <= 0) {
        _startleCd = 1.6;
        final before = trust;
        trust = math.max(0, trust - (struck ? 12 : 8));
        f.pose = 'startle';
        _friendPoseT = 0.8;
        if (before > trust) _float('Startled!', f.x, f.z - 14, 'info', ttl: 0.9);
        _emit('startle', x: f.x, z: f.z);
        // it skips back among the stones
        f.wx = f.homeX + (f.x - p.x).sign * 22;
        f.wz = f.homeZ + (f.z - p.z).sign * 14;
      }
    } else if (!fightNear && d < 74 && !p.running && trust < trustDrift) {
      // being near and gentle: the closer and the stiller, the faster
      final still = p.moving ? 0.6 : 1.0;
      trust = math.min(trustDrift, trust + (d < 40 ? 4.2 : 2.6) * still * dt);
    }
    // where it goes: wary, it keeps its distance; warming up, it stays put and watches; trusting, it
    // comes closer
    double tx = f.wx ?? f.homeX, tz = f.wz ?? f.homeZ, sp = 16;
    if (fightNear) {
      tx = f.homeX;
      tz = f.homeZ - 18;
      sp = 26;
    } else if (trust < 30 && d < 46) {
      final k = 1 / math.max(d, 1e-6);
      tx = f.x + (f.x - p.x) * k * 30;
      tz = f.z + (f.z - p.z) * k * 30;
      sp = 18;
    } else if (trust >= 55 && d > 28 && d < 110) {
      final k = 1 / math.max(d, 1e-6);
      tx = p.x + (f.x - p.x) * k * 26;
      tz = p.z + (f.z - p.z) * k * 26;
      sp = 12;
    }
    // never far from the ruins
    final hx = tx - f.homeX, hz = tz - f.homeZ, hd = _len(hx, hz);
    if (hd > 60) {
      tx = f.homeX + hx / hd * 60;
      tz = f.homeZ + hz / hd * 60;
    }
    final dx = tx - f.x, dz = tz - f.z;
    if (_len(dx, dz) > 3) {
      final ph = f.phase;
      _move(f, dx, dz, sp * (math.sin(f.phase * math.pi).abs() * 1.6 + 0.2), dt);
      f.phase = (ph + dt * 1.5) % 1.0;
      f.moving = true;
    } else {
      f.moving = false;
      f.wx = f.wz = null;
    }
    if (d < 140 && (!f.moving || trust >= 30)) f.face(p.x - f.x, p.z - f.z);
    if (_friendPoseT <= 0) f.pose = fightNear || trust < 30 ? 'wary' : (trust >= 55 ? 'happy' : null);
  }

  /// A friend at your heels (a step behind and to the side), hopping to keep up.
  void _friendFollow(Foe f, double dt) {
    final p = pet;
    final d = f.dist(p);
    if (d > 260) {
      // left far behind (a dodge through a doorway): it catches up out of sight
      f
        ..x = p.x - p.fx * 20
        ..z = p.z - p.fz * 20;
      return;
    }
    if (d > 30) {
      final tx = p.x - p.fx * 18 + p.fz * 12, tz = p.z - p.fz * 18 - p.fx * 12;
      final (vx, vz) = _steer(f, tx - f.x, tz - f.z, look: 14);
      final ph = f.phase;
      _move(f, vx, vz, (d > 70 ? _petRun * 1.05 : _petWalk * 1.1) * (math.sin(f.phase * math.pi).abs() * 1.5 + 0.35), dt);
      f.phase = (ph + dt * (d > 70 ? 2.6 : 1.7)) % 1.0;
      f.moving = true;
    } else {
      f.moving = false;
      f.face(p.x - f.x, p.z - f.z);
    }
  }

  /// Petal Hush: while a fight goes on, every so often Petalune hums: your Evochi mends a little and the
  /// creatures close by drift off for a moment.
  void _tickHush(Foe f, double dt) {
    if (!f.calm || !inCombat) return;
    _hushT -= dt;
    if (_hushT > 0) return;
    _hushT = 16;
    f.pose = 'hum';
    _friendPoseT = 1.2;
    final heal = pet.maxHp * 0.08;
    if (pet.alive) pet.hp = math.min(pet.maxHp, pet.hp + heal);
    _float('+${heal.round()}', pet.x, pet.z - 16, 'heal', ttl: 1.0);
    for (final o in hostile) {
      if (o.distTo(pet.x, pet.z) > 80) continue;
      if (o is Boss) {
        _chill(o, 2.0);
      } else {
        o.stun = math.max(o.stun, 1.1);
        o.moving = false;
      }
    }
    bursts.add(Burst('hush', pet.x, pet.z, 1.2, size: 80));
    _emit('hush', x: f.x, z: f.z);
  }

  // ---- the Forgotten Sentinel: asleep against its gate until you come near. Awake, it lumbers after you
  // and slams its fists down (past half its Hollow, one fist and then the other), sweeps a beam from its
  // eyes, and raises runes under you. At two thirds and at a third of its Hollow it kneels behind a
  // Hollow shield and calls creatures out of the dark: calm them, or break the shield with Lumen (a
  // Lantern Tonic's light), and it staggers.
  Foe _sentinel(double x, double z) {
    final f = Foe(id: 'sentinel', kind: 'sentinel', x: x, z: z, radius: 21, health: 720 * foeHp, zone: 'gate');
    f
      ..size = 1.55
      ..cycle = 7
      ..poise = 240
      ..maxPoise = 240
      ..st = FoeState.dormant
      ..pose = 'dormant'
      ..face(0, 1);
    return f;
  }

  static const sentinelWakeR = 118.0;

  /// Recording a Short: it stays asleep, however near your Evochi comes, until this is let go.
  bool holdSentinel = false;

  /// The Hollow Sprout has seen you (its entrance has been asked for); [holdSprout]: the recorder keeps it
  /// from noticing you until it is ready.
  bool sproutWoke = false, holdSprout = false;

  /// Its entrance has played (the cinematic): it is up and fighting at once, the in-fight waking skipped.
  void sentinelAwake() {
    final f = sentinel;
    if (f == null || f.calm || (f.st != FoeState.dormant && f.st != FoeState.roar)) return;
    f
      ..st = FoeState.engage
      ..t = 0
      ..glow = 0
      ..pose = null
      ..cd = 1.0
      ..cd2 = 6
      ..target = pet;
  }

  void _tickSentinel(Foe f, double dt) {
    f.cd -= dt;
    f.cd2 -= dt;
    f.sx = f.sy = 1;
    f.lift = 0;
    if (f.st != FoeState.strike || f.move != 'beam') beam = null;
    switch (f.st) {
      case FoeState.dormant:
        // asleep against the gate: it wakes when your Evochi comes near
        f.moving = false;
        f.pose = 'dormant';
        if (phase == RaidPhase.explore && pet.alive && pet.dist(f) < sentinelWakeR && !holdSentinel) {
          f
            ..st = FoeState.roar
            ..t = 0
            ..target = pet;
          _emit('sentinel_wake', x: f.x, z: f.z);
        }
        return;
      case FoeState.roar:
        // waking: its eyes light, it heaves itself up and lifts its fists
        f.moving = false;
        f.pose = f.t < 1.5 ? 'waking' : 'up';
        f.glow = (f.t / 2.4).clamp(0.0, 1.0);
        if (f.t > 0.4 && f.t < 2.2) shake = math.max(shake, 0.12);
        if (f.t > 1.5 && f.t - dt <= 1.5) {
          shake = math.max(shake, 0.5);
          bursts.add(Burst('quake', f.x, f.z + 10, 0.7, size: 52));
          _emit('sentinel_rise', x: f.x, z: f.z);
        }
        if (f.t >= 2.4) {
          f
            ..st = FoeState.engage
            ..t = 0
            ..glow = 0
            ..pose = null
            ..cd = 0.6
            ..cd2 = 6;
        }
        return;
      default:
        break;
    }
    if (sentinelShield > 0) {
      _sentinelShielded(f, dt);
      return;
    }
    if (f.stun > 0 || f.st == FoeState.stagger) {
      f.moving = false;
      f.pose = 'hurt';
      if (f.stun <= 0) {
        f
          ..st = FoeState.engage
          ..t = 0
          ..pose = null
          ..cd = math.max(f.cd, 0.5);
      }
      return;
    }
    switch (f.st) {
      case FoeState.windup:
      case FoeState.strike:
      case FoeState.recover:
        _sentinelAttack(f, dt);
      default:
        f.st = FoeState.engage;
        _sentinelEngage(f, dt);
    }
  }

  void _sentinelEngage(Foe f, double dt) {
    final t = f.target = pet.alive ? pet : null;
    if (t == null) {
      f.moving = false;
      return;
    }
    final d = f.dist(t);
    final rage = f.hpFrac < 0.5;
    if (f.cd <= 0) {
      final r = rng.nextDouble();
      if (d < 78) {
        _startAttack(f, r < 0.62 ? 'fists' : 'runes', r < 0.62 ? (rage ? 0.78 : 0.95) : 1.15, 0.25, 0.75);
      } else if (d < 215) {
        _startAttack(f, r < 0.55 ? 'beam' : 'runes', r < 0.55 ? 1.0 : 1.15, r < 0.55 ? 1.7 : 0.25, 0.8);
      } else {
        _startAttack(f, 'runes', 1.2, 0.25, 0.8);
      }
      return;
    }
    // it lumbers after you, but never far from its gate
    f.face(t.x - f.x, t.z - f.z);
    if (d > 70 && f.distTo(f.homeX, f.homeZ) < 95) {
      final (vx, vz) = _steer(f, t.x - f.x, t.z - f.z, look: 30);
      _move(f, vx, vz, rage ? 13 : 10, dt, faceIt: false);
      f.moving = true;
    } else if (f.distTo(f.homeX, f.homeZ) >= 95) {
      final (vx, vz) = _steer(f, f.homeX - f.x, f.homeZ - f.z, look: 30);
      _move(f, vx, vz, 10, dt, faceIt: false);
      f.moving = true;
    } else {
      f.moving = false;
    }
  }

  /// The marks for the Sentinel's moves (from [_startAttack]).
  void _sentinelMarks(Foe f, String move, double windup, Actor t) {
    switch (move) {
      case 'fists':
        // both fists into the ground in front of it (past half its Hollow: one, then the other)
        if (f.hpFrac < 0.5) {
          // its left fist first (the side to its left as it faces you), then its right
          final side = f.lashes.isEven ? 1.0 : -1.0;
          f.mark = Mark(MarkShape.circle, f.x + f.ax * 34 - f.az * 20 * side, f.z + f.az * 34 + f.ax * 20 * side, windup, r: 30, owner: f);
        } else {
          f.mark = Mark(MarkShape.circle, f.x + f.ax * 34, f.z + f.az * 34, windup, r: 42, owner: f);
        }
      case 'beam':
        // the arc its eyes will sweep, faint while it gathers
        f.mark = Mark(MarkShape.cone, f.x, f.z, windup + 1.7, r: 215, dx: f.ax, dz: f.az, half: 0.95, owner: f);
      case 'runes':
        // where you stand, where you are going, and round you
        final lx = t.x + t.vx * 0.4, lz = t.z + t.vz * 0.4;
        f.mark = Mark(MarkShape.circle, lx, lz, windup, r: 19, owner: f);
        final a0 = rng.nextDouble() * math.pi * 2;
        for (var k = 0; k < (f.hpFrac < 0.5 ? 4 : 3); k++) {
          final a = a0 + k * math.pi * 2 / (f.hpFrac < 0.5 ? 4 : 3);
          f.extra.add(Mark(MarkShape.circle, lx + math.cos(a) * 44, lz + math.sin(a) * 44, windup, r: 19, owner: f));
        }
        marks.addAll(f.extra);
    }
  }

  void _sentinelAttack(Foe f, double dt) {
    final t = f.target;
    final rage = f.hpFrac < 0.5;
    if (f.st == FoeState.windup) {
      final k = f.t / f.windup;
      // fists: both raised (past half its Hollow, the one about to come down); beam: its eyes gather
      // light; runes: its arms flung wide
      f.pose = switch (f.move) { 'fists' => rage ? (f.lashes.isEven ? 'slam_r' : 'slam_l') : 'up', 'beam' => 'beam', _ => 'cast' };
      f.glow = k;
      if (f.mark != null) f.mark!.t = f.t;
      for (final m in f.extra) {
        m.t = f.t;
      }
      // the fists' aim follows you until the last moment
      if (f.move == 'fists' && t != null && k < 0.55) {
        final d = math.max(f.dist(t), 1e-6);
        f.ax = (t.x - f.x) / d;
        f.az = (t.z - f.z) / d;
        f.face(f.ax, f.az);
        final m = f.mark;
        if (m != null) {
          final side = rage ? (f.lashes.isEven ? 1.0 : -1.0) : 0.0;
          m
            ..x = f.x + f.ax * 34 - f.az * 20 * side
            ..z = f.z + f.az * 34 + f.ax * 20 * side;
        }
      }
      if (f.t < f.windup) return;
      f.st = FoeState.strike;
      f.t = 0;
      f.glow = 0;
      f.hit.clear();
      switch (f.move) {
        case 'fists':
          final m = f.mark;
          _endMark(f);
          if (m == null) return;
          f.pose = rage ? (f.lashes.isEven ? 'slam_l' : 'slam_r') : 'slam';
          bursts.add(Burst('quake', m.x, m.z, 0.7, size: m.r + 6));
          shake = math.max(shake, 0.55);
          hitstop = math.max(hitstop, 0.05);
          _emit('slam', x: m.x, z: m.z);
          for (final a in [pet, if (sher != null && party) sher!]) {
            if (m.covers(a.x, a.z, a.radius)) {
              final d = math.max(_len(a.x - m.x, a.z - m.z), 1e-6);
              _hurt(a, 20, from: f, kx: (a.x - m.x) / d * 220, kz: (a.z - m.z) / d * 220, stun: 0.3, cause: 'slam');
            }
          }
        case 'beam':
          // the mark stays up as the sweep's path
          f.pose = 'beam';
          f.aimX = math.atan2(f.az, f.ax); // the sweep's middle (an angle)
          _emit('beam', x: f.x, z: f.z);
        case 'runes':
          final hits = [f.mark, ...f.extra].whereType<Mark>().toList();
          _endMark(f);
          f.pose = 'slam';
          shake = math.max(shake, 0.35);
          _emit('runes', x: f.x, z: f.z);
          for (final m in hits) {
            bursts.add(Burst('snare', m.x, m.z, 0.9, size: m.r, tag: 'rune'));
          }
          for (final a in [pet, if (sher != null && party) sher!]) {
            if (hits.any((m) => m.covers(a.x, a.z, a.radius))) {
              _hurt(a, 14, from: f, stun: 0.3, cause: 'runes');
            }
          }
      }
      return;
    }
    if (f.st == FoeState.strike) {
      if (f.move == 'beam') {
        // the sweep: from one side of the arc to the other, burning what it crosses
        final k = (f.t / f.active).clamp(0.0, 1.0);
        final side = (f.lashes.isEven ? 1 : -1).toDouble();
        final a = f.aimX + side * (-0.95 + 1.9 * k);
        final dx = math.cos(a), dz = math.sin(a);
        f.face(dx, dz);
        final ex = f.x + dx * 6, ez = f.z + dz * 6;
        beam = (x: ex, z: ez, dx: dx, dz: dz, len: 215.0, k: k);
        for (final who in [pet, if (sher != null && party) sher!]) {
          if (f.hit.contains(who)) continue;
          final ox = who.x - ex, oz = who.z - ez;
          final along = ox * dx + oz * dz;
          if (along < 0 || along > 215) continue;
          if ((ox * dz - oz * dx).abs() < 9 + who.radius * 0.7) {
            if (_hurt(who, 16, from: f, kx: -dz * side * 120, kz: dx * side * 120, cause: 'beam')) f.hit.add(who);
          }
        }
        if (f.t < f.active) return;
        _endMark(f);
        beam = null;
      } else if (f.t < f.active) {
        return;
      }
      f.st = FoeState.recover;
      f.t = 0;
      return;
    }
    f.pose = null;
    if (f.t < f.recover * (rage ? 0.7 : 1)) return;
    f.lashes++;
    // past half its Hollow the fists come down twice: the other one follows at once
    if (f.move == 'fists' && rage && f.lashes.isOdd && t != null) {
      _startAttack(f, 'fists', 0.45, 0.25, 0.75);
      return;
    }
    f.st = FoeState.engage;
    f.t = 0;
    f.cd = (rage ? 1.3 : 1.9) + rng.nextDouble() * 0.8;
  }

  /// At two thirds and at a third of its Hollow: it kneels behind a shield and calls the dark's creatures.
  void _sentinelHealthCheck(Foe f) {
    if (storyDone || f.calm) return;
    final want = sentinelShields == 0 ? 0.66 : (sentinelShields == 1 ? 0.33 : -1.0);
    if (f.hpFrac > want) return;
    sentinelShields++;
    _endMark(f);
    beam = null;
    sentinelShieldMax = sentinelShield = 110 * foeHp;
    _shieldT = 0;
    f
      ..st = FoeState.engage
      ..t = 0
      ..pose = 'shield'
      ..stun = 0
      ..moving = false;
    shake = math.max(shake, 0.4);
    _emit('shield_up', x: f.x, z: f.z, value: sentinelShields.toDouble());
    // two (then three) creatures out of the dark round the arena's edge, far from your Evochi
    final n = sentinelShields == 1 ? 2 : 3;
    for (var i = 0; i < n; i++) {
      final a = math.atan2(pet.z - f.z, pet.x - f.x) + math.pi + (i - (n - 1) / 2) * 0.9;
      final x = f.x + math.cos(a) * 60, z = f.z + math.sin(a) * 55;
      final o = _spawn('shield_${sentinelShields}_$i', i.isEven ? 'thornling' : 'sporecap', 'gate', x, z)
        ..summoned = true
        ..maxHp = 46 * foeHp
        ..hp = 46 * foeHp
        ..cd = 1.0 + i * 0.6;
      o.homeX = f.x;
      o.homeZ = f.z;
      foes.add(o);
      bursts.add(Burst('motes', x, z, 0.9, size: 1));
      o
        ..target = pet
        ..st = FoeState.alert
        ..alertDelay = 0.4 + i * 0.3;
      o.face(pet.x - x, pet.z - z);
    }
  }

  void _sentinelShielded(Foe f, double dt) {
    _shieldT += dt;
    f.moving = false;
    f.pose = 'shield';
    f.face(pet.x - f.x, pet.z - f.z);
    // runes now and then while it waits behind its shield
    if (f.st == FoeState.windup || f.st == FoeState.strike || f.st == FoeState.recover) {
      if (f.move == 'runes') {
        _sentinelAttack(f, dt);
        f.pose = 'shield';
        return;
      }
      _endMark(f);
      f.st = FoeState.engage;
    }
    if (f.cd <= 0 && pet.alive) {
      f.target = pet;
      _startAttack(f, 'runes', 1.3, 0.25, 0.6);
      f.cd = 3.6;
      return;
    }
    // a shield that nobody can break (no Lumen, the creatures run off) gives out on its own
    if (_shieldT > 30) _shieldBreak(f);
  }

  void _shieldBreak(Foe f) {
    if (sentinelShield <= 0 && f.st == FoeState.stagger) return;
    sentinelShield = 0;
    _endMark(f);
    shake = math.max(shake, 0.5);
    bursts.add(Burst('motes', f.x, f.z - 10, 1.4, size: 3));
    _float('The shield shatters!', f.x, f.z - 30, 'crit', ttl: 1.4);
    _emit('shield_break', x: f.x, z: f.z);
    _stagger(f, 3.2);
    f.cd = 1.0;
  }

  // ---- the Hollow Sprout: rooted in the ruins, it lashes vines, sends thorns up under you, and bursts
  // with spores when you crowd it. Past half its Hollow, it lashes twice.
  void _sproutEngage(Foe f, Actor t, double d, double dt) {
    final rage = f.hpFrac < 0.5;
    if (d < f.radius + t.radius + 20 && f.cd2 <= 0) {
      _startAttack(f, 'burst', 0.7, 0.2, 0.6);
      return;
    }
    if (f.cd <= 0 && _tokens(t, ranged: true) < 2) {
      if (d < 120 && rng.nextDouble() < 0.6) {
        _startAttack(f, 'lash', rage ? 0.62 : 0.85, 0.22, 0.6);
      } else {
        _startAttack(f, 'thorns', rage ? 0.85 : 1.1, 0.25, 0.7);
      }
      return;
    }
    // it hops slowly, keeping 55 to 95 off you, never far from the ruins
    double vx, vz, sp;
    if (d > 95 && f.distTo(f.homeX, f.homeZ) < 70) {
      (vx, vz) = _steer(f, t.x - f.x, t.z - f.z);
      sp = 11;
    } else if (d < 52) {
      (vx, vz) = _escape(f, t);
      sp = 13;
    } else {
      f.strafeT -= dt;
      if (f.strafeT <= 0) {
        f.strafe = -f.strafe;
        f.strafeT = 2.5 + rng.nextDouble() * 2;
      }
      final rx = (f.x - t.x) / d, rz = (f.z - t.z) / d;
      (vx, vz) = _steer(f, -rz * f.strafe, rx * f.strafe, look: 16);
      sp = 7;
    }
    final ph = f.phase;
    _move(f, vx, vz, sp * (math.sin(f.phase * math.pi).abs() * 1.6 + 0.15), dt, faceIt: false);
    f.phase = (ph + dt * 1.2) % 1.0;
    f.moving = true;
    f.face(t.x - f.x, t.z - f.z);
  }

  void _sproutAttack(Foe f, double dt) {
    final t = f.target;
    final rage = f.hpFrac < 0.5;
    if (f.st == FoeState.windup) {
      final k = f.t / f.windup;
      f.pose = f.move == 'lash' ? 'rear' : 'swell';
      f.glow = k;
      if (f.mark != null) f.mark!.t = f.t;
      for (final m in f.extra) {
        m.t = f.t;
      }
      // the lash's aim follows you until the last moment
      if (f.move == 'lash' && t != null && k < 0.6) {
        final d = math.max(f.dist(t), 1e-6);
        f.ax = (t.x - f.x) / d;
        f.az = (t.z - f.z) / d;
        f.face(f.ax, f.az);
        final m = f.mark;
        if (m != null) {
          m.dx = f.ax;
          m.dz = f.az;
        }
      }
      if (f.t < f.windup) return;
      final hits = [f.mark, ...f.extra].whereType<Mark>().toList();
      _endMark(f);
      f.st = FoeState.strike;
      f.t = 0;
      f.glow = 0;
      switch (f.move) {
        case 'lash':
          bursts.add(Burst('lash', f.x, f.z, 0.45, dx: f.ax, dz: f.az, size: 104));
          shake = math.max(shake, 0.25);
          _emit('lash', x: f.x, z: f.z);
          for (final a in [pet, if (sher != null && party) sher!]) {
            if (hits.any((m) => m.covers(a.x, a.z, a.radius))) {
              _hurt(a, 15, from: f, kx: f.ax * 160, kz: f.az * 160, cause: 'lash');
            }
          }
        case 'thorns':
          shake = math.max(shake, 0.35);
          _emit('thorns', x: f.x, z: f.z);
          for (final m in hits) {
            bursts.add(Burst('snare', m.x, m.z, 0.9, size: m.r, tag: 'hollow'));
          }
          for (final a in [pet, if (sher != null && party) sher!]) {
            if (hits.any((m) => m.covers(a.x, a.z, a.radius))) {
              _hurt(a, 13, from: f, stun: 0.25, cause: 'thorns');
            }
          }
        case 'burst':
          bursts.add(Burst('spores', f.x, f.z, 0.9, size: 46));
          _emit('puff', x: f.x, z: f.z);
          for (final a in [pet, if (sher != null && party) sher!]) {
            final d = f.dist(a);
            if (d < 46 + a.radius * 0.6) {
              final k = 1 / math.max(d, 1e-6);
              if (_hurt(a, 10, from: f, kx: (a.x - f.x) * k * 170, kz: (a.z - f.z) * k * 170, cause: 'puff')) {
                a.slowT = math.max(a.slowT, 2.0);
              }
            }
          }
          hazards.add(Hazard(f.x, f.z, 30, 2.4));
      }
      return;
    }
    if (f.st == FoeState.strike) {
      f.pose = f.move == 'lash' ? 'lash' : 'slam';
      if (f.t > f.active) {
        f.st = FoeState.recover;
        f.t = 0;
      }
      return;
    }
    f.pose = null;
    if (f.t < f.recover * (rage ? 0.6 : 1)) return;
    // past half its Hollow, a lash comes back the other way
    if (f.move == 'lash' && rage && f.lashes == 0 && t != null) {
      f.lashes = 1;
      _startAttack(f, 'lash', 0.4, 0.22, 0.5);
      return;
    }
    f.lashes = 0;
    f.st = FoeState.engage;
    f.t = 0;
    if (f.move == 'burst') {
      f.cd2 = 5.0;
      f.cd = math.max(f.cd, 0.9);
    } else {
      f.cd = (rage ? 1.3 : 2.0) + rng.nextDouble() * 0.8;
    }
  }

  // ---- defeated: the Hollow lifts
  /// Playtesting (debug builds' C key): every creature still fighting (or those [where] picks) is calmed
  /// where it stands.
  void calmAllForTesting({bool Function(Foe f)? where}) {
    for (final f in foes.toList()) {
      if (!f.calm && (where == null || where(f))) _calm(f);
    }
  }

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
    if ((f.kind == 'hollow_sprout' && storyBeat == 'sprout') || (f.kind == 'sentinel' && storyBeat == 'sentinel')) {
      storyDone = true;
      shake = math.max(shake, 0.6);
      slowmo = 0.8;
      bursts.add(Burst('motes', f.x, f.z, 2.2, size: 3));
      if (f.kind == 'sentinel') {
        sentinelShield = 0;
        beam = null;
        f.pose = 'bow';
        // what it called out of the dark goes quiet with it
        for (final o in foes) {
          if (o.summoned && !o.calm && o.alive) _calm(o);
        }
      }
      _emit('story_done', text: f.kind, x: f.x, z: f.z);
    }
    if (f.summoned && sentinelShield > 0 && foes.every((o) => !o.summoned || o.calm || o == f)) {
      // the last of what the Sentinel called is calm: its shield has nothing left to hold it up
      final st = sentinel;
      if (st != null) _shieldBreak(st);
    }
    _emit('calm', x: f.x, z: f.z);
    hitstop = math.max(hitstop, 0.06);
    shake = math.max(shake, 0.3);
    calmed += f.summoned ? 0 : 1;
    // what it leaves: coins into the purse, sometimes a shard, a mote of light that heals
    final c = ((((f.kind == 'sporecap' ? 3 : 2) + rng.nextInt(3)) * (f.elite ? 5 : 1) + (foeHp > 1 ? (foeHp * 2).round() : 0)) * coinMul).round();
    coins += c;
    // the coins burst out of it, bounce on the ground, then fly up to your purse (the screen counts them in)
    if (c > 0) {
      final n = c.clamp(3, 12);
      for (var i = 0; i < n; i++) {
        final a = lootRng.nextDouble() * math.pi * 2, v = 40 + lootRng.nextDouble() * 55;
        final share = c ~/ n + (i < c % n ? 1 : 0);
        pickups.add(Pickup('coin', f.x, f.z, share, vx: math.cos(a) * v, vz: math.sin(a) * v * 0.7, vy: 70 + lootRng.nextDouble() * 60));
      }
    } else if (!f.summoned) {
      for (var i = 0; i < 4; i++) {
        final a = lootRng.nextDouble() * math.pi * 2, v = 70 + lootRng.nextDouble() * 50;
        pickups.add(Pickup('loot', f.x, f.z, 0, vx: math.cos(a) * v, vz: math.sin(a) * v));
      }
    }
    if (f.elite) {
      // an elite always leaves a shard, and gets a second roll at something rare
      items['lumen_shard'] = (items['lumen_shard'] ?? 0) + 1;
      _float('+1 Lumen Shard', f.x, f.z - 20, 'loot', ttl: 1.6);
      for (var i = 0; i < (surge ? 2 : 1); i++) {
        lootRoll?.call(lootRng).forEach((id, n) {
          items[id] = (items[id] ?? 0) + n;
          _float(lootLabel?.call(id, n) ?? '+$n $id', f.x, f.z - 27 - 7 * i, 'loot', ttl: 2.0);
          _emit('rare_drop', text: id, x: f.x, z: f.z);
        });
      }
    }
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
    // the Starseed Charm: a bloom of light grows where it was calmed
    if (charm == 'starseed_charm' && !f.summoned) pickups.add(Pickup('bloom', f.x - 4, f.z - 2, const [12, 18, 24][_ci]));
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
    if (f.kind == 'sentinel') {
      // restored, it bows to you, then stands at its gate again, keeping it (turned to you when you are near)
      f.moving = false;
      f.pose = f.t < 3.2 ? 'bow' : null;
      if (f.t >= 3.2 && pet.dist(f) < 120) f.face(pet.x - f.x, pet.z - f.z);
      return;
    }
    if (f.kind == 'hollow_sprout') {
      // restored, it stays among the ruins: little happy hops, turned to you
      f.moving = false;
      f.lift = math.max(0, math.sin(f.t * 5)) * 3;
      if (pet.dist(f) < 120) f.face(pet.x - f.x, pet.z - f.z);
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
        if (s.hits.contains(f)) continue;
        if (_len(f.x - s.x, f.z - s.z) < f.radius + 4) {
          final sp = math.max(_len(s.vx, s.vz), 1e-6);
          _hurt(f, _boltDmg * atk * s.power, from: pet, kx: s.vx / sp * 50, kz: s.vz / sp * 50, poise: 10 * s.power);
          s.hits.add(f);
          bursts.add(Burst('glow', s.x, s.z, 0.35));
          bursts.add(Burst('impact', f.x, f.z, 0.26, dx: s.vx / sp, dz: s.vz / sp, size: 0.9, tag: 'mint'));
          hitstop = math.max(hitstop, 0.03);
          shake = math.max(shake, 0.14);
          if (s.pierce > 0) {
            // it goes straight through and on to the next one
            s.pierce--;
            if (s.shard) break; // a crystal shard flies on straight
            s.life = s.t + 0.8;
            Foe? next;
            var nd = 130.0;
            for (final o in hostile) {
              if (s.hits.contains(o)) continue;
              final d = _len(o.x - s.x, o.z - s.z);
              if (d < nd) {
                nd = d;
                next = o;
              }
            }
            s.target = next;
            bursts.add(Burst('spark', s.x, s.z, 0.3));
            break;
          }
          s.done = true;
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

  void _chill(Foe a, double secs) {
    if (a.chillT <= 0) bursts.add(Burst('frost', a.x, a.z, 0.6, size: a is Boss ? 1.6 : 1));
    a.chillT = math.max(a.chillT, secs);
  }

  void _sapHeal(Foe a, double hp) {
    pet.hp = math.min(pet.maxHp, pet.hp + hp);
    bursts.add(Burst('sap', a.x, a.z, 0.6, dx: pet.x - a.x, dz: pet.z - a.z));
  }

  /// Dizziness builds with every hit; it reels at the top (once any stun it is already in is over).
  void _dazzle(Foe a, double by) {
    a.daze = math.min(100, a.daze + by);
    if (a.daze >= 100 && a.stun <= 0) {
      a.daze = 0;
      _stagger(a, a is Boss ? 0.9 : 1.4);
      _float('Dazzled!', a.x, a.z - 6, 'crit', ttl: 0.8);
      bursts.add(Burst('stars', a.x, a.z, 1.2, size: a is Boss ? 2 : 1));
      _emit('dazzled', x: a.x, z: a.z);
    }
  }

  /// A spark leaps from [a] to the nearest other foe.
  void _spark(Foe a, double dmg) {
    Foe? next;
    var nd = 80.0;
    for (final o in hostile) {
      if (o == a || o.calm) continue;
      final d = o.dist(a);
      if (d < nd) {
        nd = d;
        next = o;
      }
    }
    bursts.add(Burst('zap', a.x, a.z, 0.35, dx: (next?.x ?? a.x + 20) - a.x, dz: (next?.z ?? a.z) - a.z));
    _emit('zap', x: a.x, z: a.z);
    if (next != null) {
      _chaining = true;
      _hurt(next, dmg, from: pet, poise: 6, stun: 0.25);
      _chaining = false;
    }
  }

  /// Frost thaws and dizziness clears with time.
  void _cool(Foe f, double dt) {
    if (f.chillT > 0) f.chillT = math.max(0, f.chillT - dt);
    if (f.daze > 0) f.daze = math.max(0, f.daze - dt * 9);
  }

  /// Ember Draught burns: a few points a second for as long as the fire lasts.
  void _tickBurns(double dt) {
    for (final f in foes) {
      if (f.burnT <= 0 || f.calm || !f.alive) continue;
      f.burnT -= dt;
      f.hp -= 5 * dt;
      f._burnFx -= dt;
      if (f._burnFx <= 0) {
        f._burnFx = 0.22;
        bursts.add(Burst('ember', f.x + (rng.nextDouble() - 0.5) * f.radius, f.z, 0.5));
      }
      if (f.hp <= 0) {
        f.hp = 0;
        _calm(f);
      }
    }
  }

  void _tickPickups(double dt) {
    for (final p in pickups) {
      p.t += dt;
      if (p.kind == 'coin') {
        // a coin: out and up, down with a bounce or two, a short rest, then the screen flies it to the purse
        if (p.t < 1.1) {
          p.x += p.vx * dt;
          p.z += p.vz * dt;
          p.y += p.vy * dt;
          p.vy -= 300 * dt;
          if (p.y <= 0 && p.vy < 0) {
            p.y = 0;
            p.bounces++;
            p.vy = p.bounces < 3 ? -p.vy * 0.42 : 0;
            p.vx *= 0.55;
            p.vz *= 0.55;
            if (p.bounces == 1) _emit('coin_bounce', x: p.x, z: p.z);
          }
          p.vx *= math.pow(0.2, dt).toDouble();
          p.vz *= math.pow(0.2, dt).toDouble();
        } else {
          p.t = 999;
          _emit('coin_fly', value: p.amount.toDouble(), x: p.x, z: p.z);
        }
        continue;
      }
      if (p.kind == 'loot') {
        // a glint of loot: it bursts out, settles, then flies to your Evochi
        if (p.t < 0.35) {
          p.x += p.vx * dt;
          p.z += p.vz * dt;
          p.vx *= 0.9;
          p.vz *= 0.9;
        } else {
          final dx = pet.x - p.x, dz = pet.z - p.z, d = math.max(_len(dx, dz), 1e-6);
          final sp = 120 + 260 * math.min(1.0, (p.t - 0.35) * 2);
          p.x += dx / d * math.min(d, sp * dt);
          p.z += dz / d * math.min(d, sp * dt);
          if (d < pet.radius + 4) {
            p.t = 999;
            _emit('loot_in');
          }
        }
        continue;
      }
      if (p.kind == 'bloom' && p.t < 0.6) continue; // a bloom opens before it can be picked
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
    bossTrail.removeWhere((e) => time - e.$3 > 0.32);
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
    _closeCall = false;
    _hoofT = 0;
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
          // it paws the moss twice before it goes: dust off a front hoof and a thud you feel
          final k0 = b.windup <= 0 ? 1.0 : (b.t - dt) / b.windup;
          for (final at in const [0.22, 0.55]) {
            if (k0 < at && k >= at) {
              bursts.add(Burst('dust', b.x + b.fx * b.radius * 0.9, b.z + b.fz * b.radius * 0.9, 0.5, size: 1.1));
              shake = math.max(shake, 0.18);
              _emit('paw', x: b.x, z: b.z);
            }
          }
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
          // afterimages, a dust trail and the moss torn up behind it; a thud on every stride
          _trailT -= dt;
          if (_trailT <= 0) {
            _trailT = 0.045;
            bossTrail.add((b.x, b.z, time));
            bursts.add(Burst('dust', b.x - b.ax * b.radius * 0.7, b.z - b.az * b.radius * 0.7, 0.55, size: 1.2));
            bursts.add(Burst('scar', b.x - b.ax * 4, b.z - b.az * 4, 3.0, dx: b.ax, dz: b.az, size: 1));
          }
          _hoofT -= dt;
          if (_hoofT <= 0) {
            _hoofT = 0.17;
            shake = math.max(shake, 0.16);
            _emit('hoof', x: b.x, z: b.z);
          }
          // a close call: it thunders past within a hair and you are untouched: the world slows, a counter is ready
          if (!_closeCall && !b.hit.contains(pet) && pet.alive && b.travelled > 20 && b.dist(pet) < b.radius + pet.radius + 14) {
            final ahead = (pet.x - b.x) * b.ax + (pet.z - b.z) * b.az;
            if (ahead < 4) {
              _closeCall = true;
              slowmo = math.max(slowmo, 0.4);
              counterT = math.max(counterT, 1.1);
              _float('Close call!', pet.x, pet.z, 'crit', ttl: 0.9);
              _emit('close_call', x: pet.x, z: pet.z);
              _sigGain(30);
            }
          }
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
            shake = 1.0;
            hitstop = 0.14;
            _crashInto(b);
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
    cheerT = 4;
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
  /// The entrance played as a cinematic: straight into the fight (no second roar).
  void skipIntro() {
    final b = boss;
    if (b == null || bossState != BossState.intro) return;
    b.t = math.max(b.t, 2.19);
  }

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
    damage.clear();
    broken.clear();
    bossTrail.clear();
    _rebuildBlocks();
  }
}
