// Bond: separate 0-100 relationship score (style guide §17).

import '../../app/constants.dart';
import '../../core/models/game_state.dart';

int bondValue(List<BondEvent> events, [GameConfig? config]) {
  final c = config ?? GameConfig.current;
  final perDay = <String, int>{};
  final seen = <String>{};
  var total = 0;
  for (final e in events) {
    if (!seen.add('${e.key}:${e.type}')) continue;
    var amt = switch (e.type) {
      'pet' => c.bondFirstPet,
      'play' => c.bondFirstPlay,
      'goal' => c.bondGoal,
      'treat' => c.bondTreat, // a homemade treat, once a day, outside the pet/play cap
      _ => 0,
    };
    if (e.type == 'pet' || e.type == 'play') {
      final used = perDay[e.key] ?? 0;
      amt = amt.clamp(0, c.bondDirectDailyCap - used < 0 ? 0 : c.bondDirectDailyCap - used);
      perDay[e.key] = used + amt;
    }
    total += amt;
  }
  return total > c.bondMax ? c.bondMax : total;
}

int bondHearts(int bond, {int hearts = 5}) => ((bond / 100) * hearts).round().clamp(0, hearts);
