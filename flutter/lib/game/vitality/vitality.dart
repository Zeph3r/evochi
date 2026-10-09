// Vitality: deterministic replay with rest days and a grace window (style guide §17).
//
// Vitality is derived, never incrementally mutated: a late or corrected step sync
// replays the history and automatically reverses an incorrect penalty, so the
// daily processor is idempotent.

import '../../app/constants.dart';
import '../../core/models/game_state.dart';
import '../../core/utils/day_keys.dart';
import '../xp/step_aggregation.dart';

enum PetStatus { healthy, neutral, sick, dead }

PetStatus vitalityState(int v, [GameConfig? config]) {
  final c = config ?? GameConfig.current;
  if (v <= 0) return PetStatus.dead;
  if (v >= c.bandHealthy) return PetStatus.healthy;
  if (v >= c.bandNeutral) return PetStatus.neutral;
  return PetStatus.sick;
}

enum DayKind { goal, active, light, rest, grace, low, pending, dead }

class DayResult {
  const DayResult(this.key, this.kind, this.delta, this.vitality);
  final String key;
  final DayKind kind;
  final int delta;
  final int vitality;
}

class VitalityResult {
  const VitalityResult({required this.vitality, required this.dead, required this.diedAt, required this.log, required this.restDays});
  final int vitality;
  final bool dead;
  final int? diedAt;
  final List<DayResult> log;
  final List<String> restDays;
  PetStatus get status => dead ? PetStatus.dead : vitalityState(vitality);
}

class _Ev {
  _Ev.day(this.t, this.key, this.ratio, this.covered, this.steps)
      : type = 'day',
        amount = 0;
  _Ev.pet(PetEvent e)
      : t = e.t,
        type = e.type,
        amount = e.amount,
        key = '',
        ratio = 0,
        covered = true,
        steps = 0;
  final int t;
  final String type;
  final int amount;
  final String key;
  final double ratio;
  final bool covered;
  final int steps;
}

VitalityResult replayVitality({
  required String createdDay,
  required String todayKey,
  required Map<String, DayTotal> days,
  required int Function(String key) goalFor,
  required List<PetEvent> events,
  required int syncedUntil,
  required int now,
  required String zone,
  GameConfig? config,
}) {
  final c = config ?? GameConfig.current;
  final timeline = <_Ev>[];
  var k = createdDay;
  var guard = 0;
  while (k.compareTo(todayKey) < 0 && guard++ < 3650) {
    final end = dayEnd(k, zone);
    final d = days[k];
    final steps = d?.steps ?? 0;
    final ratio = steps / goalFor(k);
    timeline.add(_Ev.day(end, k, ratio, syncedUntil >= end, steps));
    k = addDays(k, 1);
  }
  for (final e in events) {
    timeline.add(_Ev.pet(e));
  }
  timeline.sort((a, b) {
    final c0 = a.t.compareTo(b.t);
    if (c0 != 0) return c0;
    return a.type == 'day' ? -1 : 1;
  });

  var v = c.vitalityStart;
  var dead = false;
  int? diedAt;
  final rest = <String>[];
  final log = <DayResult>[];
  for (final ev in timeline) {
    if (ev.type == 'day') {
      if (dead) {
        log.add(DayResult(ev.key, DayKind.dead, 0, 0));
        continue;
      }
      var delta = 0;
      DayKind kind;
      if (!ev.covered && ev.steps == 0) {
        kind = DayKind.pending; // data unavailable is not inactivity
      } else if (ev.ratio >= 1) {
        delta = c.restoreFull;
        kind = DayKind.goal;
      } else if (ev.ratio >= c.activeDayRatio) {
        delta = c.restoreHalf;
        kind = DayKind.active;
      } else if (ev.ratio >= c.lowRatio) {
        kind = DayKind.light;
      } else {
        final recent = rest.where((r) {
          final dd = diffDays(r, ev.key);
          return dd > 0 && dd < c.restWindowDays;
        }).length;
        if (recent < c.restDaysPerWindow) {
          rest.add(ev.key);
          kind = DayKind.rest;
        } else if (now < ev.t + c.graceHours * hourMs) {
          kind = DayKind.grace;
        } else {
          delta = -c.lowPenalty;
          kind = DayKind.low;
        }
      }
      v = (v + delta).clamp(0, 100);
      log.add(DayResult(ev.key, kind, delta, v));
      if (v <= 0) {
        dead = true;
        diedAt = ev.t;
      }
    } else if (ev.type == 'care') {
      if (dead) continue;
      v = (v + ev.amount).clamp(0, 100);
    } else if (ev.type == 'revive') {
      if (!dead) continue;
      dead = false;
      v = ev.amount.clamp(1, 100);
    }
  }
  return VitalityResult(vitality: dead ? 0 : v, dead: dead, diedAt: diedAt, log: log, restDays: rest);
}
