// Navigation: onboarding gate -> five-tab shell. Tabs keep their own state (IndexedStack);
// nested screens (Inspect, Evolution, Settings) push on top and return to the initiating tab.
// The Village (lib/features/village) and Home Tales (lib/features/home: Home Map, Garden, Cottage,
// Kitchen / Apothecary, Skills) push named routes on top of the shell from their own open* helpers.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/game_controller.dart';
import '../features/bag/bag_screen.dart';
import '../features/evodex/evodex_screen.dart';
import '../features/journey/journey_screen.dart';
import '../features/nest/nest_screen.dart';
import '../features/onboarding/onboarding_screens.dart';
import '../features/shared/ambience.dart';
import '../features/shared/widgets.dart';
import '../features/shop/shop_screen.dart';

/// The app's root navigator, so app-wide listeners (the Skill-up card) can open dialogs.
final rootNavigatorKey = GlobalKey<NavigatorState>();

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
  late final GameController _c = context.read<GameController>();

  @override
  void initState() {
    super.initState();
    _c.tabRequest.addListener(_onTabRequest);
  }

  @override
  void dispose() {
    _c.tabRequest.removeListener(_onTabRequest);
    super.dispose();
  }

  // the Village screens are pushed above the shell: close them, then switch tab
  void _onTabRequest() {
    final t = _c.tabRequest.value;
    if (t == null || !mounted) return;
    Navigator.of(context).popUntil((r) => r.isFirst);
    _c.tabRequest.value = null;
    if (t != _tab) setState(() => _tab = t);
  }

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
          // only the chosen tab ticks: the others keep their state but not their animations (living
          // scenes, the pet) or their place's sound
          children: [
            TickerMode(enabled: _tab == 'home', child: NestScreen(active: _tab == 'home')),
            TickerMode(enabled: _tab == 'journey', child: const JourneyScreen()),
            TickerMode(enabled: _tab == 'bag', child: BagScreen(active: _tab == 'bag')),
            TickerMode(enabled: _tab == 'shop', child: Ambience('amb_market', child: ShopScreen(active: _tab == 'shop'))),
            TickerMode(enabled: _tab == 'evodex', child: const EvoDexScreen()),
          ],
        ),
        bottomNavigationBar: EvochiNavBar(
          current: _tab,
          onTab: _go,
          badges: {
            'journey': v.claimable + c.storyView.turnIns.length,
            'evodex': (v.pet?.evolution.eligible ?? false) ? 1 : 0,
            'home': (v.pet?.dead ?? false) ? 1 : 0,
          },
        ),
      ),
    );
  }
}

/// Height the floating nav occupies at the bottom of tab screens. The shell's Scaffold uses
/// extendBody, so inside a tab the bottom padding already includes the nav bar (and the system
/// inset under it); only the 6 px gap above the bar is added. (It used to add the bar twice.)
double navInset(BuildContext context) => MediaQuery.of(context).padding.bottom + 6;
