// S06 Home / Nest (style guide §10, §14, §17) + S12 memorial when vitality reaches zero.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/router.dart';
import '../../app/theme.dart';
import '../../controllers/game_controller.dart';
import '../../core/utils/day_keys.dart';
import '../../game/engine.dart' as g;
import '../../game/vitality/vitality.dart';
import '../home/home_widgets.dart';
import '../onboarding/onboarding_screens.dart' show EvolutionStrip;
import '../pet/pet_screens.dart';
import '../settings/settings_screen.dart';
import '../shared/scene_scaffold.dart';
import '../shared/scene_view.dart';
import '../shared/widgets.dart';
import '../village/story_widgets.dart';
import '../village/village_screen.dart';
import 'sheets.dart';

class NestScreen extends StatefulWidget {
  const NestScreen({super.key, required this.active});
  final bool active;
  @override
  State<NestScreen> createState() => _NestScreenState();
}

class _NestScreenState extends State<NestScreen> {
  final scene = SceneController();
  DateTime _lastInput = DateTime.now();
  DateTime? _napUntil;
  Timer? _idle;

  // Sleep (style guide §20): the pet dozes in a quiet state (no touches for a while, sooner at
  // night) or when its bed is tapped. Any interaction wakes it.
  bool _sleeping(GameController c) {
    final now = DateTime.now();
    if (_napUntil != null && now.isBefore(_napUntil!)) return true;
    final h = hourIn(c.now, c.view.zone);
    final night = h >= 23 || h < 6;
    return now.difference(_lastInput).inSeconds > (night ? 12 : 45);
  }

