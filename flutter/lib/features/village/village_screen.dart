// Village Tales, Chapter 1: Sunlit Village Square, the three interiors, the Waystone and villager
// dialogue (Quest Bible §8). No sixth tab: the Village opens from Home (Visit Village), story quests
// live in Journey > Story and quest items in Bag > Quest Pouch. Mirrors web/src/screens/village.js.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../controllers/game_controller.dart';
import '../../game/story/story.dart' as q;
import '../nest/sheets.dart';
import '../shared/widgets.dart';
import 'story_widgets.dart';

const _villageRoute = 'village';
const _placeRoute = 'place';

Route<void> _villageRouteFor() => MaterialPageRoute<void>(settings: const RouteSettings(name: _villageRoute), builder: (_) => const VillageScreen());

/// Open the Square from anywhere (Home, Journey > Story, the Quest Pouch, after a reward).
void openVillage(BuildContext context) {
  final nav = Navigator.of(context);
  final here = ModalRoute.of(context)?.settings.name;
  if (here == _villageRoute) return;
  if (here == _placeRoute) {
    // places always sit on top of the Square (see openPlace)
    nav.popUntil((r) => r.settings.name == _villageRoute || r.isFirst);
    return;
  }
  nav.push(_villageRouteFor());
}

/// Open a place. From one place to another the route is replaced, so Back always returns to the Square.
void openPlace(BuildContext context, String id, {String? npc}) {
  final nav = Navigator.of(context);
  final here = ModalRoute.of(context)?.settings.name;
  final route = MaterialPageRoute<void>(settings: const RouteSettings(name: _placeRoute), builder: (_) => PlaceScreen(placeId: id, npc: npc));
  if (here == _placeRoute) {
    nav.pushReplacement(route);
    return;
  }
  // opened from Journey, the Bag or Home: put the Square underneath so Back lands there
  if (here != _villageRoute) nav.push(_villageRouteFor());
  nav.push(route);
}

/// Back to the Square after a reward.
void returnToVillage(BuildContext context) => openVillage(context);

class _Header extends StatelessWidget {
  const _Header({required this.title, required this.short, required this.onBack, required this.backLabel});
  final String title;
  final String short;
  final VoidCallback onBack;
  final String backLabel;
  @override
  Widget build(BuildContext context) {
    final c = context.watch<GameController>();
    final narrow = MediaQuery.of(context).size.width < 360;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Row(children: [
        Semantics(label: backLabel, child: BackSquareButton(onTap: onBack)),
        const SizedBox(width: 8),
        Expanded(
          child: Semantics(
            header: true,
            label: title,
            child: ExcludeSemantics(
              child: Container(
                height: 42,
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE2CDB4), width: 2),
                  gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFFFF9F0), Color(0xFFF3E4D1)]),
                  boxShadow: const [BoxShadow(color: Color(0xFFCDB396), offset: Offset(0, 3))],
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(narrow ? short : title, style: EvochiText.section.copyWith(fontWeight: FontWeight.w900, fontSize: 19)),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        CoinPill(balance: c.balance, onPlus: () => showCoinsInfo(context)),
      ]),
    );
  }
}

class _Pin {
  const _Pin(this.id, this.label, this.npcs);
  final String id;
  final String label;
  final List<String> npcs;
}

const _pins = [
  _Pin('lodge', 'Trail Guild', ['npc_pip', 'npc_alder']),
  _Pin('glasshouse', 'Glasshouse', ['npc_mira']),
  _Pin('workshop', 'Workshop', ['npc_bram']),
  _Pin('waystone', 'Waystone', ['waystone']),
];
const _placeIcon = {'glasshouse': 'care', 'workshop': 'bell', 'lodge': 'mail', 'waystone': 'star'};

/// What a place's pin shows: a marker ('handin' | 'quest') and/or a lock note.
(String?, String?) _placeState(GameController c, String id) {
  final st = c.storyView;
  final marks = q.npcMarkers(c.state);
  final pin = _pins.firstWhere((p) => p.id == id);
  final mark = pin.npcs.map((n) => marks[n]).whereType<String>().firstOrNull;
  String? lock;
  if (id == 'lodge') {
    final v = st.quest('vq02');
    if (v.phase == 'locked') lock = v.lock!.needLevel ? 'Quests from Lv ${v.level}' : 'Quests later';
  }
  if (id == 'waystone' && !st.flag('waystone_revealed')) lock = 'A sleeping stone';
  return (mark, lock);
}

