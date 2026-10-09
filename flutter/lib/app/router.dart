// Navigation: onboarding gate -> five-tab shell. Tabs keep their own state (IndexedStack);
// nested screens (Inspect, Evolution, Settings) push on top and return to the initiating tab.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/game_controller.dart';
import '../features/bag/bag_screen.dart';
import '../features/evodex/evodex_screen.dart';
import '../features/journey/journey_screen.dart';
import '../features/nest/nest_screen.dart';
import '../features/onboarding/onboarding_screens.dart';
import '../features/shared/widgets.dart';
import '../features/shop/shop_screen.dart';

class RootGate extends StatelessWidget {
  const RootGate({super.key});
  @override
  Widget build(BuildContext context) {
    final c = context.watch<GameController>();
    final s = c.state;
    if (s.player == null) return const WelcomeScreen();
    if (s.pet == null) return const CreateScreen();
    switch (s.onboarding.step) {
      case 'connect':
        return const ConnectScreen();
      case 'goal':
        return const GoalScreen();
      case 'awakening':
        return const AwakeningScreen();
      default:
        return const MainShell();
    }
  }
}

class TabNav extends InheritedWidget {
  const TabNav({super.key, required this.go, required super.child});
  final void Function(String tab) go;
  static TabNav of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<TabNav>()!;
  @override
  bool updateShouldNotify(TabNav old) => false;
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});
  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  static const order = ['home', 'journey', 'bag', 'shop', 'evodex'];
  String _tab = 'home';

  void _go(String t) {
    if (t == _tab) return;
    context.read<GameController>().audio.play('ui_tap', volume: 0.4);
    setState(() => _tab = t);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<GameController>();
    final v = c.view;
    return TabNav(
      go: _go,
      child: Scaffold(
        extendBody: true,
        body: IndexedStack(
          index: order.indexOf(_tab),
          children: [
            NestScreen(active: _tab == 'home'),
            const JourneyScreen(),
            BagScreen(active: _tab == 'bag'),
            ShopScreen(active: _tab == 'shop'),
            const EvoDexScreen(),
          ],
        ),
        bottomNavigationBar: EvochiNavBar(
          current: _tab,
          onTab: _go,
          badges: {
            'journey': v.claimable,
            'evodex': (v.pet?.evolution.eligible ?? false) ? 1 : 0,
            'home': (v.pet?.dead ?? false) ? 1 : 0,
          },
        ),
      ),
    );
  }
}

/// Height the floating nav occupies at the bottom of tab screens.
double navInset(BuildContext context) => 84 + MediaQuery.of(context).padding.bottom;
