// Mining gear on screen (MINES_PLAN.md): Flint's shop at the Crossing, the loadout you wear on the Old
// Trail and in the mines (Bram's forge is forge_minigame.dart).
// Gear is its own loadout: it never takes off a wearable, it only covers it while you're out mining.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../controllers/game_controller.dart';
import '../../core/models/catalog.dart';
import '../../core/models/game_state.dart';
import '../../core/services/haptics.dart';
import '../../game/engine.dart' as g;
import '../../game/mining/mining.dart' as mine;
import '../shared/widgets.dart';

const _mapNames = {'trail': 'the Old Trail', 'mine': 'the mines'};

String gearOreName(String id) => catalog[id]?.name ?? id;

/// What a piece costs, as small chips: coins, and each ore with how many you have of it.
class _Cost extends StatelessWidget {
  const _Cost(this.def, this.state);
  final mine.GearDef def;
  final GameState state;

  @override
  Widget build(BuildContext context) {
    final bal = g.balanceOf(state);
    Widget chip(Widget icon, String text, bool ok) => Container(
          margin: const EdgeInsets.only(right: 6, top: 4),
          padding: const EdgeInsets.fromLTRB(4, 2, 8, 2),
          decoration: BoxDecoration(
            color: ok ? const Color(0xFFF7EBD6) : const Color(0xFFF6DCD4),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: ok ? EvochiColor.border : const Color(0xFFD08A7A)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            icon,
            const SizedBox(width: 3),
            Text(text, style: TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w800, fontSize: 13, color: ok ? EvochiColor.ink : const Color(0xFF9A3B2B))),
          ]),
        );
    return Wrap(children: [
      if (def.coins > 0) chip(const VoxelIcon('coin', size: 18), '${def.coins}', bal >= def.coins),
      for (final e in def.ore.entries)
        chip(ItemImage(e.key, size: 20), '${g.ownedQty(state, e.key)}/${e.value} ${gearOreName(e.key)}', g.ownedQty(state, e.key) >= e.value),
    ]);
  }
}

/// A piece of gear: its icon, name, what it does, and its button.
class GearCard extends StatelessWidget {
  const GearCard({super.key, required this.def, required this.state, required this.trailing, this.note});
  final mine.GearDef def;
  final GameState state;
  final Widget trailing;
  final String? note;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.fromLTRB(8, 8, 10, 8),
        decoration: BoxDecoration(
          color: EvochiColor.shell,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: EvochiColor.border, width: 1.5),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(color: const Color(0xFFF3E1C6), borderRadius: BorderRadius.circular(12)),
            child: ItemImage('gear_${def.id}', size: 64),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(def.name, style: const TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w900, fontSize: 16, color: EvochiColor.ink)),
              Text('${mine.gearSlotNames[def.slot]} · ${mine.tierNames[def.tier]} tier',
                  style: const TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w700, fontSize: 12, color: EvochiColor.textHelper)),
              const SizedBox(height: 3),
              Text(def.desc, style: const TextStyle(fontFamily: EvochiText.body, fontSize: 13, height: 1.3, color: EvochiColor.textSecondary)),
              if (def.stats.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(def.stats.join(' · '),
                      style: const TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w800, fontSize: 12.5, color: EvochiColor.healthy)),
                ),
              if (note != null)
                Text(note!, style: const TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w800, fontSize: 12.5, color: EvochiColor.gold900))
              else
                _Cost(def, state),
            ]),
          ),
          const SizedBox(width: 8),
          trailing,
        ]),
      );
}

Widget gearSheetHead(String title, String sub, GameState s) => Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 12),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: EvochiText.section),
            Text(sub, style: EvochiText.caption),
          ]),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(6, 4, 10, 4),
          decoration: BoxDecoration(color: const Color(0xFF5A3418), borderRadius: BorderRadius.circular(10)),
          child: Row(children: [
            const VoxelIcon('coin', size: 20),
            const SizedBox(width: 4),
            Text('${g.balanceOf(s)}', style: const TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w900, fontSize: 15, color: Colors.white)),
          ]),
        ),
      ]),
    );

String whyNotGear(g.ActionResult r) => switch (r.error) {
      'insufficient' => 'Not enough EvoCoins yet: ${r.info['short']} more.',
      'missing_ore' => 'Not enough ore yet: ${((r.info['missing'] as Map?) ?? const {}).entries.map((e) => '${e.value} more ${gearOreName(e.key as String)}').join(', ')}.',
      'owned' => 'You already have that one.',
      _ => "That didn't work.",
    };

// ------------------------------------------------------------------------------------- Flint's shop
/// Flint's shop: the tools of the trade, for EvoCoins (and ore from the iron tier up). A piece you buy
/// goes on at once if its slot is empty.
Future<void> showFlintShop(BuildContext context) => showEvochiSheet<void>(context, builder: (_) => const _FlintShop());

class _FlintShop extends StatelessWidget {
  const _FlintShop();

