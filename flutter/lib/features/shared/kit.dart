// Evochi game-native kit: windows as crafted props, not app panels. The Flutter side of
// web/src/kit.css (read that file for the reasoning behind every number here).
//
// Materials, painted by tools/ui_textures.py into assets/ui: honey / mid / dark wood planks, parchment
// grain, satchel canvas, and 9-slice window frames (carved wood, plum wood, stitched leather, canvas).
// Hierarchy:
//   WINDOW  sheets, dialogs, the Bag's and the Market's lower sheet, the encounter panel: a carved
//           [FramedWindow] around parchment.
//   CARD    printed card stock ([Kit.card]): grain over a cream-to-parchment gradient, an inner double
//           rule and a hard bottom edge. The content you act on.
//   INSET   a pressed-in parchment panel ([Kit.inset], [KitInsetList]) holding plain rows split by
//           stitched rules: secondary information (finished quests, what's coming next).
//   SLOT    an inset pocket ([Kit.slot]); selected = a gold ring and glow.
//   SIGN    page titles ([WoodPlaque]), section heads ([KitSectionHead]), tabs ([KitTab]), the nav: wood.
// Each screen adds its own material through [KitPage] / [KitScope]: journal, satchel, market, board,
// kitchen, apothecary, binder. Flutter has no inset box-shadows, so [KitDecoration] paints them (lit and
// shaded edges, rings, inner shadows, the gloss strip on buttons) on top of a plain [BoxDecoration].
// Performance: big panels only get plain BoxShadows (never BackdropFilter, ImageFiltered or layers), and
// the textures are decoded at startup ([precacheKitTextures]).

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../app/theme.dart';

// ------------------------------------------------------------------- assets ----
class KitTextures {
  static const woodLight = 'assets/ui/wood_light.png'; // 512x128, tileable plank grain
  static const woodMid = 'assets/ui/wood_mid.png';
  static const woodDark = 'assets/ui/wood_dark.png';
  static const paperGrain = 'assets/ui/paper_grain.png'; // 256x256 brown-alpha overlay
  static const clothWeave = 'assets/ui/cloth_weave.png'; // 128x128 overlay
  static const frameWood = 'assets/ui/frame_wood.png'; // 192x192 9-slice, slice 56, centre transparent
  static const framePlum = 'assets/ui/frame_plum.png';
  static const frameLeather = 'assets/ui/frame_leather.png';
  static const frameCloth = 'assets/ui/frame_cloth.png';

  /// Every frame is sliced 56 px in from each side.
  static const frameSlice = 56.0;
  static const frameCenter = Rect.fromLTRB(56, 56, 136, 136);

  static const all = [woodLight, woodMid, woodDark, paperGrain, clothWeave, frameWood, framePlum, frameLeather, frameCloth];
}

/// Decode the kit's materials up front (web: main.js preloads them), so the first screen switch never
/// paints a card without its grain or a window without its frame.
void precacheKitTextures(BuildContext context) {
  for (final f in KitTextures.all) {
    precacheImage(AssetImage(f), context, onError: (_, __) {});
  }
}

class KitColor {
  static const woodInk = Color(0xFF4A2A14);
  static const woodEdge = Color(0xFF6B3F1E);
  static const woodShadow = Color(0xFF3A2010);
  static const signInk = Color(0xFF3A200E); // dark brown lettering on light wood
  static const lightWood = Color(0xFFD6A066);
  static const midWood = Color(0xFFA8693A);
  static const navWood = Color(0xFF9A5F33);
  static const darkWood = Color(0xFF6E4224);
  static const tabText = Color(0xFFFFF1D8); // cream lettering on mid wood
  static const navText = Color(0xFFFFF0D2);
  static const goldRing = Color(0xFFF7C65C);
  static const plaqueEdge = Color(0xFF7A4512); // the lit, chosen plaque
  static const groove = Color(0xFF4C3324); // progress bar track
  static const leather = Color(0xFF8E4630); // journal bookmark tabs
  static const pageTop = Color(0xFFF9ECD4); // what header plates fade into
  static const plum = Color(0xFF3E2550); // apothecary headings
}

/// Lettering on light wood: dark brown with a lit lower edge.
const kitSignShadow = [Shadow(color: Color(0xB3FFE8C4), offset: Offset(0, 1))];

/// Lettering on mid / dark wood: cream with a dark lower edge.
const kitWoodTextShadow = [Shadow(color: Color(0xA61E0C00), offset: Offset(0, 1))];

// ---------------------------------------------------------------- textures ----
enum KitWood { light, mid, dark }

/// The paper grain, tiled at its own size like `var(--grain) 0 0 / 256px` (fit none: never squeezed
/// into small boxes).
const kitGrain = DecorationImage(image: AssetImage(KitTextures.paperGrain), repeat: ImageRepeat.repeat, fit: BoxFit.none, alignment: Alignment.topLeft);

/// A plank texture tiled [width] logical px wide (the CSS background-size); [y] is its vertical
/// position (-1 top, -0.4 is the web's 30%).
DecorationImage kitWood(KitWood w, {double width = 340, double y = -0.4}) => DecorationImage(
      image: AssetImage(switch (w) {
        KitWood.light => KitTextures.woodLight,
        KitWood.mid => KitTextures.woodMid,
        KitWood.dark => KitTextures.woodDark,
      }),
      repeat: ImageRepeat.repeat,
      fit: BoxFit.none,
      scale: 512 / width,
      alignment: Alignment(-1, y),
    );

/// The satchel canvas weave, tiled [size] logical px.
DecorationImage kitWeave({double size = 64}) =>
    DecorationImage(image: const AssetImage(KitTextures.clothWeave), repeat: ImageRepeat.repeat, fit: BoxFit.none, scale: 128 / size, alignment: Alignment.topLeft);

// ---------------------------------------------------------------- materials ----
/// What a screen is made of (web: `#app[data-screen=...]`).
enum KitMaterial { plain, journal, satchel, market, board, kitchen, apothecary, binder }

/// Tells the cards, section heads and buttons below it which material they sit on.
class KitScope extends InheritedWidget {
  const KitScope({super.key, required this.material, required super.child});
  final KitMaterial material;

  static KitMaterial of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<KitScope>()?.material ?? KitMaterial.plain;

  @override
  bool updateShouldNotify(KitScope oldWidget) => material != oldWidget.material;
}

/// A screen body on its material: the [KitScope], and (unless [paper] is false, for scene screens) the
/// parchment page behind it.
class KitPage extends StatelessWidget {
  const KitPage({super.key, required this.material, required this.child, this.paper = true});
  final KitMaterial material;
  final Widget child;
  final bool paper;
  @override
  Widget build(BuildContext context) => KitScope(
        material: material,
        child: paper ? DecoratedBox(decoration: Kit.page(material), child: SizedBox.expand(child: child)) : child,
      );
}

/// A card stock: its gradient, its edge and bottom bevel, and the inner rule's colour.
class KitPaper {
  const KitPaper(this.top, this.bottom, this.edge, this.bevel, this.rule, {this.depth = 3});
  final Color top;
  final Color bottom;
  final Color edge;
  final Color bevel;
  final Color rule;
  final double depth; // the hard bottom edge

