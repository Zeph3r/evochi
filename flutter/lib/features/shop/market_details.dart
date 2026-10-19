// The Market's details sheet (web shop.js `detailBody`, kit.css `.pd-*`): an item's picture, name, type
// and rarity, its description, then a section shaped by its category (a wearable on your Evochi from
// three sides, what a care item does, where a habitat piece goes, how a seed grows), what you already
// have, the price and one row of actions.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../controllers/game_controller.dart';
import '../../core/models/catalog.dart';
import '../../core/models/game_state.dart';
import '../../game/home/home.dart' as h;
import '../shared/kit.dart';
import '../shared/widgets.dart';
import 'market_kit.dart';

class MarketDetails extends StatelessWidget {
  const MarketDetails({
    super.key,
    required this.id,
    required this.onClose,
    required this.onTry,
    required this.onNest,
    required this.onBuy,
    required this.onEarn,
    required this.onEquip,
    required this.onUnequip,
    required this.onPlace,
  });
  final String id;
  final VoidCallback onClose;
  final VoidCallback onTry; // the dressing room
  final VoidCallback onNest; // the nest preview
  final VoidCallback onBuy;
  final VoidCallback onEarn; // "not enough EvoCoins"
  final VoidCallback onEquip;
  final VoidCallback onUnequip;
  final VoidCallback onPlace;

