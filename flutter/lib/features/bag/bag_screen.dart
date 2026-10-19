// S09 Bag / inventory with live equipment preview (style guide §11, §19). The Pantry holds Home Tales
// seeds and harvests (Plant / Cook / Cottage); homemade meals sit in Care and are given as treats.
//
// Two presentations (web/src/screens/bag.js): Wear is a dressing room (a bigger Evochi centred on its
// platform with the equipment slots around it, the wearables in one strip, and one big Equip or Take
// off); the other pockets give the grid the room (a smaller Evochi, the grid filling the satchel, and an
// item card that opens for more). Picking food makes the Evochi hop for it.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/router.dart';
import '../../app/theme.dart';
import '../../controllers/game_controller.dart';
import '../../core/models/catalog.dart';
import '../../core/models/game_state.dart';
import '../../game/engine.dart' as g;
import '../../game/home/home.dart' as h;
import '../home/home_widgets.dart';
import '../nest/sheets.dart';
import '../shared/kit.dart';
import '../shared/scene_scaffold.dart';
import '../shared/scene_view.dart';
import '../shared/widgets.dart';
import '../village/story_widgets.dart';

// (pocket, short tab label, icon, full name). 'pantry' holds seeds and ingredients; 'pouch' is the
// Quest Pouch (Village Tales materials, which are never catalog items).
const _cats = <(String, String, String, String)>[
  ('wearable', 'Wear', 'wearables', 'Wearables'),
  ('consumable', 'Care', 'consumables', 'Consumables'),
  ('decoration', 'Decor', 'decorations', 'Decorations'),
  ('pantry', 'Pantry', 'skill_farming', 'Pantry: seeds and ingredients'),
  ('pouch', 'Pouch', 'journey', 'Quest Pouch'),
];

/// The catalog categories in a Bag pocket, in display order.
List<ItemCategory> _pocket(String cat) => switch (cat) {
      'wearable' => const [ItemCategory.wearable],
      'consumable' => const [ItemCategory.consumable],
      'decoration' => const [ItemCategory.decoration],
      'pantry' => const [ItemCategory.seed, ItemCategory.ingredient],
      _ => const <ItemCategory>[],
    };

const _catIcon = {
  ItemCategory.wearable: 'wearables',
  ItemCategory.consumable: 'consumables',
  ItemCategory.decoration: 'decorations',
  ItemCategory.seed: 'skill_farming',
  ItemCategory.ingredient: 'skill_cooking',
};
const _slotUi = {'head': 'Head', 'back': 'Back', 'neck': 'Neck'};

/// "Uncommon" with a leaf, or the gold "Story reward" label.
Widget _rarityTag(CatalogItem it) => it.isStory ? const StoryRewardTag(small: true) : Tag(it.rarity[0].toUpperCase() + it.rarity.substring(1), tone: TagTone.ok, icon: 'care');

class BagScreen extends StatefulWidget {
  const BagScreen({super.key, required this.active});
  final bool active;
  @override
  State<BagScreen> createState() => _BagScreenState();
}

class _BagScreenState extends State<BagScreen> {
  final _scene = SceneController();
  String _cat = 'wearable';
  String? _sel;
  String? _selQ;
  bool _more = false; // the item card opened for its full text

  bool get _pouch => _cat == 'pouch';
  bool get _wear => _cat == 'wearable';

  List<String> _owned(GameController c, String cat) {
    final cats = _pocket(cat);
    final list = c.state.inventory.entries.where((e) => e.value.quantity > 0 && cats.contains(catalog[e.key]?.category)).map((e) => e.key).toList();
    list.sort((a, b) {
      final k = cats.indexOf(item(a).category) - cats.indexOf(item(b).category);
      return k != 0 ? k : item(a).name.compareTo(item(b).name);
    });
    return list;
  }