  static const cream = KitPaper(Color(0xFFFFF8E8), Color(0xFFF6E6C8), Color(0xFFCFA676), Color(0xFFB4874F), Color(0x61C49660));
  static const solid = KitPaper(Color(0xFFFFFAEE), Color(0xFFF8EBD2), Color(0xFFCFA676), Color(0xFFB4874F), Color(0x61C49660));
  static const lore = KitPaper(Color(0xFFFFF6E2), Color(0xFFF1DFBC), Color(0xFFCFA676), Color(0xFFB4874F), Color(0x61C49660));
  static const lavender = KitPaper(Color(0xFFFBF6FF), Color(0xFFEADFF5), Color(0xFF9C7DB8), Color(0xFF6E4E8C), Color(0x598C64BE));
  static const hollow = KitPaper(Color(0xFFFCF8FF), Color(0xFFEEE3FA), Color(0xFF9C7DB8), Color(0xFF6E4E8C), Color(0x598C64BE));
  static const meadow = KitPaper(Color(0xFFF6FBEE), Color(0xFFE3F0CF), Color(0xFF9CC07A), Color(0xFF6E9A4E), Color(0x4D7AA050));
  static const nameplate = KitPaper(Color(0xFFFFF8E8), Color(0xFFF6E6C8), KitColor.woodEdge, KitColor.woodEdge, Color(0x61C49660), depth: 4);
  static const plate = KitPaper(Color(0xFFFFF9EA), Color(0xFFF4E3C2), KitColor.woodEdge, KitColor.woodEdge, Color(0x00000000), depth: 4);
  static const encounter = KitPaper(Color(0xFFFBF1DC), Color(0xFFF2E0BF), Color(0xFFCFA676), Color(0xFFB4874F), Color(0x61C49660));

  /// A tinted card ([GameCard.color]): the tint on top, a touch deeper below, cream-stock edges.
  factory KitPaper.tint(Color c) {
    final top = c.withAlpha(255);
    return KitPaper(top, Color.lerp(top, const Color(0xFF8A6A50), 0.08)!, cream.edge, cream.bevel, cream.rule);
  }

  /// The card stock a material prints on.
  static KitPaper of(KitMaterial m) => m == KitMaterial.apothecary ? lavender : cream;
}

// --------------------------------------------------------------- decoration ----
/// An inset band: `inset 0 Npx 0 color` (a lit top or shaded bottom edge) or `inset 0 0 0 Npx color`
/// (a ring), [size] px wide.
class KitBand {
  const KitBand(this.size, this.color);
  final double size;
  final Color color;
  @override
  bool operator ==(Object other) => other is KitBand && other.size == size && other.color == color;
  @override
  int get hashCode => Object.hash(size, color);
}

/// A [BoxDecoration] plus the inset effects CSS draws with inset box-shadows and pseudo-elements, all
/// painted under the child and inside the border ([inset] px in): a lit [top] edge, a shaded [bottom]
/// edge, the double rule ([rule] under [ring]), a soft inner [shadow], a [left] margin rule, a dashed
/// [stitch], the button gloss strip ([glossTop] to [glossBottom]) and its [dot], and a bar fill's
/// [shine].
class KitDecoration extends Decoration {
  const KitDecoration({
    required this.base,
    this.inset = 0,
    this.top,
    this.bottom,
    this.ring,
    this.rule,
    this.shadow,
    this.left,
    this.stitch,
    this.glossTop,
    this.glossBottom = const Color(0x14FFFFFF),
    this.glossSmall = false,
    this.dot,
    this.shine,
  });

  final BoxDecoration base;
  final double inset;
  final KitBand? top;
  final KitBand? bottom;
  final KitBand? ring;
  final KitBand? rule;
  final BoxShadow? shadow;
  final KitBand? left;
  final KitBand? stitch; // size = how far in from the outer edge
  final Color? glossTop;
  final Color glossBottom;
  final bool glossSmall;
  final Color? dot;
  final Color? shine;

  @override
  EdgeInsetsGeometry get padding => base.padding;

  @override
  bool get isComplex => true;

  @override
  bool hitTest(Size size, Offset position, {TextDirection? textDirection}) => base.hitTest(size, position, textDirection: textDirection);

  // Container(clipBehavior: ...) clips to this
  @override
  Path getClipPath(Rect rect, TextDirection textDirection) => base.getClipPath(rect, textDirection);

  @override
  Decoration? lerpFrom(Decoration? a, double t) => a is KitDecoration ? KitDecoration.lerp(a, this, t) : null;

  @override
  Decoration? lerpTo(Decoration? b, double t) => b is KitDecoration ? KitDecoration.lerp(this, b, t) : null;

