// My Evochis (docs: the Hatching Nook & Companion Collection bible): every Evochi you have, the active
// one first, as a grid of portraits you can search, filter (favourites, stage) and sort (newest,
// bond, name). Tap one for its card: who it is, how it has grown, what it wears, where it came from and
// what it remembers, with Set Active in plain sight. Switching is a tap; the one resting keeps all it
// had. The quick switch (the same sheet) opens from the active Evochi wherever the Home shows it.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/constants.dart';
import '../../app/theme.dart';
import '../../controllers/game_controller.dart';
import '../../core/models/game_state.dart';
import '../../core/services/haptics.dart';
import '../../game/bond/bond.dart';
import '../../game/hatch/hatch.dart' as hatch;
import '../../game/xp/xp.dart';
import '../shared/kit.dart';
import '../shared/sprite.dart';
import '../shared/widgets.dart';

/// Open My Evochis; [focus] opens straight onto that one's card.
Future<void> showCompanions(BuildContext context, {String? focus}) => showEvochiSheet<void>(context, builder: (_) => CompanionsSheet(focus: focus));

class CompanionsSheet extends StatefulWidget {
  const CompanionsSheet({super.key, this.focus});
  final String? focus;
  @override
  State<CompanionsSheet> createState() => _CompanionsSheetState();
}

class _CompanionsSheetState extends State<CompanionsSheet> {
  String? _open; // the card shown
  String _q = '';
  String _filter = 'all'; // all | fav | 1 | 2 | 3
  String _sort = 'newest'; // newest | bond | name

  @override
  void initState() {
    super.initState();
    _open = widget.focus;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<GameController>();
    final s = c.state;
    final all = hatch.allPets(s);
    if (_open != null) {
      final p = all.where((p) => p.id == _open).firstOrNull;
      if (p != null) return _Card(pet: p, onBack: () => setState(() => _open = null));
      _open = null;
    }
    final list = all.where((p) {
      if (_q.isNotEmpty && !p.name.toLowerCase().contains(_q.toLowerCase()) && !hatch.paletteLabel(p.paletteId).toLowerCase().contains(_q.toLowerCase())) return false;
      return switch (_filter) {
        'fav' => hatch.isFavorite(s, p.id),
        '1' || '2' || '3' => p.stage.toString() == _filter,
        _ => true,
      };
    }).toList();
    list.sort((a, b) {
      if (a.id == s.pet?.id) return -1;
      if (b.id == s.pet?.id) return 1;
      final fa = hatch.isFavorite(s, a.id), fb = hatch.isFavorite(s, b.id);
      if (fa != fb) return fa ? -1 : 1;
      return switch (_sort) {
        'bond' => bondValue(b.bondEvents).compareTo(bondValue(a.bondEvents)),
        'name' => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        _ => b.createdAt.compareTo(a.createdAt),
      };
    });
    return Semantics(
      container: true,
      label: 'My Evochis',
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Center(child: WoodPlaque(child: Text('My Evochis', style: WoodPlaque.text(EvochiText.section)))),
        const SizedBox(height: 8),
        Text('${all.length} companion${all.length == 1 ? '' : 's'} · one active, the rest resting safe at home', textAlign: TextAlign.center, style: EvochiText.caption),
        const SizedBox(height: 8),
        if (all.length > 3)
          TextField(
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Search by name or colour', isDense: true, border: OutlineInputBorder()),
            onChanged: (v) => setState(() => _q = v),
          ),
        if (all.length > 2) ...[
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              for (final (id, label) in const [('all', 'All'), ('fav', 'Favourites'), ('1', 'Hatchlings'), ('2', 'Juveniles'), ('3', 'Elders')])
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: _Chip(label: label, on: _filter == id, onTap: () => setState(() => _filter = id)),
                ),
              const SizedBox(width: 10),
              for (final (id, label) in const [('newest', 'Newest'), ('bond', 'Bond'), ('name', 'A–Z')])
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: _Chip(label: label, on: _sort == id, onTap: () => setState(() => _sort = id), icon: Icons.sort_rounded),
                ),
            ]),
          ),
        ],
        const SizedBox(height: 10),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 420),
          child: GridView.builder(
            shrinkWrap: true,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 8, crossAxisSpacing: 8, childAspectRatio: 0.86),
            itemCount: list.length,
            itemBuilder: (_, i) => _Portrait(pet: list[i], active: list[i].id == s.pet?.id, onTap: () => setState(() => _open = list[i].id)),
          ),
        ),
        if (list.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(_q.isNotEmpty || _filter != 'all' ? 'None match.' : 'No companions yet. Hatch an egg in the nook.', textAlign: TextAlign.center, style: EvochiText.bodyText),
          ),
        const SizedBox(height: 8),
        Center(child: EvochiButton(label: 'Close', tone: ButtonTone.cream, small: true, expand: false, onPressed: () => Navigator.of(context).pop())),
      ]),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.on, required this.onTap, this.icon});
  final String label;
  final bool on;
  final VoidCallback onTap;
  final IconData? icon;
  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        selected: on,
        label: label,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            height: 30,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            alignment: Alignment.center,
            decoration: on ? Kit.wood(radius: 9) : Kit.parchment(radius: 9, depth: 2, drop: false),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (icon != null) ...[Icon(icon, size: 14, color: on ? KitColor.signInk : KitColor.woodInk), const SizedBox(width: 3)],
              Text(label, style: EvochiText.tag.copyWith(fontSize: 12, color: KitColor.signInk)),
            ]),
          ),
        ),
      );
}

