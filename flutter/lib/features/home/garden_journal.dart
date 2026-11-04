// The Garden's crop journal and the village's orders (the rules: game/home/journal.dart).
//
//  - VillageOrders: today's three, each a villager's face and their ask, what they want (what you have of it),
//    what they'll give, and Deliver; a special one, for a Gilded crop, in gold
//  - JournalButton / showCropJournal: a page per crop (its crop and its Gilded keepsake, what's been grown, four
//    stamps), and Collect when a stamp or a full page has something waiting

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../controllers/game_controller.dart';
import '../../core/utils/day_keys.dart';
import '../../game/engine.dart' as g;
import '../../game/home/home.dart' as h;
import '../../game/home/journal.dart' as j;
import '../shared/kit.dart';
import '../shared/widgets.dart';
import '../village/chathead_talk.dart' show Chathead;

const _gold = Color(0xFFE0A21E);
const _leaf = Color(0xFF5FA046);

// ------------------------------------------------------------------ the orders ----
class VillageOrders extends StatelessWidget {
  const VillageOrders({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<GameController>();
    final orders = j.ordersFor(c.state, c.now);
    final left = orders.where((o) => !j.orderDone(c.state, o.id)).length;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        const Expanded(child: KitSectionHead('Village orders')),
        Text(left == 0 ? 'All done! New ones tomorrow' : 'New ones tomorrow', style: EvochiText.caption.copyWith(fontSize: 12)),
      ]),
      const SizedBox(height: 6),
      for (final o in orders) Padding(padding: const EdgeInsets.only(bottom: 8), child: _OrderCard(o)),
    ]);
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard(this.o);
  final j.VillageOrder o;

  @override
  Widget build(BuildContext context) {
    final c = context.watch<GameController>();
    final s = c.state;
    final done = j.orderDone(s, o.id);
    final ready = j.canDeliver(s, o);
    return Opacity(
      opacity: done ? 0.6 : 1,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: o.special ? const Color(0xFFFFF7DE) : const Color(0xFFFFFBF2),
          border: Border.all(color: o.special ? _gold : const Color(0xFFE2CDB4), width: o.special ? 2.5 : 1.5),
          boxShadow: o.special ? const [BoxShadow(color: Color(0x40E0A21E), blurRadius: 10)] : null,
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Chathead(npcId: 'npc_${o.villager.id}', expression: done ? 'happy' : (o.special ? 'happy' : 'neutral'), size: 52, animate: false),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(o.villager.name, style: EvochiText.cardTitle.copyWith(fontSize: 15)),
                if (o.special) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(color: _gold, borderRadius: BorderRadius.circular(8)),
                    child: Text('Special', style: EvochiText.tag.copyWith(fontSize: 10.5, color: Colors.white, fontWeight: FontWeight.w900)),
                  ),
                ],
              ]),
              Text(o.line, style: EvochiText.caption.copyWith(fontSize: 12.5, fontStyle: FontStyle.italic)),
              const SizedBox(height: 6),
              Wrap(spacing: 10, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                for (final e in o.wants.entries)
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    ItemImage(e.key, size: 26),
                    const SizedBox(width: 2),
                    Text('${g.ownedQty(s, e.key).clamp(0, e.value)}/${e.value}',
                        style: EvochiText.tag.copyWith(fontWeight: FontWeight.w900, color: g.ownedQty(s, e.key) >= e.value ? _leaf : EvochiColor.textSecondary)),
                  ]),
                const Icon(Icons.arrow_forward_rounded, size: 16, color: Color(0xFFB59A7C)),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  const VoxelIcon('coin', size: 20),
                  Text(' ${o.coins}', style: EvochiText.tag.copyWith(fontWeight: FontWeight.w900, color: EvochiColor.ink)),
                  const SizedBox(width: 6),
                  Text('+${o.xp} XP', style: EvochiText.tag.copyWith(color: _leaf, fontWeight: FontWeight.w900)),
                ]),
              ]),
            ]),
          ),
          const SizedBox(width: 6),
          if (done)
            const Padding(padding: EdgeInsets.only(top: 14), child: Icon(Icons.check_circle_rounded, color: _leaf, size: 28))
          else
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: EvochiButton(
                label: 'Deliver',
                small: true,
                expand: false,
                tone: ready ? (o.special ? ButtonTone.gold : ButtonTone.green) : ButtonTone.cream,
                onPressed: ready ? () => c.run((st, n) => j.deliverOrder(st, o.id, n)) : null,
              ),
            ),
        ]),
      ),
    );
  }
}

// ------------------------------------------------------------------ the journal ----
class JournalButton extends StatelessWidget {
  const JournalButton({super.key});
  @override
  Widget build(BuildContext context) {
    final c = context.watch<GameController>();
    final waiting = j.journalWaiting(c.state);
    return Stack(clipBehavior: Clip.none, children: [
      EvochiButton(
        label: 'Crop journal',
        small: true,
        expand: false,
        tone: ButtonTone.cream,
        icon: const Icon(Icons.menu_book_rounded, size: 20, color: Color(0xFF8A5A3B)),
        onPressed: () => showCropJournal(context),
      ),
      if (waiting) const Positioned(top: -3, right: -3, child: BadgeDot()),
    ]);
  }
}

Future<void> showCropJournal(BuildContext context) {
  final c = context.read<GameController>();
  final first = j.journal(c.state).indexWhere((p) => p.toCollect);
  return showEvochiSheet<void>(context, builder: (ctx) => _Journal(start: first < 0 ? 0 : first));
}

class _Journal extends StatefulWidget {
  const _Journal({required this.start});
  final int start;
  @override
  State<_Journal> createState() => _JournalState();
}

