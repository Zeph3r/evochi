// Apple Health (iOS) / Health Connect (Android) adapter using package:health.
//
// Platform setup (see README):
//  - iOS: HealthKit capability + NSHealthShareUsageDescription in Info.plist.
//  - Android: Health Connect, READ_STEPS permission and the permissions-rationale activity
//    in AndroidManifest.xml; minSdk 26.
// If the health package API changes between majors, only this file needs updating.

import 'dart:io' show Platform;

import 'package:health/health.dart';

import '../../core/models/game_state.dart';
import 'step_source.dart';

class HealthStepSource implements StepSource {
  HealthStepSource() {
    _health.configure();
  }

  final Health _health = Health();
  static const _types = [HealthDataType.STEPS];

  @override
  String get id => 'health';

  @override
  String get displayName => Platform.isIOS ? 'Apple Health' : 'Health Connect';

  @override
  Future<bool> isAvailable() async {
    if (Platform.isAndroid) {
      try {
        return await _health.isHealthConnectAvailable();
      } catch (_) {
        return false;
      }
    }
    return Platform.isIOS;
  }

  @override
  Future<StepPermission> requestPermission() async {
    if (!await isAvailable()) return StepPermission.unavailable;
    try {
      final ok = await _health.requestAuthorization(_types, permissions: const [HealthDataAccess.READ]);
      return ok ? StepPermission.granted : StepPermission.denied;
    } catch (_) {
      return StepPermission.denied;
    }
  }

  @override
  Future<bool> hasPermission() async {
    try {
      if (!await isAvailable()) return true; // can't tell: not Health Connect's missing grant to report
      final ok = await _health.hasPermissions(_types, permissions: const [HealthDataAccess.READ]);
      return ok != false;
    } catch (_) {
      return true;
    }
  }

  @override
  Future<List<StepSample>> readSamples(int from, int to) async {
    final points = await _health.getHealthDataFromTypes(
      types: _types,
      startTime: DateTime.fromMillisecondsSinceEpoch(from),
      endTime: DateTime.fromMillisecondsSinceEpoch(to),
    );
    final out = <StepSample>[];
    for (final p in points) {
      final v = p.value;
      if (v is! NumericHealthValue) continue;
      final count = v.numericValue.round();
      if (count <= 0) continue;
      final start = p.dateFrom.millisecondsSinceEpoch;
      final end = p.dateTo.millisecondsSinceEpoch;
      // Stable id: the platform uuid when present, else a hash of source + interval + count.
      final id = p.uuid.isNotEmpty ? 'hk_${p.uuid}' : 'hk_${p.sourceId}_${start}_${end}_$count';
      out.add(StepSample(id: id, source: p.sourceId.isNotEmpty ? p.sourceId : p.sourceName, start: start, end: end, count: count));
    }
    return out;
  }
}
