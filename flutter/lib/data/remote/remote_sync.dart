// Cloud account persistence boundary (style guide §21-22).
//
// For logged-in accounts, currency grants and spends must be confirmed by a server ledger
// (Firebase Functions or equivalent) using the same transaction ids the client generates
// (`quest:<questId>@<period>`, `purchase:<requestId>`). On conflict, resolve from the
// immutable transaction history, never from last-write-wins balances.
//
// The MVP ships [NoopRemoteSync]; plug a Firestore implementation in here.

import '../../core/models/game_state.dart';

abstract class RemoteSync {
  bool get enabled;

  /// Returns the newer cloud snapshot for [accountId], if any.
  Future<GameState?> pull(String accountId);

  /// Uploads the snapshot; the server validates ledger entries by id before accepting.
  Future<void> push(String accountId, GameState state);

  /// Server-confirmed append to the wallet ledger. Returns false if the id already exists.
  Future<bool> confirmTransaction(String accountId, WalletTxn txn);

  /// Removes all account data (privacy: delete my data).
  Future<void> deleteAccountData(String accountId);
}

class NoopRemoteSync implements RemoteSync {
  @override
  bool get enabled => false;
  @override
  Future<GameState?> pull(String accountId) async => null;
  @override
  Future<void> push(String accountId, GameState state) async {}
  @override
  Future<bool> confirmTransaction(String accountId, WalletTxn txn) async => true;
  @override
  Future<void> deleteAccountData(String accountId) async {}
}
