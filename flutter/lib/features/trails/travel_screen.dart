// Lumen Trails: the trip to an encounter. The scene pans in slowly while motes rise from it (gold to
// a wild one, violet to the Hollow) and three lines of the journey fade in one after another; then
// Continue (or Skip at any time) arrives at the encounter.
// Mirrors `travel` in web/src/screens/trails.js.

import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../game/trails/trails.dart' as tr;
import '../shared/widgets.dart';
import 'encounter_screen.dart';
import 'trails_widgets.dart';

const _travelLines = <String, List<String>>{
  'eq01': [
    'You follow the petals along the old trail.',
    'The forest hushes. Moss, flagstones, the sound of water.',
    'You arrive at a quiet ruin. Something small is watching from the arch.',
  ],
  'eq02': [
    'The Lumen Trace hums in your pocket as you walk.',
    'Purple light flickers between the stones ahead.',
    'You arrive at the ruins. The vines have grown thick, and they glow.',
  ],
  'eq03': [
    'The north road is overgrown, but the map is clear.',
    'The old bridge creaks under your feet, and holds.',
    'Beyond it, in the dusk, a gate. And in the gate, something that remembers you.',
  ],
};

class TravelScreen extends StatefulWidget {
  const TravelScreen({super.key, required this.questId});
  final String questId;
  @override
  State<TravelScreen> createState() => _TravelScreenState();
}

class _TravelScreenState extends State<TravelScreen> with TickerProviderStateMixin {
  late final AnimationController _pan = AnimationController(vsync: this, duration: const Duration(seconds: 9));
  // the entry motes: travelMote 4.2s ease-in-out, each one a little later
  late final AnimationController _motes = AnimationController(vsync: this, duration: const Duration(milliseconds: 4200));
  Timer? _timer;
  int _i = 0;
  bool _cta = false;
  bool _reduce = false;
  bool _started = false;

  List<String> get _lines => _travelLines[widget.questId] ?? _travelLines['eq01']!;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduce = MediaQuery.of(context).disableAnimations;
    if (_started) return;
    _started = true;
    if (!_reduce) {
      _pan.forward();
      _motes.repeat();
    }
    _timer = Timer(Duration(milliseconds: _reduce ? 1000 : 2200), _step);
  }

  void _step() {
    if (!mounted) return;
    if (_i < _lines.length - 1) {
      setState(() => _i++);
      _timer = Timer(Duration(milliseconds: _reduce ? 1200 : 2200), _step);
    } else {
      setState(() => _cta = true);
    }
  }

  void _arrive() {
    _timer?.cancel();
    Navigator.of(context).pushReplacement(MaterialPageRoute<void>(settings: const RouteSettings(name: 'encounter'), builder: (_) => const EncounterScreen(fresh: true)));
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pan.dispose();
    _motes.dispose();
    super.dispose();
  }

  /// One rising mote of light (18 of them, spread across the scene, in a few sizes).
  Widget _mote(int i, Size screen, bool hollow) {
    final t = (_motes.value + i * 0.37 / 4.2) % 1.0;
    final m = Curves.easeInOut.transform(t);
    final op = t < 0.2 ? 0.95 * Curves.easeInOut.transform(t / 0.2) : 0.95 * (1 - Curves.easeInOut.transform((t - 0.2) / 0.8));
    final d = 7 * (0.6 + ((i * 7) % 5) / 6);
    return Positioned(
      left: screen.width * (6 + (i * 37) % 88) / 100 + 14 * m,
      bottom: screen.height * 0.16 + screen.height * 0.46 * m,
      child: Opacity(
        opacity: op.clamp(0.0, 1.0),
        child: Container(
          width: d,
          height: d,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: hollow ? const Color(0xFFE0CCFF) : const Color(0xFFFFE9A0),
            boxShadow: [BoxShadow(color: hollow ? const Color(0xCCAA6EFF) : const Color(0xBFFFDC78), blurRadius: 10, spreadRadius: 3)],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final e = tr.encounterDefs[widget.questId] ?? tr.encounterDefs['eq01']!;
    final hollow = e.goal != 'befriend';
    final ta = trailsArt;
    final mq = MediaQuery.of(context);
    return Scaffold(
      backgroundColor: const Color(0xFF1E1A26),
      body: Stack(fit: StackFit.expand, children: [
        if (ta.available && ta.hasScene(e.scene))
          AnimatedBuilder(
            animation: _pan,
            builder: (ctx, child) {
              final t = Curves.easeInOut.transform(_pan.value);
              final scale = _reduce ? 1.0 : 1.18 - 0.18 * t;
              final dx = _reduce ? 0.0 : -0.03 * (1 - t) * mq.size.width;
              return Transform.translate(offset: Offset(dx, 0), child: Transform.scale(scale: scale, alignment: const Alignment(0, -0.2), child: child));
            },
            child: Image.asset(ta.scene(e.scene), fit: BoxFit.cover, alignment: const Alignment(0, -0.1), excludeFromSemantics: true),
          ),
        const IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x591E1A26), Color(0x001E1A26), Color(0x001E1A26), Color(0xD91E1A26)],
                stops: [0, 0.3, 0.55, 1],
              ),
            ),
          ),
        ),
        // motes of light rising toward the encounter (not with reduced motion)
        if (!_reduce)
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _motes,
                builder: (ctx, _) => Stack(clipBehavior: Clip.hardEdge, children: [for (var i = 0; i < 18; i++) _mote(i, mq.size, hollow)]),
              ),
            ),
          ),
        SafeArea(
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Row(children: [
                Semantics(label: 'Skip', child: BackSquareButton(onTap: _arrive)),
                const SizedBox(width: 8),
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      tr.placeTitle(e.place),
                      textAlign: TextAlign.center,
                      style: EvochiText.section.copyWith(color: Colors.white, fontWeight: FontWeight.w900, shadows: const [Shadow(color: Color(0x99000000), blurRadius: 4)]),
                    ),
                  ),
                ),
                const SizedBox(width: 54),
              ]),
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 18),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                GameCard(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                  child: Semantics(
                    liveRegion: true,
                    child: AnimatedSwitcher(
                      duration: Duration(milliseconds: _reduce ? 0 : 600),
                      transitionBuilder: (child, a) => FadeTransition(opacity: a, child: child),
                      child: Text(
                        _lines[_i],
                        key: ValueKey(_i),
                        style: EvochiText.bodyText.copyWith(fontSize: 16, height: 1.45, fontStyle: FontStyle.italic, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                AnimatedOpacity(
                  opacity: _cta ? 1 : 0,
                  duration: const Duration(milliseconds: 400),
                  child: IgnorePointer(ignoring: !_cta, child: EvochiButton(label: 'Continue', tone: ButtonTone.green, onPressed: _arrive)),
                ),
                const SizedBox(height: 4),
                TextButton(
                  onPressed: _arrive,
                  child: Text('Skip', style: EvochiText.button.copyWith(color: const Color(0xFFFFF6E6), fontSize: 16)),
                ),
              ]),
            ),
          ]),
        ),
      ]),
    );
  }
}
