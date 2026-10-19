// Home Tales: the Cottage. Before "A Place to Call Home" it's a ruin with the quest card and what to
// do next; once Bram has the roof up, "Restore the Cottage" plays a tiny scene (HQ01_C00 -> restore ->
// HQ01_C01 -> HQ01_B09 -> the reward card). Restored, it shows the Kitchen and Apothecary room cards
// and the three Cozy Skills. Mirrors `cottage` in web/src/screens/homeland.js.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../controllers/game_controller.dart';
import '../../game/home/home.dart' as h;
import '../../game/story/story.dart' as q;
import '../shared/widgets.dart';
import '../trails/trails_widgets.dart';
import '../village/story_widgets.dart';
import '../village/village_screen.dart';
import 'home_widgets.dart';

class CottageScreen extends StatefulWidget {
  const CottageScreen({super.key});
  @override
  State<CottageScreen> createState() => _CottageScreenState();
}

class _CottageScreenState extends State<CottageScreen> {
  String? _step; // the restoration scene's current line (HQ01_C01, then HQ01_B09)
  bool _anim = false; // the restored art is fading in, with sparks
  Timer? _animTimer;

  @override
  void dispose() {
    _animTimer?.cancel();
    super.dispose();
  }

  void _restore(GameController c) {
    final r = c.run((s, n) => q.storyHandIn(s, 'hq01', 'restore_cottage', n));
    if (!r.ok) return;
    final reduce = MediaQuery.of(context).disableAnimations;
    setState(() {
      _anim = true;
      _step = 'HQ01_C01';
    });
    c.audio.play('evolve_fanfare');
    c.analytics.track('cottage_restored', {});
    _animTimer?.cancel();
    _animTimer = Timer(Duration(milliseconds: reduce ? 10 : 1900), () {
      if (mounted) setState(() => _anim = false);
    });
  }

