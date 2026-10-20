// Platform step data boundary. The game only ever reads daily STEP counts (style guide §23).

import '../../core/models/game_state.dart';

enum StepPermission { granted, denied, unavailable }

abstract class StepSource {
  String get id; // health | demo | manual
  String get displayName;

  Future<bool> isAvailable();
  Future<StepPermission> requestPermission();

  /// False only when the platform says the permission is gone (a restored backup on a new install, or
  /// the player revoked it); anything uncertain is true, so a hiccup never disconnects anyone.
  Future<bool> hasPermission();

  /// Time-stamped observations between [from] and [to] (ms since epoch). Each sample has a
  /// stable id so re-delivery never double counts.
  Future<List<StepSample>> readSamples(int from, int to);
}
