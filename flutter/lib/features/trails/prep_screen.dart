// Lumen Trails: encounter prep. The place (with a look-around button), a banner of its scene, the
// quest card with its checklist (job accepted, the walk, required and optional items, the goal),
// your team (your Evochi and any companions), the recommended item (with a Change / Make button),
// the possible rewards, and Prepare & Enter once the hand-in is ready (or what to do first).
// Mirrors `prep` in web/src/screens/encounter.js.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../controllers/game_controller.dart';
import '../../core/models/catalog.dart';
import '../../game/engine.dart' as g;
import '../../game/home/home.dart' as h;
import '../../game/story/story.dart' as q;
import '../../game/trails/trails.dart' as tr;
import '../home/home_widgets.dart';
import '../shared/sprite.dart';
import '../shared/widgets.dart';
import '../village/story_widgets.dart';
import '../village/village_screen.dart';
import 'encounter_screen.dart';
import 'trails_widgets.dart';
import 'travel_screen.dart';

class _PlaceInfo {
  const _PlaceInfo(this.name, this.line, this.badge);
  final String name;
  final String line;
  final String badge;
}

const _placeInfo = <String, _PlaceInfo>{
  'ruins': _PlaceInfo('Mossy Ruins', 'A quiet grove with ancient light.', 'aff_nature'),
  'gate': _PlaceInfo('The Old Gate', 'The broken gate past the bridge.', 'moon'),
};

class PrepScreen extends StatefulWidget {
  const PrepScreen({super.key, required this.questId});
  final String questId;
  @override
  State<PrepScreen> createState() => _PrepScreenState();
}

class _PrepScreenState extends State<PrepScreen> {
  int? _rec; // Change: cycles the recommended items

  void _travel(GameController c, String qid) {
    final r = c.run((s, n) => tr.startEncounter(s, qid, n));
    if (!r.ok) return;
    c.audio.play('ui_tap', volume: 0.5);
    Navigator.of(context).push(MaterialPageRoute<void>(settings: const RouteSettings(name: 'travel'), builder: (_) => TravelScreen(questId: qid)));
  }

  void _resume() {
    Navigator.of(context).push(MaterialPageRoute<void>(settings: const RouteSettings(name: 'encounter'), builder: (_) => const EncounterScreen()));
  }

