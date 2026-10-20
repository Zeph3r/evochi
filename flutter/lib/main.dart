// S00 Splash / restore -> onboarding or the nest.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' hide AssetManifest;
import 'package:provider/provider.dart';

import 'app/app.dart';
import 'app/constants.dart';
import 'controllers/game_controller.dart';
import 'core/services/asset_manifest.dart';
import 'data/local/local_store.dart';
import 'data/repositories/game_repository.dart';
import 'features/shared/live_scene.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  await AssetManifest.load();
  await SceneFx.load();
  try {
    GameConfig.current = GameConfig.parse(await rootBundle.loadString('assets/config/balance_v1.json'));
  } catch (_) {
    GameConfig.current = GameConfig.defaults();
  }
  final controller = GameController(repo: GameRepository(local: SharedPrefsStore()));
  await controller.init();
  runApp(ChangeNotifierProvider.value(value: controller, child: const EvochiApp()));
}
