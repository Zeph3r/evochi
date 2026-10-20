// Home Tales: shared pieces for the Home Map, Garden, Cottage, Kitchen / Apothecary and Skills
// screens. Navigation, quest and skill strips, the quick seed shop, buying a stack of seeds, and the
// Skill-up card. No sixth tab: the Home Map opens from Home ("Explore Home"); Skills also live in
// Journey > Skills and the Cottage. Mirrors the shared bits of web/src/screens/homeland.js.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/router.dart';
import '../../app/theme.dart';
import '../../controllers/game_controller.dart';
import '../../core/models/catalog.dart';
import '../../core/services/asset_manifest.dart';
import '../../core/utils/ids.dart';
import '../../game/engine.dart' as g;
import '../../game/home/home.dart' as h;
import '../../game/story/story.dart' as q;
import '../shared/kit.dart';
import '../shared/widgets.dart';
import '../village/story_widgets.dart';
import '../village/village_screen.dart';
import 'cottage_screen.dart';
import 'garden_screen.dart';
import 'home_map_screen.dart';
import 'skills_screen.dart';
import 'station_screen.dart';
import '../shared/ambience.dart';

HomeArt get homeArt => art.home;

// ---------------------------------------------------------------- navigation ----
void _pushHome(BuildContext context, String name, WidgetBuilder builder) {
  final here = ModalRoute.of(context)?.settings.name;
  if (here == name) return;
  Navigator.of(context).push(MaterialPageRoute<void>(settings: RouteSettings(name: name), builder: builder));
}

void openHomeMap(BuildContext context) => _pushHome(context, 'homemap', (_) => const Ambience('amb_home', child: HomeMapScreen()));
void openGarden(BuildContext context) => _pushHome(context, 'garden', (_) => const Ambience('amb_home', child: GardenScreen()));
void openCottage(BuildContext context) => _pushHome(context, 'cottage', (_) => const Ambience('amb_home', child: CottageScreen()));
void openStation(BuildContext context, String id) =>
    _pushHome(context, 'station:$id', (_) => Ambience(id == 'apothecary' ? 'amb_apothecary' : 'amb_kitchen', child: StationScreen(stationId: id)));
void openSkills(BuildContext context, {String? skill}) => _pushHome(context, 'skills', (_) => SkillsScreen(initial: skill));

/// Navigate to a home destination: garden | cottage | skills | kitchen | apothecary | village | nest
/// (anything else opens the Home Map).
void goHome(BuildContext context, String where) {
  switch (where) {
    case 'kitchen' || 'apothecary':
      openStation(context, where);
    case 'garden':
      openGarden(context);
    case 'cottage':
      openCottage(context);
    case 'skills':
      openSkills(context);
    case 'village':
      openVillage(context);
    case 'nest':
      context.read<GameController>().goTab('home');
    default:
      openHomeMap(context);
  }
}

/// "Go for a walk": the Journey's Daily tab (closes the pushed home screens).
void goWalk(BuildContext context) => context.read<GameController>().goTab('journey', journey: 'daily');

// ------------------------------------------------------------------- labels ----
const skillHow = {
  'farming': 'Harvest crops in your Garden. Slower crops give more XP.',
  'cooking': 'Cook in your Kitchen. A perfect result gives +50% XP.',
  'alchemy': 'Brew in your Apothecary. A perfect result gives +50% XP.',
};

/// "3 Sunberries, 2 Golden Wheat".
String yieldText(Map<String, int> y) => y.entries.map((e) => '${e.value} ${h.itemLabel(e.key, e.value)}').join(', ');

/// What a meal or brew does ("+8 vitality · a treat (Bond +1 once a day)").
String effectText(CatalogItem it) {
  if (it.growth > 0) return 'Speeds up one garden bed by half its growing time';
  return [
    if (it.vitality > 0) '+${it.vitality} vitality',
    if (it.recovery) 'helps an unwell Evochi',
    if (it.treat) 'a treat (Bond +1 once a day)',
  ].join(' · ');
}

/// "2 more Sunberries and 1 more Golden Wheat" for what's still missing.
String missingText(Iterable<(String, int, int)> needs) => needs.map((x) => '${x.$2 - x.$3} more ${h.itemLabel(x.$1, x.$2 - x.$3)}').join(' and ');

/// "3 × Sunberry Seeds" for gift and reward chips.
String countLabel(String id, int n) => '$n × ${item(id).name}';

