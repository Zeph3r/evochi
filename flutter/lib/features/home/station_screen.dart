// Home Tales: the Kitchen and the Apothecary (one shared screen). The room with your Evochi in it,
// recipe cards with have/need chips for each ingredient, and the station itself: choosing a recipe
// turns the screen into the oven (or the cauldron). The camera pushes in, the ingredients drop in, a
// skippable timing gauge plays on a wooden plaque over the fire (a perfect stop makes a double batch
// and +50% skill XP; skipping makes a normal batch; Back cancels and uses nothing), the dish pops out,
// and a result card follows: give one to your Evochi, use it in the Garden, take it to the villager
// who asked for it, or make another. Mirrors `station` in web/src/screens/homeland.js.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../controllers/game_controller.dart';
import '../../core/services/haptics.dart';
import '../../core/models/catalog.dart';
import '../../game/engine.dart' as g;
import '../../game/home/home.dart' as h;
import '../../game/story/story.dart' as q;
import '../shared/kit.dart';
import '../shared/sprite.dart';
import '../shared/widgets.dart';
import '../village/story_widgets.dart';
import '../village/village_screen.dart';
import 'home_widgets.dart';

/// Where the station sits on its room plate (fractions of the 780 x 1000 image): the oven's mouth or
/// the cauldron's rim, where the ingredients drop, the glow sits and the dish pops out.
class _StationStage {
  const _StationStage(this.fx, this.fy, this.glow, this.label, this.going);
  final double fx;
  final double fy;
  final Color glow;
  final String label;
  final String going; // the prompt while the camera pushes in
}

const _stages = {
  'kitchen': _StationStage(0.256, 0.49, Color(0xFFFF963C), 'The oven', 'Into the oven it goes...'),
  'apothecary': _StationStage(0.333, 0.47, Color(0xFFAA78FF), 'The cauldron', 'Into the cauldron it goes...'),
};
const _wideZoom = 1.15; // the room, a little closer than the plate
const _closeZoom = 2.1; // the close-up on the station

/// Who in the story is waiting for this item right now (to suggest "Take it to ...").
q.StoryQuestView? _questWanting(q.StoryStatus st, String itemId) =>
    st.all.where((v) => v.accepted && !v.completed && v.objectives.any((o) => o.item == itemId && !o.done)).firstOrNull;

class StationScreen extends StatefulWidget {
  const StationScreen({super.key, required this.stationId});
  final String stationId;
  @override
  State<StationScreen> createState() => _StationScreenState();
}

class _StationScreenState extends State<StationScreen> {
  int _joyAt = 0; // the pet hops after something good
  Timer? _joyTimer;
  String? _cookRid; // the recipe at the station (null: the recipe list)
  int _cookSerial = 0; // a fresh cook (Cook another) restarts the stage

  String get _id => h.stationDefs.containsKey(widget.stationId) ? widget.stationId : 'kitchen';

  @override
  void dispose() {
    _joyTimer?.cancel();
    super.dispose();
  }

  void _joy() {
    setState(() => _joyAt = DateTime.now().millisecondsSinceEpoch);
    _joyTimer?.cancel();
    _joyTimer = Timer(const Duration(milliseconds: 1300), () {
      if (mounted) setState(() {});
    });
  }

  void _tapRecipe(GameController c, h.RecipeView r) {
    if (!r.open) {
      c.toast("Your ${h.stationDefs[r.station]!.name} isn't open yet", icon: 'lock', kind: 'warn');
      return;
    }
    if (!r.known) {
      if (r.needsStory) {
        c.toast('Restore the Hollow Sprout (${q.storyQuests[h.recipeQuest(r.def)]!.title}) to learn this recipe', icon: 'lock', kind: 'warn');
      } else {
        c.toast('Reach ${h.skillDefs[r.skill]!.name} Lv ${r.level} to learn this recipe', icon: 'lock', kind: 'warn');
      }
      return;
    }
    if (!r.ready) {
      final miss = [for (final e in r.have.entries) if (!e.value.ok) (e.key, e.value.need, e.value.have)];
      c.toast('You need ${missingText(miss)}', icon: miss.isEmpty ? 'skill_farming' : 'item:${miss.first.$1}', kind: 'warn');
      c.audio.play('error_bonk', volume: 0.4);
      return;
    }
    _startCook(c, r.id);
  }

  /// To the station: the screen becomes the oven (or the cauldron) until the dish is out.
  void _startCook(GameController c, String rid) {
    c.audio.play('ui_tap', volume: 0.5);
    setState(() {
      _cookRid = rid;
      _cookSerial++;
    });
  }

  /// Back from the station before the dish is done: nothing is used.
  void _cancelCook(GameController c) {
    c.audio.play('ui_tap', volume: 0.3);
    setState(() => _cookRid = null);
  }

  /// The dish is out: the reward card opens over the station (the dish and the stamp stay behind
  /// it), and closing it goes back to the recipes, unless "Cook another" already restarted the stage.
  Future<void> _cookDone(GameController c, String rid, String quality) async {
    if (!mounted || _cookRid != rid) return;
    final serial = _cookSerial;
    await _craft(c, rid, quality);
    if (mounted && _cookRid == rid && _cookSerial == serial) setState(() => _cookRid = null);
  }