  static const _h3 = TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w900, fontSize: 14, color: Color(0xFF4A2D45));
  static const _small = TextStyle(fontFamily: EvochiText.body, fontWeight: FontWeight.w400, fontSize: 13, height: 1.38, color: EvochiColor.textSecondary);

  @override
  Widget build(BuildContext context) {
    final c = context.watch<GameController>();
    final pet = c.state.pet!;
    final it = item(id);
    final st = marketItemState(c, id);

    // one primary per state, never a price on something you own
    final alone = it.category != ItemCategory.wearable;
    final Widget buyBtn = st.afford
        ? EvochiButton(
            label: alone ? 'Purchase · ${fmt(it.price)}' : 'Purchase',
            tone: ButtonTone.green,
            icon: const VoxelIcon('coin', size: 22),
            semanticLabel: 'Purchase ${it.name} for ${fmt(it.price)} EvoCoins',
            onPressed: onBuy,
          )
        : EvochiButton(
            label: 'Need ${fmt(st.short)} more',
            tone: ButtonTone.cream,
            icon: const MarketDimCoin(size: 22),
            semanticLabel: 'You need ${fmt(st.short)} more EvoCoins',
            onPressed: onEarn,
          );
    const hanger = Icon(Icons.checkroom_rounded, color: EvochiColor.wood, size: 20);
    Widget? stateLine;
    final acts = <Widget>[];
    var column = false;
    switch (it.category) {
      case ItemCategory.wearable:
        if (st.equipped) {
          stateLine = const _StateLine('Currently equipped', equipped: true);
          acts.addAll([
            EvochiButton(label: 'Take off', tone: ButtonTone.danger, semanticLabel: 'Take off the ${it.name}', onPressed: onUnequip),
            EvochiButton(label: 'Dressing room', tone: ButtonTone.cream, icon: hanger, onPressed: onTry),
          ]);
        } else if (st.owned) {
          stateLine = const _StateLine('Owned · in your Bag');
          acts.addAll([
            EvochiButton(label: 'Try On', tone: ButtonTone.cream, icon: hanger, onPressed: onTry),
            EvochiButton(label: 'Equip', icon: const Icon(Icons.dry_cleaning_rounded, color: EvochiColor.wood, size: 20), onPressed: onEquip),
          ]);
        } else {
          acts.addAll([EvochiButton(label: 'Try On', tone: ButtonTone.cream, icon: hanger, onPressed: onTry), buyBtn]);
        }
      case ItemCategory.decoration:
        column = true;
        if (st.placed) {
          stateLine = const _StateLine('In your nest', equipped: true);
        } else if (st.owned) {
          stateLine = const _StateLine('Owned · in your Bag');
        }
        acts.add(EvochiButton(label: 'Preview in Nest', tone: ButtonTone.cream, icon: const VoxelIcon('habitats', size: 24), onPressed: onNest));
        if (st.owned && !st.stack) {
          if (!st.placed) acts.add(EvochiButton(label: 'Place', onPressed: onPlace));
        } else {
          acts.add(buyBtn);
        }
      default:
        if (st.qty > 0) stateLine = _StateLine('You have ${st.qty}');
        acts.add(buyBtn);
    }

    final tint = marketTint(it, 0);
    return Semantics(
      container: true,
      label: it.name,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        // the head: picture, name, type and rarity, close
        Stack(clipBehavior: Clip.none, children: [
          Padding(
            padding: const EdgeInsets.only(right: 44),
            child: Row(children: [
              Container(
                width: 72,
                height: 72,
                alignment: Alignment.center,
                decoration: KitDecoration(
                  base: BoxDecoration(
                    gradient: RadialGradient(center: const Alignment(0, -0.2), radius: 0.8, colors: tint),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0x6696693C), width: 2),
                  ),
                  inset: 2,
                  shadow: const BoxShadow(color: Color(0x26643C14), blurRadius: 6, offset: Offset(0, 2)),
                ),
                child: ItemImage(id, size: 62),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Semantics(header: true, child: Text(it.name, style: EvochiText.section.copyWith(fontSize: 20, height: 23 / 20))),
                  const SizedBox(height: 5),
                  Wrap(spacing: 5, runSpacing: 5, children: [Tag(marketTypeLabel(it), icon: marketCatIcon(it)), MarketRarityTag(it.rarity)]),
                ]),
              ),
            ]),
          ),
          Positioned(top: -5, right: -5, child: _CloseButton(onTap: onClose)),
        ]),
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Text(it.desc, style: EvochiText.bodyText.copyWith(fontSize: 14.5, height: 20 / 14.5, color: EvochiColor.textSecondary)),
        ),
        ..._extra(context, pet, it, st),
        if (stateLine != null) stateLine,
        if (!st.owned || st.stack)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Row(children: [
              const VoxelIcon('coin', size: 26),
              const SizedBox(width: 6),
              Text(fmt(it.price), style: const TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w900, fontSize: 22, color: EvochiColor.ink)),
              const Spacer(),
              Text('You have ${fmt(c.balance)}', style: EvochiText.tiny.copyWith(fontSize: 12.5)),
            ]),
          ),
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: column
              ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  for (var i = 0; i < acts.length; i++) ...[if (i > 0) const SizedBox(height: 8), acts[i]],
                ])
              : Row(children: [
                  for (var i = 0; i < acts.length; i++) ...[if (i > 0) const SizedBox(width: 8), Expanded(child: acts[i])],
                ]),
        ),
      ]),
    );
  }

  /// A pressed-in section (`.pd-sec`) with its heading.
  Widget _sec(String title, List<Widget> children) => Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 9, 10, 10),
          decoration: Kit.inset(radius: 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Semantics(header: true, child: Text(title, style: _h3)),
            const SizedBox(height: 7),
            ...children,
          ]),
        ),
      );

  List<Widget> _extra(BuildContext context, Pet pet, CatalogItem it, MarketItemState st) {
    final rm = MediaQuery.of(context).disableAnimations;
    switch (it.category) {
      case ItemCategory.wearable:
        // the three views of the dressing room; tap to open it
        final ov = marketOverlays(pet, id, true);
        return [
          _sec('On ${pet.name}', [
            Semantics(
              button: true,
              label: 'Open the dressing room',
              excludeSemantics: true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onTry,
                child: Row(children: [
                  for (var i = 0; i < marketViews.length; i++) ...[
                    if (i > 0) const SizedBox(width: 6),
                    Expanded(child: _ViewPreview(pet: pet, overlays: ov, view: marketViews[i].$1)),
                  ],
                ]),
              ),
            ),
            const SizedBox(height: 4),
            const Text('Fits all three forms of the lizard family. Tap to try it on.', style: EvochiText.tiny),
          ]),
        ];
      case ItemCategory.consumable:
        final aspect = marketPetAspect(pet.stage, 'left');
        return [
          _sec('What it does', [
            Wrap(spacing: 6, runSpacing: 6, children: [
              if (it.vitality > 0) Tag('+${it.vitality} Vitality', tone: TagTone.ok, icon: 'heart'),
              if (it.recovery) const Tag('12h cooldown'),
              if (it.treat) const Tag('Treat: Bond +1', tone: TagTone.stage),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              SizedBox(
                width: 72 * aspect,
                height: 72,
                child: Stack(clipBehavior: Clip.none, children: [
                  Positioned.fill(child: ExcludeSemantics(child: MarketPet(pet: pet, overlays: marketOverlays(pet, null, false), expr: 'excited', res: 200))),
                  if (!rm) const Positioned(left: 22, top: -8, width: 40, height: 40, child: _HeartsPop()),
                ]),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text('${pet.name} loves a ${it.name.toLowerCase()}. ${st.qty > 0 ? 'You have ${st.qty}.' : 'Use it from your Bag.'}', style: _small),
              ),
            ]),
          ]),
        ];
      case ItemCategory.decoration:
        return [
          _sec('Where it goes', [
            Text(it.decor == 'nest' ? 'Replaces the nest your Evochi sleeps in.' : 'Sits beside the nest, on the left, right or back spot.', style: _small),
          ]),
        ];
      case ItemCategory.seed:
        final crop = h.cropDefs[it.crop];
        if (crop == null) return const [];
        final uses = [
          for (final r in h.recipeOrder)
            if (h.recipeDefs[r]!.needs.keys.any(crop.yieldItems.containsKey)) item(h.recipeDefs[r]!.makes).name,
        ];
        final m = crop.growMin;
        final time = m >= 60 ? '${m ~/ 60} h${m % 60 > 0 ? ' ${m % 60} min' : ''}' : '$m min';
        final harvest = crop.yieldItems.entries.map((e) => '${e.value} × ${item(e.key).name}').join(', ');
        Widget crops(String stage) => Image.asset(art.home.crop(crop.id, stage), width: 48, height: 48, fit: BoxFit.contain, excludeFromSemantics: true, filterQuality: FilterQuality.medium);
        return [
          _sec('How it grows', [
            Semantics(
              label: 'Seed, sprout, growing, then ripe in $time',
              excludeSemantics: true,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  _GrowStep(pic: ItemImage(id, size: 48), label: 'Seed'),
                  const _Chev(),
                  _GrowStep(pic: crops('sprout'), label: 'Sprout'),
                  const _Chev(),
                  _GrowStep(pic: crops('growing'), label: 'Growing'),
                  const _Chev(),
                  _GrowStep(pic: crops('ripe'), label: time),
                ]),
              ),
            ),
            Wrap(spacing: 6, runSpacing: 6, children: [
              Tag('$harvest a harvest', tone: TagTone.ok),
              Tag('Farming Lv ${crop.level}', tone: st.lowLv ? TagTone.warn : TagTone.cream, icon: st.lowLv ? 'lock' : null),
              Tag('+${crop.xp} XP'),
            ]),
            if (uses.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text('Used in: ${uses.join(', ')}', style: EvochiText.tiny)),
            if (st.lowLv)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('You can buy these now and plant them once your Farming reaches Lv ${crop.level}.', style: EvochiText.tiny.copyWith(color: EvochiColor.gold900)),
              ),
          ]),
        ];
      default:
        return const [];
    }
  }
}

