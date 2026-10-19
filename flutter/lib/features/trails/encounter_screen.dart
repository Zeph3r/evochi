// Lumen Trails: the encounter. The battle shot (your Evochi from behind in the foreground, the wild
// one facing it), the intro cinematics on that same shot (the Sentinel's awakening is a story beat of
// its own), turn choreography with camera moves and ability effects, and the result.
//
// The stage (encounter_stage.dart) is one live widget tree driven imperatively through an
// [EncounterStage], so camera moves and effects never restart when the state re-renders; the panel
// under it (log, actions, goal and result cards) is ordinary widgets that rebuild with the state.
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
import '../../core/models/game_state.dart';
import '../../game/story/story.dart' as q;
import '../../game/trails/trails.dart' as tr;
import '../shared/sprite.dart';
import '../shared/widgets.dart';
import '../village/story_widgets.dart';
import 'encounter_stage.dart';
import 'trails_widgets.dart';

/// An intro's length, music and title.
class _Intro {
  const _Intro(this.ms, this.music, this.sub);
  final int ms;
  final String music;
  final String sub;
}

const _intros = <String, _Intro>{
  'rare': _Intro(4300, 'enc_wild_loop', 'Something rare is watching you.'),
  'hollow': _Intro(4900, 'enc_boss_loop', 'Hollow energy pulses in the stones.'),
  'boss': _Intro(8200, 'enc_boss_loop', 'Guardian of the Lumen Trails'),
  'standard': _Intro(2600, 'enc_wild_loop', ''),
};

String _introTitle(String intro, tr.Creature c) => switch (intro) {
      'rare' => 'A wild ${c.name} appeared!',
      'hollow' => '${c.name} stirs…',
      'boss' => 'The ${c.name.replaceFirst(RegExp(r'^Forgotten '), '')} awakens',
      _ => '${c.name} peeks out',
    };

