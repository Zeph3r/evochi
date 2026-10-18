// Balancing configuration (style guide §15-18).
//
// All numbers are STARTING VALUES for playtesting. The app loads
// assets/config/balance_v1.json at startup; [GameConfig.defaults] mirrors that
// file so pure-Dart tests and a failed asset load still behave identically.

import 'dart:convert';

class Milestone {
  const Milestone(this.id, this.ratio, this.xp);
  final String id;
  final double ratio;
  final int xp;
}

class GoalPreset {
  const GoalPreset(this.id, this.label, this.steps, this.blurb);
  final String id;
  final String label;
  final int steps;
  final String blurb;
}

class EvolutionGate {
  const EvolutionGate(this.level, this.activeDays);
  final int level;
  final int activeDays;
}

class QuestDef {
  const QuestDef({
    required this.id,
    required this.period,
    required this.title,
    required this.desc,
    required this.coins,
    required this.icon,
    this.ratio,
    this.interaction = false,
    this.goalDays,
    this.chest = false,
    this.cosmeticChance = 0,
  });
  final String id;
  final String period; // 'day' | 'week'
  final String title;
  final String desc;
  final int coins;
  final String icon;
  final double? ratio;
  final bool interaction;
  final int? goalDays;
  final bool chest;
  final double cosmeticChance;
}

class GameConfig {
  const GameConfig({
    required this.version,
    required this.defaultGoal,
    required this.goalPresets,
    required this.goalMin,
    required this.goalMax,
    required this.xpBase,
    required this.milestones,
    required this.stretchMax,
    required this.stretchSpan,
    required this.levelA,
    required this.levelB,
    required this.levelC,
    required this.levelMax,
    required this.evolution,
    required this.activeDayRatio,
    required this.vitalityStart,
    required this.restoreHalf,
    required this.restoreFull,
    required this.lowRatio,
    required this.lowPenalty,
    required this.graceHours,
    required this.restDaysPerWindow,
    required this.restWindowDays,
    required this.bandHealthy,
    required this.bandNeutral,
    required this.bondMax,
    required this.bondFirstPet,
    required this.bondFirstPlay,
    required this.bondGoal,
    required this.bondDirectDailyCap,
    this.bondTreat = 1,
    required this.recoveryCooldownHours,
    required this.reviveVitality,
    required this.reviveHerbCost,
    required this.quests,
    required this.chestCoins,
    required this.chestItemChance,
    required this.chestItems,
    required this.starterItems,
    required this.starterPlacements,
    required this.manualAllowsChests,
    required this.nameMin,
    required this.nameMax,
  });

  final String version;
  final int defaultGoal;
  final List<GoalPreset> goalPresets;
  final int goalMin;
  final int goalMax;
  final int xpBase;
  final List<Milestone> milestones;
  final int stretchMax;
  final double stretchSpan;
  final int levelA;
  final int levelB;
  final int levelC;
  final int levelMax;
  final Map<int, EvolutionGate> evolution;
  final double activeDayRatio;
  final int vitalityStart;
  final int restoreHalf;
  final int restoreFull;
  final double lowRatio;
  final int lowPenalty;
  final int graceHours;
  final int restDaysPerWindow;
  final int restWindowDays;
  final int bandHealthy;
  final int bandNeutral;
  final int bondMax;
  final int bondFirstPet;
  final int bondFirstPlay;
  final int bondGoal;
  final int bondDirectDailyCap;
  final int bondTreat; // a homemade meal or tea, once a day (outside the pet/play cap)
  final int recoveryCooldownHours;
  final int reviveVitality;
  final int reviveHerbCost;
  final List<QuestDef> quests;
  final List<int> chestCoins;
  final double chestItemChance;
  final List<String> chestItems;
  final Map<String, int> starterItems;
  final Map<String, String> starterPlacements;
  final bool manualAllowsChests;
  final int nameMin;
  final int nameMax;

  int get dailyXpCap => xpBase + milestones.fold(0, (a, m) => a + m.xp) + stretchMax;

  static GameConfig current = defaults();

