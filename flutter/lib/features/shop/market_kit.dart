// The Market's shared pieces (web/src/screens/shop.js and the "Market (browse / details / try-on)"
// section of web/src/kit.css): what an item is to this player, its type and rarity, the price tag and
// the state chips, the dressing room's pills, your Evochi drawn from any of its three views, and the
// one-shot entrances between the catalog and a preview.

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../controllers/game_controller.dart';
import '../../core/models/catalog.dart';
import '../../core/models/game_state.dart';
import '../../core/services/asset_manifest.dart';
import '../../game/engine.dart' as g;
import '../../game/home/home.dart' as h;
import '../shared/kit.dart';
import '../shared/sprite.dart';
import '../shared/widgets.dart';

/// The Featured tab's hero offer (web: the catalog's `hero: true` item).
const marketHeroId = 'golden_crest_crown';

/// The dressing room's views: the 3/4 hero both ways round, and from behind (the encounter view).
const marketViews = [('left', '3/4'), ('right', 'Other side'), ('back', 'Back')];

/// Rarity names and their dot colours (web `RARITY`).
const marketRarity = <String, (String, Color)>{
  'common': ('Common', Color(0xFFC9A78C)),
  'uncommon': ('Uncommon', Color(0xFF82B75E)),
  'rare': ('Rare', Color(0xFF39BDE3)),
  'epic': ('Epic', Color(0xFFAA8BCF)),
  'legendary': ('Legendary', Color(0xFFF4B84E)),
};

/// Everything a card, a sheet or a button needs to know about an item for this player.
class MarketItemState {
  const MarketItemState({
    required this.qty,
    required this.stack,
    required this.owned,
    required this.equipped,
    required this.placed,
    required this.afford,
    required this.short,
    required this.needLv,
    required this.lowLv,
  });
  final int qty;
  final bool stack; // care items and stackables: bought again and again
  final bool owned; // a one-of-a-kind item you have
  final bool equipped;
  final bool placed; // a habitat piece in your nest
  final bool afford;
  final int short; // EvoCoins still needed
  final int needLv; // seeds: the Farming level they grow at
  final bool lowLv;
}

MarketItemState marketItemState(GameController c, String id) {
  final s = c.state;
  final it = item(id);
  final qty = g.ownedQty(s, id);
  final stack = it.isStackable;
  final farm = h.skillLevel(h.skillXp(s, 'farming')).level;
  final needLv = it.category == ItemCategory.seed ? (h.cropDefs[it.crop]?.level ?? 1) : 0;
  final bal = c.balance;
  return MarketItemState(
    qty: qty,
    stack: stack,
    owned: qty > 0 && !stack,
    equipped: it.category == ItemCategory.wearable && s.pet?.equipped[it.slot] == id,
    placed: it.category == ItemCategory.decoration && s.placements.values.contains(id),
    afford: bal >= it.price,
    short: math.max(0, it.price - bal),
    needLv: needLv,
    lowLv: needLv > farm,
  );
}

/// "Head", "Care", "Seed", "Nest" or "Nest side" (the same words on cards, sheets and the dressing room).
String marketTypeLabel(CatalogItem it) => switch (it.category) {
      ItemCategory.wearable => slotLabels[it.slot] ?? 'Wearable',
      ItemCategory.consumable => 'Care',
      ItemCategory.seed => 'Seed',
      ItemCategory.decoration => it.decor == 'nest' ? 'Nest' : 'Nest side',
      ItemCategory.ingredient => 'Ingredient',
    };

String marketCatIcon(CatalogItem it) => switch (it.category) {
      ItemCategory.wearable => 'wearables',
      ItemCategory.consumable => 'care',
      ItemCategory.seed => 'skill_farming',
      _ => 'habitats',
    };

const _tGold = [Color(0xFFFFF5D9), Color(0xFFF8E2B0)];
const _tGreen = [Color(0xFFEFF8E2), Color(0xFFD5EBBC)];
const _tBlue = [Color(0xFFEAF5FC), Color(0xFFCFE6F6)];
const _tRose = [Color(0xFFFDF0EC), Color(0xFFF5D6CD)];
const _tViolet = [Color(0xFFF4EEFB), Color(0xFFE1D4F2)];

