// Village Tales: shared story UI. Quest details, the reward cards (story items, or Home Tales gifts
// and unlocks), the Journey > Story tab (Chapter 1, Home Tales, side stories), the Bag > Quest Pouch
// and the Home story chip (Quest Bible §8). Mirrors web/src/screens/village.js.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../controllers/game_controller.dart';
import '../../core/models/catalog.dart';
import '../../core/services/asset_manifest.dart';
import '../../game/engine.dart' as g;
import '../../game/home/home.dart' as h;
import '../../game/story/story.dart' as q;
import '../home/home_widgets.dart';
import '../pet/pet_screens.dart';
import '../shared/widgets.dart';
import 'village_screen.dart';

VillageArt get villageArt => art.village;

class Speaker {
  const Speaker(this.name, this.role, this.color);
  final String name;
  final String role;
  final Color color;
}

const speakers = <String, Speaker>{
  'npc_mira': Speaker('Mira', 'the Gardener', Color(0xFF5E7F4A)),
  'npc_bram': Speaker('Bram', 'the Lanternkeeper', Color(0xFF8D5D3B)),
  'npc_pip': Speaker('Pip', 'the Courier', Color(0xFFAD652F)),
  'npc_alder': Speaker('Alder', 'the Mapmaker', Color(0xFF43523D)),
  'waystone': Speaker('The Waystone', '', Color(0xFF6E8A7E)),
};

String npcLabel(String id) => id == 'waystone' ? 'the Waystone' : (id == 'cottage' ? 'your Cottage' : q.npcs[id]!.name);

const _unlockIcon = {'Cottage': 'home_map', 'Kitchen': 'skill_cooking', 'Apothecary': 'skill_alchemy'};

/// "Village Tales, Chapter 1 · Quest 01", "Home Tales · Quest 01" or "Side story · optional".
String questLead(q.StoryQuestView v) {
  final n = v.n.toString().padLeft(2, '0');
  if (v.line == 'home') return 'Home Tales · Quest $n';
  if (v.line == 'side') return 'Side story · optional';
  return '${q.chapterName} · Quest $n';
}

/// "Grow 3 Sunberries (1/3)" for the items still missing from a hand-in.
String _gatherText(List<q.ItemNeed> needs) => needs.where((x) => !x.ok).map((x) {
      final src = h.homeSource(x.id);
      return '${src?.verb ?? 'Find'} ${x.need} ${h.itemLabel(x.id, x.need)} (${x.have}/${x.need})';
    }).join(', ');

/// A villager's sprite (they face right, toward the player; [flip] mirrors one to face left).
class NpcImage extends StatelessWidget {
  const NpcImage(this.npcId, {super.key, this.expression = 'neutral', this.height = 60, this.flip = false});
  final String npcId;
  final String expression;
  final double height;
  final bool flip;
  @override
  Widget build(BuildContext context) {
    final classic = context.select<GameController, bool>((c) => c.state.player?.settings.classicVillagers ?? false);
    final img = Image.asset(villageArt.npc(npcId, expression, classic), height: height, fit: BoxFit.contain, excludeFromSemantics: true, filterQuality: FilterQuality.medium);
    return flip ? Transform.flip(flipX: true, child: img) : img;
  }
}

/// One line for "what to do next" on a quest.
String nextText(q.StoryQuestView v) {
  final n = v.next;
  if (v.completed) return 'Complete';
  if (v.phase == 'locked') return v.lock?.text ?? 'Locked';
  switch (n.kind) {
    case 'talk':
      return 'Talk to ${npcLabel(n.npc!)} in ${q.places[n.place]!.name}';
    case 'walk':
      if (v.paused) return 'Waiting for steps: connect a step source to keep going';
      if (v.walk.type == 'incremental') return 'Walk ${fmt(v.resolved - v.walk.progress)} more steps';
      return v.walk.todayDone
          ? 'Day ${v.walk.qualified}/${v.walk.days} done. Walk again tomorrow'
          : 'Walk ${fmt(v.resolved)} steps today (day ${v.walk.qualified + 1} of ${v.walk.days})';
    case 'gather':
      return _gatherText(n.needs);
    case 'grow':
      return 'Visit once your Evochi has grown into a ${stageLabel(n.stage)}';
    case 'handin':
      if (n.npc == 'waystone') return 'Restore the Waystone in the Square';
      if (n.npc == 'cottage') return 'Restore the Cottage on your Home Map';
      final label = n.label ?? '';
      if (label.contains(' to ')) return label;
      return RegExp(r'^(Give|Bring|Hand)').hasMatch(label) ? '$label to ${npcLabel(n.npc!)}' : label;
  }
  return '';
}

