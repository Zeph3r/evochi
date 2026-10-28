// Talking to a villager where they stand: a panel over the bottom of the walkable map with a big
// animated head of whoever speaks (their puppet, cropped to the face: it blinks, nods as it talks, and
// changes expression with the line), their name on a ribbon, the line typing in, and the choices. The
// same conversations as the place screens (game/story/story.dart: npcConversation), so quests are
// offered and handed in here.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../controllers/game_controller.dart';
import '../../core/models/game_state.dart';
import '../../game/mining/mining.dart' as mine;
import '../../game/story/story.dart' as q;
import '../shared/kit.dart';
import '../shared/widgets.dart';
import 'flint_talk.dart';
import 'npc_puppet.dart';
import 'story_widgets.dart';

/// Where a choice leads outside the talk: a place or room ('lodge', 'workshop', 'glasshouse',
/// 'waystone'), 'journey', 'discover', 'prep:<quest>', a home destination, 'forge' (Bram's anvil),
/// 'reward:<quest>', or Flint's 'flint:gear' (his shop) and 'flint:enter' (off to the mine).
typedef TalkGoto = void Function(String to);

class ChatheadTalk extends StatefulWidget {
  const ChatheadTalk({super.key, required this.npc, required this.onSwitch, required this.onClose, required this.onGoto, this.forge = false, this.onFlare});
  final String npc; // npc_bram, npc_mira, npc_pip, npc_alder, npc_flint, or 'waystone' (the stone in the Square)
  final ValueChanged<String> onSwitch; // another villager in the same room takes over
  final VoidCallback onClose;
  final TalkGoto onGoto;
  final bool forge; // Bram's forge is open to you (ore has been mined)
  final ValueChanged<String>? onFlare; // something was handed in: 'give', or 'restore' (the Waystone wakes)

  @override
  State<ChatheadTalk> createState() => _ChatheadTalkState();
}