  /// The box lerps; the effects switch halfway (they are only a few px).
  static KitDecoration lerp(KitDecoration a, KitDecoration b, double t) {
    final o = t < 0.5 ? a : b;
    return KitDecoration(
      base: BoxDecoration.lerp(a.base, b.base, t)!,
      inset: ui.lerpDouble(a.inset, b.inset, t)!,
      top: o.top,
      bottom: o.bottom,
      ring: o.ring,
      rule: o.rule,
      shadow: o.shadow,
      left: o.left,
      stitch: o.stitch,
      glossTop: a.glossTop != null && b.glossTop != null ? Color.lerp(a.glossTop, b.glossTop, t) : o.glossTop,
      glossBottom: Color.lerp(a.glossBottom, b.glossBottom, t)!,
      glossSmall: o.glossSmall,
      dot: o.dot,
      shine: o.shine,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is KitDecoration &&
      other.base == base &&
      other.inset == inset &&
      other.top == top &&
      other.bottom == bottom &&
      other.ring == ring &&
      other.rule == rule &&
      other.shadow == shadow &&
      other.left == left &&
      other.stitch == stitch &&
      other.glossTop == glossTop &&
      other.glossBottom == glossBottom &&
      other.glossSmall == glossSmall &&
      other.dot == dot &&
      other.shine == shine;

  @override
  int get hashCode => Object.hash(base, inset, top, bottom, ring, rule, shadow, left, stitch, glossTop, glossBottom, glossSmall, dot, shine);

  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) => _KitPainter(this, base.createBoxPainter(onChanged), onChanged);
}

class _KitPainter extends BoxPainter {
  _KitPainter(this.d, this.inner, VoidCallback? onChanged) : super(onChanged);
  final KitDecoration d;
  final BoxPainter inner;

  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration configuration) {
    inner.paint(canvas, offset, configuration);
    final size = configuration.size;
    if (size == null || size.isEmpty) return;
    final rect = offset & size;
    final outer = (d.base.borderRadius?.resolve(configuration.textDirection) ?? BorderRadius.zero).toRRect(rect);
    final box = outer.deflate(d.inset);
    if (box.width <= 0 || box.height <= 0) return;

    // a soft inset shadow: the outside of the box, offset and blurred, seen through the box
    final s = d.shadow;
    if (s != null) {
      canvas.save();
      canvas.clipRRect(box);
      final hole = box.shift(s.offset).deflate(s.spreadRadius);
      final path = Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(box.outerRect.inflate(s.blurRadius * 2 + s.offset.distance + 4))
        ..addRRect(hole);
      final paint = Paint()..color = s.color;
      if (s.blurRadius > 0) paint.maskFilter = MaskFilter.blur(BlurStyle.normal, s.blurSigma);
      canvas.drawPath(path, paint);
      canvas.restore();
    }

    // lit top / shaded bottom edges: the box minus itself shifted
    void edge(KitBand? b, double dy) {
      if (b == null || b.size <= 0) return;
      canvas.save();
      canvas.clipRRect(box);
      canvas.drawPath(
        Path()
          ..fillType = PathFillType.evenOdd
          ..addRRect(box)
          ..addRRect(box.shift(Offset(0, dy))),
        Paint()..color = b.color,
      );
      canvas.restore();
    }

    edge(d.top, d.top?.size ?? 0);
    edge(d.bottom, -(d.bottom?.size ?? 0));

    // rings: the rule first, the light ring over it (the CSS order)
    void ring(KitBand? b) {
      if (b == null || b.size <= 0 || box.width <= b.size * 2 || box.height <= b.size * 2) return;
      canvas.drawPath(
        Path()
          ..fillType = PathFillType.evenOdd
          ..addRRect(box)
          ..addRRect(box.deflate(b.size)),
        Paint()..color = b.color,
      );
    }

    ring(d.rule);
    ring(d.ring);

    // a margin rule over the left edge (border-left: 6px)
    final l = d.left;
    if (l != null) {
      canvas.save();
      canvas.clipRRect(outer);
      canvas.drawRect(Rect.fromLTWH(outer.left, outer.top, l.size, outer.height), Paint()..color = l.color);
      canvas.restore();
    }

    // a dashed stitch line (outline: dashed; outline-offset: -6px)
    final st = d.stitch;
    if (st != null && outer.width > st.size * 2 && outer.height > st.size * 2) {
      _dashPath(
        canvas,
        Path()..addRRect(outer.deflate(st.size)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = st.color,
        4,
        3,
      );
    }

    // the gloss strip over the top ~42%, under the label
    final gt = d.glossTop;
    if (gt != null) {
      final side = d.glossSmall ? 6.0 : 7.0;
      final g = Rect.fromLTWH(box.left + side, box.top + (d.glossSmall ? 2 : 3), box.width - side * 2, box.height * (d.glossSmall ? 0.40 : 0.42));
      if (g.width > 4 && g.height > 2) {
        final rt = math.min(9.0, g.height / 2);
        final rb = Radius.elliptical(math.min(14.0, g.width / 2), math.min(8.0, g.height / 2));
        // kept inside the box: on a round button the strip's corners would show past the circle
        canvas.save();
        canvas.clipRRect(box.deflate(1));
        canvas.drawRRect(
          RRect.fromRectAndCorners(g, topLeft: Radius.circular(rt), topRight: Radius.circular(rt), bottomLeft: rb, bottomRight: rb),
          Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [gt, d.glossBottom]).createShader(g),
        );
        canvas.restore();
      }
    }
    final dot = d.dot;
    if (dot != null && box.width > 40) canvas.drawCircle(Offset(box.right - 12.5, box.top + 10.5), 3.5, Paint()..color = dot);

    // a progress fill's highlight streak
    final sh = d.shine;
    if (sh != null && box.width > 10 && box.height > 6) {
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(box.left + 4, box.top + 2, box.width - 8, 3), const Radius.circular(2)), Paint()..color = sh);
    }
  }

  @override
  void dispose() {
    inner.dispose();
    super.dispose();
  }
}

void _dashPath(Canvas canvas, Path path, Paint paint, double dash, double gap) {
  for (final m in path.computeMetrics()) {
    var t = 0.0;
    while (t < m.length) {
      canvas.drawPath(m.extractPath(t, math.min(t + dash, m.length)), paint);
      t += dash + gap;
    }
  }
}

// ------------------------------------------------------------------- buttons ----
/// A button's colours: its gradient, outline, hard bottom edge, inner shade, drop shadow, the pressed
/// gradient and inner shadow, and its lettering.
class KitButtonPalette {
  const KitButtonPalette({
    required this.colors,
    this.stops,
    required this.border,
    required this.edge,
    this.shade,
    this.drop,
    required this.pressed,
    required this.pressShade,
    this.fg = EvochiColor.ink,
    this.textShadow = const Color(0x59FFFFFF),
    this.glossTop = const Color(0x9EFFFFFF),
    this.glossBottom = const Color(0x14FFFFFF),
    this.dot = const Color(0xD9FFFFFF),
    this.glow,
    this.grain = false,
  });
  final List<Color> colors;
  final List<double>? stops;
  final Color border;
  final Color edge;
  final Color? shade;
  final Color? drop;
  final List<Color> pressed;
  final Color pressShade;
  final Color fg;
  final Color? textShadow;
  final Color? glossTop;
  final Color glossBottom;
  final Color? dot;
  final Color? glow;
  final bool grain;

  static const gold = KitButtonPalette(
    colors: [Color(0xFFFFE5A2), Color(0xFFF9CA70), Color(0xFFF4B84E), Color(0xFFE9A541)],
    stops: [0, 0.38, 0.7, 1],
    border: Color(0xFF8A5414),
    edge: Color(0xFF6E3F0E),
    shade: Color(0x80AA6419),
    drop: Color(0x405A320A),
    pressed: [Color(0xFFF7D58A), Color(0xFFE0A13E)],
    pressShade: Color(0x59783C0A),
  );
  static const green = KitButtonPalette(
    colors: [Color(0xFFC6E59C), Color(0xFFA5D27A), Color(0xFF82B75E)],
    stops: [0, 0.4, 1],
    border: Color(0xFF3B6E28),
    edge: Color(0xFF2C5520),
    shade: Color(0x733C6E28),
    drop: Color(0x40285014),
    pressed: [Color(0xFFA9D57E), Color(0xFF74A853)],
    pressShade: Color(0x591E4614),
    textShadow: Color(0x66FFFFFF),
  );
  static const cream = KitButtonPalette(
    colors: [Color(0xFFFFF8E8), Color(0xFFF3E1C0), Color(0xFFE9D2A8)],
    stops: [0, 0.7, 1],
    border: Color(0xFF8F6A42),
    edge: Color(0xFF7A5A36),
    shade: Color(0x59AA8250),
    drop: Color(0x2E503719),
    pressed: [Color(0xFFF1DDB8), Color(0xFFE5CC9E)],
    pressShade: Color(0x4D6E5028),
    glossTop: Color(0xB3FFFFFF),
    glossBottom: Color(0x00FFFFFF),
    dot: Color(0xE6FFFFFF),
    grain: true,
  );
  static const danger = KitButtonPalette(
    colors: [Color(0xFFF4A193), Color(0xFFD85F51)],
    border: Color(0xFF7E2A22),
    edge: Color(0xFF62201A),
    shade: Color(0x668C281E),
    drop: Color(0x385A1E14),
    pressed: [Color(0xFFE48C7E), Color(0xFFC4503F)],
    pressShade: Color(0x595A1E14),
    fg: Colors.white,
    textShadow: Color(0x33000000),
  );

