// Reusable Evochi components built from the theme tokens (style guide §06-07, §25 "UI components").

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/constants.dart';
import '../../app/theme.dart';
import '../../controllers/game_controller.dart';
import '../../core/services/asset_manifest.dart';
import '../../game/vitality/vitality.dart';

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

enum ButtonTone { gold, green, cream, danger }

/// Chunky bevelled game button. Debounces repeat taps (style guide §23 "Fast repeated tap").
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
    final (top, bottom, edge, fg) = switch (widget.tone) {
      _ when !enabled => (const Color(0xFFEDE0CF), const Color(0xFFE2D2BE), const Color(0xFFC9B8A4), const Color(0xFF7E7166)),
      ButtonTone.gold => (EvochiColor.gold100, EvochiColor.primary, EvochiColor.primaryShadow, EvochiColor.ink),
      ButtonTone.green => (const Color(0xFFC6E59C), EvochiColor.steps, const Color(0xFF5C9340), EvochiColor.ink),
      ButtonTone.cream => (const Color(0xFFFFFBF4), const Color(0xFFEEDCC6), const Color(0xFFCDB396), EvochiColor.ink),
      ButtonTone.danger => (const Color(0xFFF4A193), EvochiColor.dead, const Color(0xFFA8463C), Colors.white),
    };
    final h = widget.large ? 56.0 : (widget.small ? 44.0 : 48.0);
    final style = EvochiText.button.copyWith(color: fg, fontSize: widget.large ? 20 : (widget.small ? 15 : 17));
    final child = AnimatedContainer(
      duration: const Duration(milliseconds: 60),
      height: h,
      transform: Matrix4.translationValues(0, _down ? 2 : 0, 0),
      padding: EdgeInsets.symmetric(horizontal: widget.small ? 12 : 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(widget.large ? 14 : 12),
        border: Border.all(color: edge, width: 2),
        gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [top, bottom]),
        boxShadow: [BoxShadow(color: edge, offset: Offset(0, _down ? 1 : 4))],
      ),
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

class GameCard extends StatelessWidget {
  const GameCard({super.key, required this.child, this.padding = const EdgeInsets.all(12), this.highlight = false, this.color});
  final Widget child;
  final EdgeInsets padding;
  final bool highlight;
  final Color? color;
  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: BoxDecoration(
          color: color ?? const Color(0xF5FFF9F0),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: highlight ? const Color(0xFFF2BE55) : EvochiColor.cardEdge, width: highlight ? 2 : 1.5),
          boxShadow: const [
            BoxShadow(color: EvochiColor.cardBevel, offset: Offset(0, 3)),
            BoxShadow(color: Color(0x1F502F19), blurRadius: 18, offset: Offset(0, 6)),
          ],
        ),
        child: child,
      );
}

enum TagTone { stage, ok, warn, danger, neutral, cream, red }

class Tag extends StatelessWidget {
  const Tag(this.text, {super.key, this.tone = TagTone.cream, this.icon});
  final String text;
  final TagTone tone;
  final String? icon;
  @override
  Widget build(BuildContext context) {
    final (bg, fg, edge) = switch (tone) {
      TagTone.stage => (EvochiColor.gold300, EvochiColor.gold900, const Color(0xFFE3A64A)),
      TagTone.ok => (EvochiColor.meadow100, EvochiColor.healthy, const Color(0xFFCDE5B0)),
      TagTone.warn => (const Color(0xFFFFF0D8), EvochiColor.gold900, EvochiColor.sick),
      TagTone.danger => (const Color(0xFFFBE4E0), const Color(0xFF913B36), EvochiColor.dead),
      TagTone.neutral => (const Color(0xFFEFE6DB), EvochiColor.textSecondary, const Color(0xFFDCCBB8)),
      TagTone.cream => (const Color(0xFFF6EBDD), EvochiColor.textSecondary, const Color(0xFFE5D3BE)),
      TagTone.red => (const Color(0xFFE0654B), Colors.white, const Color(0xFFB8452F)),
    };
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8), border: Border.all(color: edge, width: 1.5)),
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
        child: Container(
          height: 36,
          padding: const EdgeInsets.only(right: 4),
          decoration: BoxDecoration(color: EvochiColor.hudPill, borderRadius: BorderRadius.circular(10)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Transform.translate(offset: const Offset(-8, 0), child: const VoxelIcon('coin', size: 32)),
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 46),
              child: Text(fmt(balance), style: EvochiText.number.copyWith(color: Colors.white, fontSize: 15)),
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
                  decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(7)),
                  child: const Icon(Icons.add, color: Colors.white, size: 18),
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
        child: GestureDetector(
          onTap: onTap,
          child: Stack(clipBehavior: Clip.none, children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(11),
                border: Border.all(color: const Color(0xFFE7D3BC), width: 2),
                gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFFFF9F0), Color(0xFFF1E2CF)]),
                boxShadow: const [BoxShadow(color: Color(0xFFCDB396), offset: Offset(0, 3))],
              ),
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
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2CDB4), width: 2),
              color: const Color(0xFFFFF9F0),
              boxShadow: const [BoxShadow(color: Color(0xFFCDB396), offset: Offset(0, 3))],
            ),
            child: const Icon(Icons.chevron_left_rounded, color: EvochiColor.ink, size: 30),
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

