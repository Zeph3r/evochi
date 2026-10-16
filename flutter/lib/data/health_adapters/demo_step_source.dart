// Simulated step device for playtesting and the reduced-feature mode (QA Q02).
// Walks are queued by the playtest panel and delivered as phone + watch samples so
// cross-source de-duplication is exercised.

import 'dart:math' as math;

import '../../core/models/game_state.dart';
import '../../core/utils/ids.dart';
import 'step_source.dart';

class DemoStepSource implements StepSource {
  final List<StepSample> _pending = [];
  final _rng = math.Random();

  @override
  String get id => 'demo';
  @override
  String get displayName => 'Simulated step device';
  @override
  Future<bool> isAvailable() async => true;
  @override
  Future<StepPermission> requestPermission() async => StepPermission.granted;

  /// Queue a walk of [steps] ending at [now] as 2-minute samples. With [notBefore] the walk is
  /// squeezed so it never starts before that instant (a story quest's acceptance).
  List<StepSample> walk(int steps, int now, {bool watch = true, int notBefore = 0}) {
    final minutes = math.max(4, (steps / 110).round());
    final n = math.max(1, (minutes / 2).round());
    var start = now - minutes * 60000;
    if (notBefore > 0 && start < notBefore) start = math.min(notBefore, now);
    final dur = now - start;
    var left = steps;
    final out = <StepSample>[];
    for (var i = 0; i < n; i++) {
      final s = start + (i * dur) ~/ n;
      final e = start + ((i + 1) * dur) ~/ n;
      final c = i == n - 1 ? left : (steps / n).round();
      left -= c;
      out.add(StepSample(id: newId('ph'), source: 'demo-phone', start: s, end: e, count: c));
      if (watch) {
        out.add(StepSample(id: newId('wt'), source: 'demo-watch', start: s, end: e, count: (c * (0.96 + _rng.nextDouble() * 0.03)).round()));
      }
    }
    _pending.addAll(out);
    return out;
  }

  @override
  Future<List<StepSample>> readSamples(int from, int to) async {
    final out = _pending.where((s) => s.end >= from && s.start <= to).toList();
    _pending.removeWhere(out.contains);
    return out;
  }
}

/// Manual entry: a lower-trust fallback, flagged unverified (no chests or cosmetic chances).
List<StepSample> manualEntry(int steps, int now) => [
      StepSample(id: newId('man'), source: 'manual', start: now - 60000, end: now, count: steps < 0 ? 0 : steps, manual: true),
    ];
