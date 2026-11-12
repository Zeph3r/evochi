// The start screen paints every layer from one clock, without the asset bundle, and one tap begins (once).
import 'dart:ui' as ui;

import 'package:evochi/features/title/title_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

TitleArt fakeArt() => TitleArt({
      'moon': {'w': 66, 'h': 66},
      'clouds': {'file': 'clouds.webp', 'rects': [[0, 0, 200, 70], [210, 0, 150, 60]]},
      'hills': {'file': 'hills.webp', 'w': 1536, 'h': 240, 'lights': [[100, 200], [900, 180]]},
      'shore': {'file': 'shore.webp', 'w': 1536, 'h': 204, 'lights': [[40, 150]]},
      'lily': {'w': 42, 'h': 30},
      'village': {'file': 'village.webp', 'w': 708, 'h': 276, 'lights': [[100, 200], [300, 210]], 'ground': 240.0},
      'layout': {'horizon': 0.6, 'moon': [0.22, 0.3, 0.055], 'island_w': 0.7, 'island_bottom': 0.56, 'village_x': 0.74, 'logo_w': 0.72, 'logo_y': 0.055, 'plank_y': 0.865},
      'logo': {'file': 'logo.webp', 'w': 760, 'h': 308},
      'island': {
        'island': {'file': 'island.webp', 'w': 900, 'h': 700},
        'front': {'file': 'island_front.webp'},
        'elder': {'file': 'elder_sleep.webp', 'frameW': 400, 'frameH': 380, 'frames': 20, 'fps': 10, 'x': 200, 'y': 40},
        'flame': [700.0, 120.0],
        'egg': [300.0, 500.0],
        'zs': [350.0, 200.0],
      },
    }, const {});

TitleArt fakeArtWithBackdrop() {
  final a = fakeArt();
  return TitleArt({...a.j, 'bg': {'file': 'bg.webp', 'w': 288, 'h': 624, 'fps': 15, 'frames': 180, 'lake_y': 0.789, 'island': {'cx': 0.5, 'cy': 0.56, 'w': 0.9}}}, const {});
}

void main() {
  test('the painter draws every layer at any time without images, with and without the backdrop loop', () {
    for (final art in [fakeArt(), fakeArtWithBackdrop()]) {
      for (final t in [0.0, 1.7, 13.3, 22.6, 100.0]) {
        final rec = ui.PictureRecorder();
        final canvas = Canvas(rec);
        TitlePainter(art, t).paint(canvas, const Size(390, 844));
        rec.endRecording().dispose();
      }
    }
  });

  test('the backdrop advances only when a codec is there', () {
    final a = fakeArtWithBackdrop();
    a.advanceBg(1.0);
    expect(a.bgFrame, isNull);
    expect(a.bgDecoding, isFalse);
  });

  testWidgets('a tap begins once', (tester) async {
    final semantics = tester.ensureSemantics();
    var begun = 0;
    await tester.pumpWidget(MaterialApp(home: TitleScreen(onBegin: () => begun++, art: fakeArt())));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.byType(TitleScreen));
    await tester.tap(find.byType(TitleScreen));
    expect(begun, 1);
    expect(find.bySemanticsLabel(RegExp('Tap to begin')), findsOneWidget);
    semantics.dispose();
  });
}
