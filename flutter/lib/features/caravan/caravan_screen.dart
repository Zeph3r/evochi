// The Starlight Caravan: the premium store (docs: Evochi Economy & Monetization Plan, "Premium store").
// A travelling merchant's wagon in night blue and gold, so it never reads as the coin Market. Three
// tabs: Shop (today's deals and the rare finds, bought with Glimmer), Glimmer (packs and the Starter
// Pack, bought with real money through Google Play) and Evochi Plus. The Season Pass has its own screen.
//
// Google Play billing is not switched on yet: until it is, cash offers explain that, and with the
// developer tools on they grant as clearly labelled test purchases (never charged).

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../controllers/game_controller.dart';
import '../../core/models/catalog.dart';
import '../../core/services/haptics.dart';
import '../../core/utils/day_keys.dart';
import '../../core/utils/ids.dart';
import '../../game/economy/economy.dart' as e;
import '../../game/engine.dart' as g;
import '../../game/hatch/hatch.dart' as hatch;
import '../../game/wilds/charms.dart' as ch;
import '../home/home_widgets.dart' show openGarden;
import '../home/nook_sheet.dart' show EggPreviewPainter;
import '../shared/kit.dart';
import '../shared/widgets.dart';
import 'season_screen.dart';

const caravanRoute = '/caravan';

/// Night-blue and gold: the Caravan's own palette.
class Night {
  static const sky = Color(0xFF1B2246);
  static const sky2 = Color(0xFF2B2358);
  static const card = Color(0xFF27305F);
  static const card2 = Color(0xFF323C74);
  static const gold = Color(0xFFE8BC5C);
  static const goldDim = Color(0xFF9C7B3A);
  static const text = Color(0xFFFBEFD5);
  static const soft = Color(0xFFC6C2E8);
  static const glimmer = Color(0xFF8FE3F2);
}

Future<void> openCaravan(BuildContext context, {String tab = 'shop'}) => Navigator.of(context).push(
      MaterialPageRoute<void>(settings: const RouteSettings(name: caravanRoute), builder: (_) => CaravanScreen(tab: tab)),
    );

class CaravanScreen extends StatefulWidget {
  const CaravanScreen({super.key, this.tab = 'shop'});
  final String tab;
  @override
  State<CaravanScreen> createState() => _CaravanScreenState();
}

class _CaravanScreenState extends State<CaravanScreen> {
  late String _tab = widget.tab;

