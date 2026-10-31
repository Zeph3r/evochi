// The onboarding as a new player sees it, recorded from the real app: a fresh install (no save, the intro
// never seen) plays the cold open, then Pip's letter, the egg pick in Mira's nest with the Elder glimpse, the
// steps beat, the daily goal, and the hatch: a few short simulated walks crack the egg, it hatches, is named,
// and the name flies to Alder's map. Under the Shorts recorder's fixed clock (every frame an exact 1/30 s step
// at 1080x1920), with the sounds the game made written down for the mix.
//
//   flutter test tool/shorts/onboarding_record_test.dart [--dart-define=ONB_UNTIL=22]   (just the first 22 s)
//   python3 tools/shorts/encode_parts.py seg|audio|join ... (a long take, in pieces), or tools/shorts/encode.py
//
// Frames land in _shorts/onboarding/frames.rgba, with cues.json and meta.json (the format encode.py reads).

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:evochi/app/constants.dart';
import 'package:evochi/app/router.dart';
import 'package:evochi/app/theme.dart';
import 'package:evochi/controllers/game_controller.dart';
import 'package:evochi/core/models/game_state.dart';
import 'package:evochi/core/services/asset_manifest.dart';
import 'package:evochi/core/services/audio_service.dart';
import 'package:evochi/core/utils/day_keys.dart';
import 'package:evochi/data/local/local_store.dart';
import 'package:evochi/data/repositories/game_repository.dart';
import 'package:evochi/features/onboarding/cinematic_player.dart';
import 'package:evochi/features/onboarding/onboarding_beats.dart';
import 'package:evochi/features/onboarding/onboarding_screens.dart';
import 'package:evochi/features/shared/live_scene.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' hide AssetManifest;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const fps = 30;
const _frame = Duration(microseconds: 1000000 ~/ fps);
const _view = Size(360, 640);
const _scale = 3.0; // 1080x1920
const _limit = int.fromEnvironment('ONB_UNTIL'); // stop after this many seconds (0: the whole onboarding)
const _palette = 'coral'; // the egg in the middle of the nest (the Ocean one sits at its right edge, off a narrow phone)
final _stop = File('_transfer/stop_shorts.flag');

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
    try {
      GameConfig.current = GameConfig.parse(await rootBundle.loadString('assets/config/balance_v1.json'));
    } catch (_) {
      GameConfig.current = GameConfig.defaults();
    }
  });

  testWidgets('record the onboarding', (tester) async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({}); // a fresh install: the intro has never been seen
    final dir = Directory('_shorts/onboarding');
    await tester.runAsync(() async {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
      dir.createSync(recursive: true);
      if (_stop.existsSync()) _stop.deleteSync();
    });
    await _Rec(tester, dir).run();
  }, timeout: const Timeout(Duration(minutes: 90)));
}

class _Cut implements Exception {}

class _NoSave extends GameRepository {
  _NoSave() : super(local: MemoryStore());
  @override
  void save(GameState state) {}
}

class _Rec {
  _Rec(this.tester, this.dir);
  final WidgetTester tester;
  final Directory dir;
  final _shot = GlobalKey();
  final cues = <Map<String, Object?>>[];
  late final GameController controller;
  RandomAccessFile? _raw;
  int frame = 0;
  bool capturing = false;
  String _screen = '';
  final _sw = Stopwatch()..start();

  double get t => frame / fps;

