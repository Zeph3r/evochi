// The first hatch's config (assets/config/hatch.json) plays as written: its sounds exist, its feels are real
// haptics, every egg has a style, the shell breaks before the creature comes out, and the name comes last.

import 'dart:io';

import 'package:evochi/app/constants.dart';
import 'package:evochi/core/services/haptics.dart';
import 'package:evochi/features/onboarding/hatch_timeline.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the plan loads from the config, not the fallback', () async {
    final p = await HatchPlan.load();
    expect(identical(p, HatchPlan.fallback), isFalse);
    expect(p.beats.length, greaterThan(5));
  });

  test('sounds, feels and styles are real', () async {
    final p = await HatchPlan.load();
    for (final b in p.beats) {
      if (b.sfx != null) expect(File('assets/audio/sfx/${b.sfx}.mp3').existsSync(), isTrue, reason: b.sfx);
      if (b.buzz != null) expect(Haptic.values.asNameMap().containsKey(b.buzz), isTrue, reason: b.buzz);
    }
    for (final pal in palettes) {
      expect(p.styles.containsKey(pal.id), isTrue, reason: pal.id);
      expect(['motes', 'leaves', 'sparks', 'droplets', 'grit', 'stars'], contains(p.style(pal.id).burst));
    }
  });

  test('the order holds: shakes, cracks, burst, out, then the name', () async {
    final p = await HatchPlan.load();
    final emerge = p.beats.firstWhere((b) => b.react == 'emerge').t;
    expect(p.crackFrom, lessThan(p.burst));
    expect(p.beats.where((b) => b.shake > 0).every((b) => b.t < p.crackFrom), isTrue);
    expect(emerge, greaterThanOrEqualTo(p.burst));
    expect(p.beats.every((b) => b.t < p.naming), isTrue);
    expect(p.crack(p.burst), 3);
    expect(p.crack(0), 0);
    // a shake moves it; between them it is still
    final shake = p.beats.firstWhere((b) => b.shake > 0);
    expect(p.shake(shake.t + 0.05).$1, isNot(0));
    expect(p.shake(0.3), (0.0, 0.0));
  });
}