class _ChatheadTalkState extends State<ChatheadTalk> with SingleTickerProviderStateMixin {
  String? _node;
  String? _convNpc;
  Map<String, q.ConvNode> _extraNodes = const {};
  String? _typedKey;
  int _shown = 0;
  bool _typedDone = true;
  Timer? _typer;
  late final AnimationController _in = AnimationController(vsync: this, duration: const Duration(milliseconds: 260))..forward();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.npc != 'waystone') context.read<GameController>().run((s, n) => q.markNpcMet(s, widget.npc), quiet: true);
    });
  }

  @override
  void didUpdateWidget(ChatheadTalk old) {
    super.didUpdateWidget(old);
    if (old.npc != widget.npc) {
      _node = null;
      final c = context.read<GameController>();
      if (widget.npc != 'waystone' && c.state.story.npcsMet[widget.npc] != true) c.run((s, t) => q.markNpcMet(s, widget.npc), quiet: true);
    }
  }

  @override
  void dispose() {
    _typer?.cancel();
    _in.dispose();
    super.dispose();
  }

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
    _typer = Timer.periodic(const Duration(milliseconds: 22), (t) {
      if (!mounted) return t.cancel();
      final n = DateTime.now().difference(start).inMilliseconds ~/ 22;
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

  (q.ConvNode, Map<String, q.ConvNode>) _current(GameController c) {
    final conv = q.npcConversation(c.state, widget.npc, c.now);
    if (_node == null || _convNpc != widget.npc) {
      _node = conv.start;
      _convNpc = widget.npc;
      _extraNodes = conv.nodes;
    }
    final nodes = {..._extraNodes, ...conv.nodes};
    if (!nodes.containsKey(_node)) _node = conv.start;
    return (nodes[_node]!, nodes);
  }

  void _choose(GameController c, q.Choice ch, Map<String, q.ConvNode> nodes) {
    final met = ch.act;
    if (met != null && met.kind == 'met') c.run((s, n) => q.markNpcMet(s, met.npc!), quiet: true);
    if (ch.leave) {
      c.audio.play('ui_tap', volume: 0.4);
      widget.onClose();
      return;
    }
    if (ch.goto != null) {
      widget.onGoto(ch.goto!);
      return;
    }
    if (ch.npc != null) {
      c.audio.play('ui_tap', volume: 0.4);
      widget.onSwitch(ch.npc!);
      return;
    }
    if (ch.reward != null) {
      _node = null;
      widget.onGoto('reward:${ch.reward}');
      return;
    }
    final act = ch.act;
    if (act != null && act.kind != 'met') {
      final r = act.kind == 'accept' ? c.run((s, n) => q.acceptStoryQuest(s, act.quest, n)) : c.run((s, n) => q.storyHandIn(s, act.quest, act.turnIn!, n));
      if (!r.ok) return;
      setState(() {
        _extraNodes = nodes;
        _node = ch.then;
      });
      if (act.kind == 'accept') {
        c.audio.play('reward_chime', volume: 0.6);
        c.toast('Story quest started: ${q.storyQuests[act.quest]!.title}', icon: 'journey');
      } else {
        c.audio.play(act.turnIn == 'restore' ? 'evolve_fanfare' : 'purchase');
        widget.onFlare?.call(act.turnIn == 'restore' ? 'restore' : 'give');
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
    final reduce = (MediaQuery.maybeDisableAnimationsOf(context) ?? false) || (c.state.player?.settings.reducedMotion ?? false);
    final classic = !(c.state.player?.settings.roomLitVillagers ?? false);
    final pad = MediaQuery.paddingOf(context).bottom;
    final (node, nodes) = _current(c);
    final line = q.lines[node.id]!;
    final speakerId = speakers.containsKey(line.speaker) ? line.speaker : widget.npc;
    final speaker = speakers[speakerId] ?? speakers['waystone']!;
    final text = q.lineText(c.state, node.id, c.now, petName: c.state.pet?.name ?? 'your Evochi');
    final expression = line.expression ?? 'neutral';
    _typeLine('${widget.npc}:${node.id}', text.length, reduce);
    // one way on with nothing to decide: tap the line to carry on
    final single = node.choices.length == 1 && node.choices.first.next != null && node.choices.first.act == null;
    void onLine() => _choose(c, node.choices.first, nodes);
    final choices = <Widget>[
      for (final ch in node.choices) _TalkChoice(choice: ch, onTap: () => _choose(c, ch, nodes)),
      if (widget.npc == 'npc_bram' && widget.forge)
        _TalkChoice(label: 'Forge mining gear', icon: const ItemImage('gear_copper_harness', size: 26), onTap: () => widget.onGoto('forge')),
    ];
    final activeQuest = c.storyView.quests.where((v) => v.accepted && !v.completed && (v.next.npc == widget.npc || v.giver == widget.npc)).firstOrNull;
    final typed = _typedDone;
    return SlideTransition(
      position: Tween(begin: const Offset(0, 0.3), end: Offset.zero).animate(CurvedAnimation(parent: _in, curve: Curves.easeOutCubic)),
      child: FadeTransition(
        opacity: _in,
        child: Semantics(
          container: true,
          label: 'Talking with ${speaker.name}',
          child: Container(
            margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            padding: EdgeInsets.fromLTRB(10, 10, 10, 10 + pad * 0.5),
            decoration: BoxDecoration(
              color: const Color(0xFF4A3327),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFF2E1E16), width: 2),
              boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 18, offset: Offset(0, 6))],
            ),
            child: Container(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
              decoration: BoxDecoration(
                gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFFFF4E2), Color(0xFFF1DDBF)]),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFB08A66), width: 1.5),
              ),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Column(mainAxisSize: MainAxisSize.min, children: [
                    Chathead(npcId: speakerId, expression: expression, state: typed ? 'idle' : 'talk', classic: classic, animate: !reduce),
                    const SizedBox(height: 6),
                    _Ribbon(name: speaker.name, color: speaker.color),
                  ]),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        if (!typed) {
                          _finishLine(text.length);
                        } else if (single) {
                          onLine();
                        }
                      },
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 112),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: _TypedText(text: text, shown: typed ? text.length : _shown),
                          ),
                          Row(children: [
                            if (speaker.role.isNotEmpty)
                              Text(speaker.role, style: const TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w700, fontSize: 12, color: EvochiColor.textHelper)),
                            const Spacer(),
                            if (activeQuest != null)
                              GestureDetector(
                                onTap: () => showStoryQuest(context, activeQuest.id),
                                child: const Padding(padding: EdgeInsets.only(right: 8), child: VoxelIcon('journey', size: 22, semantic: 'This quest')),
                              ),
                            if (!typed || single) _MoreHint(active: typed),
                          ]),
                        ]),
                      ),
                    ),
                  ),
                ]),
                if (typed && !single) ...[
                  const SizedBox(height: 8),
                  for (final w in choices) ...[w, const SizedBox(height: 6)],
                ] else if (typed && single)
                  const SizedBox(height: 4),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// Any ore ever mined, or any mining gear: Bram forges for you from then on.