/// What you already have (`.pd-state`): a green "Currently equipped" / "In your nest", or a cream
/// "Owned · in your Bag" / "You have 3".
class _StateLine extends StatelessWidget {
  const _StateLine(this.text, {this.equipped = false});
  final String text;
  final bool equipped;
  @override
  Widget build(BuildContext context) {
    final fg = equipped ? const Color(0xFF2F5A22) : EvochiColor.ink;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
        decoration: BoxDecoration(
          color: equipped ? null : const Color(0xFFFFF6E2),
          gradient: equipped ? const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFE6F4D4), Color(0xFFCBE7AC)]) : null,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: equipped ? const Color(0xFF5C9340) : const Color(0xFFD7B385), width: 1.5),
        ),
        child: Row(children: [
          Icon(Icons.check_rounded, size: 18, color: fg),
          const SizedBox(width: 7),
          Expanded(child: Text(text, style: TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w900, fontSize: 15, color: fg))),
        ]),
      ),
    );
  }
}

/// The sheet's close button (`.icon-btn`), with a 44 px target.
class _CloseButton extends StatelessWidget {
  const _CloseButton({required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: 'Close',
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Center(
              child: Container(
                width: 34,
                height: 34,
                decoration: Kit.parchment(radius: 9, border: 1.5, depth: 2, drop: false, edge: const Color(0xFFC9A77A)),
                child: const Icon(Icons.close_rounded, size: 18, color: EvochiColor.ink),
              ),
            ),
          ),
        ),
      );
}

