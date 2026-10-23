// Records a living scene (LiveImage: the scene_fx shader and its emitters) for a few seconds, frame
// by frame, under the test clock: to preview new scene art with its motion before it is in the game.
//
//   flutter test tool/shorts/live_test.dart --dart-define=LIVE=village/walk_falls.webp,village/walk_plaza.webp
//
// Writes _shorts/live/<name>/frames.rgba (raw RGBA, one frame after another) and meta.json. The
// helper runs it when _transfer/run_live.flag exists (its first line: the comma list).

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:evochi/features/shared/live_scene.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _fps = 30;

void main() {
  const list = String.fromEnvironment('LIVE', defaultValue: 'village/walk_falls.webp');
  const secs = int.fromEnvironment('LIVE_SECS', defaultValue: 6);

  setUpAll(() async {
    await SceneFx.load();
  });

  for (final rel in list.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty)) {
    testWidgets('live $rel', (tester) async {
      final asset = 'assets/art/$rel';
      final fx = SceneFx.of(asset);
      expect(fx, isNotNull, reason: 'no scene_fx entry for $asset');
      final w = fx!.width, h = fx.height;
      tester.view.physicalSize = Size(w, h);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final key = GlobalKey();
      await tester.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: RepaintBoundary(key: key, child: SizedBox(width: w, height: h, child: LiveImage(asset, fit: BoxFit.fill))),
      ));
      // let the picture, its mask and the shader load (real time, the test clock held)
      for (var i = 0; i < 80; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 25)));
        await tester.pump();
      }
      final name = rel.split('/').last.split('.').first;
      final dir = Directory('_shorts/live/$name');
      final raw = await tester.runAsync(() async {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
        dir.createSync(recursive: true);
        return File('${dir.path}/frames.rgba').openSync(mode: FileMode.write);
      });
      final n = secs * _fps;
      for (var f = 0; f < n; f++) {
        await tester.pump(const Duration(microseconds: 1000000 ~/ _fps));
        final ro = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final bytes = await tester.runAsync(() async {
          final img = await ro.toImage();
          final bd = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
          img.dispose();
          return bd!.buffer.asUint8List();
        });
        await tester.runAsync(() async => raw!.writeFromSync(bytes!));
        if (f % 15 == 0) debugPrint('$name frame $f/$n');
      }
      await tester.runAsync(() async {
        raw!.closeSync();
        File('${dir.path}/meta.json').writeAsStringSync(jsonEncode({'asset': asset, 'w': w.round(), 'h': h.round(), 'fps': _fps, 'frames': n}));
      });
      rootBundle.clear();
    }, timeout: const Timeout(Duration(minutes: 30)));
  }
}
