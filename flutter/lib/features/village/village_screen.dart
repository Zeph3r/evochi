// Village Tales, Chapter 1: Sunlit Village Square, the three interiors, the Waystone and villager
// dialogue (Quest Bible §8). No sixth tab: the Village opens from Home (Visit Village), story quests
// live in Journey > Story and quest items in Bag > Quest Pouch. Mirrors web/src/screens/village.js.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../controllers/game_controller.dart';
import '../../game/story/story.dart' as q;
import '../nest/sheets.dart';
import '../shared/widgets.dart';
import 'npc_puppet.dart';
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
                SizedBox(height: 84, child: Image.asset(thumb, fit: BoxFit.cover, alignment: const Alignment(0, -0.16))),
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

class _PlaceScreenState extends State<PlaceScreen> {
  late String _npc;
  String? _node;
  String? _convNpc;
  Map<String, q.ConvNode> _extraNodes = const {};
  String? _flare; // give | restore
  Timer? _flareTimer;
  // the line types in once (24 ms a character); tap the speech box to finish it or carry on
  String? _typedKey;
  int _shown = 0;
  bool _typedDone = true;
  Timer? _typer;
  bool _reduce = false;

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
    _reduce = MediaQuery.of(context).disableAnimations;
  }

  @override
  void dispose() {
    _flareTimer?.cancel();
    _typer?.cancel();
    super.dispose();
  }

  /// Start typing a new line (called from build when the line changes).
  void _typeLine(String key, int length, bool reduce) {
    if (_typedKey == key) return;
    _typer?.cancel();
    _typedKey = key;
    if (reduce) {
      _shown = length;
      _typedDone = true;
      return;
    }
    _shown = 0;
    _typedDone = false;
    final start = DateTime.now();
    _typer = Timer.periodic(const Duration(milliseconds: 24), (t) {
      if (!mounted) return t.cancel();
      final n = DateTime.now().difference(start).inMilliseconds ~/ 24;
      setState(() {
        _shown = math.min(n, length);
        if (_shown >= length) {
          _typedDone = true;
          t.cancel();
        }
      });
    });
  }

  void _finishLine(int length) {
    _typer?.cancel();
    setState(() {
      _shown = length;
      _typedDone = true;
    });
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
    final classic = c.state.player?.settings.classicVillagers ?? false;
    final reduce = _reduce || (c.state.player?.settings.reducedMotion ?? false);
    final key = '${widget.placeId}:$_npc:${node.id}';
    _typeLine(key, text.length, reduce);
    final typed = _typedDone;
    String stateFor(String n) => line.speaker == n ? (typed ? 'idle' : 'talk') : (npcList.contains(line.speaker) ? 'listen' : 'idle');
    final single = node.choices.length == 1 && node.choices.first.next != null && node.choices.first.act == null;
    final mq = MediaQuery.of(context);
    const overlap = 64.0;
    return Scaffold(
      backgroundColor: EvochiColor.panel,
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          _Header(title: _place.name, short: _place.short, backLabel: 'Back to the Square', onBack: () => Navigator.of(context).maybePop()),
          Expanded(
            child: LayoutBuilder(builder: (ctx, outer) {
              final w = outer.maxWidth;
              final stageH = w * plateSize.height / plateSize.width;
              final visibleH = math.min(stageH, math.max(340.0, mq.size.height - 300));
              final speakerX = npcList.contains(line.speaker) ? villageArt.puppet(line.speaker)?.gx : null;
              final tailX = (speakerX ?? (_isWay ? 0.22 : 0.5)).clamp(0.14, 0.86).toDouble();
              return ListView(padding: EdgeInsets.only(bottom: 16 + mq.padding.bottom), children: [
                // the room: taller than its slot by `overlap`, so the speech box sits over its floor
                SizedBox(
                  height: visibleH - overlap,
                  child: OverflowBox(
                    alignment: Alignment.topCenter,
                    minHeight: visibleH,
                    maxHeight: visibleH,
                    child: ClipRect(
                      child: OverflowBox(
                        alignment: Alignment.bottomCenter,
                        minHeight: stageH,
                        maxHeight: stageH,
                        child: SizedBox(
                          width: w,
                          height: stageH,
                          child: Stack(clipBehavior: Clip.hardEdge, children: [
                            Positioned.fill(
                              child: ColorFiltered(
                                colorFilter: const ColorFilter.matrix(_backdrop),
                                child: Image.asset(plate, fit: BoxFit.cover, excludeFromSemantics: true, gaplessPlayback: true),
                              ),
                            ),
                            // depth: a soft vignette and a fade into the page keep the eye on the villagers
                            const Positioned.fill(
                              child: IgnorePointer(
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    gradient: RadialGradient(center: Alignment(0, 0.2), radius: 1.05, colors: [Color(0x001E1208), Color(0x001E1208), Color(0x3D1E1208)], stops: [0, 0.55, 1]),
                                  ),
                                ),
                              ),
                            ),
                            const Positioned.fill(
                              child: IgnorePointer(
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: [Color(0x00F8EBDD), Color(0x00F8EBDD), Color(0x80F8EBDD), Color(0xFFF8EBDD)],
                                      stops: [0, 0.8, 0.92, 1],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            for (final n in npcList)
                              _StageNpc(
                                npcId: n,
                                stageW: w,
                                stageH: stageH,
                                expression: exprFor(n),
                                state: stateFor(n),
                                active: n == _npc,
                                talking: line.speaker == n,
                                duo: duo,
                                mark: n != _npc ? marks[n] : null,
                                classic: classic,
                                animate: !reduce,
                                onTap: () => _switchNpc(c, n),
                              ),
                            if (_isWay && finale.contains(node.id))
                              Positioned(
                                left: w * 0.04,
                                bottom: stageH * 0.14,
                                height: stageH * 0.46,
                                child: NpcImage(line.speaker, expression: line.expression ?? 'happy', height: stageH * 0.46),
                              ),
                            Positioned.fill(
                              child: IgnorePointer(
                                child: AnimatedOpacity(
                                  opacity: _flare == null ? 0 : 1,
                                  duration: Duration(milliseconds: _flare == null ? 900 : 250),
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      gradient: RadialGradient(
                                        center: _isWay ? Alignment.center : const Alignment(-0.28, 0.24),
                                        radius: 0.6,
                                        colors: _isWay ? const [Color(0xF2BEF5E4), Color(0x009FE3CF)] : const [Color(0xD9FFECAA), Color(0x00FFD66E)],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ]),
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: _SpeechBox(
                    speaker: speaker,
                    text: text,
                    shown: typed ? text.length : _shown,
                    done: typed,
                    more: single,
                    tailX: tailX,
                    quest: activeQuest == null ? null : () => showStoryQuest(context, activeQuest.id),
                    onTap: () {
                      if (!typed) {
                        _finishLine(text.length);
                      } else if (single) {
                        _choose(c, node.choices.first, nodes);
                      }
                    },
                  ),
                ),
                const SizedBox(height: 14),
                AnimatedOpacity(
                  opacity: typed ? 1 : 0.55,
                  duration: const Duration(milliseconds: 250),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      for (final ch in node.choices) ...[
                        _ChoiceButton(choice: ch, onTap: () => _choose(c, ch, nodes)),
                        const SizedBox(height: 10),
                      ],
                    ]),
                  ),
                ),
              ]);
            }),
          ),
        ]),
      ),
    );
  }
}

// the room plate sits back a touch so the villagers and the dialogue read first
const _backdrop = <double>[
  0.92, 0.05, 0.0, 0, 0, //
  0.02, 0.94, 0.0, 0, 0, //
  0.01, 0.04, 0.89, 0, 0, //
  0, 0, 0, 1, 0,
];

/// A villager standing in the room: the animated puppet, a tap ring at their feet when you can switch
/// to them, a name chip over their head in shared rooms, and a quest marker.
class _StageNpc extends StatelessWidget {
  const _StageNpc({
    required this.npcId,
    required this.stageW,
    required this.stageH,
    required this.expression,
    required this.state,
    required this.active,
    required this.talking,
    required this.duo,
    required this.mark,
    required this.classic,
    required this.animate,
    required this.onTap,
  });
  final String npcId;
  final double stageW;
  final double stageH;
  final String expression;
  final String state;
  final bool active;
  final bool talking;
  final bool duo;
  final String? mark;
  final bool classic;
  final bool animate;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final art = villageArt.puppet(npcId);
    final size = villageArt.npcSize(npcId);
    final h = stageH * (art?.hf ?? 0.5);
    final w = h * size.width / size.height;
    final flip = art?.flip ?? false;
    final g = art?.ground ?? Offset(size.width / 2, size.height * 0.94);
    final gx = (flip ? size.width - g.dx : g.dx) / size.width;
    final gy = g.dy / size.height;
    final top = art?.top ?? Offset(size.width / 2, 0);
    final tx = (flip ? size.width - top.dx : top.dx) / size.width;
    final ty = top.dy / size.height;
    final left = stageW * (art?.gx ?? 0.36) - gx * w;
    final topPx = stageH * (art?.gy ?? 0.8) - gy * h;
    Widget fig = art == null
        ? NpcImage(npcId, expression: expression, height: h)
        : NpcPuppet(art: art, width: w, height: h, expression: expression, state: state, classic: classic, animate: animate);
    if (flip) fig = Transform.flip(flipX: true, child: fig);
    if (!active && !talking) fig = ColorFiltered(colorFilter: const ColorFilter.matrix(_dim), child: fig);
    return Positioned(
      left: left,
      top: topPx,
      width: w,
      height: h,
      child: Semantics(
        button: true,
        selected: active,
        label: 'Talk to ${speakers[npcId]!.name}${mark == 'handin' ? ', something to hand in' : mark != null ? ', new quest' : ''}',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Stack(clipBehavior: Clip.none, children: [
            if (!active) Positioned(left: gx * w - w * 0.31, top: gy * h - w * 0.09, width: w * 0.62, height: w * 0.18, child: _TapRing(animate: animate)),
            Positioned.fill(child: fig),
            if (duo)
              Positioned(
                left: tx * w - 60,
                top: ty * h - 34,
                width: 120,
                height: 28,
                child: Center(child: _NameChip(name: speakers[npcId]!.name, active: active, mark: mark)),
              )
            else if (mark != null)
              Positioned(left: tx * w - 18, top: ty * h - 44, child: _Mark(mark!)),
          ]),
        ),
      ),
    );
  }
}

