// Village Tales routing: the Village is the walkable Square (village_walk.dart) and its three houses are
// walkable rooms where the villagers live; every conversation is the chathead talk where they stand
// (chathead_talk.dart). openVillage and openPlace are how the rest of the game gets there (Home's Village
// button, Journey > Story's "Go to...", the Quest Pouch, discoveries, rewards). Also here: the title bar the
// Village, Home and trail screens share.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../controllers/game_controller.dart';
import '../../game/story/story.dart' as q;
import '../nest/sheets.dart';
import '../shared/kit.dart';
import '../shared/widgets.dart';
import 'village_walk.dart';

/// Open the Square from anywhere (Home, Journey > Story, the Quest Pouch, after a reward). From inside a
/// house, you step back out into it.
void openVillage(BuildContext context) {
  final nav = Navigator.of(context);
  final here = ModalRoute.of(context)?.settings.name;
  if (here == 'village') return;
  if (here == 'place') {
    nav.pushReplacement(walkMapRoute('village'));
    return;
  }
  nav.push(walkMapRoute('village'));
}

/// Go to a place to talk: one of the houses ('lodge', 'glasshouse', 'workshop'), you walk in at its door and
/// the talk opens with [npc] (or whoever there has something for you); the 'waystone', you arrive in the
/// Square and the stone's talk opens. From one place to another the screen is replaced.
void openPlace(BuildContext context, String id, {String? npc}) {
  final nav = Navigator.of(context);
  final here = ModalRoute.of(context)?.settings.name;
  final Route<void> route;
  if (id == 'waystone') {
    route = walkMapRoute('village', talk: 'waystone');
  } else if (q.places.containsKey(id)) {
    final marks = q.npcMarkers(context.read<GameController>().state);
    final who = npc ?? q.places[id]!.npcs.where(marks.containsKey).firstOrNull;
    route = walkMapRoute(id, at: 'village', talk: who);
  } else {
    return openVillage(context);
  }
  if (here == 'place' || here == 'village') {
    nav.pushReplacement(route);
    return;
  }
  nav.push(route);
}

/// Back to the Square after a reward.
void returnToVillage(BuildContext context) => openVillage(context);

/// The title bar used by the Village, Home and trail screens: a light-wood Back square, the place name on
/// a nailed wooden plaque, EvoCoins on dark wood.
class PlaceHeader extends StatelessWidget {
  const PlaceHeader({super.key, required this.title, required this.short, required this.onBack, required this.backLabel});
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
              child: WoodPlaque(
                height: 42,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(narrow ? short : title, style: WoodPlaque.text(EvochiText.section.copyWith(fontWeight: FontWeight.w900, fontSize: 19))),
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
