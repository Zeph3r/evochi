// Home Tales: the Kitchen and the Apothecary (one shared screen). The room with your Evochi in it,
// recipe cards with have/need chips for each ingredient, a skippable timing minigame (a perfect stop
// makes a double batch and +50% skill XP; skipping makes a normal batch; ingredients are never
// wasted) and a result card: give one to your Evochi, use it in the Garden, take it to the villager
// who asked for it, or make another. Mirrors `station` in web/src/screens/homeland.js.

import 'dart:async';

import 'package:flutter/material.dart';
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
    _minigame(c, r.id);
  }

  Future<void> _minigame(GameController c, String rid) async {
    final reduce = MediaQuery.of(context).disableAnimations;
    final quality = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      barrierColor: const Color(0x8C201B17),
      // the Apothecary's windows are framed in plum wood
      builder: (d) => KitDialog(
        variant: h.recipeDefs[rid]!.station == 'apothecary' ? FrameVariant.plum : FrameVariant.wood,
        padding: const EdgeInsets.all(16),
        child: _Minigame(recipe: h.recipeDefs[rid]!, slow: reduce),
      ),
    );
    if (quality == null || !mounted) return;
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
              _minigame(c, rid);
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
    final open = h.stationOpen(c.state, id);
    final recipes = [for (final r in h.recipeOrder) if (h.recipeDefs[r]!.station == id) h.recipeView(c.state, r)];
    final v = q.questView(c.state, s.quest, c.now);
    final joy = DateTime.now().millisecondsSinceEpoch - _joyAt < 1200;
    final pet = c.state.pet;
    final petDead = c.view.pet?.dead ?? true;
    final mq = MediaQuery.of(context);
    final reduce = mq.disableAnimations;
    // the Kitchen is a warm recipe book; the Apothecary is plum wood and lavender paper
    final apothecary = id == 'apothecary';
    final pageTop = apothecary ? const Color(0xFFF3ECFA) : const Color(0xFFFBEBD2);
    return Scaffold(
      backgroundColor: EvochiColor.panel,
      body: KitPage(
        material: apothecary ? KitMaterial.apothecary : KitMaterial.kitchen,
        child: SafeArea(
        bottom: false,
        child: Column(children: [
          PlaceHeader(title: 'Your ${s.name}', short: s.name, backLabel: 'Back', onBack: () => Navigator.of(context).maybePop()),
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
                        "${s.verb}ing has a quick timing game. It's optional: skip it any time. A perfect result makes a double batch, and ingredients are never wasted.",
                        style: EvochiText.caption,
                      ),
                    ),
                  ]),
                ),
              ),
            ]),
          ),
        ]),
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
                Text(effectText(it), style: EvochiText.caption.copyWith(fontSize: 11)),
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

// ----------------------------------------------------------------- the minigame ----
/// The timing meter: a marker sweeps back and forth; stopping it in the golden zone is "perfect".
/// Pops the dialog with 'perfect', 'good' or 'skip'.
class _Minigame extends StatefulWidget {
  const _Minigame({required this.recipe, required this.slow});
  final h.RecipeDef recipe;
  final bool slow; // reduced motion: a slower sweep
  @override
  State<_Minigame> createState() => _MinigameState();
}

class _MinigameState extends State<_Minigame> with SingleTickerProviderStateMixin {
  static const _zone = (0.62, 0.8);
  late final AnimationController _c = AnimationController(vsync: this, duration: Duration(milliseconds: widget.slow ? 2600 : 1700));
  String? _result;
  Timer? _close;

  @override
  void initState() {
    super.initState();
    _c.repeat(reverse: true); // 0 -> 1 -> 0: a triangle wave, like the web build
  }

  @override
  void dispose() {
    _close?.cancel();
    _c.dispose();
    super.dispose();
  }

  void _finish(String quality) {
    if (_result != null) return;
    _c.stop();
    setState(() => _result = quality);
    if (quality == 'skip') {
      Navigator.pop(context, quality);
      return;
    }
    _close = Timer(const Duration(milliseconds: 750), () {
      if (mounted) Navigator.pop(context, quality);
    });
  }

  void _stop() {
    final p = _c.value;
    final ok = p >= _zone.$1 - 0.015 && p <= _zone.$2 + 0.015;
    context.read<GameController>().audio.play(ok ? 'reward_chime' : 'ui_tap', volume: 0.6);
    _finish(ok ? 'perfect' : 'good');
  }

  @override
  Widget build(BuildContext context) {
    final t = _mg[widget.recipe.station]!;
    final it = item(widget.recipe.makes);
    final perfect = _result == 'perfect';
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Center(child: ItemImage(widget.recipe.makes, size: 84)),
      Text(it.name, textAlign: TextAlign.center, style: EvochiText.section),
      const SizedBox(height: 4),
      Text(t.prompt, textAlign: TextAlign.center, style: EvochiText.bodyText.copyWith(color: EvochiColor.textSecondary)),
      const SizedBox(height: 14),
      ExcludeSemantics(
        child: SizedBox(
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
                left: 4 + w * _zone.$1,
                width: w * (_zone.$2 - _zone.$1),
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
                left: 0,
                top: 0,
                width: 10,
                height: 48,
                child: AnimatedBuilder(
                  animation: _c,
                  builder: (_, child) => Transform.translate(offset: Offset(4 + w * _c.value - 5, 0), child: child),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(5),
                      border: Border.all(color: EvochiColor.ink, width: 2.5),
                      boxShadow: const [BoxShadow(color: Color(0x59000000), blurRadius: 4, offset: Offset(0, 2))],
                    ),
                  ),
                ),
              ),
            ]);
          }),
        ),
      ),
      const SizedBox(height: 8),
      SizedBox(
        height: 26,
        child: Semantics(
          liveRegion: true,
          child: Text(
            _result == null || _result == 'skip' ? '' : (perfect ? 'Perfect! Double batch' : 'Nicely done!'),
            textAlign: TextAlign.center,
            style: EvochiText.section.copyWith(fontSize: 18, color: perfect ? EvochiColor.healthy : EvochiColor.gold900),
          ),
        ),
      ),
      const SizedBox(height: 8),
      EvochiButton(label: t.stop, tone: ButtonTone.green, onPressed: _result == null ? _stop : null),
      const SizedBox(height: 8),
      EvochiButton(label: t.skip, tone: ButtonTone.cream, onPressed: _result == null ? () => _finish('skip') : null),
      const SizedBox(height: 6),
      const Text('Optional: skipping makes a normal batch. Ingredients are never wasted.', textAlign: TextAlign.center, style: EvochiText.caption),
    ]);
  }
}
