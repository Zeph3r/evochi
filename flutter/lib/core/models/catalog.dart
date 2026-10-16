// Starter catalog (style guide §18-19). Prices are starting values.
// Story rewards (Village Tales) are catalog items too, so they equip and place like any other, but
// they are never sold: acquisition 'story', no price, no shop, not tradable, not sellable.

enum ItemCategory { wearable, consumable, decoration }

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
    this.stages = const [1, 2, 3],
  }) : listPrice = price;

  final String id;
  final String name;
  final ItemCategory category;
  final int? listPrice; // null for story rewards (never sold)
  final String rarity;
  final String desc;
  final String? shop; // wearables | care | habitats; null = not in the Market
  final String acquisition; // shop | story
  final String? originQuest; // story rewards: the quest that grants it
  final bool tradable;
  final bool sellable;
  final String? slot; // head | neck | back | tail
  final String? decor; // nest | side
  final bool featured;
  final bool stackable;
  final int vitality;
  final bool recovery;
  final List<int> stages;

  bool get isStackable => category == ItemCategory.consumable || stackable;
  bool get isStory => acquisition == 'story';
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
};

/// Can this item be bought in the Market (and rolled as a quest cosmetic)? Story items never can.
bool isShopItem(String id) => catalog[id]?.forSale ?? false;

const storySource = {'vq01': 'Village Tales, Quest 01', 'vq02': 'Village Tales, Quest 02', 'vq03': 'Village Tales, Quest 03'};

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
