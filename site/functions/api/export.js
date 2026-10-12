// GET /api/export  (header: Authorization: Bearer ADMIN_KEY)  -> CSV of the list in invite order
// GET /api/export?format=json for the same as JSON.
import { json, positionOf } from './_lib.js';

export async function onRequestGet({ request, env }) {
  if (!env.DB) return json({ error: 'Waitlist database not configured' }, 503);
  const auth = request.headers.get('authorization') || '';
  const key = auth.replace(/^Bearer\s+/i, '');
  if (!env.ADMIN_KEY || key !== env.ADMIN_KEY) return json({ error: 'Unauthorized' }, 401);
  const url = new URL(request.url);
  const { results } = await env.DB.prepare('SELECT email, colour, code, ref_code, referrals, founder, created_at FROM signups ORDER BY referrals DESC, created_at ASC').all();
  const rows = results.map((r, i) => ({ position: i + 1, ...r, created_at: new Date(r.created_at).toISOString() }));
  if (url.searchParams.get('format') === 'json') return json(rows);
  const head = 'position,email,colour,code,ref_code,referrals,founder,created_at';
  const esc = (v) => (v == null ? '' : /[",\n]/.test(String(v)) ? '"' + String(v).replace(/"/g, '""') + '"' : String(v));
  const csv = [head, ...rows.map((r) => [r.position, r.email, r.colour, r.code, r.ref_code, r.referrals, r.founder, r.created_at].map(esc).join(','))].join('\n') + '\n';
  return new Response(csv, { headers: { 'content-type': 'text/csv; charset=utf-8', 'content-disposition': 'attachment; filename="evochi-waitlist.csv"', 'cache-control': 'no-store' } });
}

// DELETE /api/export?email=... (same header) removes one person, for deletion requests.
export async function onRequestDelete({ request, env }) {
  if (!env.DB) return json({ error: 'Waitlist database not configured' }, 503);
  const key = (request.headers.get('authorization') || '').replace(/^Bearer\s+/i, '');
  if (!env.ADMIN_KEY || key !== env.ADMIN_KEY) return json({ error: 'Unauthorized' }, 401);
  const email = (new URL(request.url).searchParams.get('email') || '').trim().toLowerCase();
  const r = await env.DB.prepare('DELETE FROM signups WHERE email = ?1').bind(email).run();
  return json({ deleted: r.meta?.changes || 0 });
}
