// S00 Splash / restore -> onboarding or the nest. Errors anywhere in the app go through
// core/services/diagnostics.dart (the log, the crash records, a cloud reporter once one is plugged in).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' hide AssetManifest;
import 'package:provider/provider.dart';

import 'app/app.dart';
import 'app/constants.dart';
import 'controllers/game_controller.dart';
import 'core/services/asset_manifest.dart';
import 'core/services/diagnostics.dart';
import 'data/local/local_store.dart';
import 'data/repositories/game_repository.dart';
import 'game/emotion/emotion.dart';
import 'features/shared/live_scene.dart';

void main() {
  runZonedGuarded(_main, (e, st) => Diagnostics.report(e, st, fatal: true, context: 'zone'));
}

Future<void> _main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Diagnostics.install(build: const String.fromEnvironment('BUILD_NUMBER', defaultValue: 'dev'));
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  await AssetManifest.load();
  await SceneFx.load();
  await Emotions.load();
  try {
    GameConfig.current = GameConfig.parse(await rootBundle.loadString('assets/config/balance_v1.json'));
  } catch (_) {
    GameConfig.current = GameConfig.defaults();
  }
  final controller = GameController(repo: GameRepository(local: SharedPrefsStore()));
  await controller.init();
  Log.i('app', 'ready: ${controller.state.player == null ? 'no player' : 'player, pet ${controller.state.pet?.stage ?? '-'}'}');
  runApp(ChangeNotifierProvider.value(value: controller, child: const EvochiApp()));
}