  void _sceneNext(GameController c) {
    if (_step == 'HQ01_C01') {
      c.audio.play('ui_tap', volume: 0.4);
      setState(() => _step = 'HQ01_B09');
      return;
    }
    setState(() => _step = null);
    showStoryReward(context, 'hq01', backToVillage: false);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<GameController>();
    final st = c.storyView;
    final restored = st.flag('cottage_restored');
    final v = q.questView(c.state, 'hq01', c.now);
    final scene = _step != null && q.lines.containsKey(_step) ? _step : null;
    final showRestored = restored && (scene == null || scene != 'HQ01_C00');
    final List<Widget> body;
    if (scene != null) {
      final line = q.lines[scene]!;
      final bram = line.speaker == 'npc_bram';
      body = [
        _Narration(text: q.lineText(c.state, scene, c.now, petName: c.state.pet?.name ?? 'your Evochi'), bramExpr: bram ? (line.expression ?? 'happy') : null),
        const SizedBox(height: 10),
        EvochiButton(label: scene == 'HQ01_C01' ? 'Continue' : 'Step inside', onPressed: () => _sceneNext(c)),
      ];
    } else if (!restored) {
      final ready = v.phase == 'restoration_ready';
      final n = v.next;
      Widget? cta;
      if (ready) {
        cta = EvochiButton(label: 'Restore the Cottage', tone: ButtonTone.green, icon: const Icon(Icons.auto_awesome, size: 20, color: Color(0xFFFFE27A)), onPressed: () => _restore(c));
      } else if (v.phase == 'available') {
        cta = EvochiButton(label: 'Talk to Bram in his Workshop', onPressed: () => openPlace(context, 'workshop', npc: 'npc_bram'));
      } else if (n.kind == 'walk') {
        cta = EvochiButton(label: 'Go for a walk', tone: ButtonTone.green, onPressed: () => goWalk(context));
      } else if (n.kind == 'gather') {
        cta = EvochiButton(label: 'Visit your Garden', tone: ButtonTone.green, onPressed: () => openGarden(context));
      } else if (n.kind == 'handin') {
        cta = EvochiButton(label: 'Bring them to Bram', onPressed: () => openPlace(context, 'workshop', npc: 'npc_bram'));
      }
      body = [
        _Narration(text: q.lineText(c.state, ready ? 'HQ01_C00' : 'HQ01_C02', c.now)),
        const SizedBox(height: 10),
        GameCard(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              const NpcImage('npc_bram', height: 54),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Home Tales · Quest 01', style: EvochiText.caption),
                  Text(v.title, style: EvochiText.cardTitle),
                  const SizedBox(height: 3),
                  Wrap(spacing: 6, runSpacing: 4, children: [Tag('Lv ${v.level}+'), storyStatusTag(v)]),
                ]),
              ),
              EvochiButton(label: 'Details', small: true, expand: false, tone: ButtonTone.cream, onPressed: () => showStoryQuest(context, 'hq01')),
            ]),
            const SizedBox(height: 8),
            Text(nextText(v), style: EvochiText.tag.copyWith(color: EvochiColor.ink)),
            if (v.accepted) Padding(padding: const EdgeInsets.only(top: 6), child: WalkProgress(v)),
          ]),
        ),
        if (cta != null) ...[const SizedBox(height: 10), cta],
      ];
    } else {
      final strip = [...st.home, ...st.side].where((x) => x.accepted && !x.completed).firstOrNull ?? st.home.where((x) => x.phase == 'available').firstOrNull;
      body = [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 2, 4, 0),
          child: Text('${q.lineText(c.state, 'HQ01_B08', c.now)} - Bram', style: EvochiText.caption.copyWith(fontSize: 13)),
        ),
        const SizedBox(height: 10),
        const SectionHead('Rooms'),
        const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: _RoomCard('kitchen')),
          SizedBox(width: 8),
          Expanded(child: _RoomCard('apothecary')),
        ]),
        const SizedBox(height: 10),
        if (strip != null) HomeQuestStrip(v: strip),
        const SectionHead('Skills'),
        for (final k in h.skillOrder) SkillStrip(k),
      ];
    }
    return Scaffold(
      backgroundColor: EvochiColor.panel,
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          PlaceHeader(title: restored ? 'Your Cottage' : 'The Old Cottage', short: 'Cottage', backLabel: 'Back', onBack: () => Navigator.of(context).maybePop()),
          Expanded(
            child: ListView(padding: EdgeInsets.only(bottom: 20 + MediaQuery.of(context).padding.bottom), children: [
              _CottageView(restored: showRestored || _anim, animating: _anim),
              Transform.translate(
                offset: const Offset(0, -14),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: body),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// The cottage close-up: ruined and restored renders, cross-faded while it's restored, with sparks.
class _CottageView extends StatelessWidget {
  const _CottageView({required this.restored, required this.animating});
  final bool restored;
  final bool animating;
  @override
  Widget build(BuildContext context) {
    final ha = homeArt;
    final size = ha.cottageSize;
    final reduce = MediaQuery.of(context).disableAnimations;
    return AspectRatio(
      aspectRatio: size.width / size.height,
      child: LayoutBuilder(builder: (ctx, b) {
        return Stack(fit: StackFit.expand, children: [
          Image.asset(
            ha.cottage(restored: false),
            fit: BoxFit.cover,
            alignment: ha.cottageAlignment,
            semanticLabel: restored ? null : 'The old cottage: a broken roof, boarded windows and an empty doorway.',
            excludeFromSemantics: restored,
          ),
          AnimatedOpacity(
            opacity: restored ? 1 : 0,
            duration: Duration(milliseconds: animating && !reduce ? 1800 : 300),
            curve: Curves.easeIn,
            child: Image.asset(
              ha.cottage(restored: true),
              fit: BoxFit.cover,
              alignment: ha.cottageAlignment,
              semanticLabel: restored ? 'Your restored cottage: a new red roof, warm windows and a puffing chimney.' : null,
              excludeFromSemantics: !restored,
            ),
          ),
          if (animating && !reduce)
            for (var i = 0; i < 6; i++)
              Positioned(
                left: b.maxWidth * (0.16 + i * 0.12),
                top: b.maxHeight * const [0.30, 0.16, 0.42, 0.22, 0.36, 0.26][i],
                child: _Spark(delayMs: i * 160),
              ),
          // fade into the page
          const Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 60,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x00F8EBDD), EvochiColor.panel])),
              ),
            ),
          ),
          // a discovery's clue (Lumen Trails), once the cottage stands restored
          if (restored && !animating) ClueGlint(place: 'cottage', width: b.maxWidth, height: b.maxHeight),
        ]);
      }),
    );
  }
}

class _Spark extends StatefulWidget {
  const _Spark({required this.delayMs});
  final int delayMs;
  @override
  State<_Spark> createState() => _SparkState();
}