  @override
  void initState() {
    super.initState();
    final c = context.read<GameController>();
    c.analytics.track('store_opened', {'tab': _tab});
    if (!c.state.economy.caravanMet) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _meetMerchant(context).then((_) => c.run((s, n) => e.markCaravanMet(s), quiet: true));
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<GameController>();
    final mq = MediaQuery.of(context);
    return Scaffold(
      backgroundColor: Night.sky,
      body: Stack(children: [
        const Positioned.fill(child: _NightSky()),
        SafeArea(
          bottom: false,
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: Row(children: [
                BackSquareButton(onTap: () => Navigator.of(context).maybePop()),
                const SizedBox(width: 10),
                const VoxelIcon('caravan', size: 40),
                const SizedBox(width: 6),
                Expanded(
                  child: Semantics(
                    header: true,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text('Starlight Caravan', maxLines: 1, style: EvochiText.section.copyWith(color: Night.gold, fontSize: 19)),
                    ),
                  ),
                ),
                GlimmerPill(balance: e.glimmerOf(c.state), onTap: () => setState(() => _tab = 'glimmer')),
              ]),
            ),
            _Tabs(value: _tab, onChanged: (t) => setState(() => _tab = t)),
            Expanded(
              child: ListView(
                padding: EdgeInsets.fromLTRB(14, 10, 14, 24 + mq.padding.bottom),
                children: switch (_tab) {
                  'glimmer' => _glimmerTab(context, c),
                  'plus' => _plusTab(context, c),
                  _ => _shopTab(context, c),
                },
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  // ---- Shop: the season, today's deals, the rare finds
  List<Widget> _shopTab(BuildContext context, GameController c) {
    final stock = e.caravanStock(c.state, c.now);
    final deals = stock.where((o) => o.deal).toList();
    final sv = e.seasonView(c.state, c.now);
    return [
      _SeasonBanner(view: sv, onOpen: () => openSeason(context)),
      const SizedBox(height: 16),
      // eggs for the Hatching Nook: each says exactly what it may become, its price and this week's limit
      const _Head('Eggs for the Hatching Nook', 'Chosen, not chanced: each says what it can hatch into. Two of each a week'),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final t in hatch.caravanEggs) ...[
          Expanded(child: _EggCard(template: t, bought: hatch.boughtThisWeek(c.state, t.id, c.now), onBuy: () => _buyEgg(context, c, t))),
          if (t != hatch.caravanEggs.last) const SizedBox(width: 8),
        ],
      ]),
      const SizedBox(height: 18),
      const _Head('Today\'s deals', 'New every day at midnight'),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final o in deals) ...[
          Expanded(child: _DealCard(offer: o, sold: e.dealBought(c.state, o.id), onBuy: () => _buy(context, c, o))),
          if (o != deals.last) const SizedBox(width: 8),
        ],
      ]),
      const SizedBox(height: 18),
      const _Head('This week\'s charms', 'Worn in the Wilds. They grow stronger as you calm creatures wearing them'),
      for (final o in stock.where((o) => o.section == 'charms')) ...[
        _CharmRow(offer: o, owned: ch.ownsCharm(c.state, o.itemId), onBuy: () => _buy(context, c, o)),
        const SizedBox(height: 8),
      ],
      const SizedBox(height: 10),
      const _Head('Rare finds', 'They drop rarely out there. Five-packs are 10% off'),
      for (final id in e.activeRares) ...[
        _RareRow(
          id: id,
          owned: g.ownedQty(c.state, id),
          one: stock.firstWhere((o) => o.id == 'one:$id'),
          five: stock.firstWhere((o) => o.id == 'five:$id'),
          onBuy: (o) => _buy(context, c, o),
          onInfo: () => showRareInfo(context, id),
        ),
        const SizedBox(height: 8),
      ],
      const SizedBox(height: 6),
      Center(
        child: TextButton.icon(
          onPressed: () => showChestOdds(context),
          icon: const VoxelIcon('chest_gold', size: 22),
          label: Text('Daily chest odds', style: EvochiText.tag.copyWith(color: Night.soft, decoration: TextDecoration.underline)),
        ),
      ),
    ];
  }

  Future<void> _buyEgg(BuildContext context, GameController c, hatch.EggTemplate t) async {
    final short = t.glimmer! - e.glimmerOf(c.state);
    if (short > 0) {
      await showGlimmerShort(context, short);
      return;
    }
    final bought = hatch.boughtThisWeek(c.state, t.id, c.now);
    final ok = await showEvochiDialog<bool>(
      context,
      builder: (d) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Center(child: WoodPlaque(child: Text(t.name, style: WoodPlaque.text(EvochiText.section)))),
        const SizedBox(height: 10),
        SizedBox(height: 96, child: CustomPaint(painter: EggPreviewPainter(t.id))),
        const SizedBox(height: 8),
        Text(t.blurb, textAlign: TextAlign.center, style: EvochiText.bodyText),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: Kit.inset(),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Hatches into: ${t.palettes.map(hatch.paletteLabel).join(' or ')} (decided by the egg)', style: EvochiText.bodyText),
            Text('Needs about ${t.need} steps in a cradle', style: EvochiText.bodyText),
            Text('Price: ${t.glimmer} Glimmer · ${t.weeklyLimit - bought} of ${t.weeklyLimit} left this week', style: EvochiText.bodyText),
            Text('You have ${hatch.stored(c.state).length} egg${hatch.stored(c.state).length == 1 ? '' : 's'} in the collection', style: EvochiText.caption),
          ]),
        ),
        const SizedBox(height: 12),
        EvochiButton(label: 'Choose this egg · ${t.glimmer} Glimmer', onPressed: () => Navigator.pop(d, true)),
        const SizedBox(height: 6),
        EvochiButton(label: 'Not now', tone: ButtonTone.cream, onPressed: () => Navigator.pop(d, false)),
      ]),
    );
    if (ok != true || !context.mounted) return;
    final r = c.run((s, n) => hatch.buyEgg(s, t.id, newId('egg'), n));
    if (r.ok) {
      c.toast('${t.name} is in your egg collection. Set it in a cradle at the nook.', icon: 'star');
      c.audio.buzz(Haptic.purchase);
      c.analytics.track('egg_purchase_verified', {'template': t.id});
    } else if (r.error == 'weekly_limit') {
      c.toast('That is all of those for this week.', kind: 'warn');
    }
  }

  Future<void> _buy(BuildContext context, GameController c, e.CaravanOffer o) async {
    final short = o.price - e.glimmerOf(c.state);
    if (short > 0) {
      await showGlimmerShort(context, short);
      return;
    }
    final ok = await showEvochiDialog<bool>(context, builder: (d) => _ConfirmBuy(offer: o));
    if (ok != true || !context.mounted) return;
    final r = c.run((s, n) => e.buyCaravan(s, o.id, newId('buy'), n));
    if (r.ok) c.toast('+${o.qty} ${item(o.itemId).name}', icon: 'item:${o.itemId}');
  }

  // ---- Glimmer: packs and the Starter Pack (Google Play)
  List<Widget> _glimmerTab(BuildContext context, GameController c) => [
        if (!e.offerOwned(c.state, 'starter_pack')) ...[
          _CashCard(product: e.cashProduct('starter_pack')!, highlight: true, icon: 'starter_pack', onBuy: () => buyCash(context, 'starter_pack')),
          const SizedBox(height: 14),
        ],
        const _Head('Glimmer', '100 Glimmer is about \$1. Bigger packs add a bonus'),
        for (final p in e.cashProducts.where((p) => p.id.startsWith('glimmer_'))) ...[
          _CashCard(product: p, icon: 'glimmer', onBuy: () => buyCash(context, p.id)),
          const SizedBox(height: 8),
        ],
        const SizedBox(height: 8),
        const _BillingNote(),
      ];

  // ---- Evochi Plus
  List<Widget> _plusTab(BuildContext context, GameController c) {
    final p = c.state.economy.plus;
    final active = e.plusActive(c.state, c.now);
    final ready = e.plusDailyReady(c.state, c.now);
    final days = active ? ((p.until - c.now) / dayMs).ceil() : 0;
    return [
      _NightCard(
        highlight: true,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            const VoxelIcon('plus', size: 52),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Evochi Plus', style: EvochiText.section.copyWith(color: Night.gold)),
                Text(
                  active ? 'Member${p.test ? ' (test)' : ''} · $days day${days == 1 ? '' : 's'} left' : '\$4.99 a month or \$39.99 a year',
                  style: EvochiText.caption.copyWith(color: Night.soft),
                ),
              ]),
            ),
          ]),
          if (active) ...[
            const SizedBox(height: 12),
            EvochiButton(
              label: ready ? 'Claim today: +${e.plusDailyGlimmer} Glimmer' : 'Claimed today. Back tomorrow',
              icon: const VoxelIcon('glimmer', size: 24),
              onPressed: ready ? () => c.run((s, n) => e.claimPlusDaily(s, n)) : null,
            ),
          ],
        ]),
      ),
      const SizedBox(height: 14),
      const _Head('What members get', 'Everything you pick from the Wardrobe stays yours'),
      for (final perk in _perks) _Perk(icon: perk.$1, title: perk.$2, text: perk.$3),
      const SizedBox(height: 10),
      _NightCard(
        child: Row(children: [
          const ItemImage('season_firefly_scarf', size: 48),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'The Plus Wardrobe: each month, pick one of three exclusive pieces. Three pieces of a set unlock a matching aura. The first set arrives with the Season 1 art.',
              style: EvochiText.caption.copyWith(color: Night.soft),
            ),
          ),
        ]),
      ),
      const SizedBox(height: 14),
      if (!active) ...[
        EvochiButton(label: 'Join monthly · \$4.99', onPressed: () => buyCash(context, 'plus_monthly')),
        const SizedBox(height: 8),
        EvochiButton(label: 'Join yearly · \$39.99', tone: ButtonTone.cream, onPressed: () => buyCash(context, 'plus_yearly')),
        const SizedBox(height: 10),
      ],
      Text('Renews automatically until cancelled. Cancel any time in Google Play > Payments & subscriptions.',
          textAlign: TextAlign.center, style: EvochiText.tiny.copyWith(color: Night.soft)),
      if (c.devTools) ...[
        const SizedBox(height: 14),
        EvochiButton(
          label: active ? 'Developer tools: end test membership' : 'Developer tools: 30-day test membership',
          tone: ButtonTone.plum,
          small: true,
          onPressed: () => c.run((s, n) => e.setPlusTest(s, !active, n)),
        ),
      ],
    ];
  }
}

