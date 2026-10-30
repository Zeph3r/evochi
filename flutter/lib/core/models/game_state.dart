// Game-state contracts (style guide §22). Every persisted state carries a schema version.
// JSON keys match the web build so saves are portable between the two clients.

import 'dart:convert';

import 'economy_state.dart';
import 'home_state.dart';
import 'story_state.dart';
import 'hatch_state.dart';
import 'mining_state.dart';
import 'trails_state.dart';
import '../../game/personality/personality.dart';

export 'home_state.dart';
export 'story_state.dart';
export 'hatch_state.dart';
export 'mining_state.dart';
export 'trails_state.dart';

const int schemaVersion = 1;

int _i(dynamic v, [int d = 0]) => v == null ? d : (v as num).toInt();
String? _s(dynamic v) => v as String?;
Map<String, dynamic> _m(dynamic v) => v == null ? <String, dynamic>{} : (v as Map).cast<String, dynamic>();
List<dynamic> _l(dynamic v) => v == null ? const [] : v as List;

class StepSample {
  StepSample({required this.id, required this.source, required this.start, required this.end, required this.count, this.manual = false});
  final String id;
  final String source;
  final int start;
  final int end;
  int count;
  final bool manual;

  factory StepSample.fromJson(Map<String, dynamic> j) => StepSample(
        id: j['id'] as String,
        source: (j['source'] as String?) ?? 'unknown',
        start: _i(j['start']),
        end: _i(j['end'] ?? j['start']),
        count: _i(j['count']),
        manual: j['manual'] == true,
      );
  Map<String, dynamic> toJson() => {'id': id, 'source': source, 'start': start, 'end': end, 'count': count, 'manual': manual};
}

class StepsState {
  StepsState({List<StepSample>? samples, this.connection = 'none', this.syncedUntil = 0, this.lastSync, this.lastSource, this.lastError})
      : samples = samples ?? [];
  List<StepSample> samples;
  String connection; // health | demo | manual | none
  int syncedUntil;
  int? lastSync;
  String? lastSource;
  int? lastError;

  factory StepsState.fromJson(Map<String, dynamic> j) => StepsState(
        samples: _l(j['samples']).map((e) => StepSample.fromJson(_m(e))).toList(),
        connection: (j['connection'] as String?) ?? 'none',
        syncedUntil: _i(j['syncedUntil']),
        lastSync: j['lastSync'] == null ? null : _i(j['lastSync']),
        lastSource: _s(j['lastSource']),
        lastError: j['lastError'] == null ? null : _i(j['lastError']),
      );
  Map<String, dynamic> toJson() => {
        'samples': samples.map((e) => e.toJson()).toList(),
        'connection': connection,
        'syncedUntil': syncedUntil,
        'lastSync': lastSync,
        'lastSource': lastSource,
        'lastError': lastError,
      };
}

class WalletTxn {
  WalletTxn({required this.id, required this.amount, required this.cause, required this.at, this.currency = 'evocoin'});
  final String id;
  final int amount;
  final String currency;
  final String cause;
  final int at;
  factory WalletTxn.fromJson(Map<String, dynamic> j) =>
      WalletTxn(id: j['id'] as String, amount: _i(j['amount']), currency: (j['currency'] as String?) ?? 'evocoin', cause: (j['cause'] as String?) ?? '', at: _i(j['at']));
  Map<String, dynamic> toJson() => {'id': id, 'amount': amount, 'currency': currency, 'cause': cause, 'at': at};
}

class Acquisition {
  Acquisition({required this.at, required this.source, required this.qty, this.txnId});
  final int at;
  final String source;
  final int qty;
  final String? txnId;
  factory Acquisition.fromJson(Map<String, dynamic> j) => Acquisition(at: _i(j['at']), source: (j['source'] as String?) ?? '', qty: _i(j['qty'], 1), txnId: _s(j['txnId']));
  Map<String, dynamic> toJson() => {'at': at, 'source': source, 'qty': qty, 'txnId': txnId};
}