  void _teamHelp() {
    showEvochiDialog<void>(context, builder: (d) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Your team', style: EvochiText.section, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          const Text(
            'Your Evochi takes the turns. A grown Evochi has more Energy (100 as an Eggling, 120, then 140). Befriended companions lend one ability per encounter, like Petalune’s Petal Hush.',
            style: EvochiText.bodyText,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          EvochiButton(label: 'Got it', onPressed: () => Navigator.pop(d)),
        ]));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<GameController>();
    final qid = tr.encounterDefs.containsKey(widget.questId) ? widget.questId : 'eq01';
    final e = tr.encounterDefs[qid]!;
    final cdef = tr.creatureDefs[e.creature]!;
    final quest = q.storyQuests[qid]!;
    final v = q.questView(c.state, qid, c.now);
    final n = v.next;
    final t = quest.turnIns.firstWhere((x) => x.encounter != null);
    final pet = c.state.pet;
    final giver = q.npcs[quest.giver]!;
    final walkDone = quest.walk != null && v.accepted && v.phase != quest.walk!.phase;
    final needs = q.itemNeeds(c.state, t);
    final opts = [for (final x in t.optionalItems.entries) (id: x.key, need: x.value, have: g.ownedQty(c.state, x.key))];
    final ready = n.kind == 'encounter';
    final stageOk = (pet?.stage ?? 1) >= e.recommended.stage;
    final going = n.kind == 'gather' ? needs.where((x) => !x.ok).firstOrNull : null;
    final src = going == null ? null : h.homeSource(going.id);
    final place = _placeInfo[e.place] ?? _PlaceInfo(tr.placeTitle(e.place), '', 'trail');
    final recs = e.recommended.items;
    final owned = recs.where((id) => g.ownedQty(c.state, id) > 0).toList();
    final recId = _rec != null ? recs[_rec! % recs.length] : (owned.firstOrNull ?? recs.first);
    final fx = tr.itemEffect(recId, e.goal, e.creature);
    final have = g.ownedQty(c.state, recId);
    final recSrc = have > 0 ? null : h.homeSource(recId);
    final comps = c.trailsView.companions.where((x) => x.id != e.creature).toList();
    final befriend = e.goal == 'befriend';
    final hollow = cdef.kind == 'hollow';
    final placeLower = place.name.startsWith('The ') ? 'the ${place.name.substring(4)}' : place.name;
    final goalLine = befriend ? 'Calm a wild ${cdef.name} in the ${place.name}.' : 'Restore the ${cdef.name} at $placeLower.';
    final live = c.state.trails.encounter;
    final resumable = live != null && live.quest == qid && live.done == null;
    final ta = trailsArt;
    final mq = MediaQuery.of(context);
    return Scaffold(
      backgroundColor: const Color(0xFFF8EEDF),
      body: Semantics(
        label: 'Encounter preparation',
        child: Column(children: [
          // header: back, the place, look around
          Padding(
            padding: EdgeInsets.fromLTRB(14, mq.padding.top + 10, 14, 10),
            child: Row(children: [
              Semantics(
                button: true,
                label: 'Back',
                child: GestureDetector(
                  onTap: () => Navigator.of(context).maybePop(),
                  child: const SizedBox(width: 40, height: 40, child: Icon(Icons.chevron_left_rounded, size: 30, color: EvochiColor.textSecondary)),
                ),
              ),
              const SizedBox(width: 8),
              VoxelIcon(place.badge, size: 44),
              const SizedBox(width: 8),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Semantics(header: true, child: Text(place.name, style: const TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w900, fontSize: 21, height: 1.1, color: EvochiColor.ink))),
                  if (place.line.isNotEmpty) Text(place.line, style: const TextStyle(fontFamily: EvochiText.body, fontSize: 12.5, height: 16 / 12.5, color: EvochiColor.textHelper)),
                ]),
              ),
              const SizedBox(width: 8),
              Semantics(
                button: true,
                label: 'Look around ${place.name}',
                child: GestureDetector(
                  onTap: () => openTrailPlace(context, e.place),
                  child: Container(
                    width: 44,
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE2CBAE), width: 2),
                      gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFFFF6EA), Color(0xFFF1E0CA)]),
                      boxShadow: const [BoxShadow(color: Color(0xFFD5BC9C), offset: Offset(0, 3))],
                    ),
                    child: const VoxelIcon('trail', size: 30),
                  ),
                ),
              ),
            ]),
          ),
          Expanded(
            child: ListView(padding: EdgeInsets.fromLTRB(14, 0, 14, 24 + mq.padding.bottom), children: [
              // the banner, with the creature in a disc
              Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), boxShadow: const [BoxShadow(color: Color(0x38281A0A), blurRadius: 14, offset: Offset(0, 6))]),
                child: AspectRatio(
                  aspectRatio: 2.05,
                  child: Stack(fit: StackFit.expand, children: [
                    if (ta.available && ta.hasScene(e.scene))
                      Image.asset(ta.scene(e.scene), fit: BoxFit.cover, alignment: const Alignment(0, -0.12), excludeFromSemantics: true)
                    else
                      const ColoredBox(color: EvochiColor.panel2),
                    Positioned(
                      right: 10,
                      top: 10,
                      child: Container(
                        width: 54,
                        height: 54,
                        alignment: Alignment.center,
                        decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xEBFFFAF0), boxShadow: [BoxShadow(color: Color(0x40000000), blurRadius: 8, offset: Offset(0, 3))]),
                        child: VoxelIcon('creature_${cdef.id}', size: 46, semantic: cdef.name),
                      ),
                    ),
                  ]),
                ),
              ),
              // the quest card, overlapping the banner
              Transform.translate(
                offset: const Offset(0, -38),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Semantics(
                    container: true,
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 13),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFFDF9),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFEBDCC8), width: 2),
                        boxShadow: const [BoxShadow(color: Color(0x29281A0A), blurRadius: 14, offset: Offset(0, 6))],
                      ),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        Row(children: [
                          Container(
                            width: 42,
                            height: 42,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: hollow ? const Color(0xFFEEE4FB) : const Color(0xFFE5F2CF),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: hollow ? const Color(0xFFD7C4F2) : const Color(0xFFC5E2A8), width: 1.5),
                            ),
                            child: VoxelIcon(befriend ? 'calm' : 'purify', size: 32),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Semantics(header: true, child: Text(v.title, style: const TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w900, fontSize: 16.5, color: EvochiColor.ink))),
                              Text(goalLine, style: const TextStyle(fontFamily: EvochiText.body, fontSize: 13, height: 17 / 13, color: EvochiColor.textHelper)),
                            ]),
                          ),
                        ]),
                        const SizedBox(height: 10),
                        if (v.phase == 'available' || v.phase == 'locked')
                          _CheckRow(done: false, text: v.phase == 'locked' ? (v.lock?.text ?? 'Locked') : 'Accept the job from ${giver.name}')
                        else
                          _CheckRow(done: true, text: 'Job accepted from ${giver.name}'),
                        if (quest.walk != null)
                          _CheckRow(done: walkDone, text: walkDone ? 'Reach ${place.name}' : 'Walk ${fmt(v.resolved)} steps to ${place.name} · ${fmt(v.walk.progress)} so far'),
                        for (final x in needs) _CheckRow(done: x.ok, text: 'Bring ${x.need} × ${catalog[x.id]?.name ?? x.id} (${x.have}/${x.need})'),
                        for (final o in opts) _CheckRow(done: o.have >= o.need, text: 'Bring ${catalog[o.id]?.name ?? o.id} for a better start', optional: true),
                        _CheckRow(done: v.completed, text: befriend ? 'Gain ${cdef.name}’s trust' : 'Bring its Instability to zero', last: true),
                      ]),
                    ),
                  ),
                ),
              ),
              Transform.translate(
                offset: const Offset(0, -28),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  // your team
                  _PrepHead(
                    'Your team',
                    trailing: Semantics(
                      button: true,
                      label: 'About your team',
                      child: GestureDetector(
                        onTap: _teamHelp,
                        child: Container(
                          width: 22,
                          height: 22,
                          alignment: Alignment.center,
                          decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFFBCAD9F)),
                          child: const Text('?', style: TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w900, fontSize: 13, color: Colors.white, height: 1)),
                        ),
                      ),
                    ),
                  ),
                  Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    if (pet != null)
                      Expanded(
                        child: _TeamCard(
                          me: true,
                          warn: !stageOk,
                          badge: tr.affinityDefs['lumen']!.icon,
                          picture: PetSprite(stage: pet.stage, palette: pet.paletteId, expr: 'happy', height: 72),
                          name: pet.name,
                          notes: ['Lv. ${c.view.pet?.level.level ?? 1}', '${tr.maxEnergy(c.state)} Energy'],
                          label: '${pet.name}, level ${c.view.pet?.level.level ?? 1}, ${tr.maxEnergy(c.state)} Energy${stageOk ? '' : '. A grown Evochi has more Energy'}',
                        ),
                      ),
                    for (final comp in comps) ...[
                      const SizedBox(width: 8),
                      Expanded(
                        child: _TeamCard(
                          badge: tr.affinityDefs[comp.creature.affinity]!.icon,
                          picture: VoxelIcon('creature_${comp.id}', size: 72),
                          name: comp.name,
                          notes: [comp.creature.companion?.name ?? 'Companion'],
                          label: '${comp.name}, companion. ${comp.creature.companion?.name ?? ''}',
                        ),
                      ),
                    ],
                    if (comps.isEmpty) ...[
                      const SizedBox(width: 8),
                      const Expanded(child: _TeamCard(ghost: true, name: 'Companion', notes: ['Befriend one to help'], label: 'Companion: befriend one to help')),
                    ],
                    if (pet != null && comps.length < 2) const Expanded(child: SizedBox.shrink()),
                  ]),
                  if (!stageOk)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(2, 8, 2, 0),
                      child: Text('A ${stageLabel(e.recommended.stage)} or older Evochi has more Energy for this one. You can still go.', style: const TextStyle(fontFamily: EvochiText.body, fontSize: 12.5, height: 17 / 12.5, color: Color(0xFF9A5B2C))),
                    ),
                  // the recommended item
                  _PrepHead('Recommended item', sub: '(optional)'),
                  Semantics(
                    container: true,
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFFDF9),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFEBDCC8), width: 2),
                        boxShadow: const [BoxShadow(color: Color(0xFFE4D2BC), offset: Offset(0, 2))],
                      ),
                      child: Row(children: [
                        Container(
                          width: 64,
                          height: 64,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(color: const Color(0xFFF6EADB), borderRadius: BorderRadius.circular(14)),
                          child: ItemImage(recId, size: 54),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(catalog[recId]?.name ?? recId, style: const TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w900, fontSize: 15.5, color: EvochiColor.ink)),
                            if (fx != null)
                              Text('${befriend ? '+' : '−'}${fx.amount} ${befriend ? 'Calm' : 'Instability'}${fx.liked ? ' · ${cdef.name} loves it' : ''}',
                                  style: const TextStyle(fontFamily: EvochiText.body, fontSize: 12.5, height: 17 / 12.5, color: EvochiColor.textHelper)),
                            Text.rich(TextSpan(style: const TextStyle(fontFamily: EvochiText.body, fontSize: 12.5, height: 17 / 12.5, color: EvochiColor.textHelper), children: [
                              const TextSpan(text: 'You have: '),
                              TextSpan(text: '$have', style: const TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w900, fontSize: 13, color: EvochiColor.ink)),
                            ])),
                          ]),
                        ),
                        if (have == 0 && recSrc != null)
                          _MiniButton(label: recSrc.verb, onTap: () => goHome(context, recSrc.route == 'station' ? recSrc.station! : 'garden'))
                        else if (recs.length > 1)
                          _MiniButton(label: 'Change', onTap: () => setState(() => _rec = (_rec ?? 0) + 1)),
                      ]),
                    ),
                  ),
                  // rewards
                  _PrepHead('Possible rewards'),
                  RewardTiles(rewardTilesFor(v.rewards, cdef, e.goal)),
                  const SizedBox(height: 18),
                  // the call to action
                  if (resumable)
                    EncCta(label: 'Continue the encounter', big: true, leading: const _Peaks(), onTap: _resume)
                  else if (ready)
                    EncCta(label: 'Prepare & Enter', big: true, leading: const _Peaks(), onTap: () => _travel(c, qid))
                  else if (v.phase == 'available')
                    EncCta(label: 'Talk to ${giver.name}', big: true, alt: true, onTap: () => openPlace(context, giver.location, npc: quest.giver))
                  else if (n.kind == 'walk')
                    EncCta(label: 'Go for a walk', big: true, onTap: () => goWalk(context))
                  else if (going != null && src != null)
                    EncCta(label: '${src.verb} ${catalog[going.id]?.name ?? going.id} in your ${src.place}', big: true, onTap: () => goHome(context, src.route == 'station' ? src.station! : 'garden'))
                  else if (v.completed)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: const Color(0xFFE5F2CF), borderRadius: BorderRadius.circular(14)),
                      child: Text(befriend ? '${cdef.name} is your companion.' : '${cdef.name} was restored.', textAlign: TextAlign.center, style: const TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w900, fontSize: 15, color: Color(0xFF3E7D33))),
                    ),
                  const SizedBox(height: 4),
                  Center(
                    child: Semantics(
                      button: true,
                      label: 'Quest details',
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => showStoryQuest(context, qid),
                        child: const Padding(
                          padding: EdgeInsets.fromLTRB(10, 6, 10, 6),
                          child: Text('Quest details', style: TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w800, fontSize: 14, color: EvochiColor.textHelper, decoration: TextDecoration.underline, decorationColor: EvochiColor.textHelper)),
                        ),
                      ),
                    ),
                  ),
                ]),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// A section heading ("Your team ?", "Recommended item (optional)").