class _SparkState extends State<_Spark> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));
  Timer? _start;

  @override
  void initState() {
    super.initState();
    _start = Timer(Duration(milliseconds: widget.delayMs), () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _start?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (_, child) {
          final t = _c.value;
          return Opacity(
            opacity: t < 0.2 ? t / 0.2 : (1 - t).clamp(0.0, 1.0).toDouble() / 0.8,
            child: Transform.translate(offset: Offset(0, -18 * t), child: Transform.scale(scale: 0.6 + 0.6 * t, child: child)),
          );
        },
        child: const Icon(Icons.auto_awesome, size: 26, color: Color(0xFFFFE27A), shadows: [Shadow(color: Color(0xFFC8832C), blurRadius: 2)]),
      );
}

/// A narration card (the cottage speaks in italics), or Bram's line with his face.
class _Narration extends StatelessWidget {
  const _Narration({required this.text, this.bramExpr});
  final String text;
  final String? bramExpr;
  @override
  Widget build(BuildContext context) => Semantics(
        liveRegion: true,
        child: GameCard(
          padding: const EdgeInsets.all(12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (bramExpr != null) ...[NpcImage('npc_bram', expression: bramExpr!, height: 54), const SizedBox(width: 10)],
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (bramExpr != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(color: const Color(0xFF8D5D3B), borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.white, width: 2)),
                    child: Text('Bram', style: EvochiText.tag.copyWith(color: Colors.white, fontWeight: FontWeight.w900)),
                  ),
                Text(
                  text,
                  style: EvochiText.bodyText.copyWith(fontSize: 16, height: 1.45, fontStyle: bramExpr == null ? FontStyle.italic : FontStyle.normal, color: EvochiColor.ink),
                ),
              ]),
            ),
          ]),
        ),
      );
}

/// A Kitchen / Apothecary card: open (recipes ready) or locked behind its story quest.
class _RoomCard extends StatelessWidget {
  const _RoomCard(this.id);
  final String id;
  @override
  Widget build(BuildContext context) {
    final c = context.watch<GameController>();
    final s = h.stationDefs[id]!;
    final open = h.stationOpen(c.state, id);
    final sk = h.skillView(c.state, s.skill);
    final v = q.questView(c.state, s.quest, c.now);
    final ready = open ? h.recipeOrder.where((r) => h.recipeDefs[r]!.station == id && h.recipeView(c.state, r).ready).length : 0;
    final desc = open
        ? (ready > 0 ? '$ready recipe${ready > 1 ? 's' : ''} ready' : (id == 'kitchen' ? 'Meals and treats' : 'Tonics and teas'))
        : (v.completed ? 'Opening soon' : nextText(v));
    return Semantics(
      button: true,
      label: '${s.name}. $desc${open ? '' : '. Locked'}',
      child: ExcludeSemantics(
        child: GestureDetector(
          onTap: () {
            c.audio.play('ui_tap', volume: 0.4);
            if (open) {
              openStation(context, id);
            } else {
              showStoryQuest(context, s.quest);
            }
          },
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
                SizedBox(
                  height: 84,
                  child: ColorFiltered(
                    colorFilter: open ? const ColorFilter.mode(Color(0x00000000), BlendMode.dst) : const ColorFilter.matrix(_locked),
                    child: Image.asset(homeArt.room(id), fit: BoxFit.cover, alignment: const Alignment(0, 0.28)),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
                  child: Row(children: [
                    VoxelIcon(h.skillDefs[s.skill]!.icon, size: 20),
                    const SizedBox(width: 5),
                    Flexible(child: Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: EvochiText.cardTitle.copyWith(fontSize: 14, fontWeight: FontWeight.w900))),
                    if (open) LvChip('Lv ${sk.level}'),
                  ]),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 2, 8, 8),
                  child: Text(desc, maxLines: 2, overflow: TextOverflow.ellipsis, style: EvochiText.caption.copyWith(color: EvochiColor.textSecondary, fontWeight: FontWeight.w700)),
                ),
              ]),
              if (!open)
                Positioned(
                  top: 6,
                  right: 6,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(color: const Color(0xF2FFF9F0), borderRadius: BorderRadius.circular(9), border: Border.all(color: const Color(0xFFE2CDB4), width: 1.5)),
                    child: const VoxelIcon('lock', size: 18),
                  ),
                )
              else if (ready > 0)
                const Positioned(top: 6, right: 6, child: BadgeDot()),
            ]),
          ),
        ),
      ),
    );
  }
}

// a locked room is greyed back a little
const _locked = <double>[
  0.55, 0.3, 0.1, 0, 10, //
  0.25, 0.6, 0.1, 0, 10, //
  0.25, 0.3, 0.4, 0, 10, //
  0, 0, 0, 1, 0,
];
