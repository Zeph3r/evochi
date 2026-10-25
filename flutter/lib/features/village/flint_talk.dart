// Flint at the Crossing, on the Old Trail: a short conversation in the world rather than a new screen,
// with the four things you come to him for (MINES_PLAN.md): about the mines, mining gear (his shop opens),
// going in, and what ore is for. The mine itself is next to build; until then he says it's nearly ready.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme.dart';
import '../shared/widgets.dart';

/// Flint's faces for talking (tools/art/flint_walk.py: assets/art/trail/flint.json).
class FlintFaces {
  FlintFaces(Map<String, dynamic> j)
      : faces = {
          for (final e in (j['faces'] as Map).entries)
            e.key as String: (
              (e.value as Map)['src'] as String,
              Size(((e.value as Map)['w'] as num).toDouble(), ((e.value as Map)['h'] as num).toDouble()),
              _off((e.value as Map)['face'] as List),
              _off((e.value as Map)['headTop'] as List),
            )
        };
  static Offset _off(List v) => Offset((v[0] as num).toDouble(), (v[1] as num).toDouble());
  final Map<String, (String, Size, Offset, Offset)> faces; // src, size, face point, head top

  static FlintFaces? _cache;
  static Future<FlintFaces> load() async =>
      _cache ??= FlintFaces((jsonDecode(await rootBundle.loadString('assets/art/trail/flint.json')) as Map).cast<String, dynamic>());
}

typedef _Line = (String face, String text);

const _hello = <_Line>[
  ('happy', "Well now, a visitor up the Old Trail! These hills are full of good rock. Keep the mines running, and the village keeps shining. What do you need?"),
];

const _topics = <String, List<_Line>>{
  'mines': [
    ('default', "It's a working mine, not a battlefield. I keep the corridors lit and shored. You'll find ore, old fossils, and the odd burrowing critter minding its own business."),
    ('happy', "Want a feel for it first? There's a copper vein right by the yard. Walk up to it and Pounce. Your Evochi already knows the move."),
    ('thinking', "Lately, though... some of the lumen crystals hum when someone walks past. Like the Heartroot does. Old tunnels have shifted, and shafts I sealed years back are opening up again."),
    ('determined', "Stay to the lit corridors and you'll come home with a full satchel. The deep shafts can wait till you're ready for them."),
  ],
  'gear': [
    ('happy', "Good gear makes for happier miners! Headlamps, paw guards, satchels, a lantern or two. All of it earned with coins and ore, mind."),
    ('default', "I'm still sorting the stock. Come back soon and I'll fit your Evochi out proper."),
  ],
  'enter': [
    ('determined', "Eager, eh? I like that. The first gallery's lit and shored. Copper in every wall, and a vein of iron if you look."),
    ('happy', "Walk up to a node and Pounce. Mind the shaft at the back: it goes down to the next gallery, and the rock's harder there."),
  ],
  'ore': [
    ('default', "Four kinds you'll meet. Copper's warm and crumbly, good for tools and trim. Iron's tougher: frames and sturdier gear."),
    ('thinking', "Lumen crystal glows on its own; it goes into lamps and the village's mending. Obsidian's volcanic glass. You don't melt it, you shape it, chip by chip."),
    ('happy', "Bring what you find to Bram in the village. He'll forge something worth keeping, and it'll remember where its ore came from."),
  ],
};

const _choices = [
  ('mines', 'discover', 'Ask about the mines', 'Tell me more about this place.'),
  ('gear', 'shop', 'Buy mining gear', 'I need better tools and equipment.'),
  ('enter', 'aff_stone', 'Enter the mine', "I'm ready to head in."),
  ('ore', 'gem', 'What ore is for', 'What can I do with the ores I find?'),
];

/// Talk to Flint (a sheet over the trail). Returns the choice that leads somewhere ('gear', 'enter'), or null.
Future<String?> showFlintTalk(BuildContext context) async {
  final faces = await FlintFaces.load();
  if (!context.mounted) return null;
  return showEvochiSheet<String>(context, builder: (_) => FlintTalk(faces: faces));
}