  Future<void> _craft(GameController c, String rid, String quality) async {
    final def = h.recipeDefs[rid]!;
    final r = c.run((s, n) => h.craft(s, rid, quality == 'perfect' ? 'perfect' : 'good', n));
    if (!r.ok) return;
    final ev = r.events.firstWhere((e) => e.type == 'crafted');
    final xp = r.events.where((e) => e.type == 'skill_xp').firstOrNull;
    _joy();
    final perfect = ev.data['quality'] == 'perfect';
    c.analytics.track('recipe_crafted', {'recipe': rid, 'quality': ev.data['quality']});
    c.audio.play(perfect ? 'level_up' : 'purchase', volume: 0.7);
    final id = def.makes;
    final it = item(id);
    final st = h.stationDefs[def.station]!;
    final skill = h.skillDefs[st.skill]!;
    final qty = ev.data['qty'] as int;
    await showEvochiDialog<void>(context, builder: (d) {
      final c = d.watch<GameController>();
      final want = _questWanting(c.storyView, id);
      final again = h.recipeView(c.state, rid).ready;
      final pet = c.state.pet;
      final giveable = it.growth <= 0 && !(c.view.pet?.dead ?? true) && g.ownedQty(c.state, id) > 0;
      final wantNpc = want == null ? null : q.npcs[q.storyQuests[want.id]!.turnIns.first.npc];
      return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        GoldBanner(perfect ? 'Perfect!' : (def.station == 'kitchen' ? 'Fresh from the oven!' : 'Brewed!')),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE8B956), width: 3),
            gradient: const RadialGradient(center: Alignment(0, -0.3), radius: 0.9, colors: [Color(0xFFFFF6DA), Color(0xFFFFF9F0)]),
          ),
          child: Column(children: [
            ItemImage(id, size: 112),
            Text('$qty × ${it.name}', style: EvochiText.cardTitle),
            const SizedBox(height: 4),
            Text(effectText(it), textAlign: TextAlign.center, style: EvochiText.bodyText.copyWith(color: EvochiColor.textSecondary)),
          ]),
        ),
        const SizedBox(height: 10),
        Center(child: Tag('+${xp?.data['amount'] ?? 0} ${skill.name} XP', tone: TagTone.ok, icon: skill.icon)),
        const SizedBox(height: 12),
        if (want != null) ...[
          EvochiButton(
            label: 'Take it to ${wantNpc?.name ?? 'the village'}',
            onPressed: () {
              Navigator.pop(d);
              final n = q.nextStep(c.state, want.id);
              final place = q.places[n.place];
              if (place != null) {
                openPlace(context, place.id, npc: n.npc);
              } else {
                showStoryQuest(context, want.id);
              }
            },
          ),
          const SizedBox(height: 8),
        ],
        if (it.growth > 0) ...[
          EvochiButton(
            label: 'Use it in the Garden',
            tone: want != null ? ButtonTone.cream : ButtonTone.gold,
            onPressed: () {
              Navigator.pop(d);
              openGarden(context);
            },
          ),
          const SizedBox(height: 8),
        ] else if (giveable && pet != null) ...[
          EvochiButton(
            label: 'Give one to ${pet.name}',
            tone: want != null ? ButtonTone.cream : ButtonTone.gold,
            icon: const VoxelIcon('heart', size: 22),
            onPressed: () {
              final r = c.run((s, n) => g.useConsumable(s, id, n));
              if (!r.ok) return;
              final used = r.events.where((e) => e.type == 'used').firstOrNull;
              final treat = r.events.where((e) => e.type == 'treat').firstOrNull;
              final vit = (used?.data['vitality'] as int?) ?? 0;
              final bond = (treat?.data['bond'] as int?) ?? 0;
              c.toast('${pet.name} loved it!${vit > 0 ? ' +$vit vitality' : ''}${bond > 0 ? ' · Bond +$bond' : ''}', icon: 'heart');
              c.audio.play('pet_chirp');
              Navigator.pop(d);
              if (mounted) _joy();
            },
          ),
          const SizedBox(height: 8),
        ],
        if (again) ...[
          EvochiButton(
            label: '${st.verb} another',
            tone: ButtonTone.cream,
            onPressed: () {
              Navigator.pop(d);
              // straight back to the station
              if (mounted) _startCook(c, rid);
            },
          ),
          const SizedBox(height: 8),
        ],
        EvochiButton(label: 'Done', tone: ButtonTone.cream, onPressed: () => Navigator.pop(d)),
      ]);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<GameController>();
    final id = _id;
    final s = h.stationDefs[id]!;
    final mq = MediaQuery.of(context);
    final reduce = mq.disableAnimations;
    // the Kitchen is a warm recipe book; the Apothecary is plum wood and lavender paper
    final apothecary = id == 'apothecary';
    final rid = _cookRid;
    if (rid != null && h.recipeDefs[rid]?.station != id) _cookRid = null;
    final cooking = _cookRid != null;
    final header = PlaceHeader(title: 'Your ${s.name}', short: s.name, backLabel: 'Back', onBack: () => Navigator.of(context).maybePop());
    Widget body;
    if (cooking) {
      final r = _cookRid!;
      // at the station: the stage and its controls (the system back cancels the cook)
      // at the station: the whole screen is the oven (or the cauldron), no page around it
      body = _CookView(
        key: ValueKey('cook-$_cookSerial'),
        recipe: h.recipeDefs[r]!,
        station: id,
        onDone: (quality) => _cookDone(c, r, quality),
        onCancel: () => _cancelCook(c),
      );
    } else {
      final open = h.stationOpen(c.state, id);
      final recipes = [for (final r in h.recipeOrder) if (h.recipeDefs[r]!.station == id) h.recipeView(c.state, r)];
      final v = q.questView(c.state, s.quest, c.now);
      final joy = DateTime.now().millisecondsSinceEpoch - _joyAt < 1200;
      final pet = c.state.pet;
      final petDead = c.view.pet?.dead ?? true;
      final pageTop = apothecary ? const Color(0xFFF3ECFA) : const Color(0xFFFBEBD2);
      body = Column(children: [
        header,
        Expanded(
          child: ListView(padding: EdgeInsets.only(bottom: 20 + mq.padding.bottom), children: [
            LayoutBuilder(builder: (ctx, b) {
              final hPlate = (b.maxWidth / 1.22).clamp(0.0, mq.size.height * 0.46).toDouble();
              return SizedBox(
                height: hPlate,
                child: Stack(fit: StackFit.expand, children: [
                  Image.asset(
                    homeArt.room(id),
                    fit: BoxFit.cover,
                    alignment: const Alignment(0, 0.28),
                    semanticLabel: id == 'kitchen'
                        ? 'The cottage kitchen: a brick oven glowing, shelves of jars and a round rug.'
                        : 'The apothecary: a bubbling cauldron, bottle shelves and a round window.',
                  ),
                  if (pet != null && !petDead)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: hPlate * 0.13,
                      height: hPlate * 0.38,
                      child: Center(
                        child: _Hop(
                          key: ValueKey(_joyAt),
                          active: joy && !reduce,
                          child: PetSprite(stage: pet.stage, palette: pet.paletteId, expr: joy ? 'excited' : 'happy', overlays: pet.equipped.values.toList(), height: hPlate * 0.38),
                        ),
                      ),
                    ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: 56,
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [pageTop.withAlpha(0), pageTop])),
                      ),
                    ),
                  ),
                ]),
              );
            }),
            Transform.translate(
              offset: const Offset(0, -18),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  if (open) SkillStrip(s.skill) else HomeQuestStrip(v: v, lead: 'The ${s.name} opens with'),
                  const SectionHead('Recipes'),
                  for (final r in recipes) _RecipeCard(r: r, verb: s.verb, onTap: () => _tapRecipe(c, r)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    child: Text(
                      "${s.verb}ing happens at the ${apothecary ? 'cauldron' : 'oven'}, with a quick timing game. It's optional: skip it any time. A perfect result makes a double batch, and ingredients are never wasted.",
                      style: EvochiText.caption,
                    ),
                  ),
                ]),
              ),
            ),
          ]),
        ),
      ]);
    }
    return PopScope(
      canPop: !cooking,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _cookRid != null) _cancelCook(c);
      },
      child: Scaffold(
        backgroundColor: EvochiColor.panel,
        body: KitPage(
          material: apothecary ? KitMaterial.apothecary : KitMaterial.kitchen,
          child: SafeArea(bottom: false, child: body),
        ),
      ),
    );
  }
}

/// Two little hops when [active] (after cooking or a treat).
class _Hop extends StatefulWidget {
  const _Hop({super.key, required this.active, required this.child});
  final bool active;
  final Widget child;
  @override
  State<_Hop> createState() => _HopState();
}

class _HopState extends State<_Hop> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));

  @override
  void initState() {
    super.initState();
    if (widget.active) _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (_, child) {
          final t = (_c.value * 2) % 1; // two hops
          final y = _c.isAnimating ? -18 * 4 * t * (1 - t) : 0.0;
          return Transform.translate(offset: Offset(0, y), child: child);
        },
        child: widget.child,
      );
}