  @override
  Widget build(BuildContext context) {
    final c = context.watch<GameController>();
    final s = c.state;
    final defs = mine.gearDefs.values.where((d) => d.maker == 'flint').toList()..sort((a, b) => a.tier != b.tier ? a.tier - b.tier : a.coins - b.coins);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      gearSheetHead("Flint's Shop", 'Good gear makes for happier miners. Worn on the trail and in the mines only.', s),
      for (final d in defs)
        Builder(builder: (context) {
          final owned = mine.ownedGear(s, d.id);
          final worn = owned != null && s.mining.loadout[d.slot] == owned.id;
          return GearCard(
            def: d,
            state: s,
            note: owned == null ? null : (worn ? 'Wearing it' : 'Yours: in your gear'),
            trailing: owned != null
                ? (worn
                    ? const SizedBox(width: 72)
                    : EvochiButton(label: 'Wear', small: true, expand: false, tone: ButtonTone.cream, onPressed: () => _wear(c, owned.id)))
                : EvochiButton(label: 'Buy', small: true, expand: false, onPressed: () => _buy(context, c, d)),
          );
        }),
      Align(
        alignment: Alignment.centerRight,
        child: EvochiButton(label: 'Done', small: true, expand: false, tone: ButtonTone.cream, onPressed: () => Navigator.of(context).pop()),
      ),
    ]);
  }

  void _buy(BuildContext context, GameController c, mine.GearDef d) {
    final r = c.run((s, now) => mine.buyGear(s, d.id, 'flint:${d.id}:$now', now), quiet: true);
    if (!r.ok) {
      c.toast(whyNotGear(r), icon: 'warning', kind: 'warn');
      c.audio.play('error_bonk', volume: 0.5);
      return;
    }
    final worn = r.events.any((e) => e.data['worn'] == true);
    c.audio.play('purchase', volume: 0.7);
    c.toast(worn ? '${d.name}: it’s on! Ready to mine.' : '${d.name} is yours. Wear it from your gear.', icon: 'shop');
  }
}

void _wear(GameController c, String pieceId) {
  final r = c.run((s, now) => mine.wearGear(s, pieceId), quiet: true);
  if (r.ok) c.audio.buzz(Haptic.equip);
}

// ------------------------------------------------------------------------------------- the loadout
/// Your mining loadout: the six slots, what's in each, and what it adds up to.
Future<void> showGearLoadout(BuildContext context) => showEvochiSheet<void>(context, builder: (_) => const _Loadout());

class _Loadout extends StatelessWidget {
  const _Loadout();

  @override
  Widget build(BuildContext context) {
    final c = context.watch<GameController>();
    final s = c.state;
    final tier = mine.oreTierOf(s);
    final power = mine.miningPowerOf(s);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      gearSheetHead('Mining gear', 'Worn on the trail and in the mines. Your wearables stay as they are.', s),
      Container(
        padding: const EdgeInsets.all(10),
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(color: const Color(0xFFEFF8E2), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFB7D98B))),
        child: Text(
          'Breaks ${[for (var t = 1; t <= tier; t++) mine.tierNames[t]!.toLowerCase()].join(', ')} ore · Mining power ${(power * 100).round()}%',
          style: const TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w900, fontSize: 14, color: EvochiColor.healthy),
        ),
      ),
      for (final slot in mine.gearSlots) _SlotRow(slot: slot, state: s, c: c),
      Align(
        alignment: Alignment.centerRight,
        child: EvochiButton(label: 'Done', small: true, expand: false, tone: ButtonTone.cream, onPressed: () => Navigator.of(context).pop()),
      ),
    ]);
  }
}

class _SlotRow extends StatelessWidget {
  const _SlotRow({required this.slot, required this.state, required this.c});
  final String slot;
  final GameState state;
  final GameController c;

  @override
  Widget build(BuildContext context) {
    final wornId = state.mining.loadout[slot];
    final worn = wornId == null ? null : state.mining.piece(wornId);
    final options = state.mining.gear.where((p) => mine.gearDefs[p.def]?.slot == slot).toList();
    final def = worn == null ? null : mine.gearDefs[worn.def];
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      decoration: BoxDecoration(color: EvochiColor.shell, borderRadius: BorderRadius.circular(12), border: Border.all(color: EvochiColor.border)),
      child: Row(children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(color: const Color(0xFFF3E1C6), borderRadius: BorderRadius.circular(10)),
          child: def == null ? const Icon(Icons.add_rounded, color: EvochiColor.border) : ItemImage('gear_${def.id}', size: 52),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(mine.gearSlotNames[slot]!, style: const TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w700, fontSize: 12, color: EvochiColor.textHelper)),
            Text(def?.name ?? (options.isEmpty ? 'Nothing yet' : 'Empty'),
                style: const TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w900, fontSize: 15, color: EvochiColor.ink)),
            if (worn != null) Text(gearMemory(worn), style: EvochiText.caption),
          ]),
        ),
        if (options.length > (worn == null ? 0 : 1) || worn != null)
          PopupMenuButton<String>(
            tooltip: 'Change',
            icon: const Icon(Icons.swap_horiz_rounded, color: EvochiColor.wood),
            onSelected: (v) {
              if (v == '_off') {
                c.run((s, now) => mine.takeOffGear(s, slot), quiet: true);
              } else {
                _wear(c, v);
              }
            },
            itemBuilder: (_) => [
              for (final p in options)
                if (p.id != wornId) PopupMenuItem(value: p.id, child: Text('Wear ${mine.gearDefs[p.def]!.name}')),
              if (worn != null) const PopupMenuItem(value: '_off', child: Text('Take it off')),
            ],
          ),
      ]),
    );
  }
}

/// A piece's memory, in a line: who made it, where its ore came from, its finish, its first trip.
String gearMemory(GearPiece p) {
  final parts = <String>[
    p.from == 'bram' ? 'Forged by Bram' : 'From Flint',
    if (p.oreFrom != null) 'ore from ${_mapNames[p.oreFrom] ?? p.oreFrom}',
    if (p.finish != null) mine.gearFinishes[p.finish]!.toLowerCase(),
    p.firstTrip == null ? 'not been mining yet' : 'been mining',
  ];
  return parts.join(' · ');
}