Widget storyStatusTag(q.StoryQuestView v) {
  if (v.completed) return const Tag('Complete', tone: TagTone.ok);
  if (v.phase == 'locked') return Tag('Lv ${v.level}', tone: TagTone.neutral, icon: 'lock');
  if (v.phase == 'available') return const Tag('New', tone: TagTone.stage);
  if (v.next.kind == 'handin') return const Tag('Ready', tone: TagTone.ok);
  if (v.next.kind == 'grow') return const Tag('Needs a Juvenile', tone: TagTone.warn);
  if (v.paused) return const Tag('Paused', tone: TagTone.warn);
  return const Tag('In progress');
}

/// Walking progress: a bar for single walks, day markers plus today's bar for multi-day walks. Once
/// the walk is done (or for quests without one), a small counter per item still needed.
class WalkProgress extends StatelessWidget {
  const WalkProgress(this.v, {super.key});
  final q.StoryQuestView v;
  @override
  Widget build(BuildContext context) {
    if (!v.accepted || v.completed) return const SizedBox.shrink();
    if (!v.hasWalk || v.next.kind != 'walk') {
      // item objectives (harvests, homemade food): one small counter per item still needed
      final its = v.objectives.where((o) => o.item != null && !o.done).toList();
      if (its.isEmpty) return const SizedBox.shrink();
      return Wrap(spacing: 10, runSpacing: 6, children: [
        for (final o in its)
          Semantics(
            label: '${item(o.item!).name}: ${o.have} of ${o.need}',
            child: ExcludeSemantics(
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                ItemImage(o.item!, size: 26),
                const SizedBox(width: 4),
                SizedBox(width: 56, child: ProgressBarX(value: o.need == 0 ? 1 : o.have / o.need, height: 8, tone: o.ready ? 'green' : 'amber')),
                const SizedBox(width: 4),
                Text('${o.have}/${o.need}', style: EvochiText.tag.copyWith(fontSize: 12, color: o.ready ? EvochiColor.healthy : EvochiColor.textSecondary)),
              ]),
            ),
          ),
      ]);
    }
    final w = v.walk;
    if (w.type == 'incremental') {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ProgressBarX(value: w.progress / v.resolved, height: 10, tone: 'green', semantic: 'Story walk'),
        const SizedBox(height: 3),
        Text('${fmt(w.progress)} / ${fmt(v.resolved)} new steps', style: EvochiText.caption.copyWith(fontSize: 12)),
      ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Semantics(
        label: '${w.qualified} of ${w.days} walking days',
        child: Row(children: [
          for (var i = 0; i < w.days; i++)
            Container(
              width: 28,
              height: 28,
              margin: const EdgeInsets.only(right: 6),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: i < w.qualified ? null : const Color(0xFFE7D9C8),
                gradient: i < w.qualified ? const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFA8D87E), EvochiColor.steps]) : null,
              ),
              child: i < w.qualified
                  ? const Icon(Icons.check_rounded, size: 16, color: EvochiColor.ink)
                  : Text('${i + 1}', style: EvochiText.tag.copyWith(color: EvochiColor.textHelper)),
            ),
        ]),
      ),
      if (w.qualified < w.days) ...[
        const SizedBox(height: 6),
        ProgressBarX(value: w.todayDone ? 1 : w.todaySteps / v.resolved, height: 10, tone: 'green'),
        const SizedBox(height: 3),
        Text('Today: ${fmt(w.todayDone ? v.resolved : w.todaySteps)} / ${fmt(v.resolved)} steps${w.todayDone ? ' ✓' : ''}', style: EvochiText.caption.copyWith(fontSize: 12)),
      ],
    ]);
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.image, required this.label, this.story = false});
  final Widget image;
  final String label;
  final bool story;
  @override
  Widget build(BuildContext context) => Container(
        height: 36,
        padding: const EdgeInsets.only(left: 4, right: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: story ? const Color(0xFFE8B956) : const Color(0xFFE5D3BE), width: 1.5),
          color: story ? null : const Color(0xFFF6EBDD),
          gradient: story ? const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFFFF6DA), Color(0xFFFFE7A8)]) : null,
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [image, const SizedBox(width: 4), Text(label, style: EvochiText.tag.copyWith(color: EvochiColor.ink))]),
      );
}

