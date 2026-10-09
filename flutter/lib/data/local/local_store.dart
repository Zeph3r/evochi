// Offline-first local persistence (style guide §21): the pet snapshot loads instantly from disk.

import 'package:shared_preferences/shared_preferences.dart';

import '../../core/models/game_state.dart';

abstract class LocalStore {
  Future<GameState?> load();
  Future<void> save(GameState state);
  Future<void> clear();
}

class SharedPrefsStore implements LocalStore {
  static const _key = 'evochi.save.v1';

  @override
  Future<GameState?> load() async {
    final p = await SharedPreferences.getInstance();
    return GameState.tryParse(p.getString(_key));
  }

  @override
  Future<void> save(GameState state) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_key, state.serialize());
  }

  @override
  Future<void> clear() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_key);
  }
}

/// In-memory store for tests and for when device storage is unavailable.
class MemoryStore implements LocalStore {
  String? _text;
  @override
  Future<GameState?> load() async => GameState.tryParse(_text);
  @override
  Future<void> save(GameState state) async => _text = state.serialize();
  @override
  Future<void> clear() async => _text = null;
}
