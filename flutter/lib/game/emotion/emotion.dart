// Character emotions as data (assets/config/emotions.json): what each one looks like on a face and in a body,
// how long it lasts, what it gives way to, and how much it matters next to what is already playing. One layer
// over the scene's reactions (SceneController.feel), so screens and story beats say how a character feels,
// and the character's own personality decides how big and how quick that looks.

import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

class EmotionDef {
  const EmotionDef({required this.id, required this.faces, required this.motion, required this.ms, this.priority = 1, this.ends = const {}, this.particles, this.next});
  final String id;

  /// the face per kind of character ('evochi', 'villager')
  final Map<String, String> faces;
  final String motion;
  final int ms;
  final int priority;
  final Map<String, String> ends;
  final String? particles;
  final String? next;

  String face(String kind) => faces[kind] ?? faces['evochi'] ?? 'neutral';
  String? end(String kind) => ends[kind];

  factory EmotionDef.fromJson(String id, Map<String, dynamic> j) => EmotionDef(
        id: id,
        faces: ((j['face'] as Map?) ?? const {}).cast<String, String>(),
        motion: (j['motion'] as String?) ?? 'none',
        ms: ((j['ms'] as num?) ?? 1000).toInt(),
        priority: ((j['priority'] as num?) ?? 1).toInt(),
        ends: ((j['end'] as Map?) ?? const {}).cast<String, String>(),
        particles: j['particles'] as String?,
        next: j['next'] as String?,
      );
}

class Emotions {
  Emotions._();

  /// the eleven the game speaks in; config entries beyond these work too
  static const names = ['neutral', 'happy', 'excited', 'curious', 'surprised', 'sad', 'frustrated', 'afraid', 'determined', 'sleepy', 'affectionate'];

  static Map<String, EmotionDef> table = const {};

  /// engine event type -> how your Evochi takes it (emotion, intensity)
  static Map<String, (String, double)> events = const {};

  static EmotionDef? of(String id) => table[id];

  static (String, double)? forEvent(String type) => events[type];

  static void parse(String text) {
    final j = jsonDecode(text) as Map<String, dynamic>;
    table = {for (final e in (j['emotions'] as Map<String, dynamic>).entries) e.key: EmotionDef.fromJson(e.key, (e.value as Map).cast<String, dynamic>())};
    events = {
      for (final e in ((j['events'] as Map<String, dynamic>?) ?? const {}).entries)
        if (table.containsKey((e.value as List)[0])) e.key: ((e.value as List)[0] as String, ((e.value as List)[1] as num).toDouble()),
    };
  }

  static Future<void> load() async {
    try {
      parse(await rootBundle.loadString('assets/config/emotions.json'));
    } catch (_) {
      table = const {};
      events = const {};
    }
  }
}
