// S10 Shop / Evochi Market (style guide §12, §18 "Purchase/preview UX").

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/router.dart';
import '../../app/theme.dart';
import '../../controllers/game_controller.dart';
import '../../core/models/catalog.dart';
import '../../core/utils/ids.dart';
import '../../game/engine.dart' as g;
import '../nest/sheets.dart';
import '../shared/scene_scaffold.dart';
import '../shared/scene_view.dart';
import '../shared/widgets.dart';

const _cats = [('featured', 'Featured', 'star'), ('wearables', 'Wearables', 'wearables'), ('care', 'Care', 'care'), ('habitats', 'Habitats', 'habitats')];

List<String> _listFor(String cat) =>
    catalog.values.where((it) => isShopItem(it.id) && (cat == 'featured' ? it.featured : it.shop == cat)).map((it) => it.id).toList();

(String, String) _tagFor(CatalogItem it) => switch (it.category) {
      ItemCategory.wearable => (it.slot == 'neck' ? 'Neck' : (slotLabels[it.slot] ?? 'Wearable'), 'wearables'),
      ItemCategory.consumable => ('Care', 'care'),
      ItemCategory.decoration => ('Habitat', 'habitats'),
    };

const _tints = [
  [Color(0xFFFFF5D9), Color(0xFFF8E2B0)],
  [Color(0xFFEFF8E2), Color(0xFFD5EBBC)],
  [Color(0xFFEAF5FC), Color(0xFFCFE6F6)],
];

