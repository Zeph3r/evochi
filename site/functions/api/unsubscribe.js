// GET  /api/unsubscribe?code=XXXX  -> removes that sign-up and shows a small confirmation page
// POST /api/unsubscribe?code=XXXX  -> same, for Gmail/Yahoo one-click unsubscribe (List-Unsubscribe-Post)
import { settings } from './_lib.js';

const page = (siteUrl, title, body) => new Response(`<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>${title}</title>
<style>body{margin:0;background:#F4E2CD;font:17px/1.6 Lato,'Helvetica Neue',Arial,sans-serif;color:#684C3C}main{max-width:520px;margin:48px auto;padding:36px 32px;background:#FFF9F0;border:3px solid #C9A78C;border-radius:28px;text-align:center}h1{margin:0 0 10px;font:900 30px/1.15 Nunito,'Trebuchet MS',Arial,sans-serif;color:#3B2923}a.btn{display:inline-block;margin-top:18px;padding:13px 26px;border-radius:16px;background:#F4B84E;border:3px solid #C8832C;color:#3B2923;font:900 17px Nunito,Arial,sans-serif;text-decoration:none}img{width:180px;height:auto;margin-bottom:10px}</style></head>
<body><main><img src="${siteUrl}/assets/email/egg-ocean.png" alt=""><h1>${title}</h1><p>${body}</p><a class="btn" href="${siteUrl}/">Back to evochigame.com</a></main></body></html>`,
  { headers: { 'content-type': 'text/html; charset=utf-8', 'cache-control': 'no-store' } });

async function handle({ request, env }) {
  const { siteUrl } = settings(env);
  const code = new URL(request.url).searchParams.get('code') || '';
  if (!/^[a-z0-9]{6,12}$/.test(code) || !env.DB) return page(siteUrl, 'That link has expired.', 'If you still want off the list, reply to any Evochi email and we\'ll remove you by hand.');
  await env.DB.prepare('DELETE FROM signups WHERE code = ?1').bind(code).run();
  return page(siteUrl, "You're off the list.", 'No more emails from us. If you change your mind, the waitlist is always open, and Mochi holds no grudges.');
}

export const onRequestGet = handle;
export const onRequestPost = handle;
