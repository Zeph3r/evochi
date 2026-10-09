// Evolution gates (style guide §16).

import '../../app/constants.dart';

class EvolutionStatus {
  const EvolutionStatus({
    required this.maxed,
    required this.eligible,
    this.next,
    this.gate,
    this.levelOk = false,
    this.daysOk = false,
    this.levelProgress = 1,
    this.daysProgress = 1,
  });
  final bool maxed;
  final bool eligible;
  final int? next;
  final EvolutionGate? gate;
  final bool levelOk;
  final bool daysOk;
  final double levelProgress;
  final double daysProgress;
}

EvolutionStatus canEvolve(int stage, int level, int activeDays, [GameConfig? config]) {
  final c = config ?? GameConfig.current;
  if (stage >= 3) return const EvolutionStatus(maxed: true, eligible: false);
  final gate = c.evolution[stage + 1]!;
  final levelOk = level >= gate.level;
  final daysOk = activeDays >= gate.activeDays;
  return EvolutionStatus(
    maxed: false,
    eligible: levelOk && daysOk,
    next: stage + 1,
    gate: gate,
    levelOk: levelOk,
    daysOk: daysOk,
    levelProgress: (level / gate.level).clamp(0.0, 1.0).toDouble(),
    daysProgress: (activeDays / gate.activeDays).clamp(0.0, 1.0).toDouble(),
  );
}
