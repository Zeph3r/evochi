// Motion tokens: the durations and curves the interface moves by, reduced motion as the app sees it, and the
// small entrance every card and line of speech shares. New motion takes its timing from here so screens feel
// like one game; the art's own animation (cinematic shots, the hatch, acting clips) keeps its own clocks.

import 'dart:async';

import 'package:flutter/widgets.dart';

class Motion {
  Motion._();

  // durations
  static const press = Duration(milliseconds: 70); // a button going down
  static const release = Duration(milliseconds: 150); // and coming back up
  static const quick = Duration(milliseconds: 180); // small state changes: a toggle, a selection
  static const base = Duration(milliseconds: 280); // cards and panels entering
  static const calm = Duration(milliseconds: 420); // larger reveals, sheets
  static const page = Duration(milliseconds: 560); // one onboarding step to the next

  // curves
  static const Curve enter = Curves.easeOutCubic; // arriving: fast, then settling
  static const Curve exit = Curves.easeInCubic; // leaving: gathering speed
  static const Curve move = Curves.easeInOutCubic; // going from one place to another
  static const Curve land = Curves.easeOutBack; // things that land, with a little overshoot

  /// Reduce motion: the OS setting or the in-game toggle (the app folds both into MediaQuery). Rebuilds the
  /// caller when it changes.
  static bool reduced(BuildContext context) => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  /// The same, safe to read once from initState (it does not subscribe to changes).
  static bool reducedNow(BuildContext context) =>
      context.getInheritedWidgetOfExactType<MediaQuery>()?.data.disableAnimations ??
      WidgetsBinding.instance.platformDispatcher.accessibilityFeatures.disableAnimations;
}

/// Fades its child in while it rises a few pixels into place, once, when it first builds. Under reduced motion
/// it only fades, and quicker.
class Entrance extends StatefulWidget {
  const Entrance({super.key, required this.child, this.delay = Duration.zero, this.duration = Motion.base, this.rise = 12});
  final Widget child;
  final Duration delay;
  final Duration duration;
  final double rise;

  @override
  State<Entrance> createState() => _EntranceState();
}

class _EntranceState extends State<Entrance> with SingleTickerProviderStateMixin {
  late final AnimationController _a = AnimationController(vsync: this, duration: widget.duration);
  late final Animation<double> _v = CurvedAnimation(parent: _a, curve: Motion.enter);
  Timer? _wait;

  @override
  void initState() {
    super.initState();
    if (Motion.reducedNow(context)) _a.duration = Motion.quick;
    if (widget.delay == Duration.zero) {
      _a.forward();
    } else {
      _wait = Timer(widget.delay, () {
        if (mounted) _a.forward();
      });
    }
  }

  @override
  void dispose() {
    _wait?.cancel();
    _a.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rise = Motion.reduced(context) ? 0.0 : widget.rise;
    return AnimatedBuilder(
      animation: _v,
      child: widget.child,
      builder: (_, child) => Opacity(
        opacity: _v.value,
        child: rise == 0 ? child : Transform.translate(offset: Offset(0, (1 - _v.value) * rise), child: child),
      ),
    );
  }
}
