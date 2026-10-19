// Home Tales: the Home Map. The nest (your Evochi), the Garden, the Cottage and the Village Gate on
// one plate, the starter-seed gift on the first visit, a quest strip and a row per place. A befriended
// companion visits by the nest, and a discovery's clue glints here when one is ready (Lumen Trails).
// Mirrors `homemap` in web/src/screens/homeland.js.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../controllers/game_controller.dart';
import '../../game/home/home.dart' as h;
import '../../game/story/story.dart' as q;
import '../shared/sprite.dart';
import '../shared/widgets.dart';
import '../trails/trails_widgets.dart';
import '../village/village_screen.dart';
import 'home_widgets.dart';

const _mapPins = [('garden', 'Garden'), ('cottage', 'Cottage'), ('gate', 'Village Gate')];

/// What a map pin shows: a marker ('handin' | 'quest'), a short note, or a lock note.
(String?, String?, String?) _pinState(String id, h.HomeStatus hv, q.StoryStatus st) {
  if (id == 'garden') {
    if (hv.ripe > 0) return ('handin', '${hv.ripe} ready!', null);
    if (hv.emptyOpen > 0) return (hv.count('harvests') > 0 || hv.growing > 0 ? null : 'quest', '${hv.emptyOpen} empty bed${hv.emptyOpen > 1 ? 's' : ''}', null);
    return (null, '${hv.growing} growing', null);
  }
  if (id == 'cottage') {
    if (st.cottageReady) return ('quest', 'Ready to restore', null);
    if (!hv.kitchen) return (null, null, 'Needs repair');
    return (null, hv.apothecary ? 'Kitchen · Apothecary' : 'Kitchen', null);
  }
  return (st.turnIns.isNotEmpty ? 'handin' : (st.offers.isNotEmpty ? 'quest' : null), 'Sunlit Village', null);
}

class HomeMapScreen extends StatefulWidget {
  const HomeMapScreen({super.key});
  @override
  State<HomeMapScreen> createState() => _HomeMapScreenState();
}

class _HomeMapScreenState extends State<HomeMapScreen> {
  bool _gift = false;
  Timer? _tick;
  Timer? _giftTimer;

  @override
  void initState() {
    super.initState();
    // beds grow on real time
    _tick = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final c = context.read<GameController>();
      if (!c.state.home.starterSeeds && !_gift) {
        _gift = true;
        _giftTimer = Timer(const Duration(milliseconds: 380), () {
          if (mounted) _welcomeGift(c);
        });
      }
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _giftTimer?.cancel();
    super.dispose();
  }