/// "20 min", "1 h 30 min".
String durationText(int ms) {
  final m = ms <= 0 ? 0 : (ms / 60000).ceil();
  if (m < 60) return '$m min';
  return '${m ~/ 60} h ${m % 60} min';
}

Color skillColor(String skill) => Color(h.skillDefs[skill]!.color);

// ------------------------------------------------------------- small widgets ----
const homeChevron = Text('›', style: TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w900, fontSize: 24, color: EvochiColor.textHelper));

/// A section head: a leaf, the title, an optional [trailing] chip, then a stitched rule to the end of the
/// line (and an optional [end] after it).
class SectionHead extends StatelessWidget {
  const SectionHead(this.text, {super.key, this.trailing, this.end});
  final String text;
  final Widget? trailing;
  final Widget? end;
  @override
  Widget build(BuildContext context) => KitSectionHead(text, trailing: trailing, end: end);
}

/// A card that opens something (strips, rows).
class TapCard extends StatelessWidget {
  const TapCard({super.key, required this.child, required this.onTap, required this.label, this.padding = const EdgeInsets.all(12), this.color, this.highlight = false});
  final Widget child;
  final VoidCallback onTap;
  final String label;
  final EdgeInsets padding;
  final Color? color;
  final bool highlight;
  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: label,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            context.read<GameController>().audio.play('ui_tap', volume: 0.4);
            onTap();
          },
          child: ExcludeSemantics(child: GameCard(padding: padding, color: color, highlight: highlight, child: child)),
        ),
      );
}

/// "Lv 3" in a little gold chip.
class LvChip extends StatelessWidget {
  const LvChip(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(left: 4),
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(color: EvochiColor.gold100, borderRadius: BorderRadius.circular(7), border: Border.all(color: EvochiColor.primary, width: 1.5)),
        child: Text(text, style: EvochiText.tag.copyWith(color: EvochiColor.gold900, fontSize: 12, fontWeight: FontWeight.w900)),
      );
}

/// A progress bar in a skill's colour.
class SkillBar extends StatelessWidget {
  const SkillBar({super.key, required this.value, required this.color, this.height = 11, this.semantic});
  final double value;
  final Color color;
  final double height;
  final String? semantic;
  @override
  Widget build(BuildContext context) {
    final v = value.isNaN ? 0.0 : value.clamp(0.0, 1.0).toDouble();
    // the kit's carved groove, filled in the skill's colour
    return Semantics(
      label: semantic,
      value: '${(v * 100).round()}%',
      child: Container(
        height: height,
        decoration: Kit.groove(height / 2),
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: v,
          heightFactor: 1,
          child: Container(decoration: Kit.barFill([Color.lerp(color, Colors.white, 0.35)!, color], height / 2)),
        ),
      ),
    );
  }
}

/// The gold title banner on reward cards ("Quest complete!", "Welcome home!").
class GoldBanner extends StatelessWidget {
  const GoldBanner(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: EvochiColor.primaryShadow, width: 2),
            gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [EvochiColor.gold100, EvochiColor.primary]),
            boxShadow: const [BoxShadow(color: EvochiColor.primaryShadow, offset: Offset(0, 3))],
          ),
          child: Text(text, textAlign: TextAlign.center, style: EvochiText.section.copyWith(fontSize: 20, fontWeight: FontWeight.w900)),
        ),
      );
}

/// A skill strip: icon, level, XP bar. Opens the Skills chart on that skill.
class SkillStrip extends StatelessWidget {
  const SkillStrip(this.skill, {super.key});
  final String skill;
  @override
  Widget build(BuildContext context) {
    final c = context.watch<GameController>();
    final s = h.skillView(c.state, skill);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TapCard(
        label: '${s.name} level ${s.level}. Open Skills',
        padding: const EdgeInsets.fromLTRB(9, 9, 12, 9),
        onTap: () => openSkills(context, skill: skill),
        child: Row(children: [
          VoxelIcon(s.icon, size: 42),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(s.name, style: EvochiText.cardTitle),
                LvChip('Lv ${s.level}'),
                const Spacer(),
                Text(s.maxed ? 'Max level' : '${fmt(s.into)} / ${fmt(s.need)} XP', style: EvochiText.caption),
              ]),
              const SizedBox(height: 5),
              SkillBar(value: s.pct, color: Color(s.color)),
            ]),
          ),
          const SizedBox(width: 6),
          homeChevron,
        ]),
      ),
    );
  }
}

