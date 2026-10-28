// S08 Journey: today's steps, sync status, quests and the week (style guide §14-15, §18), plus
// the Trail Guild's daily discoveries (Daily), Village Tales (Story) and the Home Tales skills chart
// (Skills).

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/router.dart';
import '../../app/theme.dart';
import '../../controllers/game_controller.dart';
import '../../core/utils/day_keys.dart';
import '../../game/economy/economy.dart' as econ;
import '../../game/engine.dart' as g;
import '../../game/vitality/vitality.dart';
import '../../game/wilds/wilds.dart' as w;
import '../../game/xp/xp.dart';
import '../caravan/season_screen.dart';
import '../home/skills_screen.dart';
import '../nest/sheets.dart';
import '../settings/settings_screen.dart';
import '../shared/kit.dart';
import '../shared/widgets.dart';
import '../trails/trails_widgets.dart';
import '../village/story_widgets.dart';
import '../wilds/descent_sheet.dart';
import 'chest_reveal.dart';

class JourneyScreen extends StatefulWidget {
  const JourneyScreen({super.key});
  @override
  State<JourneyScreen> createState() => _JourneyScreenState();
}

class _JourneyScreenState extends State<JourneyScreen> {
  final _manual = TextEditingController();

  @override
  void dispose() {
    _manual.dispose();
    super.dispose();
  }

  void _claim(GameController c, String id) {
    final r = c.run((s, n) => g.claimQuest(s, id, n));
    if (!r.ok) return;
    c.analytics.track('quest_claimed', {'quest': id});
    final ev = r.events.where((e) => e.type == 'claimed').toList();
    if (ev.isEmpty) return;
    final data = ev.first.data;
    final rewards = (data['rewards'] as List).cast<Map<String, Object?>>();
    final tier = data['tier'];
    if (tier is String || rewards.any((x) => x['chest'] == true)) {
      // the whole claim plays out of the chest: the quest's coins and the chest's contents together
      showChestReveal(context, tier: tier is String ? tier : 'wood', rewards: rewards);
    }
  }

