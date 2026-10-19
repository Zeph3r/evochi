// The Market's previews (web shop.js `tryRoom` / `nestRoom`, kit.css `.try-*`, `.tp-*`): the dressing
// room for wearables (a curtained stage with your Evochi large on a rug, three views, zoom on the
// slot, the piece on or off) and the nest preview for habitat pieces (the real meadow behind, the
// piece in its spot). Both share the bottom panel: the item, its state and price, and two buttons.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/router.dart';
import '../../app/theme.dart';
import '../../controllers/game_controller.dart';
import '../../core/models/catalog.dart';
import '../../core/models/game_state.dart';
import '../shared/kit.dart';
import '../shared/widgets.dart';
import '../village/village_screen.dart';
import 'market_kit.dart';

/// The primary purchase button of a preview: Purchase, or "Need N more" when you can't pay yet.
Widget _buyOrEarn(CatalogItem it, MarketItemState st, VoidCallback onBuy, VoidCallback onEarn) => st.afford
    ? EvochiButton(label: 'Purchase', tone: ButtonTone.green, icon: const VoxelIcon('coin', size: 22), semanticLabel: 'Purchase ${it.name} for ${fmt(it.price)} EvoCoins', onPressed: onBuy)
    : EvochiButton(
        label: 'Need ${fmt(st.short)} more',
        tone: ButtonTone.cream,
        icon: const MarketDimCoin(size: 22),
        semanticLabel: 'You need ${fmt(st.short)} more EvoCoins',
        onPressed: onEarn,
      );

/// The dressing room (wearables).
class MarketDressingRoom extends StatelessWidget {
  const MarketDressingRoom({
    super.key,
    required this.id,
    required this.view,
    required this.showing,
    required this.zoom,
    required this.cheer,
    required this.play,
    required this.onExit,
    required this.onToggle,
    required this.onZoom,
    required this.onRotate,
    required this.onView,
    required this.onPetTap,
    required this.onBuy,
    required this.onEarn,
    required this.onEquip,
    required this.onUnequip,
  });
  final String id;
  final String view; // left | right | back
  final bool showing; // the piece on (false: "Show original")
  final bool zoom;
  final int cheer; // bumps make the Evochi hop
  final bool play; // the entrance (only right after entering)
  final VoidCallback onExit;
  final VoidCallback onToggle;
  final VoidCallback onZoom;
  final ValueChanged<int> onRotate;
  final ValueChanged<String> onView;
  final VoidCallback onPetTap;
  final VoidCallback onBuy;
  final VoidCallback onEarn;
  final VoidCallback onEquip;
  final VoidCallback onUnequip;

