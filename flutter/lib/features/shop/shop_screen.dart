// S10 Shop / Evochi Market (style guide §12, §18 "Purchase/preview UX"). The Garden shelf sells Home
// Tales seeds, bought 1, 3 or 5 at a time, with "Plant now" after buying.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/router.dart';
import '../../app/theme.dart';
import '../../controllers/game_controller.dart';
import '../../core/models/catalog.dart';
import '../../core/utils/ids.dart';
import '../../game/engine.dart' as g;
import '../../game/home/home.dart' as h;
import '../home/home_widgets.dart';
import '../nest/sheets.dart';
import '../shared/kit.dart';
import '../shared/scene_scaffold.dart';
import '../shared/scene_view.dart';
import '../shared/widgets.dart';

const _cats = [
  ('featured', 'Featured', 'star'),
  ('wearables', 'Wearables', 'wearables'),
  ('care', 'Care', 'care'),
  ('habitats', 'Habitats', 'habitats'),
  ('garden', 'Garden', 'skill_farming'),
];

List<String> _listFor(String cat) =>
    catalog.values.where((it) => isShopItem(it.id) && (cat == 'featured' ? it.featured : it.shop == cat)).map((it) => it.id).toList();

(String, String) _tagFor(CatalogItem it) => switch (it.category) {
      ItemCategory.wearable => (it.slot == 'neck' ? 'Neck' : (slotLabels[it.slot] ?? 'Wearable'), 'wearables'),
      ItemCategory.consumable => ('Care', 'care'),
      ItemCategory.decoration => ('Habitat', 'habitats'),
      ItemCategory.seed => ('Seed', 'skill_farming'),
      ItemCategory.ingredient => ('Ingredient', 'skill_cooking'),
    };

/// The stall's shelf cards and the featured card (`.prod`, `.shop-feature`).
const _shelf = KitPaper(Color(0xFFFFFAEE), Color(0xFFF5E3C0), Color(0xFFA87542), Color(0xFF7A5230), Color(0x61C49660));