class Ownership {
  Ownership({this.quantity = 0, List<Acquisition>? acquisitions}) : acquisitions = acquisitions ?? [];
  int quantity;
  final List<Acquisition> acquisitions;
  factory Ownership.fromJson(Map<String, dynamic> j) =>
      Ownership(quantity: _i(j['quantity']), acquisitions: _l(j['acquisitions']).map((e) => Acquisition.fromJson(_m(e))).toList());
  Map<String, dynamic> toJson() => {'quantity': quantity, 'acquisitions': acquisitions.map((e) => e.toJson()).toList()};
}

class Settings {
  Settings({
    this.sound = true,
    this.music = true,
    this.haptics = true,
    this.reducedMotion = false,
    this.notifications = false,
    this.quietStart = 21,
    this.quietEnd = 8,
    this.analytics = false,
    this.roomLitVillagers = false,
    this.largeText = false,
    this.devTools = false,
  });
  bool sound;
  bool music;
  bool haptics;
  bool reducedMotion;
  bool notifications;
  int quietStart;
  int quietEnd;
  bool analytics;
  // villagers lit by each room's lanterns and windows; off, they are drawn flat like the Evochi (the
  // default since the walkable village; the old 'classicVillagers' key is left behind on purpose)
  bool roomLitVillagers;
  bool largeText; // bigger labels, descriptions and item text everywhere
  // the step simulator and playtest shortcuts (off by default here: the app reads real health data;
  // the web preview defaults it on)
  bool devTools;
  factory Settings.fromJson(Map<String, dynamic> j) => Settings(
        sound: j['sound'] != false,
        music: j['music'] != false,
        haptics: j['haptics'] != false,
        reducedMotion: j['reducedMotion'] == true,
        notifications: j['notifications'] == true,
        quietStart: _i(j['quietStart'], 21),
        quietEnd: _i(j['quietEnd'], 8),
        analytics: j['analytics'] == true,
        roomLitVillagers: j['roomLitVillagers'] == true,
        largeText: j['largeText'] == true,
        devTools: j['devTools'] == true,
      );
  Map<String, dynamic> toJson() => {
        'sound': sound,
        'music': music,
        'haptics': haptics,
        'reducedMotion': reducedMotion,
        'notifications': notifications,
        'quietStart': quietStart,
        'quietEnd': quietEnd,
        'analytics': analytics,
        'roomLitVillagers': roomLitVillagers,
        'largeText': largeText,
        'devTools': devTools,
      };
}

class GoalChange {
  GoalChange(this.from, this.goal);
  final String from;
  final int goal;
  factory GoalChange.fromJson(Map<String, dynamic> j) => GoalChange(j['from'] as String, _i(j['goal']));
  Map<String, dynamic> toJson() => {'from': from, 'goal': goal};
}

class Player {
  Player({
    required this.id,
    required this.accountType,
    required this.timezone,
    required this.createdAt,
    required this.goal,
    this.email,
    List<GoalChange>? goalHistory,
    Settings? settings,
  })  : goalHistory = goalHistory ?? [],
        settings = settings ?? Settings();
  final String id;
  String accountType; // guest | email | apple | google
  String? email;
  String timezone;
  final int createdAt;
  int goal;
  List<GoalChange> goalHistory;
  Settings settings;
  factory Player.fromJson(Map<String, dynamic> j) => Player(
        id: j['id'] as String,
        accountType: (j['accountType'] as String?) ?? 'guest',
        email: _s(j['email']),
        timezone: (j['timezone'] as String?) ?? 'UTC',
        createdAt: _i(j['createdAt']),
        goal: _i(j['goal'], 7000),
        goalHistory: _l(j['goalHistory']).map((e) => GoalChange.fromJson(_m(e))).toList(),
        settings: Settings.fromJson(_m(j['settings'])),
      );
  Map<String, dynamic> toJson() => {
        'id': id,
        'accountType': accountType,
        'email': email,
        'timezone': timezone,
        'createdAt': createdAt,
        'goal': goal,
        'goalHistory': goalHistory.map((e) => e.toJson()).toList(),
        'settings': settings.toJson(),
      };
}

class PetEvent {
  PetEvent({required this.t, required this.type, required this.amount, this.itemId, this.recovery = false, this.via});
  final int t;
  final String type; // care | revive
  final int amount;
  final String? itemId;
  final bool recovery;
  final String? via;
  factory PetEvent.fromJson(Map<String, dynamic> j) => PetEvent(
      t: _i(j['t']), type: j['type'] as String, amount: _i(j['amount']), itemId: _s(j['itemId']), recovery: j['recovery'] == true, via: _s(j['via']));
  Map<String, dynamic> toJson() => {'t': t, 'type': type, 'amount': amount, 'itemId': itemId, 'recovery': recovery, 'via': via};
}