  void _pick(GameController c, String id) {
    final it = item(id);
    setState(() {
      // tapping the chosen item again opens (or closes) its card
      _more = _sel == id && it.category != ItemCategory.wearable ? !_more : false;
      _sel = id;
    });
    if (it.category == ItemCategory.wearable) {
      _scene.react('equip');
      c.analytics.track('item_previewed', {'item': id});
    } else if (it.category == ItemCategory.consumable && it.growth <= 0) {
      _scene.react('snack'); // food: an excited hop and hearts
    } else {
      _scene.react('inspect');
    }
    c.audio.play('ui_tap', volume: 0.4);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<GameController>();
    final req = c.bagCategoryRequest;
    if (req != null && _cats.any((x) => x.$1 == req)) {
      c.bagCategoryRequest = null;
      _cat = req;
      _sel = null;
      _more = false;
    }
    final reqItem = c.bagItemRequest;
    if (reqItem != null) {
      c.bagItemRequest = null;
      _sel = reqItem; // (dropped below if it isn't in this pocket)
    }
    final pet = c.state.pet!;
    final v = c.view;
    final list = _pouch ? const <String>[] : _owned(c, _cat);
    if (_sel != null && (!list.contains(_sel))) _sel = null;
    if (!_pouch) {
      _sel ??= _wear ? (pet.equipped.values.isNotEmpty ? pet.equipped.values.first : (list.isEmpty ? null : list.first)) : (list.isEmpty ? null : list.first);
    }
    if (_selQ != null && (c.storyView.pouch[_selQ] ?? 0) <= 0) _selQ = null;
    final sel = _sel;
    final equipped = Map<String, String>.of(pet.equipped);
    if (sel != null && item(sel).category == ItemCategory.wearable) equipped[item(sel).slot!] = sel; // try-on preview
    final mq = MediaQuery.of(context);
    final reduce = mq.disableAnimations;
    final cols = mq.size.width >= 370 ? 4 : 3;
    final wear = _wear;
    // a traveller's satchel: a canvas sheet in a stitched frame, fabric tabs, cloth pockets
    return Scaffold(
      body: KitPage(
        material: KitMaterial.satchel,
        paper: false,
        child: SceneScaffold(
          controller: _scene,
          onPetTap: () => _scene.react('pet'),
          petLabel: pet.name,
          minHero: wear ? 220 : 140,
          // the pockets: a short hero (20% of the screen, 140-180) and the satchel fills the rest
          heroHeight: wear ? null : (mq.size.height * 0.2).clamp(140.0, 180.0).toDouble(),
          bottomInset: navInset(context),
          headerAllowance: 70,
          groundOffset: 20,
          config: (gy) => SceneConfig(
            habitat: 'meadow',
            platform: true,
            focus: Offset(wear ? 0.5 : 0.45, gy),
            reducedMotion: reduce,
            pet: PetConfig(stage: pet.stage, palette: pet.paletteId, status: v.pet!.status, equipped: equipped.values.toList(), scale: wear ? 1.3 : 0.8),
          ),
          header: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
            child: Row(children: [
              const TitleImage('title_bag', height: 44, label: 'Bag'),
              const Spacer(),
              CoinPill(balance: v.balance, onPlus: () => showCoinsInfo(context)),
            ]),
          ),
          heroBuilder: wear ? (ctx, pr) => _dressingRoom(c, pet, sel, pr) : null,
          hero: wear ? null : const SizedBox.expand(),
          panel: wear ? _wearPanel(c, list, sel) : _pocketPanel(c, list, sel, cols),
        ),
      ),
    );
  }

  Widget _tabs() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(children: [
          for (final cat in _cats)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: _TabChip(
                  label: cat.$2,
                  fullLabel: cat.$4,
                  icon: cat.$3,
                  selected: _cat == cat.$1,
                  onTap: () => setState(() {
                    _cat = cat.$1;
                    _sel = null;
                    _selQ = null;
                    _more = false;
                  }),
                ),
              ),
            ),
        ]),
      );

  /// The satchel: a canvas sheet in the stitched cloth frame.
  Widget _satchel(Widget child) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: FramedWindow(
          variant: FrameVariant.cloth,
          border: 13,
          padding: const EdgeInsets.fromLTRB(4, 6, 4, 6), // tight, so 360 px phones keep their room
          sheet: Kit.sheet(weave: true, colors: const [Color(0xFFEFDDBA), Color(0xFFE2C99E)]),
          shadow: const BoxShadow(color: Color(0x40321C0A), blurRadius: 14, offset: Offset(0, -4)),
          child: child,
        ),
      );

  Widget _empty() => Padding(
        padding: const EdgeInsets.all(18),
        child: Column(children: [
          Opacity(opacity: 0.6, child: VoxelIcon(_cats.firstWhere((x) => x.$1 == _cat).$3, size: 54)),
          const SizedBox(height: 6),
          const Text('Nothing in this pocket yet.', style: EvochiText.cardTitle),
          const SizedBox(height: 10),
          if (_cat == 'pantry')
            EvochiButton(label: 'Visit your Garden', small: true, expand: false, tone: ButtonTone.green, onPressed: () => openGarden(context))
          else
            EvochiButton(label: 'Visit the Market', small: true, expand: false, onPressed: () => TabNav.of(context).go('shop')),
        ]),
      );

  Widget _tile(GameController c, String id, String? sel) {
    final pet = c.state.pet!;
    return _ItemTile(
      id: id,
      qty: g.ownedQty(c.state, id),
      selected: id == sel,
      marked: pet.equipped.values.contains(id) || c.state.placements.values.contains(id),
      onTap: () => _pick(c, id),
    );
  }

  // ------------------------------------------------------------ the dressing room ----
  /// The equipment slots around the Evochi ([pr]: its rect in the hero) and the "Dressing room" /
  /// "Trying on" tag over its head (web: bag.position).
  Widget _dressingRoom(GameController c, Pet pet, String? sel, Rect? pr) => LayoutBuilder(builder: (ctx, b) {
        const bw = 60.0, bh = 74.0;
        final w = b.maxWidth, hh = b.maxHeight;
        double cx(double x) => x.clamp(6.0, math.max(6.0, w - bw - 6)).toDouble();
        double cy(double y) => y.clamp(0.0, math.max(0.0, hh - bh)).toDouble();
        final selIt = sel == null ? null : item(sel);
        final trying = selIt != null && selIt.category == ItemCategory.wearable && pet.equipped[selIt.slot] != sel;
        final kids = <Widget>[];
        // (no rect on the very first frame, before the scene is measured: the slots wait a frame)
        if (pr != null) {
          final mid = pr.center.dx;
          final midY = pr.top + pr.height * 0.62;
          final vis = pr.width * 0.24;
          if (w - 6 - (mid + vis + 14) >= bw * 2 + 10) {
            kids.addAll([
              Positioned(left: cx(mid - vis - bw - 14), top: cy(midY - 38), child: _slotBox(c, pet, sel, 'head')),
              Positioned(left: cx(mid + vis + 14), top: cy(midY - 38), child: _slotBox(c, pet, sel, 'back')),
              Positioned(left: cx(mid + vis + 14 + bw + 10), top: cy(midY - 38), child: _slotBox(c, pet, sel, 'neck')),
            ]);
          } else {
            // narrow phones: Head and Back stack on the left, Accessory on the right
            final leftX = math.max(6.0, mid - vis - bw - 10);
            final top = cy(math.max(4.0, midY - 82));
            kids.addAll([
              Positioned(left: leftX, top: top, child: _slotBox(c, pet, sel, 'head')),
              Positioned(left: leftX, top: cy(top + 84), child: _slotBox(c, pet, sel, 'back')),
              Positioned(left: cx(math.min(w - bw - 6, mid + vis + 10)), top: cy(midY - 38), child: _slotBox(c, pet, sel, 'neck')),
            ]);
          }
          kids.add(Positioned(
            left: (mid - 90).clamp(0.0, math.max(0.0, w - 180)).toDouble(),
            width: 180,
            top: math.max(0.0, pr.top + pr.height * 0.02 - 36),
            // a parchment tag with a tail pointing at the try-on
            child: IgnorePointer(
              child: Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    height: 30,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    alignment: Alignment.center,
                    decoration: Kit.parchment(radius: 9),
                    child: Text(trying ? 'Trying on' : 'Dressing room', style: EvochiText.tag.copyWith(color: EvochiColor.ink, fontWeight: FontWeight.w900, fontSize: 14)),
                  ),
                  const KitTail(width: 12, height: 7),
                ]),
              ),
            ),
          ));
        }
        return Stack(children: kids);
      });

  Widget _slotBox(GameController c, Pet pet, String? sel, String slot) {
    final id = pet.equipped[slot];
    final active = sel != null && item(sel).slot == slot;
    return Semantics(
      button: true,
      label: '${_slotUi[slot]} slot: ${id == null ? 'empty' : item(id).name}',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: () => setState(() {
          _cat = 'wearable';
          _more = false;
          _sel = id ?? _owned(c, 'wearable').where((x) => item(x).slot == slot).firstOrNull;
          if (_sel == null) c.toast('No ${_slotUi[slot]!.toLowerCase()} items yet - find some in the Market', icon: 'shop', kind: 'warn');
        }),
        // an equipment slot: a parchment box with a dark wood edge (lit gold while chosen)
        child: Container(
          width: 60,
          height: 74,
          padding: const EdgeInsets.only(top: 4),
          decoration: active
              ? KitDecoration(
                  base: BoxDecoration(
                    gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFFFF6DE), Color(0xFFFFE8B0)]),
                    image: kitGrain,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFF2B544), width: 2.5),
                    boxShadow: const [BoxShadow(color: Color(0x99FFBE46), blurRadius: 14), BoxShadow(color: Color(0xFFD99B33), offset: Offset(0, 3)), BoxShadow(color: Color(0xFFF7CD70), spreadRadius: 2)],
                  ),
                  inset: 2.5,
                )
              : KitDecoration(
                  base: BoxDecoration(
                    gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFFFF8E6), Color(0xFFEFD8AE)]),
                    image: kitGrain,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: KitColor.woodEdge, width: 2.5),
                    boxShadow: const [BoxShadow(color: Color(0x40321C0A), blurRadius: 12, offset: Offset(0, 6)), BoxShadow(color: KitColor.woodEdge, offset: Offset(0, 3))],
                  ),
                  inset: 2.5,
                  shadow: const BoxShadow(color: Color(0x336E461E), blurRadius: 5, offset: Offset(0, 2)),
                ),
          child: Stack(clipBehavior: Clip.none, children: [
            Column(children: [
              if (id != null) ItemImage(id, size: 44) else Opacity(opacity: 0.35, child: VoxelIcon(slot == 'head' ? 'wearables' : (slot == 'back' ? 'bag' : 'care'), size: 40)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: FittedBox(fit: BoxFit.scaleDown, child: Text(_slotUi[slot]!, maxLines: 1, style: EvochiText.tag.copyWith(fontSize: 12))),
              ),
            ]),
            // an empty slot gets a small "+"
            if (id == null)
              Positioned(
                right: 2,
                top: 26,
                child: Container(
                  width: 18,
                  height: 18,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: KitColor.woodEdge, shape: BoxShape.circle, border: Border.all(color: const Color(0xFFFFF1D2), width: 1.5)),
                  child: const Text('+', style: TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w900, fontSize: 13, height: 1, color: Colors.white)),
                ),
              ),
          ]),
        ),
      ),
    );
  }

  /// Wear: the tabs, one strip of wearables (80 x 92 pockets), and the bar with one big button.
  Widget _wearPanel(GameController c, List<String> list, String? sel) => Column(children: [
        _tabs(),
        const SizedBox(height: 10),
        _satchel(Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (list.isEmpty)
            _empty()
          else
            SizedBox(
              height: 100,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(3, 4, 3, 4),
                itemCount: list.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) => SizedBox(width: 80, child: _tile(c, list[i], sel)),
              ),
            ),
          if (sel != null && item(sel).category == ItemCategory.wearable) ...[const SizedBox(height: 8), _WearBar(id: sel, scene: _scene)],
        ])),
      ]);

  /// The other pockets: the tabs and a satchel that fills the screen, the grid scrolling in it and the
  /// item card at its foot.
  Widget _pocketPanel(GameController c, List<String> list, String? sel, int cols) => Column(children: [
        _tabs(),
        const SizedBox(height: 10),
        Expanded(
          child: _satchel(LayoutBuilder(builder: (ctx, b) {
            final Widget body;
            Widget? card;
            if (_pouch) {
              body = SingleChildScrollView(padding: const EdgeInsets.all(2), child: PouchGrid(selected: _selQ, cols: cols, onSelect: (id) => setState(() => _selQ = id)));
              if (_selQ != null) card = PouchDetail(id: _selQ!);
            } else if (list.isEmpty) {
              body = SingleChildScrollView(child: _empty());
            } else {
              // tiles keep their own height: the rows never stretch to fill the satchel
              body = GridView.count(
                crossAxisCount: cols,
                padding: const EdgeInsets.fromLTRB(3, 4, 3, 4),
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 0.86,
                children: [for (final id in list) _tile(c, id, sel)],
              );
              if (sel != null) {
                card = _ItemCard(id: sel, scene: _scene, more: _more, onMore: () => setState(() => _more = !_more));
              }
            }
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Expanded(child: body),
              if (card != null) ...[
                const SizedBox(height: 8),
                // the card never takes more than about 60% of the satchel; open, it scrolls
                ConstrainedBox(constraints: BoxConstraints(maxHeight: math.max(0.0, b.maxHeight * 0.62)), child: SingleChildScrollView(child: card)),
              ],
            ]);
          })),
        ),
      ]);
}