  /// What's left to do first: the quests ready to claim, then the ones in progress; the claimed ones
  /// fold into one green line (web: questList in journey.js).
  List<Widget> _questList(GameController c, List<g.QuestView> qs, String when) {
    final open = [...qs.where((q) => !q.claimed && q.eligible), ...qs.where((q) => !q.claimed && !q.eligible)];
    final claimed = qs.where((q) => q.claimed).length;
    // the tier today's Daily Goal chest would open as (it climbs with the week's goal days)
    final chest = open.any((q) => q.def.chest) ? econ.chestTierPreview(c.state, c.now) : null;
    return [
      for (final q in open) _QuestRow(q: q, chest: chest, onClaim: () => _claim(c, q.def.id)),
      if (claimed > 0) _ClaimedLine(open.isEmpty ? 'All $claimed claimed $when. Nice walking.' : '$claimed claimed $when'),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<GameController>();
    final v = c.view;
    final conn = c.state.steps.connection;
    final xp = v.todayXp;
    final pct = (v.todaySteps / v.goal).clamp(0.0, 1.0).toDouble();
    final source = switch (conn) {
      'health' => c.health.displayName,
      'demo' => 'Simulated step device',
      'manual' => 'Manual entry',
      _ => 'Not connected',
    };
    final tab = c.journeyTab;
    final Widget today = GameCard(
      padding: const EdgeInsets.all(14),
      child: Column(children: [
        Row(children: [
          SizedBox(
            width: 128,
            height: 128,
            child: Semantics(
              label: '${fmt(v.todaySteps)} of ${fmt(v.goal)} steps',
              child: CustomPaint(
                painter: _RingPainter(pct),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const VoxelIcon('steps', size: 28),
                  Text(fmt(v.todaySteps), style: EvochiText.number.copyWith(fontSize: 22)),
                  Text('of ${fmt(v.goal)}', style: EvochiText.caption),
                ]),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Today', style: EvochiText.cardTitle),
              const SizedBox(height: 4),
              Text('${xp.total} activity XP (${xp.base} base + ${xp.milestones} milestones${xp.stretch > 0 ? ' + ${xp.stretch} stretch' : ''})', style: EvochiText.bodyText),
              const SizedBox(height: 6),
              Wrap(spacing: 4, runSpacing: 4, children: [
                for (final m in c.config.milestones) Tag('${(m.ratio * 100).round()}% +${m.xp}', tone: xp.reached.contains(m.id) ? TagTone.ok : TagTone.cream),
              ]),
              if (v.todayUnverified) const Padding(padding: EdgeInsets.only(top: 6), child: Tag('Includes unverified manual steps', tone: TagTone.warn)),
            ]),
          ),
        ]),
        const Divider(height: 24, color: Color(0x40C49660)),
        Row(children: [
          VoxelIcon(conn == 'none' ? 'warning' : 'steps', size: 28),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(source, style: EvochiText.cardTitle.copyWith(fontSize: 14)),
              Text(
                conn == 'none' ? 'Connect a source to earn from your steps' : 'Last sync ${_ago(c.state.steps.lastSync, c.now)}',
                style: EvochiText.caption,
              ),
            ]),
          ),
          if (conn == 'none')
            EvochiButton(
              label: 'Connect',
              tone: ButtonTone.green,
              small: true,
              expand: false,
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
            )
          else if (conn != 'manual')
            EvochiButton(label: c.syncing ? 'Syncing' : 'Sync', tone: ButtonTone.cream, small: true, expand: false, onPressed: c.syncing ? null : c.sync),
        ]),
      ]),
    );
    final sources = <Widget>[
      // the step simulator is a developer tool (Profile > Developer tools)
      if (conn == 'demo' && c.devTools)
        GameCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Row(children: [Expanded(child: Text('Go for a walk', style: EvochiText.cardTitle)), Tag('Playtest')]),
            const Text('Simulates time-stamped samples from a phone and a watch. Overlapping samples are de-duplicated.', style: EvochiText.caption),
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final n in const [500, 1000, 2500])
                EvochiButton(label: '+${fmt(n)}', tone: ButtonTone.green, small: true, expand: false, onPressed: () => c.simulateWalk(n)),
              EvochiButton(
                label: 'Reach goal',
                small: true,
                expand: false,
                onPressed: v.todaySteps >= v.goal ? null : () => c.simulateWalk(math.max(100, v.goal - v.todaySteps)),
              ),
            ]),
          ]),
        ),
      if (conn == 'manual')
        GameCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Row(children: [Expanded(child: Text('Add steps manually', style: EvochiText.cardTitle)), Tag('Unverified', tone: TagTone.warn)]),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _manual,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(hintText: 'e.g. 1500', filled: true, fillColor: EvochiColor.shell),
                ),
              ),
              const SizedBox(width: 8),
              EvochiButton(
                label: 'Add',
                small: true,
                expand: false,
                onPressed: () {
                  final n = int.tryParse(_manual.text.trim());
                  if (n == null || n <= 0 || n > 60000) {
                    c.toast('Enter a number of steps between 1 and 60,000', icon: 'steps', kind: 'warn');
                    return;
                  }
                  _manual.clear();
                  c.addManualSteps(n);
                },
              ),
            ]),
            const SizedBox(height: 6),
            const Text('Manual steps give XP and keep your Evochi healthy, but never unlock reward chests or cosmetic chances.', style: EvochiText.caption),
          ]),
        ),
    ];
    // an explorer's journal: ruled pages, leather bookmark tabs, entries with a margin rule
    return Scaffold(
      backgroundColor: EvochiColor.panel,
      body: KitPage(
        material: KitMaterial.journal,
        child: CustomScrollView(slivers: [
        SliverToBoxAdapter(
          child: SizedBox(
            height: 150,
            child: Stack(fit: StackFit.expand, children: [
              Image.asset(art.thumb('meadow'), fit: BoxFit.cover, alignment: const Alignment(0, -0.3)),
              const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment(0, 0.3), end: Alignment.bottomCenter, colors: [Color(0x00FBF0DA), Color(0xFFFBF0DA)]))),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const TitleImage('title_journey', height: 44, label: 'Journey'),
                    const Spacer(),
                    CoinPill(balance: v.balance, onPlus: () => showCoinsInfo(context)),
                  ]),
                ),
              ),
            ]),
          ),
        ),
        DecoratedSliver(
          decoration: const RuledPaper(),
          sliver: SliverPadding(
          padding: EdgeInsets.fromLTRB(14, 0, 14, navInset(context) + 12),
          sliver: SliverList.list(children: [
            _JourneyTabs(
              tab: tab,
              dailyDot: v.quests.any((q) => q.def.period == 'day' && q.eligible && !q.claimed) || (c.state.player != null && c.trailsView.ready.isNotEmpty),
              weeklyDot: v.quests.any((q) => q.def.period == 'week' && q.eligible && !q.claimed),
              storyDot: c.storyView.turnIns.isNotEmpty || c.storyView.encounters.isNotEmpty,
              onTab: (t) {
                c.audio.play('ui_tap', volume: 0.3);
                setState(() => c.journeyTab = t);
              },
            ),
            const SizedBox(height: 10),
            if (tab == 'story') ...[
              const StoryTab(),
              const SizedBox(height: 10),
              ...sources,
            ] else if (tab == 'skills') ...[
              const SkillsPanel(),
            ] else ...[
              today,
              const SizedBox(height: 10),
              const SeasonStrip(),
              const SizedBox(height: 10),
              const _WildsCard(),
              const SizedBox(height: 10),
              ...sources,
              const SizedBox(height: 14),
              if (tab == 'daily') ...[
                const _SectionHead("Today's quests"),
                ..._questList(c, v.quests.where((q) => q.def.period == 'day').toList(), 'today'),
                const SizedBox(height: 4),
                const DiscoveriesPanel(),
              ] else ...[
                const _SectionHead('This week'),
                ..._questList(c, v.quests.where((q) => q.def.period == 'week').toList(), 'this week'),
                const SizedBox(height: 4),
                _WeekCard(),
              ],
            ],
          ]),
        ),
        ),
      ]),
      ),
    );
  }
}

