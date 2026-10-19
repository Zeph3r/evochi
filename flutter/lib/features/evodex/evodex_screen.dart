// S11 EvoDex: forms, turnaround, colourways, the friends of the trail (Lumen Trails) and the Hall of
// Memories.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/constants.dart';
import '../../app/router.dart';
import '../../app/theme.dart';
import '../../controllers/game_controller.dart';
import '../nest/sheets.dart';
import '../shared/kit.dart';
import '../shared/sprite.dart';
import '../shared/widgets.dart';
import '../trails/trails_widgets.dart';

const _desc = {
  1: 'A small, scaly egg creature with the spirit of a lizard. Curious, cheerful and already full of adventurous energy.',
  2: 'More agile and alert, with a developing crest and tail. Shows greater personality while keeping the same voxel charm.',
  3: 'Strong, agile and full of life. Its crystalline crest and plated tail show years of growth and adventure.',
};

class EvoDexScreen extends StatefulWidget {
  const EvoDexScreen({super.key});
  @override
  State<EvoDexScreen> createState() => _EvoDexScreenState();
}

class _EvoDexScreenState extends State<EvoDexScreen> {
  int? _stage;
  String _view = 'front';

  @override
  Widget build(BuildContext context) {
    final c = context.watch<GameController>();
    final s = c.state;
    final pal = s.pet?.paletteId ?? 'amber';
    bool unlocked(int st) => s.unlocks.containsKey('stage:lizard:$st');
    final sel = (_stage != null && unlocked(_stage!)) ? _stage! : (s.pet?.stage ?? 1);
    final evo = c.view.pet?.evolution;
    final found = palettes.where((p) => s.unlocks.containsKey('palette:${p.id}')).length;
    // a collector's binder: every card has ring holes down its left edge
    return Scaffold(
      backgroundColor: EvochiColor.panel,
      body: KitPage(
        material: KitMaterial.binder,
        child: CustomScrollView(slivers: [
        SliverToBoxAdapter(
          child: SizedBox(
            height: 150,
            child: Stack(fit: StackFit.expand, children: [
              Image.asset(art.thumb('cliffs'), fit: BoxFit.cover),
              const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment(0, 0.3), end: Alignment.bottomCenter, colors: [Color(0x00FAEED8), Color(0xFFFAEED8)]))),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const TitleImage('title_evodex', height: 44, label: 'EvoDex'),
                    const Spacer(),
                    CoinPill(balance: c.balance, onPlus: () => showCoinsInfo(context)),
                  ]),
                ),
              ),
            ]),
          ),
        ),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(14, 0, 14, navInset(context) + 12),
          sliver: SliverList.list(children: [
            GameCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  const Expanded(child: Text('Lizard family', style: EvochiText.section)),
                  Tag('${[1, 2, 3].where(unlocked).length} / 3 forms', tone: TagTone.stage),
                ]),
                const SizedBox(height: 8),
                for (final st in const [1, 2, 3])
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Semantics(
                      button: unlocked(st),
                      selected: sel == st && unlocked(st),
                      label: unlocked(st) ? stageLabel(st) : 'Undiscovered form',
                      child: GestureDetector(
                        onTap: unlocked(st) ? () => setState(() => _stage = st) : null,
                        // a sleeve in the binder page; the one on show gets the gold ring
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: Kit.slot(selected: sel == st && unlocked(st), radius: 14),
                          child: Row(children: [
                            Container(
                              width: 104,
                              height: 88,
                              decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), gradient: const RadialGradient(colors: [Color(0xFFFFF9EC), Color(0xFFF2E3CF)])),
                              alignment: Alignment.center,
                              child: PetSprite(stage: st, palette: pal, height: 76, silhouette: !unlocked(st)),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Row(children: [Text(unlocked(st) ? stageLabel(st) : '???', style: EvochiText.cardTitle), const SizedBox(width: 6), Tag('#00$st')]),
                                const SizedBox(height: 4),
                                Text(
                                  unlocked(st) ? _desc[st]! : 'Discovered at level ${c.config.evolution[st]!.level} with ${c.config.evolution[st]!.activeDays} active days.',
                                  style: EvochiText.caption.copyWith(color: EvochiColor.textSecondary),
                                ),
                                if (!unlocked(st) && evo != null && !evo.maxed && evo.next == st)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 6),
                                    child: ProgressBarX(value: evo.levelProgress < evo.daysProgress ? evo.levelProgress : evo.daysProgress, height: 8),
                                  ),
                              ]),
                            ),
                          ]),
                        ),
                      ),
                    ),
                  ),
              ]),
            ),
            const SizedBox(height: 10),
            GameCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Expanded(child: Text('${stageLabel(sel)} turnaround', style: EvochiText.cardTitle)),
                  Text(palettes.firstWhere((p) => p.id == pal).label, style: EvochiText.caption),
                ]),
                const SizedBox(height: 8),
                Container(
                  height: 170,
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), gradient: const RadialGradient(colors: [Color(0xFFFFF9EC), Color(0xFFEFDFC9)])),
                  alignment: Alignment.center,
                  child: PetSprite(stage: sel, palette: pal, view: _view, height: 150, semanticLabel: '${stageLabel(sel)}, $_view view'),
                ),
                const SizedBox(height: 8),
                Row(children: [
                  for (final view in const ['front', 'left', 'back', 'right', 'top'])
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: Semantics(
                          selected: view == _view,
                          button: true,
                          label: '$view view',
                          child: GestureDetector(
                            onTap: () => setState(() => _view = view),
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: Kit.slot(selected: view == _view, radius: 10),
                              child: Column(children: [
                                SizedBox(height: 40, child: PetSprite(stage: sel, palette: pal, view: view, height: 38)),
                                Text(view, style: EvochiText.tag.copyWith(fontSize: 10)),
                              ]),
                            ),
                          ),
                        ),
                      ),
                    ),
                ]),
              ]),
            ),
            const SizedBox(height: 10),
            GameCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [const Expanded(child: Text('Colourways', style: EvochiText.cardTitle)), Tag('$found / 6 found')]),
                const SizedBox(height: 8),
                Row(children: [
                  for (final p in palettes)
                    Expanded(
                      child: Semantics(
                        label: s.unlocks.containsKey('palette:${p.id}') ? p.label : 'Undiscovered colourway',
                        child: PetSprite(stage: 1, palette: p.id, height: 46, silhouette: !s.unlocks.containsKey('palette:${p.id}')),
                      ),
                    ),
                ]),
                const SizedBox(height: 6),
                const Text('Each new egg you raise in a different colour adds it to your EvoDex.', style: EvochiText.caption),
              ]),
            ),
            const SizedBox(height: 10),
            const FriendsPanel(),
            const SizedBox(height: 10),
            GameCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Text('Hall of Memories', style: EvochiText.cardTitle),
                const SizedBox(height: 6),
                if (s.pastPets.isEmpty)
                  const Text('Evochi you raise and lay to rest are remembered here.', style: EvochiText.caption)
                else
                  for (final m in s.pastPets)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(children: [
                        SizedBox(width: 64, height: 54, child: PetSprite(stage: m.stage, palette: m.paletteId, expr: 'memorial', height: 50)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(m.name, style: EvochiText.cardTitle),
                            Text('${stageLabel(m.stage)} - Lv ${m.peakLevel} - ${m.daysTogether} days together - ${fmt(m.lifetimeSteps)} steps', style: EvochiText.caption),
                          ]),
                        ),
                      ]),
                    ),
              ]),
            ),
          ]),
        ),
      ]),
      ),
    );
  }
}
