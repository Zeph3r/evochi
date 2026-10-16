// S09 Bag / inventory with live equipment preview (style guide §11, §19).

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/router.dart';
import '../../app/theme.dart';
import '../../controllers/game_controller.dart';
import '../../core/models/catalog.dart';
import '../../game/engine.dart' as g;
import '../nest/sheets.dart';
import '../shared/scene_scaffold.dart';
import '../shared/scene_view.dart';
import '../shared/widgets.dart';
import '../village/story_widgets.dart';

// (category, short tab label, icon, full name). A null category is the Quest Pouch (Village Tales
// materials, which are never catalog items).
const _cats = <(ItemCategory?, String, String, String)>[
  (ItemCategory.wearable, 'Wear', 'wearables', 'Wearables'),
  (ItemCategory.consumable, 'Care', 'consumables', 'Consumables'),
  (ItemCategory.decoration, 'Decor', 'decorations', 'Decorations'),
  (null, 'Pouch', 'journey', 'Quest Pouch'),
];
const _slotUi = {'head': 'Head', 'back': 'Back', 'neck': 'Accessory'};

class BagScreen extends StatefulWidget {
  const BagScreen({super.key, required this.active});
  final bool active;
  @override
  State<BagScreen> createState() => _BagScreenState();
}

class _BagScreenState extends State<BagScreen> {
  final _scene = SceneController();
  ItemCategory _cat = ItemCategory.wearable;
  bool _pouch = false;
  String? _sel;
  String? _selQ;