class RewardChips extends StatelessWidget {
  const RewardChips(this.r, {super.key});
  final q.StoryRewards r;
  @override
  Widget build(BuildContext context) => Wrap(spacing: 6, runSpacing: 6, children: [
        for (final id in r.items) _Chip(image: ItemImage(id, size: 30), label: item(id).name, story: true),
        if (r.coins > 0) _Chip(image: const VoxelIcon('coin', size: 30), label: '${r.coins}'),
        for (final e in r.gifts.entries) _Chip(image: ItemImage(e.key, size: 30), label: '${e.value} × ${item(e.key).name}'),
        for (final u in r.unlocks) _Chip(image: VoxelIcon(_unlockIcon[u] ?? 'star', size: 30), label: 'Unlocks $u', story: true),
        for (final t in r.titles) _Chip(image: const VoxelIcon('crown', size: 30), label: 'Title: ${q.titles[t]}'),
      ]);
}

/// The gold "Story reward" label used on reward cards and item details.
class StoryRewardTag extends StatelessWidget {
  const StoryRewardTag({super.key, this.small = false});
  final bool small;
  @override
  Widget build(BuildContext context) => Container(
        height: small ? 24 : 26,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: const Color(0xFFE8B956), width: 2),
          color: small ? null : const Color(0xFFFFF9F0),
          gradient: small ? const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFFFF6DA), Color(0xFFFFE7A8)]) : null,
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const VoxelIcon('star', size: 16),
          const SizedBox(width: 4),
          Text(small ? 'Story reward' : 'STORY REWARD', style: EvochiText.tag.copyWith(color: EvochiColor.gold900, fontSize: 12, letterSpacing: small ? 0 : 0.4)),
        ]),
      );
}

// ---------------------------------------------------------------- quest details (sheet) ----
Future<void> showStoryQuest(BuildContext context, String qid) {
  final c = context.read<GameController>();
  c.run((s, n) => q.markOfferSeen(s, qid), quiet: true);
  return showEvochiSheet<void>(context, builder: (sheet) {
    final c = sheet.watch<GameController>();
    final v = q.questView(c.state, qid, c.now);
    final go = v.completed ? null : _questGo(context, sheet, c, v);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Center(child: Container(width: 44, height: 5, margin: const EdgeInsets.only(bottom: 12), decoration: BoxDecoration(color: const Color(0xFFDCC6AE), borderRadius: BorderRadius.circular(3)))),
      Row(children: [
        NpcImage(v.giver, expression: v.completed ? 'happy' : 'neutral', height: 72),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(questLead(v), style: EvochiText.caption),
            Semantics(header: true, child: Text(v.title, style: EvochiText.section)),
            const SizedBox(height: 4),
            Wrap(spacing: 6, runSpacing: 4, children: [Tag('Lv ${v.level}+'), storyStatusTag(v)]),
          ]),
        ),
      ]),
      const SizedBox(height: 10),
      Text(v.summary, style: EvochiText.bodyText),
      if (v.paused) ...[
        const SizedBox(height: 10),
        const GameCard(
          color: Color(0xFFE9F4FB),
          padding: EdgeInsets.all(10),
          child: Row(children: [
            VoxelIcon('steps', size: 26),
            SizedBox(width: 8),
            Expanded(child: Text('Step sync is off, so this walk is paused. Your progress is saved and nothing expires.', style: EvochiText.tag)),
          ]),
        ),
      ],
      if (v.accepted && !v.completed) ...[
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: EvochiColor.inset, borderRadius: BorderRadius.circular(12)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Next: ${nextText(v)}', style: EvochiText.cardTitle.copyWith(fontSize: 14)),
            const SizedBox(height: 6),
            WalkProgress(v),
          ]),
        ),
      ],
      const SizedBox(height: 12),
      for (final o in v.objectives) _ObjectiveRow(o: o, now: v.accepted && o.id == v.current),
      const SizedBox(height: 10),
      const Text('Rewards', style: EvochiText.cardTitle),
      const SizedBox(height: 6),
      RewardChips(v.rewards),
      const SizedBox(height: 6),
      const Text("Story rewards are earned, never sold: they can't be bought, traded or sold.", style: EvochiText.caption),
      if (v.accepted && !v.completed)
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Track on Home', style: EvochiText.cardTitle),
          value: v.tracked,
          activeTrackColor: EvochiColor.steps,
          onChanged: (on) => c.run((s, n) => q.setTracked(s, qid, on)),
        ),
      const SizedBox(height: 8),
      if (go != null) ...[go, const SizedBox(height: 8)],
      EvochiButton(label: 'Close', tone: ButtonTone.cream, onPressed: () => Navigator.pop(sheet)),
    ]);
  });
}