  Future<void> run() async {
    tester.view.physicalSize = Size(_view.width * 3, _view.height * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    AudioService.record = cues;
    AudioService.clock = () => capturing ? t : -1;
    _raw = await tester.runAsync(() => File('${dir.path}/frames.rgba').open(mode: FileMode.write));
    try {
      await _preload();
      final now = DateTime.now().millisecondsSinceEpoch;
      controller = GameController(repo: _NoSave())
        ..state = GameState.fresh(now, 'America/New_York')
        ..ready = true;
      await tester.pumpWidget(_stage());
      await _settle();
      capturing = true;
      try {
        await _play();
      } on _Cut {
        debugPrint('== cut at ${t.toStringAsFixed(1)} s (ONB_UNTIL)');
      }
    } finally {
      await tester.runAsync(() async => _raw?.closeSync());
      AudioService.record = null;
      AudioService.clock = null;
      await tester.pumpWidget(const SizedBox());
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 250));
      }
    }
    final meta = {'id': 'onboarding', 'fps': fps, 'frames': frame, 'w': (_view.width * _scale).round(), 'h': (_view.height * _scale).round(), 'format': 'rgba', 'music': null};
    await tester.runAsync(() async {
      File('${dir.path}/cues.json').writeAsStringSync(jsonEncode(cues));
      File('${dir.path}/meta.json').writeAsStringSync(jsonEncode(meta));
    });
    debugPrint('recorded $frame frames (${t.toStringAsFixed(1)} s) in ${(_sw.elapsedMilliseconds / 1000).toStringAsFixed(0)} s');
  }

  // ----------------------------------------------------------------------------------- the take
  Future<void> _play() async {
    // the cold open, to Pip's letter
    await _until(() => _has(find.text('Begin Your Journey')), 45);
    _log('welcome');
    await _hold(3.2);
    await _tap(find.text('Begin Your Journey'));
    await _hold(1.6);
    await _tap(find.text('Start my adventure'));
    // Mira's nest: pick the Coral egg, it lifts and glows, the Elder it becomes turns on its ring
    await _until(() => _has(find.byType(EggPickScreen)), 6);
    _log('nest');
    await _hold(2.6);
    await _tap(find.byWidgetPredicate((w) => w is Semantics && w.properties.label == 'Coral egg'));
    await _hold(5.0);
    await _tap(find.text('This one'));
    // the steps beat
    await _until(() => _has(find.byType(ConnectScreen)), 6);
    _log('steps');
    await _hold(3.4);
    await _tap(find.text('Use simulated step device'));
    // the daily goal
    await _until(() => _has(find.byType(GoalScreen)), 6);
    _log('goal');
    await _hold(2.2);
    await _tap(find.text('Continue'));
    // the hatch: four short walks crack the egg
    await _until(() => _has(find.byType(HatchScreen)), 6);
    _log('hatch');
    await _hold(2.4);
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(() => controller.simulateWalk(40));
      await tester.pump();
      await _hold(2.0);
    }
    if (_has(find.text('Hatch'))) {
      await _tap(find.text('Hatch'));
    } else {
      // not enough counted (a walk that fell outside the egg's days): warm it in your hands
      if (_has(find.text('Hold the egg'))) {
        await _tap(find.text('Hold the egg'));
        await _hold(0.8);
      }
      await _tap(find.text('Hatch now'));
    }
    _log('burst');
    await _until(() => _has(find.byType(TextField)), 6);
    await _hold(1.0);
    await tester.enterText(find.byType(TextField), 'Mochi');
    await tester.pump();
    await _hold(1.2);
    await _tap(find.text('Confirm'));
    _log('named');
    await _until(() => _has(find.text('Enter the nest')), 9);
    await _hold(2.6);
  }

  // ----------------------------------------------------------------------------------- the camera
  Widget _stage() => ChangeNotifierProvider.value(
        value: controller,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: evochiTheme(),
          home: const RootGate(),
          builder: (context, child) => RepaintBoundary(key: _shot, child: child ?? const SizedBox()),
        ),
      );

  /// One frame: the clock moves on 1/30 s and the picture is saved. A new screen holds the clock until its
  /// pictures are decoded, so nothing pops in on camera.
  Future<void> _step() async {
    if (_stop.existsSync()) throw StateError('stopped by _transfer/stop_shorts.flag');
    if (_limit > 0 && t >= _limit) throw _Cut();
    await tester.pump(_frame);
    final s = _which();
    if (s != _screen) {
      _screen = s;
      await _settle();
    } else if (frame % 10 == 0) {
      // anything else loading (a sheet's art, the shot list) gets a moment of real time
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 6)));
      await tester.pump();
    }
    await _snap();
    if (frame % 30 == 0) debugPrint('frame $frame  t ${t.toStringAsFixed(1)}  $_screen  ${(_sw.elapsedMilliseconds / 1000).toStringAsFixed(0)} s');
  }

  String _which() {
    for (final (name, type) in const [
      ('hatch', HatchScreen),
      ('goal', GoalScreen),
      ('connect', ConnectScreen),
      ('nest', EggPickScreen),
      ('welcome', WelcomeScreen),
      ('cine', CinematicPlayer),
    ]) {
      if (find.byType(type).evaluate().isNotEmpty) return name;
    }
    return '';
  }

  Future<void> _settle() async {
    for (var i = 0; i < 48; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 25)));
      await tester.pump();
    }
  }

  Future<void> _snap() async {
    final ro = _shot.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (ro == null || !capturing) return;
    final bytes = await tester.runAsync(() async {
      final img = await ro.toImage(pixelRatio: _scale);
      final bd = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
      img.dispose();
      return bd!.buffer.asUint8List();
    });
    await tester.runAsync(() async => _raw!.writeFromSync(bytes!));
    frame++;
  }

  bool _has(Finder f) => f.evaluate().isNotEmpty;

  Future<void> _hold(double secs) async {
    for (var i = 0; i < (secs * fps).round(); i++) {
      await _step();
    }
  }

  Future<void> _until(bool Function() cond, double maxSecs) async {
    for (var i = 0; i < (maxSecs * fps).round() && !cond(); i++) {
      await _step();
    }
    if (!cond()) debugPrint('WAITED OUT at ${t.toStringAsFixed(1)} s on $_screen');
  }

  Future<void> _tap(Finder f) async {
    if (!_has(f)) {
      debugPrint('MISSING $f at ${t.toStringAsFixed(1)} s on $_screen');
      return;
    }
    // a button below the fold scrolls into view first, on camera, as a thumb would bring it up
    final el = f.last.evaluate().first;
    if (Scrollable.maybeOf(el) != null) {
      unawaited(Scrollable.ensureVisible(el,
          duration: const Duration(milliseconds: 700), curve: Curves.easeInOut, alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd));
      await _hold(0.9);
    }
    await tester.tap(f.last, warnIfMissed: false);
    await tester.pump();
    await _settle(); // a sheet or the next screen's pictures
  }

  void _log(String what) => debugPrint('== $what at ${t.toStringAsFixed(1)} s');

  /// The cinematic's plates and the onboarding's sprites, decoded before the camera rolls.
  Future<void> _preload() async {
    const palettes = ['amber', 'forest', 'coral', 'ocean', 'amethyst', 'obsidian'];
    final names = <String>[
      'lumen_print', 'map_lit', 'map_faded', 'map_hollow', 'village_dusk', 'glasshouse_night', 'pip', 'pip_gold', 'steps', 'nest', 'nest_empty',
      for (final p in palettes) ...['nest_egg_$p', 'egg_${p}_0'],
      for (var k = 1; k < 4; k++) 'egg_${_palette}_$k',
      'egg_shards_$_palette',
      for (var i = 0; i < 36; i++) 'elder_${_palette}_${i.toString().padLeft(2, '0')}',
    ];
    await tester.runAsync(() async {
      for (final n in names) {
        try {
          await AtlasCache.load('$cineDir/$n.webp');
        } catch (e) {
          debugPrint('preload $n: $e');
        }
      }
    });
  }
}