class ProgressBarX extends StatelessWidget {
  const ProgressBarX({super.key, required this.value, this.height = 14, this.tone = 'gold', this.semantic});
  final double value;
  final double height;
  final String tone; // gold | green | amber | red
  final String? semantic;
  @override
  Widget build(BuildContext context) {
    final colors = switch (tone) {
      'green' => const [Color(0xFFA8D87E), Color(0xFF6FA44E)],
      'amber' => const [Color(0xFFF6CD86), EvochiColor.sick],
      'red' => const [Color(0xFFF29A8C), EvochiColor.dead],
      _ => const [Color(0xFFFFE29A), Color(0xFFE2A03E)],
    };
    final v = value.isNaN ? 0.0 : value.clamp(0.0, 1.0);
    return Semantics(
      label: semantic,
      value: '${(v * 100).round()}%',
      child: Container(
        height: height,
        decoration: BoxDecoration(color: tone == 'gold' ? EvochiColor.track : const Color(0xFFC9BEB3), borderRadius: BorderRadius.circular(height / 2)),
        child: LayoutBuilder(
          builder: (c, b) => Align(
            alignment: Alignment.centerLeft,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: v),
              duration: const Duration(milliseconds: 700),
              curve: Curves.easeOutCubic,
              builder: (c, t, _) => Container(
                width: b.maxWidth * t,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(height / 2),
                  gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: colors),
                ),
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
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(6, 0, 6, 6),
        height: 72,
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE9D4BB), width: 2),
          gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFFBF2E6), Color(0xFFF1E1CD)]),
          boxShadow: const [BoxShadow(color: Color(0xFFCFB597), offset: Offset(0, 4)), BoxShadow(color: Color(0x40000000), blurRadius: 22, offset: Offset(0, 8))],
        ),
        child: Row(children: [
          for (final t in tabs)
            Expanded(
              child: Semantics(
                selected: t.$1 == current,
                button: true,
                label: '${t.$2}${(badges[t.$1] ?? 0) > 0 ? ', new' : ''}',
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onTab(t.$1),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    decoration: t.$1 == current
                        ? BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFFFF7DA), Color(0xFFFFE9AE)]),
                            border: Border.all(color: const Color(0xFFF4C25A), width: 2),
                            boxShadow: const [BoxShadow(color: Color(0xBFFFC850), blurRadius: 14)],
                          )
                        : null,
                    child: Stack(clipBehavior: Clip.none, alignment: Alignment.center, children: [
                      Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        AnimatedScale(scale: t.$1 == current ? 1.08 : 1, duration: const Duration(milliseconds: 150), child: VoxelIcon(t.$1, size: 36)),
                        Text(t.$2, style: EvochiText.tag.copyWith(fontSize: 12.5, color: t.$1 == current ? EvochiColor.ink : EvochiColor.textSecondary)),
                      ]),
                      if ((badges[t.$1] ?? 0) > 0) const Positioned(top: 2, right: 10, child: BadgeDot()),
                    ]),
                  ),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}

Future<T?> showEvochiSheet<T>(BuildContext context, {required WidgetBuilder builder}) => showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      backgroundColor: EvochiColor.canvas,
      barrierColor: const Color(0x8C201B17),
      builder: (c) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(18, 10, 18, 18 + MediaQuery.of(c).viewInsets.bottom),
          child: SingleChildScrollView(child: builder(c)),
        ),
      ),
    );

Future<T?> showEvochiDialog<T>(BuildContext context, {required WidgetBuilder builder}) => showDialog<T>(
      context: context,
      barrierColor: const Color(0x8C201B17),
      builder: (c) => Dialog(
        backgroundColor: EvochiColor.canvas,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        child: Padding(padding: const EdgeInsets.all(20), child: builder(c)),
      ),
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
      final bg = switch (t.kind) {
        'warn' => const Color(0xF280531F),
        'err' => const Color(0xF2913B36),
        _ => const Color(0xF23A622E),
      };
      ScaffoldMessenger.maybeOf(context)
        ?..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          backgroundColor: bg,
          duration: const Duration(milliseconds: 2400),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          content: Row(children: [
            if (t.icon != null) ...[VoxelIcon(t.icon!, size: 28), const SizedBox(width: 8)],
            Expanded(child: Text(t.message, style: EvochiText.tag.copyWith(color: Colors.white, fontSize: 14))),
          ]),
        ));
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