class _PrepHead extends StatelessWidget {
  const _PrepHead(this.text, {this.sub, this.trailing});
  final String text;
  final String? sub;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 18, 2, 8),
        child: Row(children: [
          Semantics(header: true, child: Text(text, style: const TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w900, fontSize: 17, color: Color(0xFF4A2D45)))),
          if (sub != null) ...[const SizedBox(width: 6), Text(sub!, style: const TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w700, fontSize: 14, color: EvochiColor.textHelper))],
          if (trailing != null) ...[const SizedBox(width: 6), trailing!],
        ]),
      );
}

/// One line of the quest checklist: a tick box (dashed when optional), the text, an "optional" pill.
class _CheckRow extends StatelessWidget {
  const _CheckRow({required this.done, required this.text, this.optional = false, this.last = false});
  final bool done;
  final String text;
  final bool optional;
  final bool last;
  @override
  Widget build(BuildContext context) => Semantics(
        label: '$text${done ? ', done' : ''}${optional ? ', optional' : ''}',
        child: ExcludeSemantics(
          child: Padding(
            padding: EdgeInsets.only(bottom: last ? 0 : 8),
            child: Row(children: [
              Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  color: done ? null : const Color(0xFFFBF5EC),
                  gradient: done ? const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF8FDA6E), Color(0xFF5FB447)]) : null,
                  border: optional && !done ? null : Border.all(color: done ? const Color(0xFF4E9B3A) : const Color(0xFFDCCAB4), width: 2),
                ),
                child: done ? const Icon(Icons.check_rounded, size: 16, color: Colors.white) : (optional ? CustomPaint(size: const Size(22, 22), painter: _DashedBox()) : null),
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(text, style: TextStyle(fontFamily: EvochiText.body, fontSize: 14, height: 18 / 14, color: done ? EvochiColor.textSecondary : EvochiColor.textHelper))),
              if (optional)
                Container(
                  margin: const EdgeInsets.only(left: 8),
                  padding: const EdgeInsets.fromLTRB(7, 1, 7, 1),
                  decoration: BoxDecoration(color: const Color(0xFFF3E8DA), borderRadius: BorderRadius.circular(8)),
                  child: const Text('optional', style: TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w800, fontSize: 11, color: EvochiColor.textHelper)),
                ),
            ]),
          ),
        ),
      );
}

