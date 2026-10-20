// Lumen Trails: encounter prep, after the UX board. "Encounter Preparation" with a look-around button,
// the scene banner with its place, the creature's nameplate over it (portrait, name, rarity and kind,
// level, its meter), the Objective (the goal and the checklist: job accepted, the walk, required and
// optional items), Recommended (the suggested item with its effect and Change / Make, and the
// suggested approach), Your Team (your Evochi with its Energy, companions ready to help, or a slot
// waiting for one), and Begin Encounter once the hand-in is ready (or what to do first).
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
import '../shared/kit.dart';
import '../shared/widgets.dart';
import '../village/story_widgets.dart';
import '../village/village_screen.dart';
import 'encounter_screen.dart';
import 'trails_widgets.dart';
import 'travel_screen.dart';
import '../shared/live_scene.dart';
import '../shared/ambience.dart';

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

const _rarity = {'rare': 'Rare', 'uncommon': 'Uncommon', 'legendary': 'Legendary', 'common': 'Common'};

/// A team row that needs a grown Evochi: card stock with an amber edge.
const _warnPaper = KitPaper(Color(0xFFFFF8E8), Color(0xFFF6E6C8), Color(0xFFD99A4E), Color(0xFFB4874F), Color(0x61C49660));

BoxDecoration _card() => BoxDecoration(
      color: const Color(0xFFFFFDF9),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFFEBDCC8), width: 2),
      boxShadow: const [BoxShadow(color: Color(0xFFE4D2BC), offset: Offset(0, 2))],
    );

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
    Navigator.of(context).push(MaterialPageRoute<void>(settings: const RouteSettings(name: 'travel'), builder: (_) => Ambience(scenePlace(tr.encounterDefs[qid]?.scene), child: TravelScreen(questId: qid))));
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
    final goalMore = befriend ? 'Earn its trust, and it may join your journey.' : 'Calm the Hollow energy and bring its light back.';
    final sign = befriend ? '+' : '−';
    final label = befriend ? 'Calm' : 'Instability';
    final (apIcon, apName, apText) = befriend
        ? ('calm', 'Calm', 'Gifts ${cdef.name} loves count 1.5×. A Gentle Nudge makes it curious.')
        : ('sun', 'Lumen', 'Lumen Glow is 30% stronger against the Hollow.');
    final maxE = tr.maxEnergy(c.state);
    final level = c.view.pet?.level.level ?? 1;
    final live = c.state.trails.encounter;
    final resumable = live != null && live.quest == qid && live.done == null;
    final ta = trailsArt;
    final mq = MediaQuery.of(context);
    final checks = <Widget>[
      if (v.phase == 'available' || v.phase == 'locked')
        _CheckRow(done: false, text: v.phase == 'locked' ? (v.lock?.text ?? 'Locked') : 'Accept the job from ${giver.name}')
      else
        _CheckRow(done: true, text: 'Job accepted from ${giver.name}'),
      if (quest.walk != null) _CheckRow(done: walkDone, text: walkDone ? 'Reach ${place.name}' : 'Walk ${fmt(v.resolved)} steps to ${place.name} · ${fmt(v.walk.progress)} so far'),
      for (final x in needs) _CheckRow(done: x.ok, text: 'Bring ${x.need} × ${catalog[x.id]?.name ?? x.id} (${x.have}/${x.need})'),
      for (final o in opts) _CheckRow(done: o.have >= o.need, text: 'Bring ${catalog[o.id]?.name ?? o.id} for a better start', optional: true),
    ];
    const gap = SizedBox(height: 10);
    return Scaffold(
      backgroundColor: const Color(0xFFF8EEDF),
      body: KitPage(
        material: KitMaterial.plain,
        child: Semantics(
        label: 'Encounter preparation',
        child: Column(children: [
          // header: a light-wood Back square, "Encounter Preparation" on a wooden plaque, look around
          Padding(
            padding: EdgeInsets.fromLTRB(14, mq.padding.top + 10, 14, 8),
            child: Row(children: [
              BackSquareButton(onTap: () => Navigator.of(context).maybePop()),
              const SizedBox(width: 8),
              Expanded(
                child: Semantics(
                  header: true,
                  child: WoodPlaque(
                    height: 42,
                    nails: false,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text('Encounter Preparation', style: WoodPlaque.text(const TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w900, fontSize: 19, height: 1.1))),
                    ),
                  ),
                ),
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
                    decoration: Kit.parchment(radius: 12, drop: false),
                    child: const VoxelIcon('trail', size: 30),
                  ),
                ),
              ),
            ]),
          ),
          Expanded(
            child: ListView(padding: EdgeInsets.fromLTRB(14, 0, 14, 24 + mq.padding.bottom), children: [
              // the banner with its place, and the creature's nameplate over its lower edge
              LayoutBuilder(builder: (ctx, box) {
                final bh = box.maxWidth / 2.05;
                return Stack(clipBehavior: Clip.none, children: [
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 0,
                    height: bh,
                    child: Container(
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), boxShadow: const [BoxShadow(color: Color(0x38281A0A), blurRadius: 14, offset: Offset(0, 6))]),
                      child: Stack(fit: StackFit.expand, children: [
                        if (ta.available && ta.hasScene(e.scene))
                          LiveImage(ta.scene(e.scene), fit: BoxFit.cover, alignment: const Alignment(0, -0.12), excludeFromSemantics: true)
                        else
                          const ColoredBox(color: EvochiColor.panel2),
                        Positioned(
                          left: 10,
                          top: 10,
                          child: Container(
                            padding: const EdgeInsets.fromLTRB(4, 3, 12, 3),
                            decoration: BoxDecoration(color: const Color(0xEDFFFDF8), borderRadius: BorderRadius.circular(14), boxShadow: const [BoxShadow(color: Color(0x2E000000), blurRadius: 6, offset: Offset(0, 2))]),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              VoxelIcon(place.badge, size: 24),
                              const SizedBox(width: 6),
                              Text(place.name, style: const TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w900, fontSize: 13.5, color: EvochiColor.ink)),
                            ]),
                          ),
                        ),
                      ]),
                    ),
                  ),
                  Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    SizedBox(height: bh - 42),
                    Padding(padding: const EdgeInsets.symmetric(horizontal: 10), child: _Nameplate(cdef: cdef, e: e, level: quest.level)),
                  ]),
                ]);
              }),
              // the objective
              const _PrepHead('Objective'),
              gap,
              Semantics(
                container: true,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(14, 11, 14, 10),
                  decoration: _card(),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Text('$goalLine $goalMore', style: const TextStyle(fontFamily: EvochiText.body, fontSize: 14.5, height: 20 / 14.5, color: EvochiColor.textSecondary)),
                    const SizedBox(height: 16),
                    for (var i = 0; i < checks.length; i++) ...[if (i > 0) const SizedBox(height: 8), checks[i]],
                  ]),
                ),
              ),
              // recommended: an item and an approach
              const _PrepHead('Recommended'),
              gap,
              IntrinsicHeight(
                child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Expanded(
                    child: _RecTile(
                      kicker: 'Suggested Item',
                      hollow: hollow,
                      picture: ItemImage(recId, size: 44),
                      name: catalog[recId]?.name ?? recId,
                      pill: fx == null ? null : '$sign${fx.amount} $label',
                      restore: !befriend,
                      line: '${have > 0 ? 'You have $have' : 'You have none yet'}${fx != null && fx.liked ? ' · ${cdef.name} loves it' : ''}',
                      button: have == 0 && recSrc != null
                          ? _MiniButton(label: recSrc.verb, onTap: () => goHome(context, recSrc.route == 'station' ? recSrc.station! : 'garden'))
                          : recs.length > 1
                              ? _MiniButton(label: 'Change', onTap: () => setState(() => _rec = (_rec ?? 0) + 1))
                              : null,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: _RecTile(kicker: 'Suggested Approach', hollow: hollow, picture: VoxelIcon(apIcon, size: 44), name: apName, line: apText)),
                ]),
              ),
              // your team
              _PrepHead(
                'Your Team',
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
              gap,
              if (pet != null)
                _TeamRow(
                  warn: !stageOk,
                  face: EncFace.pet(pet, size: 46, wearables: false),
                  name: pet.name,
                  line: 'Lv. $level · ${stageLabel(pet.stage)}',
                  label: '${pet.name}, level $level, ${stageLabel(pet.stage)}. Energy $maxE of $maxE${stageOk ? '' : '. A grown Evochi has more Energy'}',
                  trailing: Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
                    const Text('Energy', style: TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w800, fontSize: 12, color: EvochiColor.textHelper)),
                    const SizedBox(height: 2),
                    const ThinBar(kind: 'energy', frac: 1, width: 92),
                    const SizedBox(height: 2),
                    Text('$maxE / $maxE', style: const TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w900, fontSize: 12, color: EvochiColor.ink)),
                  ]),
                ),
              for (final comp in comps) ...[
                const SizedBox(height: 8),
                _TeamRow(
                  face: EncFace.creature(comp.id, size: 46),
                  name: comp.name,
                  line: '${comp.creature.companion?.name ?? 'Companion'} · once per encounter',
                  label: '${comp.name}, ${comp.creature.companion?.name ?? 'companion'}, once per encounter. Ready',
                  trailing: Container(
                    padding: const EdgeInsets.fromLTRB(10, 2, 10, 2),
                    decoration: BoxDecoration(color: const Color(0xFFE5F2CF), borderRadius: BorderRadius.circular(10)),
                    child: const Text('Ready', style: TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w900, fontSize: 12, color: Color(0xFF3E7D33))),
                  ),
                ),
              ],
              if (comps.isEmpty) ...[
                const SizedBox(height: 8),
                const _TeamRow(ghost: true, face: EncFace.question(size: 46), name: 'Companion', line: 'Befriend one to help in encounters', label: 'Companion: befriend one to help in encounters'),
              ],
              if (!stageOk)
                Padding(
                  padding: const EdgeInsets.fromLTRB(2, 10, 2, 0),
                  child: Text('A ${stageLabel(e.recommended.stage)} or older Evochi has more Energy for this one. You can still go.', style: const TextStyle(fontFamily: EvochiText.body, fontSize: 12.5, height: 17 / 12.5, color: Color(0xFF9A5B2C))),
                ),
              const SizedBox(height: 18),
              // the call to action
              if (resumable)
                EncCta(label: 'Continue the encounter', big: true, gold: true, trailing: const _Chevron(), onTap: _resume)
              else if (ready)
                EncCta(label: 'Begin Encounter', big: true, gold: true, trailing: const _Chevron(), onTap: () => _travel(c, qid))
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
      ),
    );
  }
}