class _RecipeCard extends StatelessWidget {
  const _RecipeCard({required this.r, required this.verb, required this.onTap});
  final h.RecipeView r;
  final String verb;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final c = context.watch<GameController>();
    final it = item(r.makes);
    final owned = g.ownedQty(c.state, r.makes);
    final apothecary = KitScope.of(context) == KitMaterial.apothecary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Opacity(
        opacity: r.known ? 1 : 0.7,
        child: GameCard(
          highlight: r.ready,
          // a recipe card: a terracotta margin rule in the kitchen's book
          rule: apothecary ? null : const Color(0xFFD8705A),
          padding: const EdgeInsets.all(10),
          child: Row(children: [
            Container(
              width: 60,
              height: 60,
              alignment: Alignment.center,
              // a round plate in the kitchen, a jar label in the apothecary
              decoration: apothecary
                  ? KitDecoration(
                      base: BoxDecoration(
                        gradient: const RadialGradient(center: Alignment(0, -0.2), radius: 0.8, colors: [Color(0xFFFFFFFF), Color(0xFFE6DAF4)]),
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(12), bottom: Radius.circular(18)),
                        border: Border.all(color: const Color(0xFF9C7DB8), width: 2),
                      ),
                      inset: 2,
                      shadow: const BoxShadow(color: Color(0x33502878), blurRadius: 5, offset: Offset(0, 2)),
                    )
                  : const KitDecoration(
                      base: BoxDecoration(
                        gradient: RadialGradient(center: Alignment(0, -0.2), radius: 0.8, colors: [Color(0xFFFFFDF4), Color(0xFFF4DDB4)]),
                        borderRadius: BorderRadius.all(Radius.circular(30)),
                        border: Border.fromBorderSide(BorderSide(color: Color(0xFFC98A4E), width: 2)),
                      ),
                      inset: 2,
                      shadow: BoxShadow(color: Color(0x33784614), blurRadius: 5, offset: Offset(0, 2)),
                    ),
              child: ItemImage(r.makes, size: 52),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Wrap(spacing: 6, runSpacing: 2, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  Text(r.name, style: EvochiText.cardTitle),
                  if (owned > 0) Tag('x$owned'),
                ]),
                Text(effectText(it), style: EvochiText.tiny.copyWith(fontWeight: FontWeight.w400)),
                const SizedBox(height: 4),
                Wrap(spacing: 6, runSpacing: 4, children: [
                  for (final e in r.have.entries)
                    Semantics(
                      label: '${item(e.key).name}: ${e.value.have} of ${e.value.need}',
                      child: ExcludeSemantics(
                        child: Container(
                          height: 28,
                          padding: const EdgeInsets.only(left: 2, right: 7),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(9),
                            color: e.value.ok ? EvochiColor.meadow100 : const Color(0xFFFFF0D8),
                            border: Border.all(color: e.value.ok ? const Color(0xFFCDE5B0) : const Color(0xFFF2C98A), width: 1.5),
                          ),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            ItemImage(e.key, size: 24),
                            const SizedBox(width: 2),
                            Text('${e.value.have > 99 ? 99 : e.value.have}/${e.value.need}',
                                style: EvochiText.tag.copyWith(fontSize: 12, color: e.value.ok ? EvochiColor.healthy : EvochiColor.gold900)),
                          ]),
                        ),
                      ),
                    ),
                ]),
              ]),
            ),
            const SizedBox(width: 8),
            if (!r.known)
              // a story recipe (the Lantern Tonic) waits on its quest once the level is reached
              Tag(r.needsStory && h.skillView(c.state, r.skill).level >= r.level ? 'Story' : 'Lv ${r.level}', tone: TagTone.neutral, icon: 'lock')
            else
              // the Apothecary's Brew glows plum
              EvochiButton(
                label: verb,
                small: true,
                expand: false,
                tone: apothecary ? ButtonTone.plum : (r.ready ? ButtonTone.green : ButtonTone.cream),
                semanticLabel: '$verb ${r.name}',
                onPressed: onTap,
              ),
          ]),
        ),
      ),
    );
  }
}

// --------------------------------------------------------------- the station flow ----
/// At the oven or the cauldron (web: cookStage / cookControls / finishCook in homeland.js). A full-screen
/// game scene, not a page: the room plate pushes in from the room to the station's mouth while the
/// ingredients fly in, a glow pulses and embers (or bubbles) rise. Then the station's own gauge comes
/// up in the scene: the Kitchen's heat dial (a needle swings across it) or the Apothecary's stirring
/// ring round the cauldron's rim (a glowing ladle runs round it). One big round button stops it: in
/// the gold is a perfect batch (double, +50% skill XP), anywhere else a good one; Skip makes a normal
/// batch; the back plaque leaves without using anything. A stamp, the dish popping out of the mouth
/// with sparkles, your Evochi cheering in the corner, a buzz in the hand, then [onDone] (1.35 s; 0.45 s
/// for a skip). Reduced motion: no push-in, nothing flies, no particles, a slower gauge.
class _CookView extends StatefulWidget {
  const _CookView({super.key, required this.recipe, required this.station, required this.onDone, required this.onCancel});
  final h.RecipeDef recipe;
  final String station;
  final ValueChanged<String> onDone; // perfect | good | skip
  final VoidCallback onCancel;
  @override
  State<_CookView> createState() => _CookViewState();
}

class _CookViewState extends State<_CookView> with SingleTickerProviderStateMixin {
  static const _push = Cubic(0.45, 0, 0.2, 1); // the camera's push-in
  static const _pop = Cubic(0.2, 1.4, 0.4, 1); // overshoots: pops
  static const _drop = Cubic(0.5, 0, 0.9, 0.5); // falls faster as it goes in
  static const zone = (0.62, 0.8); // the gold, as a fraction of the gauge
  late final Ticker _ticker;
  final _clock = ValueNotifier<double>(0); // seconds since the cook began
  String _phase = 'in'; // in (pushing in) | play (the gauge is up) | done
  double _playAt = 0;
  double _doneAt = 0;
  double _p = 0; // the gauge's marker, 0..1
  bool _inGold = false;
  bool _down = false;
  String? _quality;
  bool _reported = false;
  bool _rm = false;

