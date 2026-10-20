// Lumen Trails: the encounter. The battle shot (your Evochi from behind in the foreground, the wild
// one facing it), the intro cinematics on that same shot (the Sentinel's awakening is a story beat of
// its own) ending on the hero shot under the intro card ("A Wild / Petalune / Appeared!", the goal,
// Begin Encounter), turn choreography with camera moves, hit-stops, punches and the board's effects,
// the feedback language (the log card's headline and line, announcements, status chips), and the
// result card with reward toasts.
//
// The stage (encounter_stage.dart) is one live widget tree driven imperatively through an
// [EncounterStage], so camera moves and effects never restart when the state re-renders; the panel
// under it (log, actions, intro and result cards) is ordinary widgets that rebuild with the state.
// Rules live in lib/game/trails/trails.dart (startEncounter / encounterAct / completeEncounter).
// Mirrors the `encounter` screen in web/src/screens/encounter.js.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/router.dart';
import '../../app/theme.dart';
import '../../controllers/game_controller.dart';
import '../../core/models/catalog.dart';
import '../../core/services/asset_manifest.dart';
import '../../game/story/story.dart' as q;
import '../../game/trails/trails.dart' as tr;
import '../../core/services/haptics.dart';
import '../shared/kit.dart';
import '../shared/sprite.dart';
import '../shared/widgets.dart';
import '../village/story_widgets.dart';
import 'encounter_icons.dart';
import 'encounter_stage.dart';
import 'trails_widgets.dart';

/// An intro's length and music.
class _Intro {
  const _Intro(this.ms, this.music);
  final int ms;
  final String music;
}

const _intros = <String, _Intro>{
  'rare': _Intro(2700, 'enc_wild_loop'),
  'hollow': _Intro(3000, 'enc_boss_loop'),
  'boss': _Intro(6300, 'enc_boss_loop'),
  'standard': _Intro(2200, 'enc_wild_loop'),
};

// the intro card's line about the creature
const _introLines = <String, String>{
  'petalune': 'A gentle Evochi that nurtures life in the ruins. It seems cautious, but curious about you…',
  'hollow_sprout': 'A forest Evochi tangled in Hollow growth. It flinches at every sound, but kindness still reaches it…',
  'sentinel': 'A guardian of the Lumen Trails, asleep for an age. Its light is dim, but it still listens…',
};

/// The title stacks: "A Wild / Petalune / Appeared!", "A Hollow / Sprout / Appeared!", "The Forgotten /
/// Sentinel / Awakens!".
(String, String, String) _introTitle(tr.Creature c) {
  if (c.boss) {
    final w = c.name.split(' ');
    return ('The ${w.sublist(0, w.length - 1).join(' ')}', w.last, 'Awakens!');
  }
  if (c.kind == 'hollow' && c.name.startsWith('Hollow ')) return ('A Hollow', c.name.substring(7), 'Appeared!');
  return ('A Wild', c.name, 'Appeared!');
}

String _petExpr(tr.EncounterView v) {
  if (v.success) return 'excited';
  if (v.energy < 25) return 'sleepy';
  return 'default';
}

// ------------------------------------------------------------------ words (the board's feedback language) ----
/// A line on the log card: a bold headline and the line under it, whose turn it is, and the attempt.
class _LogLine {
  const _LogLine(this.title, this.sub, this.who, this.seed);
  final String title;
  final String sub;
  final String who; // you | wild
  final String seed;
}

String _theName(tr.Creature c) => c.id == 'sentinel' ? 'The Sentinel' : (c.id == 'hollow_sprout' ? 'The Sprout' : c.name);

/// Your line for the log card, and the announcement it may make.
({String title, String sub, String? ann, String tone}) _youLine(String pet, tr.EncounterView v, tr.EncounterActionDef a, String? itemId) {
  final c = v.creature;
  final hollow = c.kind == 'hollow';
  switch (a.kind) {
    case 'item':
      final f = itemId == null ? null : tr.itemEffect(itemId, v.goal, c.id);
      final liked = f?.liked ?? false;
      final weak = !liked && (f?.amount ?? 0) < 10;
      return (
        title: '$pet offers ${(itemId == null ? null : catalog[itemId]?.name) ?? 'a gift'}!',
        sub: liked ? '${c.name} loves it!' : (weak ? 'It’s not very effective…' : '${c.name} sniffs it curiously…'),
        ann: liked ? '${_theName(c)} loves it!' : (weak ? 'It’s not very effective…' : null),
        tone: liked ? 'love' : 'meh',
      );
    case 'companion':
      return (title: 'Petalune uses Petal Hush!', sub: 'A soft, green hum fills the air…', ann: null, tone: 'calm');
    case 'light':
      return (title: '$pet uses Lumen Glow!', sub: hollow ? 'Warm light pushes back the Hollow…' : 'A warm light soothes ${c.name}…', ann: hollow ? 'It’s very effective!' : null, tone: 'good');
    case 'physical':
      final fun = v.goal == 'befriend' && v.e.curious;
      return (title: '$pet uses Gentle Nudge!', sub: fun ? 'It’s having fun!' : 'The air settles a little…', ann: fun ? 'It’s having fun!' : null, tone: 'good');
    default:
      return (title: '$pet uses Soothe!', sub: '$pet rests. Energy returns.', ann: null, tone: 'calm');
  }
}

/// The wild one's reply: a short headline (and whether it is worth an announcement) over the game's
/// own line.
({String title, String sub, String tone, bool ann}) _wildLine(tr.EncounterView v, String? mood, String? kind, int wild, int drain, String text) {
  final c = v.creature;
  final the = _theName(c);
  if (v.goal == 'befriend') {
    if (kind == 'item' && mood == 'curious' && wild > 0) return (title: 'Trust is growing.', sub: text, tone: 'love', ann: true);
    if (mood == 'wary') return (title: '${c.name} seems wary.', sub: text, tone: 'wary', ann: true);
    if (mood == 'calm') return (title: '${c.name} looks more at ease!', sub: text, tone: 'love', ann: true);
    return (title: '${c.name} is watching you closely…', sub: text, tone: 'calm', ann: false);
  }
  if (mood == 'waking') return (title: '$the stirs!', sub: text, tone: 'hollow', ann: true);
  if (mood == 'surging' && drain != 0) return (title: 'Hollow energy lashes out!', sub: text, tone: 'hollow', ann: true);
  if (mood == 'surging') return (title: 'Hollow energy surged!', sub: text, tone: 'hollow', ann: true);
  if (mood == 'flickering') return (title: '$the’s light flickers…', sub: text, tone: 'calm', ann: false);
  return (title: '$the is calming down…', sub: text, tone: 'calm', ann: true);
}

/// The last turn's line on the log card.
_LogLine _finalLog(tr.EncounterView v) {
  final c = v.creature;
  return v.goal == 'befriend'
      ? _LogLine('${c.name} trusts you.', 'A new friend may join you soon…', 'wild', v.seed)
      : _LogLine('${c.name} restored.', 'The Hollow energy fades, and its light returns.', 'wild', v.seed);
}

/// The status chips, read from the real state (the board's mini-library, where the rules have one).
(List<StageStatus>, List<StageStatus>) _statuses(tr.EncounterView v, double energy) {
  final w = <StageStatus>[];
  final p = <StageStatus>[];
  if (v.done != null) return (w, p);
  final c = v.creature;
  if (c.kind == 'hollow') w.add(const StageStatus('hollowed', 'Hollowed', 'Lumen Glow is 30% stronger against the Hollow.'));
  if (v.phase2) w.add(const StageStatus('waking', 'Waking', 'It lashes out more often now. Keep your Energy up.'));
  if (v.mood == 'surging' && c.kind == 'hollow') w.add(const StageStatus('unsteady', 'Unsteady', 'Hollow energy is surging through it.'));
  if (v.mood == 'flickering') w.add(const StageStatus('flicker', 'Flickering', 'Its Hollow is loosening.'));
  if (v.goal == 'befriend') {
    if (v.mood == 'wary') w.add(const StageStatus('wary', 'Wary', 'It may skitter away. Gifts and patience help.'));
    if (v.e.curious) w.add(const StageStatus('trust', 'Curious', 'Gentle Nudge adds +4 Calm while it’s curious.'));
    if (v.mood == 'calm') w.add(const StageStatus('soothed', 'Soothed', 'It feels at ease with you.'));
  }
  if (v.phase2) p.add(const StageStatus('charged', 'Lumen Charged', 'Lumen Glow is 25% stronger now.'));
  if (energy < tr.encounterActions['lumen_glow']!.energy) p.add(const StageStatus('tired', 'Tired', 'Not enough Energy for Lumen Glow. Soothe to rest.'));
  if (v.actions.any((a) => a.kind == 'companion' && a.can)) p.add(const StageStatus('bloom', 'Petalune is with you', 'Petal Hush is ready, once this encounter.'));
  return (w, p);
}

/// The second line of an action button: what it costs (the board's clear action hierarchy).
String _actionSub(tr.ActionView a, tr.EncounterView v) {
  switch (a.kind) {
    case 'item':
      final n = v.items.fold<int>(0, (t, i) => t + i.qty);
      return n > 0 ? '$n available' : 'Nothing useful yet';
    case 'restore':
      return '+30 Energy';
    case 'companion':
      return v.companionUsed ? 'Used this time' : 'Once · no Energy';
    default:
      return '−${a.energy} Energy';
  }
}

/// What an action does, for screen readers.
String _actionLong(tr.ActionView a, tr.EncounterView v) {
  final l = v.meterLabel;
  if (a.kind == 'restore') return '${a.name}: +30 Energy and a little ${l == 'Calm' ? 'Calm' : 'less Instability'}';
  if (a.kind == 'item') return '${a.name}: ${_actionSub(a, v)}';
  return '${a.name}: ${v.goal == 'befriend' ? '+' : '−'}${a.power} $l${a.energy > 0 ? ', costs ${a.energy} Energy' : ''}';
}

class EncounterScreen extends StatefulWidget {
  const EncounterScreen({super.key, this.fresh = false});
  final bool fresh; // just arrived from the travel scene: play the intro
  @override
  State<EncounterScreen> createState() => _EncounterScreenState();
}

class _EncounterScreenState extends State<EncounterScreen> {
  final _panelKey = GlobalKey();
  double _ph = 280; // the panel's height (the view ends 20px above it)
  EncounterStage? _stage;
  ShotGeometry? _geom;
  String? _seed;
  String? _phase; // intro | card | play | outro | result
  bool _busy = false;
  bool _holdPet = false, _holdWild = false;
  double? _dispMeter, _dispEnergy; // the mid-turn numbers while a turn plays out
  bool _logOpen = false;
  _LogLine? _log; // the log card's line once a turn has played (tied to the attempt)
  bool _init = false, _introStarted = false, _resultShown = false;
  Timer? _outroTimer;
  final _timers = <Timer>[];
  bool _leaving = false;
  bool _rm = false;
  String? _amb; // the ambient the effects are showing (gold | hollow | won)
  Timer? _idleTimer; // between turns your Evochi blinks and the wild one glances about
  bool _idleOn = false;
  final _rand = math.Random();