const _perks = [
  ('glimmer', '100 Glimmer to start, then 10 every day', 'Claim it here each day you open Evochi. About 400 a month.'),
  ('chest_gold', 'Better daily chests', 'An extra roll at a rare find in every chest, and one free tier-up a week.'),
  ('skill_farming', 'Beds water themselves', 'Every bed is watered the moment you plant it.'),
  ('season', '+75 Season XP a day', 'With each daily claim, so the pass fills sooner.'),
  ('wearables', 'The Plus Wardrobe', 'An exclusive piece every month, yours to keep.'),
];

// ================================================================ shared pieces ====

/// The Glimmer purse: like the coin purse, in night blue.
class GlimmerPill extends StatelessWidget {
  const GlimmerPill({super.key, required this.balance, required this.onTap});
  final int balance;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: '${fmt(balance)} Glimmer',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            height: 36,
            padding: const EdgeInsets.fromLTRB(5, 0, 8, 0),
            decoration: BoxDecoration(
              gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF3A4688), Night.sky]),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Night.gold, width: 2),
              boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 8, offset: Offset(0, 3))],
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const VoxelIcon('glimmer', size: 26),
              const SizedBox(width: 4),
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 28),
                child: Text(fmt(balance), textScaler: TextScaler.noScaling, style: EvochiText.number.copyWith(color: Night.text, fontSize: 15)),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.add_circle_rounded, color: Night.gold, size: 20),
            ]),
          ),
        ),
      );
}

