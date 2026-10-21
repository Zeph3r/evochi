// Season 1: First Light (docs: Evochi Economy & Monetization Plan, "Season 1"). Forty tiers over eight
// weeks with a free track and a premium track (500 Glimmer). Season XP comes from walking: 1 per 10
// verified steps, 150 per goal day, 500 for a Weekly Explorer week, 200 for calming a guardian.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../controllers/game_controller.dart';
import '../../core/models/catalog.dart';
import '../../core/utils/ids.dart';
import '../../game/economy/economy.dart' as e;
import '../shared/widgets.dart';
import 'caravan_screen.dart';

Future<void> openSeason(BuildContext context) => Navigator.of(context).push(
      MaterialPageRoute<void>(settings: const RouteSettings(name: '/season'), builder: (_) => const SeasonScreen()),
    );

class SeasonScreen extends StatelessWidget {
  const SeasonScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<GameController>();
    final v = e.seasonView(c.state, c.now);
    final mq = MediaQuery.of(context);
    final def = v.def;
    return Scaffold(
      backgroundColor: Night.sky,
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Night.sky, Night.sky2])),
        child: SafeArea(
          bottom: false,
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: Row(children: [
                BackSquareButton(onTap: () => Navigator.of(context).maybePop()),
                const SizedBox(width: 10),
                const VoxelIcon('season', size: 40),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Season 1', style: EvochiText.tiny.copyWith(color: Night.soft)),
                    Semantics(header: true, child: Text(def.name, style: EvochiText.section.copyWith(color: Night.gold, height: 1.1))),
                  ]),
                ),
                GlimmerPill(balance: e.glimmerOf(c.state), onTap: () => openCaravan(context, tab: 'glimmer')),
              ]),
            ),
            Expanded(
              child: ListView.builder(
                padding: EdgeInsets.fromLTRB(14, 8, 14, 24 + mq.padding.bottom),
                itemCount: def.tiers + 1,
                itemBuilder: (ctx, i) => i == 0 ? _Summary(view: v) : _TierRow(view: v, tier: i),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.view});
  final e.SeasonView view;
  @override
  Widget build(BuildContext context) {
    final c = context.read<GameController>();
    final v = view;
    final def = v.def;
    final done = v.tier >= def.tiers;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF3D3F86), Night.card]),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Night.gold, width: 2),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Text('Tier ${v.tier}', style: EvochiText.pageTitle.copyWith(color: Night.text)),
              Text(' / ${def.tiers}', style: EvochiText.section.copyWith(color: Night.soft)),
              const Spacer(),
              Text(v.active ? '${v.daysLeft} days left' : 'Season over', style: EvochiText.tag.copyWith(color: Night.gold)),
            ]),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: done ? 1 : v.intoTier / def.tierXp,
                minHeight: 10,
                backgroundColor: const Color(0xFF151A36),
                valueColor: const AlwaysStoppedAnimation(Night.gold),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              done ? 'Every tier reached. Well walked!' : '${fmt(v.intoTier)} / ${fmt(def.tierXp)} XP to tier ${v.tier + 1}',
              style: EvochiText.caption.copyWith(color: Night.soft),
            ),
            const SizedBox(height: 8),
            Text(
              'Earn Season XP by walking: 1 per ${def.stepsPerXp} steps, ${def.goalDayXp} per goal day, ${def.weeklyXp} for a Weekly Explorer week, ${def.bossXp} for calming a guardian.',
              style: EvochiText.tiny.copyWith(color: Night.soft, fontWeight: FontWeight.w400),
            ),
          ]),
        ),
        const SizedBox(height: 10),
        if (v.claimable > 0) ...[
          EvochiButton(
            label: 'Claim ${v.claimable} reward${v.claimable == 1 ? '' : 's'}',
            tone: ButtonTone.green,
            icon: const VoxelIcon('chest', size: 24),
            onPressed: () => _claim(context, c),
          ),
          const SizedBox(height: 8),
        ],
        if (!v.premium && v.active) ...[
          EvochiButton(
            label: 'Unlock the premium track · ${def.passGlimmer}',
            icon: const VoxelIcon('glimmer', size: 24),
            onPressed: () => _buyPass(context, c, def.passGlimmer),
          ),
          const SizedBox(height: 4),
          Text('The First Light outfit, a banner, a shimmer, 10 Sunstones and 150 Glimmer back.',
              textAlign: TextAlign.center, style: EvochiText.tiny.copyWith(color: Night.soft, fontWeight: FontWeight.w400)),
          const SizedBox(height: 8),
        ],
        if (v.tiersOnSale)
          EvochiButton(
            label: 'Buy a tier · ${def.tierGlimmer}',
            small: true,
            tone: ButtonTone.cream,
            icon: const VoxelIcon('glimmer', size: 22),
            onPressed: () => _buyTier(context, c, def.tierGlimmer),
          ),
        const SizedBox(height: 6),
        Row(children: [
          const SizedBox(width: 58),
          Expanded(child: Text('Free', textAlign: TextAlign.center, style: EvochiText.tag.copyWith(color: Night.soft))),
          const SizedBox(width: 8),
          Expanded(child: Text(v.premium ? 'Premium' : 'Premium (locked)', textAlign: TextAlign.center, style: EvochiText.tag.copyWith(color: Night.gold))),
        ]),
      ]),
    );
  }

  void _claim(BuildContext context, GameController c) {
    final r = c.run((s, n) => e.claimSeason(s, n));
    final ev = r.events.where((x) => x.type == 'season_claimed').firstOrNull;
    if (ev == null) return;
    final rewards = (ev.data['rewards'] as List).cast<Map<String, Object?>>();
    c.audio.play('reward_chime');
    showEvochiDialog<void>(context, builder: (d) => Column(mainAxisSize: MainAxisSize.min, children: [
          const VoxelIcon('season', size: 72),
          const Text('Season rewards', style: EvochiText.section),
          const SizedBox(height: 8),
          Wrap(alignment: WrapAlignment.center, spacing: 6, runSpacing: 6, children: [for (final r in _merge(rewards)) _RewardTag(r)]),
          const SizedBox(height: 12),
          EvochiButton(label: 'Collect', onPressed: () => Navigator.pop(d)),
        ]));
  }

  Future<void> _buyPass(BuildContext context, GameController c, int price) async {
    final short = price - e.glimmerOf(c.state);
    if (short > 0) {
      await showGlimmerShort(context, short);
      return;
    }
    c.run((s, n) => e.buySeasonPass(s, n));
  }

  Future<void> _buyTier(BuildContext context, GameController c, int price) async {
    final short = price - e.glimmerOf(c.state);
    if (short > 0) {
      await showGlimmerShort(context, short);
      return;
    }
    c.run((s, n) => e.buySeasonTier(s, newId('tier'), n));
  }
}