/// The artwork pocket's tint for the [i]th item of a shelf (`.bg-gold`, `.bg-green`...).
List<Color> marketTint(CatalogItem it, int i) {
  final t = switch (it.category) {
    ItemCategory.wearable => const [_tGold, _tGreen, _tBlue, _tRose, _tViolet],
    ItemCategory.consumable => const [_tGreen, _tRose],
    ItemCategory.decoration => const [_tGold, _tGreen],
    ItemCategory.seed => const [_tGreen, _tGold],
    _ => const [_tGold],
  };
  return t[i % t.length];
}

/// What the Evochi wears in a preview: its own things, plus [id] in its slot while [showing].
List<String> marketOverlays(Pet pet, String? id, bool showing) {
  final eq = Map<String, String>.of(pet.equipped);
  final it = id == null ? null : catalog[id];
  if (showing && it != null && it.category == ItemCategory.wearable && it.slot != null) eq[it.slot!] = it.id;
  return eq.values.toList();
}

/// The art's width / height for a view ('back' is the encounter frame).
double marketPetAspect(int stage, String view) {
  final e = art.char(stage);
  final b = view == 'back' ? e.battle : null;
  return b != null ? b.w / b.h : e.w / e.h;
}

/// Where the dressing room zooms: the slot's anchor in the art (head: the top of the head and 10% of
/// the frame down; neck; back), in the hero frame or the back view. The other side is the same art
/// mirrored by a wrapper, so the point stays in the art's own coordinates.
Alignment marketZoomAlignment(int stage, String? slot, String view) {
  final e = art.char(stage);
  final b = view == 'back' ? e.battle : null;
  final w = b != null ? b.w : e.w;
  final hh = b != null ? b.h : e.h;
  bool has(String n) => b != null ? b.hasAnchor(n) : ((e.j['anchors'] as Map?)?.containsKey(n) ?? false);
  Offset at(String n) => b != null ? b.anchor(n) : e.anchor(n);
  Offset? pt;
  if (slot == 'head') {
    if (b != null && (b.hasAnchor('head_top') || b.hasAnchor('body_top'))) {
      pt = b.headTop + Offset(0, hh * 0.1);
    } else if (b == null && has('head_top')) {
      pt = at('head_top') + Offset(0, hh * 0.1);
    }
  } else {
    final n = slot == 'back' ? 'back' : 'neck';
    if (has(n)) pt = at(n);
  }
  if (pt == null || w <= 0 || hh <= 0) return const Alignment(0, -0.2); // 50% 40%
  return Alignment((pt.dx / w * 2 - 1).clamp(-1.0, 1.0).toDouble(), (pt.dy / hh * 2 - 1).clamp(-1.0, 1.0).toDouble());
}

// some pieces sit where the camera can't see them from behind (the Tiny Crown faces forward)
final _hiddenDone = <String, bool>{};
final _hiddenJobs = <String, Future<bool>>{};

/// The answer, if [marketHiddenFromBehind] has already worked it out.
bool? marketHiddenKnown(int stage, String id) => _hiddenDone['$stage|$id'];

/// True when [id] has no visible pixels in the back view's overlay (so the dressing room can say so).
Future<bool> marketHiddenFromBehind(int stage, String id) {
  final key = '$stage|$id';
  return _hiddenJobs.putIfAbsent(key, () async {
    var hidden = false;
    try {
      hidden = await _scanHidden(stage, id);
    } catch (_) {
      hidden = false;
    }
    _hiddenDone[key] = hidden;
    return hidden;
  });
}

