// Village Tales story state (Quest Bible v1.0 §9). It belongs to the player account, not to a pet:
// it survives memorials, new pets, colourway changes and evolution. JSON keys match the web build
// (`state.story`) so saves stay portable between the two clients.

const int storySchemaVersion = 1;

int _i(dynamic v, [int d = 0]) => v == null ? d : (v as num).toInt();
Map<String, dynamic> _m(dynamic v) => v == null ? <String, dynamic>{} : (v as Map).cast<String, dynamic>();
List<dynamic> _l(dynamic v) => v == null ? const [] : v as List;

const defaultStoryFlags = {
  'lamp_lit': false,
  'waystone_revealed': false,
  'waystone_restored': false,
  'cottage_restored': false, // Home Tales: opens the Kitchen
  'apothecary_unlocked': false, // Home Tales: opens the Apothecary
};

class QuestState {
  QuestState({
    required this.phase,
    required this.acceptedAt,
    required this.acceptedDay,
    required this.resolvedSteps,
    Map<String, int>? dayProgress,
    this.freshTotal = 0,
    this.tracked = true,
    this.completedAt,
    this.seenCompletion = false,
    this.readyAt,
  }) : dayProgress = dayProgress ?? {};

  String phase;
  final int acceptedAt;
  final String acceptedDay;
  final int resolvedSteps; // frozen at acceptance: min(nominal, personal goal); 0 for walk-less quests
  final Map<String, int> dayProgress; // local day -> steps after acceptance (max, never lowered)
  int freshTotal;
  bool tracked;
  int? completedAt;
  bool seenCompletion;
  int? readyAt;

  factory QuestState.fromJson(Map<String, dynamic> j) => QuestState(
        phase: j['phase'] as String,
        acceptedAt: _i(j['acceptedAt']),
        acceptedDay: (j['acceptedDay'] as String?) ?? '',
        resolvedSteps: _i(j['resolvedSteps']),
        dayProgress: _m(j['dayProgress']).map((k, v) => MapEntry(k, _i(v))),
        freshTotal: _i(j['freshTotal']),
        tracked: j['tracked'] != false,
        completedAt: j['completedAt'] == null ? null : _i(j['completedAt']),
        seenCompletion: j['seenCompletion'] == true,
        readyAt: j['readyAt'] == null ? null : _i(j['readyAt']),
      );

  Map<String, dynamic> toJson() => {
        'phase': phase,
        'acceptedAt': acceptedAt,
        'acceptedDay': acceptedDay,
        'resolvedSteps': resolvedSteps,
        'dayProgress': dayProgress,
        'freshTotal': freshTotal,
        'tracked': tracked,
        'completedAt': completedAt,
        'seenCompletion': seenCompletion,
        if (readyAt != null) 'readyAt': readyAt,
      };
}

class StoryState {
  StoryState({
    this.schemaVersion = storySchemaVersion,
    this.activeQuestId,
    Map<String, QuestState>? questStates,
    Map<String, int>? questPouch,
    Map<String, List<String>>? qualifiedDayKeys,
    List<String>? claimedRewards,
    Map<String, bool>? flags,
    List<String>? titleUnlocks,
    Map<String, bool>? npcsMet,
    Map<String, bool>? offersSeen,
    this.peakLevel = 1,
  })  : questStates = questStates ?? {},
        questPouch = questPouch ?? {},
        qualifiedDayKeys = qualifiedDayKeys ?? {},
        claimedRewards = claimedRewards ?? [],
        flags = {...defaultStoryFlags, ...?flags},
        titleUnlocks = titleUnlocks ?? [],
        npcsMet = npcsMet ?? {},
        offersSeen = offersSeen ?? {};

  int schemaVersion;
  String? activeQuestId;
  final Map<String, QuestState> questStates;
  final Map<String, int> questPouch; // quest materials only (never catalog items)
  final Map<String, List<String>> qualifiedDayKeys; // multi-day quests: distinct local days that counted
  final List<String> claimedRewards; // quest ids whose rewards were paid (exactly once)
  final Map<String, bool> flags;
  final List<String> titleUnlocks;
  final Map<String, bool> npcsMet;
  final Map<String, bool> offersSeen;
  int peakLevel; // highest level any Evochi on this account reached (story gates never go backwards)

  /// Old saves have no story object: they start a fresh one.
  factory StoryState.fromJson(dynamic raw) {
    if (raw is! Map) return StoryState();
    final j = raw.cast<String, dynamic>();
    return StoryState(
      schemaVersion: _i(j['schemaVersion'], storySchemaVersion),
      activeQuestId: j['activeQuestId'] as String?,
      questStates: _m(j['questStates']).map((k, v) => MapEntry(k, QuestState.fromJson(_m(v)))),
      questPouch: _m(j['questPouch']).map((k, v) => MapEntry(k, _i(v))),
      qualifiedDayKeys: _m(j['qualifiedDayKeys']).map((k, v) => MapEntry(k, _l(v).cast<String>().toList())),
      claimedRewards: _l(j['claimedRewards']).cast<String>().toList(),
      flags: _m(j['flags']).map((k, v) => MapEntry(k, v == true)),
      titleUnlocks: _l(j['titleUnlocks']).cast<String>().toList(),
      npcsMet: _m(j['npcsMet']).map((k, v) => MapEntry(k, v == true)),
      offersSeen: _m(j['offersSeen']).map((k, v) => MapEntry(k, v == true)),
      peakLevel: _i(j['peakLevel'], 1),
    );
  }

  Map<String, dynamic> toJson() => {
        'schemaVersion': schemaVersion,
        'activeQuestId': activeQuestId,
        'questStates': questStates.map((k, v) => MapEntry(k, v.toJson())),
        'questPouch': questPouch,
        'qualifiedDayKeys': qualifiedDayKeys,
        'claimedRewards': claimedRewards,
        'flags': flags,
        'titleUnlocks': titleUnlocks,
        'npcsMet': npcsMet,
        'offersSeen': offersSeen,
        'peakLevel': peakLevel,
      };
}
