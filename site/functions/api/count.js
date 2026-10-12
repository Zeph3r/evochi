// GET /api/count -> { count, goal, founders_left }
import { json, counts } from './_lib.js';

export async function onRequestGet({ env }) {
  if (!env.DB) return json({ error: 'Waitlist database not configured' }, 503);
  const c = await counts(env);
  // cache at the edge for 15 s so a traffic spike never hits D1 more than a few times a minute
  return json(c, 200, { 'cache-control': 'public, max-age=15, s-maxage=15' });
}