/// The creature's nameplate over the banner: its portrait, name, rarity and kind, the quest's level,
/// and its meter as it starts (Calm empty, Instability full).
class _Nameplate extends StatelessWidget {
  const _Nameplate({required this.cdef, required this.e, required this.level});
  final tr.Creature cdef;
  final tr.EncounterDef e;
  final int level;
  @override
  Widget build(BuildContext context) {
    final hollow = cdef.kind == 'hollow';
    final befriend = e.goal == 'befriend';
    final kind = '${_rarity[cdef.rarity] ?? ''} · ${hollow ? 'Hollow' : tr.affinityDefs[cdef.affinity]!.name}';
    final value = befriend ? '0 / ${e.meter}' : '${e.meter} / ${e.meter}';
    return Semantics(
      container: true,
      label: '${cdef.name}, $kind, level $level. ${befriend ? 'Calm' : 'Instability'} $value',
      child: ExcludeSemantics(
        // `.prep-plate`: card stock (lavender for the Hollow)
        child: Container(
          padding: const EdgeInsets.fromLTRB(9, 9, 12, 11),
          decoration: Kit.card(paper: hollow ? KitPaper.hollow : KitPaper.cream, radius: 16),
          child: Row(children: [
            EncFace.creature(cdef.id, size: 52, hollow: hollow),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                      Text(cdef.name, style: const TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w900, fontSize: 17, height: 1.15, color: EvochiColor.ink)),
                      Text(kind, style: const TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w800, fontSize: 12, color: EvochiColor.textHelper)),
                    ]),
                  ),
                  const SizedBox(width: 10),
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text('Lv. $level', style: const TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w900, fontSize: 13, color: EvochiColor.textSecondary)),
                  ),
                ]),
                const SizedBox(height: 6),
                Row(children: [
                  Expanded(child: ThinBar(kind: befriend ? 'calm' : 'inst', frac: befriend ? 0 : 1)),
                  const SizedBox(width: 8),
                  Text(value, style: const TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w900, fontSize: 12.5, color: EvochiColor.ink)),
                ]),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

