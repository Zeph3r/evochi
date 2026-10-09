// Step observations -> authoritative daily totals (style guide §15, §21 "Health synchronization").
// The fitness provider is a source of time-stamped observations, not a reward ledger.
//  - samples are de-duplicated by id (re-delivery never double counts)
//  - samples are bucketed into 15-minute intervals per source; for each interval the
//    maximum across sources is used, so a phone + watch walking together count once
//  - manual entries are a lower-trust fallback: day total = max(verified, manual)

import { dayKey } from './time.js';

const BUCKET = 15 * 60 * 1000;

export function normalizeSample(s) {
  if (!s || typeof s !== 'object') throw new Error('bad sample');
  const count = Math.max(0, Math.round(Number(s.count) || 0));
  const start = Number(s.start);
  const end = Number(s.end ?? s.start);
  if (!Number.isFinite(start) || !Number.isFinite(end) || end < start) throw new Error('bad sample time');
  if (!s.id) throw new Error('sample needs id');
  return { id: String(s.id), source: String(s.source || 'unknown'), start, end, count, manual: !!s.manual };
}

/** Merge new samples into the stored list, ignoring ids already present. Returns {list, added}. */
export function mergeSamples(existing, incoming) {
  const seen = new Set(existing.map((s) => s.id));
  const list = existing.slice();
  let added = 0;
  for (const raw of incoming) {
    const s = normalizeSample(raw);
    if (seen.has(s.id)) continue;
    seen.add(s.id);
    list.push(s);
    added++;
  }
  return { list, added };
}

/** Split a sample's count across 15-minute buckets proportionally to overlap. */
function spread(s) {
  const out = [];
  if (s.end <= s.start) {
    out.push([Math.floor(s.start / BUCKET) * BUCKET, s.count]);
    return out;
  }
  const dur = s.end - s.start;
  let t = s.start;
  let assigned = 0;
  while (t < s.end) {
    const b = Math.floor(t / BUCKET) * BUCKET;
    const next = Math.min(b + BUCKET, s.end);
    const share = Math.round((s.count * (next - s.start)) / dur) - assigned;
    assigned += share;
    out.push([b, share]);
    t = next;
  }
  return out;
}

export function aggregateDays(samples, tz) {
  // verified: day -> bucket -> source -> count
  const ver = new Map();
  const man = new Map();
  for (const s of samples) {
    if (s.manual) {
      const k = dayKey(s.start, tz);
      man.set(k, (man.get(k) || 0) + s.count);
      continue;
    }
    for (const [b, c] of spread(s)) {
      const k = dayKey(b, tz);
      if (!ver.has(k)) ver.set(k, new Map());
      const bm = ver.get(k);
      if (!bm.has(b)) bm.set(b, new Map());
      const src = bm.get(b);
      src.set(s.source, (src.get(s.source) || 0) + c);
    }
  }
  const days = {};
  const keys = new Set([...ver.keys(), ...man.keys()]);
  for (const k of keys) {
    let v = 0;
    const bm = ver.get(k);
    if (bm) for (const src of bm.values()) v += Math.max(...src.values());
    const m = man.get(k) || 0;
    const steps = Math.max(v, m);
    days[k] = { verified: v, manual: m, steps, unverified: steps > v };
  }
  return days;
}