class _TabChip extends StatelessWidget {
  const _TabChip({required this.label, required this.fullLabel, required this.icon, required this.selected, required this.onTap});
  final String label;
  final String fullLabel;
  final String icon;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
        selected: selected,
        button: true,
        label: fullLabel,
        excludeSemantics: true,
        child: GestureDetector(
          onTap: onTap,
          // a stitched fabric tab
          child: KitTab(
            selected: selected,
            style: KitTabStyle.cloth,
            height: 48,
            radius: const BorderRadius.vertical(top: Radius.circular(12), bottom: Radius.circular(6)),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              VoxelIcon(icon, size: 24),
              const SizedBox(width: 3),
              Flexible(child: FittedBox(fit: BoxFit.scaleDown, child: Text(label, style: KitTab.label(EvochiText.tag, selected, style: KitTabStyle.cloth)))),
            ]),
          ),
        ),
      );
}

class _ItemTile extends StatelessWidget {
  const _ItemTile({required this.id, required this.qty, required this.selected, required this.marked, required this.onTap});
  final String id;
  final int qty;
  final bool selected;
  final bool marked;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final it = item(id);
    return Semantics(
      selected: selected,
      button: true,
      label: '${it.name}${qty > 1 ? ', $qty owned' : ''}${marked ? ', in use' : ''}',
      child: GestureDetector(
        onTap: onTap,
        // a cloth pocket with a stitched seam
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: Kit.slot(selected: selected, radius: 12, cloth: true),
          child: Stack(children: [
            Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Expanded(child: ItemImage(id, size: 62)),
              Text(it.name, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: EvochiText.tag.copyWith(fontSize: 12, color: EvochiColor.ink)),
            ]),
            if (it.category != ItemCategory.wearable && (qty > 1 || it.isStackable))
              Positioned(
                right: 0,
                top: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4E3018),
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(color: const Color(0xFFF2D49E), width: 1.5),
                    boxShadow: const [BoxShadow(color: Color(0x4D000000), offset: Offset(0, 1))],
                  ),
                  child: Text('x$qty', style: EvochiText.tag.copyWith(color: Colors.white, fontSize: 11.5)), // a counter: stays compact
                ),
              ),
            if (marked) const Positioned(left: 0, top: 0, child: Icon(Icons.check_circle, color: EvochiColor.steps, size: 20)),
            if (it.isStory) const Positioned(right: 0, bottom: 18, child: VoxelIcon('star', size: 20)),
          ]),
        ),
      ),
    );
  }
}