/// A section heading ("Objective", "Recommended", "Your Team ?").
class _PrepHead extends StatelessWidget {
  const _PrepHead(this.text, {this.trailing});
  final String text;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 18, 2, 0),
        child: Row(children: [
          Semantics(header: true, child: Text(text, style: const TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w900, fontSize: 17, color: Color(0xFF4A2D45)))),
          if (trailing != null) ...[const SizedBox(width: 6), trailing!],
        ]),
      );
}

/// A recommendation tile: a small kicker, a picture on a soft tile, a name, an effect pill, a line
/// and an optional button.
class _RecTile extends StatelessWidget {
  const _RecTile({required this.kicker, required this.hollow, required this.picture, required this.name, required this.line, this.pill, this.restore = false, this.button});
  final String kicker;
  final bool hollow;
  final Widget picture;
  final String name;
  final String line;
  final String? pill;
  final bool restore;
  final Widget? button;
  @override
  Widget build(BuildContext context) => Semantics(
        container: true,
        child: Container(
          padding: const EdgeInsets.fromLTRB(8, 10, 8, 12),
          decoration: Kit.card(radius: 16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(kicker, textAlign: TextAlign.center, style: TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w800, fontSize: 12, color: hollow ? const Color(0xFF7B52C2) : const Color(0xFF5E9A3E))),
            const SizedBox(height: 5),
            Container(
              width: 56,
              height: 56,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: hollow ? const Color(0xFFF1E9FC) : const Color(0xFFEEF7E2), borderRadius: BorderRadius.circular(16)),
              child: picture,
            ),
            const SizedBox(height: 5),
            Text(name, textAlign: TextAlign.center, style: const TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w900, fontSize: 15, height: 1.15, color: EvochiColor.ink)),
            if (pill != null) ...[
              const SizedBox(height: 3),
              Container(
                padding: const EdgeInsets.fromLTRB(9, 1, 9, 1),
                decoration: BoxDecoration(color: restore ? const Color(0xFFEEE4FB) : const Color(0xFFE5F2CF), borderRadius: BorderRadius.circular(10)),
                child: Text(pill!, style: TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w900, fontSize: 12, color: restore ? const Color(0xFF5B3AA0) : const Color(0xFF3E7D33))),
              ),
            ],
            const SizedBox(height: 3),
            Text(line, textAlign: TextAlign.center, style: const TextStyle(fontFamily: EvochiText.body, fontSize: 12, height: 16 / 12, color: EvochiColor.textHelper)),
            if (button != null) ...[const SizedBox(height: 7), button!],
          ]),
        ),
      );
}

