// Sound effects + ambient loop. Respects the sound/music settings (style guide §20).

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';

import 'asset_manifest.dart';

class AudioService {
  final AudioPlayer _ambient = AudioPlayer();
  final List<AudioPlayer> _pool = List.generate(4, (_) => AudioPlayer());
  int _next = 0;
  bool sound = true;
  bool music = true;
  bool haptics = true;
  bool _ambientOn = false;

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

  Future<void> startAmbient() async {
    if (!music || _ambientOn) return;
    final rel = _rel('ambient_meadow_loop');
    if (rel == null) return;
    _ambientOn = true;
    try {
      await _ambient.setReleaseMode(ReleaseMode.loop);
      await _ambient.setVolume(0.3);
      await _ambient.play(AssetSource(rel));
    } catch (_) {
      _ambientOn = false;
    }
  }

  Future<void> stopAmbient() async {
    _ambientOn = false;
    try {
      await _ambient.stop();
    } catch (_) {}
  }

  void tick() {
    if (haptics) HapticFeedback.selectionClick();
  }

  void bump() {
    if (haptics) HapticFeedback.lightImpact();
  }
}