  /// The Apothecary's Brew: plum with a violet glow.
  static const plum = KitButtonPalette(
    colors: [Color(0xFFD6B8F2), Color(0xFFA983D6), Color(0xFF8358B8)],
    stops: [0, 0.45, 1],
    border: Color(0xFF4E2E6C),
    edge: Color(0xFF3E2258),
    shade: Color(0x66461E6E),
    glow: Color(0x8CAA78F0),
    pressed: [Color(0xFFBF9BE6), Color(0xFF7A4FB0)],
    pressShade: Color(0x59461E6E),
    fg: Colors.white,
    textShadow: Color(0x80280A3C),
  );
  static const disabled = KitButtonPalette(
    colors: [Color(0xFFE6D5BC), Color(0xFFE6D5BC)],
    border: Color(0xFFB29A7E),
    edge: Color(0xFFB29A7E),
    pressed: [Color(0xFFE6D5BC), Color(0xFFE6D5BC)],
    pressShade: Color(0x26644628),
    fg: Color(0xFF7E7166),
    textShadow: null,
    glossTop: null,
    dot: null,
  );
}

// ------------------------------------------------------------- the factories ----
class Kit {
  /// Printed card stock (`.card`): grain over the paper's gradient, a 2 px edge, the inner double rule,
  /// a hard bottom edge and a soft drop. [flat] drops the inner rule (place cards); [rule] adds a 6 px
  /// margin rule on the left (journal entries, recipes).
  static KitDecoration card({KitPaper paper = KitPaper.cream, double radius = 14, bool highlight = false, Color? rule, bool flat = false}) {
    final edge = highlight ? const Color(0xFFE2A93E) : paper.edge;
    final bevel = highlight ? const Color(0xFFC0852A) : paper.bevel;
    return KitDecoration(
      base: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [paper.top, paper.bottom]),
        image: kitGrain,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: edge, width: 2),
        boxShadow: [
          const BoxShadow(color: Color(0x2946280F), blurRadius: 14, offset: Offset(0, 7)),
          if (highlight) const BoxShadow(color: Color(0x80FFC850), blurRadius: 12),
          BoxShadow(color: bevel, offset: Offset(0, paper.depth)),
        ],
      ),
      inset: 2,
      rule: flat || paper.rule == const Color(0x00000000) ? null : KitBand(3.5, paper.rule),
      ring: flat ? null : const KitBand(2, Color(0xBFFFFCF0)),
      left: rule == null ? null : KitBand(6, rule),
    );
  }

  /// A recessed panel (`.card.inset`): grain on deeper parchment, an inner shadow, a lit lip below.
  static KitDecoration inset({double radius = 12, Color color = const Color(0xFFF6E7CB), Color edge = const Color(0xFFD7B385)}) => KitDecoration(
        base: BoxDecoration(
          color: color,
          image: kitGrain,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: edge, width: 1.5),
          boxShadow: const [BoxShadow(color: Color(0xB3FFFFFF), offset: Offset(0, 1))],
        ),
        inset: 1.5,
        shadow: const BoxShadow(color: Color(0x296E461E), blurRadius: 6, offset: Offset(0, 3)),
        bottom: const KitBand(1, Color(0x99FFFFFF)),
      );

  /// A light-wood sign or square (`.place-title`, `.back-btn`, `.steps-card`, price tags): planks, a dark
  /// outline, a lit top edge, a shaded bottom edge and a hard [edge] below; [pressed] sinks it.
  static KitDecoration wood({
    double radius = 12,
    double border = 2.5,
    double width = 340,
    double y = -0.4,
    double edge = 3,
    bool pressed = false,
    bool drop = true,
    Color borderColor = KitColor.woodInk,
  }) =>
      KitDecoration(
        base: BoxDecoration(
          color: KitColor.lightWood,
          image: kitWood(KitWood.light, width: width, y: y),
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: borderColor, width: border),
          boxShadow: [
            if (drop && !pressed) const BoxShadow(color: Color(0x38281405), blurRadius: 10, offset: Offset(0, 5)),
            BoxShadow(color: KitColor.woodShadow, offset: Offset(0, pressed ? 1 : edge)),
          ],
        ),
        inset: border,
        top: KitBand(2, pressed ? const Color(0x80FFEECD) : const Color(0xA6FFEECD)),
        bottom: pressed ? null : const KitBand(3, Color(0x5978461E)),
      );

  /// A parchment chip with a wood edge (`.loc-pill`, `.preview-tag`, map pins, `.icon-btn`).
  static KitDecoration parchment({
    double radius = 10,
    Color edge = KitColor.woodEdge,
    double border = 2,
    double depth = 3,
    bool drop = true,
    List<Color> colors = const [Color(0xFFFFF8E6), Color(0xFFF1DDB8)],
  }) =>
      KitDecoration(
        base: BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: colors),
          image: kitGrain,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: edge, width: border),
          boxShadow: [
            if (drop) const BoxShadow(color: Color(0x33321C0A), blurRadius: 10, offset: Offset(0, 5)),
            BoxShadow(color: edge, offset: Offset(0, depth)),
          ],
        ),
        inset: border,
        top: const KitBand(1.5, Color(0xFFFFFDF5)),
      );

  /// An inset pocket (`.tile`): an inner shadow, a 2 px edge; [selected] = a gold ring and glow. [cloth]
  /// is the satchel's: canvas weave and a dashed stitch 6 px in.
  static KitDecoration slot({bool selected = false, double radius = 13, bool cloth = false}) => KitDecoration(
        base: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0, -0.24),
            radius: 0.85,
            colors: selected ? const [Color(0xFFFFFCEF), Color(0xFFFFE7A8)] : (cloth ? const [Color(0xFFFBF0DA), Color(0xFFE9D3AC)] : const [Color(0xFFFFF9E8), Color(0xFFF0DBB4)]),
          ),
          image: cloth ? kitWeave(size: 40) : kitGrain,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: selected ? const Color(0xFFC47F1E) : (cloth ? const Color(0xFF8C6A44) : const Color(0xFFB98A55)), width: 2),
          boxShadow: selected
              ? const [BoxShadow(color: Color(0xA6FFBE46), blurRadius: 14), BoxShadow(color: KitColor.goldRing, spreadRadius: 3)]
              : const [BoxShadow(color: Color(0xCCFFF6E5), offset: Offset(0, 2))],
        ),
        inset: 2,
        shadow: selected ? const BoxShadow(color: Color(0x33965A14), blurRadius: 5, offset: Offset(0, 2)) : const BoxShadow(color: Color(0x386E461E), blurRadius: 7, offset: Offset(0, 3)),
        bottom: selected ? null : const KitBand(2, Color(0x8CFFFFFF)),
        stitch: cloth ? KitBand(6, selected ? const Color(0xB3C47F1E) : const Color(0x8C6E4B28)) : null,
      );

  /// A picture well inside a card (`.detail .pic`): gold-edged, softly sunk.
  static KitDecoration well({double radius = 12, Color edge = const Color(0xFFC47F1E), List<Color> colors = const [Color(0xFFFFFCEF), Color(0xFFFBE7BE)], Color lip = const Color(0xFFE7B65A), Color shade = const Color(0x33965A14), bool round = false}) => KitDecoration(
        base: BoxDecoration(
          gradient: RadialGradient(center: const Alignment(0, -0.2), radius: 0.8, colors: colors),
          image: kitGrain,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: edge, width: round ? 2 : 2.5),
          boxShadow: [BoxShadow(color: lip, offset: const Offset(0, 2))],
        ),
        inset: round ? 2 : 2.5,
        shadow: BoxShadow(color: shade, blurRadius: 6, offset: const Offset(0, 2)),
      );

  /// A game button (`.btn`) in [p]: chunky outline, the gloss strip under the label, a hard edge that
  /// shrinks as it sinks 3 px when [pressed].
  static KitDecoration button(KitButtonPalette p, {bool pressed = false, bool small = false, double radius = 13, double border = 2.5, bool dot = true, bool disabled = false, double depth = 4}) {
    final down = pressed && !disabled;
    final gloss = disabled ? null : p.glossTop;
    return KitDecoration(
      base: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: down ? p.pressed : p.colors, stops: down ? null : p.stops),
        image: p.grain && !disabled ? kitGrain : null,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: p.border, width: border),
        boxShadow: [
          if (!down && !disabled && p.drop != null) BoxShadow(color: p.drop!, blurRadius: 12, offset: const Offset(0, 7)),
          if (!disabled && p.glow != null) BoxShadow(color: p.glow!, blurRadius: 14),
          BoxShadow(color: p.edge, offset: Offset(0, disabled ? 2 : (down ? 1 : depth))),
        ],
      ),
      inset: border,
      bottom: down || disabled || p.shade == null ? null : KitBand(3, p.shade!),
      shadow: down || disabled ? BoxShadow(color: p.pressShade, blurRadius: disabled ? 3 : 4, offset: const Offset(0, 2)) : null,
      glossTop: gloss == null ? null : (down ? Color.lerp(const Color(0x00FFFFFF), gloss, 0.45) : gloss),
      glossBottom: p.glossBottom,
      glossSmall: small,
      dot: small || !dot || disabled || down ? null : p.dot,
    );
  }

  /// A tab plaque (`.tab`): wood, leather (the journal) or canvas (the satchel); the chosen one turns
  /// parchment-gold with a gold ring.
  static KitDecoration tab({required bool selected, KitTabStyle style = KitTabStyle.wood, BorderRadius radius = const BorderRadius.vertical(top: Radius.circular(11), bottom: Radius.circular(7))}) {
    if (selected) {
      return KitDecoration(
        base: BoxDecoration(
          gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFFFF7DC), Color(0xFFFFE19A)]),
          image: kitGrain,
          borderRadius: radius,
          border: Border.all(color: KitColor.plaqueEdge, width: 2),
          boxShadow: const [
            BoxShadow(color: Color(0x8CFFC450), blurRadius: 14),
            BoxShadow(color: KitColor.plaqueEdge, offset: Offset(0, 4)),
            BoxShadow(color: KitColor.goldRing, spreadRadius: 2),
          ],
        ),
        inset: 2,
        top: const KitBand(2, Color(0xFFFFFDF2)),
      );
    }
    return switch (style) {
      KitTabStyle.leather => KitDecoration(
          base: BoxDecoration(
            gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFA05B42), Color(0xFF7D3E2A)]),
            borderRadius: radius,
            border: Border.all(color: const Color(0xFF3E1E12), width: 2),
            boxShadow: const [BoxShadow(color: Color(0xFF2E140A), offset: Offset(0, 3))],
          ),
          inset: 2,
          rule: const KitBand(3.5, Color(0x8CF1D9A8)),
          ring: const KitBand(2, KitColor.leather),
        ),
      KitTabStyle.cloth => KitDecoration(
          base: BoxDecoration(
            color: const Color(0xFF8A6440),
            image: kitWeave(size: 48),
            borderRadius: radius,
            border: Border.all(color: const Color(0xFF3E2A16), width: 2),
            boxShadow: const [BoxShadow(color: Color(0xFF2E1E0E), offset: Offset(0, 3))],
          ),
          inset: 2,
          rule: const KitBand(3.5, Color(0x73FFE6BE)),
          ring: const KitBand(2, Color(0xFF8A6440)),
        ),
      KitTabStyle.wood => KitDecoration(
          base: BoxDecoration(
            color: KitColor.midWood,
            image: kitWood(KitWood.mid, width: 300),
            borderRadius: radius,
            border: Border.all(color: KitColor.woodInk, width: 2),
            boxShadow: const [BoxShadow(color: KitColor.woodShadow, offset: Offset(0, 3))],
          ),
          inset: 2,
          top: const KitBand(2, Color(0x66FFD6A0)),
          bottom: const KitBand(3, Color(0x4D281204)),
        ),
    };
  }

  /// The bottom nav (`.nav`): a carved mid-wood bar.
  static KitDecoration navBar() => KitDecoration(
        base: BoxDecoration(
          color: KitColor.navWood,
          image: kitWood(KitWood.mid, width: 360, y: -1),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: KitColor.woodInk, width: 2.5),
          boxShadow: const [BoxShadow(color: Color(0x59281405), blurRadius: 22, offset: Offset(0, 9)), BoxShadow(color: KitColor.woodShadow, offset: Offset(0, 4))],
        ),
        inset: 2.5,
        top: const KitBand(2, Color(0x73FFD6A0)),
        bottom: const KitBand(4, Color(0x4D281204)),
      );

  /// The current nav item: a raised parchment-gold plaque.
  static KitDecoration navCurrent() => KitDecoration(
        base: BoxDecoration(
          gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFFFF7DA), Color(0xFFFFDF96)]),
          image: kitGrain,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: KitColor.woodInk, width: 2.5),
          boxShadow: const [BoxShadow(color: Color(0xA6FFC850), blurRadius: 16), BoxShadow(color: KitColor.woodInk, offset: Offset(0, 4))],
        ),
        inset: 2.5,
        top: const KitBand(2, Color(0xFFFFFDF2)),
      );

  /// The EvoCoin pill: dark wood.
  static KitDecoration coinPill() => KitDecoration(
        base: BoxDecoration(
          color: KitColor.darkWood,
          image: kitWood(KitWood.dark, width: 260, y: -1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFF2E180A), width: 2),
          boxShadow: const [BoxShadow(color: Color(0x4D1E0F05), blurRadius: 8, offset: Offset(0, 4)), BoxShadow(color: Color(0xFF2E180A), offset: Offset(0, 2))],
        ),
        inset: 2,
        top: const KitBand(1.5, Color(0x4DFFD296)),
      );

  /// A progress bar's track (`.bar`): a dark carved groove with a [ring] and a lit lip below.
  static KitDecoration groove(double radius, {Color ring = const Color(0xFF7A5032)}) => KitDecoration(
        base: BoxDecoration(
          color: KitColor.groove,
          borderRadius: BorderRadius.circular(radius),
          boxShadow: [const BoxShadow(color: Color(0xB3FFF4DC), offset: Offset(0, 1.5), spreadRadius: 2), BoxShadow(color: ring, spreadRadius: 2)],
        ),
        shadow: const BoxShadow(color: Color(0x73000000), blurRadius: 3, offset: Offset(0, 2)),
      );

  /// A progress bar's fill: glossy, with a highlight streak.
  static KitDecoration barFill(List<Color> colors, double radius, {List<double>? stops}) => KitDecoration(
        base: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: colors, stops: stops),
        ),
        top: const KitBand(2, Color(0x8CFFFFFF)),
        bottom: const KitBand(2, Color(0x2E783C0A)),
        shine: const Color(0x73FFFFFF),
      );

  /// A toast: parchment with a dark edge ([edge]) and a hard bottom edge ([depth]).
  static KitDecoration toast(List<Color> colors, Color edge, Color depth) => KitDecoration(
        base: BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: colors),
          image: kitGrain,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: edge, width: 2.5),
          boxShadow: [const BoxShadow(color: Color(0x40000000), blurRadius: 18, offset: Offset(0, 8)), BoxShadow(color: depth, offset: const Offset(0, 3))],
        ),
        inset: 2.5,
        top: const KitBand(1.5, Color(0xFFFFFDF5)),
      );

  /// The page behind a screen: grain over its material's parchment.
  static BoxDecoration page(KitMaterial m) {
    final (a, b) = switch (m) {
      KitMaterial.journal => (const Color(0xFFFBF0DA), const Color(0xFFF2DFBD)),
      KitMaterial.kitchen => (const Color(0xFFFBEBD2), const Color(0xFFF1D7B0)),
      KitMaterial.apothecary => (const Color(0xFFF3ECFA), const Color(0xFFE2D3F0)),
      _ => (const Color(0xFFFAEED8), const Color(0xFFF2DFBE)),
    };
    return BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [a, b]), image: kitGrain);
  }

  /// The sheet inside a window frame: parchment (or the satchel's canvas with [weave]).
  static BoxDecoration sheet({List<Color> colors = const [Color(0xFFFFF8E8), Color(0xFFF4E1BF)], bool weave = false, double radius = 6}) => BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: colors),
        image: weave ? kitWeave(size: 64) : kitGrain,
        borderRadius: BorderRadius.circular(radius),
      );
}