/// One of the three small views of your Evochi wearing it (`.pd-prev .pv`).
class _ViewPreview extends StatelessWidget {
  const _ViewPreview({required this.pet, required this.overlays, required this.view});
  final Pet pet;
  final List<String> overlays;
  final String view;
  @override
  Widget build(BuildContext context) => Container(
        height: 108,
        decoration: BoxDecoration(
          gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFFFF9EC), Color(0xFFF3E0BC)]),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFE0C49A), width: 1.5),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8.5),
          child: Stack(children: [
            const Positioned.fill(child: CustomPaint(painter: _GroundShadow())),
            Positioned(
              left: 0,
              right: 0,
              bottom: 4,
              height: 100,
              child: FractionallySizedBox(
                widthFactor: 0.94,
                child: marketMirror(MarketPet(pet: pet, overlays: overlays, view: view == 'right' ? 'left' : view, res: 200), view == 'right'),
              ),
            ),
          ]),
        ),
      );
}

/// A soft oval shadow on the floor of a preview.
class _GroundShadow extends CustomPainter {
  const _GroundShadow();
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawOval(
      Rect.fromCenter(center: Offset(size.width / 2, size.height * 0.92), width: size.width * 0.84, height: size.height * 0.2),
      Paint()
        ..color = const Color(0x385A3214)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
  }

  @override
  bool shouldRepaint(_GroundShadow oldDelegate) => false;
}

class _GrowStep extends StatelessWidget {
  const _GrowStep({required this.pic, required this.label});
  final Widget pic;
  final String label;
  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(width: 48, height: 48, child: pic),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(label, maxLines: 1, softWrap: false, style: const TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w800, fontSize: 12, color: EvochiColor.textSecondary)),
          ),
        ]),
      );
}

class _Chev extends StatelessWidget {
  const _Chev();
  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.only(bottom: 20),
        child: Icon(Icons.chevron_right_rounded, size: 20, color: Color(0xFFB48A5A)),
      );
}

/// Three little hearts floating up from a happy Evochi (`.hearts-pop`), one every 0.8 s.
class _HeartsPop extends StatefulWidget {
  const _HeartsPop();
  @override
  State<_HeartsPop> createState() => _HeartsPopState();
}

class _HeartsPopState extends State<_HeartsPop> with SingleTickerProviderStateMixin {
  late final AnimationController _a = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400))..repeat();

  @override
  void dispose() {
    _a.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: ExcludeSemantics(
          child: AnimatedBuilder(
            animation: _a,
            builder: (_, __) => Stack(clipBehavior: Clip.none, children: [
              for (var i = 0; i < 3; i++) _heart(i),
            ]),
          ),
        ),
      );

  Widget _heart(int i) {
    const lefts = [12.0, 0.0, 24.0];
    final t = (_a.value - i / 3) % 1.0;
    final e = Curves.easeOut.transform(t);
    final o = t < 0.25 ? t / 0.25 : 1 - (t - 0.25) / 0.75;
    return Positioned(
      left: lefts[i],
      bottom: 0,
      width: 16,
      height: 16,
      child: Opacity(
        opacity: o.clamp(0.0, 1.0).toDouble(),
        child: Transform.translate(
          offset: Offset(0, 14 - 36 * e),
          child: Transform.scale(scale: 0.6 + 0.4 * e, child: const VoxelIcon('heart', size: 16)),
        ),
      ),
    );
  }
}