  @override
  void initState() {
    super.initState();
    _idle = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted && widget.active) setState(() {});
    });
  }

  @override
  void dispose() {
    _idle?.cancel();
    super.dispose();
  }

  void _touch() {
    _lastInput = DateTime.now();
    _napUntil = null;
  }

  void _pet(GameController c) {
    _touch();
    c.run((s, n) => g.interact(s, 'pet', n));
    scene.react('pet');
    c.audio.play('pet_chirp');
    c.analytics.track('interact', {'kind': 'pet'});
    setState(() {});
  }

  void _play(GameController c) {
    _touch();
    c.run((s, n) => g.interact(s, 'play', n));
    scene.react('play');
    c.audio.play('play_boing');
    c.analytics.track('interact', {'kind': 'play'});
    setState(() {});
  }

  void _bed(GameController c) {
    setState(() {
      if (_sleeping(c)) {
        _touch();
        scene.react('surprised');
      } else {
        _napUntil = DateTime.now().add(const Duration(minutes: 1));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<GameController>();
    final v = c.view;
    final pet = c.state.pet!;
    final pv = v.pet!;
    if (pv.dead) return MemorialView(scene: scene);
    final reduce = MediaQuery.of(context).disableAnimations;
    final screenH = MediaQuery.of(context).size.height;
    final story = c.storyView.active;
    final chip = story != null && story.tracked && screenH >= 640;
    // the story chip takes the evolution strip's room, so the strip folds into its compact row
    final compact = screenH < 680 || (chip && screenH < 920);
    final sleeping = _sleeping(c);
    return Listener(
      onPointerDown: (_) {
        if (sleeping) setState(_touch);
        _lastInput = DateTime.now();
      },
      child: Scaffold(
        body: SceneScaffold(
          controller: scene,
          onPetTap: () => _pet(c),
          petLabel: 'Pet ${pet.name}',
          bottomInset: navInset(context),
          headerAllowance: 120,
          groundOffset: 22,
          config: (gy) => SceneConfig(
            habitat: 'meadow',
            decor: c.state.placements,
            focus: Offset(0.5, gy),
            reducedMotion: reduce,
            pet: PetConfig(stage: pet.stage, palette: pet.paletteId, status: pv.status, equipped: pet.equipped.values.toList(), sleeping: sleeping),
          ),
          header: _NestHud(onBed: () => _bed(c), sleeping: sleeping),
          hero: Stack(children: [
            if (pv.evolution.eligible)
              Align(
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: EvochiButton(
                    label: 'Evolve ${pet.name}!',
                    expand: false,
                    icon: const VoxelIcon('evolve', size: 26),
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const EvolutionScreen())),
                  ),
                ),
              ),
            // the nest bed: tap to tuck the pet in for a nap (or wake it)
            Align(
              alignment: Alignment.bottomCenter,
              child: Semantics(
                button: true,
                label: sleeping ? 'Wake ${pet.name}' : 'Tuck ${pet.name} into the nest for a nap',
                child: GestureDetector(onTap: () => _bed(c), child: const SizedBox(width: 200, height: 30)),
              ),
            ),
          ]),
          panel: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              ..._banner(context, c),
              if (chip) const StoryChip(),
              _IdCard(),
              const SizedBox(height: 8),
              _StepsCard(),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: _ActionButton(label: 'Pet', icon: 'heart', tone: ButtonTone.gold, onTap: () => _pet(c))),
                const SizedBox(width: 10),
                Expanded(child: _ActionButton(label: 'Play', icon: 'play', tone: ButtonTone.green, onTap: () => _play(c))),
                const SizedBox(width: 10),
                Expanded(
                  child: _ActionButton(
                    label: 'Inspect',
                    icon: 'inspect',
                    tone: ButtonTone.cream,
                    onTap: () {
                      scene.react('inspect');
                      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PetDetailsScreen()));
                    },
                  ),
                ),
              ]),
              const SizedBox(height: 8),
              if (compact)
                GameCard(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(children: [
                    const VoxelIcon('evolve', size: 22),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        pv.evolution.maxed
                            ? 'Final form reached'
                            : 'Next: ${stageLabel(pet.stage + 1)} - Lv ${pv.level.level}/${pv.evolution.gate!.level}, ${pv.activeDays}/${pv.evolution.gate!.activeDays} active days',
                        style: EvochiText.tag,
                      ),
                    ),
                  ]),
                )
              else
                GameCard(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Row(children: [
                      Text('Evolution Family', style: EvochiText.cardTitle.copyWith(fontSize: 15)),
                      const Spacer(),
                      const Text('Grow together!', style: EvochiText.caption),
                    ]),
                    EvolutionStrip(
                      palette: pet.paletteId,
                      current: pet.stage,
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PetDetailsScreen())),
                    ),
                  ]),
                ),
              const SizedBox(height: 8),
            ]),
          ),
        ),
      ),
    );
  }

  List<Widget> _banner(BuildContext context, GameController c) {
    final v = c.view;
    final s = c.state;
    if (v.pet!.status == PetStatus.sick) {
      return [
        GameCard(
          color: const Color(0xFFFFF0D8),
          padding: const EdgeInsets.all(10),
          child: Row(children: [
            const VoxelIcon('potion', size: 26),
            const SizedBox(width: 8),
            Expanded(child: Text('${s.pet!.name} feels unwell. A walk or a Healing Herb will help.', style: EvochiText.tag)),
            EvochiButton(label: 'Care', small: true, expand: false, onPressed: () => showCareSheet(context)),
          ]),
        ),
        const SizedBox(height: 8),
      ];
    }
    final last = s.steps.lastSync;
    if (s.steps.connection != 'none' && last != null && c.now - last > 36 * hourMs) {
      return [
        const GameCard(
          color: Color(0xFFE9F4FB),
          padding: EdgeInsets.all(10),
          child: Row(children: [
            VoxelIcon('steps', size: 26),
            SizedBox(width: 8),
            Expanded(child: Text('Steps have not synced for a while. Missing days count as pending, not inactive.', style: EvochiText.tag)),
          ]),
        ),
        const SizedBox(height: 8),
      ];
    }
    return const [];
  }
}