/// One companion in the grid: its sprite on a parchment card, name, stage, a star when favourite, a
/// gold "Active" plaque on the one that is out with you.
class _Portrait extends StatelessWidget {
  const _Portrait({required this.pet, required this.active, required this.onTap});
  final Pet pet;
  final bool active;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final s = context.read<GameController>().state;
    final fav = hatch.isFavorite(s, pet.id);
    return Semantics(
      button: true,
      label: '${pet.name}, ${stageLabels[pet.stage]}${active ? ', active' : ''}${fav ? ', favourite' : ''}',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
          decoration: Kit.card(highlight: active),
          child: Column(children: [
            Expanded(
              child: Stack(alignment: Alignment.center, children: [
                PetSprite(stage: pet.stage, palette: pet.paletteId, expr: active ? 'happy' : 'default', overlays: pet.equipped.values.toList(), height: 84),
                if (fav) const Positioned(top: 0, right: 0, child: VoxelIcon('star', size: 18)),
                if (active)
                  Positioned(
                    top: 0,
                    left: 0,
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(6, 2, 6, 2),
                      decoration: Kit.wood(radius: 7),
                      child: Text('Active', style: EvochiText.tag.copyWith(fontSize: 10.5, color: KitColor.signInk)),
                    ),
                  ),
              ]),
            ),
            const SizedBox(height: 4),
            Text(pet.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: EvochiText.cardTitle.copyWith(fontSize: 15)),
            Text('${hatch.paletteLabel(pet.paletteId)} · ${stageLabels[pet.stage]}', style: EvochiText.caption.copyWith(fontSize: 12)),
          ]),
        ),
      ),
    );
  }
}

/// A companion's card: Overview, Growth, Gear and Memories, Set Active at the bottom.
class _Card extends StatefulWidget {
  const _Card({required this.pet, required this.onBack});
  final Pet pet;
  final VoidCallback onBack;
  @override
  State<_Card> createState() => _CardState();
}

class _CardState extends State<_Card> {
  String _tab = 'overview';

