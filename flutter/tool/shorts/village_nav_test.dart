// A check of the village's ways in and out (no recording): opens the Square at a few points in the story,
// taps the Waystone, and writes a picture of each moment to _shorts/nav/ (with anything that went wrong in
// logs/run_test.txt), at a narrow phone's size and a big one.
//
//   flutter test tool/shorts/village_nav_test.dart

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
import 'package:evochi/features/shared/widgets.dart';
import 'package:evochi/features/village/village_walk.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' hide AssetManifest;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'shorts.dart' show mochi;

class _NoSave extends GameRepository {
  _NoSave() : super(local: MemoryStore());
  @override
  void save(GameState state) {}
}

final _nav = GlobalKey<NavigatorState>();

String? _top() {
  String? name;
  _nav.currentState!.popUntil((r) {
    name = r.settings.name ?? (r.isFirst ? 'shell' : '?');
    return true;
  });
  return name;
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

  // the story's points: before the Waystone is found, found, ready to restore, restored
  GameState at(String phase) {
    final st = mochi('amber');
    if (phase == 'start') return st;
    for (final dep in const ['vq01', 'vq02']) {
      st.story.questStates[dep] = QuestState.fromJson({'phase': 'completed', 'acceptedAt': 0, 'acceptedDay': '2026-10-20', 'resolvedSteps': 2000, 'completedAt': 1});
    }
    if (phase == 'revealed') {
      st.story.flags['waystone_revealed'] = true;
    } else {
      st.story.questStates['vq03'] = QuestState.fromJson(
          {'phase': phase, 'acceptedAt': 0, 'acceptedDay': '2026-10-20', 'resolvedSteps': 2000, if (phase == 'completed') 'completedAt': 1});
      st.story.flags['waystone_revealed'] = true;
      if (phase == 'completed') st.story.flags['waystone_restored'] = true;
    }
    return st;
  }

  testWidgets('the village: the Waystone at each point in the story, Back, the Market', (tester) async {
    AudioService.record = [];
    final controller = GameController(repo: _NoSave())
      ..state = at('start')
      ..ready = true;
    final shot = GlobalKey();
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: controller,
      child: MaterialApp(
        navigatorKey: _nav,
        debugShowCheckedModeBanner: false,
        theme: evochiTheme(),
        home: const Scaffold(body: Center(child: Text('THE SHELL'))),
        builder: (context, child) => RepaintBoundary(key: shot, child: child),
      ),
    ));
    for (final (w, h) in const [(360.0, 640.0), (412.0, 892.0)]) {
      tester.view.physicalSize = Size(w * 2, h * 2);
      tester.view.devicePixelRatio = 2;
      for (final phase in const ['start', 'revealed', 'restoration_ready', 'completed']) {
        controller.state = at(phase);
        _nav.currentState!.popUntil((r) => r.isFirst);
        await tester.pump(const Duration(milliseconds: 400));
        _nav.currentState!.push(walkMapRoute('village'));
        await tester.pump(const Duration(milliseconds: 16));
        for (var i = 0; i < 600 && !(VillageWalkScreen.current?.ready ?? false); i++) {
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 25)));
          await tester.pump(const Duration(milliseconds: 16));
        }
        expect(VillageWalkScreen.current?.ready, isTrue, reason: 'the village did not load');
        final name = '${w.toInt()}_$phase';
        Future<void> snap(String what) async {
          await tester.pump(const Duration(milliseconds: 16));
          final ro = shot.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          await tester.runAsync(() async {
            final img = await ro.toImage(pixelRatio: 1);
            final bd = await img.toByteData(format: ui.ImageByteFormat.png);
            img.dispose();
            Directory('_shorts/nav').createSync(recursive: true);
            File('_shorts/nav/${name}_$what.png').writeAsBytesSync(bd!.buffer.asUint8List());
          });
        }

        for (var i = 0; i < 30; i++) {
          await tester.pump(const Duration(milliseconds: 33)); // the fade in done
        }
        await snap('square');
        // the Waystone's button in the bottom row
        await tester.tap(find.text('Waystone').last);
        for (var i = 0; i < 90; i++) {
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
          await tester.pump(const Duration(milliseconds: 33));
          final e = tester.takeException();
          if (e != null) debugPrint('EXCEPTION ($name): $e');
        }
        await snap('waystone');
        debugPrint('ROUTE ($name): ${ModalRoute.of(VillageWalkScreen.current!.context)?.settings.name}');
        Future<void> settle([int n = 40]) async {
          for (var i = 0; i < n; i++) {
            await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
            await tester.pump(const Duration(milliseconds: 33));
            final e = tester.takeException();
            if (e != null) debugPrint('EXCEPTION ($name): $e');
          }
          for (var i = 0; i < 400 && !(VillageWalkScreen.current?.ready ?? true); i++) {
            await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
            await tester.pump(const Duration(milliseconds: 16));
          }
        }

        String where() {
          final v = VillageWalkScreen.current;
          return v == null ? 'no map (the shell)' : '${v.widget.map} at (${v.me.x.toStringAsFixed(1)}, ${v.me.z.toStringAsFixed(1)})';
        }

        if (phase == 'start' && w < 400) {
          // Back closes the talk first
          await tester.tap(find.byType(BackSquareButton).first);
          await settle(10);
          debugPrint('BACK IN TALK ($name): still ${where()}');
          // into the Guild, and Back: out on its step in the Square
          _nav.currentState!.pushReplacement(walkMapRoute('lodge', at: 'village'));
          await settle();
          debugPrint('IN ($name): ${where()}');
          await tester.tap(find.byType(BackSquareButton).first);
          await settle();
          debugPrint('BACK FROM THE GUILD ($name): ${where()}');
          // the Old Trail, and Back: the Square at the trail's gate
          _nav.currentState!.pushReplacement(walkMapRoute('trail', at: 'village'));
          await settle();
          await tester.tap(find.byType(BackSquareButton).first);
          await settle();
          debugPrint('BACK FROM THE TRAIL ($name): ${where()}');
          // the Market from the bottom row: it opens over the Square
          await tester.tap(find.text('Market').last);
          for (var i = 0; i < 500 && _top() != 'market'; i++) {
            await tester.pump(const Duration(milliseconds: 33));
          }
          await settle(30);
          debugPrint('MARKET ($name): top route ${_top()}, ${where()}');
          await snap('market');
          await tester.tap(find.byType(BackSquareButton).first);
          await settle();
          debugPrint('BACK FROM THE MARKET ($name): ${where()}, top route ${_top()}');
        }
      }
    }
    tester.view.reset();
    AudioService.record = null;
    await tester.pumpWidget(const SizedBox());
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
  }, timeout: const Timeout(Duration(minutes: 15)));
}