  @override
  Widget build(BuildContext context) {
    final c = context.watch<GameController>();
    final pet = c.state.pet!;
    final it = item(id);
    final st = marketItemState(c, id);
    final on = showing || st.equipped;
    final ov = marketOverlays(pet, id, on);
    final Widget primary;
    if (st.equipped) {
      primary = EvochiButton(label: 'Take off', tone: ButtonTone.danger, semanticLabel: 'Take off the ${it.name}', onPressed: onUnequip);
    } else if (st.owned) {
      primary = EvochiButton(label: 'Equip Now', icon: const Icon(Icons.dry_cleaning_rounded, color: EvochiColor.wood, size: 20), onPressed: onEquip);
    } else {
      primary = _buyOrEarn(it, st, onBuy, onEarn);
    }
    final chip = st.equipped
        ? const MarketChip('Equipped', kind: MarketChipKind.equipped)
        : st.owned
            ? const MarketChip('Owned', kind: MarketChipKind.owned)
            : on
                ? const MarketChip('Previewing', kind: MarketChipKind.preview)
                : const MarketChip('Without it');
    return Semantics(
      container: true,
      label: 'Dressing room: ${it.name}',
      child: Column(children: [
        SafeArea(bottom: false, child: PlaceHeader(title: 'Dressing Room', short: 'Try On', onBack: onExit, backLabel: 'Back to the Market')),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: MarketEntrance(kind: MarketEntranceKind.stage, play: play, child: _stage(pet, it, st, on, ov)),
          ),
        ),
        MarketEntrance(
          kind: MarketEntranceKind.panel,
          play: play,
          child: MarketTryPanel(
            id: id,
            meta: MarketMeta(it: it, size: 12),
            chip: chip,
            price: st.owned ? null : MarketPriceTag(kind: st.afford ? MarketTagKind.price : MarketTagKind.short, price: it.price),
            cancelLabel: st.owned ? 'Done' : 'Cancel',
            onCancel: onExit,
            primary: primary,
          ),
        ),
        SizedBox(height: navInset(context)),
      ]),
    );
  }

  /// The curtained stage (`.try-stage`): the pills on top, your Evochi on its rug, the turn arrows and
  /// the three view thumbnails.
  Widget _stage(Pet pet, CatalogItem it, MarketItemState st, bool on, List<String> ov) {
    final viewName = marketViews.firstWhere((x) => x.$1 == view, orElse: () => marketViews.first).$2;
    return FramedWindow(
      border: 12,
      padding: EdgeInsets.zero,
      sheet: BoxDecoration(
        gradient: const RadialGradient(center: Alignment(0, -0.12), radius: 0.8, colors: [Color(0xFFFFF6DC), Color(0xFFF7E3B8), Color(0xFFD9AE78)], stops: [0, 0.52, 1]),
        borderRadius: BorderRadius.circular(6),
      ),
      shadow: const BoxShadow(color: Color(0x33321C0A), blurRadius: 12, offset: Offset(0, 4)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(5),
        child: LayoutBuilder(builder: (ctx, b) {
          final hh = b.maxHeight;
          // short stages squeeze the gaps above and below the Evochi
          final pt = math.min(54.0, hh * 0.2);
          final pb = math.min(76.0, hh * 0.28);
          final arrowTop = math.max(0.0, hh * 0.46 - 22);
          return Stack(children: [
            const Positioned(left: 0, top: 0, bottom: 0, width: 26, child: _Curtain(left: true)),
            const Positioned(right: 0, top: 0, bottom: 0, width: 26, child: _Curtain(left: false)),
            Positioned(
              left: 0,
              right: 0,
              top: pt,
              height: math.max(0.0, hh - pt - pb),
              child: MarketPetStage(
                pet: pet,
                overlays: ov,
                view: view,
                zoom: zoom,
                slot: it.slot,
                cheer: cheer,
                onTap: onPetTap,
                label: '${pet.name}${on ? ' wearing the ${it.name}' : ''}, $viewName view',
              ),
            ),
            Positioned(
              top: 8,
              left: 32,
              right: 32,
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                if (st.equipped)
                  const SizedBox.shrink()
                else
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: MarketPill(label: on ? 'Show original' : 'Show preview', icon: Icons.visibility_rounded, pressed: !on, onTap: onToggle),
                    ),
                  ),
                const SizedBox(width: 6),
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: MarketPill(label: zoom ? 'Zoom out' : 'Zoom in', icon: zoom ? Icons.zoom_out_rounded : Icons.zoom_in_rounded, pressed: zoom, onTap: onZoom),
                  ),
                ),
              ]),
            ),
            Positioned(left: 32, top: arrowTop, child: _Arrow(left: true, onTap: () => onRotate(-1))),
            Positioned(right: 32, top: arrowTop, child: _Arrow(left: false, onTap: () => onRotate(1))),
            Positioned(
              left: 0,
              right: 0,
              bottom: 8,
              child: Semantics(
                container: true,
                label: 'Views',
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  for (var i = 0; i < marketViews.length; i++) ...[
                    if (i > 0) const SizedBox(width: 8),
                    _ViewThumb(pet: pet, overlays: ov, view: marketViews[i].$1, label: marketViews[i].$2, selected: marketViews[i].$1 == view, onTap: () => onView(marketViews[i].$1)),
                  ],
                ]),
              ),
            ),
            if (view == 'back' && on) Positioned(left: 34, right: 34, bottom: pb, child: _HiddenNote(stage: pet.stage, id: id, name: it.name)),
          ]);
        }),
      ),
    );
  }
}