/// The dressing room's bar under the strip: what you're trying on, its slot and rarity, and one big
/// button (gold Equip, or cream Take off when it's already worn).
class _WearBar extends StatelessWidget {
  const _WearBar({required this.id, required this.scene});
  final String id;
  final SceneController scene;
  @override
  Widget build(BuildContext context) {
    final c = context.watch<GameController>();
    final it = item(id);
    final eq = c.state.pet!.equipped[it.slot] == id;
    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        decoration: KitDecoration(
          base: BoxDecoration(
            gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFFFF9EA), Color(0xFFF4E2C0)]),
            image: kitGrain,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF8C6A44), width: 2),
            boxShadow: const [BoxShadow(color: Color(0xFF6E5236), offset: Offset(0, 3))],
          ),
          inset: 2,
          ring: const KitBand(2, Color(0xB3FFFCF0)),
        ),
        child: Row(children: [
          Container(width: 54, height: 54, alignment: Alignment.center, decoration: Kit.well(), child: ItemImage(id, size: 46)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(it.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w900, fontSize: 16.5, height: 1.15, color: EvochiColor.ink)),
              const SizedBox(height: 4),
              // (scaled down rather than overflowing beside the big button on narrow phones)
              Wrap(spacing: 4, runSpacing: 4, children: [
                FittedBox(fit: BoxFit.scaleDown, child: Tag(_slotUi[it.slot] ?? 'Wearable', icon: 'wearables')),
                FittedBox(fit: BoxFit.scaleDown, child: _rarityTag(it)),
              ]),
            ]),
          ),
          const SizedBox(width: 10),
          if (eq)
            EvochiButton(
              label: 'Take off',
              large: true,
              expand: false,
              tone: ButtonTone.cream,
              semanticLabel: 'Take off ${it.name}',
              icon: const Icon(Icons.delete_outline_rounded, color: EvochiColor.wood, size: 22),
              onPressed: () => c.run((s, n) => g.unequip(s, it.slot!)),
            )
          else
            EvochiButton(
              label: 'Equip',
              large: true,
              expand: false,
              icon: const Icon(Icons.checkroom_rounded, color: EvochiColor.wood, size: 22),
              onPressed: () {
                if (c.run((s, n) => g.equip(s, id, n)).ok) {
                  scene.react('equip');
                  c.audio.play('reward_chime', volume: 0.5);
                  c.toast('${it.name} equipped', icon: 'wearables');
                  c.analytics.track('accessory_equipped', {'item': id});
                }
              },
            ),
        ]),
      ),
    );
  }
}

