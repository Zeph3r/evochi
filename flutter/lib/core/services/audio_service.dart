// Sound effects + the looping track (the meadow ambience by default; encounters switch it to their own
// loops with a crossfade). Respects the sound/music settings (style guide §20). Mirrors
// web/src/ui/audio.js.

import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart' hide AssetManifest;

import 'asset_manifest.dart';

const defaultLoop = 'ambient_meadow_loop';

class AudioService {
  AudioPlayer _ambient = AudioPlayer();
  final List<AudioPlayer> _pool = List.generate(4, (_) => AudioPlayer());
  int _next = 0;
  bool sound = true;
  bool music = true;
  bool haptics = true;
  bool _ambientOn = false;
  String _loopName = defaultLoop; // the track that should be playing (a name without a file is silence)
  String _playing = defaultLoop; // the track the live player has
  Timer? _fadeIn;

  void configure({required bool sound, required bool music, required bool haptics}) {
    this.sound = sound;
    this.haptics = haptics;
    if (this.music != music) {
      this.music = music;
      music ? startAmbient() : stopAmbient();
    }
  }

  String? _rel(String name) {
    final p = AssetManifest.instance?.audio(name);
    // audioplayers' AssetSource is relative to assets/
    return p?.replaceFirst('assets/', '');
  }

  Future<void> play(String name, {double volume = 0.8}) async {
    if (!sound) return;
    final rel = _rel(name);
    if (rel == null) return;
    final p = _pool[_next];
    _next = (_next + 1) % _pool.length;
    try {
      await p.stop();
      await p.setVolume(volume);
      await p.play(AssetSource(rel));
    } catch (_) {}
  }

  double _loopVolume(String name) => name == defaultLoop ? 0.3 : 0.5;

  /// Start the current loop, fading in over [fade] seconds (0: at once).
  Future<void> startAmbient({double fade = 0}) async {
    if (!music || _ambientOn) return;
    final name = _loopName;
    final rel = _rel(name);
    if (rel == null) return; // 'none' and unknown names: silence
    _ambientOn = true;
    _playing = name;
    final player = _ambient;
    final target = _loopVolume(name);
    try {
      await player.setReleaseMode(ReleaseMode.loop);
      await player.setVolume(fade > 0 ? 0 : target);
      await player.play(AssetSource(rel));
      if (fade > 0) _ramp(player, 0, target, fade);
    } catch (_) {
      if (identical(player, _ambient)) _ambientOn = false;
    }
  }

  /// Stop the loop, fading out over [fade] seconds (0: at once). The player is handed off so a new
  /// loop can start while this one fades.
  Future<void> stopAmbient({double fade = 0}) async {
    _fadeIn?.cancel();
    _fadeIn = null;
    final old = _ambient;
    final wasOn = _ambientOn;
    _ambientOn = false;
    if (!wasOn) return;
    if (fade > 0) {
      _ambient = AudioPlayer();
      _ramp(old, _loopVolume(_playing), 0, fade, then: () async {
        try {
          await old.stop();
          await old.dispose();
        } catch (_) {}
      });
      return;
    }
    try {
      await old.stop();
    } catch (_) {}
  }

  /// Switch the looping track (null = the meadow ambience), crossfading. Encounters use their own
  /// loops; a name with no file (e.g. 'none') plays silence until the next switch.
  void setMusic(String? name, {double fade = 0.8}) {
    final want = name ?? defaultLoop;
    if (want == _loopName && (_ambientOn || !music)) return;
    _loopName = want;
    if (!music) return;
    stopAmbient(fade: fade);
    startAmbient(fade: fade);
  }

  /// Linear volume ramp in 40 ms steps (audioplayers has no scheduled gain).
  void _ramp(AudioPlayer p, double from, double to, double seconds, {Future<void> Function()? then}) {
    final steps = (seconds * 25).ceil().clamp(1, 200);
    var i = 0;
    final t = Timer.periodic(const Duration(milliseconds: 40), (timer) async {
      i++;
      final v = from + (to - from) * (i / steps);
      try {
        await p.setVolume(v.clamp(0.0, 1.0));
      } catch (_) {}
      if (i >= steps) {
        timer.cancel();
        if (then != null) await then();
      }
    });
    if (then == null) _fadeIn = t;
  }

  void tick() {
    if (haptics) HapticFeedback.selectionClick();
  }

  void bump() {
    if (haptics) HapticFeedback.lightImpact();
  }
}
