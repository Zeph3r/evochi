// Your Evochi's personality (docs: Evochi Personality and Combat Architecture, v1.0): who it is, made once when
// it hatches and kept for life. It decides how an action looks, never what it does: a hop when food arrives, a
// careful step back before investigating, a slow tilt and a lean toward a leaf. Recognition comes from a few
// habits repeated, not from many random ones.
//
// What is saved is the whole result (traits, profile, signature, habits, repertoires, style), not only the
// seed, so a later change to the generator never quietly turns one companion into another. An Evochi from
// before personalities gets one once, by a versioned migration, from its own id.

import 'catalog.dart';

/// The save format's version (the behaviours' content is revised in the catalog, apart from this).
const personalityVersion = 1;

/// The five traits, each 0..1.
const traitNames = ['energy', 'curiosity', 'boldness', 'sociability', 'expressiveness'];

class Personality {
  Personality({
    required this.version,
    required this.seed,
    required this.traits,
    required this.profile,
    required this.interest,
    required this.signature,
    required this.habits,
    required this.idle,
    required this.combat,
    required this.style,
    this.origin = 'hatch',
  });

  final int version;
  final int seed;
  final Map<String, double> traits;

  /// the profile it was made from (cautious | lively | calm): a description of the whole, not a class
  final String profile;

  /// what it is drawn to (plants | food | shiny | critters | water)
  final String interest;

  /// its one dominant habit, kept for the moments that matter (catalog behaviour id)
  final String signature;

  /// two supporting habits
  final List<String> habits;

  /// what it does with itself when nothing is happening
  final List<String> idle;

  /// how it carries itself in an encounter: stance, anticipation, recovery, calmedReaction -> behaviour ids
  final Map<String, String> combat;

  /// small, bounded differences in timing and size: amplitude, tempo, holdTilt
  final Map<String, double> style;

  /// how it came by this personality: 'hatch', or 'migration' for an Evochi from before them
  final String origin;

  double trait(String t) => traits[t] ?? 0.5;

  factory Personality.fromJson(Map<String, dynamic> j) => Personality(
        version: (j['personalityVersion'] as num?)?.toInt() ?? 1,
        seed: (j['personalitySeed'] as num?)?.toInt() ?? 0,
        traits: {for (final e in ((j['traits'] as Map?) ?? const {}).entries) e.key as String: (e.value as num).toDouble()},
        profile: (j['profile'] as String?) ?? 'calm',
        interest: (j['interest'] as String?) ?? 'plants',
        signature: (j['signature'] as String?) ?? 'tilt_then_lean',
        habits: [for (final h in (j['supportingHabits'] as List?) ?? const []) h as String],
        idle: [for (final h in (j['idleRepertoire'] as List?) ?? const []) h as String],
        combat: {for (final e in ((j['combatRepertoire'] as Map?) ?? const {}).entries) e.key as String: e.value as String},
        style: {for (final e in ((j['style'] as Map?) ?? const {}).entries) e.key as String: (e.value as num).toDouble()},
        origin: (j['origin'] as String?) ?? 'hatch',
      );

  Map<String, dynamic> toJson() => {
        'personalityVersion': version,
        'personalitySeed': seed,
        'traits': traits,
        'profile': profile,
        'interest': interest,
        'signature': signature,
        'supportingHabits': habits,
        'idleRepertoire': idle,
        'combatRepertoire': combat,
        'style': style,
        'origin': origin,
      };
}

/// A small seeded generator (mulberry32), the same on every platform and Dart version, so a seed always makes
/// the same companion. (What is saved is the result; this only matters while generating.)
class SeededRandom {
  SeededRandom(int seed) : _s = seed & 0xFFFFFFFF;
  int _s;

  double next() {
    _s = (_s + 0x6D2B79F5) & 0xFFFFFFFF;
    var t = _s;
    t = _imul(t ^ (t >> 15), t | 1);
    t ^= (t + _imul(t ^ (t >> 7), t | 61)) & 0xFFFFFFFF;
    return ((t ^ (t >> 14)) & 0xFFFFFFFF) / 4294967296.0;
  }

  double range(double a, double b) => a + (b - a) * next();
  int below(int n) => (next() * n).floor().clamp(0, n - 1);
  T pick<T>(List<T> l) => l[below(l.length)];

  static int _imul(int a, int b) => ((a & 0xFFFFFFFF) * (b & 0xFFFFFFFF)) & 0xFFFFFFFF;
}

/// A stable 32-bit seed from a string (FNV-1a): an Evochi's own id.
int seedFrom(String s) {
  var h = 0x811C9DC5;
  for (final c in s.codeUnits) {
    h ^= c;
    h = (h * 0x01000193) & 0xFFFFFFFF;
  }
  return h;
}

/// Makes a personality: a profile, traits within it, an interest it can show, its signature, two supporting
/// habits, an idle and a combat repertoire, and small style differences; every behaviour chosen is checked
/// against the catalog (it exists and the profile allows it), falling back to the neutral one.
Personality generatePersonality(int seed, {String origin = 'hatch', String? profile}) {
  final r = SeededRandom(seed);
  final prof = profiles[profile] ?? profiles.values.elementAt(r.below(profiles.length));
  final traits = {for (final t in traitNames) t: _round(r.range(prof.traits[t]!.$1, prof.traits[t]!.$2))};
  final interest = r.pick(prof.interests);
  final pool = [...prof.habitPool]..sort();
  final habits = <String>[];
  while (habits.length < 2 && pool.isNotEmpty) {
    habits.add(pool.removeAt(r.below(pool.length)));
  }
  String valid(String id) => behaviors.containsKey(id) ? id : neutralIdle;
  return Personality(
    version: personalityVersion,
    seed: seed,
    traits: traits,
    profile: prof.id,
    interest: interest,
    signature: valid(prof.signature),
    habits: [for (final h in habits) valid(h)],
    idle: [for (final h in prof.idle) valid(h)],
    combat: {for (final e in prof.combat.entries) e.key: valid(e.value)},
    style: {
      'amplitude': _round(r.range(0.88, 1.12)),
      'tempo': _round(r.range(0.92, 1.08)),
      'holdTilt': _round(r.range(0.9, 1.2)),
    },
    origin: origin,
  );
}

/// The one-time migration: an Evochi from before personalities gets one from its own id (so it is the same
/// one however often the save is loaded before it is next written).
Personality migratePersonality(String petId) => generatePersonality(seedFrom(petId), origin: 'migration');

double _round(double v) => (v * 100).round() / 100;