class _NestHud extends StatelessWidget {
  const _NestHud({required this.onBed, required this.sleeping});
  final VoidCallback onBed;
  final bool sleeping;
  @override
  Widget build(BuildContext context) {
    final c = context.watch<GameController>();
    final v = c.view;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Flexible(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            TitleImage('wordmark_evochi', height: 40, label: 'Evochi - ${c.state.pet!.name}\'s nest'),
            const SizedBox(height: 10),
            Semantics(
              button: true,
              label: 'Sunlit Meadow - arrange decorations',
              child: GestureDetector(
                onTap: () => showHabitatSheet(context),
                child: Container(
                  height: 36,
                  padding: const EdgeInsets.fromLTRB(6, 0, 10, 0),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFE7D3BC), width: 2),
                    color: const Color(0xFFFFF9F0),
                    boxShadow: const [BoxShadow(color: Color(0xFFCDB396), offset: Offset(0, 3))],
                  ),
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    VoxelIcon('pin', size: 24),
                    SizedBox(width: 4),
                    Text('Sunlit Meadow', style: EvochiText.cardTitle),
                    Text('  ›', style: EvochiText.cardTitle),
                  ]),
                ),
              ),
            ),
            const SizedBox(height: 8),
            // the trip row: Explore Home (Home Tales) and Visit Village, scaled down on narrow phones
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                _ExploreHomeButton(attention: c.homeAttention),
                const SizedBox(width: 8),
                _VisitVillageButton(attention: c.storyAttention > 0, short: MediaQuery.of(context).size.width < 400),
              ]),
            ),
          ]),
        ),
        const SizedBox(width: 8),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          CoinPill(balance: v.balance, onPlus: () => showCoinsInfo(context)),
          const SizedBox(height: 10),
          SquareIconButton(
            icon: 'settings',
            label: 'Settings',
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
          ),
          const SizedBox(height: 10),
          SquareIconButton(icon: 'mail', label: 'Quests and rewards', badge: v.claimable, onTap: () => TabNav.of(context).go('journey')),
        ]),
      ]),
    );
  }
}

/// Opens the Home Map (Home Tales). The dot means a bed is ripe, the starter seeds are waiting, or the
/// Cottage is ready to restore.
class _ExploreHomeButton extends StatelessWidget {
  const _ExploreHomeButton({required this.attention});
  final bool attention;
  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: 'Explore Home${attention ? ', something new' : ''}',
        child: GestureDetector(
          onTap: () {
            context.read<GameController>().audio.play('ui_tap', volume: 0.4);
            openHomeMap(context);
          },
          child: Stack(clipBehavior: Clip.none, children: [
            Container(
              height: 44,
              padding: const EdgeInsets.fromLTRB(6, 0, 12, 0),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF5C9340), width: 2),
                gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFD5EDB4), Color(0xFFA6D27D)]),
                boxShadow: const [BoxShadow(color: Color(0xFF4F7E37), offset: Offset(0, 3)), BoxShadow(color: Color(0x333C2314), blurRadius: 8, offset: Offset(0, 4))],
              ),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                VoxelIcon('home_map', size: 28),
                SizedBox(width: 6),
                Text('Explore Home', style: TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w900, fontSize: 15, color: EvochiColor.ink)),
              ]),
            ),
            if (attention) const Positioned(top: -6, right: -6, child: BadgeDot()),
          ]),
        ),
      );
}

/// Opens Sunlit Village (Village Tales). The dot means a villager has something for you.
class _VisitVillageButton extends StatelessWidget {
  const _VisitVillageButton({required this.attention, this.short = false});
  final bool attention;
  final bool short;
  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: 'Visit Sunlit Village${attention ? ', something new' : ''}',
        child: GestureDetector(
          onTap: () {
            context.read<GameController>().audio.play('ui_tap', volume: 0.4);
            openVillage(context);
          },
          child: Stack(clipBehavior: Clip.none, children: [
            Container(
              height: 44,
              padding: const EdgeInsets.fromLTRB(6, 0, 12, 0),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF8D5D3B), width: 2),
                gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFE3B98B), Color(0xFFC69469)]),
                boxShadow: const [BoxShadow(color: Color(0xFF6E4529), offset: Offset(0, 3)), BoxShadow(color: Color(0x333C2314), blurRadius: 8, offset: Offset(0, 4))],
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const VoxelIcon('habitats', size: 28),
                const SizedBox(width: 6),
                Text(short ? 'Village' : 'Visit Village', style: const TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w900, fontSize: 15, color: EvochiColor.ink)),
              ]),
            ),
            if (attention) const Positioned(top: -6, right: -6, child: BadgeDot()),
          ]),
        ),
      );
}