  late GameController _c;

  @override
  void initState() {
    super.initState();
    _c = context.read<GameController>();
  }

  // ------------------------------------------------------------------ timers, audio ----
  Timer _later(int ms, VoidCallback fn) {
    late Timer t;
    t = Timer(Duration(milliseconds: ms), () {
      _timers.remove(t);
      if (mounted) fn();
    });
    _timers.add(t);
    return t;
  }

  void _clearTimers() {
    for (final t in _timers) {
      t.cancel();
    }
    _timers.clear();
    _outroTimer?.cancel();
    _outroTimer = null;
    _stage?.clearTimers();
  }

  void _music(String? name) => _c.audio.setMusic(name);
  void _sfx(String name, double vol) => _c.audio.play(name, volume: vol);

  void _stopIdle() {
    _idleTimer?.cancel();
    _idleTimer = null;
    _idleOn = false;
  }

  @override
  void dispose() {
    _clearTimers();
    _stopIdle();
    _stage?.dispose();
    _c.audio.setMusic(null);
    super.dispose();
  }

  void _toGuild() {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(guildRoute());
  }

  String get _petName => _c.state.pet?.name ?? 'Your Evochi';

  /// What the log card shows when nothing is playing: the last turn's lines, or how it began.
  _LogLine _currentLog(tr.EncounterView v) {
    final l = _log;
    if (l != null && l.seed == v.seed) return l;
    final c = v.creature;
    if (v.success) return _finalLog(v);
    if (v.turn == 0) {
      if (v.goal == 'befriend') return _LogLine('A wild ${c.name} appeared!', 'It watches you from a distance…', 'wild', v.seed);
      return _LogLine(c.boss ? 'The Sentinel is awake!' : 'Hollow energy shudders through the ruins…', v.log.isEmpty ? '' : v.log.first.text, 'wild', v.seed);
    }
    return _LogLine(v.log.isEmpty ? '' : v.log.last.text, '', v.log.isEmpty ? 'wild' : v.log.last.who, v.seed);
  }

  // ------------------------------------------------------------------ the stage in sync ----
  /// Bring the live stage in line with the state (or with the mid-turn numbers while a turn plays).
  void _syncStage(tr.EncounterView v) {
    final st = _stage;
    if (st == null) return;
    final meter = _dispMeter ?? v.meter.toDouble();
    final energy = _dispEnergy ?? v.energy.toDouble();
    st.update((s) {
      s.meter = (meter / v.max).clamp(0.0, 1.0);
      s.meterText = '${meter.round()} / ${v.max}';
      s.energy = (v.energyMax == 0 ? 0.0 : energy / v.energyMax).clamp(0.0, 1.0);
      s.energyText = '${energy.round()} / ${v.energyMax}';
      if (!_holdWild) s.wildState = v.stateKey;
      if (!_holdPet) s.petExpr = _petExpr(v);
      if (!_busy) s.wildMood = v.done != null ? 'done' : v.mood;
      s.phase2 = v.phase2;
      s.hollow = v.creature.kind == 'hollow' && !v.success;
    });
    // the status chips and the turn
    final (w, p) = _statuses(v, energy);
    st.setStatus(w, p, v.done != null ? 'Done' : 'Turn ${v.turn + 1}');
    // the air: petals and motes over the grove, Hollow embers and crystals around the wild one
    final fx = st.effects;
    final g = _geom;
    if (fx != null && g != null) {
      final kind = v.success ? 'won' : (v.creature.kind == 'hollow' ? 'hollow' : 'gold');
      if (_amb != kind) {
        _amb = kind;
        fx.setAmbient(kind, kind == 'hollow' ? Rect.fromLTWH(g.wildCx - 0.14, g.wildHeadY - 0.04, 0.28, g.wildBottom - g.wildHeadY + 0.04) : const Rect.fromLTWH(0.04, 0.10, 0.92, 0.62));
      }
    }
  }

  /// Between turns your Evochi blinks and the wild one glances about, so the shot is never dead still.
  void _scheduleIdle() {
    _idleTimer?.cancel();
    _idleTimer = Timer(Duration(milliseconds: 2400 + _rand.nextInt(2600)), () {
      final st = _stage;
      final v = tr.encounterView(_c.state, _c.now);
      if (!mounted || st == null || v == null || _leaving) {
        _idleOn = false;
        return;
      }
      final quiet = !_busy && !_holdPet && (_phase == 'play' || _phase == 'card');
      if (quiet && _petExpr(v) == 'default') {
        st.update((s) => s.petExpr = 'blink');
        _later(150, () {
          if (!_busy && !_holdPet) st.update((s) => s.petExpr = _petExpr(v));
        });
      }
      if (quiet && v.done == null && _rand.nextDouble() < 0.55) st.retriggerWild('look', 1500);
      _scheduleIdle();
    });
  }

  /// After each frame (the web's `mount`): measure the panel, sync the stage, start the intro or the
  /// outro, and bring on the result (the toasts, the speech bubble, the won air).
  void _afterBuild(tr.EncounterView v) {
    if (!mounted || _stage == null) return;
    final h = _panelKey.currentContext?.size?.height;
    if (h != null && (h - _ph).abs() > 0.5) setState(() => _ph = h);
    _syncStage(v);
    final st = _stage!;
    if (!_init) {
      _init = true;
      if (!_idleOn) {
        _idleOn = true;
        _scheduleIdle();
      }
      if (_phase == 'intro' && !_introStarted) {
        _introStarted = true;
        _playIntro(v);
      } else {
        // a fresh stage mid-encounter (came back from elsewhere): no intro, just the shot
        final card = _phase == 'card' || _phase == 'intro';
        st.update((s) {
          s.lit = true;
          s.eyeL = true;
          s.eyeR = true;
          if (!card) s.petIn = true;
          if (v.success) s.won = true;
        });
        if (card) st.setShot('hero', instant: true);
        _music(_phase == 'result' ? null : (_intros[v.intro] ?? _intros['standard']!).music);
        if (_phase == 'intro') {
          _clearTimers();
          setState(() => _phase = 'card');
        }
      }
    }
    if (_phase == 'outro' && _outroTimer == null) {
      st.update((s) => s.won = true);
      _outroTimer = _later(_rm ? 700 : 2400, () {
        _outroTimer = null;
        if (_phase == 'outro') {
          setState(() => _phase = 'result');
          _music(null);
        }
      });
    }
    if (_phase == 'result' && !_resultShown) {
      _resultShown = true;
      st.setShot('wild');
      _rewardToasts(v);
      // a speech bubble over the creature: a heart for a new friend, light for a restored one
      final g = _geom!;
      final wf = g.wildFace ?? Offset(g.wildCx, g.wildHeadY + 0.06);
      st.speech(Offset(wf.dx + g.wildWidth * 0.06, g.wildHeadY - 0.03), v.goal);
      _amb = 'won';
      st.effects?.setAmbient('won', Rect.fromLTWH(g.wildCx - 0.22, g.wildHeadY - 0.08, 0.44, g.wildBottom - g.wildHeadY + 0.08));
    }
  }

  /// The reward toasts as the result comes in (the board's Reward Toast), one after another.
  void _rewardToasts(tr.EncounterView v) {
    final st = _stage;
    final r = q.storyQuests[v.quest]?.rewards;
    if (st == null || r == null) return;
    final list = <({String text, String? icon, String? itemId})>[
      if (r.companion != null) (text: '${tr.creatureDefs[r.companion]?.name ?? r.companion} joined your team!', icon: 'creature_${r.companion}', itemId: null),
      for (final id in r.items) (text: '${catalog[id]?.name ?? id} obtained!', icon: null, itemId: id),
      for (final t in r.titles) (text: '${q.titles[t] ?? t} title earned!', icon: 'crown', itemId: null),
      for (final x in r.unlocks) (text: '$x unlocked!', icon: 'star', itemId: null),
    ];
    for (var i = 0; i < math.min(3, list.length); i++) {
      final t = list[i];
      _later(350 + i * 2500, () {
        st.toast(t.text, icon: t.icon, itemId: t.itemId);
        _sfx('reward_chime', 0.4);
      });
    }
  }

