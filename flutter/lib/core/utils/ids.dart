import 'dart:math' as math;

final _rng = math.Random.secure();
int _counter = 0;

/// Unique, sortable-ish ids for players, pets, purchases and claims.
String newId(String prefix) {
  _counter = (_counter + 1) % 1000000;
  final t = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
  final r = List.generate(6, (_) => _rng.nextInt(36).toRadixString(36)).join();
  return '${prefix}_$t$r${_counter.toRadixString(36)}';
}
