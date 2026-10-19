// Reusable Evochi components built from the theme tokens (style guide §06-07, §25 "UI components"),
// dressed in the game-native kit (kit.dart, after web/src/kit.css): card stock, outlined glossy buttons
// that sink, stamped tags, wooden signs, a carved groove for progress, a wooden nav bar, and carved
// window frames around sheets and dialogs.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/constants.dart';
import '../../app/theme.dart';
import '../../controllers/game_controller.dart';
import '../../core/services/asset_manifest.dart';
import '../../game/vitality/vitality.dart';
import 'kit.dart';

AssetManifest get art => AssetManifest.instance!;

String fmt(int n) {
  final s = n.abs().toString();
  final b = StringBuffer(n < 0 ? '-' : '');
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return b.toString();
}

class VoxelIcon extends StatelessWidget {
  const VoxelIcon(this.name, {super.key, this.size = 28, this.semantic});
  final String name;
  final double size;
  final String? semantic;
  @override
  Widget build(BuildContext context) => Image.asset(art.icon(name), width: size, height: size, semanticLabel: semantic, excludeFromSemantics: semantic == null, filterQuality: FilterQuality.medium);
}

class ItemImage extends StatelessWidget {
  const ItemImage(this.id, {super.key, this.size = 64});
  final String id;
  final double size;
  @override
  Widget build(BuildContext context) => Image.asset(art.item(id), width: size, height: size, excludeFromSemantics: true, filterQuality: FilterQuality.medium);
}

class TitleImage extends StatelessWidget {
  const TitleImage(this.name, {super.key, this.height = 44, required this.label});
  final String name;
  final double height;
  final String label;
  @override
  Widget build(BuildContext context) => Semantics(
        header: true,
        label: label,
        child: ExcludeSemantics(child: Image.asset(art.title(name), height: height, filterQuality: FilterQuality.medium)),
      );
}

enum ButtonTone { gold, green, cream, danger, plum }

KitButtonPalette buttonPalette(ButtonTone t) => switch (t) {
      ButtonTone.gold => KitButtonPalette.gold,
      ButtonTone.green => KitButtonPalette.green,
      ButtonTone.cream => KitButtonPalette.cream,
      ButtonTone.danger => KitButtonPalette.danger,
      ButtonTone.plum => KitButtonPalette.plum,
    };

/// Chunky game button: a dark outline, a gloss strip under the label, and a hard edge it sinks into
/// (3 px) while pressed. Debounces repeat taps (style guide §23 "Fast repeated tap").
class EvochiButton extends StatefulWidget {
  const EvochiButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.tone = ButtonTone.gold,
    this.icon,
    this.large = false,
    this.small = false,
    this.expand = true,
    this.semanticLabel,
  });
  final String label;
  final VoidCallback? onPressed;
  final ButtonTone tone;
  final Widget? icon;
  final bool large;
  final bool small;
  final bool expand;
  final String? semanticLabel;

  @override
  State<EvochiButton> createState() => _EvochiButtonState();
}

class _EvochiButtonState extends State<EvochiButton> {
  bool _down = false;
  DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final p = enabled ? buttonPalette(widget.tone) : KitButtonPalette.disabled;
    final down = _down && enabled;
    final h = widget.large ? 56.0 : (widget.small ? 44.0 : 48.0);
    final style = EvochiText.button.copyWith(
      color: p.fg,
      fontSize: widget.large ? 20 : (widget.small ? 15 : 17),
      shadows: p.textShadow == null ? null : [Shadow(color: p.textShadow!, offset: const Offset(0, 1))],
    );
    final child = AnimatedContainer(
      duration: const Duration(milliseconds: 60),
      height: h,
      transform: Matrix4.translationValues(0, down ? 3 : 0, 0),
      padding: EdgeInsets.symmetric(horizontal: widget.small ? 12 : 18),
      decoration: Kit.button(p, pressed: down, small: widget.small, disabled: !enabled, radius: widget.large ? 14 : (widget.small ? 10 : 13)),
      child: Row(
        mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (widget.icon != null) ...[widget.icon!, const SizedBox(width: 8)],
          Flexible(child: Text(widget.label, style: style, overflow: TextOverflow.ellipsis, maxLines: 1)),
        ],
      ),
    );
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.semanticLabel ?? widget.label,
      child: ExcludeSemantics(
        child: GestureDetector(
          onTapDown: enabled ? (_) => setState(() => _down = true) : null,
          onTapCancel: () => setState(() => _down = false),
          onTapUp: enabled ? (_) => setState(() => _down = false) : null,
          onTap: enabled
              ? () {
                  final t = DateTime.now();
                  if (t.difference(_last).inMilliseconds < 350) return;
                  _last = t;
                  context.read<GameController>().audio.tick();
                  widget.onPressed!();
                }
              : null,
          child: child,
        ),
      ),
    );
  }
}

