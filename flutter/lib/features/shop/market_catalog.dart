// The Market's catalog (web shop.js "browse", kit.css `.shop-stall`, `.prod2`, `.hero-offer`): a
// carved-wood stall under a striped awning whose inside scrolls, the Featured tab's hero offer, a
// shelf heading and two columns of product cards.

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/models/catalog.dart';
import '../../core/models/game_state.dart';
import '../shared/kit.dart';
import '../shared/widgets.dart';
import 'market_kit.dart';

/// The stall (`.shop-stall`): a carved frame on parchment, the awning hanging over its top edge, a
/// soft fade where the shelf meets the awning; only [child] (the scrolling catalog) moves.
class MarketStall extends StatelessWidget {
  const MarketStall({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Stack(clipBehavior: Clip.none, fit: StackFit.expand, children: [
        FramedWindow(
          border: 13,
          padding: EdgeInsets.zero,
          sheet: Kit.sheet(colors: const [Color(0xFFFFF6E2), Color(0xFFF1DDB6)]),
          shadow: const BoxShadow(color: Color(0x47321C0A), blurRadius: 16, offset: Offset(0, 6)),
          child: Stack(fit: StackFit.expand, children: [
            child,
            // cards slide under the awning instead of being cut
            const Positioned(
              left: 0,
              right: 0,
              top: 0,
              height: 16,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFF9EBCD), Color(0x00F9EBCD)])),
                ),
              ),
            ),
          ]),
        ),
        const Positioned(left: 6, right: 6, top: -6, height: 30, child: ShopAwning()),
      ]);
}

/// The shelf heading (`.shelf-head`): a leaf, the title, how many items, a stitched rule.
class MarketShelfHead extends StatelessWidget {
  const MarketShelfHead({super.key, required this.title, required this.count});
  final String title;
  final int count;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 2, 2, 8),
        child: Row(children: [
          const KitLeaf(),
          const SizedBox(width: 7),
          Flexible(
            child: Semantics(
              header: true,
              child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: EvochiText.section.copyWith(fontSize: 16.5, height: 1.2)),
            ),
          ),
          const SizedBox(width: 7),
          Text('$count ${count == 1 ? 'item' : 'items'}', style: const TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w800, fontSize: 12.5, color: EvochiColor.textSecondary)),
          const Expanded(child: Padding(padding: EdgeInsets.only(left: 8), child: StitchedRule())),
        ]),
      );
}

/// A product card (`.prod2`): the artwork in a tinted pocket (with "xN" for stackables you have), the
/// name (two lines at most), "<type> · ● <Rarity>", the Farming level a seed still needs, and one
/// footer: the price, a dimmed price you can't pay yet, Owned, or Equipped / In your nest. The whole
/// card opens the details sheet; a drag that starts on it still scrolls the shelf.
class MarketProductCard extends StatelessWidget {
  const MarketProductCard({super.key, required this.id, required this.index, required this.st, required this.artHeight, required this.imageSize, required this.showIcon, required this.onTap});
  final String id;
  final int index;
  final MarketItemState st;
  final double artHeight;
  final double imageSize;
  final bool showIcon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final it = item(id);
    final on = st.equipped || st.placed;
    final Widget foot = st.equipped
        ? const MarketPriceTag(kind: MarketTagKind.equipped, expand: true)
        : st.placed
            ? const MarketPriceTag(kind: MarketTagKind.equipped, label: 'In your nest', expand: true)
            : st.owned
                ? const MarketPriceTag(kind: MarketTagKind.owned, expand: true)
                : MarketPriceTag(kind: st.afford ? MarketTagKind.price : MarketTagKind.short, price: it.price, expand: true);
    final status = st.equipped
        ? 'Equipped'
        : st.placed
            ? 'In your nest'
            : st.owned
                ? 'Owned'
                : '${it.price} EvoCoins${st.afford ? '' : ', ${st.short} more needed'}';
    final rarity = marketRarity[it.rarity]?.$1 ?? '';
    final tint = marketTint(it, index);
    return Semantics(
      button: true,
      label: '${it.name}, ${marketTypeLabel(it)}, $rarity. $status${st.stack && st.qty > 0 ? ', you have ${st.qty}' : ''}',
      excludeSemantics: true,
      child: KitPress(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        builder: (_, down) => AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          transform: Matrix4.translationValues(0, down ? 2 : 0, 0),
          padding: const EdgeInsets.fromLTRB(7, 7, 7, 8),
          decoration: KitDecoration(
            base: BoxDecoration(
              gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFFFFAEE), Color(0xFFF5E3C0)]),
              image: kitGrain,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: on ? const Color(0xFF5C9340) : const Color(0xFFA87542), width: 2),
              boxShadow: [
                if (on) const BoxShadow(color: Color(0x7382B75E), spreadRadius: 2),
                BoxShadow(color: const Color(0x293C230C), blurRadius: down ? 6 : 10, offset: Offset(0, down ? 3 : 6)),
                BoxShadow(color: on ? const Color(0xFF3D6E2B) : const Color(0xFF7A5230), offset: Offset(0, down ? 1 : 3)),
              ],
            ),
            inset: 2,
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            // the artwork pocket
            Container(
              height: artHeight,
              decoration: KitDecoration(
                base: BoxDecoration(
                  gradient: RadialGradient(center: const Alignment(0, -0.2), radius: 0.9, colors: tint),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0x5996693C), width: 2),
                ),
                inset: 2,
                shadow: const BoxShadow(color: Color(0x26643C14), blurRadius: 6, offset: Offset(0, 2)),
              ),
              child: Stack(children: [
                Center(child: ItemImage(id, size: imageSize)),
                if (st.stack && st.qty > 0)
                  Positioned(
                    top: 3,
                    right: 3,
                    child: Container(
                      height: 22,
                      padding: const EdgeInsets.symmetric(horizontal: 7),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: KitColor.woodInk,
                        borderRadius: BorderRadius.circular(7),
                        border: Border.all(color: const Color(0xFF2E180A), width: 1.5),
                      ),
                      child: Text('x${st.qty}', style: const TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w900, fontSize: 12, height: 1.1, color: Color(0xFFFFE9B8))),
                    ),
                  ),
              ]),
            ),
            const SizedBox(height: 4),
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 32),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1),
                child: Text(
                  it.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w900, fontSize: 14.5, height: 16 / 14.5, color: EvochiColor.ink),
                ),
              ),
            ),
            const SizedBox(height: 4),
            MarketMeta(it: it, icon: showIcon),
            if (it.category == ItemCategory.seed && st.lowLv) ...[
              const SizedBox(height: 4),
              Row(children: [
                const VoxelIcon('lock', size: 15),
                const SizedBox(width: 3),
                Flexible(
                  child: Text('Farming Lv ${st.needLv}',
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w800, fontSize: 12, color: EvochiColor.gold900)),
                ),
              ]),
            ],
            const SizedBox(height: 4),
            const Spacer(),
            foot,
          ]),
        ),
      ),
    );
  }
}

