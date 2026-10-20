// A place's background sound. Wrap a place screen in Ambience('amb_kitchen', child: ...) and its bed
// plays while the screen is on show (its route on top, its tab chosen: it follows TickerMode),
// crossfading from wherever you came from and back again when you leave. See AudioService.

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../controllers/game_controller.dart';
import '../../core/services/audio_service.dart';

class Ambience extends StatefulWidget {
  const Ambience(this.name, {super.key, required this.child, this.gain = 1});

  /// The loop: amb_home, amb_village, amb_kitchen, amb_apothecary, amb_workshop, amb_lodge,
  /// amb_glasshouse, amb_forest, amb_hollow, amb_dusk, amb_market, or ambient_meadow_loop.
  final String name;

  /// Its volume against the usual (1.6: up close to the fire).
  final double gain;
  final Widget child;

  @override
  State<Ambience> createState() => _AmbienceState();
}

class _AmbienceState extends State<Ambience> {
  final _token = Object();
  AudioService? _audio;
  bool _on = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _audio ??= Provider.of<GameController>(context, listen: false).audio;
    _sync();
  }

  @override
  void didUpdateWidget(Ambience old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    final shown = TickerMode.of(context);
    if (shown) {
      _audio!.updateAmbience(_token, widget.name, gain: widget.gain);
      _on = true;
    } else if (_on) {
      _audio!.popAmbience(_token);
      _on = false;
    }
  }

  @override
  void dispose() {
    if (_on) _audio?.popAmbience(_token);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// A Lumen Trails scene's bed.
String sceneAmbience(String? scene) => switch (scene) {
      'sentinel_gate' => 'amb_dusk',
      'mossy_ruins_hollow' => 'amb_hollow',
      _ => 'amb_forest',
    };

/// A village place's bed (the Waystone stands out on the Square).
String placeAmbience(String id) => switch (id) {
      'workshop' => 'amb_workshop',
      'lodge' => 'amb_lodge',
      'glasshouse' => 'amb_glasshouse',
      _ => 'amb_village',
    };
