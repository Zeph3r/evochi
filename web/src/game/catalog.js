// Item catalog (style guide §18-19). Prices are STARTING VALUES.

export const RARITY = {
  common: { label: 'Common', color: '#C9A78C' },
  uncommon: { label: 'Uncommon', color: '#82B75E' },
  rare: { label: 'Rare', color: '#39BDE3' },
  epic: { label: 'Epic', color: '#AA8BCF' },
  legendary: { label: 'Legendary', color: '#F4B84E' },
};

export const SLOT_LABEL = { head: 'Head', neck: 'Neck', back: 'Back', tail: 'Tail' };
export const DECOR_SLOTS = {
  nest: { label: 'Nest', accepts: ['nest'] },
  left: { label: 'Left', accepts: ['side'] },
  right: { label: 'Right', accepts: ['side'] },
  back: { label: 'Back', accepts: ['side'] },
};

const ALL_STAGES = [1, 2, 3];

export const ITEMS = {
  leaf_scarf: {
    name: 'Leaf Scarf', category: 'wearable', slot: 'neck', price: 120, rarity: 'common',
    desc: 'A soft scarf made from fresh leaves and a tiny flower. Simple, cozy, and perfect for little adventures.',
    stages: ALL_STAGES, shop: 'wearables', featured: true,
  },
  golden_crest_crown: {
    name: 'Golden Crest Crown', category: 'wearable', slot: 'head', price: 150, rarity: 'rare',
    desc: 'A regal crown fit for a brave little explorer. Shines with the spirit of new adventures.',
    stages: ALL_STAGES, shop: 'wearables', featured: true, hero: true,
  },
  explorer_hat: {
    name: 'Explorer Hat', category: 'wearable', slot: 'head', price: 180, rarity: 'uncommon',
    desc: 'A trusty hat with trail goggles and a meadow feather. Ready for any path.',
    stages: ALL_STAGES, shop: 'wearables', featured: true,
  },
  blue_scarf: {
    name: 'Blue Scarf', category: 'wearable', slot: 'neck', price: 100, rarity: 'common',
    desc: 'A hand-knitted scarf the colour of a clear morning sky.',
    stages: ALL_STAGES, shop: 'wearables',
  },
  tiny_crown: {
    name: 'Tiny Crown', category: 'wearable', slot: 'head', price: 90, rarity: 'uncommon',
    desc: 'A little crown that sits at a jaunty angle. Royalty, but make it casual.',
    stages: ALL_STAGES, shop: 'wearables',
  },
  butterfly_clip: {
    name: 'Butterfly Clip', category: 'wearable', slot: 'head', price: 70, rarity: 'common',
    desc: 'A sunny butterfly that likes to ride along on walks.',
    stages: ALL_STAGES, shop: 'wearables',
  },
  red_backpack: {
    name: 'Red Backpack', category: 'wearable', slot: 'back', price: 140, rarity: 'uncommon',
    desc: 'Room for snacks, pebbles, and one very important leaf.',
    stages: ALL_STAGES, shop: 'wearables',
  },
  explorer_pack: {
    name: 'Explorer Pack', category: 'wearable', slot: 'back', price: 220, rarity: 'epic',
    desc: 'A leather pack with a rolled bedroll on top, for long journeys.',
    stages: ALL_STAGES, shop: 'wearables',
  },
  meadow_nest: {
    name: 'Meadow Nest', category: 'decoration', decor: 'nest', price: 200, rarity: 'rare',
    desc: 'A mossy nest woven with daisies. Your Evochi naps best here.',
    shop: 'habitats', featured: true,
  },
  nest_bed: {
    name: 'Nest Bed', category: 'decoration', decor: 'nest', price: 80, rarity: 'common',
    desc: 'A simple straw bed. Warm, soft, and smells like sunshine.',
    shop: 'habitats',
  },
  explorer_lantern: {
    name: 'Explorer Lantern', category: 'decoration', decor: 'side', price: 120, rarity: 'uncommon',
    desc: 'A warm lantern that keeps the nest cozy after sunset.',
    shop: 'habitats', featured: true,
  },
  sunlit_flower: {
    name: 'Sunlit Flower', category: 'decoration', decor: 'side', price: 45, rarity: 'common', stackable: true,
    desc: 'A cheerful daisy cluster that turns to face the sun.',
    shop: 'habitats',
  },
  berry_snack: {
    name: 'Berry Snack', category: 'consumable', price: 20, rarity: 'common', stackable: true,
    effect: { vitality: 4 },
    desc: 'A handful of sweet meadow berries. Restores 4 vitality.',
    shop: 'care',
  },
  healing_herb: {
    name: 'Healing Herb', category: 'consumable', price: 80, rarity: 'common', stackable: true,
    effect: { vitality: 10, recovery: true },
    desc: 'A soothing herb bundle. Restores 10 vitality (12h cooldown).',
    shop: 'care', featured: true,
  },

  // ---- Village Tales, Chapter 1 story rewards (Quest Bible §4) ----
  // Ordinary inventory items so they equip / place like everything else, but earned only from the
  // story: acquisition 'story', shop null, price null, never tradable or sellable, never in chests.
  reward_firefly_hearth: {
    name: 'Firefly Hearth', category: 'decoration', decor: 'nest', price: null, rarity: 'legendary',
    desc: 'A tiny hollow stump lit by three golden fireflies. Bram made it from the light you brought back to Sunlit Village.',
    shop: null, acquisition: 'story', originQuest: 'vq01', tradable: false, sellable: false,
  },
  reward_windtrail_mantle: {
    name: 'Windtrail Mantle', category: 'wearable', slot: 'back', price: null, rarity: 'legendary',
    desc: 'A short sky-blue travel cape, embroidered with cream trail lines and fastened with two copper clasps. Travelers should look the part.',
    stages: ALL_STAGES, shop: null, acquisition: 'story', originQuest: 'vq02', tradable: false, sellable: false,
  },
  reward_waystone_bloom: {
    name: 'Waystone Bloom', category: 'decoration', decor: 'side', price: null, rarity: 'legendary',
    desc: 'A white stone plinth with a floating mint-and-gold crystal blossom. It glows a little brighter when you walk.',
    shop: null, acquisition: 'story', originQuest: 'vq03', tradable: false, sellable: false,
  },

  // ---- Home: seeds (the Market's Garden shelf), harvests, Kitchen meals and Apothecary brews ----
  // Harvests and homemade food are ordinary stackable inventory items (acquisition 'home'): never sold
  // in the Market, so walking and the garden stay the way to get them.
  seed_sunberry: {
    name: 'Sunberry Seeds', category: 'seed', crop: 'sunberry', price: 8, rarity: 'common', stackable: true, shop: 'garden',
    desc: 'Plant in a garden bed. Ripe in about 20 minutes, and sooner when you walk. Farming Lv 1.',
  },
  seed_meadow_carrot: {
    name: 'Carrot Seeds', category: 'seed', crop: 'meadow_carrot', price: 10, rarity: 'common', stackable: true, shop: 'garden',
    desc: 'Crunchy Meadow Carrots in about 45 minutes. Farming Lv 1.',
  },
  seed_golden_wheat: {
    name: 'Wheat Seeds', category: 'seed', crop: 'golden_wheat', price: 12, rarity: 'common', stackable: true, shop: 'garden',
    desc: 'Golden Wheat for tarts and buns, ready in about 1.5 hours. Farming Lv 2.',
  },
  seed_glowleaf: {
    name: 'Glowleaf Seeds', category: 'seed', crop: 'glowleaf', price: 20, rarity: 'uncommon', stackable: true, shop: 'garden',
    desc: 'A softly shining herb for tonics. Slow growing: about 3 hours. Farming Lv 3.',
  },
  seed_moonshroom: {
    name: 'Moonshroom Spores', category: 'seed', crop: 'moonshroom', price: 35, rarity: 'rare', stackable: true, shop: 'garden',
    desc: 'Speckled mushrooms that glow at dusk. Takes about 6 hours. Farming Lv 5.',
  },
  sunberry: {
    name: 'Sunberry', category: 'ingredient', price: null, rarity: 'common', stackable: true, shop: null, acquisition: 'home',
    desc: 'Sweet, sun-warm berries from your own garden.',
  },
  meadow_carrot: {
    name: 'Meadow Carrot', category: 'ingredient', price: null, rarity: 'common', stackable: true, shop: null, acquisition: 'home',
    desc: 'A crunchy orange carrot with a leafy top.',
  },
  golden_wheat: {
    name: 'Golden Wheat', category: 'ingredient', price: null, rarity: 'common', stackable: true, shop: null, acquisition: 'home',
    desc: 'A bundle of golden wheat, ready for the oven.',
  },
  glowleaf: {
    name: 'Glowleaf', category: 'ingredient', price: null, rarity: 'uncommon', stackable: true, shop: null, acquisition: 'home',
    desc: 'A minty herb that glows faintly. The heart of every tonic.',
  },
  moonshroom: {
    name: 'Moonshroom', category: 'ingredient', price: null, rarity: 'rare', stackable: true, shop: null, acquisition: 'home',
    desc: 'A speckled violet mushroom with a soft night-time shimmer.',
  },
  sunberry_tart: {
    name: 'Sunberry Tart', category: 'consumable', kind: 'meal', price: null, rarity: 'uncommon', stackable: true, shop: null,
    acquisition: 'home', effect: { vitality: 8, treat: true },
    desc: 'Baked in your Cottage oven. Restores 8 vitality, and a homemade treat adds Bond once a day.',
  },
  carrot_stew: {
    name: 'Carrot Stew', category: 'consumable', kind: 'meal', price: null, rarity: 'common', stackable: true, shop: null,
    acquisition: 'home', effect: { vitality: 6, treat: true },
    desc: 'A warm bowl of stew. Restores 6 vitality; a homemade treat adds Bond once a day.',
  },
  golden_bun: {
    name: 'Golden Bun', category: 'consumable', kind: 'meal', price: null, rarity: 'common', stackable: true, shop: null,
    acquisition: 'home', effect: { vitality: 5, treat: true },
    desc: 'A soft wheat bun, still warm. Restores 5 vitality; a homemade treat adds Bond once a day.',
  },
  moonshroom_pie: {
    name: 'Moonshroom Pie', category: 'consumable', kind: 'meal', price: null, rarity: 'rare', stackable: true, shop: null,
    acquisition: 'home', effect: { vitality: 14, treat: true },
    desc: 'A savoury pie with a shimmering crust. Restores 14 vitality; a homemade treat adds Bond once a day.',
  },
  glowleaf_tonic: {
    name: 'Glowleaf Tonic', category: 'consumable', kind: 'potion', price: null, rarity: 'uncommon', stackable: true, shop: null,
    acquisition: 'home', effect: { vitality: 10 },
    desc: 'A gentle mint-green tonic. Restores 10 vitality. Some old friends of the forest love it.',
  },
  meadow_tea: {
    name: 'Meadow Tea', category: 'consumable', kind: 'potion', price: null, rarity: 'common', stackable: true, shop: null,
    acquisition: 'home', effect: { vitality: 6, treat: true },
    desc: 'Calming herb tea. Restores 6 vitality; a homemade treat adds Bond once a day.',
  },
  sprout_tonic: {
    name: 'Sprout Tonic', category: 'consumable', kind: 'garden', price: null, rarity: 'uncommon', stackable: true, shop: null,
    acquisition: 'home', effect: { growth: 0.5 },
    desc: 'Pour on a growing bed in your Garden: it grows half its time at once (once per planting).',
  },
  moonlight_draught: {
    name: 'Moonlight Draught', category: 'consumable', kind: 'potion', price: null, rarity: 'rare', stackable: true, shop: null,
    acquisition: 'home', effect: { vitality: 20, recovery: true },
    desc: 'A deep-blue draught full of tiny stars. Restores 20 vitality (12h cooldown, like a Healing Herb).',
  },

  // ---- Lumen Trails: found on discoveries, brewed for encounters, earned from the guardians
  lumen_shard: {
    name: 'Lumen Shard', category: 'ingredient', price: null, rarity: 'uncommon', stackable: true, shop: null, acquisition: 'trail',
    desc: 'A sliver of trail-light, cool to the touch. The Trail Guild trades them for nothing: they are for brewing Lantern Tonic.',
  },
  lantern_tonic: {
    name: 'Lantern Tonic', category: 'consumable', kind: 'potion', price: null, rarity: 'rare', stackable: true, shop: null,
    acquisition: 'home', effect: { vitality: 12, lantern: true },
    desc: 'Lumen in a bottle. Restores 12 vitality, and in an encounter it steadies the Hollow like nothing else.',
  },
  ancient_relic: {
    name: 'Ancient Relic', category: 'decoration', decor: 'side', price: null, rarity: 'legendary', shop: null, acquisition: 'story',
    originQuest: 'eq03',
    desc: 'A stone tablet from the Sentinel\'s gate, its three trail grooves glowing softly. A piece of the Lumen Trails for your nest.',
  },
};

/** Items the Market may ever list (story rewards and quest materials never qualify). */
export function isShopItem(id) {
  const it = ITEMS[id];
  return !!it && !!it.shop && it.acquisition !== 'story' && Number.isFinite(it.price);
}

export const STORY_SOURCE = { vq01: 'Village Tales, Quest 01', vq02: 'Village Tales, Quest 02', vq03: 'Village Tales, Quest 03', eq03: 'Lumen Trails, Quest 03' };

export const CATEGORY_LABEL = { wearable: 'Wearables', consumable: 'Consumables', decoration: 'Decorations', seed: 'Seeds', ingredient: 'Ingredients' };

export function item(id) {
  const it = ITEMS[id];
  if (!it) throw new Error('Unknown item ' + id);
  return it;
}

export function isStackable(id) {
  const it = item(id);
  return it.category === 'consumable' || !!it.stackable;
}

export function itemCompatible(id, stage) {
  const it = item(id);
  if (it.category !== 'wearable') return true;
  return (it.stages || ALL_STAGES).includes(stage);
}