// ------------------------------------------------------------------ windows ----
enum FrameVariant { wood, plum, leather, cloth }

String _frameAsset(FrameVariant v) => switch (v) {
      FrameVariant.wood => KitTextures.frameWood,
      FrameVariant.plum => KitTextures.framePlum,
      FrameVariant.leather => KitTextures.frameLeather,
      FrameVariant.cloth => KitTextures.frameCloth,
    };

/// A 9-slice window frame drawn [border] logical px wide (the 56 px slices scaled down). [openBottom]
/// leaves the bottom edge off, the sides running down to the bottom (the encounter panel).
class KitFrame extends StatefulWidget {
  const KitFrame({super.key, this.variant = FrameVariant.wood, this.border = 14, this.openBottom = false});
  final FrameVariant variant;
  final double border;
  final bool openBottom;
  @override
  State<KitFrame> createState() => _KitFrameState();
}

class _KitFrameState extends State<KitFrame> {
  ImageStream? _stream;
  ImageInfo? _info;
  late final ImageStreamListener _listener = ImageStreamListener(_onImage);

  void _onImage(ImageInfo info, bool synchronousCall) {
    if (!mounted) {
      info.dispose();
      return;
    }
    setState(() {
      _info?.dispose();
      _info = info;
    });
  }

  void _resolve() {
    final stream = AssetImage(_frameAsset(widget.variant)).resolve(createLocalImageConfiguration(context));
    if (_stream != null && stream.key == _stream!.key) return;
    _stream?.removeListener(_listener);
    _stream = stream;
    stream.addListener(_listener);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(KitFrame oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.variant != widget.variant) _resolve();
  }