  bool get _ring => widget.station == 'apothecary';
  GameController get _c => context.read<GameController>();

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick)..start();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _rm = MediaQuery.of(context).disableAnimations;
  }

  @override
  void dispose() {
    _ticker.dispose();
    _clock.dispose();
    super.dispose();
  }

  // the dial's needle swings across and back; the ladle runs round the ring (once per loop it passes
  // the gold, a little longer each time than the needle does twice, so both feel about as hard)
  double get _period => _ring ? (_rm ? 2.2 : 1.35) : (_rm ? 2.6 : 1.7);

  void _tick(Duration elapsed) {
    final t = elapsed.inMicroseconds / 1e6;
    if (_phase == 'in' && t >= (_rm ? 0.3 : 1.75)) {
      setState(() {
        _phase = 'play';
        _playAt = t;
      });
      _c.audio.buzz(Haptic.tap, strength: 0.6); // the gauge is up
    }
    if (_phase == 'play') {
      final u = (t - _playAt) / _period;
      if (_ring) {
        _p = u % 1;
      } else {
        final x = u % 1 * 2; // a triangle wave, 0 -> 1 -> 0
        _p = x < 1 ? x : 2 - x;
      }
      final gold = _p >= zone.$1 && _p <= zone.$2;
      if (gold && !_inGold) _c.audio.tick(); // a notch as it crosses into the gold
      _inGold = gold;
    }
    if (_phase == 'done' && !_reported && t - _doneAt >= (_quality == 'skip' ? 0.45 : 1.35)) {
      _reported = true;
      _ticker.stop();
      widget.onDone(_quality!);
      return;
    }
    _clock.value = t;
  }

  void _stop() {
    if (_phase != 'play') return;
    final ok = _p >= zone.$1 - 0.015 && _p <= zone.$2 + 0.015;
    _c.audio.play(ok ? 'reward_chime' : 'ui_tap', volume: 0.6);
    _c.audio.buzz(ok ? Haptic.perfect : Haptic.good);
    _finish(ok ? 'perfect' : 'good');
  }

  void _finish(String quality) {
    if (_phase == 'done') return;
    setState(() {
      if (_phase == 'in') _playAt = _clock.value; // a skip before the gauge was up: it shows, frozen
      _phase = 'done';
      _quality = quality;
      _doneAt = _clock.value;
      _down = false;
    });
  }

  /// The plate's rect at [zoom] in [box], with the station's mouth at [focus] (clamped so the plate
  /// always covers the box; a tall phone needs a closer wide shot to fill its height).
  Rect _frame(_StationStage st, double zoom, double ar, Size box, Offset focus) {
    final z = math.max(zoom, box.height / (box.width * ar) * 1.002);
    final w = box.width * z;
    final hgt = w * ar;
    final l = (focus.dx - st.fx * w).clamp(math.min(0.0, box.width - w), 0.0).toDouble();
    final t = (focus.dy - st.fy * hgt).clamp(math.min(0.0, box.height - hgt), 0.0).toDouble();
    return Rect.fromLTWH(l, t, w, hgt);
  }

  @override
  Widget build(BuildContext context) {
    final st = _stages[widget.station]!;
    final it = item(widget.recipe.makes);
    return LayoutBuilder(builder: (ctx, b) => _scene(Size(b.maxWidth, b.maxHeight), st, it));
  }

  Widget _scene(Size box, _StationStage st, CatalogItem it) {
    final mq = MediaQuery.of(context);
    final top = mq.padding.top;
    final bottom = mq.padding.bottom;
    final rs = homeArt.roomSize(widget.station);
    final ar = rs.height / rs.width;
    // the station sits a little above the middle: the gauge and the button live below it
    final focus = Offset(box.width / 2, box.height * 0.38);
    final wide = _frame(st, _wideZoom, ar, box, focus);
    final close = _frame(st, _closeZoom, ar, box, focus);
    final mouth = Offset(close.left + st.fx * close.width, close.top + st.fy * close.height);
    final drops = [for (final e in widget.recipe.needs.entries) for (var i = 0; i < math.min(e.value, 3); i++) e.key].take(6).toList();
    final plate = homeArt.room(widget.station);
    final w = box.width;
    final pet = Provider.of<GameController>(context, listen: false).state.pet;
    final perfect = _quality == 'perfect';
    final verb = _ring ? 'Stir!' : 'Take it out!';
    final hint = _ring ? 'Stir when the ladle reaches the gold!' : 'Stop the needle in the gold!';
    // the gauge: the Kitchen's dial sits on the hearth below the oven's mouth; the ring rides the rim
    final dialW = math.min(w * 0.78, 340.0);
    final dialH = dialW * 0.58;
    final dialTop = math.min(mouth.dy + w * 0.15, box.height - bottom - 176 - dialH);
    final ringC = mouth.translate(0, w * 0.035);
    final ringR = Size(w * 0.34, w * 0.115);
    return ValueListenableBuilder<double>(
      valueListenable: _clock,
      builder: (ctx, t, _) {
        final push = _rm ? 1.0 : _push.transform((t / 0.95).clamp(0.0, 1.0).toDouble());
        final frame = Rect.lerp(wide, close, push)!;
        final up = _phase == 'in' ? 0.0 : (_rm ? 1.0 : ((t - _playAt) / 0.35).clamp(0.0, 1.0).toDouble()); // the gauge arriving
        final popT = _phase == 'done' ? ((t - _doneAt) / (_quality == 'skip' ? 0.4 : 0.9)).clamp(0.0, 1.0).toDouble() : -1.0;
        final pop = popT < 0 ? 0.0 : _pop.transform(popT);
        final dish = w * 0.30;
        final dishC = mouth.translate(0, -0.6 * dish * pop);
        final stampT = _phase == 'done' && _quality != 'skip' ? ((t - _doneAt) / 0.35).clamp(0.0, 1.0).toDouble() : 0.0;
        final hintA = _phase == 'in' ? 1.0 : (_phase == 'play' ? (1 - ((t - _playAt - 2.6) / 0.5)).clamp(0.0, 1.0).toDouble() : 0.0);
        final gold = _phase == 'play' && _inGold;
        // your Evochi: watching, then cheering (a hop on a perfect one)
        final cheer = _phase == 'done' && _quality != 'skip';
        final hopT = cheer && !_rm ? ((t - _doneAt) / 0.6).clamp(0.0, 1.0).toDouble() : 0.0;
        final hop = math.sin(math.pi * hopT) * (perfect ? 22 : 10);
        final petExpr = cheer ? (perfect ? 'excited' : 'happy') : (_phase == 'play' ? 'determined' : 'happy');
        return Stack(clipBehavior: Clip.hardEdge, children: [
          const Positioned.fill(child: ColoredBox(color: Color(0xFF2A1A10))),
          // the room plate, pushing in from the room to the station
          Positioned.fromRect(
            rect: frame,
            child: Image.asset(plate, fit: BoxFit.fill, gaplessPlayback: true, filterQuality: FilterQuality.medium, excludeFromSemantics: true),
          ),
          // the vignette, the glow and the embers (or bubbles), painted straight over the plate
          Positioned.fill(
            child: CustomPaint(
              painter: _StageFx(t: t, mouth: mouth, glow: st.glow, bubbles: _ring, playAt: _phase == 'in' ? null : _playAt, rm: _rm),
            ),
          ),
          // a dusk at the top and the bottom so the plaques and the button read over the room
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: const [Color(0x99140A05), Color(0x00140A05), Color(0x00140A05), Color(0xB3140A05)],
                    stops: [0, (top + 120) / box.height, 0.62, 1],
                  ),
                ),
              ),
            ),
          ),
          // the ingredients fly up into the mouth, one after another
          if (!_rm) ...[for (var i = 0; i < drops.length; i++) _dropAt(drops[i], i, t, mouth, w)],
          // the stirring ring round the cauldron (behind the dish)
          if (_ring && up > 0)
            Positioned.fill(
              child: IgnorePointer(
                child: Opacity(
                  opacity: up,
                  child: CustomPaint(painter: _StirRing(center: ringC, radii: ringR * (0.85 + 0.15 * up), value: _p, gold: zone, hot: gold, perfect: perfect, t: t, rm: _rm)),
                ),
              ),
            ),
          // the dish pops out of the mouth
          if (popT >= 0)
            Positioned(
              left: dishC.dx - dish / 2,
              top: dishC.dy - dish / 2,
              width: dish,
              height: dish,
              child: Transform.scale(scale: math.max(0.0, pop), child: Image.asset(art.item(widget.recipe.makes), fit: BoxFit.contain, excludeFromSemantics: true)),
            ),
          if (popT >= 0 && !_rm) Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: _Sparks(t: t - _doneAt - 0.15, center: dishC)))),
          // the Kitchen's heat dial, on the hearth
          if (!_ring && up > 0)
            Positioned(
              left: (w - dialW) / 2,
              top: dialTop + 18 * (1 - up),
              width: dialW,
              height: dialH,
              child: IgnorePointer(
                child: Opacity(
                  opacity: up,
                  child: CustomPaint(painter: _HeatDial(value: _p, gold: zone, hot: gold, perfect: perfect, t: t, rm: _rm)),
                ),
              ),
            ),
          // the top: back, the recipe, what goes in
          Positioned(
            left: 10,
            right: 10,
            top: top + 8,
            child: Column(children: [
              Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                _WoodSquare(icon: Icons.arrow_back_rounded, label: 'Back, without cooking', onTap: _phase == 'done' ? null : widget.onCancel),
                Expanded(child: Center(child: _RecipePlaque(id: widget.recipe.makes, name: it.name))),
                const SizedBox(width: 46),
              ]),
              const SizedBox(height: 8),
              _Ingredients(needs: widget.recipe.needs, used: _phase != 'in'),
            ]),
          ),
          // the hint, then out of the way
          if (hintA > 0)
            Positioned(
              left: 24,
              right: 24,
              top: top + 104,
              child: IgnorePointer(
                child: Opacity(
                  opacity: hintA,
                  child: Center(child: _Ribbon(text: _phase == 'in' ? st.going : hint)),
                ),
              ),
            ),
          // "Perfect!" / "Nicely done!"
          if (stampT > 0)
            Positioned(
              left: 0,
              right: 0,
              top: top + box.height * 0.13,
              child: IgnorePointer(
                child: Opacity(
                  opacity: (stampT / 0.5).clamp(0.0, 1.0).toDouble(),
                  child: Transform.scale(
                    scale: _rm ? 1 : 1.6 - 0.6 * _pop.transform(stampT),
                    child: _Stamp(perfect: perfect),
                  ),
                ),
              ),
            ),
          if (_quality != null && _quality != 'skip')
            Semantics(liveRegion: true, label: perfect ? 'Perfect! Double batch' : 'Nicely done!', child: const SizedBox.shrink()),
          // your Evochi, watching from the corner
          if (pet != null)
            Positioned(
              left: 4,
              bottom: bottom + 8 + hop,
              child: IgnorePointer(
                child: ExcludeSemantics(
                  child: PetSprite(stage: pet.stage, palette: pet.paletteId, expr: petExpr, overlays: pet.equipped.values.toList(), height: math.min(w * 0.27, 130)),
                ),
              ),
            ),
          // the big round button
          Positioned(
            left: 0,
            right: 0,
            bottom: bottom + 18,
            child: Center(
              child: _BigButton(
                label: verb,
                icon: _ring ? 'swirl' : 'skill_cooking',
                plum: _ring,
                enabled: _phase == 'play',
                hot: gold,
                down: _down,
                t: t,
                rm: _rm,
                onDown: (d) => setState(() => _down = d && _phase == 'play'),
                onTap: _stop,
              ),
            ),
          ),
          // Skip: a normal batch, no gauge
          Positioned(
            right: 10,
            bottom: bottom + 34,
            child: _SkipPill(onTap: _phase == 'done' ? null : () => _finish('skip')),
          ),
        ]);
      },
    );
  }

  /// Ingredient [i] (of the recipe's, up to 6) flying up from below into the mouth: staggered, 0.75 s.
  Widget _dropAt(String id, int i, double t, Offset mouth, double w) {
    final u = (t - (0.55 + i * 0.16)) / 0.75;
    if (u < 0 || u > 1) return const SizedBox.shrink();
    final sx = (i.isOdd ? 1 : -1) * (40.0 + 22 * i);
    double dx, dy, rot, sc, op = 1;
    if (u < 0.55) {
      final v = _drop.transform(u / 0.55);
      dx = sx + (sx * 0.35 - sx) * v;
      dy = 260 + (-40 - 260) * v;
      rot = -30 + 40 * v;
      sc = 1.1 - 0.2 * v;
    } else {
      final v = _drop.transform((u - 0.55) / 0.45);
      dx = sx * 0.35 * (1 - v);
      dy = -40 * (1 - v);
      rot = 10 + 20 * v;
      sc = 0.9 - 0.55 * v;
      op = 1 - v;
    }
    final size = w * 0.15;
    return Positioned(
      left: mouth.dx - size / 2 + dx,
      top: mouth.dy - size / 2 + dy,
      width: size,
      height: size,
      child: Transform.rotate(
        angle: rot * math.pi / 180,
        child: Transform.scale(
          scale: sc,
          // the image's own opacity (no layer)
          child: Image.asset(art.item(id), fit: BoxFit.contain, opacity: AlwaysStoppedAnimation(op.clamp(0.0, 1.0).toDouble()), excludeFromSemantics: true),
        ),
      ),
    );
  }
}

