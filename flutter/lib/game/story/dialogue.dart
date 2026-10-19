// Villager dialogue for Village Tales: Chapter 1, the Home Tales, the side stories and the Lumen
// Trails (the Waystone's map lore and the three trail jobs). Lines are the Quest Bible's script (IDs
// kept); a few connective lines the Bible implies but doesn't write out (locked hints, "still
// waiting") are marked `extra`. Mirrors LINES / npcConversation / lineText in web/src/game/story.js.

import 'dart:math' as math;

import '../../core/models/game_state.dart';
import '../engine.dart' as g;
import 'story.dart';

class Line {
  const Line(this.speaker, this.expression, this.text, {this.extra = false});
  final String speaker; // npc id, 'waystone' or 'cottage'
  final String? expression; // neutral | happy | worried | thinking | proud
  final String text;
  final bool extra;
}

const lines = <String, Line>{
  'VQ01_M00': Line('npc_mira', 'happy', "Oh! You're new to Sunlit Village. I'm Mira. Your Evochi looks curious."),
  'VQ01_M01': Line('npc_mira', 'worried', 'The nursery lamp by the gate used to shine every evening. Lately, even the fireflies have forgotten the way home.'),
  'VQ01_M02': Line('npc_mira', 'thinking', 'Bram says its wick needs a Lumenbud. Those only wake when the morning dew gets stirred up.'),
  'VQ01_M03': Line('npc_mira', 'happy', "Wonderful! Take your Evochi on a walk. After {resolved_steps} new steps, I'll collect enough Dawn Dew for one sprig."),
  'VQ01_M04': Line('npc_mira', 'neutral', "The seedlings are listening. You've walked {progress}/{resolved_steps} steps since we spoke."),
  'VQ01_M05': Line('npc_mira', 'happy', 'There it is. A tiny bit of sunrise in a bottle. May I use it to wake this Lumenbud?'),
  'VQ01_M06': Line('npc_mira', 'proud', "Look! Three little lights. Take the sprig to Bram's workshop. He'll know where it belongs."),
  'VQ01_M07': Line('npc_mira', 'happy', 'Evening looks warmer now. Your footsteps made that happen.'),
  'VQ01_B00': Line('npc_bram', 'worried', "A dark lamp and no replacement wick. That's the sort of problem that keeps me up."),
  'VQ01_B01': Line('npc_bram', 'thinking', 'Well now. Mira grew a proper Lumenbud? Let me see those glowing leaves.'),
  'VQ01_B02': Line('npc_bram', 'happy', 'One twist here, a little spark there... Ha! The village has its glow back.'),
  'VQ01_B03': Line('npc_bram', 'proud', 'Keep this Firefly Hearth for your Nest. Good light is meant to be shared.'),
  'VQ01_B04': Line('npc_bram', 'neutral', "If that little Hearth ever flickers, don't worry. Good work lasts."),
  'VQ02_PIP00': Line('npc_pip', 'worried', 'Delivery for... oh! Sorry, I thought your Evochi was the postbox. The ears threw me off.'),
  'VQ02_PIP01': Line('npc_pip', 'worried', 'I promised Alder a letter from beyond the bridge. Trouble is, the wind scattered its special route paper!'),
  'VQ02_PIP02': Line('npc_pip', 'thinking', 'Not for an old trail letter. Windprint Paper only appears when someone walks the route with care.'),
  'VQ02_PIP03': Line('npc_pip', 'happy', "Two walks, two days. Reach {resolved_steps} steps on each day and we'll have enough paper to seal it."),
  'VQ02_PIP04': Line('npc_pip', 'neutral', "We're at {qualifying_days}/2 Windprints. One good walk at a time. No need to rush!"),
  'VQ02_PIP05': Line('npc_pip', 'happy', 'Both sheets! Let me fold the corners... and press the Guild seal. There!'),
  'VQ02_PIP06': Line('npc_pip', 'proud', 'Please hand this Sealed Trail Letter to Alder at the map desk. I want him to read it first.'),
  'VQ02_PIP07': Line('npc_pip', 'happy', 'Delivered! For once, my mail has a happy ending and all its corners.'),
  'PIP_LOCKED': Line('npc_pip', 'thinking', "I've got a long delivery brewing, but it's a big route for a little Evochi. {lock_hint} and come find me!", extra: true),
  'VQ02_ALD00': Line('npc_alder', 'neutral', 'Maps tell us where the road goes. Letters remind us why it matters.'),
  'VQ02_ALD01': Line('npc_alder', 'thinking', "That Guild seal... I haven't seen one of those in many seasons. May I?"),
  'VQ02_ALD02': Line('npc_alder', 'proud', "It's the old path record! There was a waystone on the north road. I thought we'd lost its story."),
  'VQ02_ALD03': Line('npc_alder', 'happy', 'Pip asked me to give you this Windtrail Mantle. Travelers should look the part.'),
  'VQ02_ALD04': Line('npc_alder', 'neutral', "The north road has another chapter left in it. Come back when you're ready."),
  'VQ03_ALD00': Line('npc_alder', 'thinking', 'Your letter unlocked an older map. See these three carved lines? They match the sleeping waystone in the Square.'),
  'VQ03_ALD01': Line('npc_alder', 'neutral', 'I believe so. The stone remembers three journeys, each on a different day. We need to trace those memories.'),
  'VQ03_ALD02': Line('npc_alder', 'happy', 'Walk {resolved_steps} steps on three separate days. Each day will reveal one Echo Rubbing.'),
  'VQ03_ALD03': Line('npc_alder', 'neutral', 'Old stones are patient. {qualifying_days}/3 memories found. Rest when you need to.'),
  'VQ03_ALD04': Line('npc_alder', 'proud', 'Three complete markings. Bram has the tools to bind them. Take them to his workshop.'),
  'ALD_WAITING': Line('npc_alder', 'thinking', 'The Core will want company before it wakes. Mira knows the last ingredient.', extra: true),
  'VQ03_ALD05': Line('npc_alder', 'happy', "The best maps don't tell us to hurry. They remind us there's somewhere worth going."),
  'VQ03_ALD06': Line('npc_alder', 'happy', 'The village shines differently with you in it.'),
  'VQ03_BRA00': Line('npc_bram', 'thinking', "These grooves aren't random scratches. They're a pattern. Here, let me make them a home."),
  'VQ03_BRA01': Line('npc_bram', 'proud', "A new Waystone Core. No sparks yet, mind you. You need Mira's Glowbloom Essence for that."),
  'VQ03_BRA02': Line('npc_bram', 'happy', 'Not bad for a few careful steps and a stubborn old lampwright.'),
  'VQ03_MIR00': Line('npc_mira', 'happy', "You found the stone's memory! The last ingredient isn't rare. It's care, gathered a little every day."),
  'VQ03_MIR01': Line('npc_mira', 'proud', "Take this. Plant the Core and Essence together in the Square. I'll meet you under the old lantern."),
  'VQ03_MIR02': Line('npc_mira', 'happy', 'Look at that... every path has a little light again.'),
  'VQ03_PIP08': Line('npc_pip', 'happy', "I'm going to need a bigger postbag for all this good news!"),
  'WAY_LORE': Line('waystone', null, 'An old standing stone in the middle of the Square, cool to the touch. Moss has crept into three faint carved lines.', extra: true),
  'VQ03_WAY00': Line('waystone', null, 'A cool stone with three dark channels. One of its grooves glimmers when your Evochi approaches.'),
  'VQ03_WAY01': Line('waystone', null, 'The Core settles into the stone. Mint light runs through the grooves. Fireflies rise over Sunlit Village.'),
  'WAY_DONE': Line('waystone', null, 'Mint light hums in the grooves. Fireflies drift over the Square, and every path out of the village has a little glow.', extra: true),

  // ---- Home Tales 1: A Place to Call Home (Bram)
  'HQ01_B00': Line('npc_bram', 'thinking', "That old cottage past your nest? Roof's half gone and the door's wandered off. Shame. It's a good little house."),
  'HQ01_B01': Line('npc_bram', 'neutral', "I'll fix it up if you'll lend a hand. I need sturdy timber, the kind you only spot when you're out walking the hedgerows."),
  'HQ01_B02': Line('npc_bram', 'happy', "Good! Walk {resolved_steps} steps and keep your eyes open. And grow a few Sunberries for the builders' lunch, eh?"),
  'HQ01_B03': Line('npc_bram', 'neutral', "Timber turns up for walkers. You're {progress}/{resolved_steps} steps along. No hurry."),
  'HQ01_B04': Line('npc_bram', 'thinking', "Fine timber, that! Now, about lunch... three Sunberries, if your garden's grown any. You've got {sunberry}/3."),
  'HQ01_B05': Line('npc_bram', 'happy', "Timber AND Sunberries. That's a builder's breakfast. Hand them over and I'll get the roof up."),
  'HQ01_B06': Line('npc_bram', 'proud', "Roof's on, shutters are hung. The last bit's yours: go and open the place up. It's on your Home Map."),
  'HQ01_B07': Line('npc_bram', 'neutral', "It's waiting for you. Go on, open it up."),
  'HQ01_B08': Line('npc_bram', 'happy', "Good roof, good friends. That's all a cottage needs."),
  'HQ01_C00': Line('cottage', null, 'The old cottage stands quiet. Bram has stacked the timber by the door, and new roof beams are waiting.'),
  'HQ01_C01': Line('cottage', null, 'Hammers tap, shutters swing open and a warm glow fills the windows. The chimney gives a happy little puff.'),
  'HQ01_C02': Line('cottage', null, 'An old cottage with a broken roof and an empty doorway. Someone in the village might know how to fix it.', extra: true),
  'HQ01_B09': Line('npc_bram', 'proud', 'There. A hearth, a kitchen, and a place to call home. Welcome in.'),

  // ---- Home Tales 2: Mira's Mortar (Mira)
  'HQ02_M00': Line('npc_mira', 'happy', 'Your kitchen smells lovely, all the way from here! Have you ever tried brewing?'),
  'HQ02_M01': Line('npc_mira', 'thinking', "My grandmother's mortar is gathering dust. Bring me two Glowleaf from your garden and I'll show you how it's done."),
  'HQ02_M02': Line('npc_mira', 'happy', "Glowleaf grows slowly, so plant it early. You'll need Farming level 3 to coax it out of the soil."),
  'HQ02_M03': Line('npc_mira', 'neutral', 'Any Glowleaf yet? You have {glowleaf}/2. The seedlings say hello.'),
  'HQ02_M04': Line('npc_mira', 'happy', "Oh, they're glowing beautifully! Here, take the mortar. Your cottage has a little back room that would suit it."),
  'HQ02_M05': Line('npc_mira', 'proud', 'The Apothecary is yours. Start with a Glowleaf Tonic. Stir slowly, smile often.'),
  'HQ02_M06': Line('npc_mira', 'happy', 'How are the brews going? Your Evochi looks very well looked after.'),

  // ---- Side story: The Shy Visitor (Pip)
  'SQ01_P00': Line('npc_pip', 'thinking', "Psst! Something small and fluffy keeps peeking at the mail sacks. I think it's hungry, but it's SO shy."),
  'SQ01_P01': Line('npc_pip', 'happy', "They say shy visitors can't resist a fresh Sunberry Tart. Could you bake one?"),
  'SQ01_P02': Line('npc_pip', 'happy', "Bake it in your Cottage kitchen and bring it here. I'll leave it on the step!"),
  'SQ01_P03': Line('npc_pip', 'neutral', 'No tart yet? Sunberries, wheat and a warm oven. You can do it!'),
  'SQ01_P04': Line('npc_pip', 'happy', 'It smells amazing! Let me put it on the step... shh... look!'),
  'SQ01_P05': Line('npc_pip', 'proud', 'A little fox-sprite! It took the tart and left some Moonshroom spores behind. I think that means thank you.'),
  'SQ01_P06': Line('npc_pip', 'happy', 'The fox-sprite waves at me now. Well, it wiggles its tail. Same thing!'),

  // ---- Side story: Guardian of the Old Grove (Alder)
  'SQ02_A00': Line('npc_alder', 'thinking', 'There is an old guardian in the grove past the north road. It only wakes for an Evochi that has grown a little.'),
  'SQ02_A01': Line('npc_alder', 'neutral', 'Bring a Glowleaf Tonic. The guardian is very old, and very thirsty.'),
  'SQ02_A02': Line('npc_alder', 'happy', "Brew one in your Apothecary, then come and find me. We'll walk there together."),
  'SQ02_A03': Line('npc_alder', 'neutral', 'The grove is patient. A Glowleaf Tonic, whenever you have one.'),
  'SQ02_A04': Line('npc_alder', 'proud', 'A fine tonic. The guardian opens one mossy eye, drinks, and the whole grove sighs with green light.'),
  'SQ02_A05': Line('npc_alder', 'happy', 'It remembered {pet}. Few travellers can say that.'),
  'SQ02_A06': Line('npc_alder', 'happy', 'The old grove has been greener since your visit.'),
  'SQ02_ALOCK': Line('npc_alder', 'thinking', 'Your Evochi is still very young. When it has grown into a Juvenile, ask me about the old grove.', extra: true),

  // ---- The Waystone's map (after Chapter 1): Alder's lore reveal
  'ALD_MAP00': Line('npc_alder', 'surprised', "Something strange happened when the Waystone woke. It doesn't just light the Square. Look: it's projecting a map."),
  'ALD_MAP01': Line('npc_alder', 'thinking', 'Ancient paths, reaching into regions nobody has walked in generations. The old books called them the Lumen Trails.'),
  'ALD_MAP02': Line('npc_alder', 'neutral', 'One trail leads to the Whispering Woods. Another toward a coastal cove. And a third, far older, has nearly vanished.'),
  'ALD_MAP03': Line('npc_alder', 'proud', "Evochi weren't made to fight one another, {pet}. They were guardians of these paths. Every species kept the world connected."),
  'ALD_MAP04': Line('npc_alder', 'thinking', "So here is our mystery: why did the trails fade, and why have some guardians forgotten their purpose? The Guild's discoveries will help us find out."),

  // ---- Trail 1: The Forest Guardian (Pip)
  'EQ01_P00': Line('npc_pip', 'happy', "Guild business! We've spotted an unusual Evochi near the Mossy Ruins. Leafy ears, a flower on its head, FAST."),
  'EQ01_P01': Line('npc_pip', 'thinking', "It's shy, so no chasing. Follow the clues on a walk, bring something it might like to eat, and let it come to you."),
  'EQ01_P02': Line('npc_pip', 'happy', "Walk {resolved_steps} steps and keep your eyes on the path. A Sunberry Tart wouldn't hurt either!"),
  'EQ01_P03': Line('npc_pip', 'neutral', "Any sign of it? You're {progress}/{resolved_steps} steps along the trail."),
  'EQ01_P04': Line('npc_pip', 'happy', "A clue! Pressed flower, green fur. It's at the ruins, I'd bet my satchel. Go gently."),
  'EQ01_P05': Line('npc_pip', 'proud', "You made friends with it?! A Petalune! The Guild hasn't logged one in forty years. Welcome to the Guild proper, Trail Friend."),
  'EQ01_P06': Line('npc_pip', 'happy', 'Petalune keeps leaving petals on my mail sacks. I think it likes you.'),
  'EQ01_LOCK': Line('npc_pip', 'thinking', "The Guild only sends members after wild Evochi. Finish a couple of daily discoveries first ({discoveries}/2 so far) and I'll put your name down.", extra: true),

  // ---- Trail 2: Tangled Lumen (Mira)
  'EQ02_M00': Line('npc_mira', 'worried', "Petalune led me to something sad at the ruins. A little plant spirit, all tangled up in purple light. It isn't sick. It's... faded."),
  'EQ02_M01': Line('npc_mira', 'thinking', 'The old books call it the Hollow: Lumen gone unstable. Kindness steadies it. Fresh Glowleaf helps most of all.'),
  'EQ02_M02': Line('npc_mira', 'happy', 'Walk {resolved_steps} steps near the ruins to gather a trace of its Lumen, and bring two Glowleaf from your garden.'),
  'EQ02_M03': Line('npc_mira', 'neutral', "How is the poor thing? You'll need 2 Glowleaf ({glowleaf}/2) and a steady heart."),
  'EQ02_M04': Line('npc_mira', 'proud', 'You restored it! Look at it bloom. Here, I wrote down a recipe: Lantern Tonic. Lumen Shards and Glowleaf. The Guild will want it.'),
  'EQ02_M05': Line('npc_mira', 'happy', 'The little sprout waves at everyone now. Whatever the Hollow is, it can be undone.'),

  // ---- Trail 3: The Forgotten Sentinel (Alder)
  'EQ03_A00': Line('npc_alder', 'thinking', "The faded third trail on the map. I've matched it to the north road, past the old bridge. There's a gate there, and something very old sleeping at it."),
  'EQ03_A01': Line('npc_alder', 'worried', "A guardian of the trails, tangled in Hollow for longer than anyone remembers. It won't be gentle. But it isn't our enemy."),
  'EQ03_A02': Line('npc_alder', 'neutral', 'Walk {resolved_steps} steps along the north road while I copy the map. Bring a Lantern Tonic: nothing steadies the Hollow like Lumen in a bottle.'),
  'EQ03_A03': Line('npc_alder', 'neutral', 'The bridge will hold. The question is the guardian. Lantern Tonic, a grown Evochi if you have one, and patience.'),
  'EQ03_A04': Line('npc_alder', 'proud', 'You restored a Sentinel. The map changed the moment it woke: the third trail is bright again, and it goes on past the horizon.'),
  'EQ03_A05': Line('npc_alder', 'happy', "I'll be honest, {pet}. I don't think the trails faded because the world was dying. I think they faded because people stopped exploring it."),
  'EQ03_A06': Line('npc_alder', 'happy', 'The Sentinel hums at dusk now. Pip says it sounds like the Waystone. More Trails are on the way, Trailwarden.'),
};