/// Coins and Glimmer summed; items counted.
List<Map<String, Object?>> _merge(List<Map<String, Object?>> rewards) {
  final coins = rewards.where((r) => r['kind'] == 'coins').fold<int>(0, (a, r) => a + (r['amount'] as int));
  final gl = rewards.where((r) => r['kind'] == 'glimmer').fold<int>(0, (a, r) => a + (r['amount'] as int));
  final items = <String, int>{};
  for (final r in rewards.where((r) => r['kind'] == 'item')) {
    items[r['itemId'] as String] = (items[r['itemId'] as String] ?? 0) + 1;
  }
  return [
    if (coins > 0) {'kind': 'coins', 'amount': coins},
    if (gl > 0) {'kind': 'glimmer', 'amount': gl},
    for (final x in items.entries) {'kind': 'item', 'itemId': x.key, 'qty': x.value},
    for (final r in rewards.where((r) => r['kind'] == 'title')) r,
  ];
}

class _RewardTag extends StatelessWidget {
  const _RewardTag(this.r);
  final Map<String, Object?> r;
  @override
  Widget build(BuildContext context) => switch (r['kind']) {
        'coins' => Tag('+${fmt(r['amount'] as int)}', tone: TagTone.stage, icon: 'coin'),
        'glimmer' => Tag('+${fmt(r['amount'] as int)} Glimmer', tone: TagTone.stage, icon: 'glimmer'),
        'title' => Tag('Title: ${r['title']}', tone: TagTone.ok, icon: 'star'),
        _ => Tag('${(r['qty'] as int? ?? 1) > 1 ? '${r['qty']} × ' : ''}${item(r['itemId'] as String).name}', tone: TagTone.ok),
      };
}

