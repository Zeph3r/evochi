// Home Tales state: the garden beds, the three Cozy Skills, the starter-seed gift and a few counters.
// Like the story it belongs to the player account, not to one Evochi: beds, skill XP and recipes
// survive memorials and new pets. JSON keys match the web build (`state.home`), so saves stay
// portable between the two clients. Old saves without a home object start a fresh one.

const int homeSchemaVersion = 1;

int _i(dynamic v, [int d = 0]) => v == null ? d : (v as num).toInt();
Map<String, dynamic> _m(dynamic v) => v is Map ? v.cast<String, dynamic>() : <String, dynamic>{};

/// Every garden bed, in order (p4 opens at Farming Lv 4).
const homePlotIds = ['p1', 'p2', 'p3', 'p4'];
const defaultHomeSkills = {'farming': 0, 'cooking': 0, 'alchemy': 0};
const defaultHomeCounts = {'harvests': 0, 'cooked': 0, 'brewed': 0, 'perfect': 0};

/// One planted bed.
class PlotState {
  PlotState({required this.crop, required this.plantedAt, this.watered = false, this.tonic = false, this.boost = 0, this.dew = false});
  final String crop;
  final int plantedAt;
  bool watered; // optional watering, once per planting
  bool tonic; // a Sprout Tonic was poured on it (once per planting)
  double boost; // growing time added by rare finds: a Sunstone (1.0), Moonwell Dew (0.25)
  bool dew; // Moonwell Dew reached this bed (once per planting)

  factory PlotState.fromJson(Map<String, dynamic> j) => PlotState(
        crop: j['crop'] as String,
        plantedAt: _i(j['plantedAt']),
        watered: j['watered'] == true,
        tonic: j['tonic'] == true,
        boost: (j['boost'] as num?)?.toDouble() ?? 0,
        dew: j['dew'] == true,
      );

  Map<String, dynamic> toJson() => {'crop': crop, 'plantedAt': plantedAt, 'watered': watered, 'tonic': tonic, if (boost > 0) 'boost': boost, if (dew) 'dew': dew};
}

class HomeState {
  HomeState({
    this.version = homeSchemaVersion,
    Map<String, PlotState?>? plots,
    Map<String, int>? skills,
    this.starterSeeds = false,
    Map<String, int>? counts,
    Map<String, bool>? seen,
  })  : plots = <String, PlotState?>{for (final id in homePlotIds) id: null, ...?plots},
        skills = <String, int>{...defaultHomeSkills, ...?skills},
        counts = <String, int>{...defaultHomeCounts, ...?counts},
        seen = seen ?? <String, bool>{};

  int version; // JSON 'schemaVersion'
  final Map<String, PlotState?> plots; // bed id -> what's growing (null = empty)
  final Map<String, int> skills; // farming | cooking | alchemy -> lifetime skill XP
  bool starterSeeds; // the first-visit seed gift was claimed (once per account)
  final Map<String, int> counts; // harvests | cooked | brewed | perfect
  final Map<String, bool> seen;

  /// Old saves have no home object: they start a fresh one. Missing keys are filled in place.
  factory HomeState.fromJson(dynamic raw) {
    if (raw is! Map) return HomeState();
    final j = raw.cast<String, dynamic>();
    return HomeState(
      version: _i(j['schemaVersion'], homeSchemaVersion),
      plots: _m(j['plots']).map<String, PlotState?>((k, v) => MapEntry(k, v is Map ? PlotState.fromJson(v.cast<String, dynamic>()) : null)),
      skills: _m(j['skills']).map<String, int>((k, v) => MapEntry(k, _i(v))),
      starterSeeds: j['starterSeeds'] == true,
      counts: _m(j['counts']).map<String, int>((k, v) => MapEntry(k, _i(v))),
      seen: _m(j['seen']).map<String, bool>((k, v) => MapEntry(k, v == true)),
    );
  }

  Map<String, dynamic> toJson() => {
        'schemaVersion': version,
        'plots': plots.map<String, dynamic>((k, v) => MapEntry(k, v?.toJson())),
        'skills': skills,
        'starterSeeds': starterSeeds,
        'counts': counts,
        'seen': seen,
      };
}