/// A CARD: printed card stock (grain, an inner double rule, a hard bottom edge). It prints on its
/// screen's material ([KitScope]): lavender in the Apothecary. [color] tints it, [paper] picks a stock
/// outright, [rule] adds a margin rule down the left (journal entries, recipes), and [pinned] / [tilt]
/// pin it to the notice board. (The EvoDex binder's ring holes are gone: on a phone they read as stray
/// bullets.)
class GameCard extends StatelessWidget {
  const GameCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(12),
    this.highlight = false,
    this.color,
    this.paper,
    this.rule,
    this.pinned = false,
    this.tilt = 0,
  });
  final Widget child;
  final EdgeInsets padding;
  final bool highlight;
  final Color? color;
  final KitPaper? paper;
  final Color? rule;
  final bool pinned;
  final double tilt; // degrees
  @override
  Widget build(BuildContext context) {
    final m = KitScope.of(context);
    final stock = paper ?? (color != null ? KitPaper.tint(color!) : KitPaper.of(m));
    final card = Container(
      padding: padding,
      decoration: Kit.card(paper: stock, highlight: highlight, rule: rule),
      child: child,
    );
    return pinned || tilt != 0 ? Pinned(pin: pinned, tilt: tilt, child: card) : card;
  }
}

enum TagTone { stage, ok, warn, danger, neutral, cream, red }

class Tag extends StatelessWidget {
  const Tag(this.text, {super.key, this.tone = TagTone.cream, this.icon});
  final String text;
  final TagTone tone;
  final String? icon;
  @override
  Widget build(BuildContext context) {
    // a little stamped capsule: a lit top edge and a hard shadow under it; cream and neutral are printed
    // on grained paper
    final (Color? bg, Gradient? grad, Color fg, Color edge) = switch (tone) {
      TagTone.stage => (null, const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFFFE5A2), Color(0xFFF9CA70)]), EvochiColor.gold900, const Color(0xFFC98A2C)),
      TagTone.ok => (EvochiColor.meadow100, null, EvochiColor.healthy, const Color(0xFF9CC27A)),
      TagTone.warn => (const Color(0xFFFFF0D8), null, EvochiColor.gold900, EvochiColor.sick),
      TagTone.danger => (const Color(0xFFFBE4E0), null, const Color(0xFF913B36), EvochiColor.dead),
      TagTone.neutral || TagTone.cream => (null, const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFFBF0DA), Color(0xFFEEDDBC)]), const Color(0xFF5A3E2A), const Color(0xFFC9A77A)),
      TagTone.red => (null, const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFF07A5C), Color(0xFFD8573F)]), Colors.white, const Color(0xFFB8452F)),
    };
    final grain = tone == TagTone.neutral || tone == TagTone.cream;
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: KitDecoration(
        base: BoxDecoration(
          color: bg,
          gradient: grad,
          image: grain ? kitGrain : null,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: edge, width: 1.5),
          boxShadow: const [BoxShadow(color: Color(0x385A3719), offset: Offset(0, 1.5))],
        ),
        inset: 1.5,
        top: const KitBand(1, Color(0x99FFFFFF)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[VoxelIcon(icon!, size: 16), const SizedBox(width: 4)],
        Text(text, style: EvochiText.tag.copyWith(color: fg)),
      ]),
    );
  }
}