  // ------------------------------------------------------------------ intros (on the same shot) ----
  // The intro ends on the hero shot of the wild one with the big title, the goal and Begin Encounter
  // (the 'card' phase); your Evochi steps in when you begin.
  void _playIntro(tr.EncounterView v) {
    final st = _stage!;
    final g = _geom!;
    final intro = _intros[v.intro] ?? _intros['standard']!;
    void done() {
      if (!mounted) return;
      if (_phase != 'intro') return;
      setState(() {
        _phase = 'card';
        _holdWild = false;
        _holdPet = false;
      });
    }

    if (_rm) {
      st.setShot('hero', instant: true);
      st.update((s) {
        s.lit = true;
        s.eyeL = true;
        s.eyeR = true;
        if (v.intro == 'boss') s.wildState = v.stateKey;
      });
      _music(intro.music);
      _later(900, done);
      return;
    }
    final fx = st.effects;
    final w = g.wild;
    final eyes = g.wildEyesAbs;
    if (v.intro == 'boss') {
      // the Sentinel's awakening: dark and still, a rumble, stones falling, its eyes light one after
      // the other, the gate shakes and crackles, your Evochi flinches, and the music turns
      _holdWild = true;
      _holdPet = true;
      st.update((s) {
        s.introDark = true;
        s.wildState = 'dormant';
        s.petExpr = 'default';
      });
      st.setShot('face', instant: true);
      _music('none');
      _later(300, () {
        _sfx('enc_rumble', 0.9);
        st.update((s) => s.trembling = true);
        st.doShake();
        fx?.burst(Offset(w.dx, g.wildHeadY - 0.06), 6, shape: 'rock', pal: 'rock', blend: BlendMode.srcOver, speed: 6, vary: 0.6, angle: math.pi / 2, spread: 0.5, size: 1.6, sizeK: 'hold', alphaK: 'hold', life: 1.1, gravity: 120, spin: 5, jitter: 12);
      });
      _later(1100, () => st.doShake());
      _later(1500, () {
        _sfx('enc_awaken', 0.9);
        st.update((s) => s.eyeL = true);
        if (eyes != null) fx?.flashAt(eyes[0], size: 14, life: 1.2, pal: 'violet', alphaK: 'inout', sizeK: 'grow');
      });
      _later(2300, () {
        st.update((s) => s.eyeR = true);
        if (eyes != null) fx?.flashAt(eyes[1], size: 14, life: 1.2, pal: 'violet', alphaK: 'inout', sizeK: 'grow');
      });
      _later(3300, () {
        st.update((s) {
          s.wildState = 'hollow';
          s.lit = true;
        });
        fx?.embers(w, 18, pal: 'violet', w: 26, h: 24, life: 1.6);
        fx?.crackleAround(w, r: 16, n: 4, ms: 500);
      });
      _later(3850, () {
        st.doShake(big: true);
        st.doFlash('violet');
        st.punch(big: true);
        fx?.ring(w, r0: 4, r1: 48, ms: 800, pal: 'violet', width: 3);
        fx?.hollowShards(w, n: 14, scale: 1.3);
        fx?.dustBurst(Offset(w.dx, g.wildBottom - 0.02), n: 12, scale: 1.2);
        fx?.crackleAround(w, r: 22, n: 6, ms: 700);
        fx?.pulse(pal: 'dark', ms: 900, alpha: 0.6);
        st.setShot('wide');
        st.update((s) => s.petIn = true);
      });
      _later(4500, () {
        st.update((s) => s.petExpr = 'surprised');
        st.retriggerPet('flinch', 1100);
        _sfx('pet_chirp', 0.5);
        _music(intro.music);
      });
      _later(5500, () {
        st.update((s) => s.trembling = false);
        st.setShot('hero');
      });
      _later(intro.ms, () {
        _holdPet = false;
        st.update((s) => s.petExpr = 'determined');
        done();
      });
      return;
    }
    // rare / hollow / standard: close on the wild one, a reaction, then the hero shot for the title
    st.setShot('close', instant: true);
    _music(intro.music);
    final hollow = v.intro == 'hollow';
    if (hollow) {
      st.update((s) => s.silhouette = true);
      _later(500, () {
        _sfx('enc_surge', 0.6);
        fx?.ring(w, r0: 3, r1: 40, ms: 800, pal: 'violet', width: 2.6);
        fx?.embers(w, 20, pal: 'violet', w: 22, h: 20, life: 1.6);
        fx?.crackleAround(w, r: 14, n: 4, ms: 600);
        fx?.smoke(Offset(w.dx, g.wildBottom), n: 6, scale: 1.1);
        fx?.pulse(pal: 'dark', ms: 900, alpha: 0.45);
        st.doShake();
      });
      _later(1500, () => st.update((s) => s.silhouette = false));
    } else {
      _later(900, () {
        st.retriggerWild('bang', 1600);
        _sfx('pet_chirp', 0.45);
        fx?.burst(Offset(w.dx, g.wildHeadY), 8, shape: 'sparkle', pal: 'gold', speed: 30, vary: 0.5, drag: 2.5, size: 3, sizeK: 'spark', life: 0.8, spin: 3, gravity: 10);
      });
    }
    _later(hollow ? 1800 : 1500, () => st.setShot('hero'));
    _later(intro.ms, done);
  }

  void _skipIntro(tr.EncounterView v) {
    _clearTimers();
    final st = _stage;
    if (st != null) {
      st.update((s) {
        s.trembling = false;
        s.silhouette = false;
        s.lit = true;
        s.eyeL = true;
        s.eyeR = true;
        if (v.intro == 'boss') s.wildState = v.stateKey;
      });
      st.setShot('hero', instant: true);
      _music((_intros[v.intro] ?? _intros['standard']!).music);
    }
    setState(() {
      _holdWild = false;
      _holdPet = false;
      _phase = 'card';
    });
  }

  /// Begin Encounter: your Evochi steps in and the camera pulls back to the wide shot.
  void _begin() {
    _sfx('ui_tap', 0.4);
    final st = _stage;
    if (st != null) {
      _sfx('enc_whoosh', 0.45);
      st.update((s) => s.petIn = true);
      st.setShot('wide');
    }
    setState(() => _phase = 'play');
  }

  // ------------------------------------------------------------------ a turn, choreographed ----
  /// A value eased (ease-out cubic) over [ms] on the stage's wall clock, like the web's `tween`.
  void _tween(int ms, void Function(double k) fn) {
    final st = _stage;
    if (st == null) return;
    final c = st.clock;
    final t0 = c.wall;
    late VoidCallback step;
    step = () {
      if (!mounted) {
        c.removeListener(step);
        return;
      }
      final k = ((c.wall - t0) * 1000 / math.max(1, ms)).clamp(0.0, 1.0);
      fn(1 - math.pow(1 - k, 3).toDouble());
      if (k >= 1) c.removeListener(step);
    };
    c.addListener(step);
    step();
  }