/// The quest card's main button: where to go next (a walk, your Garden or Kitchen, a villager...).
Widget? _questGo(BuildContext context, BuildContext sheet, GameController c, q.StoryQuestView v) {
  final n = v.next;
  Widget button(String label, VoidCallback go, {ButtonTone tone = ButtonTone.gold}) => EvochiButton(
        label: label,
        tone: tone,
        onPressed: () {
          Navigator.pop(sheet);
          go();
        },
      );
  if (n.kind == 'walk') return button('Go for a walk', () => c.goTab('journey', journey: 'daily'), tone: ButtonTone.green);
  if (n.kind == 'gather') {
    final miss = n.needs.where((x) => !x.ok).firstOrNull;
    final src = miss == null ? null : h.homeSource(miss.id);
    if (src != null) {
      final where = src.route == 'station' ? src.station! : 'garden';
      return button('Go to your ${src.place}', () => goHome(context, where), tone: ButtonTone.green);
    }
  }
  if (n.kind == 'grow') {
    return button('Check on your Evochi', () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const PetDetailsScreen())), tone: ButtonTone.cream);
  }
  if (n.place == 'cottage') return button('Go to your Cottage', () => goHome(context, 'cottage'));
  if (v.phase == 'locked' && (v.lock?.needSkills.isNotEmpty ?? false)) return button('Open Skills', () => goHome(context, 'skills'), tone: ButtonTone.cream);
  if (const {'talk', 'handin', 'locked', 'gather', 'grow'}.contains(n.kind)) {
    final place = q.places[n.place];
    return button('Go to ${place?.name ?? 'the Village'}', () {
      if (place != null) {
        openPlace(context, place.id, npc: n.npc != null && n.npc != 'waystone' ? n.npc : null);
      } else {
        openVillage(context);
      }
    });
  }
  return null;
}

class _ObjectiveRow extends StatelessWidget {
  const _ObjectiveRow({required this.o, required this.now});
  final q.ObjectiveView o;
  final bool now;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Semantics(
          label: '${o.text}${o.done ? ', done' : ''}',
          child: ExcludeSemantics(
            child: Row(children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: o.done ? const Color(0xFF5C9340) : (now ? const Color(0xFFF0B952) : const Color(0xFFD8C3AA)), width: 2),
                  color: o.done ? EvochiColor.steps : EvochiColor.canvas,
                  boxShadow: now ? const [BoxShadow(color: EvochiColor.gold100, spreadRadius: 2)] : null,
                ),
                child: o.done ? const Icon(Icons.check_rounded, size: 16, color: EvochiColor.ink) : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  o.text,
                  style: EvochiText.bodyText.copyWith(
                    fontWeight: now ? FontWeight.w900 : FontWeight.w700,
                    color: o.done ? EvochiColor.textHelper : (now ? EvochiColor.ink : EvochiColor.textSecondary),
                    decoration: o.done ? TextDecoration.lineThrough : null,
                  ),
                ),
              ),
            ]),
          ),
        ),
      );
}

