// The cold open on a fresh install (IntroGate): once it ends, Welcome shows in its place under the root
// router, so the state changes after Welcome (the guest start, the egg) still move the player on. It used to
// push Welcome as a new route over the router, and the onboarding stalled on Welcome.

import 'package:evochi/controllers/game_controller.dart';
import 'package:evochi/core/models/game_state.dart';
import 'package:evochi/data/local/local_store.dart';
import 'package:evochi/data/repositories/game_repository.dart';
import 'package:evochi/features/onboarding/cinematic_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('after the cold open Welcome shows in place, and the router above it still moves the player on', (tester) async {
    SharedPreferences.setMockInitialValues({}); // a fresh install: the intro never seen
    final started = ValueNotifier(false); // stands in for RootGate seeing the guest start
    final c = GameController(repo: GameRepository(local: MemoryStore()))
      ..state = GameState.fresh(DateTime.utc(2026, 10, 30, 18).millisecondsSinceEpoch, 'America/New_York')
      ..ready = true;
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: c,
      child: MaterialApp(
        home: ValueListenableBuilder<bool>(
          valueListenable: started,
          builder: (_, s, __) => s ? const Text('the nest') : const IntroGate(child: Text('welcome')),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump();
    expect(find.byType(CinematicScreen), findsOneWidget);
    expect(find.text('welcome'), findsNothing);

    // the cut ends
    tester.widget<CinematicScreen>(find.byType(CinematicScreen)).onFinished!();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1)); // the cross-fade
    await tester.pump();
    expect(find.text('welcome'), findsOneWidget);
    expect(find.byType(CinematicScreen), findsNothing);

    // the guest start: the router swaps the screen, as RootGate does for the nest
    started.value = true;
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('the nest'), findsOneWidget);
    expect(find.text('welcome'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
}
