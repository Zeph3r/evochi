// A run in the Wilds kept across the app closing: the floor and what had been done on it, written every few
// seconds of play and the moment the app goes to the background, cleared when the run ends (leaving for the
// trailhead's camp, or the floor being left any other way). On the next launch, a snapshot found here puts the
// Wilds screen back up over the shell with its pause card showing, the run where it was.
//
// Only what the floor needs to be rebuilt and caught up is kept: its seed and depth (a floor is made from
// its seed), the satchel, Raid HP, where your Evochi stood, the creatures calmed, the guardian's Raid HP, the
// ore struck, the spots spent. Whatever was mid-air (an attack, a telegraph, a buff) is not: the floor comes
// back quiet. The fight itself never lives in the save (game/wilds/wilds.dart), so this is its own small
// record beside it.

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class WildsResume {
  const WildsResume({
    required this.mapId,
    required this.depth,
    required this.seed,
    required this.surge,
    required this.story,
    required this.mine,
    required this.runId,
    required this.banks,
    required this.hp,
    required this.x,
    required this.z,
    required this.coins,
    required this.items,
    required this.calmed,
    required this.unbankedCalms,
    required this.calmFoes,
    required this.bossHp,
    required this.bossCalm,
    required this.storyDone,
    required this.trust,
    required this.sig,
    required this.ward,
    required this.oreDamage,
    required this.used,
    required this.satchel,
    required this.sealOpen,
    required this.savedAt,
  });

  // the floor
  final String mapId;
  final int? depth;
  final int seed;
  final bool surge, mine;
  final String? story;
  // the run
  final String runId;
  final int banks;
  final double hp, x, z;
  final int coins;
  final Map<String, int> items;
  final int calmed, unbankedCalms;
  final List<String> calmFoes;
  final double? bossHp;
  final bool bossCalm, storyDone;
  final double trust, sig;
  final int ward;
  final Map<String, double> oreDamage;
  final List<String> used;
  final Map<String, int> satchel;
  final bool sealOpen;
  final int savedAt;

  static const _key = 'evochi.wilds.resume.v1';

  /// A run left open for longer than this is let go (a week: the floor would be stale, the save moved on).
  static const keepFor = Duration(days: 7);

  Map<String, dynamic> toJson() => {
        'v': 1,
        'mapId': mapId,
        'depth': depth,
        'seed': seed,
        'surge': surge,
        'story': story,
        'mine': mine,
        'runId': runId,
        'banks': banks,
        'hp': hp,
        'x': x,
        'z': z,
        'coins': coins,
        'items': items,
        'calmed': calmed,
        'unbankedCalms': unbankedCalms,
        'calmFoes': calmFoes,
        'bossHp': bossHp,
        'bossCalm': bossCalm,
        'storyDone': storyDone,
        'trust': trust,
        'sig': sig,
        'ward': ward,
        'oreDamage': oreDamage,
        'used': used,
        'satchel': satchel,
        'sealOpen': sealOpen,
        'savedAt': savedAt,
      };

  static WildsResume? fromJson(Map<String, dynamic> j) {
    if (j['v'] != 1) return null;
    Map<String, int> ints(Object? o) => {for (final e in ((o as Map?) ?? const {}).entries) e.key as String: (e.value as num).toInt()};
    return WildsResume(
      mapId: j['mapId'] as String? ?? 'thicket',
      depth: (j['depth'] as num?)?.toInt(),
      seed: (j['seed'] as num).toInt(),
      surge: j['surge'] as bool? ?? false,
      story: j['story'] as String?,
      mine: j['mine'] as bool? ?? false,
      runId: j['runId'] as String,
      banks: (j['banks'] as num?)?.toInt() ?? 0,
      hp: (j['hp'] as num).toDouble(),
      x: (j['x'] as num).toDouble(),
      z: (j['z'] as num).toDouble(),
      coins: (j['coins'] as num?)?.toInt() ?? 0,
      items: ints(j['items']),
      calmed: (j['calmed'] as num?)?.toInt() ?? 0,
      unbankedCalms: (j['unbankedCalms'] as num?)?.toInt() ?? 0,
      calmFoes: [for (final f in (j['calmFoes'] as List?) ?? const []) f as String],
      bossHp: (j['bossHp'] as num?)?.toDouble(),
      bossCalm: j['bossCalm'] as bool? ?? false,
      storyDone: j['storyDone'] as bool? ?? false,
      trust: (j['trust'] as num?)?.toDouble() ?? 0,
      sig: (j['sig'] as num?)?.toDouble() ?? 0,
      ward: (j['ward'] as num?)?.toInt() ?? 0,
      oreDamage: {for (final e in ((j['oreDamage'] as Map?) ?? const {}).entries) e.key as String: (e.value as num).toDouble()},
      used: [for (final u in (j['used'] as List?) ?? const []) u as String],
      satchel: ints(j['satchel']),
      sealOpen: j['sealOpen'] as bool? ?? false,
      savedAt: (j['savedAt'] as num?)?.toInt() ?? 0,
    );
  }

  /// The run left open, if one is (and it is not stale); null otherwise.
  static Future<WildsResume?> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final text = p.getString(_key);
      if (text == null) return null;
      final r = fromJson((jsonDecode(text) as Map).cast<String, dynamic>());
      if (r == null || DateTime.now().millisecondsSinceEpoch - r.savedAt > keepFor.inMilliseconds) {
        await p.remove(_key);
        return null;
      }
      return r;
    } catch (_) {
      return null; // an unreadable record is no run
    }
  }

  static Future<void> save(WildsResume r) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_key, jsonEncode(r.toJson()));
    } catch (_) {}
  }

  static Future<void> clear() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.remove(_key);
    } catch (_) {}
  }
}