  // Every move has the same four beats: a wind-up, the action, the impact (a hit-stop, a soft flash on
  // the one that was hit, a camera punch, the effect from the board's library at the point of contact)
  // and the recovery, with the number popping first and the meter following it. The colours keep one
  // language: gold light and green leaves are you, violet crystals and crackle are the Hollow.
  void _runTurn(String actionId, String? itemId) {
    if (_busy) return;
    final c = _c;
    final before = tr.encounterView(c.state, c.now);
    if (before == null) return;
    final r = c.run((s, n) => tr.encounterAct(s, actionId, itemId, n));
    if (!r.ok) return;
    final after = tr.encounterView(c.state, c.now);
    final st = _stage;
    final gm = _geom;
    if (after == null || st == null || gm == null) return;
    final ev = r.events.where((e) => e.type == 'encounter_turn').firstOrNull;
    final you = (ev?.data['you'] as int?) ?? 0;
    final wild = (ev?.data['wild'] as int?) ?? 0;
    final mood = ev?.data['mood'] as String?;
    final drain = (ev?.data['drain'] as int?) ?? 0;
    final evKind = ev?.data['kind'] as String?;
    final a = tr.encounterActions[actionId]!;
    final k = _rm ? 0.35 : 1.0;
    int ms(num x) => (x * k).round();
    final sign = before.goal == 'befriend' ? 1 : -1;
    final label = before.meterLabel;
    final mid = (before.meter + sign * you).clamp(0, before.max).toDouble();
    final cost = math.max(0, a.energy);
    final hollow = before.creature.kind == 'hollow';
    final wildText = after.log.isNotEmpty ? after.log.last.text : '';
    final yl = _youLine(_petName, before, a, itemId);
    // the panel: lock the buttons, show your line; the plates: pay the Energy at once
    setState(() {
      _busy = true;
      _holdPet = true;
      _holdWild = true;
      _dispMeter = before.meter.toDouble();
      _dispEnergy = (before.energy - cost).toDouble();
      _log = _LogLine(yl.title, yl.sub, 'you', before.seed);
    });
    _syncStage(before);
    st.update((s) => s.petExpr = 'determined');
    final fx = st.effects;
    final w = gm.wild; // the wild one's body
    final wf = gm.wildFace ?? Offset(w.dx, gm.wildHeadY + 0.06); // its face
    final wc = Offset(w.dx - gm.wildWidth * 0.28, w.dy + 0.03); // its near side, where a nudge lands
    final wg = Offset(w.dx - 0.03, gm.wildBottom); // the ground at its feet
    final p = gm.petHead; // your Evochi's head
    final pc = gm.pet; // its body
    final pg = Offset(gm.petCx, gm.petFeetY); // the ground at its feet
    // the numbers pop beside its head (the board's "+16 Calm" bubble), clear of the toasts on the left
    final numX = w.dx + gm.wildWidth * 0.3;
    final numY = before.creature.size == 'large' ? wf.dy - 0.04 : math.max(gm.wildHeadY + 0.04, w.dy - 0.08);
    void meterTo(double to, int dur) {
      final from = _dispMeter ?? before.meter.toDouble();
      _tween(ms(dur), (t) {
        if (_dispMeter == null) return;
        _dispMeter = from + (to - from) * t;
        _syncStage(before);
      });
    }

    void energyTo(double to, int dur) {
      final from = _dispEnergy ?? before.energy.toDouble();
      _tween(ms(dur), (t) {
        if (_dispEnergy == null) return;
        _dispEnergy = from + (to - from) * t;
        _syncStage(before);
      });
    }

    // the bouncy hit feedback: stars that pop out and fall
    void stars(Offset at, int n, double s) => fx?.burst(at, n, shape: 'star', pal: 'gold', speed: 46 * s, vary: 0.5, drag: 2.6, size: 3.2 * s, sizeK: 'pop', alphaK: 'hold', life: 0.75, spin: 7, gravity: 70);

    // 3. the impact on the wild one: the visuals fire the moment the projectile lands (or on the beat
    // for the moves without one); the number and the meter follow on the beat
    var landedOnce = false;
    void landed() {
      if (landedOnce) return;
      landedOnce = true;
      // your move lands: a firm tap for a glow, a nudge or a gift (Soothe and Petal Hush breathe instead)
      if (a.kind == 'light' || a.kind == 'physical' || a.kind == 'item') _c.audio.buzz(Haptic.hit, strength: a.kind == 'item' ? 0.6 : 1);
      switch (a.kind) {
        case 'light':
          // Golden Pulse winds out round the face; on a Hollow one, its crystals break off
          st.hitstop(ms(100));
          st.retriggerWild('hit', 600);
          fx?.flashAt(wf, size: 26, life: 0.3, pal: 'gold');
          fx?.goldenPulse(wf, r1: 24, ms: 700);
          stars(wf, 7, 0.9);
          if (hollow) {
            fx?.hollowShards(wf, n: 12, scale: 1);
          } else {
            fx?.shards(wf, 14, pal: 'gold', scale: 0.8);
          }
          st.punch();
          _later(ms(100), () => st.doShake());
          _sfx('reward_chime', 0.35);
        case 'physical':
          st.hitstop(ms(80));
          st.retriggerWild('hit', 600);
          fx?.dustBurst(wc, n: 8, scale: 0.9, ground: wg);
          stars(wc, 7, 1);
          fx?.ring(wc, r0: 1, r1: 16, ms: 320, pal: 'white', width: 1.6, alpha: 0.8);
          st.punch();
          _later(ms(80), () => st.doShake());
          _sfx('play_boing', 0.5);
        case 'item':
          st.hitstop(ms(60));
          st.retriggerWild('munch', 800);
          fx?.burst(wf, 10, shape: 'sparkle', pal: 'gold', speed: 38, vary: 0.5, drag: 3, size: 3.4, sizeK: 'spark', life: 0.7, spin: 3, gravity: 30);
          fx?.flashAt(wf, size: 18, life: 0.25, pal: 'gold');
          fx?.ring(wf, r0: 1, r1: 16, ms: 320, pal: 'white', width: 1.4, alpha: 0.75);
          if (you >= 20) _later(ms(320), () => fx?.hearts(wf, n: 4));
          _sfx('pet_chirp', 0.45);
        case 'companion':
          st.retriggerWild('perk', 700);
          fx?.hearts(wf, n: 3);
          fx?.ring(wf, r0: 3, r1: 22, ms: 600, pal: 'pink', width: 1.4, alpha: 0.7, blend: BlendMode.srcOver);
        default:
          if (you != 0) {
            st.retriggerWild('perk', 700);
            fx?.hearts(wf, n: 2, pal: 'teal');
          }
      }
    }

    var impact = 900;
    var replyGap = 800;
    // 1-2. your move
    switch (a.kind) {
      case 'light':
        // Lumen Glow: motes gather into your Evochi as it brightens, then a comet of gold light flies
        st.setShot('pet', speed: 'fast');
        st.retriggerPet('cast', 720);
        _sfx('enc_glow', 0.7);
        fx?.converge(p, 24, r: 19, pal: 'gold', life: 0.44 * k, size: 2.6);
        fx?.halo(p, size: 26, life: 0.5, pal: 'gold', layer: 'front', alpha: 0.9);
        _later(ms(440), () {
          st.setShot('wild', speed: 'fast');
          fx?.flashAt(p, size: 30, life: 0.28, pal: 'gold');
          if (fx != null) {
            fx.comet(p, wf, ms: ms(210).toDouble(), pal: 'gold', size: 7.5, bow: -9, trail: 4, onArrive: landed);
          } else {
            _later(ms(230), landed);
          }
        });
        impact = ms(680);
      case 'physical':
        // Gentle Nudge: a crouch and a hop into it, Lumen Wisps winding along, a Dust Burst where it lands
        st.setShot('pet', speed: 'fast');
        st.retriggerPet('lunge', 900);
        _sfx('enc_whoosh', 0.6);
        _later(ms(110), () => fx?.wisps(pc, wc, n: 5, ms: 300 * k));
        _later(ms(190), () {
          st.setShot('wild', speed: 'fast');
          fx?.dust(pg, n: 5, scale: 0.8);
        });
        impact = ms(320);
      case 'restore':
        // Soothe: it settles, Healing Sparkles and leaves rise, rings of calm spread, Energy counts up
        st.setShot('pet', speed: 'fast');
        st.retriggerPet('rest', 1300);
        st.update((s) => s.petExpr = 'sleepy');
        _sfx('enc_soothe', 0.6);
        fx?.halo(p, size: 54, life: 1.3, pal: 'teal', layer: 'front', alpha: 0.5);
        for (var i = 0; i < 3; i++) {
          _later(ms(120 + i * 230), () => fx?.ring(p, r0: 4, r1: 40, ms: 1000, pal: 'teal', width: 1.6, alpha: 0.7));
        }
        fx?.healing(Offset(p.dx, p.dy + 0.04), n: 18, w: 30, h: 22);
        _later(ms(450), () => fx?.healing(Offset(p.dx, p.dy + 0.02), n: 9, w: 26, h: 16));
        _later(ms(650), () {
          st.floatText(Offset(p.dx, p.dy + 0.02), '+30 Energy', 'energy');
          energyTo(math.min(before.energyMax, before.energy + 30).toDouble(), 520);
        });
        _later(ms(950), () => st.setShot('wide'));
        impact = ms(1150);
        replyGap = 650;
      case 'item':
        // an item: it turns over in an arc with a sparkle behind it
        st.setShot('pet', speed: 'fast');
        st.retriggerPet('toss', 600);
        _sfx('enc_whoosh', 0.5);
        final imPath = itemId == null ? null : art.item(itemId);
        if (imPath != null) AtlasCache.load(imPath);
        _later(ms(230), () {
          st.setShot('wild', speed: 'fast');
          if (fx != null) {
            final m = fx.comet(Offset(p.dx, p.dy - 0.02), Offset(wf.dx, wf.dy + 0.02),
                ms: ms(600).toDouble(), pal: 'gold', size: 3, bow: -24, trail: 1, ease: 'inout', img: imPath == null ? null : AtlasCache.peek(imPath), imgSize: 11, spin: 9, onArrive: landed);
            if (imPath != null && m.img == null) AtlasCache.load(imPath).then((i) => m.img = i);
          } else {
            st.projectile('toss', p, Offset(wf.dx, wf.dy + 0.02), ms(600), arc: -20, itemId: itemId);
            _later(ms(600), landed);
          }
        });
        impact = ms(830);
      case 'companion':
        // Petal Hush: Petalune swoops in and a stream of Flower Petals winds across to the wild one
        st.setShot('wide');
        st.buddy();
        _sfx('enc_soothe', 0.6);
        _later(ms(260), () => fx?.stream(const Offset(0.10, 0.42), wf, 48, pal: 'pink', ms: 650 * k, size: 4));
        _later(ms(380), () => fx?.wisps(const Offset(0.12, 0.44), wf, n: 4, ms: 620 * k));
        _later(ms(520), () => st.setShot('wild', speed: 'fast'));
        impact = ms(1100);
        replyGap = 900;
    }
    _later(impact, () {
      if (a.kind != 'light' && a.kind != 'item') landed();
      // the number pops, then the meter follows it
      _later(a.kind == 'restore' ? 0 : ms(110), () {
        landed();
        if (you != 0) st.floatText(Offset(numX, numY), '${sign > 0 ? '+' : '−'}$you $label', hollow ? 'good violet' : 'good');
        meterTo(mid, 380);
        final ann = yl.ann;
        if (ann != null) _later(ms(160), () => st.announce(ann, yl.tone));
      });
    });
    // 4. the reply (or the finish)
    final replyAt = impact + ms(replyGap);
    if (after.success) {
      _later(replyAt - ms(200), () => _finishChoreo(before, after));
      return;
    }
    _later(replyAt, () {
      final wl = _wildLine(before, mood, evKind, wild, drain, wildText);
      setState(() => _log = _LogLine(wl.title, wl.sub, 'wild', before.seed));
      if (wl.ann) st.announce(wl.title, wl.tone);
      final bad = wild < 0;
      st.setShot(mood == 'surging' || drain != 0 ? 'wild' : 'wide');
      st.update((s) => s.wildMood = mood ?? '');
      switch (mood) {
        case 'wary':
          st.retriggerWild('skitter', 900);
          _sfx('enc_whoosh', 0.35);
          fx?.dust(wg, n: 5, scale: 0.8);
        case 'curious':
          st.retriggerWild('tilt', 900);
          st.bubble(Offset(w.dx + 0.06, gm.wildHeadY - 0.02), '?');
        case 'calm':
          st.retriggerWild('perk', 700);
          fx?.hearts(wf, n: 2);
        case 'surging' || 'waking':
          // the Hollow swells in it: Violet Crackle, Hollow Shards, a dark pulse
          _sfx('enc_surge', 0.6);
          st.retriggerWild('surge', 900);
          fx?.ring(w, r0: 4, r1: 42, ms: 700, pal: 'violet', width: 2.6);
          fx?.crackleAround(w, r: 16, n: mood == 'waking' ? 7 : 5, ms: 650);
          fx?.hollowShards(w, n: 8, scale: 0.8);
          fx?.embers(w, 20, pal: 'violet', w: 26, h: 24, life: 1.5);
          fx?.smoke(wg, n: 6);
          fx?.pulse(pal: 'dark', ms: 850, alpha: mood == 'waking' ? 0.6 : 0.4);
          _later(ms(300), () => st.doShake(big: mood == 'waking'));
          if (mood == 'waking') {
            st.doFlash('violet');
            st.punch(big: true);
          }
        case 'flickering':
          st.retriggerWild('flicker', 900);
          fx?.embers(w, 8, pal: 'violet', life: 1.0);
          fx?.crackleAround(w, r: 12, n: 2, ms: 400);
        default:
          st.retriggerWild('look', 1400);
      }
      if (wild != 0) {
        _later(ms(120), () {
          st.floatText(Offset(numX + 0.04, numY + 0.10), '${(wild > 0) == (sign > 0) ? '+' : '−'}${wild.abs()} $label', bad ? 'bad' : 'good');
          meterTo(after.meter.toDouble(), 380);
        });
      }
      if (drain != 0) {
        // it comes at you: a crouch, a lunge toward the camera, a bolt of Violet Crackle onto your Evochi
        _later(ms(260), () {
          st.retriggerWild('lunge', 900);
          var hurtOnce = false;
          void hurt() {
            if (hurtOnce) return;
            hurtOnce = true;
            _c.audio.buzz(Haptic.hurt);
            st.hitstop(ms(80));
            st.update((s) => s.petExpr = 'surprised');
            st.retriggerPet('hurt', 750);
            fx?.flashAt(p, size: 30, life: 0.3, pal: 'violet');
            fx?.hollowShards(p, n: 8, scale: 0.7);
            fx?.smoke(Offset(p.dx, p.dy + 0.06), n: 6, scale: 0.9);
            st.punch(at: 'pet');
            _later(ms(80), () => st.doShake());
            _sfx('enc_surge', 0.35);
          }

          _later(ms(150), () {
            st.setShot('pet', speed: 'fast');
            _sfx('enc_whoosh', 0.5);
            fx?.smoke(wf, n: 4, scale: 0.7);
            if (fx != null) {
              fx.crackle(wf, p, ms: 320 * k, width: 1.1, jag: 4, segs: 10, branches: 3);
              _later(ms(70), () => fx.crackle(wf, Offset(p.dx + 0.02, p.dy + 0.03), ms: 240 * k, width: 0.7, jag: 5, segs: 9, branches: 2));
              _later(ms(60), hurt);
            } else {
              _later(ms(120), hurt);
            }
          });
          _later(ms(440), () {
            hurt();
            st.floatText(Offset(p.dx, p.dy + 0.04), '$drain Energy', 'bad');
            energyTo(after.energy.toDouble(), 380);
          });
        });
      }
    });
    _later(replyAt + ms(drain != 0 ? 1700 : 1100), () {
      st.setShot('wide');
      setState(() {
        _busy = false;
        _dispMeter = null;
        _dispEnergy = null;
        _holdPet = false;
        _holdWild = false;
      });
    });
  }

