// The mine keeps its own depth: going down its shaft never counts as a Deep Wilds floor, so each entrance
// offers its own "descend to your deepest".

import 'package:evochi/core/models/game_state.dart';
import 'package:evochi/core/utils/day_keys.dart';
import 'package:evochi/game/wilds/wilds.dart' as w;
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(ensureTimeZones);
  final t0 = DateTime.utc(2026, 10, 5, 14).millisecondsSinceEpoch;

  test('mine galleries and Wilds floors are remembered apart', () {
    var s = GameState.fresh(t0, 'America/New_York');
    expect(w.deepestMineFloor(s), 1);
    expect(w.deepestFloor(s), 1);
    s = w.mineReach(s, 2, t0).state;
    s = w.mineReach(s, 3, t0).state;
    expect(w.deepestMineFloor(s), 3);
    expect(w.deepestFloor(s), 1);
    s = w.wildsReach(s, 2, t0).state;
    expect(w.deepestFloor(s), 2);
    expect(w.deepestMineFloor(s), 3);
    // the same gallery twice is a no-op
    expect(identical(w.mineReach(s, 3, t0).state, s), isTrue);
  });
}