class _TierRow extends StatelessWidget {
  const _TierRow({required this.view, required this.tier});
  final e.SeasonView view;
  final int tier;
  @override
  Widget build(BuildContext context) {
    final v = view;
    final reached = v.tier >= tier;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(children: [
        Container(
          width: 50,
          height: 50,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: reached ? Night.gold : Night.card,
            border: Border.all(color: reached ? const Color(0xFF8A5A1E) : Night.goldDim, width: 2),
          ),
          child: Text('$tier', style: EvochiText.number.copyWith(fontSize: 17, color: reached ? EvochiColor.ink : Night.soft)),
        ),
        const SizedBox(width: 8),
        Expanded(child: _Cell(reward: e.seasonReward('free', tier), reached: reached, claimed: v.claimedFree.contains(tier), locked: false)),
        const SizedBox(width: 8),
        Expanded(child: _Cell(reward: e.seasonReward('premium', tier), reached: reached, claimed: v.claimedPaid.contains(tier), locked: !v.premium, premium: true)),
      ]),
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({required this.reward, required this.reached, required this.claimed, required this.locked, this.premium = false});
  final e.SeasonReward reward;
  final bool reached;
  final bool claimed;
  final bool locked;
  final bool premium;
  @override
  Widget build(BuildContext context) {
    final r = reward;
    final (Widget icon, String label) = switch (r) {
      _ when r.items.isNotEmpty => (ItemImage(r.items.keys.first, size: 34), _itemsLabel(r)),
      _ when r.title != null => (const VoxelIcon('star', size: 30), 'Title'),
      _ when r.glimmer > 0 => (const VoxelIcon('glimmer', size: 30), '${r.glimmer}'),
      _ => (const VoxelIcon('coin', size: 28), '${r.coins}'),
    };
    final big = r.items.keys.any((id) => (catalog[id]?.rarity ?? '') == 'legendary' || (catalog[id]?.rarity ?? '') == 'epic');
    return Opacity(
      opacity: reached || premium ? 1 : 0.75,
      child: Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: premium ? const Color(0xFF3A3470) : Night.card,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: big ? Night.gold : (premium ? Night.goldDim : const Color(0xFF4A5592)), width: big ? 2 : 1),
        ),
        child: Row(children: [
          icon,
          const SizedBox(width: 6),
          Expanded(
            child: Text(label, maxLines: 2, overflow: TextOverflow.ellipsis, style: EvochiText.tiny.copyWith(color: Night.text, height: 1.15)),
          ),
          if (claimed)
            const Icon(Icons.check_circle_rounded, color: Color(0xFF8BD17C), size: 20)
          else if (locked)
            const Icon(Icons.lock_rounded, color: Night.goldDim, size: 18),
        ]),
      ),
    );
  }
}

String _itemsLabel(e.SeasonReward r) {
  final parts = [for (final x in r.items.entries) '${x.value > 1 ? '${x.value} × ' : ''}${item(x.key).name}'];
  if (r.coins > 0) parts.add('${r.coins} coins');
  if (r.glimmer > 0) parts.add('${r.glimmer} Glimmer');
  if (r.title != null) parts.add('a title');
  return parts.join(' + ');
}

/// The Journey's season strip: the tier, what's waiting, and Evochi Plus's daily claim when it's ready.
class SeasonStrip extends StatelessWidget {
  const SeasonStrip({super.key});
  @override
  Widget build(BuildContext context) {
    final c = context.watch<GameController>();
    final v = e.seasonView(c.state, c.now);
    if (!v.active && v.claimable == 0) return const SizedBox.shrink();
    final plusReady = e.plusDailyReady(c.state, c.now);
    return Semantics(
      button: true,
      label: 'Season 1, ${v.def.name}: tier ${v.tier} of ${v.def.tiers}${v.claimable > 0 ? ', ${v.claimable} rewards to claim' : ''}',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: () => openSeason(context),
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Night.sky, Night.sky2]),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Night.gold, width: 2),
            boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 6, offset: Offset(0, 3))],
          ),
          child: Row(children: [
            const VoxelIcon('season', size: 42),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Season 1: ${v.def.name}', style: EvochiText.cardTitle.copyWith(color: Night.gold, fontSize: 15)),
                const SizedBox(height: 3),
                Row(children: [
                  Text('Tier ${v.tier}/${v.def.tiers}', style: EvochiText.tiny.copyWith(color: Night.text)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: v.tier >= v.def.tiers ? 1 : v.intoTier / v.def.tierXp,
                        minHeight: 6,
                        backgroundColor: const Color(0xFF151A36),
                        valueColor: const AlwaysStoppedAnimation(Night.gold),
                      ),
                    ),
                  ),
                ]),
                if (v.claimable > 0 || plusReady)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      [if (v.claimable > 0) '${v.claimable} reward${v.claimable == 1 ? '' : 's'} to claim', if (plusReady) 'Plus Glimmer waiting'].join(' · '),
                      style: EvochiText.tiny.copyWith(color: Night.glimmer),
                    ),
                  ),
              ]),
            ),
            if (v.claimable > 0 || plusReady) const BadgeDot(),
            const Icon(Icons.chevron_right_rounded, color: Night.gold, size: 28),
          ]),
        ),
      ),
    );
  }
}
