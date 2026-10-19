// S01 Welcome, S02 Create, S03 Fitness connect, S04 Goal, S05 Awakening (style guide §08-09, §13).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/constants.dart';
import '../../app/theme.dart';
import '../../controllers/game_controller.dart';
import '../../core/utils/ids.dart';
import '../../data/health_adapters/step_source.dart';
import '../../game/engine.dart' as g;
import '../shared/scene_scaffold.dart';
import '../shared/scene_view.dart';
import '../shared/sprite.dart';
import '../shared/widgets.dart';

// ------------------------------------------------------------------ welcome ----
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});
  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  final _scene = SceneController();

  void _startGuest() {
    final c = context.read<GameController>();
    showEvochiSheet<void>(context, builder: (s) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Row(children: [VoxelIcon('paw', size: 40), SizedBox(width: 8), Text('Play as a guest', style: EvochiText.section)]),
        const SizedBox(height: 8),
        const Text(
          "Your Evochi is saved on this device. If you uninstall the app, a guest pet can't be recovered. You can add an account later in Settings.",
          style: EvochiText.bodyText,
        ),
        const SizedBox(height: 14),
        EvochiButton(
          label: 'Start my adventure',
          large: true,
          icon: const Icon(Icons.play_arrow_rounded, color: EvochiColor.ink),
          onPressed: () {
            Navigator.pop(s);
            c.run((st, n) => g.startGuest(st, n, st.tzHint));
            c.analytics.track('onboarding_started', {'method': 'guest'});
            c.audio.play('reward_chime', volume: 0.5);
          },
        ),
        const SizedBox(height: 10),
        EvochiButton(label: 'Not now', tone: ButtonTone.cream, onPressed: () => Navigator.pop(s)),
      ]);
    });
  }

  void _provider(String name) {
    showEvochiSheet<void>(context, builder: (s) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Continue with $name', style: EvochiText.section),
          const SizedBox(height: 8),
          Text(
            '$name sign-in links your Evochi to a cloud account so it follows you to new phones. '
            'It activates once the Firebase project is configured (see README). Until then you can play as a guest and link later.',
            style: EvochiText.bodyText,
          ),
          const SizedBox(height: 14),
          EvochiButton(label: 'Continue as Guest', onPressed: () {
            Navigator.pop(s);
            _startGuest();
          }),
        ]));
  }

  void _email() {
    final ctl = TextEditingController();
    String? err;
    showEvochiSheet<void>(context, builder: (s) => StatefulBuilder(builder: (s, set) {
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Continue with Email', style: EvochiText.section),
            const SizedBox(height: 8),
            TextField(
              controller: ctl,
              autofocus: true,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              decoration: InputDecoration(labelText: 'Email', errorText: err, filled: true, fillColor: EvochiColor.shell),
            ),
            const SizedBox(height: 12),
            EvochiButton(
              label: 'Continue',
              onPressed: () {
                final v = ctl.text.trim();
                if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v)) {
                  set(() => err = 'Enter a valid email address.');
                  return;
                }
                Navigator.pop(s);
                final c = context.read<GameController>();
                c.run((st, n) => g.startGuest(st, n, st.tzHint, accountType: 'email', email: v));
                c.analytics.track('onboarding_started', {'method': 'email'});
              },
            ),
          ]);
        }));
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.of(context).disableAnimations;
    return Scaffold(
      body: SceneScaffold(
        controller: _scene,
        onPetTap: () {
          _scene.react('pet');
          context.read<GameController>().audio.play('pet_chirp');
        },
        petLabel: 'Say hello',
        minHero: 210,
        groundOffset: 30,
        headerAllowance: 150,
        config: (gy) => SceneConfig(habitat: 'welcome', focus: Offset(0.5, gy), reducedMotion: reduce, pet: const PetConfig(stage: 1, palette: 'amber')),
        header: Padding(
          padding: const EdgeInsets.only(top: 30),
          child: Column(children: [
            Semantics(header: true, label: 'Evochi', child: ExcludeSemantics(child: Image.asset(art.title('wordmark_evochi'), width: 300))),
            const SizedBox(height: 6),
            const Text(
              'Every step brings your Evochi to life.',
              style: TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w900, fontSize: 17, color: EvochiColor.ink, shadows: [Shadow(color: Colors.white, blurRadius: 10)]),
            ),
          ]),
        ),
        hero: LayoutBuilder(builder: (c, b) {
          final cw = (b.maxWidth * 0.34).clamp(90.0, 140.0).toDouble();
          return Stack(children: [
            Positioned(left: b.maxWidth * 0.04, bottom: b.maxHeight * 0.38, child: _GlassCard(width: cw, stage: 2, expr: 'determined')),
            Positioned(right: b.maxWidth * 0.02, bottom: b.maxHeight * 0.45, child: _GlassCard(width: cw * 1.05, stage: 3, expr: 'default')),
          ]);
        }),
        panel: Padding(
          padding: const EdgeInsets.fromLTRB(26, 0, 26, 14),
          child: SafeArea(
            top: false,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              EvochiButton(label: 'Begin Your Journey', large: true, icon: const Icon(Icons.play_arrow_rounded, color: EvochiColor.ink, size: 30), onPressed: _startGuest),
              const SizedBox(height: 10),
              EvochiButton(label: 'Continue with Apple', tone: ButtonTone.cream, icon: const Icon(Icons.apple, color: EvochiColor.ink), onPressed: () => _provider('Apple')),
              const SizedBox(height: 10),
              EvochiButton(label: 'Continue with Google', tone: ButtonTone.cream, icon: const Icon(Icons.g_mobiledata_rounded, color: EvochiColor.ink, size: 30), onPressed: () => _provider('Google')),
              const SizedBox(height: 10),
              EvochiButton(label: 'Continue with Email', tone: ButtonTone.cream, icon: const Icon(Icons.mail_rounded, color: EvochiColor.wood), onPressed: _email),
              const SizedBox(height: 6),
              const Row(children: [
                Expanded(child: Divider(color: Color(0x55684C3C))),
                Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('Or', style: EvochiText.tag)),
                Expanded(child: Divider(color: Color(0x55684C3C))),
              ]),
              Center(child: EvochiButton(label: 'Try as Guest', tone: ButtonTone.cream, small: true, expand: false, onPressed: _startGuest)),
              const SizedBox(height: 8),
              const Text(
                'By continuing, you agree to our Terms of Service and Privacy Policy.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.white, shadows: [Shadow(color: Color(0xCC32200F), blurRadius: 3)]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _GlassCard extends StatelessWidget {
  const _GlassCard({required this.width, required this.stage, required this.expr});
  final double width;
  final int stage;
  final String expr;
  @override
  Widget build(BuildContext context) => Container(
        width: width,
        height: width * 0.8,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x6BFFFFFF), Color(0x2EFFFFFF)]),
          border: Border.all(color: const Color(0xBFFFFFFF), width: 1.5),
          boxShadow: const [BoxShadow(color: Color(0x8CFFF0BE), blurRadius: 22)],
        ),
        alignment: Alignment.center,
        child: ExcludeSemantics(child: PetSprite(stage: stage, palette: 'amber', expr: expr, height: width * 0.7)),
      );
}

