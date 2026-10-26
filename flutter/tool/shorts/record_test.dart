// The Shorts recorder: the real game played under a fixed clock (every frame an exact 1/30 s step at
// 1080x1920, however long a frame takes to capture), an autopilot at the controls, captions and the
// end card drawn over it in the game's own type. It writes, per Short, the frames, the sounds the game
// made and when, and the music it asked for; tools/shorts/encode.py turns that into an MP4.
//
//   flutter test tool/shorts/record_test.dart --dart-define=SHORTS=sentinel,briarback
//
// Run on the PC by 1_check.bat when _transfer/run_shorts.flag exists (its first line names the Shorts).
// Frames land in _shorts/<id>/f_00000.png, with cues.json (sounds, music) and meta.json.

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
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
import 'package:evochi/features/wilds/wilds_combat.dart';
import 'package:evochi/features/village/village_walk.dart';
import 'package:evochi/features/wilds/wilds_screen.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' hide AssetManifest;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'shorts.dart';

const fps = 30;
const _frame = Duration(microseconds: 1000000 ~/ fps);

void main() {
  final want = const String.fromEnvironment('SHORTS', defaultValue: 'all').split(',').map((s) => s.trim()).toSet();
  const outRoot = String.fromEnvironment('SHORTS_OUT', defaultValue: '_shorts');

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
    // the Material icons (the back arrow, the pad's glyphs)
    final icons = FontLoader('MaterialIcons')..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
    await AssetManifest.load();
    await SceneFx.load();
  });

  for (final sh in [...allShorts, ...weekShorts, bench]) {
    if (want.contains('all') ? sh == bench : !want.contains(sh.id)) continue;
    testWidgets('record ${sh.id}', (tester) async {
      final dir = Directory('$outRoot/${sh.id}');
      await tester.runAsync(() async {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
        dir.createSync(recursive: true);
        if (_stop.existsSync()) _stop.deleteSync();
      });
      // nothing cached by an earlier Short's clock (a pending future from a finished test never completes)
      rootBundle.clear();
      await Recorder(tester, sh, dir).run();
    }, timeout: const Timeout(Duration(minutes: 60)));
  }
}

final _stop = File('_transfer/stop_shorts.flag');

/// A save that never writes (and leaves no timers behind).
class _Fade extends PageTransitionsBuilder {
  const _Fade();
  @override
  Widget buildTransitions<T>(PageRoute<T> route, BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation, Widget child) =>
      FadeTransition(opacity: animation, child: child);
}

class _NoSave extends GameRepository {
  _NoSave() : super(local: MemoryStore());
  @override
  void save(GameState state) {}
}

class Recorder implements Take {
  Recorder(this.tester, this.short, this.dir);
  final WidgetTester tester;
  final Short short;
  final Directory dir;
  @override
  int frame = 0;
  bool capturing = false;
  final time = ValueNotifier<double>(0);
  final endAt = ValueNotifier<double?>(null);
  final live = <Cap>[];
  final _shot = GlobalKey();
  final cues = <Map<String, Object?>>[];
  RandomAccessFile? _raw; // every frame, raw RGBA, one after another (frames.rgba)
  final _sw = Stopwatch()..start();
  double _tPump = 0, _tGrab = 0, _tWrite = 0;
  final pilot = Pilot();
  late GameController controller;
  int _clip = 0;

  @override
  double get t => frame / fps;
  @override
  WildsDirectorHandle? get screen => WildsScreen.current;
  @override
  Raid? get raid => WildsScreen.current?.raid;
  @override
  VillageWalkScreenState? get walk => VillageWalkScreen.current;
  @override
  Pilot get autopilot => pilot;
  @override
  GameState get state => controller.state;
  @override
  GameController get ctl => controller;
  Clip? _current;

  /// Whatever is up has its pictures: a Wilds floor its map and fight, a walkable map its tiles, a
  /// sheet straight away (or the clip's own word on it).
  bool get _up {
    final own = _current?.loaded;
    if (own != null) return own();
    if (WildsScreen.current != null) return raid != null;
    final w = VillageWalkScreen.current;
    if (w != null) return w.ready;
    return true;
  }

  @override
  Future<void> tapText(String text) async {
    await tester.tap(find.text(text).last, warnIfMissed: false);
    await tester.pump();
  }