class _Mark extends StatelessWidget {
  const _Mark(this.kind);
  final String kind;
  @override
  Widget build(BuildContext context) => Container(
        width: 24,
        height: 24,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: kind == 'handin' ? EvochiColor.steps : EvochiColor.primary,
          border: Border.all(color: const Color(0xFFFFF6EC), width: 2),
          boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 4, offset: Offset(0, 2))],
        ),
        child: kind == 'handin'
            ? const Icon(Icons.check_rounded, size: 15, color: EvochiColor.ink)
            : Text('!', style: EvochiText.tag.copyWith(color: EvochiColor.ink, fontSize: 15, fontWeight: FontWeight.w900)),
      );
}

// ------------------------------------------------------------------- the Square ----
class VillageScreen extends StatefulWidget {
  const VillageScreen({super.key});
  @override
  State<VillageScreen> createState() => _VillageScreenState();
}

class _VillageScreenState extends State<VillageScreen> {
  @override
  void initState() {
    super.initState();
    // re-check story walks on entering the Village
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<GameController>().run((s, n) => q.storyTick(s, n), quiet: true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<GameController>();
    final st = c.storyView;
    final va = villageArt;
    final size = va.squareSize;
    final nu = st.nextUp;
    final lit = st.flag('lamp_lit');
    final restored = st.flag('waystone_restored');
    return Scaffold(
      backgroundColor: EvochiColor.panel,
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          _Header(title: 'Sunlit Village', short: 'Village', backLabel: 'Back to your nest', onBack: () => Navigator.of(context).maybePop()),
          Expanded(
            child: ListView(padding: EdgeInsets.only(bottom: 20 + MediaQuery.of(context).padding.bottom), children: [
              AspectRatio(
                aspectRatio: size.width / size.height,
                child: LayoutBuilder(builder: (ctx, b) {
                  return Stack(clipBehavior: Clip.hardEdge, children: [
                    Positioned.fill(
                      child: Image.asset(
                        va.square(lampLit: lit, restored: restored),
                        fit: BoxFit.cover,
                        semanticLabel: "Sunlit Village Square: Mira's Glasshouse on the left, Bram's Workshop on the right, the Trail Guild Lodge up the road and the Waystone in the middle${lit ? '. The nursery lamp is lit.' : '.'}",
                      ),
                    ),
                    for (final p in _pins)
                      Positioned(
                        left: va.anchor(p.id).dx / size.width * b.maxWidth,
                        top: va.anchor(p.id).dy / size.height * b.maxHeight,
                        child: FractionalTranslation(translation: const Offset(-0.5, -1), child: _PinButton(pin: p)),
                      ),
                  ]);
                }),
              ),
              Transform.translate(
                offset: const Offset(0, -14),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    if (nu != null)
                      Semantics(
                        button: true,
                        label: '${nu.title}. ${nextText(nu)}',
                        child: GestureDetector(
                          onTap: () => showStoryQuest(context, nu.id),
                          child: GameCard(
                            padding: const EdgeInsets.fromLTRB(8, 10, 12, 10),
                            child: Row(children: [
                              SizedBox(width: 54, height: 60, child: NpcImage(nu.giver, expression: nu.next.kind == 'handin' ? 'happy' : 'neutral', height: 60)),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(nu.accepted ? 'Current story' : (nu.phase == 'locked' ? 'Coming up' : 'New story'), style: EvochiText.caption),
                                  Text(nu.title, style: EvochiText.cardTitle),
                                  Text(nextText(nu), style: EvochiText.bodyText.copyWith(color: EvochiColor.textSecondary)),
                                  if (nu.accepted) Padding(padding: const EdgeInsets.only(top: 6), child: WalkProgress(nu)),
                                ]),
                              ),
                              const Text('›', style: TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w900, fontSize: 24, color: EvochiColor.textHelper)),
                            ]),
                          ),
                        ),
                      )
                    else
                      const GameCard(
                        padding: EdgeInsets.fromLTRB(8, 10, 12, 10),
                        child: Row(children: [
                          VoxelIcon('star', size: 44),
                          SizedBox(width: 10),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text('Chapter 1 complete', style: EvochiText.cardTitle),
                              Text('Every path has a little light again. More Village Tales are on the way.', style: EvochiText.bodyText),
                            ]),
                          ),
                        ]),
                      ),
                    const SizedBox(height: 14),
                    Row(children: [
                      Container(width: 6, height: 18, decoration: BoxDecoration(color: EvochiColor.primary, borderRadius: BorderRadius.circular(3))),
                      const SizedBox(width: 8),
                      Semantics(header: true, child: const Text('Places', style: EvochiText.section)),
                    ]),
                    const SizedBox(height: 8),
                    GridView.count(
                      crossAxisCount: 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                      childAspectRatio: 1.02,
                      children: [for (final p in _pins) _PlaceCard(id: p.id)],
                    ),
                    const SizedBox(height: 10),
                    Semantics(
                      button: true,
                      label: 'Evochi Market. Story rewards are never sold here.',
                      child: GestureDetector(
                        onTap: () => c.goTab('shop'),
                        child: const GameCard(
                          child: Row(children: [
                            VoxelIcon('shop', size: 40),
                            SizedBox(width: 10),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text('Evochi Market', style: EvochiText.cardTitle),
                                Text('The village shop. Story rewards are never sold here.', style: EvochiText.caption),
                              ]),
                            ),
                            Text('›', style: TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w900, fontSize: 24, color: EvochiColor.textHelper)),
                          ]),
                        ),
                      ),
                    ),
                  ]),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _PinButton extends StatelessWidget {
  const _PinButton({required this.pin});
  final _Pin pin;
  @override
  Widget build(BuildContext context) {
    final c = context.watch<GameController>();
    final (mark, lock) = _placeState(c, pin.id);
    final name = q.places[pin.id]!.name;
    return Semantics(
      button: true,
      label: '$name${mark == 'handin' ? ', something to hand in' : (mark == 'quest' ? ', new quest' : '')}${lock != null ? ', $lock' : ''}',
      child: ExcludeSemantics(
        child: GestureDetector(
          onTap: () {
            c.audio.play('ui_tap', volume: 0.4);
            openPlace(context, pin.id);
          },
          child: Stack(clipBehavior: Clip.none, children: [
            Container(
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: const Color(0xF2FFF9F0),
                border: Border.all(color: mark != null ? const Color(0xFFF0B952) : const Color(0xFFE2CDB4), width: 2),
                boxShadow: const [BoxShadow(color: Color(0xFFCDB396), offset: Offset(0, 3)), BoxShadow(color: Color(0x40281910), blurRadius: 10, offset: Offset(0, 4))],
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(pin.label, style: EvochiText.cardTitle.copyWith(fontSize: 13, fontWeight: FontWeight.w900)),
                if (lock != null)
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    const VoxelIcon('lock', size: 13),
                    const SizedBox(width: 2),
                    Text(lock, style: EvochiText.tag.copyWith(fontSize: 11)),
                  ]),
              ]),
            ),
            if (mark != null) Positioned(top: -12, right: -10, child: _Mark(mark)),
          ]),
        ),
      ),
    );
  }
}