  void _welcomeGift(GameController c) {
    final r = c.run((s, n) => h.claimStarterSeeds(s, n));
    if (!r.ok || r.events.isEmpty) return;
    c.audio.play('reward_chime');
    showEvochiDialog<void>(context, builder: (d) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const GoldBanner('Welcome home!'),
          const SizedBox(height: 10),
          const Center(child: VoxelIcon('home_map', size: 84)),
          const SizedBox(height: 8),
          const Text(
            'Mira left a pouch of seeds by your nest. Plant them in your Garden: crops grow over time, and faster when you go for a walk.',
            style: EvochiText.bodyText,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: [
            for (final e in h.starterSeedGift.entries) ItemCountChip(id: e.key, label: countLabel(e.key, e.value)),
          ]),
          const SizedBox(height: 12),
          EvochiButton(
            label: 'Plant them',
            tone: ButtonTone.green,
            onPressed: () {
              Navigator.pop(d);
              openGarden(context);
            },
          ),
          const SizedBox(height: 8),
          EvochiButton(label: 'Look around first', tone: ButtonTone.cream, onPressed: () => Navigator.pop(d)),
        ]));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<GameController>();
    final hv = h.homeStatus(c.state, c.now);
    final st = c.storyView;
    final ha = homeArt;
    final size = ha.mapSize;
    final restored = st.flag('cottage_restored');
    final pet = c.state.pet;
    final petDead = c.view.pet?.dead ?? true;
    final hq = homeQuestFor(st);
    final friend = c.trailsView.companions.firstOrNull; // the first companion visits by the nest
    final readyDishes = hv.kitchen ? h.recipeOrder.where((r) => h.recipeView(c.state, r).ready).length : 0;
    final gardenSub = hv.ripe > 0
        ? '${hv.ripe} bed${hv.ripe > 1 ? 's' : ''} ready to harvest'
        : (hv.growing > 0 ? '${hv.growing} growing' : (hv.emptyOpen > 0 ? 'Beds are ready for seeds' : ''));
    final cottageSub = restored
        ? (readyDishes > 0 ? '$readyDishes recipe${readyDishes > 1 ? 's' : ''} ready to make' : (hv.apothecary ? 'Kitchen and Apothecary' : 'Kitchen open'))
        : (st.cottageReady ? 'Ready to restore!' : 'Needs a new roof');
    final narrow = MediaQuery.of(context).size.width < 360;
    return Scaffold(
      backgroundColor: EvochiColor.panel,
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          PlaceHeader(title: 'Your Home', short: 'Home', backLabel: 'Back', onBack: () => Navigator.of(context).maybePop()),
          Expanded(
            child: ListView(padding: EdgeInsets.only(bottom: 20 + MediaQuery.of(context).padding.bottom), children: [
              AspectRatio(
                aspectRatio: size.width / size.height,
                child: LayoutBuilder(builder: (ctx, b) {
                  Offset at(String id) {
                    final a = ha.mapAnchor(id);
                    return Offset(a.dx / size.width * b.maxWidth, a.dy / size.height * b.maxHeight);
                  }

                  return Stack(clipBehavior: Clip.hardEdge, children: [
                    Positioned.fill(
                      child: Image.asset(
                        ha.map(restored: restored),
                        fit: BoxFit.cover,
                        semanticLabel:
                            'Your home: the nest in the meadow, the garden beds on the right, ${restored ? 'your restored cottage' : 'an old cottage with a broken roof'} up the path and the gate to Sunlit Village.',
                      ),
                    ),
                    if (pet != null && !petDead)
                      Positioned(
                        left: at('nest').dx,
                        top: at('nest').dy,
                        child: FractionalTranslation(
                          translation: const Offset(-0.5, -0.78),
                          child: Semantics(
                            button: true,
                            label: "Back to ${pet.name}'s nest",
                            child: GestureDetector(
                              onTap: () => goHome(context, 'nest'),
                              child: ExcludeSemantics(
                                child: Column(mainAxisSize: MainAxisSize.min, children: [
                                  PetSprite(stage: pet.stage, palette: pet.paletteId, expr: 'happy', overlays: pet.equipped.values.toList(), height: b.maxWidth * 0.15),
                                  const _NameChip('Nest'),
                                ]),
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (friend != null && trailsArt.available)
                      Positioned(
                        left: (ha.mapAnchor('nest').dx + 150) / size.width * b.maxWidth,
                        top: (ha.mapAnchor('nest').dy - 40) / size.height * b.maxHeight,
                        child: FractionalTranslation(
                          translation: const Offset(-0.5, -0.8),
                          child: Semantics(
                            label: '${friend.name} is visiting',
                            child: CreatureImage(friend.id, height: b.maxWidth * 0.1 * trailsArt.creatureSize(friend.id).height / trailsArt.creatureSize(friend.id).width),
                          ),
                        ),
                      ),
                    for (final p in _mapPins)
                      Positioned(
                        left: at(p.$1).dx,
                        top: at(p.$1).dy,
                        child: FractionalTranslation(
                          translation: const Offset(-0.5, -1),
                          child: _MapPin(id: p.$1, label: p.$2, state: _pinState(p.$1, hv, st)),
                        ),
                      ),
                    ClueGlint(place: 'homemap', width: b.maxWidth, height: b.maxHeight),
                  ]);
                }),
              ),
              Transform.translate(
                offset: const Offset(0, -14),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    if (hq != null) HomeQuestStrip(v: hq, lead: hq.phase == 'locked' ? 'Coming up · Home Tales' : null),
                    const SectionHead('Around your home'),
                    _HomeRow(
                      label: 'Garden. $gardenSub',
                      icon: 'skill_farming',
                      title: 'Garden',
                      sub: gardenSub,
                      trailing: _MiniBeds(plots: hv.plots),
                      onTap: () => openGarden(context),
                    ),
                    _HomeRow(
                      label: 'Cottage. $cottageSub',
                      icon: restored ? 'skill_cooking' : 'home_map',
                      title: 'Cottage',
                      sub: cottageSub,
                      trailing: st.cottageReady ? const Tag('Ready', tone: TagTone.ok) : null,
                      onTap: () => openCottage(context),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: TapCard(
                        label: 'Skills: ${[for (final k in h.skillOrder) '${hv.skills[k]!.name} level ${hv.skills[k]!.level}'].join(', ')}',
                        onTap: () => openSkills(context),
                        child: Row(children: [
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              const Text('Skills', style: EvochiText.cardTitle),
                              const SizedBox(height: 4),
                              Wrap(spacing: 5, runSpacing: 5, children: [
                                for (final k in h.skillOrder) _SkillChip(skill: hv.skills[k]!, showName: !narrow),
                              ]),
                            ]),
                          ),
                          homeChevron,
                        ]),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      child: Text(
                        'Walk → grow → cook and brew → share with your Evochi or a friend in the village. Nothing here ever expires.',
                        style: EvochiText.caption,
                      ),
                    ),
                  ]),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _NameChip extends StatelessWidget {
  const _NameChip(this.name);
  final String name;
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(top: 2),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xF5FFF9F0),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFE2CDB4), width: 2),
          boxShadow: const [BoxShadow(color: Color(0xFFCDB396), offset: Offset(0, 2))],
        ),
        child: Text(name, style: EvochiText.tag.copyWith(color: EvochiColor.ink, fontWeight: FontWeight.w900)),
      );
}

class _MapPin extends StatelessWidget {
  const _MapPin({required this.id, required this.label, required this.state});
  final String id;
  final String label;
  final (String?, String?, String?) state;
  @override
  Widget build(BuildContext context) {
    final (mark, sub, lock) = state;
    return Semantics(
      button: true,
      label: '$label${sub != null ? ', $sub' : ''}${lock != null ? ', $lock' : ''}',
      child: ExcludeSemantics(
        child: GestureDetector(
          onTap: () {
            context.read<GameController>().audio.play('ui_tap', volume: 0.4);
            if (id == 'gate') {
              openVillage(context);
            } else {
              goHome(context, id);
            }
          },
          child: Stack(clipBehavior: Clip.none, children: [
            Container(
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: const Color(0xF2FFF9F0),
                border: Border.all(color: mark != null ? const Color(0xFFF0B952) : const Color(0xFFE2CDB4), width: 2),
                boxShadow: const [BoxShadow(color: Color(0xFFCDB396), offset: Offset(0, 3)), BoxShadow(color: Color(0x40281910), blurRadius: 10, offset: Offset(0, 4))],
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(label, style: EvochiText.cardTitle.copyWith(fontSize: 13, fontWeight: FontWeight.w900)),
                if (lock != null)
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    const VoxelIcon('lock', size: 13),
                    const SizedBox(width: 2),
                    Text(lock, style: EvochiText.tag.copyWith(fontSize: 11)),
                  ])
                else if (sub != null && sub.isNotEmpty)
                  Text(sub, style: EvochiText.tag.copyWith(fontSize: 11)),
              ]),
            ),
            if (mark != null) Positioned(top: -12, right: -10, child: PinMark(mark)),
          ]),
        ),
      ),
    );
  }
}