/// The nest preview (habitat pieces): the real meadow shows through behind (the screen draws it), with
/// the piece in its spot unless you're comparing with the original.
class MarketNestRoom extends StatelessWidget {
  const MarketNestRoom({
    super.key,
    required this.id,
    required this.showing,
    required this.play,
    required this.onExit,
    required this.onToggle,
    required this.onBuy,
    required this.onEarn,
    required this.onPlace,
  });
  final String id;
  final bool showing;
  final bool play;
  final VoidCallback onExit;
  final VoidCallback onToggle;
  final VoidCallback onBuy;
  final VoidCallback onEarn;
  final VoidCallback onPlace;

  @override
  Widget build(BuildContext context) {
    final c = context.watch<GameController>();
    final it = item(id);
    final st = marketItemState(c, id);
    final spot = marketNestSpot(c.state, it);
    final own = st.owned && !st.stack;
    final Widget primary = own
        ? (st.placed ? const Center(child: MarketPriceTag(kind: MarketTagKind.owned, label: 'In your nest', expand: true)) : EvochiButton(label: 'Place it here', onPressed: onPlace))
        : _buyOrEarn(it, st, onBuy, onEarn);
    final chip = st.placed
        ? const MarketChip('In your nest', kind: MarketChipKind.equipped)
        : own
            ? const MarketChip('Owned', kind: MarketChipKind.owned)
            : showing
                ? const MarketChip('Previewing', kind: MarketChipKind.preview)
                : const MarketChip('Without it');
    return Semantics(
      container: true,
      label: 'Preview in nest: ${it.name}',
      child: Column(children: [
        SafeArea(bottom: false, child: PlaceHeader(title: 'Preview in Nest', short: 'Preview', onBack: onExit, backLabel: 'Back to the Market')),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: MarketEntrance(
              kind: MarketEntranceKind.stage,
              play: play,
              // (no backdrop of its own: taps on the meadow reach your Evochi)
              child: Stack(children: [
                Positioned(
                  top: 8,
                  left: 4,
                  right: 4,
                  child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    if (st.placed)
                      const SizedBox.shrink()
                    else
                      Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: MarketPill(label: showing ? 'Show original' : 'Show preview', icon: Icons.visibility_rounded, pressed: !showing, onTap: onToggle),
                        ),
                      ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerRight, child: MarketPill(label: '${decorSlots[spot]?.label ?? 'Nest'} spot')),
                    ),
                  ]),
                ),
              ]),
            ),
          ),
        ),
        MarketEntrance(
          kind: MarketEntranceKind.panel,
          play: play,
          child: MarketTryPanel(
            id: id,
            meta: MarketMeta(it: it, size: 12),
            chip: chip,
            price: own ? null : MarketPriceTag(kind: st.afford ? MarketTagKind.price : MarketTagKind.short, price: it.price),
            cancelLabel: st.owned ? 'Done' : 'Cancel',
            onCancel: onExit,
            primary: primary,
          ),
        ),
        SizedBox(height: navInset(context)),
      ]),
    );
  }
}

/// The preview's bottom panel (`.try-panel`): the item's picture, name, "<type> · ● <Rarity>", its state
/// chip and price, then Cancel / Done and the one thing to do.
class MarketTryPanel extends StatelessWidget {
  const MarketTryPanel({
    super.key,
    required this.id,
    required this.meta,
    required this.chip,
    this.price,
    required this.cancelLabel,
    required this.onCancel,
    required this.primary,
  });
  final String id;
  final Widget meta;
  final Widget chip;
  final Widget? price;
  final String cancelLabel;
  final VoidCallback onCancel;
  final Widget primary;

