// Bottom sheets shared by Home, Bag and Pet details: care, habitat arrangement, rename, info.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/router.dart';
import '../../app/theme.dart';
import '../../controllers/game_controller.dart';
import '../../core/models/catalog.dart';
import '../../game/engine.dart' as g;
import '../shared/widgets.dart';

Future<void> showCareSheet(BuildContext context) => showEvochiSheet<void>(context, builder: (s) {
      return Consumer<GameController>(builder: (s, c, _) {
        final v = c.view;
        final pv = v.pet!;
        final cool = pv.recoveryReadyAt > c.now;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Care for ${c.state.pet!.name}', style: EvochiText.section),
          const SizedBox(height: 10),
          Row(children: [
            const Text('Vitality', style: EvochiText.cardTitle),
            const SizedBox(width: 8),
            Expanded(child: ProgressBarX(value: pv.vitality.vitality / 100, tone: pv.vitality.vitality < 35 ? 'amber' : 'green', height: 12)),
            const SizedBox(width: 8),
            Text('${pv.vitality.vitality}', style: EvochiText.number.copyWith(fontSize: 16)),
          ]),
          const SizedBox(height: 10),
          for (final id in const ['berry_snack', 'healing_herb'])
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: GameCard(
                padding: const EdgeInsets.all(10),
                child: Row(children: [
                  ItemImage(id, size: 52),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [Text(item(id).name, style: EvochiText.cardTitle), const SizedBox(width: 6), Tag('x${g.ownedQty(c.state, id)}')]),
                      Text(item(id).desc, style: EvochiText.caption),
                      if (item(id).recovery && cool)
                        Text('Ready in ${((pv.recoveryReadyAt - c.now) / 60000).ceil()} min', style: EvochiText.caption.copyWith(color: EvochiColor.gold900)),
                    ]),
                  ),
                  const SizedBox(width: 6),
                  if (g.ownedQty(c.state, id) > 0)
                    EvochiButton(
                      label: 'Use',
                      small: true,
                      expand: false,
                      onPressed: (item(id).recovery && cool) || pv.vitality.vitality >= 100
                          ? null
                          : () {
                              if (c.run((st, n) => g.useConsumable(st, id, n)).ok) {
                                c.toast('+${item(id).vitality} vitality', icon: 'heart');
                                c.audio.play('reward_chime', volume: 0.6);
                              }
                            },
                    )
                  else
                    EvochiButton(
                      label: 'Shop',
                      small: true,
                      expand: false,
                      tone: ButtonTone.cream,
                      onPressed: () {
                        Navigator.pop(s);
                        TabNav.of(context).go('shop');
                      },
                    ),
                ]),
              ),
            ),
          const Text('Walking at least half your goal restores vitality too - care items are never required.', style: EvochiText.caption),
          const SizedBox(height: 10),
          EvochiButton(label: 'Close', tone: ButtonTone.cream, onPressed: () => Navigator.pop(s)),
        ]);
      });
    });

