// The way in, at the Thicket's arch or the mouth of Flint's mine: a picture of the entrance, and two ways
// down. From the top (the Sunlit Thicket, or the mine's first gallery), or straight down to the deepest floor
// you have reached; that floor is drawn as strata, the floors above it in bands of rock getting darker, its
// own band glowing. A fresh run starts either way. Until you have found the steps down, the second way is
// shown locked, with what opens it.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../controllers/game_controller.dart';
import '../../core/services/haptics.dart';
import '../../game/wilds/story_floors.dart' as sf;
import '../../game/wilds/wilds.dart' as w;
import '../shared/kit.dart';
import '../shared/widgets.dart';
import 'wilds_screen.dart';

/// Ask which way in. Returns the floor chosen (1, or the deepest reached), or null for "not now".
Future<int?> showDescentSheet(BuildContext context, {required bool mine}) =>
    showEvochiSheet<int>(context, builder: (_) => _DescentSheet(mine: mine));

/// The Wilds (or a gallery of the mine) at [depth]: the Thicket for floor 1 of the Wilds, a deep floor
/// otherwise (a Guild job's floor when one waits there).
Route<void> descentRoute(BuildContext context, int depth, {required bool mine}) {
  final s = context.read<GameController>().state;
  final day = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 86400000;
  final Widget screen;
  if (mine) {
    screen = WildsScreen(depth: depth, seed: day * 131 + depth, mine: true);
  } else if (depth <= 1) {
    screen = const WildsScreen();
  } else {
    screen = WildsScreen(depth: depth, story: sf.storyFloorAt(s, depth)?.quest);
  }
  return PageRouteBuilder<void>(
    transitionDuration: const Duration(milliseconds: 600),
    pageBuilder: (_, __, ___) => screen,
    transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
  );
}

/// Ask, then go: the sheet, and the floor it picks.
Future<void> enterDescent(BuildContext context, {required bool mine}) async {
  final depth = await showDescentSheet(context, mine: mine);
  if (depth == null || !context.mounted) return;
  context.read<GameController>().audio.play('enc_whoosh', volume: 0.5);
  await Navigator.of(context).push(descentRoute(context, depth, mine: mine));
}

class _DescentSheet extends StatelessWidget {
  const _DescentSheet({required this.mine});
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final c = context.watch<GameController>();
    final deepest = mine ? w.deepestMineFloor(c.state) : w.deepestFloor(c.state);
    final story = mine || deepest < 2 ? null : sf.storyFloorAt(c.state, deepest);
    final accent = mine ? const Color(0xFFC98A4E) : const Color(0xFF7FB069);
    void pick(int depth) {
      c.audio.play('ui_tap', volume: 0.4);
      c.audio.buzz(Haptic.tap);
      Navigator.of(context).pop(depth);
    }

    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      // the entrance, with its name over the picture
      ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: AspectRatio(
          aspectRatio: 1080 / 560,
          child: Stack(fit: StackFit.expand, children: [
            Image.asset(mine ? 'assets/art/trail/entrance_mine.webp' : 'assets/art/trail/entrance_thicket.webp',
                fit: BoxFit.cover, alignment: const Alignment(0, -0.2), excludeFromSemantics: true),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: [0.35, 1],
                  colors: [Color(0x00140E0B), Color(0xE6140E0B)],
                ),
              ),
            ),
            Positioned(
              left: 14,
              right: 14,
              bottom: 12,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(mine ? "Flint's Mine" : 'The Lumen Wilds',
                    style: const TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w900, fontSize: 26, color: Color(0xFFFFF4E2), shadows: [
                      Shadow(color: Color(0xCC000000), offset: Offset(0, 2), blurRadius: 4),
                    ])),
                Text(mine ? 'Lit galleries, copper in every wall, harder rock below.' : 'The Thicket first, then Fernwood Trail, floor by floor.',
                    style: const TextStyle(fontFamily: EvochiText.body, fontSize: 14, color: Color(0xFFF1E3CC), shadows: [Shadow(color: Color(0xCC000000), blurRadius: 3)])),
              ]),
            ),
          ]),
        ),
      ),
      const SizedBox(height: 12),
      Text('Where do you want to start?', textAlign: TextAlign.center, style: EvochiText.cardTitle.copyWith(fontSize: 17)),
      const SizedBox(height: 10),
      _WayCard(
        floor: 1,
        accent: accent,
        title: mine ? 'Start at the first gallery' : 'Start at the Sunlit Thicket',
        sub: mine ? 'Lit and shored, the best place to warm up.' : 'Calm the Thicket, then find the steps down.',
        tag: 'From the top',
        deepest: deepest,
        onTap: () => pick(1),
      ),
      const SizedBox(height: 10),
      _WayCard(
        floor: deepest,
        accent: accent,
        locked: deepest < 2,
        title: deepest < 2 ? 'Descend deeper' : 'Descend to F$deepest',
        sub: deepest < 2
            ? (mine ? 'Find the shaft at the back of a gallery to open this.' : 'Find the steps down past the Thicket to open this.')
            : (mine ? 'The deepest gallery you have reached. A fresh trip starts there.' : 'Fernwood Trail, the deepest you have been. A fresh run starts there.'),
        tag: deepest < 2 ? 'Locked' : 'Deepest yet',
        note: story != null ? 'A Guild job waits on this floor' : null,
        deepest: deepest,
        onTap: deepest < 2 ? null : () => pick(deepest),
      ),
      const SizedBox(height: 8),
      Align(
        alignment: Alignment.center,
        child: TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Not now', style: TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w800, fontSize: 15, color: EvochiColor.textHelper)),
        ),
      ),
    ]);
  }
}

