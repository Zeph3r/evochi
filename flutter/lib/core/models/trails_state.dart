// Lumen Trails state: the Trail Guild's daily discovery boards, guild XP, companions, restored
// guardians, an old save's open encounter (until settled) and a few counters. Like the story and the home it belongs
// to the player account, not to one Evochi. JSON keys match the web build (`state.trails`), so saves
// stay portable between the two clients. Old saves without a trails object start a fresh one.

const int trailsSchemaVersion = 1;

int _i(dynamic v, [int d = 0]) => v == null ? d : (v as num).toInt();
Map<String, dynamic> _m(dynamic v) => v is Map ? v.cast<String, dynamic>() : <String, dynamic>{};
List<dynamic> _l(dynamic v) => v is List ? v : const [];

const defaultTrailStats = {'discoveries': 0, 'encounters': 0, 'befriended': 0, 'restored': 0, 'retreats': 0};

/// One discovery's progress on a given day's board.
class DiscoveryProgress {
  DiscoveryProgress({required this.acceptedAt, this.foundAt, this.walked = 0});
  final int acceptedAt; // when the walk began (steps after this count)
  int? foundAt; // inspected at its place (rewards paid)
  int walked; // frozen walking progress (never lowered by late samples)

  factory DiscoveryProgress.fromJson(Map<String, dynamic> j) => DiscoveryProgress(
        acceptedAt: _i(j['acceptedAt']),
        foundAt: j['foundAt'] == null ? null : _i(j['foundAt']),
        walked: _i(j['walked']),
      );

  Map<String, dynamic> toJson() => {'acceptedAt': acceptedAt, 'foundAt': foundAt, 'walked': walked};
}

/// One day's board: the three posted discoveries and their progress.
class TrailDay {
  TrailDay({required this.ids, Map<String, DiscoveryProgress>? states}) : states = states ?? {};
  final List<String> ids;
  final Map<String, DiscoveryProgress> states;

  factory TrailDay.fromJson(Map<String, dynamic> j) => TrailDay(
        ids: _l(j['ids']).cast<String>().toList(),
        states: _m(j['states']).map((k, v) => MapEntry(k, DiscoveryProgress.fromJson(_m(v)))),
      );

  Map<String, dynamic> toJson() => {'ids': ids, 'states': states.map((k, v) => MapEntry(k, v.toJson()))};
}

class CompanionState {
  CompanionState({required this.since, this.encounters = 0});
  final int since;
  int encounters;

  factory CompanionState.fromJson(Map<String, dynamic> j) => CompanionState(since: _i(j['since']), encounters: _i(j['encounters']));
  Map<String, dynamic> toJson() => {'since': since, 'encounters': encounters};
}

/// An encounter an old save left open (the Guild's jobs once played out on a turn-based stage; they are
/// story floors in the Deep Wilds now). Only what settling it needs is kept: whose job, whether it was won,
/// and what was offered during it (game/trails/trails.dart settleOldEncounter).
class OldEncounter {
  OldEncounter({required this.quest, required this.creature, required this.goal, required this.seed, Map<String, int>? used, this.done})
      : used = used ?? {};
  final String quest;
  final String creature;
  final String goal; // befriend | restore
  final String seed;
  final Map<String, int> used; // items offered during it
  final String? done; // 'success' if it was won

  factory OldEncounter.fromJson(Map<String, dynamic> j) => OldEncounter(
        quest: (j['quest'] as String?) ?? '',
        creature: (j['creature'] as String?) ?? '',
        goal: (j['goal'] as String?) ?? 'befriend',
        seed: (j['seed'] as String?) ?? '',
        used: _m(j['used']).map((k, v) => MapEntry(k, _i(v))),
        done: j['done'] as String?,
      );

  Map<String, dynamic> toJson() => {'quest': quest, 'creature': creature, 'goal': goal, 'seed': seed, 'used': used, 'done': done};
}

class TrailsState {
  TrailsState({
    this.version = trailsSchemaVersion,
    this.guildXp = 0,
    Map<String, TrailDay>? days,
    Map<String, CompanionState>? companions,
    Map<String, int>? restored,
    this.oldEncounter,
    Map<String, int>? attempts,
    Map<String, bool>? seen,
    Map<String, int>? stats,
  })  : days = days ?? {},
        companions = companions ?? {},
        restored = restored ?? {},
        attempts = attempts ?? {},
        seen = seen ?? {},
        stats = <String, int>{...defaultTrailStats, ...?stats};

  int version; // JSON 'schemaVersion'
  int guildXp;
  final Map<String, TrailDay> days; // dayKey -> that day's board
  final Map<String, CompanionState> companions; // creatureId -> since / encounters
  final Map<String, int> restored; // creatureId -> restored at
  OldEncounter? oldEncounter; // an old save's open encounter, until it is settled on load
  final Map<String, int> attempts; // questId -> n (old saves: the turn-based encounter's attempts)
  final Map<String, bool> seen; // one-time scenes: guild_intro
  final Map<String, int> stats; // discoveries | encounters | befriended | restored | retreats

  int stat(String k) => stats[k] ?? 0;

  /// Old saves have no trails object: they start a fresh one. Missing keys are filled in place.
  factory TrailsState.fromJson(dynamic raw) {
    if (raw is! Map) return TrailsState();
    final j = raw.cast<String, dynamic>();
    return TrailsState(
      version: _i(j['schemaVersion'], trailsSchemaVersion),
      guildXp: _i(j['guildXp']),
      days: _m(j['days']).map((k, v) => MapEntry(k, TrailDay.fromJson(_m(v)))),
      companions: _m(j['companions']).map((k, v) => MapEntry(k, CompanionState.fromJson(_m(v)))),
      restored: _m(j['restored']).map((k, v) => MapEntry(k, _i(v))),
      oldEncounter: j['encounter'] is Map ? OldEncounter.fromJson(_m(j['encounter'])) : null,
      attempts: _m(j['attempts']).map((k, v) => MapEntry(k, _i(v))),
      seen: _m(j['seen']).map((k, v) => MapEntry(k, v == true)),
      stats: _m(j['stats']).map((k, v) => MapEntry(k, _i(v))),
    );
  }

  Map<String, dynamic> toJson() => {
        'schemaVersion': version,
        'guildXp': guildXp,
        'days': days.map((k, v) => MapEntry(k, v.toJson())),
        'companions': companions.map((k, v) => MapEntry(k, v.toJson())),
        'restored': restored,
        if (oldEncounter != null) 'encounter': oldEncounter!.toJson(),
        'attempts': attempts,
        'seen': seen,
        'stats': stats,
      };
}