class _HomeRow extends StatelessWidget {
  const _HomeRow({required this.label, required this.icon, required this.title, required this.sub, required this.onTap, this.trailing});
  final String label;
  final String icon;
  final String title;
  final String sub;
  final VoidCallback onTap;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: TapCard(
          label: label,
          padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
          onTap: onTap,
          child: Row(children: [
            VoxelIcon(icon, size: 42),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: EvochiText.cardTitle),
                if (sub.isNotEmpty) Text(sub, style: EvochiText.caption.copyWith(fontSize: 13)),
              ]),
            ),
            if (trailing != null) ...[const SizedBox(width: 6), trailing!],
            const SizedBox(width: 6),
            homeChevron,
          ]),
        ),
      );
}

/// The four beds at a glance: locked, empty, growing (a progress ring) or ripe (glowing).
class _MiniBeds extends StatelessWidget {
  const _MiniBeds({required this.plots});
  final List<h.PlotView> plots;
  @override
  Widget build(BuildContext context) => SizedBox(
        width: 52,
        child: Wrap(spacing: 4, runSpacing: 4, children: [for (final p in plots) _MiniBed(p)]),
      );
}

class _MiniBed extends StatelessWidget {
  const _MiniBed(this.p);
  final h.PlotView p;
  @override
  Widget build(BuildContext context) {
    if (!p.unlocked) {
      return Container(
        width: 24,
        height: 24,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: const Color(0xFFE7D9C8), borderRadius: BorderRadius.circular(7), border: Border.all(color: const Color(0xFFD3BFA8), width: 1.5)),
        child: const Opacity(opacity: 0.7, child: VoxelIcon('lock', size: 14)),
      );
    }
    if (p.empty) {
      return Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(color: const Color(0xFF8A5A3A), borderRadius: BorderRadius.circular(7), border: Border.all(color: const Color(0xFF6B4329), width: 1.5)),
      );
    }
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: p.ripe ? EvochiColor.gold100 : const Color(0xFFE7D9C8),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: p.ripe ? const Color(0xFFE3A64A) : const Color(0xFF5C9340), width: 1.5),
        boxShadow: p.ripe ? const [BoxShadow(color: Color(0xE6FFC850), blurRadius: 8)] : null,
      ),
      child: Stack(alignment: Alignment.center, children: [
        if (!p.ripe)
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.all(1),
              child: CircularProgressIndicator(value: p.progress, strokeWidth: 3, color: EvochiColor.steps, backgroundColor: const Color(0x00000000)),
            ),
          ),
        ItemImage(p.crop!, size: 18),
      ]),
    );
  }
}

class _SkillChip extends StatelessWidget {
  const _SkillChip({required this.skill, required this.showName});
  final h.SkillView skill;
  final bool showName;
  @override
  Widget build(BuildContext context) => Container(
        height: 26,
        padding: const EdgeInsets.fromLTRB(3, 0, 5, 0),
        decoration: BoxDecoration(color: const Color(0xFFF6EBDD), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFFE5D3BE), width: 1.5)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          VoxelIcon(skill.icon, size: 20),
          if (showName) ...[const SizedBox(width: 3), Text(skill.name, style: EvochiText.tag.copyWith(fontSize: 12))],
          const SizedBox(width: 3),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(color: Color(skill.color), borderRadius: BorderRadius.circular(6)),
            child: Text('${skill.level}', style: EvochiText.tag.copyWith(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w900)),
          ),
        ]),
      );
}