/// The glow at the station's mouth (screen-blended over the plate), the vignette that keeps the eye on
/// it, and seven embers (the oven) or bubbles (the cauldron) rising from it.
class _StageFx extends CustomPainter {
  _StageFx({required this.t, required this.mouth, required this.glow, required this.bubbles, required this.playAt, required this.rm});
  final double t;
  final Offset mouth;
  final Color glow;
  final bool bubbles;
  final double? playAt; // the gauge came up (the glow brightens)
  final bool rm;

  static double _c(double v) => v.clamp(0.0, 1.0).toDouble();

  @override
  void paint(Canvas canvas, Size size) {
    final box = Offset.zero & size;
    // vignette: darker toward the edges, clear around the mouth
    final vig = rm ? 1.0 : _c(t / 0.9);
    if (vig > 0) {
      final far = [box.topLeft, box.topRight, box.bottomLeft, box.bottomRight].map((p) => (p - mouth).distance).reduce(math.max);
      canvas.drawRect(
        box,
        Paint()
          ..shader = RadialGradient(
            center: Alignment(mouth.dx / size.width * 2 - 1, mouth.dy / size.height * 2 - 1),
            radius: far / size.shortestSide,
            colors: [const Color(0x00140A05), const Color(0x00140A05), Color.fromRGBO(20, 10, 5, 0.45 * vig)],
            stops: const [0, 0.3, 0.95],
          ).createShader(box),
      );
    }
    // the glow: fades in as the camera arrives, brightens once the gauge is up, and breathes
    var op = 0.55 * (rm ? 1.0 : _c((t - 0.6) / 0.8));
    final pa = playAt;
    if (pa != null) op += 0.3 * (rm ? 1.0 : _c((t - pa - 0.6) / 0.8));
    if (op > 0) {
      final breathe = rm ? 1.0 : 0.92 + 0.14 * (0.5 - 0.5 * math.cos(math.pi * ((t / 1.1) % 2)));
      final r = size.width * 0.35 * breathe;
      final rect = Rect.fromCircle(center: mouth, radius: r);
      canvas.drawCircle(
        mouth,
        r,
        Paint()
          ..blendMode = BlendMode.screen
          ..shader = RadialGradient(
            colors: [glow.withAlpha((191 * op).round()), glow.withAlpha((64 * op).round()), glow.withAlpha(0)],
            stops: const [0, 0.55, 1],
          ).createShader(rect),
      );
    }
    if (rm) return;
    // embers or bubbles: seven, each rising for 1.6 s, staggered
    for (var i = 0; i < 7; i++) {
      final start = 0.9 + i * 0.23;
      if (t < start) continue;
      final u = ((t - start) / 1.6) % 1;
      final m = Curves.easeOut.transform(u);
      final a = u < 0.2 ? Curves.easeOut.transform(u / 0.2) : 1 - Curves.easeOut.transform((u - 0.2) / 0.8);
      if (a <= 0) continue;
      final c = Offset(mouth.dx + (i - 3) * 0.032 * size.width + (i - 3) * 6 * m, mouth.dy - 120 * m);
      final s = 0.6 + 0.5 * m;
      if (bubbles) {
        final r = 6 * s;
        final rect = Rect.fromCircle(center: c, radius: r);
        canvas.drawCircle(
          c,
          r,
          Paint()
            ..shader = RadialGradient(
              center: const Alignment(-0.3, -0.3),
              colors: [Color.fromRGBO(255, 255, 255, a), Color.fromRGBO(205, 180, 255, a), Color.fromRGBO(150, 110, 230, 0.4 * a)],
              stops: const [0, 0.45, 1],
            ).createShader(rect),
        );
      } else {
        final r = 3.5 * s;
        canvas.drawCircle(c, r + 3, Paint()
          ..color = Color.fromRGBO(255, 154, 60, 0.8 * a)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
        canvas.drawCircle(c, r, Paint()..color = Color.fromRGBO(255, 210, 122, a));
      }
    }
  }

  @override
  bool shouldRepaint(_StageFx old) => old.t != t || old.mouth != mouth || old.playAt != playAt || old.rm != rm;
}

/// A ring of ten gold sparkles bursting out of [center] over 0.9 s ([t] seconds in).
class _Sparks extends CustomPainter {
  _Sparks({required this.t, required this.center, this.color = const Color(0xFFFFE5A2), this.size = 14, this.base = 70, this.step = 22});
  final double t;
  final Offset center;
  final Color color;
  final double size;
  final double base; // how far the nearest ones fly
  final double step;

