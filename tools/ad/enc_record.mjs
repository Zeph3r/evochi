// Records an encounter from the web build frame-exactly: the intro cinematic, every turn and the result,
// at 30 fps and 1080 px wide, for the encounter Shorts (v5). Timers, rAF, Date and CSS animations all
// follow one virtual clock, so each JPEG is exactly 1/30 s after the last however long capture takes.
//   node enc_record.mjs OUT_DIR eq01|eq02|eq03 [--dpr 2.769]      (web/dist served on :8765)
// Writes fNNNNN.jpg plus log.json: the scene time of every action, sound cue and phase change.
import chromium from '@sparticuz/chromium';
import puppeteer from 'puppeteer-core';
import fs from 'node:fs';

const args = process.argv.slice(2);
const OUT = args[0];
const QID = args[1] || 'eq01';
const DPR = Number((args.includes('--dpr') ? args[args.indexOf('--dpr') + 1] : 0) || 1080 / 390);
const FPS = 30;
const DT = 1000 / FPS;
fs.mkdirSync(OUT, { recursive: true });

// the attempts whose seeded replies match the scripts (found with scratchpad/v5/seeds.mjs)
const PLAN = {
  eq01: { pid: 'player_short_1', companion: false, ready: 'ruins_ready', pre: [], xp: 4200,
    moves: [['lumen_glow'], ['gentle_nudge'], ['item', 'sunberry_tart'], ['lumen_glow'], ['lumen_glow'], ['lumen_glow']] },
  eq02: { pid: 'player_short_135', companion: true, ready: 'ruins_ready', pre: ['eq01'], xp: 5000,
    moves: [['lumen_glow'], ['soothe'], ['lumen_glow'], ['petal_hush'], ['lumen_glow'], ['lumen_glow'], ['soothe'], ['lumen_glow']] },
  eq03: { pid: 'player_short_0', companion: true, ready: 'gate_ready', pre: ['eq01', 'eq02'], xp: 6500,
    moves: [['item', 'lantern_tonic'], ['lumen_glow'], ['lumen_glow'], ['soothe'], ['lumen_glow'], ['soothe'], ['lumen_glow'], ['lumen_glow']] },
}[QID];

const CLOCK = `(() => {
  let now = 5000; const RealDate = Date; const epoch = RealDate.now();
  const rafQ = new Map(); let rafId = 0; const timers = new Map(); let tid = 0;
  performance.now = () => now;
  class VDate extends RealDate { constructor(...a) { if (a.length === 0) super(epoch + now); else super(...a); } static now() { return epoch + now; } }
  window.Date = VDate;
  window.requestAnimationFrame = (cb) => { const id = ++rafId; rafQ.set(id, cb); return id; };
  window.cancelAnimationFrame = (id) => rafQ.delete(id);
  window.setTimeout = (cb, ms = 0, ...a) => { const id = ++tid; timers.set(id, { at: now + Math.max(0, +ms || 0), cb, a }); return id; };
  window.clearTimeout = (id) => timers.delete(id);
  window.setInterval = (cb, ms = 0, ...a) => { const id = ++tid; const every = Math.max(1, +ms || 1); timers.set(id, { at: now + every, cb, a, every }); return id; };
  window.clearInterval = (id) => timers.delete(id);
  window.__now = () => now;
  window.__step = (dt) => {
    const target = now + dt;
    for (;;) {
      let nid = null, nt = null;
      for (const [id, t] of timers) if (t.at <= target && (!nt || t.at < nt.at)) { nid = id; nt = t; }
      if (!nt) break;
      now = nt.at;
      if (nt.every) nt.at += nt.every; else timers.delete(nid);
      try { typeof nt.cb === 'function' ? nt.cb(...nt.a) : (0, eval)(String(nt.cb)); } catch (e) { console.error('timer', e); }
    }
    now = target;
    const q = [...rafQ.values()]; rafQ.clear();
    for (const cb of q) { try { cb(now); } catch (e) { console.error('raf', e); } }
  };
  // CSS animations and transitions: paused the moment they appear and seeked to the virtual clock
  window.__syncAnims = () => {
    void document.body.offsetWidth;
    for (const a of document.getAnimations({ subtree: true })) {
      if (a.__t0 === undefined) { a.__t0 = now; try { a.pause(); } catch {} }
      try { a.currentTime = now - a.__t0; } catch {}
    }
  };
})();`;