// ------------------------------------------------------------------- reward card ----
/// "Quest complete!" with the story reward, Equip now / Place in Nest, then back to the Village.
/// Quests that pay out gifts and unlocks instead (Home Tales, side stories) get [_homeRewardCard].
Future<void> showStoryReward(BuildContext context, String qid, {bool backToVillage = true}) async {
  final c = context.read<GameController>();
  final quest = q.storyQuests[qid]!;
  c.run((s, n) => q.markCompletionSeen(s, qid), quiet: true);
  c.audio.play('reward_chime');
  if (quest.rewards.items.isEmpty) {
    await _homeRewardCard(context, quest, backToVillage: backToVillage);
    return;
  }
  final id = quest.rewards.items.first;
  final it = item(id);
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierColor: const Color(0x8C201B17),
    builder: (d) => Dialog(
      backgroundColor: EvochiColor.canvas,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: SingleChildScrollView(
          child: Builder(builder: (d) {
            final c = d.watch<GameController>();
            final s = c.state;
            final compact = MediaQuery.of(d).size.height < 700;
            final equipped = it.category == ItemCategory.wearable && s.pet?.equipped[it.slot] == id;
            final placed = it.category == ItemCategory.decoration && s.placements.values.contains(id);
            return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Center(
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 22, vertical: compact ? 4 : 6),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: EvochiColor.primaryShadow, width: 2),
                    gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [EvochiColor.gold100, EvochiColor.primary]),
                    boxShadow: const [BoxShadow(color: EvochiColor.primaryShadow, offset: Offset(0, 3))],
                  ),
                  child: Text('Quest complete!', style: EvochiText.section.copyWith(fontSize: compact ? 17 : 20, fontWeight: FontWeight.w900)),
                ),
              ),
              const SizedBox(height: 8),
              Text(questLead(q.questView(s, qid, c.now)), style: EvochiText.caption, textAlign: TextAlign.center),
              Text(quest.title, style: EvochiText.section, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              Stack(clipBehavior: Clip.none, alignment: Alignment.topCenter, children: [
                Container(
                  padding: EdgeInsets.fromLTRB(14, compact ? 16 : 20, 14, 14),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFFE8B956), width: 3),
                    gradient: const RadialGradient(center: Alignment(0, -0.3), radius: 0.9, colors: [Color(0xFFFFF6DA), Color(0xFFFFF9F0)]),
                    boxShadow: const [BoxShadow(color: Color(0xFFFFF1C9), spreadRadius: 4), BoxShadow(color: Color(0xFFD9A84A), offset: Offset(0, 4))],
                  ),
                  child: Column(children: [
                    ItemImage(id, size: compact ? 96 : 132),
                    Text(it.name, style: EvochiText.cardTitle),
                    const SizedBox(height: 4),
                    Text(it.desc, style: EvochiText.bodyText.copyWith(color: EvochiColor.textSecondary, fontSize: 14), textAlign: TextAlign.center),
                  ]),
                ),
                const Positioned(top: -13, child: StoryRewardTag()),
              ]),
              const SizedBox(height: 12),
              Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: [
                Tag('+${quest.rewards.coins}', tone: TagTone.stage, icon: 'coin'),
                for (final t in quest.rewards.titles) Tag('Title: ${q.titles[t]}', tone: TagTone.ok, icon: 'crown'),
              ]),
              const SizedBox(height: 12),
              if (it.category == ItemCategory.wearable)
                EvochiButton(
                  label: equipped ? 'Equipped' : 'Equip now',
                  onPressed: equipped || s.pet == null
                      ? null
                      : () {
                          if (c.run((st, n) => g.equip(st, id, n)).ok) {
                            c.audio.play('reward_chime', volume: 0.5);
                            c.toast('${it.name} equipped', icon: 'wearables');
                          }
                        },
                )
              else
                EvochiButton(
                  label: placed ? 'Placed in your Nest' : 'Place in Nest',
                  onPressed: placed
                      ? null
                      : () {
                          final slots = decorSlots.values.where((x) => x.accepts == it.decor).toList();
                          final slot = slots.where((x) => s.placements[x.id] == null).firstOrNull ?? slots.first;
                          if (c.run((st, n) => g.placeDecoration(st, id, slot.id)).ok) {
                            c.audio.play('ui_tap');
                            c.toast('${it.name} placed in the ${slot.label.toLowerCase()} spot', icon: 'decorations');
                          }
                        },
                ),
              const SizedBox(height: 8),
              EvochiButton(label: backToVillage ? 'Back to Village' : 'Done', tone: ButtonTone.cream, onPressed: () => Navigator.pop(d)),
            ]);
          }),
        ),
      ),
    ),
  );
  if (backToVillage && context.mounted) returnToVillage(context);
}