// ------------------------------------------------------------------- create ----
class CreateScreen extends StatefulWidget {
  const CreateScreen({super.key});
  @override
  State<CreateScreen> createState() => _CreateScreenState();
}

class _CreateScreenState extends State<CreateScreen> {
  final _scene = SceneController();
  late final TextEditingController _name;
  String? _err;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: context.read<GameController>().state.onboarding.draftName);
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _palette(String id) {
    final c = context.read<GameController>();
    c.mutate((s) => s.onboarding.draftPalette = id);
    _scene.react('equip');
  }

  void _cycle(int dir) {
    final c = context.read<GameController>();
    final ids = palettes.map((p) => p.id).toList();
    final i = ids.indexOf(c.state.onboarding.draftPalette);
    _palette(ids[(i + dir + ids.length) % ids.length]);
  }

  void _confirm() {
    final c = context.read<GameController>();
    final v = g.validateName(_name.text);
    if (!v.ok) {
      setState(() => _err = v.error);
      return;
    }
    var req = c.state.onboarding.requestId;
    if (req == null) {
      req = newId('create');
      c.mutate((s) => s.onboarding.requestId = req);
    }
    final pal = c.state.onboarding.draftPalette;
    final r = c.run((s, n) => g.createPet(s, name: v.name, paletteId: pal, requestId: req!, now: n));
    if (r.ok) {
      c.audio.play('reward_chime');
      c.analytics.track('pet_created', {'palette': pal});
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<GameController>();
    final pal = c.state.onboarding.draftPalette;
    final again = c.state.pastPets.isNotEmpty;
    final reduce = MediaQuery.of(context).disableAnimations;
    return Scaffold(
      body: SceneScaffold(
        controller: _scene,
        onPetTap: () => _scene.react('pet'),
        petLabel: 'Preview your Evochi',
        minHero: 210,
        headerAllowance: 130,
        config: (gy) => SceneConfig(habitat: 'meadow', platform: true, focus: Offset(0.5, gy), reducedMotion: reduce, pet: PetConfig(stage: 1, palette: pal)),
        header: Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (!again)
              BackSquareButton(onTap: () => c.mutate((s) => s.player = null))
            else
              const SizedBox(width: 46),
            Expanded(
              child: Column(children: [
                TitleImage('title_create_your', height: 28, label: 'Create your Evochi'),
                ExcludeSemantics(child: Image.asset(art.title('wordmark_evochi'), height: 50)),
                const Tag('A small beginning, a big adventure.'),
              ]),
            ),
            const SizedBox(width: 46),
          ]),
        ),
        hero: Align(
          alignment: const Alignment(0, 0.55),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              _ArrowButton(icon: Icons.chevron_left_rounded, label: 'Previous colour', onTap: () => _cycle(-1)),
              _ArrowButton(icon: Icons.chevron_right_rounded, label: 'Next colour', onTap: () => _cycle(1)),
            ]),
          ),
        ),
        panel: Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          child: SafeArea(
            top: false,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              GameCard(
                padding: const EdgeInsets.fromLTRB(16, 8, 10, 8),
                child: Row(children: [
                  const Text('Name', style: EvochiText.cardTitle),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _name,
                      maxLength: GameConfig.current.nameMax,
                      onChanged: (v) {
                        c.mutate((s) => s.onboarding.draftName = v);
                        if (_err != null) setState(() => _err = null);
                      },
                      style: EvochiText.number.copyWith(fontSize: 20),
                      decoration: InputDecoration(
                        counterText: '',
                        hintText: 'Ember',
                        errorText: _err,
                        filled: true,
                        fillColor: EvochiColor.inset,
                        suffixIcon: const Icon(Icons.edit_rounded, color: EvochiColor.primaryShadow),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                      ),
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 8),
              GameCard(
                padding: const EdgeInsets.all(10),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const _MiniHead(icon: 'palette', title: 'Choose Color', note: 'This color will carry through all evolutions.'),
                  const SizedBox(height: 8),
                  Row(children: [
                    for (final p in palettes)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 3),
                          child: Semantics(
                            selected: p.id == pal,
                            button: true,
                            label: p.label,
                            child: GestureDetector(
                              onTap: () => _palette(p.id),
                              child: AspectRatio(
                                aspectRatio: 1 / 1.05,
                                child: Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(12),
                                    color: p.id == pal ? const Color(0xFFFFF4D6) : const Color(0xFFFBF2E6),
                                    border: Border.all(color: p.id == pal ? const Color(0xFFF2BE55) : const Color(0xFFE6D3BD), width: 2),
                                  ),
                                  alignment: Alignment.center,
                                  child: PetSprite(stage: 1, palette: p.id, height: 46),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ]),
                ]),
              ),
              const SizedBox(height: 8),
              GameCard(
                padding: const EdgeInsets.all(10),
                child: Column(children: [
                  const _MiniHead(icon: 'evolve', title: 'Evolution Preview', note: 'See how your Evochi grows!'),
                  const SizedBox(height: 6),
                  EvolutionStrip(palette: pal, current: 1),
                ]),
              ),
              const SizedBox(height: 8),
              GameCard(
                padding: const EdgeInsets.all(10),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const _MiniHead(icon: 'decorations', title: 'Your Starting Home', note: 'This will be your home when the journey begins.'),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Stack(children: [
                      Image.asset(art.thumb('meadow'), height: 96, width: double.infinity, fit: BoxFit.cover),
                      const Positioned(left: 8, bottom: 6, child: Tag('Sunlit Meadow', icon: 'pin')),
                    ]),
                  ),
                  const SizedBox(height: 4),
                  const Text('More habitats unlock later in your journey.', style: EvochiText.caption),
                ]),
              ),
              const SizedBox(height: 10),
              EvochiButton(label: 'Confirm Evochi', large: true, icon: const VoxelIcon('paw', size: 28), onPressed: _confirm),
            ]),
          ),
        ),
      ),
    );
  }
}

