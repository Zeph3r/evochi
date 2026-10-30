// Records the way from the Old Trail into Fernlight Wood under the test clock: by the old mine, over the
// new plank bridge across the ravine, out of the trail and in over the brook into the wood, up the path to
// the meadow. Frames at 30 fps, 412 x 892 dp at 2x. The clock holds while tiles of the
// picture load, so no frame shows one missing.
//
//   flutter test tool/shorts/trail_wood_test.dart
//
// Writes _shorts/trail_wood/frames.rgba (raw RGBA, one frame after another) and meta.json. The
// helper runs it from _transfer/run_test.flag (its first line: the test file).

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:evochi/app/theme.dart';
import 'package:evochi/controllers/game_controller.dart';
import 'package:evochi/core/models/game_state.dart';
import 'package:evochi/core/services/asset_manifest.dart';
import 'package:evochi/core/services/audio_service.dart';
import 'package:evochi/core/utils/day_keys.dart';
import 'package:evochi/data/local/local_store.dart';
import 'package:evochi/data/repositories/game_repository.dart';
import 'package:evochi/features/shared/live_scene.dart';
import 'package:evochi/features/village/village_walk.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' hide AssetManifest;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'shorts.dart' show mochi;

const _fps = 30;
const _frame = Duration(microseconds: 1000000 ~/ _fps);
const _dpr = 2.0;
const _size = Size(412, 892);

class _NoSave extends GameRepository {
  _NoSave() : super(local: MemoryStore());
  @override
  void save(GameState state) {}
}

void main() {
  setUpAll(() async {
    ensureTimeZones();
    for (final (family, files) in const [
      ('Nunito', ['assets/fonts/Nunito-Bold.ttf', 'assets/fonts/Nunito-ExtraBold.ttf', 'assets/fonts/Nunito-Black.ttf']),
      ('Lato', ['assets/fonts/Lato-Regular.ttf', 'assets/fonts/Lato-Bold.ttf', 'assets/fonts/Lato-Black.ttf']),
    ]) {
      final l = FontLoader(family);
      for (final f in files) {
        l.addFont(rootBundle.load(f));
      }
      await l.load();
    }
    final icons = FontLoader('MaterialIcons')..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
    await AssetManifest.load();
    await SceneFx.load();
  });

  testWidgets('record the Old Trail into Fernlight Wood', (tester) async {
    tester.view.physicalSize = Size(_size.width * _dpr, _size.height * _dpr);
    tester.view.devicePixelRatio = _dpr;
    addTearDown(tester.view.reset);
    AudioService.record = [];
    final controller = GameController(repo: _NoSave())
      ..state = mochi('forest', stage: 2)
      ..ready = true;
    final shot = GlobalKey();
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: controller,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: evochiTheme(),
        home: const VillageWalkScreen(map: 'trail', arrive: 'thicket'),
        builder: (context, child) => RepaintBoundary(key: shot, child: child),
      ),
    ));
    for (var i = 0; i < 600 && !(VillageWalkScreen.current?.ready ?? false); i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 25)));
      await tester.pump();
    }
    expect(VillageWalkScreen.current?.ready, isTrue, reason: 'the trail did not load');
    for (var i = 0; i < 60; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 25)));
      await tester.pump(_frame);
    }
    final dir = Directory('_shorts/trail_wood');
    final raw = await tester.runAsync(() async {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
      dir.createSync(recursive: true);
      return File('${dir.path}/frames.rgba').openSync(mode: FileMode.write);
    });
    var frames = 0;
    Future<void> settle() async {
      for (var i = 0; i < 400 && !(VillageWalkScreen.current?.ready ?? true); i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump();
      }
    }

    Future<void> grab() async {
      await settle();
      await tester.pump(_frame);
      final ro = shot.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final bytes = await tester.runAsync(() async {
        final img = await ro.toImage(pixelRatio: _dpr);
        final bd = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
        img.dispose();
        return bd!.buffer.asUint8List();
      });
      await tester.runAsync(() async => raw!.writeFromSync(bytes!));
      frames++;
      if (frames % 30 == 0) debugPrint('trail wood frame $frames');
    }

    Future<void> hold(double secs) async {
      for (var i = 0; i < (secs * _fps).round(); i++) {
        await grab();
      }
    }

    final s = VillageWalkScreen.current!;
    Future<void> walk(VillageWalkScreenState v, double x, double z, {double max = 14}) async {
      v.walkTo(x, z);
      for (var i = 0; i < max * _fps && v.me.moving && VillageWalkScreen.current == v; i++) {
        await grab();
      }
    }

    await hold(1.0);
    await walk(s, 124.0, -6.0); // back from the ravine a step: the bridge across it
    await hold(0.8);
    await walk(s, 131.0, -24.0); // over the bridge and out of the trail
    // into the wood: the next screen comes up and loads
    for (var i = 0; i < 4 * _fps && (VillageWalkScreen.current == s || !(VillageWalkScreen.current?.ready ?? false)); i++) {
      await grab();
    }
    final w = VillageWalkScreen.current!;
    await hold(1.0);
    await walk(w, 15.0, 13.0);
    await walk(w, 26.0, -21.0);
    await hold(1.2);
    await tester.runAsync(() async {
      raw!.closeSync();
      File('${dir.path}/meta.json').writeAsStringSync(jsonEncode({'w': (_size.width * _dpr).round(), 'h': (_size.height * _dpr).round(), 'fps': _fps, 'frames': frames}));
    });
    AudioService.record = null;
    await tester.pumpWidget(const SizedBox());
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
  }, timeout: const Timeout(Duration(minutes: 40)));
}