Future<bool> _scanHidden(int stage, String id) async {
  final b = art.char(stage).battle;
  final r = b?.overlay(id);
  if (b == null || r == null) return true;
  final img = await AtlasCache.load(b.overlaysFile);
  // a quarter-size copy of the overlay's cell is plenty to find a visible pixel
  final w = math.max(1, (r.width / 4).ceil());
  final hh = math.max(1, (r.height / 4).ceil());
  final rec = ui.PictureRecorder();
  Canvas(rec).drawImageRect(img, r, Rect.fromLTWH(0, 0, w.toDouble(), hh.toDouble()), Paint()..filterQuality = FilterQuality.low);
  final pic = rec.endRecording();
  final small = await pic.toImage(w, hh);
  pic.dispose();
  final data = await small.toByteData(format: ui.ImageByteFormat.rawRgba);
  small.dispose();
  if (data == null) return false;
  for (var i = 3; i < data.lengthInBytes; i += 4) {
    if (data.getUint8(i) > 12) return false;
  }
  return true;
}

/// Where a habitat piece goes: the first free spot that fits it (the nest, or left / right / back).
String marketNestSpot(GameState s, CatalogItem it) {
  final fits = [for (final d in decorSlots.values) if (d.accepts == it.decor) d.id];
  if (fits.isEmpty) return 'nest';
  return fits.firstWhere((id) => s.placements[id] == null, orElse: () => fits.first);
}

// ------------------------------------------------------------------ widgets ----
/// Your Evochi as the Market draws it. [view] 'left' is the 3/4 hero frame ('right' is the same frame,
/// mirrored by the caller), 'back' the encounter's frame with its own overlays. It fills its box
/// (contained, standing on the bottom edge), drawn from [res] px art so it stays crisp when large and
/// always uses the full frames (never the trimmed thumbnails), so anchors line up.
class MarketPet extends StatelessWidget {
  const MarketPet({super.key, required this.pet, required this.overlays, this.view = 'left', this.expr = 'happy', this.res = 480, this.alignment = Alignment.bottomCenter});
  final Pet pet;
  final List<String> overlays;
  final String view;
  final String expr;
  final double res;
  final Alignment alignment;
  @override
  Widget build(BuildContext context) {
    final back = view == 'back' && art.char(pet.stage).battle != null;
    final Widget sprite = back
        ? BattleSprite(stage: pet.stage, palette: pet.paletteId, overlays: overlays, width: res * marketPetAspect(pet.stage, 'back'))
        : PetSprite(stage: pet.stage, palette: pet.paletteId, expr: expr, overlays: overlays, height: math.max(160.0, res));
    return FittedBox(fit: BoxFit.contain, alignment: alignment, child: sprite);
  }
}

/// A child mirrored left to right (the dressing room's other side).
Widget marketMirror(Widget child, bool flip) => Transform(alignment: Alignment.center, transform: Matrix4.diagonal3Values(flip ? -1.0 : 1.0, 1.0, 1.0), child: child);

/// The rarity dot (`.rdot`).
class MarketRarityDot extends StatelessWidget {
  const MarketRarityDot(this.rarity, {super.key});
  final String rarity;
  @override
  Widget build(BuildContext context) => Container(
        width: 9,
        height: 9,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: marketRarity[rarity]?.$2 ?? const Color(0xFFC9A78C),
          border: Border.all(color: const Color(0x733C1E0A), width: 1.5),
        ),
      );
}

/// "<type> · ● <Rarity>" (`.meta`), with the category icon on wider screens ([icon]).
class MarketMeta extends StatelessWidget {
  const MarketMeta({super.key, required this.it, this.icon = false, this.size = 12});
  final CatalogItem it;
  final bool icon;
  final double size;
  @override
  Widget build(BuildContext context) {
    final style = TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w800, fontSize: size, height: 1.2, color: EvochiColor.textSecondary);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      if (icon) ...[VoxelIcon(marketCatIcon(it), size: 16), const SizedBox(width: 4)],
      Flexible(child: Text(marketTypeLabel(it), maxLines: 1, softWrap: false, overflow: TextOverflow.ellipsis, style: style)),
      const SizedBox(width: 4),
      Opacity(opacity: 0.6, child: Text('·', style: style)),
      const SizedBox(width: 4),
      MarketRarityDot(it.rarity),
      const SizedBox(width: 4),
      Flexible(child: Text(marketRarity[it.rarity]?.$1 ?? '', maxLines: 1, softWrap: false, overflow: TextOverflow.ellipsis, style: style)),
    ]);
  }
}