/// The pockets' item card: its picture, name and tags, two lines of description with More / Less for
/// the rest (and where it came from, what it's used in), and the actions in a full-width row below.
class _ItemCard extends StatelessWidget {
  const _ItemCard({required this.id, required this.scene, required this.more, required this.onMore});
  final String id;
  final SceneController scene;
  final bool more;
  final VoidCallback onMore;
  @override
  Widget build(BuildContext context) {
    final c = context.watch<GameController>();
    final it = item(id);
    final pet = c.state.pet!;
    final pv = c.view.pet!;
    final List<Widget> buttons;
    String? note;
    String tag;
    switch (it.category) {
      case ItemCategory.wearable:
        final eq = pet.equipped[it.slot] == id;
        tag = _slotUi[it.slot] ?? 'Wearable';
        buttons = [
          EvochiButton(
            label: eq ? 'Equipped' : 'Equip',
            small: true,
            icon: const Icon(Icons.checkroom_rounded, color: EvochiColor.wood, size: 20),
            onPressed: eq
                ? null
                : () {
                    if (c.run((s, n) => g.equip(s, id, n)).ok) {
                      scene.react('equip');
                      c.audio.play('reward_chime', volume: 0.5);
                      c.toast('${it.name} equipped', icon: 'wearables');
                      c.analytics.track('accessory_equipped', {'item': id});
                    }
                  },
          ),
          EvochiButton(
            label: 'Remove',
            small: true,
            tone: ButtonTone.cream,
            icon: const Icon(Icons.delete_outline_rounded, color: EvochiColor.wood, size: 20),
            onPressed: eq ? () => c.run((s, n) => g.unequip(s, it.slot!)) : null,
          ),
        ];
      case ItemCategory.consumable when it.growth > 0:
        tag = 'Garden';
        buttons = [EvochiButton(label: 'Use in Garden', small: true, tone: ButtonTone.green, onPressed: () => openGarden(context))];
      case ItemCategory.consumable:
        tag = it.kind == 'meal' ? 'Homemade' : 'Care';
        final cool = it.recovery && pv.recoveryReadyAt > c.now;
        final treatOpen = it.treat && !g.treatGivenToday(c.state, c.view.today);
        final full = pv.vitality.vitality >= 100 && !treatOpen;
        buttons = [
          EvochiButton(
            label: it.treat ? 'Give' : 'Use',
            small: true,
            tone: ButtonTone.green,
            onPressed: cool || pv.dead || full
                ? null
                : () {
                    final r = c.run((s, n) => g.useConsumable(s, id, n));
                    if (!r.ok) return;
                    final used = r.events.where((e) => e.type == 'used').firstOrNull;
                    final vit = (used?.data['vitality'] as int?) ?? 0;
                    final treat = r.events.any((e) => e.type == 'treat');
                    scene.react(treat ? 'play' : 'pet');
                    c.toast(treat ? '${pet.name} loved the ${it.name}!${vit > 0 ? ' +$vit vitality' : ''}' : '+$vit vitality', icon: 'heart');
                    c.audio.play(treat ? 'pet_chirp' : 'reward_chime', volume: 0.6);
                  },
          ),
        ];
        note = full ? 'Vitality full' : (cool ? 'Cooling down' : (treatOpen ? 'Treat: Bond +1' : 'Vitality ${pv.vitality.vitality}'));
      case ItemCategory.seed:
        tag = 'Seed';
        buttons = [EvochiButton(label: 'Plant', small: true, tone: ButtonTone.green, onPressed: () => openGarden(context))];
        note = 'Farming Lv ${h.cropDefs[it.crop]?.level ?? 1}';
      case ItemCategory.ingredient:
        tag = 'Ingredient';
        final room = h.recipesUsing(id).map((r) => r.station).where((st) => h.stationOpen(c.state, st)).firstOrNull;
        buttons = [
          if (room != null)
            EvochiButton(label: h.stationDefs[room]!.verb, small: true, onPressed: () => openStation(context, room))
          else
            EvochiButton(label: 'Cottage', small: true, tone: ButtonTone.cream, onPressed: () => openCottage(context)),
        ];
      case ItemCategory.decoration:
        tag = 'Decoration';
        final placed = c.state.placements.values.where((x) => x == id).length;
        buttons = [
          EvochiButton(
            label: 'Place',
            small: true,
            onPressed: placed >= g.ownedQty(c.state, id)
                ? null
                : () {
                    final target = decorSlots.values.where((s) => s.accepts == it.decor).toList();
                    final slot = target.where((s) => c.state.placements[s.id] == null).firstOrNull ?? target.first;
                    if (c.run((s, n) => g.placeDecoration(s, id, slot.id)).ok) {
                      c.toast('${it.name} placed in the ${slot.label.toLowerCase()} spot', icon: 'decorations');
                      c.analytics.track('decoration_placed', {'item': id});
                    }
                  },
          ),
          EvochiButton(label: 'Arrange', small: true, tone: ButtonTone.cream, onPressed: () => showHabitatSheet(context)),
        ];
    }
    final uses = it.category == ItemCategory.ingredient ? h.recipesUsing(id) : const <h.RecipeDef>[];
    return Semantics(
      liveRegion: true,
      container: true,
      child: GameCard(
        paper: satchelPaper,
        padding: const EdgeInsets.all(8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(width: 64, height: 64, decoration: Kit.well(), alignment: Alignment.center, child: ItemImage(id, size: 56)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(it.name, style: EvochiText.cardTitle),
                const SizedBox(height: 4),
                Wrap(spacing: 4, runSpacing: 4, children: [Tag(tag, icon: _catIcon[it.category]), _rarityTag(it)]),
                const SizedBox(height: 4),
                Text(
                  it.desc,
                  maxLines: more ? null : 2,
                  overflow: more ? TextOverflow.visible : TextOverflow.ellipsis,
                  style: EvochiText.bodyText.copyWith(color: EvochiColor.textSecondary, height: 1.36),
                ),
                if (more) ...[
                  storySourceLine(id),
                  if (uses.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text('Used in: ${uses.map((r) => item(r.makes).name).join(', ')}', style: EvochiText.tiny),
                    ),
                ],
                Semantics(
                  button: true,
                  label: more ? 'Show less' : 'Show more about ${it.name}',
                  excludeSemantics: true,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onMore,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(0, 6, 16, 4),
                      child: Text(more ? 'Less ▴' : 'More ▾', style: const TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w800, fontSize: 13, color: Color(0xFF9A6418))),
                    ),
                  ),
                ),
              ]),
            ),
          ]),
          const SizedBox(height: 6),
          Row(children: [
            for (var i = 0; i < buttons.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(child: buttons[i]),
            ],
            if (note != null) ...[
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 132),
                child: Text(note, textAlign: TextAlign.right, maxLines: 2, style: EvochiText.tiny),
              ),
            ],
          ]),
        ]),
      ),
    );
  }
}