/// The Featured tab's hero offer (`.hero-offer`): your Evochi wearing it, its name, slot and rarity,
/// the price (or Owned / Equipped) and "Try it on".
class MarketHeroOffer extends StatelessWidget {
  const MarketHeroOffer({super.key, required this.pet, required this.id, required this.st, required this.onTry});
  final Pet pet;
  final String id;
  final MarketItemState st;
  final VoidCallback onTry;

  @override
  Widget build(BuildContext context) {
    final it = item(id);
    return Semantics(
      container: true,
      label: 'Featured: ${it.name}',
      child: Padding(
        padding: const EdgeInsets.fromLTRB(1, 0, 1, 12),
        child: Stack(clipBehavior: Clip.none, children: [
          Container(
            decoration: KitDecoration(
              base: BoxDecoration(
                gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFFFF6DA), Color(0xFFF6DDA4)]),
                image: kitGrain,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFC47F1E), width: 2.5),
                boxShadow: const [BoxShadow(color: Color(0x59F7C65C), spreadRadius: 3), BoxShadow(color: Color(0xFF8A5A12), offset: Offset(0, 3))],
              ),
              inset: 2.5,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(11.5),
              child: Stack(children: [
                // a warm glow behind the Evochi
                const Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: RadialGradient(center: Alignment(-0.52, 0.1), radius: 0.95, colors: [Color(0xF2FFECA0), Color(0x00FFECA0)], stops: [0, 0.62]),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 10, 10, 10),
                  child: Row(children: [
                    Expanded(
                      flex: 44,
                      child: SizedBox(
                        height: 140,
                        child: Align(
                          alignment: Alignment.bottomCenter,
                          child: SizedBox(
                            height: 132,
                            child: Semantics(
                              image: true,
                              label: '${pet.name} wearing the ${it.name}',
                              child: MarketPet(pet: pet, overlays: marketOverlays(pet, id, true), res: 300),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      flex: 56,
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(it.name, style: const TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w900, fontSize: 18, height: 20 / 18, color: EvochiColor.ink)),
                        const SizedBox(height: 4),
                        MarketMeta(it: it),
                        const SizedBox(height: 8),
                        Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                          if (st.owned)
                            MarketPriceTag(kind: MarketTagKind.owned, label: st.equipped ? 'Equipped' : 'Owned')
                          else
                            MarketPriceTag(kind: st.afford ? MarketTagKind.price : MarketTagKind.short, price: it.price),
                          EvochiButton(
                            label: 'Try it on',
                            small: true,
                            expand: false,
                            icon: const Icon(Icons.checkroom_rounded, color: EvochiColor.wood, size: 18),
                            onPressed: onTry,
                          ),
                        ]),
                      ]),
                    ),
                  ]),
                ),
              ]),
            ),
          ),
          // the "Featured" ribbon over the top edge
          Positioned(
            top: -9,
            left: 10,
            child: IgnorePointer(
              child: Container(
                height: 22,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFFFE5A2), Color(0xFFF4B84E)]),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: KitColor.plaqueEdge, width: 1.5),
                  boxShadow: const [BoxShadow(color: KitColor.plaqueEdge, offset: Offset(0, 2))],
                ),
                child: const Text('Featured', style: TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w900, fontSize: 12.5, height: 1.1, color: Color(0xFF5A3410))),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
