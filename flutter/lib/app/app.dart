import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/game_controller.dart';
import '../features/home/home_widgets.dart';
import '../features/shared/kit.dart';
import '../features/shared/widgets.dart';
import 'router.dart';
import 'theme.dart';

class EvochiApp extends StatefulWidget {
  const EvochiApp({super.key});
  @override
  State<EvochiApp> createState() => _EvochiAppState();
}

class _EvochiAppState extends State<EvochiApp> with WidgetsBindingObserver {
  bool _precached = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // the kit's wood, paper, canvas and frames, decoded before the first screen needs them
    if (!_precached) {
      _precached = true;
      precacheKitTextures(context);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final c = context.read<GameController>();
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      c.flush();
      c.audio.stopAmbient();
    } else if (state == AppLifecycleState.resumed) {
      c.sync();
      c.audio.startAmbient();
    }
  }

  @override
  Widget build(BuildContext context) {
    final reduce = context.select<GameController, bool>((c) => c.state.player?.settings.reducedMotion ?? false);
    final large = context.select<GameController, bool>((c) => c.state.player?.settings.largeText ?? false);
    return MaterialApp(
      title: 'Evochi',
      navigatorKey: rootNavigatorKey,
      debugShowCheckedModeBanner: false,
      theme: evochiTheme(),
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        // honour the OS reduce-motion setting as well as the in-game toggle. Text: the game's layout is
        // drawn to fixed sizes like the web build, so the phone's own font size is capped (a 115-130%
        // system font squashed tabs, buttons and the coin purse on Android); Profile > Larger text
        // raises small and secondary text on purpose instead.
        final sys = mq.textScaler.clamp(minScaleFactor: 1.0, maxScaleFactor: 1.0);
        return MediaQuery(
          data: mq.copyWith(disableAnimations: mq.disableAnimations || reduce, textScaler: large ? EvochiTextScaler(sys) : sys),
          child: ToastListener(child: SkillUpListener(child: child!)),
        );
      },
      home: const RootGate(),
    );
  }
}