Widget statusTag(PetStatus s) => switch (s) {
      PetStatus.healthy => const Tag('Healthy', tone: TagTone.ok, icon: 'care'),
      PetStatus.neutral => const Tag('Neutral', tone: TagTone.neutral, icon: 'heart_empty'),
      PetStatus.sick => const Tag('Unwell', tone: TagTone.warn, icon: 'potion'),
      PetStatus.dead => const Tag('Resting', tone: TagTone.danger, icon: 'heart_empty'),
    };

class CoinPill extends StatelessWidget {
  const CoinPill({super.key, required this.balance, required this.onPlus});
  final int balance;
  final VoidCallback onPlus;
  @override
  Widget build(BuildContext context) => Semantics(
        label: '${fmt(balance)} EvoCoins',
        // dark wood, with a gold plus
        child: Container(
          height: 36,
          padding: const EdgeInsets.only(right: 4),
          decoration: Kit.coinPill(),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Transform.translate(offset: const Offset(-8, 0), child: const VoxelIcon('coin', size: 32)),
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 46),
              child: Text(fmt(balance), style: EvochiText.number.copyWith(color: Colors.white, fontSize: 15, shadows: kitWoodTextShadow)),
            ),
            SizedBox(
              width: 44,
              height: 44,
              child: IconButton(
                onPressed: onPlus,
                tooltip: 'How to earn EvoCoins',
                icon: Container(
                  width: 26,
                  height: 26,
                  decoration: const KitDecoration(
                    base: BoxDecoration(
                      gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFFFE5A2), Color(0xFFF4B84E)]),
                      borderRadius: BorderRadius.all(Radius.circular(7)),
                      border: Border.fromBorderSide(BorderSide(color: Color(0xFF7A4512), width: 1.5)),
                    ),
                    inset: 1.5,
                    top: KitBand(1, Color(0x99FFFFFF)),
                  ),
                  child: const Icon(Icons.add, color: Color(0xFF5A3410), size: 18),
                ),
              ),
            ),
          ]),
        ),
      );
}

class SquareIconButton extends StatelessWidget {
  const SquareIconButton({super.key, required this.icon, required this.label, required this.onTap, this.badge = 0});
  final String icon;
  final String label;
  final VoidCallback onTap;
  final int badge;
  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: badge > 0 ? '$label, $badge ready' : label,
        child: KitPress(
          onTap: onTap,
          builder: (_, down) => Stack(clipBehavior: Clip.none, children: [
            // a light-wood square that sinks when pressed
            AnimatedContainer(
              duration: const Duration(milliseconds: 60),
              width: 46,
              height: 46,
              transform: Matrix4.translationValues(0, down ? 2 : 0, 0),
              decoration: Kit.wood(radius: 11, width: 300, y: -1, pressed: down),
              alignment: Alignment.center,
              child: VoxelIcon(icon, size: 30),
            ),
            if (badge > 0) const Positioned(top: -5, right: -5, child: BadgeDot()),
          ]),
        ),
      );
}