/// A dashed border for the optional tick boxes.
class _DashedBox extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFDCCAB4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final r = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(6)).deflate(1);
    final path = Path()..addRRect(r);
    const dash = 3.0, gap = 2.5;
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, d + dash), paint);
        d += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBox old) => false;
}

/// A team card: a badge top-left, a picture, a name and a line or two. [me] frames your Evochi in
/// gold ([warn] in orange when a grown one is recommended); [ghost] is the dashed "Befriend one".
class _TeamCard extends StatelessWidget {
  const _TeamCard({this.me = false, this.warn = false, this.ghost = false, this.badge, this.picture, required this.name, required this.notes, required this.label});
  final bool me;
  final bool warn;
  final bool ghost;
  final String? badge;
  final Widget? picture;
  final String name;
  final List<String> notes; // "Lv. 3", "100 Energy", a companion's ability
  final String label;
  @override
  Widget build(BuildContext context) => Semantics(
        label: label,
        child: ExcludeSemantics(
          child: Container(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
            decoration: BoxDecoration(
              color: ghost ? const Color(0x99FFFDF9) : const Color(0xFFFFFDF9),
              borderRadius: BorderRadius.circular(16),
              border: ghost ? null : Border.all(color: warn ? const Color(0xFFEBA36A) : (me ? const Color(0xFFF0C234) : const Color(0xFFEBDCC8)), width: 2),
              boxShadow: ghost
                  ? null
                  : [
                      if (me) const BoxShadow(color: Color(0x59F0C234), spreadRadius: 2),
                      const BoxShadow(color: Color(0xFFE4D2BC), offset: Offset(0, 2)),
                    ],
            ),
            child: Stack(clipBehavior: Clip.none, children: [
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(
                  height: 72,
                  width: double.infinity,
                  child: ghost
                      ? const Center(child: Text('?', style: TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w900, fontSize: 34, color: Color(0xFFD6C5B2))))
                      : Center(child: picture),
                ),
                const SizedBox(height: 4),
                Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w900, fontSize: 14, color: EvochiColor.ink)),
                for (final l in notes) Text(l, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w700, fontSize: 11.5, height: 1.2, color: EvochiColor.textHelper)),
              ]),
              if (ghost) Positioned.fill(child: CustomPaint(painter: _DashedCard())),
              if (badge != null) Positioned(left: -4, top: -2, child: VoxelIcon(badge!, size: 24)),
            ]),
          ),
        ),
      );
}