Future<void> showHabitatSheet(BuildContext context) => showEvochiSheet<void>(context, builder: (s) {
      return Consumer<GameController>(builder: (s, c, _) {
        final st = c.state;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Row(children: [
            VoxelIcon('habitats', size: 40),
            SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Sunlit Meadow', style: EvochiText.section),
                Text("Arrange decorations in the nest's spots.", style: EvochiText.caption),
              ]),
            ),
          ]),
          const SizedBox(height: 10),
          for (final slot in decorSlots.values)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: GameCard(
                padding: const EdgeInsets.all(10),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(children: [
                    Expanded(child: Text('${slot.label} spot', style: EvochiText.cardTitle)),
                    if (st.placements[slot.id] != null)
                      EvochiButton(
                        label: 'Remove',
                        small: true,
                        expand: false,
                        tone: ButtonTone.cream,
                        onPressed: () => c.run((x, n) => g.removeDecoration(x, slot.id)),
                      ),
                  ]),
                  const SizedBox(height: 6),
                  Builder(builder: (_) {
                    final options = st.inventory.keys
                        .where((id) => catalog[id]?.category == ItemCategory.decoration && catalog[id]!.decor == slot.accepts && g.ownedQty(st, id) > 0)
                        .toList();
                    if (options.isEmpty) return const Text("Nothing that fits here yet - try the Market's Habitats tab.", style: EvochiText.caption);
                    return Wrap(spacing: 6, runSpacing: 6, children: [
                      for (final id in options)
                        Semantics(
                          selected: st.placements[slot.id] == id,
                          button: true,
                          label: item(id).name,
                          child: GestureDetector(
                            onTap: () {
                              if (c.run((x, n) => g.placeDecoration(x, id, slot.id)).ok) c.audio.play('ui_tap');
                            },
                            child: Container(
                              width: 88,
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                color: const Color(0xFFFFFBF6),
                                border: Border.all(color: st.placements[slot.id] == id ? const Color(0xFFF2BE55) : const Color(0xFFEADAC6), width: 2),
                              ),
                              child: Column(children: [
                                ItemImage(id, size: 46),
                                Text(item(id).name, textAlign: TextAlign.center, style: EvochiText.tag.copyWith(fontSize: 12, color: EvochiColor.ink)),
                              ]),
                            ),
                          ),
                        ),
                    ]);
                  }),
                ]),
              ),
            ),
          EvochiButton(label: 'Done', tone: ButtonTone.cream, onPressed: () => Navigator.pop(s)),
        ]);
      });
    });

Future<void> showRenameSheet(BuildContext context) {
  final c = context.read<GameController>();
  final ctl = TextEditingController(text: c.state.pet!.name);
  String? err;
  return showEvochiSheet<void>(context, builder: (s) => StatefulBuilder(builder: (s, set) {
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Rename your Evochi', style: EvochiText.section),
          const SizedBox(height: 8),
          TextField(
            controller: ctl,
            autofocus: true,
            maxLength: c.config.nameMax,
            decoration: InputDecoration(errorText: err, filled: true, fillColor: EvochiColor.shell, counterText: ''),
          ),
          const SizedBox(height: 10),
          EvochiButton(
            label: 'Save',
            onPressed: () {
              final r = c.run((st, n) => g.renamePet(st, ctl.text), quiet: true);
              if (!r.ok) {
                set(() => err = r.info['message'] as String?);
                return;
              }
              Navigator.pop(s);
            },
          ),
        ]);
      }));
}

Future<void> showCoinsInfo(BuildContext context) => showEvochiSheet<void>(context, builder: (s) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Row(children: [VoxelIcon('coin', size: 44), SizedBox(width: 8), Text('EvoCoins', style: EvochiText.section)]),
          const SizedBox(height: 8),
          const Text(
            'EvoCoins are earned by walking and caring for your Evochi. Complete Journey quests to collect them, then spend them in the Market.',
            style: EvochiText.bodyText,
          ),
          const SizedBox(height: 4),
          const Text('Glimmer, the rarer currency, is found now and then out there and spent at the Starlight Caravan. EvoCoins are never sold.', style: EvochiText.caption),
          const SizedBox(height: 12),
          EvochiButton(
            label: 'Open Journey',
            onPressed: () {
              Navigator.pop(s);
              TabNav.of(context).go('journey');
            },
          ),
        ]));

Future<void> showBondInfo(BuildContext context) {
  final c = context.read<GameController>();
  final cfg = c.config;
  return showEvochiSheet<void>(context, builder: (s) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [const VoxelIcon('heart', size: 40), const SizedBox(width: 8), Text('Bond ${c.view.pet!.bond} / 100', style: EvochiText.section)]),
        const SizedBox(height: 8),
        Text(
          'Bond is your friendship with ${c.state.pet!.name}. It grows from your first pet (+${cfg.bondFirstPet}) and first play '
          '(+${cfg.bondFirstPlay}) each day, plus +${cfg.bondGoal} when you reach your step goal. Direct interactions add at most '
          '+${cfg.bondDirectDailyCap} a day, so there is no need to tap-grind.',
          style: EvochiText.bodyText,
        ),
        const SizedBox(height: 4),
        const Text('Higher bond unlocks more playful idle gestures. It never affects step access or health.', style: EvochiText.caption),
        const SizedBox(height: 12),
        EvochiButton(label: 'Got it', tone: ButtonTone.cream, onPressed: () => Navigator.pop(s)),
      ]));
}