  @override
  void paint(Canvas canvas, Size box) {
    final u = t / 0.9;
    if (u <= 0 || u >= 1) return;
    final m = Curves.easeOut.transform(u);
    final paint = Paint()..color = color.withAlpha((255 * (1 - m)).round());
    for (var i = 0; i < 10; i++) {
      final a = i * 36 * math.pi / 180;
      final d = (base + (i % 3) * step) * m;
      final c = center + Offset(math.sin(a) * d, -math.cos(a) * d);
      canvas.drawPath(kitStarPath(c, size * (0.6 + 0.6 * m) / 2), paint);
    }
  }

  @override
  bool shouldRepaint(_Sparks old) => old.t != t || old.center != center;
}

/// The Kitchen's heat dial: a brass half-moon on a wooden plinth, a heat band from cool cream to red
/// with the gold "perfect" wedge, ticks, and a dark needle swinging across it ([value] 0..1, left to
/// right). [hot]: the needle is in the gold (the wedge lights); [perfect]: it was stopped there.
class _HeatDial extends CustomPainter {
  _HeatDial({required this.value, required this.gold, required this.hot, required this.perfect, required this.t, required this.rm});
  final double value;
  final (double, double) gold;
  final bool hot;
  final bool perfect;
  final double t;
  final bool rm;

  static const _ink = Color(0xFF4A2A14);

  Offset _at(Offset c, double r, double p) {
    final a = math.pi + p * math.pi;
    return c + Offset(math.cos(a) * r, math.sin(a) * r);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height * 0.9);
    final r = size.width * 0.47;
    // the plinth it stands on
    final plinth = RRect.fromRectAndRadius(Rect.fromLTRB(c.dx - r - 8, c.dy - 6, c.dx + r + 8, size.height), const Radius.circular(8));
    canvas.drawRRect(plinth.shift(const Offset(0, 4)), Paint()..color = const Color(0x66140A05));
    canvas.drawRRect(plinth, Paint()..color = const Color(0xFF6B3F1E));
    canvas.drawRRect(plinth, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..color = _ink);
    canvas.drawLine(Offset(plinth.left + 6, plinth.top + 3), Offset(plinth.right - 6, plinth.top + 3), Paint()
      ..strokeWidth = 1.5
      ..color = const Color(0x59FFD296));
    // the brass bezel
    final outer = Rect.fromCircle(center: c, radius: r);
    final half = Path()
      ..moveTo(c.dx - r, c.dy)
      ..arcTo(outer, math.pi, math.pi, false)
      ..close();
    canvas.drawPath(half.shift(const Offset(0, 4)), Paint()..color = const Color(0x59140A05));
    canvas.drawPath(
      half,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFFE9A6), Color(0xFFD9A043), Color(0xFF9A6620)],
        ).createShader(outer),
    );
    canvas.drawPath(half, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = _ink);
    // the face
    final rf = r * 0.87;
    final face = Rect.fromCircle(center: c, radius: rf);
    final facePath = Path()
      ..moveTo(c.dx - rf, c.dy)
      ..arcTo(face, math.pi, math.pi, false)
      ..close();
    canvas.drawPath(
      facePath,
      Paint()
        ..shader = const RadialGradient(center: Alignment(0, 0.6), radius: 0.9, colors: [Color(0xFFFFFBF0), Color(0xFFF3E0BC)]).createShader(face),
    );
    canvas.drawPath(facePath, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = const Color(0xFFB4874F));
    // the heat band: cool cream on the left, through gold, to red on the right
    final rb = r * 0.70;
    final bw = r * 0.17;
    final band = Rect.fromCircle(center: c, radius: rb);
    const n = 48;
    for (var i = 0; i < n; i++) {
      final p0 = i / n;
      final col = p0 < 0.4
          ? Color.lerp(const Color(0xFFF2E3C2), const Color(0xFFFFC46B), p0 / 0.4)!
          : (p0 < 0.85 ? Color.lerp(const Color(0xFFFFC46B), const Color(0xFFFF8A3C), (p0 - 0.4) / 0.45)! : Color.lerp(const Color(0xFFFF8A3C), const Color(0xFFD9442E), (p0 - 0.85) / 0.15)!);
      canvas.drawArc(band, math.pi + p0 * math.pi, math.pi / n + 0.01, false, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = bw
        ..color = col);
    }
    // the gold: lit while the needle's in it, green-gold when it was stopped there
    final g0 = math.pi + gold.$1 * math.pi;
    final gs = (gold.$2 - gold.$1) * math.pi;
    final pulse = rm ? 1.0 : 0.6 + 0.4 * (0.5 + 0.5 * math.sin(t * 9));
    if (hot || perfect) {
      canvas.drawArc(band, g0, gs, false, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = bw + 14
        ..color = (perfect ? const Color(0xFF9BE07A) : const Color(0xFFFFD45A)).withAlpha(((0.55 * (perfect ? 1 : pulse) * 255).round().clamp(0, 255)))
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8));
    }
    canvas.drawArc(band, g0, gs, false, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = bw + 6
      ..color = _ink);
    canvas.drawArc(band, g0 + 0.01, gs - 0.02, false, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = bw + 1
      ..shader = SweepGradient(
        center: Alignment((c.dx / size.width) * 2 - 1, (c.dy / size.height) * 2 - 1),
        colors: perfect ? const [Color(0xFFD8F0B8), Color(0xFF82B75E)] : const [Color(0xFFFFF1B0), Color(0xFFF4B84E)],
      ).createShader(band));
    canvas.drawPath(kitStarPath(_at(c, rb, (gold.$1 + gold.$2) / 2), bw * 0.42), Paint()..color = perfect ? Colors.white : const Color(0xFFFFFBEA));
    // the ticks
    final tick = Paint()
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFF8A5A2E);
    for (var i = 0; i <= 10; i++) {
      final p = i / 10;
      canvas.drawLine(_at(c, rf * 0.97, p), _at(c, rf * (i % 5 == 0 ? 0.86 : 0.9), p), tick);
    }
    // the needle
    final tip = _at(c, rb + bw * 0.55, value);
    final dir = (tip - c) / (tip - c).distance;
    final side = Offset(-dir.dy, dir.dx) * (r * 0.045);
    final needle = Path()
      ..moveTo(c.dx + side.dx, c.dy + side.dy)
      ..lineTo(tip.dx, tip.dy)
      ..lineTo(c.dx - side.dx, c.dy - side.dy)
      ..close();
    canvas.drawPath(needle.shift(const Offset(2, 3)), Paint()
      ..color = const Color(0x55140A05)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2));
    canvas.drawPath(needle, Paint()..color = const Color(0xFF3A200E));
    canvas.drawLine(c, tip, Paint()
      ..strokeWidth = 1.2
      ..color = const Color(0x66FFE2B0));
    // the brass cap
    final cap = r * 0.1;
    canvas.drawCircle(c, cap, Paint()
      ..shader = const RadialGradient(center: Alignment(-0.3, -0.4), colors: [Color(0xFFFFF1C4), Color(0xFFE2B04E), Color(0xFF8A5A1A)]).createShader(Rect.fromCircle(center: c, radius: cap)));
    canvas.drawCircle(c, cap, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = _ink);
  }

  @override
  bool shouldRepaint(_HeatDial o) => o.value != value || o.hot != hot || o.perfect != perfect || (hot && o.t != t);
}