  // the last turn: the Hollow cracks, sheds its crystals and dissolves into motes of light, and the
  // creature comes back in a burst; or a befriended one bounces with hearts. Then the outro and the result.
  void _finishChoreo(tr.EncounterView before, tr.EncounterView after) {
    final st = _stage;
    final gm = _geom;
    if (st == null || gm == null) return;
    final fx = st.effects;
    final w = gm.wild;
    final wf = gm.wildFace ?? Offset(w.dx, gm.wildHeadY + 0.06);
    final p = gm.petHead;
    final restore = before.goal != 'befriend';
    final wildH = gm.wildWidth * gm.ar / gm.wildAr; // its frame's height, as a fraction of the backdrop's
    final box = Rect.fromLTWH(gm.wildLeft + gm.wildWidth * 0.15, gm.wildHeadY, gm.wildWidth * 0.7, gm.wildTop + wildH * gm.wildGy - gm.wildHeadY);
    final fl = _finalLog(after);
    setState(() => _log = fl);
    final from = _dispMeter ?? before.meter.toDouble();
    _tween(350, (t) {
      if (_dispMeter == null) return;
      _dispMeter = from + (after.meter - from) * t;
      _syncStage(before);
    });
    _music('none');
    st.setShot('wild');
    void done(int ms) => _later(ms, () {
          setState(() {
            _busy = false;
            _dispMeter = null;
            _dispEnergy = null;
            _holdPet = false;
            _holdWild = false;
            _phase = 'outro';
          });
        });
    void confetti() {
      fx?.burst(w, 26, shape: 'petal', pal: 'pink', blend: BlendMode.srcOver, speed: 62, vary: 0.6, drag: 1.9, size: 2.6, sizeK: 'hold', alphaK: 'hold', life: 1.7, gravity: 42, spin: 7, angle: -math.pi / 2, spread: 1.3);
      fx?.burst(w, 14, shape: 'sparkle', pal: 'gold', speed: 70, vary: 0.6, drag: 2, size: 3.4, sizeK: 'spark', life: 1.2, gravity: 50, spin: 2, angle: -math.pi / 2, spread: 1.4);
    }

    void revealed() {
      // calmed or restored: a little celebration in the hand
      _c.audio.buzz(Haptic.win);
      st.update((s) {
        s.wildState = after.stateKey;
        s.hollow = false;
        s.phase2 = false;
        s.won = true;
      });
    }
    if (restore && fx != null && !_rm) {
      _sfx('enc_glow', 0.6);
      st.retriggerWild('dissolve', 580);
      fx.hollowShards(w, n: 16, scale: 1.2);
      fx.crackleAround(w, r: 16, n: 4, ms: 400);
      fx.dissolve(box, n: 72, ms: 520, pal: 'gold');
      fx.rays(w, n: 9, r: 58, ms: 2400, pal: 'gold', alpha: 0.5);
      fx.halo(w, size: 64, life: 1.3, pal: 'gold', layer: 'back', alpha: 0.9);
      _later(580, () {
        revealed();
        st.retriggerWild('pop', 700);
        _sfx('evolve_fanfare', 0.8);
        st.doFlash('gold');
        st.punch(big: true);
        fx.ring(w, r0: 4, r1: 52, ms: 720, pal: 'gold', width: 3);
        fx.goldenPulse(w, r1: 36, ms: 900, arms: 4, width: 2);
        fx.shards(w, 26, pal: 'gold', scale: 1.3);
        confetti();
        _later(100, () => st.doShake());
        _syncStage(after);
      });
      _later(1250, () {
        st.update((s) => s.petExpr = 'excited');
        st.retriggerPet('hop', 1200);
        fx.hearts(p, n: 3, spread: 4);
      });
      done(1900);
      return;
    }
    revealed();
    _sfx('evolve_fanfare', 0.8);
    st.doFlash('gold');
    fx?.halo(w, size: 56, life: 1.4, pal: 'gold', layer: 'back', alpha: 0.9);
    fx?.rays(w, n: 8, r: 52, ms: 2200, pal: 'gold', alpha: 0.45);
    fx?.ring(w, r0: 4, r1: 46, ms: 700, pal: 'gold', width: 2.6);
    fx?.healing(wf, n: 12, w: 26, h: 20, pal: 'gold');
    fx?.hearts(wf, n: 7, spread: 9);
    confetti();
    st.retriggerWild('joy', 1800);
    _syncStage(after);
    _later(900, () {
      st.update((s) => s.petExpr = 'excited');
      st.retriggerPet('hop', 1200);
      fx?.hearts(p, n: 3, spread: 4);
    });
    done(1400);
  }

  // ------------------------------------------------------------------ actions ----
  void _onAction(String id) {
    if (_busy) return;
    if (id == 'item') {
      _pickItem();
    } else {
      _runTurn(id, null);
    }
  }

