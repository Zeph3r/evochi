// A Trail Guild job's place in the Deep Wilds: who waits there, what the job still needs, and the way
// down to it once it is ready (game/wilds/story_floors.dart). Opened from the job (the Guild, the quest
// card, the Journey tab) where the old encounter prep used to be.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../controllers/game_controller.dart';
import '../../core/models/catalog.dart';
import '../../game/story/story.dart' as q;
import '../../game/trails/trails.dart' as tr;
import '../../game/wilds/story_floors.dart' as sf;
import '../shared/kit.dart';
import '../shared/widgets.dart';
import 'deep_floor.dart' show deepTrail;
import 'wilds_screen.dart';

String _how(sf.StoryFloor f) => switch (f.beat) {
      'trust' => 'Petalune is shy, and it is never fought. Stay near it and be gentle: no running at it, no attacks near it. '
          'Hum to it, and offer a treat from your Bag (it loves Sunberry Tarts).',
      'sprout' => 'The Hollow has tangled the sprout and it lashes out: vines, thorns underfoot, bursts of spores. '
          'Calm its Hollow in a fight and it comes back to itself.',
      _ => 'An old guardian sleeps against the gate, tangled in Hollow. Wake it and weather its fists, its eyes\' beam and '
          'its runes. When it hides behind a Hollow shield, calm what it calls, or drink your Lantern Tonic: '
          'its light breaks the shield.',
    };

/// The job's place: open it, or see what it still needs.
Future<void> showStoryFloorBrief(BuildContext context, String qid) {
  final f = sf.storyFloors[qid]!;
  return showDialog<void>(
    context: context,
    barrierColor: const Color(0x8C201B17),
    builder: (d) => KitDialog(child: _Brief(floor: f, onClose: () => Navigator.pop(d))),
  );
}

class _Brief extends StatelessWidget {
  const _Brief({required this.floor, required this.onClose});
  final sf.StoryFloor floor;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final c = context.watch<GameController>();
    final qid = floor.quest;
    final v = q.questView(c.state, qid, c.now);
    final quest = q.storyQuests[qid]!;
    final cdef = tr.creatureDefs[floor.creature]!;
    final open = sf.storyFloorOpen(c.state, qid);
    final pose = switch (floor.creature) { 'petalune' => 'wary', 'sentinel' => 'hollow', _ => 'hollow' };
    final n = v.next;
    final String? wait = switch (n.kind) {
      'locked' => v.lock?.text ?? 'Not open yet',
      'talk' => 'Take the job from ${q.npcs[quest.giver]?.name ?? 'the Guild'} first.',
      'walk' => 'Walk ${fmt(v.resolved)} steps to find the way (${fmt(v.walk.progress)} so far).',
      'gather' => 'Bring ${n.needs.where((x) => !x.ok).map((x) => '${x.need} × ${catalog[x.id]?.name ?? x.id}').join(', ')}.',
      'grow' => 'Your Evochi needs to grow a little first.',
      'done' => 'Done: ${cdef.name} remembers you.',
      _ => null,
    };
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        SizedBox(
          width: 76,
          height: 76,
          child: Image.asset('assets/art/trails/creature_${floor.creature}_$pose.webp', fit: BoxFit.contain, filterQuality: FilterQuality.medium),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(quest.title, style: EvochiText.cardTitle.copyWith(fontSize: 18)),
            const SizedBox(height: 2),
            Text('${floor.place} · F${floor.depth} of $deepTrail', style: EvochiText.caption.copyWith(color: EvochiColor.textSecondary)),
            Text(cdef.name, style: EvochiText.tag.copyWith(color: EvochiColor.ink)),
          ]),
        ),
      ]),
      const SizedBox(height: 10),
      Text(_how(floor), style: EvochiText.bodyText.copyWith(height: 1.35)),
      const SizedBox(height: 10),
      for (final o in v.objectives)
        Padding(
          padding: const EdgeInsets.only(bottom: 3),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(o.done || o.ready ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                size: 16, color: o.done || o.ready ? const Color(0xFF5E9E4A) : const Color(0xFFB4874F)),
            const SizedBox(width: 6),
            Expanded(child: Text(o.text, style: EvochiText.caption.copyWith(color: o.optional ? EvochiColor.textSecondary : EvochiColor.ink))),
          ]),
        ),
      if (wait != null) ...[
        const SizedBox(height: 6),
        Text(wait, style: EvochiText.caption.copyWith(color: const Color(0xFF9A6A2E))),
      ],
      const SizedBox(height: 12),
      if (open)
        EvochiButton(
          label: 'Go to the ${floor.place}',
          tone: ButtonTone.green,
          onPressed: () {
            final nav = Navigator.of(context);
            onClose();
            c.audio.play('enc_whoosh', volume: 0.5);
            nav.push(MaterialPageRoute<void>(builder: (_) => WildsScreen(depth: floor.depth, story: qid)));
          },
        ),
      const SizedBox(height: 6),
      EvochiButton(label: open ? 'Not yet' : 'OK', tone: ButtonTone.cream, onPressed: onClose),
    ]);
  }
}
