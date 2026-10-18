// Evochi balancing configuration.
// All numbers in this file are STARTING VALUES for playtesting (style guide §15-18).
// Load from versioned configuration; never hard-code these in widgets.

export const CONFIG = {
  version: '1.0.0',

  goal: {
    default: 7000,
    presets: [
      { id: 'beginner', label: 'Beginner', steps: 5000, blurb: 'Gentle start' },
      { id: 'standard', label: 'Standard', steps: 7000, blurb: 'Recommended' },
      { id: 'active', label: 'Active', steps: 10000, blurb: 'For regular walkers' },
    ],
    min: 1000,
    max: 30000,
  },

  xp: {
    base: 100, // floor(base * min(S,G)/G)
    milestones: [
      { id: 'm25', ratio: 0.25, xp: 10 },
      { id: 'm50', ratio: 0.5, xp: 15 },
      { id: 'm100', ratio: 1.0, xp: 25 },
    ],
    stretchMax: 20, // floor(20 * min(max(S-G,0), 0.5G) / 0.5G)
    stretchSpan: 0.5,
  },

  // XP needed to go from level L to L+1: roundToNearest10(a + b*(L-1) + c*(L-1)^2)
  level: { a: 120, b: 40, c: 4, max: 99 },

  evolution: {
    // target stage -> requirement
    2: { level: 10, activeDays: 7 },
    3: { level: 25, activeDays: 21 },
  },
  activeDayRatio: 0.5,

  vitality: {
    start: 100,
    restoreHalf: 8, // day >= 50% of goal
    restoreFull: 14, // day >= 100% of goal (instead of restoreHalf)
    lowRatio: 0.25, // below this is a low-activity day
    lowPenalty: 8,
    graceHours: 48, // penalties apply only after this delay (late syncs can still arrive)
    restDaysPerWindow: 2, // protected low days per rolling 7-day window
    restWindowDays: 7,
    bands: { healthy: 70, neutral: 35, sick: 1 },
  },

  bond: {
    max: 100,
    firstPet: 2,
    firstPlay: 3,
    goalCelebration: 1,
    directDailyCap: 5,
    treat: 1, // a homemade meal or tea, once a day (outside the pet/play cap)
  },

  care: {
    recoveryCooldownHours: 12,
    revive: { vitality: 40, herbCost: 3 },
  },

  quests: [
    { id: 'first_steps', period: 'day', title: 'First Steps', desc: 'Reach 25% of your step goal', ratio: 0.25, coins: 15, icon: 'steps' },
    { id: 'daily_walker', period: 'day', title: 'Daily Walker', desc: 'Reach 50% of your step goal', ratio: 0.5, coins: 25, icon: 'steps' },
    { id: 'daily_goal', period: 'day', title: 'Daily Goal', desc: 'Reach 100% of your step goal', ratio: 1.0, coins: 40, chest: true, icon: 'chest' },
    { id: 'bond_time', period: 'day', title: 'Bond Time', desc: 'Pet or play with your Evochi', interaction: true, coins: 5, icon: 'heart' },
    { id: 'weekly_explorer', period: 'week', title: 'Weekly Explorer', desc: 'Meet your goal on 4 days this week', goalDays: 4, coins: 100, cosmeticChance: 0.35, icon: 'trophy' },
  ],

  chest: {
    // deterministic per day; verified activity only
    coins: [10, 15, 20, 30],
    itemChance: 0.4,
    items: ['berry_snack', 'berry_snack', 'healing_herb', 'sunlit_flower'],
  },

  starter: {
    coins: 0,
    items: [
      { itemId: 'berry_snack', quantity: 2 },
      { itemId: 'nest_bed', quantity: 1 },
    ],
    placements: [{ slotId: 'nest', itemId: 'nest_bed' }],
  },

  manualSteps: {
    // manual entries award XP and vitality, but never chests or cosmetic chances
    allowChests: false,
  },

  name: { min: 1, max: 12 },
};

export const STAGES = [
  { stage: 1, id: 'eggling', label: 'Eggling' },
  { stage: 2, id: 'juvenile', label: 'Juvenile' },
  { stage: 3, id: 'elder', label: 'Elder' },
];

export const PALETTES = [
  { id: 'amber', label: 'Amber', role: 'Canonical', shell: '#FFF0DE', pattern: '#F9CA70', crest: '#F4B84E' },
  { id: 'forest', label: 'Forest', role: 'Nature', shell: '#F1F4E5', pattern: '#A5CD82', crest: '#78B55B' },
  { id: 'coral', label: 'Coral', role: 'Warm', shell: '#FFF0E8', pattern: '#F3A78D', crest: '#DB745B' },
  { id: 'ocean', label: 'Ocean', role: 'Cool', shell: '#F0F7FB', pattern: '#97CDEB', crest: '#4C9BCC' },
  { id: 'amethyst', label: 'Amethyst', role: 'Mystery', shell: '#F6EEFB', pattern: '#C8B1E4', crest: '#9975C9' },
  { id: 'obsidian', label: 'Obsidian', role: 'High contrast', shell: '#3E414B', pattern: '#6B6473', crest: '#DD6A5B' },
];

export const HABITATS = [
  { id: 'sunlit_meadow', label: 'Sunlit Meadow', available: true },
  { id: 'whispering_forest', label: 'Whispering Forest', available: false },
  { id: 'skyline_cliffs', label: 'Skyline Cliffs', available: false },
];