/// An engine action a dialogue choice runs before moving on.
class StoryAct {
  const StoryAct.accept(this.quest)
      : kind = 'accept',
        turnIn = null,
        npc = null;
  const StoryAct.handIn(this.quest, String this.turnIn)
      : kind = 'handin',
        npc = null;

  /// A one-time scene was seen: marks [npc] (a scene key) in `npcsMet`, then the choice moves on.
  const StoryAct.met(String this.npc)
      : kind = 'met',
        quest = '',
        turnIn = null;
  final String kind; // accept | handin | met
  final String quest;
  final String? turnIn;
  final String? npc; // met: the scene key (waystone_map, eq01_hint, eq01_thanks, ...)
}

class Choice {
  const Choice(this.label, {this.next, this.act, this.then, this.goto, this.npc, this.reward, this.leave = false});
  final String label;
  final String? next; // another line in this conversation
  final StoryAct? act;
  final String? then; // the line shown after [act] succeeds
  /// A place id, 'journey', 'discover' (Journey > Daily), 'prep:<quest>' (encounter prep), or a
  /// home destination: garden | cottage | kitchen | apothecary.
  final String? goto;
  final String? npc; // switch to another villager in the same place
  final String? reward; // open the reward card for this quest id
  final bool leave;

  /// Primary (gold) choices move the story forward.
  bool get primary => act != null || reward != null || goto == 'waystone';
}

