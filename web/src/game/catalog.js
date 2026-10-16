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
};

/** Items the Market may ever list (story rewards and quest materials never qualify). */
export function isShopItem(id) {
  const it = ITEMS[id];
  return !!it && !!it.shop && it.acquisition !== 'story' && Number.isFinite(it.price);
}

export const STORY_SOURCE = { vq01: 'Village Tales, Quest 01', vq02: 'Village Tales, Quest 02', vq03: 'Village Tales, Quest 03' };

export const CATEGORY_LABEL = { wearable: 'Wearables', consumable: 'Consumables', decoration: 'Decorations' };

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