  List<String> _owned(GameController c, ItemCategory cat) {
    final list = c.state.inventory.entries.where((e) => e.value.quantity > 0 && catalog[e.key]?.category == cat).map((e) => e.key).toList();
    list.sort((a, b) => item(a).name.compareTo(item(b).name));
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<GameController>();
    if (c.bagCategoryRequest == 'pouch') {
      c.bagCategoryRequest = null;
      _pouch = true;
    }
    final pet = c.state.pet!;
    final v = c.view;
    final list = _pouch ? const <String>[] : _owned(c, _cat);
    if (_sel != null && (!list.contains(_sel))) _sel = null;
    if (!_pouch) {
      _sel ??= _cat == ItemCategory.wearable ? (pet.equipped.values.isNotEmpty ? pet.equipped.values.first : (list.isEmpty ? null : list.first)) : (list.isEmpty ? null : list.first);
    }
    if (_selQ != null && (c.storyView.pouch[_selQ] ?? 0) <= 0) _selQ = null;
    final sel = _sel;
    final equipped = Map<String, String>.of(pet.equipped);
    if (sel != null && item(sel).category == ItemCategory.wearable) equipped[item(sel).slot!] = sel; // try-on preview
    final reduce = MediaQuery.of(context).disableAnimations;
    final cols = MediaQuery.of(context).size.width >= 370 ? 4 : 3;
    return Scaffold(
      body: SceneScaffold(
        controller: _scene,
        onPetTap: () => _scene.react('pet'),
        petLabel: pet.name,
        minHero: 190,
        bottomInset: navInset(context),
        headerAllowance: 70,
        groundOffset: 20,
        config: (gy) => SceneConfig(
          habitat: 'meadow',
          platform: true,
          focus: Offset(0.45, gy),
          reducedMotion: reduce,
          pet: PetConfig(stage: pet.stage, palette: pet.paletteId, status: v.pet!.status, equipped: equipped.values.toList()),
        ),
        header: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
          child: Row(children: [
            const TitleImage('title_bag', height: 44, label: 'Bag'),
            const Spacer(),
            CoinPill(balance: v.balance, onPlus: () => showCoinsInfo(context)),
          ]),
        ),
        hero: LayoutBuilder(builder: (ctx, b) {
          Widget slotBox(String slot) {
            final id = pet.equipped[slot];
            final active = sel != null && item(sel).slot == slot;
            return Semantics(
              button: true,
              label: '${_slotUi[slot]} slot: ${id == null ? 'empty' : item(id).name}',
              child: GestureDetector(
                onTap: () => setState(() {
                  _cat = ItemCategory.wearable;
                  _pouch = false;
                  _sel = id ?? _owned(c, ItemCategory.wearable).where((x) => item(x).slot == slot).firstOrNull;
                  if (_sel == null) c.toast('No ${_slotUi[slot]!.toLowerCase()} items yet - find some in the Market', icon: 'shop', kind: 'warn');
                }),
                child: Container(
                  width: 60,
                  height: 74,
                  padding: const EdgeInsets.only(top: 4),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: active ? const Color(0xFFF2B544) : const Color(0xFFE2CDB4), width: 2),
                    color: active ? const Color(0xFFFFF0C8) : const Color(0xF0FFFAF3),
                    boxShadow: [BoxShadow(color: active ? const Color(0xFFD99B33) : const Color(0xFFCDB396), offset: const Offset(0, 3))],
                  ),
                  child: Column(children: [
                    if (id != null) ItemImage(id, size: 44) else Opacity(opacity: 0.35, child: VoxelIcon(slot == 'head' ? 'wearables' : (slot == 'back' ? 'bag' : 'care'), size: 40)),
                    Text(_slotUi[slot]!, style: EvochiText.tag.copyWith(fontSize: 12)),
                  ]),
                ),
              ),
            );
          }

          final narrow = b.maxWidth < 370;
          return Stack(children: [
            Positioned(left: b.maxWidth * 0.45 - 30, top: 6, child: const Tag('Preview')),
            if (narrow) ...[
              Positioned(left: 10, bottom: 96, child: slotBox('head')),
              Positioned(left: 10, bottom: 14, child: slotBox('back')),
              Positioned(right: 10, bottom: 50, child: slotBox('neck')),
            ] else ...[
              Positioned(left: b.maxWidth * 0.45 - 150, bottom: 40, child: slotBox('head')),
              Positioned(left: b.maxWidth * 0.45 + 80, bottom: 40, child: slotBox('back')),
              Positioned(left: b.maxWidth * 0.45 + 150, bottom: 40, child: slotBox('neck')),
            ],
          ]);
        }),
        panel: Column(children: [
          Padding(
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
                      selected: cat.$1 == null ? _pouch : (!_pouch && _cat == cat.$1),
                      onTap: () => setState(() {
                        if (cat.$1 == null) {
                          _pouch = true;
                        } else {
                          _pouch = false;
                          _cat = cat.$1!;
                        }
                        _sel = null;
                        _selQ = null;
                      }),
                    ),
                  ),
                ),
            ]),
          ),
          const SizedBox(height: 8),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 6),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: EvochiColor.panel, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFEFD9C0), width: 2)),
            child: Column(children: [
              if (_pouch) ...[
                PouchGrid(selected: _selQ, cols: cols, onSelect: (id) => setState(() => _selQ = id)),
                if (_selQ != null) ...[const SizedBox(height: 8), PouchDetail(id: _selQ!)],
              ] else if (list.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(children: [
                    Opacity(opacity: 0.6, child: VoxelIcon(_cats.firstWhere((x) => x.$1 == _cat).$3, size: 54)),
                    const SizedBox(height: 6),
                    const Text('Nothing in this pocket yet.', style: EvochiText.cardTitle),
                    const SizedBox(height: 10),
                    EvochiButton(label: 'Visit the Market', small: true, expand: false, onPressed: () => TabNav.of(context).go('shop')),
                  ]),
                )
              else
                GridView.count(
                  crossAxisCount: cols,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 0.86,
                  children: [
                    for (final id in list)
                      _ItemTile(
                        id: id,
                        qty: g.ownedQty(c.state, id),
                        selected: id == sel,
                        marked: pet.equipped.values.contains(id) || c.state.placements.values.contains(id),
                        onTap: () {
                          setState(() => _sel = id);
                          if (item(id).category == ItemCategory.wearable) {
                            _scene.react('equip');
                            c.analytics.track('item_previewed', {'item': id});
                          }
                        },
                      ),
                  ],
                ),
              if (!_pouch && sel != null) ...[const SizedBox(height: 8), _Detail(id: sel, scene: _scene)],
            ]),
          ),
        ]),
      ),
    );
  }
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
          child: Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12), bottom: Radius.circular(6)),
              border: Border.all(color: selected ? const Color(0xFFF0B952) : const Color(0xFFE2CDB4), width: 2),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: selected ? const [Color(0xFFFFF4D6), Color(0xFFFFE1A1)] : const [Color(0xFFFBF2E7), Color(0xFFEFE0CD)],
              ),
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              VoxelIcon(icon, size: 24),
              const SizedBox(width: 3),
              Flexible(child: FittedBox(fit: BoxFit.scaleDown, child: Text(label, style: EvochiText.tag.copyWith(color: selected ? EvochiColor.ink : EvochiColor.textSecondary)))),
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
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: selected ? const Color(0xFFF2BE55) : (it.isStory ? const Color(0xFFE8B956) : const Color(0xFFEADAC6)), width: 2),
            color: selected ? const Color(0xFFFFF7E4) : (it.isStory ? const Color(0xFFFFF6DE) : const Color(0xFFFFFBF6)),
          ),
          child: Stack(children: [
            Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Expanded(child: ItemImage(id, size: 62)),
              Text(it.name, textAlign: TextAlign.center, maxLines: 2, style: EvochiText.tag.copyWith(fontSize: 12, color: EvochiColor.ink)),
            ]),
            if (it.category != ItemCategory.wearable)
              Positioned(
                right: 0,
                top: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(color: const Color(0xFF5E4B40), borderRadius: BorderRadius.circular(7)),
                  child: Text('x$qty', style: EvochiText.tag.copyWith(color: Colors.white, fontSize: 11)),
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

class _Detail extends StatelessWidget {
  const _Detail({required this.id, required this.scene});
  final String id;
  final SceneController scene;
  @override
  Widget build(BuildContext context) {
    final c = context.watch<GameController>();
    final it = item(id);
    final pet = c.state.pet!;
    final pv = c.view.pet!;
    List<Widget> acts;
    String tag;
    switch (it.category) {
      case ItemCategory.wearable:
        final eq = pet.equipped[it.slot] == id;
        tag = _slotUi[it.slot] ?? 'Wearable';
        acts = [
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
          const SizedBox(height: 8),
          EvochiButton(
            label: 'Remove',
            small: true,
            tone: ButtonTone.cream,
            icon: const Icon(Icons.delete_outline_rounded, color: EvochiColor.wood, size: 20),
            onPressed: eq ? () => c.run((s, n) => g.unequip(s, it.slot!)) : null,
          ),
        ];
      case ItemCategory.consumable:
        tag = 'Care';
        final cool = it.recovery && pv.recoveryReadyAt > c.now;
        acts = [
          EvochiButton(
            label: 'Use',
            small: true,
            tone: ButtonTone.green,
            onPressed: cool || pv.dead || pv.vitality.vitality >= 100
                ? null
                : () {
                    if (c.run((s, n) => g.useConsumable(s, id, n)).ok) {
                      scene.react('pet');
                      c.toast('+${it.vitality} vitality', icon: 'heart');
                      c.audio.play('reward_chime', volume: 0.6);
                    }
                  },
          ),
          const SizedBox(height: 6),
          Text(pv.vitality.vitality >= 100 ? 'Vitality full' : (cool ? 'Cooling down' : 'Vitality ${pv.vitality.vitality}'), style: EvochiText.caption, textAlign: TextAlign.center),
        ];
      case ItemCategory.decoration:
        tag = 'Decoration';
        final placed = c.state.placements.values.where((x) => x == id).length;
        acts = [
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
          const SizedBox(height: 8),
          EvochiButton(label: 'Arrange', small: true, tone: ButtonTone.cream, onPressed: () => showHabitatSheet(context)),
        ];
    }
    return GameCard(
      padding: const EdgeInsets.all(10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Container(
          width: 76,
          height: 76,
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFF2BE55), width: 2), color: const Color(0xFFFFF9EF)),
          alignment: Alignment.center,
          child: ItemImage(id, size: 66),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(it.name, style: EvochiText.cardTitle),
            const SizedBox(height: 4),
            Wrap(spacing: 4, runSpacing: 4, children: [
              Tag(tag),
              if (it.isStory) const StoryRewardTag(small: true) else Tag(it.rarity[0].toUpperCase() + it.rarity.substring(1), tone: TagTone.ok, icon: 'care'),
            ]),
            const SizedBox(height: 4),
            Text(it.desc, style: EvochiText.caption.copyWith(color: EvochiColor.textSecondary)),
            storySourceLine(id),
          ]),
        ),
        const SizedBox(width: 8),
        SizedBox(width: 112, child: Column(mainAxisSize: MainAxisSize.min, children: acts)),
      ]),
    );
  }
}
