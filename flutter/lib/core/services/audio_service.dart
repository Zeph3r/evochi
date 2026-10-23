// Sound effects, place music and place ambience.
//
// Where you are decides what plays: each place screen wraps itself in an Ambience
// (lib/features/shared/ambience.dart) and the newest one on screen wins (the Nest when there's none).
// A place has two layers (placeSounds):
// - Music, behind the Music switch, indoors only: a small playlist of gentle arrangements of
//   public-domain airs (tools/art/music.py). A track plays once, then a quiet gap, then the next one.
//   An encounter's track overrides the place's while it runs.
// - An ambient bed, behind the Sound effects switch: the kitchen fire, the cauldron, the forge, the
//   stream, a waterfall (tools/art/ambience.py). Beds crossfade into their next pass instead of
//   relying on the codec's loop, so an mp3's padding never leaves a gap.

import 'dart:async';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';

import 'asset_manifest.dart';
import 'haptics.dart';

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
  // mining: the feel lands with the sound, on the Pounce's contact (and plays with the sound off)
  'mine_copper_chip': Haptic.mineLight,
  'mine_copper_crack': Haptic.mineMedium,
  'mine_copper_break': Haptic.mineHeavy,
  'mine_iron_chip': Haptic.mineMedium,
  'mine_iron_crack': Haptic.mineMedium,
  'mine_iron_break': Haptic.mineHeavy,
  'mine_lumen_chip': Haptic.mineChime,
  'mine_lumen_crack': Haptic.mineChime,
  'mine_lumen_break': Haptic.mineHeavy,
  'mine_obsidian_chip': Haptic.mineSnap,
  'mine_obsidian_crack': Haptic.mineSnap,
  'mine_obsidian_break': Haptic.mineShatter,
  'mine_collect': Haptic.mineCollect,
  'mine_clink': Haptic.mineClink,
};

/// What a place sounds like: an optional ambient bed and a playlist.
class PlaceSound {
  const PlaceSound({this.bed, required this.music, this.musicVolume = 0.5});
  final String? bed;
  final List<String> music;

  /// Lower where a bed plays, so the fire still reads under the tune.
  final double musicVolume;
}

// Music plays indoors only (the cottage's rooms, the village's houses); everywhere else keeps to its
// own sounds: the stream on the Square, the waterfall at the ruins, or quiet.
const placeSounds = <String, PlaceSound>{
  'nest': PlaceSound(music: []),
  'home': PlaceSound(music: []),
  'village': PlaceSound(bed: 'amb_village', music: []),
  'kitchen': PlaceSound(bed: 'amb_kitchen', music: ['mus_old_mill', 'mus_fair_maid', 'mus_skylark'], musicVolume: 0.38),
  'apothecary': PlaceSound(bed: 'amb_apothecary', music: ['mus_enchanted_valley', 'mus_dark_woman', 'mus_young_mans_dream'], musicVolume: 0.38),
  'workshop': PlaceSound(bed: 'amb_workshop', music: ['mus_bench_of_rushes', 'mus_my_love', 'mus_good_ship'], musicVolume: 0.38),
  'lodge': PlaceSound(music: ['mus_seaside', 'mus_black_rose', 'mus_fair_child']),
  'glasshouse': PlaceSound(bed: 'amb_glasshouse', music: ['mus_fairy_boy', 'mus_lullaby', 'mus_summer_morning', 'mus_red_lark']),
  'forest': PlaceSound(bed: 'amb_forest', music: []),
  'hollow': PlaceSound(bed: 'amb_forest', music: []),
  'dusk': PlaceSound(music: []),
  'market': PlaceSound(music: []),
};

/// How loud each bed plays (the kitchen fire is a faint crackle on purpose).
const _bedVolumes = <String, double>{
  'amb_village': 0.36,
  'amb_kitchen': 0.32,
  'amb_apothecary': 0.38,
  'amb_workshop': 0.36,
  'amb_glasshouse': 0.4,
  'amb_forest': 0.34,
};