class _Tabs extends StatelessWidget {
  const _Tabs({required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String> onChanged;
  static const tabs = [('shop', 'Shop', 'caravan'), ('glimmer', 'Glimmer', 'glimmer'), ('plus', 'Plus', 'plus')];
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
        child: Row(children: [
          for (final t in tabs)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Semantics(
                  button: true,
                  selected: value == t.$1,
                  label: t.$2,
                  excludeSemantics: true,
                  child: GestureDetector(
                    onTap: () => onChanged(t.$1),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      height: 44,
                      decoration: BoxDecoration(
                        color: value == t.$1 ? Night.card2 : Night.card.withAlpha(140),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: value == t.$1 ? Night.gold : Night.goldDim.withAlpha(128), width: value == t.$1 ? 2 : 1),
                      ),
                      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        VoxelIcon(t.$3, size: 24),
                        const SizedBox(width: 6),
                        Text(t.$2, style: EvochiText.tag.copyWith(color: value == t.$1 ? Night.gold : Night.soft, fontSize: 14)),
                      ]),
                    ),
                  ),
                ),
              ),
            ),
        ]),
      );
}

class _Head extends StatelessWidget {
  const _Head(this.title, this.sub);
  final String title;
  final String sub;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Semantics(header: true, child: Text(title, style: EvochiText.cardTitle.copyWith(color: Night.gold, fontSize: 17))),
          Text(sub, style: EvochiText.caption.copyWith(color: Night.soft)),
        ]),
      );
}

/// An egg on offer: its shell, its name, what it may hatch into, its price, and how many are left.
class _EggCard extends StatelessWidget {
  const _EggCard({required this.template, required this.bought, required this.onBuy});
  final hatch.EggTemplate template;
  final int bought;
  final VoidCallback onBuy;
  @override
  Widget build(BuildContext context) {
    final t = template;
    final left = t.weeklyLimit - bought;
    return _NightCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(height: 84, child: CustomPaint(painter: EggPreviewPainter(t.id))),
        const SizedBox(height: 6),
        Text(t.name, textAlign: TextAlign.center, style: EvochiText.cardTitle.copyWith(color: Night.text)),
        Text('Hatches ${t.palettes.map(hatch.paletteLabel).join(' or ')}', textAlign: TextAlign.center, style: EvochiText.caption.copyWith(color: Night.soft)),
        Text('~${t.need} steps', textAlign: TextAlign.center, style: EvochiText.caption.copyWith(color: Night.soft)),
        const SizedBox(height: 8),
        EvochiButton(
          label: left <= 0 ? 'Next week' : '${t.glimmer} Glimmer',
          small: true,
          tone: left <= 0 ? ButtonTone.cream : ButtonTone.gold,
          semanticLabel: '${t.name}, ${t.glimmer} Glimmer, $left of ${t.weeklyLimit} left this week',
          onPressed: left <= 0 ? null : onBuy,
        ),
        const SizedBox(height: 2),
        Text('$left of ${t.weeklyLimit} this week', textAlign: TextAlign.center, style: EvochiText.tiny.copyWith(color: Night.soft)),
      ]),
    );
  }
}

class _NightCard extends StatelessWidget {
  const _NightCard({required this.child, this.highlight = false, this.padding = const EdgeInsets.all(12)});
  final Widget child;
  final bool highlight;
  final EdgeInsets padding;
  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: highlight ? const [Color(0xFF3D3F86), Night.card] : const [Night.card2, Night.card]),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: highlight ? Night.gold : Night.goldDim.withAlpha(179), width: highlight ? 2 : 1.5),
          boxShadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 10, offset: Offset(0, 4))],
        ),
        child: child,
      );
}

/// A price button: the Glimmer icon and the price.
class _PriceButton extends StatelessWidget {
  const _PriceButton({required this.label, required this.onTap, this.full = 0, this.enabled = true});
  final String label;
  final int full;
  final VoidCallback onTap;
  final bool enabled;
  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        enabled: enabled,
        label: '$label Glimmer',
        excludeSemantics: true,
        child: GestureDetector(
          onTap: enabled ? onTap : null,
          child: Opacity(
            opacity: enabled ? 1 : 0.5,
            child: Container(
              constraints: const BoxConstraints(minHeight: 40, minWidth: 64),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFFFE5A2), Color(0xFFF2B54C)]),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF8A5A1E), width: 2),
                boxShadow: const [BoxShadow(color: Color(0xFF6B4416), offset: Offset(0, 2))],
              ),
              child: Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
                const VoxelIcon('glimmer', size: 20),
                const SizedBox(width: 3),
                Text(label, style: EvochiText.tag.copyWith(color: EvochiColor.ink, fontSize: 14)),
                if (full > 0) ...[
                  const SizedBox(width: 4),
                  Text(fmt(full), style: EvochiText.tiny.copyWith(color: EvochiColor.gold900, decoration: TextDecoration.lineThrough)),
                ],
              ]),
            ),
          ),
        ),
      );
}