/// The Apothecary's stirring ring round the cauldron's rim (an ellipse in perspective): a violet track,
/// thinner and dimmer behind the cauldron, the gold arc at the front, and a glowing ladle-light running
/// round it with a little trail ([value] 0..1 is once round; the gold sits front and centre).
class _StirRing extends CustomPainter {
  _StirRing({required this.center, required this.radii, required this.value, required this.gold, required this.hot, required this.perfect, required this.t, required this.rm});
  final Offset center;
  final Size radii;
  final double value;
  final (double, double) gold;
  final bool hot;
  final bool perfect;
  final double t;
  final bool rm;

  double get _off => math.pi / 2 - 2 * math.pi * (gold.$1 + gold.$2) / 2; // the gold's middle at the front
  double _a(double p) => 2 * math.pi * p + _off;
  Offset _pt(double p) => center + Offset(math.cos(_a(p)) * radii.width, math.sin(_a(p)) * radii.height);
  double _front(double p) => 0.5 + 0.5 * math.sin(_a(p)); // 0 behind the cauldron, 1 in front

  @override
  void paint(Canvas canvas, Size size) {
    const n = 96;
    final pulse = rm ? 1.0 : 0.6 + 0.4 * (0.5 + 0.5 * math.sin(t * 9));
    for (var pass = 0; pass < 3; pass++) {
      for (var i = 0; i < n; i++) {
        final p0 = i / n;
        final p1 = (i + 1) / n;
        final f = _front((p0 + p1) / 2);
        final inGold = (p0 + p1) / 2 >= gold.$1 && (p0 + p1) / 2 <= gold.$2;
        final w = 3 + 5 * f;
        final paint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round;
        if (pass == 0) {
          // the dark edge under it all
          paint
            ..strokeWidth = w + (inGold ? 7 : 4)
            ..color = Color.fromRGBO(40, 18, 60, 0.35 + 0.45 * f);
        } else if (pass == 1) {
          if (!inGold || !(hot || perfect)) continue;
          paint
            ..strokeWidth = w + 16
            ..color = (perfect ? const Color(0xFF9BE07A) : const Color(0xFFFFD45A)).withAlpha(((0.5 * (perfect ? 1 : pulse) * 255).round().clamp(0, 255)))
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
        } else {
          paint
            ..strokeWidth = w + (inGold ? 3 : 0)
            ..color = inGold
                ? (perfect ? const Color(0xFFB8EC8E) : Color.lerp(const Color(0xFFFFE9A0), const Color(0xFFF4B84E), 0.4)!)
                : Color.lerp(const Color(0xFF8E6BD6), const Color(0xFFE2D2FF), f)!.withAlpha(((0.45 + 0.5 * f) * 255).round().clamp(0, 255));
        }
        canvas.drawLine(_pt(p0), _pt(p1), paint);
      }
    }
    // a star on the gold
    final gm = (gold.$1 + gold.$2) / 2;
    canvas.drawPath(kitStarPath(_pt(gm).translate(0, radii.height * 0.32), 8), Paint()..color = const Color(0xFFFFF6D0));
    // the ladle-light and its trail
    for (var k = 6; k >= 0; k--) {
      final p = (value - k * 0.014) % 1;
      final f = _front(p);
      final rr = (7 + 6 * f) * (1 - k * 0.11);
      final pos = _pt(p);
      final a = k == 0 ? 1.0 : 0.5 * (1 - k / 7);
      if (k == 0) {
        canvas.drawCircle(pos, rr + 7, Paint()
          ..color = const Color(0xFFFFE9A0).withAlpha(((0.55) * 255).round().clamp(0, 255))
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7));
        canvas.drawCircle(pos, rr, Paint()
          ..shader = const RadialGradient(center: Alignment(-0.3, -0.4), colors: [Colors.white, Color(0xFFFFE9A0), Color(0xFFE2A43A)]).createShader(Rect.fromCircle(center: pos, radius: rr)));
        canvas.drawCircle(pos, rr, Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = const Color(0xFF6E3F0E));
      } else {
        canvas.drawCircle(pos, rr, Paint()..color = const Color(0xFFFFE9A0).withAlpha(((a) * 255).round().clamp(0, 255)));
      }
    }
  }

  @override
  bool shouldRepaint(_StirRing o) => o.value != value || o.hot != hot || o.perfect != perfect || o.radii != radii || o.center != center || (hot && o.t != t);
}