class FlintTalk extends StatefulWidget {
  const FlintTalk({super.key, required this.faces});
  final FlintFaces faces;

  @override
  State<FlintTalk> createState() => _FlintTalkState();
}

class _FlintTalkState extends State<FlintTalk> {
  List<_Line> _lines = _hello;
  int _i = 0;
  String? _then; // what the talk leads to once these lines are read
  bool get _last => _i >= _lines.length - 1;

  void _next() {
    if (_last && _then != null) {
      Navigator.of(context).pop(_then);
      return;
    }
    setState(() => _i++);
  }

  void _pick(String topic) {
    if (topic == 'gear') {
      Navigator.of(context).pop('gear'); // his shop opens
      return;
    }
    setState(() {
      _lines = _topics[topic]!;
      _i = 0;
      _then = topic == 'enter' ? 'enter' : null; // after his words, off to the mine
    });
  }

  @override
  Widget build(BuildContext context) {
    final (face, text) = _lines[_i];
    return Semantics(
      container: true,
      label: 'Talking with Flint',
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _Portrait(faces: widget.faces, expr: face),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Flint', style: TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w900, fontSize: 18, color: EvochiColor.ink)),
              const SizedBox(height: 2),
              const Text('Keeper of the mines', style: TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w700, fontSize: 12.5, color: EvochiColor.textHelper)),
              const SizedBox(height: 8),
              Text(text, style: const TextStyle(fontFamily: EvochiText.body, fontSize: 15.5, height: 1.35, color: EvochiColor.ink)),
            ]),
          ),
        ]),
        const SizedBox(height: 12),
        if (!_last || _then != null)
          Align(
            alignment: Alignment.centerRight,
            child: EvochiButton(label: _last ? 'Head in' : 'Next', tone: _last ? ButtonTone.gold : ButtonTone.cream, small: true, expand: false, onPressed: _next),
          )
        else ...[
          for (final (id, icon, title, sub) in _choices)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _Choice(icon: icon, title: title, sub: sub, onTap: () => _pick(id)),
            ),
          Align(
            alignment: Alignment.centerRight,
            child: EvochiButton(label: 'Leave', tone: ButtonTone.cream, small: true, expand: false, onPressed: () => Navigator.of(context).pop()),
          ),
        ],
      ]),
    );
  }
}

/// Flint's head, round (his face image framed on its face point).
class _Portrait extends StatelessWidget {
  const _Portrait({required this.faces, required this.expr});
  final FlintFaces faces;
  final String expr;

  @override
  Widget build(BuildContext context) {
    const d = 92.0;
    final (src, size, face, top) = faces.faces[expr] ?? faces.faces['default']!;
    final s = d / ((face.dy - top.dy) * 2.1);
    final centre = Offset(face.dx, (face.dy + top.dy) / 2);
    return Container(
      width: d,
      height: d,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFFE9D3B4),
        border: Border.all(color: EvochiColor.wood, width: 3),
      ),
      child: ClipOval(
        child: Stack(clipBehavior: Clip.hardEdge, children: [
          Positioned(
            left: d / 2 - centre.dx * s,
            top: d / 2 - centre.dy * s,
            width: size.width * s,
            height: size.height * s,
            child: Image.asset(src, fit: BoxFit.fill, filterQuality: FilterQuality.medium, excludeFromSemantics: true, gaplessPlayback: true),
          ),
        ]),
      ),
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({required this.icon, required this.title, required this.sub, required this.onTap});
  final String icon, title, sub;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: title,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.fromLTRB(10, 8, 12, 8),
            decoration: BoxDecoration(
              color: EvochiColor.shell,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: EvochiColor.border, width: 1.5),
            ),
            child: Row(children: [
              VoxelIcon(icon, size: 30),
              const SizedBox(width: 10),
              Expanded(
                child: ExcludeSemantics(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title, style: const TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w900, fontSize: 15, color: EvochiColor.ink)),
                    Text(sub, style: const TextStyle(fontFamily: EvochiText.body, fontSize: 12.5, color: EvochiColor.textSecondary)),
                  ]),
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: EvochiColor.wood),
            ]),
          ),
        ),
      );
}
