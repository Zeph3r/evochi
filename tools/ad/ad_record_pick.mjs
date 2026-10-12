// Records real gameplay clips from the Evochi web build at 780x1688 using the CDP screencast,
// writing JPEG frames with timestamps plus a log of every tap (for the tap-ripple overlay).
//   node ad_record.mjs OUT_DIR      (web/dist served on :8765)
import chromium from '@sparticuz/chromium';
import puppeteer from 'puppeteer-core';
import fs from 'node:fs';
import path from 'node:path';

const OUT = process.argv[2];
fs.mkdirSync(OUT, { recursive: true });
const b = await puppeteer.launch({ executablePath: await chromium.executablePath(), args: chromium.args, headless: true });
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const PET = { name: 'Mochi', palette: 'ocean' };

// Virtual clock: performance.now, Date, rAF and timers all advance only when window.__step(ms)
// is called, so each screenshot is one exact 1/30 s frame regardless of how long capture takes.
const CLOCK = `(() => {
  let now = 5000; const RealDate = Date; const epoch = RealDate.now();
  const rafQ = new Map(); let rafId = 0; const timers = new Map(); let tid = 0;
  performance.now = () => now;
  class VDate extends RealDate { constructor(...a) { if (a.length === 0) super(epoch + now); else super(...a); } static now() { return epoch + now; } }
  window.Date = VDate;
  window.requestAnimationFrame = (cb) => { const id = ++rafId; rafQ.set(id, cb); return id; };
  window.cancelAnimationFrame = (id) => rafQ.delete(id);
  window.setTimeout = (cb, ms = 0, ...args) => { const id = ++tid; timers.set(id, { at: now + Math.max(0, +ms || 0), cb, args }); return id; };
  window.clearTimeout = (id) => timers.delete(id);
  window.setInterval = (cb, ms = 0, ...args) => { const id = ++tid; const every = Math.max(1, +ms || 1); timers.set(id, { at: now + every, cb, args, every }); return id; };
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
      try { typeof nt.cb === 'function' ? nt.cb(...nt.args) : (0, eval)(String(nt.cb)); } catch (e) { console.error('timer', e); }
    }
    now = target;
    const q = [...rafQ.values()]; rafQ.clear();
    for (const cb of q) { try { cb(now); } catch (e) { console.error('raf', e); } }
  };
})();`;

const HIDE = `
.card.dev { display: none !important; }
.toasts { display: none !important; }
`;

async function newPage() {
  const p = await b.newPage();
  await p.setViewport({ width: 390, height: 844, deviceScaleFactor: 2 });
  p.on('pageerror', (e) => console.log('pageerror', e.message));
  p.on('console', (m) => { if (m.type() === 'error') console.log('console', m.text().slice(0, 200)); });
  await p.goto('http://127.0.0.1:8765/preview.html', { waitUntil: 'networkidle0' });
  await p.evaluate(() => localStorage.clear());
  await p.evaluateOnNewDocument(CLOCK);
  await p.reload({ waitUntil: 'networkidle0' });
  for (let i = 0; i < 60 && !(await p.evaluate(() => !!window.__evochi)); i++) { await p.evaluate(() => window.__step(33.3333)); await sleep(20); }
  if (!(await p.evaluate(() => !!window.__evochi))) throw new Error('game did not boot under the virtual clock');
  const anim = await p.createCDPSession();
  await anim.send('Animation.enable');
  await anim.send('Animation.setPlaybackRate', { playbackRate: 0.35 });
  await p.addStyleTag({ content: HIDE });
  await p.evaluate(() => {
    const fix = () => {
      const w = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
      while (w.nextNode()) if (w.currentNode.nodeValue.includes('Simulated step device')) w.currentNode.nodeValue = 'Apple Health';
    };
    new MutationObserver(fix).observe(document.body, { childList: true, subtree: true, characterData: true });
    fix();
  });
  return p;
}

async function setup(p, { evolveReady = false, grown = false } = {}) {
  await p.evaluate(async (o) => {
    const { app, store, G } = window.__evochi;
    const now = store.now();
    store.run((s) => G.startGuest(s, now, 'America/New_York'));
    store.run((s) => G.createPet(s, { name: o.name, paletteId: o.palette, requestId: 'x' }, now));
    store.run((s) => G.setConnection(s, 'demo', now));
    store.run((s) => G.finishOnboarding(s));
    const s = structuredClone(store.state); s.flags.coachDone = true; store.replace(s);
    app.tab('home');
  }, PET);
  await idle(p, 0.5);
  if (evolveReady || grown) {
    await click(p, 'set', null);
    await click(p, 'dv3', null);
    await click(p, 'sback', null);
  }
  if (grown) {
    await p.evaluate(() => {
      const { store, G } = window.__evochi;
      const run = (f) => store.run((s, n) => f(s, n), store.now());
      run((s, n) => G.evolve(s, n));
      run((s, n) => G.grantCoins(s, 900, n));
      for (const id of ['golden_crest_crown', 'meadow_nest', 'sunlit_flower', 'explorer_lantern']) run((s, n) => G.purchase(s, id, 'buy-' + id, n));
      run((s, n) => G.equip(s, 'golden_crest_crown', n));
      run((s) => G.placeDecoration(s, 'meadow_nest', 'nest'));
      run((s) => G.placeDecoration(s, 'sunlit_flower', 'left'));
      run((s) => G.placeDecoration(s, 'explorer_lantern', 'right'));
    });
  }
  await p.evaluate(() => { const { app } = window.__evochi; app.ui.home = { wakeUntil: Date.now() + 1e7 }; app.tab('home'); });
  await idle(p, 0.9);
}