class _ArrowButton extends StatelessWidget {
  const _ArrowButton({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: label,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE2CDB4), width: 2),
              color: const Color(0xFFFFF9F0),
              boxShadow: const [BoxShadow(color: Color(0xFFCDB396), offset: Offset(0, 3))],
            ),
            child: Icon(icon, color: EvochiColor.ink),
          ),
        ),
      );
}

class _MiniHead extends StatelessWidget {
  const _MiniHead({required this.icon, required this.title, required this.note});
  final String icon;
  final String title;
  final String note;
  @override
  Widget build(BuildContext context) => Row(children: [
        VoxelIcon(icon, size: 22),
        const SizedBox(width: 6),
        Text(title, style: EvochiText.cardTitle.copyWith(fontSize: 15)),
        const SizedBox(width: 8),
        Expanded(child: Text(note, textAlign: TextAlign.right, style: EvochiText.tiny.copyWith(fontWeight: FontWeight.w400))),
      ]);
}

/// Eggling -> Juvenile -> Elder strip, current stage highlighted (Create, Home).
class EvolutionStrip extends StatelessWidget {
  const EvolutionStrip({super.key, required this.palette, required this.current, this.onTap});
  final String palette;
  final int current;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    Widget cell(int st) {
      final cur = st == current;
      return Expanded(
        child: Semantics(
          label: '${stageLabel(st)}${cur ? ', current form' : ''}',
          button: onTap != null,
          child: GestureDetector(
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.fromLTRB(2, 4, 2, 2),
              decoration: cur
                  ? BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: const Color(0xFFFFF7E2),
                      border: Border.all(color: const Color(0xFFF2BE55), width: 2.5),
                    )
                  : null,
              child: Column(children: [
                SizedBox(height: 58, child: PetSprite(stage: st, palette: palette, expr: st == 2 ? 'determined' : 'default', height: 56)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 1),
                  decoration: BoxDecoration(color: cur ? EvochiColor.gold300 : const Color(0xFFEFE3D3), borderRadius: BorderRadius.circular(8)),
                  child: Text(stageLabel(st), style: EvochiText.tag.copyWith(fontSize: 12, color: cur ? EvochiColor.gold900 : EvochiColor.textSecondary)),
                ),
              ]),
            ),
          ),
        ),
      );
    }

    const chev = Text('›', style: TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w900, fontSize: 22, color: Color(0xFFB79C82)));
    return Row(children: [cell(1), chev, cell(2), chev, cell(3)]);
  }
}