class _PlaceCard extends StatelessWidget {
  const _PlaceCard({required this.id});
  final String id;
  @override
  Widget build(BuildContext context) {
    final c = context.watch<GameController>();
    final st = c.storyView;
    final (mark, lock) = _placeState(c, id);
    final p = q.places[id]!;
    final thumb = id == 'waystone' ? villageArt.waystone(restored: st.flag('waystone_restored')) : villageArt.place(id);
    return Semantics(
      button: true,
      label: '${p.name}. ${lock ?? p.blurb}${mark != null ? '. Something new here' : ''}',
      child: ExcludeSemantics(
        child: GestureDetector(
          onTap: () => openPlace(context, id),
          child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE6D3BD), width: 2),
              color: EvochiColor.canvas,
              boxShadow: const [BoxShadow(color: EvochiColor.cardBevel, offset: Offset(0, 3))],
            ),
            child: Stack(children: [
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                SizedBox(height: 84, child: Image.asset(thumb, fit: BoxFit.cover)),
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
                  child: Row(children: [
                    VoxelIcon(_placeIcon[id]!, size: 20),
                    const SizedBox(width: 5),
                    Expanded(child: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: EvochiText.cardTitle.copyWith(fontSize: 14, fontWeight: FontWeight.w900))),
                  ]),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 2, 8, 8),
                  child: Text(lock ?? p.blurb, maxLines: 2, overflow: TextOverflow.ellipsis, style: EvochiText.caption.copyWith(color: EvochiColor.textSecondary, fontWeight: FontWeight.w700)),
                ),
              ]),
              if (mark != null) const Positioned(top: 6, right: 6, child: BadgeDot()),
            ]),
          ),
        ),
      ),
    );
  }
}