String _ago(int? ms, int now) {
  if (ms == null) return 'never';
  final s = ((now - ms) / 1000).round();
  if (s < 45) return 'just now';
  final m = (s / 60).round();
  if (m < 60) return '$m min ago';
  final h = (m / 60).round();
  if (h < 24) return '$h h ago';
  return '${(h / 24).round()} days ago';
}

class _JourneyTabs extends StatelessWidget {
  const _JourneyTabs({required this.tab, required this.dailyDot, required this.weeklyDot, required this.storyDot, required this.onTab});
  final String tab;
  final bool dailyDot;
  final bool weeklyDot;
  final bool storyDot;
  final ValueChanged<String> onTab;
  @override
  Widget build(BuildContext context) {
    final tabs = [
      ('daily', 'Daily', 'steps', dailyDot),
      ('weekly', 'Weekly', 'trophy', weeklyDot),
      ('story', 'Story', 'habitats', storyDot),
      ('skills', 'Skills', 'skill_farming', false),
    ];
    // one label size for the four bookmarks. The row keeps 8 px above it: the header (the sliver
    // before it) paints over anything that pokes above, which cut off the open tab's glow and the dots
    final group = [for (final t in tabs) t.$2];
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(children: [
      for (final t in tabs)
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: Semantics(
              selected: tab == t.$1,
              button: true,
              label: '${t.$1 == 'skills' ? 'Skills' : '${t.$2} quests'}${t.$4 ? ', something ready' : ''}',
              child: GestureDetector(
                onTap: () => onTab(t.$1),
                child: Stack(clipBehavior: Clip.none, children: [
                  // leather bookmark tabs; the open one lifts and lights up
                  KitTab(
                    selected: tab == t.$1,
                    style: KitTabStyle.leather,
                    height: 48,
                    radius: BorderRadius.circular(12),
                    // clear of the plaque's stitched rim, so the longest label never runs into it
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      VoxelIcon(t.$3, size: 20),
                      const SizedBox(width: 3),
                      Flexible(
                        child: KitRowLabel(t.$2, group: group, style: KitTab.label(EvochiText.tag, tab == t.$1)),
                      ),
                    ]),
                  ),
                  if (t.$4) const Positioned(top: -4, right: -4, child: BadgeDot()),
                ]),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

class _SectionHead extends StatelessWidget {
  const _SectionHead(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => KitSectionHead(text, padding: const EdgeInsets.only(bottom: 8));
}

/// "2 claimed today" / "All 3 claimed today. Nice walking." (`.claimed-line`).
class _ClaimedLine extends StatelessWidget {
  const _ClaimedLine(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0x99E5F2CF),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0x7382B75E), width: 1.5),
          ),
          child: Row(children: [
            const Icon(Icons.check_rounded, size: 18, color: EvochiColor.healthy),
            const SizedBox(width: 8),
            Expanded(child: Text(text, style: const TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w800, fontSize: 13.5, color: EvochiColor.healthy))),
          ]),
        ),
      );
}