class ConvNode {
  const ConvNode(this.id, this.choices);
  final String id;
  final List<Choice> choices;
}

class Conversation {
  const Conversation(this.npc, this.start, this.nodes);
  final String npc;
  final String start;
  final Map<String, ConvNode> nodes;
}

Choice _leave([String label = 'Leave']) => Choice(label, leave: true);

/// The conversation a villager (or the Waystone, or your Cottage) opens with in the current state.
Conversation npcConversation(GameState state, String npcId, int now) {
  final story = state.story;
  String ph(String qid) => questPhase(state, qid);
  final met = story.npcsMet[npcId] == true;
  final nodes = <String, ConvNode>{};
  String node(String id, List<Choice> choices) {
    nodes[id] = ConvNode(id, choices);
    return id;
  }

  late String start;
  switch (npcId) {
    case 'npc_mira':
      final p3 = ph('vq03');
      final p1 = ph('vq01');
      if (p3 == 'core_ready') {
        start = node('VQ03_MIR00', [const Choice('Ask Mira for Glowbloom Essence', act: StoryAct.handIn('vq03', 'mira_essence'), then: 'VQ03_MIR01'), _leave('Not yet')]);
        node('VQ03_MIR01', [const Choice('Go to the Waystone', goto: 'waystone'), _leave()]);
      } else if (p3 == 'restoration_ready') {
        start = node('VQ03_MIR01', [const Choice('Go to the Waystone', goto: 'waystone'), _leave()]);
      } else if (p1 == 'available') {
        node('VQ01_M01', [const Choice('What happened to it?', next: 'VQ01_M02'), const Choice('I can help.', act: StoryAct.accept('vq01'), then: 'VQ01_M03'), _leave('Maybe later.')]);
        node('VQ01_M02', [const Choice('I can help.', act: StoryAct.accept('vq01'), then: 'VQ01_M03'), _leave('Maybe later.')]);
        node('VQ01_M03', [const Choice('Go for a walk', goto: 'journey'), _leave('See you soon')]);
        start = met ? 'VQ01_M01' : node('VQ01_M00', [const Choice('Nice to meet you!', next: 'VQ01_M01')]);
      } else if (p1 == 'accepted_walk') {
        start = node('VQ01_M04', [const Choice('Go for a walk', goto: 'journey'), _leave('See you soon')]);
      } else if (p1 == 'dew_ready') {
        start = node('VQ01_M05', [const Choice('Give Dawn Dew Vial', act: StoryAct.handIn('vq01', 'mira_dew'), then: 'VQ01_M06'), _leave('Not yet')]);
        node('VQ01_M06', [const Choice("Go to Bram's Workshop", goto: 'workshop'), _leave()]);
      } else if (p1 == 'sprig_ready') {
        start = node('VQ01_M06', [const Choice("Go to Bram's Workshop", goto: 'workshop'), _leave()]);
      } else if (ph('hq02') == 'available') {
        node('HQ02_M00', [const Choice('Brewing?', next: 'HQ02_M01')]);
        node('HQ02_M01', [const Choice("I'd love to learn.", act: StoryAct.accept('hq02'), then: 'HQ02_M02'), _leave('Maybe later.')]);
        node('HQ02_M02', [const Choice('Visit your Garden', goto: 'garden'), _leave('See you soon')]);
        start = 'HQ02_M00';
      } else if (ph('hq02') == 'need_glowleaf') {
        if (nextStep(state, 'hq02').kind == 'handin') {
          start = node('HQ02_M04', [const Choice('Give 2 Glowleaf', act: StoryAct.handIn('hq02', 'mira_glowleaf'), then: 'HQ02_M05'), _leave('Not yet')]);
          node('HQ02_M05', [const Choice('Thank you, Mira!', reward: 'hq02')]);
        } else {
          start = node('HQ02_M03', [const Choice('Visit your Garden', goto: 'garden'), _leave('See you soon')]);
        }
      } else if (ph('eq02') == 'available') {
        node('EQ02_M00', [const Choice('Faded?', next: 'EQ02_M01')]);
        node('EQ02_M01', [const Choice("I'll help it.", act: StoryAct.accept('eq02'), then: 'EQ02_M02'), _leave('Maybe later.')]);
        node('EQ02_M02', [const Choice('Go for a walk', goto: 'journey'), const Choice('Visit your Garden', goto: 'garden'), _leave('See you soon')]);
        start = 'EQ02_M00';
      } else if (ph('eq02') == 'accepted_walk') {
        start = node('EQ02_M03', [const Choice('Go for a walk', goto: 'journey'), const Choice('Visit your Garden', goto: 'garden'), _leave('See you soon')]);
      } else if (ph('eq02') == 'ruins_ready') {
        start = node('EQ02_M03', [const Choice('Go to the Mossy Ruins', goto: 'prep:eq02'), const Choice('Visit your Garden', goto: 'garden'), _leave('See you soon')]);
      } else if (ph('eq02') == 'completed' && story.npcsMet['eq02_thanks'] != true) {
        start = node('EQ02_M04', [const Choice('Thank you, Mira!', act: StoryAct.met('eq02_thanks'), leave: true)]);
      } else if (p3 == 'completed' && ph('eq02') != 'completed') {
        start = node('VQ03_MIR02', [_leave('Goodbye, Mira')]);
      } else if (ph('eq02') == 'completed') {
        start = node('EQ02_M05', [_leave('Goodbye, Mira')]);
      } else if (ph('hq02') == 'completed') {
        start = node('HQ02_M06', [_leave('Goodbye, Mira')]);
      } else {
        start = node('VQ01_M07', [_leave('Goodbye, Mira')]);
      }
    case 'npc_bram':
      final p3 = ph('vq03');
      final p1 = ph('vq01');
      final h1 = ph('hq01');
      if (p3 == 'rubbings_ready') {
        start = node('VQ03_BRA00', [const Choice('Give 3 Echo Rubbings', act: StoryAct.handIn('vq03', 'bram_rubbings'), then: 'VQ03_BRA01'), _leave('Not yet')]);
        node('VQ03_BRA01', [const Choice("Go to Mira's Glasshouse", goto: 'glasshouse'), _leave()]);
      } else if (p3 == 'core_ready') {
        start = node('VQ03_BRA01', [const Choice("Go to Mira's Glasshouse", goto: 'glasshouse'), _leave()]);
      } else if (p1 == 'sprig_ready') {
        start = node('VQ01_B01', [const Choice('Give Lumenbud Sprig', act: StoryAct.handIn('vq01', 'bram_sprig'), then: 'VQ01_B02'), _leave('Not yet')]);
        node('VQ01_B02', [const Choice('Continue', next: 'VQ01_B03')]);
        node('VQ01_B03', [const Choice('Thank you, Bram!', reward: 'vq01')]);
      } else if (h1 == 'available') {
        node('HQ01_B00', [const Choice('What does it need?', next: 'HQ01_B01')]);
        node('HQ01_B01', [const Choice("I'll help!", act: StoryAct.accept('hq01'), then: 'HQ01_B02'), _leave('Maybe later.')]);
        node('HQ01_B02', [const Choice('Go for a walk', goto: 'journey'), const Choice('Visit your Garden', goto: 'garden'), _leave('See you soon')]);
        start = 'HQ01_B00';
      } else if (h1 == 'accepted_walk') {
        start = node('HQ01_B03', [const Choice('Go for a walk', goto: 'journey'), const Choice('Visit your Garden', goto: 'garden'), _leave('See you soon')]);
      } else if (h1 == 'timber_ready') {
        if (nextStep(state, 'hq01').kind == 'handin') {
          start = node('HQ01_B05', [const Choice('Give the timber and 3 Sunberries', act: StoryAct.handIn('hq01', 'bram_timber'), then: 'HQ01_B06'), _leave('Not yet')]);
          node('HQ01_B06', [const Choice('Go to your Cottage', goto: 'cottage'), _leave()]);
        } else {
          start = node('HQ01_B04', [const Choice('Visit your Garden', goto: 'garden'), _leave('See you soon')]);
        }
      } else if (h1 == 'restoration_ready') {
        start = node('HQ01_B07', [const Choice('Go to your Cottage', goto: 'cottage'), _leave()]);
      } else if (p3 == 'completed') {
        start = node('VQ03_BRA02', [_leave('Goodbye, Bram')]);
      } else if (h1 == 'completed') {
        start = node('HQ01_B08', [_leave('Goodbye, Bram')]);
      } else if (p1 == 'completed') {
        start = node('VQ01_B04', [_leave('Goodbye, Bram')]);
      } else {
        start = node('VQ01_B00', [_leave()]);
      }
    case 'npc_pip':
      final p2 = ph('vq02');
      final p3 = ph('vq03');
      final s1 = ph('sq01');
      final e1 = ph('eq01');
      final e1lock = lockReason(state, 'eq01');
      if (p2 == 'paper_2_ready') {
        start = node('VQ02_PIP05', [const Choice('Give 2 Windprint Papers', act: StoryAct.handIn('vq02', 'pip_papers'), then: 'VQ02_PIP06'), _leave('Not yet')]);
        node('VQ02_PIP06', [const Choice('Talk to Alder', npc: 'npc_alder'), _leave()]);
      } else if (p2 == 'letter_ready') {
        start = node('VQ02_PIP06', [const Choice('Talk to Alder', npc: 'npc_alder'), _leave()]);
      } else if (e1 == 'available') {
        // the Guild's first trail job: offered as soon as it unlocks, even mid-chapter
        node('EQ01_P00', [const Choice('Shy how?', next: 'EQ01_P01')]);
        node('EQ01_P01', [const Choice("I'll find it.", act: StoryAct.accept('eq01'), then: 'EQ01_P02'), _leave('Not now.')]);
        node('EQ01_P02', [const Choice('Go for a walk', goto: 'journey'), const Choice('Go to your Kitchen', goto: 'kitchen'), _leave('See you soon')]);
        start = met ? 'EQ01_P00' : node('VQ02_PIP00', [const Choice('Hello, Pip!', next: 'EQ01_P00')]);
      } else if (e1 == 'accepted_walk') {
        start = node('EQ01_P03', [const Choice('Go for a walk', goto: 'journey'), _leave('See you soon')]);
      } else if (e1 == 'ruins_ready') {
        start = node('EQ01_P04', [const Choice('Go to the Mossy Ruins', goto: 'prep:eq01'), _leave('Not yet')]);
      } else if (e1 == 'completed' && story.npcsMet['eq01_thanks'] != true) {
        start = node('EQ01_P05', [const Choice('Thank you, Pip!', act: StoryAct.met('eq01_thanks'), leave: true)]);
      } else if (p2 == 'locked') {
        node('PIP_LOCKED', [_leave('Okay!')]);
        start = met ? 'PIP_LOCKED' : node('VQ02_PIP00', [const Choice('Hello, Pip!', next: 'PIP_LOCKED')]);
      } else if (p2 == 'available') {
        node('VQ02_PIP01', [
          const Choice("Can't you use ordinary paper?", next: 'VQ02_PIP02'),
          const Choice("I'll help deliver it.", act: StoryAct.accept('vq02'), then: 'VQ02_PIP03'),
          _leave('Not now.'),
        ]);
        node('VQ02_PIP02', [const Choice("I'll help deliver it.", act: StoryAct.accept('vq02'), then: 'VQ02_PIP03'), _leave('Not now.')]);
        node('VQ02_PIP03', [const Choice('Go for a walk', goto: 'journey'), _leave('See you soon')]);
        start = met ? 'VQ02_PIP01' : node('VQ02_PIP00', [const Choice('Hello, Pip!', next: 'VQ02_PIP01')]);
      } else if (p2 == 'accepted_two_days') {
        // mid-walk: Pip nudges you on, and mentions the Guild's rule for its first trail job once
        final lockHint = e1 == 'locked' && e1lock != null && e1lock.needDiscoveries > 0 && e1lock.needQuest == null && story.npcsMet['eq01_hint'] != true;
        if (lockHint) {
          node('EQ01_LOCK', [
            const Choice("See today's discoveries", goto: 'discover', act: StoryAct.met('eq01_hint')),
            const Choice('Okay!', act: StoryAct.met('eq01_hint'), leave: true),
          ]);
          start = 'EQ01_LOCK';
        } else {
          start = node('VQ02_PIP04', [const Choice('Go for a walk', goto: 'journey'), _leave('See you soon')]);
        }
      } else if (e1 == 'locked' && e1lock != null && e1lock.needDiscoveries > 0 && p2 != 'available' && p2 != 'locked') {
        start = node('EQ01_LOCK', [const Choice("See today's discoveries", goto: 'discover'), _leave('Okay!')]);
      } else if (s1 == 'available') {
        node('SQ01_P00', [const Choice('Hungry?', next: 'SQ01_P01')]);
        node('SQ01_P01', [const Choice("I'll bake one!", act: StoryAct.accept('sq01'), then: 'SQ01_P02'), _leave('Not now.')]);
        node('SQ01_P02', [const Choice('Go to your Kitchen', goto: 'kitchen'), _leave('See you soon')]);
        start = 'SQ01_P00';
      } else if (s1 == 'need_tart') {
        if (nextStep(state, 'sq01').kind == 'handin') {
          start = node('SQ01_P04', [const Choice('Give a Sunberry Tart', act: StoryAct.handIn('sq01', 'pip_tart'), then: 'SQ01_P05'), _leave('Not yet')]);
          node('SQ01_P05', [const Choice('Thank you, Pip!', reward: 'sq01')]);
        } else {
          start = node('SQ01_P03', [const Choice('Go to your Kitchen', goto: 'kitchen'), _leave('See you soon')]);
        }
      } else if (p3 == 'completed') {
        start = node('VQ03_PIP08', [_leave('Goodbye, Pip')]);
      } else if (e1 == 'completed' && (s1 == 'completed' || s1 == 'locked')) {
        start = node('EQ01_P06', [_leave('Goodbye, Pip')]);
      } else if (s1 == 'completed') {
        start = node('SQ01_P06', [_leave('Goodbye, Pip')]);
      } else {
        start = node('VQ02_PIP07', [_leave('Goodbye, Pip')]);
      }
    case 'npc_alder':
      final p2 = ph('vq02');
      final p3 = ph('vq03');
      if (p2 == 'letter_ready') {
        start = node('VQ02_ALD01', [const Choice('Hand over the Sealed Trail Letter', act: StoryAct.handIn('vq02', 'alder_letter'), then: 'VQ02_ALD02'), _leave('Not yet')]);
        node('VQ02_ALD02', [const Choice('Continue', next: 'VQ02_ALD03')]);
        node('VQ02_ALD03', [const Choice('Thank you, Alder!', reward: 'vq02')]);
      } else if (p3 == 'available') {
        node('VQ03_ALD00', [
          const Choice('Can it be repaired?', next: 'VQ03_ALD01'),
          const Choice("Let's wake it.", act: StoryAct.accept('vq03'), then: 'VQ03_ALD02'),
          _leave('I need more time.'),
        ]);
        node('VQ03_ALD01', [const Choice("Let's wake it.", act: StoryAct.accept('vq03'), then: 'VQ03_ALD02'), _leave('I need more time.')]);
        node('VQ03_ALD02', [const Choice('Go for a walk', goto: 'journey'), _leave('See you soon')]);
        start = 'VQ03_ALD00';
      } else if (p3 == 'accepted_three_days') {
        start = node('VQ03_ALD03', [const Choice('Go for a walk', goto: 'journey'), _leave('See you soon')]);
      } else if (p3 == 'rubbings_ready') {
        start = node('VQ03_ALD04', [const Choice("Go to Bram's Workshop", goto: 'workshop'), _leave()]);
      } else if (p3 == 'core_ready' || p3 == 'restoration_ready') {
        final core = p3 == 'core_ready';
        start = node('ALD_WAITING', [Choice(core ? "Go to Mira's Glasshouse" : 'Go to the Waystone', goto: core ? 'glasshouse' : 'waystone'), _leave()]);
      } else if (p3 == 'completed' && story.npcsMet['waystone_map'] != true) {
        node('ALD_MAP00', [const Choice('A map?', next: 'ALD_MAP01')]);
        node('ALD_MAP01', [const Choice('Where do they go?', next: 'ALD_MAP02')]);
        node('ALD_MAP02', [const Choice('Continue', next: 'ALD_MAP03')]);
        node('ALD_MAP03', [const Choice('Continue', next: 'ALD_MAP04')]);
        node('ALD_MAP04', [const Choice("Let's find out", act: StoryAct.met('waystone_map'), leave: true)]);
        start = 'ALD_MAP00';
      } else if (ph('eq03') == 'available') {
        node('EQ03_A00', [const Choice('Something old?', next: 'EQ03_A01')]);
        node('EQ03_A01', [const Choice("Let's wake it.", act: StoryAct.accept('eq03'), then: 'EQ03_A02'), _leave('I need more time.')]);
        node('EQ03_A02', [const Choice('Go for a walk', goto: 'journey'), const Choice('Go to your Apothecary', goto: 'apothecary'), _leave('See you soon')]);
        start = 'EQ03_A00';
      } else if (ph('eq03') == 'accepted_walk') {
        start = node('EQ03_A03', [const Choice('Go for a walk', goto: 'journey'), const Choice('Go to your Apothecary', goto: 'apothecary'), _leave('See you soon')]);
      } else if (ph('eq03') == 'gate_ready') {
        start = node('EQ03_A03', [const Choice('Go to the old gate', goto: 'prep:eq03'), const Choice('Go to your Apothecary', goto: 'apothecary'), _leave('See you soon')]);
      } else if (ph('eq03') == 'completed' && story.npcsMet['eq03_thanks'] != true) {
        node('EQ03_A04', [const Choice('Continue', next: 'EQ03_A05')]);
        node('EQ03_A05', [const Choice('Thank you, Alder', act: StoryAct.met('eq03_thanks'), leave: true)]);
        start = 'EQ03_A04';
      } else if (ph('eq03') == 'completed' && ph('sq02') != 'available' && ph('sq02') != 'need_tonic') {
        start = node('EQ03_A06', [_leave('Goodbye, Alder')]);
      } else if (ph('sq02') == 'available') {
        node('SQ02_A00', [const Choice('What does it need?', next: 'SQ02_A01')]);
        node('SQ02_A01', [const Choice("Let's wake it.", act: StoryAct.accept('sq02'), then: 'SQ02_A02'), _leave('Another time.')]);
        node('SQ02_A02', [const Choice('Go to your Apothecary', goto: 'apothecary'), _leave('See you soon')]);
        start = 'SQ02_A00';
      } else if (ph('sq02') == 'need_tonic') {
        final k = nextStep(state, 'sq02').kind;
        if (k == 'handin') {
          start = node('SQ02_A04', [const Choice('Offer the Glowleaf Tonic', act: StoryAct.handIn('sq02', 'alder_tonic'), then: 'SQ02_A05'), _leave('Not yet')]);
          node('SQ02_A05', [const Choice('Thank you, Alder!', reward: 'sq02')]);
        } else if (k == 'grow') {
          start = node('SQ02_ALOCK', [_leave('Okay!')]);
        } else {
          start = node('SQ02_A03', [const Choice('Go to your Apothecary', goto: 'apothecary'), _leave('See you soon')]);
        }
      } else if (ph('sq02') == 'locked' && ph('hq02') == 'completed' && lockReason(state, 'sq02')?.needStage != null) {
        start = node('SQ02_ALOCK', [_leave('Okay!')]);
      } else if (p3 == 'completed') {
        start = node('VQ03_ALD06', [_leave('Goodbye, Alder')]);
      } else if (ph('sq02') == 'completed') {
        start = node('SQ02_A06', [_leave('Goodbye, Alder')]);
      } else if (p2 == 'completed') {
        start = node('VQ02_ALD04', [_leave()]);
      } else {
        start = node('VQ02_ALD00', [_leave()]);
      }
    case 'cottage':
      if (ph('hq01') == 'restoration_ready') {
        start = node('HQ01_C00', [const Choice('Restore the Cottage', act: StoryAct.handIn('hq01', 'restore_cottage'), then: 'HQ01_C01'), _leave('Not yet')]);
        node('HQ01_C01', [const Choice('Continue', next: 'HQ01_B09')]);
        node('HQ01_B09', [const Choice('Step inside', reward: 'hq01')]);
      } else {
        start = node('HQ01_C02', [_leave('Back to the map')]);
      }
    case 'waystone':
      final p3 = ph('vq03');
      if (p3 == 'completed') {
        start = node('WAY_DONE', [_leave('Back to the Square')]);
      } else if (p3 == 'restoration_ready') {
        start = node('VQ03_WAY00', [const Choice('Restore the Waystone', act: StoryAct.handIn('vq03', 'restore'), then: 'VQ03_WAY01'), _leave('Not yet')]);
        node('VQ03_WAY01', [const Choice('Continue', next: 'VQ03_MIR02')]);
        node('VQ03_MIR02', [const Choice('Continue', next: 'VQ03_BRA02')]);
        node('VQ03_BRA02', [const Choice('Continue', next: 'VQ03_PIP08')]);
        node('VQ03_PIP08', [const Choice('Continue', next: 'VQ03_ALD05')]);
        node('VQ03_ALD05', [const Choice('Claim your rewards', reward: 'vq03')]);
      } else if (story.flags['waystone_revealed'] == true) {
        start = node('VQ03_WAY00', [_leave('Back to the Square')]);
      } else {
        start = node('WAY_LORE', [_leave('Back to the Square')]);
      }
    default:
      throw ArgumentError('Unknown villager $npcId');
  }
  return Conversation(npcId, start, nodes);
}

