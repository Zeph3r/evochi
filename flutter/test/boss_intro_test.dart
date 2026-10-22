import 'package:evochi/features/wilds/boss_intro.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(IntroCut cut, List<String> cues, VoidCallback done) => MaterialApp(
      home: Scaffold(
        body: BossIntro(
          art: BossIntroArt.blank(),
          evochi: null,
          cut: cut,
          name: 'Briarback',
          title: 'Guardian of the Thicket',
          petName: 'Mochi',
          tint: cineTint('ocean'),
          onCue: cues.add,
          onDone: done,
        ),
      ),
    );

void main() {
  testWidgets('the full entrance plays its beats in order, then hands over to the fight', (tester) async {
    final cues = <String>[];
    var done = 0;
    await tester.pumpWidget(_host(IntroCut.full, cues, () => done++));
    expect(find.text('BRIARBACK'), findsNothing); // the title waits for the slam
    for (var i = 0; i < 45; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('BRIARBACK'), findsWidgets);
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(cues, ['open', 'roar', 'blast', 'dig', 'slam', 'whoosh', 'ready']);
    expect(done, 1);
  });

  testWidgets('a tap skips it, once', (tester) async {
    final cues = <String>[];
    var done = 0;
    await tester.pumpWidget(_host(IntroCut.full, cues, () => done++));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.byType(BossIntro));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byType(BossIntro), warnIfMissed: false);
    await tester.pump(const Duration(seconds: 8));
    expect(done, 1);
    expect(cues.contains('slam'), isFalse);
  });

  testWidgets('a rematch gets the short cut: the slam and the title', (tester) async {
    final cues = <String>[];
    var done = 0;
    await tester.pumpWidget(_host(IntroCut.short, cues, () => done++));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(cues, ['slam']);
    expect(done, 1);
  });

  group('the Forgotten Sentinel\'s entrance', () {
    Widget host(IntroCut cut, List<String> cues, VoidCallback done) => MaterialApp(
          home: Scaffold(
            body: SentinelIntro(
              art: BossIntroArt.blank(frames: 40, impact: 26),
              evochi: null,
              cut: cut,
              petName: 'Mochi',
              tint: cineTint('forest'),
              onCue: cues.add,
              onDone: done,
            ),
          ),
        );

    testWidgets('wakes, roars, fires at your Evochi, which leaps clear; then the title over it looming', (tester) async {
      final cues = <String>[];
      var done = 0;
      await tester.pumpWidget(host(IntroCut.full, cues, () => done++));
      expect(find.text('THE FORGOTTEN SENTINEL'), findsNothing);
      for (var i = 0; i < 56; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('THE FORGOTTEN SENTINEL'), findsWidgets);
      for (var i = 0; i < 25; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(cues, ['open', 'ignite', 'rise', 'roar', 'charge', 'beam', 'leap', 'blast', 'land', 'title']);
      expect(done, 1);
    });

    testWidgets('a second time, the short cut: the looming shot and the title', (tester) async {
      final cues = <String>[];
      var done = 0;
      await tester.pumpWidget(host(IntroCut.short, cues, () => done++));
      for (var i = 0; i < 25; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(cues, ['title']);
      expect(done, 1);
    });

    testWidgets('a tap skips it, once', (tester) async {
      final cues = <String>[];
      var done = 0;
      await tester.pumpWidget(host(IntroCut.full, cues, () => done++));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.byType(SentinelIntro));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.byType(SentinelIntro), warnIfMissed: false);
      await tester.pump(const Duration(seconds: 9));
      expect(done, 1);
      expect(cues.contains('beam'), isFalse);
    });
  });
}
