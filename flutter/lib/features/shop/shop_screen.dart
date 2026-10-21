// S10 Shop / Evochi Market (style guide §12, §18; web/src/screens/shop.js). Three experiences instead
// of one cramped screen:
//   BROWSE    a fixed sign, five wood tabs and a search / sort row, then one scrolling stall (the
//             Featured hero offer and two columns of product cards) above the nav (market_catalog.dart)
//   DETAILS   a sheet per item, shaped by its category (market_details.dart)
//   TRY-ON    a full-screen dressing room for wearables and the nest preview for habitat pieces
//             (market_preview.dart)
// The catalog keeps its scroll position through redraws, the sheet, a preview and a trip to another
// tab; a new tab, sort or search starts it at the top. The economy, catalog, prices, ownership and the
// purchase flow are unchanged: one request id per purchase, debounced, x1 / x3 / x5 for seeds and care.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/router.dart';
import '../../app/theme.dart';
import '../../controllers/game_controller.dart';
import '../../core/models/catalog.dart';
import '../../core/utils/ids.dart';
import '../../game/economy/economy.dart' as e;
import '../../game/engine.dart' as g;
import '../caravan/caravan_screen.dart';
import '../home/home_widgets.dart';
import '../nest/sheets.dart';
import '../shared/kit.dart';
import '../shared/scene_view.dart';
import '../shared/widgets.dart';
import 'market_catalog.dart';
import 'market_details.dart';
import 'market_kit.dart';
import 'market_preview.dart';

const _cats = [
  ('featured', 'Featured', 'star'),
  ('wearables', 'Wearables', 'wearables'),
  ('care', 'Care', 'care'),
  ('habitats', 'Habitats', 'habitats'),
  ('garden', 'Garden', 'skill_farming'),
];
const _sorts = [('shop', 'Shop order'), ('low', 'Price: low'), ('high', 'Price: high')];