/// Line text with live values filled in.
String lineText(GameState state, String id, int now, {String petName = 'your Evochi'}) {
  final l = lines[id];
  if (l == null) return '';
  const byPrefix = {'VQ01': 'vq01', 'VQ02': 'vq02', 'PIP_': 'vq02', 'HQ01': 'hq01', 'HQ02': 'hq02', 'SQ01': 'sq01', 'SQ02': 'sq02', 'EQ01': 'eq01', 'EQ02': 'eq02', 'EQ03': 'eq03', 'ALD_': 'vq03'};
  final qid = byPrefix[id.length >= 4 ? id.substring(0, 4) : id] ?? 'vq03';
  final v = questView(state, qid, now);
  final lock = lockReason(state, 'vq02');
  final hint = lock == null
      ? 'Come back soon'
      : lock.needLevel && lock.needQuest != null
          ? 'Help Mira and Bram light the lamp, reach level ${lock.level},'
          : lock.needLevel
              ? 'Reach level ${lock.level}'
              : 'Help Mira and Bram light the lamp first,';
  final sunberry = math.min(3, g.ownedQty(state, 'sunberry'));
  final glowleaf = math.min(2, g.ownedQty(state, 'glowleaf'));
  return fill(l.text, {
    'resolved_steps': fmtN(v.resolved),
    'progress': fmtN(v.walk.progress),
    'qualifying_days': '${v.walk.qualified}',
    'lock_hint': hint,
    'pet': petName,
    'sunberry': '$sunberry',
    'glowleaf': '$glowleaf',
    'discoveries': '${state.trails.stat('discoveries')}',
  });
}
