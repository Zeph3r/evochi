// The personality genome: who an Evochi is, as continuous traits rolled from its egg's seed rather than picked
// from a few archetypes. Each gene is 0..1 (shown 0..100); most land near the middle and the extremes are rarer,
// so a very bold or very lazy one is something to notice. Nothing reads a gene alone: the brain (brain.dart)
// weighs them together, so a handful of genes make many distinct companions (a curious one with no courage
// creeps up on new things and bolts; a curious feisty one pounces).
//
// A child's genome comes from two parents' (each gene a blend of theirs, now and then nudged), with its own
// seed, so breeding can be added later and players can breed for calmer or more adventurous companions.

import 'personality.dart' show SeededRandom, imul32;

/// the genes, in a fixed order (the order they are rolled in: never reorder, only add at the end)
const geneNames = ['curiosity', 'courage', 'sociability', 'energy', 'appetite', 'feistiness', 'expressiveness'];

/// what each gene is called, and what its ends look like in a companion
const geneInfo = <String, (String label, String low, String high)>{
  'curiosity': ('Curiosity', 'Unbothered', 'Curious'),
  'courage': ('Courage', 'Timid', 'Brave'),
  'sociability': ('Sociability', 'Independent', 'Friendly'),
  'energy': ('Energy', 'Sleepy', 'Lively'),
  'appetite': ('Appetite', 'Dainty', 'Greedy'),
  'feistiness': ('Feistiness', 'Gentle', 'Feisty'),
  'expressiveness': ('Expressiveness', 'Stoic', 'Bubbly'),
};

// what it is, by the gene that stands out most (high, low)
const _nouns = <String, (String, String)>{
  'curiosity': ('Explorer', 'Homebody'),
  'courage': ('Adventurer', 'Worrier'),
  'sociability': ('Cuddler', 'Loner'),
  'energy': ('Bouncer', 'Napper'),
  'appetite': ('Snacker', 'Nibbler'),
  'feistiness': ('Scrapper', 'Softie'),
  'expressiveness': ('Performer', 'Thinker'),
};

class Genome {
  Genome(this.seed, Map<String, double> genes, {this.generation = 0, this.parents = const []})
      : genes = {for (final g in geneNames) g: (genes[g] ?? 0.5).clamp(0.0, 1.0)};

  final int seed;
  final Map<String, double> genes;

  /// 0 for a hatched egg, a parent's generation + 1 for a bred one
  final int generation;

  /// its parents' seeds (a bred one)
  final List<int> parents;

  double operator [](String g) => genes[g] ?? 0.5;

  /// the gene as players see it, 0..100
  int score(String g) => (this[g] * 100).round();

  /// rolled from an egg's seed: each gene the mean of three rolls (most near the middle), spread back out a
  /// little so the ends are reachable but rare (about one gene in ten past 15 or 85)
  factory Genome.fromSeed(int seed) {
    final r = SeededRandom(seed ^ 0x9E3779B9);
    final g = <String, double>{};
    for (final name in geneNames) {
      final m = (r.next() + r.next() + r.next()) / 3;
      g[name] = _round((0.5 + (m - 0.5) * 1.3).clamp(0.02, 0.98));
    }
    return Genome(seed, g);
  }

  /// a child of [a] and [b]: each gene somewhere between theirs, a quarter of them nudged (a mutation)
  factory Genome.child(Genome a, Genome b, int nonce) {
    final seed = _mix(_mix(a.seed, b.seed), nonce);
    final r = SeededRandom(seed);
    final g = <String, double>{};
    for (final name in geneNames) {
      final w = r.next();
      var v = a[name] * w + b[name] * (1 - w);
      if (r.next() < 0.25) v += (r.next() - 0.5) * 0.24;
      g[name] = _round(v.clamp(0.02, 0.98));
    }
    return Genome(seed, g, generation: 1 + (a.generation > b.generation ? a.generation : b.generation), parents: [a.seed, b.seed]);
  }

  Genome copyWith(String gene, double value) =>
      Genome(seed, {...genes, gene: value}, generation: generation, parents: parents);

  /// the five traits the acting catalog is keyed by (personality.dart's traitNames)
  Map<String, double> get traits => {
        'energy': this['energy'],
        'curiosity': this['curiosity'],
        'boldness': this['courage'],
        'sociability': this['sociability'],
        'expressiveness': this['expressiveness'],
      };

  /// a name for who it is: its most striking gene as a noun, its next as an adjective ("Timid Explorer")
  String describe() {
    final ranked = [...geneNames]..sort((x, y) => (this[y] - 0.5).abs().compareTo((this[x] - 0.5).abs()));
    final top = ranked[0], next = ranked[1];
    final noun = this[top] >= 0.5 ? _nouns[top]!.$1 : _nouns[top]!.$2;
    final adj = this[next] >= 0.5 ? geneInfo[next]!.$3 : geneInfo[next]!.$2;
    if ((this[top] - 0.5).abs() < 0.08) return 'Easygoing Sort';
    return '$adj $noun';
  }

  Map<String, dynamic> toJson() => {'seed': seed, 'genes': genes, 'generation': generation, 'parents': parents};

  factory Genome.fromJson(Map<String, dynamic> j) => Genome(
        (j['seed'] as num).toInt(),
        {for (final e in ((j['genes'] as Map?) ?? const {}).entries) e.key as String: (e.value as num).toDouble()},
        generation: (j['generation'] as num?)?.toInt() ?? 0,
        parents: [for (final p in (j['parents'] as List?) ?? const []) (p as num).toInt()],
      );
}

int _mix(int a, int b) {
  var h = (a ^ 0x85EBCA6B) & 0xFFFFFFFF;
  h = imul32(h ^ (b & 0xFFFFFFFF), 0x27D4EB2D);
  h ^= h >> 15;
  h = imul32(h, 0x165667B1);
  return h ^ (h >> 13);
}

double _round(double v) => (v * 100).round() / 100;
