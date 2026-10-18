import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/game_controller.dart';
import '../features/home/home_widgets.dart';
import '../features/shared/widgets.dart';
import 'router.dart';
import 'theme.dart';

class EvochiApp extends StatefulWidget {
  const EvochiApp({super.key});
  @override
  State<EvochiApp> createState() => _EvochiAppState();
}

class _EvochiAppState extends State<EvochiApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
    return MaterialApp(
      title: 'Evochi',
      navigatorKey: rootNavigatorKey,
      debugShowCheckedModeBanner: false,
      theme: evochiTheme(),
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        // honour the OS reduce-motion setting as well as the in-game toggle
        return MediaQuery(
          data: mq.copyWith(disableAnimations: mq.disableAnimations || reduce),
          child: ToastListener(child: SkillUpListener(child: child!)),
        );
      },
      home: const RootGate(),
    );
  }
}