class _IdCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final c = context.watch<GameController>();
    final pet = c.state.pet!;
    final pv = c.view.pet!;
    return GameCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 10),
      child: IntrinsicHeight(
        child: Row(children: [
          Flexible(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Row(mainAxisSize: MainAxisSize.min, children: [
                Flexible(
                  child: Text(pet.name,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w900, fontSize: 28, color: EvochiColor.ink)),
                ),
                IconButton(tooltip: 'Rename ${pet.name}', onPressed: () => showRenameSheet(context), icon: const Icon(Icons.edit_rounded, color: EvochiColor.primaryShadow, size: 20)),
              ]),
              Wrap(spacing: 6, runSpacing: 4, children: [Tag(stageLabel(pet.stage), tone: TagTone.stage), statusTag(pv.status)]),
            ]),
          ),
          const VerticalDivider(color: Color(0xFFE8D5BF), thickness: 1.5, width: 20),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
              Text.rich(TextSpan(style: EvochiText.number, children: [
                const TextSpan(text: 'Lv. '),
                TextSpan(text: '${pv.level.level}', style: const TextStyle(fontSize: 24)),
              ])),
              const SizedBox(height: 4),
              Row(children: [
                Expanded(child: ProgressBarX(value: pv.level.progress, semantic: 'Experience')),
                const SizedBox(width: 6),
                Text('${fmt(pv.level.into)} / ${fmt(pv.level.need)} XP', style: EvochiText.tag.copyWith(fontSize: 12)),
              ]),
              const SizedBox(height: 4),
              Row(children: [
                Hearts(filled: pv.hearts, bond: pv.bond),
                const Spacer(),
                IconButton(tooltip: 'What is bond?', onPressed: () => showBondInfo(context), icon: const Icon(Icons.help_outline_rounded, color: EvochiColor.textHelper)),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _StepsCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final c = context.watch<GameController>();
    final v = c.view;
    final conn = c.state.steps.connection;
    return GameCard(
      padding: const EdgeInsets.all(10),
      child: Row(children: [
        Container(
          width: 50,
          height: 50,
          decoration: const BoxDecoration(color: Color(0xFFEEE3D4), shape: BoxShape.circle),
          alignment: Alignment.center,
          child: const VoxelIcon('steps', size: 36),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Semantics(
            button: true,
            label: 'Daily steps ${fmt(v.todaySteps)} of ${fmt(v.goal)}. Open Journey',
            child: GestureDetector(
              onTap: () => TabNav.of(context).go('journey'),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Text('Daily Steps', style: EvochiText.caption),
                  if (v.todayUnverified) ...[const SizedBox(width: 6), const Tag('Unverified', tone: TagTone.warn)],
                ]),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text.rich(TextSpan(style: EvochiText.number.copyWith(fontSize: 21), children: [
                    TextSpan(text: fmt(v.todaySteps)),
                    TextSpan(text: ' / ${fmt(v.goal)} steps', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                  ])),
                ),
                const SizedBox(height: 4),
                ProgressBarX(value: v.todaySteps / v.goal, height: 12, tone: 'green'),
              ]),
            ),
          ),
        ),
        const SizedBox(width: 10),
        if (conn == 'none')
          EvochiButton(
            label: 'Connect',
            tone: ButtonTone.green,
            small: true,
            expand: false,
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
          )
        else
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
            decoration: BoxDecoration(color: EvochiColor.meadow100, borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFD2E8B9), width: 1.5)),
            child: Text('↑ +${v.pet!.xpToday} XP today!', style: EvochiText.tag.copyWith(color: EvochiColor.healthy, fontSize: 12)),
          ),
      ]),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.label, required this.icon, required this.tone, required this.onTap});
  final String label;
  final String icon;
  final ButtonTone tone;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => SizedBox(
        height: 58,
        child: EvochiButton(label: label, tone: tone, icon: VoxelIcon(icon, size: 28), onPressed: onTap),
      );
}

