// Step data adapters for the web build.
// On phones the Flutter client reads HealthKit / Health Connect. The browser has no
// step API, so the web build offers a simulated device (treated as a verified source
// for playtesting) and manual entry (a lower-trust, clearly flagged fallback).

import { dayStart, dayKey, HOUR } from './time.js';
import { uid } from './state.js';

const MIN = 60000;

/**
 * Simulate a walk of `steps` ending at `now`, as 2-minute samples from the "phone".
 * With `watch` true, a second wearable reports the same walk (slightly different
 * counts) to exercise cross-source de-duplication.
 */
export function simulateWalk(steps, now, { watch = true, minutes = null, notBefore = 0 } = {}) {
  const out = [];
  let dur = minutes ?? Math.max(4, Math.round(steps / 110));
  // never start before `notBefore`: compress the walk into the time since then
  if (notBefore && now - dur * MIN < notBefore) dur = Math.max((now - notBefore) / MIN, 0);
  const n = Math.max(1, Math.round(dur / 2));
  const start = now - dur * MIN;
  let left = steps;
  for (let i = 0; i < n; i++) {
    const s = start + (i * dur * MIN) / n;
    const e = start + ((i + 1) * dur * MIN) / n;
    const c = i === n - 1 ? left : Math.round(steps / n);
    left -= c;
    out.push({ id: uid('ph'), source: 'demo-phone', start: Math.round(s), end: Math.round(e), count: c });
    if (watch) {
      out.push({ id: uid('wt'), source: 'demo-watch', start: Math.round(s), end: Math.round(e), count: Math.round(c * (0.96 + Math.random() * 0.03)) });
    }
  }
  return out;
}

/** Samples for a whole past day (used by the playtest "backfill" tool). */
export function simulateDay(key, steps, tz) {
  const start = dayStart(key, tz) + 9 * HOUR;
  const out = [];
  const chunks = 8;
  for (let i = 0; i < chunks; i++) {
    const s = start + i * HOUR;
    out.push({ id: `bf_${key}_${i}_${steps}`, source: 'demo-phone', start: s, end: s + 30 * MIN, count: Math.round(steps / chunks) });
  }
  return out;
}

export function manualEntry(steps, now) {
  return [{ id: uid('man'), source: 'manual', start: now - MIN, end: now, count: Math.max(0, Math.round(steps)), manual: true }];
}

export { dayKey };