  static GameConfig defaults() => const GameConfig(
        version: '1.0.0',
        defaultGoal: 7000,
        goalPresets: [
          GoalPreset('beginner', 'Beginner', 5000, 'Gentle start'),
          GoalPreset('standard', 'Standard', 7000, 'Recommended'),
          GoalPreset('active', 'Active', 10000, 'For regular walkers'),
        ],
        goalMin: 1000,
        goalMax: 30000,
        xpBase: 100,
        milestones: [Milestone('m25', 0.25, 10), Milestone('m50', 0.5, 15), Milestone('m100', 1.0, 25)],
        stretchMax: 20,
        stretchSpan: 0.5,
        levelA: 120,
        levelB: 40,
        levelC: 4,
        levelMax: 99,
        evolution: {2: EvolutionGate(10, 7), 3: EvolutionGate(25, 21)},
        activeDayRatio: 0.5,
        vitalityStart: 100,
        restoreHalf: 8,
        restoreFull: 14,
        lowRatio: 0.25,
        lowPenalty: 8,
        graceHours: 48,
        restDaysPerWindow: 2,
        restWindowDays: 7,
        bandHealthy: 70,
        bandNeutral: 35,
        bondMax: 100,
        bondFirstPet: 2,
        bondFirstPlay: 3,
        bondGoal: 1,
        bondDirectDailyCap: 5,
        bondTreat: 1,
        recoveryCooldownHours: 12,
        reviveVitality: 40,
        reviveHerbCost: 3,
        quests: [
          QuestDef(id: 'first_steps', period: 'day', title: 'First Steps', desc: 'Reach 25% of your step goal', ratio: 0.25, coins: 15, icon: 'steps'),
          QuestDef(id: 'daily_walker', period: 'day', title: 'Daily Walker', desc: 'Reach 50% of your step goal', ratio: 0.5, coins: 25, icon: 'steps'),
          QuestDef(id: 'daily_goal', period: 'day', title: 'Daily Goal', desc: 'Reach 100% of your step goal', ratio: 1.0, coins: 40, chest: true, icon: 'chest'),
          QuestDef(id: 'bond_time', period: 'day', title: 'Bond Time', desc: 'Pet or play with your Evochi', interaction: true, coins: 5, icon: 'heart'),
          QuestDef(id: 'weekly_explorer', period: 'week', title: 'Weekly Explorer', desc: 'Meet your goal on 4 days this week', goalDays: 4, coins: 100, cosmeticChance: 0.35, icon: 'trophy'),
        ],
        chestCoins: [10, 15, 20, 30],
        chestItemChance: 0.4,
        chestItems: ['berry_snack', 'berry_snack', 'healing_herb', 'sunlit_flower'],
        starterItems: {'berry_snack': 2, 'nest_bed': 1},
        starterPlacements: {'nest': 'nest_bed'},
        manualAllowsChests: false,
        nameMin: 1,
        nameMax: 12,
      );