// --------------------------------------------------------------- memorial ----
class MemorialView extends StatelessWidget {
  const MemorialView({super.key, required this.scene});
  final SceneController scene;
  @override
  Widget build(BuildContext context) {
    final c = context.watch<GameController>();
    final v = c.view;
    final pet = c.state.pet!;
    final pv = v.pet!;
    final herbs = g.ownedQty(c.state, 'healing_herb');
    final need = c.config.reviveHerbCost;
    final walk = (v.todaySteps / v.goal).clamp(0.0, 1.0).toDouble();
    return Scaffold(
      body: SceneScaffold(
        controller: scene,
        bottomInset: navInset(context),
        headerAllowance: 60,
        config: (gy) => SceneConfig(
          habitat: 'meadow',
          decor: c.state.placements,
          focus: Offset(0.5, gy),
          pet: PetConfig(stage: pet.stage, palette: pet.paletteId, status: PetStatus.dead),
        ),
        header: Align(
          alignment: Alignment.topRight,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: SquareIconButton(icon: 'settings', label: 'Settings', onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen()))),
          ),
        ),
        panel: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: GameCard(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('${pet.name} is resting', textAlign: TextAlign.center, style: EvochiText.pageTitle),
              const SizedBox(height: 6),
              const Text(
                'Your Evochi ran out of vitality and has gone quiet in the nest. You can rekindle it, or let it rest and start a new egg.',
                textAlign: TextAlign.center,
                style: EvochiText.bodyText,
              ),
              const SizedBox(height: 10),
              _kv([
                ('Peak level', '${pv.level.level}'),
                ('Form reached', stageLabel(pet.stage)),
                ('Time together', '${pv.daysTogether} days'),
                ('Verified steps together', fmt(pv.lifetimeSteps)),
              ]),
              const SizedBox(height: 10),
              GameCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const Row(children: [VoxelIcon('steps', size: 28), SizedBox(width: 6), Expanded(child: Text('Rekindle with a walk', style: EvochiText.cardTitle)), Tag('Free', tone: TagTone.ok)]),
                  const SizedBox(height: 8),
                  ProgressBarX(value: walk, tone: 'green', height: 12),
                  const SizedBox(height: 4),
                  Text('${fmt(v.todaySteps)} / ${fmt(v.goal)} steps today', style: EvochiText.caption),
                  const SizedBox(height: 8),
                  EvochiButton(
                    label: 'Rekindle ${pet.name}',
                    tone: ButtonTone.green,
                    onPressed: walk >= 1
                        ? () {
                            if (c.run((s, n) => g.reviveWithWalk(s, n)).ok) {
                              c.toast('${pet.name} is back!', icon: 'heart');
                              c.audio.play('level_up');
                            }
                          }
                        : null,
                  ),
                ]),
              ),
              const SizedBox(height: 10),
              GameCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(children: [
                    const ItemImage('healing_herb', size: 32),
                    const SizedBox(width: 6),
                    Expanded(child: Text('Use $need Healing Herbs', style: EvochiText.cardTitle)),
                    Tag('You have $herbs'),
                  ]),
                  const SizedBox(height: 8),
                  EvochiButton(
                    label: 'Rekindle with herbs',
                    onPressed: herbs >= need
                        ? () {
                            if (c.run((s, n) => g.reviveWithHerbs(s, n)).ok) {
                              c.toast('${pet.name} is back!', icon: 'heart');
                              c.audio.play('level_up');
                            }
                          }
                        : null,
                  ),
                  if (herbs < need) const Padding(padding: EdgeInsets.only(top: 6), child: Text("Herbs are sold for EvoCoins in the Market's Care tab.", style: EvochiText.caption)),
                ]),
              ),
              const SizedBox(height: 10),
              EvochiButton(
                label: 'Start a New Egg',
                tone: ButtonTone.cream,
                icon: const VoxelIcon('paw', size: 26),
                onPressed: () => showEvochiDialog<void>(context, builder: (d) => Column(mainAxisSize: MainAxisSize.min, children: [
                      Text('Let ${pet.name} rest?', style: EvochiText.section),
                      const SizedBox(height: 8),
                      Text('${pet.name} will be remembered in your EvoDex Hall of Memories. You keep every cosmetic, decoration and EvoCoin.', style: EvochiText.bodyText),
                      const SizedBox(height: 12),
                      EvochiButton(
                        label: 'Start a New Egg',
                        onPressed: () {
                          Navigator.pop(d);
                          c.audio.play('memorial', volume: 0.6);
                          c.run((s, n) => g.memorialize(s, n));
                        },
                      ),
                      const SizedBox(height: 8),
                      EvochiButton(label: 'Not yet', tone: ButtonTone.cream, onPressed: () => Navigator.pop(d)),
                    ])),
              ),
              const SizedBox(height: 6),
              const Text('Cosmetics, coins and decorations always stay with your account.', textAlign: TextAlign.center, style: EvochiText.caption),
            ]),
          ),
        ),
      ),
    );
  }
}

Widget _kv(List<(String, String)> rows) => Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: const Color(0xFFFBF1E4), borderRadius: BorderRadius.circular(12)),
      child: Column(children: [
        for (final r in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(children: [Expanded(child: Text(r.$1, style: EvochiText.bodyText)), Text(r.$2, style: EvochiText.cardTitle)]),
          ),
      ]),
    );