class ShopScreen extends StatefulWidget {
  const ShopScreen({super.key, required this.active});
  final bool active;
  @override
  State<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends State<ShopScreen> {
  final _scene = SceneController();
  String _cat = 'featured';
  String? _sel;
  bool _tryOn = false;

  Future<void> _buy(GameController c, String id) async {
    final it = item(id);
    final requestId = newId('buy');
    var pending = false;
    await showEvochiDialog<void>(context, builder: (d) => StatefulBuilder(builder: (d, set) {
          return Column(mainAxisSize: MainAxisSize.min, children: [
            ItemImage(id, size: 104),
            Text('Buy ${it.name}?', style: EvochiText.section, textAlign: TextAlign.center),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: const Color(0xFFFBF1E4), borderRadius: BorderRadius.circular(12)),
              child: Column(children: [
                Row(children: [const Expanded(child: Text('Price', style: EvochiText.bodyText)), Text('${fmt(it.price)} EvoCoins', style: EvochiText.cardTitle)]),
                Row(children: [const Expanded(child: Text('Balance after', style: EvochiText.bodyText)), Text('${fmt(c.balance - it.price)} EvoCoins', style: EvochiText.cardTitle)]),
              ]),
            ),
            if (it.category == ItemCategory.wearable)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('Fits all three forms of the lizard family. Owned by your account and kept forever.', textAlign: TextAlign.center, style: EvochiText.caption),
              ),
            const SizedBox(height: 12),
            EvochiButton(
              label: pending ? 'Purchasing...' : 'Purchase for ${fmt(it.price)}',
              tone: ButtonTone.green,
              onPressed: pending
                  ? null
                  : () async {
                      set(() => pending = true); // one tap only: the request id makes retries idempotent
                      await Future<void>.delayed(const Duration(milliseconds: 300));
                      final r = c.run((s, n) => g.purchase(s, id, requestId, n));
                      if (d.mounted) Navigator.pop(d);
                      if (r.ok) {
                        c.analytics.track('item_purchased', {'item': id, 'price': it.price});
                        _scene.react('reward');
                        if (mounted) _purchased(c, id);
                      }
                    },
            ),
            const SizedBox(height: 8),
            EvochiButton(label: 'Cancel', tone: ButtonTone.cream, onPressed: pending ? null : () => Navigator.pop(d)),
          ]);
        }));
  }

  void _purchased(GameController c, String id) {
    final it = item(id);
    showEvochiDialog<void>(context, builder: (d) => Column(mainAxisSize: MainAxisSize.min, children: [
          ItemImage(id, size: 110),
          Text('${it.name} is yours!', style: EvochiText.section, textAlign: TextAlign.center),
          const Text("It's waiting in your Bag.", style: EvochiText.bodyText),
          const SizedBox(height: 12),
          if (it.category == ItemCategory.wearable)
            EvochiButton(
              label: 'Equip now',
              icon: const Icon(Icons.checkroom_rounded, color: EvochiColor.wood),
              onPressed: () {
                Navigator.pop(d);
                if (c.run((s, n) => g.equip(s, id, n)).ok) {
                  c.toast('${it.name} equipped', icon: 'wearables');
                  setState(() => _tryOn = false);
                  TabNav.of(context).go('bag');
                }
              },
            ),
          if (it.category == ItemCategory.decoration)
            EvochiButton(
              label: 'Place in nest',
              onPressed: () {
                Navigator.pop(d);
                showHabitatSheet(context);
              },
            ),
          const SizedBox(height: 8),
          EvochiButton(label: 'Keep shopping', tone: ButtonTone.cream, onPressed: () => Navigator.pop(d)),
        ]));
  }

  void _earn(GameController c, CatalogItem it) {
    showEvochiSheet<void>(context, builder: (s) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Row(children: [VoxelIcon('coin', size: 40), SizedBox(width: 8), Text('Almost there!', style: EvochiText.section)]),
          const SizedBox(height: 8),
          Text(
            '${it.name} costs ${fmt(it.price)} EvoCoins and you have ${fmt(c.balance)}. Complete today\'s quests on your Journey to earn the rest.',
            style: EvochiText.bodyText,
          ),
          const SizedBox(height: 12),
          EvochiButton(
            label: 'Open Journey',
            onPressed: () {
              Navigator.pop(s);
              TabNav.of(context).go('journey');
            },
          ),
        ]));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<GameController>();
    final pet = c.state.pet!;
    final list = _listFor(_cat);
    if (_sel == null || !list.contains(_sel)) _sel = _cat == 'featured' ? 'golden_crest_crown' : list.first;
    final id = _sel!;
    final it = item(id);
    final own = g.ownedQty(c.state, id);
    final owned = own > 0 && !it.isStackable;
    final afford = c.balance >= it.price;
    final (tg, tgi) = _tagFor(it);
    final equipped = Map<String, String>.of(pet.equipped);
    if (_tryOn && it.category == ItemCategory.wearable) equipped[it.slot!] = id;
    final reduce = MediaQuery.of(context).disableAnimations;
    final w = MediaQuery.of(context).size.width;
    return Scaffold(
      backgroundColor: const Color(0xFFC9A27A),
      body: SceneScaffold(
        controller: _scene,
        onPetTap: () => _scene.react('pet'),
        petLabel: pet.name,
        minHero: 230,
        bottomInset: navInset(context),
        headerAllowance: 130,
        groundOffset: 6,
        config: (gy) => SceneConfig(
          habitat: 'market',
          zoom: 1.32,
          background: const Color(0xFFC9A27A),
          focus: Offset(0.26, gy),
          reducedMotion: reduce,
          pet: PetConfig(stage: pet.stage, palette: pet.paletteId, status: c.view.pet!.status, equipped: equipped.values.toList(), scale: pet.stage == 3 ? 0.85 : 1),
        ),
        header: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Semantics(
                header: true,
                label: 'Evochi Market',
                child: ExcludeSemantics(
                  child: Column(children: [Image.asset(art.title('wordmark_evochi'), height: 34), Image.asset(art.title('title_market'), height: 28)]),
                ),
              ),
              const Spacer(),
              CoinPill(balance: c.balance, onPlus: () => showCoinsInfo(context)),
            ]),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(children: [
              for (final cat in _cats)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: Semantics(
                      selected: _cat == cat.$1,
                      button: true,
                      label: cat.$2,
                      child: GestureDetector(
                        onTap: () => setState(() {
                          _cat = cat.$1;
                          _sel = null;
                          _tryOn = false;
                        }),
                        child: Container(
                          height: w < 400 ? 54 : 46,
                          decoration: BoxDecoration(
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(12), bottom: Radius.circular(6)),
                            border: Border.all(color: _cat == cat.$1 ? const Color(0xFFF0B952) : const Color(0xFFE2CDB4), width: 2),
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: _cat == cat.$1 ? const [Color(0xFFFFF4D6), Color(0xFFFFE1A1)] : const [Color(0xFFFBF2E7), Color(0xFFEFE0CD)],
                            ),
                          ),
                          child: Flex(
                            direction: w < 400 ? Axis.vertical : Axis.horizontal,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              VoxelIcon(cat.$3, size: 22),
                              const SizedBox(width: 3, height: 1),
                              Flexible(child: FittedBox(fit: BoxFit.scaleDown, child: Text(cat.$2, style: EvochiText.tag.copyWith(fontSize: 12.5)))),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ]),
          ),
        ]),
        hero: Align(
          alignment: Alignment.bottomRight,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(0, 10, 8, 12),
            child: SizedBox(
              width: w * (w < 360 ? 0.62 : 0.56),
              child: GameCard(
                padding: const EdgeInsets.fromLTRB(10, 9, 10, 10),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Tag(_cat == 'featured' ? 'FEATURED' : tg.toUpperCase(), tone: TagTone.red),
                        const SizedBox(height: 4),
                        Text(it.name, style: EvochiText.section.copyWith(fontSize: 19, fontWeight: FontWeight.w900)),
                      ]),
                    ),
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(color: const Color(0xFFFFF6E8), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFECD9C1))),
                      child: ItemImage(id, size: 46),
                    ),
                  ]),
                  if (w >= 360) Text(it.desc, maxLines: 3, overflow: TextOverflow.ellipsis, style: EvochiText.caption.copyWith(color: EvochiColor.textSecondary, fontSize: 12.5)),
                  const SizedBox(height: 6),
                  Wrap(spacing: 4, runSpacing: 4, children: [
                    Tag(it.category == ItemCategory.wearable ? 'Wearable' : (it.category == ItemCategory.consumable ? 'Consumable' : 'Decoration'), icon: tgi),
                    Tag(tg),
                    Tag(it.rarity[0].toUpperCase() + it.rarity.substring(1), tone: TagTone.ok, icon: 'care'),
                  ]),
                  Container(
                    margin: const EdgeInsets.symmetric(vertical: 7),
                    height: 36,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(color: const Color(0xFFF1E4D4), borderRadius: BorderRadius.circular(10)),
                    child: Row(children: [
                      const VoxelIcon('coin', size: 28),
                      const SizedBox(width: 8),
                      Text(fmt(it.price), style: EvochiText.number.copyWith(fontSize: 19)),
                      const Spacer(),
                      if (it.isStackable && own > 0) Text('Owned x$own', style: EvochiText.caption),
                    ]),
                  ),
                  Row(children: [
                    if (it.category == ItemCategory.wearable) ...[
                      Expanded(
                        child: EvochiButton(
                          label: _tryOn ? 'Take off' : 'Try On',
                          small: true,
                          tone: ButtonTone.cream,
                          onPressed: () {
                            setState(() => _tryOn = !_tryOn);
                            if (_tryOn) {
                              _scene.react('equip');
                              c.audio.play('reward_chime', volume: 0.4);
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: owned
                          ? EvochiButton(label: 'Owned', small: true, tone: ButtonTone.green, onPressed: () => TabNav.of(context).go('bag'))
                          : EvochiButton(
                              label: 'Purchase',
                              small: true,
                              tone: afford ? ButtonTone.green : ButtonTone.cream,
                              icon: const VoxelIcon('coin', size: 20),
                              semanticLabel: afford ? 'Purchase ${it.name}' : 'Purchase - you need ${fmt(it.price - c.balance)} more EvoCoins',
                              onPressed: () => afford ? _buy(c, id) : _earn(c, it),
                            ),
                    ),
                  ]),
                ]),
              ),
            ),
          ),
        ),
        panel: Container(
          margin: const EdgeInsets.symmetric(horizontal: 8),
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
          decoration: BoxDecoration(color: EvochiColor.panel, borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0xFFEFD9C0), width: 2)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              const Icon(Icons.grid_view_rounded, color: Color(0xFF4A3A32), size: 20),
              const SizedBox(width: 6),
              Text(_cat == 'featured' ? 'Featured Items' : _cats.firstWhere((x) => x.$1 == _cat).$2, style: EvochiText.cardTitle),
              const Spacer(),
              if (_cat == 'featured')
                TextButton(onPressed: () => setState(() => _cat = 'wearables'), child: const Text('See All ›', style: EvochiText.tag)),
            ]),
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 0.66,
              children: [
                for (var i = 0; i < list.length; i++)
                  Builder(builder: (_) {
                    final pid = list[i];
                    final p = item(pid);
                    final (ptg, ptgi) = _tagFor(p);
                    final pown = g.ownedQty(c.state, pid) > 0 && !p.isStackable;
                    final tint = _tints[p.category == ItemCategory.consumable ? 1 : i % _tints.length];
                    return Semantics(
                      selected: pid == id,
                      button: true,
                      label: '${p.name}, ${p.price} EvoCoins${pown ? ', owned' : ''}',
                      child: GestureDetector(
                        onTap: () {
                          setState(() {
                            _sel = pid;
                            _tryOn = false;
                          });
                          c.analytics.track('item_previewed', {'item': pid});
                        },
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFFBF5),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: pid == id ? const Color(0xFFF2BE55) : const Color(0xFFEADAC6), width: 2),
                          ),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Expanded(
                              child: Container(
                                decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), gradient: RadialGradient(colors: tint)),
                                alignment: Alignment.center,
                                child: Stack(children: [
                                  Center(child: ItemImage(pid, size: 62)),
                                  if (pown) const Positioned(left: 2, top: 2, child: Tag('Owned', tone: TagTone.ok)),
                                ]),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(p.name, maxLines: 2, style: EvochiText.cardTitle.copyWith(fontSize: 13.5, height: 1.1)),
                            const SizedBox(height: 2),
                            Tag(ptg, icon: ptgi),
                            const SizedBox(height: 4),
                            Container(
                              height: 28,
                              padding: const EdgeInsets.symmetric(horizontal: 6),
                              decoration: BoxDecoration(color: const Color(0xFFF3E8DA), borderRadius: BorderRadius.circular(8)),
                              child: Row(children: [const VoxelIcon('coin', size: 20), const SizedBox(width: 4), Text(fmt(p.price), style: EvochiText.number.copyWith(fontSize: 15))]),
                            ),
                          ]),
                        ),
                      ),
                    );
                  }),
              ],
            ),
          ]),
        ),
      ),
    );
  }
}