// --------------------------------------------------------------- places + dialogue ----
class PlaceScreen extends StatefulWidget {
  const PlaceScreen({super.key, required this.placeId, this.npc});
  final String placeId;
  final String? npc;
  @override
  State<PlaceScreen> createState() => _PlaceScreenState();
}

class _PlaceScreenState extends State<PlaceScreen> with SingleTickerProviderStateMixin {
  late String _npc;
  String? _node;
  String? _convNpc;
  Map<String, q.ConvNode> _extraNodes = const {};
  String? _flare; // give | restore
  Timer? _flareTimer;
  late final AnimationController _idle = AnimationController(vsync: this, duration: const Duration(milliseconds: 2600));

  q.Place get _place => q.places[widget.placeId]!;
  bool get _isWay => widget.placeId == 'waystone';

  @override
  void initState() {
    super.initState();
    final c = context.read<GameController>();
    if (_isWay) {
      _npc = 'waystone';
    } else {
      final marks = q.npcMarkers(c.state);
      _npc = widget.npc ?? _place.npcs.where((n) => marks.containsKey(n)).firstOrNull ?? _place.npcs.first;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) c.run((s, n) => q.markNpcMet(s, _npc), quiet: true);
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.of(context).disableAnimations) {
      _idle.stop();
    } else if (!_idle.isAnimating) {
      _idle.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _flareTimer?.cancel();
    _idle.dispose();
    super.dispose();
  }

  /// The current line node. The opening graph stays reachable after an action moves the story on,
  /// so the follow-up line still shows until the player moves on.
  (q.ConvNode, Map<String, q.ConvNode>) _current(GameController c) {
    final conv = q.npcConversation(c.state, _npc, c.now);
    if (_node == null || _convNpc != _npc) {
      _node = conv.start;
      _convNpc = _npc;
      _extraNodes = conv.nodes;
    }
    final nodes = {..._extraNodes, ...conv.nodes};
    if (!nodes.containsKey(_node)) _node = conv.start;
    return (nodes[_node]!, nodes);
  }

  void _switchNpc(GameController c, String n) {
    if (_npc == n) return;
    setState(() {
      _npc = n;
      _node = null;
    });
    c.audio.play('ui_tap', volume: 0.4);
    if (c.state.story.npcsMet[n] != true) c.run((s, t) => q.markNpcMet(s, n), quiet: true);
  }