class BondEvent {
  BondEvent({required this.key, required this.type, required this.t});
  final String key;
  final String type; // pet | play | goal
  final int t;
  factory BondEvent.fromJson(Map<String, dynamic> j) => BondEvent(key: j['key'] as String, type: j['type'] as String, t: _i(j['t']));
  Map<String, dynamic> toJson() => {'key': key, 'type': type, 't': t};
}

class Pet {
  Pet({
    required this.id,
    required this.requestId,
    required this.name,
    required this.paletteId,
    required this.stage,
    required this.habitatId,
    required this.createdAt,
    required this.createdDay,
    this.speciesId = 'lizard',
    this.origin,
    Map<String, int>? xpAwarded,
    List<PetEvent>? events,
    List<BondEvent>? bondEvents,
    List<Map<String, int>>? evolutions,
    Map<String, String>? equipped,
    Personality? personality,
  })  : xpAwarded = xpAwarded ?? {},
        events = events ?? [],
        bondEvents = bondEvents ?? [],
        evolutions = evolutions ?? [],
        equipped = equipped ?? {},
        // an Evochi from before personalities gets one, once, from its own id (saved with it from then on)
        personality = personality ?? migratePersonality(id);
  final String id;
  final String? requestId;
  final String speciesId;
  final String? origin; // where it came from, in words (an egg's provenance), null for the first Evochi
  String name;
  final String paletteId;
  int stage;
  String habitatId;
  final int createdAt;
  final String createdDay;
  final Map<String, int> xpAwarded;
  final List<PetEvent> events;
  final List<BondEvent> bondEvents;
  final List<Map<String, int>> evolutions;
  final Map<String, String> equipped;

  /// who it is (game/personality): made when it hatched, kept for life, through evolution
  final Personality personality;

  factory Pet.fromJson(Map<String, dynamic> j) => Pet(
        id: j['id'] as String,
        requestId: _s(j['requestId']),
        speciesId: (j['speciesId'] as String?) ?? 'lizard',
        origin: j['origin'] as String?,
        name: j['name'] as String,
        paletteId: j['paletteId'] as String,
        stage: _i(j['stage'], 1),
        habitatId: (j['habitatId'] as String?) ?? 'sunlit_meadow',
        createdAt: _i(j['createdAt']),
        createdDay: j['createdDay'] as String,
        xpAwarded: _m(j['xpAwarded']).map((k, v) => MapEntry(k, _i(v))),
        events: _l(j['events']).map((e) => PetEvent.fromJson(_m(e))).toList(),
        bondEvents: _l(j['bondEvents']).map((e) => BondEvent.fromJson(_m(e))).toList(),
        evolutions: _l(j['evolutions']).map((e) => _m(e).map((k, v) => MapEntry(k, _i(v)))).toList(),
        equipped: _m(j['equipped']).map((k, v) => MapEntry(k, v as String)),
        personality: j['personality'] is Map ? Personality.fromJson(_m(j['personality'])) : null,
      );
  Map<String, dynamic> toJson() => {
        'id': id,
        'requestId': requestId,
        'speciesId': speciesId,
        if (origin != null) 'origin': origin,
        'name': name,
        'paletteId': paletteId,
        'stage': stage,
        'habitatId': habitatId,
        'createdAt': createdAt,
        'createdDay': createdDay,
        'xpAwarded': xpAwarded,
        'events': events.map((e) => e.toJson()).toList(),
        'bondEvents': bondEvents.map((e) => e.toJson()).toList(),
        'evolutions': evolutions,
        'equipped': equipped,
        'personality': personality.toJson(),
      };
}

