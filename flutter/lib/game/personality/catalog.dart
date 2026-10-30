// The personality catalog: three profiles to start (cautious, lively, calm) and the behaviours they draw on, as
// data. A behaviour is a performance with a stable id: where it may play (its contexts), what it needs (a
// target, a stage it is drawn for), how much each trait draws it, how long before it may play again, what the
// body does (an acting clip, tools/art/acting.py) and the face over it, and what plays if it cannot.
//
// Signatures are the habits a player learns to recognise: kept for the moments that matter (hatching, food
// arriving, a first encounter) and rationed by a long cooldown. Supporting habits fill in; the neutral idle is
// always there.

class ProfileDef {
  const ProfileDef({
    required this.id,
    required this.label,
    required this.traits,
    required this.interests,
    required this.signature,
    required this.habitPool,
    required this.idle,
    required this.combat,
  });
  final String id, label;

  /// each trait's range in this profile
  final Map<String, (double, double)> traits;
  final List<String> interests;
  final String signature;
  final List<String> habitPool;
  final List<String> idle;
  final Map<String, String> combat;
}

class BehaviorDef {
  const BehaviorDef({
    required this.id,
    required this.kind,
    required this.contexts,
    this.affinity = const {},
    this.interest,
    this.base = 1.0,
    this.priority = 1,
    this.cooldown = 20,
    this.clip,
    this.motion = 'none',
    this.expr = 'happy',
    this.exprEnd,
    this.duration = 1.2,
    this.particles = '',
    this.fallback = neutralIdle,
  });
  final String id;

  /// signature | habit | idle | neutral | combat
  final String kind;

  /// where it may play: hatch, feed, pet, play, reward, idle, return, wilds_open, wilds_await, wilds_calmed ...
  final Set<String> contexts;

  /// trait -> pull: each factor is (trait value)^pull for a positive pull, (1 - value)^-pull for a negative one,
  /// so a cautious companion is drawn to what low boldness likes; all bounded, never negative
  final Map<String, double> affinity;

  /// drawn more when this is what the companion is interested in
  final String? interest;
  final double base;
  final int priority;

  /// seconds before it may play again
  final double cooldown;

  /// the acting clip (tools/art/acting.py); null: no clip, the face (and [motion]) carry it
  final String? clip;

  /// what the body does where its clip isn't drawn for this stage: the scene's own simple motions
  final String motion;
  final String expr;
  final String? exprEnd;
  final double duration;
  final String particles;
  final String fallback;
}

const neutralIdle = 'neutral_idle';

const profiles = <String, ProfileDef>{
  // gathers its courage: a small step back, then it commits; checks before it relaxes
  'cautious': ProfileDef(
    id: 'cautious',
    label: 'Cautious',
    traits: {'energy': (0.25, 0.5), 'curiosity': (0.5, 0.9), 'boldness': (0.05, 0.35), 'sociability': (0.3, 0.7), 'expressiveness': (0.4, 0.75)},
    interests: ['plants', 'critters', 'shiny'],
    signature: 'step_back_then_commit',
    habitPool: ['careful_peek', 'relieved_hop', 'look_around'],
    idle: ['careful_peek', 'look_around', 'gentle_sway'],
    combat: {'stance': 'careful_ready', 'anticipation': 'small_brace', 'recovery': 'check_then_relax', 'calmedReaction': 'cautious_approach'},
  ),
  // can't keep still: a double hop when something good happens, a wiggle, a quick look round
  'lively': ProfileDef(
    id: 'lively',
    label: 'Lively',
    traits: {'energy': (0.7, 1.0), 'curiosity': (0.4, 0.8), 'boldness': (0.55, 0.9), 'sociability': (0.6, 1.0), 'expressiveness': (0.65, 1.0)},
    interests: ['food', 'critters', 'shiny'],
    signature: 'double_hop',
    habitPool: ['happy_wiggle', 'proud_chin_lift', 'quick_look'],
    idle: ['happy_wiggle', 'quick_look', 'bounce_in_place'],
    combat: {'stance': 'bouncy_ready', 'anticipation': 'quick_bounce', 'recovery': 'celebratory_shuffle', 'calmedReaction': 'bounce_over'},
  ),
  // takes things in: a tilt of the head, then it leans in; settles into a gentle sway
  'calm': ProfileDef(
    id: 'calm',
    label: 'Calm',
    traits: {'energy': (0.1, 0.4), 'curiosity': (0.55, 0.95), 'boldness': (0.35, 0.65), 'sociability': (0.35, 0.75), 'expressiveness': (0.25, 0.55)},
    interests: ['plants', 'water', 'shiny'],
    signature: 'tilt_then_lean',
    habitPool: ['gentle_sway', 'slow_blink', 'proud_chin_lift'],
    idle: ['gentle_sway', 'slow_blink', 'inspect_leaf'],
    combat: {'stance': 'planted_focus', 'anticipation': 'plant_feet', 'recovery': 'settle_sway', 'calmedReaction': 'gentle_nod'},
  ),
};