  void _pickItem() {
    final c = _c;
    showEvochiSheet<void>(context, builder: (sheet) {
      final v = tr.encounterView(sheet.watch<GameController>().state, c.now);
      if (v == null) return const SizedBox.shrink();
      return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('Offer something', style: EvochiText.section),
        const SizedBox(height: 10),
        if (v.items.isEmpty)
          const Text('Nothing in your Bag helps here yet. Homemade food calms wild Evochi; tonics and Glowleaf steady the Hollow.', style: EvochiText.bodyText)
        else
          for (final it in v.items)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Semantics(
                button: true,
                label: '${it.name}, ${it.qty} owned. ${v.goal == 'befriend' ? 'Plus' : 'Minus'} ${it.amount} ${v.meterLabel}${it.liked ? '. ${v.creature.name} loves this' : ''}',
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    Navigator.pop(sheet);
                    _runTurn('item', it.id);
                  },
                  child: ExcludeSemantics(
                    child: GameCard(
                      padding: const EdgeInsets.fromLTRB(8, 8, 10, 8),
                      child: Row(children: [
                        ItemImage(it.id, size: 48),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [Flexible(child: Text(it.name, style: EvochiText.cardTitle)), const SizedBox(width: 6), Tag('×${it.qty}')]),
                            Text.rich(
                              TextSpan(children: [
                                TextSpan(text: '${v.goal == 'befriend' ? '+' : '−'}${it.amount} ${v.meterLabel}'),
                                if (it.liked) TextSpan(text: ' · ${v.creature.name} loves this', style: const TextStyle(color: EvochiColor.gold900, fontWeight: FontWeight.w800)),
                              ]),
                              style: EvochiText.caption.copyWith(fontSize: 13),
                            ),
                          ]),
                        ),
                      ]),
                    ),
                  ),
                ),
              ),
            ),
        const SizedBox(height: 4),
        EvochiButton(label: 'Back', tone: ButtonTone.cream, onPressed: () => Navigator.pop(sheet)),
      ]);
    });
  }

  void _confirmRetreat() {
    final c = _c;
    showEvochiDialog<void>(context, builder: (d) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Leave for now?', style: EvochiText.section, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          const Text('The encounter ends. Any items you used come back, and you can try again from the Guild whenever you like.', style: EvochiText.bodyText, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          EvochiButton(
            label: 'Retreat',
            onPressed: () {
              Navigator.pop(d);
              _leaving = true;
              _clearTimers();
              _stopIdle();
              final r = c.run((s, n) => tr.encounterAct(s, 'retreat', null, n));
              if (r.ok) {
                _phase = null;
                _seed = null;
                _music(null);
                _toGuild();
              } else {
                _leaving = false;
              }
            },
          ),
          const SizedBox(height: 8),
          EvochiButton(label: 'Stay', tone: ButtonTone.cream, onPressed: () => Navigator.pop(d)),
        ]));
  }

  void _finish(String qid) {
    _leaving = true;
    final r = _c.run((s, n) => tr.completeEncounter(s, n));
    if (!r.ok) {
      _leaving = false;
      return;
    }
    _clearTimers();
    _stopIdle();
    _phase = null;
    _seed = null;
    _music(null);
    _toGuild();
    final root = rootNavigatorKey.currentContext;
    if (root != null) showStoryReward(root, qid, backToVillage: false);
  }

  // ------------------------------------------------------------------ the screen ----
  @override
  Widget build(BuildContext context) {
    final c = context.watch<GameController>();
    final v = tr.encounterView(c.state, c.now);
    final pet = c.state.pet;
    if (v == null || pet == null) {
      // nothing running (retreated, finished, or never started): back to the Guild
      if (!_leaving) {
        _leaving = true;
        WidgetsBinding.instance.addPostFrameCallback((_) => _toGuild());
      }
      return const Scaffold(backgroundColor: Color(0xFF241E2C));
    }
    _rm = MediaQuery.of(context).disableAnimations;
    if (_seed != v.seed) {
      // a new attempt: fresh stage, fresh timeline
      _clearTimers();
      _stage?.dispose();
      _stage = EncounterStage(reducedMotion: _rm);
      _seed = v.seed;
      _busy = false;
      _dispMeter = null;
      _dispEnergy = null;
      _holdPet = false;
      _holdWild = false;
      _logOpen = false;
      _log = null;
      _init = false;
      _introStarted = false;
      _resultShown = false;
      _amb = null;
      _phase ??= widget.fresh ? 'intro' : 'play';
      // the first frame already looks like the intro's opening (no flash of the wide shot)
      final introPending = _phase == 'intro' && !_rm;
      final boss = v.intro == 'boss';
      _stage!
        ..wildState = boss && introPending ? 'dormant' : v.stateKey
        ..shot = introPending ? (boss ? 'face' : 'close') : (_phase == 'card' ? 'hero' : 'wide')
        ..introDark = boss && introPending
        ..petIn = !introPending && _phase != 'card';
    }
    _phase ??= 'play';
    if (v.success && _phase == 'play' && !_busy) _phase = 'outro';
    final hasArt = trailsArt.hasBattle(v.scene, v.creature.id) && art.char(pet.stage).battle != null;
    if (!hasArt) return _NoArtEncounter(view: v, onAction: _onAction, onRetreat: _confirmRetreat, onFinish: () => _finish(v.quest), busy: _busy);
    _geom = shotGeometry(v, pet);
    _stage!.geometry = _geom; // the camera needs it (the first one snaps it to the opening shot)
    WidgetsBinding.instance.addPostFrameCallback((_) => _afterBuild(v));
    final phase = _phase!;
    final stage = EncounterStageView(
      stage: _stage!,
      props: StageProps(
        view: v,
        geometry: _geom!,
        pet: pet,
        petLevel: c.view.pet?.level.level ?? 1,
        phase: phase,
        panelHeight: _ph,
        onSkip: () => _skipIntro(v),
      ),
    );
    final Widget panel = switch (phase) {
      'card' => _IntroCard(key: ValueKey('card-${v.seed}'), view: v, rm: _rm, onBegin: _begin, onRetreat: _confirmRetreat),
      'result' => _SlideUp(key: ValueKey('result-${v.seed}'), rm: _rm, child: _resultPanel(v)),
      _ => _playPanel(v, hidden: phase == 'intro'),
    };
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (v.success) {
          if (phase == 'result') _finish(v.quest);
        } else {
          _confirmRetreat();
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF241E2C),
        body: Semantics(
          label: 'Encounter with ${v.creature.name}',
          child: Stack(fit: StackFit.expand, children: [
            stage,
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: AnimatedSlide(
                // the intro card arrives in place (its own entrance plays), the panel slides
                duration: phase == 'card' ? Duration.zero : const Duration(milliseconds: 550),
                curve: const Cubic(0.3, 0.8, 0.25, 1),
                offset: phase == 'intro' ? const Offset(0, 1.1) : Offset.zero,
                child: IgnorePointer(ignoring: phase == 'intro', child: _Panel(key: _panelKey, bare: phase == 'card', child: panel)),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  // ------------------------------------------------------------------ the panels ----
  Widget _playPanel(tr.EncounterView v, {bool hidden = false}) {
    final lg = _currentLog(v);
    final hollow = v.creature.kind == 'hollow';
    final names = [v.creature.name, _c.state.pet?.name ?? ''];
    final main = v.actions.where((a) => a.kind != 'companion').toList();
    final comp = v.actions.where((a) => a.kind == 'companion').firstOrNull;
    final hist = v.log.length > 1 ? v.log.sublist(math.max(0, v.log.length - 6), v.log.length - 1) : v.log.sublist(0, 0);
    final icn = lg.who == 'wild' && hollow ? 'hollow' : lg.who;
    // one name size for the four actions: the size at which the longest ("Gentle Nudge") fits a half-row
    // button (the panel's frame and padding, the gap, then each button's padding, icon and border)
    final bw = (MediaQuery.of(context).size.width - 2 * 14 - 10) / 2;
    final nameSize = kitFitFontSize(context, main.map((a) => a.name), _ActionButton.nameStyle, bw - 16 - 50 - 6, min: 12);
    return ExcludeSemantics(
      excluding: hidden,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        // the log card: an icon, the headline, the line under it (tap for the earlier lines)
        Semantics(
          button: true,
          liveRegion: true,
          label: '${lg.title}${lg.sub.isEmpty ? '' : '. ${lg.sub}'}. ${_logOpen ? 'Hide' : 'Show'} earlier lines',
          child: GestureDetector(
            onTap: () => setState(() => _logOpen = !_logOpen),
            child: ExcludeSemantics(
              // `.enc-log`: card stock
              child: Container(
                constraints: const BoxConstraints(minHeight: 58),
                padding: const EdgeInsets.fromLTRB(10, 8, 34, 8),
                decoration: Kit.card(radius: 16),
                child: Stack(clipBehavior: Clip.none, children: [
                  Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
                    if (_logOpen && hist.isNotEmpty) ...[
                      for (final l in hist)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 3),
                          child: logText(l.text, names, fontSize: 13, height: 18 / 13, color: l.who == 'you' ? const Color(0xFF6B5040) : EvochiColor.textHelper),
                        ),
                      Container(margin: const EdgeInsets.only(top: 3, bottom: 6), height: 1.5, color: const Color(0xFFE6D5C0)),
                    ],
                    Row(children: [
                      _LogIcon(icn),
                      const SizedBox(width: 10),
                      Expanded(
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 350),
                          transitionBuilder: (child, a) => FadeTransition(opacity: a, child: SlideTransition(position: Tween(begin: const Offset(0, 0.12), end: Offset.zero).animate(a), child: child)),
                          layoutBuilder: (current, previous) => Stack(alignment: Alignment.centerLeft, children: [...previous, if (current != null) current]),
                          child: Column(
                            key: ValueKey('${lg.title}|${lg.sub}'),
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(lg.title, style: const TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w900, fontSize: 15.5, height: 1.2, color: EvochiColor.ink)),
                              if (lg.sub.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(lg.sub, style: const TextStyle(fontFamily: EvochiText.body, fontSize: 13.5, height: 18 / 13.5, color: EvochiColor.textHelper)),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ]),
                  ]),
                  Positioned(
                    right: -21,
                    bottom: 7,
                    child: AnimatedRotation(
                      duration: const Duration(milliseconds: 200),
                      turns: _logOpen ? 0.5 : 0,
                      child: const CustomPaint(size: Size(12, 8), painter: _ChevPainter()),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        for (var i = 0; i < main.length; i += 2)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            // the two buttons of a row share its height. The panel scrolls, so the row has no height
            // of its own to stretch into: without IntrinsicHeight it failed to lay out, which on a
            // phone (a release build) left the panel blank and the battle squeezed above it
            child: IntrinsicHeight(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Expanded(child: _ActionButton(a: main[i], v: v, busy: _busy, nameSize: nameSize, onTap: () => _onAction(main[i].id))),
                const SizedBox(width: 10),
                Expanded(child: i + 1 < main.length ? _ActionButton(a: main[i + 1], v: v, busy: _busy, nameSize: nameSize, onTap: () => _onAction(main[i + 1].id)) : const SizedBox.shrink()),
              ]),
            ),
          ),
        // the companion's ability and Retreat share the last row
        if (comp != null)
          Row(children: [
            Expanded(child: _CompButton(a: comp, v: v, busy: _busy, onTap: () => _onAction(comp.id))),
            const SizedBox(width: 10),
            _RetreatButton(label: 'Retreat', enabled: !_busy && !v.success, onTap: _confirmRetreat),
          ])
        else
          _RetreatButton(label: 'Retreat', enabled: !_busy && !v.success, onTap: _confirmRetreat),
      ]),
    );
  }

  Widget _resultPanel(tr.EncounterView v) {
    final cdef = v.creature;
    final befriend = v.goal == 'befriend';
    final (big, z, sub, ic) = befriend
        ? (cdef.name, 'Is Calmed!', 'You earned its trust!', 'leaf')
        : cdef.boss
            ? (_theName(cdef), 'Is Restored!', 'Its light returns. The old trail is open.', 'sun')
            : (cdef.name, 'Is Restored!', 'Its light is back!', 'sun');
    final r = q.storyQuests[v.quest]!.rewards;
    final tiles = <_ResultTile>[
      _ResultTile(icon: 'creature_${cdef.id}', name: cdef.name.replaceFirst(RegExp(r'^Forgotten '), ''), sub: befriend ? 'Now trusts you!' : 'Restored!', hl: true),
      for (final id in r.items) _ResultTile(item: id, name: catalog[id]?.name ?? id, sub: 'Keepsake'),
      if (r.coins > 0) _ResultTile(icon: 'coin', name: '+${r.coins}', sub: 'EvoCoins'),
      for (final e in r.gifts.entries) _ResultTile(item: e.key, name: '+${e.value}', sub: catalog[e.key]?.name ?? e.key),
      for (final t in r.titles) _ResultTile(icon: 'crown', name: q.titles[t] ?? t, sub: 'Title'),
    ];
    final used = v.used.entries.map((e) => '${catalog[e.key]?.name ?? e.key}${e.value > 1 ? ' ×${e.value}' : ''}').join(', ');
    final (tint, outline) = befriend ? (const Color(0xFF74CC46), const Color(0xFF2C5A1C)) : (const Color(0xFFFFCD4A), const Color(0xFF8A5A12));
    // two outlined lines need air between them (at 0.98 the outline and drop of "The Sentinel" collided
    // with "Is Restored!"): 1.1 line height, 3 px apart, and the second line a size down
    final sw = MediaQuery.of(context).size.width;
    final bigSize = (sw * 0.094).clamp(30.0, 38.0).toDouble();
    final zSize = (sw * 0.076).clamp(25.0, 31.0).toDouble();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Semantics(
        container: true,
        // `.rs-card`: card stock
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
          decoration: Kit.card(radius: 20),
          child: Column(children: [
            // "Petalune / Is Calmed!"
            Semantics(
              header: true,
              label: '$big $z',
              child: ExcludeSemantics(
                child: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Column(children: [
                    _Entrance(delay: 120, ms: 600, stamp: true, rm: _rm, child: _OutlinedText(big, size: bigSize, tint: tint, outline: outline, stroke: 3, drop: 5, dropColor: const Color(0x2E000000), height: 1.1)),
                    const SizedBox(height: 3),
                    _Entrance(delay: 260, ms: 500, stamp: true, rm: _rm, child: _OutlinedText(z, size: zSize, tint: tint, outline: outline, stroke: 3, drop: 5, dropColor: const Color(0x2E000000), height: 1.1)),
                  ]),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(mainAxisSize: MainAxisSize.min, children: [
              EncIcon(ic, size: 24),
              const SizedBox(width: 6),
              Flexible(child: Text(sub, style: const TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w800, fontSize: 15, color: EvochiColor.textSecondary))),
            ]),
            const SizedBox(height: 12),
            const Text('Rewards', style: TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w900, fontSize: 15, color: Color(0xFF4A2D45))),
            const SizedBox(height: 8),
            _ResultTiles(tiles: tiles, restore: !befriend),
            const SizedBox(height: 8),
            Text('${v.turn} turn${v.turn == 1 ? '' : 's'}${used.isEmpty ? '' : ' · $used'}',
                textAlign: TextAlign.center, style: const TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w700, fontSize: 12, color: EvochiColor.textHelper)),
          ]),
        ),
      ),
      const SizedBox(height: 10),
      EncCta(label: 'Continue', trailing: const Icon(Icons.arrow_forward_rounded, size: 26, color: Color(0xFF1F4A22)), onTap: () => _finish(v.quest)),
    ]);
  }
}

/// The action panel under the shot: a WINDOW rising from the bottom, parchment in the carved wood frame
/// (top and sides only, `.enc-panel`); the frame takes the old side padding, so the actions keep their
/// width. [bare] for the intro card, which sits on the darkened shot itself.
class _Panel extends StatelessWidget {
  const _Panel({super.key, required this.child, this.bare = false});
  final Widget child;
  final bool bare;
  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    if (bare) {
      return Padding(padding: EdgeInsets.fromLTRB(22, 0, 22, 14 + mq.padding.bottom), child: child);
    }
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: mq.size.height * 0.74),
      child: FramedWindow(
        border: 11,
        openBottom: true,
        padding: EdgeInsets.fromLTRB(3, 8, 3, 8 + mq.padding.bottom),
        sheet: Kit.sheet(colors: const [Color(0xFFFBF1DC), Color(0xFFF2E0BF)], radius: 4),
        shadow: const BoxShadow(color: Color(0x52140C06), blurRadius: 14, offset: Offset(0, -6)),
        child: SingleChildScrollView(child: child),
      ),
    );
  }
}

/// The result panel comes up from below (panelUp .55s).
class _SlideUp extends StatelessWidget {
  const _SlideUp({super.key, required this.child, required this.rm});
  final Widget child;
  final bool rm;
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: rm ? 0.0 : 1.0, end: 0.0),
        duration: const Duration(milliseconds: 550),
        curve: const Cubic(0.3, 0.8, 0.25, 1),
        builder: (_, t, c) => FractionalTranslation(translation: Offset(0, t), child: c),
        child: child,
      );
}

