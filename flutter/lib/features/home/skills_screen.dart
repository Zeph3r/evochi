// Home Tales: the Skills chart. Three tabs (Farming, Cooking, Alchemy), a skill card with its XP bar
// and how to earn it, and a milestone timeline where each step shows what it needs: a skill level,
// and sometimes a story quest. [SkillsPanel] is shared with Journey > Skills.
// Mirrors `skills` / skillsPanel in web/src/screens/homeland.js.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../controllers/game_controller.dart';
import '../../game/home/home.dart' as h;
import '../../game/story/story.dart' as q;
import '../shared/kit.dart';
import '../shared/widgets.dart';
import '../village/story_widgets.dart';
import '../village/village_screen.dart';
import 'home_widgets.dart';

class SkillsScreen extends StatelessWidget {
  const SkillsScreen({super.key, this.initial});
  final String? initial;
  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: EvochiColor.panel,
        // the explorer's journal, like Journey > Skills
        body: KitPage(
          material: KitMaterial.journal,
          child: SafeArea(
            bottom: false,
            child: Column(children: [
              PlaceHeader(title: 'Skills', short: 'Skills', backLabel: 'Back', onBack: () => Navigator.of(context).maybePop()),
              Expanded(
                child: ListView(
                  padding: EdgeInsets.fromLTRB(14, 6, 14, 20 + MediaQuery.of(context).padding.bottom),
                  children: [SkillsPanel(initial: initial)],
                ),
              ),
            ]),
          ),
        ),
      );
}

const _count = {'farming': ('harvests', 'harvest'), 'cooking': ('cooked', 'dish'), 'alchemy': ('brewed', 'brew')};

/// A milestone's story requirement: the quest that opens a recipe's room, or the quest itself.
(String, bool, String)? _storyReq(GameController c, h.SkillMilestone m) {
  if (m.kind == 'recipe') {
    final r = h.recipeDefs[m.id]!;
    final st = h.stationDefs[r.station]!;
    // a story recipe (the Lantern Tonic) is taught by its own quest
    if (r.flag != null) {
      final quest = h.recipeQuest(r);
      return (quest, h.storyFlag(c.state, r.flag!), 'Story: ${q.storyQuests[quest]!.title}');
    }
    return (st.quest, h.stationOpen(c.state, st.id), '${st.name}: ${q.storyQuests[st.quest]!.title}');
  }
  if (m.kind == 'quest') {
    final v = q.questView(c.state, m.id, c.now);
    return (m.id, v.completed, 'Story: ${v.title}');
  }
  return null;
}

class SkillsPanel extends StatefulWidget {
  const SkillsPanel({super.key, this.initial});
  final String? initial;
  @override
  State<SkillsPanel> createState() => _SkillsPanelState();
}

class _SkillsPanelState extends State<SkillsPanel> {
  late String _skill = h.skillDefs.containsKey(widget.initial) ? widget.initial! : 'farming';