class _SeasonBanner extends StatelessWidget {
  const _SeasonBanner({required this.view, required this.onOpen});
  final e.SeasonView view;
  final VoidCallback onOpen;
  @override
  Widget build(BuildContext context) {
    final v = view;
    return GestureDetector(
      onTap: onOpen,
      child: _NightCard(
        highlight: true,
        child: Row(children: [
          const VoxelIcon('season', size: 54),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Season 1: ${v.def.name}', style: EvochiText.cardTitle.copyWith(color: Night.gold)),
              Text(
                v.active ? 'Tier ${v.tier} of ${v.def.tiers} · ${v.daysLeft} days left${v.claimable > 0 ? ' · ${v.claimable} to claim' : ''}' : 'The season has ended',
                style: EvochiText.caption.copyWith(color: Night.soft),
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: v.def.tiers == 0 ? 0 : v.tier / v.def.tiers,
                  minHeight: 8,
                  backgroundColor: const Color(0xFF151A36),
                  valueColor: const AlwaysStoppedAnimation(Night.gold),
                ),
              ),
            ]),
          ),
          const SizedBox(width: 6),
          if (v.claimable > 0) const BadgeDot(),
          const Icon(Icons.chevron_right_rounded, color: Night.gold, size: 30),
        ]),
      ),
    );
  }
}

class _DealCard extends StatelessWidget {
  const _DealCard({required this.offer, required this.sold, required this.onBuy});
  final e.CaravanOffer offer;
  final bool sold;
  final VoidCallback onBuy;
  @override
  Widget build(BuildContext context) {
    final it = item(offer.itemId);
    return _NightCard(
      highlight: offer.off >= 20,
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
      child: Column(children: [
        Align(
          alignment: Alignment.topRight,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(color: offer.off >= 20 ? const Color(0xFFD8573F) : Night.goldDim, borderRadius: BorderRadius.circular(6)),
            child: Text('-${offer.off}%', style: EvochiText.tiny.copyWith(color: Colors.white)),
          ),
        ),
        GestureDetector(onTap: () => showRareInfo(context, offer.itemId), child: ItemImage(offer.itemId, size: 56)),
        const SizedBox(height: 4),
        Text('${offer.qty} × ${it.name}', textAlign: TextAlign.center, maxLines: 2, style: EvochiText.tiny.copyWith(color: Night.text)),
        const SizedBox(height: 6),
        sold
            ? Text('Sold today', style: EvochiText.tiny.copyWith(color: Night.soft))
            : _PriceButton(label: fmt(offer.price), full: offer.full, onTap: onBuy),
      ]),
    );
  }
}

class _RareRow extends StatelessWidget {
  const _RareRow({required this.id, required this.owned, required this.one, required this.five, required this.onBuy, required this.onInfo});
  final String id;
  final int owned;
  final e.CaravanOffer one;
  final e.CaravanOffer five;
  final ValueChanged<e.CaravanOffer> onBuy;
  final VoidCallback onInfo;
  @override
  Widget build(BuildContext context) {
    final it = item(id);
    return _NightCard(
      padding: const EdgeInsets.fromLTRB(8, 8, 10, 8),
      child: Row(children: [
        GestureDetector(onTap: onInfo, child: ItemImage(id, size: 52)),
        const SizedBox(width: 8),
        Expanded(
          child: GestureDetector(
            onTap: onInfo,
            behavior: HitTestBehavior.opaque,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(it.name, style: EvochiText.cardTitle.copyWith(color: Night.text, fontSize: 15)),
              Text(_shortUse[id] ?? '', maxLines: 2, overflow: TextOverflow.ellipsis, style: EvochiText.tiny.copyWith(color: Night.soft, fontWeight: FontWeight.w400)),
              if (owned > 0) Text('You have $owned', style: EvochiText.tiny.copyWith(color: Night.glimmer)),
            ]),
          ),
        ),
        const SizedBox(width: 6),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          _PriceButton(label: fmt(one.price), onTap: () => onBuy(one)),
          const SizedBox(height: 6),
          Row(mainAxisSize: MainAxisSize.min, children: [
            Text('×5 ', style: EvochiText.tiny.copyWith(color: Night.soft)),
            _PriceButton(label: fmt(five.price), onTap: () => onBuy(five)),
          ]),
        ]),
      ]),
    );
  }
}

/// A charm the Caravan has this week: rank I, one each; owned ones say so.
class _CharmRow extends StatelessWidget {
  const _CharmRow({required this.offer, required this.owned, required this.onBuy});
  final e.CaravanOffer offer;
  final bool owned;
  final VoidCallback onBuy;
  @override
  Widget build(BuildContext context) {
    final id = offer.itemId;
    final d = ch.charmDefs[id];
    return _NightCard(
      padding: const EdgeInsets.fromLTRB(8, 8, 10, 8),
      child: Row(children: [
        GestureDetector(onTap: () => showRareInfo(context, id), child: ItemImage(id, size: 52)),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(item(id).name, style: EvochiText.cardTitle.copyWith(color: Night.text, fontSize: 15)),
            Text(d?.short ?? '', maxLines: 2, overflow: TextOverflow.ellipsis, style: EvochiText.tiny.copyWith(color: Night.soft, fontWeight: FontWeight.w400)),
            Text(owned ? 'You have it: wear it from the Bag' : 'Rank I · grows to III as you play',
                style: EvochiText.tiny.copyWith(color: owned ? Night.glimmer : Night.soft)),
          ]),
        ),
        const SizedBox(width: 6),
        owned
            ? Text('Owned', style: EvochiText.tag.copyWith(color: Night.glimmer))
            : _PriceButton(label: fmt(offer.price), onTap: onBuy),
      ]),
    );
  }
}