// ------------------------------------------------------------------ connect ----
class ConnectScreen extends StatefulWidget {
  const ConnectScreen({super.key});
  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  final _scene = SceneController();
  bool _busy = false;
  String? _note;

  Future<void> _health() async {
    final c = context.read<GameController>();
    setState(() => _busy = true);
    final p = await c.connectHealth();
    if (!mounted) return;
    setState(() => _busy = false);
    if (p == StepPermission.granted) {
      c.run((s, n) => g.setOnboardingStep(s, 'goal'));
      c.analytics.track('step_source', {'source': 'health'});
    } else {
      // QA Q02: permission denied still reaches Home in reduced-feature mode
      setState(() => _note = p == StepPermission.unavailable
          ? 'Step data is not available on this device. You can use the simulated device or enter steps manually.'
          : 'No problem - you can connect later in Settings. Your Evochi will wait for you.');
    }
  }

  void _choose(String conn) {
    final c = context.read<GameController>();
    if (conn != 'none') c.run((s, n) => g.setConnection(s, conn, n));
    // the simulated step device walks through the step simulator, a developer tool: turn them on
    if (conn == 'demo' && c.state.player != null) c.updateSettings((x) => x.devTools = true);
    c.run((s, n) => g.setOnboardingStep(s, 'goal'));
    c.analytics.track('step_source', {'source': conn});
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<GameController>();
    final p = c.state.pet!;
    final reduce = MediaQuery.of(context).disableAnimations;
    return Scaffold(
      body: SceneScaffold(
        controller: _scene,
        onPetTap: () => _scene.react('pet'),
        petLabel: p.name,
        minHero: 200,
        headerAllowance: 40,
        config: (gy) => SceneConfig(
            habitat: 'meadow', decor: c.state.placements, focus: Offset(0.5, gy), reducedMotion: reduce, pet: PetConfig(stage: 1, palette: p.paletteId, expr: 'curious')),
        header: const SizedBox(height: 8),
        panel: _Sheet(children: [
          const Row(children: [VoxelIcon('steps', size: 44), SizedBox(width: 8), Text('Walk together', style: EvochiText.pageTitle)]),
          const SizedBox(height: 6),
          Text(
            '${p.name} grows from your real-world steps. Evochi reads only your daily step count - nothing else - to give XP, quests and coins. '
            'Step access is optional and you can change it any time in Settings.',
            style: EvochiText.bodyText,
          ),
          if (_note != null) ...[const SizedBox(height: 8), Text(_note!, style: EvochiText.bodyText.copyWith(color: EvochiColor.gold900))],
          const SizedBox(height: 12),
          EvochiButton(
            label: _busy ? 'Waiting for permission...' : 'Connect ${c.health.displayName}',
            large: true,
            icon: const VoxelIcon('steps', size: 28),
            onPressed: _busy ? null : _health,
          ),
          const SizedBox(height: 10),
          EvochiButton(label: 'Use simulated step device', tone: ButtonTone.cream, onPressed: () => _choose('demo')),
          const SizedBox(height: 10),
          EvochiButton(label: 'Enter steps manually', tone: ButtonTone.cream, onPressed: () => _choose('manual')),
          TextButton(onPressed: () => _choose('none'), child: const Text('Connect later', style: EvochiText.cardTitle)),
          const Text('Manual steps are marked unverified and do not count toward reward chests.', textAlign: TextAlign.center, style: EvochiText.caption),
        ]),
      ),
    );
  }
}

