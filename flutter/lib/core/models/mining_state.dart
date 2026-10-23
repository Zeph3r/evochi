// Mining in the save (MINES_PLAN.md): the mining gear you own and the loadout your Evochi wears on the Old
// Trail and in the mines. The loadout is its own set of slots, apart from the wearables: a helmet never
// takes off a hat you bought, it only covers it while you're out mining. Each piece remembers where it
// came from (who made it, where its ore was mined, its finish, its first trip) for its memory card.
// Old saves without a mining object start a fresh one.

int _i(dynamic v, [int d = 0]) => v == null ? d : (v as num).toInt();
Map<String, dynamic> _m(dynamic v) => v is Map ? v.cast<String, dynamic>() : <String, dynamic>{};
List<dynamic> _l(dynamic v) => v is List ? v : const [];

/// One piece of mining gear.
class GearPiece {
  GearPiece({required this.id, required this.def, required this.at, required this.from, this.oreFrom, this.finish, this.firstTrip});
  final String id; // unique (the purchase or forging that made it)
  final String def; // its kind (game/mining/gear.dart)
  final int at; // when you got it
  final String from; // flint (bought) | bram (forged)
  final String? oreFrom; // where its ore was mined (a map id: 'trail'), forged pieces
  final String? finish; // the finish Bram gave it
  int? firstTrip; // when it first went mining

  factory GearPiece.fromJson(Map<String, dynamic> j) => GearPiece(
        id: j['id'] as String,
        def: j['def'] as String,
        at: _i(j['at']),
        from: (j['from'] as String?) ?? 'flint',
        oreFrom: j['oreFrom'] as String?,
        finish: j['finish'] as String?,
        firstTrip: j['firstTrip'] == null ? null : _i(j['firstTrip']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'def': def,
        'at': at,
        'from': from,
        if (oreFrom != null) 'oreFrom': oreFrom,
        if (finish != null) 'finish': finish,
        if (firstTrip != null) 'firstTrip': firstTrip,
      };
}

class MiningState {
  MiningState({List<GearPiece>? gear, Map<String, String>? loadout})
      : gear = gear ?? [],
        loadout = loadout ?? {};
  final List<GearPiece> gear;
  final Map<String, String> loadout; // slot -> the piece worn there

  GearPiece? piece(String id) {
    for (final p in gear) {
      if (p.id == id) return p;
    }
    return null;
  }

  factory MiningState.fromJson(dynamic v) {
    final j = _m(v);
    return MiningState(
      gear: _l(j['gear']).map((e) => GearPiece.fromJson(_m(e))).toList(),
      loadout: _m(j['loadout']).map((k, v) => MapEntry(k, v as String)),
    );
  }

  Map<String, dynamic> toJson() => {'gear': gear.map((e) => e.toJson()).toList(), 'loadout': loadout};
}
