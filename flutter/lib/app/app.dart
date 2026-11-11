import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/game_controller.dart';
import '../core/services/diagnostics.dart';
import '../core/services/nav_sound.dart';
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
  late final _navSound = NavSound(() => context.read<GameController>().audio);

  // the steps are read again every minute while the app is open (not only when it comes back to the front), so a
  // walk with the app on screen counts as it happens
  Timer? _live;

  void _liveSync() {
    _live?.cancel();
    _live = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) context.read<GameController>().sync();
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _liveSync();
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
    _live?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final c = context.read<GameController>();
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      c.flush();
      c.audio.stopAmbient();
      _live?.cancel();
      Log.i('app', state == AppLifecycleState.paused ? 'paused' : 'inactive');
      unawaited(Diagnostics.flush(clean: state == AppLifecycleState.paused));
    } else if (state == AppLifecycleState.detached) {
      Log.i('app', 'detached');
      unawaited(Diagnostics.flush(clean: true));
    } else if (state == AppLifecycleState.resumed) {
      c.sync();
      c.audio.startAmbient();
      _liveSync();
      Log.i('app', 'resumed');
      unawaited(Diagnostics.flush(clean: false));
    }
  }

  @override
  Widget build(BuildContext context) {
    final reduce = context.select<GameController, bool>((c) => c.state.player?.settings.reducedMotion ?? false);
    final large = context.select<GameController, bool>((c) => c.state.player?.settings.largeText ?? false);
    return MaterialApp(
      title: 'Evochi',
      navigatorKey: rootNavigatorKey,
      navigatorObservers: [_navSound],
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