class _Sheet extends StatelessWidget {
  const _Sheet({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.fromLTRB(16, 18, 16, 16 + MediaQuery.of(context).padding.bottom),
        decoration: const BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [EvochiColor.panel, Color(0xFFF3E2CE)]),
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
          border: Border(top: BorderSide(color: Color(0xFFEFD9C0), width: 2)),
          boxShadow: [BoxShadow(color: Color(0x2E462D19), blurRadius: 22, offset: Offset(0, -6))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
      );
}

// --------------------------------------------------------------------- goal ----
class GoalScreen extends StatefulWidget {
  const GoalScreen({super.key});
  @override
  State<GoalScreen> createState() => _GoalScreenState();
}

class _GoalScreenState extends State<GoalScreen> {
  final _scene = SceneController();
  int? _sel;

  @override
  Widget build(BuildContext context) {
    final c = context.watch<GameController>();
    final cfg = GameConfig.current;
    final sel = _sel ?? c.state.player!.goal;
    final isPreset = cfg.goalPresets.any((p) => p.steps == sel);
    final p = c.state.pet!;
    final reduce = MediaQuery.of(context).disableAnimations;
    Widget choice({required bool selected, required String icon, required Widget body, VoidCallback? onTap, Widget? trailing}) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Semantics(
            selected: selected,
            button: onTap != null,
            child: GestureDetector(
              onTap: onTap,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: selected ? const Color(0xFFFFF6DC) : const Color(0xFFFFFBF5),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: selected ? const Color(0xFFF2BE55) : const Color(0xFFE6D3BD), width: 2),
                ),
                child: Row(children: [VoxelIcon(icon, size: 40), const SizedBox(width: 10), Expanded(child: body), if (trailing != null) trailing]),
              ),
            ),
          ),
        );
    return Scaffold(
      body: SceneScaffold(
        controller: _scene,
        onPetTap: () => _scene.react('pet'),
        petLabel: p.name,
        minHero: 160,
        headerAllowance: 40,
        config: (gy) => SceneConfig(habitat: 'meadow', decor: c.state.placements, focus: Offset(0.5, gy), reducedMotion: reduce, pet: PetConfig(stage: 1, palette: p.paletteId)),
        header: const SizedBox(height: 8),
        panel: _Sheet(children: [
          const Row(children: [VoxelIcon('star', size: 40), SizedBox(width: 8), Text('Pick a daily goal', style: EvochiText.pageTitle)]),
          const SizedBox(height: 6),
          const Text("Choose what feels comfortable. You can change it later - it's a game target, not a health prescription.", style: EvochiText.bodyText),
          const SizedBox(height: 10),
          for (final gp in cfg.goalPresets)
            choice(
              selected: sel == gp.steps,
              icon: gp.id == 'beginner' ? 'care' : (gp.id == 'standard' ? 'steps' : 'trophy'),
              onTap: () => setState(() => _sel = gp.steps),
              body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [Text(gp.label, style: EvochiText.cardTitle), const SizedBox(width: 6), Tag(gp.blurb, tone: gp.id == 'standard' ? TagTone.stage : TagTone.cream)]),
                Text('${fmt(gp.steps)} steps a day', style: EvochiText.caption),
              ]),
            ),
          choice(
            selected: !isPreset,
            icon: 'palette',
            body: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Custom', style: EvochiText.cardTitle), Text('500-step increments', style: EvochiText.caption)]),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(tooltip: 'Decrease goal', onPressed: () => setState(() => _sel = (sel - 500).clamp(cfg.goalMin, cfg.goalMax)), icon: const Icon(Icons.remove_circle_outline)),
              Text(fmt(sel), style: EvochiText.number.copyWith(fontSize: 16)),
              IconButton(tooltip: 'Increase goal', onPressed: () => setState(() => _sel = (sel + 500).clamp(cfg.goalMin, cfg.goalMax)), icon: const Icon(Icons.add_circle_outline)),
            ]),
          ),
          const SizedBox(height: 4),
          EvochiButton(
            label: 'Continue',
            large: true,
            icon: const Icon(Icons.play_arrow_rounded, color: EvochiColor.ink),
            onPressed: () {
              c.run((s, n) => g.setGoal(s, sel, n));
              c.run((s, n) => g.setOnboardingStep(s, 'awakening'));
            },
          ),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------- awakening ----
