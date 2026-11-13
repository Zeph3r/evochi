// The live pet lab on its own (flutter run -t lib/main_lab.dart; flutter build web -t lib/main_lab.dart): the
// developer screen without the rest of the game, for trying the live Eggling and its brain anywhere.
import 'package:flutter/material.dart';

import 'features/live/live_lab_screen.dart';

void main() => runApp(MaterialApp(
      title: 'Evochi live pet lab',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: const Color(0xFFE0913A), useMaterial3: true),
      home: LiveLabScreen(seed: int.tryParse(Uri.base.queryParameters['seed'] ?? '')),
    ));
