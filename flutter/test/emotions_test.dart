// The emotion config (assets/config/emotions.json) stays inside what the game can draw: every face is one the
// atlases have, every motion one the scene knows, every "next" and event points at an emotion that exists.

import 'dart:io';

import 'package:evochi/game/emotion/emotion.dart';
import 'package:flutter_test/flutter_test.dart';

const _evochiFaces = {'default', 'blink', 'happy', 'curious', 'surprised', 'determined', 'sad', 'sleepy', 'excited', 'neutral', 'sick', 'memorial'};
const _villagerFaces = {'neutral', 'happy', 'worried', 'thinking', 'proud'};
const _motions = {'none', 'bounce', 'hop', 'tilt', 'wiggle', 'jolt', 'droop', 'stomp', 'cower', 'lean', 'sway', 'nuzzle', 'emerge'};

void main() {
  setUpAll(() => Emotions.parse(File('assets/config/emotions.json').readAsStringSync()));

  test('all eleven emotions are there', () {
    for (final n in Emotions.names) {
      expect(Emotions.of(n), isNotNull, reason: n);
    }
  });

  test('faces and motions are ones the game has', () {
    for (final e in Emotions.table.values) {
      expect(_evochiFaces, contains(e.face('evochi')), reason: e.id);
      expect(_villagerFaces, contains(e.face('villager')), reason: e.id);
      if (e.end('evochi') != null) expect(_evochiFaces, contains(e.end('evochi')), reason: e.id);
      expect(_motions, contains(e.motion), reason: e.id);
      expect(e.ms, inInclusiveRange(200, 4000), reason: e.id);
      expect(['hearts', 'stars', null], contains(e.particles), reason: e.id);
    }
  });

  test('what an emotion settles into exists, and no chain loops', () {
    for (final e in Emotions.table.values) {
      final seen = <String>{e.id};
      var n = e.next;
      while (n != null) {
        expect(Emotions.of(n), isNotNull, reason: '${e.id} -> $n');
        expect(seen.add(n), isTrue, reason: 'loop through $n');
        n = Emotions.of(n)!.next;
      }
    }
  });

  test('every game event maps to an emotion at a sane intensity', () {
    expect(Emotions.events, isNotEmpty);
    for (final e in Emotions.events.entries) {
      expect(Emotions.of(e.value.$1), isNotNull, reason: e.key);
      expect(e.value.$2, inInclusiveRange(0.1, 1.0), reason: e.key);
    }
  });
}
