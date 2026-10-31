// The emotion vocabulary (assets/config/emotions.json) on three Evochi side by side, one of each personality
// profile (cautious, lively, calm), so the same feeling can be seen at three sizes and tempos: each emotion
// plays at full intensity, then at a third, with its name underneath. Recorded under the Shorts recorder's
// fixed clock, the scene's own reactions and nothing else.
//
//   flutter test tool/shorts/emotions_record_test.dart
//
// Frames land in _shorts/emotions/frames.rgba with meta.json (the format the encoders read).

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:evochi/app/constants.dart';
import 'package:evochi/app/theme.dart';
import 'package:evochi/core/services/asset_manifest.dart';
import 'package:evochi/core/utils/day_keys.dart';
import 'package:evochi/game/emotion/emotion.dart';
import 'package:evochi/game/personality/catalog.dart';
import 'package:evochi/game/personality/personality.dart';
import 'package:evochi/features/shared/live_scene.dart';
import 'package:evochi/features/shared/scene_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' hide AssetManifest;
import 'package:flutter_test/flutter_test.dart';

const fps = 30;
const _frame = Duration(microseconds: 1000000 ~/ fps);
const _view = Size(540, 400);
const _scale = 2.0; // 1080x800
const _palette = 'coral';

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
    await Emotions.load();
    try {
      GameConfig.current = GameConfig.parse(await rootBundle.loadString('assets/config/balance_v1.json'));
    } catch (_) {
      GameConfig.current = GameConfig.defaults();
    }
  });

  testWidgets('record the emotions', (tester) async {
    final dir = Directory('_shorts/emotions');
    await tester.runAsync(() async {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
      dir.createSync(recursive: true);
    });
    tester.view.physicalSize = Size(_view.width * _scale, _view.height * _scale);
    tester.view.devicePixelRatio = _scale;
    addTearDown(tester.view.reset);
    final shot = GlobalKey();
    final caption = ValueNotifier<String>('');
    final scenes = [for (final _ in profiles.keys) SceneController()];
    final raw = await tester.runAsync(() => File('${dir.path}/frames.rgba').open(mode: FileMode.write));
    var frame = 0;
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: evochiTheme(),
      home: RepaintBoundary(
        key: shot,
        child: Material(
          color: const Color(0xFF1E2A1C),
          child: Column(children: [
            Expanded(
              child: Row(children: [
                for (final (i, prof) in profiles.keys.indexed)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(3),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Stack(fit: StackFit.expand, children: [
                          HabitatScene(
                            controller: scenes[i],
                            config: SceneConfig(
                              habitat: 'meadow',
                              zoom: 2.4,
                              focus: const Offset(0.5, 0.82),
                              pet: PetConfig(stage: 1, palette: _palette, personality: generatePersonality(11, profile: prof)),
                            ),
                          ),
                          Positioned(
                            left: 0,
                            right: 0,
                            top: 8,
                            child: Text(profiles[prof]!.label, textAlign: TextAlign.center, style: EvochiText.tag.copyWith(color: Colors.white, shadows: const [Shadow(blurRadius: 4)])),
                          ),
                        ]),
                      ),
                    ),
                  ),
              ]),
            ),
            SizedBox(
              height: 56,
              child: Center(
                child: ValueListenableBuilder<String>(
                  valueListenable: caption,
                  builder: (_, s, __) => Text(s, style: EvochiText.pageTitle.copyWith(color: const Color(0xFFFFF0DE))),
                ),
              ),
            ),
          ]),
        ),
      ),
    ));
    for (var i = 0; i < 60; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 25)));
      await tester.pump();
    }

    Future<void> step() async {
      await tester.pump(_frame);
      if (frame % 10 == 0) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 4)));
        await tester.pump();
      }
      final ro = shot.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final bytes = await tester.runAsync(() async {
        final img = await ro.toImage(pixelRatio: _scale);
        final bd = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
        img.dispose();
        return bd!.buffer.asUint8List();
      });
      await tester.runAsync(() async => raw!.writeFromSync(bytes!));
      frame++;
      if (frame % 30 == 0) debugPrint('frame $frame  ${caption.value}');
    }

    Future<void> hold(double s) async {
      for (var i = 0; i < (s * fps).round(); i++) {
        await step();
      }
    }

    await hold(0.8);
    for (final e in Emotions.names) {
      final def = Emotions.of(e);
      if (def == null) continue;
      for (final k in [1.0, 0.35]) {
        caption.value = k == 1 ? e : '$e, softly';
        for (final s in scenes) {
          s.feel(e, intensity: k);
        }
        // its length at an ordinary tempo, what it settles into, and a breath
        await hold(def.ms / 1000 + (def.next != null && def.next != 'neutral' ? 1.0 : 0.0) + 0.5);
      }
    }
    await tester.runAsync(() async => raw!.closeSync());
    final meta = {'id': 'emotions', 'fps': fps, 'frames': frame, 'w': (_view.width * _scale).round(), 'h': (_view.height * _scale).round(), 'format': 'rgba', 'music': null};
    await tester.runAsync(() async {
      File('${dir.path}/cues.json').writeAsStringSync('[]');
      File('${dir.path}/meta.json').writeAsStringSync(jsonEncode(meta));
    });
    await tester.pumpWidget(const SizedBox());
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    debugPrint('recorded $frame frames (${(frame / fps).toStringAsFixed(1)} s)');
  }, timeout: const Timeout(Duration(minutes: 90)));
}