const _shortUse = {
  'sunstone': 'Ripens a garden bed at once',
  'moonwell_dew': 'Waters every bed, +25% growth each',
  'heartbloom': 'Wakes a fainted Evochi; a second wind in the Wilds',
  'wayfinder_compass': 'Doubles your next trail discovery',
  'golden_acorn': 'Your next daily chest opens a tier better',
  'hollow_ward': 'A three-hit shield for your next Wilds run',
};

class _CashCard extends StatelessWidget {
  const _CashCard({required this.product, required this.icon, required this.onBuy, this.highlight = false});
  final e.CashProduct product;
  final String icon;
  final VoidCallback onBuy;
  final bool highlight;
  @override
  Widget build(BuildContext context) {
    final p = product;
    final contents = [
      if (p.glimmer > 0) '${fmt(p.glimmer)} Glimmer',
      for (final x in p.items.entries) '${x.value} ${item(x.key).name}${x.value > 1 && !item(x.key).name.endsWith('s') ? 's' : ''}',
    ].join(' + ');
    return _NightCard(
      highlight: highlight,
      child: Row(children: [
        ItemImage(icon, size: highlight ? 64 : 48),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(child: Text(p.name, style: EvochiText.cardTitle.copyWith(color: highlight ? Night.gold : Night.text))),
              if (p.note.isNotEmpty) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(color: highlight ? const Color(0xFFD8573F) : Night.goldDim, borderRadius: BorderRadius.circular(6)),
                  child: Text(p.note, style: EvochiText.tiny.copyWith(color: Colors.white)),
                ),
              ],
            ]),
            Text(contents, style: EvochiText.caption.copyWith(color: Night.soft)),
          ]),
        ),
        const SizedBox(width: 8),
        EvochiButton(label: p.price, small: true, expand: false, onPressed: onBuy),
      ]),
    );
  }
}

class _BillingNote extends StatelessWidget {
  const _BillingNote();
  @override
  Widget build(BuildContext context) {
    final c = context.watch<GameController>();
    return Text(
      c.devTools
          ? 'Developer tools are on: buying here makes a free test purchase. Real purchases go through Google Play once billing is switched on.'
          : 'Purchases go through Google Play. Billing opens in an upcoming test build.',
      textAlign: TextAlign.center,
      style: EvochiText.tiny.copyWith(color: Night.soft, fontWeight: FontWeight.w400),
    );
  }
}

class _Perk extends StatelessWidget {
  const _Perk({required this.icon, required this.title, required this.text});
  final String icon;
  final String title;
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          VoxelIcon(icon, size: 32),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: EvochiText.cardTitle.copyWith(color: Night.text, fontSize: 15)),
              Text(text, style: EvochiText.caption.copyWith(color: Night.soft)),
            ]),
          ),
        ]),
      );
}

class _ConfirmBuy extends StatelessWidget {
  const _ConfirmBuy({required this.offer});
  final e.CaravanOffer offer;
  @override
  Widget build(BuildContext context) {
    final c = context.watch<GameController>();
    final it = item(offer.itemId);
    final bal = e.glimmerOf(c.state);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      ItemImage(offer.itemId, size: 84),
      Text('${offer.qty} × ${it.name}', style: EvochiText.section, textAlign: TextAlign.center),
      const SizedBox(height: 4),
      Text(it.desc, style: EvochiText.caption, textAlign: TextAlign.center),
      const SizedBox(height: 10),
      Text('${fmt(offer.price)} Glimmer · you have ${fmt(bal)}', style: EvochiText.cardTitle),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: EvochiButton(label: 'Not now', tone: ButtonTone.cream, onPressed: () => Navigator.pop(context, false))),
        const SizedBox(width: 8),
        Expanded(child: EvochiButton(label: 'Buy', icon: const VoxelIcon('glimmer', size: 22), onPressed: () => Navigator.pop(context, true))),
      ]),
    ]);
  }
}

class _NightSky extends StatelessWidget {
  const _NightSky();
  @override
  Widget build(BuildContext context) => const DecoratedBox(
        decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Night.sky, Night.sky2])),
        child: CustomPaint(painter: _Stars()),
      );
}

class _Stars extends CustomPainter {
  const _Stars();
  @override
  void paint(Canvas canvas, Size size) {
    final r = math.Random(11);
    final p = Paint();
    for (var i = 0; i < 70; i++) {
      final x = r.nextDouble() * size.width, y = r.nextDouble() * size.height * 0.85;
      final a = 0.25 + r.nextDouble() * 0.55;
      p.color = Color.fromRGBO(255, 244, 214, a);
      canvas.drawCircle(Offset(x, y), 0.6 + r.nextDouble() * 1.3, p);
    }
  }