const b = await puppeteer.launch({ executablePath: await chromium.executablePath(), args: [...chromium.args, '--force-device-scale-factor=' + DPR], headless: true });
const p = await b.newPage();
await p.setViewport({ width: 390, height: 844, deviceScaleFactor: DPR });
await p.emulateMediaFeatures([{ name: 'prefers-reduced-motion', value: 'no-preference' }]);
p.on('pageerror', (e) => console.log('pageerror', e.message));
p.on('console', (m) => { if (m.type() === 'error') console.log('console', m.text().slice(0, 200)); });
await p.goto('http://127.0.0.1:8765/preview.html', { waitUntil: 'networkidle0' });
await p.evaluate(() => localStorage.clear());
await p.evaluateOnNewDocument(CLOCK);
await p.reload({ waitUntil: 'networkidle0' });
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
for (let i = 0; i < 80 && !(await p.evaluate(() => !!window.__evochi)); i++) { await p.evaluate(() => window.__step(33.3333)); await sleep(20); }
if (!(await p.evaluate(() => !!window.__evochi))) throw new Error('game did not boot under the virtual clock');
await p.addStyleTag({ content: '.toasts { display: none !important; }' });
const cdp = await p.createCDPSession();

// the state: Mochi the Ocean Juvenile, the quest ready for its encounter, the items in the Bag
await p.evaluate((P, QID) => {
  const { app, store, G } = window.__evochi;
  const T0 = store.now();
  store.run((s) => G.startGuest(s, T0, 'America/New_York'));
  store.run((s) => G.createPet(s, { name: 'Mochi', paletteId: 'ocean', requestId: 'r' }, T0));
  store.run((s) => G.setConnection(s, 'demo', T0));
  store.run((s) => G.finishOnboarding(s));
  const s = structuredClone(store.state);
  s.player.id = P.pid;
  s.pet.stage = 2;
  s.pet.xpAwarded = { ...(s.pet.xpAwarded || {}), short_backfill: P.xp };
  s.flags.coachDone = true;
  s.home.starterSeeds = true;
  const done = (id, steps) => { s.story.questStates[id] = { phase: 'completed', acceptedAt: T0 - 3600000, completedAt: T0, resolvedSteps: steps, seenCompletion: true, tracked: false }; s.story.claimedRewards.push(id); };
  for (const id of ['vq01', 'vq02', 'vq03', 'hq01']) done(id, 3000);
  for (const id of P.pre) done(id, 1500);
  Object.assign(s.story.flags, { cottage_restored: true, waystone_revealed: true, waystone_restored: true, sprout_restored: P.pre.includes('eq02') });
  s.story.peakLevel = 6;
  s.story.questStates[QID] = { phase: P.ready, acceptedAt: T0 - 3600000, resolvedSteps: 1500, tracked: true };
  if (P.companion) s.trails.companions.petalune = { since: T0, encounters: 0 };
  G.grantItem(s, 'sunberry_tart', 3, 't', T0, null);
  G.grantItem(s, 'glowleaf', 3, 't', T0, null);
  G.grantItem(s, 'lantern_tonic', 2, 't', T0, null);
  G.grantItem(s, 'q_mossy_clue', 1, 't', T0, null);
  G.grantItem(s, 'q_lumen_trace', 1, 't', T0, null);
  G.grantItem(s, 'q_old_trail_map', 1, 't', T0, null);
  store.replace(s);
  // sound cues go to the log (headless has no audio)
  window.__log = [];
  const t0 = window.__now();
  app.sfx = (n, v) => window.__log.push({ t: (window.__now() - t0) / 1000, sfx: n, v });
  window.__t0 = t0;
  app.go('prep', { id: QID });
}, PLAN, QID);