class _JournalState extends State<_Journal> {
  late final PageController _pc = PageController(initialPage: widget.start);
  late int _at = widget.start;

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<GameController>();
    final pages = j.journal(c.state);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Padding(padding: EdgeInsets.fromLTRB(4, 4, 4, 2), child: Text('Crop journal', style: EvochiText.cardTitle)),
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
        child: Text('A page for every crop, filled in as you grow it.', style: EvochiText.caption.copyWith(fontSize: 12.5)),
      ),
      SizedBox(
        height: 330,
        child: PageView(
          controller: _pc,
          onPageChanged: (i) => setState(() => _at = i),
          children: [for (final p in pages) _Page(p)],
        ),
      ),
      const SizedBox(height: 6),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        for (var i = 0; i < pages.length; i++)
          GestureDetector(
            onTap: () => _pc.animateToPage(i, duration: const Duration(milliseconds: 250), curve: Curves.easeOut),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              width: i == _at ? 18 : 8,
              height: 8,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                color: pages[i].toCollect ? _gold : (i == _at ? const Color(0xFF8A5A3B) : const Color(0xFFD8C4A8)),
              ),
            ),
          ),
      ]),
    ]);
  }
}

class _Page extends StatelessWidget {
  const _Page(this.p);
  final j.JournalPage p;

  @override
  Widget build(BuildContext context) {
    final c = context.watch<GameController>();
    final crop = h.cropDefs[p.crop]!;
    final gid = h.gildedOf[p.crop]!;
    final unlocked = h.cropUnlocked(c.state, p.crop);
    final first = p.firstAt;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFFFFBF0), Color(0xFFF3E6CF)]),
        border: Border.all(color: const Color(0xFFD9C09C), width: 2),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          _Shown(p.seen, ItemImage(p.crop, size: 64)),
          const SizedBox(width: 8),
          _Shown(p.golden > 0, ItemImage(gid, size: 46)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p.seen ? crop.name : (unlocked ? '${crop.name} (not grown yet)' : '???'), style: EvochiText.cardTitle.copyWith(fontSize: 17)),
              Text(
                !unlocked
                    ? (h.foundCrops.contains(crop.id) ? "Forage its spores in the mine's Hollow galleries" : 'Opens at Farming ${crop.level}')
                    : 'Grown ${p.grown} · Golden ${p.golden}${first != null ? '\nFirst harvest ${_date(first, g.zoneOf(c.state))}' : ''}',
                style: EvochiText.caption.copyWith(fontSize: 12.5),
              ),
            ]),
          ),
        ]),
        const SizedBox(height: 12),
        // the four stamps
        Row(children: [
          for (final st in j.stamps)
            Expanded(child: _StampMark(label: st.label, xp: st.xp, earned: p.earned.contains(st.id), collected: p.collected.contains(st.id))),
        ]),
        const Spacer(),
        Text(
          p.pageCollected ? 'Page complete!' : 'Fill the page: +${j.pageBonus[p.crop]} EvoCoins',
          textAlign: TextAlign.center,
          style: EvochiText.tag.copyWith(color: p.pageCollected ? _leaf : const Color(0xFF8A6A48), fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 8),
        EvochiButton(
          label: p.toCollect ? 'Collect' : (p.pageCollected ? 'All collected' : 'Keep growing'),
          tone: p.toCollect ? ButtonTone.gold : ButtonTone.cream,
          onPressed: p.toCollect ? () => c.run((s, n) => j.collectJournal(s, p.crop, n)) : null,
        ),
      ]),
    );
  }
}

String _date(int ms, String zone) {
  final k = dayKey(ms, zone); // yyyy-mm-dd
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final parts = k.split('-');
  return '${months[int.parse(parts[1]) - 1]} ${int.parse(parts[2])}';
}

/// What the page has seen, in colour; what it hasn't, a soft silhouette.
class _Shown extends StatelessWidget {
  const _Shown(this.seen, this.child);
  final bool seen;
  final Widget child;
  @override
  Widget build(BuildContext context) => seen ? child : ColorFiltered(colorFilter: const ColorFilter.mode(Color(0x55604A30), BlendMode.srcIn), child: child);
}

class _StampMark extends StatelessWidget {
  const _StampMark({required this.label, required this.xp, required this.earned, required this.collected});
  final String label;
  final int xp;
  final bool earned, collected;
  @override
  Widget build(BuildContext context) {
    final waiting = earned && !collected;
    return Column(children: [
      Container(
        width: 54,
        height: 54,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: collected ? const Color(0xFFE6F0D4) : (waiting ? const Color(0xFFFFF1C2) : const Color(0x00000000)),
          border: Border.all(color: collected ? _leaf : (waiting ? _gold : const Color(0xFFCDB89A)), width: collected || waiting ? 3 : 2),
          boxShadow: waiting ? const [BoxShadow(color: Color(0x80FFD45A), blurRadius: 10)] : null,
        ),
        child: Center(
          child: collected
              ? const Icon(Icons.eco_rounded, color: _leaf, size: 28)
              : waiting
                  ? const Icon(Icons.auto_awesome, color: _gold, size: 26)
                  : const Icon(Icons.lock_outline_rounded, color: Color(0xFFCDB89A), size: 20),
        ),
      ),
      const SizedBox(height: 4),
      Text(label, textAlign: TextAlign.center, style: EvochiText.tag.copyWith(fontSize: 10.5, color: EvochiColor.ink, height: 1.1)),
      Text('+$xp XP', style: EvochiText.tag.copyWith(fontSize: 10, color: _leaf)),
    ]);
  }
}
