// Developer tools: the personality lab. Shows who your Evochi is (its saved traits, profile, signature, habits,
// repertoires and style), lets you ask a preview director what it would do in a context and mood (every
// candidate's weight, its factors, what was ruled out and why, the cooldowns that follow), force any behaviour,
// play the three profiles side by side, and play any emotion (assets/config/emotions.json) at any intensity on
// any personality, to see how the same feeling looks on different companions. Nothing here is saved: it never
// changes the companion.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../controllers/game_controller.dart';
import '../../game/emotion/emotion.dart';
import '../../game/personality/catalog.dart';
import '../../game/personality/director.dart';
import '../../game/personality/personality.dart';
import '../shared/acting.dart';
import '../shared/scene_view.dart';
import '../shared/widgets.dart';

const _contexts = ['idle', 'hatch', 'feed', 'pet', 'play', 'reward', 'return', 'wilds_open', 'wilds_calmed'];

Future<void> openPersonalityLab(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const PersonalityLabScreen()));

class PersonalityLabScreen extends StatefulWidget {
  const PersonalityLabScreen({super.key});
  @override
  State<PersonalityLabScreen> createState() => _PersonalityLabScreenState();
}

class _PersonalityLabScreenState extends State<PersonalityLabScreen> {
  String _context = 'idle';
  double _content = 0.6, _excited = 0.3, _tired = 0.2;
  int? _seed; // a preview seed (null: your Evochi's own personality)
  BehaviorDirector? _director;
  Choice? _choice;
  String? _forced;
  int _replay = 0, _sideReplay = 0;
  double _now = 0;
  final _feelScene = SceneController();
  String _emotion = 'happy';
  double _intensity = 1;

  Personality _who(GameController c) {
    final s = _seed;
    if (s != null) return generatePersonality(s);
    return c.state.pet?.personality ?? generatePersonality(1);
  }

  BehaviorDirector _dir(Personality p) {
    final d = _director;
    if (d != null && d.p.seed == p.seed && d.p.profile == p.profile) return d;
    return _director = BehaviorDirector(p, rng: math.Random(7));
  }

  Mood get _mood => Mood(content: _content, excited: _excited, tired: _tired);

