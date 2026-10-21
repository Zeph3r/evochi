// Starter catalog (style guide §18-19). Prices are starting values.
// Story rewards (Village Tales) are catalog items too, so they equip and place like any other, but
// they are never sold: acquisition 'story', no price, no shop, not tradable, not sellable.
// Home Tales adds seeds (the Market's Garden shelf), harvests (ingredients) and homemade meals and
// brews (consumables with acquisition 'home', never sold), mirroring web/src/game/catalog.js.
// Lumen Trails adds Lumen Shards (found on discoveries, acquisition 'trail'), the Lantern Tonic and the
// Ancient Relic (a story decoration from the Sentinel's gate).

enum ItemCategory { wearable, consumable, decoration, seed, ingredient }

const categoryLabels = {
  ItemCategory.wearable: 'Wearables',
  ItemCategory.consumable: 'Consumables',
  ItemCategory.decoration: 'Decorations',
  ItemCategory.seed: 'Seeds',
  ItemCategory.ingredient: 'Ingredients',
};

class CatalogItem {
  const CatalogItem({
    required this.id,
    required this.name,
    required this.category,
    int? price,
    required this.rarity,
    required this.desc,
    required this.shop,
    this.acquisition = 'shop',
    this.originQuest,
    this.tradable = true,
    this.sellable = true,
    this.slot,
    this.decor,
    this.featured = false,
    this.stackable = false,
    this.vitality = 0,
    this.recovery = false,
    this.treat = false,
    this.growth = 0,
    this.lantern = false,
    this.kind,
    this.crop,
    this.stages = const [1, 2, 3],
    this.glimmer,
    this.pendingArt = false,
  }) : listPrice = price;

  final String id;
  final String name;
  final ItemCategory category;
  final int? listPrice; // null for story rewards (never sold)
  final String rarity;
  final String desc;
  final String? shop; // wearables | care | habitats | garden; null = not in the Market
  final String acquisition; // shop | story | home | trail
  final String? originQuest; // story rewards: the quest that grants it
  final bool tradable;
  final bool sellable;
  final String? slot; // head | neck | back | tail
  final String? decor; // nest | side
  final bool featured;
  final bool stackable;
  final int vitality;
  final bool recovery;
  final bool treat; // a homemade treat: Bond once a day, even at full vitality
  final double growth; // > 0: a garden item (Sprout Tonic), used on a bed, never given to the pet
  final bool lantern; // Lantern Tonic: steadies the Hollow in encounters
  final String? kind; // consumables: meal | potion | garden
  final String? crop; // seeds: the crop they grow
  final List<int> stages;
  final int? glimmer; // Starlight Caravan price in Glimmer (rare items); null = not sold there
  final bool pendingArt; // a season reward whose wearable art is not rendered yet: owned, not equippable

  bool get isStackable => category == ItemCategory.consumable || stackable;
  bool get isRare => kind == 'rare';
  bool get isStory => acquisition == 'story';
  bool get isHome => acquisition == 'home';
  bool get forSale => shop != null && listPrice != null && !isStory;
  /// Market price. Only meaningful for items that are [forSale].
  int get price => listPrice ?? 0;
}

const slotLabels = {'head': 'Head', 'neck': 'Neck', 'back': 'Back', 'tail': 'Tail'};

class DecorSlot {
  const DecorSlot(this.id, this.label, this.accepts);
  final String id;
  final String label;
  final String accepts;
}

const decorSlots = <String, DecorSlot>{
  'nest': DecorSlot('nest', 'Nest', 'nest'),
  'left': DecorSlot('left', 'Left', 'side'),
  'right': DecorSlot('right', 'Right', 'side'),
  'back': DecorSlot('back', 'Back', 'side'),
};