/// The station's one big round button: a brass ring round a gold (Kitchen) or plum (Apothecary) face
/// with the station's icon, its word on a dark-wood tag below. It glows while the gauge is in the
/// gold, sinks under the finger, and rests dim until the gauge is up.
class _BigButton extends StatelessWidget {
  const _BigButton({
    required this.label,
    required this.icon,
    required this.plum,
    required this.enabled,
    required this.hot,
    required this.down,
    required this.t,
    required this.rm,
    required this.onDown,
    required this.onTap,
  });
  final String label;
  final String icon;
  final bool plum;
  final bool enabled;
  final bool hot;
  final bool down;
  final double t;
  final bool rm;
  final ValueChanged<bool> onDown;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final face = plum ? const [Color(0xFFF1E4FF), Color(0xFFC09AF0), Color(0xFF7C4FC0)] : const [Color(0xFFFFF0B8), Color(0xFFF7C45A), Color(0xFFD9822B)];
    final glow = hot && !rm ? 0.55 + 0.45 * (0.5 + 0.5 * math.sin(t * 12)) : (hot ? 1.0 : 0.0);
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => onDown(true) : null,
        onTapUp: enabled ? (_) => onDown(false) : null,
        onTapCancel: () => onDown(false),
        onTap: enabled ? onTap : null,
        child: Opacity(
          opacity: enabled ? 1 : 0.62,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(
              width: 116,
              height: 116,
              child: Stack(alignment: Alignment.center, children: [
                if (glow > 0)
                  Container(
                    width: 112,
                    height: 112,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: (plum ? const Color(0xFFD9B8FF) : const Color(0xFFFFD45A)).withAlpha(((0.8 * glow) * 255).round().clamp(0, 255)), blurRadius: 26, spreadRadius: 6)],
                    ),
                  ),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 70),
                  width: 104,
                  height: 104,
                  transform: Matrix4.translationValues(0, down ? 4 : 0, 0),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFFFE9A6), Color(0xFFD9A043), Color(0xFF8A5A1A)]),
                    border: Border.all(color: const Color(0xFF3A200E), width: 3),
                    boxShadow: [
                      BoxShadow(color: const Color(0xFF3A200E), offset: Offset(0, down ? 1 : 5)),
                      if (!down) const BoxShadow(color: Color(0x66140A05), blurRadius: 14, offset: Offset(0, 9)),
                    ],
                  ),
                  padding: const EdgeInsets.all(8),
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(center: const Alignment(-0.25, -0.45), radius: 0.95, colors: face, stops: const [0, 0.55, 1]),
                      border: Border.all(color: const Color(0x99FFFFFF), width: 2),
                    ),
                    child: Center(child: VoxelIcon(icon, size: 58)),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 5),
              decoration: BoxDecoration(
                color: const Color(0xFF5A3418),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF2E180A), width: 2),
                boxShadow: const [BoxShadow(color: Color(0xFF2E180A), offset: Offset(0, 2))],
              ),
              child: Text(label, style: const TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w900, fontSize: 16, color: Color(0xFFFFF0D2), shadows: kitWoodTextShadow)),
            ),
          ]),
        ),
      ),
    );
  }
}

/// "Skip": a small wooden pill (a normal batch, no gauge).
class _SkipPill extends StatelessWidget {
  const _SkipPill({required this.onTap});
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        enabled: onTap != null,
        label: 'Skip: make a normal batch',
        excludeSemantics: true,
        child: KitPress(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          builder: (_, down) => Opacity(
            opacity: onTap == null ? 0.5 : 1,
            child: Container(
              constraints: const BoxConstraints(minHeight: 44, minWidth: 64),
              padding: const EdgeInsets.fromLTRB(10, 0, 12, 0),
              decoration: Kit.wood(radius: 22, edge: 3, pressed: down, width: 220),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.fast_forward_rounded, size: 20, color: Color(0xFF3A200E)),
                SizedBox(width: 3),
                Text('Skip', style: TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w900, fontSize: 15, color: Color(0xFF3A200E))),
              ]),
            ),
          ),
        ),
      );
}

/// A light-wood square with an icon (the back plaque).
class _WoodSquare extends StatelessWidget {
  const _WoodSquare({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        enabled: onTap != null,
        label: label,
        excludeSemantics: true,
        child: KitPress(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          builder: (_, down) => Opacity(
            opacity: onTap == null ? 0.5 : 1,
            child: Container(
              width: 46,
              height: 46,
              decoration: Kit.wood(radius: 12, edge: 3, pressed: down, width: 200),
              child: Icon(icon, size: 24, color: const Color(0xFF3A200E)),
            ),
          ),
        ),
      );
}

/// What's cooking, on a parchment plaque.
class _RecipePlaque extends StatelessWidget {
  const _RecipePlaque({required this.id, required this.name});
  final String id;
  final String name;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(6, 4, 14, 4),
        decoration: Kit.parchment(radius: 12),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          ItemImage(id, size: 32),
          const SizedBox(width: 6),
          Flexible(
            child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w900, fontSize: 17, color: EvochiColor.ink)),
          ),
        ]),
      );
}

/// What goes in: small dark-wood tags with each ingredient and how many (they dim once they're in).
class _Ingredients extends StatelessWidget {
  const _Ingredients({required this.needs, required this.used});
  final Map<String, int> needs;
  final bool used;
  @override
  Widget build(BuildContext context) => AnimatedOpacity(
        duration: const Duration(milliseconds: 400),
        opacity: used ? 0.6 : 1,
        child: Wrap(alignment: WrapAlignment.center, spacing: 6, runSpacing: 6, children: [
          for (final e in needs.entries)
            Container(
              padding: const EdgeInsets.fromLTRB(4, 2, 9, 2),
              decoration: BoxDecoration(
                color: const Color(0xE65A3418),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF2E180A), width: 1.5),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                ItemImage(e.key, size: 24),
                const SizedBox(width: 2),
                Text('×${e.value}', style: const TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w900, fontSize: 13, color: Color(0xFFFFF0D2), shadows: kitWoodTextShadow)),
              ]),
            ),
        ]),
      );
}

/// A short line on a parchment ribbon (the hint).
class _Ribbon extends StatelessWidget {
  const _Ribbon({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(14, 6, 14, 7),
        decoration: Kit.parchment(radius: 10, depth: 2),
        child: Text(text, textAlign: TextAlign.center, style: const TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w800, fontSize: 14.5, color: EvochiColor.ink)),
      );
}

/// "Perfect!" in fat outlined gold with a "Double batch ×2" ribbon, or "Nicely done!" in green.
class _Stamp extends StatelessWidget {
  const _Stamp({required this.perfect});
  final bool perfect;
  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, children: [
        _Outlined(
          perfect ? 'Perfect!' : 'Nicely done!',
          size: perfect ? 46 : 38,
          fill: perfect ? const Color(0xFFFFD95A) : const Color(0xFFA6E37E),
          stroke: perfect ? const Color(0xFF7A4512) : const Color(0xFF2C5A1C),
        ),
        if (perfect) ...[
          const SizedBox(height: 2),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 3, 12, 4),
            decoration: BoxDecoration(
              color: const Color(0xFF5FA046),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF2F5A22), width: 2),
              boxShadow: const [BoxShadow(color: Color(0xFF2F5A22), offset: Offset(0, 2))],
            ),
            child: const Text('Double batch ×2', style: TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w900, fontSize: 15, color: Colors.white, shadows: [Shadow(color: Color(0x66000000), offset: Offset(0, 1))])),
          ),
        ],
      ]);
}

/// Fat game lettering: a thick rounded outline under the fill, and a soft drop under both.
class _Outlined extends StatelessWidget {
  const _Outlined(this.text, {required this.size, required this.fill, required this.stroke});
  final String text;
  final double size;
  final Color fill;
  final Color stroke;
  @override
  Widget build(BuildContext context) {
    final base = TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w900, fontSize: size, height: 1.1, letterSpacing: 0.5);
    return Stack(children: [
      Text(
        text,
        style: base.copyWith(
          foreground: Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = size * 0.2
            ..strokeJoin = StrokeJoin.round
            ..color = stroke,
          shadows: const [Shadow(color: Color(0x66000000), offset: Offset(0, 5), blurRadius: 2)],
        ),
      ),
      Text(text, style: base.copyWith(color: fill)),
    ]);
  }
}
