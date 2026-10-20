// Lumen Trails: the Trail Guild Board. Your guild rank, the lore of the Fading Paths, today's three
// discoveries, the trail jobs (encounter quests) and the friends you've made on the trail.
// Mirrors `guild` in web/src/screens/trails.js.

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
import '../shared/live_scene.dart';

class GuildScreen extends StatefulWidget {
  const GuildScreen({super.key});
  @override
  State<GuildScreen> createState() => _GuildScreenState();
}

class _GuildScreenState extends State<GuildScreen> {
  late bool _lore; // the lore card is open (always on the first visit)

  @override
  void initState() {
    super.initState();
    final c = context.read<GameController>();
    _lore = c.state.trails.seen['guild_intro'] != true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) c.run((s, n) => tr.markTrailSeen(s, 'guild_intro'), quiet: true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<GameController>();
    final t = c.trailsView;
    final st = c.storyView;
    final friends = [
      for (final f in t.companions) (f.id, 'Companion'),
      for (final id in t.restored.keys) (id, 'Restored'),
    ];
    // the notice board: today's discoveries are papers pinned up a hair off straight
    return Scaffold(
      backgroundColor: EvochiColor.panel,
      body: KitPage(
        material: KitMaterial.board,
        child: SafeArea(
        bottom: false,
        child: Column(children: [
          PlaceHeader(title: 'Trail Guild Board', short: 'Guild', backLabel: 'Back', onBack: () => Navigator.of(context).maybePop()),
          Expanded(
            child: ListView(padding: EdgeInsets.only(bottom: 20 + MediaQuery.of(context).padding.bottom), children: [
              const _GuildHead(),
              Transform.translate(
                offset: const Offset(0, -16),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    const GuildRankCard(),
                    const SizedBox(height: 10),
                    if (_lore)
                      _LoreCard(onHide: () => setState(() => _lore = false))
                    else
                      TapCard(
                        label: '${tr.TrailLore.title}. Why your steps light the trails',
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                        onTap: () => setState(() => _lore = true),
                        child: Row(children: [
                          const VoxelIcon('trail', size: 36),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(tr.TrailLore.title, style: EvochiText.cardTitle),
                              Text('Why your steps light the trails', style: EvochiText.caption),
                            ]),
                          ),
                          homeChevron,
                        ]),
                      ),
                    const SizedBox(height: 10),
                    SectionHead("Today's discoveries", end: Text('Resets in ${resetText(t.msToReset)}', style: EvochiText.tiny)),
                    const SizedBox(height: 4),
                    for (var i = 0; i < t.discoveries.length; i++) DiscoveryRow(t.discoveries[i], pinned: true, tilt: i.isEven ? -0.5 : 0.45),
                    const SizedBox(height: 4),
                    const SectionHead('Trail jobs', trailing: Tag('Encounters')),
                    for (final v in st.trail) TrailQuestRow(v),
                    if (friends.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      const SectionHead('Friends of the trail'),
                      FriendGrid(children: [
                        for (final f in friends) FriendCard(id: f.$1, known: true, sub: f.$2, onTap: () => showCreatureCard(context, f.$1)),
                      ]),
                      const SizedBox(height: 8),
                    ],
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      child: Text(
                        'Discoveries are cozy and quick. Encounters are optional, and never a fight to the finish: you calm, befriend and restore. Your Evochi never faints.',
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

/// The Lodge plate with the Guild's badge and name over it.
class _GuildHead extends StatelessWidget {
  const _GuildHead();
  @override
  Widget build(BuildContext context) => SizedBox(
        height: 150,
        child: Stack(fit: StackFit.expand, children: [
          // the soft grade is applied as the plate paints (no offscreen layer)
          LiveImage(villageArt.place('lodge'), fit: BoxFit.cover, alignment: const Alignment(0, -0.2), colorFilter: const ColorFilter.matrix(_soft), excludeFromSemantics: true),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x73281E14), Color(0x00281E14), Color(0x4DF9ECD4), KitColor.pageTop],
                stops: [0, 0.55, 0.85, 1],
              ),
            ),
          ),
          Positioned(
            left: 14,
            top: 24,
            child: Semantics(
              header: true,
              label: 'Sunlit Village Trail Guild',
              child: ExcludeSemantics(
                child: Row(children: [
                  const VoxelIcon('trail_badge', size: 40),
                  const SizedBox(width: 8),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Sunlit Village', style: EvochiText.caption.copyWith(color: const Color(0xFFFFF6E6), shadows: _shadow)),
                    Text('Trail Guild', style: EvochiText.section.copyWith(color: Colors.white, shadows: _shadow)),
                  ]),
                ]),
              ),
            ),
          ),
        ]),
      );
}

const _shadow = [Shadow(color: Color(0x66000000), offset: Offset(0, 1), blurRadius: 2)];

// a touch less saturated, so the title reads over the plate
const _soft = <double>[
  0.93, 0.06, 0.01, 0, 0, //
  0.03, 0.93, 0.04, 0, 0, //
  0.03, 0.06, 0.91, 0, 0, //
  0, 0, 0, 1, 0,
];

class _LoreCard extends StatelessWidget {
  const _LoreCard({required this.onHide});
  final VoidCallback onHide;
  @override
  Widget build(BuildContext context) => Semantics(
        container: true,
        label: tr.TrailLore.title,
        child: GameCard(
          paper: KitPaper.lore,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              const Expanded(child: Text(tr.TrailLore.title, style: EvochiText.cardTitle)),
              EvochiButton(label: 'Hide', small: true, expand: false, tone: ButtonTone.cream, onPressed: onHide),
            ]),
            const SizedBox(height: 6),
            const Text(tr.TrailLore.intro, style: EvochiText.bodyText),
            const SizedBox(height: 6),
            const Text(tr.TrailLore.trails, style: EvochiText.bodyText),
            const SizedBox(height: 6),
            const Text(tr.TrailLore.guild, style: EvochiText.caption),
          ]),
        ),
      );
}