/// A team row: a round face, a name and a line, and something on the right (Energy, "Ready"); a
/// dashed [ghost] row waits for a companion.
class _TeamRow extends StatelessWidget {
  const _TeamRow({this.warn = false, this.ghost = false, required this.face, required this.name, required this.line, required this.label, this.trailing});
  final bool warn;
  final bool ghost;
  final Widget face;
  final String name;
  final String line;
  final String label;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) {
    final row = Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 12, 8),
      decoration: ghost ? null : Kit.card(paper: warn ? _warnPaper : KitPaper.cream, radius: 16),
      child: Row(children: [
        face,
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w900, fontSize: 15.5, height: 1.15, color: EvochiColor.ink)),
            Text(line, style: const TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w700, fontSize: 12, color: EvochiColor.textHelper)),
          ]),
        ),
        if (trailing != null) ...[const SizedBox(width: 10), trailing!],
      ]),
    );
    return Semantics(
      label: label,
      child: ExcludeSemantics(child: ghost ? CustomPaint(foregroundPainter: const _DashedRow(), child: row) : row),
    );
  }
}

/// The ghost row's dashed outline.
class _DashedRow extends CustomPainter {
  const _DashedRow();
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFEBDCC8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final path = Path()..addRRect(RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(16)).deflate(1));
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
  bool shouldRepaint(_DashedRow old) => false;
}

/// One line of the checklist: a tick box (dashed when optional), the text, an "optional" pill.
class _CheckRow extends StatelessWidget {
  const _CheckRow({required this.done, required this.text, this.optional = false});
  final bool done;
  final String text;
  final bool optional;
  @override
  Widget build(BuildContext context) => Semantics(
        label: '$text${done ? ', done' : ''}${optional ? ', optional' : ''}',
        child: ExcludeSemantics(
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
                child: const Text('optional', style: TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w800, fontSize: 12, color: EvochiColor.textHelper)),
              ),
          ]),
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

/// "Change" / "Make": the small cream button on the recommended item tile.
class _MiniButton extends StatelessWidget {
  const _MiniButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: label,
        // `.rec-tile .mini`: parchment with a wood edge, sinking when pressed
        child: KitPress(
          onTap: () {
            context.read<GameController>().audio.tick();
            onTap();
          },
          builder: (_, down) => AnimatedContainer(
            duration: const Duration(milliseconds: 60),
            transform: Matrix4.translationValues(0, down ? 2 : 0, 0),
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
            decoration: Kit.parchment(radius: 12, depth: down ? 1 : 3, drop: false),
            child: Text(label, style: const TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w900, fontSize: 13, color: EvochiColor.ink)),
          ),
        ),
      );
}

/// The chevron on Begin Encounter (the web's arrow path, stroked).
class _Chevron extends StatelessWidget {
  const _Chevron();
  @override
  Widget build(BuildContext context) => const SizedBox(width: 22, height: 22, child: CustomPaint(painter: _ChevronPainter()));
}

class _ChevronPainter extends CustomPainter {
  const _ChevronPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 24;
    final p = Path()
      ..moveTo(9 * s, 5 * s)
      ..lineTo(16 * s, 12 * s)
      ..lineTo(9 * s, 19 * s);
    canvas.drawPath(
      p,
      Paint()
        ..color = const Color(0xFF4A2E0C)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3 * s
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_ChevronPainter old) => false;
}