class PastPet {
  PastPet({
    required this.id,
    required this.name,
    required this.paletteId,
    required this.stage,
    required this.peakLevel,
    required this.createdAt,
    required this.endedAt,
    required this.daysTogether,
    required this.lifetimeSteps,
  });
  final String id;
  final String name;
  final String paletteId;
  final int stage;
  final int peakLevel;
  final int createdAt;
  final int endedAt;
  final int daysTogether;
  final int lifetimeSteps;
  factory PastPet.fromJson(Map<String, dynamic> j) => PastPet(
        id: j['id'] as String,
        name: j['name'] as String,
        paletteId: j['paletteId'] as String,
        stage: _i(j['stage'], 1),
        peakLevel: _i(j['peakLevel'], 1),
        createdAt: _i(j['createdAt']),
        endedAt: _i(j['endedAt']),
        daysTogether: _i(j['daysTogether']),
        lifetimeSteps: _i(j['lifetimeSteps']),
      );
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'paletteId': paletteId,
        'stage': stage,
        'peakLevel': peakLevel,
        'createdAt': createdAt,
        'endedAt': endedAt,
        'daysTogether': daysTogether,
        'lifetimeSteps': lifetimeSteps,
      };
}

class Onboarding {
  Onboarding({this.step = 'welcome', this.draftName = '', this.draftPalette = 'amber', this.requestId});
  String step; // welcome | create | connect | goal | awakening | done
  String draftName;
  String draftPalette;
  String? requestId;
  factory Onboarding.fromJson(Map<String, dynamic> j) {
    final d = _m(j['draft']);
    return Onboarding(
      step: (j['step'] as String?) ?? 'welcome',
      draftName: (d['name'] as String?) ?? '',
      draftPalette: (d['paletteId'] as String?) ?? 'amber',
      requestId: _s(j['requestId']),
    );
  }
  Map<String, dynamic> toJson() => {
        'step': step,
        'draft': {'name': draftName, 'paletteId': draftPalette, 'habitatId': 'sunlit_meadow'},
        'requestId': requestId,
      };
}

class GameState {
  GameState({
    required this.createdAt,
    required this.tzHint,
    this.player,
    Onboarding? onboarding,
    this.pet,
    List<PastPet>? pastPets,
    StepsState? steps,
    List<WalletTxn>? txns,
    Map<String, Ownership>? inventory,
    Map<String, Map<String, dynamic>>? claims,
    Map<String, String>? placements,
    Map<String, int>? unlocks,
    List<Map<String, dynamic>>? audit,
    Map<String, bool>? flags,
    StoryState? story,
    HomeState? home,
    TrailsState? trails,
    EconomyState? economy,
    MiningState? mining,
    HatchState? hatch,
    List<Pet>? companions,
    this.clockOffset = 0,
    this.configVersion = '1.0.0',
    this.savedAtMs = 0,
  })  : onboarding = onboarding ?? Onboarding(),
        pastPets = pastPets ?? [],
        steps = steps ?? StepsState(),
        txns = txns ?? [],
        inventory = inventory ?? {},
        claims = claims ?? {},
        placements = placements ?? {},
        unlocks = unlocks ?? {},
        audit = audit ?? [],
        flags = flags ?? {},
        story = story ?? StoryState(),
        home = home ?? HomeState(),
        trails = trails ?? TrailsState(),
        economy = economy ?? EconomyState(),
        mining = mining ?? MiningState(),
        hatch = hatch ?? HatchState(),
        companions = companions ?? [];

  Player? player;
  Onboarding onboarding;
  Pet? pet;
  final List<PastPet> pastPets;
  final StepsState steps;
  final List<WalletTxn> txns;
  final Map<String, Ownership> inventory;
  final Map<String, Map<String, dynamic>> claims;
  final Map<String, String> placements;
  final Map<String, int> unlocks;
  List<Map<String, dynamic>> audit;
  final Map<String, bool> flags;
  final StoryState story; // Village Tales: account-level, survives pets (see story_state.dart)
  final HomeState home; // Home Tales: garden, skills, starter gift; account-level too (home_state.dart)
  final TrailsState trails; // Lumen Trails: discoveries, guild XP, companions, the live encounter (trails_state.dart)
  final EconomyState economy; // Plus, the Season Pass, the Caravan, armed rare items, Play purchases (economy_state.dart)
  final MiningState mining; // mining gear and the loadout worn on the trail and in the mines (mining_state.dart)
  final HatchState hatch; // the Hatching Nook's eggs and cradles (hatch_state.dart)
  final List<Pet> companions; // the Evochis resting while another is active: each keeps its growth, bond and gear
  int clockOffset; // playtest tools only
  final int createdAt;
  String tzHint;
  String configVersion;
  int savedAtMs;