/// A price on a light-wood tag.
Widget _priceTag({required double height, required Widget child, EdgeInsets padding = const EdgeInsets.symmetric(horizontal: 6)}) => Container(
      height: height,
      padding: padding,
      decoration: Kit.wood(radius: 9, border: 2, width: 240, edge: 2, drop: false),
      child: child,
    );

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
    var n = 1; // seeds: 1, 3 or 5 at a time
    final multi = it.category == ItemCategory.seed;
    await showEvochiDialog<void>(context, builder: (d) => StatefulBuilder(builder: (d, set) {
          return Column(mainAxisSize: MainAxisSize.min, children: [
            ItemImage(id, size: 104),
            Text('Buy ${it.name}?', style: EvochiText.section, textAlign: TextAlign.center),
            const SizedBox(height: 10),
            if (multi) ...[
              QtyPick(price: it.price, balance: c.balance, value: n, onChanged: (k) => set(() => n = k)),
              const SizedBox(height: 10),
            ],
            Container(
              padding: const EdgeInsets.all(10),
              decoration: Kit.inset(),
              child: Column(children: [
                Row(children: [const Expanded(child: Text('Price', style: EvochiText.bodyText)), Text('${fmt(it.price * n)} EvoCoins', style: EvochiText.cardTitle)]),
                Row(children: [const Expanded(child: Text('Balance after', style: EvochiText.bodyText)), Text('${fmt(c.balance - it.price * n)} EvoCoins', style: EvochiText.cardTitle)]),
              ]),
            ),
            if (it.category == ItemCategory.wearable)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('Fits all three forms of the lizard family. Owned by your account and kept forever.', textAlign: TextAlign.center, style: EvochiText.caption),
              ),
            const SizedBox(height: 12),
            EvochiButton(
              label: pending ? 'Purchasing...' : 'Purchase${n > 1 ? ' $n' : ''} for ${fmt(it.price * n)}',
              tone: ButtonTone.green,
              onPressed: pending
                  ? null
                  : () async {
                      set(() => pending = true); // one tap only: the request id makes retries idempotent
                      await Future<void>.delayed(const Duration(milliseconds: 300));
                      final qty = n;
                      final r = qty > 1 ? buyMany(c, id, qty, requestId) : c.run((s, t) => g.purchase(s, id, requestId, t));
                      if (d.mounted) Navigator.pop(d);
                      if (r.ok) {
                        c.analytics.track('item_purchased', {'item': id, 'price': it.price * qty, 'qty': qty});
                        _scene.react('reward');
                        if (mounted) _purchased(c, id, qty);
                      }
                    },
            ),
            const SizedBox(height: 8),
            EvochiButton(label: 'Cancel', tone: ButtonTone.cream, onPressed: pending ? null : () => Navigator.pop(d)),
          ]);
        }));
  }

  void _purchased(GameController c, String id, [int n = 1]) {
    final it = item(id);
    final seed = it.category == ItemCategory.seed;
    showEvochiDialog<void>(context, builder: (d) => Column(mainAxisSize: MainAxisSize.min, children: [
          _BuyReveal(id: id),
          Text(n > 1 ? '$n × ${it.name} are yours!' : '${it.name} is yours!', style: EvochiText.section, textAlign: TextAlign.center),
          Text(seed ? "They're in your Bag's Pantry." : "It's waiting in your Bag.", style: EvochiText.bodyText),
          const SizedBox(height: 12),
          if (seed)
            EvochiButton(
              label: 'Plant now',
              tone: ButtonTone.green,
              onPressed: () {
                Navigator.pop(d);
                openGarden(context);
              },
            ),
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
    final seedLevel = h.cropDefs[it.crop]?.level ?? 1;
    final equipped = Map<String, String>.of(pet.equipped);
    if (_tryOn && it.category == ItemCategory.wearable) equipped[it.slot!] = id;
    final reduce = MediaQuery.of(context).disableAnimations;
    final w = MediaQuery.of(context).size.width;
    // a market stall: wooden tabs, a wood-framed lower sheet under a striped awning, shelf cards with
    // prices on light-wood tags
    return Scaffold(
      backgroundColor: const Color(0xFFC9A27A),
      body: KitPage(
        material: KitMaterial.market,
        paper: false,
        child: SceneScaffold(
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
                        // wooden plaques; the chosen one lifts and lights up
                        child: KitTab(
                          selected: _cat == cat.$1,
                          height: w < 400 ? 54 : 46,
                          padding: EdgeInsets.zero,
                          radius: const BorderRadius.vertical(top: Radius.circular(12), bottom: Radius.circular(6)),
                          child: Flex(
                            direction: w < 400 ? Axis.vertical : Axis.horizontal,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              VoxelIcon(cat.$3, size: 22),
                              const SizedBox(width: 3, height: 1),
                              Flexible(child: FittedBox(fit: BoxFit.scaleDown, child: Text(cat.$2, style: KitTab.label(EvochiText.tag.copyWith(fontSize: 12.5), _cat == cat.$1)))),
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
                paper: _shelf,
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
                      alignment: Alignment.center,
                      decoration: Kit.slot(radius: 10),
                      child: ItemImage(id, size: 44),
                    ),
                  ]),
                  if (w >= 360) Text(it.desc, maxLines: 3, overflow: TextOverflow.ellipsis, style: EvochiText.caption.copyWith(color: EvochiColor.textSecondary, fontSize: 12.5)),
                  const SizedBox(height: 6),
                  Wrap(spacing: 4, runSpacing: 4, children: [
                    Tag(
                      switch (it.category) {
                        ItemCategory.wearable => 'Wearable',
                        ItemCategory.consumable => 'Consumable',
                        ItemCategory.seed => 'Farming Lv $seedLevel',
                        _ => 'Decoration',
                      },
                      icon: tgi,
                    ),
                    Tag(tg),
                    Tag(it.rarity[0].toUpperCase() + it.rarity.substring(1), tone: TagTone.ok, icon: 'care'),
                  ]),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    child: _priceTag(
                      height: 36,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Row(children: [
                        const VoxelIcon('coin', size: 28),
                        const SizedBox(width: 8),
                        Text(fmt(it.price), style: WoodPlaque.text(EvochiText.number.copyWith(fontSize: 19))),
                        const Spacer(),
                        if (it.isStackable && own > 0) Text('Owned x$own', style: WoodPlaque.text(EvochiText.caption)),
                      ]),
                    ),
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
        // the stall: a wood-framed sheet with the red and cream awning along its top
        panel: Padding(
          padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
          child: Stack(clipBehavior: Clip.none, fit: StackFit.passthrough, children: [
          FramedWindow(
          border: 13,
          padding: const EdgeInsets.fromLTRB(6, 24, 6, 4),
          sheet: Kit.sheet(colors: const [Color(0xFFFFF6E2), Color(0xFFF1DDB6)]),
          shadow: const BoxShadow(color: Color(0x40321C0A), blurRadius: 14, offset: Offset(0, -4)),
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
                    final tint = _tints[p.category == ItemCategory.consumable ? 1 : (p.category == ItemCategory.seed ? (i.isEven ? 1 : 0) : i % _tints.length)];
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
                        // a shelf card; the chosen one gets a gold ring
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: KitDecoration(
                            base: BoxDecoration(
                              gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [_shelf.top, _shelf.bottom]),
                              image: kitGrain,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: pid == id ? const Color(0xFFC47F1E) : _shelf.edge, width: 2),
                              boxShadow: pid == id
                                  ? const [BoxShadow(color: Color(0x8CFFBE46), blurRadius: 14), BoxShadow(color: Color(0xFF7A5230), offset: Offset(0, 3)), BoxShadow(color: KitColor.goldRing, spreadRadius: 3)]
                                  : const [BoxShadow(color: Color(0x2E3C230C), blurRadius: 10, offset: Offset(0, 6)), BoxShadow(color: Color(0xFF7A5230), offset: Offset(0, 3))],
                            ),
                            inset: 2,
                          ),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Expanded(
                              child: Container(
                                decoration: KitDecoration(
                                  base: BoxDecoration(
                                    borderRadius: BorderRadius.circular(10),
                                    gradient: RadialGradient(colors: tint),
                                    border: Border.all(color: const Color(0x5996693C), width: 2),
                                  ),
                                  inset: 2,
                                  shadow: const BoxShadow(color: Color(0x26643C14), blurRadius: 6, offset: Offset(0, 2)),
                                ),
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
                            _priceTag(
                              height: 28,
                              child: Row(children: [const VoxelIcon('coin', size: 20), const SizedBox(width: 4), Text(fmt(p.price), style: WoodPlaque.text(EvochiText.number.copyWith(fontSize: 15)))]),
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
          // the awning hangs over the frame's top edge
          const Positioned(left: 7, right: 7, top: 3, height: 30, child: ShopAwning()),
          ]),
        ),
      ),
      ),
    );
  }
}

/// The purchase reveal (`.bought` in kit.css): a "Purchased!" banner pops in, the item pops up out of
/// nothing inside slowly turning gold rays, a ring of sparkles bursts out and five coins fall away.
/// Reduced motion: the banner and the item only (no rays, coins or sparkles).
class _BuyReveal extends StatefulWidget {
  const _BuyReveal({required this.id});
  final String id;
  @override
  State<_BuyReveal> createState() => _BuyRevealState();
}

class _BuyRevealState extends State<_BuyReveal> with TickerProviderStateMixin {
  static const _bounce = Cubic(0.2, 1.4, 0.4, 1);
  static const _spring = Cubic(0.2, 1.5, 0.4, 1);
  late final AnimationController _in = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));
  late final AnimationController _spin = AnimationController(vsync: this, duration: const Duration(seconds: 6));
  bool _started = false;
  bool _rm = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _rm = MediaQuery.of(context).disableAnimations;
    if (!_started) {
      _started = true;
      _in.forward();
      if (!_rm) _spin.repeat();
    } else if (_rm && _spin.isAnimating) {
      _spin.stop();
    }
  }

  @override
  void dispose() {
    _in.dispose();
    _spin.dispose();
    super.dispose();
  }

  /// Progress (0..1) of a part that starts [start] s in and lasts [dur] s, at [t] s.
  static double _seg(double t, double start, double dur) => ((t - start) / dur).clamp(0.0, 1.0).toDouble();

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: AnimatedBuilder(
          animation: Listenable.merge([_in, _spin]),
          builder: (ctx, _) {
            final t = _in.value * 1.4; // seconds in
            final b = _seg(t, 0, 0.45);
            final pop = _spring.transform(_seg(t, 0.1, 0.7));
            return Column(mainAxisSize: MainAxisSize.min, children: [
              Opacity(
                opacity: _bounce.transform(b).clamp(0.0, 1.0).toDouble(),
                child: Transform.scale(scale: 0.5 + 0.5 * _bounce.transform(b), child: const GoldBanner('Purchased!')),
              ),
              const SizedBox(height: 4),
              SizedBox(
                width: 150,
                height: 150,
                child: Stack(clipBehavior: Clip.none, children: [
                  if (!_rm) ...[
                    Positioned(left: -30, top: -30, right: -30, bottom: -30, child: CustomPaint(painter: _Rays(turn: _spin.value, fade: _seg(t, 0, 0.4)))),
                    Positioned.fill(child: CustomPaint(painter: _BuySparks(t: t - 0.25))),
                    for (var i = 0; i < 5; i++) _coin(i, t),
                  ],
                  Positioned(
                    left: 15,
                    top: 15,
                    width: 120,
                    height: 120,
                    child: Transform.rotate(
                      angle: -12 * math.pi / 180 * (1 - pop),
                      child: Transform.scale(scale: math.max(0.0, pop), child: ItemImage(widget.id, size: 120)),
                    ),
                  ),
                ]),
              ),
            ]);
          },
        ),
      );

  /// Coin [i] of five, tumbling out from under the item and fading (0.9 s, 0.07 s apart).
  Widget _coin(int i, double t) {
    final u = _seg(t, i * 0.07, 0.9);
    if (u <= 0 || u >= 1) return const SizedBox.shrink();
    final m = Curves.easeOut.transform(u);
    return Positioned(
      left: 75 - 13 + (i - 2) * 34 * m,
      top: 90 - 13 + 90 * m,
      width: 26,
      height: 26,
      child: Transform.rotate(
        angle: math.pi * m,
        child: Transform.scale(
          scale: 1 - 0.4 * m,
          child: Image.asset(art.icon('coin'), opacity: AlwaysStoppedAnimation(1 - m), excludeFromSemantics: true),
        ),
      ),
    );
  }
}