class BackSquareButton extends StatelessWidget {
  const BackSquareButton({super.key, required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: 'Back',
        child: KitPress(
          onTap: onTap,
          builder: (_, down) => AnimatedContainer(
            duration: const Duration(milliseconds: 60),
            width: 46,
            height: 46,
            transform: Matrix4.translationValues(0, down ? 2 : 0, 0),
            decoration: Kit.wood(radius: 12, width: 300, y: -1, pressed: down),
            child: const Icon(Icons.chevron_left_rounded, color: KitColor.signInk, size: 30, shadows: kitSignShadow),
          ),
        ),
      );
}

class BadgeDot extends StatelessWidget {
  const BadgeDot({super.key});
  @override
  Widget build(BuildContext context) => Container(
        width: 14,
        height: 14,
        decoration: BoxDecoration(color: EvochiColor.dead, shape: BoxShape.circle, border: Border.all(color: const Color(0xFFFFF6EC), width: 2)),
      );
}

/// A progress bar: a dark carved groove ([ring] around it) with a glossy fill.
class ProgressBarX extends StatelessWidget {
  const ProgressBarX({super.key, required this.value, this.height = 14, this.tone = 'gold', this.semantic, this.ring = const Color(0xFF7A5032)});
  final double value;
  final double height;
  final String tone; // gold | green | amber | red
  final String? semantic;
  final Color ring;
  @override
  Widget build(BuildContext context) {
    final (colors, stops) = switch (tone) {
      'green' => (const [Color(0xFFA8D87E), Color(0xFF82B75E), Color(0xFF6FA44E)], const [0.0, 0.6, 1.0]),
      'amber' => (const [Color(0xFFF6CD86), EvochiColor.sick], null),
      'red' => (const [Color(0xFFF29A8C), EvochiColor.dead], null),
      _ => (const [Color(0xFFFFE29A), Color(0xFFF4B84E), Color(0xFFE2A03E)], const [0.0, 0.55, 1.0]),
    };
    final v = value.isNaN ? 0.0 : value.clamp(0.0, 1.0);
    return Semantics(
      label: semantic,
      value: '${(v * 100).round()}%',
      child: Container(
        height: height,
        decoration: Kit.groove(height / 2, ring: ring),
        child: LayoutBuilder(
          builder: (c, b) => Align(
            alignment: Alignment.centerLeft,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: v),
              duration: const Duration(milliseconds: 700),
              curve: Curves.easeOutCubic,
              builder: (c, t, _) => Container(
                width: b.maxWidth * t,
                decoration: Kit.barFill(colors, height / 2, stops: stops),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class Hearts extends StatelessWidget {
  const Hearts({super.key, required this.filled, this.bond = 0});
  final int filled;
  final int bond;
  @override
  Widget build(BuildContext context) => Semantics(
        label: 'Bond $bond of 100',
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const VoxelIcon('heart', size: 20),
          const SizedBox(width: 2),
          for (var i = 0; i < 5; i++) VoxelIcon(i < filled ? 'heart' : 'heart_empty', size: 16),
        ]),
      );
}

class EvochiNavBar extends StatelessWidget {
  const EvochiNavBar({super.key, required this.current, required this.onTab, this.badges = const {}});
  final String current;
  final ValueChanged<String> onTab;
  final Map<String, int> badges;
  static const tabs = [('home', 'Home'), ('journey', 'Journey'), ('bag', 'Bag'), ('shop', 'Shop'), ('evodex', 'EvoDex')];
  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.of(context).disableAnimations;
    // a carved wooden bar; the current item is a parchment-gold plaque raised 4 px out of it
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(6, 0, 6, 6),
        height: 72,
        padding: const EdgeInsets.all(5),
        decoration: Kit.navBar(),
        child: Row(children: [
          for (var i = 0; i < tabs.length; i++)
            Expanded(
              child: Builder(builder: (_) {
                final t = tabs[i];
                final on = t.$1 == current;
                // a carved groove between items, except beside the raised one
                final groove = i > 0 && !on && tabs[i - 1].$1 != current;
                return Stack(clipBehavior: Clip.none, children: [
                  if (groove)
                    const Positioned(
                      left: -1,
                      top: 14,
                      bottom: 14,
                      width: 2,
                      child: DecoratedBox(
                        decoration: BoxDecoration(color: Color(0x73281204), boxShadow: [BoxShadow(color: Color(0x40FFD6A0), offset: Offset(1.5, 0))]),
                      ),
                    ),
                  Positioned.fill(
                    child: Semantics(
                      selected: on,
                      button: true,
                      label: '${t.$2}${(badges[t.$1] ?? 0) > 0 ? ', new' : ''}',
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => onTab(t.$1),
                        child: AnimatedContainer(
                          duration: reduce ? Duration.zero : const Duration(milliseconds: 150),
                          transform: Matrix4.translationValues(0, on ? -4 : 0, 0),
                          decoration: on ? Kit.navCurrent() : null,
                          child: Stack(clipBehavior: Clip.none, alignment: Alignment.center, children: [
                            Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                              AnimatedScale(scale: on ? 1.08 : 1, duration: const Duration(milliseconds: 150), child: VoxelIcon(t.$1, size: 36)),
                              Text(
                                t.$2,
                                style: EvochiText.tag.copyWith(
                                  fontSize: 12.5,
                                  color: on ? KitColor.signInk : KitColor.navText,
                                  shadows: on ? const [Shadow(color: Color(0x99FFFFFF), offset: Offset(0, 1))] : const [Shadow(color: Color(0xA61E0C00), offset: Offset(0, 1))],
                                ),
                              ),
                            ]),
                            if ((badges[t.$1] ?? 0) > 0) const Positioned(top: 2, right: 10, child: BadgeDot()),
                          ]),
                        ),
                      ),
                    ),
                  ),
                ]);
              }),
            ),
        ]),
      ),
    );
  }
}