bool bramForges(GameState s) => s.mining.gear.isNotEmpty || mine.oreItem.values.any((id) => s.inventory.containsKey(id));

/// The speaker's head: their puppet drawn big and cropped to the face, so it blinks and moves as the
/// line is said (the flat portrait, framed on its face point, when a build has no puppet).
class Chathead extends StatelessWidget {
  const Chathead({super.key, required this.npcId, this.expression = 'neutral', this.state = 'idle', this.classic = false, this.animate = true, this.size = 108});
  final String npcId;
  final String expression, state;
  final bool classic, animate;
  final double size;

  @override
  Widget build(BuildContext context) {
    final va = villageArt;
    final art = va.puppet(npcId);
    Widget inner;
    if (npcId == 'npc_flint') {
      // Flint's faces are his own art (not a puppet): the story's expressions map onto them
      inner = FlintHead(expression: switch (expression) { 'proud' => 'determined', 'worried' => 'surprised', 'neutral' => 'default', final e => e }, size: size);
    } else if (npcId == 'waystone') {
      // the stone itself, its runes in the frame (lit once it is restored)
      final restored = context.watch<GameController>().storyView.flag('waystone_restored');
      inner = Image.asset(va.waystone(restored: restored), fit: BoxFit.cover, alignment: const Alignment(0, -0.2), excludeFromSemantics: true, gaplessPlayback: true);
    } else if (art != null) {
      final head = art.layers.where((l) => l.part == 'head').firstOrNull?.box ?? Rect.fromLTWH(0, 0, art.w, art.h * 0.45);
      final s = size * 0.82 / head.height;
      final centre = head.center;
      inner = Stack(clipBehavior: Clip.hardEdge, children: [
        Positioned(
          left: size / 2 - centre.dx * s,
          top: size * 0.54 - centre.dy * s,
          width: art.w * s,
          height: art.h * s,
          child: NpcPuppet(art: art, width: art.w * s, height: art.h * s, expression: expression, state: state, classic: classic, animate: animate),
        ),
      ]);
    } else {
      final face = va.npcFace(npcId);
      final sz = va.npcSize(npcId);
      final s = size * 0.9 / (sz.height * 0.36);
      inner = Stack(clipBehavior: Clip.hardEdge, children: [
        Positioned(
          left: size / 2 - face.dx * s,
          top: size * 0.56 - face.dy * s,
          width: sz.width * s,
          height: sz.height * s,
          child: Image.asset(va.npc(npcId, expression, classic), fit: BoxFit.fill, filterQuality: FilterQuality.medium, excludeFromSemantics: true, gaplessPlayback: true),
        ),
      ]);
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF4A3327), width: 3),
        boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 6, offset: Offset(0, 3))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(13),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: RadialGradient(center: Alignment(0, -0.2), radius: 0.9, colors: [Color(0xFFE9D3B4), Color(0xFFC9AA86)]),
          ),
          child: inner,
        ),
      ),
    );
  }
}

