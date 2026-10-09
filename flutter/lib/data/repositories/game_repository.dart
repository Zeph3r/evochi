// Repository: local snapshot first, cloud second (offline-first, style guide §21).

import 'dart:async';

import '../../core/models/game_state.dart';
import '../local/local_store.dart';
import '../remote/remote_sync.dart';

class GameRepository {
  GameRepository({required this.local, RemoteSync? remote}) : remote = remote ?? NoopRemoteSync();

  final LocalStore local;
  final RemoteSync remote;
  Timer? _debounce;
  bool storageOk = true;

  Future<GameState?> load() async {
    try {
      return await local.load();
    } catch (_) {
      storageOk = false;
      return null;
    }
  }

  /// Debounced write; a pending write is flushed on [flush] (app pause).
  void save(GameState state) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 150), () => _write(state));
  }

  Future<void> flush(GameState state) async {
    _debounce?.cancel();
    await _write(state);
  }

  Future<void> _write(GameState state) async {
    try {
      await local.save(state);
      storageOk = true;
    } catch (_) {
      storageOk = false;
    }
    final id = state.player?.id;
    if (remote.enabled && id != null && state.player!.accountType != 'guest') {
      unawaited(remote.push(id, state).catchError((_) {}));
    }
  }

  Future<void> wipe(GameState? current) async {
    _debounce?.cancel();
    await local.clear();
    final id = current?.player?.id;
    if (remote.enabled && id != null) await remote.deleteAccountData(id);
  }
}
