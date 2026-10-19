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

class _MinigameText {
  const _MinigameText(this.prompt, this.stop, this.skip);
  final String prompt;
  final String stop;
  final String skip;
}

const _mg = {
  'kitchen': _MinigameText('Tap when the marker reaches the golden zone to bake a perfect batch.', 'Take it out!', 'Skip, just cook it'),
  'apothecary': _MinigameText('Tap when the marker reaches the golden zone to brew a perfect batch.', 'Stir now!', 'Skip, just brew it'),
};

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

  void _cookDone(GameController c, String rid, String quality) {
    if (!mounted || _cookRid != rid) return;
    setState(() => _cookRid = null);
    _craft(c, rid, quality);
  }

  void _craft(GameController c, String rid, String quality) {
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
    showEvochiDialog<void>(context, builder: (d) {
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
      body = Column(children: [
        header,
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.only(bottom: 20 + mq.padding.bottom),
            child: _CookView(
              key: ValueKey('cook-$_cookSerial'),
              recipe: h.recipeDefs[r]!,
              station: id,
              onDone: (quality) => _cookDone(c, r, quality),
              onCancel: () => _cancelCook(c),
            ),
          ),
        ),
      ]);
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
/// At the oven or the cauldron (web: cookStage / cookControls / finishCook in homeland.js): a square
/// stage on the room plate pushes in from the room to the station's mouth while the ingredients fly
/// in, a glow pulses and embers (or bubbles) rise; after ~1.75 s the timing gauge slides up on a
/// light-wood plaque. Stopping it (or skipping) freezes the gauge, a banner pops in, the dish pops out
/// of the mouth with a burst of sparkles, and [onDone] follows (1.35 s; 0.45 s for a skip). Back
/// ([onCancel]) leaves without using anything. Everything about the cook lives here, so a fuller
/// minigame can replace the gauge later. Reduced motion: no push-in, nothing flies, no particles.
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
  late final Ticker _ticker;
  final _clock = ValueNotifier<double>(0); // seconds since the cook began
  String _phase = 'in'; // in (pushing in) | play (the gauge is up) | done
  double _playAt = 0;
  double _doneAt = 0;
  double _p = 0; // the gauge's marker, 0..1
  String? _quality;
  bool _reported = false;
  bool _rm = false;

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

  double get _period => _rm ? 2.6 : 1.7;

  void _tick(Duration elapsed) {
    final t = elapsed.inMicroseconds / 1e6;
    if (_phase == 'in' && t >= (_rm ? 0.3 : 1.75)) {
      setState(() {
        _phase = 'play';
        _playAt = t;
      });
    }
    if (_phase == 'play') {
      final x = ((t - _playAt) / _period) % 1 * 2; // a triangle wave, 0 -> 1 -> 0
      _p = x < 1 ? x : 2 - x;
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
    final ok = _p >= _Meter.zone.$1 - 0.015 && _p <= _Meter.zone.$2 + 0.015;
    context.read<GameController>().audio.play(ok ? 'reward_chime' : 'ui_tap', volume: 0.6);
    _finish(ok ? 'perfect' : 'good');
  }

  void _finish(String quality) {
    if (_phase == 'done') return;
    setState(() {
      if (_phase == 'in') _playAt = _clock.value; // a skip before the gauge was up: it shows, frozen
      _phase = 'done';
      _quality = quality;
      _doneAt = _clock.value;
    });
  }

  /// The plate's rect at [zoom] in a [box]: centred on the station, clamped so it always covers the box.
  Rect _frame(_StationStage st, double zoom, double ar, Size box) {
    final w = box.width * zoom;
    final hgt = w * ar;
    final l = (box.width / 2 - st.fx * w).clamp(math.min(0.0, box.width - w), 0.0).toDouble();
    final t = (box.height / 2 - st.fy * hgt).clamp(math.min(0.0, box.height - hgt), 0.0).toDouble();
    return Rect.fromLTWH(l, t, w, hgt);
  }

  @override
  Widget build(BuildContext context) {
    final st = _stages[widget.station]!;
    final text = _mg[widget.station]!;
    final it = item(widget.recipe.makes);
    final done = _phase == 'done';
    final result = _quality == 'perfect' ? 'Perfect! Double batch' : (_quality == 'good' ? 'Nicely done!' : '');
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AspectRatio(
        aspectRatio: 1,
        child: Container(
          decoration: const BoxDecoration(
            color: Color(0xFF2A1A10),
            border: Border(bottom: BorderSide(color: KitColor.woodInk, width: 4)),
            boxShadow: [BoxShadow(color: Color(0xFFC99A62), offset: Offset(0, 4)), BoxShadow(color: Color(0x40281405), blurRadius: 18, offset: Offset(0, 10))],
          ),
          child: ClipRect(
            child: LayoutBuilder(builder: (ctx, b) => _stage(Size(b.maxWidth, b.maxHeight), st, it, result)),
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(_phase == 'in' ? st.going : text.prompt, style: EvochiText.caption.copyWith(color: EvochiColor.textSecondary)),
          const SizedBox(height: 10),
          EvochiButton(label: text.stop, tone: ButtonTone.green, large: true, onPressed: _phase == 'play' ? _stop : null),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: EvochiButton(label: text.skip, tone: ButtonTone.cream, onPressed: done ? null : () => _finish('skip'))),
            const SizedBox(width: 8),
            _TextButton(label: 'Back', onTap: done ? null : widget.onCancel),
          ]),
          const SizedBox(height: 10),
          const Text("Optional: skipping makes a normal batch. Ingredients are only used once it's done.", style: EvochiText.tiny),
        ]),
      ),
    ]);
  }

  Widget _stage(Size box, _StationStage st, CatalogItem it, String result) {
    final rs = homeArt.roomSize(widget.station);
    final ar = rs.height / rs.width;
    final wide = _frame(st, _wideZoom, ar, box);
    final close = _frame(st, _closeZoom, ar, box);
    final mouth = Offset(close.left + st.fx * close.width, close.top + st.fy * close.height);
    final drops = [for (final e in widget.recipe.needs.entries) for (var i = 0; i < math.min(e.value, 3); i++) e.key].take(6).toList();
    final plate = homeArt.room(widget.station);
    final w = box.width;
    return ValueListenableBuilder<double>(
      valueListenable: _clock,
      builder: (ctx, t, _) {
        final push = _rm ? 1.0 : _push.transform((t / 0.95).clamp(0.0, 1.0).toDouble());
        final frame = Rect.lerp(wide, close, push)!;
        final up = _phase == 'in' ? 0.0 : ((t - _playAt) / 0.3).clamp(0.0, 1.0).toDouble(); // the gauge sliding up
        final popT = _phase == 'done' ? ((t - _doneAt) / (_quality == 'skip' ? 0.4 : 0.9)).clamp(0.0, 1.0).toDouble() : -1.0;
        final pop = popT < 0 ? 0.0 : _pop.transform(popT);
        final dish = w * 0.34;
        final dishC = mouth.translate(0, -0.55 * dish * pop);
        final bannerT = _phase == 'done' && result.isNotEmpty ? ((t - _doneAt) / 0.35).clamp(0.0, 1.0).toDouble() : 0.0;
        return Stack(clipBehavior: Clip.hardEdge, children: [
          // the room plate, pushing in from the room to the station
          Positioned(
            left: frame.left,
            top: frame.top,
            width: frame.width,
            height: frame.height,
            child: Image.asset(plate, fit: BoxFit.fill, gaplessPlayback: true, filterQuality: FilterQuality.medium, excludeFromSemantics: true),
          ),
          // the vignette, the glow and the embers (or bubbles), painted straight over the plate
          Positioned.fill(
            child: CustomPaint(
              painter: _StageFx(t: t, mouth: mouth, glow: st.glow, bubbles: widget.station == 'apothecary', playAt: _phase == 'in' ? null : _playAt, rm: _rm),
            ),
          ),
          // the ingredients fly up into the mouth, one after another
          if (!_rm) ...[for (var i = 0; i < drops.length; i++) _dropAt(drops[i], i, t, mouth, w)],
          // the dish pops out of the mouth
          if (popT >= 0)
            Positioned(
              left: dishC.dx - dish / 2,
              top: dishC.dy - dish / 2,
              width: dish,
              height: dish,
              child: Transform.scale(scale: math.max(0.0, pop), child: Image.asset(art.item(widget.recipe.makes), fit: BoxFit.contain, excludeFromSemantics: true)),
            ),
          if (popT >= 0 && !_rm) Positioned.fill(child: CustomPaint(painter: _Sparks(t: t - _doneAt - 0.15, center: dishC))),
          // the recipe on a parchment plaque
          Positioned(
            left: 0,
            right: 0,
            top: box.height * 0.04,
            child: Center(
              child: Container(
                padding: const EdgeInsets.fromLTRB(6, 5, 14, 5),
                decoration: Kit.parchment(radius: 12, drop: false),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  ItemImage(widget.recipe.makes, size: 30),
                  const SizedBox(width: 6),
                  Text(it.name, style: const TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w900, fontSize: 16, color: EvochiColor.ink)),
                ]),
              ),
            ),
          ),
          // "Perfect! Double batch" / "Nicely done!"
          if (bannerT > 0)
            Positioned(
              left: 0,
              right: 0,
              top: box.height * 0.18,
              child: Center(
                child: Opacity(
                  opacity: (bannerT / 0.7).clamp(0.0, 1.0).toDouble(),
                  child: Transform.scale(
                    scale: 0.6 + 0.4 * _pop.transform(bannerT),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFF8A5414), width: 2.5),
                        gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFFFF0B8), Color(0xFFF9CF6A)]),
                        boxShadow: const [BoxShadow(color: Color(0xFF6E3F0E), offset: Offset(0, 4))],
                      ),
                      child: Text(result, style: const TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w900, fontSize: 20, color: KitColor.signInk)),
                    ),
                  ),
                ),
              ),
            ),
          if (result.isNotEmpty) Semantics(liveRegion: true, label: result, child: const SizedBox.shrink()),
          // the timing gauge on a light-wood plaque, over the fire
          if (up > 0)
            Positioned(
              left: w * 0.06,
              right: w * 0.06,
              bottom: box.height * 0.05,
              child: Transform.translate(
                offset: Offset(0, 14 * (1 - up)),
                child: Opacity(
                  opacity: up,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: Kit.wood(radius: 14, width: 320, y: -0.2, edge: 4),
                    child: ExcludeSemantics(child: _Meter(value: _p, perfect: _quality == 'perfect')),
                  ),
                ),
              ),
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

