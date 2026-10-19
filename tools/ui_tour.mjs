// Screenshots every screen of the web build with a seeded mid-game save (Mochi the Ocean Juvenile, the
// village chapter done, the home restored, a stocked Bag), for UI reviews and before/after sheets.
//   [PORT=8765] node ui_tour.mjs OUT_DIR [width=390] [only=comma,separated,names]      (web/dist served on :PORT)
// Writes NN_name.png at DPR 2 and prints any page errors or failed requests.
import chromium from '@sparticuz/chromium';
import puppeteer from 'puppeteer-core';
import fs from 'node:fs';

const OUT = process.argv[2];
const W = Number(process.argv[3] || 390);
const ONLY = process.argv[4] ? process.argv[4].split(',') : null;
fs.mkdirSync(OUT, { recursive: true });
const b = await puppeteer.launch({ executablePath: await chromium.executablePath(), args: chromium.args, headless: true });
const errors = [];
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const p = await b.newPage();
await p.setViewport({ width: W, height: 844, deviceScaleFactor: 2 });
p.on('pageerror', (e) => errors.push('pageerror: ' + e.message));
p.on('console', (m) => { if (m.type() === 'error') errors.push(m.text().slice(0, 200)); });
p.on('response', (r) => { if (r.status() >= 400) errors.push(`${r.status()} ${r.url()}`); });
await p.goto(`http://127.0.0.1:${process.env.PORT || 8765}/preview.html`, { waitUntil: 'networkidle0' });
await p.evaluate(() => localStorage.clear());
await p.reload({ waitUntil: 'networkidle0' });
await p.waitForFunction(() => window.__evochi);
await p.addStyleTag({ content: '.toasts { display: none !important; }' });

let n = 0;
const shot = async (name, wait = 900) => {
  n++;
  if (ONLY && !ONLY.includes(name)) return;
  await sleep(wait);
  await p.evaluate(() => document.querySelectorAll('img[loading="lazy"]').forEach((i) => { i.loading = 'eager'; }));
  await sleep(150);
  await p.screenshot({ path: `${OUT}/${String(n).padStart(2, '0')}_${name}.png` });
};
const run = (fn, arg) => p.evaluate(fn, arg);
const click = (k) => p.evaluate((k) => { const el = document.querySelector(`[data-k="${k}"]`); if (el) el.click(); return !!el; }, k);
const scroll = (y) => p.evaluate((y) => { const s = document.querySelector('.screen.scroll, .fill-scroll, .home-stack'); if (s) s.scrollTop = y; }, y);
const go = (id, params = {}) => run(([id, params]) => { const { app } = window.__evochi; app.closeAllModals?.(); app.go(id, params); }, [id, params]);
const tab = (id, ui) => run(([id, ui]) => { const { app } = window.__evochi; app.closeAllModals?.(); if (ui) app.ui[id] = ui; app.tab(id); }, [id, ui]);

// the save
await run(() => {
  const { app, store, G } = window.__evochi;
  const T0 = store.now();
  store.run((s) => G.startGuest(s, T0, 'America/New_York'));
  store.run((s) => G.createPet(s, { name: 'Mochi', paletteId: 'ocean', requestId: 'tour' }, T0));
  store.run((s) => G.setConnection(s, 'demo', T0));
  store.run((s) => G.finishOnboarding(s));
  const s = structuredClone(store.state);
  s.pet.stage = 2;
  s.pet.xpAwarded = { ...(s.pet.xpAwarded || {}), tour: 4200 };
  s.flags.coachDone = true;
  s.home.starterSeeds = true;
  s.home.skills = { farming: 120, cooking: 60, alchemy: 20 };
  const done = (id) => { s.story.questStates[id] = { phase: 'completed', acceptedAt: T0 - 3600000, completedAt: T0, resolvedSteps: 3000, seenCompletion: true, tracked: false }; s.story.claimedRewards.push(id); };
  for (const id of ['vq01', 'vq02', 'vq03', 'hq01']) done(id);
  Object.assign(s.story.flags, { cottage_restored: true, waystone_revealed: true, waystone_restored: true });
  s.story.questStates.eq01 = { phase: 'ruins_ready', acceptedAt: T0 - 3600000, resolvedSteps: 1500, tracked: true };
  s.story.peakLevel = 6;
  for (const [id, q] of Object.entries({ seed_sunberry: 2, seed_golden_wheat: 3, sunberry: 5, golden_wheat: 2, meadow_carrot: 3, sunberry_tart: 2, glowleaf: 3, lantern_tonic: 1, leaf_scarf: 1, explorer_hat: 1, red_backpack: 1 })) s.inventory[id] = { quantity: q, acquisitions: [] };
  s.pet.equipped = { neck: 'leaf_scarf' };
  store.replace(s);
  store.run((st, t) => G.grantCoins(st, 1240, t), store.now());
  app.go('home');
});

await shot('home', 1600);
await go('inspect'); await shot('pet');
await tab('journey', { tab: 'daily' }); await shot('journey_daily');
await tab('journey', { tab: 'story' }); await shot('journey_story');
await tab('journey', { tab: 'skills' }); await shot('journey_skills');
await tab('bag', { cat: 'wearable', sel: 'explorer_hat' }); await shot('bag_wear');
await tab('bag', { cat: 'consumable', sel: 'sunberry_tart' }); await shot('bag_care');
await tab('bag', { cat: 'pantry' }); await shot('bag_pantry');
await tab('shop', { cat: 'featured' }); await shot('shop_featured');
await tab('shop', { cat: 'wearables' }); await shot('shop_wear');
await click('buy'); await shot('shop_buy_modal', 600);
await go('evodex'); await shot('evodex');
await go('settings'); await shot('settings');
await go('village'); await shot('village', 1400);
await scroll(700); await shot('village_lower', 500);
await go('place', { id: 'glasshouse' }); await shot('place_glasshouse', 1400);
await go('homemap'); await shot('homemap', 1400);
await go('garden'); await shot('garden', 1400);
await go('cottage'); await shot('cottage', 1400);
await go('station', { id: 'kitchen' }); await shot('kitchen', 1400);
await go('station', { id: 'apothecary' }); await shot('apothecary', 1400);
await go('skills'); await shot('skills');
await go('guild'); await shot('guild', 1400);
await go('trailplace', { id: 'ruins' }); await shot('trail_ruins', 1400);
await go('prep', { id: 'eq01' }); await shot('prep', 1400);
await click('travel'); await sleep(500); await click('t-skip2'); await shot('enc_intro', 1300);
await shot('enc_card', 1800);
await click('begin'); await shot('enc_play', 2200);
await click('act-lumen_glow'); await shot('enc_turn', 1500);

console.log('shots', n, 'ERRORS', errors.length);
for (const e of [...new Set(errors)]) console.log(' ', e);
await Promise.race([b.close(), sleep(3000)]);
process.exit(0);