// a touch darker and less saturated for the villager who isn't talking
const _dim = <double>[
  0.84, 0.06, 0.02, 0, 0, //
  0.03, 0.86, 0.03, 0, 0, //
  0.02, 0.06, 0.84, 0, 0, //
  0, 0, 0, 1, 0,
];

class _TapRing extends StatefulWidget {
  const _TapRing({required this.animate});
  final bool animate;
  @override
  State<_TapRing> createState() => _TapRingState();
}

class _TapRingState extends State<_TapRing> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
  @override
  void initState() {
    super.initState();
    if (widget.animate) _c.repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, child) => Opacity(opacity: 0.5 + 0.5 * _c.value, child: Transform.scale(scale: 0.9 + 0.14 * _c.value, child: child)),
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.rectangle,
              borderRadius: const BorderRadius.all(Radius.elliptical(200, 60)),
              border: Border.all(color: const Color(0xF2FFEEB2), width: 3),
              boxShadow: const [BoxShadow(color: Color(0xD9FFD26E), blurRadius: 10)],
            ),
          ),
        ),
      );
}

class _NameChip extends StatelessWidget {
  const _NameChip({required this.name, required this.active, this.mark});
  final String name;
  final bool active;
  final String? mark;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(
          color: active ? EvochiColor.gold100 : const Color(0xF5FFF9F0),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: active ? EvochiColor.primary : const Color(0xFFE2CDB4), width: 2),
          boxShadow: [BoxShadow(color: active ? EvochiColor.primaryShadow : const Color(0xFFCDB396), offset: const Offset(0, 2))],
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (mark != null && !active) ...[Transform.scale(scale: 0.8, child: _Mark(mark!)), const SizedBox(width: 2)],
          Text(name, style: EvochiText.tag.copyWith(color: EvochiColor.ink, fontWeight: FontWeight.w900)),
        ]),
      );
}