class _QuestRow extends StatelessWidget {
  const _QuestRow({required this.q, required this.onClaim, this.chest});
  final g.QuestView q;
  final VoidCallback onClaim;
  /// The tier of chest a chest quest opens today ('silver'); null when unknown.
  final String? chest;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Opacity(
          opacity: q.claimed ? 0.72 : 1,
          child: GameCard(
            padding: const EdgeInsets.all(10),
            rule: const Color(0xFFC0634A), // the journal entry's margin rule
            child: Row(children: [
              VoxelIcon(q.def.icon, size: 40),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Flexible(child: Text(q.def.title, style: EvochiText.cardTitle)),
                    // the chest it opens today, as its own little chest (the tier's name for screen readers)
                    if (q.def.chest) ...[
                      const SizedBox(width: 6),
                      Semantics(label: chestTierLabel(chest ?? 'wood'), child: VoxelIcon('chest_${chest ?? 'wood'}', size: 26)),
                    ],
                  ]),
                  Text(q.def.desc, style: EvochiText.caption),
                  const SizedBox(height: 4),
                  ProgressBarX(value: q.progress / q.target, height: 10, tone: 'green'),
                  const SizedBox(height: 2),
                  Text(q.label, style: EvochiText.tiny),
                ]),
              ),
              const SizedBox(width: 8),
              if (q.claimed)
                const Tag('Claimed', tone: TagTone.ok)
              else
                EvochiButton(
                  label: '${q.def.coins}',
                  small: true,
                  expand: false,
                  tone: q.eligible ? ButtonTone.gold : ButtonTone.cream,
                  icon: const VoxelIcon('coin', size: 20),
                  semanticLabel: 'Claim ${q.def.coins} EvoCoins for ${q.def.title}',
                  onPressed: q.eligible ? onClaim : null,
                ),
            ]),
          ),
        ),
      );
}

