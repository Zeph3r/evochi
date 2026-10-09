// Activity XP and level curve (style guide §15).

import '../../app/constants.dart';

class ActivityXp {
  const ActivityXp({required this.base, required this.milestones, required this.stretch, required this.reached});
  final int base;
  final int milestones;
  final int stretch;
  final List<String> reached;
  int get total => base + milestones + stretch;
}

/// floor(100 * min(S,G)/G) + milestones (25/50/100%) + floor(20 * min(max(S-G,0), 0.5G) / 0.5G)
ActivityXp calculateDailyXp(int steps, int goal, [GameConfig? config]) {
  final c = config ?? GameConfig.current;
  final s = steps < 0 ? 0 : steps;
  final g = goal < 1 ? 1 : goal;
  final base = (c.xpBase * (s < g ? s : g)) ~/ g;
  var ms = 0;
  final reached = <String>[];
  for (final m in c.milestones) {
    if (s >= m.ratio * g) {
      ms += m.xp;
      reached.add(m.id);
    }
  }
  final span = c.stretchSpan * g;
  final over = (s - g).clamp(0, span).toDouble();
  final stretch = (c.stretchMax * over / span).floor();
  return ActivityXp(base: base, milestones: ms, stretch: stretch, reached: reached);
}

int _round10(num x) => (x / 10).round() * 10;

/// XP needed to go from [level] to level + 1: roundToNearest10(a + b(L-1) + c(L-1)^2).
int xpToNext(int level, [GameConfig? config]) {
  final c = config ?? GameConfig.current;
  final n = level - 1;
  return _round10(c.levelA + c.levelB * n + c.levelC * n * n);
}

class LevelInfo {
  const LevelInfo(this.level, this.into, this.need);
  final int level;
  final int into;
  final int need;
  double get progress => need == 0 ? 1 : into / need;
}

/// Level from cumulative lifetime XP (daily step resets never reset creature XP).
LevelInfo levelInfo(int totalXp, [GameConfig? config]) {
  final c = config ?? GameConfig.current;
  var level = 1;
  var rem = totalXp < 0 ? 0 : totalXp;
  while (level < c.levelMax) {
    final need = xpToNext(level, c);
    if (rem < need) return LevelInfo(level, rem, need);
    rem -= need;
    level++;
  }
  return LevelInfo(level, 0, 0);
}

bool isActiveDay(int steps, int goal, [GameConfig? config]) => steps >= (config ?? GameConfig.current).activeDayRatio * goal;