const _bedSeconds = 40.0; // every bed is a 40 s loop (if the player can't say)

class _Place {
  _Place(this.token, this.place, this.gain);
  final Object token;
  String place;
  double gain;
}

class AudioService {
  /// Recording a Short (flutter/tool/shorts): nothing is played. Every sound and every change of music is
  /// written down with the moment it happened ([clock], in the video's seconds) for the mix.
  static List<Map<String, Object?>>? record;
  static double Function()? clock;

  late final List<AudioPlayer> _pool = List.generate(4, (_) => AudioPlayer());
  int _next = 0;
  bool sound = true;
  bool music = true;
  bool haptics = true;
  bool _paused = false; // the app is in the background
  final List<_Place> _places = []; // the place screens on show, oldest first
  String? _override; // an encounter's track
  Timer? _settle;
  _Bed? _bed;
  String? _bedName;
  late final _MusicBus _bus = _MusicBus(_rel);

  bool _configured = false;

  void configure({required bool sound, required bool music, required bool haptics}) {
    final first = !_configured;
    _configured = true;
    final s = this.sound != sound, m = this.music != music;
    this.sound = sound;
    this.music = music;
    this.haptics = haptics;
    if (s || first) _applyBed();
    if (m || first) _applyMusic(); // the first call (app start) begins the Nest's music
  }

  String? _rel(String name) {
    final p = AssetManifest.instance?.audio(name);
    // audioplayers' AssetSource is relative to assets/
    return p?.replaceFirst('assets/', '');
  }

  Future<void> play(String name, {double volume = 0.8}) async {
    final rec = record;
    if (rec != null) {
      rec.add({'t': clock?.call() ?? 0, 'sfx': name, 'vol': volume});
      return;
    }
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

  String get _place => _places.isEmpty ? 'nest' : _places.last.place;
  PlaceSound get _sounds => placeSounds[_place] ?? placeSounds['nest']!;

  /// Back from the background: the place's bed and music again.
  Future<void> startAmbient({double fade = 0.6}) async {
    _paused = false;
    _applyBed(fade: fade);
    _applyMusic();
  }

  /// Into the background: everything stops at once.
  Future<void> stopAmbient({double fade = 0}) async {
    _paused = true;
    final bed = _bed;
    _bed = null;
    _bedName = null;
    await bed?.stop(fade);
    _bus.stop(fade: fade);
  }

  /// An encounter's track (null: back to the place's music). A name with no file (e.g. 'none')
  /// is silence until it's cleared.
  void setMusic(String? name, {double fade = 0.8}) {
    _override = name;
    final rec = record;
    if (rec != null) {
      rec.add({'t': clock?.call() ?? 0, 'music': name, 'fade': fade});
      return;
    }
    _applyMusic();
  }

  /// A place screen came on show (or changed its gain).
  void updatePlace(Object token, String place, {double gain = 1}) {
    final p = _places.where((p) => identical(p.token, token)).firstOrNull;
    if (p == null) {
      _places.add(_Place(token, place, gain));
    } else {
      if (p.place == place && p.gain == gain) return;
      p
        ..place = place
        ..gain = gain;
    }
    _later();
  }

  /// A place screen left.
  void leavePlace(Object token) {
    final n = _places.length;
    _places.removeWhere((p) => identical(p.token, token));
    if (_places.length != n) _later();
  }

  // routes swap places in a burst (one leaves as the next arrives): settle before switching
  void _later() {
    _settle?.cancel();
    _settle = Timer(const Duration(milliseconds: 60), () {
      _applyBed();
      _applyMusic();
    });
  }

  void _applyBed({double fade = 1.2}) {
    if (_paused || record != null) return;
    final want = sound ? _sounds.bed : null;
    final gain = _places.isEmpty ? 1.0 : _places.last.gain;
    final vol = want == null ? 0.0 : (_bedVolumes[want] ?? 0.4) * gain;
    if (want == _bedName && _bed != null) {
      _bed!.setVolume(vol, 0.8);
      return;
    }
    _bed?.stop(fade);
    _bed = null;
    _bedName = want;
    if (want == null) return;
    final rel = _rel(want);
    if (rel == null) return;
    final bed = _Bed(rel, vol);
    _bed = bed;
    bed.start(fade);
  }

  void _applyMusic() {
    if (_paused || record != null) return;
    if (!music) {
      _bus.stop(fade: 1.0);
      return;
    }
    final o = _override;
    if (o != null) {
      _bus.want('encounter:$o', [o], 0.5, loop: true);
      return;
    }
    final s = _sounds;
    _bus.want(_place, s.music, s.musicVolume);
  }

  /// The phone's motor (see haptics.dart), behind the Haptics switch.
  final Haptics hx = Haptics();

  /// Play a named feel (behind the Haptics switch).
  void buzz(Haptic h, {double strength = 1}) {
    if (haptics && record == null) hx.play(h, strength: strength);
  }

  void tick() => buzz(Haptic.tick);

  void bump() => buzz(Haptic.tap);
}

/// Volume ramps for any player, in 40 ms steps (audioplayers has no scheduled gain): rising on a
/// sine, falling on a cosine, so two crossfading players keep the same loudness.
class _Fader {
  static final _vol = <AudioPlayer, double>{};
  static final _timers = <AudioPlayer, Timer>{};