  @override
  Widget build(BuildContext context) {
    final it = item(id);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
      child: FramedWindow(
        border: 12,
        padding: const EdgeInsets.fromLTRB(10, 9, 10, 10),
        sheet: Kit.sheet(colors: const [Color(0xFFFFF8E8), Color(0xFFF4E1BF)]),
        shadow: const BoxShadow(color: Color(0x40321C0A), blurRadius: 12, offset: Offset(0, 4)),
        child: Semantics(
          liveRegion: true,
          container: true,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Container(
                width: 50,
                height: 50,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: const Color(0xFFFFF6E2), borderRadius: BorderRadius.circular(11), border: Border.all(color: const Color(0xFFD7B385), width: 1.5)),
                child: ItemImage(id, size: 44),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(it.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w900, fontSize: 17, height: 19 / 17, color: EvochiColor.ink)),
                  const SizedBox(height: 2),
                  meta,
                ]),
              ),
              const SizedBox(width: 8),
              Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
                chip,
                if (price != null) ...[const SizedBox(height: 4), price!],
              ]),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: EvochiButton(label: cancelLabel, tone: ButtonTone.cream, onPressed: onCancel)),
              const SizedBox(width: 8),
              Expanded(child: primary),
            ]),
          ]),
        ),
      ),
    );
  }
}

/// Your Evochi large on the dressing room's rug: it bobs gently (not while zoomed), hops when tapped or
/// when something new goes on ([cheer]), fades a touch as it turns to a new [view], and zooms 1.6x on its
/// [slot]. 'right' mirrors the whole figure, so the zoom point stays on the art. Reduced motion: still.
class MarketPetStage extends StatefulWidget {
  const MarketPetStage({
    super.key,
    required this.pet,
    required this.overlays,
    required this.view,
    required this.zoom,
    required this.slot,
    required this.cheer,
    required this.onTap,
    required this.label,
  });
  final Pet pet;
  final List<String> overlays;
  final String view;
  final bool zoom;
  final String? slot;
  final int cheer;
  final VoidCallback onTap;
  final String label;

  @override
  State<MarketPetStage> createState() => _MarketPetStageState();
}

