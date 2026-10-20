// Sound effects + the looping track. The track follows where you are: each place screen wraps itself
// in an Ambience (lib/features/shared/ambience.dart) and the newest one on screen wins (the Nest's
// meadow when there's none); an encounter's music overrides the place while it runs. Place beds
// (amb_*) crossfade into their next pass instead of relying on the codec's loop, so an mp3's padding
// never leaves a gap. Respects the sound/music settings (style guide §20).

import 'dart:async';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';

import 'asset_manifest.dart';
import 'haptics.dart';

const defaultLoop = 'ambient_meadow_loop';

/// The sounds that carry a feel of their own (see haptics.dart): the buzz plays with the sound, even
/// when the sound is off, as long as Haptics is on. Its strength follows the sound's volume.
const _soundFeel = <String, Haptic>{
  'pet_chirp': Haptic.purr,
  'play_boing': Haptic.hop,
  'reward_chime': Haptic.reward,
  'level_up': Haptic.levelUp,
  'evolve_fanfare': Haptic.evolve,
  'purchase': Haptic.purchase,
  'error_bonk': Haptic.error,
  'enc_glow': Haptic.glow,
  'enc_soothe': Haptic.soothe,
  'enc_surge': Haptic.surge,
  'enc_rumble': Haptic.rumble,
  'enc_awaken': Haptic.thump,
};

/// How loud each loop plays. The beds are quiet on purpose: the kitchen fire is a faint crackle.
const _loopVolumes = <String, double>{
  defaultLoop: 0.3,
  'amb_home': 0.42,
  'amb_village': 0.45,
  'amb_kitchen': 0.32,
  'amb_apothecary': 0.38,
  'amb_workshop': 0.36,
  'amb_lodge': 0.36,
  'amb_glasshouse': 0.4,
  'amb_forest': 0.45,
  'amb_hollow': 0.45,
  'amb_dusk': 0.42,
  'amb_market': 0.38,
};

class _Place {
  _Place(this.token, this.name, this.gain);
  final Object token;
  String name;
  double gain;
}

class AudioService {
  final List<AudioPlayer> _pool = List.generate(4, (_) => AudioPlayer());
  int _next = 0;
  bool sound = true;
  bool music = true;
  bool haptics = true;
  _Bed? _bed; // the loop that's playing (null: none)
  String _loopName = defaultLoop; // the track that should be playing (a name without a file is silence)
  final List<_Place> _places = []; // the place screens on show, oldest first
  String? _music; // an encounter's track, over any place
  Timer? _settle;

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
    var feel = _soundFeel[name];
    // a quiet chime (a toggle, a small confirm) is only a notch
    if (feel == Haptic.reward && volume < 0.5) feel = Haptic.tick;
    if (feel != null) buzz(feel, strength: 0.45 + volume * 0.65);
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

  double _loopVolume(String name) => (_loopVolumes[name] ?? 0.5) * (_music != null || _places.isEmpty ? 1.0 : _places.last.gain);

  /// Start the current loop, fading in over [fade] seconds (0: at once).
  Future<void> startAmbient({double fade = 0}) async {
    if (!music || _bed != null) return;
    final name = _loopName;
    final rel = _rel(name);
    if (rel == null) return; // 'none' and unknown names: silence
    final bed = _Bed(rel, _loopVolume(name), crossLoop: name == defaultLoop || name.startsWith('amb_'));
    _bed = bed;
    await bed.start(fade);
  }

  /// Stop the loop, fading out over [fade] seconds (0: at once). A new loop can start while this one
  /// fades.
  Future<void> stopAmbient({double fade = 0}) async {
    final bed = _bed;
    _bed = null;
    await bed?.stop(fade);
  }

  /// An encounter's track (null: back to the place's). A name with no file (e.g. 'none') plays
  /// silence until it's cleared.
  void setMusic(String? name, {double fade = 0.8}) {
    _music = name;
    _apply(fade: fade);
  }

  /// A place screen came on show with its bed ([gain] scales its volume: louder at the oven's mouth).
  void pushAmbience(Object token, String name, {double gain = 1}) {
    _places.removeWhere((p) => identical(p.token, token));
    _places.add(_Place(token, name, gain));
    _later();
  }

  /// A place screen changed its bed or its gain.
  void updateAmbience(Object token, String name, {double gain = 1}) {
    final p = _places.where((p) => identical(p.token, token)).firstOrNull;
    if (p == null) return pushAmbience(token, name, gain: gain);
    if (p.name == name && p.gain == gain) return;
    p
      ..name = name
      ..gain = gain;
    _later();
  }

  /// A place screen left.
  void popAmbience(Object token) {
    final n = _places.length;
    _places.removeWhere((p) => identical(p.token, token));
    if (_places.length != n) _later();
  }