const now = () => p.evaluate(() => (window.__now() - window.__t0) / 1000);
const step = async () => {
  await p.evaluate(() => { window.__step(1000 / 30); window.__syncAnims(); });
  // let any image that just changed source decode before the frame is captured
  await p.evaluate(() => Promise.race([Promise.all([...document.images].filter((i) => !i.complete).map((i) => new Promise((r) => { i.addEventListener('load', r, { once: true }); i.addEventListener('error', r, { once: true }); }))), new Promise((r) => setTimeout(r, 400))]));
};
let n = 0;
const log = { fps: FPS, dpr: DPR, qid: QID, frames: 0, events: [] };
const mark = async (what) => log.events.push({ t: await now(), what });
const shot = async () => {
  const { data } = await cdp.send('Page.captureScreenshot', { format: 'jpeg', quality: 92, optimizeForSpeed: true });
  fs.writeFileSync(`${OUT}/f${String(n).padStart(5, '0')}.jpg`, Buffer.from(data, 'base64'));
  n++;
};
const ui = () => p.evaluate(() => { const { app, store } = window.__evochi; const e = store.derived().trails.encounter; const u = app.ui.encounter || {}; return { route: app.route.id, phase: u.phase, busy: !!u.busy, done: e?.done || null, energy: e?.energy, meter: e?.meter }; });
const click = (sel) => p.evaluate((s) => { const el = document.querySelector(s); if (!el) return false; el.click(); return true; }, sel);

// travel -> arrive (skip the travel lines): the intro starts at frame 0
await click('[data-k="travel"]');
await step();
await click('[data-k="t-skip2"]');
await p.evaluate(() => { window.__t0 = window.__now(); });
await mark('intro');
let moves = [...PLAN.moves];
let idle = 0;
let began = false;
let resultAt = null;
const t1 = Date.now();
for (let i = 0; i < 60 * FPS; i++) {
  await shot();
  await step();
  const u = await ui();
  if (u.route !== 'encounter') break;
  if (u.phase === 'card' && !began) {
    idle++;
    if (idle >= 18) { await click('[data-k="begin"]'); began = true; idle = 0; await mark('begin'); }
  } else if (u.phase === 'play' && !u.busy && !u.done && moves.length) {
    idle++;
    if (idle >= 15) {
      const [a, item] = moves.shift();
      if (a === 'item') { await click('[data-k="act-item"]'); await step(); await shot(); await step(); await click(`[data-k="pick-${item}"]`); }
      else await click(`[data-k="act-${a}"]`);
      await mark(`act:${a}${item ? ':' + item : ''}`);
      idle = 0;
    }
  } else if (u.phase === 'result') {
    if (resultAt == null) { resultAt = i; await mark('result'); }
    if (i - resultAt > 3 * FPS) break;
  } else if (u.phase === 'play' && !u.busy && !u.done && !moves.length) {
    // out of planned moves (should not happen with the chosen seeds): soothe or glow until done
    idle++;
    if (idle >= 15) { await click(u.energy >= 24 ? '[data-k="act-lumen_glow"]' : '[data-k="act-soothe"]'); await mark('act:auto'); idle = 0; }
  } else idle = 0;
  if (i % 60 === 0) console.log('frame', i, 'phase', u.phase, 'busy', u.busy, 'meter', u.meter, 'energy', u.energy, ((Date.now() - t1) / (i + 1)).toFixed(0) + ' ms/frame');
}
log.frames = n;
log.events.push(...(await p.evaluate(() => window.__log)).map((e) => ({ t: e.t, what: 'sfx:' + e.sfx })));
log.events.sort((a, b) => a.t - b.t);
fs.writeFileSync(`${OUT}/log.json`, JSON.stringify(log, null, 1));
console.log('frames', n, 'events', log.events.filter((e) => !e.what.startsWith('sfx')).map((e) => `${e.t.toFixed(2)} ${e.what}`).join(' | '));
await b.close();