/// The Home Tales quest worth showing on the Home Map: a ready hand-in first, then what's in progress.
q.StoryQuestView? homeQuestFor(q.StoryStatus st) {
  final list = [...st.home, ...st.side];
  return list.where((v) => v.accepted && !v.completed && v.next.kind == 'handin').firstOrNull ??
      st.home.where((v) => v.accepted && !v.completed).firstOrNull ??
      st.home.where((v) => v.phase == 'available').firstOrNull ??
      st.side.where((v) => v.accepted && !v.completed).firstOrNull ??
      st.home.where((v) => v.phase == 'locked').firstOrNull;
}

/// A quest summary row (face, title, what's next, progress) that opens the quest card.
class HomeQuestStrip extends StatelessWidget {
  const HomeQuestStrip({super.key, required this.v, this.lead});
  final q.StoryQuestView v;
  final String? lead;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: TapCard(
          label: '${v.title}. ${nextText(v)}',
          padding: const EdgeInsets.fromLTRB(8, 10, 12, 10),
          onTap: () => showStoryQuest(context, v.id),
          child: Row(children: [
            SizedBox(width: 54, height: 60, child: NpcImage(v.giver, expression: v.next.kind == 'handin' ? 'happy' : 'neutral', height: 60)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(lead ?? (v.line == 'side' ? 'Side story · optional' : 'Home Tales'), style: EvochiText.caption),
                Text(v.title, style: EvochiText.cardTitle),
                Text(nextText(v), style: EvochiText.bodyText.copyWith(color: EvochiColor.textSecondary)),
                if (v.accepted && !v.completed) Padding(padding: const EdgeInsets.only(top: 6), child: WalkProgress(v)),
              ]),
            ),
            homeChevron,
          ]),
        ),
      );
}

/// A small tile with an item and a count ("x3"), for gifts and rewards.
class ItemCountChip extends StatelessWidget {
  const ItemCountChip({super.key, required this.id, required this.label});
  final String id;
  final String label;
  @override
  Widget build(BuildContext context) => Container(
        height: 36,
        padding: const EdgeInsets.only(left: 4, right: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFE8B956), width: 1.5),
          gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFFFF6DA), Color(0xFFFFE7A8)]),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [ItemImage(id, size: 30), const SizedBox(width: 4), Text(label, style: EvochiText.tag.copyWith(color: EvochiColor.ink))]),
      );
}

// --------------------------------------------------------------- buying seeds ----
/// Buy [n] of a stackable item in one go (each unit is its own idempotent purchase).
g.ActionResult buyMany(GameController c, String id, int n, String requestId) => c.run((s, now) {
      var st = s;
      final events = <g.GameEvent>[];
      for (var i = 0; i < n; i++) {
        final r = g.purchase(st, id, '$requestId:$i', now);
        if (!r.ok) return i > 0 ? g.ActionResult(st, events: events) : r;
        st = r.state;
        events.addAll(r.events);
      }
      return g.ActionResult(st, events: events);
    });