  // routes swap places in a burst (one leaves as the next arrives): settle before switching
  void _later() {
    _settle?.cancel();
    _settle = Timer(const Duration(milliseconds: 60), () => _apply(fade: 1.2));
  }

  void _apply({double fade = 0.8}) {
    final want = _music ?? (_places.isEmpty ? defaultLoop : _places.last.name);
    if (want == _loopName) {
      _bed?.setVolume(_loopVolume(want), 0.8); // the same bed, maybe at a new gain
      if (_bed == null && music) startAmbient(fade: fade);
      return;
    }
    _loopName = want;
    if (!music) return;
    stopAmbient(fade: fade);
    startAmbient(fade: fade);
  }

  /// The phone's motor (see haptics.dart), behind the Haptics switch.
  final Haptics hx = Haptics();

  /// Play a named feel (behind the Haptics switch).
  void buzz(Haptic h, {double strength = 1}) {
    if (haptics) hx.play(h, strength: strength);
  }

  void tick() => buzz(Haptic.tick);

  void bump() => buzz(Haptic.tap);
}

/// One looping track. Music loops on the player; a bed starts its next pass a few seconds before
/// this one ends and crossfades (equal power), so the loop never clicks or gaps.
class _Bed {
  _Bed(this.rel, this.volume, {required this.crossLoop});
  final String rel;
  double volume;
  final bool crossLoop;
  static const _overlap = 2.5; // s

  final _vol = <AudioPlayer, double>{};
  final _ramps = <AudioPlayer, Timer>{};
  AudioPlayer? _current;
  Timer? _nextPass;
  bool _stopped = false;

  Future<void> start(double fade) => _pass(fade);

  Future<void> _pass(double fade) async {
    if (_stopped) return;
    final p = AudioPlayer();
    final prev = _current;
    _current = p;
    _vol[p] = 0;
    try {
      await p.setReleaseMode(crossLoop ? ReleaseMode.stop : ReleaseMode.loop);
      await p.setVolume(fade > 0 ? 0 : volume);
      _vol[p] = fade > 0 ? 0 : volume;
      await p.play(AssetSource(rel));
      if (_stopped) return _kill(p);
      if (fade > 0) _ramp(p, volume, fade, rising: true);
      if (prev != null) _ramp(prev, 0, fade, then: () => _kill(prev));
      if (!crossLoop) return;
      final d = await p.getDuration();
      final secs = (d?.inMilliseconds ?? 0) / 1000.0;
      if (secs < _overlap * 3 || _stopped) return; // too short to crossfade: it simply ends
      _nextPass?.cancel();
      _nextPass = Timer(Duration(milliseconds: ((secs - _overlap) * 1000).round()), () => _pass(_overlap));
    } catch (_) {
      if (identical(_current, p)) _current = null;
      await _kill(p);
    }
  }

  void setVolume(double v, double seconds) {
    volume = v;
    final p = _current;
    if (p != null && !_stopped) _ramp(p, v, seconds, rising: (_vol[p] ?? 0) < v);
  }

  Future<void> stop(double fade) async {
    _stopped = true;
    _nextPass?.cancel();
    for (final p in _vol.keys.toList()) {
      if (fade > 0) {
        _ramp(p, 0, fade, then: () => _kill(p));
      } else {
        await _kill(p);
      }
    }
  }

  Future<void> _kill(AudioPlayer p) async {
    _ramps.remove(p)?.cancel();
    _vol.remove(p);
    try {
      await p.stop();
      await p.dispose();
    } catch (_) {}
  }

  /// A volume ramp in 40 ms steps (audioplayers has no scheduled gain): rising on a sine, falling on a
  /// cosine, so two crossfading passes keep the same loudness.
  void _ramp(AudioPlayer p, double to, double seconds, {bool rising = false, Future<void> Function()? then}) {
    _ramps.remove(p)?.cancel();
    final from = _vol[p] ?? 0;
    final steps = (seconds * 25).ceil().clamp(1, 400);
    var i = 0;
    late final Timer timer;
    timer = Timer.periodic(const Duration(milliseconds: 40), (_) async {
      i++;
      final x = i / steps;
      final k = rising ? math.sin(x * math.pi / 2) : 1 - math.cos(x * math.pi / 2);
      final v = (from + (to - from) * k).clamp(0.0, 1.0).toDouble();
      _vol[p] = v;
      if (i >= steps) {
        timer.cancel();
        if (identical(_ramps[p], timer)) _ramps.remove(p);
      }
      try {
        await p.setVolume(v);
      } catch (_) {}
      if (i >= steps && then != null) await then();
    });
    _ramps[p] = timer;
  }
}
