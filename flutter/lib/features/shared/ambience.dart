// Where you are, for the ears. Wrap a place screen in Ambience('kitchen', child: ...) and, while the
// screen is on show (its route on top, its tab chosen: it follows TickerMode), the place's sound
// plays: its music (a small playlist of gentle airs, with quiet between tracks) and its ambient bed
// (the kitchen fire, the cauldron, the stream). See AudioService.placeSounds for what plays where.

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../controllers/game_controller.dart';
import '../../core/services/audio_service.dart';

class Ambience extends StatefulWidget {
  const Ambience(this.place, {super.key, required this.child, this.gain = 1});

  /// A key of AudioService.placeSounds: nest, home, village, kitchen, apothecary, workshop, lodge,
  /// glasshouse, forest, hollow, dusk, market.
  final String place;

  /// The ambient bed's volume against the usual (1.7: up close to the fire). The music stays put.
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
      _audio!.updatePlace(_token, widget.place, gain: widget.gain);
      _on = true;
    } else if (_on) {
      _audio!.leavePlace(_token);
      _on = false;
    }
  }

  @override
  void dispose() {
    if (_on) _audio?.leavePlace(_token);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// A Lumen Trails scene's place.
String scenePlace(String? scene) => switch (scene) {
      'sentinel_gate' => 'dusk',
      'mossy_ruins_hollow' => 'hollow',
      _ => 'forest',
    };

/// A village place (the Waystone stands out on the Square).
String villagePlace(String id) => switch (id) {
      'workshop' || 'lodge' || 'glasshouse' => id,
      _ => 'village',
    };