/// Reward card for quests that pay out gifts, unlocks and titles instead of one story item.
Future<void> _homeRewardCard(BuildContext context, q.StoryQuest quest, {required bool backToVillage}) async {
  final r = quest.rewards;
  final room = r.unlocks.contains('Apothecary') ? 'apothecary' : (r.unlocks.contains('Kitchen') ? 'kitchen' : null);
  String? goTo;
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierColor: const Color(0x8C201B17),
    builder: (d) => Dialog(
      backgroundColor: EvochiColor.canvas,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: SingleChildScrollView(
          child: Builder(builder: (d) {
            final c = d.watch<GameController>();
            return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const GoldBanner('Quest complete!'),
              const SizedBox(height: 8),
              Text(questLead(q.questView(c.state, quest.id, c.now)), style: EvochiText.caption, textAlign: TextAlign.center),
              Text(quest.title, style: EvochiText.section, textAlign: TextAlign.center),
              if (r.unlocks.isNotEmpty) ...[
                const SizedBox(height: 16),
                Stack(clipBehavior: Clip.none, alignment: Alignment.topCenter, children: [
                  Container(
                    padding: const EdgeInsets.fromLTRB(14, 20, 14, 14),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0xFFE8B956), width: 3),
                      gradient: const RadialGradient(center: Alignment(0, -0.3), radius: 0.9, colors: [Color(0xFFFFF6DA), Color(0xFFFFF9F0)]),
                      boxShadow: const [BoxShadow(color: Color(0xFFFFF1C9), spreadRadius: 4), BoxShadow(color: Color(0xFFD9A84A), offset: Offset(0, 4))],
                    ),
                    child: Wrap(alignment: WrapAlignment.center, spacing: 14, runSpacing: 8, children: [
                      for (final u in r.unlocks)
                        Column(mainAxisSize: MainAxisSize.min, children: [VoxelIcon(_unlockIcon[u] ?? 'star', size: 74), Text(u, style: EvochiText.cardTitle)]),
                    ]),
                  ),
                  Positioned(
                    top: -13,
                    child: Container(
                      height: 26,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(borderRadius: BorderRadius.circular(9), border: Border.all(color: const Color(0xFFE8B956), width: 2), color: const Color(0xFFFFF9F0)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const VoxelIcon('star', size: 16),
                        const SizedBox(width: 4),
                        Text('UNLOCKED', style: EvochiText.tag.copyWith(color: EvochiColor.gold900, fontSize: 12, letterSpacing: 0.4)),
                      ]),
                    ),
                  ),
                ]),
              ],
              const SizedBox(height: 12),
              Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: [
                if (r.coins > 0) Tag('+${r.coins}', tone: TagTone.stage, icon: 'coin'),
                for (final e in r.gifts.entries) ItemCountChip(id: e.key, label: '${e.value} × ${item(e.key).name}'),
                for (final t in r.titles) Tag('Title: ${q.titles[t]}', tone: TagTone.ok, icon: 'crown'),
              ]),
              const SizedBox(height: 12),
              if (room != null) ...[
                EvochiButton(
                  label: 'Open your ${room == 'kitchen' ? 'Kitchen' : 'Apothecary'}',
                  onPressed: () {
                    goTo = room;
                    Navigator.pop(d);
                  },
                ),
                const SizedBox(height: 8),
              ],
              EvochiButton(label: backToVillage ? 'Back to Village' : 'Done', tone: room != null ? ButtonTone.cream : ButtonTone.gold, onPressed: () => Navigator.pop(d)),
            ]);
          }),
        ),
      ),
    ),
  );
  if (!context.mounted) return;
  if (goTo != null) {
    goHome(context, goTo!);
  } else if (backToVillage) {
    returnToVillage(context);
  }
}