  @override
  Widget build(BuildContext context) {
    final c = context.watch<GameController>();
    final s = c.state;
    final p = widget.pet;
    final active = s.pet?.id == p.id;
    final fav = hatch.isFavorite(s, p.id);
    final xp = p.xpAwarded.values.fold(0, (a, b) => a + b);
    final lvl = levelInfo(xp);
    final bond = bondValue(p.bondEvents);
    final firstDay = p.createdDay;
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        BackSquareButton(onTap: widget.onBack),
        const SizedBox(width: 8),
        Expanded(child: Text(p.name, style: EvochiText.section, maxLines: 1, overflow: TextOverflow.ellipsis)),
        Semantics(
          button: true,
          label: fav ? 'Remove from favourites' : 'Add to favourites',
          child: GestureDetector(
            onTap: () {
              c.run((st, n) => hatch.toggleFavorite(st, p.id), quiet: true);
              c.audio.buzz(Haptic.tick);
            },
            child: Opacity(opacity: fav ? 1 : 0.4, child: const VoxelIcon('star', size: 28)),
          ),
        ),
      ]),
      const SizedBox(height: 8),
      Row(children: [
        Container(
          width: 120,
          height: 120,
          decoration: Kit.well(round: true),
          alignment: Alignment.center,
          child: PetSprite(stage: p.stage, palette: p.paletteId, expr: 'happy', overlays: p.equipped.values.toList(), height: 100),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${hatch.paletteLabel(p.paletteId)} · ${stageLabels[p.stage]}', style: EvochiText.cardTitle),
            const SizedBox(height: 4),
            Text('Level ${lvl.level}', style: EvochiText.bodyText),
            Row(children: [const Text('Bond ', style: EvochiText.bodyText), Hearts(filled: bondHearts(bond), bond: bond)]),
            const SizedBox(height: 4),
            Text(p.origin ?? 'Your first Evochi', style: EvochiText.caption),
            if (active) ...[const SizedBox(height: 6), const Tag('Active now', tone: TagTone.ok)],
          ]),
        ),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        for (final (id, label) in const [('overview', 'Overview'), ('growth', 'Growth'), ('gear', 'Gear'), ('memories', 'Memories')])
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Semantics(
                button: true,
                selected: _tab == id,
                label: label,
                child: GestureDetector(
                  onTap: () => setState(() => _tab = id),
                  child: KitTab(selected: _tab == id, height: 36, child: Text(label, style: EvochiText.tag.copyWith(fontSize: 12, color: _tab == id ? KitColor.signInk : KitColor.tabText))),
                ),
              ),
            ),
          ),
      ]),
      const SizedBox(height: 8),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: Kit.inset(),
        constraints: const BoxConstraints(minHeight: 110),
        child: switch (_tab) {
          'growth' => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Steps have raised ${p.name} to level ${lvl.level}: ${lvl.into} of ${lvl.need} toward the next.', style: EvochiText.bodyText),
              const SizedBox(height: 6),
              for (final e in p.evolutions) Text('${stageLabels[e['stage']] ?? 'Stage ${e['stage']}'} since ${_when(e['at'] ?? 0)}', style: EvochiText.bodyText),
            ]),
          'gear' => p.equipped.isEmpty
              ? Text('${p.name} wears nothing yet. Wearables are kept per Evochi; mining gear is one loadout for whoever goes out.', style: EvochiText.bodyText)
              : Wrap(spacing: 8, runSpacing: 8, children: [for (final id in p.equipped.values) Column(mainAxisSize: MainAxisSize.min, children: [ItemImage(id, size: 40), Text(id, style: EvochiText.tiny)])]),
          'memories' => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p.origin == null ? 'Hatched at the very start of your story.' : '${p.origin}, hatched ${_when(p.createdAt)}.', style: EvochiText.bodyText),
              const SizedBox(height: 4),
              Text('${p.bondEvents.where((e) => e.type == 'goal').length} days the walk goal was met together.', style: EvochiText.bodyText),
              Text('${p.events.where((e) => e.type == 'care').length} times cared for.', style: EvochiText.bodyText),
            ]),
          _ => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${p.name} the ${hatch.paletteLabel(p.paletteId)} ${stageLabels[p.stage]!.toLowerCase()}, with you since $firstDay.', style: EvochiText.bodyText),
              const SizedBox(height: 6),
              Text(active ? 'Out with you now.' : 'Resting at home, safe: nothing it has is lost while it waits.', style: EvochiText.caption),
            ]),
        },
      ),
      const SizedBox(height: 10),
      if (active)
        const EvochiButton(label: 'This is your active Evochi', tone: ButtonTone.cream, onPressed: null)
      else
        EvochiButton(
          label: 'Set active',
          icon: const VoxelIcon('paw', size: 22),
          onPressed: () {
            final r = c.run((st, n) => hatch.setActive(st, p.id), quiet: true);
            if (r.ok) {
              c.audio.play('equip', volume: 0.6);
              c.audio.buzz(Haptic.good);
              c.toast('${p.name} is with you now.', icon: 'paw');
              c.analytics.track('companion_activated', {'palette': p.paletteId, 'stage': p.stage});
              Navigator.of(context).pop();
            }
          },
        ),
      const SizedBox(height: 6),
      Row(children: [
        Expanded(child: EvochiButton(label: 'Rename', tone: ButtonTone.cream, small: true, onPressed: () => _rename(context, c, p))),
      ]),
    ]);
  }

  static String _when(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  Future<void> _rename(BuildContext context, GameController c, Pet p) async {
    final ctl = TextEditingController(text: p.name);
    String? err;
    await showEvochiDialog<void>(context, builder: (d) {
      return StatefulBuilder(builder: (d, setD) {
        return Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('A new name', style: EvochiText.section),
          const SizedBox(height: 8),
          TextField(controller: ctl, maxLength: 16, autofocus: true, decoration: InputDecoration(errorText: err, counterText: '', border: const OutlineInputBorder())),
          const SizedBox(height: 8),
          EvochiButton(
            label: 'Keep it',
            onPressed: () {
              final r = c.run((st, n) => hatch.renameCompanion(st, p.id, ctl.text), quiet: true);
              if (!r.ok) {
                setD(() => err = (r.info['message'] as String?) ?? 'Try another');
                return;
              }
              Navigator.pop(d);
            },
          ),
          const SizedBox(height: 6),
          EvochiButton(label: 'Cancel', tone: ButtonTone.cream, onPressed: () => Navigator.pop(d)),
        ]);
      });
    });
    if (mounted) setState(() {});
  }
}