class ShopScreen extends StatefulWidget {
  const ShopScreen({super.key, required this.active});
  final bool active;
  @override
  State<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends State<ShopScreen> {
  final _scene = SceneController();
  final _q = TextEditingController();
  final _qFocus = FocusNode();
  late ScrollController _scroll = _newScroll(0);
  double _scrollY = 0; // where the catalog was, kept while it's off screen
  String _cat = 'featured';
  String _sort = 'shop';
  String? _view; // null: the catalog | try: the dressing room | nest: the nest preview
  String? _sel;
  bool _showing = true; // the previewed piece on (false: "Show original")
  String _tview = 'left';
  bool _zoom = false;
  int _cheer = 0;
  DateTime? _enterAt;
  DateTime? _backAt;

  GameController get _c => context.read<GameController>();

  @override
  void initState() {
    super.initState();
    _qFocus.addListener(_onFocus);
  }

  @override
  void dispose() {
    _scroll.dispose();
    _qFocus.removeListener(_onFocus);
    _qFocus.dispose();
    _q.dispose();
    super.dispose();
  }

  ScrollController _newScroll(double at) => ScrollController(initialScrollOffset: at)..addListener(_onScroll);

  void _onScroll() {
    if (_scroll.hasClients) _scrollY = _scroll.offset;
  }

  void _onFocus() {
    if (mounted) setState(() {}); // the search field's gold ring
  }

  /// Moving between the catalog and a preview plays a short entrance once, not on every redraw.
  static bool _fresh(DateTime? t) => t != null && DateTime.now().difference(t).inMilliseconds < 450;

  void _toTop() {
    _scrollY = 0;
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  List<String> _list() {
    final q = _q.text.trim().toLowerCase();
    var list = [
      for (final it in catalog.values)
        if (isShopItem(it.id) && (_cat == 'featured' ? it.featured : it.shop == _cat)) it.id,
    ];
    // on the Featured front, the hero offer is already up top
    if (_cat == 'featured' && q.isEmpty) list.remove(marketHeroId);
    if (q.isNotEmpty) {
      list = [
        for (final id in list)
          if (item(id).name.toLowerCase().contains(q) || marketTypeLabel(item(id)).toLowerCase().contains(q)) id,
      ];
    }
    if (_sort != 'shop') {
      // stable: equal prices keep the shop's order
      final order = {for (var i = 0; i < list.length; i++) list[i]: i};
      final dir = _sort == 'low' ? 1 : -1;
      list.sort((a, b) {
        final d = dir * (item(a).price - item(b).price);
        return d != 0 ? d : order[a]! - order[b]!;
      });
    }
    return list;
  }

  // ---------------------------------------------------------------- browsing ----
  void _setCat(String cat) {
    if (_cat == cat) return;
    setState(() {
      _cat = cat;
      _q.clear();
      _toTop();
    });
    _c.audio.play('ui_tap', volume: 0.3);
  }

  void _onQuery(String _) => setState(_toTop);

  void _cycleSort() {
    final i = _sorts.indexWhere((x) => x.$1 == _sort);
    setState(() {
      _sort = _sorts[(i + 1) % _sorts.length].$1;
      _toTop();
    });
    _c.audio.play('ui_tap', volume: 0.3);
  }

  void _clearQuery() {
    _q.clear();
    setState(_toTop);
  }

  void _open(String id) {
    _c.audio.play('ui_tap', volume: 0.4);
    _openDetails(id);
  }

  /// The details sheet; the catalog stays put behind it.
  void _openDetails(String id) {
    _sel = id;
    _qFocus.unfocus();
    _c.analytics.track('item_previewed', {'item': id});
    showEvochiSheet<void>(context, builder: (s) {
      void close() => Navigator.pop(s);
      return MarketDetails(
        id: id,
        onClose: close,
        onTry: () {
          close();
          _enterTry(id);
        },
        onNest: () {
          close();
          _enterNest(id);
        },
        onBuy: () {
          close();
          _buy(id);
        },
        onEarn: () {
          close();
          _earn(id);
        },
        onEquip: () => _equip(id),
        onUnequip: () => _unequip(item(id).slot ?? 'head'),
        onPlace: () => _place(id),
      );
    });
  }

  // ---------------------------------------------------------------- previews ----
  void _enterTry(String id) {
    _qFocus.unfocus();
    setState(() {
      _view = 'try';
      _sel = id;
      _showing = true;
      _tview = 'left';
      _zoom = false;
      _enterAt = DateTime.now();
    });
    _c.audio.play('reward_chime', volume: 0.4);
    _c.analytics.track('item_previewed', {'item': id, 'where': 'dressing_room'});
  }

  void _enterNest(String id) {
    _qFocus.unfocus();
    setState(() {
      _view = 'nest';
      _sel = id;
      _showing = true;
      _enterAt = DateTime.now();
    });
    _c.audio.play('ui_tap', volume: 0.5);
  }

  /// Back to the catalog, on the same shelf ([quiet]: no entrance or sound, e.g. on the way to the Bag).
  void _exitPreview({bool quiet = false}) {
    if (_view == null) return;
    // the shelf left the tree with its scroll position: a fresh controller starts where it was
    final old = _scroll..removeListener(_onScroll);
    _scroll = _newScroll(_scrollY);
    if (old.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
    } else {
      old.dispose();
    }
    setState(() {
      _view = null;
      if (!quiet) _backAt = DateTime.now();
    });
    if (!quiet) _c.audio.play('ui_tap', volume: 0.3);
  }

  void _rotate(int d) {
    final i = marketViews.indexWhere((x) => x.$1 == _tview);
    setState(() => _tview = marketViews[(i + d + marketViews.length) % marketViews.length].$1);
    _c.audio.play('ui_tap', volume: 0.3);
    _c.audio.tick(); // a notch as your Evochi turns
  }

  void _pickView(String v) {
    setState(() => _tview = v);
    _c.audio.play('ui_tap', volume: 0.3);
    _c.audio.tick();
  }

  void _toggle() {
    setState(() => _showing = !_showing);
    _c.audio.play(_showing ? 'reward_chime' : 'ui_tap', volume: 0.35);
  }

  void _toggleZoom() {
    setState(() => _zoom = !_zoom);
    _c.audio.play('ui_tap', volume: 0.3);
  }

  void _petTap() {
    setState(() => _cheer++);
    _c.audio.play('pet_chirp');
  }

  void _nestPetTap() {
    _scene.react('pet');
    _c.audio.play('pet_chirp');
  }

  // ------------------------------------------- actions shared by the sheet and the previews ----
  void _equip(String id) {
    final c = _c;
    final it = item(id);
    if (!c.run((s, n) => g.equip(s, id, n)).ok) return;
    c.audio.play('reward_chime', volume: 0.5);
    c.toast('${it.name} equipped', icon: 'wearables');
    c.analytics.track('accessory_equipped', {'item': id, 'where': 'market'});
    if (_view == 'try' && mounted) setState(() => _cheer++);
  }

  void _unequip(String slot) {
    final c = _c;
    c.run((s, n) => g.unequip(s, slot));
    c.audio.play('ui_tap');
    if (mounted) setState(() => _showing = false);
  }

  void _place(String id) {
    final c = _c;
    final it = item(id);
    final spot = marketNestSpot(c.state, it);
    if (!c.run((s, n) => g.placeDecoration(s, id, spot)).ok) return;
    c.toast('${it.name} placed in the ${(decorSlots[spot]?.label ?? spot).toLowerCase()} spot', icon: 'decorations');
    c.audio.play('ui_tap');
    c.analytics.track('decoration_placed', {'item': id, 'where': 'market'});
  }

  void _viewInBag(String id) {
    final pocket = switch (item(id).category) {
      ItemCategory.wearable => 'wearable',
      ItemCategory.consumable => 'consumable',
      ItemCategory.decoration => 'decoration',
      _ => 'pantry',
    };
    _exitPreview(quiet: true);
    _c.goTab('bag', bag: pocket, bagItem: id);
  }

  /// Not enough EvoCoins: how to earn the rest.
  void _earn(String id) {
    final c = _c;
    final it = item(id);
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
          const SizedBox(height: 8),
          EvochiButton(label: 'Keep browsing', tone: ButtonTone.cream, onPressed: () => Navigator.pop(s)),
        ]));
  }

  Future<void> _buy(String id) async {
    final c = _c;
    final it = item(id);
    final requestId = newId('buy');
    var pending = false;
    var n = 1; // seeds and care: 1, 3 or 5 at a time
    final multi = it.category == ItemCategory.seed || it.category == ItemCategory.consumable;
    await showEvochiDialog<void>(context, builder: (d) => StatefulBuilder(builder: (d, set) {
          return Column(mainAxisSize: MainAxisSize.min, children: [
            ItemImage(id, size: 104),
            Text('Buy ${it.name}?', style: EvochiText.section, textAlign: TextAlign.center),
            const SizedBox(height: 10),
            if (multi) ...[
              QtyPick(price: it.price, balance: c.balance, value: n, onChanged: pending ? (_) {} : (k) => set(() => n = k)),
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
                      final r = qty > 1 ? buyMany(c, id, qty, requestId) : c.run((s, now) => g.purchase(s, id, requestId, now));
                      if (d.mounted) Navigator.pop(d);
                      if (r.ok) {
                        c.analytics.track('item_purchased', {'item': id, 'price': it.price * qty, 'qty': qty});
                        if (mounted) _purchased(id, qty);
                      }
                    },
            ),
            const SizedBox(height: 8),
            EvochiButton(label: 'Cancel', tone: ButtonTone.cream, onPressed: pending ? null : () => Navigator.pop(d)),
          ]);
        }));
  }

  void _purchased(String id, [int n = 1]) {
    final it = item(id);
    final seed = it.category == ItemCategory.seed;
    if (_view == 'try') setState(() => _cheer++);
    _scene.react('reward');
    showEvochiDialog<void>(context, builder: (d) => Column(mainAxisSize: MainAxisSize.min, children: [
          _BuyReveal(id: id),
          Text(n > 1 ? '$n × ${it.name} are yours!' : '${it.name} is yours!', style: EvochiText.section, textAlign: TextAlign.center),
          Text(seed ? "They're in your Bag's Pantry." : 'It has been added to your Bag.', style: EvochiText.bodyText, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          if (seed) ...[
            EvochiButton(
              label: 'Plant now',
              tone: ButtonTone.green,
              onPressed: () {
                Navigator.pop(d);
                openGarden(context);
              },
            ),
            const SizedBox(height: 8),
          ],
          if (it.category == ItemCategory.wearable) ...[
            EvochiButton(
              label: 'Equip Now',
              tone: ButtonTone.green,
              icon: const Icon(Icons.dry_cleaning_rounded, color: EvochiColor.wood, size: 20),
              onPressed: () {
                Navigator.pop(d);
                _equip(id);
                // stay where you were: the dressing room shows it on, the catalog opens its sheet equipped
                if (_view != 'try') _openDetails(id);
              },
            ),
            const SizedBox(height: 8),
          ],
          if (it.category == ItemCategory.decoration) ...[
            EvochiButton(
              label: 'Place in nest',
              tone: ButtonTone.green,
              onPressed: () {
                Navigator.pop(d);
                _place(id);
                if (_view != 'nest') _openDetails(id);
              },
            ),
            const SizedBox(height: 8),
          ],
          EvochiButton(
            label: 'View in Bag',
            tone: ButtonTone.cream,
            onPressed: () {
              Navigator.pop(d);
              _viewInBag(id);
            },
          ),
          const SizedBox(height: 4),
          _GhostButton(label: 'Keep shopping', onTap: () => Navigator.pop(d)),
        ]));
  }

  // ------------------------------------------------------------------- build ----
  @override
  Widget build(BuildContext context) {
    final c = context.watch<GameController>();
    final pet = c.state.pet;
    final rm = MediaQuery.of(context).disableAnimations;
    final sel = _sel == null ? null : catalog[_sel!];
    var view = _view;
    if (pet == null || sel == null || (view == 'try' && sel.category != ItemCategory.wearable) || (view == 'nest' && sel.category != ItemCategory.decoration)) {
      view = null;
    }
    final nest = view == 'nest';
    // browsing and the dressing room: the market stall as a backdrop (the page draws the Evochi); the
    // nest preview: the real meadow with the piece in its spot, unless you're comparing with the original
    final SceneConfig scene;
    if (nest && pet != null && sel != null) {
      final pl = Map<String, String>.of(c.state.placements);
      if (_showing) pl[marketNestSpot(c.state, sel)] = sel.id;
      scene = SceneConfig(
        habitat: 'meadow',
        decor: pl,
        focus: const Offset(0.5, 0.5),
        reducedMotion: rm,
        pet: PetConfig(stage: pet.stage, palette: pet.paletteId, status: c.view.pet!.status, equipped: pet.equipped.values.toList()),
      );
    } else {
      scene = SceneConfig(habitat: 'market', zoom: 1.32, background: const Color(0xFFC9A27A), focus: const Offset(0.3, 0.42), reducedMotion: rm);
    }
    final play = !rm && _fresh(_enterAt);
    final Widget body;
    if (view == 'try') {
      body = MarketDressingRoom(
        id: _sel!,
        view: _tview,
        showing: _showing,
        zoom: _zoom,
        cheer: _cheer,
        play: play,
        onExit: _exitPreview,
        onToggle: _toggle,
        onZoom: _toggleZoom,
        onRotate: _rotate,
        onView: _pickView,
        onPetTap: _petTap,
        onBuy: () => _buy(_sel!),
        onEarn: () => _earn(_sel!),
        onEquip: () => _equip(_sel!),
        onUnequip: () => _unequip(item(_sel!).slot ?? 'head'),
      );
    } else if (view == 'nest') {
      body = MarketNestRoom(
        id: _sel!,
        showing: _showing,
        play: play,
        onExit: _exitPreview,
        onToggle: _toggle,
        onBuy: () => _buy(_sel!),
        onEarn: () => _earn(_sel!),
        onPlace: () => _place(_sel!),
      );
    } else {
      body = _browse(c, rm);
    }
    return PopScope(
      // the system back gesture leaves a preview before it leaves the app
      canPop: !(widget.active && view != null),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _exitPreview();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFC9A27A),
        resizeToAvoidBottomInset: false,
        body: KitPage(
          material: KitMaterial.market,
          paper: false,
          child: Stack(children: [
            Positioned.fill(
              child: KeyedSubtree(
                key: ValueKey(nest ? 'meadow' : 'market'),
                child: HabitatScene(config: scene, controller: _scene, onPetTap: nest ? _nestPetTap : null, petLabel: 'Pet ${pet?.name ?? 'your Evochi'}'),
              ),
            ),
            Positioned.fill(child: body),
          ]),
        ),
      ),
    );
  }

  /// BROWSE: the sign, the tabs and the search row stay put; only the stall's inside scrolls.
  Widget _browse(GameController c, bool rm) {
    final narrow = MediaQuery.of(context).size.width <= 380;
    final cat = _cats.firstWhere((x) => x.$1 == _cat, orElse: () => _cats.first);
    final list = _list();
    final back = !rm && _fresh(_backAt);
    return Semantics(
      container: true,
      label: 'Evochi Market',
      child: Column(children: [
        SafeArea(bottom: false, child: _header(c)),
        const SizedBox(height: 4),
        _tabs(),
        MarketEntrance(kind: MarketEntranceKind.back, play: back, child: _searchRow(cat.$2, narrow)),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(6, 14, 6, 6),
            child: MarketEntrance(
              kind: MarketEntranceKind.back,
              play: back,
              child: Semantics(
                container: true,
                label: cat.$2,
                child: MarketStall(child: LayoutBuilder(builder: (ctx, b) => _catalog(c, list, cat, b.maxWidth, narrow))),
              ),
            ),
          ),
        ),
        SizedBox(height: navInset(context)),
      ]),
    );
  }

  Widget _header(GameController c) => Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 2),
        child: Row(children: [
          Semantics(
            header: true,
            label: 'Evochi Market',
            child: ExcludeSemantics(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Image.asset(art.title('wordmark_evochi'), height: 28, filterQuality: FilterQuality.medium),
                Transform.translate(offset: const Offset(0, -3), child: Image.asset(art.title('title_market'), height: 25, filterQuality: FilterQuality.medium)),
              ]),
            ),
          ),
          const Spacer(),
          // the Starlight Caravan: the premium store, its own wagon beside the coin purse
          Semantics(
            button: true,
            label: 'Starlight Caravan, ${e.glimmerOf(c.state)} Glimmer',
            excludeSemantics: true,
            child: GestureDetector(
              onTap: () => openCaravan(context),
              // a little night-blue door to the premium store
              child: Container(
                height: 36,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF3A4688), Color(0xFF1B2246)]),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFE8BC5C), width: 2),
                  boxShadow: const [BoxShadow(color: Color(0x4D1E0F05), blurRadius: 8, offset: Offset(0, 4))],
                ),
                child: const VoxelIcon('caravan', size: 30),
              ),
            ),
          ),
          const SizedBox(width: 8),
          CoinPill(balance: c.balance, onPlus: () => showCoinsInfo(context)),
        ]),
      );

  /// Five wooden plaques; the chosen one lifts and lights up.
  Widget _tabs() {
    // one label size for the five plaques: the size at which "Wearables" fits
    final group = [for (final x in _cats) x.$2];
    return Padding(
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
                  excludeSemantics: true,
                  child: GestureDetector(
                    onTap: () => _setCat(cat.$1),
                    child: KitTab(
                      selected: _cat == cat.$1,
                      height: 52,
                      padding: const EdgeInsets.fromLTRB(2, 3, 2, 0),
                      radius: const BorderRadius.vertical(top: Radius.circular(11), bottom: Radius.circular(6)),
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        VoxelIcon(cat.$3, size: 24),
                        Flexible(
                          child: KitRowLabel(cat.$2, group: group, style: KitTab.label(EvochiText.tag.copyWith(fontSize: 12), _cat == cat.$1)),
                        ),
                      ]),
                    ),
                  ),
                ),
              ),
            ),
        ]),
      );
  }

  /// "Find an item..." (by name or type, within the tab) and the sort button (shop order, price low,
  /// price high; just the icon on narrow phones).
  Widget _searchRow(String label, bool narrow) {
    final sort = _sorts.firstWhere((x) => x.$1 == _sort).$2;
    final focused = _qFocus.hasFocus;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: Row(children: [
        Expanded(
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: KitDecoration(
              base: BoxDecoration(
                color: const Color(0xFFFBF0D9),
                image: kitGrain,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: KitColor.woodInk, width: 2.5),
                boxShadow: [
                  if (focused) const BoxShadow(color: KitColor.goldRing, spreadRadius: 3),
                  const BoxShadow(color: KitColor.woodShadow, offset: Offset(0, 2)),
                ],
              ),
              inset: 2.5,
              shadow: const BoxShadow(color: Color(0x336E461E), blurRadius: 5, offset: Offset(0, 3)),
            ),
            child: Row(children: [
              const Icon(Icons.search_rounded, size: 22, color: Color(0xFF6B4A34)),
              const SizedBox(width: 6),
              Expanded(
                child: Semantics(
                  label: 'Find an item in $label',
                  textField: true,
                  child: TextField(
                    controller: _q,
                    focusNode: _qFocus,
                    onChanged: _onQuery,
                    textInputAction: TextInputAction.search,
                    autocorrect: false,
                    enableSuggestions: false,
                    cursorColor: KitColor.woodInk,
                    style: const TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w800, fontSize: 15, color: EvochiColor.ink),
                    decoration: const InputDecoration.collapsed(
                      hintText: 'Find an item...',
                      hintStyle: TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w700, fontSize: 15, color: Color(0xFF9C7E62)),
                    ),
                  ),
                ),
              ),
            ]),
          ),
        ),
        const SizedBox(width: 8),
        Semantics(
          button: true,
          label: 'Sort by $sort',
          excludeSemantics: true,
          child: KitPress(
            onTap: _cycleSort,
            builder: (_, down) => AnimatedContainer(
              duration: const Duration(milliseconds: 60),
              height: 44,
              width: narrow ? 44 : null,
              padding: EdgeInsets.symmetric(horizontal: narrow ? 0 : 10),
              transform: Matrix4.translationValues(0, down ? 2 : 0, 0),
              decoration: Kit.wood(radius: 12, border: 2.5, width: 300, y: -1, pressed: down, drop: false),
              child: Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
                const Icon(Icons.swap_vert_rounded, size: 22, color: KitColor.woodInk),
                if (!narrow) ...[
                  const SizedBox(width: 5),
                  Text(sort, style: const TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w900, fontSize: 13, color: KitColor.signInk, shadows: kitSignShadow)),
                ],
              ]),
            ),
          ),
        ),
      ]),
    );
  }

  /// What scrolls: the hero offer (Featured only), the shelf heading and the two-column grid.
  Widget _catalog(GameController c, List<String> list, (String, String, String) cat, double width, bool narrow) {
    final pet = c.state.pet!;
    final q = _q.text.trim();
    final featured = _cat == 'featured';
    final cardW = math.max(0.0, (width - 6 - 9) / 2);
    final artH = (MediaQuery.of(context).size.width * 0.25).clamp(86.0, 116.0).toDouble();
    final img = math.max(24.0, math.min(92.0, math.min((cardW - 18) * 0.72, artH - 8)));
    Widget card(int k) => MarketProductCard(
          id: list[k],
          index: k,
          st: marketItemState(c, list[k]),
          artHeight: artH,
          imageSize: img,
          // the category icon only when the card has room for "Nest side · ● Uncommon" beside it
          showIcon: !narrow && cardW >= 176,
          onTap: () => _open(list[k]),
        );
    return SingleChildScrollView(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(3, 16, 3, 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (featured && q.isEmpty) MarketHeroOffer(pet: pet, id: marketHeroId, st: marketItemState(c, marketHeroId), onTry: () => _enterTry(marketHeroId)),
        MarketShelfHead(title: featured ? (q.isEmpty ? 'More featured items' : 'Featured items') : cat.$2, count: list.length),
        if (list.isEmpty)
          _empty(cat, q)
        else
          for (var i = 0; i < list.length; i += 2)
            Padding(
              padding: EdgeInsets.only(bottom: i + 2 < list.length ? 10 : 0),
              // the two cards of a row share its height, their price tags on one line
              child: IntrinsicHeight(
                child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Expanded(child: card(i)),
                  const SizedBox(width: 9),
                  Expanded(child: i + 1 < list.length ? card(i + 1) : const SizedBox.shrink()),
                ]),
              ),
            ),
        const SizedBox(height: 4),
      ]),
    );
  }

  Widget _empty((String, String, String) cat, String q) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 22),
        child: Column(children: [
          Opacity(opacity: 0.6, child: VoxelIcon(cat.$3, size: 54)),
          const SizedBox(height: 6),
          Text('Nothing called "$q" in ${cat.$2}.', textAlign: TextAlign.center, style: EvochiText.cardTitle),
          const SizedBox(height: 10),
          EvochiButton(label: 'Clear search', small: true, expand: false, tone: ButtonTone.cream, onPressed: _clearQuery),
        ]),
      );
}

/// A plain text button (`.btn.ghost`): "Keep shopping".
class _GhostButton extends StatelessWidget {
  const _GhostButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: SizedBox(
            height: 44,
            child: Center(child: Text(label, style: const TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w800, fontSize: 16, color: EvochiColor.textSecondary))),
          ),
        ),
      );
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
