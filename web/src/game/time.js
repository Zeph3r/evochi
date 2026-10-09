// Day attribution in the account time zone (style guide §14, §15, QA Q11).
// A day key is "YYYY-MM-DD" in the player's saved IANA zone, never the device's
// current zone, so travel cannot double-count a day.

const fmtCache = new Map();

function formatter(tz) {
  let f = fmtCache.get(tz);
  if (!f) {
    f = new Intl.DateTimeFormat('en-CA', {
      timeZone: tz, year: 'numeric', month: '2-digit', day: '2-digit',
      hour: '2-digit', minute: '2-digit', second: '2-digit', hourCycle: 'h23',
    });
    fmtCache.set(tz, f);
  }
  return f;
}

function parts(ms, tz) {
  const out = {};
  for (const p of formatter(tz).formatToParts(new Date(ms))) out[p.type] = p.value;
  return out;
}

export function dayKey(ms, tz) {
  const p = parts(ms, tz);
  return `${p.year}-${p.month}-${p.day}`;
}

/** Offset (ms) of tz relative to UTC at instant ms: local = utc + offset */
export function tzOffset(ms, tz) {
  const p = parts(ms, tz);
  const asUTC = Date.UTC(+p.year, +p.month - 1, +p.day, +p.hour, +p.minute, +p.second);
  return asUTC - Math.floor(ms / 1000) * 1000;
}

/** UTC instant (ms) of local midnight that starts the given day key in tz. */
export function dayStart(key, tz) {
  const [y, m, d] = key.split('-').map(Number);
  const guess = Date.UTC(y, m - 1, d, 0, 0, 0);
  let t = guess - tzOffset(guess, tz);
  // refine across DST transitions
  t = guess - tzOffset(t, tz);
  return t;
}

export function dayEnd(key, tz) {
  return dayStart(addDays(key, 1), tz);
}

export function addDays(key, n) {
  const [y, m, d] = key.split('-').map(Number);
  const t = Date.UTC(y, m - 1, d + n);
  const dt = new Date(t);
  return dt.toISOString().slice(0, 10);
}

export function diffDays(a, b) {
  // b - a in whole days (keys)
  const [y1, m1, d1] = a.split('-').map(Number);
  const [y2, m2, d2] = b.split('-').map(Number);
  return Math.round((Date.UTC(y2, m2 - 1, d2) - Date.UTC(y1, m1 - 1, d1)) / 86400000);
}

/** ISO week key (Monday start) for a day key, e.g. "2026-W41". */
export function weekKey(key) {
  const [y, m, d] = key.split('-').map(Number);
  const dt = new Date(Date.UTC(y, m - 1, d));
  const dow = (dt.getUTCDay() + 6) % 7; // Mon=0
  dt.setUTCDate(dt.getUTCDate() - dow + 3); // Thursday of this week
  const wy = dt.getUTCFullYear();
  const jan4 = new Date(Date.UTC(wy, 0, 4));
  const week = 1 + Math.round(((dt - jan4) / 86400000 - 3 + ((jan4.getUTCDay() + 6) % 7)) / 7);
  return `${wy}-W${String(week).padStart(2, '0')}`;
}

export function weekDays(key) {
  const [y, m, d] = key.split('-').map(Number);
  const dt = new Date(Date.UTC(y, m - 1, d));
  const dow = (dt.getUTCDay() + 6) % 7;
  const monday = addDays(key, -dow);
  return Array.from({ length: 7 }, (_, i) => addDays(monday, i));
}

export function deviceZone() {
  try {
    return Intl.DateTimeFormat().resolvedOptions().timeZone || 'UTC';
  } catch {
    return 'UTC';
  }
}

export const HOUR = 3600000;
export const DAY = 86400000;