/// A coin with its colour drained (`.dim`, `.pr.short img`): the price you can't pay yet.
class MarketDimCoin extends StatelessWidget {
  const MarketDimCoin({super.key, this.size = 22, this.saturation = 0.35, this.opacity = 0.75});
  final double size;
  final double saturation;
  final double opacity;
  @override
  Widget build(BuildContext context) {
    final s = saturation;
    const r = 0.2126, gr = 0.7152, b = 0.0722;
    return Opacity(
      opacity: opacity,
      child: ColorFiltered(
        colorFilter: ColorFilter.matrix([
          r * (1 - s) + s, gr * (1 - s), b * (1 - s), 0, 0, //
          r * (1 - s), gr * (1 - s) + s, b * (1 - s), 0, 0,
          r * (1 - s), gr * (1 - s), b * (1 - s) + s, 0, 0,
          0, 0, 0, 1, 0,
        ]),
        child: VoxelIcon('coin', size: size),
      ),
    );
  }
}

enum MarketTagKind { price, short, owned, equipped }

/// A product's one footer (`.pr`): the price on a light-wood tag, a dimmed "short" tag you can't pay
/// yet, a pale green "Owned", or a solid green "✓ Equipped" / "✓ In your nest". [expand] fills the width
/// (product cards).
class MarketPriceTag extends StatelessWidget {
  const MarketPriceTag({super.key, required this.kind, this.price = 0, this.label, this.expand = false});
  final MarketTagKind kind;
  final int price;
  final String? label;
  final bool expand;
  @override
  Widget build(BuildContext context) {
    final Decoration deco;
    final Widget body;
    const text = TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w900, fontSize: 16, height: 1.1, color: KitColor.signInk);
    // (only a tag that fills its width lets its label shrink)
    Widget fit(Widget t) => expand ? Flexible(child: t) : t;
    final size = expand ? MainAxisSize.max : MainAxisSize.min;
    if (kind == MarketTagKind.price || kind == MarketTagKind.short) {
      final short = kind == MarketTagKind.short;
      deco = short
          ? KitDecoration(
              base: BoxDecoration(
                color: const Color(0xFFEADBC4),
                image: kitGrain,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF9C7E62), width: 2),
                boxShadow: const [BoxShadow(color: Color(0xFF9C7E62), offset: Offset(0, 2))],
              ),
              inset: 2,
            )
          : Kit.wood(radius: 8, border: 2, width: 240, y: -0.2, edge: 2, drop: false);
      body = Row(mainAxisSize: size, children: [
        Transform.translate(offset: const Offset(-3, 0), child: short ? const MarketDimCoin(size: 21, saturation: 0.4, opacity: 0.8) : const VoxelIcon('coin', size: 21)),
        const SizedBox(width: 2),
        fit(Text(fmt(price), maxLines: 1, softWrap: false, overflow: TextOverflow.fade, style: short ? text.copyWith(color: const Color(0xFF8A4B2E)) : text.copyWith(shadows: kitSignShadow))),
      ]);
    } else if (kind == MarketTagKind.owned) {
      deco = BoxDecoration(
        gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFE6F4D4), Color(0xFFCBE7AC)]),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF5C9340), width: 2),
        boxShadow: const [BoxShadow(color: Color(0xFF5C9340), offset: Offset(0, 2))],
      );
      body = Row(mainAxisSize: size, mainAxisAlignment: MainAxisAlignment.center, children: [
        fit(Text(label ?? 'Owned', maxLines: 1, softWrap: false, overflow: TextOverflow.fade, style: text.copyWith(fontSize: 13.5, color: const Color(0xFF2F5A22)))),
      ]);
    } else {
      deco = BoxDecoration(
        color: const Color(0xFF5FA046),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF3D6E2B), width: 2),
        boxShadow: const [BoxShadow(color: Color(0xFF3D6E2B), offset: Offset(0, 2))],
      );
      const shade = [Shadow(color: Color(0x40000000), offset: Offset(0, 1))];
      body = Row(mainAxisSize: size, mainAxisAlignment: MainAxisAlignment.center, children: [
        const Icon(Icons.check_rounded, size: 16, color: Colors.white, shadows: shade),
        const SizedBox(width: 4),
        fit(Text(label ?? 'Equipped', maxLines: 1, softWrap: false, overflow: TextOverflow.fade, style: text.copyWith(fontSize: 13.5, color: Colors.white, shadows: shade))),
      ]);
    }
    return Container(height: 30, padding: const EdgeInsets.symmetric(horizontal: 8), decoration: deco, child: body);
  }
}