String _petExpr(tr.EncounterView v) {
  if (v.success) return 'excited';
  if (v.energy < 25) return 'sleepy';
  return 'default';
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
  (String, String)? _log; // the line being shown while busy (text, who)
  bool _init = false, _introStarted = false, _titleShown = false, _ribbon = false;
  Timer? _outroTimer;
  final _timers = <Timer>[];
  bool _leaving = false;
  bool _rm = false;

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

  @override
  void dispose() {
    _clearTimers();
    _stage?.dispose();
    _c.audio.setMusic(null);
    super.dispose();
  }

  void _toGuild() {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(guildRoute());
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
  }

  /// After each frame (the web's `mount`): measure the panel, sync the stage, start the intro or the
  /// outro, and show the ribbon on the result.
  void _afterBuild(tr.EncounterView v) {
    if (!mounted || _stage == null) return;
    final h = _panelKey.currentContext?.size?.height;
    if (h != null && (h - _ph).abs() > 0.5) setState(() => _ph = h);
    _syncStage(v);
    final st = _stage!;
    if (!_init) {
      _init = true;
      if (_phase == 'intro' && !_introStarted) {
        _introStarted = true;
        _playIntro(v);
      } else {
        // a fresh stage mid-encounter (came back from elsewhere): no intro, just the shot
        st.update((s) {
          s.petIn = true;
          s.lit = true;
          s.eyeL = true;
          s.eyeR = true;
          if (v.success) s.won = true;
        });
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
    final on = _phase == 'result';
    if (on && !_ribbon) {
      _ribbon = true;
      st.setShot('wild');
    } else if (!on && _ribbon) {
      _ribbon = false;
    }
  }

  // ------------------------------------------------------------------ intros (on the same shot) ----
  void _playIntro(tr.EncounterView v) {
    final st = _stage!;
    final g = _geom!;
    final intro = _intros[v.intro] ?? _intros['standard']!;
    void done() {
      if (!mounted) return;
      if (_phase != 'intro') return;
      setState(() {
        _titleShown = false;
        _phase = 'card';
        _holdWild = false;
        _holdPet = false;
      });
    }

    void showTitle() => setState(() => _titleShown = true);
    if (_rm) {
      st.setShot('wide', instant: true);
      st.update((s) {
        s.petIn = true;
        s.lit = true;
        if (v.intro == 'boss') s.wildState = v.stateKey;
      });
      _music(intro.music);
      showTitle();
      _later(1400, done);
      return;
    }
    if (v.intro == 'boss') {
      // the Sentinel's awakening: dark and still, a rumble, its eyes light one after the other, the
      // ruins shake, your Evochi flinches, and the music turns before the encounter begins
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
      });
      _later(1100, () => st.doShake());
      _later(1500, () {
        _sfx('enc_awaken', 0.9);
        st.update((s) => s.eyeL = true);
      });
      _later(2300, () => st.update((s) => s.eyeR = true));
      _later(3300, () => st.update((s) {
            s.wildState = 'hollow';
            s.lit = true;
          }));
      _later(3850, () {
        st.doShake(big: true);
        st.doFlash('violet');
        st.burst('ring violet', g.wild, n: 1, life: 1400);
        st.setShot('wide');
        st.update((s) => s.petIn = true);
      });
      _later(4500, () {
        st.update((s) => s.petExpr = 'surprised');
        st.retriggerPet('flinch', 1100);
        _sfx('pet_chirp', 0.5);
        _music(intro.music);
      });
      _later(5400, showTitle);
      _later(intro.ms, () {
        st.update((s) {
          s.trembling = false;
          s.petExpr = 'determined';
        });
        _holdPet = false;
        done();
      });
      return;
    }
    // rare / hollow / standard: start close on the wild one, then pull back as your Evochi steps in
    st.setShot('close', instant: true);
    _music(intro.music);
    final hollow = v.intro == 'hollow';
    if (hollow) {
      st.update((s) => s.silhouette = true);
      _later(500, () {
        _sfx('enc_surge', 0.6);
        st.burst('ring violet', g.wild, n: 1, life: 1400);
        st.doShake();
      });
      _later(1500, () => st.update((s) => s.silhouette = false));
    } else {
      _later(900, () {
        st.retriggerWild('bang', 1600);
        _sfx('pet_chirp', 0.45);
      });
    }
    _later(hollow ? 2000 : 1700, () {
      st.setShot('wide');
      st.update((s) {
        s.petIn = true;
        s.lit = true;
      });
      _sfx('enc_whoosh', 0.5);
    });
    _later(hollow ? 2900 : 2600, showTitle);
    _later(intro.ms, done);
  }

  void _skipIntro(tr.EncounterView v) {
    _clearTimers();
    final st = _stage;
    if (st != null) {
      st.update((s) {
        s.trembling = false;
        s.silhouette = false;
        s.petIn = true;
        s.lit = true;
        s.eyeL = true;
        s.eyeR = true;
      });
      st.setShot('wide', instant: true);
      _music((_intros[v.intro] ?? _intros['standard']!).music);
    }
    setState(() {
      _holdWild = false;
      _holdPet = false;
      _titleShown = false;
      _phase = 'card';
    });
  }

  // ------------------------------------------------------------------ a turn, choreographed ----
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
    final a = tr.encounterActions[actionId]!;
    final k = _rm ? 0.35 : 1.0;
    int ms(num x) => (x * k).round();
    final sign = before.goal == 'befriend' ? 1 : -1;
    final label = before.meterLabel;
    final mid = (before.meter + sign * you).clamp(0, before.max).toDouble();
    final cost = math.max(0, a.energy);
    final hollow = before.creature.kind == 'hollow';
    final youLine = after.log.length > before.log.length ? after.log[before.log.length].text : '';
    final wildLine = after.log.isNotEmpty ? after.log.last.text : '';
    // the panel: lock the buttons, show your line; the plates: pay the Energy at once
    setState(() {
      _busy = true;
      _holdPet = true;
      _holdWild = true;
      _dispMeter = before.meter.toDouble();
      _dispEnergy = (before.energy - cost).toDouble();
      _log = (youLine, 'you');
    });
    _syncStage(before);
    st.update((s) => s.petExpr = 'determined');
    final w = gm.wild;
    final p = gm.petHead;
    var impact = 900;
    // 1-2. your move
    switch (a.kind) {
      case 'light':
        st.setShot('pet');
        st.retriggerPet('cast', 900);
        _sfx('enc_glow', 0.7);
        _later(ms(380), () {
          st.projectile(hollow ? 'orb violet' : 'orb', p, w, ms(520), arc: -6);
          st.setShot('wild');
        });
        impact = ms(900);
      case 'physical':
        st.setShot('pet');
        st.retriggerPet('lunge', 800);
        _sfx('enc_whoosh', 0.6);
        _later(ms(300), () => st.setShot('wild'));
        impact = ms(420);
      case 'restore':
        st.setShot('pet');
        st.retriggerPet('rest', 1300);
        st.update((s) => s.petExpr = 'sleepy');
        _sfx('enc_soothe', 0.6);
        st.burst('ring teal', gm.pet, n: 1, life: 1200);
        for (var i = 0; i < 5; i++) {
          _later(ms(i * 120), () => st.rise(Offset(gm.petCx + (i - 2) * 0.04, gm.petCy - 0.04), 'heart', 1300));
        }
        _later(ms(650), () {
          _dispEnergy = math.min(before.energyMax, before.energy + 30).toDouble();
          _syncStage(before);
          st.floatText(Offset(p.dx, p.dy + 0.04), '+30 Energy', 'energy');
        });
        _later(ms(900), () => st.setShot('wide'));
        impact = ms(1150);
      case 'item':
        st.setShot('pet');
        _sfx('enc_whoosh', 0.5);
        _later(ms(200), () {
          st.projectile('toss', p, Offset(w.dx, w.dy + 0.04), ms(700), arc: -18, itemId: itemId);
          st.setShot('wild');
        });
        impact = ms(920);
      case 'companion':
        st.setShot('wide');
        st.buddy();
        _sfx('enc_soothe', 0.6);
        for (var i = 0; i < 9; i++) {
          _later(ms(200 + i * 60), () => st.projectile('petal', Offset(0.04, 0.64 + (i % 3) * 0.06), Offset(w.dx + ((i % 3) * 3 - 3) / 100, w.dy + (i % 2) * 0.04), ms(760), arc: -10 - (i % 4) * 4));
        }
        impact = ms(1050);
    }
    // 3. impact on the wild one
    _later(impact, () {
      _dispMeter = mid;
      _syncStage(before);
      switch (a.kind) {
        case 'light':
          st.burst(hollow ? 'spark violet' : 'spark', w, n: 9);
          st.doFlash(hollow ? 'violet' : 'gold');
          _sfx('reward_chime', 0.35);
        case 'physical':
          st.burst('boop', Offset(w.dx - 0.03, w.dy + 0.02), n: 6, inner: 'spark');
          _sfx('play_boing', 0.5);
        case 'item':
          st.burst('boop', w, n: 6, inner: you >= 20 ? 'heart' : 'spark');
          _sfx('pet_chirp', 0.45);
        default:
          st.burst('boop soft', w, n: 5, inner: a.kind == 'companion' ? 'heart' : 'spark');
      }
      if (a.kind != 'restore' || you != 0) st.retriggerWild(a.kind == 'restore' ? 'perk' : 'hit', 700);
      if (you != 0) st.floatText(Offset(w.dx, gm.wildHeadY + 0.02), '${sign > 0 ? '+' : '−'}$you $label', hollow ? 'good violet' : 'good');
    });
    // 4. the reply (or the finish)
    final replyAt = impact + ms(650);
    if (after.success) {
      _later(replyAt - ms(250), () => _finishChoreo(before, after));
      return;
    }
    _later(replyAt, () {
      setState(() => _log = (wildLine, 'wild'));
      final bad = wild < 0;
      st.setShot(mood == 'surging' || drain != 0 ? 'wild' : 'wide');
      st.update((s) => s.wildMood = mood ?? '');
      switch (mood) {
        case 'wary':
          st.retriggerWild('skitter', 900);
          _sfx('enc_whoosh', 0.35);
        case 'curious':
          st.retriggerWild('tilt', 900);
          st.bubble(Offset(w.dx + 0.06, gm.wildHeadY - 0.02), '?');
        case 'surging' || 'waking':
          _sfx('enc_surge', 0.6);
          st.burst('ring violet', w, n: 1, life: 1200);
          st.retriggerWild('surge', 900);
          st.doShake(big: mood == 'waking');
          if (mood == 'waking') st.doFlash('violet');
        case 'flickering':
          st.retriggerWild('flicker', 900);
        default:
          st.burst('boop soft', w, n: 4, inner: 'spark');
      }
      if (wild != 0) {
        _dispMeter = after.meter.toDouble();
        _syncStage(before);
        st.floatText(Offset(w.dx, gm.wildHeadY + 0.02), '${(wild > 0) == (sign > 0) ? '+' : '−'}${wild.abs()} $label', bad ? 'bad' : 'good');
      }
      if (drain != 0) {
        _later(ms(320), () {
          st.projectile('lash', w, gm.petHead, ms(300), arc: 4);
          _later(ms(300), () {
            st.update((s) => s.petExpr = 'surprised');
            st.retriggerPet('hurt', 700);
            st.doShake();
            _dispEnergy = after.energy.toDouble();
            _syncStage(before);
            st.floatText(Offset(p.dx, p.dy + 0.04), '$drain Energy', 'bad');
          });
        });
      }
    });
    _later(replyAt + ms(drain != 0 ? 1500 : 1100), () {
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

  void _finishChoreo(tr.EncounterView before, tr.EncounterView after) {
    final st = _stage;
    final gm = _geom;
    if (st == null || gm == null) return;
    final w = gm.wild;
    setState(() => _log = (after.log.isEmpty ? '' : after.log.last.text, 'wild'));
    _dispMeter = after.meter.toDouble();
    _syncStage(before);
    st.update((s) {
      s.wildState = after.stateKey;
      s.hollow = false;
      s.phase2 = false;
      s.won = true;
    });
    _music('none');
    _sfx('evolve_fanfare', 0.8);
    st.setShot('wild');
    st.doFlash('gold');
    st.burst('spark big', w, n: 12, life: 1400);
    st.retriggerWild('joy', 1800);
    for (var i = 0; i < 6; i++) {
      _later(300 + i * 160, () => st.rise(Offset(w.dx + (i - 2.5) * 0.05, w.dy - 0.06), 'heart', 1500, big: true));
    }
    _later(900, () {
      st.update((s) => s.petExpr = 'excited');
      st.retriggerPet('hop', 1200);
    });
    _later(1300, () {
      setState(() {
        _busy = false;
        _dispMeter = null;
        _dispEnergy = null;
        _holdPet = false;
        _holdWild = false;
        _phase = 'outro';
      });
    });
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
      _titleShown = false;
      _ribbon = false;
      _phase ??= widget.fresh ? 'intro' : 'play';
      // the first frame already looks like the intro's opening (no flash of the wide shot)
      final introPending = _phase == 'intro' && !_rm;
      final boss = v.intro == 'boss';
      _stage!
        ..wildState = boss && introPending ? 'dormant' : v.stateKey
        ..shot = introPending ? (boss ? 'face' : 'close') : 'wide'
        ..introDark = boss && introPending
        ..petIn = !introPending;
    }
    _phase ??= 'play';
    if (v.success && _phase == 'play' && !_busy) _phase = 'outro';
    final hasArt = trailsArt.hasBattle(v.scene, v.creature.id) && art.char(pet.stage).battle != null;
    if (!hasArt) return _NoArtEncounter(view: v, onAction: _onAction, onRetreat: _confirmRetreat, onFinish: () => _finish(v.quest), busy: _busy);
    _geom = shotGeometry(v, pet);
    WidgetsBinding.instance.addPostFrameCallback((_) => _afterBuild(v));
    final phase = _phase!;
    final intro = _intros[v.intro] ?? _intros['standard']!;
    final stage = EncounterStageView(
      stage: _stage!,
      props: StageProps(
        view: v,
        geometry: _geom!,
        pet: pet,
        petLevel: c.view.pet?.level.level ?? 1,
        phase: phase,
        panelHeight: _ph,
        title: _introTitle(v.intro, v.creature),
        titleSub: intro.sub,
        titleShown: _titleShown,
        onSkip: () => _skipIntro(v),
      ),
    );
    final Widget panel = switch (phase) {
      'card' => _cardPanel(v, pet),
      'result' => _resultPanel(v),
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
                duration: const Duration(milliseconds: 550),
                curve: const Cubic(0.3, 0.8, 0.25, 1),
                offset: phase == 'intro' ? const Offset(0, 1.1) : Offset.zero,
                child: IgnorePointer(ignoring: phase == 'intro', child: _Panel(key: _panelKey, child: panel)),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  // ------------------------------------------------------------------ the panels ----
  Widget _playPanel(tr.EncounterView v, {bool hidden = false}) {
    final hollow = v.creature.kind == 'hollow';
    final last = _busy && _log != null ? _log! : (v.log.isEmpty ? ('', 'wild') : (v.log.last.text, v.log.last.who));
    final names = [v.creature.name, _c.state.pet?.name ?? ''];
    final main = v.actions.where((a) => a.kind != 'companion').toList();
    final comp = v.actions.where((a) => a.kind == 'companion').firstOrNull;
    final hist = v.log.length > 1 ? v.log.sublist(math.max(0, v.log.length - 6), v.log.length - 1) : v.log.sublist(0, 0);
    return ExcludeSemantics(
      excluding: hidden,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Semantics(
          button: true,
          liveRegion: true,
          label: '${last.$1}. Turn ${v.turn + 1}. ${_logOpen ? 'Hide' : 'Show'} earlier lines',
          child: GestureDetector(
            onTap: () => setState(() => _logOpen = !_logOpen),
            child: ExcludeSemantics(
              child: Container(
                constraints: const BoxConstraints(minHeight: 64),
                padding: const EdgeInsets.fromLTRB(14, 10, 36, 9),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFDF9),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFEBDCC8), width: 2),
                  boxShadow: const [BoxShadow(color: Color(0xFFE4D2BC), offset: Offset(0, 2))],
                ),
                child: Stack(clipBehavior: Clip.none, children: [
                  Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    if (_logOpen && hist.isNotEmpty) ...[
                      for (final l in hist)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 3),
                          child: logText(l.text, names, fontSize: 13, height: 18 / 13, color: l.who == 'you' ? const Color(0xFF6B5040) : EvochiColor.textHelper),
                        ),
                      Container(margin: const EdgeInsets.only(top: 3, bottom: 6), height: 1.5, color: const Color(0xFFE6D5C0)),
                    ],
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 350),
                      transitionBuilder: (child, a) => FadeTransition(opacity: a, child: SlideTransition(position: Tween(begin: const Offset(0, 0.25), end: Offset.zero).animate(a), child: child)),
                      layoutBuilder: (current, previous) => Stack(alignment: Alignment.topLeft, children: [...previous, if (current != null) current]),
                      child: KeyedSubtree(key: ValueKey(last.$1), child: logText(last.$1, names)),
                    ),
                    const SizedBox(height: 3),
                    Text('Turn ${v.turn + 1}${v.phase2 ? ' · waking' : ''}', style: const TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w800, fontSize: 11.5, color: EvochiColor.textHelper)),
                  ]),
                  Positioned(
                    right: -26,
                    bottom: 2,
                    child: AnimatedRotation(
                      duration: const Duration(milliseconds: 200),
                      turns: _logOpen ? 0.5 : 0,
                      child: const Icon(Icons.arrow_drop_down_rounded, size: 22, color: Color(0xFFA8937F)),
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
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Expanded(child: _ActionButton(a: main[i], v: v, hollow: hollow, busy: _busy, onTap: () => _onAction(main[i].id))),
              const SizedBox(width: 10),
              Expanded(child: i + 1 < main.length ? _ActionButton(a: main[i + 1], v: v, hollow: hollow, busy: _busy, onTap: () => _onAction(main[i + 1].id)) : const SizedBox.shrink()),
            ]),
          ),
        if (comp != null) Padding(padding: const EdgeInsets.only(bottom: 10), child: _ActionButton(a: comp, v: v, hollow: hollow, busy: _busy, onTap: () => _onAction(comp.id))),
        _RetreatButton(label: 'Retreat', enabled: !_busy && !v.success, onTap: _confirmRetreat),
      ]),
    );
  }

  Widget _cardPanel(tr.EncounterView v, Pet pet) {
    final cdef = v.creature;
    final hollow = cdef.kind == 'hollow';
    final befriend = v.goal == 'befriend';
    final rec = v.recommended.items.map((i) => catalog[i]?.name ?? i).join(', ');
    final have = v.items.take(3).map((i) => '${i.name}${i.qty > 1 ? ' ×${i.qty}' : ''}').join(', ');
    final body = TextStyle(fontFamily: EvochiText.body, fontSize: 14.5, height: 20 / 14.5, color: EvochiColor.textSecondary);
    final bold = body.copyWith(fontWeight: FontWeight.w900, color: EvochiColor.ink);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Semantics(
        container: true,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
          decoration: BoxDecoration(
            color: const Color(0xFFFFFDF9),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFEBDCC8), width: 2),
            boxShadow: const [BoxShadow(color: Color(0xFFE4D2BC), offset: Offset(0, 2))],
          ),
          child: Column(children: [
            Container(
              padding: const EdgeInsets.fromLTRB(4, 3, 12, 3),
              decoration: BoxDecoration(color: hollow ? const Color(0xFFEEE4FB) : const Color(0xFFE5F2CF), borderRadius: BorderRadius.circular(13)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                VoxelIcon(befriend ? 'calm' : 'purify', size: 24),
                const SizedBox(width: 6),
                Text(befriend ? 'Befriend' : 'Restore', style: TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w900, fontSize: 13.5, color: hollow ? const Color(0xFF5B3AA0) : const Color(0xFF3E7D33))),
              ]),
            ),
            const SizedBox(height: 6),
            Semantics(header: true, child: Text(cdef.boss ? cdef.name : '${cdef.name} appeared', textAlign: TextAlign.center, style: const TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w900, fontSize: 21, height: 1.2, color: EvochiColor.ink))),
            const SizedBox(height: 5),
            Text.rich(
              TextSpan(style: body, children: [
                if (befriend) ...[
                  const TextSpan(text: 'Fill its '),
                  TextSpan(text: 'Calm', style: bold),
                  TextSpan(text: ' meter. Take turns using abilities, items or a quiet moment. ${cdef.name} may skitter, but nothing here can hurt ${pet.name}.'),
                ] else ...[
                  const TextSpan(text: 'Bring its '),
                  TextSpan(text: 'Instability', style: bold),
                  TextSpan(text: ' to zero. Lumen Glow works best on the Hollow. It may tire ${pet.name} out, never worse.'),
                ],
              ]),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              ItemImage(v.recommended.items.first, size: 24),
              const SizedBox(width: 5),
              Flexible(
                child: Text.rich(
                  TextSpan(style: const TextStyle(fontFamily: EvochiText.body, fontWeight: FontWeight.w700, fontSize: 13, color: EvochiColor.textSecondary), children: [
                    const TextSpan(text: 'Recommended: '),
                    TextSpan(text: rec, style: const TextStyle(fontWeight: FontWeight.w900, color: EvochiColor.ink)),
                  ]),
                ),
              ),
            ]),
            const SizedBox(height: 3),
            Text(have.isNotEmpty ? 'You have $have' : 'No useful items yet (that’s fine)', textAlign: TextAlign.center, style: const TextStyle(fontFamily: EvochiText.body, fontSize: 13, color: EvochiColor.textHelper)),
          ]),
        ),
      ),
      const SizedBox(height: 10),
      EncCta(
        label: 'Begin',
        onTap: () {
          _sfx('ui_tap', 0.4);
          setState(() => _phase = 'play');
        },
      ),
      const SizedBox(height: 4),
      _RetreatButton(label: 'Not yet', enabled: true, onTap: _confirmRetreat),
    ]);
  }

  Widget _resultPanel(tr.EncounterView v) {
    final cdef = v.creature;
    final r = q.storyQuests[v.quest]!.rewards;
    final a = tr.affinityDefs[cdef.affinity]!;
    final befriend = v.goal == 'befriend';
    final used = v.used.entries.map((e) => '${catalog[e.key]?.name ?? e.key}${e.value > 1 ? ' ×${e.value}' : ''}').join(', ');
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Container(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFDF9),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFEBDCC8), width: 2),
          boxShadow: const [BoxShadow(color: Color(0xFFE4D2BC), offset: Offset(0, 2))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Rewards', textAlign: TextAlign.center, style: TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w900, fontSize: 16, color: Color(0xFF4A2D45))),
          const SizedBox(height: 8),
          RewardTiles(rewardTilesFor(r, cdef, v.goal), row: true),
        ]),
      ),
      const SizedBox(height: 10),
      Semantics(
        container: true,
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
          decoration: BoxDecoration(
            gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: befriend ? const [Color(0xFFF3FBEA), Color(0xFFE1F1CC)] : const [Color(0xFFFFF9EA), Color(0xFFF7EACA)]),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: befriend ? const Color(0xFFA9D58A) : const Color(0xFFE5BF73), width: 2),
          ),
          child: Row(children: [
            Container(
              width: 76,
              height: 76,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: const Color(0xB3FFFFFF), borderRadius: BorderRadius.circular(14)),
              child: VoxelIcon('creature_${cdef.id}', size: 66),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Flexible(child: Text(cdef.name, style: const TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w900, fontSize: 16, color: EvochiColor.ink))),
                  const SizedBox(width: 4),
                  VoxelIcon(a.icon, size: 20, semantic: a.name),
                ]),
                const SizedBox(height: 2),
                Text(
                  befriend
                      ? 'New companion! ${cdef.name} joins your journey, visits your nest and helps in encounters.'
                      : '${cdef.name} is restored. ${v.boss ? 'The third trail on the Waystone’s map glows again.' : 'The ruins feel brighter already.'}',
                  style: const TextStyle(fontFamily: EvochiText.body, fontSize: 13.5, height: 18 / 13.5, color: EvochiColor.textSecondary),
                ),
                const SizedBox(height: 3),
                Text('${v.turn} turn${v.turn == 1 ? '' : 's'}${used.isEmpty ? '' : ' · $used'}', style: const TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w700, fontSize: 11.5, color: EvochiColor.textHelper)),
              ]),
            ),
          ]),
        ),
      ),
      const SizedBox(height: 10),
      EncCta(label: 'Continue', trailing: const Icon(Icons.arrow_forward_rounded, size: 24, color: Color(0xFF1F4A22)), onTap: () => _finish(v.quest)),
    ]);
  }
}