  @override
  bool shouldRepaint(_Stars old) => false;
}

// ================================================================ sheets used elsewhere ====

Future<void> _meetMerchant(BuildContext context) => showEvochiDialog<void>(
      context,
      builder: (d) => Column(mainAxisSize: MainAxisSize.min, children: [
        const VoxelIcon('caravan', size: 88),
        const Text('Wren, the Starlight merchant', style: EvochiText.section, textAlign: TextAlign.center),
        const SizedBox(height: 6),
        const Text(
          '"Evening, traveller! My caravan follows the fireflies from village to village. I trade in rare finds, '
          'paid in Glimmer, a light that\'s hard to come by out there. Have a look around."',
          style: EvochiText.bodyText,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        EvochiButton(label: 'Have a look', onPressed: () => Navigator.pop(d)),
      ]),
    );

/// A rare find's card: what it does, how many you have, where it drops, and its use.
Future<void> showRareInfo(BuildContext context, String id) => showEvochiSheet<void>(
      context,
      builder: (s) {
        final c = context.read<GameController>();
        final it = item(id);
        return Padding(
          padding: const EdgeInsets.all(8),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Center(child: ItemImage(id, size: 96)),
            Text(it.name, style: EvochiText.section, textAlign: TextAlign.center),
            const SizedBox(height: 4),
            Text(it.desc, style: EvochiText.bodyText, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(_dropsText[id] ?? '', style: EvochiText.caption, textAlign: TextAlign.center),
            const SizedBox(height: 4),
            Text('You have ${g.ownedQty(c.state, id)}', style: EvochiText.cardTitle, textAlign: TextAlign.center),
            if (id == 'golden_acorn') TextButton(onPressed: () => showChestOdds(context), child: const Text('Daily chest odds')),
            const SizedBox(height: 10),
            ...rareActions(s, id, close: true),
          ]),
        );
      },
    );

const _dropsText = {
  'sunstone': 'Drops from Wilds creatures (rarely), the guardian, and daily chests.',
  'moonwell_dew': 'Found on trail discoveries and in daily chests.',
  'heartbloom': 'Left by the Wilds guardian, and in daily chests.',
  'wayfinder_compass': 'Found on trail discoveries.',
  'golden_acorn': 'From the Weekly Explorer quest, Wilds creatures and daily chests.',
  'hollow_ward': 'Dropped by Wilds creatures.',
};

/// What you can do with a rare find right now (Bag cards and the info sheet share these).
List<Widget> rareActions(BuildContext context, String id, {bool close = false}) {
  final c = context.watch<GameController>();
  final owned = g.ownedQty(c.state, id);
  void done() {
    if (close) Navigator.of(context).maybePop();
  }

  if (owned < 1 && e.activeRares.contains(id)) {
    return [
      EvochiButton(label: 'Get at the Caravan', small: true, icon: const VoxelIcon('caravan', size: 22), onPressed: () {
        done();
        openCaravan(context);
      }),
    ];
  }
  switch (id) {
    case 'sunstone' || 'moonwell_dew':
      return [
        EvochiButton(label: 'Use in Garden', small: true, tone: ButtonTone.green, onPressed: () {
          done();
          openGarden(context);
        }),
      ];
    case 'heartbloom':
      final dead = c.view.pet?.dead ?? false;
      return [
        EvochiButton(
          label: dead ? 'Wake ${c.state.pet?.name ?? 'your Evochi'}' : 'Use when fainted, or in the Wilds',
          small: true,
          tone: ButtonTone.green,
          onPressed: dead
              ? () {
                  c.run((s, n) => e.reviveWithHeartbloom(s, n));
                  done();
                }
              : null,
        ),
      ];
    case 'prism_scale' || 'starseed':
      // set into its charm
      final charm = id == 'prism_scale' ? 'prism_charm' : 'starseed_charm';
      final has = ch.ownsCharm(c.state, charm);
      final d = ch.charmDefs[charm]!;
      return [
        EvochiButton(
          label: has ? '${d.name} already set' : 'Set into the ${d.name}',
          small: true,
          tone: ButtonTone.green,
          onPressed: has
              ? null
              : () {
                  final r = c.run((s, n) => ch.setCharm(s, charm, n));
                  if (r.ok) {
                    c.audio.play('reward_chime', volume: 0.6);
                    c.toast('${d.name} set. Wear it in the Wilds: ${d.short.toLowerCase()}', icon: 'item:$charm');
                    done();
                  }
                },
        ),
        const SizedBox(height: 4),
        Text('Needs ${d.forge.entries.map((e) => '${e.value} ${catalog[e.key]?.name ?? e.key}').join(' and ')}.', style: EvochiText.caption, textAlign: TextAlign.center),
      ];
    case 'golden_acorn' || 'wayfinder_compass' || 'hollow_ward':
      final armed = e.isArmed(c.state, id);
      return [
        EvochiButton(
          label: armed ? 'Ready and waiting' : 'Get it ready',
          small: true,
          tone: ButtonTone.green,
          onPressed: armed ? null : () => c.run((s, n) => e.armRare(s, id)),
        ),
        const SizedBox(height: 4),
        Text(e.armable[id]!, style: EvochiText.caption, textAlign: TextAlign.center),
      ];
    default:
      return [const EvochiButton(label: 'Arrives with Season 1', small: true, tone: ButtonTone.cream, onPressed: null)];
  }
}