/// A bottom sheet: a WINDOW, parchment in a carved wood frame, running down to the screen's edge.
Future<T?> showEvochiSheet<T>(BuildContext context, {required WidgetBuilder builder}) => showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      elevation: 0,
      barrierColor: const Color(0x8C201B17),
      builder: (c) {
        final mq = MediaQuery.of(c);
        final keyboard = mq.viewInsets.bottom;
        return SafeArea(
          bottom: false,
          child: Padding(
            padding: EdgeInsets.only(bottom: keyboard),
            child: FramedWindow(
              padding: EdgeInsets.fromLTRB(10, 8, 10, 10 + (keyboard > 0 ? 0 : mq.padding.bottom)),
              shadow: const BoxShadow(color: Color(0x4D000000), blurRadius: 18, offset: Offset(0, -6)),
              child: SingleChildScrollView(child: builder(c)),
            ),
          ),
        );
      },
    );

/// A dialog: a WINDOW, parchment in a carved wood frame.
Future<T?> showEvochiDialog<T>(BuildContext context, {required WidgetBuilder builder}) => showDialog<T>(
      context: context,
      barrierColor: const Color(0x8C201B17),
      builder: (c) => KitDialog(child: builder(c)),
    );

String stageLabel(int s) => stageLabels[s] ?? '';

/// Listens to controller toasts and shows them as voxel-styled snack bars.
class ToastListener extends StatefulWidget {
  const ToastListener({super.key, required this.child});
  final Widget child;
  @override
  State<ToastListener> createState() => _ToastListenerState();
}

class _ToastListenerState extends State<ToastListener> {
  @override
  void initState() {
    super.initState();
    final ctl = context.read<GameController>();
    ctl.toasts.listen((t) {
      if (!mounted) return;
      // parchment with a dark edge: green for good news, amber for warnings, rose for errors
      final deco = switch (t.kind) {
        'warn' => Kit.toast(const [Color(0xFFFFF6DC), Color(0xFFFBE0A6)], KitColor.plaqueEdge, KitColor.woodShadow),
        'err' => Kit.toast(const [Color(0xFFFDEDE8), Color(0xFFF4C8BE)], const Color(0xFF7E2A22), const Color(0xFF62201A)),
        _ => Kit.toast(const [Color(0xFFF3FAE8), Color(0xFFD9EDBF)], const Color(0xFF2F5A21), const Color(0xFF2F5A21)),
      };
      ScaffoldMessenger.maybeOf(context)
        ?..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          padding: EdgeInsets.zero,
          clipBehavior: Clip.none,
          duration: const Duration(milliseconds: 2400),
          content: Container(
            padding: const EdgeInsets.fromLTRB(8, 8, 14, 8),
            decoration: deco,
            child: Row(children: [
              if (t.icon != null) ...[
                t.icon!.startsWith('item:') ? ItemImage(t.icon!.substring(5), size: 30) : VoxelIcon(t.icon!, size: 28),
                const SizedBox(width: 8),
              ],
              Expanded(child: Text(t.message, style: EvochiText.tag.copyWith(color: EvochiColor.ink, fontSize: 14))),
            ]),
          ),
        ));
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