  @override
  void dispose() {
    _stream?.removeListener(_listener);
    _info?.dispose();
    _info = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CustomPaint(painter: _FramePainter(_info?.image, widget.border, widget.openBottom));
}

class _FramePainter extends CustomPainter {
  _FramePainter(this.image, this.border, this.openBottom);
  final ui.Image? image;
  final double border;
  final bool openBottom;

  @override
  void paint(Canvas canvas, Size size) {
    final img = image;
    if (img == null || size.isEmpty || border <= 0) return;
    final k = border / KitTextures.frameSlice; // logical px per image px
    // with an open bottom the frame runs past the bottom edge, so its lower corners are cut away
    final h = openBottom ? size.height + border + 1 : size.height;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.scale(k);
    canvas.drawImageNine(
      img,
      KitTextures.frameCenter,
      Rect.fromLTWH(0, 0, size.width / k, h / k),
      Paint()
        ..filterQuality = FilterQuality.medium
        ..isAntiAlias = true,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_FramePainter oldDelegate) => oldDelegate.image != image || oldDelegate.border != border || oldDelegate.openBottom != openBottom;
}

/// A WINDOW: [child] on a parchment [sheet] inside a carved 9-slice frame [border] px wide.
/// [padding] is inside the frame. The sheet tucks under the frame's band, so no gap shows.
class FramedWindow extends StatelessWidget {
  const FramedWindow({
    super.key,
    required this.child,
    this.variant = FrameVariant.wood,
    this.border = 14,
    this.padding = const EdgeInsets.all(12),
    this.sheet,
    this.openBottom = false,
    this.shadow = const BoxShadow(color: Color(0x4D000000), blurRadius: 18, offset: Offset(0, 6)),
  });
  final Widget child;
  final FrameVariant variant;
  final double border;
  final EdgeInsets padding;
  final Decoration? sheet;
  final bool openBottom;
  final BoxShadow? shadow;

  @override
  Widget build(BuildContext context) {
    final b = border;
    final under = b * 0.7;
    final r = Radius.circular(b * 0.85);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: openBottom ? BorderRadius.vertical(top: r) : BorderRadius.all(r),
        boxShadow: shadow == null ? null : [shadow!],
      ),
      // passthrough: the content keeps the parent's min sizes (a dialog's 280 px), as a plain Padding would
      child: Stack(clipBehavior: Clip.none, fit: StackFit.passthrough, children: [
        Positioned.fill(left: under, top: under, right: under, bottom: openBottom ? 0 : under, child: DecoratedBox(decoration: sheet ?? Kit.sheet())),
        Padding(padding: EdgeInsets.fromLTRB(b + padding.left, b + padding.top, b + padding.right, (openBottom ? 0 : b) + padding.bottom), child: child),
        Positioned.fill(child: IgnorePointer(child: KitFrame(variant: variant, border: b, openBottom: openBottom))),
      ]),
    );
  }
}

/// A dialog in a carved frame (`.scrim.center .modal`).
class KitDialog extends StatelessWidget {
  const KitDialog({super.key, required this.child, this.padding = const EdgeInsets.all(14), this.variant = FrameVariant.wood});
  final Widget child;
  final EdgeInsets padding;
  final FrameVariant variant;
  @override
  Widget build(BuildContext context) => Dialog(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
        child: FramedWindow(
          variant: variant,
          padding: padding,
          shadow: const BoxShadow(color: Color(0x59000000), blurRadius: 24, offset: Offset(0, 10)),
          child: child,
        ),
      );
}

// -------------------------------------------------------------------- signs ----
/// A little brass nail (the plaques' corners).
class BrassNail extends StatelessWidget {
  const BrassNail({super.key, this.size = 6});
  final double size;
  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            center: Alignment(-0.24, -0.3),
            radius: 0.9,
            colors: [Color(0xFFFFF1C4), Color(0xFFFFF1C4), Color(0xFFE2B04E), Color(0xFF9A6A1E), Color(0xFF5A3A10)],
            stops: [0, 0.18, 0.40, 0.72, 1],
          ),
          boxShadow: [BoxShadow(color: Color(0x99FFE6B4), offset: Offset(0, 1))],
        ),
      );
}