/// The storybook speech box: a name tab over its top edge, a tail pointing at the speaker, the line
/// typing in, and a nudge (▼) when tapping the box carries on.
class _SpeechBox extends StatelessWidget {
  const _SpeechBox({
    required this.speaker,
    required this.text,
    required this.shown,
    required this.done,
    required this.more,
    required this.tailX,
    required this.quest,
    required this.onTap,
  });
  final Speaker speaker;
  final String text;
  final int shown;
  final bool done;
  final bool more;
  final double tailX;
  final VoidCallback? quest;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const paper = Color(0xFFFFF9F0);
    const edge = Color(0xFFE2CDB4);
    return Semantics(
      liveRegion: true,
      label: '${speaker.name}: $text',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: LayoutBuilder(builder: (ctx, b) {
          return Stack(clipBehavior: Clip.none, children: [
            Container(
              margin: const EdgeInsets.only(top: 22),
              padding: const EdgeInsets.fromLTRB(16, 22, 16, 18),
              decoration: BoxDecoration(
                color: paper,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: edge, width: 2.5),
                boxShadow: const [
                  BoxShadow(color: Color(0xFFCDB396), offset: Offset(0, 4)),
                  BoxShadow(color: Color(0x3D28190A), blurRadius: 26, offset: Offset(0, 12)),
                ],
              ),
              child: ExcludeSemantics(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 50),
                  child: Text.rich(
                    TextSpan(children: [
                      TextSpan(text: text.substring(0, math.max(0, math.min(shown, text.length)))),
                      // the untyped rest keeps its space, so the box doesn't grow while typing
                      TextSpan(text: text.substring(math.max(0, math.min(shown, text.length))), style: const TextStyle(color: Color(0x00000000))),
                    ]),
                    style: EvochiText.bodyText.copyWith(fontSize: 17, height: 1.47, fontWeight: FontWeight.w600, color: EvochiColor.ink),
                  ),
                ),
              ),
            ),
            // tail toward the speaker
            Positioned(
              left: b.maxWidth * tailX - 11,
              top: 11,
              child: Transform.rotate(
                angle: math.pi / 4,
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: const BoxDecoration(
                    color: paper,
                    borderRadius: BorderRadius.only(topLeft: Radius.circular(5)),
                    border: Border(left: BorderSide(color: edge, width: 2.5), top: BorderSide(color: edge, width: 2.5)),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: speaker.color,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white, width: 2),
                      boxShadow: const [BoxShadow(color: Color(0x38000000), offset: Offset(0, 3)), BoxShadow(color: Color(0x2E28190A), blurRadius: 10, offset: Offset(0, 4))],
                    ),
                    child: Text.rich(
                      TextSpan(children: [
                        TextSpan(text: speaker.name, style: EvochiText.cardTitle.copyWith(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 17)),
                        if (speaker.role.isNotEmpty) TextSpan(text: '  ${speaker.role}', style: EvochiText.tag.copyWith(color: const Color(0xD9FFFFFF), fontSize: 12)),
                      ]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                if (quest != null) ...[
                  const SizedBox(width: 8),
                  EvochiButton(label: 'Quest', small: true, expand: false, tone: ButtonTone.cream, icon: const VoxelIcon('journey', size: 22), onPressed: quest),
                ],
              ]),
            ),
            if (more && done)
              const Positioned(right: 16, bottom: 6, child: Text('▼', style: TextStyle(fontSize: 13, color: EvochiColor.primaryShadow))),
          ]);
        }),
      ),
    );
  }
}

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