/// x1 / x3 / x5 with their prices; options the player can't afford are disabled.
class QtyPick extends StatelessWidget {
  const QtyPick({super.key, required this.price, required this.balance, required this.value, required this.onChanged});
  final int price;
  final int balance;
  final int value;
  final ValueChanged<int> onChanged;
  @override
  Widget build(BuildContext context) => Semantics(
        label: 'How many',
        child: Row(children: [
          for (final n in const [1, 3, 5])
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Builder(builder: (_) {
                  final can = balance >= price * n;
                  final on = value == n;
                  return Semantics(
                    selected: on,
                    button: true,
                    enabled: can,
                    label: '$n for ${fmt(price * n)} EvoCoins',
                    child: GestureDetector(
                      onTap: can ? () => onChanged(n) : null,
                      child: Opacity(
                        opacity: can ? 1 : 0.45,
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                          decoration: Kit.slot(selected: on, radius: 12),
                          child: ExcludeSemantics(
                            child: Column(mainAxisSize: MainAxisSize.min, children: [
                              Text('x$n', style: EvochiText.button.copyWith(fontSize: 17)),
                              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                                const VoxelIcon('coin', size: 15),
                                const SizedBox(width: 3),
                                Text(fmt(price * n), style: EvochiText.tag.copyWith(fontSize: 12)),
                              ]),
                            ]),
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
        ]),
      );
}

/// The Garden's quick seed shop: buy 1, 3 or 5 without leaving the bed.
Future<void> openSeedShop(BuildContext context, String seed, {VoidCallback? after}) {
  final c = context.read<GameController>();
  var n = 3;
  var requestId = newId('seeds');
  return showEvochiDialog<void>(context, builder: (d) => StatefulBuilder(builder: (d, set) {
        final it = item(seed);
        final bal = d.watch<GameController>().balance;
        bool can(int k) => bal >= it.price * k;
        if (!can(n)) n = can(3) ? 3 : 1;
        return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Center(child: ItemImage(seed, size: 96)),
          Text(it.name, style: EvochiText.section, textAlign: TextAlign.center),
          const SizedBox(height: 4),
          Text(it.desc, style: EvochiText.caption, textAlign: TextAlign.center),
          const SizedBox(height: 10),
          QtyPick(price: it.price, balance: bal, value: n, onChanged: (k) => set(() => n = k)),
          const SizedBox(height: 12),
          EvochiButton(
            label: 'Buy $n for ${fmt(it.price * n)}',
            tone: ButtonTone.green,
            icon: const VoxelIcon('coin', size: 22),
            onPressed: can(n)
                ? () {
                    final r = buyMany(c, seed, n, requestId);
                    if (!r.ok) return;
                    requestId = newId('seeds');
                    Navigator.pop(d);
                    c.toast('+$n ${h.itemLabel(seed, n)}', icon: 'item:$seed');
                    c.analytics.track('item_purchased', {'item': seed, 'qty': n});
                    after?.call();
                  }
                : null,
          ),
          if (!can(1)) ...[
            const SizedBox(height: 6),
            Text('You need ${fmt(it.price - bal)} more EvoCoins. Journey quests pay out every day.',
                textAlign: TextAlign.center, style: EvochiText.caption.copyWith(color: EvochiColor.gold900)),
          ],
          const SizedBox(height: 8),
          EvochiButton(label: 'Not now', tone: ButtonTone.cream, onPressed: () => Navigator.pop(d)),
        ]);
      }));
}

// --------------------------------------------------------------- skill-ups ----
/// A milestone's picture: the crop or dish, the farming icon for a bed, a story icon for a quest.
Widget milestoneImage(h.SkillMilestone m, {double size = 40, bool npcForQuest = false}) {
  switch (m.kind) {
    case 'crop' || 'recipe':
      return ItemImage(m.id, size: size);
    case 'plot':
      return VoxelIcon('skill_farming', size: size);
    default:
      return npcForQuest ? NpcImage(q.storyQuests[m.id]!.giver, expression: 'happy', height: size) : VoxelIcon('journey', size: size);
  }
}

const milestoneKind = {'crop': 'New crop', 'plot': 'New bed', 'recipe': 'Recipe', 'quest': 'Story'};

/// "Farming Lv 2!" with what the new level opens.
Future<void> showSkillUp(BuildContext context, String skill, int level, List<h.SkillMilestone> unlocks) {
  final s = h.skillDefs[skill]!;
  return showEvochiDialog<void>(context, builder: (d) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Center(child: VoxelIcon(s.icon, size: 92)),
        const SizedBox(height: 6),
        GoldBanner('${s.name} Lv $level!'),
        const SizedBox(height: 12),
        if (unlocks.isEmpty)
          const Text('Keep going: the next unlock is on your Skills chart.', style: EvochiText.bodyText, textAlign: TextAlign.center)
        else
          for (final m in unlocks)
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: Kit.inset(),
              child: Row(children: [
                milestoneImage(m),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(m.kind == 'recipe' ? 'New recipe' : milestoneKind[m.kind]!, style: EvochiText.caption),
                    Text(m.label, style: EvochiText.cardTitle.copyWith(fontSize: 14)),
                  ]),
                ),
              ]),
            ),
        const SizedBox(height: 8),
        EvochiButton(label: 'Wonderful!', onPressed: () => Navigator.pop(d)),
      ]));
}

/// Shows the Skill-up card whenever an action levels a Cozy Skill (wraps the app, like ToastListener).
class SkillUpListener extends StatefulWidget {
  const SkillUpListener({super.key, required this.child});
  final Widget child;
  @override
  State<SkillUpListener> createState() => _SkillUpListenerState();
}

class _SkillUpListenerState extends State<SkillUpListener> {
  StreamSubscription<g.GameEvent>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = context.read<GameController>().events.listen((e) {
      if (e.type != 'skill_up' || !mounted) return;
      final ctx = rootNavigatorKey.currentContext;
      if (ctx == null) return;
      final unlocks = (e.data['unlocks'] as List? ?? const []).whereType<h.SkillMilestone>().toList();
      showSkillUp(ctx, e.data['skill'] as String, e.data['level'] as int, unlocks);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