  factory GameState.fresh(int now, String tz) => GameState(createdAt: now, tzHint: tz);

  factory GameState.fromJson(Map<String, dynamic> j) {
    final nest = _m(j['nest']);
    final s = GameState(
      createdAt: _i(j['createdAt']),
      tzHint: (j['tzHint'] as String?) ?? 'UTC',
      player: j['player'] == null ? null : Player.fromJson(_m(j['player'])),
      onboarding: Onboarding.fromJson(_m(j['onboarding'])),
      pet: j['pet'] == null ? null : Pet.fromJson(_m(j['pet'])),
      pastPets: _l(j['pastPets']).map((e) => PastPet.fromJson(_m(e))).toList(),
      steps: StepsState.fromJson(_m(j['steps'])),
      txns: _l(_m(j['wallet'])['txns']).map((e) => WalletTxn.fromJson(_m(e))).toList(),
      inventory: _m(j['inventory']).map((k, v) => MapEntry(k, Ownership.fromJson(_m(v)))),
      claims: _m(j['claims']).map((k, v) => MapEntry(k, _m(v))),
      placements: _m(nest['placements']).map((k, v) => MapEntry(k, v as String)),
      unlocks: _m(j['unlocks']).map((k, v) => MapEntry(k, _i(v))),
      audit: _l(j['audit']).map((e) => _m(e)).toList(),
      flags: _m(j['flags']).map((k, v) => MapEntry(k, v == true)),
      story: StoryState.fromJson(j['story']),
      home: HomeState.fromJson(j['home']),
      trails: TrailsState.fromJson(j['trails']),
      economy: EconomyState.fromJson(j['economy']),
      mining: MiningState.fromJson(j['mining']),
      hatch: HatchState.fromJson(j['hatch']),
      companions: _l(j['companions']).map((e) => Pet.fromJson(_m(e))).toList(),
      clockOffset: _i(_m(j['debug'])['clockOffset']),
      configVersion: (j['configVersion'] as String?) ?? '1.0.0',
      savedAtMs: _i(j['savedAtMs']),
    );
    // saves from before the Developer tools switch that already walk with the simulated step device
    // keep their step simulator
    final pl = s.player;
    if (pl != null && !_m(_m(j['player'])['settings']).containsKey('devTools') && s.steps.connection == 'demo') pl.settings.devTools = true;
    return s;
  }

  Map<String, dynamic> toJson() => {
        'schema': schemaVersion,
        'configVersion': configVersion,
        'player': player?.toJson(),
        'onboarding': onboarding.toJson(),
        'pet': pet?.toJson(),
        'pastPets': pastPets.map((e) => e.toJson()).toList(),
        'steps': steps.toJson(),
        'wallet': {'txns': txns.map((e) => e.toJson()).toList()},
        'inventory': inventory.map((k, v) => MapEntry(k, v.toJson())),
        'claims': claims,
        'nest': {'habitatId': 'sunlit_meadow', 'placements': placements},
        'unlocks': unlocks,
        'audit': audit,
        'flags': flags,
        'story': story.toJson(),
        'home': home.toJson(),
        'trails': trails.toJson(),
        'economy': economy.toJson(),
        'mining': mining.toJson(),
        'hatch': hatch.toJson(),
        'companions': companions.map((e) => e.toJson()).toList(),
        'debug': {'clockOffset': clockOffset},
        'tzHint': tzHint,
        'createdAt': createdAt,
        'savedAtMs': savedAtMs,
      };

  /// Deep copy (actions never mutate the state they were given).
  GameState copy() => GameState.fromJson((jsonDecode(jsonEncode(toJson())) as Map).cast<String, dynamic>());

  String serialize() => jsonEncode(toJson());

  /// Parses a save; returns null for unknown or newer schemas (never crash on load).
  static GameState? tryParse(String? text) {
    if (text == null || text.isEmpty) return null;
    try {
      final j = (jsonDecode(text) as Map).cast<String, dynamic>();
      final schema = _i(j['schema']);
      if (schema < 1 || schema > schemaVersion) return null;
      return GameState.fromJson(j);
    } catch (_) {
      return null;
    }
  }
}
