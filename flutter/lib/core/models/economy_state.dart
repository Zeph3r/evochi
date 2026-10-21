// The economy in the save: Evochi Plus, the Season Pass, the Starlight Caravan's daily deals, effects a
// rare item has armed for later (a Golden Acorn on the next chest, a Wayfinder Compass on the next
// discovery, a Hollow Ward on the next Wilds run), one-time offers and Play purchases.
//
// Balances are not stored here: Glimmer lives in the wallet ledger (WalletTxn currency 'glimmer') next to
// EvoCoins, so every earn and spend has a unique id and can never apply twice. Old saves without an
// economy object start a fresh one.

const int economySchemaVersion = 1;

int _i(dynamic v, [int d = 0]) => v == null ? d : (v as num).toInt();
Map<String, dynamic> _m(dynamic v) => v is Map ? v.cast<String, dynamic>() : <String, dynamic>{};
List<dynamic> _l(dynamic v) => v is List ? v : const [];

/// Evochi Plus membership. [until] is when the current paid period ends (0 = never a member).
class PlusState {
  PlusState({this.until = 0, this.since = 0, this.product = '', this.lastDaily = '', this.welcomed = false, Map<String, String>? picks, this.test = false})
      : picks = picks ?? {};
  int until;
  int since;
  String product; // plus_monthly | plus_yearly | test
  String lastDaily; // day key of the last daily Glimmer claim
  bool welcomed; // the joining bonus was paid
  final Map<String, String> picks; // Plus Wardrobe: month key (2026-10) -> the cosmetic picked
  bool test; // a playtest membership from the developer tools, never a real one

  factory PlusState.fromJson(Map<String, dynamic> j) => PlusState(
        until: _i(j['until']),
        since: _i(j['since']),
        product: (j['product'] as String?) ?? '',
        lastDaily: (j['lastDaily'] as String?) ?? '',
        welcomed: j['welcomed'] == true,
        picks: _m(j['picks']).map((k, v) => MapEntry(k, v as String)),
        test: j['test'] == true,
      );

  Map<String, dynamic> toJson() =>
      {'until': until, 'since': since, 'product': product, 'lastDaily': lastDaily, 'welcomed': welcomed, 'picks': picks, 'test': test};
}

/// One season's progress: XP awarded for events (steps are counted live from the step samples), the
/// premium track, and the tiers claimed on each track.
class SeasonProgress {
  SeasonProgress({Map<String, int>? awards, this.premium = false, this.boughtTiers = 0, List<int>? free, List<int>? paid})
      : awards = awards ?? {},
        free = free ?? [],
        paid = paid ?? [];
  final Map<String, int> awards; // award id (goal:2026-10-21, boss:2026-10-21, weekly:2026-W43) -> XP
  bool premium;
  int boughtTiers; // tiers bought with Glimmer (each worth one tier of XP)
  final List<int> free; // claimed tiers on the free track
  final List<int> paid; // claimed tiers on the premium track

  factory SeasonProgress.fromJson(Map<String, dynamic> j) => SeasonProgress(
        awards: _m(j['awards']).map((k, v) => MapEntry(k, _i(v))),
        premium: j['premium'] == true,
        boughtTiers: _i(j['boughtTiers']),
        free: _l(j['free']).map((e) => _i(e)).toList(),
        paid: _l(j['paid']).map((e) => _i(e)).toList(),
      );

  Map<String, dynamic> toJson() => {'awards': awards, 'premium': premium, 'boughtTiers': boughtTiers, 'free': free, 'paid': paid};
}

/// A completed Google Play purchase and what it granted (the order id makes the grant one-time).
class PlayPurchase {
  PlayPurchase({required this.orderId, required this.product, required this.at, this.token = '', this.state = 'granted'});
  final String orderId;
  final String product;
  final int at;
  final String token;
  String state; // granted | refunded

  factory PlayPurchase.fromJson(Map<String, dynamic> j) => PlayPurchase(
        orderId: (j['orderId'] as String?) ?? '',
        product: (j['product'] as String?) ?? '',
        at: _i(j['at']),
        token: (j['token'] as String?) ?? '',
        state: (j['state'] as String?) ?? 'granted',
      );

  Map<String, dynamic> toJson() => {'orderId': orderId, 'product': product, 'at': at, 'token': token, 'state': state};
}

class EconomyState {
  EconomyState({
    this.version = economySchemaVersion,
    PlusState? plus,
    Map<String, SeasonProgress>? seasons,
    Map<String, int>? armed,
    Map<String, int>? offers,
    List<PlayPurchase>? purchases,
    this.caravanMet = false,
  })  : plus = plus ?? PlusState(),
        seasons = seasons ?? {},
        armed = armed ?? {},
        offers = offers ?? {},
        purchases = purchases ?? [];

  int version;
  final PlusState plus;
  final Map<String, SeasonProgress> seasons; // season id -> progress
  final Map<String, int> armed; // golden_acorn | wayfinder_compass | hollow_ward -> charges waiting
  final Map<String, int> offers; // one-time offers bought (starter_pack) -> when
  final List<PlayPurchase> purchases;
  bool caravanMet; // the merchant's introduction was seen

  SeasonProgress season(String id) => seasons.putIfAbsent(id, () => SeasonProgress());

  factory EconomyState.fromJson(dynamic raw) {
    if (raw is! Map) return EconomyState();
    final j = raw.cast<String, dynamic>();
    return EconomyState(
      version: _i(j['schemaVersion'], economySchemaVersion),
      plus: PlusState.fromJson(_m(j['plus'])),
      seasons: _m(j['seasons']).map((k, v) => MapEntry(k, SeasonProgress.fromJson(_m(v)))),
      armed: _m(j['armed']).map((k, v) => MapEntry(k, _i(v))),
      offers: _m(j['offers']).map((k, v) => MapEntry(k, _i(v))),
      purchases: _l(j['purchases']).map((e) => PlayPurchase.fromJson(_m(e))).toList(),
      caravanMet: j['caravanMet'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
        'schemaVersion': version,
        'plus': plus.toJson(),
        'seasons': seasons.map((k, v) => MapEntry(k, v.toJson())),
        'armed': armed,
        'offers': offers,
        'purchases': purchases.map((e) => e.toJson()).toList(),
        'caravanMet': caravanMet,
      };
}