enum MarketChipKind { plain, preview, owned, equipped }

/// The preview panel's state chip (`.mk-chip`): Previewing / Without it / ✓ Owned / ✓ Equipped.
class MarketChip extends StatelessWidget {
  const MarketChip(this.label, {super.key, this.kind = MarketChipKind.plain});
  final String label;
  final MarketChipKind kind;
  @override
  Widget build(BuildContext context) {
    final (Color? bg, Gradient? grad, Color fg, Color edge) = switch (kind) {
      MarketChipKind.preview => (null, const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFFFE5A2), Color(0xFFF9CA70)]), EvochiColor.gold900, const Color(0xFFE3A64A)),
      MarketChipKind.equipped => (const Color(0xFF5FA046), null, Colors.white, const Color(0xFF3D6E2B)),
      MarketChipKind.owned => (const Color(0xFFE6F4D4), null, const Color(0xFF2F5A22), const Color(0xFF82B75E)),
      MarketChipKind.plain => (const Color(0xFFF6EBDD), null, EvochiColor.textSecondary, const Color(0xFFE5D3BE)),
    };
    final check = kind == MarketChipKind.owned || kind == MarketChipKind.equipped;
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(color: bg, gradient: grad, borderRadius: BorderRadius.circular(8), border: Border.all(color: edge, width: 1.5)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (check) ...[Icon(Icons.check_rounded, size: 14, color: fg), const SizedBox(width: 4)],
        Text(label, maxLines: 1, softWrap: false, style: TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w900, fontSize: 12, height: 1.1, color: fg)),
      ]),
    );
  }
}

/// A round parchment pill on the stage (`.try-top .pill`, `.spot-tag`). [pressed] lights it gold; no
/// [onTap] makes it a plain label.
class MarketPill extends StatelessWidget {
  const MarketPill({super.key, required this.label, this.icon, this.pressed = false, this.onTap, this.semanticLabel});
  final String label;
  final IconData? icon;
  final bool pressed;
  final VoidCallback? onTap;
  final String? semanticLabel;
  @override
  Widget build(BuildContext context) {
    Widget pill(bool down) => AnimatedContainer(
          duration: const Duration(milliseconds: 60),
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 11),
          transform: Matrix4.translationValues(0, down ? 1 : 0, 0),
          decoration: KitDecoration(
            base: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: pressed ? const [Color(0xFFFFE9AE), Color(0xFFF7C65C)] : const [Color(0xFFFFF8E6), Color(0xFFEED7AE)],
              ),
              image: kitGrain,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: KitColor.woodInk, width: 2),
              boxShadow: [BoxShadow(color: KitColor.woodShadow, offset: Offset(0, down ? 1 : 2))],
            ),
            inset: 2,
            top: const KitBand(1.5, Color(0xFFFFFDF5)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[Icon(icon, size: 19, color: KitColor.woodInk), const SizedBox(width: 5)],
            Text(label, maxLines: 1, softWrap: false, style: const TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w900, fontSize: 13, color: KitColor.signInk)),
          ]),
        );
    if (onTap == null) return Semantics(label: semanticLabel ?? label, excludeSemantics: true, child: pill(false));
    return Semantics(
      button: true,
      toggled: pressed,
      label: semanticLabel ?? label,
      excludeSemantics: true,
      child: KitPress(onTap: onTap, builder: (_, down) => pill(down)),
    );
  }
}

