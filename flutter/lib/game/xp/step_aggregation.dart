// Step observations -> authoritative daily totals (style guide §21 "Health synchronization").
//  - samples are de-duplicated by id (re-delivery never double counts)
//  - samples are spread over 15-minute buckets per source; each bucket takes the
//    maximum across sources, so a phone and a watch walking together count once
//  - manual entries are lower trust: day total = max(verified, manual), flagged unverified

import '../../core/models/game_state.dart';
import '../../core/utils/day_keys.dart';

const int _bucket = 15 * 60 * 1000;

class DayTotal {
  const DayTotal({required this.verified, required this.manual});
  final int verified;
  final int manual;
  int get steps => verified > manual ? verified : manual;
  bool get unverified => steps > verified;
}

class MergeResult {
  MergeResult(this.list, this.added);
  final List<StepSample> list;
  final int added;
}

MergeResult mergeSamples(List<StepSample> existing, List<StepSample> incoming) {
  final seen = existing.map((s) => s.id).toSet();
  final list = List<StepSample>.of(existing);
  var added = 0;
  for (final s in incoming) {
    if (s.end < s.start || s.count < 0) continue; // malformed observation
    if (!seen.add(s.id)) continue;
    list.add(s);
    added++;
  }
  return MergeResult(list, added);
}

List<MapEntry<int, int>> _spread(StepSample s) {
  if (s.end <= s.start) return [MapEntry((s.start ~/ _bucket) * _bucket, s.count)];
  final out = <MapEntry<int, int>>[];
  final dur = s.end - s.start;
  var t = s.start;
  var assigned = 0;
  while (t < s.end) {
    final b = (t ~/ _bucket) * _bucket;
    final next = (b + _bucket) < s.end ? b + _bucket : s.end;
    final share = ((s.count * (next - s.start)) / dur).round() - assigned;
    assigned += share;
    out.add(MapEntry(b, share));
    t = next;
  }
  return out;
}

Map<String, DayTotal> aggregateDays(List<StepSample> samples, String zone) {
  final ver = <String, Map<int, Map<String, int>>>{};
  final man = <String, int>{};
  for (final s in samples) {
    if (s.manual) {
      final k = dayKey(s.start, zone);
      man[k] = (man[k] ?? 0) + s.count;
      continue;
    }
    for (final e in _spread(s)) {
      final k = dayKey(e.key, zone);
      final bm = ver.putIfAbsent(k, () => {});
      final src = bm.putIfAbsent(e.key, () => {});
      src[s.source] = (src[s.source] ?? 0) + e.value;
    }
  }
  final out = <String, DayTotal>{};
  for (final k in {...ver.keys, ...man.keys}) {
    var v = 0;
    final bm = ver[k];
    if (bm != null) {
      for (final src in bm.values) {
        v += src.values.reduce((a, b) => a > b ? a : b);
      }
    }
    out[k] = DayTotal(verified: v, manual: man[k] ?? 0);
  }
  return out;
}

/// Fold samples older than [keepDays] into one record per day and kind, keeping saves small.
/// Day totals (and so XP, quests and the vitality replay) are unchanged.
List<StepSample> compactSamples(List<StepSample> samples, String zone, String today, {int keepDays = 14}) {
  final cutoff = addDays(today, -keepDays);
  bool isOld(StepSample s) => dayKey(s.start, zone).compareTo(cutoff) < 0 && !s.source.startsWith('compacted');
  final old = samples.where(isOld).toList();
  if (old.isEmpty) return samples;
  final keep = samples.where((s) => !isOld(s)).toList();
  final days = aggregateDays(old, zone);
  days.forEach((k, d) {
    final mid = dayStart(k, zone) + 12 * hourMs;
    if (d.verified > 0) {
      final ex = keep.where((s) => s.source == 'compacted' && dayKey(s.start, zone) == k).toList();
      if (ex.isNotEmpty) {
        ex.first.count += d.verified;
      } else {
        keep.add(StepSample(id: 'cmp_$k', source: 'compacted', start: mid, end: mid, count: d.verified));
      }
    }
    if (d.manual > 0) {
      final ex = keep.where((s) => s.source == 'compacted-manual' && dayKey(s.start, zone) == k).toList();
      if (ex.isNotEmpty) {
        ex.first.count += d.manual;
      } else {
        keep.add(StepSample(id: 'cmpm_$k', source: 'compacted-manual', start: mid, end: mid, count: d.manual, manual: true));
      }
    }
  });
  return keep;
}
