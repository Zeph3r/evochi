// GET /api/me?code=XXXX -> the sign-up's current place (no email needed; the code is the key they were given)
import { json, describe } from './_lib.js';

export async function onRequestGet({ request, env }) {
  if (!env.DB) return json({ error: 'Waitlist database not configured' }, 503);
  const code = new URL(request.url).searchParams.get('code') || '';
  if (!/^[a-z0-9]{6,12}$/.test(code)) return json({ error: 'Unknown code' }, 404);
  const row = await env.DB.prepare('SELECT * FROM signups WHERE code = ?1').bind(code).first();
  if (!row) return json({ error: 'Unknown code' }, 404);
  return json(await describe(env, row));
}