  void _choose(GameController c, q.Choice ch, Map<String, q.ConvNode> nodes) {
    if (ch.leave) {
      c.audio.play('ui_tap', volume: 0.4);
      Navigator.of(context).maybePop();
      return;
    }
    if (ch.goto != null) {
      if (ch.goto == 'journey') {
        c.goTab('journey', journey: 'daily');
      } else {
        openPlace(context, ch.goto!);
      }
      return;
    }
    if (ch.npc != null) {
      _switchNpc(c, ch.npc!);
      return;
    }
    if (ch.reward != null) {
      _node = null;
      showStoryReward(context, ch.reward!);
      return;
    }
    final act = ch.act;
    if (act != null) {
      final r = act.kind == 'accept'
          ? c.run((s, n) => q.acceptStoryQuest(s, act.quest, n))
          : c.run((s, n) => q.storyHandIn(s, act.quest, act.turnIn!, n));
      if (!r.ok) return;
      setState(() {
        _extraNodes = nodes; // keep this conversation's lines after the state moved on
        _node = ch.then;
      });
      if (act.kind == 'accept') {
        c.audio.play('reward_chime', volume: 0.6);
        c.toast('Story quest started: ${q.storyQuests[act.quest]!.title}', icon: 'journey');
      } else {
        final restore = act.turnIn == 'restore';
        c.audio.play(restore ? 'evolve_fanfare' : 'purchase');
        setState(() => _flare = restore ? 'restore' : 'give');
        _flareTimer?.cancel();
        _flareTimer = Timer(const Duration(milliseconds: 1400), () {
          if (mounted) setState(() => _flare = null);
        });
      }
      return;
    }
    if (ch.next != null) {
      c.audio.play('ui_tap', volume: 0.3);
      setState(() => _node = ch.next);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<GameController>();
    final st = c.storyView;
    final (node, nodes) = _current(c);
    final line = q.lines[node.id]!;
    final speaker = speakers[line.speaker] ?? speakers['waystone']!;
    final text = q.lineText(c.state, node.id, c.now, petName: c.state.pet?.name ?? 'your Evochi');
    final va = villageArt;
    final restored = st.flag('waystone_restored') || _flare == 'restore';
    final plate = _isWay ? va.waystone(restored: restored) : va.place(widget.placeId);
    final plateSize = _isWay ? va.waystoneSize : va.placeSize(widget.placeId);
    final npcList = _isWay ? const <String>[] : _place.npcs;
    final duo = npcList.length > 1;
    final marks = q.npcMarkers(c.state);
    String exprFor(String n) => line.speaker == n ? (line.expression ?? 'neutral') : 'neutral';
    final activeQuest = st.quests.where((v) => v.accepted && !v.completed && (v.next.npc == _npc || v.giver == _npc)).firstOrNull ??
        st.quests.where((v) => v.phase == 'available' && v.giver == _npc).firstOrNull;
    const finale = ['VQ03_MIR02', 'VQ03_BRA02', 'VQ03_PIP08', 'VQ03_ALD05'];
    return Scaffold(
      backgroundColor: EvochiColor.panel,
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          _Header(title: _place.name, short: _place.short, backLabel: 'Back to the Square', onBack: () => Navigator.of(context).maybePop()),
          Expanded(
            child: ListView(padding: EdgeInsets.only(bottom: 16 + MediaQuery.of(context).padding.bottom), children: [
              AspectRatio(
                aspectRatio: plateSize.width / plateSize.height,
                child: LayoutBuilder(builder: (ctx, b) {
                  final h = b.maxHeight * (duo ? 0.56 : 0.70);
                  return Stack(clipBehavior: Clip.hardEdge, children: [
                    Positioned.fill(child: Image.asset(plate, fit: BoxFit.cover, excludeFromSemantics: true, gaplessPlayback: true)),
                    const Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      height: 60,
                      child: IgnorePointer(
                        child: DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x00F8EBDD), Color(0xA6F8EBDD)]))),
                      ),
                    ),
                    for (var i = 0; i < npcList.length; i++)
                      Positioned(
                        left: duo && i == 1 ? null : b.maxWidth * (duo ? 0.03 : 0.05),
                        right: duo && i == 1 ? b.maxWidth * 0.03 : null,
                        bottom: b.maxHeight * 0.04,
                        height: h,
                        child: _NpcButton(
                          npcId: npcList[i],
                          expression: exprFor(npcList[i]),
                          active: npcList[i] == _npc,
                          flip: duo && i == 1,
                          mark: npcList[i] != _npc ? marks[npcList[i]] : null,
                          idle: _idle,
                          height: h,
                          tint: _roomTint[widget.placeId],
                          onTap: () => _switchNpc(c, npcList[i]),
                        ),
                      ),
                    if (_isWay && finale.contains(node.id))
                      Positioned(
                        left: b.maxWidth * 0.04,
                        bottom: b.maxHeight * 0.03,
                        height: b.maxHeight * 0.46,
                        child: NpcImage(line.speaker, expression: line.expression ?? 'happy', height: b.maxHeight * 0.46),
                      ),
                    Positioned.fill(
                      child: IgnorePointer(
                        child: AnimatedOpacity(
                          opacity: _flare == null ? 0 : 1,
                          duration: Duration(milliseconds: _flare == null ? 900 : 250),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: RadialGradient(
                                center: _isWay ? Alignment.center : const Alignment(-0.32, 0.28),
                                radius: 0.6,
                                colors: _isWay ? const [Color(0xF2BEF5E4), Color(0x009FE3CF)] : const [Color(0xD9FFECAA), Color(0x00FFD66E)],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ]);
                }),
              ),
              if (duo)
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
                  child: Row(children: [
                    for (final n in npcList)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 3),
                          child: _NpcTab(npcId: n, selected: n == _npc, badge: marks.containsKey(n), onTap: () => _switchNpc(c, n)),
                        ),
                      ),
                  ]),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
                child: Semantics(
                  liveRegion: true,
                  label: speaker.name,
                  child: GameCard(
                    color: EvochiColor.canvas,
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                        Flexible(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            decoration: BoxDecoration(
                              color: speaker.color,
                              borderRadius: BorderRadius.circular(10),
                              boxShadow: const [BoxShadow(color: Color(0x33000000), offset: Offset(0, 2))],
                            ),
                            child: Text.rich(
                              TextSpan(children: [
                                TextSpan(text: speaker.name, style: EvochiText.cardTitle.copyWith(color: Colors.white, fontWeight: FontWeight.w900)),
                                if (speaker.role.isNotEmpty)
                                  TextSpan(text: '  ${speaker.role}', style: EvochiText.tag.copyWith(color: const Color(0xD9FFFFFF), fontSize: 12)),
                              ]),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        if (activeQuest != null) ...[
                          const SizedBox(width: 8),
                          EvochiButton(
                            label: 'Quest',
                            small: true,
                            expand: false,
                            tone: ButtonTone.cream,
                            icon: const VoxelIcon('journey', size: 22),
                            onPressed: () => showStoryQuest(context, activeQuest.id),
                          ),
                        ],
                      ]),
                      const SizedBox(height: 10),
                      Text(text, style: EvochiText.bodyText.copyWith(fontSize: 16, height: 1.45, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 12),
                      for (final ch in node.choices) ...[
                        _ChoiceButton(choice: ch, onTap: () => _choose(c, ch, nodes)),
                        const SizedBox(height: 10),
                      ],
                    ]),
                  ),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _NpcButton extends StatelessWidget {
  const _NpcButton({
    required this.npcId,
    required this.expression,
    required this.active,
    required this.flip,
    required this.mark,
    required this.idle,
    required this.height,
    required this.onTap,
    this.tint,
  });
  final String npcId;
  final String expression;
  final bool active;
  final bool flip;
  final String? mark;
  final Animation<double> idle;
  final double height;
  final VoidCallback onTap;
  final List<double>? tint; // a little of the room's light (sprites are shared between places)
  @override
  Widget build(BuildContext context) {
    final sz = villageArt.npcSize(npcId);
    final w = height * sz.width / sz.height;
    final g = villageArt.npcGround(npcId);
    final gx = flip ? 1 - g.dx : g.dx;
    Widget img = NpcImage(npcId, expression: expression, height: height, flip: flip);
    if (tint != null) img = ColorFiltered(colorFilter: ColorFilter.matrix(tint!), child: img);
    if (!active) img = ColorFiltered(colorFilter: const ColorFilter.matrix(_dim), child: img);
    return Semantics(
      button: true,
      selected: active,
      label: 'Talk to ${speakers[npcId]!.name}',
      child: GestureDetector(
        onTap: onTap,
        child: SizedBox(
          width: w,
          height: height,
          child: Stack(clipBehavior: Clip.none, children: [
            // soft contact shadow on the floor, under the feet
            Positioned(
              left: w * (gx - 0.25),
              top: height * g.dy - height * 0.045,
              width: w * 0.5,
              height: height * 0.09,
              child: IgnorePointer(child: CustomPaint(painter: _ContactShadow())),
            ),
            AnimatedBuilder(
              animation: idle,
              builder: (_, child) => Transform(
                alignment: Alignment.bottomCenter,
                transform: Matrix4.diagonal3Values(1, 1 + 0.018 * idle.value, 1),
                child: child,
              ),
              child: img,
            ),
            if (mark != null) Positioned(top: 0, right: w * 0.12, child: _Mark(mark!)),
          ]),
        ),
      ),
    );
  }
}

class _ContactShadow extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = const Color(0x7324160A)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, size.height * 0.35);
    canvas.drawOval(Rect.fromLTWH(size.width * 0.1, size.height * 0.15, size.width * 0.8, size.height * 0.7), p);
  }

  @override
  bool shouldRepaint(_ContactShadow oldDelegate) => false;
}