/// The ghost card's dashed outline (drawn over the padding box).
class _DashedCard extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFEBDCC8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final r = RRect.fromRectAndRadius(Rect.fromLTWH(-10, -8, size.width + 20, size.height + 18), const Radius.circular(16)).deflate(1);
    final path = Path()..addRRect(r);
    const dash = 6.0, gap = 4.0;
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, d + dash), paint);
        d += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedCard old) => false;
}

/// "Change" / "Make": the small cream button on the recommended item card.
class _MiniButton extends StatelessWidget {
  const _MiniButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: label,
        child: GestureDetector(
          onTap: () {
            context.read<GameController>().audio.tick();
            onTap();
          },
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2CBAE), width: 2),
              gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFFFF6EA), Color(0xFFF1E0CA)]),
              boxShadow: const [BoxShadow(color: Color(0xFFD5BC9C), offset: Offset(0, 3))],
            ),
            child: Text(label, style: const TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w900, fontSize: 14, color: EvochiColor.ink)),
          ),
        ),
      );
}

/// Two green peaks with a snowcap, on the Prepare & Enter button.
class _Peaks extends StatelessWidget {
  const _Peaks();
  @override
  Widget build(BuildContext context) => const SizedBox(width: 38, height: 28, child: CustomPaint(painter: _PeaksPainter()));
}

class _PeaksPainter extends CustomPainter {
  const _PeaksPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / 32;
    final sy = size.height / 24;
    final peaks = Path()
      ..moveTo(2 * sx, 21 * sy)
      ..lineTo(12 * sx, 5 * sy)
      ..lineTo(18 * sx, 14 * sy)
      ..lineTo(21 * sx, 10 * sy)
      ..lineTo(30 * sx, 21 * sy)
      ..close();
    canvas.drawPath(peaks, Paint()..color = const Color(0xFF2F6B3A));
    final cap = Path()
      ..moveTo(12 * sx, 5 * sy)
      ..lineTo(15 * sx, 9.6 * sy)
      ..lineTo(12.8 * sx, 8.7 * sy)
      ..lineTo(11 * sx, 10.4 * sy)
      ..lineTo(9.6 * sx, 8.9 * sy)
      ..close();
    canvas.drawPath(cap, Paint()..color = const Color(0xFFE9F6DC));
  }

  @override
  bool shouldRepaint(_PeaksPainter old) => false;
}