/// Gold rays turning slowly behind a reveal, fading out toward their tips.
class _Rays extends CustomPainter {
  _Rays({required this.turn, required this.fade});
  final double turn; // 0..1, a full turn every 6 s
  final double fade; // fades in over 0.4 s
  @override
  void paint(Canvas canvas, Size size) {
    if (fade <= 0) return;
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    final rect = Rect.fromCircle(center: c, radius: r);
    final path = Path();
    for (var k = 0; k < 15; k++) {
      final a = (k * 24 - 90) * math.pi / 180;
      path
        ..moveTo(c.dx, c.dy)
        ..arcTo(rect, a, 10 * math.pi / 180, false)
        ..close();
    }
    final gold = Color.fromRGBO(255, 214, 110, 0.47 * fade);
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(turn * 2 * math.pi);
    canvas.translate(-c.dx, -c.dy);
    canvas.drawPath(path, Paint()..shader = RadialGradient(colors: [gold, gold, gold.withAlpha(0)], stops: const [0, 0.35, 1]).createShader(rect));
    canvas.restore();
  }

  @override
  bool shouldRepaint(_Rays old) => old.turn != turn || old.fade != fade;
}

/// Ten sparkles bursting out of the reveal's centre ([t] s in, 0.9 s).
class _BuySparks extends CustomPainter {
  _BuySparks({required this.t});
  final double t;
  @override
  void paint(Canvas canvas, Size size) {
    final u = t / 0.9;
    if (u <= 0 || u >= 1) return;
    final m = Curves.easeOut.transform(u);
    final c = size.center(Offset.zero);
    final paint = Paint()..color = const Color(0xFFFFE5A2).withAlpha((255 * (1 - m)).round());
    for (var i = 0; i < 10; i++) {
      final a = i * 36 * math.pi / 180;
      final d = (78 + (i % 3) * 20) * m;
      canvas.drawPath(kitStarPath(c + Offset(math.sin(a) * d, -math.cos(a) * d), 8 * (0.6 + 0.6 * m)), paint);
    }
  }

  @override
  bool shouldRepaint(_BuySparks old) => old.t != t;
}
