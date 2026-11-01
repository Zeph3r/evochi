// The cast showcase (developer): Pip, Mira and a Coral Evochi performing in isolation, to tune their acting.
// Pip and Mira play their rendered lines (tools/art/cine_anim.py: talk, then the breathing idle) at the speed
// you pick, again on a tap; the Evochi plays any of its acting clips (tools/art/acting.py) in any personality's
// manner. Nothing here touches the game.

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../game/personality/catalog.dart';
import '../../game/personality/personality.dart';
import '../onboarding/posed_plate.dart';
import '../shared/acting.dart';
import '../shared/widgets.dart';

void openCastLab(BuildContext context) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const CastLab()));

class CastLab extends StatefulWidget {
  const CastLab({super.key});
  @override
  State<CastLab> createState() => _CastLabState();
}

class _CastLabState extends State<CastLab> {
  String _who = 'pip';
  double _speed = 1;
  int _take = 0;
  final _cue = PoseController();
  String _clip = neutralIdle;
  String _profile = 'lively';

  static const _speeds = [0.25, 0.5, 1.0, 1.5];

  @override
  Widget build(BuildContext context) {
    final evochi = _who == 'coral';
    return Scaffold(
      backgroundColor: EvochiColor.canvas,
      appBar: AppBar(title: const Text('Cast showcase', style: EvochiText.section), backgroundColor: EvochiColor.canvas),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'pip', label: Text('Pip')),
              ButtonSegment(value: 'mira', label: Text('Mira')),
              ButtonSegment(value: 'coral', label: Text('Coral Evochi')),
            ],
            selected: {_who},
            onSelectionChanged: (s) => setState(() {
              _who = s.first;
              _take++;
            }),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(children: [
            const Text('Speed', style: EvochiText.tag),
            const SizedBox(width: 8),
            for (final v in _speeds)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: Text('${v}x'),
                  selected: _speed == v,
                  onSelected: evochi ? null : (_) => setState(() {
                        _speed = v;
                        _take++;
                      }),
                ),
              ),
          ]),
        ),
        Expanded(
          child: evochi
              ? _evochi()
              : ClipRect(
                  child: PosedPlate(_who,
                      key: ValueKey('$_who:$_take:$_speed'),
                      alignment: Alignment(0, _who == 'pip' ? -0.35 : -0.25),
                      controller: _cue,
                      speed: _speed,
                      onMissing: const Center(child: Text('No plate in this build', style: EvochiText.bodyText))),
                ),
        ),
        if (!evochi)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              Expanded(child: EvochiButton(label: 'Say the line', small: true, onPressed: () => _cue.play('talk'))),
              const SizedBox(width: 8),
              Expanded(child: EvochiButton(label: 'Breathe', small: true, tone: ButtonTone.cream, onPressed: () => _cue.play('idle'))),
              const SizedBox(width: 8),
              Expanded(child: EvochiButton(label: 'From the top', small: true, tone: ButtonTone.cream, onPressed: () => setState(() => _take++))),
            ]),
          ),
      ]),
    );
  }

  Widget _evochi() {
    final p = generatePersonality(7, profile: _profile);
    return ListView(padding: const EdgeInsets.all(12), children: [
      SizedBox(
        height: 220,
        child: Center(
          child: ActingSprite(
            key: ValueKey('cast:$_profile'),
            stage: 1,
            palette: 'coral',
            personality: p,
            behavior: behaviors[_clip],
            replay: _take,
            delay: const Duration(milliseconds: 60),
            height: 200,
          ),
        ),
      ),
      const Text('Personality', style: EvochiText.tag),
      Wrap(spacing: 6, children: [
        for (final pr in const ['lively', 'calm', 'cautious'])
          ChoiceChip(
              label: Text(pr),
              selected: _profile == pr,
              onSelected: (_) => setState(() {
                    _profile = pr;
                    _take++;
                  })),
      ]),
      const SizedBox(height: 8),
      const Text('Gesture', style: EvochiText.tag),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final b in behaviors.values)
          ChoiceChip(
              label: Text(b.id),
              selected: _clip == b.id,
              onSelected: (_) => setState(() {
                    _clip = b.id;
                    _take++;
                  })),
      ]),
    ]);
  }
}