/// The rarity stamp in the details sheet (web `rarityTag`): a leaf, the rarity, its own edge colour.
class MarketRarityTag extends StatelessWidget {
  const MarketRarityTag(this.rarity, {super.key});
  final String rarity;
  @override
  Widget build(BuildContext context) {
    final edge = switch (rarity) {
      'common' => const Color(0xFF82B75E),
      'uncommon' => const Color(0xFF5FA046),
      'rare' => const Color(0xFF39BDE3),
      'epic' => const Color(0xFFAA8BCF),
      _ => const Color(0xFFF4B84E),
    };
    final (Color? bg, Gradient? grad, Color fg) = switch (rarity) {
      'common' || 'uncommon' => (EvochiColor.meadow100, null, EvochiColor.healthy),
      'rare' || 'epic' => (null, const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFFBF0DA), Color(0xFFEEDDBC)]), const Color(0xFF5A3E2A)),
      _ => (null, const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFFFE5A2), Color(0xFFF9CA70)]), EvochiColor.gold900),
    };
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: KitDecoration(
        base: BoxDecoration(
          color: bg,
          gradient: grad,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: edge, width: 1.5),
          boxShadow: const [BoxShadow(color: Color(0x385A3719), offset: Offset(0, 1.5))],
        ),
        inset: 1.5,
        top: const KitBand(1, Color(0x99FFFFFF)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const VoxelIcon('care', size: 16),
        const SizedBox(width: 4),
        Text(marketRarity[rarity]?.$1 ?? rarity, style: EvochiText.tag.copyWith(color: fg)),
      ]),
    );
  }
}

enum MarketEntranceKind { stage, panel, back }

/// A short one-shot entrance, played once when it mounts with [play] (and never under reduced motion):
/// the preview's stage scales and fades in, its panel slides up, the catalog fades back in. Later
/// rebuilds never replay it, and the tree under it keeps its shape (the search field keeps its focus).
class MarketEntrance extends StatefulWidget {
  const MarketEntrance({super.key, required this.child, required this.kind, this.play = true});
  final Widget child;
  final MarketEntranceKind kind;
  final bool play;
  @override
  State<MarketEntrance> createState() => _MarketEntranceState();
}

class _MarketEntranceState extends State<MarketEntrance> with SingleTickerProviderStateMixin {
  static const _stageCurve = Cubic(0.2, 0.9, 0.3, 1.08);
  late final AnimationController _a = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: switch (widget.kind) { MarketEntranceKind.stage => 340, MarketEntranceKind.panel => 350, MarketEntranceKind.back => 200 }),
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final rm = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (widget.play && !rm) {
      _a.forward();
    } else {
      _a.value = 1;
    }
  }

  @override
  void dispose() {
    _a.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _a,
        child: widget.child,
        builder: (_, child) {
          final v = _a.value;
          double o = 1, dy = 0, s = 1;
          if (widget.kind == MarketEntranceKind.stage) {
            final e = _stageCurve.transform(v);
            o = e.clamp(0.0, 1.0).toDouble();
            s = 0.94 + 0.06 * e;
            dy = 10 * (1 - e);
          } else if (widget.kind == MarketEntranceKind.panel) {
            final e = Curves.easeOut.transform(((v * 350 - 50) / 300).clamp(0.0, 1.0).toDouble());
            o = e;
            dy = 18 * (1 - e);
          } else {
            final e = Curves.easeOut.transform(v);
            o = 0.45 + 0.55 * e;
            dy = 4 * (1 - e);
          }
          return Opacity(opacity: o, child: Transform.translate(offset: Offset(0, dy), child: Transform.scale(scale: s, child: child)));
        },
      );
}
