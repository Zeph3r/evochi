// Lumen Trails: the trail places. The Mossy Ruins (and, while Tangled Lumen is underway, the ruins
// tangled in Hollow) and the Old Gate past the bridge: the scene, the friends who live there, the trail
// job waiting there, and a glinting clue when a discovery is ready to inspect.
// Mirrors `trailplace` in web/src/screens/trails.js.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../controllers/game_controller.dart';
import '../../game/trails/trails.dart' as tr;
import '../home/home_widgets.dart';
import '../shared/kit.dart';
import '../shared/widgets.dart';
import '../village/story_widgets.dart';
import '../village/village_screen.dart';
import 'trails_widgets.dart';

class TrailPlaceScreen extends StatelessWidget {
  const TrailPlaceScreen({super.key, required this.placeId});
  final String placeId; // ruins | gate

  @override
  Widget build(BuildContext context) {
    final c = context.watch<GameController>();
    final id = placeId == 'gate' ? 'gate' : 'ruins';
    final st = c.storyView;
    final t = c.trailsView;
    final e2 = st.quest('eq02').phase;
    final sceneId = id == 'gate'
        ? 'sentinel_gate'
        : (st.flag('sprout_restored') || !st.flag('petalune_befriended')
            ? 'mossy_ruins'
            : (e2 == 'ruins_ready' || e2 == 'accepted_walk' ? 'mossy_ruins_hollow' : 'mossy_ruins'));
    final name = id == 'gate' ? 'The Old Gate' : 'Mossy Ruins';
    final quest = st.trail.where((v) => v.next.place == id && v.accepted && !v.completed).firstOrNull;
    final friends = id == 'ruins' ? ['petalune', 'hollow_sprout'].where(t.known).toList() : (t.isRestored('sentinel') ? ['sentinel'] : <String>[]);
    final clue = tr.cluesAt(c.state, id, c.now).isNotEmpty;
    final String text;
    if (id == 'gate') {
      text = t.isRestored('sentinel')
          ? 'The gate stands open. Beyond it the third trail glows faintly, on and on past the horizon.'
          : 'The bridge creaks but holds. Past it, the old gate waits in the dusk, humming with Hollow light.';
    } else if (t.isRestored('hollow_sprout')) {
      text = 'The ruins are peaceful now. Petals drift from the arch, and the little sprout waves at everyone who passes.';
    } else if (st.flag('petalune_befriended')) {
      text = 'The ruins are quiet. Somewhere under the moss, trail runes point north.';
    } else {
      text = 'A quiet ruin where the forest has taken the stones back. Runes under the moss, a waterfall behind the arch.';
    }
    final ta = trailsArt;
    return Scaffold(
      backgroundColor: EvochiColor.panel,
      body: KitPage(
        material: KitMaterial.plain,
        child: SafeArea(
        bottom: false,
        child: Column(children: [
          PlaceHeader(title: name, short: name.replaceFirst('The ', ''), backLabel: 'Back', onBack: () => Navigator.of(context).maybePop()),
          Expanded(
            child: ListView(padding: EdgeInsets.only(bottom: 20 + MediaQuery.of(context).padding.bottom), children: [
              if (ta.available && ta.hasScene(sceneId))
                TrailPlate(
                  scene: sceneId,
                  semanticLabel: id == 'gate' ? 'A great broken gate at dusk, Hollow crystals glowing around it.' : 'A quiet forest ruin: a mossy arch, flagstones and a waterfall.',
                  overlays: (w, h) {
                    final plate = ta.sceneSize(sceneId);
                    final wild = ta.sceneAnchor(sceneId, 'wild');
                    return [
                      for (final f in friends)
                        creatureAt(
                          id: f,
                          state: tr.creatureDefs[f]!.states.done,
                          anchor: wild,
                          plate: plate,
                          w: w,
                          h: h,
                          widthFrac: tr.creatureDefs[f]!.size == 'large' ? 0.44 : 0.26,
                          footFrac: 0.88,
                        ),
                    ];
                  },
                  front: (w, h) => [ClueGlint(place: id, width: w, height: h)],
                )
              else
                const SizedBox(height: 24),
              Transform.translate(
                offset: const Offset(0, -14),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    if (quest != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: TapCard(
                          label: '${quest.title}. ${nextText(quest)}',
                          padding: const EdgeInsets.fromLTRB(8, 10, 12, 10),
                          highlight: quest.next.kind == 'encounter',
                          onTap: () => quest.next.kind == 'encounter' ? openPrep(context, quest.id) : showStoryQuest(context, quest.id),
                          child: Row(children: [
                            SizedBox(width: 54, height: 60, child: Center(child: CreatureFace(tr.encounterDefs[quest.id]!.creature))),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                const Text('Trail job', style: EvochiText.caption),
                                Text(quest.title, style: EvochiText.cardTitle),
                                Text(nextText(quest), style: EvochiText.bodyText.copyWith(color: EvochiColor.textSecondary)),
                              ]),
                            ),
                            homeChevron,
                          ]),
                        ),
                      ),
                    Padding(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2), child: Text(text, style: EvochiText.bodyText)),
                    if (friends.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(spacing: 8, runSpacing: 8, children: [
                        for (final f in friends)
                          Semantics(
                            button: true,
                            label: tr.creatureDefs[f]!.name,
                            child: GestureDetector(
                              onTap: () => showCreatureCard(context, f),
                              child: ExcludeSemantics(
                                child: Container(
                                  height: 36,
                                  padding: const EdgeInsets.only(left: 4, right: 10),
                                  decoration: Kit.parchment(radius: 10, depth: 2, drop: false),
                                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                                    CreatureFace(f, size: 26),
                                    const SizedBox(width: 4),
                                    Text(tr.creatureDefs[f]!.name, style: EvochiText.tag.copyWith(color: EvochiColor.ink)),
                                  ]),
                                ),
                              ),
                            ),
                          ),
                      ]),
                    ],
                    if (clue) ...[
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Text('Something glints here. Tap it to inspect.', style: EvochiText.tag.copyWith(color: EvochiColor.gold900, fontWeight: FontWeight.w800)),
                      ),
                    ],
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