class _WeekCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final c = context.watch<GameController>();
    final v = c.view;
    final log = {for (final x in v.pet?.vitality.log ?? const <DayResult>[]) x.key: x.kind};
    return GameCard(
      child: Column(children: [
        Row(children: [
          for (final k in weekDays(v.today))
            Expanded(
              child: Builder(builder: (_) {
                final steps = v.days[k]?.steps ?? 0;
                final goal = g.goalFor(c.state, k);
                var bg = const Color(0xFFE7D9C8);
                var mark = '';
                if (k.compareTo(v.today) <= 0) {
                  if (steps >= goal) {
                    bg = EvochiColor.steps;
                    mark = '✓';
                  } else if (isActiveDay(steps, goal)) {
                    bg = EvochiColor.primary;
                    mark = '½';
                  } else if (log[k] == DayKind.rest) {
                    bg = EvochiColor.sky100;
                    mark = 'z';
                  } else if (log[k] == DayKind.low) {
                    bg = const Color(0xFFFBE4E0);
                    mark = '!';
                  }
                }
                final p = k.split('-').map(int.parse).toList();
                const names = ['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su'];
                final dow = DateTime.utc(p[0], p[1], p[2]).weekday - 1;
                return Semantics(
                  label: '$k: ${fmt(steps)} steps',
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      color: k == v.today ? const Color(0xFFFFF6DC) : const Color(0xFFF5E9DA),
                      border: Border.all(color: k == v.today ? const Color(0xFFF2BE55) : const Color(0xFFE8D5BF), width: 1.5),
                    ),
                    child: Column(children: [
                      Text(names[dow], style: EvochiText.tag.copyWith(fontSize: 12)),
                      const SizedBox(height: 3),
                      Container(width: 26, height: 26, decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)), alignment: Alignment.center, child: Text(mark, style: EvochiText.tag)),
                      const SizedBox(height: 3),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(steps == 0 ? '-' : (steps >= 1000 ? '${(steps / 1000).toStringAsFixed(1)}k' : '$steps'), style: EvochiText.tiny),
                      ),
                    ]),
                  ),
                );
              }),
            ),
        ]),
        const SizedBox(height: 8),
        const Wrap(spacing: 6, runSpacing: 6, children: [
          Tag('✓ Goal', tone: TagTone.ok),
          Tag('½ Active', tone: TagTone.stage),
          Tag('z Rest day', tone: TagTone.neutral),
          Tag('! Low', tone: TagTone.danger),
        ]),
      ]),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.pct);
  final double pct;
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2 - 8;
    canvas.drawCircle(c, r, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..color = const Color(0xFFE7D9C8));
    final rect = Rect.fromCircle(center: c, radius: r);
    canvas.drawArc(
      rect,
      -math.pi / 2,
      math.pi * 2 * pct,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 12
        ..strokeCap = StrokeCap.round
        ..shader = const SweepGradient(colors: [Color(0xFFA8D87E), Color(0xFF5FA046)]).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.pct != pct;
}


/// The way into the Lumen Wilds: the entrance asks where to start (the Sunlit Thicket, or the deepest
/// floor of Fernwood Trail you have reached).
class _WildsCard extends StatelessWidget {
  const _WildsCard();

  @override
  Widget build(BuildContext context) {
    final c = context.watch<GameController>();
    final deepest = w.deepestFloor(c.state);
    final calm = w.floorCleared(c.state, 'thicket');
    return GameCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const VoxelIcon('journey', size: 28),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Lumen Wilds', style: EvochiText.cardTitle),
              Text(
                deepest >= 2
                    ? 'Deepest yet: F$deepest, Fernwood Trail'
                    : (calm ? 'The Thicket is calm. Fernwood Trail waits past the old gate.' : 'Calm the Hollow creatures in the Sunlit Thicket.'),
                style: EvochiText.caption,
              ),
            ]),
          ),
        ]),
        const SizedBox(height: 8),
        // one way in, the same as the arch on the Old Trail: from the top, or down to the deepest floor
        EvochiButton(
          label: deepest >= 2 ? 'Enter the Wilds' : 'Enter the Sunlit Thicket',
          tone: ButtonTone.green,
          small: true,
          onPressed: () => enterDescent(context, mine: false),
        ),
      ]),
    );
  }
}
