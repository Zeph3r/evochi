// POST /api/waitlist { email, colour, ref, token } -> { position, code, colour, founder, referrals, count, goal, founders_left }
// 409 with the same body when the email is already on the list, so the page can show their place.
import { json, COLOURS, settings, normaliseEmail, sha256, makeCode, describe, verifyTurnstile, sendWelcome, sendReferral } from './_lib.js';

export async function onRequestPost({ request, env, waitUntil }) {
  if (!env.DB) return json({ error: "Sign-ups aren't live yet. Please try again later." }, 503);
  let body;
  try {
    body = await request.json();
  } catch {
    return json({ error: 'Bad request' }, 400);
  }
  const email = normaliseEmail(body.email);
  if (!email) return json({ error: "That email address doesn't look right." }, 400);
  const colour = COLOURS.includes(body.colour) ? body.colour : 'ocean';
  const ref = typeof body.ref === 'string' && /^[a-z0-9]{6,12}$/.test(body.ref) ? body.ref : null;

  const ip = request.headers.get('cf-connecting-ip') || '';
  if (!(await verifyTurnstile(env, body.token, ip))) return json({ error: 'Please complete the check and try again.' }, 400);

  const ipHash = (await sha256(ip + '|' + (env.ADMIN_KEY || 'evochi'))).slice(0, 32);
  const now = Date.now();

  // 20 sign-ups per address per hour is plenty for a family on one connection
  const recent = await env.DB.prepare('SELECT COUNT(*) AS n FROM signups WHERE ip_hash = ?1 AND created_at > ?2').bind(ipHash, now - 3600_000).first();
  if (Number(recent?.n || 0) >= 20) return json({ error: 'Too many sign-ups from this connection. Try again in an hour.' }, 429);

  const existing = await env.DB.prepare('SELECT * FROM signups WHERE email = ?1').bind(email).first();
  if (existing) return json(await describe(env, existing), 409);

  const { spots } = settings(env);
  let referrer = null;
  if (ref) referrer = await env.DB.prepare('SELECT code FROM signups WHERE code = ?1').bind(ref).first();

  // Founder's Crown goes to the first N who signed up, by time, regardless of later referrals
  const before = await env.DB.prepare('SELECT COUNT(*) AS n FROM signups').first();
  const founder = Number(before?.n || 0) < spots ? 1 : 0;

  // a referred sign-up starts one place ahead of a plain one ("you both move up")
  const referrals = referrer ? 1 : 0;
  let code = makeCode();
  for (let attempt = 0; attempt < 5; attempt++) {
    try {
      await env.DB.prepare(
        'INSERT INTO signups (email, colour, code, ref_code, referrals, founder, created_at, ip_hash) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)',
      ).bind(email, colour, code, referrer ? referrer.code : null, referrals, founder, now, ipHash).run();
      break;
    } catch (e) {
      const msg = String(e && e.message);
      if (msg.includes('signups.email')) {
        const row = await env.DB.prepare('SELECT * FROM signups WHERE email = ?1').bind(email).first();
        return json(await describe(env, row), 409);
      }
      if (msg.includes('signups.code') && attempt < 4) { code = makeCode(); continue; }
      return json({ error: 'Something went wrong saving your spot. Please try again.' }, 500);
    }
  }
  if (referrer) {
    await env.DB.prepare('UPDATE signups SET referrals = referrals + 1 WHERE code = ?1').bind(referrer.code).run();
    const them = await env.DB.prepare('SELECT * FROM signups WHERE code = ?1').bind(referrer.code).first();
    if (them) waitUntil(describe(env, them).then((d) => sendReferral(env, them.email, d)));
  }

  const row = await env.DB.prepare('SELECT * FROM signups WHERE email = ?1').bind(email).first();
  const me = await describe(env, row);
  waitUntil(sendWelcome(env, email, me));
  return json(me, 200);
}
