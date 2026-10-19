// Lumen Trails: the trip to an encounter. The scene pans in slowly while three lines of the journey
// fade in one after another; then Continue (or Skip at any time) arrives at the encounter.
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

class _TravelScreenState extends State<TravelScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _pan = AnimationController(vsync: this, duration: const Duration(seconds: 9));
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
    if (!_reduce) _pan.forward();
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final e = tr.encounterDefs[widget.questId] ?? tr.encounterDefs['eq01']!;
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