/// Not enough Glimmer: the smallest pack that covers it.
Future<void> showGlimmerShort(BuildContext context, int short) {
  final pack = e.cashProducts.where((p) => p.id.startsWith('glimmer_') && p.glimmer >= short).firstOrNull ?? e.cashProducts.last;
  return showEvochiDialog<void>(
    context,
    builder: (d) => Column(mainAxisSize: MainAxisSize.min, children: [
      const VoxelIcon('glimmer', size: 72),
      Text('You need ${fmt(short)} more Glimmer', style: EvochiText.section, textAlign: TextAlign.center),
      const SizedBox(height: 6),
      Text('${pack.name}: ${fmt(pack.glimmer)} Glimmer for ${pack.price}.', style: EvochiText.bodyText, textAlign: TextAlign.center),
      const SizedBox(height: 4),
      const Text('Glimmer also turns up on the Season Pass, the Weekly Explorer quest and, rarely, in the Wilds.', style: EvochiText.caption, textAlign: TextAlign.center),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: EvochiButton(label: 'Not now', tone: ButtonTone.cream, onPressed: () => Navigator.pop(d))),
        const SizedBox(width: 8),
        Expanded(
          child: EvochiButton(
            label: 'Get ${pack.price}',
            onPressed: () {
              Navigator.pop(d);
              buyCash(context, pack.id);
            },
          ),
        ),
      ]),
    ]),
  );
}

/// A Google Play product. Billing is not live yet: with the developer tools on, a free test purchase.
Future<void> buyCash(BuildContext context, String productId) async {
  final c = context.read<GameController>();
  final p = e.cashProduct(productId)!;
  c.analytics.track('purchase_started', {'product': productId});
  if (!c.devTools) {
    await showEvochiDialog<void>(
      context,
      builder: (d) => Column(mainAxisSize: MainAxisSize.min, children: [
        const VoxelIcon('caravan', size: 72),
        Text(p.name, style: EvochiText.section),
        const SizedBox(height: 6),
        const Text('Purchases open in an upcoming test build, through Google Play. Nothing is charged today.', style: EvochiText.bodyText, textAlign: TextAlign.center),
        const SizedBox(height: 12),
        EvochiButton(label: 'OK', onPressed: () => Navigator.pop(d)),
      ]),
    );
    return;
  }
  final ok = await showEvochiDialog<bool>(
    context,
    builder: (d) => Column(mainAxisSize: MainAxisSize.min, children: [
      const VoxelIcon('glimmer', size: 64),
      Text('Test purchase: ${p.name}', style: EvochiText.section, textAlign: TextAlign.center),
      const SizedBox(height: 6),
      Text('A free test of ${p.price}. Nothing is charged; it is marked as a test in your save.', style: EvochiText.bodyText, textAlign: TextAlign.center),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: EvochiButton(label: 'Cancel', tone: ButtonTone.cream, onPressed: () => Navigator.pop(d, false))),
        const SizedBox(width: 8),
        Expanded(child: EvochiButton(label: 'Test buy', tone: ButtonTone.plum, onPressed: () => Navigator.pop(d, true))),
      ]),
    ]),
  );
  if (ok != true) return;
  final r = c.run((s, n) => e.grantPlayPurchase(s, productId, 'test-${newId('order')}', n));
  if (r.ok) c.toast('${p.name} (test) added', icon: 'glimmer');
}

/// Published daily chest odds (Play policy: a bought Golden Acorn can change a chest).
Future<void> showChestOdds(BuildContext context) => showEvochiSheet<void>(
      context,
      builder: (s) => Padding(
        padding: const EdgeInsets.all(8),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Daily chest odds', style: EvochiText.section, textAlign: TextAlign.center),
          const SizedBox(height: 4),
          const Text(
            'Your chest tier climbs with the goal days you reach this week (1-3 Wooden, 4-5 Silver, 6-7 Gold), '
            'one better when you walk 150% of your goal. A Golden Acorn lifts it one more.',
            style: EvochiText.caption,
            textAlign: TextAlign.center,
          ),
          for (final t in e.chestTiers) ...[
            const SizedBox(height: 10),
            Row(children: [VoxelIcon('chest_$t', size: 28), const SizedBox(width: 6), Text(e.chestNames[t]!, style: EvochiText.cardTitle)]),
            for (final o in e.chestOdds(t))
              Row(children: [
                Expanded(child: Text(o.label, style: EvochiText.caption)),
                Text(o.odds, style: EvochiText.tag),
              ]),
          ],
        ]),
      ),
    );