// each room's light on the villagers: warm lanterns in the Workshop and Lodge, daylight in the Glasshouse
const _roomTint = <String, List<double>>{
  'workshop': [
    1.02, 0.04, 0.0, 0, 0, //
    0.02, 0.95, 0.0, 0, 0, //
    0.0, 0.02, 0.86, 0, 0, //
    0, 0, 0, 1, 0,
  ],
  'lodge': [
    1.0, 0.02, 0.0, 0, 0, //
    0.01, 0.97, 0.0, 0, 0, //
    0.0, 0.01, 0.92, 0, 0, //
    0, 0, 0, 1, 0,
  ],
};

// a touch darker and less saturated for the villager who isn't talking
const _dim = <double>[
  0.84, 0.06, 0.02, 0, 0, //
  0.03, 0.86, 0.03, 0, 0, //
  0.02, 0.06, 0.84, 0, 0, //
  0, 0, 0, 1, 0,
];

class _NpcTab extends StatelessWidget {
  const _NpcTab({required this.npcId, required this.selected, required this.badge, required this.onTap});
  final String npcId;
  final bool selected;
  final bool badge;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
        selected: selected,
        button: true,
        label: speakers[npcId]!.name,
        child: GestureDetector(
          onTap: onTap,
          child: Stack(clipBehavior: Clip.none, children: [
            Container(
              height: 48,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: selected ? const Color(0xFFF0B952) : const Color(0xFFE2CDB4), width: 2),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: selected ? const [Color(0xFFFFF4D6), Color(0xFFFFE1A1)] : const [Color(0xFFFBF2E7), Color(0xFFEFE0CD)],
                ),
              ),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                NpcImage(npcId, height: 30),
                const SizedBox(width: 4),
                Text(speakers[npcId]!.name, style: EvochiText.tag.copyWith(color: selected ? EvochiColor.ink : EvochiColor.textSecondary)),
              ]),
            ),
            if (badge) const Positioned(top: -4, right: -4, child: BadgeDot()),
          ]),
        ),
      );
}