/// A nailed wooden title plaque (`.place-title`): light wood, a dark outline, brass nails left and right.
class WoodPlaque extends StatelessWidget {
  const WoodPlaque({super.key, required this.child, this.height = 42, this.nails = true, this.padding = const EdgeInsets.symmetric(horizontal: 14)});
  final Widget child;
  final double height;
  final bool nails;
  final EdgeInsets padding;
  @override
  Widget build(BuildContext context) => Container(
        height: height,
        decoration: Kit.wood(radius: 12),
        child: Stack(alignment: Alignment.center, children: [
          Padding(padding: padding, child: child),
          if (nails) ...[
            const Positioned(left: 4, top: 0, bottom: 0, child: Center(child: BrassNail())),
            const Positioned(right: 4, top: 0, bottom: 0, child: Center(child: BrassNail())),
          ],
        ]),
      );

  /// The plaque's lettering.
  static TextStyle text(TextStyle base) => base.copyWith(color: KitColor.signInk, shadows: kitSignShadow);
}

/// A red push-pin (the notice board).
class PushPin extends StatelessWidget {
  const PushPin({super.key, this.size = 13});
  final double size;
  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            center: Alignment(-0.24, -0.3),
            radius: 0.9,
            colors: [Color(0xFFFFD3C8), Color(0xFFFFD3C8), Color(0xFFE0533E), Color(0xFF9A2A1C)],
            stops: [0, 0.16, 0.42, 0.78],
          ),
          boxShadow: [BoxShadow(color: Color(0x66280A05), blurRadius: 2, offset: Offset(0, 2))],
        ),
      );
}

/// A paper on the notice board: a push-pin over its top edge ([pin]) and a hair off straight ([tilt],
/// degrees).
class Pinned extends StatelessWidget {
  const Pinned({super.key, required this.child, this.tilt = 0, this.pin = true});
  final Widget child;
  final double tilt;
  final bool pin;
  @override
  Widget build(BuildContext context) {
    var w = child;
    if (pin) {
      w = Stack(clipBehavior: Clip.none, fit: StackFit.passthrough, children: [
        child,
        const Positioned(left: 0, right: 0, top: -6, child: IgnorePointer(child: Center(child: PushPin()))),
      ]);
    }
    if (tilt != 0) w = Transform.rotate(angle: tilt * math.pi / 180, child: w);
    return w;
  }
}

/// The section heads' leaf bullet (kit.css `--leaf`).
class KitLeaf extends StatelessWidget {
  const KitLeaf({super.key, this.size = 22});
  final double size;
  @override
  Widget build(BuildContext context) => CustomPaint(size: Size(size, size), painter: const _LeafPainter());
}

class _LeafPainter extends CustomPainter {
  const _LeafPainter();
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    final leaf = Path()
      ..moveTo(3.5, 20.5)
      ..cubicTo(3.5, 11, 10, 4.5, 20.5, 3.5)
      ..cubicTo(19.5, 14, 13, 20.5, 3.5, 20.5)
      ..close();
    const ink = Color(0xFF3F6E2C);
    canvas.drawPath(leaf, Paint()..color = const Color(0xFF94C46C));
    canvas.drawPath(
      leaf,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.7
        ..strokeJoin = StrokeJoin.round
        ..color = ink,
    );
    canvas.drawPath(
      Path()
        ..moveTo(5, 19)
        ..cubicTo(9, 14, 13.5, 10.5, 17.5, 7.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round
        ..color = ink,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_LeafPainter oldDelegate) => false;
}

/// A dashed "stitched" rule (`border-top: 2px dashed`), filling its width.
class StitchedRule extends StatelessWidget {
  const StitchedRule({super.key, this.color = const Color(0x668C5F32)});
  final Color color;
  @override
  Widget build(BuildContext context) => SizedBox(height: 2, child: CustomPaint(painter: _DashPainter(color)));
}

class _DashPainter extends CustomPainter {
  const _DashPainter(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = color;
    for (var x = 0.0; x < size.width; x += 10) {
      canvas.drawRect(Rect.fromLTWH(x, 0, math.min(6.0, size.width - x), size.height), p);
    }
  }

  @override
  bool shouldRepaint(_DashPainter oldDelegate) => oldDelegate.color != color;
}

/// A five-point sparkle [r] px from [c] to its tips (the web's star clip-path), for reward bursts.
Path kitStarPath(Offset c, double r) {
  const pts = [(0.50, 0.00), (0.61, 0.35), (0.98, 0.35), (0.68, 0.57), (0.79, 0.91), (0.50, 0.70), (0.21, 0.91), (0.32, 0.57), (0.02, 0.35), (0.39, 0.35)];
  final path = Path();
  for (var i = 0; i < pts.length; i++) {
    final x = c.dx + (pts[i].$1 * 2 - 1) * r;
    final y = c.dy + (pts[i].$2 * 2 - 1) * r;
    if (i == 0) {
      path.moveTo(x, y);
    } else {
      path.lineTo(x, y);
    }
  }
  return path..close();
}

/// Level 3 of the framing (`.card.inset.mini-list`): a pressed-in parchment panel whose [children]
/// (plain rows) are split by stitched rules. For secondary lists: what's coming next, finished quests.
class KitInsetList extends StatelessWidget {
  const KitInsetList({super.key, required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        decoration: Kit.inset(),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const StitchedRule(color: Color(0x5996693C)),
            children[i],
          ],
        ]),
      );
}

/// A section head (`.sec-head`): a leaf, the title, an optional [trailing] chip, a stitched rule filling
/// the rest of the line, and an optional [end] after it ("Resets in 8 h").
class KitSectionHead extends StatelessWidget {
  const KitSectionHead(this.text, {super.key, this.trailing, this.end, this.padding = const EdgeInsets.only(top: 4, bottom: 8)});
  final String text;
  final Widget? trailing;
  final Widget? end;
  final EdgeInsets padding;
  @override
  Widget build(BuildContext context) {
    final plum = KitScope.of(context) == KitMaterial.apothecary;
    return Padding(
      padding: padding,
      child: Row(children: [
        const KitLeaf(),
        const SizedBox(width: 7),
        Semantics(header: true, child: Text(text, style: plum ? EvochiText.section.copyWith(color: KitColor.plum) : EvochiText.section)),
        if (trailing != null) ...[const SizedBox(width: 6), trailing!],
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(left: 11),
            child: StitchedRule(color: plum ? const Color(0x666E4696) : const Color(0x668C5F32)),
          ),
        ),
        if (end != null) ...[const SizedBox(width: 8), end!],
      ]),
    );
  }
}

/// The tab plaques' materials: wood (default), the journal's leather bookmarks, the satchel's canvas.
enum KitTabStyle { wood, leather, cloth }