class _Ribbon extends StatelessWidget {
  const _Ribbon({required this.name, required this.color});
  final String name;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
        width: 108,
        padding: const EdgeInsets.symmetric(vertical: 3),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFF2E1E16), width: 1.5),
        ),
        child: Text(name,
            textAlign: TextAlign.center,
            style: const TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w900, fontSize: 14, color: Color(0xFFFFF4E2), shadows: [Shadow(color: Color(0x80000000), offset: Offset(0, 1), blurRadius: 1)])),
      );
}

/// The line, typed in: the rest of it laid out invisibly so the box never jumps.
class _TypedText extends StatelessWidget {
  const _TypedText({required this.text, required this.shown});
  final String text;
  final int shown;
  @override
  Widget build(BuildContext context) {
    const style = TextStyle(fontFamily: EvochiText.body, fontSize: 15.5, height: 1.35, color: EvochiColor.ink);
    return RichText(
      text: TextSpan(style: style, children: [
        TextSpan(text: text.substring(0, shown)),
        TextSpan(text: text.substring(shown), style: style.copyWith(color: Colors.transparent)),
      ]),
    );
  }
}

/// The little arrow that says there is more (it bobs once the line is in).
class _MoreHint extends StatefulWidget {
  const _MoreHint({required this.active});
  final bool active;
  @override
  State<_MoreHint> createState() => _MoreHintState();
}

class _MoreHintState extends State<_MoreHint> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 700))..repeat(reverse: true);
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (_, __) => Transform.translate(
          offset: Offset(0, widget.active ? 3 * _c.value : 0),
          child: Icon(Icons.arrow_drop_down_rounded, size: 28, color: widget.active ? EvochiColor.wood : EvochiColor.border),
        ),
      );
}

class _TalkChoice extends StatelessWidget {
  const _TalkChoice({this.choice, this.label, this.icon, required this.onTap});
  final q.Choice? choice;
  final String? label;
  final Widget? icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final ch = choice;
    final primary = ch?.primary ?? false;
    final act = ch?.act;
    final turnIn = act != null && act.kind == 'handin' ? q.storyQuests[act.quest]!.turnIns.firstWhere((t) => t.id == act.turnIn) : null;
    final give = turnIn == null ? const <String, int>{} : <String, int>{...turnIn.consume, ...turnIn.consumeItems};
    final text = label ?? ch!.label;
    return Semantics(
      button: true,
      label: text,
      child: ExcludeSemantics(
        child: KitPress(
          onTap: () {
            context.read<GameController>().audio.tick();
            onTap();
          },
          builder: (_, down) => AnimatedContainer(
            duration: const Duration(milliseconds: 60),
            constraints: const BoxConstraints(minHeight: 42),
            transform: Matrix4.translationValues(0, down ? 2 : 0, 0),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: Kit.button(primary ? KitButtonPalette.gold : KitButtonPalette.cream, pressed: down, radius: 10, depth: 3),
            child: Row(children: [
              if (icon != null) ...[icon!, const SizedBox(width: 8)],
              if (give.isNotEmpty) ...[
                for (final e in give.entries) ...[
                  ItemImage(e.key, size: 28),
                  if (e.value > 1) Text('x${e.value}', style: EvochiText.tag.copyWith(color: EvochiColor.ink, fontWeight: FontWeight.w900)),
                ],
                const SizedBox(width: 6),
              ],
              Expanded(child: Text(text, maxLines: 2, overflow: TextOverflow.ellipsis, style: EvochiText.button.copyWith(fontSize: 15))),
              const Icon(Icons.chevron_right_rounded, color: EvochiColor.wood, size: 22),
            ]),
          ),
        ),
      ),
    );
  }
}