/// A dialogue choice: left-aligned, wraps to two lines, shows the items being handed over.
class _ChoiceButton extends StatelessWidget {
  const _ChoiceButton({required this.choice, required this.onTap});
  final q.Choice choice;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final primary = choice.primary;
    final act = choice.act;
    final give = act != null && act.kind == 'handin'
        ? q.storyQuests[act.quest]!.turnIns.firstWhere((t) => t.id == act.turnIn).consume
        : const <String, int>{};
    return Semantics(
      button: true,
      label: choice.label,
      child: ExcludeSemantics(
        child: GestureDetector(
          onTap: () {
            context.read<GameController>().audio.tick();
            onTap();
          },
          child: Container(
            constraints: const BoxConstraints(minHeight: 50),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: primary ? EvochiColor.primaryShadow : const Color(0xFFCDB396), width: 2),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: primary ? const [EvochiColor.gold100, EvochiColor.primary] : const [Color(0xFFFFFBF4), Color(0xFFEEDCC6)],
              ),
              boxShadow: [BoxShadow(color: primary ? EvochiColor.primaryShadow : const Color(0xFFCDB396), offset: const Offset(0, 4))],
            ),
            child: Row(children: [
              if (give.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.fromLTRB(2, 2, 6, 2),
                  decoration: BoxDecoration(color: const Color(0x8CFFFFFF), borderRadius: BorderRadius.circular(9)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    for (final e in give.entries) ...[
                      ItemImage(e.key, size: 34),
                      if (e.value > 1) Text('x${e.value}', style: EvochiText.tag.copyWith(color: EvochiColor.ink, fontWeight: FontWeight.w900)),
                    ],
                  ]),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(child: Text(choice.label, maxLines: 2, overflow: TextOverflow.ellipsis, style: EvochiText.button.copyWith(fontSize: 16))),
            ]),
          ),
        ),
      ),
    );
  }
}