const catalog = <String, CatalogItem>{
  'leaf_scarf': CatalogItem(
      id: 'leaf_scarf', name: 'Leaf Scarf', category: ItemCategory.wearable, slot: 'neck', price: 120, rarity: 'common',
      desc: 'A soft scarf made from fresh leaves and a tiny flower. Simple, cozy, and perfect for little adventures.',
      shop: 'wearables', featured: true),
  'golden_crest_crown': CatalogItem(
      id: 'golden_crest_crown', name: 'Golden Crest Crown', category: ItemCategory.wearable, slot: 'head', price: 150,
      rarity: 'rare', desc: 'A regal crown fit for a brave little explorer. Shines with the spirit of new adventures.',
      shop: 'wearables', featured: true),
  'explorer_hat': CatalogItem(
      id: 'explorer_hat', name: 'Explorer Hat', category: ItemCategory.wearable, slot: 'head', price: 180, rarity: 'uncommon',
      desc: 'A trusty hat with trail goggles and a meadow feather. Ready for any path.', shop: 'wearables', featured: true),
  'blue_scarf': CatalogItem(
      id: 'blue_scarf', name: 'Blue Scarf', category: ItemCategory.wearable, slot: 'neck', price: 100, rarity: 'common',
      desc: 'A hand-knitted scarf the colour of a clear morning sky.', shop: 'wearables'),
  'tiny_crown': CatalogItem(
      id: 'tiny_crown', name: 'Tiny Crown', category: ItemCategory.wearable, slot: 'head', price: 90, rarity: 'uncommon',
      desc: 'A little crown that sits at a jaunty angle. Royalty, but make it casual.', shop: 'wearables'),
  'butterfly_clip': CatalogItem(
      id: 'butterfly_clip', name: 'Butterfly Clip', category: ItemCategory.wearable, slot: 'head', price: 70, rarity: 'common',
      desc: 'A sunny butterfly that likes to ride along on walks.', shop: 'wearables'),
  'red_backpack': CatalogItem(
      id: 'red_backpack', name: 'Red Backpack', category: ItemCategory.wearable, slot: 'back', price: 140, rarity: 'uncommon',
      desc: 'Room for snacks, pebbles, and one very important leaf.', shop: 'wearables'),
  'explorer_pack': CatalogItem(
      id: 'explorer_pack', name: 'Explorer Pack', category: ItemCategory.wearable, slot: 'back', price: 220, rarity: 'epic',
      desc: 'A leather pack with a rolled bedroll on top, for long journeys.', shop: 'wearables'),
  'meadow_nest': CatalogItem(
      id: 'meadow_nest', name: 'Meadow Nest', category: ItemCategory.decoration, decor: 'nest', price: 200, rarity: 'rare',
      desc: 'A mossy nest woven with daisies. Your Evochi naps best here.', shop: 'habitats', featured: true),
  'nest_bed': CatalogItem(
      id: 'nest_bed', name: 'Nest Bed', category: ItemCategory.decoration, decor: 'nest', price: 80, rarity: 'common',
      desc: 'A simple straw bed. Warm, soft, and smells like sunshine.', shop: 'habitats'),
  'explorer_lantern': CatalogItem(
      id: 'explorer_lantern', name: 'Explorer Lantern', category: ItemCategory.decoration, decor: 'side', price: 120,
      rarity: 'uncommon', desc: 'A warm lantern that keeps the nest cozy after sunset.', shop: 'habitats', featured: true),
  'sunlit_flower': CatalogItem(
      id: 'sunlit_flower', name: 'Sunlit Flower', category: ItemCategory.decoration, decor: 'side', price: 45, rarity: 'common',
      stackable: true, desc: 'A cheerful daisy cluster that turns to face the sun.', shop: 'habitats'),
  'berry_snack': CatalogItem(
      id: 'berry_snack', name: 'Berry Snack', category: ItemCategory.consumable, price: 20, rarity: 'common', vitality: 4,
      desc: 'A handful of sweet meadow berries. Restores 4 vitality.', shop: 'care'),
  'healing_herb': CatalogItem(
      id: 'healing_herb', name: 'Healing Herb', category: ItemCategory.consumable, price: 80, rarity: 'common', vitality: 10,
      recovery: true, desc: 'A soothing herb bundle. Restores 10 vitality (12h cooldown).', shop: 'care', featured: true),
  // ---- Village Tales, Chapter 1 story rewards
  'reward_firefly_hearth': CatalogItem(
      id: 'reward_firefly_hearth', name: 'Firefly Hearth', category: ItemCategory.decoration, decor: 'nest', rarity: 'legendary',
      desc: 'A tiny hollow stump lit by three golden fireflies. Bram made it from the light you brought back to Sunlit Village.',
      shop: null, acquisition: 'story', originQuest: 'vq01', tradable: false, sellable: false),
  'reward_windtrail_mantle': CatalogItem(
      id: 'reward_windtrail_mantle', name: 'Windtrail Mantle', category: ItemCategory.wearable, slot: 'back', rarity: 'legendary',
      desc: 'A short sky-blue travel cape, embroidered with cream trail lines and fastened with two copper clasps. Travelers should look the part.',
      shop: null, acquisition: 'story', originQuest: 'vq02', tradable: false, sellable: false),
  'reward_waystone_bloom': CatalogItem(
      id: 'reward_waystone_bloom', name: 'Waystone Bloom', category: ItemCategory.decoration, decor: 'side', rarity: 'legendary',
      desc: 'A white stone plinth with a floating mint-and-gold crystal blossom. It glows a little brighter when you walk.',
      shop: null, acquisition: 'story', originQuest: 'vq03', tradable: false, sellable: false),
  // ---- Home: seeds (the Market's Garden shelf), harvests, Kitchen meals and Apothecary brews.
  // Harvests and homemade food are ordinary stackable inventory items (acquisition 'home'): never sold
  // in the Market, so walking and the garden stay the way to get them.
  'seed_sunberry': CatalogItem(
      id: 'seed_sunberry', name: 'Sunberry Seeds', category: ItemCategory.seed, crop: 'sunberry', price: 8, rarity: 'common',
      stackable: true, shop: 'garden', desc: 'Plant in a garden bed. Ripe in about 20 minutes, and sooner when you walk. Farming Lv 1.'),
  'seed_meadow_carrot': CatalogItem(
      id: 'seed_meadow_carrot', name: 'Carrot Seeds', category: ItemCategory.seed, crop: 'meadow_carrot', price: 10, rarity: 'common',
      stackable: true, shop: 'garden', desc: 'Crunchy Meadow Carrots in about 45 minutes. Farming Lv 1.'),
  'seed_golden_wheat': CatalogItem(
      id: 'seed_golden_wheat', name: 'Wheat Seeds', category: ItemCategory.seed, crop: 'golden_wheat', price: 12, rarity: 'common',
      stackable: true, shop: 'garden', desc: 'Golden Wheat for tarts and buns, ready in about 1.5 hours. Farming Lv 2.'),
  'seed_glowleaf': CatalogItem(
      id: 'seed_glowleaf', name: 'Glowleaf Seeds', category: ItemCategory.seed, crop: 'glowleaf', price: 20, rarity: 'uncommon',
      stackable: true, shop: 'garden', desc: 'A softly shining herb for tonics. Slow growing: about 3 hours. Farming Lv 3.'),
  'seed_moonshroom': CatalogItem(
      id: 'seed_moonshroom', name: 'Moonshroom Spores', category: ItemCategory.seed, crop: 'moonshroom', price: 35, rarity: 'rare',
      stackable: true, shop: 'garden', desc: 'Speckled mushrooms that glow at dusk. Takes about 6 hours. Farming Lv 5.'),
  'sunberry': CatalogItem(
      id: 'sunberry', name: 'Sunberry', category: ItemCategory.ingredient, rarity: 'common', stackable: true, shop: null, acquisition: 'home',
      desc: 'Sweet, sun-warm berries from your own garden.'),
  'meadow_carrot': CatalogItem(
      id: 'meadow_carrot', name: 'Meadow Carrot', category: ItemCategory.ingredient, rarity: 'common', stackable: true, shop: null, acquisition: 'home',
      desc: 'A crunchy orange carrot with a leafy top.'),
  'golden_wheat': CatalogItem(
      id: 'golden_wheat', name: 'Golden Wheat', category: ItemCategory.ingredient, rarity: 'common', stackable: true, shop: null, acquisition: 'home',
      desc: 'A bundle of golden wheat, ready for the oven.'),
  'glowleaf': CatalogItem(
      id: 'glowleaf', name: 'Glowleaf', category: ItemCategory.ingredient, rarity: 'uncommon', stackable: true, shop: null, acquisition: 'home',
      desc: 'A minty herb that glows faintly. The heart of every tonic.'),
  'moonshroom': CatalogItem(
      id: 'moonshroom', name: 'Moonshroom', category: ItemCategory.ingredient, rarity: 'rare', stackable: true, shop: null, acquisition: 'home',
      desc: 'A speckled violet mushroom with a soft night-time shimmer.'),
  'sunberry_tart': CatalogItem(
      id: 'sunberry_tart', name: 'Sunberry Tart', category: ItemCategory.consumable, kind: 'meal', rarity: 'uncommon', stackable: true, shop: null,
      acquisition: 'home', vitality: 8, treat: true,
      desc: 'Baked in your Cottage oven. Restores 8 vitality, and a homemade treat adds Bond once a day.'),
  'carrot_stew': CatalogItem(
      id: 'carrot_stew', name: 'Carrot Stew', category: ItemCategory.consumable, kind: 'meal', rarity: 'common', stackable: true, shop: null,
      acquisition: 'home', vitality: 6, treat: true,
      desc: 'A warm bowl of stew. Restores 6 vitality; a homemade treat adds Bond once a day.'),
  'golden_bun': CatalogItem(
      id: 'golden_bun', name: 'Golden Bun', category: ItemCategory.consumable, kind: 'meal', rarity: 'common', stackable: true, shop: null,
      acquisition: 'home', vitality: 5, treat: true,
      desc: 'A soft wheat bun, still warm. Restores 5 vitality; a homemade treat adds Bond once a day.'),
  'moonshroom_pie': CatalogItem(
      id: 'moonshroom_pie', name: 'Moonshroom Pie', category: ItemCategory.consumable, kind: 'meal', rarity: 'rare', stackable: true, shop: null,
      acquisition: 'home', vitality: 14, treat: true,
      desc: 'A savoury pie with a shimmering crust. Restores 14 vitality; a homemade treat adds Bond once a day.'),
  'glowleaf_tonic': CatalogItem(
      id: 'glowleaf_tonic', name: 'Glowleaf Tonic', category: ItemCategory.consumable, kind: 'potion', rarity: 'uncommon', stackable: true, shop: null,
      acquisition: 'home', vitality: 10,
      desc: 'A gentle mint-green tonic. Restores 10 vitality. Some old friends of the forest love it. In the Wilds: Regenerating, +3 Raid HP a second for 20s.'),
  'meadow_tea': CatalogItem(
      id: 'meadow_tea', name: 'Meadow Tea', category: ItemCategory.consumable, kind: 'potion', rarity: 'common', stackable: true, shop: null,
      acquisition: 'home', vitality: 6, treat: true,
      desc: 'Calming herb tea. Restores 6 vitality; a homemade treat adds Bond once a day. In the Wilds: Swift, stamina back 60% faster and cheaper dodges for 30s.'),
  'sprout_tonic': CatalogItem(
      id: 'sprout_tonic', name: 'Sprout Tonic', category: ItemCategory.consumable, kind: 'garden', rarity: 'uncommon', stackable: true, shop: null,
      acquisition: 'home', growth: 0.5,
      desc: 'Pour on a growing bed in your Garden: it grows half its time at once (once per planting).'),
  'moonlight_draught': CatalogItem(
      id: 'moonlight_draught', name: 'Moonlight Draught', category: ItemCategory.consumable, kind: 'potion', rarity: 'rare', stackable: true, shop: null,
      acquisition: 'home', vitality: 20, recovery: true,
      desc: 'A deep-blue draught full of tiny stars. Restores 20 vitality (12h cooldown, like a Healing Herb). In the Wilds: Moonlit, a 1 in 4 chance to crit for 30s.'),
  // ---- Lumen Trails: found on discoveries, brewed for encounters, earned from the guardians
  'lumen_shard': CatalogItem(
      id: 'lumen_shard', name: 'Lumen Shard', category: ItemCategory.ingredient, rarity: 'uncommon', stackable: true, shop: null, acquisition: 'trail',
      desc: 'A sliver of trail-light, cool to the touch. The Trail Guild trades them for nothing: they are for brewing Lantern Tonic.'),
  'lantern_tonic': CatalogItem(
      id: 'lantern_tonic', name: 'Lantern Tonic', category: ItemCategory.consumable, kind: 'potion', rarity: 'rare', stackable: true, shop: null,
      acquisition: 'home', vitality: 12, lantern: true,
      desc: 'Lumen in a bottle. Restores 12 vitality, and in an encounter it steadies the Hollow like nothing else. In the Wilds: Lantern-lit, the Hollow hits 35% softer for 30s.'),
  // ---- Wilds brews (the Apothecary): drunk in the Wilds they set your Evochi alight or bristling
  'ember_draught': CatalogItem(
      id: 'ember_draught', name: 'Ember Draught', category: ItemCategory.consumable, kind: 'potion', rarity: 'rare', stackable: true, shop: null,
      acquisition: 'home', vitality: 8,
      desc: 'A warm orange brew with a little flame dancing on the cork. Restores 8 vitality. In the Wilds: Ember, your hits set foes alight for 30s.'),
  'thornskin_tonic': CatalogItem(
      id: 'thornskin_tonic', name: 'Thornskin Tonic', category: ItemCategory.consumable, kind: 'potion', rarity: 'epic', stackable: true, shop: null,
      acquisition: 'home', vitality: 8,
      desc: 'Briar Heartwood steeped in glowleaf: it bristles in the bottle. Restores 8 vitality. In the Wilds: Thornskin, strikers take 40% of their blow back for 25s.'),
  'ancient_relic': CatalogItem(
      id: 'ancient_relic', name: 'Ancient Relic', category: ItemCategory.decoration, decor: 'side', rarity: 'legendary',
      desc: "A stone tablet from the Sentinel's gate, its three trail grooves glowing softly. A piece of the Lumen Trails for your nest.",
      shop: null, acquisition: 'story', originQuest: 'eq03', tradable: false, sellable: false),
  // ---- Lumen Wilds: what a floor's guardian leaves once it is calm (fragments for Wilds cosmetics)
  'briar_heartwood': CatalogItem(
      id: 'briar_heartwood', name: 'Briar Heartwood', category: ItemCategory.ingredient, rarity: 'epic', stackable: true, shop: null,
      acquisition: 'trail', tradable: false, sellable: false,
      desc: "A piece of the Briarback's antler, warm wood split open on a mint-green glow. The Hollow is gone from it. "
          'A crafting fragment from the Sunlit Thicket.'),
  // ---- Rare finds (the economy plan): they drop rarely in play and the Starlight Caravan sells them for
  // Glimmer. Each one is a consumable of kind 'rare'; what it does lives in game/economy/economy.dart.
  'sunstone': CatalogItem(
      id: 'sunstone', name: 'Sunstone', category: ItemCategory.consumable, kind: 'rare', rarity: 'rare', stackable: true, shop: null,
      acquisition: 'drop', tradable: false, glimmer: 30,
      desc: 'A warm gold gem that holds a whole afternoon of sunlight. Set it on a garden bed and the crop ripens at once.'),
  'moonwell_dew': CatalogItem(
      id: 'moonwell_dew', name: 'Moonwell Dew', category: ItemCategory.consumable, kind: 'rare', rarity: 'uncommon', stackable: true, shop: null,
      acquisition: 'drop', tradable: false, glimmer: 20,
      desc: 'Pale blue water from the old moonwell. Waters every planted bed at once and adds a quarter of a growing time to each.'),
  'heartbloom': CatalogItem(
      id: 'heartbloom', name: 'Heartbloom', category: ItemCategory.consumable, kind: 'rare', rarity: 'epic', stackable: true, shop: null,
      acquisition: 'drop', tradable: false, glimmer: 60,
      desc: 'A rose-pink bloom with heart-shaped petals. Wakes a fainted Evochi at full Vitality, and in the Wilds it gets you back on your feet once.'),
  'wayfinder_compass': CatalogItem(
      id: 'wayfinder_compass', name: 'Wayfinder Compass', category: ItemCategory.consumable, kind: 'rare', rarity: 'rare', stackable: true, shop: null,
      acquisition: 'drop', tradable: false, glimmer: 40,
      desc: 'A brass compass whose needle points at the best-hidden things. Doubles the reward of your next trail discovery.'),
  'golden_acorn': CatalogItem(
      id: 'golden_acorn', name: 'Golden Acorn', category: ItemCategory.consumable, kind: 'rare', rarity: 'rare', stackable: true, shop: null,
      acquisition: 'drop', tradable: false, glimmer: 50,
      desc: 'A lucky acorn of solid gold. Your next daily chest opens one tier better.'),
  'hollow_ward': CatalogItem(
      id: 'hollow_ward', name: 'Hollow Ward', category: ItemCategory.consumable, kind: 'rare', rarity: 'uncommon', stackable: true, shop: null,
      acquisition: 'drop', tradable: false, glimmer: 25,
      desc: 'A violet charm carved with a calming rune. Your next Wilds run starts with a shield that turns away the first three hits.'),
  'starseed': CatalogItem(
      id: 'starseed', name: 'Starseed', category: ItemCategory.consumable, kind: 'rare', rarity: 'rare', stackable: true, shop: null,
      acquisition: 'drop', tradable: false,
      desc: 'A seed with a tiny star caught inside. It will grow Starfruit once the garden has room for it.'),
  'prism_scale': CatalogItem(
      id: 'prism_scale', name: 'Prism Scale', category: ItemCategory.consumable, kind: 'rare', rarity: 'legendary', stackable: true, shop: null,
      acquisition: 'drop', tradable: false,
      desc: 'An iridescent scale that throws rainbows. One day it will give your Evochi a shimmer of its own.'),
  // ---- Season 1: First Light. Pass rewards; their wearable art arrives with the season.
  'season_dawn_circlet': CatalogItem(
      id: 'season_dawn_circlet', name: 'Dawn Circlet', category: ItemCategory.wearable, slot: 'head', rarity: 'epic', shop: null,
      acquisition: 'season', tradable: false, sellable: false, pendingArt: true,
      desc: 'A thin gold circlet set with a sliver of morning light. Season 1: First Light, premium track.'),
  'season_firefly_scarf': CatalogItem(
      id: 'season_firefly_scarf', name: 'Firefly Scarf', category: ItemCategory.wearable, slot: 'neck', rarity: 'epic', shop: null,
      acquisition: 'season', tradable: false, sellable: false, pendingArt: true,
      desc: 'A night-blue scarf embroidered with tiny glowing fireflies. Season 1: First Light, premium track.'),
  'season_lantern_wings': CatalogItem(
      id: 'season_lantern_wings', name: 'Lantern Wings', category: ItemCategory.wearable, slot: 'back', rarity: 'legendary', shop: null,
      acquisition: 'season', tradable: false, sellable: false, pendingArt: true,
      desc: 'Little paper-lantern wings that glow when you walk. Season 1: First Light, premium track.'),
  'season_glow_ribbon': CatalogItem(
      id: 'season_glow_ribbon', name: 'Glow Ribbon', category: ItemCategory.wearable, slot: 'tail', rarity: 'epic', shop: null,
      acquisition: 'season', tradable: false, sellable: false, pendingArt: true,
      desc: 'A ribbon for the tail that trails a faint light. Season 1: First Light, premium track.'),
  'season_first_light_banner': CatalogItem(
      id: 'season_first_light_banner', name: 'First Light Banner', category: ItemCategory.decoration, decor: 'side', rarity: 'epic', shop: null,
      acquisition: 'season', tradable: false, sellable: false, pendingArt: true,
      desc: 'A camp banner stitched with a rising sun over the Thicket. Season 1: First Light, premium track.'),
  'season_first_light_scarf': CatalogItem(
      id: 'season_first_light_scarf', name: 'First Light Scarf', category: ItemCategory.wearable, slot: 'neck', rarity: 'rare', shop: null,
      acquisition: 'season', tradable: false, sellable: false, pendingArt: true,
      desc: 'A soft dawn-coloured scarf for everyone who walked Season 1. Season 1: First Light, free track.'),
  'season_dawn_shimmer': CatalogItem(
      id: 'season_dawn_shimmer', name: 'Dawn Shimmer', category: ItemCategory.decoration, decor: 'side', rarity: 'legendary', shop: null,
      acquisition: 'season', tradable: false, sellable: false, pendingArt: true,
      desc: 'A swirl of morning light that will follow your Evochi. Season 1: First Light, the final premium reward.'),
};

/// Can this item be bought in the Market (and rolled as a quest cosmetic)? Story items never can.
bool isShopItem(String id) => catalog[id]?.forSale ?? false;

const storySource = {'vq01': 'Village Tales, Quest 01', 'vq02': 'Village Tales, Quest 02', 'vq03': 'Village Tales, Quest 03', 'eq03': 'Lumen Trails, Quest 03'};

CatalogItem item(String id) {
  final it = catalog[id];
  if (it == null) throw ArgumentError('Unknown item $id');
  return it;
}

bool itemCompatible(String id, int stage) {
  final it = item(id);
  if (it.category != ItemCategory.wearable) return true;
  return it.stages.contains(stage);
}
