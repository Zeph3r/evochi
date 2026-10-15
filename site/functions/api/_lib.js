// Shared helpers for the waitlist API (Cloudflare Pages Functions + D1).
import { renderEmail } from './_emails.js';

export const json = (data, status = 200, extra = {}) =>
  new Response(JSON.stringify(data), { status, headers: { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store', ...extra } });

export const COLOURS = ['amber', 'forest', 'coral', 'ocean', 'amethyst', 'obsidian'];

export function settings(env) {
  return {
    goal: Number(env.WAITLIST_GOAL) || 5000,
    spots: Number(env.FOUNDER_SPOTS) || 1000,
    siteUrl: (env.SITE_URL || 'https://evochigame.com').replace(/\/+$/, ''),
  };
}

export function normaliseEmail(raw) {
  const e = String(raw || '').trim().toLowerCase();
  if (e.length > 254 || !/^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(e)) return null;
  return e;
}

export async function sha256(text) {
  const buf = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(text));
  return [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

// short, unambiguous referral codes: 8 chars from a 32-symbol alphabet (no 0/O, 1/I)
export function makeCode() {
  const alphabet = 'abcdefghjkmnpqrstuvwxyz23456789';
  const bytes = crypto.getRandomValues(new Uint8Array(8));
  return [...bytes].map((b) => alphabet[b % alphabet.length]).join('');
}

/** Public counts: total sign-ups and Founder's Crowns still unclaimed. */
export async function counts(env) {
  const { goal, spots } = settings(env);
  const row = await env.DB.prepare('SELECT COUNT(*) AS n, SUM(founder) AS f FROM signups').first();
  const count = Number(row?.n || 0);
  const founders = Number(row?.f || 0);
  return { count, goal, founders_left: Math.max(0, spots - founders) };
}

/** Place in line: by referrals (more first), then by sign-up time. */
export async function positionOf(env, row) {
  const r = await env.DB.prepare(
    'SELECT COUNT(*) AS n FROM signups WHERE referrals > ?1 OR (referrals = ?1 AND created_at < ?2)',
  ).bind(row.referrals, row.created_at).first();
  return Number(r?.n || 0) + 1;
}

export async function describe(env, row) {
  const c = await counts(env);
  return {
    position: await positionOf(env, row),
    code: row.code,
    colour: row.colour,
    founder: !!row.founder,
    referrals: row.referrals,
    count: c.count,
    goal: c.goal,
    founders_left: c.founders_left,
  };
}

/** Cloudflare Turnstile check; passes when no secret is configured. */
export async function verifyTurnstile(env, token, ip) {
  if (!env.TURNSTILE_SECRET) return true;
  if (!token) return false;
  const body = new FormData();
  body.append('secret', env.TURNSTILE_SECRET);
  body.append('response', token);
  if (ip) body.append('remoteip', ip);
  try {
    const r = await fetch('https://challenges.cloudflare.com/turnstile/v0/siteverify', { method: 'POST', body });
    const j = await r.json();
    return !!j.success;
  } catch {
    return false;
  }
}

/** Shared bits for the transactional emails (Resend). Set RESEND_API_KEY and FROM_EMAIL to turn them on. */

function emailData(env, me) {
  const { siteUrl, goal } = settings(env);
  return {
    siteUrl,
    assetBase: `${siteUrl}/assets/email`,
    signoff: env.EMAIL_SIGNOFF || 'Mochi & the Evochi team',
    companyLine: env.COMPANY_LINE || '',
    goal,
    position: me.position, colour: me.colour, founder: me.founder, code: me.code, referrals: me.referrals, count: me.count,
  };
}

async function sendEmail(env, to, { subject, html, text }, unsubLink) {
  if (!env.RESEND_API_KEY || !env.FROM_EMAIL) return;
  const headers = unsubLink ? { 'List-Unsubscribe': `<${unsubLink}>`, 'List-Unsubscribe-Post': 'List-Unsubscribe=One-Click' } : undefined;
  try {
    await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: { authorization: `Bearer ${env.RESEND_API_KEY}`, 'content-type': 'application/json' },
      body: JSON.stringify({ from: env.FROM_EMAIL, to: [to], reply_to: env.REPLY_TO || undefined, subject, html, text, headers }),
    });
  } catch {
    /* email is a courtesy; the sign-up already succeeded */
  }
}

/** Welcome email with their place, egg, referral link and the hatch meter. Never blocks the sign-up. */
export async function sendWelcome(env, email, me) {
  if (!env.RESEND_API_KEY || !env.FROM_EMAIL) return;
  const data = emailData(env, me);
  await sendEmail(env, email, renderEmail('waitlist-welcome', data), `${data.siteUrl}/api/unsubscribe?code=${me.code}`);
}

/** "Someone hatched with your link": to the referrer, with their new place in line. */
export async function sendReferral(env, email, me) {
  if (!env.RESEND_API_KEY || !env.FROM_EMAIL) return;
  const data = emailData(env, me);
  await sendEmail(env, email, renderEmail('referral-moved-up', data), `${data.siteUrl}/api/unsubscribe?code=${me.code}`);
}
