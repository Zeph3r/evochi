// The live pet lab on its own (flutter run -t lib/main_lab.dart; flutter build web -t lib/main_lab.dart): the
// developer screen without the rest of the game, for trying the live Eggling and its brain anywhere.
//   ?seed=123                         the egg
//   ?genes=curiosity:95,courage:5     genes set by hand (0..100) over the seed's
//   ?demo=2:object,14:visitor,26:pet  a scripted showing (seconds: food | object | visitor | pet | breed | egg)
import 'package:flutter/material.dart';

import 'features/live/live_lab_screen.dart';

void main() {
  final q = Uri.base.queryParameters;
  Map<String, double>? genes;
  if (q['genes'] != null) {
    genes = {
      for (final kv in q['genes']!.split(','))
        if (kv.contains(':')) kv.split(':')[0]: (double.tryParse(kv.split(':')[1]) ?? 50) / 100,
    };
  }
  final demo = <(double, String)>[
    for (final ev in (q['demo'] ?? '').split(','))
      if (ev.contains(':')) (double.tryParse(ev.split(':')[0]) ?? 0, ev.split(':')[1]),
  ];
  runApp(MaterialApp(
    title: 'Evochi live pet lab',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(colorSchemeSeed: const Color(0xFFE0913A), useMaterial3: true),
    home: LiveLabScreen(seed: int.tryParse(q['seed'] ?? ''), genes: genes, demo: demo),
  ));
}