  void _openMilestone(BuildContext context, h.SkillMilestone m) {
    if (m.kind == 'quest') {
      showStoryQuest(context, m.id);
      return;
    }
    if (m.kind == 'recipe') {
      final r = h.recipeDefs[m.id]!;
      final state = context.read<GameController>().state;
      if (!h.stationOpen(state, r.station)) {
        showStoryQuest(context, h.stationDefs[r.station]!.quest);
      } else if (r.flag != null && !h.storyFlag(state, r.flag!)) {
        showStoryQuest(context, h.recipeQuest(r));
      } else {
        goHome(context, r.station);
      }
      return;
    }
    goHome(context, 'garden');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<GameController>();
    final k = _skill;
    final all = {for (final id in h.skillOrder) id: h.skillView(c.state, id)};
    final s = all[k]!;
    final station = k == 'cooking' ? 'kitchen' : (k == 'alchemy' ? 'apothecary' : null);
    final stOpen = station == null || h.stationOpen(c.state, station);
    final sq = station == null ? null : q.questView(c.state, h.stationDefs[station]!.quest, c.now);
    final count = c.state.home.counts[_count[k]!.$1] ?? 0;
    final noun = _count[k]!.$2;
    final countText = '${fmt(count)} $noun${count == 1 ? '' : (noun.endsWith('h') ? 'es' : 's')}';
    final ms = h.skillMilestones(k);
    var nextMarked = false;
    final rows = <Widget>[];
    for (final m in ms) {
      final reached = s.level >= m.level;
      final sr = _storyReq(c, m);
      final done = reached && (sr == null || sr.$2);
      final next = !done && !nextMarked;
      if (next) nextMarked = true;
      rows.add(_MilestoneRow(m: m, skill: s, reached: reached, done: done, next: next, req: sr, onTap: () => _openMilestone(context, m)));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        for (final id in h.skillOrder)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: _SkillTab(
                skill: all[id]!,
                selected: id == k,
                onTap: () {
                  c.audio.play('ui_tap', volume: 0.3);
                  setState(() => _skill = id);
                },
              ),
            ),
          ),
      ]),
      const SizedBox(height: 10),
      Semantics(
        label: '${s.name}, level ${s.level}',
        child: GameCard(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              VoxelIcon(s.icon, size: 60),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [Expanded(child: Text(s.name, style: EvochiText.section)), Tag('Lv ${s.level}', tone: TagTone.stage)]),
                  const SizedBox(height: 6),
                  SkillBar(value: s.pct, color: Color(s.color), semantic: '${s.name} XP'),
                  const SizedBox(height: 3),
                  Text('${s.maxed ? 'Max level' : '${fmt(s.into)} / ${fmt(s.need)} XP to Lv ${s.level + 1}'} · $countText', style: EvochiText.caption),
                ]),
              ),
            ]),
            const SizedBox(height: 8),
            Text(skillHow[k]!, style: EvochiText.bodyText.copyWith(color: EvochiColor.textSecondary)),
            if (!stOpen && sq != null) ...[
              const SizedBox(height: 10),
              Semantics(
                button: true,
                label: 'Your ${h.stationDefs[station]!.name} opens with the story quest ${sq.title}. ${nextText(sq)}',
                child: GestureDetector(
                  onTap: () => showStoryQuest(context, sq.id),
                  child: ExcludeSemantics(
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: const Color(0xFFE9F4FB), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFBFDDF0), width: 1.5)),
                      child: Row(children: [
                        const VoxelIcon('lock', size: 26),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text.rich(
                            TextSpan(children: [
                              TextSpan(text: 'Your ${h.stationDefs[station]!.name} opens with the story quest '),
                              TextSpan(text: sq.title, style: const TextStyle(fontWeight: FontWeight.w900)),
                              TextSpan(text: '. ${nextText(sq)}'),
                            ]),
                            style: EvochiText.tag,
                          ),
                        ),
                        homeChevron,
                      ]),
                    ),
                  ),
                ),
              ),
            ],
          ]),
        ),
      ),
      const SizedBox(height: 10),
      const SectionHead('Milestones'),
      Stack(children: [
        // the timeline's spine, behind the dots
        Positioned(
          left: 44 + 8 + 9,
          top: 14,
          bottom: 14,
          width: 4,
          child: DecoratedBox(decoration: BoxDecoration(color: const Color(0xFFE2D4C3), borderRadius: BorderRadius.circular(2))),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows),
      ]),
      const Padding(
        padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Text(
          'Each milestone shows what it needs: a skill level, and sometimes a story quest. Side stories are always optional.',
          style: EvochiText.caption,
        ),
      ),
    ]);
  }
}