  void _ask(Personality p) {
    _now += 5; // each ask is five seconds on: watch the cooldowns hold
    setState(() {
      _forced = null;
      _choice = _dir(p).choose(_context, _now, mood: _mood);
      _replay++;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<GameController>();
    final pet = c.state.pet;
    final p = _who(c);
    final d = _dir(p);
    final stage = pet?.stage ?? 1;
    final palette = pet?.paletteId ?? 'amber';
    final choice = _choice;
    final shown = _forced != null ? behaviors[_forced] : choice?.behavior;
    return Scaffold(
      backgroundColor: EvochiColor.canvas,
      appBar: AppBar(title: const Text('Personality lab', style: EvochiText.section), backgroundColor: EvochiColor.canvas),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
        GameCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_seed == null ? '${pet?.name ?? 'Your Evochi'} (saved)' : 'Preview seed $_seed (not saved)', style: EvochiText.cardTitle),
            Text('${profiles[p.profile]?.label ?? p.profile} · interested in ${p.interest} · seed ${p.seed} · v${p.version} · ${p.origin}', style: EvochiText.caption),
            const SizedBox(height: 8),
            for (final t in traitNames) _Bar(t, p.trait(t)),
            const SizedBox(height: 6),
            Text('Signature: ${p.signature}', style: EvochiText.bodyText),
            Text('Habits: ${p.habits.join(', ')}', style: EvochiText.bodyText),
            Text('Idle: ${p.idle.join(', ')}', style: EvochiText.bodyText),
            Text('Encounter: ${p.combat.entries.map((e) => '${e.key} ${e.value}').join(' · ')}', style: EvochiText.caption),
            Text('Style: ${p.style.entries.map((e) => '${e.key} ${e.value}').join(' · ')}', style: EvochiText.caption),
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 6, children: [
              EvochiButton(
                  label: 'New preview seed',
                  small: true,
                  expand: false,
                  tone: ButtonTone.cream,
                  onPressed: () => setState(() {
                        _seed = math.Random().nextInt(1 << 31);
                        _choice = null;
                      })),
              if (_seed != null)
                EvochiButton(
                    label: 'Back to mine',
                    small: true,
                    expand: false,
                    tone: ButtonTone.cream,
                    onPressed: () => setState(() {
                          _seed = null;
                          _choice = null;
                        })),
            ]),
          ]),
        ),
        const SizedBox(height: 10),
        GameCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Ask the director', style: EvochiText.cardTitle),
            Wrap(spacing: 4, runSpacing: 4, children: [
              for (final k in _contexts) ChoiceChip(label: Text(k), selected: _context == k, onSelected: (_) => setState(() => _context = k)),
            ]),
            _Slider('content', _content, (v) => setState(() => _content = v)),
            _Slider('excited', _excited, (v) => setState(() => _excited = v)),
            _Slider('tired', _tired, (v) => setState(() => _tired = v)),
            Row(children: [
              Expanded(child: EvochiButton(label: 'What would it do?', small: true, onPressed: () => _ask(p))),
              const SizedBox(width: 8),
              EvochiButton(
                  label: 'Reset cooldowns',
                  small: true,
                  expand: false,
                  tone: ButtonTone.cream,
                  onPressed: () => setState(() {
                        _director = null;
                        _choice = null;
                      })),
            ]),
            const SizedBox(height: 8),
            Center(
              child: SizedBox(
                height: 170,
                child: ActingSprite(
                  key: ValueKey('lab:${p.seed}:$stage:$palette'),
                  stage: stage,
                  palette: palette,
                  personality: p,
                  behavior: shown ?? behaviors[neutralIdle],
                  replay: _replay,
                  delay: const Duration(milliseconds: 60),
                  height: 160,
                ),
              ),
            ),
            if (shown != null) Text('${shown.id}: ${describeBehavior(shown)}', style: EvochiText.bodyText, textAlign: TextAlign.center),
            if (choice != null && _forced == null) ...[
              const SizedBox(height: 8),
              const Text('Candidates', style: EvochiText.tag),
              for (final s in ([...choice.candidates]..sort((a, b) => b.weight.compareTo(a.weight))))
                if (s.excluded == null)
                  Text('${s.id == choice.behavior.id ? '▶ ' : ''}${s.id}  ${s.weight.toStringAsFixed(3)}  ${s.factors.entries.map((e) => '${e.key} ${e.value.toStringAsFixed(2)}').join(' · ')}',
                      style: EvochiText.tiny),
              const SizedBox(height: 4),
              const Text('Ruled out', style: EvochiText.tag),
              Text(choice.candidates.where((s) => s.excluded != null && s.excluded != 'context').map((s) => '${s.id} (${s.excluded})').join(', '), style: EvochiText.tiny),
            ],
            const SizedBox(height: 6),
            Text(
                'Cooldowns at ${_now.toStringAsFixed(0)} s: ${d.cooldownUntil.entries.where((e) => e.value > _now).map((e) => '${e.key} ${(e.value - _now).toStringAsFixed(0)} s').join(', ')}'
                '${d.signatureUntil > _now ? ' · signatures rest ${(d.signatureUntil - _now).toStringAsFixed(0)} s' : ''}',
                style: EvochiText.tiny),
          ]),
        ),
        const SizedBox(height: 10),
        GameCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Force a behaviour', style: EvochiText.cardTitle),
            const Text('Plays it whatever the director would choose.', style: EvochiText.caption),
            const SizedBox(height: 6),
            Wrap(spacing: 4, runSpacing: 4, children: [
              for (final b in behaviors.values.where((b) => b.kind != 'combat'))
                ActionChip(
                    label: Text(b.id),
                    onPressed: () => setState(() {
                          _forced = b.id;
                          _replay++;
                        })),
            ]),
          ]),
        ),
        const SizedBox(height: 10),
        GameCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Emotions', style: EvochiText.cardTitle),
            Text(
                Emotions.table.isEmpty
                    ? 'No emotions loaded (assets/config/emotions.json).'
                    : 'How a feeling looks on this personality: its face, a motion sized by the intensity, its expressiveness and style, and what it settles into.',
                style: EvochiText.caption),
            const SizedBox(height: 6),
            Wrap(spacing: 4, runSpacing: 4, children: [
              for (final e in Emotions.table.keys) ChoiceChip(label: Text(e), selected: _emotion == e, onSelected: (_) => setState(() => _emotion = e)),
            ]),
            _Slider('intensity', _intensity, (v) => setState(() => _intensity = v)),
            SizedBox(
              height: 200,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: HabitatScene(
                  key: ValueKey('feel:${p.seed}:$stage:$palette'),
                  controller: _feelScene,
                  config: SceneConfig(
                    habitat: 'meadow',
                    focus: const Offset(0.5, 0.86),
                    reducedMotion: MediaQuery.of(context).disableAnimations,
                    pet: PetConfig(stage: stage, palette: palette, personality: p),
                  ),
                ),
              ),
            ),
            if (Emotions.of(_emotion) case final e?)
              Text('${e.id}: face ${e.face('evochi')}${e.end('evochi') != null ? ' then ${e.end('evochi')}' : ''} · ${e.motion} · ${e.ms} ms · priority ${e.priority}${e.next != null ? ' · then ${e.next}' : ''}',
                  style: EvochiText.tiny),
            const SizedBox(height: 6),
            EvochiButton(label: 'Feel it', small: true, onPressed: () => _feelScene.feel(_emotion, intensity: _intensity)),
          ]),
        ),
        const SizedBox(height: 10),
        GameCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('The three side by side', style: EvochiText.cardTitle),
            Text('Each profile\'s choice for "$_context", from a fresh director each time.', style: EvochiText.caption),
            const SizedBox(height: 6),
            Row(children: [
              for (final prof in profiles.keys)
                Expanded(
                  child: Column(children: [
                    SizedBox(
                      height: 120,
                      child: ActingSprite(
                        key: ValueKey('side:$prof'),
                        stage: stage,
                        palette: palette,
                        personality: generatePersonality(11, profile: prof),
                        director: BehaviorDirector(generatePersonality(11, profile: prof), rng: math.Random(_sideReplay)),
                        context: _context,
                        replay: _sideReplay,
                        delay: const Duration(milliseconds: 60),
                        height: 110,
                      ),
                    ),
                    Text(profiles[prof]!.label, style: EvochiText.tag),
                  ]),
                ),
            ]),
            const SizedBox(height: 6),
            EvochiButton(label: 'Play all three', small: true, onPressed: () => setState(() => _sideReplay++)),
          ]),
        ),
      ]),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar(this.name, this.v);
  final String name;
  final double v;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          SizedBox(width: 110, child: Text(name, style: EvochiText.tiny)),
          Expanded(child: LinearProgressIndicator(value: v, minHeight: 8, color: EvochiColor.steps, backgroundColor: const Color(0x22000000))),
          SizedBox(width: 40, child: Text(v.toStringAsFixed(2), style: EvochiText.tiny, textAlign: TextAlign.right)),
        ]),
      );
}

class _Slider extends StatelessWidget {
  const _Slider(this.name, this.v, this.onChanged);
  final String name;
  final double v;
  final ValueChanged<double> onChanged;
  @override
  Widget build(BuildContext context) => Row(children: [
        SizedBox(width: 70, child: Text(name, style: EvochiText.tiny)),
        Expanded(child: Slider(value: v, onChanged: onChanged)),
        SizedBox(width: 34, child: Text(v.toStringAsFixed(2), style: EvochiText.tiny)),
      ]);
}