class _MarketPetStageState extends State<MarketPetStage> with TickerProviderStateMixin {
  late final AnimationController _bob = AnimationController(vsync: this, duration: const Duration(milliseconds: 2800));
  late final AnimationController _hop = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
  late final AnimationController _turn = AnimationController(vsync: this, duration: const Duration(milliseconds: 280), value: 1);
  bool _rm = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _rm = MediaQuery.of(context).disableAnimations;
    if (_rm) {
      _bob
        ..stop()
        ..value = 0;
      _hop
        ..stop()
        ..value = 0;
      _turn.value = 1;
    } else if (!_bob.isAnimating) {
      _bob.repeat();
    }
  }

  @override
  void didUpdateWidget(MarketPetStage old) {
    super.didUpdateWidget(old);
    if (_rm) return;
    if (old.cheer != widget.cheer) _hop.forward(from: 0);
    if (old.view != widget.view) _turn.forward(from: 0);
  }

  @override
  void dispose() {
    _bob.dispose();
    _hop.dispose();
    _turn.dispose();
    super.dispose();
  }

  /// The hop (tryHop): up 22 px by 35%, a little dip past the floor at 70%, back down.
  static double _hopY(double t) {
    double seg(double a, double len) => ((t - a) / len).clamp(0.0, 1.0).toDouble();
    if (t < 0.35) return -22 * Curves.easeOut.transform(seg(0, 0.35));
    if (t < 0.7) return -22 + 24 * Curves.easeIn.transform(seg(0.35, 0.35));
    return 2 - 2 * Curves.easeOut.transform(seg(0.7, 0.3));
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (ctx, b) {
        final w0 = b.maxWidth, h0 = b.maxHeight;
        final art = widget.view == 'back' ? 'back' : 'left';
        final a = marketPetAspect(widget.pet.stage, art);
        final hh = math.max(0.0, math.min(h0, w0 * 0.78 / a));
        final ww = hh * a;
        final rugW = math.min(w0 * 0.64, 260.0);
        final align = marketZoomAlignment(widget.pet.stage, widget.slot, art);
        final zoomed = TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 1, end: widget.zoom ? 1.6 : 1),
          duration: _rm ? Duration.zero : const Duration(milliseconds: 350),
          curve: const Cubic(0.3, 0.8, 0.25, 1),
          builder: (_, s, child) => Transform.scale(scale: s, alignment: align, child: child),
          child: SizedBox(width: ww, height: hh, child: MarketPet(pet: widget.pet, overlays: widget.overlays, view: art, res: 480)),
        );
        final turned = AnimatedBuilder(
          animation: _turn,
          builder: (_, child) => Opacity(opacity: 0.4 + 0.6 * Curves.easeOut.transform(_turn.value), child: child),
          child: marketMirror(zoomed, widget.view == 'right'),
        );
        final body = Stack(clipBehavior: Clip.none, children: [
          Positioned(
            left: (w0 - rugW) / 2,
            width: rugW,
            bottom: -10,
            height: 34,
            child: IgnorePointer(
              child: AnimatedOpacity(
                opacity: widget.zoom ? 0 : 0.9,
                duration: _rm ? Duration.zero : const Duration(milliseconds: 250),
                child: const CustomPaint(painter: _RugPainter()),
              ),
            ),
          ),
          Positioned(left: (w0 - ww) / 2, width: ww, bottom: 0, height: hh, child: turned),
        ]);
        return Semantics(
          button: true,
          label: widget.label,
          excludeSemantics: true,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onTap,
            child: AnimatedBuilder(
              animation: Listenable.merge([_bob, _hop]),
              child: SizedBox.expand(child: body),
              builder: (_, child) {
                var dy = 0.0;
                if (_hop.isAnimating) {
                  dy = _hopY(_hop.value);
                } else if (!widget.zoom && !_rm) {
                  dy = -4 * (0.5 - 0.5 * math.cos(2 * math.pi * _bob.value));
                }
                return Transform.translate(offset: Offset(0, dy), child: child);
              },
            ),
          ),
        );
      });
}

/// A round wood arrow that turns your Evochi (`.try-arrow`).
class _Arrow extends StatelessWidget {
  const _Arrow({required this.left, required this.onTap});
  final bool left;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: left ? 'Turn left' : 'Turn right',
        excludeSemantics: true,
        child: KitPress(
          onTap: onTap,
          builder: (_, down) => AnimatedContainer(
            duration: const Duration(milliseconds: 60),
            width: 44,
            height: 44,
            transform: Matrix4.translationValues(0, down ? 2 : 0, 0),
            decoration: Kit.wood(radius: 22, border: 2.5, width: 300, y: -1, pressed: down, drop: false),
            child: Icon(left ? Icons.chevron_left_rounded : Icons.chevron_right_rounded, color: KitColor.signInk, size: 28, shadows: kitSignShadow),
          ),
        ),
      );
}