  Future<void> run() async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    AudioService.record = cues;
    AudioService.clock = () => capturing ? t : -1;
    WildsScreen.director = (r, i, at) => pilot(r, i, at);
    WildsScreen.plainArt = !const bool.fromEnvironment('SHORTS_FX');
    WildsScreen.recordZoom = 0.8;
    _raw = await tester.runAsync(() => File('${dir.path}/frames.rgba').open(mode: FileMode.write));
    try {
      for (var i = 0; i < short.clips.length; i++) {
        _clip = i;
        await _playClip(short.clips[i]);
      }
      await _endCard();
    } finally {
      await tester.runAsync(() async => _raw?.closeSync());
      AudioService.record = null;
      AudioService.clock = null;
      WildsScreen.director = null;
      VillageWalkScreenState.onExit = null;
      WildsScreen.recordZoom = 1.0;
      WildsScreen.recordQuiet = false;
      await tester.pumpWidget(const SizedBox());
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 250));
      }
    }
    final meta = {'id': short.id, 'fps': fps, 'frames': frame, 'w': _w, 'h': _h, 'format': 'rgba', 'music': short.music};
    await tester.runAsync(() async {
      File('${dir.path}/cues.json').writeAsStringSync(jsonEncode(cues));
      File('${dir.path}/meta.json').writeAsStringSync(jsonEncode(meta));
    });
  }

  Widget _stage(Widget game) => ChangeNotifierProvider.value(
        value: controller,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          // a plain fade between floors (the zoom transition shows a still of the new floor taken
          // while it was loading)
          theme: evochiTheme().copyWith(pageTransitionsTheme: const PageTransitionsTheme(builders: {
            TargetPlatform.android: _Fade(),
            TargetPlatform.iOS: _Fade(),
            TargetPlatform.windows: _Fade(),
            TargetPlatform.linux: _Fade(),
            TargetPlatform.macOS: _Fade(),
          })),
          home: game,
          // the camera sits above the navigator, so a new floor (a replaced route) stays in shot
          builder: (context, child) => RepaintBoundary(
            key: _shot,
            child: Stack(children: [
              Positioned.fill(child: child ?? const SizedBox()),
              Positioned.fill(
                  child: IgnorePointer(
                      child: Material(type: MaterialType.transparency, child: Overlays(short: short, time: time, live: live, endAt: endAt)))),
            ]),
          ),
        ),
      );

  Future<void> _playClip(Clip c) async {
    // a clean slate for every clip (its own save, screen and navigator)
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    controller = GameController(repo: _NoSave())
      ..state = c.state()
      ..ready = true;
    pilot.reset(c.pilot);
    mark = null;
    _current = c;
    VillageWalkScreenState.onExit = c.exits ? null : (_) {};
    WildsScreen.recordZoom = c.zoom;
    WildsScreen.recordQuiet = c.quiet;
    await tester.pumpWidget(_stage(KeyedSubtree(key: ValueKey('clip$_clip'), child: c.open())));
    await waitLoaded();
    // before the camera rolls: set things up, let it settle (nothing is captured)
    capturing = false;
    await c.setup?.call(this);
    for (var i = 0; i < (c.preroll * fps).round(); i++) {
      await tester.pump(_frame);
    }
    capturing = true;
    final start = t;
    final fired = <int>{};
    final n = (c.secs * fps).round();
    for (var i = 0; i < n; i++) {
      if (c.until != null && _up && c.until!(this)) break;
      final at = t - start;
      for (var k = 0; k < c.beats.length; k++) {
        final b = c.beats[k];
        // the hook (a beat in the short's first tenth of a second) is up from the very first frame
        final due = _clip == 0 && b.at <= 0.1 ? 0.0 : b.at;
        if (fired.contains(k) || at < due) continue;
        if (b.when != null && !b.when!(this)) continue;
        fired.add(k);
        await b.run(this);
      }
      await step();
    }
  }

  /// One frame: the clock moves on 1/30 s, the picture is saved.
  @override
  Future<void> step() async {
    // Claude can stop a run that is going wrong (_transfer/stop_shorts.flag)
    if (_stop.existsSync()) throw StateError('stopped by _transfer/stop_shorts.flag');
    final a = _sw.elapsedMicroseconds;
    // the overlays drawn at this frame's time (set before the pump, so the frame being captured shows
    // what was said at it: the hook is on frame 0)
    time.value = t;
    await tester.pump(_frame);
    _tPump += (_sw.elapsedMicroseconds - a) / 1e6;
    // a new floor loading (the descent swaps the screen), or a new map: hold the clock until it is up,
    // so the video never shows the loading spinner
    if (capturing && !_up) await waitLoaded();
    await _snap();
    if (frame % 15 == 0) {
      // where the time goes (to the log)
      debugPrint('frame $frame  pump ${(_tPump / frame).toStringAsFixed(3)}s  grab ${(_tGrab / frame).toStringAsFixed(3)}s  write ${(_tWrite / frame).toStringAsFixed(3)}s');
      debugPrint('  ${screen?.debugLine}');
    }
  }

  /// Wait (no time passes in the game, nothing is captured) until the Wilds screen that is up has its
  /// map and fight, and its pictures had a moment to decode.
  @override
  Future<void> waitLoaded() async {
    for (var i = 0; i < 400 && !_up; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 25)));
      await tester.pump();
    }
    for (var i = 0; i < 40; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 25)));
      await tester.pump();
    }
  }

  /// A key as if pressed (the Wilds' playtesting shortcuts).
  @override
  Future<void> key(LogicalKeyboardKey k) async {
    final before = screen;
    screen?.key(k);
    await tester.pump();
    // a shortcut that swaps the screen (a new floor): wait for the new one to load, the clock held
    if (!identical(screen, before) || !_up) await waitLoaded();
  }

  static const _scale = int.fromEnvironment('SHORTS_SCALE', defaultValue: 3) * 1.0;
  int get _w => (360 * _scale).round();
  int get _h => (640 * _scale).round();

  Future<void> _snap() async {
    final ro = _shot.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (ro == null) return;
    time.value = t;
    final a = _sw.elapsedMicroseconds;
    final bytes = await tester.runAsync(() async {
      final img = await ro.toImage(pixelRatio: _scale);
      final bd = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
      img.dispose();
      return bd!.buffer.asUint8List();
    });
    final b = _sw.elapsedMicroseconds;
    _tGrab += (b - a) / 1e6;
    await tester.runAsync(() async => _raw!.writeFromSync(bytes!));
    _tWrite += (_sw.elapsedMicroseconds - b) / 1e6;
    frame++;
  }

  /// The end card over the last moment of the game (it keeps going, quieter, under the card).
  Future<void> _endCard() async {
    pilot.on = false;
    endAt.value = t;
    final n = (short.endSecs * fps).round();
    for (var i = 0; i < n; i++) {
      await step();
    }
  }

  @override
  int get clip => _clip;

  @override
  double? mark;

  @override
  void say(List<(String, Color)> spans, {double secs = 2.0, double size = 26, double y = 190}) {
    // one caption at a time: whatever is still up gives way
    for (final c in live) {
      if (c.t1 > t) c.t1 = t;
    }
    live.add(Cap(t, t + secs, spans, size: size, y: y));
    // the overlays rebuild on the clock: nudge it so a caption said now is drawn on the next pump
    time.value = t + 1e-7 * (++_said);
  }

  int _said = 0;
}

