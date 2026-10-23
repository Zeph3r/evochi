// Records a mining trip under the test clock, the bible's acceptance run (MINES_PLAN.md: one trip from
// the village ends in a worn item): at the Crossing, three Pounces burst a copper node and three more a
// second; Flint's shop, a Copper Headlamp bought and on at once; back to the village, Bram forges a Copper
// Harness from the ore (prepare, shape, finish); out on the trail again, wearing both. Frames at 30 fps,
// 412 x 892 dp at 2x.
//
//   flutter test tool/shorts/mining_trip_test.dart
//
// Writes _shorts/mining_trip/frames.rgba (raw RGBA, one frame after another) and meta.json.

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
import 'package:evochi/game/engine.dart' as g;
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

  testWidgets('record a mining trip', (tester) async {
    tester.view.physicalSize = Size(_size.width * _dpr, _size.height * _dpr);
    tester.view.devicePixelRatio = _dpr;
    addTearDown(tester.view.reset);
    AudioService.record = [];
    // Chapter 1's first quest done, so Pip has the next one for you (his "!")
    final st = mochi('obsidian');
    g.addTxn(st, WalletTxn(id: 'shorts:coins', amount: 400, cause: 'shorts', at: st.createdAt));
    st.story.questStates['vq01'] = QuestState.fromJson(
        {'phase': 'completed', 'acceptedAt': 0, 'acceptedDay': '2026-10-20', 'resolvedSteps': 2000, 'completedAt': 1});
    final controller = GameController(repo: _NoSave())
      ..state = st
      ..ready = true;
    final shot = GlobalKey();
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: controller,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: evochiTheme(),
        home: const VillageWalkScreen(map: 'trail', arrive: 'village'),
        builder: (context, child) => RepaintBoundary(key: shot, child: child),
      ),
    ));
    // load (real time; the test clock held)
    for (var i = 0; i < 600 && !(VillageWalkScreen.current?.ready ?? false); i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 25)));
      await tester.pump();
    }
    expect(VillageWalkScreen.current?.ready, isTrue, reason: 'the trail did not load');
    for (var i = 0; i < 60; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 25)));
      await tester.pump(_frame);
    }
    final dir = Directory('_shorts/mining_trip');
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
      if (frames % 30 == 0) debugPrint('mining trip frame $frames');
    }

    Future<void> hold(double secs) async {
      for (var i = 0; i < (secs * _fps).round(); i++) {
        await grab();
      }
    }

    var s = VillageWalkScreen.current!;
    VillageWalkScreenState.onExit = (_) {};
    Future<void> walk(double x, double z, {double max = 14}) async {
      s.walkTo(x, z);
      for (var i = 0; i < max * _fps && s.me.moving; i++) {
        await grab();
      }
    }

    Future<void> tapText(String t) async {
      await tester.tap(find.text(t).last);
      await grab();
    }

    Future<void> tapIn(String card, String button) async {
      final c = find.ancestor(of: find.text(card), matching: find.byType(Container)).first;
      await tester.tap(find.descendant(of: c, matching: find.text(button)));
      await grab();
    }

    Future<void> mine(int node) async {
      s.mineOre(s.ores[node]);
      for (var i = 0; i < 10 * _fps && s.me.moving; i++) {
        await grab();
      }
      await hold(0.4);
      for (var hit = 0; hit < 3; hit++) {
        s.pounceDown();
        s.pounceUp();
        for (var i = 0; i < 2 * _fps && s.pounce.active; i++) {
          await grab();
        }
        await hold(hit < 2 ? 0.35 : 1.6);
      }
    }

    Future<void> newMap() async {
      for (var i = 0; i < 600 && (VillageWalkScreen.current == s || !(VillageWalkScreen.current?.ready ?? false)); i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 25)));
        await tester.pump(_frame);
      }
      s = VillageWalkScreen.current!;
      await hold(1.0);
    }

    // at the Crossing, by the copper vein
    s.me
      ..x = 84
      ..z = 0.6;
    await hold(1.0);
    await mine(0);
    await mine(1);
    // Flint's shop: a Copper Headlamp, on at once
    s.talkTo('flint');
    for (var i = 0; i < 12 * _fps && (s.me.moving || s.me.wait > 0); i++) {
      await grab();
    }
    await hold(1.6);
    await tapText('Buy mining gear');
    await hold(1.6);
    await tapIn('Copper Headlamp', 'Buy');
    await hold(1.8);
    await tapText('Done');
    await hold(1.6);
    // back to the village: Bram forges a harness from the ore
    s.goTo('village', 'trail');
    await newMap();
    s.talkTo('bram');
    for (var i = 0; i < 20 * _fps && (s.me.moving || s.me.wait > 0); i++) {
      await grab();
    }
    await hold(1.4);
    await tester.scrollUntilVisible(find.text('Forge mining gear'), 200, scrollable: find.byType(Scrollable).last);
    await tapText('Forge mining gear');
    await hold(1.4);
    await tapIn('Copper Harness', 'Forge');
    await hold(1.4);
    await tapText('Pick up the hammer');
    await hold(0.6);
    for (var i = 0; i < 16 * _fps && find.text('Finish it').evaluate().isEmpty; i++) {
      if (i % 5 == 0) await tester.tap(find.text('Strike!'));
      await grab();
    }
    await hold(0.8);
    await tapText('Engraved with a trail motif');
    await hold(0.8);
    await tapText('Finish it');
    await hold(2.0);
    await tapText('Done');
    await hold(0.6);
    tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    await hold(1.2);
    // out on the trail again, wearing both
    s.goTo('trail', 'village');
    await newMap();
    await walk(14.0, 0.6);
    await hold(2.5);
    VillageWalkScreenState.onExit = null;
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
