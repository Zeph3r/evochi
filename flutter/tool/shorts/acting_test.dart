// Records the three personalities side by side in the meadow, Eggling each: hatching (the signature), a tap
// (pet), food (snack), then left to idle. A check that the acting clips play in place of the still sprite,
// line up with it, and hand back to it cleanly. Frames at 30 fps, 412 x 892 dp at 2x.
//
//   flutter test tool/shorts/acting_test.dart
//
// Writes _shorts/acting/frames.rgba (raw RGBA) and meta.json; the helper runs it from _transfer/run_test.flag.

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:evochi/app/theme.dart';
import 'package:evochi/core/services/asset_manifest.dart';
import 'package:evochi/core/utils/day_keys.dart';
import 'package:evochi/features/shared/acting.dart';
import 'package:evochi/features/shared/live_scene.dart';
import 'package:evochi/features/shared/scene_view.dart';
import 'package:evochi/game/personality/personality.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' hide AssetManifest;
import 'package:flutter_test/flutter_test.dart';

const _fps = 30;
const _frame = Duration(microseconds: 1000000 ~/ _fps);
const _dpr = 2.0;
const _size = Size(412, 892);
const _profiles = ['lively', 'calm', 'cautious'];
const _palettes = ['coral', 'forest', 'ocean'];

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
    await AssetManifest.load();
    await SceneFx.load();
  });

  testWidgets('record the three personalities acting', (tester) async {
    tester.view.physicalSize = Size(_size.width * _dpr, _size.height * _dpr);
    tester.view.devicePixelRatio = _dpr;
    addTearDown(tester.view.reset);
    final who = [for (final p in _profiles) generatePersonality(21, profile: p)];
    final scenes = [for (final _ in _profiles) SceneController()];
    final tick = ValueNotifier(0);
    final shot = GlobalKey();
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: evochiTheme(),
      home: RepaintBoundary(
        key: shot,
        child: Column(children: [
          for (var i = 0; i < 3; i++)
            Expanded(
              child: Stack(children: [
                Positioned.fill(
                  child: HabitatScene(
                    controller: scenes[i],
                    config: SceneConfig(
                      habitat: 'meadow',
                      focus: const Offset(0.5, 0.86),
                      zoom: 1.5,
                      pet: PetConfig(stage: 1, palette: _palettes[i], personality: who[i]),
                    ),
                  ),
                ),
                Positioned(
                  left: 10,
                  top: 8,
                  child: ValueListenableBuilder<int>(
                    valueListenable: tick,
                    builder: (_, __, ___) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      color: const Color(0xCCFFF9F0),
                      child: Text('${_profiles[i]} · ${directorFor(who[i]).last?.behavior.id ?? ''}', style: EvochiText.tag),
                    ),
                  ),
                ),
              ]),
            ),
        ]),
      ),
    ));
    Future<void> warm(int n) async {
      for (var i = 0; i < n; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 25)));
        await tester.pump(_frame);
      }
    }

    await warm(40); // the atlases and the clips' index
    final dir = Directory('_shorts/acting');
    final raw = await tester.runAsync(() async {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
      dir.createSync(recursive: true);
      return File('${dir.path}/frames.rgba').openSync(mode: FileMode.write);
    });
    var frames = 0;
    Future<void> grab() async {
      // a moment of real time, so a clip's next frames decode as they would on a phone
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 12)));
      await tester.pump(_frame);
      tick.value++;
      final ro = shot.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final bytes = await tester.runAsync(() async {
        final img = await ro.toImage(pixelRatio: _dpr);
        final bd = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
        img.dispose();
        return bd!.buffer.asUint8List();
      });
      await tester.runAsync(() async => raw!.writeFromSync(bytes!));
      frames++;
      if (frames % 30 == 0) debugPrint('acting frame $frames');
    }

    Future<void> hold(double secs) async {
      for (var i = 0; i < (secs * _fps).round(); i++) {
        await grab();
      }
    }

    await hold(0.8);
    for (final s in scenes) {
      s.react('hatch');
    }
    await hold(2.4);
    for (final s in scenes) {
      s.react('pet');
    }
    await hold(2.0);
    for (final s in scenes) {
      s.react('snack');
    }
    await hold(2.0);
    for (final s in scenes) {
      s.react('play');
    }
    await hold(9.0); // left to itself: an idle habit each
    await tester.runAsync(() async {
      raw!.closeSync();
      File('${dir.path}/meta.json').writeAsStringSync(jsonEncode({'w': (_size.width * _dpr).round(), 'h': (_size.height * _dpr).round(), 'fps': _fps, 'frames': frames}));
    });
    await tester.pumpWidget(const SizedBox());
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
  }, timeout: const Timeout(Duration(minutes: 40)));
}