  /// Parse the versioned JSON exported from the shared balancing sheet.
  static GameConfig fromJson(Map<String, dynamic> j) {
    final d = defaults();
    T pick<T>(T Function() f, T fallback) {
      try {
        return f();
      } catch (_) {
        return fallback;
      }
    }

    Map<String, dynamic> m(String k) => (j[k] as Map).cast<String, dynamic>();
    return GameConfig(
      version: pick(() => j['version'] as String, d.version),
      defaultGoal: pick(() => (m('goal')['default'] as num).toInt(), d.defaultGoal),
      goalPresets: pick(
          () => (m('goal')['presets'] as List)
              .map((p) => GoalPreset(p['id'] as String, p['label'] as String, (p['steps'] as num).toInt(), p['blurb'] as String))
              .toList(),
          d.goalPresets),
      goalMin: pick(() => (m('goal')['min'] as num).toInt(), d.goalMin),
      goalMax: pick(() => (m('goal')['max'] as num).toInt(), d.goalMax),
      xpBase: pick(() => (m('xp')['base'] as num).toInt(), d.xpBase),
      milestones: pick(
          () => (m('xp')['milestones'] as List)
              .map((x) => Milestone(x['id'] as String, (x['ratio'] as num).toDouble(), (x['xp'] as num).toInt()))
              .toList(),
          d.milestones),
      stretchMax: pick(() => (m('xp')['stretchMax'] as num).toInt(), d.stretchMax),
      stretchSpan: pick(() => (m('xp')['stretchSpan'] as num).toDouble(), d.stretchSpan),
      levelA: pick(() => (m('level')['a'] as num).toInt(), d.levelA),
      levelB: pick(() => (m('level')['b'] as num).toInt(), d.levelB),
      levelC: pick(() => (m('level')['c'] as num).toInt(), d.levelC),
      levelMax: pick(() => (m('level')['max'] as num).toInt(), d.levelMax),
      evolution: pick(
          () => {
                for (final e in m('evolution').entries)
                  int.parse(e.key): EvolutionGate((e.value['level'] as num).toInt(), (e.value['activeDays'] as num).toInt()),
              },
          d.evolution),
      activeDayRatio: pick(() => (j['activeDayRatio'] as num).toDouble(), d.activeDayRatio),
      vitalityStart: pick(() => (m('vitality')['start'] as num).toInt(), d.vitalityStart),
      restoreHalf: pick(() => (m('vitality')['restoreHalf'] as num).toInt(), d.restoreHalf),
      restoreFull: pick(() => (m('vitality')['restoreFull'] as num).toInt(), d.restoreFull),
      lowRatio: pick(() => (m('vitality')['lowRatio'] as num).toDouble(), d.lowRatio),
      lowPenalty: pick(() => (m('vitality')['lowPenalty'] as num).toInt(), d.lowPenalty),
      graceHours: pick(() => (m('vitality')['graceHours'] as num).toInt(), d.graceHours),
      restDaysPerWindow: pick(() => (m('vitality')['restDaysPerWindow'] as num).toInt(), d.restDaysPerWindow),
      restWindowDays: pick(() => (m('vitality')['restWindowDays'] as num).toInt(), d.restWindowDays),
      bandHealthy: pick(() => (m('vitality')['bands']['healthy'] as num).toInt(), d.bandHealthy),
      bandNeutral: pick(() => (m('vitality')['bands']['neutral'] as num).toInt(), d.bandNeutral),
      bondMax: pick(() => (m('bond')['max'] as num).toInt(), d.bondMax),
      bondFirstPet: pick(() => (m('bond')['firstPet'] as num).toInt(), d.bondFirstPet),
      bondFirstPlay: pick(() => (m('bond')['firstPlay'] as num).toInt(), d.bondFirstPlay),
      bondGoal: pick(() => (m('bond')['goalCelebration'] as num).toInt(), d.bondGoal),
      bondDirectDailyCap: pick(() => (m('bond')['directDailyCap'] as num).toInt(), d.bondDirectDailyCap),
      bondTreat: pick(() => (m('bond')['treat'] as num).toInt(), d.bondTreat),
      recoveryCooldownHours: pick(() => (m('care')['recoveryCooldownHours'] as num).toInt(), d.recoveryCooldownHours),
      reviveVitality: pick(() => (m('care')['revive']['vitality'] as num).toInt(), d.reviveVitality),
      reviveHerbCost: pick(() => (m('care')['revive']['herbCost'] as num).toInt(), d.reviveHerbCost),
      quests: pick(
          () => (j['quests'] as List)
              .map((q) => QuestDef(
                    id: q['id'] as String,
                    period: q['period'] as String,
                    title: q['title'] as String,
                    desc: q['desc'] as String,
                    coins: (q['coins'] as num).toInt(),
                    icon: q['icon'] as String,
                    ratio: (q['ratio'] as num?)?.toDouble(),
                    interaction: q['interaction'] == true,
                    goalDays: (q['goalDays'] as num?)?.toInt(),
                    chest: q['chest'] == true,
                    cosmeticChance: ((q['cosmeticChance'] as num?) ?? 0).toDouble(),
                  ))
              .toList(),
          d.quests),
      chestCoins: pick(() => (m('chest')['coins'] as List).map((e) => (e as num).toInt()).toList(), d.chestCoins),
      chestItemChance: pick(() => (m('chest')['itemChance'] as num).toDouble(), d.chestItemChance),
      chestItems: pick(() => (m('chest')['items'] as List).cast<String>(), d.chestItems),
      starterItems: pick(
          () => {for (final it in (m('starter')['items'] as List)) it['itemId'] as String: (it['quantity'] as num).toInt()},
          d.starterItems),
      starterPlacements: pick(
          () => {for (final it in (m('starter')['placements'] as List)) it['slotId'] as String: it['itemId'] as String},
          d.starterPlacements),
      manualAllowsChests: pick(() => m('manualSteps')['allowChests'] == true, d.manualAllowsChests),
      nameMin: pick(() => (m('name')['min'] as num).toInt(), d.nameMin),
      nameMax: pick(() => (m('name')['max'] as num).toInt(), d.nameMax),
    );
  }

  static GameConfig parse(String text) => fromJson((jsonDecode(text) as Map).cast<String, dynamic>());
}

class PaletteInfo {
  const PaletteInfo(this.id, this.label, this.role);
  final String id;
  final String label;
  final String role;
}

const palettes = <PaletteInfo>[
  PaletteInfo('amber', 'Amber', 'Canonical'),
  PaletteInfo('forest', 'Forest', 'Nature'),
  PaletteInfo('coral', 'Coral', 'Warm'),
  PaletteInfo('ocean', 'Ocean', 'Cool'),
  PaletteInfo('amethyst', 'Amethyst', 'Mystery'),
  PaletteInfo('obsidian', 'Obsidian', 'High contrast'),
];

const stageLabels = {1: 'Eggling', 2: 'Juvenile', 3: 'Elder'};
