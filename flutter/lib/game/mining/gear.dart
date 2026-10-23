// Mining gear (MINES_PLAN.md): six slots of a loadout worn only on the Old Trail and in the mines, four
// tiers named for the ore (copper, iron, lumen, obsidian). Flint sells the tools of the trade (headlamps,
// picks, satchels, lanterns) for EvoCoins, and from the iron tier up for some of your ore too; Bram
// forges the armour (harnesses, paw guards) from the ore you mined. Gear earns its keep in the mine: it
// sets which ore you can break (iron needs iron-tier gear that opens it) and how hard you strike.
// Gear is never sold for Glimmer: you earn it by walking and mining. Prices and numbers are starting
// values to playtest.

const gearSlots = ['helmet', 'harness', 'paws', 'satchel', 'lantern', 'tool'];
const gearSlotNames = {
  'helmet': 'Helmet',
  'harness': 'Harness',
  'paws': 'Paw guards',
  'satchel': 'Satchel',
  'lantern': 'Lantern',
  'tool': 'Tool',
};
const tierNames = {1: 'Copper', 2: 'Iron', 3: 'Lumen', 4: 'Obsidian'};

class GearDef {
  const GearDef({
    required this.id,
    required this.name,
    required this.slot,
    required this.tier,
    required this.maker,
    this.coins = 0,
    this.ore = const {},
    this.power = 0,
    this.opens = false,
    this.light = 0,
    this.carry = 0,
    required this.desc,
  });
  final String id;
  final String name;
  final String slot; // gearSlots
  final int tier; // 1 copper, 2 iron, 3 lumen, 4 obsidian
  final String maker; // flint (sold) | bram (forged)
  final int coins; // EvoCoins
  final Map<String, int> ore; // ore item -> how many
  final double power; // mining power it adds (a strike's worth, x 1 + power)
  final bool opens; // it lets you break ore of its tier
  final int light; // light radius in the mine
  final int carry; // satchel room
  final String desc;

  /// What it does, in a few words.
  List<String> get stats => [
        if (opens) 'Breaks ${tierNames[tier]!.toLowerCase()} ore',
        if (power > 0) 'Mining power +${(power * 100).round()}%',
        if (light > 0) 'Light +$light',
        if (carry > 0) 'Carry +$carry',
      ];
}

const gearDefs = <String, GearDef>{
  // ---- Flint's: the tools of the trade
  'copper_headlamp': GearDef(
      id: 'copper_headlamp', name: 'Copper Headlamp', slot: 'helmet', tier: 1, maker: 'flint', coins: 120, light: 1,
      desc: 'A trusty hard hat with a warm headlamp on the front. Lights the way for new miners.'),
  'copper_pick': GearDef(
      id: 'copper_pick', name: 'Copper Pick', slot: 'tool', tier: 1, maker: 'flint', coins: 100, power: 0.15,
      desc: 'A small pick strapped across the back. Your Evochi still does the Pouncing; the pick steadies it.'),
  'copper_satchel': GearDef(
      id: 'copper_satchel', name: 'Copper Satchel', slot: 'satchel', tier: 1, maker: 'flint', coins: 90, carry: 4,
      desc: 'A stout little bag at the side, copper-riveted, for what you find underground.'),
  'copper_lantern': GearDef(
      id: 'copper_lantern', name: 'Copper Lantern', slot: 'lantern', tier: 1, maker: 'flint', coins: 110, light: 1,
      desc: 'A lantern that hangs at the side and keeps your Evochi easy to spot in the dark.'),
  'iron_pick': GearDef(
      id: 'iron_pick', name: 'Iron Pick', slot: 'tool', tier: 2, maker: 'flint', coins: 260, ore: {'copper_ore': 6}, power: 0.35, opens: true,
      desc: "Flint's iron-headed pick. It bites into the rust-red rock: with it, iron breaks."),
  // ---- Bram's: armour, forged from your ore
  'copper_harness': GearDef(
      id: 'copper_harness', name: 'Copper Harness', slot: 'harness', tier: 1, maker: 'bram', ore: {'copper_ore': 6}, power: 0.1, carry: 2,
      desc: 'Copper-trimmed straps that hold your tools close. Simple, reliable, full of charm.'),
  'copper_paw_guards': GearDef(
      id: 'copper_paw_guards', name: 'Copper Paw Guards', slot: 'paws', tier: 1, maker: 'bram', ore: {'copper_ore': 4},
      desc: 'Copper caps for the paws, for rough rock and sharp chips.'),
  'iron_harness': GearDef(
      id: 'iron_harness', name: 'Iron Harness', slot: 'harness', tier: 2, maker: 'bram', ore: {'iron_ore': 6, 'copper_ore': 2}, power: 0.2, carry: 3,
      opens: true, desc: 'An iron frame with pockets to spare. Built for rough tunnels; iron gives under it.'),
  'iron_paw_guards': GearDef(
      id: 'iron_paw_guards', name: 'Iron Paw Guards', slot: 'paws', tier: 2, maker: 'bram', ore: {'iron_ore': 4},
      desc: 'Sturdy iron caps for the paws. Nothing sharp gets through.'),
};

/// The finishes Bram can give a forged piece (its look; no stats).
const gearFinishes = {
  'polished': 'Polished',
  'brushed': 'Brushed',
  'engraved': 'Engraved with a trail motif',
};