// Recorder --------------------------------------------------------------------------
const FPS = 30, DT = 1000 / FPS;
let rec = null;
async function startRec(p, name) {
  const dir = path.join(OUT, name);
  fs.mkdirSync(dir, { recursive: true });
  rec = { p, dir, name, n: 0, taps: [] };
}
// advance the virtual clock `sec` seconds, capturing one frame per tick
async function frames(sec) {
  const n = Math.round(sec * FPS);
  for (let k = 0; k < n; k++) {
    await rec.p.evaluate((dt) => window.__step(dt), DT);
    const buf = await rec.p.screenshot({ type: 'jpeg', quality: 92 });
    fs.writeFileSync(path.join(rec.dir, `f${String(rec.n).padStart(5, '0')}.jpg`), buf);
    rec.n++;
  }
}
const vt = () => rec.n / FPS;
async function stopRec() {
  const s = rec;
  const out = { name: s.name, w: 780, h: 1688, fps: FPS, frames: s.n, taps: s.taps };
  fs.writeFileSync(path.join(s.dir, 'clip.json'), JSON.stringify(out));
  console.log(`clip ${s.name}: ${s.n} frames, ${(s.n / FPS).toFixed(2)}s, taps ${s.taps.map((t) => t.label + '@' + t.t.toFixed(2)).join(' ')}`);
  rec = null;
}
// real mouse click at the element centre, logged for the tap-ripple overlay
async function click(p, key, label = key, { x: fx, y: fy } = {}) {
  const el = await p.$(key.startsWith('.') || key.startsWith('[') ? key : `[data-k="${key}"]`);
  if (!el) throw new Error('missing ' + key);
  const box = await el.boundingBox();
  if (!box) { await el.evaluate((e) => e.click()); return; }   // hidden helper button: click it directly
  const x = box.x + box.width * (fx ?? 0.5), y = box.y + box.height * (fy ?? 0.5);
  if (rec && label) rec.taps.push({ t: vt(), x: x * 2, y: y * 2, label });
  await p.mouse.click(x, y);
}
async function tapPet(p, label = 'pet') {
  const box = await (await p.$('.tapzone')).boundingBox();
  const x = box.x + box.width * 0.5, y = box.y + box.height * 0.55;
  if (rec) rec.taps.push({ t: vt(), x: x * 2, y: y * 2, label });
  await p.mouse.click(x, y);
}
// let the game settle without recording
async function idle(p, sec) { for (let k = 0; k < Math.round(sec * FPS); k++) await p.evaluate((dt) => window.__step(dt), DT); }


// Pick-your-egg: welcome -> guest -> create (colours, name) -> awakening. Not recorded: connect + goal screens.
let p = await newPage();
await idle(p, 0.3);
await startRec(p, 'pick');
await frames(0.6);
await click(p, 'guest', 'guest');
await frames(0.8);
await click(p, '[data-act="guest-go"]', 'go');
await frames(1.0);
for (const pal of ['forest', 'coral', 'amethyst', 'obsidian', 'amber', 'ocean']) { await click(p, 'sw-' + pal, 'sw'); await frames(0.55); }
await click(p, 'name', 'name');
await frames(0.3);
await p.type('[data-k="name"]', 'Mochi', { delay: 0 });
await frames(0.1);
// the virtual clock means type() delays don't tick; the value lands at once, so re-render the field now
await p.evaluate(() => { const i = document.querySelector('[data-k="name"]'); i.dispatchEvent(new Event('input', { bubbles: true })); });
await frames(0.6);
await (await p.$('[data-k="confirm"]')).evaluate((e) => e.scrollIntoView({ block: 'center' }));
await frames(0.5);
await click(p, 'confirm', 'confirm');
await frames(0.3);
await stopRec();
// connect + goal screens, unrecorded
await idle(p, 0.5);
await click(p, 'demo', null);
await idle(p, 0.5);
await click(p, 'gsave', null);
await idle(p, 0.2);
await p.evaluate(() => { const { store } = window.__evochi; const s = structuredClone(store.state); s.flags.coachDone = true; store.replace(s); });
await startRec(p, 'hatch');
await frames(2.2);                    // 'Something is stirring...' then the reveal at 0.9 s
await tapPet(p, 'pet');
await frames(1.6);
await click(p, 'awake-go', 'go');
await frames(2.0);
await tapPet(p, 'pet');
await frames(1.4);
await stopRec();
await p.close();
await b.close();
