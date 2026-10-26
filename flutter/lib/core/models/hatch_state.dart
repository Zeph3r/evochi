// The Hatching Nook and the eggs (docs: Evochi Hatching Nook & Companion Collection design bible): every
// egg is one durable instance from the day it is found or chosen to the day it hatches, in one of five
// states (owned in the collection, incubating in a cradle, ready, hatched), with its own step ledger so
// a day's walking counts once however often the steps sync. The nook's cradle count is a progression
// choice, never a cap on the eggs you may keep.

Map<String, dynamic> _m(dynamic v) => v is Map ? v.cast<String, dynamic>() : <String, dynamic>{};
List<dynamic> _l(dynamic v) => v is List ? v : const [];
int _i(dynamic v, [int d = 0]) => v == null ? d : (v as num).toInt();

class Egg {
  Egg({
    required this.id,
    required this.templateId,
    required this.origin,
    required this.acquiredAt,
    this.state = 'owned',
    this.slot,
    this.assignedDay,
    this.progress = 0,
    Map<String, int>? stepsAwarded,
    Set<String>? careDays,
    this.hatchedPetId,
    this.hatchedAt,
  })  : stepsAwarded = stepsAwarded ?? {},
        careDays = careDays ?? {};
  final String id;
  final String templateId;
  final String origin; // where it came from, in words ("Found in the Sunlit Thicket", "Chosen at the Caravan")
  final int acquiredAt;
  String state; // owned | incubating | ready | hatched
  int? slot; // the cradle it sits in while incubating or ready
  String? assignedDay; // the day it went into a cradle (steps count from then)
  int progress; // steps toward hatching (plus care), never reset
  final Map<String, int> stepsAwarded; // day -> the steps already counted from it
  final Set<String> careDays; // days it was given care
  String? hatchedPetId;
  int? hatchedAt;

  bool get inCradle => state == 'incubating' || state == 'ready';

  factory Egg.fromJson(Map<String, dynamic> j) => Egg(
        id: j['id'] as String,
        templateId: j['templateId'] as String,
        origin: (j['origin'] as String?) ?? '',
        acquiredAt: _i(j['acquiredAt']),
        state: (j['state'] as String?) ?? 'owned',
        slot: j['slot'] == null ? null : _i(j['slot']),
        assignedDay: j['assignedDay'] as String?,
        progress: _i(j['progress']),
        stepsAwarded: _m(j['stepsAwarded']).map((k, v) => MapEntry(k, _i(v))),
        careDays: _l(j['careDays']).cast<String>().toSet(),
        hatchedPetId: j['hatchedPetId'] as String?,
        hatchedAt: j['hatchedAt'] == null ? null : _i(j['hatchedAt']),
      );
  Map<String, dynamic> toJson() => {
        'id': id,
        'templateId': templateId,
        'origin': origin,
        'acquiredAt': acquiredAt,
        'state': state,
        if (slot != null) 'slot': slot,
        if (assignedDay != null) 'assignedDay': assignedDay,
        'progress': progress,
        'stepsAwarded': stepsAwarded,
        'careDays': careDays.toList(),
        if (hatchedPetId != null) 'hatchedPetId': hatchedPetId,
        if (hatchedAt != null) 'hatchedAt': hatchedAt,
      };
}

class HatchState {
  HatchState({List<Egg>? eggs, this.slots = 1, Map<String, int>? found, this.hatched = 0})
      : eggs = eggs ?? [],
        found = found ?? {};
  final List<Egg> eggs;
  int slots; // cradles in the nook
  final Map<String, int> found; // day -> eggs found out in the world that day (a gentle cap)
  int hatched; // how many have hatched, ever

  factory HatchState.fromJson(dynamic v) {
    final j = _m(v);
    return HatchState(
      eggs: _l(j['eggs']).map((e) => Egg.fromJson(_m(e))).toList(),
      slots: _i(j['slots'], 1),
      found: _m(j['found']).map((k, v) => MapEntry(k, _i(v))),
      hatched: _i(j['hatched']),
    );
  }
  Map<String, dynamic> toJson() => {'eggs': eggs.map((e) => e.toJson()).toList(), 'slots': slots, 'found': found, 'hatched': hatched};
}