  static double of(AudioPlayer p) => _vol[p] ?? 0;

  static Future<void> set(AudioPlayer p, double v) async {
    _timers.remove(p)?.cancel();
    _vol[p] = v;
    try {
      await p.setVolume(v);
    } catch (_) {}
  }

  static void ramp(AudioPlayer p, double to, double seconds, {Future<void> Function()? then}) {
    _timers.remove(p)?.cancel();
    final from = _vol[p] ?? 0;
    final rising = to > from;
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
        if (identical(_timers[p], timer)) _timers.remove(p);
      }
      try {
        await p.setVolume(v);
      } catch (_) {}
      if (i >= steps && then != null) await then();
    });
    _timers[p] = timer;
  }

  static Future<void> kill(AudioPlayer p) async {
    _timers.remove(p)?.cancel();
    _vol.remove(p);
    try {
      await p.stop();
      await p.dispose();
    } catch (_) {}
  }
}

/// One ambient bed. Each pass starts a few seconds before the last one ends and they crossfade; if
/// a pass ever ends first anyway, the next starts at once.
class _Bed {
  _Bed(this.rel, this.volume);
  final String rel;
  double volume;
  static const _overlap = 2.5; // s

  final _players = <AudioPlayer>{};
  AudioPlayer? _current;
  Timer? _nextPass;
  bool _stopped = false;

  Future<void> start(double fade) => _pass(fade);

  Future<void> _pass(double fade) async {
    if (_stopped) return;
    _nextPass?.cancel();
    final p = AudioPlayer();
    final prev = _current;
    _current = p;
    _players.add(p);
    try {
      await p.setReleaseMode(ReleaseMode.stop);
      await _Fader.set(p, fade > 0 ? 0 : volume);
      p.onPlayerComplete.listen((_) {
        _players.remove(p);
        _Fader.kill(p);
        // the pass ran out before its successor began (a long pause, a slow device): go again now
        if (identical(_current, p) && !_stopped) _pass(0.4);
      });
      await p.play(AssetSource(rel));
      if (_stopped) {
        _players.remove(p);
        return _Fader.kill(p);
      }
      if (fade > 0) _Fader.ramp(p, volume, fade);
      if (prev != null) {
        _Fader.ramp(prev, 0, fade, then: () async {
          _players.remove(prev);
          await _Fader.kill(prev);
        });
      }
      Duration? d;
      try {
        d = await p.getDuration();
      } catch (_) {}
      final secs = (d == null || d.inMilliseconds < 5000) ? _bedSeconds : d.inMilliseconds / 1000.0;
      if (_stopped) return;
      _nextPass = Timer(Duration(milliseconds: ((secs - _overlap) * 1000).round()), () => _pass(_overlap));
    } catch (_) {
      _players.remove(p);
      if (identical(_current, p)) _current = null;
      await _Fader.kill(p);
    }
  }

