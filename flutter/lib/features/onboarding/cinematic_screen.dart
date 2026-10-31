// The cold open as a screen: shown once before Welcome on a fresh install (IntroSeen remembers it on this
// phone, outside the save, so a new pet never replays it), and again from Settings > Watch the intro.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../controllers/game_controller.dart';
import 'cinematic_player.dart';

class IntroSeen {
  static const _key = 'evochi.intro_seen.v1';
  static bool? _cached;

  static Future<bool> get() async {
    if (_cached != null) return _cached!;
    try {
      final p = await SharedPreferences.getInstance();
      return _cached = p.getBool(_key) ?? false;
    } catch (_) {
      return _cached = false;
    }
  }

  static Future<void> set(bool v) async {
    _cached = v;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(_key, v);
    } catch (_) {}
  }
}

/// Plays the cold open, then calls [onFinished] (the first launch: IntroGate shows Welcome in its place, under
/// the root router). From Settings it just pops.
class CinematicScreen extends StatelessWidget {
  const CinematicScreen({super.key, this.onFinished, this.replay = false});
  final VoidCallback? onFinished;
  final bool replay;

  @override
  Widget build(BuildContext context) {
    final c = context.read<GameController>();
    final reduce = MediaQuery.of(context).disableAnimations || (c.state.player?.settings.reducedMotion ?? false);
    return CinematicPlayer(
      reducedMotion: reduce,
      onSfx: (name) {
        // the cut's cues (tools/art/sfx.py --cine): the one footstep the whole onboarding hears, the Lumen rising
        // along the trails, the Hollow creeping in
        const map = {'footstep': 'cine_footstep', 'lumen_rise': 'cine_lumen_rise', 'hollow_creep': 'cine_hollow'};
        final s = map[name];
        if (s != null) c.audio.play(s, volume: name == 'footstep' ? 0.6 : 0.5);
      },
      onDone: () async {
        await IntroSeen.set(true);
        if (!context.mounted) return;
        if (replay) {
          Navigator.of(context).pop();
          return;
        }
        // not a new route: the root router (RootGate) has to stay in place, or the state changes after Welcome
        // (the guest start, the egg) would have nothing to move the player on
        onFinished?.call();
      },
    );
  }
}

/// On a fresh install the cold open comes first; afterwards straight to [child].
class IntroGate extends StatefulWidget {
  const IntroGate({super.key, required this.child});
  final Widget child;
  @override
  State<IntroGate> createState() => _IntroGateState();
}

class _IntroGateState extends State<IntroGate> {
  bool? _seen;

  @override
  void initState() {
    super.initState();
    IntroSeen.get().then((v) {
      if (mounted) setState(() => _seen = v);
    });
  }

  @override
  Widget build(BuildContext context) {
    final seen = _seen;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 700),
      child: seen == null
          ? const ColoredBox(key: ValueKey('wait'), color: Colors.black, child: SizedBox.expand())
          : seen
              ? KeyedSubtree(key: const ValueKey('child'), child: widget.child)
              : CinematicScreen(key: const ValueKey('cine'), onFinished: () => setState(() => _seen = true)),
    );
  }
}
