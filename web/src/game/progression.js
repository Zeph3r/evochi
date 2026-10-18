// Pure progression rules: XP, levels, evolution gates, vitality replay, bond.
import { CONFIG } from './config.js';
import { dayEnd, addDays, diffDays, HOUR } from './time.js';

// ---------------------------------------------------------------- XP ----
export function activityXp(steps, goal, cfg = CONFIG.xp) {
  const S = Math.max(0, steps | 0);
  const G = Math.max(1, goal | 0);
  const base = Math.floor((cfg.base * Math.min(S, G)) / G);
  let milestones = 0;
  const reached = [];
  for (const m of cfg.milestones) {
    if (S >= m.ratio * G) {
      milestones += m.xp;
      reached.push(m.id);
    }
  }
  const span = cfg.stretchSpan * G;
  const stretch = Math.floor((cfg.stretchMax * Math.min(Math.max(S - G, 0), span)) / span);
  return { base, milestones, stretch, total: base + milestones + stretch, reached };
}

export function dailyXpCap(cfg = CONFIG.xp) {
  return cfg.base + cfg.milestones.reduce((a, m) => a + m.xp, 0) + cfg.stretchMax;
}

const round10 = (x) => Math.round(x / 10) * 10;

export function xpToNext(level, cfg = CONFIG.level) {
  const n = level - 1;
  return round10(cfg.a + cfg.b * n + cfg.c * n * n);
}

/** Level derived from cumulative lifetime XP (never reset by daily steps). */
export function levelInfo(totalXp, cfg = CONFIG.level) {
  let level = 1;
  let rem = Math.max(0, totalXp | 0);
  while (level < cfg.max) {
    const need = xpToNext(level, cfg);
    if (rem < need) return { level, into: rem, need };
    rem -= need;
    level++;
  }
  return { level, into: 0, need: 0 };
}

// -------------------------------------------------------- active days ----
export function isActiveDay(steps, goal) {
  return steps >= CONFIG.activeDayRatio * goal;
}

export function activeDayCount(days, goalFor, sinceKey) {
  let n = 0;
  for (const [k, d] of Object.entries(days)) {
    if (sinceKey && k < sinceKey) continue;
    if (isActiveDay(d.steps, goalFor(k))) n++;
  }
  return n;
}

// ---------------------------------------------------------- evolution ----
export function evolutionStatus(stage, level, activeDays) {
  if (stage >= 3) return { maxed: true, eligible: false };
  const req = CONFIG.evolution[stage + 1];
  const eligible = level >= req.level && activeDays >= req.activeDays;
  return {
    maxed: false,
    eligible,
    next: stage + 1,
    req,
    levelOk: level >= req.level,
    daysOk: activeDays >= req.activeDays,
    levelProgress: Math.min(1, level / req.level),
    daysProgress: Math.min(1, activeDays / req.activeDays),
  };
}

// ----------------------------------------------------------- vitality ----
export function vitalityState(v) {
  const b = CONFIG.vitality.bands;
  if (v <= 0) return 'dead';
  if (v >= b.healthy) return 'healthy';
  if (v >= b.neutral) return 'neutral';
  return 'sick';
}

/**
 * Deterministic vitality replay. Because vitality is derived (not incrementally
 * mutated), a late or corrected step sync re-runs the history and automatically
 * reverses an incorrect penalty (style guide §17: idempotent, reversible).
 *
 * @param {object} p
 *   createdAt  ms  pet creation
 *   createdDay day key of creation
 *   days       {dayKey: {steps}}  aggregated step totals
 *   goalFor    (dayKey) => goal
 *   events     [{t, type: 'care'|'revive'|'reset', amount}]
 *   syncedUntil ms: latest instant covered by a successful sync (missing data is never "inactive")
 *   now        ms
 *   tz         account time zone
 */
export function replayVitality(p) {
  const V = CONFIG.vitality;
  const timeline = [];
  const today = p.todayKey;
  // closed days from creation day up to yesterday
  let k = p.createdDay;
  let guard = 0;
  while (k < today && guard++ < 3650) {
    const end = dayEnd(k, p.tz);
    const d = p.days[k];
    const goal = p.goalFor(k);
    const steps = d ? d.steps : 0;
    const ratio = steps / goal;
    const covered = (p.syncedUntil ?? 0) >= end;
    timeline.push({ t: end, type: 'day', key: k, ratio, covered, steps });
    k = addDays(k, 1);
  }
  for (const e of p.events || []) timeline.push(e);
  timeline.sort((a, b) => a.t - b.t || (a.type === 'day' ? -1 : 1));

  let v = V.start;
  let dead = false;
  let diedAt = null;
  const restDays = []; // keys protected as rest days
  const log = [];
  for (const ev of timeline) {
    if (ev.type === 'day') {
      if (dead) {
        log.push({ key: ev.key, kind: 'dead' });
        continue;
      }
      let delta = 0;
      let kind;
      if (!ev.covered && ev.steps === 0) {
        kind = 'pending'; // data unavailable: not inactive
      } else if (ev.ratio >= 1) {
        delta = V.restoreFull;
        kind = 'goal';
      } else if (ev.ratio >= CONFIG.activeDayRatio) {
        delta = V.restoreHalf;
        kind = 'active';
      } else if (ev.ratio >= V.lowRatio) {
        kind = 'light';
      } else {
        // low activity day: rest protection first, then grace window
        const recent = restDays.filter((r) => diffDays(r, ev.key) > 0 && diffDays(r, ev.key) < V.restWindowDays);
        if (recent.length < V.restDaysPerWindow) {
          restDays.push(ev.key);
          kind = 'rest';
        } else if (p.now < ev.t + V.graceHours * HOUR) {
          kind = 'grace';
        } else {
          delta = -V.lowPenalty;
          kind = 'low';
        }
      }
      v = Math.max(0, Math.min(100, v + delta));
      log.push({ key: ev.key, kind, delta, v });
      if (v <= 0) {
        dead = true;
        diedAt = ev.t;
      }
    } else if (ev.type === 'care') {
      if (dead) continue;
      v = Math.max(0, Math.min(100, v + ev.amount));
    } else if (ev.type === 'revive') {
      if (!dead) continue;
      dead = false;
      v = Math.max(1, Math.min(100, ev.amount));
      log.push({ kind: 'revive', v, t: ev.t });
    }
  }
  return { vitality: dead ? 0 : v, dead, diedAt, restDays, log, state: dead ? 'dead' : vitalityState(v) };
}

// ---------------------------------------------------------------- bond ----
/** bond events: [{key, type: 'pet'|'play'|'goal'}] unique per (key,type) */
export function bondValue(events) {
  const B = CONFIG.bond;
  const perDay = new Map();
  let total = 0;
  const seen = new Set();
  for (const e of events) {
    const id = e.key + ':' + e.type;
    if (seen.has(id)) continue;
    seen.add(id);
    let amt = e.type === 'pet' ? B.firstPet : e.type === 'play' ? B.firstPlay : e.type === 'goal' ? B.goalCelebration
      : e.type === 'treat' ? (B.treat || 0) : 0;
    if (e.type === 'pet' || e.type === 'play') {
      const used = perDay.get(e.key) || 0;
      amt = Math.max(0, Math.min(amt, B.directDailyCap - used));
      perDay.set(e.key, used + amt);
    }
    total += amt;
  }
  return Math.min(B.max, total);
}

export function bondHearts(bond, hearts = 5) {
  return Math.max(0, Math.min(hearts, Math.round((bond / 100) * hearts)));
}