/// An entrance: a stamp (titleStamp: from 1.7x and transparent, with an overshoot) or a fade up
/// (encFadeUp: 12px), after [delay] ms.
class _Entrance extends StatefulWidget {
  const _Entrance({required this.child, this.delay = 0, this.ms = 500, this.stamp = false, this.rm = false});
  final Widget child;
  final int delay;
  final int ms;
  final bool stamp;
  final bool rm;
  @override
  State<_Entrance> createState() => _EntranceState();
}

class _EntranceState extends State<_Entrance> with SingleTickerProviderStateMixin {
  late final AnimationController _a = AnimationController(vsync: this, duration: Duration(milliseconds: widget.delay + widget.ms));

  @override
  void initState() {
    super.initState();
    if (widget.rm) {
      _a.value = 1;
    } else {
      _a.forward();
    }
  }

  @override
  void dispose() {
    _a.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _a,
        builder: (_, child) {
          final total = widget.delay + widget.ms;
          final raw = ((_a.value * total - widget.delay) / widget.ms).clamp(0.0, 1.0);
          if (widget.stamp) {
            final k = const Cubic(0.2, 1.6, 0.4, 1).transform(raw);
            return Opacity(opacity: k.clamp(0.0, 1.0), child: Transform.scale(scale: 1.7 - 0.7 * k, child: child));
          }
          final k = Curves.ease.transform(raw);
          return Opacity(opacity: k, child: Transform.translate(offset: Offset(0, 12 * (1 - k)), child: child));
        },
        child: widget.child,
      );
}

/// A big game title line with a thick outline and a drop shadow (the web's stacked text-shadows):
/// the shadow, then the outline as a stroke, then the fill.
class _OutlinedText extends StatelessWidget {
  const _OutlinedText(this.text,
      {required this.size, required this.tint, required this.outline, required this.stroke, required this.drop, this.dropColor = const Color(0x47000000), this.letterSpacing = 0, this.height = 0.98});
  final String text;
  final double size;
  final Color tint; // the letters' colour
  final Color outline;
  final double stroke; // the outline's thickness outside the glyph
  final double drop; // the drop shadow's offset down
  final Color dropColor;
  final double letterSpacing;
  final double height; // line height (the result card's two lines want 1.1)
  @override
  Widget build(BuildContext context) {
    final base = TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w900, fontSize: size, height: height, letterSpacing: letterSpacing);
    return Stack(children: [
      Transform.translate(offset: Offset(0, drop), child: Text(text, textAlign: TextAlign.center, style: base.copyWith(color: dropColor))),
      Text(
        text,
        textAlign: TextAlign.center,
        style: base.copyWith(
          foreground: Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = stroke * 2
            ..strokeJoin = StrokeJoin.round
            ..color = outline,
        ),
      ),
      Text(text, textAlign: TextAlign.center, style: base.copyWith(color: tint)),
    ]);
  }
}

/// The intro card on the hero shot: "A Wild / Petalune / Appeared!", the goal, a line about the
/// creature, Begin Encounter and Not yet.
class _IntroCard extends StatelessWidget {
  const _IntroCard({super.key, required this.view, required this.rm, required this.onBegin, required this.onRetreat});
  final tr.EncounterView view;
  final bool rm;
  final VoidCallback onBegin;
  final VoidCallback onRetreat;
  @override
  Widget build(BuildContext context) {
    final c = view.creature;
    final hollow = c.kind == 'hollow';
    final befriend = view.goal == 'befriend';
    final (a, big, z) = _introTitle(c);
    final goal = befriend ? 'Earn its trust' : 'Restore its light';
    final bigSize = (MediaQuery.of(context).size.width * 0.15).clamp(44.0, 60.0);
    const ink = Color(0xFF3B2923);
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.center, children: [
      Semantics(
        header: true,
        label: '$a $big $z',
        child: ExcludeSemantics(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            _Entrance(ms: 500, stamp: true, rm: rm, child: _OutlinedText(a, size: 31, tint: Colors.white, outline: ink, stroke: 3, drop: 6, letterSpacing: 0.3)),
            _Entrance(
              delay: 120,
              ms: 600,
              stamp: true,
              rm: rm,
              child: _OutlinedText(big,
                  size: bigSize,
                  tint: hollow ? const Color(0xFFCBA8FF) : const Color(0xFF92E058),
                  outline: hollow ? const Color(0xFF3A2168) : const Color(0xFF2C5A1C),
                  stroke: 4,
                  drop: 7,
                  dropColor: hollow ? const Color(0x4D000000) : const Color(0x47000000)),
            ),
            _Entrance(delay: 260, ms: 500, stamp: true, rm: rm, child: _OutlinedText(z, size: 31, tint: Colors.white, outline: ink, stroke: 3, drop: 6, letterSpacing: 0.3)),
          ]),
        ),
      ),
      const SizedBox(height: 11),
      // the goal
      _Entrance(
        delay: 400,
        rm: rm,
        child: Container(
          padding: const EdgeInsets.fromLTRB(5, 5, 16, 5),
          decoration: BoxDecoration(
            color: const Color(0xFFFFFDF6),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFF0E2C8), width: 2),
            boxShadow: const [BoxShadow(color: Color(0x33000000), offset: Offset(0, 3))],
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 30,
              height: 30,
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(shape: BoxShape.circle, color: hollow ? const Color(0xFFFFF1C9) : const Color(0xFFE5F2CF)),
              child: EncIcon(befriend ? 'leaf' : 'sun', size: 20),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text.rich(
                TextSpan(children: [
                  const TextSpan(text: 'Goal: '),
                  TextSpan(text: goal, style: const TextStyle(fontWeight: FontWeight.w900, color: EvochiColor.ink)),
                ]),
                style: const TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w800, fontSize: 16, color: EvochiColor.textSecondary),
              ),
            ),
          ]),
        ),
      ),
      const SizedBox(height: 11),
      // a line about it
      _Entrance(
        delay: 500,
        rm: rm,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 330),
          child: Text(
            _introLines[c.id] ?? c.blurb,
            textAlign: TextAlign.center,
            style: const TextStyle(fontFamily: EvochiText.body, fontWeight: FontWeight.w600, fontSize: 15, height: 21 / 15, color: Color(0xFFFFF8EC), shadows: [Shadow(color: Color(0xBF000000), offset: Offset(0, 1), blurRadius: 3)]),
          ),
        ),
      ),
      const SizedBox(height: 11),
      _Entrance(
        delay: 600,
        rm: rm,
        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 340), child: EncCta(label: 'Begin Encounter', gold: true, onTap: onBegin)),
      ),
      const SizedBox(height: 11),
      _RetreatButton(label: 'Not yet', enabled: true, light: true, onTap: onRetreat),
    ]);
  }
}

/// The log card's round icon: a spark for you, a leaf for the wild one, a violet star for the Hollow.
class _LogIcon extends StatelessWidget {
  const _LogIcon(this.kind);
  final String kind; // you | wild | hollow
  @override
  Widget build(BuildContext context) {
    final (bg, ring, icon) = switch (kind) {
      'wild' => (const Color(0xFFE9F5DC), const Color(0xFFBCDDA0), 'leaf'),
      'hollow' => (const Color(0xFFF0E7FC), const Color(0xFFCDB4F2), 'hollow'),
      _ => (const Color(0xFFFFF4D6), const Color(0xFFF2D58F), 'spark'),
    };
    return Container(
      width: 34,
      height: 34,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(shape: BoxShape.circle, color: bg, border: Border.all(color: ring, width: 1.5)),
      child: EncIcon(icon, size: 22),
    );
  }
}

/// The log card's little chevron.
class _ChevPainter extends CustomPainter {
  const _ChevPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final p = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(p, Paint()..color = const Color(0xFFA8937F));
  }

  @override
  bool shouldRepaint(_ChevPainter old) => false;
}

/// A reward on the result card.
class _ResultTile {
  const _ResultTile({this.icon, this.item, required this.name, required this.sub, this.hl = false});
  final String? icon;
  final String? item;
  final String name;
  final String sub;
  final bool hl; // the creature itself, highlighted
}

/// The result's reward tiles in a wrapping grid (auto-fit columns of at least 50px that share the row):
/// five fit one row down to 360 wide (the Sentinel's list used to wrap a lone tile).
class _ResultTiles extends StatelessWidget {
  const _ResultTiles({required this.tiles, required this.restore});
  final List<_ResultTile> tiles;
  final bool restore;
  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (ctx, box) {
        const gapX = 4.0, gapY = 8.0;
        final w = box.maxWidth - 4;
        final cols = math.max(1, ((w + gapX) / (50 + gapX)).floor());
        final per = math.min(cols, math.max(1, tiles.length));
        final tw = (w - gapX * (per - 1)) / per;
        // the picture: clamp(48px, 13.6% of the screen, 58px), the art 82% of it
        final pic = math.min(tw, (MediaQuery.of(ctx).size.width * 0.136).clamp(48.0, 58.0).toDouble());
        final inner = pic * 0.82;
        return Padding(
          padding: const EdgeInsets.fromLTRB(2, 2, 2, 4),
          child: Wrap(spacing: gapX, runSpacing: gapY, children: [
            for (final t in tiles)
              SizedBox(
                width: tw,
                child: Semantics(
                  label: '${t.name}, ${t.sub}',
                  child: ExcludeSemantics(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Container(
                        width: pic,
                        height: pic,
                        alignment: Alignment.center,
                        decoration: t.hl
                            ? BoxDecoration(
                                borderRadius: BorderRadius.circular(14),
                                gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: restore ? const [Color(0xFFFFF6DA), Color(0xFFF8E2A6)] : const [Color(0xFFEAF7D9), Color(0xFFCFEBB0)]),
                                border: Border.all(color: restore ? const Color(0xFFC98A2C) : const Color(0xFF6E9A4E), width: 2),
                                boxShadow: [BoxShadow(color: restore ? const Color(0xFFB4874F) : const Color(0xFF6E9A4E), offset: const Offset(0, 2))],
                              )
                            : Kit.slot(radius: 14),
                        child: t.item != null ? ItemImage(t.item!, size: inner) : VoxelIcon(t.icon ?? 'star', size: inner),
                      ),
                      const SizedBox(height: 2),
                      Text(t.name, textAlign: TextAlign.center, style: const TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w900, fontSize: 12.5, height: 1.15, color: EvochiColor.ink)),
                      Text(t.sub, textAlign: TextAlign.center, style: const TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w700, fontSize: 12, height: 1.2, color: EvochiColor.textHelper)),
                    ]),
                  ),
                ),
              ),
          ]),
        );
      });
}