/// The cream panel under the shot (24px top corners, a shadow up).
class _Panel extends StatelessWidget {
  const _Panel({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return Container(
      constraints: BoxConstraints(maxHeight: mq.size.height * 0.74),
      padding: EdgeInsets.fromLTRB(14, 12, 14, 8 + mq.padding.bottom),
      decoration: const BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFFBF3E7), Color(0xFFF6EADA)], stops: [0, 0.6]),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [BoxShadow(color: Color(0x47140C06), blurRadius: 20, offset: Offset(0, -8))],
      ),
      child: SingleChildScrollView(child: child),
    );
  }
}

/// One action: its icon, name and effect, coloured by kind; a cost chip when it takes Energy.
class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.a, required this.v, required this.hollow, required this.busy, required this.onTap});
  final tr.ActionView a;
  final tr.EncounterView v;
  final bool hollow;
  final bool busy;
  final VoidCallback onTap;

  String get _sub {
    final l = v.meterLabel;
    final sign = v.goal == 'befriend' ? '+' : '−';
    return switch (a.kind) {
      'item' => v.items.isNotEmpty ? '${v.items.length} in your Bag' : 'Nothing useful yet',
      'restore' => '+30 Energy',
      'companion' => v.companionUsed ? 'Used this time' : '$sign${a.power} $l · once',
      _ => '$sign${a.power} $l',
    };
  }

  @override
  Widget build(BuildContext context) {
    final style = switch (a.kind) {
      'light' => hollow ? 'purify' : 'sun',
      'physical' => 'orange',
      'restore' => 'teal',
      'item' => 'cream',
      'companion' => 'green',
      _ => 'cream',
    };
    final icon = switch (a.kind) {
      'light' => hollow ? 'purify' : 'sun',
      'physical' => 'nudge',
      'restore' => 'calm',
      'item' => 'bag',
      'companion' => 'creature_petalune',
      _ => a.icon,
    };
    final (colors, border, shadow) = switch (style) {
      'sun' => (const [Color(0xFFFFF4CC), Color(0xFFFFE39A), Color(0xFFF8C75A)], const Color(0xFFE3AA3A), const Color(0xFFCF952C)),
      'teal' => (const [Color(0xFFE6FCF4), Color(0xFFB2EDD9), Color(0xFF82DBC1)], const Color(0xFF45AF8D), const Color(0xFF369073)),
      'orange' => (const [Color(0xFFFFE6CC), Color(0xFFFDC48E), Color(0xFFF6A262)], const Color(0xFFE1813F), const Color(0xFFC4672B)),
      'purify' => (const [Color(0xFFF3EAFE), Color(0xFFD9C4F8), Color(0xFFBE9FEF)], const Color(0xFF9871D5), const Color(0xFF7A56B8)),
      'green' => (const [Color(0xFFF3FBE8), Color(0xFFD2EDB4), Color(0xFFB3DB8C)], const Color(0xFF7DB758), const Color(0xFF5D953F)),
      _ => (const [Color(0xFFFFFEFA), Color(0xFFF7EDDF), Color(0xFFEDDCC6)], const Color(0xFFD6BFA2), const Color(0xFFC2A988)),
    };
    final cost = a.energy > 0 ? a.energy : 0;
    final enabled = a.can && !busy && !v.success;
    final sub = _sub;
    return Semantics(
      button: true,
      enabled: enabled,
      label: '${a.name}: $sub${cost > 0 ? ', costs $cost Energy' : ''}',
      child: ExcludeSemantics(
        child: GestureDetector(
          onTap: enabled
              ? () {
                  context.read<GameController>().audio.tick();
                  onTap();
                }
              : null,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 250),
            opacity: enabled ? 1 : (busy ? 0.8 : 0.55),
            child: ColorFiltered(
              colorFilter: enabled ? const ColorFilter.mode(Colors.transparent, BlendMode.dst) : ColorFilter.matrix(_saturate(busy ? 0.75 : 0.4)),
              child: Container(
                constraints: BoxConstraints(minHeight: a.kind == 'companion' ? 60 : 66),
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 9),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: border, width: 2.5),
                  gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: colors, stops: const [0, 0.5, 1]),
                  boxShadow: [BoxShadow(color: shadow, offset: const Offset(0, 4)), BoxShadow(color: shadow.withAlpha(56), blurRadius: 12, offset: const Offset(0, 7))],
                ),
                child: Row(children: [
                  SizedBox(width: 42, height: 42, child: VoxelIcon(icon, size: 42)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                      Text(a.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w900, fontSize: 15.5, height: 1.15, color: EvochiColor.ink)),
                      const SizedBox(height: 2),
                      Wrap(crossAxisAlignment: WrapCrossAlignment.center, runSpacing: 2, children: [
                        Text(sub, style: const TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w800, fontSize: 12, height: 1.2, color: Color(0xC73B2923))),
                        if (cost > 0)
                          Container(
                            margin: const EdgeInsets.only(left: 5),
                            padding: const EdgeInsets.only(left: 1, right: 6),
                            height: 17,
                            decoration: BoxDecoration(color: const Color(0x99FFFFFF), borderRadius: BorderRadius.circular(8)),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              const VoxelIcon('energy', size: 14),
                              Text('$cost', style: const TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w900, fontSize: 11.5, color: Color(0xFF6A4818))),
                            ]),
                          ),
                      ]),
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

/// "Retreat" / "Not yet": a text button with a running figure.
class _RetreatButton extends StatelessWidget {
  const _RetreatButton({required this.label, required this.enabled, required this.onTap});
  final String label;
  final bool enabled;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Center(
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
                    const Icon(Icons.directions_run_rounded, size: 20, color: Color(0xFF6B5143)),
                    const SizedBox(width: 6),
                    Text(label, style: const TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w900, fontSize: 15.5, color: Color(0xFF6B5143))),
                  ]),
                ),
              ),
            ),
          ),
        ),
      );
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
    final hollow = v.creature.kind == 'hollow';
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
                  decoration: BoxDecoration(color: const Color(0xFFFFFCF6), borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFEBD8C1), width: 2)),
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
                  Padding(padding: const EdgeInsets.only(bottom: 10), child: _ActionButton(a: a, v: v, hollow: hollow, busy: busy, onTap: () => onAction(a.id))),
                _RetreatButton(label: 'Retreat', enabled: !busy, onTap: onRetreat),
              ],
            ]),
          ),
        ]),
      ),
    );
  }
}
