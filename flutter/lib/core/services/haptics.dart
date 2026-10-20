// The game's haptic vocabulary: one short, named feel per moment, played alongside the matching sound.
// On phones with a vibration motor that takes patterns (Android 8+, iPhones with Core Haptics) a feel
// is a little waveform with strengths (a purr, a swell, a rumble); elsewhere it falls back to the
// system's taps on a timer. Desktop and web: nothing. The player's Haptics switch (Profile) gates it
// all, through AudioService. Keep them short and rare: a buzz on every tap gets switched off.

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:vibration/vibration.dart';

enum Haptic {
  tick, // a notch: tabs, toggles, a needle entering the gold
  tap, // a light confirm
  purr, // petting your Evochi: soft pulses
  hop, // Play: a little bounce
  glow, // Lumen Glow gathering: a swell
  hit, // your move lands
  soothe, // Soothe: two slow, soft breaths
  surge, // the Hollow surges: a sharp hit
  hurt, // it lashes out at your Evochi: Energy lost
  win, // calmed or restored
  rumble, // the Sentinel stirring: long and low
  thump, // a big landing: eyes lighting, an evolution's last beat
  reward, // a chime: a reward, a quest step
  levelUp,
  evolve, // a build-up that lands
  purchase,
  harvest, // a crop pops out of the bed
  equip, // a snap: it's on
  error, // a short double buzz
  perfect, // a perfect bake or brew
  good, // a good one
}

/// (wait, buzz, wait, buzz...) in ms with a strength 1-255 for each step (0 for the waits), and a
/// fallback of (delay ms, system tap) for phones without patterns.
class _Feel {
  const _Feel(this.timings, this.amps, this.fallback);
  final List<int> timings;
  final List<int> amps;
  final List<(int, _Tap)> fallback;
}

enum _Tap { selection, light, medium, heavy }

const _feels = <Haptic, _Feel>{
  Haptic.tick: _Feel([0, 10], [0, 90], [(0, _Tap.selection)]),
  Haptic.tap: _Feel([0, 16], [0, 120], [(0, _Tap.light)]),
  Haptic.purr: _Feel(
    [0, 26, 74, 30, 70, 32, 70, 30, 74, 26],
    [0, 55, 0, 75, 0, 85, 0, 70, 0, 50],
    [(0, _Tap.light), (110, _Tap.light), (220, _Tap.light), (330, _Tap.light)],
  ),
  Haptic.hop: _Feel([0, 22, 90, 34], [0, 110, 0, 190], [(0, _Tap.light), (110, _Tap.medium)]),
  Haptic.glow: _Feel([0, 40, 30, 50, 30, 60], [0, 50, 0, 100, 0, 160], [(0, _Tap.light), (80, _Tap.light), (160, _Tap.medium)]),
  Haptic.hit: _Feel([0, 34], [0, 200], [(0, _Tap.medium)]),
  Haptic.soothe: _Feel([0, 70, 200, 70], [0, 60, 0, 60], [(0, _Tap.light), (260, _Tap.light)]),
  Haptic.surge: _Feel([0, 45, 40, 30], [0, 255, 0, 150], [(0, _Tap.heavy), (80, _Tap.light)]),
  Haptic.hurt: _Feel([0, 38, 30, 22], [0, 230, 0, 120], [(0, _Tap.heavy)]),
  Haptic.win: _Feel([0, 30, 70, 30, 70, 70], [0, 150, 0, 190, 0, 255], [(0, _Tap.light), (100, _Tap.medium), (200, _Tap.heavy)]),
  Haptic.rumble: _Feel(
    [0, 140, 0, 140, 0, 140, 0, 160],
    [0, 45, 0, 65, 0, 85, 0, 110],
    [(0, _Tap.light), (140, _Tap.light), (280, _Tap.medium), (420, _Tap.medium)],
  ),
  Haptic.thump: _Feel([0, 70], [0, 255], [(0, _Tap.heavy)]),
  Haptic.reward: _Feel([0, 24, 60, 30], [0, 120, 0, 170], [(0, _Tap.light), (85, _Tap.medium)]),
  Haptic.levelUp: _Feel([0, 30, 60, 30, 60, 50], [0, 140, 0, 180, 0, 230], [(0, _Tap.medium), (90, _Tap.medium), (180, _Tap.heavy)]),
  Haptic.evolve: _Feel(
    [0, 120, 0, 120, 0, 120, 60, 90],
    [0, 50, 0, 80, 0, 120, 0, 255],
    [(0, _Tap.light), (120, _Tap.medium), (240, _Tap.medium), (420, _Tap.heavy)],
  ),
  Haptic.purchase: _Feel([0, 28, 50, 40], [0, 150, 0, 220], [(0, _Tap.medium), (80, _Tap.heavy)]),
  Haptic.harvest: _Feel([0, 18], [0, 190], [(0, _Tap.medium)]),
  Haptic.equip: _Feel([0, 16], [0, 230], [(0, _Tap.heavy)]),
  Haptic.error: _Feel([0, 40, 60, 40], [0, 170, 0, 170], [(0, _Tap.medium), (100, _Tap.medium)]),
  Haptic.perfect: _Feel([0, 40, 50, 80], [0, 200, 0, 255], [(0, _Tap.medium), (90, _Tap.heavy)]),
  Haptic.good: _Feel([0, 30], [0, 150], [(0, _Tap.medium)]),
};

class Haptics {
  bool _ready = false;
  bool _motor = false; // the vibration plugin can drive it at all
  bool _patterns = false; // timed patterns
  bool _amps = false; // strengths
  int _lastAt = 0;
  Haptic? _last;

  bool get _phone => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  /// Ask the phone what its motor can do (once, at start; safe to call anywhere).
  Future<void> init() async {
    if (_ready || !_phone) return;
    _ready = true;
    try {
      _motor = await Vibration.hasVibrator();
      if (_motor) {
        _patterns = await Vibration.hasCustomVibrationsSupport();
        _amps = await Vibration.hasAmplitudeControl();
      }
    } catch (_) {
      _motor = false;
    }
  }

  /// Play [h] at [strength] (0-1, scales the pattern's strengths). The same feel twice within 60 ms
  /// plays once (two sounds of one moment shouldn't double it).
  void play(Haptic h, {double strength = 1}) {
    if (!_phone) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (_last == h && now - _lastAt < 60) return;
    _last = h;
    _lastAt = now;
    final f = _feels[h]!;
    if (_motor && _patterns && h != Haptic.tick) {
      final k = strength.clamp(0.3, 1.0);
      final run = _amps
          ? Vibration.vibrate(pattern: f.timings, intensities: [for (final a in f.amps) a == 0 ? 0 : (a * k).round().clamp(1, 255)])
          : Vibration.vibrate(pattern: f.timings);
      unawaited(run.catchError((_) {}));
      return;
    }
    for (final (delay, tap) in f.fallback) {
      if (delay == 0) {
        _tap(tap);
      } else {
        Timer(Duration(milliseconds: delay), () => _tap(tap));
      }
    }
  }

  void stop() {
    if (!_phone || !_motor) return;
    unawaited(Vibration.cancel().catchError((_) {}));
  }

  static void _tap(_Tap t) {
    switch (t) {
      case _Tap.selection:
        HapticFeedback.selectionClick();
      case _Tap.light:
        HapticFeedback.lightImpact();
      case _Tap.medium:
        HapticFeedback.mediumImpact();
      case _Tap.heavy:
        HapticFeedback.heavyImpact();
    }
  }
}
