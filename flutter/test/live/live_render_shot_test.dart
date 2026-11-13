// Draws the live Eggling to PNGs (flutter test --dart-define=LIVE_SHOTS=dir): a look at the renderer against the
// clips' sprites.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:evochi/features/live/live_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('the live Eggling draws', () async {
    final m = await LiveModel.load('assets/live/eggling');
    expect(m.n, greaterThan(1000));
    const shots = String.fromEnvironment('LIVE_SHOTS');
    final out = shots.isEmpty ? null : shots;
    final r = LiveRenderer(m);
    final poses = <String, LivePose>{
      'rest': LivePose(),
      'squash': LivePose()..v[0] = 0.8,
      'lean_turn': LivePose()
        ..v[1] = 10
        ..v[4] = -35,
      'hop': LivePose()
        ..v[0] = 1.12
        ..v[7] = 5
        ..v[9] = 1.4
        ..v[12] = 1.4,
    };
    for (final e in poses.entries) {
      final rec = ui.PictureRecorder();
      final c = Canvas(rec);
      c.drawRect(const Rect.fromLTWH(0, 0, 420, 460), Paint()..color = const Color(0xFFF3EBDD));
      final sw = Stopwatch()..start();
      r.paint(c, const Offset(210, 400), 9.0, e.value, expression: e.key == 'hop' ? 'excited' : 'default');
      final ms = sw.elapsedMicroseconds / 1000;
      final pic = rec.endRecording();
      final img = await pic.toImage(420, 460);
      final png = await img.toByteData(format: ui.ImageByteFormat.png);
      img.dispose();
      pic.dispose();
      expect(png, isNotNull);
      // ignore: avoid_print
      print('${e.key}: built in ${ms.toStringAsFixed(1)} ms');
      if (out != null) File('$out/live_${e.key}.png').writeAsBytesSync(png!.buffer.asUint8List());
    }
  });
}