class AwakeningScreen extends StatefulWidget {
  const AwakeningScreen({super.key});
  @override
  State<AwakeningScreen> createState() => _AwakeningScreenState();
}

class _AwakeningScreenState extends State<AwakeningScreen> {
  final _scene = SceneController();
  bool _revealed = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    final reduce = WidgetsBinding.instance.platformDispatcher.accessibilityFeatures.disableAnimations;
    _timer = Timer(Duration(milliseconds: reduce ? 50 : 900), () {
      if (!mounted) return;
      setState(() => _revealed = true);
      _scene.react('pet');
      context.read<GameController>().audio.play('evolve_fanfare', volume: 0.5);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<GameController>();
    final p = c.state.pet!;
    final reduce = MediaQuery.of(context).disableAnimations;
    return Scaffold(
      body: SceneScaffold(
        controller: _scene,
        onPetTap: () => _scene.react('pet'),
        petLabel: p.name,
        headerAllowance: 40,
        config: (gy) => SceneConfig(
          habitat: 'meadow',
          decor: c.state.placements,
          focus: Offset(0.5, gy),
          reducedMotion: reduce,
          forceExpr: _revealed ? null : 'sleepy',
          pet: PetConfig(stage: p.stage, palette: p.paletteId, visible: _revealed),
        ),
        header: const SizedBox(height: 8),
        panel: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
          child: GameCard(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              Semantics(
                liveRegion: true,
                child: Text(_revealed ? '${p.name} has hatched!' : 'Something is stirring...', style: EvochiText.pageTitle, textAlign: TextAlign.center),
              ),
              const SizedBox(height: 6),
              Text(
                _revealed ? 'Say hello! Tap your Evochi to pet it. Walk, care and play together to help it grow.' : 'A little light flickers in the nest.',
                textAlign: TextAlign.center,
                style: EvochiText.bodyText,
              ),
              const SizedBox(height: 12),
              EvochiButton(
                label: _revealed ? 'Enter the nest' : 'Skip',
                large: true,
                onPressed: () {
                  c.run((s, n) => g.setOnboardingStep(s, 'done'));
                  c.analytics.track('onboarding_completed');
                },
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