/// One way in: the strata (where this floor sits), the floor's badge, its words, a press that sinks.
class _WayCard extends StatelessWidget {
  const _WayCard(
      {required this.floor, required this.accent, required this.title, required this.sub, required this.tag, required this.deepest, this.note, this.locked = false, this.onTap});
  final int floor, deepest;
  final Color accent;
  final String title, sub, tag;
  final String? note;
  final bool locked;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: !locked,
        label: '$title. $sub${note != null ? '. $note' : ''}',
        excludeSemantics: true,
        child: KitPress(
          onTap: onTap,
          builder: (_, down) => AnimatedContainer(
            duration: const Duration(milliseconds: 70),
            transform: Matrix4.translationValues(0, down && !locked ? 2 : 0, 0),
            padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: locked ? const [Color(0xFFEDE4D6), Color(0xFFE0D5C4)] : const [Color(0xFFFFF8EA), Color(0xFFF3E2C4)],
              ),
              border: Border.all(color: locked ? const Color(0xFFC9BBA6) : const Color(0xFFB08A58), width: 2),
              boxShadow: [
                if (!locked && !down) const BoxShadow(color: Color(0xFFB89466), offset: Offset(0, 3)),
                const BoxShadow(color: Color(0x22000000), blurRadius: 8, offset: Offset(0, 4)),
              ],
            ),
            child: Opacity(
              opacity: locked ? 0.6 : 1,
              child: Row(children: [
                SizedBox(width: 54, height: 72, child: CustomPaint(painter: _Strata(floor: floor, deepest: math.max(deepest, 2), accent: accent, locked: locked))),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: (locked ? const Color(0xFF8D8274) : accent).withValues(alpha: 0.18), borderRadius: BorderRadius.circular(8)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        if (locked) ...[const VoxelIcon('lock', size: 13), const SizedBox(width: 3)],
                        Text(tag, style: TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w900, fontSize: 12.5, color: Color.lerp(accent, Colors.black, 0.45))),
                      ]),
                    ),
                    const SizedBox(height: 3),
                    Text(title, style: EvochiText.cardTitle.copyWith(fontSize: 17)),
                    Text(sub, style: const TextStyle(fontFamily: EvochiText.body, fontSize: 13.5, height: 1.3, color: EvochiColor.textSecondary)),
                    if (note != null) ...[
                      const SizedBox(height: 4),
                      Row(children: [
                        const VoxelIcon('trail_badge', size: 16),
                        const SizedBox(width: 4),
                        Flexible(child: Text(note!, style: const TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w800, fontSize: 12.5, color: EvochiColor.gold900))),
                      ]),
                    ],
                  ]),
                ),
                if (!locked) const Icon(Icons.chevron_right_rounded, color: EvochiColor.wood, size: 26),
              ]),
            ),
          ),
        ),
      );
}

/// A slice of ground: the surface (grass, or the mine's lit timber) over bands of rock that darken with
/// depth, one band a floor, down to the deepest you have reached; this way's floor glows, with its number.
class _Strata extends CustomPainter {
  _Strata({required this.floor, required this.deepest, required this.accent, required this.locked});
  final int floor, deepest;
  final Color accent;
  final bool locked;

  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(10));
    canvas.save();
    canvas.clipRRect(r);
    final bands = math.min(deepest, 7); // past 7 floors, the deepest band stands for the rest
    final top = size.height * 0.16;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, top), Paint()..color = accent);
    final bh = (size.height - top) / bands;
    for (var i = 0; i < bands; i++) {
      final k = bands == 1 ? 0.0 : i / (bands - 1);
      final col = Color.lerp(const Color(0xFFA58A6C), const Color(0xFF3A2C24), k)!;
      canvas.drawRect(Rect.fromLTWH(0, top + i * bh, size.width, bh + 0.5), Paint()..color = col);
      canvas.drawLine(Offset(0, top + i * bh), Offset(size.width, top + i * bh), Paint()
        ..color = const Color(0x33000000)
        ..strokeWidth = 1);
    }
    // this way's floor: the surface band (floor 1) or the deepest band, glowing
    final band = floor <= 1 ? Rect.fromLTWH(0, 0, size.width, top + bh) : Rect.fromLTWH(0, top + (bands - 1) * bh, size.width, bh);
    if (!locked) {
      canvas.drawRect(band, Paint()..color = const Color(0x55FFE08A));
      canvas.drawRect(band.deflate(1), Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = const Color(0xFFFFD66E));
    }
    canvas.restore();
    canvas.drawRRect(r, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = const Color(0xFF5A3E28));
    final tp = TextPainter(
      text: TextSpan(
          text: locked ? '?' : 'F$floor',
          style: const TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w900, fontSize: 15, color: Color(0xFFFFF4E2), shadows: [
            Shadow(color: Color(0xCC000000), offset: Offset(0, 1), blurRadius: 2),
          ])),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset((size.width - tp.width) / 2, band.center.dy - tp.height / 2));
  }

  @override
  bool shouldRepaint(_Strata old) => old.floor != floor || old.deepest != deepest || old.locked != locked;
}