/// A tab plaque (`.tab`). The chosen one lifts 3 px and lights up.
/// One font size for a whole row of labels (tabs, a row of buttons): the largest size, up to
/// [style]'s, at which the longest label fits in [width]. Shrinking each label on its own (a
/// FittedBox per label) left "Wear" big and "Pantry" small side by side.
double kitFitFontSize(BuildContext context, Iterable<String> labels, TextStyle style, double width, {double min = 10}) {
  final base = style.fontSize ?? 14;
  if (width <= 0) return min;
  final scaler = MediaQuery.maybeTextScalerOf(context) ?? TextScaler.noScaling;
  var size = base;
  for (final l in labels) {
    final tp = TextPainter(text: TextSpan(text: l, style: style), textDirection: TextDirection.ltr, textScaler: scaler, maxLines: 1)..layout();
    if (tp.width > width) size = math.min(size, base * width / tp.width * 0.98);
    tp.dispose();
  }
  return math.max(min, size);
}

/// A label that shares its size with the rest of its row: it measures the room it actually gets and
/// sizes itself (and, since every sibling does the same sum over the same [group], all of them) so
/// the longest label in [group] fits. Put it where the label goes, inside a Flexible.
class KitRowLabel extends StatelessWidget {
  const KitRowLabel(this.text, {super.key, required this.group, required this.style, this.min = 9.5});
  final String text;
  final List<String> group;
  final TextStyle style;
  final double min;
  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (ctx, box) {
        final fs = box.maxWidth.isFinite ? kitFitFontSize(ctx, group, style, box.maxWidth, min: min) : (style.fontSize ?? 14);
        return Text(text, maxLines: 1, softWrap: false, overflow: TextOverflow.clip, style: style.copyWith(fontSize: fs));
      });
}

class KitTab extends StatelessWidget {
  const KitTab({super.key, required this.selected, required this.child, this.style = KitTabStyle.wood, this.height = 48, this.padding = const EdgeInsets.symmetric(horizontal: 4), this.radius});
  final bool selected;
  final Widget child;
  final KitTabStyle style;
  final double height;
  final EdgeInsets padding;
  final BorderRadius? radius;
  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final d = reduce ? Duration.zero : const Duration(milliseconds: 120);
    // the chosen tab rises 3 px within the row's own height, so a clipping parent can't cut its top off
    return AnimatedPadding(
      duration: d,
      padding: EdgeInsets.only(top: selected ? 0 : 3, bottom: selected ? 3 : 0),
      child: AnimatedContainer(
        duration: d,
        height: height,
        padding: padding,
        decoration: radius == null ? Kit.tab(selected: selected, style: style) : Kit.tab(selected: selected, style: style, radius: radius!),
        child: child,
      ),
    );
  }

  /// A tab's lettering: dark on the chosen plaque, cream on the others.
  static TextStyle label(TextStyle base, bool selected, {KitTabStyle style = KitTabStyle.wood}) => base.copyWith(
        color: selected ? KitColor.signInk : (style == KitTabStyle.cloth ? const Color(0xFFFFF3DC) : KitColor.tabText),
        shadows: selected ? const [Shadow(color: Color(0x99FFFFFF), offset: Offset(0, 1))] : kitWoodTextShadow,
      );
}

/// Tracks a finger on a control so it can sink while pressed. [builder] gets `down`.
class KitPress extends StatefulWidget {
  const KitPress({super.key, required this.builder, this.onTap, this.behavior});
  final Widget Function(BuildContext context, bool down) builder;
  final VoidCallback? onTap;
  final HitTestBehavior? behavior;
  @override
  State<KitPress> createState() => _KitPressState();
}

class _KitPressState extends State<KitPress> {
  bool _down = false;
  void _set(bool v) {
    if (_down != v && mounted) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final on = widget.onTap != null;
    return GestureDetector(
      behavior: widget.behavior,
      onTapDown: on ? (_) => _set(true) : null,
      onTapUp: on ? (_) => _set(false) : null,
      onTapCancel: on ? () => _set(false) : null,
      onTap: widget.onTap,
      child: widget.builder(context, _down && on),
    );
  }
}

/// The market stall's red and cream awning with its scalloped edge (`.shop-lower::before`). Give it a
/// box about 30 px tall.
class ShopAwning extends StatelessWidget {
  const ShopAwning({super.key});
  @override
  Widget build(BuildContext context) => const IgnorePointer(child: CustomPaint(painter: _AwningPainter()));
}

class _AwningPainter extends CustomPainter {
  const _AwningPainter();
  @override
  void paint(Canvas canvas, Size size) {
    const tile = 26.0, band = 21.0;
    final shape = Path()..addRect(Rect.fromLTWH(0, 0, size.width, band));
    for (var x = 0.0; x < size.width; x += tile) {
      shape.addOval(Rect.fromCenter(center: Offset(x + tile / 2, band), width: tile, height: 18));
    }
    canvas.drawPath(shape.shift(const Offset(0, 2)), Paint()..color = const Color(0x735A1E0F));
    canvas.save();
    canvas.clipPath(shape);
    for (var i = 0; i * tile < size.width; i++) {
      canvas.drawRect(Rect.fromLTWH(i * tile, 0, tile, size.height), Paint()..color = i.isEven ? const Color(0xFFE46A4E) : const Color(0xFFFFF4E0));
    }
    // a soft shade under the valance's top
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, 3), Paint()..color = const Color(0x26000000));
    canvas.restore();
  }

  @override
  bool shouldRepaint(_AwningPainter oldDelegate) => false;
}

/// The journal's ruled lines, one every [gap] px (use it on a [DecoratedSliver] so they scroll with the
/// page, like the web's `background-attachment: local`).
class RuledPaper extends Decoration {
  const RuledPaper({this.gap = 30, this.color = const Color(0x21966E46)});
  final double gap;
  final Color color;
  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) => _RuledPainter(this);
  @override
  bool operator ==(Object other) => other is RuledPaper && other.gap == gap && other.color == color;
  @override
  int get hashCode => Object.hash(gap, color);
}

class _RuledPainter extends BoxPainter {
  _RuledPainter(this.d);
  final RuledPaper d;
  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration configuration) {
    final size = configuration.size;
    if (size == null || size.isEmpty || d.gap <= 1) return;
    final p = Paint()..color = d.color;
    for (var y = d.gap - 1; y < size.height; y += d.gap) {
      canvas.drawRect(Rect.fromLTWH(offset.dx, offset.dy + y, size.width, 1), p);
    }
  }
}

/// A small downward tail under a chip (the Bag's "Preview" tag, map pins).
class KitTail extends StatelessWidget {
  const KitTail({super.key, this.color = const Color(0xFFF1DDB8), this.edge = KitColor.woodEdge, this.width = 14, this.height = 8});
  final Color color;
  final Color edge;
  final double width;
  final double height;
  @override
  Widget build(BuildContext context) => CustomPaint(size: Size(width, height), painter: _TailPainter(color, edge));
}

class _TailPainter extends CustomPainter {
  const _TailPainter(this.color, this.edge);
  final Color color;
  final Color edge;
  @override
  void paint(Canvas canvas, Size size) {
    final p = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width / 2, size.height)
      ..lineTo(size.width, 0);
    canvas.drawPath(p..close(), Paint()..color = color);
    canvas.drawPath(
      Path()
        ..moveTo(0, 0)
        ..lineTo(size.width / 2, size.height)
        ..lineTo(size.width, 0),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round
        ..color = edge,
    );
  }

  @override
  bool shouldRepaint(_TailPainter oldDelegate) => oldDelegate.color != color || oldDelegate.edge != edge;
}