/// Captions, the @handle and series stamp, the end card: drawn over the game in its own type.
class Overlays extends StatelessWidget {
  const Overlays({super.key, required this.short, required this.time, required this.live, required this.endAt});
  final Short short;
  final ValueListenable<double> time;
  final List<Cap> live; // captions placed by beats as they fired
  final ValueListenable<double?> endAt;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<double>(
        valueListenable: time,
        builder: (context, t, _) {
          final end = endAt.value ?? double.infinity;
          return Stack(children: [
            for (final c in [...short.caps, ...live])
              if (t >= c.t0 && t < c.t1 + 0.12 && t < end) _caption(c, t),
            if (t >= end) _endCard(t - end),
          ]);
        },
      );

  static double _pop(double since, double dur) {
    if (since <= 0) return 0;
    if (since >= dur) return 1;
    return Curves.easeOutBack.transform(since / dur);
  }

  Widget _caption(Cap c, double t) {
    // the hook is whole on the first frame (it is the video's cover); later captions pop in
    final pin = c.t0 < 0.05 ? 1.0 : _pop(t - c.t0, 0.34);
    final out = t > c.t1 ? 1 - (t - c.t1) / 0.12 : 1.0;
    final wob = 1 + 0.005 * math.sin((t - c.t0) * 3);
    final tilt = ((c.t0 * 7) % 3 - 1.5 + 0.25 * math.sin((t - c.t0) * 1.5)) * math.pi / 180;
    final base = TextStyle(fontFamily: 'Nunito', fontWeight: FontWeight.w900, fontSize: c.size, height: 1.08, letterSpacing: -0.01 * c.size);
    List<TextSpan> spans(bool stroke) => [
          for (final (text, col) in c.spans)
            TextSpan(
                text: text,
                style: stroke
                    ? base.copyWith(
                        foreground: Paint()
                          ..style = PaintingStyle.stroke
                          ..strokeWidth = c.size * 0.17
                          ..strokeJoin = StrokeJoin.round
                          ..color = const Color(0xFF3B2923))
                    : base.copyWith(color: col)),
        ];
    return Positioned(
      left: 23,
      right: 23,
      top: c.y,
      child: Opacity(
        opacity: out.clamp(0.0, 1.0),
        child: Transform.rotate(
          angle: tilt,
          child: Transform.scale(
            scale: pin * wob,
            child: Stack(alignment: Alignment.center, children: [
              Transform.translate(
                offset: Offset(0, c.size * 0.09),
                child: Text.rich(TextSpan(children: spans(true)),
                    textAlign: TextAlign.center, style: const TextStyle(shadows: [Shadow(color: Color(0x5A000000), blurRadius: 10, offset: Offset(0, 4))])),
              ),
              Text.rich(TextSpan(children: spans(true)), textAlign: TextAlign.center),
              Text.rich(TextSpan(children: spans(false)), textAlign: TextAlign.center),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _endCard(double since) {
    final p = _pop(since, 0.4);
    final fade = (since / 0.15).clamp(0.0, 1.0);
    final pulse = since > 0.6 ? 1 + 0.035 * math.max(0, math.sin((since - 0.6) * 4.2)) : 1.0;
    const ink = Color(0xFF3B2923);
    return Stack(children: [
      Positioned.fill(child: ColoredBox(color: Color.fromRGBO(24, 18, 32, 0.45 * fade))),
      Positioned(
        left: 30,
        right: 30,
        top: 92,
        child: Opacity(
          opacity: fade,
          child: Transform.translate(
            offset: Offset(0, (1 - p) * 20),
            child: Transform.scale(
              scale: 0.5 + 0.5 * p,
              child: Container(
                padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
                decoration: BoxDecoration(
                  color: const Color(0xF7FFF9F0),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFC9A78C), width: 1.7),
                  boxShadow: const [
                    BoxShadow(color: Color(0xFFD8BD9F), offset: Offset(0, 3.3)),
                    BoxShadow(color: Color(0x59283C1E), blurRadius: 27, offset: Offset(0, 13)),
                  ],
                ),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Image.asset('assets/art/titles/wordmark_evochi.webp', width: 173, filterQuality: FilterQuality.medium),
                  const SizedBox(height: 8),
                  Text.rich(
                    TextSpan(children: [
                      for (final (text, col) in short.endTitle) TextSpan(text: text, style: TextStyle(color: col ?? ink)),
                    ]),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontFamily: 'Nunito', fontWeight: FontWeight.w900, fontSize: 28.5, height: 1.06, letterSpacing: -0.5, color: ink),
                  ),
                  const SizedBox(height: 10),
                  Transform.rotate(
                    angle: -1.5 * math.pi / 180,
                    child: Transform.scale(
                      scale: pulse,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Color(0xFFFFE5A2), Color(0xFFF9CA70), Color(0xFFF4B84E), Color(0xFFE9A541)],
                              stops: [0, 0.38, 0.7, 1]),
                          borderRadius: BorderRadius.circular(9),
                          border: Border.all(color: const Color(0xFFC8832C), width: 1.7),
                          boxShadow: const [BoxShadow(color: Color(0xFFC8832C), offset: Offset(0, 3.3))],
                        ),
                        child: Text(short.cta, style: const TextStyle(fontFamily: 'Nunito', fontWeight: FontWeight.w900, fontSize: 20.5, color: ink)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 9),
                  const Text('link in bio', style: TextStyle(fontFamily: 'Nunito', fontWeight: FontWeight.w900, fontSize: 15.3, color: Color(0xFF477B3A))),
                  const SizedBox(height: 6),
                  const Text('@evochigame', style: TextStyle(fontFamily: 'Nunito', fontWeight: FontWeight.w800, fontSize: 12, color: Color(0xFF8A6A55))),
                ]),
              ),
            ),
          ),
        ),
      ),
    ]);
  }
}