class _SkillTab extends StatelessWidget {
  const _SkillTab({required this.skill, required this.selected, required this.onTap});
  final h.SkillView skill;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
        selected: selected,
        button: true,
        label: '${skill.name}, level ${skill.level}',
        excludeSemantics: true,
        child: GestureDetector(
          onTap: onTap,
          // the journal's leather bookmark tabs
          child: KitTab(
            selected: selected,
            style: KitTabStyle.leather,
            height: 48,
            radius: BorderRadius.circular(12),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              VoxelIcon(skill.icon, size: 24),
              const SizedBox(width: 3),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(skill.name, style: KitTab.label(EvochiText.tag, selected)),
                ),
              ),
              LvChip('${skill.level}'),
            ]),
          ),
        ),
      );
}

class _MilestoneRow extends StatelessWidget {
  const _MilestoneRow({required this.m, required this.skill, required this.reached, required this.done, required this.next, required this.req, required this.onTap});
  final h.SkillMilestone m;
  final h.SkillView skill;
  final bool reached;
  final bool done;
  final bool next;
  final (String, bool, String)? req;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final r = req;
    final lvColor = done ? EvochiColor.healthy : (next ? EvochiColor.gold900 : EvochiColor.textHelper);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(children: [
        SizedBox(width: 44, child: Text('Lv ${m.level}', textAlign: TextAlign.right, style: EvochiText.tag.copyWith(color: lvColor, fontWeight: FontWeight.w900))),
        const SizedBox(width: 8),
        Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: done ? null : const Color(0xFFFFF9F0),
            gradient: done ? const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFA8D87E), EvochiColor.steps]) : null,
            border: Border.all(color: done ? const Color(0xFF5C9340) : (next ? const Color(0xFFF0B952) : const Color(0xFFD8C3AA)), width: 3),
            boxShadow: next ? const [BoxShadow(color: EvochiColor.gold100, spreadRadius: 3)] : null,
          ),
          child: done ? const Icon(Icons.check_rounded, size: 12, color: EvochiColor.ink) : null,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Semantics(
            button: true,
            label: '${milestoneKind[m.kind]}: ${m.label}. ${done ? 'Unlocked' : 'Locked'}',
            child: GestureDetector(
              onTap: onTap,
              child: ExcludeSemantics(
                child: Opacity(
                  opacity: done || reached ? 1 : 0.85,
                  child: GameCard(
                    highlight: next,
                    padding: const EdgeInsets.all(8),
                    child: Row(children: [
                      SizedBox(width: 40, height: 40, child: Center(child: milestoneImage(m, size: 40, npcForQuest: true))),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Wrap(spacing: 6, runSpacing: 2, crossAxisAlignment: WrapCrossAlignment.center, children: [
                            Text(m.label, style: EvochiText.cardTitle.copyWith(fontSize: 14, fontWeight: FontWeight.w900)),
                            Tag(milestoneKind[m.kind]!, tone: m.kind == 'quest' ? TagTone.stage : TagTone.cream),
                          ]),
                          const SizedBox(height: 4),
                          Wrap(spacing: 6, runSpacing: 4, children: [
                            _Req(ok: reached, icon: 'lock', text: '${skill.name} Lv ${m.level}'),
                            if (r != null) _Req(ok: r.$2, icon: 'journey', text: r.$3),
                          ]),
                        ]),
                      ),
                    ]),
                  ),
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

/// One requirement: a tick when met, otherwise its icon (a lock for levels, a story icon for quests).
class _Req extends StatelessWidget {
  const _Req({required this.ok, required this.icon, required this.text});
  final bool ok;
  final String icon;
  final String text;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(4, 2, 8, 2),
        decoration: BoxDecoration(
          color: ok ? EvochiColor.meadow100 : const Color(0xFFEFE6DB),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: ok ? const Color(0xFFCDE5B0) : const Color(0xFFDCCBB8), width: 1.5),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (ok) const Icon(Icons.check_rounded, size: 14, color: EvochiColor.healthy) else VoxelIcon(icon, size: 14),
          const SizedBox(width: 3),
          Flexible(child: Text(text, style: EvochiText.tag.copyWith(fontSize: 12, color: ok ? EvochiColor.healthy : EvochiColor.textSecondary))),
        ]),
      );
}