/// The timing gauge: a dark groove, the golden zone (62-80%) and a white marker at [value].
class _Meter extends StatelessWidget {
  const _Meter({required this.value, required this.perfect});
  final double value;
  final bool perfect;
  static const zone = (0.62, 0.8);
  @override
  Widget build(BuildContext context) => SizedBox(
        height: 48,
        child: LayoutBuilder(builder: (ctx, b) {
          final w = b.maxWidth - 8;
          return Stack(clipBehavior: Clip.none, children: [
            Positioned(
              left: 4,
              right: 4,
              top: 7,
              height: 34,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(17),
                  gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF5C4637), Color(0xFF4A382C)]),
                  boxShadow: const [BoxShadow(color: Color(0xFFE2CDB4), offset: Offset(0, 2))],
                ),
              ),
            ),
            Positioned(
              left: 4 + w * zone.$1,
              width: w * (zone.$2 - zone.$1),
              top: 11,
              height: 26,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: perfect ? const [Color(0xFFD8F0B8), Color(0xFF82B75E)] : const [Color(0xFFFFE9A8), Color(0xFFF4B84E)],
                  ),
                  boxShadow: [BoxShadow(color: perfect ? const Color(0xFF96E664) : const Color(0xD9FFD264), blurRadius: perfect ? 18 : 12)],
                ),
              ),
            ),
            Positioned(
              left: 4 + w * value - 5,
              top: 0,
              width: 10,
              height: 48,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(color: EvochiColor.ink, width: 2.5),
                  boxShadow: const [BoxShadow(color: Color(0x59000000), blurRadius: 4, offset: Offset(0, 2))],
                ),
              ),
            ),
          ]);
        }),
      );
}

/// A plain text button (`.btn.ghost`): "Back" beside the station's buttons.
class _TextButton extends StatelessWidget {
  const _TextButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        enabled: onTap != null,
        label: label,
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 64, minHeight: 48),
            child: Center(
              child: Text(label, style: TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w900, fontSize: 17, color: onTap == null ? EvochiColor.textHelper : EvochiColor.textSecondary)),
            ),
          ),
        ),
      );
}
