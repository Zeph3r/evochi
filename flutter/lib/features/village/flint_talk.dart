// Flint at the Crossing, on the Old Trail: his faces for the chathead. He is a story NPC like the villagers
// (game/story: npc_flint, his lines and conversation in dialogue.dart): you tap him and he talks in the same
// chathead panel (chathead_talk.dart), about the mines, mining gear (his shop opens), going in, and ore.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

/// Flint's face for the chathead: his face image framed on its face point, filling [size] (the frame and
/// clipping are the chathead's).
class FlintHead extends StatelessWidget {
  const FlintHead({super.key, required this.expression, this.size = 108});
  final String expression;
  final double size;

  @override
  Widget build(BuildContext context) => FutureBuilder<FlintFaces>(
        future: FlintFaces.load(),
        builder: (context, snap) {
          final faces = snap.data;
          if (faces == null) return SizedBox.square(dimension: size);
          final (src, sz, face, top) = faces.faces[expression] ?? faces.faces['default']!;
          final s = size / ((face.dy - top.dy) * 2.1);
          final centre = Offset(face.dx, (face.dy + top.dy) / 2);
          return SizedBox.square(
            dimension: size,
            child: Stack(clipBehavior: Clip.hardEdge, children: [
              Positioned(
                left: size / 2 - centre.dx * s,
                top: size / 2 - centre.dy * s,
                width: sz.width * s,
                height: sz.height * s,
                child: Image.asset(src, fit: BoxFit.fill, filterQuality: FilterQuality.medium, excludeFromSemantics: true, gaplessPlayback: true),
              ),
            ]),
          );
        },
      );
}