// -------------------------------------------------------------- Journey > Story ----
class StoryTab extends StatelessWidget {
  const StoryTab({super.key});
  @override
  Widget build(BuildContext context) {
    final c = context.watch<GameController>();
    final st = c.storyView;
    final done = st.quests.where((v) => v.completed).length;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Semantics(
        label: q.chapterName,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: SizedBox(
            height: 140,
            child: Stack(fit: StackFit.expand, children: [
              Image.asset(villageArt.square(lampLit: st.flag('lamp_lit'), restored: st.flag('waystone_restored')), fit: BoxFit.cover, alignment: const Alignment(0, -0.1)),
              const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.center, colors: [Color(0x8C281E14), Color(0x00281E14)]))),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(q.chapterName, style: EvochiText.caption.copyWith(color: const Color(0xFFFFF6E6))),
                  Text(q.chapterTitle, style: EvochiText.cardTitle.copyWith(color: Colors.white)),
                  const SizedBox(height: 6),
                  Wrap(spacing: 6, children: [
                    Tag('$done / ${st.quests.length} quests', tone: TagTone.stage),
                    if (st.titles.isNotEmpty) Tag(q.titles[st.titles.first]!, tone: TagTone.ok),
                  ]),
                ]),
              ),
              Positioned(right: 10, bottom: 10, child: EvochiButton(label: 'Visit Village', small: true, expand: false, onPressed: () => openVillage(context))),
            ]),
          ),
        ),
      ),
      const SizedBox(height: 10),
      for (final v in st.quests) StoryQuestCard(v: v),
      const SizedBox(height: 6),
      const SectionHead('Home Tales'),
      for (final v in st.home) StoryQuestCard(v: v),
      const SizedBox(height: 6),
      const SectionHead('Side stories', trailing: Tag('Optional')),
      for (final v in st.side) StoryQuestCard(v: v),
      const Padding(
        padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Text(
          'Story walks only count steps taken after you accept a quest. Rest days never break them, and nothing expires. Side stories never block the main story.',
          style: EvochiText.caption,
        ),
      ),
    ]);
  }
}

class StoryQuestCard extends StatelessWidget {
  const StoryQuestCard({super.key, required this.v});
  final q.StoryQuestView v;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Semantics(
          button: true,
          label: '${v.title}. ${nextText(v)}',
          child: GestureDetector(
            onTap: () => showStoryQuest(context, v.id),
            child: Opacity(
              opacity: v.completed ? 0.78 : 1,
              child: GameCard(
                padding: const EdgeInsets.fromLTRB(6, 8, 10, 8),
                child: Row(children: [
                  SizedBox(width: 54, height: 60, child: NpcImage(v.giver, expression: v.completed ? 'happy' : 'neutral', height: 60)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                        Text(v.title, style: EvochiText.cardTitle.copyWith(fontSize: 15, fontWeight: FontWeight.w900)),
                        storyStatusTag(v),
                      ]),
                      Text(nextText(v), style: EvochiText.caption.copyWith(fontSize: 13)),
                      if (v.accepted && !v.completed) Padding(padding: const EdgeInsets.only(top: 4), child: WalkProgress(v)),
                    ]),
                  ),
                  const Text('›', style: TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w900, fontSize: 24, color: EvochiColor.textHelper)),
                ]),
              ),
            ),
          ),
        ),
      );
}