  void setVolume(double v, double seconds) {
    volume = v;
    final p = _current;
    if (p != null && !_stopped) _Fader.ramp(p, v, seconds);
  }

  Future<void> stop(double fade) async {
    _stopped = true;
    _nextPass?.cancel();
    for (final p in _players.toList()) {
      _players.remove(p);
      if (fade > 0) {
        _Fader.ramp(p, 0, fade, then: () => _Fader.kill(p));
      } else {
        await _Fader.kill(p);
      }
    }
  }
}

/// The music: a place's playlist, one track at a time with a quiet gap between, or one looping
/// track (an encounter's).
class _MusicBus {
  _MusicBus(this._rel);
  final String? Function(String) _rel;
  final _rng = math.Random();
  final _lastIndex = <String, int>{};
  AudioPlayer? _player;
  String? _key;
  List<String> _list = const [];
  bool _loop = false;
  double _volume = 0.5;
  Timer? _wait;

  /// Play [list] (keyed by its place, so the same place carries on) at [volume].
  void want(String key, List<String> list, double volume, {bool loop = false}) {
    if (key == _key) {
      if (volume != _volume) {
        _volume = volume;
        final p = _player;
        if (p != null) _Fader.ramp(p, volume, 0.8);
      }
      return;
    }
    final had = _player != null;
    _fadeOut(1.6);
    _wait?.cancel();
    _key = key;
    _list = list;
    _loop = loop;
    _volume = volume;
    // a breath between one place's tune and the next
    _wait = Timer(Duration(milliseconds: had ? 1800 : 700), _start);
  }

  void stop({double fade = 0}) {
    _wait?.cancel();
    _key = null;
    _fadeOut(fade);
  }

  void _fadeOut(double fade) {
    final p = _player;
    _player = null;
    if (p == null) return;
    if (fade > 0) {
      _Fader.ramp(p, 0, fade, then: () => _Fader.kill(p));
    } else {
      _Fader.kill(p);
    }
  }

  Future<void> _start() async {
    final key = _key;
    if (key == null || _list.isEmpty) return;
    final String name;
    if (_loop) {
      name = _list.first;
    } else {
      // the next in the place's list (a random first one), never the same twice running
      final last = _lastIndex[key];
      final i = last == null ? _rng.nextInt(_list.length) : (last + 1) % _list.length;
      _lastIndex[key] = i;
      name = _list[i];
    }
    final rel = _rel(name);
    if (rel == null) return; // 'none': silence
    final p = AudioPlayer();
    _player = p;
    try {
      await p.setReleaseMode(_loop ? ReleaseMode.loop : ReleaseMode.stop);
      await _Fader.set(p, 0);
      p.onPlayerComplete.listen((_) {
        _Fader.kill(p);
        if (!identical(_player, p)) return;
        _player = null;
        if (_key != key) return;
        // a quiet stretch (just the place's own sounds), then the next tune
        _wait?.cancel();
        _wait = Timer(Duration(seconds: 20 + _rng.nextInt(26)), _start);
      });
      await p.play(AssetSource(rel));
      if (!identical(_player, p) || _key != key) {
        if (identical(_player, p)) _player = null;
        return _Fader.kill(p);
      }
      _Fader.ramp(p, _volume, 2.0);
    } catch (_) {
      if (identical(_player, p)) _player = null;
      await _Fader.kill(p);
    }
  }
}