const behaviors = <String, BehaviorDef>{
  // ---- signatures
  'double_hop': BehaviorDef(
      id: 'double_hop', kind: 'signature', contexts: {'hatch', 'feed', 'play', 'idle', 'wilds_open', 'wilds_calmed'},
      affinity: {'energy': 1.5, 'expressiveness': 1.0}, base: 1.4, priority: 3, cooldown: 75,
      clip: 'double_hop', motion: 'hop', expr: 'excited', duration: 1.25, particles: 'stars'),
  'tilt_then_lean': BehaviorDef(
      id: 'tilt_then_lean', kind: 'signature', contexts: {'hatch', 'feed', 'idle', 'wilds_open', 'wilds_calmed'},
      affinity: {'curiosity': 1.5, 'energy': -1.0}, interest: 'plants', base: 1.4, priority: 3, cooldown: 75,
      clip: 'tilt_then_lean', motion: 'tilt', expr: 'curious', exprEnd: 'happy', duration: 1.6),
  'step_back_then_commit': BehaviorDef(
      id: 'step_back_then_commit', kind: 'signature', contexts: {'hatch', 'feed', 'idle', 'wilds_open', 'wilds_calmed'},
      affinity: {'boldness': -1.5, 'curiosity': 1.0}, base: 1.4, priority: 3, cooldown: 75,
      clip: 'step_back_then_commit', motion: 'wiggle', expr: 'surprised', exprEnd: 'determined', duration: 1.5),
  // ---- supporting habits
  'proud_chin_lift': BehaviorDef(
      id: 'proud_chin_lift', kind: 'habit', contexts: {'pet', 'reward', 'play'},
      affinity: {'boldness': 1.0, 'expressiveness': 0.8}, base: 1.0, priority: 2, cooldown: 30,
      clip: 'chin_lift', motion: 'bounce', expr: 'happy', duration: 1.1, particles: 'stars'),
  'careful_peek': BehaviorDef(
      id: 'careful_peek', kind: 'habit', contexts: {'idle', 'feed', 'return'},
      affinity: {'curiosity': 1.0, 'boldness': -1.0}, base: 1.0, priority: 2, cooldown: 25,
      clip: 'careful_peek', motion: 'tilt', expr: 'curious', duration: 1.3),
  'relieved_hop': BehaviorDef(
      id: 'relieved_hop', kind: 'habit', contexts: {'pet', 'reward', 'feed'},
      affinity: {'boldness': -0.8, 'expressiveness': 0.6}, base: 0.9, priority: 2, cooldown: 30,
      clip: 'small_hop', motion: 'hop', expr: 'happy', duration: 0.9, particles: 'hearts'),
  'look_around': BehaviorDef(
      id: 'look_around', kind: 'idle', contexts: {'idle', 'return'},
      affinity: {'curiosity': 0.8, 'boldness': -0.5}, base: 0.9, priority: 1, cooldown: 20,
      clip: 'look_around', motion: 'tilt', expr: 'curious', duration: 1.4),
  'happy_wiggle': BehaviorDef(
      id: 'happy_wiggle', kind: 'habit', contexts: {'idle', 'pet', 'play', 'reward'},
      affinity: {'energy': 1.0, 'expressiveness': 1.0}, base: 1.0, priority: 2, cooldown: 22,
      clip: 'happy_wiggle', motion: 'wiggle', expr: 'excited', duration: 0.9, particles: 'hearts'),
  'quick_look': BehaviorDef(
      id: 'quick_look', kind: 'idle', contexts: {'idle', 'return'},
      affinity: {'energy': 0.8, 'curiosity': 0.6}, base: 0.9, priority: 1, cooldown: 18,
      clip: 'quick_look', motion: 'tilt', expr: 'curious', duration: 0.9),
  'bounce_in_place': BehaviorDef(
      id: 'bounce_in_place', kind: 'idle', contexts: {'idle'},
      affinity: {'energy': 1.2}, base: 0.9, priority: 1, cooldown: 20,
      clip: 'bounce_in_place', motion: 'bounce', expr: 'happy', duration: 1.0),
  'gentle_sway': BehaviorDef(
      id: 'gentle_sway', kind: 'idle', contexts: {'idle', 'return'},
      affinity: {'energy': -1.0}, base: 1.0, priority: 1, cooldown: 16,
      clip: 'gentle_sway', motion: 'none', expr: 'happy', duration: 1.8),
  'slow_blink': BehaviorDef(
      id: 'slow_blink', kind: 'idle', contexts: {'idle'},
      affinity: {'energy': -1.2, 'expressiveness': -0.4}, base: 0.9, priority: 1, cooldown: 14,
      motion: 'none', expr: 'sleepy', exprEnd: 'happy', duration: 1.2),
  'inspect_leaf': BehaviorDef(
      id: 'inspect_leaf', kind: 'idle', contexts: {'idle'},
      affinity: {'curiosity': 1.2}, interest: 'plants', base: 0.9, priority: 1, cooldown: 24,
      clip: 'tilt_then_lean', motion: 'tilt', expr: 'curious', duration: 1.5),
  // ---- neutral: always there, the floor under every choice
  neutralIdle: BehaviorDef(
      id: neutralIdle, kind: 'neutral', contexts: {'idle', 'hatch', 'feed', 'pet', 'play', 'reward', 'return', 'wilds_open', 'wilds_calmed'},
      base: 0.35, priority: 0, cooldown: 0, motion: 'none', expr: 'happy', duration: 1.0),
  // ---- the encounter (phase 2: the expression director picks these round an authoritative combat action)
  'careful_ready': BehaviorDef(id: 'careful_ready', kind: 'combat', contexts: {'wilds_stance'}, clip: 'careful_ready', expr: 'determined'),
  'small_brace': BehaviorDef(id: 'small_brace', kind: 'combat', contexts: {'wilds_anticipation'}, clip: 'small_brace', expr: 'determined'),
  'check_then_relax': BehaviorDef(id: 'check_then_relax', kind: 'combat', contexts: {'wilds_recovery'}, clip: 'check_then_relax', expr: 'curious', exprEnd: 'happy'),
  'cautious_approach': BehaviorDef(id: 'cautious_approach', kind: 'combat', contexts: {'wilds_calmed'}, clip: 'step_back_then_commit', expr: 'curious', exprEnd: 'happy'),
  'bouncy_ready': BehaviorDef(id: 'bouncy_ready', kind: 'combat', contexts: {'wilds_stance'}, clip: 'bounce_in_place', expr: 'excited'),
  'quick_bounce': BehaviorDef(id: 'quick_bounce', kind: 'combat', contexts: {'wilds_anticipation'}, clip: 'small_hop', expr: 'determined'),
  'celebratory_shuffle': BehaviorDef(id: 'celebratory_shuffle', kind: 'combat', contexts: {'wilds_recovery'}, clip: 'happy_wiggle', expr: 'excited'),
  'bounce_over': BehaviorDef(id: 'bounce_over', kind: 'combat', contexts: {'wilds_calmed'}, clip: 'double_hop', expr: 'excited'),
  'planted_focus': BehaviorDef(id: 'planted_focus', kind: 'combat', contexts: {'wilds_stance'}, clip: 'gentle_sway', expr: 'determined'),
  'plant_feet': BehaviorDef(id: 'plant_feet', kind: 'combat', contexts: {'wilds_anticipation'}, clip: 'careful_ready', expr: 'determined'),
  'settle_sway': BehaviorDef(id: 'settle_sway', kind: 'combat', contexts: {'wilds_recovery'}, clip: 'gentle_sway', expr: 'happy'),
  'gentle_nod': BehaviorDef(id: 'gentle_nod', kind: 'combat', contexts: {'wilds_calmed'}, clip: 'tilt_then_lean', expr: 'happy'),
};