// ------------------------------------------------------------------- Home chip ----
/// The tracked story quest, one compact row above the pet card (only while it's in progress).
class StoryChip extends StatelessWidget {
  const StoryChip({super.key});
  @override
  Widget build(BuildContext context) {
    final c = context.watch<GameController>();
    final v = c.storyView.active;
    if (v == null || !v.tracked) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Semantics(
        button: true,
        label: '${v.title}. ${nextText(v)}',
        child: GestureDetector(
          onTap: () => showStoryQuest(context, v.id),
          child: GameCard(
            color: const Color(0xF5F0F7E8),
            padding: const EdgeInsets.fromLTRB(6, 6, 10, 6),
            child: Row(children: [
              NpcImage(q.storyQuests[v.id]!.giver, expression: v.next.kind == 'handin' ? 'happy' : 'neutral', height: 36),
              const SizedBox(width: 8),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(v.title, style: EvochiText.cardTitle.copyWith(fontSize: 13, fontWeight: FontWeight.w900)),
                  Text(nextText(v), maxLines: 1, overflow: TextOverflow.ellipsis, style: EvochiText.tag.copyWith(fontSize: 12)),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------- Quest Pouch ----
class PouchGrid extends StatelessWidget {
  const PouchGrid({super.key, required this.selected, required this.onSelect, required this.cols});
  final String? selected;
  final ValueChanged<String> onSelect;
  final int cols;
  @override
  Widget build(BuildContext context) {
    final c = context.watch<GameController>();
    final pouch = c.storyView.pouch;
    final ids = q.questMaterials.keys.where((id) => (pouch[id] ?? 0) > 0).toList();
    if (ids.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(18),
        child: Column(children: [
          const Opacity(opacity: 0.6, child: VoxelIcon('journey', size: 54)),
          const SizedBox(height: 6),
          const Text('Your Quest Pouch is empty.', style: EvochiText.cardTitle),
          const Text("Items you collect for Sunlit Village's story land here.", style: EvochiText.caption, textAlign: TextAlign.center),
          const SizedBox(height: 10),
          EvochiButton(label: 'Visit Village', small: true, expand: false, onPressed: () => openVillage(context)),
        ]),
      );
    }
    return GridView.count(
      crossAxisCount: cols,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 0.86,
      children: [
        for (final id in ids)
          Semantics(
            selected: id == selected,
            button: true,
            label: '${q.questMaterials[id]!.name}, quest item${(pouch[id] ?? 0) > 1 ? ', ${pouch[id]} owned' : ''}',
            child: GestureDetector(
              onTap: () => onSelect(id),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: id == selected ? const Color(0xFF5E7F4A) : const Color(0xFF7F9871), width: 2),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: id == selected ? const [Color(0xFFFBFEF7), Color(0xFFE2EDD5)] : const [Color(0xFFF7FBF2), Color(0xFFEAF1E1)],
                  ),
                ),
                child: Stack(children: [
                  Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Expanded(child: ItemImage(id, size: 62)),
                    Text(q.questMaterials[id]!.name, textAlign: TextAlign.center, maxLines: 2, style: EvochiText.tag.copyWith(fontSize: 12, color: EvochiColor.ink)),
                  ]),
                  Positioned(
                    left: 0,
                    top: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: const BoxDecoration(color: Color(0xFF7F9871), borderRadius: BorderRadius.only(topLeft: Radius.circular(6), topRight: Radius.circular(6), bottomRight: Radius.circular(6), bottomLeft: Radius.circular(2))),
                      child: Text('QUEST', style: EvochiText.tag.copyWith(color: Colors.white, fontSize: 9.5, letterSpacing: 0.5)),
                    ),
                  ),
                  if ((pouch[id] ?? 0) > 1)
                    Positioned(
                      right: 0,
                      top: 0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(color: const Color(0xFF5E4B40), borderRadius: BorderRadius.circular(7)),
                        child: Text('x${pouch[id]}', style: EvochiText.tag.copyWith(color: Colors.white, fontSize: 11)),
                      ),
                    ),
                ]),
              ),
            ),
          ),
      ],
    );
  }
}

class PouchDetail extends StatelessWidget {
  const PouchDetail({super.key, required this.id});
  final String id;
  @override
  Widget build(BuildContext context) {
    final m = q.questMaterials[id]!;
    final who = npcLabel(m.usedBy);
    final place = q.placeOf(m.usedBy);
    return GameCard(
      padding: const EdgeInsets.all(10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFF7F9871), width: 2), color: const Color(0xFFF3F8EC)),
            alignment: Alignment.center,
            child: ItemImage(id, size: 62),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(m.name, style: EvochiText.cardTitle),
              const SizedBox(height: 4),
              const Wrap(spacing: 4, runSpacing: 4, children: [Tag('Quest item', tone: TagTone.ok), Tag("Can't trade"), Tag("Can't sell")]),
              const SizedBox(height: 4),
              Text(m.desc, style: EvochiText.caption.copyWith(color: EvochiColor.textSecondary)),
              Text('Used by $who', style: EvochiText.caption.copyWith(fontSize: 11)),
            ]),
          ),
        ]),
        const SizedBox(height: 8),
        EvochiButton(label: 'Go to ${who.replaceFirst('the ', '')}', small: true, onPressed: () => openPlace(context, place)),
      ]),
    );
  }
}

/// "Village Tales, Quest 0N: <title>" under a story reward's description.
Widget storySourceLine(String itemId) {
  final it = catalog[itemId];
  if (it == null || !it.isStory) return const SizedBox.shrink();
  return Text('${storySource[it.originQuest]}: ${q.storyQuests[it.originQuest]!.title}', style: EvochiText.caption.copyWith(fontSize: 11));
}