/// One action: its icon, name and what it costs, coloured by kind.
class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.a, required this.v, required this.busy, required this.onTap, this.nameSize = 15.5});
  static const nameStyle = TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w900, fontSize: 15.5, height: 1.15, color: EvochiColor.ink);
  final double nameSize;
  final tr.ActionView a;
  final tr.EncounterView v;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // gold light is you in every encounter; the Hollow is the violet
    final style = switch (a.kind) {
      'light' => 'sun',
      'physical' => 'orange',
      'restore' => 'teal',
      'item' => 'cream',
      'companion' => 'green',
      _ => 'cream',
    };
    final icon = switch (a.kind) {
      'light' => 'sun',
      'physical' => 'nudge',
      'restore' => 'calm',
      'item' => 'bag',
      'companion' => 'creature_petalune',
      _ => a.icon,
    };
    // (gradient, outline, hard edge, inner shade, drop)
    final (colors, border, edge, shade, drop) = switch (style) {
      'sun' => (const [Color(0xFFFFF4CC), Color(0xFFFFE39A), Color(0xFFF8C75A)], const Color(0xFF9A6414), const Color(0xFF7A4A0E), const Color(0x59C8821E), const Color(0x40965F14)),
      'teal' => (const [Color(0xFFE6FCF4), Color(0xFFB2EDD9), Color(0xFF82DBC1)], const Color(0xFF23705A), const Color(0xFF1C5A48), const Color(0x4D288C6E), const Color(0x381E6E50)),
      'orange' => (const [Color(0xFFFFE6CC), Color(0xFFFDC48E), Color(0xFFF6A262)], const Color(0xFF9A4A1C), const Color(0xFF7A3812), const Color(0x4DC86428), const Color(0x40964614)),
      'green' => (const [Color(0xFFF3FBE8), Color(0xFFD2EDB4), Color(0xFFB3DB8C)], const Color(0xFF3B6E28), const Color(0xFF2C5520), const Color(0x4D508C32), const Color(0x383C6414)),
      _ => (const [Color(0xFFFFF9EC), Color(0xFFF4E3C4), Color(0xFFE9D3AA)], const Color(0xFF8F6A42), const Color(0xFF7A5A36), const Color(0x4DAA8250), const Color(0x2E78501E)),
    };
    final cream = style == 'cream';
    final enabled = a.can && !busy && !v.success;
    final sub = _actionSub(a, v);
    return Semantics(
      button: true,
      enabled: enabled,
      label: _actionLong(a, v),
      child: ExcludeSemantics(
        child: KitPress(
          onTap: enabled
              ? () {
                  context.read<GameController>().audio.tick();
                  onTap();
                }
              : null,
          builder: (_, down) => AnimatedOpacity(
            duration: const Duration(milliseconds: 250),
            opacity: enabled ? 1 : (busy ? 0.8 : 0.55),
            child: ColorFiltered(
              colorFilter: enabled ? const ColorFilter.mode(Colors.transparent, BlendMode.dst) : ColorFilter.matrix(_saturate(busy ? 0.75 : 0.4)),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 60),
                constraints: BoxConstraints(minHeight: a.kind == 'companion' ? 60 : 66),
                transform: Matrix4.translationValues(0, down ? 3 : 0, 0),
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 9),
                decoration: KitDecoration(
                  base: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: border, width: 2.5),
                    gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: colors, stops: cream ? const [0, 0.6, 1] : const [0, 0.5, 1]),
                    image: cream ? kitGrain : null,
                    boxShadow: [
                      if (!down) BoxShadow(color: drop, blurRadius: 12, offset: const Offset(0, 7)),
                      BoxShadow(color: down ? const Color(0x993C1E05) : edge, offset: Offset(0, down ? 1 : 4)),
                    ],
                  ),
                  inset: 2.5,
                  bottom: down ? null : KitBand(3, shade),
                  shadow: down ? const BoxShadow(color: Color(0x403C1E05), blurRadius: 4, offset: Offset(0, 2)) : null,
                  glossTop: down ? const Color(0x44FFFFFF) : const Color(0x99FFFFFF),
                  glossBottom: const Color(0x00FFFFFF),
                  glossSmall: true,
                ),
                child: Row(children: [
                  SizedBox(width: 42, height: 42, child: VoxelIcon(icon, size: 42)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                      Text(a.name, maxLines: 1, softWrap: false, overflow: TextOverflow.clip, style: nameStyle.copyWith(fontSize: nameSize)),
                      const SizedBox(height: 2),
                      Text(sub, style: const TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w800, fontSize: 12.5, height: 1.2, color: Color(0xC73B2923))),
                    ]),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The companion's ability: a compact green button beside Retreat (Petal Hush, once an encounter).
class _CompButton extends StatefulWidget {
  const _CompButton({required this.a, required this.v, required this.busy, required this.onTap});
  final tr.ActionView a;
  final tr.EncounterView v;
  final bool busy;
  final VoidCallback onTap;
  @override
  State<_CompButton> createState() => _CompButtonState();
}

class _CompButtonState extends State<_CompButton> {
  bool _down = false;
  @override
  Widget build(BuildContext context) {
    final a = widget.a;
    final v = widget.v;
    final enabled = a.can && !widget.busy && !v.success;
    return Semantics(
      button: true,
      enabled: enabled,
      label: '${_actionLong(a, v)}, once this encounter',
      child: ExcludeSemantics(
        child: GestureDetector(
          onTapDown: enabled ? (_) => setState(() => _down = true) : null,
          onTapCancel: () => setState(() => _down = false),
          onTapUp: (_) => setState(() => _down = false),
          onTap: enabled
              ? () {
                  context.read<GameController>().audio.tick();
                  widget.onTap();
                }
              : null,
          child: Opacity(
            opacity: enabled ? 1 : 0.55,
            child: ColorFiltered(
              colorFilter: enabled ? const ColorFilter.mode(Colors.transparent, BlendMode.dst) : ColorFilter.matrix(_saturate(0.4)),
              child: Container(
                constraints: const BoxConstraints(minHeight: 48),
                transform: Matrix4.translationValues(0, _down ? 2 : 0, 0),
                padding: const EdgeInsets.fromLTRB(6, 4, 12, 4),
                // `.enc-comp`: a green outline, a gloss strip, a hard edge
                decoration: KitDecoration(
                  base: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFF3B6E28), width: 2.5),
                    gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFF3FBE8), Color(0xFFD2EDB4)]),
                    boxShadow: [BoxShadow(color: const Color(0xFF2C5520), offset: Offset(0, _down ? 1 : 3))],
                  ),
                  inset: 2.5,
                  bottom: _down ? null : const KitBand(2, Color(0x4D508C32)),
                  glossTop: const Color(0x99FFFFFF),
                  glossBottom: const Color(0x00FFFFFF),
                  glossSmall: true,
                ),
                child: Row(children: [
                  const VoxelIcon('creature_petalune', size: 38),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                      Text(a.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w900, fontSize: 14.5, height: 1.1, color: EvochiColor.ink)),
                      Text(_actionSub(a, v), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w800, fontSize: 12, color: Color(0xB33B2923))),
                    ]),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// saturate(s) as a colour matrix.
List<double> _saturate(double s) {
  const lr = 0.213, lg = 0.715, lb = 0.072;
  return <double>[
    lr + (1 - lr) * s, lg - lg * s, lb - lb * s, 0, 0, //
    lr - lr * s, lg + (1 - lg) * s, lb - lb * s, 0, 0, //
    lr - lr * s, lg - lg * s, lb + (1 - lb) * s, 0, 0, //
    0, 0, 0, 1, 0,
  ];
}

/// "Retreat" / "Not yet": a text button with a running figure ([light] on the dark intro card).
class _RetreatButton extends StatelessWidget {
  const _RetreatButton({required this.label, required this.enabled, required this.onTap, this.light = false});
  final String label;
  final bool enabled;
  final VoidCallback onTap;
  final bool light;
  @override
  Widget build(BuildContext context) {
    final color = light ? const Color(0xFFFFF3DE) : const Color(0xFF6B5143);
    final shadows = light ? const [Shadow(color: Color(0x99000000), offset: Offset(0, 1), blurRadius: 2)] : null;
    return Center(
      child: Semantics(
        button: true,
        enabled: enabled,
        label: label,
        child: ExcludeSemantics(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: enabled ? onTap : null,
            child: Opacity(
              opacity: enabled ? 1 : 0.45,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.directions_run_rounded, size: 20, color: color, shadows: shadows),
                  const SizedBox(width: 6),
                  Text(label, style: TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w900, fontSize: 15.5, color: color, shadows: shadows)),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Older art packs without the battle shots: the creature and your Evochi on a dark stage, with the
/// same panel logic in its simplest form (log, actions, result).
class _NoArtEncounter extends StatelessWidget {
  const _NoArtEncounter({required this.view, required this.onAction, required this.onRetreat, required this.onFinish, required this.busy});
  final tr.EncounterView view;
  final void Function(String id) onAction;
  final VoidCallback onRetreat;
  final VoidCallback onFinish;
  final bool busy;
  @override
  Widget build(BuildContext context) {
    final v = view;
    final c = context.watch<GameController>();
    final pet = c.state.pet;
    return Scaffold(
      backgroundColor: const Color(0xFF241E2C),
      body: SafeArea(
        child: Column(children: [
          Expanded(
            child: Stack(children: [
              Center(child: CreatureImage(v.creature.id, state: v.stateKey, height: v.creature.size == 'large' ? 220 : 160)),
              if (pet != null) Positioned(left: 16, bottom: 12, child: PetSprite(stage: pet.stage, palette: pet.paletteId, expr: v.success ? 'excited' : 'default', overlays: pet.equipped.values.toList(), height: 120)),
              Positioned(
                left: 14,
                right: 14,
                top: 12,
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: Kit.card(paper: KitPaper.plate, radius: 16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Text(v.creature.name, style: EvochiText.cardTitle.copyWith(fontWeight: FontWeight.w900)),
                    const SizedBox(height: 6),
                    StageMeter(kind: v.goal == 'befriend' ? 'calm' : 'inst', label: v.meterLabel, frac: v.meter / v.max, value: '${v.meter} / ${v.max}'),
                    const SizedBox(height: 6),
                    StageMeter(kind: 'energy', label: 'Energy', frac: v.energyMax == 0 ? 0 : v.energy / v.energyMax, value: '${v.energy} / ${v.energyMax}', labelInside: false),
                  ]),
                ),
              ),
            ]),
          ),
          _Panel(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
              Text(v.log.isEmpty ? '' : v.log.last.text, style: EvochiText.bodyText.copyWith(fontSize: 15)),
              const SizedBox(height: 10),
              if (v.success)
                EncCta(label: 'Continue', onTap: onFinish)
              else ...[
                for (final a in v.actions)
                  Padding(padding: const EdgeInsets.only(bottom: 10), child: _ActionButton(a: a, v: v, busy: busy, onTap: () => onAction(a.id))),
                _RetreatButton(label: 'Retreat', enabled: !busy, onTap: onRetreat),
              ],
            ]),
          ),
        ]),
      ),
    );
  }
}