/// One of the three view thumbnails at the foot of the stage (`.try-views`).
class _ViewThumb extends StatelessWidget {
  const _ViewThumb({required this.pet, required this.overlays, required this.view, required this.label, required this.selected, required this.onTap});
  final Pet pet;
  final List<String> overlays;
  final String view;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        selected: selected,
        label: '$label view',
        excludeSemantics: true,
        child: KitPress(
          onTap: onTap,
          builder: (_, down) => AnimatedContainer(
            duration: const Duration(milliseconds: 60),
            width: 60,
            height: 60,
            padding: const EdgeInsets.all(2),
            transform: Matrix4.translationValues(0, down ? 1 : 0, 0),
            decoration: KitDecoration(
              base: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: selected ? const [Color(0xFFFFF4D6), Color(0xFFFFE1A1)] : const [Color(0xFFFFFAEE), Color(0xFFF2DCB4)],
                ),
                image: kitGrain,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: selected ? const Color(0xFFC47F1E) : const Color(0xFFA87542), width: 2),
                boxShadow: [
                  if (selected) const BoxShadow(color: KitColor.goldRing, spreadRadius: 3),
                  const BoxShadow(color: Color(0xFF7A5230), offset: Offset(0, 2)),
                ],
              ),
              inset: 2,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(9),
              child: Align(
                alignment: Alignment.bottomCenter,
                child: SizedBox(
                  width: 52,
                  height: 52,
                  child: marketMirror(MarketPet(pet: pet, overlays: overlays, view: view == 'right' ? 'left' : view, res: 160), view == 'right'),
                ),
              ),
            ),
          ),
        ),
      );
}

/// "The Tiny Crown can't be seen from behind." (`.try-note`), once the back view's overlay is known to
/// be empty.
class _HiddenNote extends StatelessWidget {
  const _HiddenNote({required this.stage, required this.id, required this.name});
  final int stage;
  final String id;
  final String name;
  @override
  Widget build(BuildContext context) => FutureBuilder<bool>(
        future: marketHiddenFromBehind(stage, id),
        initialData: marketHiddenKnown(stage, id),
        builder: (_, snap) => snap.data != true
            ? const SizedBox.shrink()
            : Center(
                child: IgnorePointer(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xF0FFF8E6),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFD7B385), width: 1.5),
                      boxShadow: const [BoxShadow(color: Color(0x4D784F28), offset: Offset(0, 2))],
                    ),
                    child: Text(
                      "The $name can't be seen from behind.",
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w800, fontSize: 13, color: KitColor.signInk),
                    ),
                  ),
                ),
              ),
      );
}

/// A red stage curtain down one side of the dressing room.
class _Curtain extends StatelessWidget {
  const _Curtain({required this.left});
  final bool left;
  @override
  Widget build(BuildContext context) => IgnorePointer(child: CustomPaint(painter: _CurtainPainter(left)));
}

class _CurtainPainter extends CustomPainter {
  const _CurtainPainter(this.left);
  final bool left;
  @override
  void paint(Canvas canvas, Size size) {
    const r = Radius.circular(14);
    final box = RRect.fromRectAndCorners(Offset.zero & size, bottomRight: left ? r : Radius.zero, bottomLeft: left ? Radius.zero : r);
    // the folds cast a soft shadow onto the stage
    canvas.drawRRect(
      box.shift(Offset(left ? 2 : -2, 0)),
      Paint()
        ..color = const Color(0x593C0A05)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    canvas.save();
    canvas.clipRRect(box);
    for (var x = 0.0; x < size.width; x += 13) {
      canvas.drawRect(Rect.fromLTWH(x, 0, 6, size.height), Paint()..color = const Color(0xFFA8443A));
      canvas.drawRect(Rect.fromLTWH(x + 6, 0, 4, size.height), Paint()..color = const Color(0xFFC65A4B));
      canvas.drawRect(Rect.fromLTWH(x + 10, 0, 3, size.height), Paint()..color = const Color(0xFF8E3830));
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_CurtainPainter oldDelegate) => oldDelegate.left != left;
}

/// The round rug your Evochi stands on (`.try-rug`): gold, ochre and red rings.
class _RugPainter extends CustomPainter {
  const _RugPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height * 0.45);
    final rx = size.width * 0.707, ry = size.height * 0.55 * 1.414;
    void ring(double f, Color col) => canvas.drawOval(Rect.fromCenter(center: c, width: rx * f * 2, height: ry * f * 2), Paint()..color = col);
    ring(0.65, const Color(0xFFA8443A));
    ring(0.465, const Color(0xFFC47F1E));
    ring(0.345, const Color(0xFFE9B04E));
  }

  @override
  bool shouldRepaint(_RugPainter oldDelegate) => false;
}
